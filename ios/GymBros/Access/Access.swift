import Foundation

// Controle de acesso por role (RBAC). Role diz quem a pessoa é para o app; permissão diz o que ela pode fazer.
// Toda decisão passa por `RolePolicy.allows` (via `AccessStore.can`): nada é concedido sem estar escrito na matriz.
// Roles e permissões são enums: uma nova só chega aos aparelhos numa nova versão do app.
// Isto não protege o servidor: o CloudKit só conhece as próprias permissões (docs/rbac.md).

enum AppRole: String, CaseIterable, Codable, Sendable {
    case admin = "ADMIN"
    case developer = "DEVELOPER"
    case user = "USER"

    var title: String {
        switch self {
        case .admin: "Administrador"
        case .developer: "Desenvolvedor"
        case .user: "Usuário"
        }
    }

    /// Só o identificador exato vale; desconhecidos são descartados (nunca viram outra role)
    static func parse(_ raw: [String]) -> Set<AppRole> { Set(raw.compactMap(AppRole.init(rawValue:))) }
}

enum Permission: String, CaseIterable, Codable, Sendable {
    case profileRead = "profile.read"
    case profileUpdate = "profile.update"
    case friendsRead = "friends.read"
    case friendsManage = "friends.manage"
    case leaguesRead = "leagues.read"
    case leaguesCreate = "leagues.create"
    case leaguesJoin = "leagues.join"
    case leaguesUpdate = "leagues.update"
    case checkInsPublish = "checkIns.publish"
    case messagesPublish = "messages.publish"
    case commentsCreate = "comments.create"
    case directMessagesSend = "directMessages.send"
    case moderationReport = "moderation.report"
    case moderationBlock = "moderation.block"
    case moderationReview = "moderation.review"
    case moderationRemoveContent = "moderation.removeContent"
    case usersManageRoles = "users.manageRoles"
    case diagnosticsRead = "diagnostics.read"
}

/// `.own`: só no que é seu (ou no que você está criando). `.any`: também no dos outros.
enum PermissionScope: Sendable {
    case own, any
}

/// Recurso com dono, para as permissões de escopo `.own`
protocol OwnedResource {
    var isMine: Bool { get }
}

struct RolePolicy: Sendable {
    let grants: [AppRole: [Permission: PermissionScope]]

    /// `isMine == nil`: ação sem recurso de outra pessoa (criar, publicar o próprio, ver uma tela)
    func allows(_ roles: Set<AppRole>, _ permission: Permission, isMine: Bool? = nil) -> Bool {
        roles.contains { role in
            switch grants[role]?[permission] {
            case .any: true
            case .own: isMine ?? true
            case nil: false
            }
        }
    }

    func permissions(of role: AppRole) -> Set<Permission> { Set((grants[role] ?? [:]).keys) }

    static let standard = RolePolicy(grants: [
        .user: [
            .profileRead: .any,
            .profileUpdate: .own,
            .friendsRead: .own,
            .friendsManage: .own,
            .leaguesRead: .any,
            .leaguesCreate: .own,
            .leaguesJoin: .own,
            .leaguesUpdate: .own,
            .checkInsPublish: .own,
            .messagesPublish: .own,
            .commentsCreate: .own,
            .directMessagesSend: .own,
            .moderationReport: .any,
            .moderationBlock: .any,
        ],
        .developer: [
            .diagnosticsRead: .any,
        ],
        .admin: [
            .moderationReview: .any,
            .moderationRemoveContent: .any,
            .usersManageRoles: .any,
        ],
    ])
}

/// Quem está usando o app e com quais roles. Só `.resolved` concede alguma coisa.
enum AccessContext: Equatable, Sendable {
    /// De onde vieram as roles
    enum Source: Equatable, Sendable {
        /// Atribuição oficial encontrada
        case assigned
        /// Sem atribuição: role padrão (USER)
        case standard
        /// A consulta falhou: só USER, nunca o que estava atribuído antes
        case fallback
    }

    case signedOut
    case loading(userID: String)
    case resolved(userID: String, roles: Set<AppRole>, source: Source)

    var userID: String? {
        switch self {
        case .signedOut: nil
        case let .loading(id), let .resolved(id, _, _): id
        }
    }

    var roles: Set<AppRole> {
        if case let .resolved(_, roles, _) = self { return roles }
        return []
    }

    /// Roles a partir da atribuição lida: nenhuma atribuição = USER; atribuição só com valores inválidos = nenhuma role
    static func resolve(userID: String, assignment: [String]?) -> AccessContext {
        guard let assignment else { return .resolved(userID: userID, roles: [.user], source: .standard) }
        return .resolved(userID: userID, roles: AppRole.parse(assignment), source: .assigned)
    }
}

enum AccessError: LocalizedError, Equatable {
    case forbidden(Permission)
    case requiresTrustedServer

    var errorDescription: String? {
        switch self {
        case .forbidden: "Sua conta não tem permissão para isso."
        case .requiresTrustedServer: "Esta ação precisa de um servidor confiável, que o app ainda não tem."
        }
    }
}

extension League: OwnedResource {
    /// Criada neste aparelho; liga achada pelo código (`joined`) é de outra pessoa
    var isMine: Bool { !joined }
}
