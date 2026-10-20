import HealthKit
import SwiftData
import SwiftUI

// Treino feito sem dar "Começar": no registro de atividade dá para dizer qual rotina (ou quais exercícios) ou qual WOD
// foi. Ao salvar, vira o mesmo que o treino guiado gravaria: sessão com as séries (progressão, recordes, divisão dos
// atributos) ou resultado do WOD (histórico e recorde do WOD).

struct ManualWorkoutDraft: Equatable {
    enum Mode: Hashable { case none, routine, wod }

    struct Item: Identifiable, Equatable {
        let id = UUID()
        var exerciseID: String
        var sets: Int
        var reps: Int
        var weight: Double?
    }

    var mode: Mode = .none
    // Rotina ou exercícios à mão
    var routineID: UUID?
    var title = "Treino livre"
    var items: [Item] = []
    // WOD
    var wodID: String?
    var minutesDone = 10
    var secondsDone = 0
    var capped = false
    var rounds = 0
    var reps = 0
    var rx = true

    /// For Time sem cap estourado precisa de um tempo: 0:00 viraria um recorde impossível de bater
    func hasResult(_ wod: Wod) -> Bool {
        if case .forTime(let cap) = wod.format, !(capped && cap != nil) { return minutesDone * 60 + secondsDone > 0 }
        return true
    }

    var isEmpty: Bool {
        switch mode {
        case .none: true
        case .routine: items.isEmpty
        case .wod: wodID == nil
        }
    }

    /// WODs do coach que você já trouxe, até 7 dias antes ou depois do treino, o mais perto primeiro
    static func coachWods(near date: Date) -> [PlannedWod] {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        func gap(_ p: PlannedWod) -> Int { abs(cal.dateComponents([.day], from: day, to: cal.startOfDay(for: p.day)).day ?? 99) }
        return WodPlan.all().filter { gap($0) <= 7 }.sorted { gap($0) < gap($1) }
    }

    /// Resumo para o cartão do registro: "Peito · 5 exercícios · 18 séries", "Fran · 7:30 RX"
    @MainActor
    var summary: (icon: String, title: String, subtitle: String)? {
        switch mode {
        case .none: return nil
        case .routine:
            guard !items.isEmpty else { return nil }
            let sets = items.map(\.sets).reduce(0, +)
            return ("dumbbell.fill", title, "\(items.count) \(items.count == 1 ? "exercício" : "exercícios") · \(sets) séries")
        case .wod:
            guard let w = Self.wod(wodID) else { return nil }
            return ("flame.fill", w.name, w.format.name + " · " + result(for: w).text + (rx ? " RX" : ""))
        }
    }

    @MainActor
    static func wod(_ id: String?) -> Wod? {
        guard let id else { return nil }
        return Wod.byID(id) ?? WodPlan.all().first { $0.wodID == id }?.wod
    }

    /// Resultado do WOD como texto (para o título do check-in)
    @MainActor
    var wodText: String? {
        guard mode == .wod, let wod = Self.wod(wodID) else { return nil }
        return "\(wod.name) · \(result(for: wod).text)"
    }

    @MainActor
    private func result(for wod: Wod) -> WodResult {
        let r = WodResult(wodID: wod.id, wodName: wod.name, formatName: wod.format.name)
        switch wod.format {
        case .forTime(let cap):
            if capped, cap != nil {
                r.capped = true
                r.seconds = (cap ?? minutesDone) * 60
                r.reps = reps
            } else {
                r.seconds = minutesDone * 60 + secondsDone
            }
        case .amrap, .intervals(_, _, false): r.rounds = rounds; r.reps = reps
        default: break
        }
        r.rx = rx
        return r
    }

    /// Grava a sessão ou o resultado ligados à atividade (antes de calcular a divisão dos atributos)
    @MainActor
    func save(for activity: Activity, context: ModelContext) {
        switch mode {
        case .none: return
        case .routine:
            guard !items.isEmpty else { return }
            let s = WorkoutSession(title: title, routineUUID: routineID)
            s.start = activity.date
            s.end = activity.date.addingTimeInterval(Double(max(activity.minutes, 1)) * 60)
            s.effort = activity.effort
            s.activityUUID = activity.uuid
            s.gymUUID = activity.gymUUID
            s.placeAsked = true
            context.insert(s)
            for (i, item) in items.enumerated() {
                for k in 0..<max(item.sets, 1) {
                    let set = LoggedSet(exerciseID: item.exerciseID, exerciseOrder: i, index: k, weight: item.weight ?? 0, reps: item.reps, rest: 90)
                    set.done = true
                    s.sets.append(set)
                }
            }
        case .wod:
            guard let wod = Self.wod(wodID) else { return }
            let r = result(for: wod)
            r.date = activity.date
            r.activityUUID = activity.uuid
            context.insert(r)
        }
    }
}

/// Seção do registro de atividade: "Treino feito". Vazia, é um convite; preenchida, um resumo para editar ou tirar.
struct ManualWorkoutSection: View {
    @Binding var draft: ManualWorkoutDraft
    @Binding var type: UInt
    @Binding var minutes: Int
    let date: Date
    @State private var open = false

    var body: some View {
        GMSection("Treino feito", footer: draft.summary == nil
                  ? "Esqueceu de dar Começar? Diga o que treinou: as séries entram na progressão e nos recordes, e o resultado do WOD no histórico."
                  : nil) {
            if let s = draft.summary {
                GMRow(icon: s.icon, tile: s.icon == "flame.fill" ? Theme.streak : Theme.accent, title: s.title, subtitle: s.subtitle,
                      action: { open = true }) {
                    GMIconButton(icon: "xmark", size: 28, label: "Tirar treino") {
                        withAnimation(.snappy) { draft = ManualWorkoutDraft() }
                    }
                }
            } else {
                GMRow(icon: "plus", tile: Theme.accent, title: "Adicionar o que você treinou", subtitle: "Rotina, treino livre ou WOD do coach",
                      chevron: true, action: { open = true }) { EmptyView() }
            }
        }
        .gmModal(isPresented: $open) {
            WorkoutDoneFlow(initial: draft, date: date) { done in
                draft = done
                switch done.mode {
                case .routine: type = WorkoutType.of(.musculacao).id
                case .wod:
                    type = WorkoutType.of(.crossfit).id
                    if let total = ManualWorkoutDraft.wod(done.wodID)?.format.totalSeconds { minutes = max(5, Int((Double(total) / 60).rounded(.up))) }
                case .none: break
                }
            }
        }
    }
}

/// "O que você treinou?": escolher (rotina, livre, WOD do coach, clássico) e depois preencher séries ou resultado
struct WorkoutDoneFlow: View {
    let date: Date
    let done: (ManualWorkoutDraft) -> Void
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Routine.order) private var routines: [Routine]
    @State private var work: ManualWorkoutDraft
    @State private var choosing: Bool
    @State private var picking = false
    @State private var importing = false
    @State private var classics = false

    init(initial: ManualWorkoutDraft, date: Date, done: @escaping (ManualWorkoutDraft) -> Void) {
        self.date = date
        self.done = done
        _work = State(initialValue: initial)
        _choosing = State(initialValue: initial.summary == nil)
    }

    var body: some View {
        GMModal(choosing ? "O que você treinou?" : work.mode == .wod ? "Resultado do WOD" : work.title) {
            if choosing { chooser } else if work.mode == .wod { wodForm } else { routineForm }
        }
        .animation(.snappy, value: choosing)
        .gmModal(isPresented: $picking) {
            ExercisePicker { e in
                work.items.append(.init(exerciseID: e.id, sets: 3, reps: e.type == .time ? 30 : 10, weight: nil))
                picking = false
            }
        }
        .gmModal(isPresented: $importing) {
            ImportWodView(initialDay: date) { plan in
                work.mode = .wod
                work.wodID = plan.wodID
                choosing = false
            }
        }
    }

    // MARK: Escolha

    @ViewBuilder
    private var chooser: some View {
        GMSection("Musculação") {
            ForEach(routines) { r in
                GMRow(icon: "list.bullet", tile: Theme.accent, title: r.name,
                      subtitle: weekdaysText(r.weekdays) + " · \(r.items.count) exercícios", chevron: true, action: { load(r) }) { EmptyView() }
                GMDivider()
            }
            GMRow(icon: "plus", tile: Theme.raised, title: "Treino livre", subtitle: "Escolha os exercícios que fez", chevron: true, action: {
                work = ManualWorkoutDraft(mode: .routine)
                choosing = false
                picking = true
            }) { EmptyView() }
        }

        let coach = ManualWorkoutDraft.coachWods(near: date)
        GMSection("WOD do coach", footer: "O WOD muda todo dia: traga o do dia pelo print ou texto do app do box, ou use um que você já trouxe.") {
            GMRow(icon: "text.viewfinder", tile: Theme.streak, title: "Trazer o WOD do coach", subtitle: "Print, foto do quadro ou texto",
                  chevron: true, action: { importing = true }) { EmptyView() }
            ForEach(coach) { p in
                GMDivider()
                GMRow(icon: "flame.fill", iconTint: Theme.streak, title: p.name,
                      subtitle: PlannedWodView.dayText(p.day) + " · " + p.format.name + " · " + p.lines.prefix(2).joined(separator: ", "),
                      chevron: true, action: { pickWod(p.wodID) }) { EmptyView() }
            }
        }

        GMSection("WODs clássicos") {
            if classics {
                ForEach(Array(Wod.benchmarks.enumerated()), id: \.element.id) { i, w in
                    if i > 0 { GMDivider() }
                    GMRow(icon: "trophy.fill", iconTint: Theme.trophy, title: w.name, subtitle: w.format.name, chevron: true,
                          action: { pickWod(w.id) }) { EmptyView() }
                }
            } else {
                GMRow(icon: "trophy.fill", iconTint: Theme.trophy, title: "Ver os clássicos",
                      subtitle: Wod.benchmarks.prefix(3).map(\.name).joined(separator: ", ") + "…", chevron: true,
                      action: { withAnimation(.snappy) { classics = true } }) { EmptyView() }
            }
        }
    }

    private func back() -> some View {
        Button { choosing = true } label: {
            Label("Trocar treino", systemImage: "chevron.left").font(.subheadline.bold()).foregroundStyle(Theme.accent)
        }
        .buttonStyle(GMPress())
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Rotina com as cargas que o treino guiado sugeriria (você ajusta o que mudou)
    private func load(_ r: Routine) {
        let ctx = AppData.container.mainContext
        let finished = (try? ctx.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.end != nil },
                                                                      sortBy: [SortDescriptor(\.start)]))) ?? []
        let history = finished.map(\.log)
        work = ManualWorkoutDraft(mode: .routine, routineID: r.uuid, title: r.name, items: r.sortedItems.map { item in
            let s = Progression.suggest(exerciseID: item.exerciseID, sets: item.sets, reps: item.reps, history: history)
            return .init(exerciseID: item.exerciseID, sets: s.sets ?? item.sets, reps: s.reps, weight: s.weight > 0 ? s.weight : nil)
        })
        choosing = false
    }

    private func pickWod(_ id: String) {
        work = ManualWorkoutDraft(mode: .wod, wodID: id)
        if case .forTime(let cap?) = ManualWorkoutDraft.wod(id)?.format { work.minutesDone = min(cap, 10) }
        choosing = false
    }

    private func finish() {
        done(work)
        dismiss()
    }

    // MARK: Rotina

    @ViewBuilder
    private var routineForm: some View {
        back()
        if work.routineID == nil {
            GMTextField(placeholder: "Nome do treino", text: $work.title, capitalization: .sentences)
        }
        Text("Ajuste o que foi diferente do previsto.").font(.caption).foregroundStyle(Theme.dim)
        ForEach($work.items) { $item in itemCard($item) }
        GMButton("Adicionar exercício", icon: "plus", kind: .secondary) { picking = true }
        GMButton("Pronto", icon: "checkmark", enabled: !work.items.isEmpty) { finish() }
    }

    private func itemCard(_ item: Binding<ManualWorkoutDraft.Item>) -> some View {
        let e = Exercise.byID(item.wrappedValue.exerciseID)
        let timed = e?.type == .time
        return GMCard {
            HStack(spacing: 12) {
                if let e { ExerciseThumb(exercise: e, size: 40) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(Exercise.name(item.wrappedValue.exerciseID)).font(.subheadline.bold()).lineLimit(1)
                    Text(line(item.wrappedValue, timed: timed)).font(.caption.monospacedDigit()).foregroundStyle(Theme.accent)
                }
                Spacer()
                GMIconButton(icon: "trash", size: 30, label: "Tirar exercício") {
                    withAnimation(.snappy) { work.items.removeAll { $0.id == item.wrappedValue.id } }
                }
            }
            GMDivider()
            GMStepper(title: "Séries", value: item.sets, range: 1...12)
            GMStepper(title: timed ? "Segundos" : "Reps", value: item.reps, range: 1...(timed ? 600 : 100), step: timed ? 5 : 1)
            if !timed {
                GMDecimalField(title: e?.type == .bodyweight ? "Carga extra" : "Carga", value: item.weight, step: e?.increment ?? 2.5,
                               start: e?.type == .bodyweight ? 0 : 20)
            }
        }
    }

    /// "3 × 10 · 60 kg"
    private func line(_ i: ManualWorkoutDraft.Item, timed: Bool) -> String {
        let w = (i.weight ?? 0) > 0 ? " · \(i.weight!.formatted(.number.precision(.fractionLength(0...1)))) kg" : ""
        return "\(i.sets) × \(i.reps)\(timed ? " s" : "")" + w
    }

    // MARK: WOD

    @ViewBuilder
    private var wodForm: some View {
        back()
        if let w = ManualWorkoutDraft.wod(work.wodID) {
            GMCard {
                HStack {
                    Text(w.name).font(.headline)
                    Spacer()
                    GMBadge(text: w.format.name, tint: Theme.streak)
                }
                ForEach(Array(w.lines.enumerated()), id: \.offset) { Text($0.element).font(.subheadline) }
            }
            GMSection("Seu resultado") {
                switch w.format {
                case .forTime(let cap):
                    // Sem limite de tempo não há time cap a estourar
                    if let cap {
                        GMToggle(title: "Estourou o time cap", subtitle: "Limite de \(cap) min", isOn: $work.capped)
                        GMDivider()
                    }
                    if work.capped && cap != nil {
                        GMStepper(title: "Reps feitas", value: $work.reps, range: 0...999)
                    } else {
                        GMStepper(title: "Minutos", value: $work.minutesDone, range: 0...90)
                        GMStepper(title: "Segundos", value: $work.secondsDone, range: 0...55, step: 5)
                    }
                case .amrap, .intervals(_, _, false):
                    GMStepper(title: "Rodadas", value: $work.rounds, range: 0...200)
                    GMStepper(title: "Reps extras", value: $work.reps, range: 0...300)
                default:
                    Text("Conta como concluído.").font(.subheadline).foregroundStyle(Theme.dim)
                }
                GMDivider()
                GMToggle(title: "RX", subtitle: "Cargas e movimentos como prescritos", isOn: $work.rx)
            }
            GMButton("Pronto", icon: "checkmark", enabled: work.hasResult(w)) { finish() }
        }
    }
}
