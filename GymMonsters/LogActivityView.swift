import SwiftData
import SwiftUI

struct LogActivityView: View {
    let snapshot: Snapshot
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

    private var preview: (xp: Int, after: Snapshot) {
        let new = ActivityRecord(id: UUID(), kind: kind, date: date, minutes: minutes, effort: effort)
        let roster = Roster(monsters: monsters, activities: activities, checkIns: checkIns, leagues: allLeagues)
        let after = Game.snapshot((roster.mainID.flatMap { roster.records[$0] } ?? []) + [new])
        return (after.xpByActivity[new.id] ?? 0, after)
    }

    var body: some View {
        GMModal("Nova atividade", confirm: "Salvar", onConfirm: save) {
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

            LeaguePostSection(selected: $leagues, photo: $photo)
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
                Text(snapshot.stage == .egg ? "Isso vai fazer o ovo chocar! 🥚" : "Isso vai fazer seu monstro evoluir! ✨")
                    .font(.subheadline.bold())
            } else if p.xp < Game.xp(kind: kind, minutes: minutes, effort: effort) {
                Text("Você já treinou bastante nesse dia, então rende menos XP. Descanso também faz parte.")
                    .font(.caption)
                    .foregroundStyle(Theme.dim)
            }
        }
    }

    private func save() {
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
                        Image(systemName: k.symbol).font(.title2)
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
