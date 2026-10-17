import SwiftData
import SwiftUI
import UserNotifications

struct WorkoutView: View {
    @Bindable var session: WorkoutSession
    /// Treinos concluídos, do mais antigo ao mais novo (sem este)
    let history: [SessionLog]

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var picking = false
    @State private var finishing = false
    @State private var confirmDiscard = false
    @State private var info: Exercise?
    @State private var exerciseMenu: String?
    @State private var platesFor: Double?
    @State private var noteFor: String?
    @State private var noteText = ""
    /// Exercícios recolhidos (a pessoa recolheu ou terminou todas as séries)
    @State private var collapsed: Set<String> = []
    /// Roleta do descanso: agora (nil) ou padrão de um exercício
    @State private var restPicker: RestTarget?
    @State private var restDraft = 90
    @State private var historyFor: String?
    @State private var choosingPlace = false
    @Query(filter: #Predicate<WorkoutSession> { $0.end != nil }, sort: \WorkoutSession.start, order: .reverse) private var doneSessions: [WorkoutSession]
    @State private var headphones = HeadphoneControl.shared.isOn
    @State private var headphoneInfo = false
    @AppStorage("headphoneInfoSeen") private var headphoneInfoSeen = false
    @State private var scrollTarget: String?
    @Query private var notes: [ExerciseNote]

    var body: some View {
        VStack(spacing: 0) {
            header
            placeChip
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        if session.exerciseIDs.isEmpty {
                            GMEmptyState(icon: "dumbbell", title: "Treino vazio", message: "Toque em + Exercício, aqui embaixo, para começar.")
                        }
                        ForEach(Array(session.exerciseIDs.enumerated()), id: \.element) { _, id in
                            exerciseCard(id).id(id)
                        }
                    }
                    .padding(16)
                    .padding(.bottom, resting ? 180 : 90)
                }
                .scrollDismissesKeyboard(.immediately)
                .onChange(of: scrollTarget) { _, target in
                    guard let target else { return }
                    withAnimation(.snappy) { proxy.scrollTo(target, anchor: .top) }
                    scrollTarget = nil
                }
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        // Ações sempre à mão, sem rolar até o fim; ficam atrás do teclado enquanto você digita
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                if resting, let end = session.restEnd { restBar(end) }
                actionBar
            }
            .ignoresSafeArea(.keyboard)
        }
        .gmKeyboardDone()
        .gmModal(isPresented: $picking) { ExercisePicker(onPick: add) }
        .gmModal(item: $info) { ExerciseInfoView(exercise: $0) }
        .gmModal(item: Binding(get: { historyFor.map { IDBox(id: $0) } }, set: { historyFor = $0?.id })) { box in
            NavigationStack { ExerciseDetailView(exerciseID: box.id, sessions: doneSessions) }
        }
        .gmModal(isPresented: $finishing) {
            FinishWorkoutView(session: session, history: history) { dismiss() }
        }
        .gmActions(isPresented: $headphoneInfo, title: "Controlar pelo fone?",
                   message: "O play/pause do fone vai marcar a série (ou pular o descanso) e o app fala no fone o que aconteceu, mesmo com o celular bloqueado. Para isso o GymBros assume o áudio: a música de outro app pausa enquanto o modo estiver ligado.",
                   actions: [GMAction("Ligar modo fone", icon: "headphones") {
                       headphoneInfoSeen = true
                       toggleHeadphones()
                   }])
        .gmActions(isPresented: $confirmDiscard, title: "Descartar este treino?", message: "Nada dele será salvo.", actions: [
            GMAction("Descartar", icon: "trash", destructive: true) {
                HeadphoneControl.shared.stop()
                cancelRest()
                context.delete(session)
                try? context.save()
                Task { await LiveWorkout.endAll() }
                dismiss()
            }
        ])
        .gmActions(isPresented: Binding(get: { exerciseMenu != nil }, set: { if !$0 { exerciseMenu = nil } }),
                   title: exerciseMenu.map(Exercise.name), actions: exerciseActions)
        .gmSheet(isPresented: Binding(get: { platesFor != nil }, set: { if !$0 { platesFor = nil } })) { _ in
            PlateCalculatorView(total: platesFor ?? 60)
        }
        .gmPrompt(isPresented: Binding(get: { noteFor != nil }, set: { if !$0 { noteFor = nil } }),
                  title: "Nota do exercício", message: "Ajuste da máquina, pegada, o que lembrar da próxima vez.",
                  placeholder: "Ex.: banco na posição 4", text: $noteText) {
            if let id = noteFor { saveNote(id, noteText) }
        }
        // Live Activity acompanha qualquer mudança do treino
        .task(id: LiveWorkout.state(for: session)) {
            await LiveWorkout.refresh(session)
            HeadphoneControl.shared.refresh()
        }
        // Descanso marcado pelo Live Activity: acompanha o fim aqui também
        .task(id: session.restEnd) { await watchRest() }
        .gmSheet(isPresented: Binding(get: { restPicker != nil }, set: { if !$0 { restPicker = nil } })) { close in
            VStack(spacing: 16) {
                Text(restPicker?.exerciseID.map { "Descanso · \(Exercise.name($0))" } ?? "Descanso agora").font(.headline)
                GMDurationWheel(seconds: $restDraft)
                if restPicker?.exerciseID != nil {
                    Text("Vale para as próximas séries deste exercício neste treino.").font(.caption).foregroundStyle(Theme.dim)
                }
                GMButton("Confirmar") {
                    if let id = restPicker?.exerciseID {
                        // Próximas séries do exercício passam a usar esse descanso
                        session.orderedSets.filter { $0.exerciseID == id && !$0.done }.forEach { $0.rest = restDraft }
                    } else if restDraft > 0 {
                        startRest(restDraft)
                    } else {
                        cancelRest()
                    }
                    close()
                }
            }
        }
        .gmSheet(isPresented: $choosingPlace) { close in
            GymChooserView { g in
                session.gymUUID = g?.uuid
                session.placeAsked = true
                try? context.save()
                close()
            }
        }
        .task { await detectPlace() }
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
            // Modo fone: play/pause do fone marca a série
            GMIconButton(icon: headphones ? "airpods.gen3" : "headphones", tint: headphones ? Theme.accent : .white) {
                if headphones { toggleHeadphones() } else if headphoneInfoSeen { toggleHeadphones() } else { headphoneInfo = true }
            }
            GMButton("Concluir", icon: "checkmark", full: false, small: true) { finishing = true }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// Barra fixa: adicionar exercício, recolher/expandir todos e descartar
    private var actionBar: some View {
        let allCollapsed = !session.exerciseIDs.isEmpty && session.exerciseIDs.allSatisfy(collapsed.contains)
        return HStack(spacing: 10) {
            GMButton("Exercício", icon: "plus", kind: .secondary) { picking = true }
            GMIconButton(icon: allCollapsed ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left", size: 48) {
                withAnimation(.snappy) { collapsed = allCollapsed ? [] : Set(session.exerciseIDs) }
            }
            GMIconButton(icon: "trash", size: 48, tint: Theme.danger) { confirmDiscard = true }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(LinearGradient(colors: [Theme.bg.opacity(0), Theme.bg, Theme.bg], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }

    private var currentID: String? { LiveWorkout.currentExercise(session) }

    /// Onde está treinando: toque para trocar
    private var placeChip: some View {
        let g = GymLocation.shared.gym(session.gymUUID)
        return Button { choosingPlace = true } label: {
            Label(g?.name ?? (session.placeAsked ? "Sem local" : "Onde você está?"), systemImage: "mappin.and.ellipse")
                .font(.caption.bold())
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(g != nil ? Theme.accent.opacity(0.18) : Theme.raised, in: .capsule)
                .foregroundStyle(g != nil ? Theme.accent : .white)
        }
        .buttonStyle(GMPress())
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    /// Lugar conhecido é escolhido sozinho; desconhecido, pergunta (uma vez por treino)
    private func detectPlace() async {
        guard !session.placeAsked else { return }
        switch await PlaceDetector.detect() {
        case .known(let g):
            session.gymUUID = g.uuid
            session.placeAsked = true
            try? context.save()
        case .ask:
            choosingPlace = true
        }
    }

    private func toggleHeadphones() {
        if headphones { HeadphoneControl.shared.stop() } else { HeadphoneControl.shared.start() }
        headphones = HeadphoneControl.shared.isOn
    }
    private var resting: Bool { session.restEnd.map { $0 > .now } ?? false }

    /// Terminou todas as séries de um exercício: recolhe e rola até o próximo que falta
    private func setToggled(_ id: String) {
        let sets = session.orderedSets.filter { $0.exerciseID == id }
        guard !sets.isEmpty, sets.allSatisfy(\.done) else { return }
        withAnimation(.snappy) { _ = collapsed.insert(id) }
        let ids = session.exerciseIDs
        if let i = ids.firstIndex(of: id) {
            let next = (ids[(i + 1)...] + ids[..<i]).first { e in
                !session.orderedSets.filter { $0.exerciseID == e }.allSatisfy(\.done)
            }
            if let next {
                collapsed.remove(next)
                session.currentExerciseID = next
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { scrollTarget = next }
            }
        }
    }

    private func saveNote(_ id: String, _ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let n = notes.first(where: { $0.exerciseID == id }) {
            if clean.isEmpty { context.delete(n) } else { n.text = clean; n.updated = .now }
        } else if !clean.isEmpty {
            context.insert(ExerciseNote(exerciseID: id, text: clean))
        }
        try? context.save()
    }

    private var exerciseActions: [GMAction] {
        guard let id = exerciseMenu else { return [] }
        var list: [GMAction] = []
        if let ex = Exercise.byID(id) {
            list.append(GMAction("Ver como fazer", icon: "info.circle") { info = ex })
            if ex.type == .weighted {
                let w = session.orderedSets.last { $0.exerciseID == id }?.weight ?? 60
                let bar = UserDefaults.standard.object(forKey: "barWeight") as? Double ?? 20
                list.append(GMAction("Calcular anilhas", icon: "circle.grid.2x1") { platesFor = ex.weightIncludesBar ? w : w + bar })
            }
        }
        let rest = session.orderedSets.first { $0.exerciseID == id && !$0.done }?.rest
            ?? session.orderedSets.last { $0.exerciseID == id }?.rest ?? 90
        list.append(GMAction("Tempo de descanso (\(clock(rest)))", icon: "timer") {
            restDraft = rest
            restPicker = RestTarget(exerciseID: id)
        })
        list.append(GMAction("Histórico de cargas", icon: "chart.line.uptrend.xyaxis") { historyFor = id })
        let current = notes.first { $0.exerciseID == id }?.text ?? ""
        list.append(GMAction(current.isEmpty ? "Adicionar nota" : "Editar nota", icon: "note.text") {
            noteText = current
            noteFor = id
        })
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
        let done = sets.filter(\.done).count
        let complete = !sets.isEmpty && done == sets.count
        let isCollapsed = collapsed.contains(id)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                if let ex {
                    Button { info = ex } label: { ExerciseThumb(exercise: ex, size: isCollapsed ? 40 : 52) }
                        .buttonStyle(GMPress())
                }
                // Tocar no nome recolhe ou expande o card
                Button {
                    withAnimation(.snappy) { if isCollapsed { collapsed.remove(id) } else { collapsed.insert(id) } }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ex?.name ?? id).font(.headline).lineLimit(1)
                            HStack(spacing: 6) {
                                if complete { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent) }
                                Text("\(done)/\(sets.count) séries" + (isCollapsed ? "" : " · " + [ex?.group.name, ex?.equipment].compactMap { $0 }.joined(separator: " · ")))
                                    .lineLimit(1)
                            }
                            .font(.caption)
                            .foregroundStyle(complete ? Theme.accent : Theme.dim)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                            .font(.caption.bold())
                            .foregroundStyle(Theme.dim)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(GMPress())
                // Marca o exercício que está fazendo agora (aparece no Live Activity e na Dynamic Island)
                let isCurrent = currentID == id
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    session.currentExerciseID = id
                    withAnimation(.snappy) { _ = collapsed.remove(id) }
                } label: {
                    Image(systemName: isCurrent ? "play.fill" : "play")
                        .font(.subheadline.bold())
                        .frame(width: 34, height: 34)
                        .background(isCurrent ? Theme.accent : Theme.raised, in: .circle)
                        .foregroundStyle(isCurrent ? .black : .white)
                }
                .buttonStyle(GMPress())
                GMIconButton(icon: "ellipsis", size: 34) { exerciseMenu = id }
            }
            if currentID == id && !isCollapsed {
                Label("Fazendo agora", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.accent)
            }
            if !isCollapsed {

            if let note = notes.first(where: { $0.exerciseID == id }), !note.text.isEmpty {
                Button { noteText = note.text; noteFor = id } label: {
                    Label(note.text, systemImage: "note.text")
                        .font(.caption)
                        .foregroundStyle(.yellow.opacity(0.9))
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(GMPress())
            }
            let lastMax = last?.sets.filter { $0.exerciseID == id && $0.done }.map(\.weight).max()
            if let lastMax, suggestion.weight > lastMax {
                // Completou tudo da última vez: subir a carga
                Label("Subir para \(Progression.fmt(suggestion.weight)) kg (+\(Progression.fmt(suggestion.weight - lastMax)) kg)", systemImage: "arrow.up.circle.fill")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Theme.accent.opacity(0.18), in: .capsule)
                    .foregroundStyle(Theme.accent)
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
                SetRow(set: s, type: ex?.type ?? .weighted, increment: ex?.increment ?? 2.5, unit: ex?.weightUnit ?? "kg") { done in
                    if done {
                        startRest(s.rest)
                        setToggled(id)
                    }
                }
            }

            GMButton("Série", icon: "plus", kind: .secondary, full: false, small: true) {
                let base = sets.last
                let new = LoggedSet(exerciseID: id, exerciseOrder: base?.exerciseOrder ?? 0, index: sets.count,
                                    weight: base?.weight ?? 0, reps: base?.targetReps ?? 10, rest: base?.rest ?? 90)
                session.sets.append(new)
            }
            }
        }
        .padding(isCollapsed ? 12 : 16)
        .background(Theme.card, in: .rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(currentID == id ? Theme.accent : complete ? Theme.accent.opacity(0.35) : .clear,
                                                           lineWidth: currentID == id ? 2 : 1))
    }

    private func add(_ ex: Exercise) {
        let order = (session.sets.map(\.exerciseOrder).max() ?? -1) + 1
        let reps = ex.type == .time ? 30 : 10
        let s = Progression.suggest(exerciseID: ex.id, sets: 3, reps: reps, history: history)
        for k in 0..<3 {
            session.sets.append(LoggedSet(exerciseID: ex.id, exerciseOrder: order, index: k, weight: s.weight, reps: s.reps, rest: 90))
        }
        collapsed.remove(ex.id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { scrollTarget = ex.id }
    }

    // MARK: Descanso

    private func restBar(_ end: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
            let left = max(end.timeIntervalSince(ctx.date), 0)
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(.white.opacity(0.12), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: left / Double(max(session.restTotal, 1)))
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 36, height: 36)
                // Tocar no tempo abre a roleta para escolher o descanso exato
                Button {
                    restDraft = max(Int(left.rounded(.up)) / 5 * 5, 5)
                    restPicker = RestTarget(exerciseID: nil)
                } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Descanso").font(.caption).foregroundStyle(Theme.dim)
                        Text(String(format: "%d:%02d", Int(left.rounded(.up)) / 60, Int(left.rounded(.up)) % 60))
                            .font(.title2.bold().monospacedDigit())
                            .underline(color: Theme.dim)
                    }
                    .foregroundStyle(.white)
                }
                .buttonStyle(GMPress())
                Spacer()
                GMIconButton(icon: "minus", size: 38) {
                    let l = Int(left.rounded(.up)) - 15
                    if l <= 0 { cancelRest() } else { startRest(l, keepTotal: true) }
                }
                GMIconButton(icon: "plus", size: 38) { startRest(Int(left.rounded(.up)) + 15, keepTotal: true) }
                GMButton("Pular", full: false, small: true) { cancelRest() }
            }
            .padding(14)
            .background(Theme.card, in: .rect(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.stroke))
            .padding(.horizontal, 12)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func startRest(_ seconds: Int, keepTotal: Bool = false) {
        withAnimation { LiveWorkout.startRest(session, seconds: seconds, keepTotal: keepTotal) }
    }

    private func cancelRest() {
        withAnimation { LiveWorkout.cancelRest(session) }
    }

    /// Vibra e fecha o card quando o descanso acaba (seja qual for quem começou)
    private func watchRest() async {
        guard let end = session.restEnd, end > .now else { return }
        try? await Task.sleep(for: .seconds(end.timeIntervalSinceNow))
        guard !Task.isCancelled, session.restEnd == end else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        withAnimation { session.restEnd = nil }
    }
}

private struct SetRow: View {
    @Bindable var set: LoggedSet
    let type: ExerciseType
    let increment: Double
    var unit = "kg"
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("\(set.index + 1)")
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(Theme.dim)
                .frame(width: 18)

            // Peso do corpo e isometria aceitam carga extra (cinto, colete, halteres)
            field(value: Binding(get: { set.weight }, set: { set.weight = max($0, 0) }),
                  step: type == .weighted ? increment : 2.5, unit: type == .weighted ? unit : "+kg", decimals: true)
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
            let ups = nextUps
            if !ups.isEmpty {
                GMSection("No próximo treino, suba a carga", footer: "Você completou todas as séries desses exercícios. A sugestão já vem preenchida no próximo treino.") {
                    ForEach(ups, id: \.0) { name, text in
                        HStack {
                            Text(name).font(.subheadline.weight(.semibold))
                            Spacer()
                            Label(text, systemImage: "arrow.up.circle.fill").font(.subheadline.bold()).foregroundStyle(Theme.accent)
                        }
                    }
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

    /// Exercícios em que a regra de progressão manda subir carga (ou reps/tempo) no próximo treino
    private var nextUps: [(String, String)] {
        let log = session.log
        return session.exerciseIDs.compactMap { id in
            let sets = log.sets.filter { $0.exerciseID == id }
            guard let w = sets.filter(\.done).map(\.weight).max(), let reps = sets.first?.target else { return nil }
            let s = Progression.suggest(exerciseID: id, sets: sets.count, reps: reps, history: history + [log])
            if s.weight > w { return (Exercise.name(id), "\(Progression.fmt(s.weight)) kg (+\(Progression.fmt(s.weight - w)))") }
            if s.reps > reps && s.weight == w {
                return (Exercise.name(id), Exercise.byID(id)?.type == .time ? "\(s.reps) s" : "\(s.reps) reps")
            }
            return nil
        }
    }

    private func save() {
        let activity = Activity(kind: .musculacao, date: session.start, minutes: minutes, effort: effort, note: session.title)
        activity.gymUUID = session.gymUUID
        context.insert(activity)
        let summary = records.isEmpty ? "" : "🏆 " + records.joined(separator: " · ")
        postCheckIns(activity: activity, leagues: leagues, title: session.title, note: summary, photo: photo, context: context)
        session.end = .now
        session.effort = effort
        session.activityUUID = activity.uuid
        try? context.save()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["rest"])
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task { await LiveWorkout.endAll() }
        HeadphoneControl.shared.stop()
        dismiss()
        onDone()
    }
}

struct RestTarget: Identifiable {
    /// nil = descanso em andamento
    let exerciseID: String?
    var id: String { exerciseID ?? "agora" }
}

struct IDBox: Identifiable { let id: String }
