import Foundation
import Observation
import SwiftUI

// Conta: mesmo esquema de ligas e amigos. AuthBackend é o contrato com o servidor; por enquanto quem responde
// é o MockAuthBackend, que só simula (não existe servidor nem Apple de verdade). Nenhuma senha é guardada:
// no servidor real, a senha vai por HTTPS e só ele valida; o app guarda apenas o token da sessão (no Keychain).

struct AuthUser: Codable, Equatable, Sendable {
    enum Provider: String, Codable, Sendable { case apple, email }

    let id: String
    var name: String
    let email: String
    let provider: Provider
    /// Token da sessão (simulado)
    let token: String
}

enum AuthError: LocalizedError {
    case invalidEmail, shortPassword, missingName, wrongPassword, emailInUse, cancelled, appleOnly

    var errorDescription: String? {
        switch self {
        case .invalidEmail: "E-mail inválido."
        case .shortPassword: "A senha precisa de pelo menos 8 caracteres."
        case .missingName: "Diga seu nome."
        case .wrongPassword: "E-mail ou senha incorretos."
        case .emailInUse: "Já existe uma conta com esse e-mail. Entre em vez de criar."
        case .cancelled: "Login cancelado."
        case .appleOnly: "Por enquanto, entre com a Apple (usa a sua conta do iCloud)."
        }
    }
}

protocol AuthBackend: Sendable {
    func signInWithApple() async throws -> AuthUser
    func signIn(email: String, password: String) async throws -> AuthUser
    func signUp(name: String, email: String, password: String) async throws -> AuthUser
    func signOut(_ user: AuthUser) async
}

// MARK: - Sessão

@MainActor @Observable
final class AuthStore {
    static let shared = AuthStore()
    private static let key = "authUser"

    var backend: any AuthBackend = MockAuthBackend()
    private(set) var user: AuthUser? = AuthStore.load()

    var isSignedIn: Bool { user != nil }

    func signInWithApple() async throws { try await finish(backend.signInWithApple()) }

    func signIn(email: String, password: String) async throws {
        try Self.validate(email: email, password: password)
        try await finish(backend.signIn(email: Self.clean(email), password: password))
    }

    func signUp(name: String, email: String, password: String) async throws {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { throw AuthError.missingName }
        try Self.validate(email: email, password: password)
        try await finish(backend.signUp(name: name.trimmingCharacters(in: .whitespaces), email: Self.clean(email), password: password))
    }

    func signOut() async {
        if let user { await backend.signOut(user) }
        user = nil
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    private func finish(_ u: AuthUser) {
        user = u
        UserDefaults.standard.set(try? JSONEncoder().encode(u), forKey: Self.key)
        // O nome da conta vira o nome de treinador, se ainda não tiver um
        if (UserDefaults.standard.string(forKey: "trainerName") ?? "").isEmpty, !u.name.isEmpty {
            UserDefaults.standard.set(u.name, forKey: "trainerName")
        }
    }

    private static func load() -> AuthUser? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(AuthUser.self, from: $0) }
    }

    static func clean(_ email: String) -> String { email.trimmingCharacters(in: .whitespaces).lowercased() }

    static func validate(email: String, password: String) throws {
        let e = clean(email)
        let parts = e.split(separator: "@")
        guard parts.count == 2, parts[0].count >= 1, parts[1].contains("."), !parts[1].hasSuffix("."), !e.contains(" ") else {
            throw AuthError.invalidEmail
        }
        guard password.count >= 8 else { throw AuthError.shortPassword }
    }
}

// MARK: - Servidor simulado

struct MockAuthBackend: AuthBackend {
    /// Contas "criadas" neste aparelho (só e-mail e nome; a senha não é guardada)
    private static let accountsKey = "mockAccounts"

    private static var accounts: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: accountsKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: accountsKey) }
    }

    private func token() -> String { UUID().uuidString }

    /// Simula a folha da Apple: devolve um e-mail de retransmissão, como a Apple faz ao ocultar o e-mail
    func signInWithApple() async throws -> AuthUser {
        try await Task.sleep(for: .milliseconds(600))
        let name = UserDefaults.standard.string(forKey: "trainerName") ?? ""
        return AuthUser(id: "apple-" + UUID().uuidString.prefix(8).lowercased(), name: name,
                        email: "\(UUID().uuidString.prefix(10).lowercased())@privaterelay.appleid.com", provider: .apple, token: token())
    }

    /// Sem servidor não dá para conferir a senha: qualquer senha válida entra
    func signIn(email: String, password: String) async throws -> AuthUser {
        try await Task.sleep(for: .milliseconds(500))
        let name = Self.accounts[email] ?? String(email.split(separator: "@").first ?? "").capitalized
        return AuthUser(id: "email-" + email, name: name, email: email, provider: .email, token: token())
    }

    func signUp(name: String, email: String, password: String) async throws -> AuthUser {
        try await Task.sleep(for: .milliseconds(500))
        guard Self.accounts[email] == nil else { throw AuthError.emailInUse }
        Self.accounts[email] = name
        return AuthUser(id: "email-" + email, name: name, email: email, provider: .email, token: token())
    }

    func signOut(_ user: AuthUser) async {}
}

// MARK: - Tela

struct LoginView: View {
    @State private var store = AuthStore.shared
    @State private var creating = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 10) {
                    LivingMonster(form: MonsterForm(stage: .baby, attribute: nil), progress: 0.5).frame(width: 120, height: 120)
                    Text("GymBros").gmFont(34, weight: .black, design: .rounded, relativeTo: .largeTitle).foregroundStyle(Theme.accent)
                    Text("Seus treinos chocam e evoluem um bro.").font(.subheadline).foregroundStyle(Theme.dim)
                }
                .padding(.top, 40)

                GMSegmented(options: [(false, "Entrar"), (true, "Criar conta")], selection: $creating)
                VStack(spacing: 10) {
                    if creating { GMTextField(placeholder: "Seu nome", text: $name, capitalization: .words) }
                    GMTextField(placeholder: "E-mail", text: $email, keyboard: .emailAddress, capitalization: .never)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                    SecureField("", text: $password, prompt: Text("Senha (mínimo 8 caracteres)").foregroundStyle(Theme.dim))
                        .textContentType(creating ? .newPassword : .password)
                        .padding(14)
                        .background(Theme.card, in: .rect(cornerRadius: Theme.radiusM))
                }
                if let error {
                    Text(error).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.danger).multilineTextAlignment(.center)
                }
                GMButton(creating ? "Criar conta" : "Entrar", icon: busy ? nil : "arrow.right", enabled: !busy && !email.isEmpty && !password.isEmpty) {
                    run { creating ? try await store.signUp(name: name, email: email, password: password)
                                   : try await store.signIn(email: email, password: password) }
                }
                HStack {
                    Rectangle().fill(Theme.stroke).frame(height: 1)
                    Text("ou").font(.caption).foregroundStyle(Theme.dim)
                    Rectangle().fill(Theme.stroke).frame(height: 1)
                }

                appleButton

                Text("Ainda não há servidor: o login é simulado e tudo continua só neste iPhone.")
                    .font(.caption).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.bg.ignoresSafeArea())
        .overlay { if busy { ProgressView().controlSize(.large).tint(Theme.accent) } }
    }

    /// Mesmo visual do botão oficial (fundo branco, logo da Apple)
    private var appleButton: some View {
        Button { run { try await store.signInWithApple() } } label: {
            HStack(spacing: 8) {
                Image(systemName: "apple.logo").font(.title3)
                Text("Continuar com a Apple").font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(.white, in: .rect(cornerRadius: Theme.radiusM))
            .foregroundStyle(.black)
        }
        .buttonStyle(GMPress())
        .disabled(busy)
        .accessibilityLabel("Continuar com a Apple")
    }

    private func run(_ action: @escaping () async throws -> Void) {
        error = nil
        busy = true
        Task {
            do {
                try await action()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                self.error = error.localizedDescription
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
            busy = false
        }
    }
}
