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
    var volume: Double { doneWorkSets.reduce(0) { $0 + $1.weight * Double($1.reps) } }

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

/// Treino encerrado sozinho (ao sair da academia) que mudou a rotina: a oferta de atualizar fica pendente
/// até a pessoa abrir a aba Treino e decidir
enum PendingRoutineUpdate {
    static let key = "pendingRoutineUpdate"

    static var sessionUUID: UUID? {
        get { UserDefaults.standard.string(forKey: key).flatMap(UUID.init) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: key) }
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
    let reason: String
}

enum Progression {
    /// Treinos seguidos sem completar antes de reduzir a carga
    static let deloadAfter = 3

    /// Próxima prescrição de um exercício. `history` são treinos concluídos, do mais antigo ao mais novo.
    /// Uma sessão só "conta como sucesso" se todas as séries prescritas foram feitas com as reps alvo.
    static func suggest(exerciseID: String, sets: Int, reps: Int, history: [SessionLog]) -> Suggestion {
        let ex = Exercise.byID(exerciseID)
        let past = history.filter { !$0.deload }.compactMap { s -> [SetLog]? in
            let mine = s.sets.filter { $0.exerciseID == exerciseID }
            return mine.isEmpty ? nil : mine
        }
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
