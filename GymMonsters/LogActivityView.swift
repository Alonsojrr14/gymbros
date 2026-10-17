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

    private var preview: (xp: Int, after: Snapshot) {
        let new = ActivityRecord(id: UUID(), kind: kind, date: date, minutes: minutes, effort: effort)
        let roster = Roster(monsters: monsters, activities: activities, checkIns: checkIns, leagues: allLeagues)
        let after = Game.snapshot((roster.mainID.flatMap { roster.records[$0] } ?? []) + [new])
        return (after.xpByActivity[new.id] ?? 0, after)
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
            }

            GMCard { previewView }

            if editing == nil {
                LeaguePostSection(selected: $leagues, photo: $photo)
            } else {
                LeaguePostSection(selected: $leagues, photo: $photo, selectAllByDefault: false)
                if !leagues.isEmpty {
                    GMSection("Post", footer: "Vale para todos os destinos marcados. Tirar um destino apaga o check-in de lá.") {
                        GMTextField(placeholder: "Título (ex.: Dia de perna 🦵)", text: $postTitle)
                        GMTextField(placeholder: "Descrição (opcional)", text: $postNote, axis: .vertical)
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
        .onAppear {
            guard let a = editing else { return }
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
                postTitle = a.note
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
            if p.after.stage > snapshot.stage {
                Text(snapshot.stage == .egg ? "Isso vai fazer o ovo chocar! 🥚" : "Isso vai fazer seu bro evoluir! ✨")
                    .font(.subheadline.bold())
            } else if p.xp < Game.xp(kind: kind, minutes: minutes, effort: effort) {
                Text("Você já treinou bastante nesse dia, então rende menos XP. Descanso também faz parte.")
                    .font(.caption)
                    .foregroundStyle(Theme.dim)
            }
        }
    }

    private func save() {
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
                    .background(on ? Theme.accent.opacity(0.2) : Theme.raised, in: .rect(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(on ? Theme.accent : .clear, lineWidth: 1.5))
                    .foregroundStyle(on ? Theme.accent : .white)
                }
                .buttonStyle(GMPress())
            }
        }
    }
}
