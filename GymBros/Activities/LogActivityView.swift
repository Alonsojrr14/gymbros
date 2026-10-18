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

    @State private var loaded = false
    @State private var blocked = false

    /// XP desta atividade e o estágio de antes de cada bro que vai evoluir com ela. Os donos seguem a
    /// regra do Roster com os destinos marcados agora; na edição, a versão antiga sai da conta
    /// (senão somaria o treino duas vezes e avisaria de uma evolução que não vai acontecer).
    private var preview: (xp: Int, grows: [Stage]) {
        let id = editing?.uuid ?? UUID()
        let roster = Roster(monsters: monsters, activities: activities, checkIns: checkIns, leagues: allLeagues)
        let owners = roster.owners(leagueIDs: leagues, owner: editing == nil ? roster.mainID : editing?.monsterUUID)
        let new = ActivityRecord(id: id, kind: kind, date: date, minutes: minutes, effort: effort)
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
        GMModal(editing == nil ? "Nova atividade" : "Editar atividade", confirm: "Salvar", onConfirm: save) {
            GMSection("Atividade") { ActivityKindGrid(kind: $kind) }

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
                        GMRow(icon: "mappin.and.ellipse", iconTint: place == nil ? Theme.dim : Theme.accent,
                              title: place ?? "Sem local", subtitle: "Onde foi", chevron: true) { choosingPlace = true }
                    }
                }
            }
        }
        .gmActions(isPresented: $choosingPlace, title: "Onde foi?", actions:
            gyms.map { g in GMAction(g.name, icon: "dumbbell.fill") { place = g.name } }
            + [GMAction("Sem local", icon: "xmark") { place = nil }])
        .onChange(of: note + postTitle + postNote) { blocked = false }
        .onAppear {
            // Só na primeira vez: não pode desfazer o que a pessoa já mudou na tela
            guard !loaded, let a = editing else { return }
            loaded = true
            kind = a.kind
            date = a.date
            minutes = a.minutes
            effort = a.effort
            note = a.note
            // Check-ins atuais desta atividade
            let posts = checkIns.filter { $0.activityUUID == a.uuid }
            leagues = Set(posts.map(\.leagueUUID))
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

    private var previewView: some View {
        let p = preview
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("+\(p.xp) XP")
                    .font(.title2.weight(.heavy).monospacedDigit())
                    .foregroundStyle(Theme.accent)
                Spacer()
                HStack(spacing: 10) {
                    ForEach(Attribute.allCases.filter { kind.weights[$0] != nil }) { a in
                        Label("+\(Int((Double(p.xp) * (kind.weights[a] ?? 0)).rounded()))", systemImage: a.symbol)
                            .foregroundStyle(a.color)
                            .font(.caption.weight(.semibold).monospacedDigit())
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
        // A observação vira o título do check-in
        let posted = editing == nil ? [note] : [postTitle, postNote]
        if !leagues.isEmpty && !posted.allSatisfy({ ContentFilter.allows($0) }) {
            blocked = true
            return
        }
        if let a = editing {
            a.kindRaw = kind.rawValue
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
            dismiss()
            return
        }
        let activity = Activity(kind: kind, date: date, minutes: minutes, effort: effort, note: note)
        context.insert(activity)
        postCheckIns(activity: activity, leagues: leagues, title: note, note: "", photo: photo, context: context)
        try? context.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

/// Grade de tipos de atividade
struct ActivityKindGrid: View {
    @Binding var kind: ActivityKind

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(ActivityKind.allCases) { k in
                let on = kind == k
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    kind = k
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: k.symbol).font(.title2).frame(height: 30)
                        Text(k.name).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, minHeight: 66)
                    .background(on ? Theme.accent.opacity(0.2) : Theme.raised, in: .rect(cornerRadius: Theme.radiusM))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusM).stroke(on ? Theme.accent : .clear, lineWidth: 1.5))
                    .foregroundStyle(on ? Theme.accent : .white)
                }
                .buttonStyle(GMPress())
            }
        }
    }
}
