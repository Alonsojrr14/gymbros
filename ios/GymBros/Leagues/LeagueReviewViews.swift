import SwiftData
import SwiftUI

/// Fila de revisão do dono: aprova ou nega cada check-in que está esperando, com a prova de cada um
struct LeagueReviewQueue: View {
    let league: League
    let items: [FeedItem]
    @Environment(\.modelContext) private var context
    @State private var denying: FeedItem?
    @State private var opened: FeedItem?
    @State private var decided: Set<String> = []

    private var pending: [FeedItem] { items.filter { !decided.contains($0.id) }.sorted { $0.date < $1.date } }

    var body: some View {
        GMModal(pending.count == 1 ? "1 check-in para revisar" : "\(pending.count) check-ins para revisar") {
            if pending.isEmpty {
                GMEmptyState(icon: "checkmark.seal", title: "Tudo revisado", message: "Nenhum check-in esperando.")
            }
            ForEach(pending) { item in
                GMCard { row(item) }
            }
            if !pending.isEmpty {
                Text("Aprovado, o check-in pontua. Negado, ele sai da liga e quem postou fica sabendo." +
                     (league.settings.posesEnabled ? " Sem a pose do dia na foto, negue." : ""))
                    .font(.footnote).foregroundStyle(Theme.dim)
            }
        }
        .gmModal(item: $opened) { CheckInDetailView(item: $0) }
        .gmActions(isPresented: Binding(get: { denying != nil }, set: { if !$0 { denying = nil } }),
                   title: "Negar este check-in?", message: "Ele sai da liga e não pontua.", actions: [
            GMAction("Negar check-in", icon: "xmark.circle", destructive: true) {
                if let d = denying { decide(d, approved: false) }
            }
        ])
    }

    private func row(_ item: FeedItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { opened = item } label: {
                HStack(spacing: 12) {
                    MonsterSprite(form: item.avatar).frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                        Text("\(item.name) · \(durationText(item.minutes)) · \(item.date.formatted(.dateTime.weekday().day().hour().minute()))")
                            .font(.caption).foregroundStyle(Theme.dim)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.dim)
                }
                .contentShape(Rectangle())
                .foregroundStyle(.white)
            }
            .buttonStyle(GMPress())
            let lines = item.proof.lines + (item.hasPhoto ? [] : ["Sem foto"])
            ForEach(lines, id: \.self) { Label($0, systemImage: "checkmark.seal").font(.caption).foregroundStyle(Theme.dim) }
            HStack(spacing: 10) {
                GMButton("Negar", icon: "xmark", kind: .secondary, small: true) { denying = item }
                GMButton("Aprovar", icon: "checkmark", small: true) { decide(item, approved: true) }
            }
        }
    }

    private func decide(_ item: FeedItem, approved: Bool) {
        context.insert(CheckInReview(leagueUUID: league.uuid, itemID: item.id, approved: approved))
        try? context.save()
        withAnimation { _ = decided.insert(item.id) }
        UINotificationFeedbackGenerator().notificationOccurred(approved ? .success : .warning)
    }
}

/// Barras de progresso até a meta da liga: cada pessoa e cada time
struct LeagueGoalsCard: View {
    let league: League
    let people: [RankRow]
    let teams: [TeamRow]

    var body: some View {
        let s = league.settings
        if s.individualGoal > 0 {
            GMSection("Meta de cada pessoa · \(league.scoring.format(s.individualGoal))",
                      footer: "\(people.filter { $0.score >= s.individualGoal }.count) de \(people.count) já bateram a meta.") {
                // Sem ranking, a ordem é por nome (ninguém vê quem está na frente)
                let list = s.rankingsDisabled ? people.sorted { ($0.isMe ? 0 : 1, $0.name) < ($1.isMe ? 0 : 1, $1.name) } : people
                ForEach(Array(list.enumerated()), id: \.element.id) { i, r in
                    bar(name: r.isMe ? "Você" : r.name, avatar: r.avatar, value: r.score, goal: s.individualGoal, mine: r.isMe)
                    if i < list.count - 1 { GMDivider() }
                }
            }
        }
        if s.teamGoal > 0 && !teams.isEmpty {
            GMSection("Meta de cada time · \(league.scoring.format(s.teamGoal))") {
                ForEach(Array(teams.enumerated()), id: \.element.id) { i, t in
                    bar(name: t.name, avatar: t.form, value: t.score, goal: s.teamGoal, mine: t.isMine)
                    if i < teams.count - 1 { GMDivider() }
                }
            }
        }
    }

    private func bar(name: String, avatar: MonsterForm, value: Int, goal: Int, mine: Bool) -> some View {
        HStack(spacing: 12) {
            MonsterSprite(form: avatar).frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(name).font(.subheadline.weight(mine ? .bold : .semibold)).lineLimit(1)
                    Spacer()
                    Text(value >= goal ? "✅ \(league.scoring.short(value))" : "\(league.scoring.short(value)) / \(league.scoring.short(goal))")
                        .font(.caption.monospacedDigit()).foregroundStyle(mine ? Theme.accent : Theme.dim)
                }
                GMProgressBar(value: min(Double(max(value, 0)) / Double(goal), 1), height: 6)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
