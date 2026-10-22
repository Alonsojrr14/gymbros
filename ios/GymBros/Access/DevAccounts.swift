#if DEBUG
import SwiftUI

/// Contas fixas para testar cada role no modo `.mock`. Só existe em builds de desenvolvimento: no Release
/// (TestFlight/App Store) este arquivo não é compilado e ninguém escolhe a própria role.
enum DevAccount: String, CaseIterable, Identifiable {
    case user, developer, admin, disabled

    var id: String { "dev-\(rawValue)" }

    var assignment: [String] {
        switch self {
        case .user: ["USER"]
        case .developer: ["USER", "DEVELOPER"]
        case .admin: ["USER", "ADMIN"]
        case .disabled: []
        }
    }

    var title: String {
        switch self {
        case .user: "Usuário"
        case .developer: "Desenvolvedor"
        case .admin: "Administrador"
        case .disabled: "Conta desativada"
        }
    }

    var icon: String {
        switch self {
        case .user: "person.fill"
        case .developer: "hammer.fill"
        case .admin: "shield.lefthalf.filled"
        case .disabled: "person.fill.xmark"
        }
    }

    var user: AuthUser {
        AuthUser(id: id, name: "Teste \(title)", email: "\(id)@gymbros.test", provider: .email, token: UUID().uuidString)
    }

    static var isAvailable: Bool { Backend.mode == .mock }

    static var assignments: [String: [String]] {
        Dictionary(uniqueKeysWithValues: allCases.map { ($0.id, $0.assignment) })
    }
}

/// Seletor de conta de teste na tela de login
struct DevAccountPicker: View {
    let select: (DevAccount) -> Void

    var body: some View {
        if DevAccount.isAvailable {
            GMSection("Desenvolvimento", footer: "Só existe em builds de desenvolvimento com o backend simulado. Entra direto com a role escolhida.") {
                ForEach(DevAccount.allCases) { account in
                    GMRow(icon: account.icon, iconTint: Theme.accent, title: account.title,
                          subtitle: account.assignment.isEmpty ? "Sem roles" : account.assignment.joined(separator: " + ")) {
                        select(account)
                    }
                    if account != DevAccount.allCases.last { GMDivider() }
                }
            }
        }
    }
}
#endif
