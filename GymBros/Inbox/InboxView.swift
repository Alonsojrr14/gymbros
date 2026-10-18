import SwiftData
import SwiftUI

/// Caixa de entrada: aba Notificações (atividade social) e aba Mensagens (conversas com amigos)
struct InboxView: View {
    enum Tab: Hashable { case activity, messages }

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase
    @State private var store = InboxStore.shared
    @State private var friends = FriendsStore.shared
    @State private var permission = NotificationPermission.shared
    @State private var tab: Tab
    @State private var path: [String] = []
    @State private var composing = false
    @State private var done: Set<String> = []
    @State private var error: String?

    init(start: InboxRoute? = nil) {
        if case .conversation(let id) = start {
            _tab = State(initialValue: .messages)
            _path = State(initialValue: [id])
        } else {
            _tab = State(initialValue: start == .activity ? .activity : InboxStore.shared.unreadActivity == 0 && InboxStore.shared.unreadMessages > 0 ? .messages : .activity)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            GMScreen("Caixa de entrada", close: true, bottomInset: 40) {
                if tab == .messages {
                    GMIconButton(icon: "square.and.pencil", label: "Nova mensagem") { composing = true }
                }
            } content: {
                GMSegmented(options: [(Tab.activity, label("Notificações", store.unreadActivity)),
                                      (Tab.messages, label("Mensagens", store.unreadMessages))], selection: $tab)
                if !permission.allowed { NotificationPermissionCard() }
                if let e = store.lastError {
                    GMEmptyState(icon: "icloud.slash", title: "Caixa de entrada indisponível", message: e)
                } else if !store.loaded {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else if tab == .activity {
                    activityList
                } else {
                    conversationList
                }
                if let error { Text(error).font(.caption).foregroundStyle(Theme.danger) }
            }
            .navigationDestination(for: String.self) { ConversationView(peerID: $0) }
        }
        .task { await permission.refresh() }
        // Enquanto a tela está aberta, busca de tempos em tempos (com servidor, chegaria por push)
        .task(id: phase) {
            guard phase == .active else { return }
            while !Task.isCancelled {
                await store.refresh(context: context)
                try? await Task.sleep(for: .seconds(15))
            }
        }
        .onChange(of: tab) { old, _ in if old == .activity { store.markActivitySeen() } }
        .onDisappear { if tab == .activity { store.markActivitySeen() } }
        .onChange(of: store.route) { _, r in
            guard let r else { return }
            store.route = nil
            switch r {
            case .activity: tab = .activity; path = []
            case .conversation(let id): tab = .messages; path = [id]
            }
        }
        .gmSheet(isPresented: $composing) { close in
            NewMessageSheet { id in
                close()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { path = [id] }
            }
        }
    }

    private func label(_ title: String, _ n: Int) -> String { n > 0 ? "\(title) · \(n)" : title }

    // MARK: Notificações

    @ViewBuilder
    private var activityList: some View {
        let all = store.activity
        if all.isEmpty {
            GMEmptyState(icon: "bell", title: "Nada por aqui ainda",
                         message: "Quando alguém reagir aos seus check-ins, mandar força ou te chamar pra treinar, aparece aqui.")
        } else {
            let new = all.filter(store.isNew), old = all.filter { !store.isNew($0) }
            if !new.isEmpty { GMSection("Novas") { rows(new) } }
            if !old.isEmpty { GMSection(new.isEmpty ? nil : "Anteriores") { rows(old) } }
        }
    }

    private func rows(_ list: [InboxEvent]) -> some View {
        ForEach(list) { e in
            InboxEventRow(event: e, isNew: store.isNew(e), done: done.contains(e.id), answer: answer(e)) { action in
                Task { await perform(action, e) }
            }
            .contentShape(Rectangle())
            .onTapGesture { open(e) }
            if e.id != list.last?.id { GMDivider() }
        }
    }

    private func answer(_ e: InboxEvent) -> Bool? {
        guard e.kind == .invite, let id = e.targetID, let m = store.message(id) else { return nil }
        return store.answer(to: m)
    }

    private func open(_ e: InboxEvent) {
        switch e.kind {
        case .cheer, .invite, .inviteReply, .liveStart: path = [e.actorID]
        default: break
        }
    }

    private func perform(_ action: InboxEventRow.Action, _ e: InboxEvent) async {
        do {
            switch action {
            case .cheer: try await store.cheer(e.actorID)
            case .accept, .decline:
                if e.kind == .friendRequest {
                    if action == .accept { await friends.accept(e.actorID) } else { await friends.decline(e.actorID) }
                } else if let id = e.targetID, let m = store.message(id) {
                    try await store.reply(to: m, accepted: action == .accept)
                }
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.snappy) { _ = done.insert(e.id) }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: Mensagens

    @ViewBuilder
    private var conversationList: some View {
        let list = store.conversations
        if list.isEmpty {
            GMEmptyState(icon: "bubble.left.and.bubble.right", title: "Nenhuma conversa",
                         message: "Mande força, chame um amigo pra treinar junto ou só diga oi.")
            GMButton("Nova mensagem", icon: "square.and.pencil") { composing = true }
        } else {
            GMCard {
                ForEach(list) { c in
                    Button { path = [c.peer.id] } label: { ConversationRow(conversation: c) }
                        .buttonStyle(GMPress())
                    if c.id != list.last?.id { GMDivider() }
                }
            }
        }
    }
}

// MARK: - Linha de notificação

struct InboxEventRow: View {
    enum Action { case cheer, accept, decline }

    let event: InboxEvent
    let isNew: Bool
    /// Já respondeu/devolveu por aqui
    let done: Bool
    /// Resposta a um convite recebido
    let answer: Bool?
    let act: (Action) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            InboxAvatar(form: event.actorForm, badge: event.topic.icon, tint: event.topic.tint, live: event.kind == .liveStart)
            VStack(alignment: .leading, spacing: 6) {
                (Text(event.actorName).bold() + Text(" " + phrase))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                if !quote.isEmpty {
                    Text(quote).font(.caption).foregroundStyle(.white.opacity(0.85)).lineLimit(2)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Theme.raised, in: .rect(cornerRadius: Theme.radiusS))
                }
                Text(shortAgo(event.date)).font(.caption2).foregroundStyle(Theme.dim)
                actions
            }
            Spacer(minLength: 0)
            if isNew { Circle().fill(Theme.accent).frame(width: 8, height: 8).padding(.top, 6).accessibilityLabel("Nova") }
        }
        .accessibilityElement(children: .combine)
    }

    private var phrase: String {
        switch event.kind {
        case .reaction: "reagiu \(event.text) ao seu check-in"
        case .comment: "comentou no seu check-in"
        case .liveStart: "começou a treinar: \(event.text) · \(event.detail)"
        case .friendRequest: "quer ser seu amigo"
        case .cheer: "mandou força pra você 💪"
        case .invite: "te chamou pra treinar junto"
        case .inviteReply: event.accepted == true ? "topou treinar junto 🤝" : "não vai poder dessa vez"
        }
    }

    private var quote: String {
        switch event.kind {
        case .reaction: event.detail
        case .comment: "“\(event.text)” · \(event.detail)"
        case .cheer: event.text
        case .invite: event.detail + (event.text.isEmpty ? "" : "\n\(event.text)")
        default: ""
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch event.kind {
        case .cheer, .liveStart:
            if done {
                doneLabel("Força enviada")
            } else {
                GMButton(event.kind == .cheer ? "Devolver força 💪" : "Mandar força 💪", kind: .secondary, full: false, small: true) { act(.cheer) }
            }
        case .invite:
            if let answer {
                doneLabel(answer ? "Você topou" : "Você recusou")
            } else {
                HStack(spacing: 8) {
                    GMButton("Bora! 🤝", full: false, small: true) { act(.accept) }
                    GMButton("Hoje não", kind: .secondary, full: false, small: true) { act(.decline) }
                }
            }
        case .friendRequest:
            if done {
                doneLabel("Respondido")
            } else {
                HStack(spacing: 8) {
                    GMButton("Aceitar", full: false, small: true) { act(.accept) }
                    GMButton("Recusar", kind: .secondary, full: false, small: true) { act(.decline) }
                }
            }
        default:
            EmptyView()
        }
    }

    private func doneLabel(_ text: String) -> some View {
        Label(text, systemImage: "checkmark").font(.caption.bold()).foregroundStyle(Theme.accent)
    }
}

/// Bro da pessoa com o ícone do tipo de notificação no canto
struct InboxAvatar: View {
    let form: MonsterForm
    var badge: String?
    var tint: Color = Theme.accent
    var live = false
    var size: CGFloat = 46

    var body: some View {
        MonsterSprite(form: form)
            .frame(width: size * 0.74, height: size * 0.74)
            .frame(width: size, height: size)
            .background(Theme.raised, in: .circle)
            .overlay(Circle().stroke(live ? Theme.online : .clear, lineWidth: 2))
            .overlay(alignment: .bottomTrailing) {
                if let badge {
                    Image(systemName: badge)
                        .font(.system(size: size * 0.2, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: size * 0.42, height: size * 0.42)
                        .background(tint, in: .circle)
                        .overlay(Circle().stroke(Theme.card, lineWidth: 2))
                        .offset(x: 3, y: 3)
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Linha de conversa

struct ConversationRow: View {
    let conversation: Conversation

    private var live: LiveFriend? { FriendsLive.simulated.first { $0.id == conversation.peer.id && $0.isLive } }

    var body: some View {
        HStack(spacing: 12) {
            InboxAvatar(form: conversation.peer.form, live: live != nil, size: 50)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(conversation.peer.name).font(.subheadline.weight(.semibold))
                    if live != nil { GMOnlineDot(size: 6) }
                    Spacer()
                    Text(shortAgo(conversation.last.date)).font(.caption2).foregroundStyle(conversation.unread > 0 ? Theme.accent : Theme.dim)
                }
                HStack {
                    Text(conversation.last.preview)
                        .font(.caption)
                        .foregroundStyle(conversation.unread > 0 ? .white : Theme.dim)
                        .fontWeight(conversation.unread > 0 ? .semibold : .regular)
                        .lineLimit(1)
                    Spacer()
                    if conversation.unread > 0 { GMCountBadge(count: conversation.unread, tint: Theme.accent) }
                }
            }
        }
        .foregroundStyle(.white)
        .contentShape(Rectangle())
    }
}

extension DirectMessage {
    /// Uma linha na lista de conversas
    var preview: String {
        switch kind {
        case .text: (outgoing ? "Você: " : "") + text
        case .cheer: outgoing ? "Você mandou força 💪" : "💪 Mandou força" + (text.isEmpty ? "" : ": \(text)")
        case .invite: (outgoing ? "Você convidou: " : "Convite: ") + (invite.map { "\($0.kind.name) · \($0.whenText)" } ?? "treinar junto")
        case .inviteReply:
            accepted == true ? (outgoing ? "Você topou o convite 🤝" : "Topou o convite 🤝") : (outgoing ? "Você recusou o convite" : "Recusou o convite")
        }
    }
}

// MARK: - Nova mensagem

struct NewMessageSheet: View {
    let pick: (String) -> Void
    @State private var friends = FriendsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nova mensagem").font(.headline).frame(maxWidth: .infinity)
            if friends.friends.isEmpty {
                GMEmptyState(icon: "person.2", title: "Sem amigos ainda", message: "Mensagens são só entre amigos. Adicione alguém em Amigos.")
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(friends.friends) { f in
                            Button { pick(f.id) } label: {
                                HStack(spacing: 12) {
                                    InboxAvatar(form: f.form, size: 42)
                                    Text(f.name).font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.dim)
                                }
                                .foregroundStyle(.white)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(GMPress())
                        }
                    }
                }
                .frame(maxHeight: 380)
            }
        }
    }
}

/// "agora", "5 min", "3 h", "ontem", "12 out."
func shortAgo(_ date: Date, now: Date = .now) -> String {
    let s = now.timeIntervalSince(date)
    if s < 60 { return "agora" }
    if s < 3600 { return "\(Int(s / 60)) min" }
    if Calendar.current.isDateInToday(date) { return "\(Int(s / 3600)) h" }
    if Calendar.current.isDateInYesterday(date) { return "ontem" }
    return date.formatted(.dateTime.day().month(.abbreviated).locale(GMDateText.locale))
}
