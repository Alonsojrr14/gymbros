import SwiftData
import SwiftUI

/// Recorde pessoal registrado à mão (ex.: o que você já levantava antes de usar o app)
@Model
final class PersonalRecord {
    var uuid: UUID = UUID()
    var exerciseID: String = ""
    var weight: Double = 0
    var reps: Int = 1
    var date: Date = Date.now

    init(exerciseID: String, weight: Double, reps: Int, date: Date) {
        self.exerciseID = exerciseID
        self.weight = weight
        self.reps = reps
        self.date = date
    }

    var log: SetLog { SetLog(exerciseID: exerciseID, weight: weight, reps: reps, target: reps, done: true) }
}

/// PRs registrados à mão, em memória para a progressão (que é uma função pura) poder consultar
enum PRBook {
    nonisolated(unsafe) static var manual: [String: [SetLog]] = [:]

    @MainActor
    static func reload() {
        let all = (try? AppData.container.mainContext.fetch(FetchDescriptor<PersonalRecord>())) ?? []
        manual = Dictionary(grouping: all.map(\.log), by: \.exerciseID)
    }

    /// Melhor série: maior 1RM estimado, ou maior carga, ou mais reps
    static func best(_ sets: [SetLog]) -> SetLog? {
        sets.filter(\.done).max { a, b in
            let ra = Progression.oneRM(weight: a.weight, reps: a.reps) ?? a.weight
            let rb = Progression.oneRM(weight: b.weight, reps: b.reps) ?? b.weight
            return (ra, a.reps) < (rb, b.reps)
        }
    }

    /// Carga de trabalho para `reps` a partir do melhor PR registrado à mão (com 1–2 reps de sobra)
    static func workingWeight(exerciseID: String, reps: Int, increment: Double) -> (weight: Double, pr: SetLog)? {
        guard let pr = best(manual[exerciseID] ?? []), pr.weight > 0 else { return nil }
        let w: Double
        if let orm = Progression.oneRM(weight: pr.weight, reps: pr.reps) {
            w = orm / (1 + Double(reps) / 30) * 0.92
        } else if pr.reps >= reps {
            w = pr.weight
        } else {
            return nil
        }
        let rounded = (w / increment).rounded(.down) * increment
        return rounded > 0 ? (rounded, pr) : nil
    }
}

// MARK: - Tela

/// Melhores marcas por exercício (treinos + registradas à mão) e a sessão de PR
struct PRBookView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PersonalRecord.date, order: .reverse) private var records: [PersonalRecord]
    @Query(filter: #Predicate<WorkoutSession> { $0.end != nil }) private var sessions: [WorkoutSession]
    @State private var session = false
    @State private var single: IDBox?
    @State private var menu: String?

    private struct Row: Identifiable {
        let id: String
        let best: SetLog
        let date: Date
        let manual: Bool
    }

    private var rows: [Row] {
        var cands: [String: [(SetLog, Date, Bool)]] = [:]
        for r in records { cands[r.exerciseID, default: []].append((r.log, r.date, true)) }
        for s in sessions {
            for set in s.log.sets where set.done && set.weight > 0 { cands[set.exerciseID, default: []].append((set, s.start, false)) }
        }
        return cands.compactMap { id, list in
            guard let b = PRBook.best(list.map(\.0)), let hit = list.first(where: { $0.0.weight == b.weight && $0.0.reps == b.reps }) else { return nil }
            return Row(id: id, best: b, date: hit.1, manual: hit.2)
        }
        .sorted { Exercise.name($0.id).localizedStandardCompare(Exercise.name($1.id)) == .orderedAscending }
    }

    var body: some View {
        GMScreen("Meus PRs", back: true) {
            GMCard {
                HStack(spacing: 12) {
                    Text("🏆").font(.system(size: 36))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Sessão de PR").font(.headline)
                        Text("Registre carga e reps máximas de vários exercícios de uma vez. No primeiro treino de cada um, a carga sugerida já vem calculada daqui.")
                            .font(.caption).foregroundStyle(Theme.dim)
                    }
                }
                GMButton("Começar sessão de PR", icon: "plus") { session = true }
            }
            if rows.isEmpty {
                GMEmptyState(icon: "trophy", title: "Nenhum PR ainda", message: "Registre seus PRs ou conclua um treino.")
            } else {
                GMSection("Melhores marcas", footer: "Considera os treinos do app e o que você registrou à mão. 1RM estimado pela fórmula de Epley (até 12 reps).") {
                    ForEach(rows) { r in
                        Button { menu = r.id } label: { row(r) }
                            .buttonStyle(GMPress())
                        if r.id != rows.last?.id { GMDivider() }
                    }
                }
            }
        }
        .gmModal(isPresented: $session) { PRSessionView() }
        .gmModal(item: $single) { PRSessionView(only: $0.id) }
        .gmActions(isPresented: Binding(get: { menu != nil }, set: { if !$0 { menu = nil } }), title: menu.map(Exercise.name) ?? "",
                   actions: menu.map { id in
                       var list = [GMAction("Registrar novo PR", icon: "plus") { single = IDBox(id: id) }]
                       let mine = records.filter { $0.exerciseID == id }
                       if !mine.isEmpty {
                           list.append(GMAction("Apagar PRs registrados à mão (\(mine.count))", icon: "trash", destructive: true) {
                               mine.forEach(context.delete)
                               try? context.save()
                               PRBook.reload()
                           })
                       }
                       return list
                   } ?? [])
    }

    private func row(_ r: Row) -> some View {
        HStack(spacing: 12) {
            if let ex = Exercise.byID(r.id) { ExerciseThumb(exercise: ex, size: 44) }
            VStack(alignment: .leading, spacing: 2) {
                Text(Exercise.name(r.id)).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text((Progression.oneRM(weight: r.best.weight, reps: r.best.reps).map { "1RM ~\(Progression.fmt($0.rounded())) kg · " } ?? "")
                     + r.date.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits)) + (r.manual ? " · registrado" : " · no treino"))
                    .font(.caption).foregroundStyle(Theme.dim)
            }
            Spacer()
            Text("\(Progression.fmt(r.best.weight)) kg × \(r.best.reps)").font(.subheadline.bold().monospacedDigit()).foregroundStyle(Theme.accent)
        }
        .contentShape(Rectangle())
        .foregroundStyle(.white)
    }
}

// MARK: - Sessão de PR

/// Vários exercícios de uma vez: carga e reps de cada um
struct PRSessionView: View {
    /// Abre só com este exercício
    var only: String? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Routine.order) private var routines: [Routine]
    @Query private var records: [PersonalRecord]
    @Query(filter: #Predicate<WorkoutSession> { $0.end != nil }) private var sessions: [WorkoutSession]
    @State private var ids: [String] = []
    @State private var weights: [String: Double] = [:]
    @State private var reps: [String: Double] = [:]
    @State private var date = Date.now
    @State private var picking = false
    @State private var loaded = false

    private var filled: [String] { ids.filter { (weights[$0] ?? 0) > 0 && (reps[$0] ?? 0) >= 1 } }

    var body: some View {
        GMModal(only == nil ? "Sessão de PR" : "Novo PR", confirm: "Salvar", confirmEnabled: !filled.isEmpty, onConfirm: save) {
            if only == nil {
                Text("Preencha só o que você testou hoje (ou lembra). Exercícios em branco são ignorados.")
                    .font(.subheadline).foregroundStyle(Theme.dim)
            }
            ForEach(ids, id: \.self) { id in card(id) }
            if only == nil {
                GMButton("Adicionar exercício", icon: "plus", kind: .secondary) { picking = true }
            }
            GMSection("Quando") { GMDateTimePicker(date: $date) }
        }
        .gmModal(isPresented: $picking) {
            ExercisePicker { ex in if !ids.contains(ex.id) { ids.append(ex.id) } }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let only { ids = [only]; return }
            // Exercícios com carga das suas rotinas, na ordem
            var seen = Set<String>()
            ids = routines.flatMap(\.sortedItems).map(\.exerciseID)
                .filter { Exercise.byID($0)?.type == .weighted && seen.insert($0).inserted }
        }
    }

    private func best(_ id: String) -> SetLog? {
        PRBook.best(records.filter { $0.exerciseID == id }.map(\.log)
                    + sessions.flatMap { $0.log.sets.filter { $0.exerciseID == id && $0.done && $0.weight > 0 } })
    }

    private func card(_ id: String) -> some View {
        let b = best(id)
        let w = weights[id] ?? 0, r = Int(reps[id] ?? 0)
        let newOrm = Progression.oneRM(weight: w, reps: r) ?? w
        let oldOrm = b.map { Progression.oneRM(weight: $0.weight, reps: $0.reps) ?? $0.weight } ?? 0
        return GMCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Exercise.name(id)).font(.headline)
                    Text(b.map { "Atual: \(Progression.fmt($0.weight)) kg × \($0.reps)" } ?? "Sem PR ainda")
                        .font(.caption).foregroundStyle(Theme.dim)
                }
                Spacer()
                if w > 0, r > 0, newOrm > oldOrm + 0.01 { GMBadge(text: "🏆 novo PR") }
                if only == nil {
                    Button { ids.removeAll { $0 == id } } label: { Image(systemName: "xmark").font(.caption.bold()).foregroundStyle(Theme.dim) }
                        .buttonStyle(GMPress())
                }
            }
            GMDecimalField(title: "Carga", value: Binding(get: { weights[id] }, set: { weights[id] = $0 }),
                           step: Exercise.byID(id)?.increment ?? 2.5, unit: "kg", start: b?.weight ?? 20)
            GMDivider()
            GMDecimalField(title: "Reps", value: Binding(get: { reps[id] }, set: { reps[id] = $0.map { max(1, $0.rounded()) } }),
                           step: 1, unit: "reps", start: 1)
            if w > 0, r > 0, let orm = Progression.oneRM(weight: w, reps: r) {
                Text("1RM estimado ~\(Progression.fmt(orm.rounded())) kg").font(.caption).foregroundStyle(Theme.accent)
            }
        }
    }

    private func save() {
        for id in filled {
            context.insert(PersonalRecord(exerciseID: id, weight: weights[id]!, reps: Int(reps[id]!), date: date))
        }
        try? context.save()
        PRBook.reload()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
