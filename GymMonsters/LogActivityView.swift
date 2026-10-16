import SwiftData
import SwiftUI

struct LogActivityView: View {
    let snapshot: Snapshot
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var activities: [Activity]

    @State private var kind: ActivityKind = .musculacao
    @State private var date = Date.now
    @State private var minutes = 60
    @State private var effort = 6.0
    @State private var note = ""

    private var preview: (xp: Int, after: Snapshot) {
        let new = ActivityRecord(id: UUID(), kind: kind, date: date, minutes: minutes, effort: Int(effort))
        let after = Game.snapshot(activities.map(\.record) + [new])
        return (after.xpByActivity[new.id] ?? 0, after)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Atividade") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(ActivityKind.allCases) { k in
                            Button { kind = k } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: k.symbol).font(.title2)
                                    Text(k.name).font(.caption2).lineLimit(1).minimumScaleFactor(0.7)
                                }
                                .frame(maxWidth: .infinity, minHeight: 64)
                                .background(kind == k ? Theme.accent.opacity(0.22) : .white.opacity(0.05), in: .rect(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(kind == k ? Theme.accent : .clear, lineWidth: 1.5))
                                .foregroundStyle(kind == k ? Theme.accent : .white)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Duração") {
                    Stepper(value: $minutes, in: 5...Game.maxMinutes, step: 5) {
                        Text(durationText(minutes)).font(.headline.monospacedDigit())
                    }
                    HStack {
                        ForEach([30, 45, 60, 90], id: \.self) { m in
                            Button("\(m) min") { minutes = m }
                                .buttonStyle(.bordered)
                                .tint(minutes == m ? Theme.accent : .gray)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }

                Section {
                    Slider(value: $effort, in: 1...10, step: 1)
                } header: {
                    HStack {
                        Text("Esforço")
                        Spacer()
                        Text("\(Int(effort))/10 · \(effortLabel(Int(effort)))").monospacedDigit()
                    }
                } footer: {
                    Text("Quão puxado foi, de 1 (bem leve) a 10 (no limite).")
                }

                Section {
                    DatePicker("Quando", selection: $date, in: ...Date.now)
                    TextField("Observação (opcional)", text: $note)
                }

                Section { previewView }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Nova atividade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salvar", action: save).bold() }
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
                Text(snapshot.stage == .egg ? "Isso vai fazer o ovo chocar! 🥚" : "Isso vai fazer seu monstro evoluir! ✨")
                    .font(.subheadline.bold())
            } else if p.xp < Game.xp(kind: kind, minutes: minutes, effort: Int(effort)) {
                Text("Você já treinou bastante nesse dia, então rende menos XP. Descanso também faz parte.")
                    .font(.caption)
                    .foregroundStyle(Theme.dim)
            }
        }
    }

    private func save() {
        context.insert(Activity(kind: kind, date: date, minutes: minutes, effort: Int(effort), note: note))
        try? context.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
