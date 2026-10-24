import Foundation
import SwiftData

/// Conta do MFIT guardada no Keychain (só neste aparelho) para o sync automático.
/// Nunca em texto puro fora do Keychain; o item usa acesso só após o primeiro desbloqueio.
@MainActor
enum MFitCredentials {
    private static let account = "mfit.client"

    static func save(mail: String, senha: String) {
        guard let data = try? JSONEncoder().encode(["mail": mail, "senha": senha]) else { return }
        Keychain.save(data, for: account)
    }

    static func load() -> (mail: String, senha: String)? {
        guard let data = Keychain.load(account),
              let dict = try? JSONDecoder().decode([String: String].self, from: data),
              let mail = dict["mail"], let senha = dict["senha"] else { return nil }
        return (mail, senha)
    }

    static func clear() { Keychain.delete(account) }
    static var isStored: Bool { load() != nil }
}

/// Sincroniza os treinos do MFIT (login + importação) usando a conta salva. Idempotente por sourceID.
@MainActor
enum MFitSync {
    static let lastSyncKey = "mfitLastSync"
    private static let minInterval: TimeInterval = 6 * 3600

    /// Sincroniza com a conta salva. Devolve quantos planos vieram.
    @discardableResult
    static func sync(context: ModelContext) async throws -> Int {
        guard let cred = MFitCredentials.load() else { throw MFitError.auth("nenhuma conta MFIT salva") }
        let client = MFitClient()
        try await client.login(mail: cred.mail, senha: cred.senha)
        let plans = try await client.importPlans()
        MFitMaterializer(context: context).materializeAll(plans)
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: lastSyncKey)
        return plans.count
    }

    /// Sync silencioso em segundo plano: só se há conta salva, não está em teste e passou do intervalo mínimo.
    static func autoSyncIfDue(context: ModelContext) async {
        guard !AppRuntime.isTesting, MFitCredentials.isStored else { return }
        let last = UserDefaults.standard.double(forKey: lastSyncKey)
        guard Date.now.timeIntervalSince1970 - last >= minInterval else { return }
        _ = try? await sync(context: context)
    }
}

/// Transforma planos MFIT já normalizados em Routine/RoutineItem + CustomExercise + ExerciseMedia.
/// Usado tanto pela tela de importação quanto pelo sync automático.
@MainActor
struct MFitMaterializer {
    let context: ModelContext

    func materializeAll(_ plans: [MFitPlan]) {
        for plan in plans { materialize(plan) }
        try? context.save()
        if let customs = try? context.fetch(FetchDescriptor<CustomExercise>()) { Exercise.register(customs) }
        if let media = try? context.fetch(FetchDescriptor<ExerciseMedia>()) { Exercise.registerMedia(media) }
    }

    private func materialize(_ plan: MFitPlan) {
        let records = (try? context.fetch(FetchDescriptor<MFitImportRecord>())) ?? []
        let routines = (try? context.fetch(FetchDescriptor<Routine>())) ?? []
        let old = records.first { $0.sourceID == plan.sourceID }

        // Mapa dia(MFIT) -> Routine existente, pelos arrays paralelos do registro anterior (preserva nome e UUID)
        var dayToRoutine: [String: Routine] = [:]
        if let old, let oldPlan = old.plan {
            let uuids = old.routineUUIDs
            for (i, d) in oldPlan.days.enumerated() where i < uuids.count {
                if let r = routines.first(where: { $0.uuid == uuids[i] }) { dayToRoutine[d.sourceID] = r }
            }
        }

        var usedUUIDs: [UUID] = []
        var matched = Set<String>()
        var order = routines.count
        for day in plan.days {
            let routine: Routine
            if let existing = dayToRoutine[day.sourceID] {
                routine = existing                       // mantém o nome que o usuário deu e o UUID
                routine.items.forEach(context.delete)
                routine.items = []
                matched.insert(day.sourceID)
            } else {
                routine = Routine(name: day.name.isEmpty ? (plan.name.isEmpty ? "Rotina MFIT" : plan.name) : day.name,
                                  weekdays: [], order: order)
                order += 1
                context.insert(routine)
            }
            if (1...7).contains(day.dayTypeCode) { routine.weekdays = [day.dayTypeCode] }
            usedUUIDs.append(routine.uuid)

            var itemOrder = 0
            for block in day.blocks {
                for (i, ex) in block.exercises.enumerated() {
                    let exID = resolveExerciseID(ex)
                    let item = RoutineItem(exerciseID: exID,
                                           sets: max(ex.sets.count, 1),
                                           reps: parseReps(ex.sets.first?.reps),
                                           rest: ex.sets.first?.restSeconds ?? 90,
                                           order: itemOrder)
                    item.supersetNext = block.isSuperset && i < block.exercises.count - 1
                    routine.items.append(item)
                    if !ex.videoURL.isEmpty { upsertMedia(exID, ex.videoURL) }
                    itemOrder += 1
                }
            }
        }
        // Dias que sumiram no MFIT: remove as rotinas órfãs desse plano
        for (sid, r) in dayToRoutine where !matched.contains(sid) { context.delete(r) }

        let keptName = old?.planName
        if let old { context.delete(old) }
        let record = MFitImportRecord(plan: plan, routineUUIDs: usedUUIDs)
        if let keptName, !keptName.isEmpty { record.planName = keptName }   // preserva o nome do plano
        context.insert(record)
    }

    private func upsertMedia(_ exerciseID: String, _ url: String) {
        let existing = (try? context.fetch(FetchDescriptor<ExerciseMedia>())) ?? []
        if let m = existing.first(where: { $0.exerciseID == exerciseID }) {
            m.videoURL = url
        } else {
            context.insert(ExerciseMedia(exerciseID: exerciseID, videoURL: url))
        }
    }

    // MARK: - Mapeamento

    private func resolveExerciseID(_ ex: MFitExercise) -> String {
        if let id = bestMatch(ex.name) { return id }
        let custom = CustomExercise(name: ex.name.isEmpty ? "Exercício MFIT" : ex.name,
                                    group: muscleGroup(ex.group),
                                    equipment: "Outro",
                                    type: exerciseType(ex.category),
                                    notes: prescriptionNotes(ex))
        context.insert(custom)
        return custom.exerciseID
    }

    private func bestMatch(_ name: String) -> String? {
        let norm = normalize(name)
        guard !norm.isEmpty else { return nil }
        if let m = Exercise.builtIn.first(where: { normalize($0.name) == norm }) { return m.id }
        let target = tokens(name)
        guard !target.isEmpty else { return nil }
        var best: (id: String, score: Double)?
        for e in Exercise.builtIn {
            let t = tokens(e.name)
            let inter = target.intersection(t).count
            guard inter > 0 else { continue }
            let score = Double(inter) / Double(target.union(t).count)
            if score > (best?.score ?? 0) { best = (e.id, score) }
        }
        if let best, best.score >= 0.5 { return best.id }
        return nil
    }

    private func tokens(_ s: String) -> Set<String> {
        let drop: Set<String> = ["com", "na", "no", "de", "da", "do", "em", "para", "por", "the", "with", "and",
                                 "halteres", "halter", "barra", "polia", "maquina", "corda", "cabo", "smith", "livre",
                                 "sentado", "sentada", "deitado", "deitada", "unilateral", "banco", "maquinas"]
        return Set(normalize(s)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count > 2 && !drop.contains($0) })
    }

    private func prescriptionNotes(_ ex: MFitExercise) -> String {
        var lines: [String] = []
        for (i, s) in ex.sets.enumerated() {
            var parts: [String] = ["Série \(i + 1)"]
            if !s.reps.isEmpty { parts.append(s.reps) }
            if !s.weight.isEmpty { parts.append("\(s.weight) kg") }
            if s.restSeconds > 0 { parts.append("desc \(s.restSeconds)s") }
            parts.append(contentsOf: [s.speed, s.distance, s.pace, s.incline, s.cadence].filter { !$0.isEmpty })
            if !s.notes.isEmpty { parts.append(s.notes) }
            lines.append(parts.joined(separator: " · "))
        }
        return lines.joined(separator: "\n")
    }

    private func parseReps(_ raw: String?) -> Int {
        guard let raw, !raw.isEmpty else { return 10 }
        let afterX = raw.split(separator: "x", maxSplits: 1).last.map(String.init) ?? raw
        let digits = afterX.drop { !$0.isNumber }.prefix { $0.isNumber }
        return Int(digits) ?? 10
    }

    private func normalize(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: .current)
            .lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func muscleGroup(_ raw: String) -> MuscleGroup {
        let n = normalize(raw)
        switch true {
        case n.contains("peito"): return .peito
        case n.contains("costas"): return .costas
        case n.contains("ombro"): return .ombros
        case n.contains("biceps"): return .biceps
        case n.contains("triceps"): return .triceps
        case n.contains("antebra"): return .antebraco
        case n.contains("quadri"): return .quadriceps
        case n.contains("posterior"): return .posterior
        case n.contains("gluteo"): return .gluteos
        case n.contains("panturr"): return .panturrilha
        case n.contains("abdom") || n.contains("core"): return .abdomen
        default: return .corpo
        }
    }

    private func exerciseType(_ category: String) -> ExerciseType {
        switch category {
        case "flexibility": return .bodyweight
        case "cardio": return .distance
        default: return .weighted
        }
    }
}
