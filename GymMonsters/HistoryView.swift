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

    @State private var menu: Activity?
    @State private var editing: Activity?
    @State private var routeFor: RouteRecord?
    @Query private var routes: [RouteRecord]

    var body: some View {
        NavigationStack {
            GMScreen("Histórico", avatar: true) {
                if activities.isEmpty {
                    GMEmptyState(icon: "figure.run", title: "Nenhuma atividade ainda", message: "Seus treinos aparecem aqui.")
                } else {
                    summary
                    ForEach(days, id: \.day) { group in
                        GMSection(group.day.formatted(.dateTime.weekday(.wide).day().month(.wide))) {
                            ForEach(group.items) { a in
                                Button { menu = a } label: {
                                    ActivityRow(activity: a, xp: snapshot.xpByActivity[a.uuid] ?? 0)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(GMPress())
                                if a.id != group.items.last?.id { GMDivider() }
                            }
                        }
                    }
                }
            }
            .gmActions(isPresented: Binding(get: { menu != nil }, set: { if !$0 { menu = nil } }),
                       title: menu.map { "\($0.kind.name) · \(durationText($0.minutes))" },
                       message: menu.map { $0.date.formatted(date: .complete, time: .shortened) + ($0.note.isEmpty ? "" : "\n\($0.note)") },
                       actions: menuActions)
            .gmModal(item: $editing) { LogActivityView(snapshot: snapshot, editing: $0) }
            .gmSheet(isPresented: Binding(get: { routeFor != nil }, set: { if !$0 { routeFor = nil } })) { _ in
                if let r = routeFor {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(r.kind.name) · \(kmText(r.meters))").font(.headline)
                        RouteMap(coords: r.coordinates).frame(height: 280).clipShape(.rect(cornerRadius: 16))
                        Text("\(clock(r.seconds)) · \(paceText(kind: r.kind, meters: r.meters, seconds: r.seconds))")
                            .font(.subheadline.monospacedDigit()).foregroundStyle(Theme.dim)
                    }
                }
            }
        }
    }

    /// Ações da atividade tocada. O item é guardado aqui, antes de a bottom sheet fechar
    /// (ao fechar, `menu` volta a nil e a ação ficaria sem saber qual atividade era).
    private var menuActions: [GMAction] {
        guard let a = menu else { return [] }
        var list: [GMAction] = []
        if let r = routes.first(where: { $0.activityUUID == a.uuid }) {
            list.append(GMAction("Ver percurso (\(kmText(r.meters)))", icon: "map") { routeFor = r })
        }
        list.append(GMAction("Editar", icon: "pencil") { editing = a })
        list.append(GMAction("Apagar atividade", icon: "trash", destructive: true) { delete(a) })
        return list
    }

    private func delete(_ a: Activity) {
        // Treino guiado e check-ins ligados a esta atividade somem junto
        let id = a.uuid
        let linked = (try? context.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.activityUUID == id }))) ?? []
        linked.forEach(context.delete)
        if let h = a.healthUUID { HealthSync.ignored.insert(h) }
        let posts = (try? context.fetch(FetchDescriptor<LeagueCheckIn>(predicate: #Predicate { $0.activityUUID == id }))) ?? []
        posts.forEach(context.delete)
        let route = (try? context.fetch(FetchDescriptor<RouteRecord>(predicate: #Predicate { $0.activityUUID == id }))) ?? []
        route.forEach(context.delete)
        context.delete(a)
        try? context.save()
    }

    private var summary: some View {
        let total = activities.reduce(0) { $0 + $1.minutes }
        let attrs = snapshot.lifetimeAttributes
        let sum = max(attrs.values.reduce(0, +), 1)
        return GMCard {
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
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.heavy).monospacedDigit())
            Text(label).font(.caption).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity)
    }
}
