import SwiftData
import SwiftUI

struct LogActivityView: View {
    let snapshot: Snapshot
    /// Atividade existente para editar (nil = nova)
    var editing: Activity? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var activities: [Activity]
    @Query private var monsters: [Monster]
    @Query private var checkIns: [LeagueCheckIn]
    @Query private var allLeagues: [League]

    @State private var kind: ActivityKind = .musculacao
    /// Tipo exato (HKWorkoutActivityType); a categoria `kind` sai dele
    @State private var type = WorkoutType.of(.musculacao).id
    @State private var date = Date.now
    @State private var minutes = 60
    @State private var effort = 6
    @State private var note = ""
    @State private var leagues: Set<UUID> = []
    @State private var photo: Data?
    // Post (na edição)
    @State private var postTitle = ""
    @State private var postNote = ""
    @State private var place: String?
    @State private var choosingPlace = false
    @Query(sort: \Gym.createdAt) private var gyms: [Gym]

    /// Rotina ou WOD feito sem dar "Começar" (só em atividade nova)
    @State private var workout = ManualWorkoutDraft()
    @State private var loaded = false
    /// Editando uma atividade que não estava postada em lugar nenhum (ex.: importada do Saúde): pode salvar sem destino
    @State private var wasUnposted = false
    @State private var blocked = false

    /// XP desta atividade e o estágio de antes de cada bro que vai evoluir com ela. Os donos seguem a
    /// regra do Roster com os destinos marcados agora; na edição, a versão antiga sai da conta
    /// (senão somaria o treino duas vezes e avisaria de uma evolução que não vai acontecer).
    /// Divisão do que está na tela; editando, mantém o detalhe do treino (séries, WOD) e o tipo do Saúde
    private var split: [Attribute: Double] {
        var s = AttributeSplit.Signals(kind: kind, minutes: minutes, effort: effort, meters: editing?.meters,
                                       healthType: type)
        // Treino feito informado agora: as séries ou o WOD já entram na prévia
        if workout.mode == .routine {
            s.sets = workout.items.flatMap { i in Array(repeating: AttributeSplit.SetSignal(exerciseID: i.exerciseID, reps: i.reps, rest: 90), count: i.sets) }
        } else if workout.mode == .wod, let w = ManualWorkoutDraft.wod(workout.wodID) {
            s.wod = .init(format: w.format, exercises: w.exercises.isEmpty ? WodMovements.ids(w.lines) : w.exercises)
        }
        if let a = editing, a.workoutType.id == type, a.minutes == minutes, a.effort == effort, let stored = ActivitySplits.weights(a.uuid) { return stored }
        return AttributeSplit.split(s)
    }

    private var preview: (xp: Int, grows: [Stage]) {
        let id = editing?.uuid ?? UUID()
        let roster = Roster(monsters: monsters, activities: activities, checkIns: checkIns, leagues: allLeagues)
        let owners = roster.owners(leagueIDs: leagues, owner: editing == nil ? roster.mainID : editing?.monsterUUID)
        let new = ActivityRecord(id: id, kind: kind, date: date, minutes: minutes, effort: effort, weights: split)
        var xp = 0, grows: [Stage] = []
        for o in owners {
            let current = roster.records[o] ?? []
            let before = Game.cachedSnapshot(current), after = Game.snapshot(current.filter { $0.id != id } + [new])
            // Vários donos: mostra o maior, como nas listas
            xp = max(xp, after.xpByActivity[id] ?? 0)
            if after.stage > before.stage { grows.append(before.stage) }
        }
        return (xp, grows)
    }

    var body: some View {
        GMModal(editing == nil ? "Nova atividade" : "Editar atividade", confirm: "Salvar", confirmEnabled: (editing != nil && wasUnposted) || hasPostDestination(leagues), onConfirm: save) {
            // Com rotina ou WOD informado, o tipo vem dele: uma "Corrida" não pode levar séries de musculação
            if workout.isEmpty {
                GMSection("Atividade") { ActivityTypePicker(type: $type) }
            } else if let t = WorkoutType.byID(type) {
                GMSection("Atividade", footer: "Definido pelo treino feito. Tire o treino para escolher outro tipo.") {
                    GMRow(icon: t.symbol, tile: Theme.accent, title: t.name, subtitle: "Pelo treino feito") { EmptyView() }
                }
            }
            if editing == nil { ManualWorkoutSection(draft: $workout, type: $type, minutes: $minutes, date: date) }

            GMSection("Duração") {
                GMStepper(value: $minutes, range: 5...Game.maxMinutes, step: 5, format: durationText)
                    .frame(maxWidth: .infinity)
                HStack(spacing: 8) {
                    ForEach([30, 45, 60, 90], id: \.self) { m in
                        GMChip(title: "\(m) min", selected: minutes == m) { minutes = m }
                    }
                }
                .frame(maxWidth: .infinity)
            }

            GMSection(footer: "Quão puxado foi, de 1 (bem leve) a 10 (no limite).") {
                GMEffortPicker(value: $effort)
            }

            GMSection("Quando") {
                GMDateTimePicker(date: $date)
                GMTextField(placeholder: "Observação (opcional)", text: $note)
                if blocked && editing == nil { ContentBlockedNote() }
                // Onde foi (opcional): vai para a atividade, o treino informado e o check-in
                if editing == nil && !gyms.isEmpty {
                    GMDivider()
                    placeRow
                }
            }

            GMCard { previewView }

            if editing == nil {
                LeaguePostSection(selected: $leagues, photo: $photo)
            } else {
                LeaguePostSection(selected: $leagues, photo: $photo, selectAllByDefault: false, fromHealth: editing?.isFromHealth ?? false)
                if !leagues.isEmpty {
                    GMSection("Post", footer: "Vale para todos os destinos marcados. Tirar um destino apaga o check-in de lá.") {
                        GMTextField(placeholder: "Título (ex.: Dia de perna 🦵)", text: $postTitle)
                        GMTextField(placeholder: "Descrição (opcional)", text: $postNote, axis: .vertical)
                        if blocked { ContentBlockedNote() }
                        GMDivider()
                        placeRow
                    }
                }
            }
        }
        .gmActions(isPresented: $choosingPlace, title: "Onde foi?", actions:
            gyms.map { g in GMAction(g.name, icon: "dumbbell.fill") { place = g.name } }
            + [GMAction("Sem local", icon: "xmark") { place = nil }])
        .onChange(of: note + postTitle + postNote) { blocked = false }
        .onChange(of: type) { _, t in kind = WorkoutType.byID(t)?.kind ?? .outro }
        .onAppear {
            // Só na primeira vez: não pode desfazer o que a pessoa já mudou na tela
            guard !loaded, let a = editing else { return }
            loaded = true
            kind = a.kind
            type = a.workoutType.id
            date = a.date
            minutes = a.minutes
            effort = a.effort
            note = a.note
            // Check-ins atuais desta atividade
            let posts = checkIns.filter { $0.activityUUID == a.uuid }
            leagues = Set(posts.map(\.leagueUUID))
            wasUnposted = posts.isEmpty
            if let first = posts.first {
                postTitle = first.title
                postNote = first.note
                photo = posts.compactMap(\.photo).first
                place = first.place
            } else {
                postTitle = a.isFromHealth ? "" : a.note
                place = GymLocation.shared.gym(a.gymUUID)?.name
            }
        }
    }

    private var placeRow: some View {
        GMRow(icon: "mappin.and.ellipse", iconTint: place == nil ? Theme.dim : Theme.accent,
              title: place ?? "Sem local", subtitle: "Onde foi", chevron: true) { choosingPlace = true }
    }

    private var previewView: some View {
        let p = preview
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("+\(p.xp) XP")
                    .font(.title2.weight(.heavy).monospacedDigit())
                    .foregroundStyle(Theme.accent)
                Spacer()
                HStack(spacing: 8) {
                    ForEach(Attribute.allCases.filter { split[$0] != nil }) { a in
                        Label("+\(Int((Double(p.xp) * (split[a] ?? 0)).rounded()))", systemImage: a.symbol)
                            .foregroundStyle(a.color)
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            }
            if !p.grows.isEmpty {
                let eggs = p.grows.allSatisfy { $0 == .egg }, many = p.grows.count > 1
                Text(eggs ? (many ? "Isso vai fazer os ovos chocarem! 🥚" : "Isso vai fazer o ovo chocar! 🥚")
                          : (many ? "Isso vai fazer seus bros evoluírem! ✨" : "Isso vai fazer seu bro evoluir! ✨"))
                    .font(.subheadline.bold())
            } else if p.xp < Game.xp(kind: kind, minutes: minutes, effort: effort) {
                Text("Você já treinou bastante nesse dia, então rende menos XP. Descanso também faz parte.")
                    .font(.caption)
                    .foregroundStyle(Theme.dim)
            }
        }
    }

    private func save() {
        // Sem observação, o treino feito vira o título (como no treino guiado)
        let title = note.isEmpty ? (workout.wodText ?? (workout.mode == .routine && !workout.items.isEmpty ? workout.title : "")) : note
        // O título vai para o check-in: passa pelo filtro, inclusive o nome digitado no treino livre
        let posted = editing == nil ? [title] : [postTitle, postNote]
        if !leagues.isEmpty && !posted.allSatisfy({ ContentFilter.allows($0) }) {
            blocked = true
            return
        }
        if let a = editing {
            a.kindRaw = kind.rawValue
            a.healthType = Int(type)
            a.date = date
            a.minutes = minutes
            a.effort = effort
            a.note = note
            // Gravado no Saúde: regrava com os dados novos
            if a.healthWrittenUUID != nil {
                HealthSync.deleteWritten(a.healthWrittenUUID)
                a.healthWrittenUUID = nil
            }
            if let g = gyms.first(where: { $0.name == place }) { a.gymUUID = g.uuid } else if place == nil { a.gymUUID = nil }
            syncCheckIns(activity: a, destinations: leagues, title: postTitle, note: postNote, photo: photo, place: place, context: context)
            try? context.save()
            ActivitySplits.stamp(a, context: context)
            dismiss()
            return
        }
        let activity = Activity(kind: kind, date: date, minutes: minutes, effort: effort, note: title)
        activity.healthType = Int(type)
        activity.gymUUID = gyms.first(where: { $0.name == place })?.uuid
        context.insert(activity)
        workout.save(for: activity, context: context)
        postCheckIns(activity: activity, leagues: leagues, title: title, note: "", photo: photo, context: context)
        try? context.save()
        ActivitySplits.stamp(activity, context: context)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

