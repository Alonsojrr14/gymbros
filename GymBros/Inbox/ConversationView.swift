import SwiftUI

/// Conversa com um amigo: mensagens, força e convites para treinar junto
struct ConversationView: View {
    let peerID: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var store = InboxStore.shared
    @State private var text = ""
    @State private var sending = false
    @State private var error: String?
    @State private var blockedWord = false
    @State private var inviting = false
    @State private var dueling = false
    @State private var menu = false
    @State private var profile: RemoteFriend?
    @State private var moderation: ModerationRequest?
    @State private var terms = TermsGate()
    @FocusState private var typing: Bool

    private var peer: InboxPeer { store.peer(peerID) }
    private var live: LiveFriend? { FriendsLive.simulated.first { $0.id == peerID && $0.isLive } }
    private var messages: [DirectMessage] { store.messages(with: peerID) }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVStack(spacing: 8) {
                    if messages.isEmpty { emptyIntro }
                    ForEach(Array(messages.enumerated()), id: \.element.id) { i, m in
                        if i == 0 || !Calendar.current.isDate(messages[i - 1].date, inSameDayAs: m.date) {
                            Text(dayText(m.date)).font(.caption2.bold()).foregroundStyle(Theme.dim).padding(.vertical, 8)
                        }
                        MessageView(message: m, peer: peer, answer: m.kind == .invite ? store.answer(to: m) : nil) { yes in
                            run { try await store.reply(to: m, accepted: yes) }
                        }
                        .id(m.id)
                        // A dos outros: denunciar ou bloquear quem mandou
                        .onLongPressGesture {
                            guard !m.outgoing else { return }
                            moderation = ModerationRequest(target: ModerationTarget(userID: peerID, userName: peer.name,
                                                                                     content: .directMessage, id: m.id))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            composer
        }
        .background(Theme.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { store.openPeer = peerID }
        .onDisappear { if store.openPeer == peerID { store.openPeer = nil } }
        // Chegou algo com a conversa aberta: já conta como lido
        .onChange(of: messages.count) { store.markRead(peerID) }
        .task(id: phase) {
            guard phase == .active else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                await store.refresh()
            }
        }
        .gmSheet(isPresented: $inviting) { close in
            InviteComposer(peerName: peer.name, suggestedKind: live?.kind, suggestedPlace: live?.place) { invite, note in
                close()
                run { try await store.invite(peerID, invite, text: note) }
            }
        }
        .gmActions(isPresented: $menu, title: peer.name, actions: menuActions)
        .gmSheet(isPresented: $dueling) { close in
            DuelComposer(opponent: DuelPerson(id: peer.id, name: peer.name, formID: peer.formID)) { close() }
        }
        .gmModal(item: $profile) { FriendProfileView(friend: $0) }
        .moderation($moderation) { dismiss() }
        .termsGate($terms)
        .onChange(of: text) { blockedWord = false }
    }

    // MARK: Cabeçalho

    private var header: some View {
        HStack(spacing: 10) {
            GMIconButton(icon: "chevron.left") { dismiss() }
            Button { openProfile() } label: {
                HStack(spacing: 10) {
                    InboxAvatar(form: peer.form, live: live != nil, size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(peer.name).font(.headline)
                        if let live {
                            HStack(spacing: 4) {
                                GMOnlineDot(size: 6)
                                Text("\(live.kind.name) agora · \(live.place)").font(.caption2.weight(.semibold)).foregroundStyle(live.color)
                            }
                        } else {
                            Text(peer.form.name).font(.caption2).foregroundStyle(Theme.dim)
                        }
                    }
                }
                .foregroundStyle(.white)
            }
            .buttonStyle(GMPress())
            Spacer()
            GMIconButton(icon: "ellipsis") { menu = true }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { GMDivider() }
    }

    private var menuActions: [GMAction] {
        [GMAction("Ver perfil", icon: "person.crop.circle") { openProfile() }]
            + ModerationTarget(userID: peerID, userName: peer.name).actions { moderation = $0 }
    }

    private func openProfile() {
        profile = FriendsStore.shared.friends.first { $0.id == peerID } ?? RemoteFriend(id: peerID, name: peer.name, formID: peer.formID, code: "")
    }

    private var emptyIntro: some View {
        VStack(spacing: 10) {
            InboxAvatar(form: peer.form, size: 90)
            Text(peer.name).font(.title3.bold())
            Text("Mande força, chame pra treinar junto ou só diga oi.").font(.subheadline).foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
    }

    // MARK: Escrever

    private var composer: some View {
        VStack(spacing: 10) {
            if blockedWord { ContentBlockedNote() }
            if let error { Text(error).font(.caption).foregroundStyle(Theme.danger).frame(maxWidth: .infinity, alignment: .leading) }
            HStack(spacing: 8) {
                quick("Mandar força", icon: "bolt.heart.fill", tint: Theme.accent) { run { try await store.cheer(peerID) } }
                quick("Treinar junto", icon: "figure.2", tint: Attribute.agilidade.color) { inviting = true }
                quick("X1", icon: "bolt.shield.fill", tint: Theme.trophy) { dueling = true }
                Spacer()
            }
            HStack(spacing: 10) {
                HStack {
                    TextField("", text: $text, prompt: Text("Mensagem…").foregroundStyle(Theme.dim), axis: .vertical)
                        .lineLimit(1...5)
                        .focused($typing)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(Theme.card, in: .capsule)
                let empty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                Button { sendText() } label: {
                    Image(systemName: "arrow.up")
                        .font(.headline.bold())
                        .frame(width: 46, height: 46)
                        .background(empty ? Theme.raised : Theme.accent, in: .circle)
                        .foregroundStyle(empty ? Theme.dim : .black)
                }
                .buttonStyle(GMPress())
                .disabled(empty || sending)
                .accessibilityLabel("Enviar")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Theme.bg)
        .overlay(alignment: .top) { GMDivider() }
    }

    private func quick(_ title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption.bold())
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(tint.opacity(0.15), in: .capsule)
                .overlay(Capsule().stroke(tint.opacity(0.5), lineWidth: 1))
                .foregroundStyle(tint)
        }
        .buttonStyle(GMPress())
        .disabled(sending)
    }

    private func sendText() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        guard ContentFilter.allows(t) else { blockedWord = true; return }
        run {
            try await store.send(.text, to: peerID, text: t)
            text = ""
        }
    }

    /// Envia depois do aceite dos termos (conteúdo de usuário), com retorno tátil e erro na tela
    private func run(_ action: @escaping () async throws -> Void) {
        terms.run {
            Task {
                sending = true
                defer { sending = false }
                do {
                    try await action()
                    error = nil
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                } catch {
                    self.error = error.localizedDescription
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }

    private func dayText(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Hoje" }
        if cal.isDateInYesterday(d) { return "Ontem" }
        return d.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(GMDateText.locale))
    }
}

// MARK: - Mensagem

private struct MessageView: View {
    let message: DirectMessage
    let peer: InboxPeer
    let answer: Bool?
    let reply: (Bool) -> Void

    var body: some View {
        switch message.kind {
        case .text: bubble
        case .cheer: cheer
        case .invite: invite
        case .inviteReply: inviteReply
        }
    }

    private var time: some View {
        Text(message.date.formatted(.dateTime.hour().minute())).font(.caption2).foregroundStyle(Theme.dim)
    }

    private var bubble: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if message.outgoing { Spacer(minLength: 60); time }
            Text(message.text)
                .font(.subheadline)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(message.outgoing ? Theme.accent : Theme.card,
                            in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: message.outgoing ? 18 : 6,
                                                       bottomTrailingRadius: message.outgoing ? 6 : 18, topTrailingRadius: 18))
                .foregroundStyle(message.outgoing ? .black : .white)
                .textSelection(.enabled)
            if !message.outgoing { time; Spacer(minLength: 60) }
        }
    }

    /// Força: cartão de destaque com o raio e a cor do app
    private var cheer: some View {
        HStack {
            if message.outgoing { Spacer(minLength: 40) }
            VStack(alignment: message.outgoing ? .trailing : .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text("💪").font(.system(size: 34))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(message.outgoing ? "Você mandou força" : "\(peer.name) mandou força").font(.subheadline.bold())
                        if !message.text.isEmpty { Text(message.text).font(.caption).foregroundStyle(.white.opacity(0.85)) }
                    }
                }
                time
            }
            .padding(14)
            .background(LinearGradient(colors: [Theme.accent.opacity(0.28), Theme.accent.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: .rect(cornerRadius: Theme.radiusL))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusL).stroke(Theme.accent.opacity(0.5), lineWidth: 1))
            if !message.outgoing { Spacer(minLength: 40) }
        }
    }

    private var invite: some View {
        let inv = message.invite ?? TrainInvite(kindRaw: ActivityKind.outro.rawValue, place: "", when: nil)
        let color = LiveFriend.color(inv.kind)
        return HStack {
            if message.outgoing { Spacer(minLength: 30) }
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: inv.kind.symbol)
                        .font(.title3.bold())
                        .frame(width: 46, height: 46)
                        .background(color, in: .circle)
                        .foregroundStyle(.black)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(message.outgoing ? "Você chamou pra treinar junto" : "Bora treinar junto?").font(.subheadline.bold())
                        Text(inv.kind.name).font(.caption.bold()).foregroundStyle(color)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    if let url = inv.mapsURL {
                        Link(destination: url) {
                            Label {
                                HStack(spacing: 6) {
                                    Text(inv.place).underline()
                                    Text("Ver no mapa").foregroundStyle(color)
                                }
                            } icon: { Image(systemName: "mappin.and.ellipse") }
                        }
                        .tint(.white)
                    } else if !inv.place.isEmpty {
                        Label(inv.place, systemImage: "mappin.and.ellipse")
                    }
                    Label(inv.whenText, systemImage: "clock")
                }
                .font(.caption.weight(.semibold))
                if !message.text.isEmpty { Text(message.text).font(.caption).foregroundStyle(.white.opacity(0.85)) }
                status
            }
            .padding(14)
            .frame(maxWidth: 290, alignment: .leading)
            .background(color.opacity(0.1), in: .rect(cornerRadius: Theme.radiusL))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusL).stroke(color.opacity(0.5), lineWidth: 1.5))
            if !message.outgoing { Spacer(minLength: 30) }
        }
    }

    @ViewBuilder
    private var status: some View {
        if let answer {
            Label(answer ? (message.outgoing ? "\(peer.name) topou" : "Você topou") : (message.outgoing ? "\(peer.name) não vai" : "Você recusou"),
                  systemImage: answer ? "checkmark.circle.fill" : "xmark.circle")
                .font(.caption.bold())
                .foregroundStyle(answer ? Theme.accent : Theme.dim)
        } else if message.outgoing {
            Label("Esperando resposta", systemImage: "hourglass").font(.caption.bold()).foregroundStyle(Theme.dim)
        } else {
            HStack(spacing: 8) {
                GMButton("Bora! 🤝", small: true) { reply(true) }
                GMButton("Hoje não", kind: .secondary, small: true) { reply(false) }
            }
        }
    }

    private var inviteReply: some View {
        let who = message.outgoing ? "Você" : peer.name
        return Label(message.accepted == true ? "\(who) topou o convite" : "\(who) recusou o convite",
                     systemImage: message.accepted == true ? "hand.thumbsup.fill" : "hand.raised")
            .font(.caption.bold())
            .foregroundStyle(message.accepted == true ? Theme.accent : Theme.dim)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Theme.raised, in: .capsule)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Convite

struct InviteComposer: View {
    let peerName: String
    var suggestedKind: ActivityKind?
    var suggestedPlace: String?
    let send: (TrainInvite, String) -> Void

    enum When: Hashable { case now, today, tomorrow, other }

    @State private var kind: ActivityKind = .musculacao
    @State private var place = ""
    @State private var gym: Gym?
    @State private var when: When = .now
    @State private var day = Calendar.current.date(byAdding: .day, value: 2, to: .now) ?? .now
    @State private var time = Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: .now) ?? .now
    @State private var note = ""

    private let gyms = GymLocation.shared.gyms

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Treinar junto com \(peerName)").font(.headline).frame(maxWidth: .infinity)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ActivityKind.allCases.filter { $0 != .outro }, id: \.self) { k in
                        GMChip(title: k.name, icon: k.symbol, selected: kind == k) { kind = k }
                    }
                }
            }
            if !gyms.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(gyms) { g in
                            GMChip(title: g.name, icon: "mappin.and.ellipse", selected: gym?.uuid == g.uuid) { pick(g) }
                        }
                    }
                }
            }
            GMTextField(placeholder: "Onde? (academia, parque…)", text: $place, capitalization: .words)
            GMChoiceChips(options: [(When.now, "Agora"), (When.today, "Hoje"), (When.tomorrow, "Amanhã"), (When.other, "Outro dia")], selection: $when)
            if when == .other { GMDateField(date: $day, limitToNow: false, minDate: .now) }
            if when != .now { GMTimeField(date: $time) }
            if isPast {
                Label("Esse horário já passou", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.bold()).foregroundStyle(Theme.warning)
            }
            GMTextField(placeholder: "Recado (opcional)", text: $note)
            if !ContentFilter.allows(place, note) { ContentBlockedNote() }
            GMButton("Enviar convite", icon: "paperplane.fill", enabled: ContentFilter.allows(place, note) && !isPast) {
                let trimmed = place.trimmingCharacters(in: .whitespaces)
                let pinned = gym.flatMap { $0.name == trimmed ? $0 : nil }
                send(TrainInvite(kindRaw: kind.rawValue, place: trimmed, when: date,
                                 latitude: pinned?.latitude, longitude: pinned?.longitude), note)
            }
        }
        .onChange(of: place) { _, new in
            if let g = gym, g.name != new.trimmingCharacters(in: .whitespaces) { gym = nil }
        }
        .onAppear {
            if let suggestedKind { kind = suggestedKind }
            if let suggestedPlace {
                place = suggestedPlace
                gym = gyms.first { $0.name == suggestedPlace }
            } else if let inside = GymLocation.shared.insideGym {
                pick(inside)
            }
        }
    }

    private func pick(_ g: Gym) {
        gym = g
        place = g.name
    }

    private var isPast: Bool { date.map { $0 < .now } ?? false }

    private var date: Date? {
        let cal = Calendar.current
        let base: Date
        switch when {
        case .now: return nil
        case .today: base = .now
        case .tomorrow: base = cal.date(byAdding: .day, value: 1, to: .now) ?? .now
        case .other: base = day
        }
        let c = cal.dateComponents([.hour, .minute], from: time)
        return cal.date(bySettingHour: c.hour ?? 19, minute: c.minute ?? 0, second: 0, of: base)
    }
}
