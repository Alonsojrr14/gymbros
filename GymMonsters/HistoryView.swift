import SwiftData
import SwiftUI

struct HistoryView: View {
    let snapshot: Snapshot
    let activities: [Activity]
    @Environment(\.modelContext) private var context

    private var days: [(day: Date, items: [Activity])] {
        let groups = Dictionary(grouping: activities) { Calendar.current.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0]!.sorted { $0.date > $1.date }) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if activities.isEmpty {
                    ContentUnavailableView("Nenhuma atividade ainda", systemImage: "figure.run",
                                           description: Text("Seus treinos aparecem aqui."))
                } else {
                    List {
                        summary
                        ForEach(days, id: \.day) { group in
                            Section(group.day.formatted(.dateTime.weekday(.wide).day().month(.wide))) {
                                ForEach(group.items) { a in
                                    ActivityRow(activity: a, xp: snapshot.xpByActivity[a.uuid] ?? 0)
                                        .listRowBackground(Theme.card)
                                }
                                .onDelete { idx in
                                    idx.map { group.items[$0] }.forEach(context.delete)
                                    try? context.save()
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Theme.bg)
            .navigationTitle("Histórico")
        }
    }

    private var summary: some View {
        let total = activities.reduce(0) { $0 + $1.minutes }
        let attrs = snapshot.lifetimeAttributes
        let sum = max(attrs.values.reduce(0, +), 1)
        return Section {
            HStack {
                stat("\(activities.count)", "atividades")
                stat(total >= 60 ? "\(total / 60) h" : "\(total) min", "treinando")
                stat("\(snapshot.totalXP)", "XP")
            }
            GeometryReader { g in
                HStack(spacing: 2) {
                    ForEach(Attribute.allCases) { a in
                        Rectangle().fill(a.color).frame(width: g.size.width * (attrs[a] ?? 0) / sum)
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 10)
            HStack(spacing: 12) {
                ForEach(Attribute.allCases) { a in
                    Label("\(Int(((attrs[a] ?? 0) / sum * 100).rounded()))%", systemImage: a.symbol)
                        .foregroundStyle(a.color)
                }
            }
            .font(.caption.weight(.semibold))
        }
        .listRowBackground(Theme.card)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.heavy).monospacedDigit())
            Text(label).font(.caption).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity)
    }
}
