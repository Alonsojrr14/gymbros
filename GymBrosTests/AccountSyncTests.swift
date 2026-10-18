import SwiftData
import XCTest
@testable import GymBros

/// Dados da conta: adoção dos dados sem dono, sair limpa e entrar devolve, contas não se misturam e excluir apaga tudo.
/// Banco em memória, UserDefaults de teste e pastas temporárias: o banco, os ajustes e o servidor simulado reais ficam intocados.
final class AccountSyncTests: GymTestCase {
    private static let standardKeys = [MainMonster.key, "trainerName", "mockAppleAccount"]
    private var savedStandard: [String: Any] = [:]
    private var suites: [String] = []
    private var defaults: UserDefaults!
    private var widget: UserDefaults!
    private var serverSuite: String!
    private var folder: URL!
    private var container: ModelContainer!
    private var ctx: ModelContext { container.mainContext }
    private let keychainAccount = "test-sync-\(UUID().uuidString)"
    private var cleaned = 0
    private var reloaded = 0
    private var moderation: ModerationStore!
    private var inbox: InboxStore!

    override func setUp() async throws {
        try await super.setUp()
        savedStandard = [:]
        for k in Self.standardKeys { if let v = UserDefaults.standard.object(forKey: k) { savedStandard[k] = v } }
        defaults = suite()
        widget = suite()
        serverSuite = "AccountSyncTests-server-\(UUID().uuidString)"
        suites.append(serverSuite)
        folder = FileManager.default.temporaryDirectory.appending(path: "AccountSyncTests-\(UUID().uuidString)")
        container = try ModelContainer(for: AppData.schema,
                                       configurations: ModelConfiguration(schema: AppData.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        cleaned = 0
        reloaded = 0
        moderation = ModerationStore(defaults: defaults)
        inbox = InboxStore(defaults: defaults)
    }

    override func tearDown() async throws {
        for s in suites { UserDefaults.standard.removePersistentDomain(forName: s) }
        suites = []
        try? FileManager.default.removeItem(at: folder)
        Keychain.delete(keychainAccount)
        for k in Self.standardKeys { UserDefaults.standard.removeObject(forKey: k) }
        for (k, v) in savedStandard { UserDefaults.standard.set(v, forKey: k) }
        container = nil
        try await super.tearDown()
    }

    private func suite() -> UserDefaults {
        let name = "AccountSyncTests-\(UUID().uuidString)"
        suites.append(name)
        return UserDefaults(suiteName: name)!
    }

    private func make(_ backend: FakeAccountAuth = FakeAccountAuth()) -> AccountSync {
        let auth = AuthStore(account: keychainAccount)
        auth.backend = backend
        let sync = AccountSync(auth: auth, context: { [unowned self] in ctx }, defaults: defaults, widget: widget,
                               asideFolder: folder.appending(path: "aside"),
                               cleanup: { [unowned self] in cleaned += 1; reloadStores() },
                               reload: { [unowned self] in reloaded += 1; reloadStores() })
        sync.backend = MockAccountDataBackend(folder: folder.appending(path: "server"), serverSuite: serverSuite)
        return sync
    }

    private func signIn(_ sync: AccountSync, _ email: String) async throws -> AuthUser {
        try await sync.auth.signIn(email: email, password: "12345678")
        let user = try XCTUnwrap(sync.auth.user)
        await sync.enter(user)
        XCTAssertTrue(sync.isReady(for: user.id))
        return user
    }

    /// Como `AccountSync.deviceReload`, mas com os stores sobre os UserDefaults de teste
    private func reloadStores() {
        moderation.reload()
        inbox.reset()
    }

    private var aside: URL { folder.appending(path: "aside") }

    private func asideFiles() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: aside.path)) ?? []).sorted()
    }

    private func count<T: PersistentModel>(_ type: T.Type) throws -> Int { try ctx.fetchCount(FetchDescriptor<T>()) }

    @discardableResult
    private func seed(name: String, minutes: Int = 30) throws -> Activity {
        let activity = Activity(kind: .corrida, date: .now, minutes: minutes, effort: 5)
        activity.healthWrittenUUID = "escrito-no-saude"
        ctx.insert(activity)
        ctx.insert(Routine(name: "Treino A"))
        ctx.insert(Monster(name: "Bro", isStarter: true))
        let body = BodyEntry(date: .now, weight: 80)
        body.photoFront = Data([4, 5])
        ctx.insert(body)
        ctx.insert(LeagueCheckIn(leagueUUID: ProfileFeed.id, activityUUID: activity.uuid, title: "Corrida", note: "", date: .now,
                                 photo: Data([1, 2, 3])))
        try ctx.save()
        defaults.set(name, forKey: "trainerName")
        defaults.set(true, forKey: "remindersOn")
        defaults.set(["x"], forKey: "healthIgnored")
        Terms.accept(defaults)
        widget.set(Data([9]), forKey: "widgetData")
        widget.set(3, forKey: "pets")
        return activity
    }

    func testLocalDataWithoutOwnerIsAdoptedAndUploaded() async throws {
        let sync = make()
        try seed(name: "Dono")
        XCTAssertNil(sync.owner)

        let user = try await signIn(sync, "dono@gymbros.app")

        XCTAssertEqual(sync.owner, AccountSync.digest(user.id))
        XCTAssertEqual(try count(Activity.self), 1)
        XCTAssertEqual(try count(Routine.self), 1)
        XCTAssertEqual(defaults.string(forKey: "trainerName"), "Dono")
        let remote = try await sync.backend.download(accountID: user.id)
        XCTAssertEqual(remote?.activities.count, 1)
        XCTAssertEqual(remote?.checkIns?.first?.photo, Data([1, 2, 3]))
        XCTAssertEqual(cleaned, 0)
    }

    func testSignOutWipesDeviceAndSignInRestores() async throws {
        let sync = make()
        _ = try await signIn(sync, "ana@gymbros.app")
        let activity = try seed(name: "Ana", minutes: 42)

        try await sync.signOut()

        XCTAssertNil(sync.auth.user)
        XCTAssertNil(sync.owner)
        XCTAssertEqual(try count(Activity.self), 0)
        XCTAssertEqual(try count(Monster.self), 0)
        XCTAssertEqual(try count(BodyEntry.self), 0)
        XCTAssertEqual(try count(LeagueCheckIn.self), 0)
        XCTAssertNil(defaults.object(forKey: "trainerName"))
        XCTAssertNil(defaults.object(forKey: "remindersOn"))
        XCTAssertFalse(Terms.isAccepted(defaults))
        XCTAssertNil(widget.object(forKey: "widgetData"))
        XCTAssertNil(widget.object(forKey: "pets"))
        XCTAssertGreaterThan(cleaned, 0)

        _ = try await signIn(sync, "ana@gymbros.app")

        let restored = try XCTUnwrap(ctx.fetch(FetchDescriptor<Activity>()).first)
        XCTAssertEqual(restored.uuid, activity.uuid)
        XCTAssertEqual(restored.minutes, 42)
        XCTAssertEqual(restored.healthWrittenUUID, "escrito-no-saude")
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<BodyEntry>()).first?.photoFront, Data([4, 5]))
        XCTAssertEqual(try count(Routine.self), 1)
        XCTAssertEqual(try count(BodyEntry.self), 1)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<LeagueCheckIn>()).first?.photo, Data([1, 2, 3]))
        XCTAssertEqual(defaults.string(forKey: "trainerName"), "Ana")
        XCTAssertTrue(defaults.bool(forKey: "remindersOn"))
        XCTAssertEqual(defaults.stringArray(forKey: "healthIgnored"), ["x"])
        XCTAssertTrue(Terms.isAccepted(defaults))
    }

    func testSignInReloadsStoresAfterRestore() async throws {
        let sync = make()
        _ = try await signIn(sync, "ana@gymbros.app")
        try seed(name: "Ana")
        defaults.set(try JSONEncoder().encode(["checkIn:abc"]), forKey: ModerationStore.hiddenKey)
        moderation.reload()
        inbox.markRead("bia")
        let read = try XCTUnwrap(inbox.readUntil["bia"])

        try await sync.signOut()
        XCTAssertTrue(moderation.hidden.isEmpty)
        XCTAssertNil(inbox.readUntil["bia"])

        reloaded = 0
        _ = try await signIn(sync, "ana@gymbros.app")

        XCTAssertGreaterThan(reloaded, 0, "Depois de restaurar, os stores e o monitoramento das academias recomeçam")
        XCTAssertTrue(moderation.isHidden(.checkIn, "abc"), "O que foi denunciado continua oculto depois de entrar de novo")
        XCTAssertEqual(inbox.readUntil["bia"]?.timeIntervalSince1970 ?? 0, read.timeIntervalSince1970, accuracy: 0.001)
    }

    func testSwitchingAccountsNeverMixesData() async throws {
        let sync = make()
        _ = try await signIn(sync, "ana@gymbros.app")
        try seed(name: "Ana", minutes: 10)
        try await sync.signOut()

        let bia = try await signIn(sync, "bia@gymbros.app")
        XCTAssertEqual(try count(Activity.self), 0)
        XCTAssertEqual(try count(Routine.self), 0)
        XCTAssertEqual(defaults.string(forKey: "trainerName"), bia.name)
        XCTAssertFalse(Terms.isAccepted(defaults))
        ctx.insert(Activity(kind: .volei, date: .now, minutes: 99, effort: 5))
        try ctx.save()
        try await sync.signOut()

        _ = try await signIn(sync, "ana@gymbros.app")
        let mine = try ctx.fetch(FetchDescriptor<Activity>())
        XCTAssertEqual(mine.map(\.minutes), [10])
        XCTAssertEqual(defaults.string(forKey: "trainerName"), "Ana")
    }

    func testSimulatedSocialServerIsPerAccount() async throws {
        let sync = make()
        let server = try XCTUnwrap(UserDefaults(suiteName: serverSuite))
        server.set(Data([1]), forKey: "mockInbox")
        _ = try await signIn(sync, "ana@gymbros.app")
        XCTAssertEqual(server.data(forKey: "mockInbox"), Data([1]), "Na adoção, o estado simulado do aparelho é da conta")
        try await sync.signOut()
        XCTAssertNil(server.object(forKey: "mockInbox"))

        _ = try await signIn(sync, "bia@gymbros.app")
        XCTAssertNil(server.object(forKey: "mockInbox"))
        server.set(Data([2]), forKey: "mockFriends")
        try await sync.signOut()

        _ = try await signIn(sync, "ana@gymbros.app")
        XCTAssertEqual(server.data(forKey: "mockInbox"), Data([1]))
        XCTAssertNil(server.object(forKey: "mockFriends"))
    }

    func testDataOfAnotherOwnerIsSetAsideBeforeLeaving() async throws {
        let sync = make()
        try seed(name: "Outro")
        defaults.set(AccountSync.digest("outra-conta"), forKey: AccountSync.ownerKey)

        _ = try await signIn(sync, "ana@gymbros.app")

        XCTAssertEqual(try count(Activity.self), 0)
        let aside = try FileManager.default.contentsOfDirectory(at: folder.appending(path: "aside"), includingPropertiesForKeys: nil)
        XCTAssertEqual(aside.count, 1)
        let copy = try Backup.decoder.decode(Backup.self, from: Data(contentsOf: aside[0]))
        XCTAssertEqual(copy.activities.count, 1)
    }

    func testDeleteAccountErasesServerAndDevice() async throws {
        let auth = FakeAccountAuth()
        let sync = make(auth)
        let user = try await signIn(sync, "apagar@gymbros.app")
        try seed(name: "Apagar")
        try await sync.upload()
        let uploaded = try await sync.backend.download(accountID: user.id)
        XCTAssertNotNil(uploaded)

        try await sync.deleteAccount()

        let deleted = await auth.deleted
        XCTAssertEqual(deleted, [user.id])
        let remote = try await sync.backend.download(accountID: user.id)
        XCTAssertNil(remote)
        XCTAssertNil(sync.auth.user)
        XCTAssertNil(Keychain.load(keychainAccount))
        XCTAssertNil(sync.owner)
        XCTAssertEqual(try count(Activity.self), 0)
        XCTAssertEqual(try count(Routine.self), 0)
        XCTAssertEqual(try count(Monster.self), 0)
        XCTAssertEqual(try count(BodyEntry.self), 0)
        XCTAssertEqual(try count(LeagueCheckIn.self), 0)
        XCTAssertNil(defaults.object(forKey: "trainerName"))
        XCTAssertFalse(Terms.isAccepted(defaults))
        XCTAssertNil(widget.object(forKey: "widgetData"))
    }

    func testDeleteAccountRemovesItsSetAsideCopies() async throws {
        let sync = make()
        let user = try await signIn(sync, "apagar@gymbros.app")
        let mine = AccountSync.digest(user.id).prefix(12)
        let other = AccountSync.digest("outra").prefix(12)
        try FileManager.default.createDirectory(at: aside, withIntermediateDirectories: true)
        for name in ["conta-\(mine)-1.json", "sem-dono-\(mine)-2.json", "conta-\(other)-3.json"] {
            try Data("{}".utf8).write(to: aside.appending(path: name))
        }

        try await sync.deleteAccount()

        XCTAssertEqual(asideFiles(), ["conta-\(other)-3.json"])
        XCTAssertNil(defaults.object(forKey: AccountSync.pendingWipeKey))
    }

    func testUnfinishedDeletionIsWipedBeforeNextAccount() async throws {
        let sync = make()
        try seed(name: "Excluida")
        let deleted = AccountSync.digest("email-excluida@gymbros.app")
        defaults.set(deleted, forKey: AccountSync.ownerKey)
        defaults.set(deleted, forKey: AccountSync.pendingWipeKey)

        let bia = try await signIn(sync, "bia@gymbros.app")

        XCTAssertEqual(try count(Activity.self), 0, "Dados de conta excluída não são adotados por outra")
        XCTAssertEqual(try count(LeagueCheckIn.self), 0)
        XCTAssertEqual(asideFiles(), [], "Nem viram cópia guardada")
        XCTAssertNil(defaults.object(forKey: AccountSync.pendingWipeKey))
        XCTAssertEqual(sync.owner, AccountSync.digest(bia.id))
        XCTAssertFalse(Terms.isAccepted(defaults))
    }

    func testFailedServerDeletionKeepsEverything() async throws {
        let sync = make(FakeAccountAuth(fails: true))
        let user = try await signIn(sync, "fica@gymbros.app")
        try seed(name: "Fica")

        do {
            try await sync.deleteAccount()
            XCTFail("Deveria falhar")
        } catch {}

        XCTAssertTrue(sync.isReady(for: user.id))
        XCTAssertNotNil(sync.auth.user)
        XCTAssertEqual(try count(Activity.self), 1)
        XCTAssertEqual(defaults.string(forKey: "trainerName"), "Fica")
        XCTAssertNil(defaults.object(forKey: AccountSync.pendingWipeKey))
    }
}

private actor FakeAccountAuth: AuthBackend {
    private let fails: Bool
    private(set) var deleted: [String] = []

    init(fails: Bool = false) { self.fails = fails }

    func signInWithApple() async throws -> AuthUser { throw AuthError.cancelled }

    func signIn(email: String, password: String) async throws -> AuthUser {
        AuthUser(id: "email-" + email, name: String(email.prefix { $0 != "@" }).capitalized, email: email, provider: .email, token: "t")
    }

    func signUp(name: String, email: String, password: String) async throws -> AuthUser { try await signIn(email: email, password: password) }

    func signOut(_ user: AuthUser) async {}

    func deleteAccount(_ user: AuthUser) async throws {
        if fails { throw URLError(.notConnectedToInternet) }
        deleted.append(user.id)
    }
}
