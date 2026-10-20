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
    /// Exercício cujo objetivo está sendo escolhido
    @State private var goalFor: String?
    /// Exercício sendo trocado (aparelho ocupado)
    @State private var swapping: IDBox?
    /// Exercício a remover, esperando confirmação
    @State private var confirmRemove: String?
    /// Série com o menu aberto (toque no número)
    @State private var setMenu: LoggedSet?
    @Query(filter: #Predicate<WorkoutSession> { $0.end != nil }, sort: \WorkoutSession.start, order: .reverse) private var doneSessions: [WorkoutSession]
    @State private var headphones = HeadphoneControl.shared.isOn
    @Query(sort: \Monster.createdAt) private var monsters: [Monster]
    @AppStorage(MainMonster.key) private var mainRaw: String?
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
                        ForEach(Array(session.exerciseIDs.enumerated()), id: \.element) { i, id in
                            exerciseCard(id).id(id)
                            if session.linkedNext(id) && i < session.exerciseIDs.count - 1 {
                                // Elo do superset
                                Image(systemName: "link")
                                    .font(.caption.bold())
                                    .frame(width: 28, height: 28)
                                    .background(Theme.info.opacity(0.2), in: .circle)
                                    .foregroundStyle(Theme.info)
                                    .padding(.vertical, -10)
                            }
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
        .gmModal(item: $swapping) { box in
            SwapExerciseView(current: box.id, exclude: Set(session.exerciseIDs), history: history) { swap(box.id, to: $0) }
        }
        .gmModal(item: $info) { ExerciseInfoView(exercise: $0) }
        .gmModal(item: Binding(get: { historyFor.map { IDBox(id: $0) } }, set: { historyFor = $0?.id })) { box in
            NavigationStack { ExerciseDetailView(exerciseID: box.id, sessions: doneSessions) }
        }
        .gmModal(isPresented: $finishing) {
            FinishWorkoutView(session: session, history: history) { dismiss() }
        }
        .gmActions(isPresented: $headphoneInfo, title: "Avisos no fone?",
                   message: "Com o app aberto, o GymBros fala no fone o aviso de 10 segundos e o fim do descanso, abaixando a música só enquanto fala. Com a tela bloqueada, marque a série pela Live Activity ou pelos controles.",
                   actions: [GMAction("Ligar modo fone", icon: "headphones") {
                       headphoneInfoSeen = true
                       toggleHeadphones()
                   }])
        .gmActions(isPresented: $confirmDiscard, title: "Descartar este treino?", message: "Nada dele será salvo.", actions: [
            GMAction("Descartar", icon: "trash", destructive: true) {
                HeadphoneControl.shared.stop()
                cancelRest()
                LiveShare.end(session.uuid.uuidString)
                context.delete(session)
                try? context.save()
                Task { await LiveWorkout.endAll() }
                dismiss()
            }
        ])
        .gmActions(isPresented: Binding(get: { exerciseMenu != nil }, set: { if !$0 { exerciseMenu = nil } }),
                   title: exerciseMenu.map(Exercise.name), actions: exerciseActions)
        .gmActions(isPresented: Binding(get: { setMenu != nil }, set: { if !$0 { setMenu = nil } }),
                   title: setMenu.map { "\(Exercise.name($0.exerciseID)) · \($0.warmup ? "aquecimento" : "série")" }, actions: setActions)
        .gmActions(isPresented: Binding(get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } }),
                   title: confirmRemove.map { "Remover \(Exercise.name($0))?" }, message: "As séries dele neste treino, feitas ou não, saem do treino.",
                   actions: confirmRemove.map { id in [GMAction("Remover", icon: "trash", destructive: true) { removeExercise(id) }] } ?? [])
        .gmActions(isPresented: Binding(get: { goalFor != nil }, set: { if !$0 { goalFor = nil } }),
                   title: "Objetivo", message: "Define a faixa de reps e como a carga sobe: +1 rep por treino até o topo da faixa, depois +carga e volta ao início.",
                   actions: goalFor.map { id in
                       TrainingGoal.allCases.map { g in GMAction(g.label, icon: "target") { setGoal(g, id) } }
                       + [GMAction("Sem objetivo (reps fixas)", icon: "xmark") { setGoal(nil, id) }]
                   } ?? [])
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
            GMIconButton(icon: "chevron.down", label: "Minimizar treino") { dismiss() }
            // Bro que treina com você (o principal recebe o XP; as ligas você escolhe ao concluir)
            let main = monsters.first { $0.uuid.uuidString == mainRaw } ?? monsters.first { $0.isStarter } ?? monsters.first
            if let main, let form = MonsterForm.byID(main.lastFormID) {
                MonsterSprite(form: form).frame(width: 30, height: 30)
                    .frame(width: 38, height: 38)
                    .background(Theme.accent.opacity(0.12), in: .circle)
                    .overlay(Circle().stroke(Theme.accent.opacity(0.4), lineWidth: 1))
                    .accessibilityLabel("Treinando com \(main.displayName(form))")
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(session.title).font(.headline).lineLimit(1)
                HStack(spacing: 4) {
                    Text(timerInterval: session.start...Date.distantFuture, countsDown: false)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.accent)
                    if let main, let form = MonsterForm.byID(main.lastFormID) {
                        Text("· com \(main.displayName(form))").font(.caption).foregroundStyle(Theme.dim).lineLimit(1)
                    }
                }
            }
            Spacer()
            // Modo fone: avisos do descanso falados no fone
            GMIconButton(icon: headphones ? "airpods.gen3" : "headphones", tint: headphones ? Theme.accent : .white, label: headphones ? "Desligar modo fone" : "Ligar modo fone") {
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
            GMIconButton(icon: allCollapsed ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left", size: 48,
                         label: allCollapsed ? "Expandir exercícios" : "Recolher exercícios") {
                withAnimation(.snappy) { collapsed = allCollapsed ? [] : Set(session.exerciseIDs) }
            }
            GMIconButton(icon: "trash", size: 48, tint: Theme.danger, label: "Descartar treino") { confirmDiscard = true }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(LinearGradient(colors: [Theme.bg.opacity(0), Theme.bg, Theme.bg], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }

    private var currentID: String? { LiveWorkout.currentExercise(session) }

    /// Onde está treinando (toque para trocar) e se os amigos veem o treino ao vivo
    private var placeChip: some View {
        let g = GymLocation.shared.gym(session.gymUUID)
        return HStack(spacing: 8) {
            Button { choosingPlace = true } label: {
                Label(g?.name ?? (session.placeAsked ? "Sem local" : "Onde você está?"), systemImage: "mappin.and.ellipse")
                    .font(.caption.bold()).lineLimit(1)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(g != nil ? Theme.accent.opacity(0.18) : Theme.raised, in: .capsule)
                    .foregroundStyle(g != nil ? Theme.accent : .white)
            }
            .buttonStyle(GMPress())
            LiveShareChip(workoutID: session.uuid.uuidString)
        }
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
        // Superset: mostra o próximo do bloco
        if let cur = session.currentExerciseID, cur != id, session.group(of: id).contains(cur), !sets.allSatisfy(\.done) {
            collapsed.remove(cur)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { scrollTarget = cur }
            return
        }
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

    /// Troca as séries que faltam de um exercício por outro do mesmo músculo, com a carga sugerida para ele
    private func swap(_ old: String, to new: Exercise) {
        let work = session.orderedSets.filter { $0.exerciseID == old && !$0.done && !$0.warmup }
        var s = Progression.suggest(exerciseID: new.id, sets: work.count, reps: work.first?.targetReps ?? 10, history: history)
        // Treino de deload: o novo também vai a 70 % (as séries já são as reduzidas do antigo)
        if session.isDeload { s = Deload.apply(s, sets: work.count, exerciseID: new.id).suggestion }
        session.swapPending(old, to: new.id, suggestion: s)
        collapsed.remove(new.id)
        try? context.save()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { scrollTarget = new.id }
    }

    /// Muda o objetivo e já ajusta as séries que faltam neste treino
    private func setGoal(_ g: TrainingGoal?, _ id: String) {
        TrainingGoal.set(g, for: id)
        let pending = session.orderedSets.filter { $0.exerciseID == id && !$0.warmup && !$0.done }
        let s = Progression.suggest(exerciseID: id, sets: pending.count, reps: pending.first?.targetReps ?? 10, history: history)
        for set in pending {
            set.reps = s.reps
            set.targetReps = s.reps
            if let g { set.rest = g.rest }
            if s.weight > 0 && set.weight == 0 { set.weight = s.weight }
        }
        try? context.save()
    }

    /// Três séries leves antes da carga de trabalho
    private func addWarmup(_ ex: Exercise) {
        let sets = session.orderedSets.filter { $0.exerciseID == ex.id }
        guard let first = sets.first, first.weight > 0 else { return }
        let warm = Progression.warmup(work: first.weight, increment: ex.increment, minimum: ex.usesBar && ex.weightIncludesBar(in: session) ? 20 : 0)
        sets.forEach { $0.index += warm.count }
        for (k, w) in warm.enumerated() {
            let s = LoggedSet(exerciseID: ex.id, exerciseOrder: first.exerciseOrder, index: k, weight: w.weight, reps: w.reps, rest: 60)
            s.warmup = true
            session.sets.append(s)
        }
        collapsed.remove(ex.id)
        try? context.save()
    }

    private func removeExercise(_ id: String) {
        // Só apaga: mexer na lista da relação (sets.removeAll) junto com o delete trava o SwiftData
        session.orderedSets.filter { $0.exerciseID == id }.forEach(context.delete)
        session.setLinkedNext(id, false)
        try? context.save()
    }

    /// Tira uma série e renumera as que ficam (a última série leva o exercício junto)
    private func removeSet(_ s: LoggedSet) {
        let id = s.exerciseID
        let rest = session.orderedSets.filter { $0.exerciseID == id && $0 !== s }
        // Só apaga: mexer na lista da relação junto com o delete trava o SwiftData
        withAnimation(.snappy) {
            context.delete(s)
            for (k, other) in rest.enumerated() { other.index = k }
        }
        if rest.isEmpty { session.setLinkedNext(id, false) }
        try? context.save()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func duplicateSet(_ s: LoggedSet) {
        let sets = session.orderedSets.filter { $0.exerciseID == s.exerciseID }
        guard let pos = sets.firstIndex(where: { $0 === s }) else { return }
        for other in sets[(pos + 1)...] { other.index += 1 }
        let copy = LoggedSet(exerciseID: s.exerciseID, exerciseOrder: s.exerciseOrder, index: s.index + 1, weight: s.weight, reps: s.targetReps, rest: s.rest)
        copy.warmup = s.warmup
        session.sets.append(copy)
        try? context.save()
    }

    private var setActions: [GMAction] {
        guard let s = setMenu else { return [] }
        let last = !session.sets.contains { $0.exerciseID == s.exerciseID && $0 !== s }
        return [
            GMAction("Duplicar série", icon: "plus.square.on.square") { duplicateSet(s) },
            GMAction(last ? "Remover série (o exercício sai do treino)" : "Remover série", icon: "trash", destructive: true) { removeSet(s) },
        ]
    }

    private func removeWarmup(_ id: String) {
        let sets = session.orderedSets.filter { $0.exerciseID == id }
        sets.filter(\.warmup).forEach(context.delete)
        for (k, s) in sets.filter({ !$0.warmup }).enumerated() { s.index = k }
        try? context.save()
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
                // `double` também lê o valor que a restauração do backup grava como texto
                let bar = UserDefaults.standard.object(forKey: "barWeight") == nil ? 20 : UserDefaults.standard.double(forKey: "barWeight")
                list.append(GMAction("Calcular anilhas", icon: "circle.grid.2x1") { platesFor = ex.weightIncludesBar(in: session) ? w : w + bar })
            }
        }
        let rest = session.orderedSets.first { $0.exerciseID == id && !$0.done }?.rest
            ?? session.orderedSets.last { $0.exerciseID == id }?.rest ?? 90
        list.append(GMAction("Tempo de descanso (\(clock(rest)))", icon: "timer") {
            restDraft = rest
            restPicker = RestTarget(exerciseID: id)
        })
        let ids = session.exerciseIDs
        if let i = ids.firstIndex(of: id), i < ids.count - 1 {
            let on = session.linkedNext(id)
            list.append(GMAction(on ? "Separar de \(Exercise.name(ids[i + 1]))" : "Superset com \(Exercise.name(ids[i + 1]))", icon: on ? "link.badge.plus" : "link") {
                session.setLinkedNext(id, !on)
                try? context.save()
            })
        }
        let sets = session.orderedSets.filter { $0.exerciseID == id }
        if sets.contains(where: \.warmup) {
            list.append(GMAction("Tirar aquecimento", icon: "flame") { removeWarmup(id) })
        } else if let ex = Exercise.byID(id), ex.type == .weighted, (sets.first?.weight ?? 0) > 0 {
            list.append(GMAction("Adicionar aquecimento", icon: "flame") { addWarmup(ex) })
        }
        if Exercise.byID(id)?.type == .weighted {
            let g = TrainingGoal.of(id)
            list.append(GMAction("Objetivo: \(g?.label ?? "nenhum")", icon: "target") { goalFor = id })
        }
        if session.pending(id) {
            list.append(GMAction("Trocar exercício (aparelho ocupado)", icon: "arrow.triangle.swap") { swapping = IDBox(id: id) })
        }
        list.append(GMAction("Histórico de cargas", icon: "chart.line.uptrend.xyaxis") { historyFor = id })
        let current = notes.first { $0.exerciseID == id }?.text ?? ""
        list.append(GMAction(current.isEmpty ? "Adicionar nota" : "Editar nota", icon: "note.text") {
            noteText = current
            noteFor = id
        })
        list.append(GMAction("Remover exercício", icon: "trash", destructive: true) { confirmRemove = id })
        return list
    }

    // MARK: Exercício

    private func exerciseCard(_ id: String) -> some View {
        let ex = Exercise.byID(id)
        let sets = session.orderedSets.filter { $0.exerciseID == id }
        let work = sets.filter { !$0.warmup }
        let warmups = sets.count - work.count
        let suggestion = Progression.suggest(exerciseID: id, sets: work.count, reps: work.first?.targetReps ?? 10, history: history)
        let group = session.group(of: id)
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

            if group.count > 1 {
                Label("Superset \((group.firstIndex(of: id) ?? 0) + 1)/\(group.count) · descanso depois de \(Exercise.name(group.last ?? id))",
                      systemImage: "link")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.info)
            }
            if let note = notes.first(where: { $0.exerciseID == id }), !note.text.isEmpty {
                Button { noteText = note.text; noteFor = id } label: {
                    Label(note.text, systemImage: "note.text")
                        .font(.caption)
                        .foregroundStyle(Theme.note.opacity(0.9))
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(GMPress())
            }
            let pending = work.filter { !$0.done }
            if suggestion.weight > 0, !pending.isEmpty, pending.allSatisfy({ $0.weight == 0 }) {
                // Treino aberto antes de registrar o PR (ou carga em branco): preenche com um toque
                Button {
                    pending.forEach { $0.weight = suggestion.weight }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Label("Usar \(Progression.fmt(suggestion.weight)) kg nas séries", systemImage: "wand.and.stars")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Theme.accent, in: .capsule)
                        .foregroundStyle(.black)
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
                        (ex?.type == .weighted || s.weight > 0 ? "\(Progression.fmt(s.weight))×\(s.reps)" : "\(s.reps)") + (s.reps < s.target ? "/\(s.target)" : "")
                    }.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(Theme.dim)
                }
            }

            ForEach(sets) { s in
                SetRow(set: s, label: s.warmup ? "A" : "\(s.index - warmups + 1)",
                       type: ex?.type ?? .weighted, increment: ex?.increment ?? 2.5, unit: ex?.weightUnit(in: session) ?? "kg",
                       onMenu: { setMenu = s }, onRemove: { removeSet(s) }) { done in
                    if done {
                        // Superset: vai para o próximo do bloco sem descanso
                        if session.advance(after: id) { startRest(s.rest) } else { cancelRest() }
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
        .background(Theme.card, in: .rect(cornerRadius: Theme.radius))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(currentID == id ? Theme.accent : complete ? Theme.accent.opacity(0.35) : .clear,
                                                           lineWidth: currentID == id ? 2 : 1))
    }

    private func add(_ ex: Exercise) {
        let order = (session.sets.map(\.exerciseOrder).max() ?? -1) + 1
        let reps = ex.type == .time ? 30 : 10
        var s = Progression.suggest(exerciseID: ex.id, sets: 3, reps: reps, history: history)
        var count = 3
        // Treino de deload: o exercício adicionado segue a mesma regra dos da rotina (70 % e menos séries)
        if session.isDeload { (s, count) = Deload.apply(s, sets: 3, exerciseID: ex.id) }
        for k in 0..<count {
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
                GMIconButton(icon: "minus", size: 38, label: "Menos 15 segundos") {
                    let l = Int(left.rounded(.up)) - 15
                    if l <= 0 { cancelRest() } else { startRest(l, keepTotal: true) }
                }
                GMIconButton(icon: "plus", size: 38, label: "Mais 15 segundos") { startRest(Int(left.rounded(.up)) + 15, keepTotal: true) }
                GMButton("Pular", full: false, small: true) { cancelRest() }
            }
            .padding(14)
            .background(Theme.card, in: .rect(cornerRadius: Theme.radius))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.stroke))
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
    /// Número da série, ou "A" no aquecimento
    let label: String
    let type: ExerciseType
    let increment: Double
    var unit = "kg"
    /// Toque no número: menu da série (remover, duplicar)
    var onMenu: () -> Void = {}
    var onRemove: () -> Void = {}
    let onToggle: (Bool) -> Void
    /// Arrasto para a esquerda: revela o remover; até o fim, remove
    @State private var offset: CGFloat = 0
    private let reveal: CGFloat = 76

    var body: some View {
        ZStack(alignment: .trailing) {
            if offset < 0 {
                Button(action: onRemove) {
                    Image(systemName: "trash.fill")
                        .font(.body.bold())
                        .frame(width: max(-offset - 8, 0), height: 44)
                        .background(Theme.danger, in: .rect(cornerRadius: Theme.radiusM))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remover série")
            }
            row
                .background(Theme.card)
                .offset(x: offset)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 18)
                        .onChanged { v in
                            // Só arrasto de lado; o de cima para baixo continua rolando a tela
                            guard abs(v.translation.width) > abs(v.translation.height) else { return }
                            offset = min(0, v.translation.width + (offset <= -reveal ? -reveal : 0))
                        }
                        .onEnded { v in
                            withAnimation(.snappy) {
                                if offset < -220 { offset = 0; onRemove() }
                                else { offset = offset < -reveal / 2 ? -reveal : 0 }
                            }
                        }
                )
        }
        .accessibilityAction(named: "Remover série", onRemove)
    }

    private var row: some View {
        HStack(spacing: 10) {
            Button(action: onMenu) {
                Text(label)
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(set.warmup ? Theme.streak : Theme.dim)
                    .frame(width: 26, height: 26)
                    .background(Theme.raised, in: .circle)
            }
            .buttonStyle(GMPress())
            .accessibilityLabel("Opções da série \(label)")

            // Peso do corpo e isometria aceitam carga extra (cinto, colete, halteres)
            GMCompactStepper(value: Binding(get: { set.weight }, set: { set.weight = max($0, 0) }),
                             step: type == .weighted ? increment : 2.5, label: Text(type == .weighted ? unit : "+kg"), decimals: true, editable: true)
            // Planejado × feito: abaixe as reps se não completou; a etiqueta mostra a meta
            GMCompactStepper(value: Binding(get: { Double(set.reps) }, set: { set.reps = max(Int($0), 0) }),
                             step: type == .time ? 5 : 1, label: repsLabel, editable: true)
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusM).stroke(missed ? Theme.warning.opacity(0.7) : .clear, lineWidth: 1.5))

            Spacer(minLength: 0)

            Button {
                set.done.toggle()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onToggle(set.done)
            } label: {
                Image(systemName: set.done ? (missed ? "checkmark.circle" : "checkmark.circle.fill") : "circle")
                    .font(.system(size: 30))
                    .foregroundStyle(set.done ? (missed ? Theme.warning : Theme.accent) : Theme.dim)
            }
            .buttonStyle(GMPress())
            .accessibilityLabel(set.done ? "Série feita" : "Marcar série como feita")
        }
        .padding(.vertical, 2)
        .opacity(set.done ? 0.75 : 1)
    }

    /// Fez menos que o planejado
    private var missed: Bool { !self.set.warmup && self.set.reps < self.set.targetReps }

    private var repsLabel: Text {
        let unit = type == .time ? "s" : "reps"
        guard self.set.targetReps > 0, set.reps != set.targetReps else { return Text(unit) }
        return Text("de \(set.targetReps)").foregroundStyle(missed ? Theme.warning : Theme.accent).bold()
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
    @Query private var routines: [Routine]
    @State private var updateRoutine = false
    @State private var leagues: Set<UUID> = []
    @State private var photo: Data?
    @State private var postTitle: String?
    @State private var blocked = false

    private var minutes: Int { max(Int(Date.now.timeIntervalSince(session.start) / 60), 1) }

    var body: some View {
        let done = session.doneWorkSets
        let volume = session.volume
        let records = Progression.records(in: session.log, history: history)
        let p = preview
        let xp = p.xp

        GMModal("Concluir treino", confirm: "Salvar", confirmEnabled: !done.isEmpty && hasPostDestination(leagues), onConfirm: save) {
            GMCard {
                HStack {
                    stat(durationText(minutes), "duração")
                    stat("\(done.count)/\(session.workSets.count)", "séries")
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
            let misses = missRows
            if !misses.isEmpty {
                GMSection("Onde melhorar", footer: "Séries em que você fez menos que o planejado. A carga se mantém no próximo treino até você completar todas.") {
                    ForEach(misses, id: \.0) { name, done, target in
                        HStack(alignment: .firstTextBaseline) {
                            Text(name).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(done).font(.subheadline.monospacedDigit())
                            Text("de \(target)").font(.caption.bold()).foregroundStyle(Theme.warning)
                        }
                    }
                }
            }
            if !records.isEmpty {
                GMSection("Recordes 🏆") {
                    ForEach(records, id: \.self) { Text($0).font(.subheadline) }
                }
            }
            if let r = routine, !session.routineChanges(r).isEmpty {
                GMSection("Rotina \(r.name)", footer: "Liga para a próxima vez já começar assim. Cargas não entram: elas vêm do histórico.") {
                    ForEach(session.routineChanges(r), id: \.self) { Text("• " + $0).font(.subheadline) }
                    GMDivider()
                    GMToggle(title: "Salvar essas mudanças na rotina", isOn: $updateRoutine)
                }
            }
            GMSection { GMEffortPicker(value: $effort) }
            LeaguePostSection(selected: $leagues, photo: $photo)
            if postTitle != nil && !leagues.isEmpty {
                GMSection("Título do post") {
                    GMTextField(placeholder: "Título (ex.: Dia de perna 🦵)", text: Binding(get: { postTitle ?? "" }, set: { postTitle = $0 }))
                    if blocked { ContentBlockedNote() }
                }
            }
            GMSection(footer: done.isEmpty ? "Marque ao menos uma série feita para salvar." : nil) {
                HStack {
                    Text("+\(xp) XP").font(.title2.weight(.heavy).monospacedDigit()).foregroundStyle(Theme.accent)
                    Spacer()
                    Label("Força", systemImage: Attribute.forca.symbol).foregroundStyle(Attribute.forca.color)
                }
                if !p.gains.isEmpty {
                    GMDivider()
                    BroGainsView(gains: p.gains)
                }
                if !p.grows.isEmpty {
                    let eggs = p.grows.allSatisfy { $0 == .egg }, many = p.grows.count > 1
                    Text(eggs ? (many ? "Isso vai fazer os ovos chocarem! 🥚" : "Isso vai fazer o ovo chocar! 🥚")
                              : (many ? "Isso vai fazer seus bros evoluírem! ✨" : "Isso vai fazer seu bro evoluir! ✨"))
                        .font(.subheadline.bold())
                }
            }
        }
        .onChange(of: postTitle) { blocked = false }
    }

    /// XP do treino e o estágio de antes de cada bro que vai evoluir. O principal leva tudo e o bro de cada liga marcada,
    /// um pouco menos (regra do Roster, como no registro de atividade). Vários donos: mostra o maior.
    private var preview: (xp: Int, grows: [Stage], gains: [BroGain]) {
        let sets = session.doneWorkSets.map { AttributeSplit.SetSignal(exerciseID: $0.exerciseID, reps: $0.reps, rest: $0.rest) }
        let split = AttributeSplit.split(.init(kind: .musculacao, minutes: minutes, effort: effort, sets: sets))
        let id = UUID()
        let roster = Roster(monsters: monsters, activities: activities, checkIns: checkIns, leagues: allLeagues)
        var xp = 0, grows: [Stage] = [], each: [UUID: Int] = [:]
        for (o, share) in roster.shares(leagueIDs: leagues, owner: roster.mainID) {
            var new = ActivityRecord(id: id, kind: .musculacao, date: session.start, minutes: minutes, effort: effort, weights: split)
            new.share = share
            let current = roster.records[o] ?? []
            let before = Game.cachedSnapshot(current), after = Game.snapshot(current + [new])
            xp = max(xp, after.xpByActivity[new.id] ?? 0)
            each[o] = after.xpByActivity[new.id] ?? 0
            if after.stage > before.stage { grows.append(before.stage) }
        }
        return (xp, grows, BroGain.preview(each, roster: roster, leagues: allLeagues, selected: leagues))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.monospacedDigit())
            Text(label).font(.caption).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity)
    }

    private var records: [String] { Progression.records(in: session.log, history: history) }

    private var routine: Routine? { session.routineUUID.flatMap { id in routines.first { $0.uuid == id } } }

    /// (exercício, reps feitas por série, meta) dos exercícios com alguma série abaixo do planejado
    private var missRows: [(String, String, Int)] {
        session.exerciseIDs.compactMap { id in
            let sets = session.orderedSets.filter { $0.exerciseID == id && $0.done && !$0.warmup }
            guard let target = sets.map(\.targetReps).max(), sets.contains(where: { $0.reps < $0.targetReps }) else { return nil }
            return (Exercise.name(id), sets.map { "\($0.reps)" }.joined(separator: " · "), target)
        }
    }

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
        let title = postTitle ?? session.title
        if !leagues.isEmpty && !ContentFilter.allows(title) {
            if postTitle == nil { postTitle = title }
            blocked = true
            return
        }
        let activity = Activity(kind: .musculacao, date: session.start, minutes: minutes, effort: effort, note: session.title)
        activity.gymUUID = session.gymUUID
        context.insert(activity)
        let summary = records.isEmpty ? "" : "🏆 " + records.joined(separator: " · ")
        postCheckIns(activity: activity, leagues: leagues, title: title, note: ContentFilter.publishable(summary), photo: photo, context: context)
        if updateRoutine, let r = routine, !session.routineChanges(r).isEmpty { session.apply(to: r, context: context) }
        session.end = .now
        LiveShare.end(session.uuid.uuidString)
        session.effort = effort
        session.activityUUID = activity.uuid
        try? context.save()
        ActivitySplits.stamp(activity, context: context)
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
