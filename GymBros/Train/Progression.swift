import Foundation
import SwiftData

/// Treino encerrado sozinho (ao sair da academia) que mudou a rotina: a oferta de atualizar fica pendente
/// até a pessoa abrir a aba Treino e decidir
enum PendingRoutineUpdate {
    static let key = "pendingRoutineUpdate"

    static var sessionUUID: UUID? {
        get { UserDefaults.standard.string(forKey: key).flatMap(UUID.init) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: key) }
    }
}

// MARK: - Progressão (funções puras do histórico)

struct SetLog {
    let exerciseID: String
    let weight: Double
    let reps: Int
    let target: Int
    let done: Bool

    var hit: Bool { done && reps >= target }
}

struct SessionLog {
    let date: Date
    let sets: [SetLog]
    /// Treino de deload: não conta para a progressão (as cargas leves não viram referência)
    var deload = false
}

/// Semana de deload: depois de várias semanas seguidas treinando, cargas a 70 % e menos séries
enum Deload {
    /// Semanas seguidas de treino antes de sugerir
    static let after = 5
    static let load = 0.7

    private static let untilKey = "deloadUntil", snoozeKey = "deloadSnooze"

    static var until: Date? {
        let t = UserDefaults.standard.double(forKey: untilKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    static var active: Bool { until.map { $0 > .now } ?? false }

    /// Começa agora e vai até o fim da semana
    static func start() {
        let end = Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.end ?? .now.addingTimeInterval(7 * 86400)
        UserDefaults.standard.set(end.timeIntervalSince1970, forKey: untilKey)
    }

    static func stop() { UserDefaults.standard.set(0, forKey: untilKey) }

    static func snooze() { UserDefaults.standard.set(Date.now.addingTimeInterval(7 * 86400).timeIntervalSince1970, forKey: snoozeKey) }

    static var snoozed: Bool { UserDefaults.standard.double(forKey: snoozeKey) > Date.now.timeIntervalSince1970 }

    /// Semanas seguidas (até esta ou a passada) com treino de musculação, parando numa semana sem treino ou de deload
    static func streak(_ sessions: [WorkoutSession]) -> Int {
        let cal = Calendar.current
        let done = sessions.filter { $0.end != nil }
        func week(_ d: Date) -> Date { cal.dateInterval(of: .weekOfYear, for: d)!.start }
        let byWeek = Dictionary(grouping: done) { week($0.start) }
        var w = week(.now)
        if byWeek[w] == nil { w = cal.date(byAdding: .weekOfYear, value: -1, to: w)! }
        var n = 0
        while let list = byWeek[w], !list.contains(where: \.isDeload) {
            n += 1
            w = cal.date(byAdding: .weekOfYear, value: -1, to: w)!
        }
        return n
    }

    static func shouldSuggest(_ sessions: [WorkoutSession]) -> Bool { !active && !snoozed && streak(sessions) >= after }

    /// Aplica o deload a uma prescrição: 70 % da carga (arredondada ao incremento) e um terço a menos de séries.
    /// Vale para itens da rotina e para exercícios adicionados ou trocados durante um treino de deload.
    static func apply(_ s: Suggestion, sets: Int, exerciseID: String) -> (suggestion: Suggestion, sets: Int) {
        let inc = Exercise.byID(exerciseID)?.increment ?? 2.5
        return (Suggestion(weight: (s.weight * load / inc).rounded() * inc, reps: s.reps, reason: "Semana de deload"),
                max(1, Int((Double(sets) * 2 / 3).rounded())))
    }
}

/// Objetivo do exercício: define a faixa de reps da dupla progressão e o descanso
enum TrainingGoal: String, CaseIterable, Identifiable {
    case forca, hipertrofia, resistencia

    var id: String { rawValue }

    var name: String {
        switch self {
        case .forca: "Força"
        case .hipertrofia: "Hipertrofia"
        case .resistencia: "Resistência"
        }
    }

    var range: ClosedRange<Int> {
        switch self {
        case .forca: 3...6
        case .hipertrofia: 8...12
        case .resistencia: 15...20
        }
    }

    var rest: Int {
        switch self {
        case .forca: 180
        case .hipertrofia: 90
        case .resistencia: 60
        }
    }

    var label: String { "\(name) · \(range.lowerBound)–\(range.upperBound) reps" }

    /// Objetivos por exercício (guardados em Ajustes, entram no backup)
    private static let key = "exerciseGoals"

    private static var all: [String: String] {
        guard let s = UserDefaults.standard.string(forKey: key), let d = s.data(using: .utf8),
              let m = try? JSONDecoder().decode([String: String].self, from: d) else { return [:] }
        return m
    }

    static func of(_ exerciseID: String) -> TrainingGoal? { all[exerciseID].flatMap(TrainingGoal.init(rawValue:)) }

    static func set(_ goal: TrainingGoal?, for exerciseID: String) {
        var m = all
        m[exerciseID] = goal?.rawValue
        if let d = try? JSONEncoder().encode(m) { UserDefaults.standard.set(String(data: d, encoding: .utf8), forKey: key) }
    }
}

struct Suggestion {
    let weight: Double
    let reps: Int
    var reason: String
    /// Quantas séries de trabalho prescrever (nil = as da rotina)
    var sets: Int? = nil
    /// Rampa que você fez à mão da última vez (séries leves antes das de trabalho), para repetir como aquecimento
    var ramp: [(weight: Double, reps: Int)] = []
}

enum Progression {
    /// Treinos seguidos sem completar antes de reduzir a carga
    static let deloadAfter = 3

    /// Abaixo disso (fração da maior carga do exercício no treino) a série é rampa, não trabalho
    static let rampShare = 0.8

    /// Séries de trabalho de um exercício num treino: tira a rampa (séries bem mais leves que a maior carga)
    static func workSets(_ sets: [SetLog]) -> [SetLog] {
        let top = sets.map(\.weight).max() ?? 0
        guard top > 0 else { return sets }
        return sets.filter { $0.weight >= top * rampShare }
    }

    /// Próxima prescrição de um exercício. `history` são treinos concluídos, do mais antigo ao mais novo.
    /// A rampa feita à mão (ex.: 30, 50, 70, 70) não conta como trabalho: só as séries pesadas viram referência,
    /// e a carga nova vai no mesmo número de séries pesadas. Subir carga e séries juntas não acontece:
    /// com carga nova, repete o número de séries pesadas; sem carga nova, pode somar uma, até o que a rotina pede.
    static func suggest(exerciseID: String, sets: Int, reps: Int, history: [SessionLog]) -> Suggestion {
        let mine = history.filter { !$0.deload }.compactMap { s -> [SetLog]? in
            let m = s.sets.filter { $0.exerciseID == exerciseID }
            return m.isEmpty ? nil : m
        }
        guard let lastAll = mine.last else { return core(exerciseID: exerciseID, sets: sets, reps: reps, past: []) }
        let past = mine.map(workSets)
        let work = past.last ?? []
        let top = lastAll.map(\.weight).max() ?? 0
        let ramp = lastAll.filter { $0.weight < top * rampShare }
        // A rotina conta a rampa feita à mão; as séries pesadas que ela pede são o resto
        let wanted = max(sets - ramp.count, 1)
        var s = core(exerciseID: exerciseID, sets: work.count, reps: reps, past: past)
        let lastWeight = work.map(\.weight).max() ?? 0
        let raised = s.weight > lastWeight
        s.sets = raised ? min(wanted, work.count) : min(wanted, work.count + 1)
        s.ramp = ramp.map { ($0.weight, $0.reps) }
        if !ramp.isEmpty {
            s.reason += " As séries leves (\(ramp.map { fmt($0.weight) }.joined(separator: ", ")) kg) contam como aquecimento."
        }
        return s
    }

    private static func core(exerciseID: String, sets: Int, reps: Int, past: [[SetLog]]) -> Suggestion {
        let ex = Exercise.byID(exerciseID)
        let goal = (ex?.type ?? .weighted) == .weighted ? TrainingGoal.of(exerciseID) : nil
        let reps = goal?.range.lowerBound ?? reps
        guard let last = past.last else {
            if ex?.type ?? .weighted == .weighted,
               let w = PRBook.workingWeight(exerciseID: exerciseID, reps: reps, increment: ex?.increment ?? 2.5) {
                return Suggestion(weight: w.weight, reps: reps,
                                  reason: "Pelo seu PR de \(fmt(w.pr.weight)) kg × \(w.pr.reps): \(fmt(w.weight)) kg para \(reps) reps, com 1–2 de sobra.")
            }
            return Suggestion(weight: 0, reps: reps, reason: ex?.type == .weighted
                              ? "Primeira vez: escolha uma carga em que as \(reps) reps saiam com boa técnica."
                              : "Primeira vez: faça o que conseguir com boa técnica.")
        }

        let lastWeight = last.filter(\.done).map(\.weight).max() ?? last.map(\.weight).max() ?? 0
        let lastTarget = last.map(\.target).max() ?? reps

        // Dupla progressão dentro da faixa do objetivo: +1 rep até o topo, depois sobe carga e volta ao início
        if let goal {
            let r = goal.range
            let target = min(max(lastTarget, r.lowerBound), r.upperBound)
            let work = Array(last.prefix(max(sets, 1)))
            let allDone = last.count >= sets && work.allSatisfy(\.done)
            let minReps = work.map(\.reps).min() ?? 0
            let inc = ex?.increment ?? 2.5
            if allDone && minReps >= r.upperBound {
                return Suggestion(weight: lastWeight + inc, reps: r.lowerBound,
                                  reason: "\(goal.name): bateu \(r.upperBound) reps em todas. +\(fmt(inc)) kg e volta para \(r.lowerBound).")
            }
            if allDone && minReps >= target {
                let next = min(target + 1, r.upperBound)
                return Suggestion(weight: lastWeight, reps: next,
                                  reason: "\(goal.name): mesma carga, \(next) reps (faixa \(r.lowerBound)–\(r.upperBound)).")
            }
            return Suggestion(weight: lastWeight, reps: target,
                              reason: "\(goal.name): mesma carga até completar \(target) reps em todas as séries.")
        }

        let target = max(reps, 1)
        if lastTarget < target {
            return Suggestion(weight: lastWeight, reps: target, reason: "Nova meta de \(target) reps: mantenha a carga até completar.")
        }
        let success = last.count >= sets && last.prefix(sets).allSatisfy(\.hit) && lastTarget >= target

        switch ex?.type ?? .weighted {
        case .time:
            return success
                ? Suggestion(weight: lastWeight, reps: lastTarget + 5, reason: "+5 s: você segurou todas as séries.")
                : Suggestion(weight: lastWeight, reps: lastTarget, reason: "Mesmo tempo: tente segurar todas as séries.")
        case .bodyweight where lastWeight == 0:
            return success
                ? Suggestion(weight: 0, reps: lastTarget + 1, reason: "+1 rep: você completou todas as séries.")
                : Suggestion(weight: 0, reps: lastTarget, reason: "Mesmas reps: faltou completar da última vez.")
        default:
            let inc = ex?.increment ?? 2.5
            if success {
                return Suggestion(weight: lastWeight + inc, reps: target,
                                  reason: "+\(fmt(inc)) kg: você completou todas as séries da última vez.")
            }
            // Falhas seguidas na mesma carga → deload de 10 %
            var misses = 0
            for s in past.reversed() {
                let w = s.filter(\.done).map(\.weight).max() ?? s.map(\.weight).max() ?? 0
                let ok = !s.isEmpty && s.allSatisfy(\.hit)
                guard w == lastWeight, !ok else { break }
                misses += 1
            }
            if misses >= deloadAfter, lastWeight > 0 {
                let reduced = ((lastWeight * 0.9) / inc).rounded(.down) * inc
                return Suggestion(weight: reduced, reps: target,
                                  reason: "Deload de 10 %: \(misses) treinos sem completar \(fmt(lastWeight)) kg. Reconstrua a partir daqui.")
            }
            return Suggestion(weight: lastWeight, reps: target,
                              reason: "Mesma carga: faltou completar da última vez (\(misses)/\(deloadAfter) antes do deload).")
        }
    }

    /// Aquecimento antes da carga de trabalho: 40 % × 10, 60 % × 6, 80 % × 3 (arredondado ao incremento)
    static func warmup(work: Double, increment: Double, minimum: Double = 0) -> [(weight: Double, reps: Int)] {
        guard work > 0 else { return [] }
        return [(0.4, 10), (0.6, 6), (0.8, 3)].compactMap { pct, reps in
            let w = max((work * pct / increment).rounded() * increment, minimum)
            return w < work ? (w, reps) : nil
        }
    }

    /// 1RM estimado (Epley). Não estima acima de 12 reps.
    static func oneRM(weight: Double, reps: Int) -> Double? {
        guard weight > 0, (1...12).contains(reps) else { return nil }
        return reps == 1 ? weight : weight * (1 + Double(reps) / 30)
    }

    static func bestOneRM(_ sets: [SetLog]) -> Double? {
        sets.filter(\.done).compactMap { oneRM(weight: $0.weight, reps: $0.reps) }.max()
    }

    /// Força da série na escala de 1RM, para comparar marcas: acima de 12 reps conta como 12 (piso conservador),
    /// nunca a carga bruta misturada com 1RM. Sem carga, 0 (desempata por reps).
    static func strength(weight: Double, reps: Int) -> Double {
        oneRM(weight: weight, reps: min(reps, 12)) ?? 0
    }

    /// Calculadora reps × carga a partir do 1RM, arredondada ao incremento do exercício
    static func repTable(oneRM: Double, increment: Double, reps: [Int] = [12, 10, 8, 5, 3]) -> [(reps: Int, weight: Double)] {
        let inc = increment > 0 ? increment : 2.5
        return reps.map { r in (r, ((oneRM / (1 + Double(r) / 30)) / inc).rounded() * inc) }
    }

    /// Esforço de um treino salvo sem a tela de conclusão: média dos últimos treinos de musculação (até 10),
    /// ou 7, o padrão da tela de conclusão
    static func estimatedEffort(recent: [Int]) -> Int {
        let valid = recent.suffix(10).filter { (1...10).contains($0) }
        guard !valid.isEmpty else { return 7 }
        return Int((Double(valid.reduce(0, +)) / Double(valid.count)).rounded())
    }

    /// Recordes batidos na sessão em relação ao histórico anterior
    static func records(in session: SessionLog, history: [SessionLog]) -> [String] {
        var out: [String] = []
        let ids = session.sets.map(\.exerciseID).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        for id in ids {
            let now = session.sets.filter { $0.exerciseID == id && $0.done }
            let before = history.flatMap(\.sets).filter { $0.exerciseID == id && $0.done } + (PRBook.manual[id] ?? [])
            guard !now.isEmpty, !before.isEmpty else { continue }
            let name = Exercise.name(id)
            let maxNow = now.map(\.weight).max() ?? 0, maxBefore = before.map(\.weight).max() ?? 0
            if maxNow > maxBefore, maxNow > 0 {
                out.append("\(name): maior carga, \(fmt(maxNow)) kg")
            } else if let a = bestOneRM(now), let b = bestOneRM(before), a > b + 0.01 {
                out.append("\(name): 1RM estimado \(fmt(a)) kg")
            } else if maxNow == 0, maxBefore == 0, let r = now.map(\.reps).max(), r > (before.map(\.reps).max() ?? 0) {
                out.append("\(name): \(r) reps")
            }
        }
        return out
    }

    /// Número em pt-BR: inteiro sem casas; 2 casas só quando o valor é exato nelas (anilha de 1,25); senão 1 casa
    static func fmt(_ w: Double) -> String {
        if w.truncatingRemainder(dividingBy: 1) == 0 { return String(Int(w)) }
        let cents = (w * 100).rounded()
        let exact = abs(w * 100 - cents) < 1e-6 && Int(cents) % 10 != 0
        let text = exact ? String(format: "%.2f", w) : String(format: "%.1f", w)
        return text.replacingOccurrences(of: ".", with: ",")
    }
}

// MARK: - Modelos prontos

struct RoutineTemplate: Identifiable {
    let name: String
    let detail: String
    let routines: [(name: String, weekdays: Set<Int>, items: [(String, Int, Int)])]
    var id: String { name }

    static let all: [RoutineTemplate] = [
        RoutineTemplate(name: "ABC", detail: "3 treinos, 6 dias: empurrar, puxar, pernas", routines: [
            ("A · Peito, ombro e tríceps", [2, 5], [("supino-reto", 4, 8), ("supino-inclinado-halter", 3, 10), ("crucifixo", 3, 12),
                                                     ("desenvolvimento-halter", 3, 10), ("elevacao-lateral", 3, 15), ("triceps-corda", 3, 12)]),
            ("B · Costas e bíceps", [3, 6], [("puxada-frente", 4, 10), ("remada-curvada", 4, 8), ("remada-baixa", 3, 12),
                                              ("face-pull", 3, 15), ("rosca-direta", 3, 10), ("rosca-martelo", 3, 12)]),
            ("C · Pernas e abdômen", [4, 7], [("agachamento", 4, 8), ("leg-press", 3, 12), ("stiff", 3, 10),
                                               ("cadeira-extensora", 3, 12), ("panturrilha-pe", 4, 15), ("prancha", 3, 45)]),
        ]),
        RoutineTemplate(name: "Full body", detail: "Corpo todo, 3× por semana", routines: [
            ("Full body", [2, 4, 6], [("agachamento", 3, 8), ("supino-reto", 3, 8), ("remada-curvada", 3, 8),
                                      ("desenvolvimento", 3, 10), ("stiff", 3, 10), ("prancha", 3, 45)]),
        ]),
        RoutineTemplate(name: "Superior / Inferior", detail: "4 dias alternando", routines: [
            ("Superior", [2, 5], [("supino-reto", 4, 8), ("remada-curvada", 4, 8), ("desenvolvimento-halter", 3, 10),
                                  ("puxada-frente", 3, 10), ("rosca-alternada", 3, 12), ("triceps-pulley", 3, 12)]),
            ("Inferior", [3, 6], [("agachamento", 4, 8), ("terra-romeno", 3, 10), ("leg-press", 3, 12),
                                  ("mesa-flexora", 3, 12), ("panturrilha-sentado", 4, 15), ("abdominal", 3, 15)]),
        ]),
        RoutineTemplate(name: "CrossFit", detail: "3 dias: olímpicos, ginástica e força + metcon", routines: [
            ("CF A · Olímpicos", [2], [("cf-power-snatch", 5, 3), ("cf-hang-power-clean", 5, 3), ("cf-push-jerk", 4, 3),
                                         ("cf-overhead-squat", 3, 5), ("cf-box-jump", 3, 10), ("cf-double-under", 3, 50)]),
            ("CF B · Ginástica", [4], [("cf-kipping-pull-up", 5, 10), ("cf-toes-to-bar", 4, 10), ("cf-hspu", 4, 6),
                                         ("cf-ring-dip", 3, 10), ("cf-pistol", 3, 8), ("cf-l-sit", 3, 20)]),
            ("CF C · Força e metcon", [6], [("agachamento-frontal", 5, 5), ("levantamento-terra", 4, 5), ("cf-push-press", 4, 6),
                                              ("thruster", 3, 12), ("kettlebell-swing", 3, 20), ("cf-wall-ball", 3, 20)]),
        ]),
        RoutineTemplate(name: "Kettlebell e metcon", detail: "Corpo todo com kettlebell, 2× por semana", routines: [
            ("Kettlebell", [3, 6], [("kettlebell-swing", 5, 20), ("agachamento-goblet", 4, 12), ("cf-kb-snatch", 4, 8),
                                    ("cf-turkish", 3, 3), ("cf-sdhp", 3, 12), ("cf-mountain-climber", 3, 30)]),
        ]),
        RoutineTemplate(name: "Em casa", detail: "Só peso do corpo, 3× por semana", routines: [
            ("Peso do corpo", [2, 4, 6], [("flexao", 4, 12), ("agachamento-livre-corpo", 4, 20), ("barra-fixa", 3, 6),
                                          ("afundo", 3, 12), ("mergulho-banco", 3, 12), ("prancha", 3, 45), ("burpee", 3, 10)]),
        ]),
    ]

    @MainActor
    func install(in context: ModelContext, startingOrder: Int) {
        for (i, r) in routines.enumerated() {
            let routine = Routine(name: r.name, weekdays: r.weekdays, order: startingOrder + i)
            context.insert(routine)
            for (j, item) in r.items.enumerated() {
                let rest = (Exercise.byID(item.0)?.group.heavy ?? false) && item.1 >= 4 ? 120 : 90
                let ri = RoutineItem(exerciseID: item.0, sets: item.1, reps: item.2, rest: rest, order: j)
                routine.items.append(ri)
            }
        }
        try? context.save()
    }
}

let weekdaySymbols: [(Int, String)] = [(2, "Seg"), (3, "Ter"), (4, "Qua"), (5, "Qui"), (6, "Sex"), (7, "Sáb"), (1, "Dom")]
