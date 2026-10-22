import Foundation
import Observation

// Denunciar e bloquear (conteúdo gerado por usuários). ModerationBackend é o contrato com o servidor;
// quem responde é escolhido em Backend.swift: MockModerationBackend (guarda denúncias e bloqueios no aparelho)
// ou CloudKitModerationBackend. O ModerationStore decide o que some da tela: o que você denunciou some na hora
// só para você; quem você bloqueou some de feeds, comentários, mural, amigos, sugestões, mapa e perfil.
// A pontuação das ligas não muda (ranking é regra do jogo, não conteúdo).

struct ReportedContent: Codable, Hashable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case checkIn, comment, message, profile, photo, directMessage

        var name: String {
            switch self {
            case .checkIn: "check-in"
            case .comment: "comentário"
            case .message: "recado"
            case .profile: "perfil"
            case .photo: "foto"
            case .directMessage: "mensagem"
            }
        }
    }

    let kind: Kind
    let id: String
    let authorID: String
    var authorName = ""

    var key: String { Kind.key(kind, id) }
}

enum ReportReason: String, Codable, CaseIterable, Sendable {
    case offensive, sexual, violence, spam, other

    var title: String {
        switch self {
        case .offensive: "Ofensivo ou assédio"
        case .sexual: "Nudez ou conteúdo sexual"
        case .violence: "Violência"
        case .spam: "Spam"
        case .other: "Outro motivo"
        }
    }

    var icon: String {
        switch self {
        case .offensive: "exclamationmark.bubble"
        case .sexual: "eye.slash"
        case .violence: "hand.raised"
        case .spam: "envelope.badge"
        case .other: "ellipsis.circle"
        }
    }
}

struct BlockedUser: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    var date = Date.now
}

protocol ModerationBackend: Sendable {
    /// Manda a denúncia para a moderação (prazo de análise: 24 h)
    func report(content: ReportedContent, reason: ReportReason) async throws
    func block(userID: String, name: String) async throws
    func unblock(userID: String) async throws
    func blockedUsers() async throws -> [BlockedUser]
}

/// O que ainda não chegou ao servidor (vai em ordem; o que falha tenta de novo no próximo envio)
enum ModerationOp: Codable, Sendable {
    case report(ReportedContent, ReportReason)
    case block(BlockedUser)
    case unblock(String)
}

// MARK: - Estado

@MainActor @Observable
final class ModerationStore {
    /// O que acontece com uma denúncia: sem servidor ninguém analisa, então não promete prazo
    static var reviewNote: String {
        Backend.mode == .mock ? "Nesta versão sem servidor, a denúncia fica só no seu iPhone." : "A denúncia é analisada em até 24 h."
    }

    static let shared = ModerationStore()

    static let blockedKey = "blockedUsers", hiddenKey = "hiddenContent", outboxKey = "moderationOutbox"
    static let defaultsKeys = [blockedKey, hiddenKey, outboxKey]

    var backend: any ModerationBackend = MockModerationBackend()
    var access: AccessStore = .shared
    /// Desfaz a amizade (e recusa o pedido) de quem foi bloqueado
    var unfriend: @MainActor (String) async -> Void = { await FriendsStore.shared.unfriend($0) }
    private let defaults: UserDefaults
    private(set) var blocked: [BlockedUser] = []
    /// Chaves (`ReportedContent.key`) do que você denunciou
    private(set) var hidden: Set<String> = []
    private(set) var outbox: [ModerationOp] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        reload()
    }

    /// Lê de novo do aparelho (depois de excluir a conta, volta vazio)
    func reload() {
        blocked = load(Self.blockedKey) ?? []
        hidden = Set(load(Self.hiddenKey) ?? [String]())
        outbox = load(Self.outboxKey) ?? []
    }

    func isBlocked(_ userID: String) -> Bool { blocked.contains { $0.id == userID } }

    func isHidden(_ kind: ReportedContent.Kind, _ id: String) -> Bool { hidden.contains(ReportedContent.Kind.key(kind, id)) }

    func hides(_ c: ReportedContent) -> Bool { isBlocked(c.authorID) || hidden.contains(c.key) }

    // MARK: Ações

    /// Some na hora para você; a denúncia vai para a moderação assim que der
    func report(_ content: ReportedContent, reason: ReportReason) async {
        guard access.can(.moderationReport) else { return }
        hidden.insert(content.key)
        save(Array(hidden), Self.hiddenKey)
        enqueue(.report(content, reason))
        await flush()
    }

    func block(userID: String, name: String) async {
        guard !isBlocked(userID), access.can(.moderationBlock) else { return }
        let user = BlockedUser(id: userID, name: name)
        blocked.append(user)
        save(blocked, Self.blockedKey)
        enqueue(.block(user))
        await unfriend(userID)
        await flush()
    }

    /// A amizade não volta sozinha. Desfazer o que é seu não depende de permissão.
    func unblock(_ userID: String) async {
        guard isBlocked(userID) else { return }
        blocked.removeAll { $0.id == userID }
        save(blocked, Self.blockedKey)
        enqueue(.unblock(userID))
        await flush()
    }

    private var flushing: Task<Void, Never>?

    /// Manda a fila em ordem, um envio por vez; para no primeiro erro
    func flush() async {
        let previous = flushing
        let task = Task {
            await previous?.value
            while let op = outbox.first {
                do {
                    switch op {
                    case let .report(c, r): try await backend.report(content: c, reason: r)
                    case let .block(u): try await backend.block(userID: u.id, name: u.name)
                    case let .unblock(id): try await backend.unblock(userID: id)
                    }
                    outbox.removeFirst()
                    save(outbox, Self.outboxKey)
                } catch {
                    return
                }
            }
        }
        flushing = task
        await task.value
    }

    /// Envia o pendente e, com a fila vazia, a lista de bloqueados do servidor vira a daqui
    func refresh() async {
        await flush()
        guard outbox.isEmpty, let list = try? await backend.blockedUsers() else { return }
        blocked = list
        save(blocked, Self.blockedKey)
    }

    private func enqueue(_ op: ModerationOp) {
        outbox.append(op)
        save(outbox, Self.outboxKey)
    }

    // MARK: Filtros (suas coisas nunca somem)

    func visible(_ items: [FeedItem]) -> [FeedItem] {
        items.compactMap { item in
            guard !item.isMe else { return item }
            if isBlocked(item.memberID) || isHidden(.checkIn, item.id) { return nil }
            guard isHidden(.photo, item.id) else { return item }
            var copy = item
            copy.photo = nil
            copy.hasPhoto = false
            return copy
        }
    }

    func visible(_ comments: [CheckInComment]) -> [CheckInComment] {
        comments.filter { $0.isMine || !(isBlocked($0.authorID) || isHidden(.comment, $0.uuid.uuidString)) }
    }

    func visible(_ messages: [RemoteMessage]) -> [RemoteMessage] {
        messages.filter { !(isBlocked($0.memberID) || isHidden(.message, $0.id)) }
    }

    func visible(_ people: [RemoteFriend]) -> [RemoteFriend] { people.filter { !isBlocked($0.id) } }

    // MARK: Disco

    private func load<T: Decodable>(_ key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }
}

extension ReportedContent.Kind {
    static func key(_ kind: Self, _ id: String) -> String { "\(kind.rawValue):\(id)" }
}

// MARK: - Servidor simulado

/// Guarda denúncias e bloqueios no aparelho, como o servidor guardaria. A "moderação" simulada é o que o
/// ModerationStore já faz: o conteúdo denunciado some na hora para quem denunciou.
struct MockModerationBackend: ModerationBackend {
    struct Report: Codable, Sendable {
        let content: ReportedContent
        let reason: ReportReason
        let date: Date
    }

    static let reportsKey = "mockReports", blocksKey = "mockBlocks"

    static var reports: [Report] {
        UserDefaults.standard.data(forKey: reportsKey).flatMap { try? JSONDecoder().decode([Report].self, from: $0) } ?? []
    }

    private static var blocks: [BlockedUser] {
        get { UserDefaults.standard.data(forKey: blocksKey).flatMap { try? JSONDecoder().decode([BlockedUser].self, from: $0) } ?? [] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: blocksKey) }
    }

    /// Conta excluída: some o que ela mandou
    static func reset() {
        UserDefaults.standard.removeObject(forKey: reportsKey)
        UserDefaults.standard.removeObject(forKey: blocksKey)
    }

    func report(content: ReportedContent, reason: ReportReason) async throws {
        var all = Self.reports.filter { $0.content.key != content.key }
        all.append(Report(content: content, reason: reason, date: .now))
        UserDefaults.standard.set(try? JSONEncoder().encode(all), forKey: Self.reportsKey)
    }

    func block(userID: String, name: String) async throws {
        guard !Self.blocks.contains(where: { $0.id == userID }) else { return }
        Self.blocks.append(BlockedUser(id: userID, name: name))
    }

    func unblock(userID: String) async throws { Self.blocks.removeAll { $0.id == userID } }

    func blockedUsers() async throws -> [BlockedUser] { Self.blocks }
}
