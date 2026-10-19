import CryptoKit
import Foundation
import Observation
import SwiftData
import SwiftUI
import UserNotifications
import WidgetKit

// Dados da conta: treinos, bros, rotinas, recordes, medidas, ligas e ajustes são da conta, não do aparelho.
// O aparelho guarda a cópia de trabalho; a cópia da conta (mesmo formato do Backup, com ajustes de usuário e fotos
// dos check-ins) sobe para o servidor depois de mudanças e ao ir para segundo plano, e volta ao entrar.

/// Contrato com o servidor da cópia da conta
protocol AccountDataBackend: Sendable {
    func upload(_ snapshot: Backup, accountID: String) async throws
    /// `nil`: a conta ainda não tem dados no servidor
    func download(accountID: String) async throws -> Backup?
    func delete(accountID: String) async throws
}

enum AccountSyncError: LocalizedError {
    case noServer

    var errorDescription: String? {
        switch self {
        case .noServer: "Os dados da conta precisam do servidor próprio do GymBros, que ainda não existe."
        }
    }
}

// MARK: - Servidor simulado

/// "Servidor" no próprio aparelho: um arquivo por conta em Application Support/MockServer, fora do banco SwiftData.
/// Sai junto com o app; o nome do arquivo é o hash da conta (e-mail não vira nome de arquivo).
struct MockAccountDataBackend: AccountDataBackend {
    let folder: URL
    /// Onde os outros servidores simulados guardam o estado (nil: `UserDefaults.standard`)
    let serverSuite: String?

    /// Estado dos outros servidores simulados (amigos, mensagens, denúncias, bloqueios e X1): no servidor real é por conta
    static let socialKeys = ["mockFriends", "mockInbox", "mockReports", "mockBlocks", MockDuelServer.key]

    init(folder: URL = URL.applicationSupportDirectory.appending(path: "MockServer", directoryHint: .isDirectory), serverSuite: String? = nil) {
        self.folder = folder
        self.serverSuite = serverSuite
    }

    private func file(_ accountID: String) -> URL { folder.appending(path: AccountSync.digest(accountID) + ".json") }
    private func socialFile(_ digest: String) -> URL { folder.appending(path: digest + ".social.plist") }
    private var server: UserDefaults { serverSuite.flatMap(UserDefaults.init(suiteName:)) ?? .standard }

    /// Saindo da conta: o estado simulado dela vai para o arquivo dela e sai do aparelho
    func park(owner digest: String) throws {
        var out: [String: Any] = [:]
        for k in Self.socialKeys { if let v = server.object(forKey: k) { out[k] = v } }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: out, format: .binary, options: 0)
            .write(to: socialFile(digest), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        for k in Self.socialKeys { server.removeObject(forKey: k) }
    }

    /// Entrando: volta o estado simulado da conta, se ela já saiu antes. Sem arquivo, o que está no aparelho já é dela.
    func unpark(owner digest: String) {
        let url = socialFile(digest)
        guard let data = try? Data(contentsOf: url),
              let values = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else { return }
        for k in Self.socialKeys { server.set(values[k], forKey: k) }
        try? FileManager.default.removeItem(at: url)
    }

    func upload(_ snapshot: Backup, accountID: String) async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Backup.encoder.encode(snapshot).write(to: file(accountID), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func download(accountID: String) async throws -> Backup? {
        let url = file(accountID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Backup.decoder.decode(Backup.self, from: Data(contentsOf: url))
    }

    func delete(accountID: String) async throws {
        for url in [file(accountID), socialFile(AccountSync.digest(accountID))] where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

/// Modo `.cloudKit`: a cópia tem dados do Apple Saúde, que não podem ir para o iCloud (guideline 5.1.3(ii)).
/// Fica para o servidor próprio (docs/cloudkit.md, "Dados da conta").
struct ServerAccountDataBackend: AccountDataBackend {
    func upload(_ snapshot: Backup, accountID: String) async throws { throw AccountSyncError.noServer }
    func download(accountID: String) async throws -> Backup? { throw AccountSyncError.noServer }
    func delete(accountID: String) async throws { throw AccountSyncError.noServer }
}

// MARK: - Sincronização

@MainActor @Observable
final class AccountSync {
    static let shared = AccountSync()

    enum Phase: Equatable {
        case idle, loading, leaving
        case ready(String)
        case failed(String)
    }

    /// Hash da conta dona dos dados locais. Sem valor: dados de antes da conta obrigatória (adotados no próximo login).
    static let ownerKey = "accountDataOwner"
    /// Hash da conta excluída cujos dados ainda não saíram do aparelho (a limpeza falhou ou o app fechou no meio)
    static let pendingWipeKey = "accountDataPendingWipe"

    var backend: any AccountDataBackend = MockAccountDataBackend()
    private(set) var phase: Phase = .idle
    @ObservationIgnored let auth: AuthStore
    @ObservationIgnored private let contextProvider: () -> ModelContext
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let widget: UserDefaults?
    @ObservationIgnored private let asideFolder: URL
    @ObservationIgnored private let cleanup: @MainActor () async -> Void
    @ObservationIgnored private let reload: @MainActor () -> Void
    @ObservationIgnored var debounce: Duration = .seconds(5)
    @ObservationIgnored private var pending: Task<Void, Never>?

    init(auth: AuthStore = .shared, context: (() -> ModelContext)? = nil, defaults: UserDefaults = .standard,
         widget: UserDefaults? = WidgetData.defaults,
         asideFolder: URL = URL.applicationSupportDirectory.appending(path: "AccountSync", directoryHint: .isDirectory),
         cleanup: (@MainActor () async -> Void)? = nil, reload: (@MainActor () -> Void)? = nil) {
        self.auth = auth
        contextProvider = context ?? { AppData.container.mainContext }
        self.defaults = defaults
        self.widget = widget
        self.asideFolder = asideFolder
        self.cleanup = cleanup ?? Self.deviceCleanup
        self.reload = reload ?? Self.deviceReload
    }

    private var context: ModelContext { contextProvider() }

    nonisolated static func digest(_ accountID: String) -> String {
        SHA256.hash(data: Data(accountID.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func isReady(for userID: String?) -> Bool { phase == .ready(userID ?? "") && userID != nil }

    var owner: String? { defaults.string(forKey: Self.ownerKey) }

    /// Ao entrar (ou abrir o app já logado). Dados de outra conta saem do aparelho; se o servidor tem dados desta conta,
    /// eles voltam; se não tem, os dados locais sem dono (de antes da conta obrigatória) passam a ser desta conta.
    /// Nada é apagado sem antes virar uma cópia em Application Support/AccountSync.
    func enter(_ user: AuthUser) async {
        if isReady(for: user.id) || phase == .loading { return }
        let me = Self.digest(user.id)
        if owner == me {
            phase = .ready(user.id)
            return
        }
        phase = .loading
        do {
            try await finishPendingDeletion()
            if let other = owner {
                try setAside("conta-" + other.prefix(12))
                try await wipe()
                try (backend as? MockAccountDataBackend)?.park(owner: other)
            }
            (backend as? MockAccountDataBackend)?.unpark(owner: me)
            if let remote = try await backend.download(accountID: user.id) {
                try setAside("sem-dono-" + me.prefix(12))
                try await wipe()
                try remote.restore(into: context, defaults: defaults)
                reload()
            }
            if (defaults.string(forKey: "trainerName") ?? "").isEmpty, !user.name.isEmpty {
                defaults.set(user.name, forKey: "trainerName")
            }
            defaults.set(me, forKey: Self.ownerKey)
            phase = .ready(user.id)
            try? await upload()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Sobe depois de um tempo sem mudanças (cada mudança recomeça a espera)
    func scheduleUpload() {
        guard case .ready = phase else { return }
        pending?.cancel()
        pending = Task { [debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            try? await self.upload()
        }
    }

    /// Indo para segundo plano: sobe já, com tempo extra do sistema para terminar
    func uploadInBackground() {
        guard case .ready = phase else { return }
        pending?.cancel()
        let id = UIApplication.shared.beginBackgroundTask(withName: "AccountSync")
        Task {
            try? await upload()
            UIApplication.shared.endBackgroundTask(id)
        }
    }

    /// Só sobe a cópia da conta que é dona dos dados locais
    func upload() async throws {
        guard case .ready(let id) = phase, owner == Self.digest(id) else { return }
        let snapshot = try Backup.make(context: context, defaults: defaults, account: true)
        try await backend.upload(snapshot, accountID: id)
    }

    /// Sobe tudo e só então tira do aparelho os dados da conta. Sem conseguir subir, nada sai e a sessão continua.
    func signOut() async throws {
        guard let user = auth.user else { return }
        pending?.cancel()
        let owned = isReady(for: user.id) && owner == Self.digest(user.id)
        if owned { try await upload() }
        phase = .leaving
        defer { phase = .idle }
        await settle()
        // Sem conseguir limpar, o dono fica: a próxima conta guarda uma cópia e limpa antes de entrar
        if owned, (try? await wipe()) != nil {
            defaults.removeObject(forKey: Self.ownerKey)
            try? (backend as? MockAccountDataBackend)?.park(owner: Self.digest(user.id))
        }
        await auth.signOut()
    }

    /// Apaga a conta no servidor (dados e cadastro) e depois tudo dela no aparelho, inclusive a sessão no Keychain
    /// e as cópias guardadas em Application Support/AccountSync. Só lança erro se a conta continuar existindo.
    func deleteAccount() async throws {
        guard let user = auth.user else { return }
        pending?.cancel()
        try await backend.delete(accountID: user.id)
        let before = phase
        let me = Self.digest(user.id)
        do {
            try await auth.deleteAccount(context: context, defaults: defaults, widget: widget) {
                // A conta já não existe: daqui em diante o aparelho tem que ficar limpo, mesmo se o app fechar no meio
                self.defaults.set(me, forKey: Self.pendingWipeKey)
                self.phase = .leaving
                await self.settle()
            }
        } catch let error where auth.isSignedIn {
            phase = before
            // A conta continua: a cópia apagada no servidor volta
            try? await upload()
            throw error
        } catch {
            // Conta excluída, mas a limpeza falhou: tenta de novo agora e, se não der, na próxima abertura
        }
        phase = .idle
        try? await finishPendingDeletion()
    }

    /// Termina a exclusão de uma conta cujos dados ficaram no aparelho. Roda ao abrir o app e antes de entrar.
    func finishPendingDeletion() async throws {
        guard let digest = defaults.string(forKey: Self.pendingWipeKey) else { return }
        try await wipe()
        try removeAside(of: digest)
        if owner == digest || owner == nil { defaults.removeObject(forKey: Self.ownerKey) }
        defaults.removeObject(forKey: Self.pendingWipeKey)
    }

    /// Dá tempo de a tela principal sair antes de apagar o que ela mostra
    private func settle() async {
        try? await Task.sleep(for: .milliseconds(350))
    }

    private func wipe() async throws {
        try AccountData.wipeAll(context: context, defaults: defaults, widget: widget)
        await cleanup()
    }

    /// Apaga as cópias guardadas com os dados de uma conta
    private func removeAside(of digest: String) throws {
        let tag = String(digest.prefix(12))
        guard let files = try? FileManager.default.contentsOfDirectory(at: asideFolder, includingPropertiesForKeys: nil) else { return }
        for url in files where ["conta-", "sem-dono-"].contains(where: { url.lastPathComponent.hasPrefix($0 + tag + "-") }) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Guarda os dados locais num arquivo antes de tirar do aparelho (só se houver algo)
    private func setAside(_ label: String) throws {
        guard AccountData.hasData(context: context) else { return }
        try FileManager.default.createDirectory(at: asideFolder, withIntermediateDirectories: true)
        let url = asideFolder.appending(path: "\(label)-\(Int(Date.now.timeIntervalSince1970)).json")
        try Backup.encoder.encode(Backup.make(context: context, defaults: defaults, account: true))
            .write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Widget, Live Activity, notificações, lugares monitorados e recordes em memória acompanham o aparelho limpo
    static func deviceCleanup() async {
        WidgetCenter.shared.reloadAllTimelines()
        await LiveWorkout.endAll()
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        deviceReload()
    }

    /// Os stores em memória voltam a ler o que está no aparelho (vazio depois de limpar, a conta depois de restaurar)
    static func deviceReload() {
        ModerationStore.shared.reload()
        InboxStore.shared.reset()
        MusicShareStore.shared.reload()
        GymLocation.shared.startMonitoring()
        PRBook.reload()
    }
}

// MARK: - Tela

/// Entre o login e a tela principal: trazendo os dados da conta, ou saindo
struct AccountLoadingView: View {
    @State private var sync = AccountSync.shared

    var body: some View {
        VStack(spacing: 16) {
            switch sync.phase {
            case .failed(let message):
                GMEmptyState(icon: "icloud.slash", title: "Não deu para abrir sua conta", message: message)
                GMButton("Tentar de novo", icon: "arrow.clockwise") {
                    if let user = sync.auth.user { Task { await sync.enter(user) } }
                }
                GMButton("Sair", icon: "rectangle.portrait.and.arrow.right", kind: .secondary) {
                    Task { try? await sync.signOut() }
                }
            case .leaving:
                ProgressView().controlSize(.large).tint(Theme.accent)
                Text("Saindo…").font(.subheadline).foregroundStyle(Theme.dim)
            default:
                ProgressView().controlSize(.large).tint(Theme.accent)
                Text("Abrindo sua conta…").font(.subheadline).foregroundStyle(Theme.dim)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg.ignoresSafeArea())
    }
}
