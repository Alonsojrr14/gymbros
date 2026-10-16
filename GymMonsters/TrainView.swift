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

    var body: some View {
        NavigationStack {
            List {
                if let s = inProgress {
                    Section {
                        Button { active = s } label: {
                            card(title: s.title, subtitle: "Em andamento desde \(s.start.formatted(date: .omitted, time: .shortened))",
                                 action: "Continuar", icon: "play.fill")
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    let todays = routines.filter { $0.weekdays.contains(today) }
                    Section(todays.isEmpty ? "Hoje" : "Hoje · \(Date.now.formatted(.dateTime.weekday(.wide)))") {
                        if todays.isEmpty {
                            Text(routines.isEmpty ? "Crie uma rotina ou use um modelo pronto." : "Nenhuma rotina para hoje. Descanso também evolui o monstro.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.dim)
                        }
                        ForEach(todays) { r in
                            Button { start(r) } label: {
                                card(title: r.name, subtitle: "\(r.items.count) exercícios · \(r.items.reduce(0) { $0 + $1.sets }) séries",
                                     action: "Começar", icon: "play.fill")
                            }
                            .buttonStyle(.plain)
                        }
                        Button { start(nil) } label: { Label("Treino livre", systemImage: "plus") }
                    }
                }

                Section("Minhas rotinas") {
                    ForEach(routines) { r in
                        NavigationLink { RoutineEditView(routine: r) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(r.name).font(.subheadline.weight(.semibold))
                                Text(weekdaysText(r.weekdays) + " · \(r.items.count) exercícios")
                                    .font(.caption)
                                    .foregroundStyle(Theme.dim)
                            }
                        }
                        .swipeActions(edge: .leading) {
                            if inProgress == nil {
                                Button("Começar") { start(r) }.tint(Theme.accent)
                            }
                        }
                    }
                    .onDelete { idx in
                        idx.map { routines[$0] }.forEach(context.delete)
                        try? context.save()
                    }
                    Button { newRoutine() } label: { Label("Nova rotina", systemImage: "plus") }
                    Button { templates = true } label: { Label("Usar modelo pronto", systemImage: "square.stack") }
                }

                Section {
                    NavigationLink { ExerciseStatsList(sessions: finished) } label: {
                        Label("Exercícios e recordes", systemImage: "chart.line.uptrend.xyaxis")
                    }
                    NavigationLink { MuscleMapView(sessions: finished) } label: {
                        Label("Mapa muscular", systemImage: "figure.stand")
                    }
                    Button { library = true } label: {
                        Label("Biblioteca de exercícios", systemImage: "books.vertical")
                    }
                }

                if !finished.isEmpty {
                    Section("Treinos recentes") {
                        ForEach(finished.prefix(10)) { s in
                            NavigationLink { SessionDetailView(session: s) } label: { SessionRow(session: s) }
                        }
                        .onDelete { idx in
                            idx.map { finished[$0] }.forEach(deleteSession)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Treino")
            .sheet(isPresented: $templates) { TemplatesView(startingOrder: routines.count) }
            .sheet(isPresented: $library) { ExercisePicker() }
            .fullScreenCover(item: $active) { s in
                WorkoutView(session: s, history: finished.reversed().map(\.log))
            }
        }
    }

    private func card(title: String, subtitle: String, action: String, icon: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(Theme.dim)
            }
            Spacer()
            Label(action, systemImage: icon)
                .font(.subheadline.bold())
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Theme.accent, in: .capsule)
                .foregroundStyle(.black)
        }
        .contentShape(Rectangle())
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
        List {
            ForEach(Array(session.exerciseIDs.enumerated()), id: \.offset) { _, id in
                Section(Exercise.name(id)) {
                    ForEach(session.orderedSets.filter { $0.exerciseID == id }) { s in
                        HStack {
                            Text("\(s.index + 1)").foregroundStyle(Theme.dim).frame(width: 24, alignment: .leading)
                            Text(setText(s))
                            Spacer()
                            Image(systemName: s.done ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundStyle(s.done ? Theme.accent : Theme.dim)
                        }
                        .listRowBackground(Theme.card)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
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
        NavigationStack {
            List(RoutineTemplate.all) { t in
                Button {
                    t.install(in: context, startingOrder: startingOrder)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(t.name).font(.headline)
                        Text(t.detail).font(.subheadline).foregroundStyle(Theme.dim)
                        ForEach(t.routines, id: \.name) { r in
                            Text("• \(r.name) (\(weekdaysText(r.weekdays)))").font(.caption).foregroundStyle(Theme.dim)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Modelos prontos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
        }
    }
}
