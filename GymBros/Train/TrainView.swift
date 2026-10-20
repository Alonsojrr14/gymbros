import SwiftData
import SwiftUI
import UserNotifications

struct TrainView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Routine.order) private var routines: [Routine]
    @Query(sort: \WorkoutSession.start, order: .reverse) private var sessions: [WorkoutSession]
    @Query private var wodResults: [WodResult]
    @AppStorage(WodPlan.key) private var plannedRaw = ""
    @State private var importing = false
    @State private var coachWod: Wod?
    @State private var wodRun = WodRun.shared
    @State private var planDetail: PlannedWod?
    @State private var active: WorkoutSession?
    @State private var templates = false
    @State private var library = false

    private var finished: [WorkoutSession] { sessions.filter { $0.end != nil } }
    private var inProgress: WorkoutSession? { sessions.first { $0.end == nil } }
    private var today: Int { Calendar.current.component(.weekday, from: .now) }
    private var plannedToday: PlannedWod? { WodPlan.pending(raw: plannedRaw, done: Set(wodResults.map(\.wodID))) }
    private var plannedNext: [PlannedWod] {
        WodPlan.all(plannedRaw).filter { $0.day > Calendar.current.startOfDay(for: .now) && !Calendar.current.isDateInToday($0.day) }
    }

    @State private var routineMenu: Routine?
    /// Rotina a apagar, esperando confirmação
    @State private var confirmDeleteRoutine: Routine?
    /// Treino encerrado sozinho que mudou a rotina (oferta de atualizar pendente)
    @AppStorage(PendingRoutineUpdate.key) private var pendingRaw = ""
    @State private var sessionMenu: WorkoutSession?
    @State private var editing: Routine?
    @State private var plates = false
    @State private var outdoor: ActivityKind?
    /// Muda quando o deload começa/termina, para a tela redesenhar
    @AppStorage("deloadUntil") private var deloadUntil: Double = 0

    var body: some View {
        NavigationStack {
            GMScreen("Treino", avatar: true) {
                deloadCard
                pendingRoutineCard
                if let w = wodRun.state {
                    GMCard {
                        card(title: w.wod.name, subtitle: w.startedAt != nil ? "WOD em andamento · \(w.wod.format.name)"
                                 : w.sessionStart != nil ? "Em andamento · \(w.onWod ? "WOD" : w.wod.parts[w.phase].title)"
                                 : "Aberto desde \(w.openedAt.formatted(date: .omitted, time: .shortened))",
                             action: "Continuar") { coachWod = w.wod }
                    }
                }
                if let s = inProgress {
                    GMCard {
                        card(title: s.title, subtitle: "Em andamento desde \(s.start.formatted(date: .omitted, time: .shortened))",
                             action: "Continuar") { active = s }
                    }
                    .onboardingTarget(.trainToday, shape: .rounded(Theme.radius))
                } else {
                    let todays = routines.filter { $0.weekdays.contains(today) }
                    GMSection(todays.isEmpty ? "Hoje" : "Hoje · \(Date.now.formatted(.dateTime.weekday(.wide)))") {
                        if let p = plannedToday, wodRun.state == nil {
                            card(title: p.name, subtitle: "Treino do coach · \(p.format.name)", action: "Começar") { coachWod = p.wod }
                            GMRow(icon: "list.bullet", title: "Ver treino completo", subtitle: p.parts.isEmpty ? nil : p.parts.map(\.title).joined(separator: ", "),
                                  chevron: true) { planDetail = p }
                            GMDivider()
                        }
                        if todays.isEmpty && plannedToday == nil {
                            Text(routines.isEmpty ? "Crie uma rotina ou use um modelo pronto." : "Nenhuma rotina para hoje. Descanso também evolui o bro.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.dim)
                        }
                        ForEach(todays) { r in
                            card(title: r.name, subtitle: "\(r.items.count) exercícios · \(r.items.reduce(0) { $0 + $1.sets }) séries",
                                 action: "Começar") { start(r) }
                            GMDivider()
                        }
                        GMRow(icon: "plus", iconTint: Theme.accent, title: "Treino livre", subtitle: "Monte na hora", chevron: true) { start(nil) }
                    }
                    .onboardingTarget(.trainToday, shape: .rounded(Theme.radius))
                }

                GMSection("Minhas rotinas") {
                    ForEach(routines) { r in
                        GMRow(icon: "list.bullet.rectangle", title: r.name,
                              subtitle: weekdaysText(r.weekdays) + " · \(r.items.count) exercícios",
                              action: { editing = r }) {
                            GMIconButton(icon: "ellipsis", size: 32) { routineMenu = r }
                        }
                        GMDivider()
                    }
                    GMRow(icon: "plus", iconTint: Theme.accent, title: "Nova rotina", action: newRoutine)
                    GMDivider()
                    GMRow(icon: "square.stack", iconTint: Theme.accent, title: "Usar modelo pronto", chevron: true) { templates = true }
                }

                GMSection("CrossFit") {
                    GMRow(icon: "doc.on.clipboard", iconTint: Theme.accent, title: "Importar treino do coach",
                          subtitle: "Cole o texto ou leia um print", chevron: true) { importing = true }
                    GMDivider()
                    ForEach(plannedNext) { p in
                        GMRow(icon: "calendar", title: p.name, subtitle: PlannedWodView.dayText(p.day) + " · " + p.format.name, chevron: true) { planDetail = p }
                        GMDivider()
                    }
                    NavigationLink { WodTimelineView() } label: {
                        GMRow(icon: "clock.arrow.circlepath", iconTint: Theme.accent, title: "Meus WODs",
                              subtitle: "Linha do tempo do que você importou e treinou", chevron: true)
                    }
                    .buttonStyle(GMPress())
                    GMDivider()
                    NavigationLink { WodListView() } label: {
                        GMRow(icon: "flame.fill", iconTint: Theme.streak, title: "WODs e cronômetro",
                              subtitle: "Fran, Cindy, Murph… · For Time, AMRAP, EMOM, Tabata", chevron: true)
                    }
                    .buttonStyle(GMPress())
                }

                GMSection("Evolução") {
                    NavigationLink { PRBookView() } label: {
                        GMRow(icon: "trophy.fill", iconTint: Theme.trophy, title: "Meus PRs", subtitle: "Sessão de PR: carga e reps de cada exercício", chevron: true)
                    }
                    .buttonStyle(GMPress())
                    GMDivider()
                    NavigationLink { ExerciseStatsList(sessions: finished) } label: {
                        GMRow(icon: "chart.line.uptrend.xyaxis", title: "Exercícios e recordes", chevron: true)
                    }
                    .buttonStyle(GMPress())
                    GMDivider()
                    NavigationLink { WeeklyVolumeView() } label: {
                        GMRow(icon: "chart.bar.fill", title: "Volume semanal por músculo", subtitle: "Séries por grupo vs. faixa de 10–20", chevron: true)
                    }
                    .buttonStyle(GMPress())
                    GMDivider()
                    NavigationLink { MuscleMapView(sessions: finished) } label: {
                        GMRow(icon: "figure.stand", title: "Mapa muscular", chevron: true)
                    }
                    .buttonStyle(GMPress())
                    GMDivider()
                    GMRow(icon: "books.vertical", title: "Biblioteca de exercícios", chevron: true) { library = true }
                    GMDivider()
                    NavigationLink { BodyTrackerView() } label: {
                        GMRow(icon: "scalemass", title: "Peso e medidas", chevron: true)
                    }
                    .buttonStyle(GMPress())
                    GMDivider()
                    GMRow(icon: "circle.grid.2x1", title: "Calculadora de anilhas", chevron: true) { plates = true }
                }

                if !finished.isEmpty {
                    GMSection("Treinos recentes") {
                        ForEach(finished.prefix(10)) { s in
                            NavigationLink { SessionDetailView(session: s) } label: {
                                HStack {
                                    SessionRow(session: s)
                                    Spacer()
                                    GMIconButton(icon: "ellipsis", size: 32) { sessionMenu = s }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(GMPress())
                            if s.id != finished.prefix(10).last?.id { GMDivider() }
                        }
                    }
                }
            }
            .navigationDestination(item: $editing) { RoutineEditView(routine: $0) }
            .onReceive(NotificationCenter.default.publisher(for: NotificationRouter.startWorkout)) { _ in startToday() }
            .gmModal(isPresented: $importing) { ImportWodView() }
            .gmModal(item: $coachWod) { WodTimerView(wod: $0) }
            .gmModal(item: $planDetail) { PlannedWodView(initial: $0) }
            .gmModal(isPresented: $templates) { TemplatesView(startingOrder: routines.count) }
            .gmModal(isPresented: $library) { ExercisePicker() }
            .gmSheet(isPresented: $plates) { _ in PlateCalculatorView(total: 60) }
            .gmModal(item: $outdoor) { RouteRunView(kind: $0) }
            .gmModal(item: $active) { s in
                WorkoutView(session: s, history: finished.reversed().map(\.log))
            }
            .gmActions(isPresented: Binding(get: { routineMenu != nil }, set: { if !$0 { routineMenu = nil } }),
                       title: routineMenu?.name, actions: routineActions)
            .gmActions(isPresented: Binding(get: { confirmDeleteRoutine != nil }, set: { if !$0 { confirmDeleteRoutine = nil } }),
                       title: confirmDeleteRoutine.map { "Apagar \($0.name)?" }, message: "Os treinos já feitos com ela continuam no histórico.",
                       actions: confirmDeleteRoutine.map { r in [GMAction("Apagar rotina", icon: "trash", destructive: true) {
                           context.delete(r)
                           try? context.save()
                       }] } ?? [])
            .gmActions(isPresented: Binding(get: { sessionMenu != nil }, set: { if !$0 { sessionMenu = nil } }),
                       title: sessionMenu?.title, message: "O XP desse treino também sai do bro.",
                       actions: sessionMenu.map { s in [GMAction("Apagar treino", icon: "trash", destructive: true) { deleteSession(s) }] } ?? [])
        }
    }

    private var routineActions: [GMAction] {
        guard let r = routineMenu else { return [] }
        var list: [GMAction] = []
        if inProgress == nil { list.append(GMAction("Começar agora", icon: "play.fill") { start(r) }) }
        list.append(GMAction("Editar", icon: "pencil") { editing = r })
        list.append(GMAction("Apagar rotina", icon: "trash", destructive: true) { confirmDeleteRoutine = r })
        return list
    }

    private func card(title: String, subtitle: String, action: String, onTap: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(Theme.dim)
            }
            Spacer()
            GMButton(action, icon: "play.fill", full: false, small: true, action: onTap)
        }
    }

    @ViewBuilder
    private var deloadCard: some View {
        let _ = deloadUntil
        if Deload.active, let until = Deload.until {
            GMCard {
                HStack(spacing: 12) {
                    Text("🔋").font(.system(size: 30))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Semana de deload").font(.headline)
                        Text("Até \(until.addingTimeInterval(-1).formatted(.dateTime.weekday(.wide))): cargas a 70 % e menos séries. Não conta para a progressão.")
                            .font(.caption).foregroundStyle(Theme.dim)
                    }
                }
                GMButton("Encerrar deload", kind: .ghost, full: false, small: true) { Deload.stop(); deloadUntil = 0 }
            }
        } else if Deload.shouldSuggest(sessions) {
            GMCard {
                HStack(spacing: 12) {
                    Text("🔋").font(.system(size: 30))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Deload.streak(sessions)) semanas seguidas pesado").font(.headline)
                        Text("Uma semana mais leve ajuda o corpo a recuperar e você volta mais forte. Cargas a 70 % e um terço a menos de séries, só nesta semana.")
                            .font(.caption).foregroundStyle(Theme.dim)
                    }
                }
                HStack(spacing: 8) {
                    GMButton("Fazer deload", icon: "battery.100.bolt", small: true) {
                        Deload.start()
                        deloadUntil = Deload.until?.timeIntervalSince1970 ?? 0
                    }
                    GMButton("Agora não", kind: .ghost, full: false, small: true) {
                        Deload.snooze()
                        deloadUntil = -1
                    }
                }
            }
        }
    }

    /// Treino encerrado ao sair da academia e a rotina dele mudou: oferece atualizar aqui (lá não dava para perguntar)
    @ViewBuilder
    private var pendingRoutineCard: some View {
        if let id = UUID(uuidString: pendingRaw), let s = sessions.first(where: { $0.uuid == id && $0.end != nil }),
           let r = routines.first(where: { $0.uuid == s.routineUUID }) {
            let changes = s.routineChanges(r)
            if !changes.isEmpty {
                GMCard {
                    Text("Atualizar a rotina \(r.name)?").font(.headline)
                    Text("O treino de \(s.start.formatted(.dateTime.weekday(.wide))) foi encerrado ao sair da academia e ficou diferente da rotina:")
                        .font(.caption).foregroundStyle(Theme.dim)
                    ForEach(changes, id: \.self) { Text("• " + $0).font(.subheadline) }
                    HStack(spacing: 8) {
                        GMButton("Salvar na rotina", icon: "checkmark", small: true) {
                            s.apply(to: r, context: context)
                            try? context.save()
                            clearPendingUpdate()
                        }
                        GMButton("Manter como está", kind: .ghost, full: false, small: true) { clearPendingUpdate() }
                    }
                }
            }
        }
    }

    private func clearPendingUpdate() {
        pendingRaw = ""
    }

    private func start(_ routine: Routine?) {
        active = LiveWorkout.startSession(routine: routine)
    }

    /// Chegou na academia: abre o treino em andamento ou começa a rotina do dia
    private func startToday() {
        if let s = inProgress { active = s; return }
        if let w = wodRun.state { coachWod = w.wod; return }
        if let p = plannedToday { coachWod = p.wod; return }
        start(routines.first { $0.weekdays.contains(today) })
    }

    private func newRoutine() {
        context.insert(Routine(name: "Nova rotina", order: routines.count))
        try? context.save()
    }

    private func deleteSession(_ s: WorkoutSession) {
        if let id = s.activityUUID {
            try? context.delete(model: Activity.self, where: #Predicate { $0.uuid == id })
        }
        context.delete(s)
        try? context.save()
    }
}

func weekdaysText(_ days: Set<Int>) -> String {
    if days.isEmpty { return "Sem dia fixo" }
    return weekdaySymbols.filter { days.contains($0.0) }.map(\.1).joined(separator: ", ")
}

struct SessionRow: View {
    let session: WorkoutSession

    var body: some View {
        // Aquecimento fica fora das séries e do volume, como na conclusão
        let done = session.doneWorkSets
        let volume = session.volume
        VStack(alignment: .leading, spacing: 4) {
            Text(session.title).font(.subheadline.weight(.semibold))
            Text([
                session.start.formatted(.dateTime.day().month(.abbreviated)),
                session.end.map { durationText(max(Int($0.timeIntervalSince(session.start) / 60), 1)) } ?? "",
                "\(done.count) séries",
                volume > 0 ? "\(Progression.fmt(volume.rounded())) kg" : "",
            ].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(Theme.dim)
        }
    }
}

struct SessionDetailView: View {
    let session: WorkoutSession
    @Environment(\.modelContext) private var context
    /// Série tocada para corrigir
    @State private var editing: LoggedSet?
    @State private var weight: Double?
    @State private var reps: Double?

    var body: some View {
        GMScreen(session.title, subtitle: session.start.formatted(date: .complete, time: .shortened), back: true) {
            GMIconButton(icon: "square.and.arrow.up", label: "Compartilhar treino") { shareWorkoutStory(session, context: context) }
        } content: {
            Text("Toque numa série para corrigir carga ou reps.").font(.caption).foregroundStyle(Theme.dim)
            ForEach(Array(session.exerciseIDs.enumerated()), id: \.offset) { _, id in
                GMSection(Exercise.name(id)) {
                    ForEach(session.orderedSets.filter { $0.exerciseID == id }) { s in
                        Button { open(s) } label: { row(s, id: id) }
                            .buttonStyle(GMPress())
                    }
                }
            }
        }
        .gmSheet(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) { close in
            if let s = editing { editor(s, close: close) }
        }
    }

    private func row(_ s: LoggedSet, id: String) -> some View {
        HStack {
            Text(s.warmup ? "A" : "\(s.index - session.orderedSets.filter { $0.exerciseID == id && $0.warmup }.count + 1)")
                .foregroundStyle(s.warmup ? Theme.streak : Theme.dim).frame(width: 24, alignment: .leading)
            Text(setText(s))
            Spacer()
            if s.done && !s.warmup && s.reps < s.targetReps {
                Text("meta \(s.targetReps)").font(.caption.bold()).foregroundStyle(Theme.warning)
            }
            Image(systemName: s.done ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(s.done ? Theme.accent : Theme.dim)
        }
        .contentShape(Rectangle())
        .foregroundStyle(.white)
    }

    private func open(_ s: LoggedSet) {
        weight = s.weight
        reps = Double(s.reps)
        editing = s
    }

    private func editor(_ s: LoggedSet, close: @escaping () -> Void) -> some View {
        let ex = Exercise.byID(s.exerciseID)
        let others = session.orderedSets.filter { $0.exerciseID == s.exerciseID && $0.warmup == s.warmup }
        return VStack(alignment: .leading, spacing: 14) {
            Text("\(Exercise.name(s.exerciseID)) · \(s.warmup ? "aquecimento" : "série \((others.firstIndex { $0 === s } ?? 0) + 1)")").font(.headline)
            GMDecimalField(title: "Carga", value: $weight, step: ex?.increment ?? 2.5, unit: ex?.weightUnit(in: session) ?? "kg", start: 10, clearable: false)
            GMDivider()
            GMDecimalField(title: "Reps", value: Binding(get: { reps }, set: { reps = $0.map { max(0, $0.rounded()) } }),
                           step: ex?.type == .time ? 5 : 1, unit: ex?.type == .time ? "s" : "reps", start: 10, clearable: false)
            GMToggle(title: "Feita", isOn: Binding(get: { s.done }, set: { s.done = $0 }))
            if others.count > 1 {
                GMButton("Aplicar carga em todas as \(others.count) séries", kind: .secondary) {
                    others.forEach { $0.weight = weight ?? 0 }
                    save(s, close)
                }
            }
            GMButton("Salvar") { save(s, close) }
        }
    }

    private func save(_ s: LoggedSet, _ close: () -> Void) {
        s.weight = max(weight ?? 0, 0)
        s.reps = Int(reps ?? Double(s.reps))
        try? context.save()
        PRBook.reload()
        close()
    }
}

func setText(_ s: LoggedSet) -> String {
    switch Exercise.byID(s.exerciseID)?.type ?? .weighted {
    case .time: return "\(s.reps) s" + (s.weight > 0 ? " · \(Progression.fmt(s.weight)) kg" : "")
    case .bodyweight where s.weight == 0: return "\(s.reps) reps"
    default: return "\(Progression.fmt(s.weight)) kg × \(s.reps)"
    }
}

struct TemplatesView: View {
    let startingOrder: Int
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GMModal("Modelos prontos") {
            ForEach(RoutineTemplate.all) { t in
                Button {
                    t.install(in: context, startingOrder: startingOrder)
                    dismiss()
                } label: {
                    GMCard {
                        Text(t.name).font(.headline)
                        Text(t.detail).font(.subheadline).foregroundStyle(Theme.dim)
                        ForEach(t.routines, id: \.name) { r in
                            Text("• \(r.name) (\(weekdaysText(r.weekdays)))").font(.caption).foregroundStyle(Theme.dim)
                        }
                    }
                }
                .buttonStyle(GMPress())
            }
        }
    }
}
