import Foundation
import Observation

/// Onde mora a atribuição oficial de roles. Devolve os valores crus; `nil` = usuário sem atribuição.
/// O app só lê: ninguém escolhe ou grava a própria role por aqui.
protocol RoleBackend: Sendable {
    func assignment(for userID: String) async throws -> [String]?
}

// MARK: - Estado

@MainActor @Observable
final class AccessStore {
    static let shared = AccessStore()

    var backend: any RoleBackend = MockRoleBackend()
    let policy: RolePolicy
    private(set) var context: AccessContext = .signedOut
    private let currentUser: @MainActor () -> AuthUser?

    init(policy: RolePolicy = .standard, currentUser: @escaping @MainActor () -> AuthUser? = { AuthStore.shared.user }) {
        self.policy = policy
        self.currentUser = currentUser
    }

    /// Ação no que é seu ou sem dono (criar, publicar o próprio, abrir uma tela)
    func can(_ permission: Permission) -> Bool { allows(permission, isMine: nil) }

    func can(_ permission: Permission, on resource: some OwnedResource) -> Bool { allows(permission, isMine: resource.isMine) }

    func authorize(_ permission: Permission) throws {
        guard can(permission) else { throw AccessError.forbidden(permission) }
    }

    /// Com conta, mas as roles desta conta ainda não chegaram
    var isLoading: Bool {
        guard let id = currentUser()?.id else { return false }
        if case let .resolved(resolved, _, _) = context { return resolved != id }
        return true
    }

    /// Roles da sessão atual; o contexto de outra conta (ou de antes do logout) não vale
    var roles: Set<AppRole> {
        guard let id = currentUser()?.id, context.userID == id else { return [] }
        return context.roles
    }

    private func allows(_ permission: Permission, isMine: Bool?) -> Bool {
        policy.allows(roles, permission, isMine: isMine)
    }

    /// Lê de novo a atribuição da conta atual. Chamado ao trocar de conta e ao abrir o app.
    func refresh() async {
        guard let user = currentUser() else {
            context = .signedOut
            return
        }
        if context.userID != user.id { context = .loading(userID: user.id) }
        let resolved: AccessContext
        do {
            resolved = .resolve(userID: user.id, assignment: try await backend.assignment(for: user.id))
        } catch {
            resolved = .resolved(userID: user.id, roles: [.user], source: .fallback)
        }
        guard currentUser()?.id == user.id else { return }
        context = resolved
    }
}

// MARK: - Servidor simulado

/// Sem servidor não há atribuição: todo mundo é USER (a não ser nas atribuições passadas, usadas nos testes)
struct MockRoleBackend: RoleBackend {
    var assignments: [String: [String]] = [:]

    func assignment(for userID: String) async throws -> [String]? { assignments[userID] }
}

// MARK: - Ações administrativas

struct PendingReport: Sendable, Equatable {
    let reporterID: String
    let content: ReportedContent
    let reason: ReportReason
    let date: Date
}

/// Ponto de integração das ações de ADMIN. Precisa de um servidor confiável que confira a role do lado dele:
/// no banco público do CloudKit, o app não lê denúncias de outras pessoas nem apaga registros que não criou.
protocol AdminBackend: Sendable {
    func reports() async throws -> [PendingReport]
    func remove(_ content: ReportedContent) async throws
    func setRoles(_ roles: Set<AppRole>, for userID: String) async throws
}

struct TrustedServerRequired: AdminBackend {
    func reports() async throws -> [PendingReport] { throw AccessError.requiresTrustedServer }
    func remove(_ content: ReportedContent) async throws { throw AccessError.requiresTrustedServer }
    func setRoles(_ roles: Set<AppRole>, for userID: String) async throws { throw AccessError.requiresTrustedServer }
}

@MainActor
struct AdminActions {
    var access: AccessStore = .shared
    var backend: any AdminBackend = Backend.mode == .firebase ? FirebaseAdminBackend() : TrustedServerRequired()

    func reports() async throws -> [PendingReport] {
        try access.authorize(.moderationReview)
        return try await backend.reports()
    }

    func remove(_ content: ReportedContent) async throws {
        try access.authorize(.moderationRemoveContent)
        try await backend.remove(content)
    }

    /// Ninguém muda as próprias roles
    func setRoles(_ roles: Set<AppRole>, for userID: String) async throws {
        try access.authorize(.usersManageRoles)
        guard userID != access.context.userID else { throw AccessError.forbidden(.usersManageRoles) }
        try await backend.setRoles(roles, for: userID)
    }
}
