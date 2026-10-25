import AuthenticationServices
import Foundation
import Observation
import Security
import SwiftData
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
    /// Apaga a conta e tudo o que ela publicou no servidor (perfil, lugar nas ligas, check-ins, recados, amizades, denúncias, bloqueios)
    func deleteAccount(_ user: AuthUser) async throws
    /// Confere, antes de apagar qualquer coisa, se o servidor vai aceitar excluir o cadastro
    func checkCanDelete() async throws
    /// Manda o e-mail com o link para criar uma senha nova
    func resetPassword(email: String) async throws
    /// Manda (de novo) o e-mail de confirmação do endereço
    func sendVerification() async throws
    /// O e-mail da conta já foi confirmado; nil = não se aplica (login simulado ou da Apple)
    func isVerified() async -> Bool?
}

/// Sem servidor de e-mail (simulado e CloudKit): nada a mandar
extension AuthBackend {
    func checkCanDelete() async throws {}
    func resetPassword(email: String) async throws {}
    func sendVerification() async throws {}
    func isVerified() async -> Bool? { nil }
}

// MARK: - Sessão

@MainActor @Observable
final class AuthStore {
    static let shared = AuthStore()

    var backend: any AuthBackend = MockAuthBackend()
    private(set) var user: AuthUser?
    /// Item do Keychain com a sessão
    private let key: String

    init(account: String = "authUser") {
        key = account
        user = Self.load(account)
    }

    var isSignedIn: Bool { user != nil }

    func signInWithApple() async throws { try await finish(backend.signInWithApple()) }

    func signIn(email: String, password: String) async throws {
        try Self.validate(email: email, password: password)
        try await finish(backend.signIn(email: Self.clean(email), password: password))
    }

    /// Conta de demonstração da revisão da Apple (só no `.mock`)
    func signInDemo() async throws {
        guard DemoAccount.isAvailable else { return }
        try await signIn(email: DemoAccount.email, password: DemoAccount.password)
    }

    func signUp(name: String, email: String, password: String) async throws {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { throw AuthError.missingName }
        try Self.validate(email: email, password: password)
        try await finish(backend.signUp(name: name.trimmingCharacters(in: .whitespaces), email: Self.clean(email), password: password))
    }

    func signOut() async {
        if let user { await backend.signOut(user) }
        endSession()
    }

    /// E-mail da conta confirmado (nil: não se aplica); atualizado por `checkVerification`
    private(set) var emailVerified: Bool?

    func resetPassword(email: String) async throws {
        let e = Self.clean(email)
        guard e.contains("@"), e.contains(".") else { throw AuthError.invalidEmail }
        try await backend.resetPassword(email: e)
    }

    func sendVerification() async throws { try await backend.sendVerification() }

    func checkVerification() async { emailVerified = user?.provider == .email ? await backend.isVerified() : nil }

    func checkCanDelete() async throws { try await backend.checkCanDelete() }

    /// Apaga a conta no servidor e, só se der certo, tudo dela neste aparelho e a sessão.
    /// Os dados da conta no servidor saem antes, pelo AccountSync (que chama este método).
    func deleteAccount(context: ModelContext, defaults: UserDefaults = .standard, widget: UserDefaults? = WidgetData.defaults,
                       beforeWipe: () async -> Void = {}) async throws {
        guard let user else { return }
        try await backend.deleteAccount(user)
        await beforeWipe()
        defer { endSession() }
        try AccountData.wipeAll(context: context, defaults: defaults, widget: widget)
    }

    #if DEBUG
    /// Só no `.mock`, em builds de desenvolvimento
    func signIn(as account: DevAccount) {
        guard DevAccount.isAvailable else { return }
        finish(account.user)
    }
    #endif

    /// Esquece a sessão sem falar com o servidor (login simulado de antes do Firebase)
    func forgetSession() { endSession() }

    private func endSession() {
        user = nil
        Keychain.delete(key)
    }

    private func finish(_ u: AuthUser) {
        user = u
        if let data = try? JSONEncoder().encode(u) { Keychain.save(data, for: key) }
        // O nome da conta vira o nome de treinador, se ainda não tiver um
        if (UserDefaults.standard.string(forKey: "trainerName") ?? "").isEmpty, !u.name.isEmpty {
            UserDefaults.standard.set(u.name, forKey: "trainerName")
        }
    }

    /// Sessões gravadas por versões antigas em `UserDefaults` migram para o Keychain na primeira leitura
    private static func load(_ key: String) -> AuthUser? {
        if let legacy = UserDefaults.standard.data(forKey: key), Keychain.save(legacy, for: key) {
            UserDefaults.standard.removeObject(forKey: key)
        }
        return Keychain.load(key).flatMap { try? JSONDecoder().decode(AuthUser.self, from: $0) }
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

// MARK: - Keychain

/// Itens do app no Keychain, legíveis só neste aparelho e depois do primeiro desbloqueio
enum Keychain {
    private static let service = "GymBros.auth"

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    @discardableResult
    static func save(_ data: Data, for account: String) -> Bool {
        let attributes: [String: Any] = [kSecValueData as String: data,
                                         kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query(account) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            return SecItemAdd(query(account).merging(attributes) { $1 } as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    static func load(_ account: String) -> Data? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    @discardableResult
    static func delete(_ account: String) -> Bool {
        let status = SecItemDelete(query(account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

// MARK: - Dados da conta no aparelho

/// Tudo o que é da conta e está neste aparelho: o banco inteiro (treinos, bros, rotinas, medidas, ligas, check-ins…)
/// e as chaves de usuário do UserDefaults. Sair ou excluir a conta tira tudo; a cópia da conta (AccountSync) devolve ao entrar.
@MainActor
enum AccountData {
    /// Chaves sociais que saem ao excluir a conta mesmo no `wipeSocial`
    static let defaultsKeys = ["friendCode", "declinedFriendRequests", "pendingRetractions", "cloudUserID", "publishedAvatar"]
    static let defaultsPrefixes = ["publishedProfile-"]

    /// Chaves de usuário: vão na cópia da conta e saem do aparelho ao sair. As do servidor simulado
    /// (`mock…`), o tutorial (já separado por conta) e o dono dos dados ficam.
    static let userKeys: [String] = Backup.settingKeys + [
        "achievementsSeen", "profilePhoto", "publicStats", "publicMonster", "publicAchievements",
        "remindersOn", "reminderMinute", "reminderRoutineOnly", "weeklySummary", "storyFrame", "headphoneInfoSeen",
        "dexRevealAll", "deloadUntil", "deloadSnooze", "barCountsBar", PendingRoutineUpdate.key,
        "gymNotifyArrival", "gymAutoFinish", "gymInsideID", "gymArrival",
        "friendCode", "declinedFriendRequests", "pendingRetractions", DemoAccount.seededKey, ProfilePhotos.showKey,
        "recentWorkoutTypes", DuelStore.fightersKey, "duelScoreRecords", RetiredActivities.key,
        TradeLedger.basesKey, TradeLedger.goneKey, TradeLedger.appliedKey, PendingJoins.key, BroDeck.seenKey, ComingFeedback.key,
        MockRoutinesBackend.publishedKey, MockRoutinesBackend.likedKey, MockRoutinesBackend.savedKey, HealthAutoPost.key, StartIntentRouter.askedKey, WhatsNew.seenKey, LeagueRemoteStore.privacyRepublishKey,
        ScreenTips.key,
    ] + HealthSync.defaultsKeys + ModerationStore.defaultsKeys + Terms.defaultsKeys + InboxStore.defaultsKeys + NotificationPrefs.defaultsKeys
        + MusicShareStore.defaultsKeys + LiveShare.defaultsKeys

    /// Chaves que só limpam (refeitas sozinhas ou ligadas a uma sessão)
    static let transientKeys = ["cloudUserID"]

    /// Chaves de usuário presentes, como property list (aceita qualquer tipo do UserDefaults)
    static func settings(_ defaults: UserDefaults) -> Data? {
        var out: [String: Any] = [:]
        for k in Set(userKeys) { if let v = defaults.object(forKey: k) { out[k] = v } }
        return try? PropertyListSerialization.data(fromPropertyList: out, format: .binary, options: 0)
    }

    /// Troca as chaves de usuário pelas da cópia (as que não estão nela saem)
    static func apply(_ data: Data, to defaults: UserDefaults) {
        let values = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] ?? [:]
        for k in Set(userKeys) { defaults.set(values[k], forKey: k) }
    }

    static func wipeSocial(context: ModelContext, defaults: UserDefaults = .standard) throws {
        try context.delete(model: CheckInComment.self)
        try context.delete(model: CheckInReview.self)
        try context.delete(model: LeagueMessage.self)
        try context.delete(model: LeagueCheckIn.self)
        try context.delete(model: League.self)
        try context.save()
        for k in defaultsKeys { defaults.removeObject(forKey: k) }
        for k in defaults.dictionaryRepresentation().keys where defaultsPrefixes.contains(where: k.hasPrefix) {
            defaults.removeObject(forKey: k)
        }
        for k in ModerationStore.defaultsKeys + Terms.defaultsKeys { defaults.removeObject(forKey: k) }
        LeagueRemoteStore.shared.reset()
        DuelStore.shared.reset()
        TradeStore.shared.reset()
        FriendsStore.shared.reset()
        for k in InboxStore.defaultsKeys { defaults.removeObject(forKey: k) }
        InboxStore.shared.reset()
        ModerationStore.shared.reload()
    }

    /// Tira do aparelho tudo o que é da conta: banco, chaves de usuário e o resumo do widget no App Group
    static func wipeAll(context: ModelContext, defaults: UserDefaults = .standard, widget: UserDefaults? = WidgetData.defaults) throws {
        try wipeSocial(context: context, defaults: defaults)
        try Backup.deleteAll(in: context)
        try context.save()
        for k in Set(userKeys + transientKeys) { defaults.removeObject(forKey: k) }
        // A divisão dos atributos é da conta (vai no snapshot dela) e tem cache em memória
        ActivitySplits.replace([:])
        WidgetData.clear(widget)
    }

    /// Há algo da pessoa no aparelho? (o ovo inicial sozinho não conta)
    static func hasData(context: ModelContext) -> Bool {
        func any<T: PersistentModel>(_ type: T.Type) -> Bool { ((try? context.fetchCount(FetchDescriptor<T>())) ?? 0) > 0 }
        let monsters = (try? context.fetchCount(FetchDescriptor<Monster>())) ?? 0
        return any(Activity.self) || any(Routine.self) || any(WorkoutSession.self) || any(BodyEntry.self) || any(League.self)
            || any(CustomExercise.self) || any(Gym.self) || any(PersonalRecord.self) || any(WodResult.self) || any(RouteRecord.self)
            || monsters > 1
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

    /// O mesmo Apple ID do aparelho, como na Apple de verdade (sair e entrar de novo traz os mesmos dados)
    private static let appleKey = "mockAppleAccount"

    /// Simula a folha da Apple: devolve um e-mail de retransmissão, como a Apple faz ao ocultar o e-mail
    func signInWithApple() async throws -> AuthUser {
        try await Task.sleep(for: .milliseconds(600))
        let name = UserDefaults.standard.string(forKey: "trainerName") ?? ""
        let seed = UserDefaults.standard.string(forKey: Self.appleKey) ?? UUID().uuidString.lowercased()
        UserDefaults.standard.set(seed, forKey: Self.appleKey)
        return AuthUser(id: "apple-" + seed.prefix(8), name: name,
                        email: "\(seed.suffix(10))@privaterelay.appleid.com", provider: .apple, token: token())
    }

    /// Sem servidor não dá para conferir a senha: qualquer senha válida entra
    func signIn(email: String, password: String) async throws -> AuthUser {
        try await Task.sleep(for: .milliseconds(500))
        let name = Self.accounts[email] ?? (email == DemoAccount.email ? DemoAccount.name : nil) ?? String(email.split(separator: "@").first ?? "").capitalized
        return AuthUser(id: "email-" + email, name: name, email: email, provider: .email, token: token())
    }

    func signUp(name: String, email: String, password: String) async throws -> AuthUser {
        try await Task.sleep(for: .milliseconds(500))
        guard Self.accounts[email] == nil else { throw AuthError.emailInUse }
        Self.accounts[email] = name
        return AuthUser(id: "email-" + email, name: name, email: email, provider: .email, token: token())
    }

    func signOut(_ user: AuthUser) async {}

    /// Sem servidor, a "conta" é o cadastro simulado e o estado de amigos de exemplo guardado no aparelho
    func deleteAccount(_ user: AuthUser) async throws {
        try await Task.sleep(for: .milliseconds(400))
        Self.accounts[user.email] = nil
        if user.provider == .apple { UserDefaults.standard.removeObject(forKey: Self.appleKey) }
        MockFriendsBackend.reset()
        MockModerationBackend.reset()
        MockInboxBackend.reset()
        UserDefaults.standard.removeObject(forKey: MockDuelServer.key)
    }
}

// MARK: - Tela

struct LoginView: View {
    /// Por que a conta é pedida aqui (ex.: "Entre para usar as ligas")
    var reason: String?
    /// Tela raiz do app sem sessão: não tem como fechar
    var required = false
    @Environment(\.dismiss) private var dismiss
    @State private var store = AuthStore.shared
    @State private var creating = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @State private var showTerms = false
    @State private var showPrivacy = false
    @State private var notice: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 10) {
                    LivingMonster(form: MonsterForm(stage: .baby, attribute: nil), progress: 0.5).frame(width: 120, height: 120)
                    Text("GymBros").gmFont(34, weight: .black, design: .rounded, relativeTo: .largeTitle).foregroundStyle(Theme.accent)
                    Text(reason ?? "Seus treinos chocam e evoluem um bro.").font(.subheadline).foregroundStyle(Theme.dim)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)

                GMSegmented(options: [(false, "Entrar"), (true, "Criar conta")], selection: $creating)
                VStack(spacing: 10) {
                    if creating { GMTextField(placeholder: "Seu nome", text: $name, capitalization: .words) }
                    GMTextField(placeholder: "E-mail", text: $email, keyboard: .emailAddress, capitalization: .never)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                    GMSecureField(placeholder: "Senha (mínimo 8 caracteres)", text: $password, contentType: creating ? .newPassword : .password)
                }
                if let error {
                    Text(error).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.danger).multilineTextAlignment(.center)
                }
                if let notice {
                    Text(notice).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent).multilineTextAlignment(.center)
                }
                if !creating, Backend.mode == .firebase {
                    Button("Esqueci minha senha", action: forgot)
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent).disabled(busy)
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

                if Backend.mode == .cloudKit || (Backend.mode == .firebase && Backend.appleCapabilities) {
                    appleButton
                }

                #if DEBUG
                DevAccountPicker { account in run { store.signIn(as: account) } }
                #endif

                if DemoAccount.isAvailable {
                    GMButton("Entrar com conta de demonstração", icon: "person.crop.circle.badge.checkmark", kind: .secondary, enabled: !busy) {
                        run { try await store.signInDemo() }
                    }
                }

                if Backend.mode == .mock {
                    Text("Ainda não há servidor: o login é simulado e os dados da conta ficam guardados neste iPhone.")
                        .font(.caption).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                }
                legal
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.bg.ignoresSafeArea())
        .overlay(alignment: .topLeading) { if !required { GMIconButton(icon: "xmark", label: "Fechar") { dismiss() }.padding(16) } }
        .overlay { if busy { ProgressView().controlSize(.large).tint(Theme.accent) } }
        .gmModal(isPresented: $showTerms) { TermsView() }
        .gmModal(isPresented: $showPrivacy) { PrivacyPolicyView() }
    }

    private var legal: some View {
        VStack(spacing: 6) {
            Text("Antes de publicar, você aceita os termos de uso: tolerância zero para conteúdo ofensivo e abuso.")
                .font(.caption).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
            HStack(spacing: 16) {
                Button("Termos de uso") { showTerms = true }
                Button("Privacidade") { showPrivacy = true }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.accent)
        }
    }

    /// Botão oficial da Apple (branco no tema escuro). O toque vai para o AuthStore, que usa o backend do modo
    /// atual: o simulado no `.mock`, a folha da Apple de verdade no `.cloudKit` (AppleIDAuthorization).
    private var appleButton: some View {
        Button { run { try await store.signInWithApple() } } label: {
            SignInWithAppleButton(.continue, onRequest: { _ in }, onCompletion: { _ in })
                .signInWithAppleButtonStyle(.white)
                .allowsHitTesting(false)
                .frame(height: 50)
                .clipShape(.rect(cornerRadius: Theme.radiusM))
        }
        .buttonStyle(GMPress())
        .disabled(busy)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Continuar com a Apple")
        .accessibilityAddTraits(.isButton)
    }

    /// Link para criar uma senha nova, no e-mail digitado
    private func forgot() {
        error = nil
        notice = nil
        guard !email.trimmingCharacters(in: .whitespaces).isEmpty else { return error = "Digite seu e-mail acima e toque de novo." }
        busy = true
        Task {
            do {
                try await store.resetPassword(email: email)
                // Por segurança o Firebase não diz se o e-mail tem conta: a mensagem é a mesma
                notice = "Se \(AuthStore.clean(email)) tiver conta, chega um link para criar uma senha nova. Veja também o spam."
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        error = nil
        notice = nil
        busy = true
        Task {
            do {
                try await action()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                if !required { dismiss() }
            } catch {
                self.error = error.localizedDescription
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
            busy = false
        }
    }
}
