import SwiftData
import SwiftUI
import UserNotifications

struct WorkoutView: View {
    @Bindable var session: WorkoutSession
    /// Treinos concluídos, do mais antigo ao mais novo (sem este)
    let history: [SessionLog]

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var restEnd: Date?
    @State private var restTotal = 90
    @State private var restTask: Task<Void, Never>?
    @State private var picking = false
    @State private var finishing = false
    @State private var confirmDiscard = false
    @State private var info: Exercise?
    @State private var exerciseMenu: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(Array(session.exerciseIDs.enumerated()), id: \.element) { _, id in
                        exerciseCard(id)
                    }
                    GMButton("Adicionar exercício", icon: "plus", kind: .secondary) { picking = true }
                    GMButton("Descartar treino", icon: "trash", kind: .danger) { confirmDiscard = true }
                        .padding(.top, 12)
                }
                .padding(16)
                .padding(.bottom, restEnd == nil ? 20 : 110)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Theme.bg.ignoresSafeArea())
        .overlay(alignment: .bottom) { if let restEnd { restBar(restEnd) } }
        .gmModal(isPresented: $picking) { ExercisePicker(onPick: add) }
        .gmModal(item: $info) { ExerciseInfoView(exercise: $0) }
        .gmModal(isPresented: $finishing) {
            FinishWorkoutView(session: session, history: history) { dismiss() }
        }
        .gmActions(isPresented: $confirmDiscard, title: "Descartar este treino?", message: "Nada dele será salvo.", actions: [
            GMAction("Descartar", icon: "trash", destructive: true) {
                cancelRest()
                context.delete(session)
                try? context.save()
                dismiss()
            }
        ])
        .gmActions(isPresented: Binding(get: { exerciseMenu != nil }, set: { if !$0 { exerciseMenu = nil } }),
                   title: exerciseMenu.map(Exercise.name), actions: exerciseActions)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            try? context.save()
        }
    }

    /// Minimizar à esquerda (o treino continua salvo), título e cronômetro, concluir à direita
    private var header: some View {
        HStack(spacing: 12) {
            GMIconButton(icon: "chevron.down") { dismiss() }
            VStack(alignment: .leading, spacing: 1) {
                Text(session.title).font(.headline).lineLimit(1)
                Text(timerInterval: session.start...Date.distantFuture, countsDown: false)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.accent)
            }
            Spacer()
            GMButton("Concluir", icon: "checkmark", full: false, small: true) { finishing = true }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var exerciseActions: [GMAction] {
        guard let id = exerciseMenu else { return [] }
        var list: [GMAction] = []
        if let ex = Exercise.byID(id) {
            list.append(GMAction("Ver como fazer", icon: "info.circle") { info = ex })
        }
        list.append(GMAction("Remover exercício", icon: "trash", destructive: true) {
            session.orderedSets.filter { $0.exerciseID == id }.forEach(context.delete)
            try? context.save()
        })
        return list
    }

    // MARK: Exercício

    private func exerciseCard(_ id: String) -> some View {
        let ex = Exercise.byID(id)
        let sets = session.orderedSets.filter { $0.exerciseID == id }
        let suggestion = Progression.suggest(exerciseID: id, sets: sets.count, reps: sets.first?.targetReps ?? 10, history: history)
        let last = history.last { $0.sets.contains { $0.exerciseID == id } }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                if let ex {
                    Button { info = ex } label: { ExerciseThumb(exercise: ex, size: 52) }
                        .buttonStyle(GMPress())
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(ex?.name ?? id).font(.headline)
                    Text([ex?.group.name, ex?.equipment].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(Theme.dim)
                }
                Spacer()
                GMIconButton(icon: "ellipsis", size: 34) { exerciseMenu = id }
            }

            Label(suggestion.reason, systemImage: "arrow.up.right")
                .font(.caption)
                .foregroundStyle(Theme.accent.opacity(0.9))

            if let last {
                let prev = last.sets.filter { $0.exerciseID == id && $0.done }
                if !prev.isEmpty {
                    Text("Última vez: " + prev.map { s in
                        ex?.type == .weighted || s.weight > 0 ? "\(Progression.fmt(s.weight))×\(s.reps)" : "\(s.reps)"
                    }.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(Theme.dim)
                }
            }

            ForEach(sets) { s in
                SetRow(set: s, type: ex?.type ?? .weighted, increment: ex?.increment ?? 2.5) { done in
                    if done { startRest(s.rest) }
                }
            }

            GMButton("Série", icon: "plus", kind: .secondary, full: false, small: true) {
                let base = sets.last
                let new = LoggedSet(exerciseID: id, exerciseOrder: base?.exerciseOrder ?? 0, index: sets.count,
                                    weight: base?.weight ?? 0, reps: base?.targetReps ?? 10, rest: base?.rest ?? 90)
                session.sets.append(new)
            }
        }
        .padding(16)
        .background(Theme.card, in: .rect(cornerRadius: 20))
    }

    private func add(_ ex: Exercise) {
        let order = (session.sets.map(\.exerciseOrder).max() ?? -1) + 1
        let reps = ex.type == .time ? 30 : 10
        let s = Progression.suggest(exerciseID: ex.id, sets: 3, reps: reps, history: history)
        for k in 0..<3 {
            session.sets.append(LoggedSet(exerciseID: ex.id, exerciseOrder: order, index: k, weight: s.weight, reps: s.reps, rest: 90))
        }
    }

    // MARK: Descanso

    private func restBar(_ end: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
            let left = max(end.timeIntervalSince(ctx.date), 0)
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(.white.opacity(0.12), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: left / Double(max(restTotal, 1)))
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Descanso").font(.caption).foregroundStyle(Theme.dim)
                    Text(String(format: "%d:%02d", Int(left.rounded(.up)) / 60, Int(left.rounded(.up)) % 60))
                        .font(.title2.bold().monospacedDigit())
                }
                Spacer()
                GMButton("+15 s", kind: .secondary, full: false, small: true) { startRest(Int(left.rounded(.up)) + 15, keepTotal: true) }
                GMButton("Pular", full: false, small: true) { cancelRest() }
            }
            .padding(14)
            .background(Theme.card, in: .rect(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.stroke))
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func startRest(_ seconds: Int, keepTotal: Bool = false) {
        guard seconds > 0 else { return }
        cancelRest()
        let end = Date.now.addingTimeInterval(TimeInterval(seconds))
        if !keepTotal { restTotal = seconds } else { restTotal = max(restTotal, seconds) }
        withAnimation { restEnd = end }

        // Aviso mesmo com o app em segundo plano
        let content = UNMutableNotificationContent()
        content.title = "Descanso acabou"
        content.body = "Bora para a próxima série 💪"
        content.sound = .default
        let req = UNNotificationRequest(identifier: "rest", content: content,
                                        trigger: UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false))
        UNUserNotificationCenter.current().add(req)

        restTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            withAnimation { restEnd = nil }
        }
    }

    private func cancelRest() {
        restTask?.cancel()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["rest"])
        withAnimation { restEnd = nil }
    }
}

private struct SetRow: View {
    @Bindable var set: LoggedSet
    let type: ExerciseType
    let increment: Double
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("\(set.index + 1)")
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(Theme.dim)
                .frame(width: 18)

            // Peso do corpo e isometria aceitam carga extra (cinto, colete, halteres)
            field(value: Binding(get: { set.weight }, set: { set.weight = max($0, 0) }),
                  step: type == .weighted ? increment : 2.5, unit: type == .weighted ? "kg" : "+kg", decimals: true)
            field(value: Binding(get: { Double(set.reps) }, set: { set.reps = max(Int($0), 0) }),
                  step: type == .time ? 5 : 1, unit: type == .time ? "s" : "reps", decimals: false)

            Spacer(minLength: 0)

            Button {
                set.done.toggle()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onToggle(set.done)
            } label: {
                Image(systemName: set.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 30))
                    .foregroundStyle(set.done ? Theme.accent : Theme.dim)
            }
            .buttonStyle(GMPress())
        }
        .padding(.vertical, 2)
        .opacity(set.done ? 0.75 : 1)
    }

    private func field(value: Binding<Double>, step: Double, unit: String, decimals: Bool) -> some View {
        HStack(spacing: 2) {
            Button { value.wrappedValue -= step } label: { Image(systemName: "minus").frame(width: 28, height: 34).contentShape(Rectangle()) }
            VStack(spacing: -2) {
                TextField("0", value: value, format: .number.precision(.fractionLength(0...(decimals ? 1 : 0))))
                    .keyboardType(decimals ? .decimalPad : .numberPad)
                    .multilineTextAlignment(.center)
                    .font(.body.bold().monospacedDigit())
                    .frame(width: 52)
                Text(unit).font(.caption2).foregroundStyle(Theme.dim)
            }
            Button { value.wrappedValue += step } label: { Image(systemName: "plus").frame(width: 28, height: 34).contentShape(Rectangle()) }
        }
        .buttonStyle(GMPress())
        .padding(.horizontal, 4)
        .background(.white.opacity(0.06), in: .rect(cornerRadius: 10))
    }
}

// MARK: - Concluir

struct FinishWorkoutView: View {
    @Bindable var session: WorkoutSession
    let history: [SessionLog]
    let onDone: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var activities: [Activity]
    @Query private var monsters: [Monster]
    @Query private var checkIns: [LeagueCheckIn]
    @Query private var allLeagues: [League]
    @State private var effort = 7
    @State private var leagues: Set<UUID> = []
    @State private var photo: Data?

    private var minutes: Int { max(Int(Date.now.timeIntervalSince(session.start) / 60), 1) }

    var body: some View {
        let done = session.sets.filter(\.done)
        let volume = done.reduce(0) { $0 + $1.weight * Double($1.reps) }
        let records = Progression.records(in: session.log, history: history)
        let new = ActivityRecord(id: UUID(), kind: .musculacao, date: session.start, minutes: minutes, effort: effort)
        let roster = Roster(monsters: monsters, activities: activities, checkIns: checkIns, leagues: allLeagues)
        let xp = Game.snapshot((roster.mainID.flatMap { roster.records[$0] } ?? []) + [new]).xpByActivity[new.id] ?? 0

        GMModal("Concluir treino", confirm: "Salvar", confirmEnabled: !done.isEmpty, onConfirm: save) {
            GMCard {
                HStack {
                    stat(durationText(minutes), "duração")
                    stat("\(done.count)/\(session.sets.count)", "séries")
                    stat(volume > 0 ? "\(Progression.fmt(volume.rounded())) kg" : "–", "volume")
                }
            }
            if !done.isEmpty {
                GMSection("Músculos trabalhados") {
                    BodyPair(intensities: normalized(muscleLoad(session.log.sets))).frame(height: 220)
                }
            }
            if !records.isEmpty {
                GMSection("Recordes 🏆") {
                    ForEach(records, id: \.self) { Text($0).font(.subheadline) }
                }
            }
            GMSection { GMEffortPicker(value: $effort) }
            LeaguePostSection(selected: $leagues, photo: $photo)
            GMSection(footer: done.isEmpty ? "Marque ao menos uma série feita para salvar." : nil) {
                HStack {
                    Text("+\(xp) XP").font(.title2.weight(.heavy).monospacedDigit()).foregroundStyle(Theme.accent)
                    Spacer()
                    Label("Força", systemImage: Attribute.forca.symbol).foregroundStyle(Attribute.forca.color)
                }
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.monospacedDigit())
            Text(label).font(.caption).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity)
    }

    private var records: [String] { Progression.records(in: session.log, history: history) }

    private func save() {
        let activity = Activity(kind: .musculacao, date: session.start, minutes: minutes, effort: effort, note: session.title)
        context.insert(activity)
        let summary = records.isEmpty ? "" : "🏆 " + records.joined(separator: " · ")
        postCheckIns(activity: activity, leagues: leagues, title: session.title, note: summary, photo: photo, context: context)
        session.end = .now
        session.effort = effort
        session.activityUUID = activity.uuid
        try? context.save()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["rest"])
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
        onDone()
    }
}
