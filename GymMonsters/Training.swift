import Foundation
import SwiftData

// MARK: - Modelos

@Model
final class Routine {
    var uuid: UUID = UUID()
    var name: String = ""
    /// Dias da semana do Calendar (1 = domingo … 7 = sábado), separados por vírgula
    var weekdaysRaw: String = ""
    var order: Int = 0
    @Relationship(deleteRule: .cascade, inverse: \RoutineItem.routine) var items: [RoutineItem] = []

    init(name: String, weekdays: Set<Int> = [], order: Int = 0) {
        self.name = name
        self.weekdaysRaw = weekdays.sorted().map(String.init).joined(separator: ",")
        self.order = order
    }

    var weekdays: Set<Int> {
        get { Set(weekdaysRaw.split(separator: ",").compactMap { Int($0) }) }
        set { weekdaysRaw = newValue.sorted().map(String.init).joined(separator: ",") }
    }

    var sortedItems: [RoutineItem] { items.sorted { $0.order < $1.order } }
}

@Model
final class RoutineItem {
    var exerciseID: String = ""
    var sets: Int = 3
    /// Repetições alvo (segundos, para exercícios por tempo)
    var reps: Int = 10
    var rest: Int = 90
    var order: Int = 0
    var routine: Routine?

    init(exerciseID: String, sets: Int, reps: Int, rest: Int, order: Int) {
        self.exerciseID = exerciseID
        self.sets = sets
        self.reps = reps
        self.rest = rest
        self.order = order
    }
}

@Model
final class WorkoutSession {
    var uuid: UUID = UUID()
    var title: String = ""
    var routineUUID: UUID?
    var start: Date = Date.now
    /// nil enquanto o treino está em andamento
    var end: Date?
    var effort: Int = 6
    /// Atividade gerada ao concluir (é ela que dá XP)
    var activityUUID: UUID?
    @Relationship(deleteRule: .cascade, inverse: \LoggedSet.session) var sets: [LoggedSet] = []

    init(title: String, routineUUID: UUID?) {
        self.title = title
        self.routineUUID = routineUUID
    }

    var orderedSets: [LoggedSet] { sets.sorted { ($0.exerciseOrder, $0.index) < ($1.exerciseOrder, $1.index) } }

    /// Exercícios na ordem do treino
    var exerciseIDs: [String] {
        var seen = Set<String>()
        return orderedSets.map(\.exerciseID).filter { seen.insert($0).inserted }
    }

    var log: SessionLog {
        SessionLog(date: start, sets: orderedSets.map {
            SetLog(exerciseID: $0.exerciseID, weight: $0.weight, reps: $0.reps, target: $0.targetReps, done: $0.done)
        })
    }
}

@Model
final class LoggedSet {
    var exerciseID: String = ""
    var exerciseOrder: Int = 0
    var index: Int = 0
    var weight: Double = 0
    var reps: Int = 0
    var targetReps: Int = 0
    var rest: Int = 90
    var done: Bool = false
    var session: WorkoutSession?

    init(exerciseID: String, exerciseOrder: Int, index: Int, weight: Double, reps: Int, rest: Int) {
        self.exerciseID = exerciseID
        self.exerciseOrder = exerciseOrder
        self.index = index
        self.weight = weight
        self.reps = reps
        self.targetReps = reps
        self.rest = rest
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
}

struct Suggestion {
    let weight: Double
    let reps: Int
    let reason: String
}

enum Progression {
    /// Treinos seguidos sem completar antes de reduzir a carga
    static let deloadAfter = 3

    /// Próxima prescrição de um exercício. `history` são treinos concluídos, do mais antigo ao mais novo.
    /// Uma sessão só "conta como sucesso" se todas as séries prescritas foram feitas com as reps alvo.
    static func suggest(exerciseID: String, sets: Int, reps: Int, history: [SessionLog]) -> Suggestion {
        let ex = Exercise.byID(exerciseID)
        let past = history.compactMap { s -> [SetLog]? in
            let mine = s.sets.filter { $0.exerciseID == exerciseID }
            return mine.isEmpty ? nil : mine
        }
        guard let last = past.last else {
            return Suggestion(weight: 0, reps: reps, reason: ex?.type == .weighted
                              ? "Primeira vez: escolha uma carga em que as \(reps) reps saiam com boa técnica."
                              : "Primeira vez: faça o que conseguir com boa técnica.")
        }

        let lastWeight = last.filter(\.done).map(\.weight).max() ?? last.map(\.weight).max() ?? 0
        let lastTarget = last.map(\.target).max() ?? reps
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
                let ok = s.count >= sets && s.prefix(sets).allSatisfy(\.hit)
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

    /// 1RM estimado (Epley). Não estima acima de 12 reps.
    static func oneRM(weight: Double, reps: Int) -> Double? {
        guard weight > 0, (1...12).contains(reps) else { return nil }
        return reps == 1 ? weight : weight * (1 + Double(reps) / 30)
    }

    static func bestOneRM(_ sets: [SetLog]) -> Double? {
        sets.filter(\.done).compactMap { oneRM(weight: $0.weight, reps: $0.reps) }.max()
    }

    /// Recordes batidos na sessão em relação ao histórico anterior
    static func records(in session: SessionLog, history: [SessionLog]) -> [String] {
        var out: [String] = []
        let ids = session.sets.map(\.exerciseID).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        for id in ids {
            let now = session.sets.filter { $0.exerciseID == id && $0.done }
            let before = history.flatMap(\.sets).filter { $0.exerciseID == id && $0.done }
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

    static func fmt(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(w)) : String(format: "%.1f", w).replacingOccurrences(of: ".", with: ",")
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
