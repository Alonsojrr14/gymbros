import SwiftData
import SwiftUI

/// Um WOD na linha do tempo: um importado do coach (com ou sem resultado) ou um resultado de WOD clássico/livre
struct WodTimelineEntry: Identifiable, Hashable {
    enum Status { case done, today, scheduled, missed }

    let id: String
    let day: Date
    let name: String
    let format: String
    let lines: [String]
    let plan: PlannedWod?
    /// Resultados, o melhor primeiro
    let results: [WodResult]

    func status(now: Date = .now) -> Status {
        if !results.isEmpty { return .done }
        let cal = Calendar.current
        if cal.isDate(day, inSameDayAs: now) { return .today }
        return day > now ? .scheduled : .missed
    }

    /// Junta os WODs importados com todos os resultados (o resultado de um importado fica nele; o resto vira item próprio)
    static func build(plans: [PlannedWod], results: [WodResult]) -> [WodTimelineEntry] {
        let byWod = Dictionary(grouping: results, by: \.wodID)
        let planIDs = Set(plans.map(\.wodID))
        let imported = plans.map { p in
            WodTimelineEntry(id: p.wodID, day: p.day, name: p.name, format: p.format.name, lines: p.lines, plan: p,
                             results: (byWod[p.wodID] ?? []).sorted { $0.score > $1.score })
        }
        let others = results.filter { !planIDs.contains($0.wodID) }.map { r in
            WodTimelineEntry(id: r.uuid.uuidString, day: r.date, name: r.wodName, format: r.formatName,
                             lines: Wod.byID(r.wodID)?.lines ?? [], plan: nil, results: [r])
        }
        return (imported + others).sorted { $0.day > $1.day }
    }

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// Todos os WODs que você importou e fez, do mais novo ao mais antigo, por mês
struct WodTimelineView: View {
    @AppStorage(WodPlan.key) private var raw = ""
    @Query(sort: \WodResult.date, order: .reverse) private var results: [WodResult]
    @State private var filter = 0
    @State private var opened: PlannedWod?
    @State private var importing = false

    private var entries: [WodTimelineEntry] { WodTimelineEntry.build(plans: WodPlan.all(raw), results: results) }

    var body: some View {
        let all = entries
        let shown = all.filter { e in
            switch filter {
            case 1: e.status() == .done
            case 2: e.status() != .done
            default: true
            }
        }
        GMScreen("Meus WODs", subtitle: "Tudo que você importou do coach e o que já treinou", back: true) {
            GMIconButton(icon: "plus", label: "Importar WOD do coach") { importing = true }
        } content: {
            stats(all)
            GMSegmented(options: [(0, "Todos"), (1, "Feitos"), (2, "Não feitos")], selection: $filter)
            if shown.isEmpty {
                GMEmptyState(icon: "flame", title: all.isEmpty ? "Nenhum WOD ainda" : "Nada por aqui",
                             message: all.isEmpty ? "Importe o WOD do coach (print ou texto) e ele aparece aqui, no dia dele." : "Mude o filtro para ver os outros.")
            }
            ForEach(months(shown), id: \.0) { month, list in
                VStack(alignment: .leading, spacing: 0) {
                    Text(month.uppercased()).font(.caption.weight(.bold)).foregroundStyle(Theme.dim).tracking(0.6)
                        .padding(.leading, 4).padding(.bottom, 10)
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, e in
                        row(e, last: i == list.count - 1)
                    }
                }
            }
        }
        .gmModal(item: $opened) { PlannedWodView(initial: $0) }
        .gmModal(isPresented: $importing) { ImportWodView() }
    }

    // MARK: Topo

    private func stats(_ all: [WodTimelineEntry]) -> some View {
        let done = all.filter { $0.status() == .done }
        let month = done.filter { Calendar.current.isDate($0.day, equalTo: .now, toGranularity: .month) }.count
        return HStack(spacing: 0) {
            stat("\(done.count)", "feitos", Theme.accent)
            stat("\(month)", "este mês", Theme.streak)
            stat("\(all.filter { $0.plan != nil }.count)", "importados", Theme.info)
        }
        .padding(.vertical, 14)
        .background(Theme.card, in: .rect(cornerRadius: Theme.radius))
    }

    private func stat(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).gmFont(24, weight: .heavy, design: .rounded, relativeTo: .title2).foregroundStyle(tint)
            Text(label).font(.caption).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func months(_ list: [WodTimelineEntry]) -> [(String, [WodTimelineEntry])] {
        var out: [(String, [WodTimelineEntry])] = []
        for e in list {
            let key = e.day.formatted(.dateTime.month(.wide).year().locale(GMDateText.locale)).capitalizedFirst
            if out.last?.0 == key { out[out.count - 1].1.append(e) } else { out.append((key, [e])) }
        }
        return out
    }

    // MARK: Linha

    private func row(_ e: WodTimelineEntry, last: Bool) -> some View {
        let status = e.status()
        let tint = color(status)
        return HStack(alignment: .top, spacing: 12) {
            // Dia
            VStack(spacing: 0) {
                Text(e.day.formatted(.dateTime.day())).gmFont(20, weight: .heavy, design: .rounded, relativeTo: .title3)
                Text(e.day.formatted(.dateTime.weekday(.abbreviated).locale(GMDateText.locale)).replacingOccurrences(of: ".", with: "").uppercased())
                    .gmFont(10, weight: .bold, relativeTo: .caption2).foregroundStyle(Theme.dim)
            }
            .frame(width: 40)
            .padding(.top, 10)
            // Trilho
            VStack(spacing: 0) {
                Circle().fill(tint).frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Theme.bg, lineWidth: 3))
                    .padding(.top, 16)
                Rectangle().fill(last ? .clear : Theme.track).frame(width: 2)
            }
            .frame(width: 12)
            // Cartão
            card(e, status: status, tint: tint)
                .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private func card(_ e: WodTimelineEntry, status: WodTimelineEntry.Status, tint: Color) -> some View {
        let body = VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(e.name).font(.subheadline.bold()).lineLimit(1)
                Spacer(minLength: 6)
                Text(e.format).font(.caption2.bold()).foregroundStyle(Theme.streak)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Theme.streak.opacity(0.15), in: .capsule)
            }
            if !e.lines.isEmpty {
                Text(e.lines.prefix(3).joined(separator: " · ")).font(.caption).foregroundStyle(Theme.dim).lineLimit(2)
            }
            HStack(spacing: 6) {
                Image(systemName: icon(status)).font(.caption.bold())
                Text(label(e, status)).font(.caption.bold().monospacedDigit())
            }
            .foregroundStyle(tint)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: Theme.radiusL))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusL).stroke(status == .today ? tint.opacity(0.6) : .clear, lineWidth: 1.5))
        .foregroundStyle(.white)

        if let plan = e.plan {
            Button { opened = plan } label: { body }.buttonStyle(GMPress())
        } else if let wod = e.results.first.flatMap({ Wod.byID($0.wodID) }) {
            NavigationLink { WodDetailView(wod: wod) } label: { body }.buttonStyle(GMPress())
        } else {
            body
        }
    }

    private func color(_ s: WodTimelineEntry.Status) -> Color {
        switch s {
        case .done: Theme.accent
        case .today: Theme.streak
        case .scheduled: Theme.info
        case .missed: Theme.dim
        }
    }

    private func icon(_ s: WodTimelineEntry.Status) -> String {
        switch s {
        case .done: "checkmark.circle.fill"
        case .today: "flame.fill"
        case .scheduled: "calendar"
        case .missed: "minus.circle"
        }
    }

    private func label(_ e: WodTimelineEntry, _ s: WodTimelineEntry.Status) -> String {
        switch s {
        case .done:
            let r = e.results[0]
            return "Feito · " + r.text + (r.rx ? " RX" : "") + (e.results.count > 1 ? " · \(e.results.count)×" : "")
        case .today: return "Hoje"
        case .scheduled: return "Agendado"
        case .missed: return "Não registrado"
        }
    }
}
