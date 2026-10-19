import SwiftUI
import UIKit
import UserNotifications

// Preferências de notificação (Ajustes → Notificações) e a entrega das notificações sociais.
// Cada tópico é uma chave `notify.<tópico>` no UserDefaults (vai com a conta); `notify.paused` silencia tudo,
// inclusive lembretes, resumo, descanso e chegada na academia. Com servidor, as mesmas chaves filtram o push.

enum NotificationTopic: String, CaseIterable, Identifiable, Sendable {
    case messages, cheers, invites, duels, friendsTraining, reactions, friendRequests

    var id: String { rawValue }
    var key: String { "notify.\(rawValue)" }

    var title: String {
        switch self {
        case .messages: "Mensagens diretas"
        case .cheers: "Força recebida"
        case .invites: "Convites para treinar junto"
        case .friendsTraining: "Amigo começou a treinar"
        case .reactions: "Reações e comentários"
        case .friendRequests: "Pedidos de amizade"
        case .duels: "X1"
        }
    }

    var subtitle: String {
        switch self {
        case .messages: "Quando um amigo te escreve"
        case .cheers: "Quando alguém manda força 💪 para você"
        case .invites: "Convites e respostas aos seus convites"
        case .friendsTraining: "Quando um amigo começa um treino ao vivo"
        case .reactions: "Nos seus check-ins do perfil e das ligas"
        case .friendRequests: "Quando alguém quer ser seu amigo"
        case .duels: "Desafios, respostas e resultado dos seus X1"
        }
    }

    var icon: String {
        switch self {
        case .messages: "bubble.left.and.bubble.right.fill"
        case .cheers: "bolt.heart.fill"
        case .invites: "figure.2"
        case .friendsTraining: "dot.radiowaves.left.and.right"
        case .reactions: "face.smiling.inverse"
        case .friendRequests: "person.badge.plus"
        case .duels: "bolt.shield.fill"
        }
    }

    var tint: Color {
        switch self {
        case .messages: Theme.info
        case .cheers: Theme.accent
        case .invites: Attribute.agilidade.color
        case .friendsTraining: Theme.online
        case .reactions: Theme.streak
        case .friendRequests: Attribute.tecnica.color
        case .duels: Theme.trophy
        }
    }

    /// Ação da notificação (botões ao segurar)
    var category: String {
        switch self {
        case .messages: SocialNotifier.messageCategory
        case .cheers: SocialNotifier.cheerCategory
        case .invites: SocialNotifier.inviteCategory
        default: SocialNotifier.socialCategory
        }
    }
}

enum NotificationPrefs {
    static let pausedKey = "notify.paused"
    /// Vão com a conta
    static var defaultsKeys: [String] { NotificationTopic.allCases.map(\.key) + [pausedKey] }

    static func paused(_ defaults: UserDefaults = .standard) -> Bool { defaults.bool(forKey: pausedKey) }

    /// Tópico ligado (todos começam ligados) e nada pausado
    static func isOn(_ topic: NotificationTopic, defaults: UserDefaults = .standard) -> Bool {
        !paused(defaults) && (defaults.object(forKey: topic.key) as? Bool ?? true)
    }

    static func enabledCount(_ defaults: UserDefaults = .standard) -> Int {
        NotificationTopic.allCases.filter { defaults.object(forKey: $0.key) as? Bool ?? true }.count
    }
}

/// Permissão do iOS para notificar
@MainActor @Observable
final class NotificationPermission {
    static let shared = NotificationPermission()
    private(set) var status: UNAuthorizationStatus = .notDetermined

    func refresh() async {
        status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func request() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        await refresh()
    }

    var denied: Bool { status == .denied }

    static func openSystemSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
    }
}

/// O que vira notificação: uma mensagem direta ou um evento da atividade
struct InboxNotice: Identifiable {
    let id: String
    let topic: NotificationTopic
    let title: String
    let body: String
    /// Conversa para abrir no toque (nil = aba Notificações)
    let peerID: String?
    /// Convite, para os botões "Bora" e "Hoje não"
    var messageID: String?

    init(message m: DirectMessage, peer: InboxPeer) {
        id = m.id
        topic = m.topic
        peerID = m.peerID
        messageID = m.kind == .invite ? m.id : nil
        switch m.kind {
        case .text:
            title = peer.name
            body = m.text
        case .cheer:
            title = "\(peer.name) mandou força 💪"
            body = m.text.isEmpty ? "Manda de volta?" : m.text
        case .invite:
            title = "\(peer.name) te chamou pra treinar junto"
            body = m.invite.map { "\($0.kind.name) · \($0.place) · \($0.whenText)" + (m.text.isEmpty ? "" : "\n\(m.text)") } ?? m.text
        case .inviteReply:
            title = m.accepted == true ? "\(peer.name) topou treinar junto 🤝" : "\(peer.name) não vai dessa vez"
            body = m.accepted == true ? "Combinado! Abre a conversa para acertar os detalhes." : "Fica para a próxima."
        }
    }

    init(event e: InboxEvent) {
        id = e.id
        topic = e.topic
        switch e.kind {
        case .reaction:
            title = "\(e.actorName) reagiu \(e.text) ao seu check-in"
            body = e.detail
            peerID = nil
        case .comment:
            title = "\(e.actorName) comentou no seu check-in"
            body = e.text
            peerID = nil
        case .liveStart:
            title = "\(e.actorName) começou a treinar"
            body = "\(e.text) · \(e.detail). Manda força!"
            peerID = e.actorID
        case .friendRequest:
            title = "\(e.actorName) quer ser seu amigo"
            body = "Toque para aceitar ou recusar."
            peerID = nil
        case .cheer, .invite, .inviteReply:
            title = e.actorName
            body = e.text
            peerID = e.actorID
        case .duelChallenge:
            title = "\(e.actorName) te desafiou para um X1 ⚔️"
            body = "\(e.detail) · 24 h para aceitar. Vence quem fizer mais nas 24 h depois do aceite."
            peerID = nil
        case .duelAccepted:
            title = "\(e.actorName) aceitou seu X1 ⚔️"
            body = "\(e.detail) · valendo pelas próximas 24 h."
            peerID = nil
        case .duelDeclined:
            title = "\(e.actorName) recusou seu X1"
            body = e.detail
            peerID = nil
        case .duelExpired:
            title = "Seu X1 com \(e.actorName) expirou"
            body = "\(e.detail) · ninguém aceitou em 24 h."
            peerID = nil
        case .duelResult:
            title = "X1 encerrado · \(e.detail)"
            body = e.text.isEmpty ? "Seu X1 com \(e.actorName) terminou." : e.text
            peerID = nil
        }
    }
}

/// Notificações locais das mensagens e da atividade (com servidor, viriam por push com o mesmo formato)
enum SocialNotifier {
    static let messageCategory = "DM", cheerCategory = "CHEER", inviteCategory = "INVITE", socialCategory = "SOCIAL"
    static let replyAction = "REPLY", cheerBackAction = "CHEER_BACK", acceptAction = "INVITE_YES", declineAction = "INVITE_NO"

    static var categories: [UNNotificationCategory] {
        let reply = UNTextInputNotificationAction(identifier: replyAction, title: "Responder", options: [],
                                                  textInputButtonTitle: "Enviar", textInputPlaceholder: "Mensagem")
        let cheerBack = UNNotificationAction(identifier: cheerBackAction, title: "Mandar força de volta 💪", options: [])
        let yes = UNNotificationAction(identifier: acceptAction, title: "Bora! 🤝", options: [])
        let no = UNNotificationAction(identifier: declineAction, title: "Hoje não", options: [])
        return [
            UNNotificationCategory(identifier: messageCategory, actions: [reply], intentIdentifiers: []),
            UNNotificationCategory(identifier: cheerCategory, actions: [cheerBack, reply], intentIdentifiers: []),
            UNNotificationCategory(identifier: inviteCategory, actions: [yes, no], intentIdentifiers: []),
            UNNotificationCategory(identifier: socialCategory, actions: [], intentIdentifiers: []),
        ]
    }

    static func deliver(_ n: InboxNotice) {
        let c = UNMutableNotificationContent()
        c.title = n.title
        c.body = n.body
        c.sound = .default
        c.categoryIdentifier = n.topic.category
        c.threadIdentifier = n.peerID.map { "dm-\($0)" } ?? n.topic.rawValue
        var info: [String: String] = ["inbox": n.id]
        if let p = n.peerID { info["peer"] = p }
        if let m = n.messageID { info["message"] = m }
        c.userInfo = info
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "inbox-\(n.id)", content: c, trigger: nil))
    }

    /// Toque ou botão numa notificação social. Devolve false se não era dela.
    @MainActor
    static func handle(_ response: UNNotificationResponse) async -> Bool {
        let info = response.notification.request.content.userInfo
        guard info["inbox"] != nil else { return false }
        let store = InboxStore.shared
        let peer = info["peer"] as? String
        switch response.actionIdentifier {
        case replyAction:
            if let peer, let text = (response as? UNTextInputNotificationResponse)?.userText {
                _ = try? await store.send(.text, to: peer, text: text)
            }
        case cheerBackAction:
            if let peer { try? await store.cheer(peer) }
        case acceptAction, declineAction:
            await store.refresh()
            if let id = info["message"] as? String, let invite = store.message(id) {
                try? await store.reply(to: invite, accepted: response.actionIdentifier == acceptAction)
            }
        default:
            store.route = peer.map { .conversation($0) } ?? .activity
        }
        return true
    }
}

extension NotificationPermission {
    var allowed: Bool { status == .authorized || status == .provisional || status == .ephemeral }
}

/// Pede a permissão do iOS ou, se negada, leva aos Ajustes do iPhone
struct NotificationPermissionCard: View {
    @State private var permission = NotificationPermission.shared

    var body: some View {
        GMCard {
            HStack(alignment: .top, spacing: 12) {
                GMIconTile(icon: permission.denied ? "bell.slash.fill" : "bell.badge.fill", tint: permission.denied ? Theme.warning : Theme.badge)
                VStack(alignment: .leading, spacing: 4) {
                    Text(permission.denied ? "Notificações desligadas no iPhone" : "Saiba na hora quando te chamarem")
                        .font(.subheadline.weight(.semibold))
                    Text(permission.denied ? "Nada do GymBros toca no iPhone. Força, convites e mensagens só aparecem dentro do app."
                                           : "Força, convites para treinar junto, mensagens, reações e seus lembretes.")
                        .font(.caption).foregroundStyle(Theme.dim)
                }
            }
            GMButton(permission.denied ? "Abrir Ajustes do iPhone" : "Ativar notificações", icon: "bell", kind: .secondary, small: true) {
                if permission.denied { NotificationPermission.openSystemSettings() } else { Task { await permission.request() } }
            }
        }
        .task { await permission.refresh() }
    }
}
