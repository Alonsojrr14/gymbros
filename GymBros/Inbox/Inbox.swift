import Foundation
import Observation
import SwiftData

// Caixa de entrada: mensagens diretas (texto, força e convite para treinar junto) e a atividade social
// (reações e comentários nos seus check-ins, amigo que começou a treinar, pedido de amizade).
// Mesmo esquema das ligas e dos amigos: InboxBackend é o contrato com o servidor e os tipos têm o formato da API.
// Quem responde é escolhido em Backend.swift: MockInboxBackend (amigos simulados que respondem sozinhos)
// ou ServerInboxBackend (mensagens diretas precisam de servidor próprio; ver docs/cloudkit.md).
// O InboxStore guarda o estado, o que você já leu e o que já virou notificação (NotificationPrefs decide o que toca).

/// Tipo de mensagem direta
enum DirectKind: String, Codable, Sendable {
    case text
    /// "Mandar força": um empurrão de incentivo, com texto opcional
    case cheer
    /// Convite para treinar junto
    case invite
    /// Resposta a um convite (`replyTo` + `accepted`)
    case inviteReply
}

struct TrainInvite: Codable, Hashable, Sendable {
    var kindRaw: String
    var place: String
    /// Quando; nil = agora
    var when: Date?
    /// Local salvo de quem convidou, para o amigo abrir no mapa mesmo sem ter esse lugar
    var latitude: Double?
    var longitude: Double?

    var kind: ActivityKind { ActivityKind(rawValue: kindRaw) ?? .outro }

    var mapsURL: URL? {
        guard let latitude, let longitude else { return nil }
        var c = URLComponents(string: "https://maps.apple.com/")
        c?.queryItems = [URLQueryItem(name: "ll", value: "\(latitude),\(longitude)"), URLQueryItem(name: "q", value: place.isEmpty ? "Treino" : place)]
        return c?.url
    }

    /// "Agora", "Hoje, 19:00", "Amanhã, 07:00" ou "sáb., 25 out., 08:00"
    var whenText: String {
        guard let when else { return "Agora" }
        let cal = Calendar.current
        let time = when.formatted(.dateTime.hour().minute())
        if cal.isDateInToday(when) { return "Hoje, \(time)" }
        if cal.isDateInTomorrow(when) { return "Amanhã, \(time)" }
        return "\(when.formatted(.dateTime.weekday().day().month(.abbreviated))), \(time)"
    }
}

struct DirectMessage: Codable, Hashable, Identifiable, Sendable {
    let id: String
    /// A outra pessoa da conversa
    let peerID: String
    /// Mandada por você
    let outgoing: Bool
    let date: Date
    var kind: DirectKind = .text
    var text: String = ""
    var invite: TrainInvite?
    /// Resposta: id do convite respondido
    var replyTo: String?
    var accepted: Bool?

    var topic: NotificationTopic {
        switch kind {
        case .text: .messages
        case .cheer: .cheers
        case .invite, .inviteReply: .invites
        }
    }
}

/// Quem aparece na caixa de entrada (nome e bro atuais)
struct InboxPeer: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let formID: String

    var form: MonsterForm { MonsterForm.byID(formID) ?? .egg }
}

/// Uma linha da aba Notificações
struct InboxEvent: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// Reação (emoji) ou comentário num check-in seu; `id` é o do comentário, `targetID` o do check-in
        case reaction, comment
        /// Amigo começou a treinar; `text` = atividade, `detail` = lugar
        case liveStart
        case friendRequest
        /// Vindos das mensagens diretas
        case cheer, invite, inviteReply
        /// X1 (`targetID` = id do X1): desafio recebido, aceito, recusado, expirado e resultado
        case duelChallenge, duelAccepted, duelDeclined, duelExpired, duelResult
    }

    let id: String
    let kind: Kind
    let actorID: String
    let actorName: String
    let actorFormID: String
    let date: Date
    var text = ""
    var detail = ""
    var targetID: String?
    /// Resposta a convite ou a desafio: topou? (nil = ainda pendente)
    var accepted: Bool?

    var actorForm: MonsterForm { MonsterForm.byID(actorFormID) ?? .egg }

    var topic: NotificationTopic {
        switch kind {
        case .reaction, .comment: .reactions
        case .liveStart: .friendsTraining
        case .friendRequest: .friendRequests
        case .cheer: .cheers
        case .invite, .inviteReply: .invites
        case .duelChallenge, .duelAccepted, .duelDeclined, .duelExpired, .duelResult: .duels
        }
    }
}

struct InboxState: Codable, Sendable {
    var messages: [DirectMessage] = []
    var events: [InboxEvent] = []
    var peers: [InboxPeer] = []
}

enum InboxError: LocalizedError {
    case needsServer, notFriend, blocked

    var errorDescription: String? {
        switch self {
        case .needsServer: "Mensagens diretas precisam do servidor do GymBros, que ainda não está no ar."
        case .notFriend: "Só dá para mandar mensagem para amigos."
        case .blocked: "Você bloqueou essa pessoa."
        }
    }
}

protocol InboxBackend: Sendable {
    /// Mensagens e atividade recentes (o servidor guarda 90 dias)
    func fetch() async throws -> InboxState
    /// Entrega a mensagem; devolve como ficou no servidor
    func send(_ message: DirectMessage) async throws -> DirectMessage
}

// MARK: - Estado

/// Uma conversa: a pessoa e a última mensagem
struct Conversation: Identifiable, Hashable {
    let peer: InboxPeer
    let last: DirectMessage
    let unread: Int
    var id: String { peer.id }
}

/// Para onde um toque numa notificação leva
enum InboxRoute: Equatable {
    case activity
    case conversation(String)
}

@MainActor @Observable
final class InboxStore {
    static let shared = InboxStore()

    static let seenKey = "inboxSeenAt", readKey = "inboxReadUntil", notifiedKey = "inboxNotified", requestsKey = "inboxRequestsSeen",
               firstSeenKey = "inboxFirstSeen"
    /// Vão com a conta (AccountSync) e saem do aparelho ao sair
    static let defaultsKeys = [seenKey, readKey, notifiedKey, requestsKey, firstSeenKey]

    var backend: any InboxBackend = MockInboxBackend() {
        didSet { state = InboxState() }
    }
    var access: AccessStore = .shared
    var moderation: ModerationStore = .shared
    /// Pedidos de amizade pendentes (vêm do FriendsStore)
    var friendRequests: @MainActor () -> [RemoteFriend] = { FriendsStore.shared.incoming }
    var friendIDs: @MainActor () -> Set<String> = { FriendsStore.shared.friendIDs }
    /// X1 que envolvem você, já atualizados do servidor das ligas (trocado nos testes)
    var duelNotices: @MainActor () async -> [DuelNotice] = { await InboxStore.loadDuels() }
    /// Entrega uma notificação local (trocado nos testes)
    var notify: @MainActor (InboxNotice) -> Void = { SocialNotifier.deliver($0) }

    private let defaults: UserDefaults
    private(set) var state = InboxState()
    /// Eventos de X1 da última busca
    private(set) var duelEvents: [InboxEvent] = []
    private(set) var lastError: String?
    private(set) var loaded = false
    /// Até quando a aba Notificações foi vista
    private(set) var seenAt: Date
    /// Por conversa: até quando você leu
    private(set) var readUntil: [String: Date]
    /// Conversa aberta na tela: o que chega nela não vira notificação e já conta como lido
    var openPeer: String? {
        didSet { if let openPeer { markRead(openPeer) } }
    }
    /// Toque numa notificação do sistema
    var route: InboxRoute?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        seenAt = defaults.object(forKey: Self.seenKey) as? Date ?? .distantPast
        readUntil = (defaults.dictionary(forKey: Self.readKey) as? [String: Double] ?? [:]).mapValues(Date.init(timeIntervalSince1970:))
    }

    // MARK: Leitura

    func peer(_ id: String) -> InboxPeer {
        if let p = state.peers.first(where: { $0.id == id }) { return p }
        if let f = FriendsStore.shared.friends.first(where: { $0.id == id }) { return InboxPeer(id: f.id, name: f.name, formID: f.formID) }
        return InboxPeer(id: id, name: "Treinador", formID: MonsterForm.egg.id)
    }

    /// Sem quem você bloqueou e sem o que você denunciou
    private var visibleMessages: [DirectMessage] {
        state.messages.filter { !moderation.isBlocked($0.peerID) && ($0.outgoing || !moderation.isHidden(.directMessage, $0.id)) }
    }

    func messages(with peerID: String) -> [DirectMessage] {
        visibleMessages.filter { $0.peerID == peerID }.sorted { $0.date < $1.date }
    }

    var conversations: [Conversation] {
        Dictionary(grouping: visibleMessages, by: \.peerID).compactMap { id, list in
            guard let last = list.max(by: { $0.date < $1.date }) else { return nil }
            return Conversation(peer: peer(id), last: last, unread: unread(in: list, peer: id))
        }
        .sorted { $0.last.date > $1.last.date }
    }

    /// Notificações: atividade do servidor, força e convites recebidos e pedidos de amizade, mais novas primeiro
    var activity: [InboxEvent] {
        var out = (state.events + duelEvents).filter { !moderation.isBlocked($0.actorID) && !moderation.isHidden(.comment, $0.id) }
        for m in visibleMessages where !m.outgoing && m.kind != .text {
            let p = peer(m.peerID)
            let kind: InboxEvent.Kind = m.kind == .cheer ? .cheer : m.kind == .invite ? .invite : .inviteReply
            out.append(InboxEvent(id: "dm-\(m.id)", kind: kind, actorID: p.id, actorName: p.name, actorFormID: p.formID, date: m.date,
                                  text: m.text, detail: m.invite.map { "\($0.kind.name) · \($0.place)" } ?? "", targetID: m.id,
                                  accepted: m.accepted))
        }
        let firstSeen = requestsSeen
        for f in friendRequests() {
            out.append(InboxEvent(id: "request-\(f.id)", kind: .friendRequest, actorID: f.id, actorName: f.name, actorFormID: f.formID,
                                  date: firstSeen[f.id] ?? .now))
        }
        return out.sorted { $0.date > $1.date }
    }

    private func unread(in list: [DirectMessage], peer: String) -> Int {
        guard openPeer != peer else { return 0 }
        let since = readUntil[peer] ?? .distantPast
        return list.filter { !$0.outgoing && $0.date > since }.count
    }

    func unread(_ peerID: String) -> Int { unread(in: messages(with: peerID), peer: peerID) }

    var unreadMessages: Int { conversations.reduce(0) { $0 + $1.unread } }

    /// Força e convites contam nas mensagens, não duas vezes
    var unreadActivity: Int { activity.filter { $0.date > seenAt && !$0.id.hasPrefix("dm-") }.count }

    var badge: Int { unreadMessages + unreadActivity }

    func isNew(_ e: InboxEvent) -> Bool { e.date > seenAt }

    // MARK: Convites

    /// Resposta ao convite: true topou, false recusou, nil sem resposta
    func answer(to invite: DirectMessage) -> Bool? {
        state.messages.last { $0.kind == .inviteReply && $0.replyTo == invite.id }?.accepted
    }

    func message(_ id: String) -> DirectMessage? { state.messages.first { $0.id == id } }

    // MARK: Lido

    func markActivitySeen() {
        seenAt = .now
        defaults.set(seenAt, forKey: Self.seenKey)
    }

    func markRead(_ peerID: String) {
        let last = state.messages.filter { $0.peerID == peerID }.map(\.date).max() ?? .now
        readUntil[peerID] = max(last, .now)
        defaults.set(readUntil.mapValues(\.timeIntervalSince1970), forKey: Self.readKey)
    }

    // MARK: Servidor

    private var refreshing = false

    /// Busca o que chegou, aplica reações nos seus check-ins e toca as notificações novas
    func refresh(context: ModelContext? = nil) async {
        guard AuthStore.shared.isSignedIn || !(backend is MockInboxBackend), !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            state = try await backend.fetch()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        loaded = true
        duelEvents = Self.events(from: await duelNotices(), firstSeen: firstSeen)
        rememberRequests()
        if let context { applyReactions(context) }
        deliverNew()
    }

    // MARK: X1

    /// Atualiza os X1 e devolve os seus (com placar dos encerrados)
    static func loadDuels() async -> [DuelNotice] {
        await DuelStore.shared.refresh()
        return DuelStore.shared.notices()
    }

    /// Quando cada evento sem data própria (recusa) apareceu pela primeira vez
    private func firstSeen(_ id: String) -> Date {
        var seen = defaults.dictionary(forKey: Self.firstSeenKey) as? [String: Double] ?? [:]
        if let t = seen[id] { return Date(timeIntervalSince1970: t) }
        seen[id] = Date.now.timeIntervalSince1970
        defaults.set(seen, forKey: Self.firstSeenKey)
        return .now
    }

    /// Desafio recebido, aceito, resultado (os dois lados); recusado e expirado só para quem desafiou
    static func events(from duels: [DuelNotice], firstSeen: (String) -> Date) -> [InboxEvent] {
        var out: [InboxEvent] = []
        for d in duels {
            func event(_ prefix: String, _ kind: InboxEvent.Kind, _ date: Date, text: String = "", accepted: Bool? = nil) -> InboxEvent {
                InboxEvent(id: "x1-\(prefix)-\(d.id)", kind: kind, actorID: d.opponent.id, actorName: d.opponent.name, actorFormID: d.opponent.formID,
                           date: date, text: text, detail: "X1 de \(d.metric.name.lowercased())", targetID: d.id, accepted: accepted)
            }
            if !d.iChallenged {
                let answer: Bool?
                switch d.phase {
                case .pending: answer = nil
                case .active, .finished: answer = true
                case .declined, .expired: answer = false
                }
                out.append(event("recebido", .duelChallenge, d.createdAt, text: d.phase == .expired ? "expirou" : "", accepted: answer))
            }
            if d.iChallenged, let at = d.acceptedAt { out.append(event("aceito", .duelAccepted, at)) }
            switch d.phase {
            case .declined where d.iChallenged: out.append(event("recusado", .duelDeclined, firstSeen("x1-recusado-\(d.id)")))
            case .expired where d.iChallenged: out.append(event("expirado", .duelExpired, d.expiresAt))
            case .finished(let ended): out.append(event("resultado", .duelResult, ended, text: d.resultText ?? ""))
            default: break
            }
        }
        return out
    }

    /// Responde a um desafio recebido pela linha da notificação
    func answerDuel(_ e: InboxEvent, accept: Bool, monster: UUID? = nil) async throws {
        guard let id = e.targetID, let duel = DuelStore.shared.duel(id) else { throw DuelRefusal.notPending }
        try await DuelStore.shared.respond(duel, accept: accept, monster: monster)
        await refresh()
    }

    /// Primeira vez que cada pedido de amizade apareceu (o servidor de amigos não manda data)
    private var requestsSeen: [String: Date] {
        (defaults.dictionary(forKey: Self.requestsKey) as? [String: Double] ?? [:]).mapValues(Date.init(timeIntervalSince1970:))
    }

    private func rememberRequests() {
        var seen = requestsSeen
        let ids = Set(friendRequests().map(\.id))
        for id in ids where seen[id] == nil { seen[id] = .now }
        seen = seen.filter { ids.contains($0.key) }
        defaults.set(seen.mapValues(\.timeIntervalSince1970), forKey: Self.requestsKey)
    }

    /// Reações e comentários dos outros nos seus check-ins viram comentários de verdade (aparecem no check-in)
    private func applyReactions(_ context: ModelContext) {
        let incoming = state.events.filter { ($0.kind == .reaction || $0.kind == .comment) && $0.targetID != nil }
        guard !incoming.isEmpty else { return }
        let existing = Set(((try? context.fetch(FetchDescriptor<CheckInComment>())) ?? []).map(\.uuid.uuidString))
        var changed = false
        for e in incoming where !existing.contains(e.id) {
            guard let uuid = UUID(uuidString: e.id), let target = e.targetID else { continue }
            let c = CheckInComment(itemID: target, text: e.text, authorID: e.actorID, authorName: e.actorName)
            c.uuid = uuid
            c.date = e.date
            context.insert(c)
            changed = true
        }
        if changed { try? context.save() }
    }

    /// O que ainda não virou notificação. Na primeira busca da conta só marca (não toca o histórico inteiro).
    private func deliverNew() {
        let first = defaults.object(forKey: Self.notifiedKey) == nil
        var notified = Set(defaults.stringArray(forKey: Self.notifiedKey) ?? [])
        let recent = Date.now.addingTimeInterval(-6 * 3600)
        var notices: [InboxNotice] = []
        for m in visibleMessages where !m.outgoing && !notified.contains(m.id) {
            notified.insert(m.id)
            guard !first, m.date > recent, openPeer != m.peerID else { continue }
            notices.append(InboxNotice(message: m, peer: peer(m.peerID)))
        }
        for e in activity where !e.id.hasPrefix("dm-") && !notified.contains(e.id) {
            notified.insert(e.id)
            guard !first, e.date > recent else { continue }
            notices.append(InboxNotice(event: e))
        }
        // Só os últimos (a lista não cresce para sempre)
        let keep = Set(state.messages.map(\.id) + activity.map(\.id))
        defaults.set(Array(notified.intersection(keep).union(notices.map(\.id))), forKey: Self.notifiedKey)
        for n in notices where NotificationPrefs.isOn(n.topic, defaults: defaults) { notify(n) }
    }

    // MARK: Enviar

    @discardableResult
    func send(_ kind: DirectKind, to peerID: String, text: String = "", invite: TrainInvite? = nil, replyTo: String? = nil,
              accepted: Bool? = nil) async throws -> DirectMessage {
        try access.authorize(.directMessagesSend)
        guard !moderation.isBlocked(peerID) else { throw InboxError.blocked }
        // Responder a quem já falou com você vale mesmo sem amizade (ex.: amizade desfeita depois)
        guard friendIDs().contains(peerID) || state.messages.contains(where: { $0.peerID == peerID }) else { throw InboxError.notFriend }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ContentFilter.allows(t) else { throw ContentFilterError.blocked }
        let m = DirectMessage(id: UUID().uuidString, peerID: peerID, outgoing: true, date: .now, kind: kind, text: t, invite: invite,
                              replyTo: replyTo, accepted: accepted)
        let sent = try await backend.send(m)
        state.messages.append(sent)
        markRead(peerID)
        // Amigos simulados respondem em alguns segundos; o servidor de verdade avisaria por push
        Task { [weak self] in
            for delay in [4, 9] {
                try? await Task.sleep(for: .seconds(delay))
                await self?.refresh()
            }
        }
        return sent
    }

    func cheer(_ peerID: String, text: String = "") async throws { try await send(.cheer, to: peerID, text: text) }

    func invite(_ peerID: String, _ invite: TrainInvite, text: String = "") async throws {
        try await send(.invite, to: peerID, text: text, invite: invite)
    }

    func reply(to invite: DirectMessage, accepted: Bool) async throws {
        try await send(.inviteReply, to: invite.peerID, replyTo: invite.id, accepted: accepted)
    }

    /// Esquece o que veio do servidor (saiu ou excluiu a conta)
    func reset() {
        state = InboxState()
        duelEvents = []
        loaded = false
        lastError = nil
        openPeer = nil
        route = nil
        seenAt = defaults.object(forKey: Self.seenKey) as? Date ?? .distantPast
        readUntil = (defaults.dictionary(forKey: Self.readKey) as? [String: Double] ?? [:]).mapValues(Date.init(timeIntervalSince1970:))
    }
}

enum ContentFilterError: LocalizedError {
    case blocked
    var errorDescription: String? { "Essa mensagem tem palavras que não são permitidas." }
}

// MARK: - Servidor de verdade

/// Mensagens diretas não podem morar no banco público do CloudKit: qualquer conta do iCloud leria as conversas.
/// O caminho é um servidor próprio (HTTPS, token da sessão do AuthBackend, mensagens cifradas em repouso, push pelo APNs
/// filtrado pelas preferências de notificação). Até lá, no modo `.cloudKit` a caixa de entrada mostra o aviso.
struct ServerInboxBackend: InboxBackend {
    func fetch() async throws -> InboxState { throw InboxError.needsServer }
    func send(_ message: DirectMessage) async throws -> DirectMessage { throw InboxError.needsServer }
}

extension UUID {
    /// Sempre o mesmo UUID para o mesmo texto (ids estáveis no servidor simulado)
    init(seed: String) {
        var a = SeededRandom(seed: seed), bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<16 { bytes[i] = UInt8(a.next() * 256) & 0xFF }
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        self = UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
