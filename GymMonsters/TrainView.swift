import SwiftData
import SwiftUI
import UserNotifications

struct TrainView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Routine.order) private var routines: [Routine]
    @Query(sort: \WorkoutSession.start, order: .reverse) private var sessions: [WorkoutSession]
    @State private var active: WorkoutSession?
    @State private var templates = false
    @State private var library = false

    private var finished: [WorkoutSession] { sessions.filter { $0.end != nil } }
    private var inProgress: WorkoutSession? { sessions.first { $0.end == nil } }
    private var today: Int { Calendar.current.component(.weekday, from: .now) }

    @State private var routineMenu: Routine?
    @State private var sessionMenu: WorkoutSession?
    @State private var editing: Routine?
    @State private var plates = false

    var body: some View {
        NavigationStack {
            GMScreen("Treino", avatar: true) {
                if let s = inProgress {
                    GMCard {
                        card(title: s.title, subtitle: "Em andamento desde \(s.start.formatted(date: .omitted, time: .shortened))",
                             action: "Continuar") { active = s }
                    }
                } else {
                    let todays = routines.filter { $0.weekdays.contains(today) }
                    GMSection(todays.isEmpty ? "Hoje" : "Hoje · \(Date.now.formatted(.dateTime.weekday(.wide)))") {
                        if todays.isEmpty {
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

                GMSection("Evolução") {
                    NavigationLink { ExerciseStatsList(sessions: finished) } label: {
                        GMRow(icon: "chart.line.uptrend.xyaxis", title: "Exercícios e recordes", chevron: true)
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
            .gmModal(isPresented: $templates) { TemplatesView(startingOrder: routines.count) }
            .gmModal(isPresented: $library) { ExercisePicker() }
            .gmSheet(isPresented: $plates) { _ in PlateCalculatorView(total: 60) }
            .gmModal(item: $active) { s in
                WorkoutView(session: s, history: finished.reversed().map(\.log))
            }
            .gmActions(isPresented: Binding(get: { routineMenu != nil }, set: { if !$0 { routineMenu = nil } }),
                       title: routineMenu?.name, actions: routineActions)
            .gmActions(isPresented: Binding(get: { sessionMenu != nil }, set: { if !$0 { sessionMenu = nil } }),
                       title: sessionMenu?.title, message: "O XP desse treino também sai do bro.", actions: [
                GMAction("Apagar treino", icon: "trash", destructive: true) { if let s = sessionMenu { deleteSession(s) } }
            ])
        }
    }

    private var routineActions: [GMAction] {
        guard let r = routineMenu else { return [] }
        var list: [GMAction] = []
        if inProgress == nil { list.append(GMAction("Começar agora", icon: "play.fill") { start(r) }) }
        list.append(GMAction("Editar", icon: "pencil") { editing = r })
        list.append(GMAction("Apagar rotina", icon: "trash", destructive: true) {
            context.delete(r)
            try? context.save()
        })
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

    private func start(_ routine: Routine?) {
        let history = finished.reversed().map(\.log)
        let session = WorkoutSession(title: routine?.name ?? "Treino livre", routineUUID: routine?.uuid)
        context.insert(session)
        for (i, item) in (routine?.sortedItems ?? []).enumerated() {
            let s = Progression.suggest(exerciseID: item.exerciseID, sets: item.sets, reps: item.reps, history: history)
            for k in 0..<item.sets {
                session.sets.append(LoggedSet(exerciseID: item.exerciseID, exerciseOrder: i, index: k,
                                              weight: s.weight, reps: s.reps, rest: item.rest))
            }
        }
        try? context.save()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        active = session
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
        let done = session.sets.filter(\.done)
        let volume = done.reduce(0) { $0 + $1.weight * Double($1.reps) }
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

    var body: some View {
        GMScreen(session.title, subtitle: session.start.formatted(date: .complete, time: .shortened), back: true) {
            ForEach(Array(session.exerciseIDs.enumerated()), id: \.offset) { _, id in
                GMSection(Exercise.name(id)) {
                    ForEach(session.orderedSets.filter { $0.exerciseID == id }) { s in
                        HStack {
                            Text("\(s.index + 1)").foregroundStyle(Theme.dim).frame(width: 24, alignment: .leading)
                            Text(setText(s))
                            Spacer()
                            Image(systemName: s.done ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundStyle(s.done ? Theme.accent : Theme.dim)
                        }
                    }
                }
            }
        }
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
