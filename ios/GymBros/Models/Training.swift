import Foundation
import SwiftData

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
    /// Superset com o exercício seguinte (sem descanso entre eles)
    var supersetNext: Bool = false
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
    /// Exercício marcado como "fazendo agora" (aparece no Live Activity)
    var currentExerciseID: String?
    /// Descanso em andamento (salvo para o Live Activity poder controlar com o app fechado)
    var restEnd: Date?
    var restTotal: Int = 90
    /// Lugar onde o treino está sendo feito
    var gymUUID: UUID?
    /// Já perguntou/identificou o lugar (não pergunta de novo)
    var placeAsked: Bool = false
    /// Exercícios ligados ao seguinte em superset (ids separados por vírgula)
    var supersetRaw: String = ""
    /// Feito numa semana de deload
    var isDeload: Bool = false
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

    // MARK: Superset

    func linkedNext(_ id: String) -> Bool { supersetRaw.split(separator: ",").contains { $0 == id } }

    func setLinkedNext(_ id: String, _ on: Bool) {
        var s = Set(supersetRaw.split(separator: ",").map(String.init))
        if on { s.insert(id) } else { s.remove(id) }
        supersetRaw = s.sorted().joined(separator: ",")
    }

    /// Bloco de exercícios seguidos ligados em superset que contém `id` (só ele, se não está em superset)
    func group(of id: String) -> [String] {
        let ids = exerciseIDs
        guard var i = ids.firstIndex(of: id) else { return [id] }
        while i > 0 && linkedNext(ids[i - 1]) { i -= 1 }
        var out = [ids[i]]
        while i < ids.count - 1 && linkedNext(ids[i]) { i += 1; out.append(ids[i]) }
        return out
    }

    func pending(_ id: String) -> Bool { sets.contains { $0.exerciseID == id && !$0.done } }

    /// Depois de uma série de `id`: escolhe o exercício atual e diz se é hora de descansar.
    /// No superset vai para o próximo do bloco sem descanso; descansa ao fechar a volta.
    @discardableResult
    func advance(after id: String) -> Bool {
        let members = group(of: id)
        let i = members.firstIndex(of: id) ?? 0
        if let later = members[(i + 1)...].first(where: pending) {
            currentExerciseID = later
            return false
        }
        if let first = members.first(where: pending) {
            currentExerciseID = first
            return true
        }
        let ids = exerciseIDs
        if let last = members.last, let j = ids.firstIndex(of: last) {
            currentExerciseID = (ids[(j + 1)...] + ids[..<j]).first(where: pending) ?? id
        }
        return true
    }

    var log: SessionLog {
        SessionLog(date: start, sets: orderedSets.filter { !$0.warmup }.map {
            SetLog(exerciseID: $0.exerciseID, weight: $0.weight, reps: $0.reps, target: $0.targetReps, done: $0.done)
        }, deload: isDeload)
    }

    // MARK: Totais (aquecimento fica de fora em todo lugar)

    /// Séries de trabalho (sem aquecimento)
    var workSets: [LoggedSet] { sets.filter { !$0.warmup } }
    /// Séries de trabalho feitas
    var doneWorkSets: [LoggedSet] { sets.filter { $0.done && !$0.warmup } }
    /// Volume: Σ carga × reps das séries de trabalho feitas
    /// Carga × reps; séries de distância × tempo ficam fora (lá `weight` são metros)
    var volume: Double { doneWorkSets.filter { Exercise.byID($0.exerciseID)?.type != .distance }.reduce(0) { $0 + $1.weight * Double($1.reps) } }

    // MARK: Troca de exercício

    /// Passa as séries pendentes de `old` para `new` com a sugestão `s` (carga e reps).
    /// Aquecimentos pendentes do antigo são apagados. Se o antigo já tinha série feita, o novo entra logo depois dele;
    /// senão ocupa o lugar. Em ambos os casos é o novo que segue no superset com o próximo (o antigo não fica ligado ao novo).
    func swapPending(_ old: String, to new: String, suggestion s: Suggestion) {
        let pending = orderedSets.filter { $0.exerciseID == old && !$0.done }
        let work = pending.filter { !$0.warmup }
        let allMoved = !sets.contains { $0.exerciseID == old && $0.done }
        let linked = linkedNext(old)
        // Aquecimento do antigo não serve para o novo
        // Só apaga: mexer na lista da relação (sets.removeAll) junto com o delete trava o SwiftData
        for w in pending where w.warmup { modelContext?.delete(w) }
        // Se já fez séries do antigo, o novo entra logo depois dele (abre espaço na ordem)
        if !allMoved, let order = work.first?.exerciseOrder {
            sets.filter { $0.exerciseOrder > order }.forEach { $0.exerciseOrder += 1 }
            work.forEach { $0.exerciseOrder = order + 1 }
        }
        for (k, set) in work.enumerated() {
            set.exerciseID = new
            set.index = k
            set.weight = s.weight
            set.reps = s.reps
            set.targetReps = s.reps
        }
        // Superset: o novo herda o elo com o próximo; o antigo (já feito, ou sumido) sai do bloco
        if linked && !work.isEmpty {
            setLinkedNext(old, false)
            setLinkedNext(new, true)
        }
        currentExerciseID = new
    }

    // MARK: Rotina de origem

    /// Como o treino ficou: exercício, séries, reps alvo, descanso e superset
    struct Plan: Equatable { let id: String; let sets: Int; let reps: Int; let rest: Int; let superset: Bool }

    func plan(routine: Routine?) -> [Plan] {
        let ids = exerciseIDs
        return ids.enumerated().compactMap { i, id in
            let work = orderedSets.filter { $0.exerciseID == id && !$0.warmup }
            guard let first = work.first else { return nil }
            // Com objetivo, as reps mudam a cada treino pela dupla progressão: não são mudança da rotina
            let reps = TrainingGoal.of(id) != nil ? (routine?.items.first { $0.exerciseID == id }?.reps ?? first.targetReps) : first.targetReps
            return Plan(id: id, sets: work.count, reps: reps, rest: first.rest,
                        superset: linkedNext(id) && i < ids.count - 1)
        }
    }

    /// Diferenças entre o treino feito e a rotina, em frases
    func routineChanges(_ r: Routine) -> [String] {
        let old = r.sortedItems.map { Plan(id: $0.exerciseID, sets: $0.sets, reps: $0.reps, rest: $0.rest, superset: $0.supersetNext) }
        let new = plan(routine: r)
        guard old != new else { return [] }
        var out: [String] = []
        let oldIDs = old.map(\.id), newIDs = new.map(\.id)
        for p in new where !oldIDs.contains(p.id) { out.append("Entra \(Exercise.name(p.id)) (\(p.sets)×\(p.reps))") }
        for p in old where !newIDs.contains(p.id) { out.append("Sai \(Exercise.name(p.id))") }
        if oldIDs.filter(newIDs.contains) != newIDs.filter(oldIDs.contains) { out.append("Nova ordem dos exercícios") }
        for p in new {
            guard let o = old.first(where: { $0.id == p.id }) else { continue }
            let name = Exercise.name(p.id)
            if o.sets != p.sets { out.append("\(name): \(o.sets) → \(p.sets) séries") }
            if o.reps != p.reps { out.append("\(name): \(o.reps) → \(p.reps) reps") }
            if o.rest != p.rest { out.append("\(name): descanso \(clock(o.rest)) → \(clock(p.rest))") }
            if o.superset != p.superset { out.append("\(name): \(p.superset ? "superset com o próximo" : "sai do superset")") }
        }
        return out.isEmpty ? ["Ajustes na estrutura do treino"] : out
    }

    /// Recria os itens da rotina como o treino ficou (cargas não entram)
    func apply(to r: Routine, context: ModelContext) {
        let p = plan(routine: r)
        r.items.forEach(context.delete)
        r.items = []
        for (i, p) in p.enumerated() {
            let item = RoutineItem(exerciseID: p.id, sets: p.sets, reps: p.reps, rest: p.rest, order: i)
            item.supersetNext = p.superset
            r.items.append(item)
        }
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
    /// Série de aquecimento: não conta para progressão, recordes e volume
    var warmup: Bool = false
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
