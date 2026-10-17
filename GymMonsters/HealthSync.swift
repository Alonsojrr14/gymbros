import Foundation
import HealthKit
import SwiftData

/// Importa treinos do app Saúde (iPhone/Apple Watch) como atividades e, se ligado,
/// grava no Saúde as atividades registradas aqui (contam nos anéis do Fitness).
@MainActor
enum HealthSync {
    static let store = HKHealthStore()
    static var available: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Janela da primeira importação
    static let firstImportDays = 14

    private static let enabledKey = "healthEnabled"
    private static let lastSyncKey = "healthLastSync"
    private static let ignoredKey = "healthIgnored"

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var lastSync: Date? {
        get { UserDefaults.standard.object(forKey: lastSyncKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastSyncKey) }
    }

    /// Treinos do Saúde que o usuário apagou aqui: não voltam na próxima sincronização
    static var ignored: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: ignoredKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: ignoredKey) }
    }

    static func requestAccess() async throws {
        try await store.requestAuthorization(toShare: [], read: [HKObjectType.workoutType(), HKQuantityType(.bodyMass)])
    }

    // MARK: Gravar no Saúde

    private static let writeKey = "healthWrite", writeSinceKey = "healthWriteSince"

    static var writeEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: writeKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: writeKey)
            // Só grava o que for registrado daqui para frente (o passado pode já estar no Saúde pelo Watch)
            if newValue { UserDefaults.standard.set(Date.now.addingTimeInterval(-3600), forKey: writeSinceKey) }
        }
    }

    private static var writeSince: Date { UserDefaults.standard.object(forKey: writeSinceKey) as? Date ?? .now }

    static func requestWrite() async throws {
        try await store.requestAuthorization(toShare: [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned)],
                                             read: [HKObjectType.workoutType(), HKQuantityType(.bodyMass)])
    }

    private static var exporting = false

    /// Grava no Saúde as atividades registradas aqui que ainda não foram (as importadas de lá ficam de fora)
    static func exportPending(context: ModelContext) async {
        guard available, writeEnabled, !exporting else { return }
        exporting = true
        defer { exporting = false }
        let since = writeSince
        let list = ((try? context.fetch(FetchDescriptor<Activity>())) ?? [])
            .filter { $0.healthUUID == nil && $0.healthWrittenUUID == nil && $0.date >= since
                && $0.date.addingTimeInterval(Double($0.minutes) * 60) <= .now.addingTimeInterval(120) }
        guard !list.isEmpty else { return }
        let bodyWeight = ((try? context.fetch(FetchDescriptor<BodyEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? [])
            .compactMap(\.weight).first
        let weight: Double
        if let bodyWeight { weight = bodyWeight } else { weight = await bodyMass() ?? 70 }
        for a in list {
            if let id = try? await write(a, weight: weight) {
                a.healthWrittenUUID = id.uuidString
                try? context.save()
            }
        }
    }

    /// Calorias ativas estimadas: MET da atividade ajustado pelo esforço, sem o metabolismo basal
    static func activeKcal(kind: ActivityKind, minutes: Int, effort: Int, weight: Double) -> Double {
        let met = kind.met * (0.6 + 0.08 * Double(effort))
        return max(met - 1, 0) * 3.5 * weight / 200 * Double(minutes)
    }

    private static func write(_ a: Activity, weight: Double) async throws -> UUID? {
        let config = HKWorkoutConfiguration()
        config.activityType = activityType(a.kind)
        config.locationType = [.corrida, .caminhada, .bike, .futebol, .volei].contains(a.kind) ? .outdoor : .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        let start = a.date, end = a.date.addingTimeInterval(Double(max(a.minutes, 1)) * 60)
        try await builder.beginCollection(at: start)
        let kcal = activeKcal(kind: a.kind, minutes: a.minutes, effort: a.effort, weight: weight)
        let sample = HKQuantitySample(type: HKQuantityType(.activeEnergyBurned),
                                      quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal), start: start, end: end)
        try await builder.addSamples([sample])
        try await builder.endCollection(at: end)
        return try await builder.finishWorkout()?.uuid
    }

    /// Apaga do Saúde um treino gravado pelo GymBros (atividade apagada ou editada)
    static func deleteWritten(_ uuid: String?) {
        guard available, let uuid, let id = UUID(uuidString: uuid) else { return }
        Task {
            let q = HKSampleQueryDescriptor(predicates: [.workout(HKQuery.predicateForObject(with: id))], sortDescriptors: [])
            if let w = try? await q.result(for: store).first { try? await store.delete(w) }
        }
    }

    static func activityType(_ k: ActivityKind) -> HKWorkoutActivityType {
        switch k {
        case .musculacao: .traditionalStrengthTraining
        case .crossfit: .crossTraining
        case .corrida: .running
        case .caminhada: .walking
        case .bike: .cycling
        case .natacao: .swimming
        case .volei: .volleyball
        case .futebol: .soccer
        case .lutas: .martialArts
        case .danca: .cardioDance
        case .yoga: .yoga
        case .outro: .other
        }
    }

    struct Result {
        var imported: [Activity] = []
        var skippedOverlap = 0
    }

    /// Busca treinos novos e cria as atividades. Pula os que já existem ou que se sobrepõem
    /// a uma atividade já registrada (ex.: treino guiado de musculação gravado também no Watch).
    static func sync(context: ModelContext) async throws -> Result {
        guard available, enabled else { return Result() }
        let since = lastSync.map { $0.addingTimeInterval(-2 * 86400) }
            ?? Calendar.current.date(byAdding: .day, value: -firstImportDays, to: .now)!

        let query = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForSamples(withStart: since, end: nil))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let workouts = try await query.result(for: store)
        let weight = await bodyMass() ?? 70

        let existing = try context.fetch(FetchDescriptor<Activity>())
        let known = Set(existing.compactMap(\.healthUUID)).union(existing.compactMap(\.healthWrittenUUID)).union(ignored)
        var ranges = existing.map { ($0.date, $0.date.addingTimeInterval(Double($0.minutes) * 60)) }

        var result = Result()
        for w in workouts {
            let id = w.uuid.uuidString
            // Treinos que o próprio GymBros gravou não voltam como importados
            guard !known.contains(id), w.duration >= 5 * 60,
                  w.sourceRevision.source.bundleIdentifier != Bundle.main.bundleIdentifier else { continue }
            let start = w.startDate, end = w.endDate
            // Sobreposição de mais da metade do treino com algo já registrado → mesmo treino
            let overlaps = ranges.contains { r in
                let shared = min(end, r.1).timeIntervalSince(max(start, r.0))
                return shared > 0.5 * min(end.timeIntervalSince(start), r.1.timeIntervalSince(r.0))
            }
            if overlaps {
                result.skippedOverlap += 1
                continue
            }

            let kind = kind(for: w.workoutActivityType)
            let minutes = Int((w.duration / 60).rounded())
            let kcal = w.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
            let activity = Activity(kind: kind, date: start, minutes: minutes,
                                    effort: effort(kind: kind, minutes: minutes, kcal: kcal, weight: weight),
                                    note: kcal.map { "\(Int($0)) kcal" } ?? "")
            activity.healthUUID = id
            activity.source = w.sourceRevision.source.name
            context.insert(activity)
            ranges.append((start, end))
            result.imported.append(activity)
        }
        try context.save()
        lastSync = .now
        return result
    }

    /// Esforço 1–10 a partir do gasto real comparado ao esperado para a atividade em ritmo moderado
    static func effort(kind: ActivityKind, minutes: Int, kcal: Double?, weight: Double) -> Int {
        guard let kcal, kcal > 0, minutes > 0 else { return 5 }
        // kcal/min esperado = MET × 3,5 × peso / 200
        let expected = kind.met * 3.5 * weight / 200 * Double(minutes)
        // Calorias ativas não incluem o metabolismo basal (~1 MET)
        let ratio = kcal / max(expected - 3.5 * weight / 200 * Double(minutes), 1)
        return min(max(Int((5 * ratio).rounded()), 1), 10)
    }

    private static func bodyMass() async -> Double? {
        let q = HKSampleQueryDescriptor(predicates: [.quantitySample(type: HKQuantityType(.bodyMass))],
                                        sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)], limit: 1)
        return try? await q.result(for: store).first?.quantity.doubleValue(for: .gramUnit(with: .kilo))
    }

    static func kind(for type: HKWorkoutActivityType) -> ActivityKind {
        switch type {
        case .running: .corrida
        case .walking, .hiking: .caminhada
        case .cycling, .handCycling: .bike
        case .swimming, .waterFitness, .waterPolo: .natacao
        case .volleyball: .volei
        case .soccer, .americanFootball, .australianFootball, .rugby, .handball, .basketball, .hockey: .futebol
        case .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining: .musculacao
        case .crossTraining, .highIntensityIntervalTraining, .mixedCardio, .jumpRope: .crossfit
        case .martialArts, .boxing, .kickboxing, .wrestling, .fencing: .lutas
        case .cardioDance, .socialDance, .barre: .danca
        case .yoga, .pilates, .flexibility, .mindAndBody, .taiChi: .yoga
        default: .outro
        }
    }
}
