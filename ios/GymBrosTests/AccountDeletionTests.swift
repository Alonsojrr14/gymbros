import SwiftData
import XCTest
@testable import GymBros

/// Excluir conta: servidor primeiro; depois sai tudo da conta no aparelho (treinos, bros, dados sociais, ajustes) e a sessão
final class AccountDeletionTests: GymTestCase {
    private static let mockKeys = ["mockAccounts", "mockFriends", "mockReports", "mockBlocks"]
    private var savedMock: [String: Any] = [:]
    private var defaults: UserDefaults!
    private var suite = ""
    private let account = "test-auth-\(UUID().uuidString)"

    override func setUp() async throws {
        try await super.setUp()
        suite = "AccountDeletionTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        savedMock = [:]
        for k in Self.mockKeys { if let v = UserDefaults.standard.object(forKey: k) { savedMock[k] = v } }
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        Keychain.delete(account)
        for k in Self.mockKeys { UserDefaults.standard.removeObject(forKey: k) }
        for (k, v) in savedMock { UserDefaults.standard.set(v, forKey: k) }
        try await super.tearDown()
    }

    private func container() throws -> ModelContainer {
        try ModelContainer(for: AppData.schema,
                           configurations: ModelConfiguration(schema: AppData.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }

    private func seed(_ ctx: ModelContext) throws {
        let league = League(name: "Teste", emoji: "🏆", scoring: .pontos)
        let activity = Activity(kind: .corrida, date: .now, minutes: 30, effort: 5)
        let checkIn = LeagueCheckIn(leagueUUID: league.uuid, activityUUID: activity.uuid, title: "Corrida", note: "", date: .now, photo: nil)
        ctx.insert(league)
        ctx.insert(activity)
        ctx.insert(checkIn)
        ctx.insert(LeagueMessage(leagueUUID: league.uuid, text: "Bora"))
        ctx.insert(CheckInComment(itemID: checkIn.uuid.uuidString, text: "🔥"))
        ctx.insert(Monster(name: "Bro", isStarter: true))
        try ctx.save()
        defaults.set("ABC123", forKey: "friendCode")
        defaults.set([league.uuid.uuidString: [UUID().uuidString]], forKey: "pendingRetractions")
        defaults.set("hash", forKey: "publishedProfile-mock")
        defaults.set("Zero", forKey: "trainerName")
    }

    private func count<T: PersistentModel>(_ type: T.Type, _ ctx: ModelContext) throws -> Int {
        try ctx.fetchCount(FetchDescriptor<T>())
    }

    func testWipeRemovesSocialDataAndKeepsWorkoutsAndBros() throws {
        let c = try container()
        let ctx = c.mainContext
        try seed(ctx)

        try AccountData.wipeSocial(context: ctx, defaults: defaults)

        XCTAssertEqual(try count(League.self, ctx), 0)
        XCTAssertEqual(try count(LeagueCheckIn.self, ctx), 0)
        XCTAssertEqual(try count(LeagueMessage.self, ctx), 0)
        XCTAssertEqual(try count(CheckInComment.self, ctx), 0)
        XCTAssertEqual(try count(Activity.self, ctx), 1)
        XCTAssertEqual(try count(Monster.self, ctx), 1)
        XCTAssertNil(defaults.object(forKey: "friendCode"))
        XCTAssertNil(defaults.object(forKey: "pendingRetractions"))
        XCTAssertNil(defaults.object(forKey: "publishedProfile-mock"))
        XCTAssertEqual(defaults.string(forKey: "trainerName"), "Zero")
    }

    func testDeleteAccountCallsServerThenEndsSession() async throws {
        let c = try container()
        let ctx = c.mainContext
        try seed(ctx)
        let backend = FakeAuthBackend()
        let store = AuthStore(account: account)
        store.backend = backend
        try await store.signIn(email: "teste@gymbros.app", password: "12345678")
        XCTAssertNotNil(Keychain.load(account))

        try await store.deleteAccount(context: ctx, defaults: defaults, widget: nil)

        let deleted = await backend.deleted
        XCTAssertEqual(deleted, ["email-teste@gymbros.app"])
        XCTAssertNil(store.user)
        XCTAssertNil(Keychain.load(account))
        XCTAssertNil(AuthStore(account: account).user)
        XCTAssertEqual(try count(League.self, ctx), 0)
        XCTAssertEqual(try count(Activity.self, ctx), 0)
        XCTAssertEqual(try count(Monster.self, ctx), 0)
        XCTAssertNil(defaults.object(forKey: "trainerName"))
    }

    func testServerFailureKeepsAccountAndData() async throws {
        let c = try container()
        let ctx = c.mainContext
        try seed(ctx)
        let store = AuthStore(account: account)
        store.backend = FakeAuthBackend(fails: true)
        try await store.signIn(email: "teste@gymbros.app", password: "12345678")

        do {
            try await store.deleteAccount(context: ctx, defaults: defaults, widget: nil)
            XCTFail("Deveria falhar")
        } catch {}

        XCTAssertNotNil(store.user)
        XCTAssertNotNil(Keychain.load(account))
        XCTAssertEqual(try count(League.self, ctx), 1)
        XCTAssertEqual(defaults.string(forKey: "friendCode"), "ABC123")
    }

    func testSignedOutPostCreatesNoCheckIns() throws {
        let c = try container()
        let ctx = c.mainContext
        let league = League(name: "Teste", emoji: "🏆", scoring: .pontos)
        let activity = Activity(kind: .corrida, date: .now, minutes: 30, effort: 5)
        ctx.insert(league)
        ctx.insert(activity)

        postCheckIns(activity: activity, leagues: [league.uuid, ProfileFeed.id], title: "Corrida", note: "", photo: nil,
                     context: ctx, signedIn: false)
        XCTAssertEqual(try count(LeagueCheckIn.self, ctx), 0)

        postCheckIns(activity: activity, leagues: [league.uuid, ProfileFeed.id], title: "Corrida", note: "", photo: nil,
                     context: ctx, signedIn: true)
        XCTAssertEqual(try count(LeagueCheckIn.self, ctx), 2)
    }

    func testSignedOutEditKeepsExistingPostsUntouched() throws {
        let c = try container()
        let ctx = c.mainContext
        let activity = Activity(kind: .corrida, date: .now, minutes: 30, effort: 5)
        ctx.insert(activity)
        postCheckIns(activity: activity, leagues: [ProfileFeed.id], title: "Corrida", note: "", photo: nil,
                     context: ctx, signedIn: true)
        let post = try XCTUnwrap(ctx.fetch(FetchDescriptor<LeagueCheckIn>()).first)
        post.syncedAt = .now

        syncCheckIns(activity: activity, destinations: [ProfileFeed.id, UUID()], title: "Outro", note: "nota", photo: nil,
                     place: nil, context: ctx, signedIn: false)

        XCTAssertEqual(try count(LeagueCheckIn.self, ctx), 1)
        XCTAssertEqual(post.title, "Corrida")
        XCTAssertNotNil(post.syncedAt)
    }

    func testMockDeletionFreesEmailAndResetsExampleFriends() async throws {
        let mock = MockAuthBackend()
        let email = "apagar-\(UUID().uuidString.prefix(8))@gymbros.app"
        let user = try await mock.signUp(name: "Teste", email: email, password: "12345678")
        _ = try await MockFriendsBackend().remove("ana")
        XCTAssertFalse(MockFriendsBackend.load().friends.contains { $0.id == "ana" })

        try await mock.deleteAccount(user)

        let again = try await mock.signUp(name: "Teste", email: email, password: "12345678")
        XCTAssertTrue(MockFriendsBackend.load().friends.contains { $0.id == "ana" })
        try await mock.deleteAccount(again)
    }
}

private actor FakeAuthBackend: AuthBackend {
    private let fails: Bool
    private(set) var deleted: [String] = []

    init(fails: Bool = false) { self.fails = fails }

    func signInWithApple() async throws -> AuthUser { throw AuthError.cancelled }

    func signIn(email: String, password: String) async throws -> AuthUser {
        AuthUser(id: "email-" + email, name: "Teste", email: email, provider: .email, token: "t")
    }

    func signUp(name: String, email: String, password: String) async throws -> AuthUser { try await signIn(email: email, password: password) }

    func signOut(_ user: AuthUser) async {}

    func deleteAccount(_ user: AuthUser) async throws {
        if fails { throw URLError(.notConnectedToInternet) }
        deleted.append(user.id)
    }
}
