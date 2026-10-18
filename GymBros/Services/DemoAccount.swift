import Foundation
import SwiftData

/// Conta de demonstração para a revisão da Apple. Só existe no `.mock`: entra pelo AuthBackend como qualquer conta
/// de e-mail e, na primeira vez, já está na liga de exemplo (participantes, check-ins e mural simulados).
enum DemoAccount {
    static let email = "revisao@gymbros.app"
    static let password = "GymBros2026"
    static let name = "Bro Revisor"
    /// Já recebeu a liga de exemplo (vai na cópia da conta: sair da liga não a traz de volta)
    static let seededKey = "demoSeeded"

    static var isAvailable: Bool { Backend.mode == .mock }

    static func isDemo(_ user: AuthUser?) -> Bool { user?.email == email }

    /// Põe a conta de demonstração na liga de exemplo uma única vez
    @MainActor
    @discardableResult
    static func seedIfNeeded(user: AuthUser?, context: ModelContext, representative: UUID?,
                             mode: BackendMode = Backend.mode, defaults: UserDefaults = .standard) -> Bool {
        guard mode == .mock, isDemo(user), !defaults.bool(forKey: seededKey) else { return false }
        let code = MockLeague.code
        let joined = ((try? context.fetchCount(FetchDescriptor<League>(predicate: #Predicate { $0.code == code }))) ?? 0) > 0
        if !joined {
            let league = MockLeague.make()
            league.monsterUUID = context.representative(representative)
            context.insert(league)
            try? context.save()
        }
        defaults.set(true, forKey: seededKey)
        return !joined
    }
}
