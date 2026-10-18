import SwiftData
import SwiftUI

/// Mural da liga: recados dos participantes (com o bro de cada um) e os seus.
/// Os seus ficam no aparelho até o servidor aceitar (LeagueMessage.syncedAt).
struct LeagueMuralView: View {
    let league: League
    let avatar: MonsterForm
    @Environment(\.modelContext) private var context
    @Query(sort: \LeagueMessage.date, order: .reverse) private var allMessages: [LeagueMessage]
    @AppStorage("trainerName") private var trainerName = ""
    @State private var text = ""
    @State private var menu: LeagueMessage?
    @State private var moderation: ModerationRequest?
    @State private var blocked = false
    @State private var terms = TermsGate()

    private struct Line: Identifiable {
        let id: String
        var memberID = "me"
        let name: String
        let form: MonsterForm
        let isMe: Bool
        let date: Date
        let text: String
        var pending = false
        var mine: LeagueMessage?
    }

    var body: some View {
        let lines = merged
        VStack(alignment: .leading, spacing: 16) {
            if !league.isOver { composer }
            if lines.isEmpty {
                GMEmptyState(icon: "bubble.left.and.bubble.right", title: "Mural vazio", message: "Mande o primeiro recado pra galera da liga.")
            }
            let cal = Calendar.current
            let days = Dictionary(grouping: lines.prefix(150)) { cal.startOfDay(for: $0.date) }
            ForEach(days.keys.sorted(by: >), id: \.self) { day in
                VStack(alignment: .leading, spacing: 10) {
                    Text(dayTitle(day)).font(.headline)
                    ForEach(days[day]!.sorted { $0.date > $1.date }) { bubble($0) }
                }
            }
        }
        .gmActions(isPresented: Binding(get: { menu != nil }, set: { if !$0 { menu = nil } }), title: "Recado", actions: [
            GMAction("Apagar recado", icon: "trash", destructive: true) {
                if let m = menu { context.delete(m); try? context.save() }
            }
        ])
        .moderation($moderation)
        .termsGate($terms)
        .onChange(of: text) { blocked = false }
    }

    private var merged: [Line] {
        let remote = LeagueRemoteStore.shared.remote(league)
        let others = ModerationStore.shared.visible(remote.messages).compactMap { m -> Line? in
            guard let who = remote.member(m.memberID) else { return nil }
            return Line(id: m.id, memberID: who.id, name: who.name, form: who.form, isMe: false, date: m.date, text: m.text)
        }
        let mine = allMessages.filter { $0.leagueUUID == league.uuid }.map {
            Line(id: $0.uuid.uuidString, name: trainerName.isEmpty ? "Você" : trainerName, form: avatar, isMe: true, date: $0.date,
                 text: $0.text, pending: $0.syncedAt == nil, mine: $0)
        }
        return others + mine
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            composerField
            if blocked { ContentBlockedNote() }
        }
    }

    private var composerField: some View {
        HStack(alignment: .bottom, spacing: 8) {
            MonsterSprite(form: avatar).frame(width: 36, height: 36)
            GMTextField(placeholder: "Escrever no mural…", text: $text, axis: .vertical)
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 40, height: 40)
                    .accessibilityLabel("Enviar")
                    .background(canSend ? Theme.accent : Theme.raised, in: .circle)
                    .foregroundStyle(canSend ? .black : Theme.dim)
            }
            .buttonStyle(GMPress())
            .disabled(!canSend)
        }
    }

    private var canSend: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func send() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        guard AccessStore.shared.can(.messagesPublish) else { return }
        guard ContentFilter.allows(t) else { blocked = true; return }
        terms.run { publish(t) }
    }

    private func publish(_ t: String) {
        context.insert(LeagueMessage(leagueUUID: league.uuid, text: t))
        try? context.save()
        text = ""
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task { await LeagueRemoteStore.shared.flush(context: context) }
    }

    private func bubble(_ l: Line) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            if l.isMe { Spacer(minLength: 40) } else { MonsterSprite(form: l.form).frame(width: 32, height: 32) }
            VStack(alignment: l.isMe ? .trailing : .leading, spacing: 3) {
                if !l.isMe { Text(l.name).font(.caption.weight(.bold)).foregroundStyle(Theme.dim) }
                Text(l.text)
                    .font(.subheadline)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(l.isMe ? Theme.accent : Theme.card, in: .rect(cornerRadius: Theme.radiusL))
                    .foregroundStyle(l.isMe ? .black : .white)
                HStack(spacing: 4) {
                    if l.pending { Image(systemName: "clock") }
                    Text(l.date.formatted(.dateTime.hour().minute()))
                }
                .font(.caption2.monospacedDigit()).foregroundStyle(Theme.dim)
            }
            .onLongPressGesture {
                if let m = l.mine {
                    menu = m
                } else if !l.isMe {
                    moderation = ModerationRequest(target: ModerationTarget(userID: l.memberID, userName: l.name, content: .message, id: l.id))
                }
            }
            if l.isMe { MonsterSprite(form: l.form).frame(width: 32, height: 32) } else { Spacer(minLength: 40) }
        }
    }

    private func dayTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Hoje" }
        if cal.isDateInYesterday(day) { return "Ontem" }
        let s = day.formatted(.dateTime.weekday(.wide).day().month(.wide))
        return s.prefix(1).uppercased() + s.dropFirst()
    }
}
