import SwiftData
import XCTest
@testable import GymBros

/// Denunciar some na hora só para quem denunciou; bloquear esconde a pessoa em tudo (menos na pontuação) e desfaz a amizade
final class ModerationTests: GymTestCase {
    private var defaults: UserDefaults!
    private var suite = ""
    private var backend: FakeModerationBackend!
    private var store: ModerationStore!
    private var unfriended: [String] = []
    private var access: AccessStore!

    override func setUp() async throws {
        try await super.setUp()
        suite = "ModerationTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        backend = FakeModerationBackend()
        unfriended = []
        access = await signedInAccess()
        store = makeStore()
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try await super.tearDown()
    }

    private func makeStore() -> ModerationStore {
        let s = ModerationStore(defaults: defaults)
        s.backend = backend
        s.access = access
        s.unfriend = { [weak self] id in self?.unfriended.append(id) }
        return s
    }

    private func item(_ id: String, by member: String, me: Bool = false, photo: Bool = false) -> FeedItem {
        FeedItem(id: id, memberID: me ? "me" : member, name: member, avatar: .egg, isMe: me, date: .now, title: "Treino", note: "",
                 kind: .corrida, minutes: 30, score: 10, photo: nil, hasPhoto: photo)
    }

    func testReportHidesOnlyThatContentAndReachesServer() async {
        let feed = [item("a1", by: "ana"), item("a2", by: "ana"), item("m1", by: "eu", me: true)]

        await store.report(ReportedContent(kind: .checkIn, id: "a1", authorID: "ana"), reason: .spam)

        XCTAssertEqual(store.visible(feed).map(\.id), ["a2", "m1"])
        let reports = await backend.reports
        XCTAssertEqual(reports.map(\.0.id), ["a1"])
        XCTAssertEqual(reports.first?.1, .spam)
        XCTAssertTrue(store.outbox.isEmpty)
        XCTAssertTrue(unfriended.isEmpty)
    }

    func testReportedPhotoKeepsCheckInWithoutPhoto() async {
        await store.report(ReportedContent(kind: .photo, id: "a1", authorID: "ana"), reason: .sexual)

        let shown = store.visible([item("a1", by: "ana", photo: true)])
        XCTAssertEqual(shown.count, 1)
        XCTAssertFalse(shown[0].hasPhoto)
    }

    func testReportOfflineStaysHiddenAndRetries() async {
        await backend.setFails(true)
        await store.report(ReportedContent(kind: .message, id: "msg", authorID: "bruno"), reason: .offensive)

        XCTAssertTrue(store.isHidden(.message, "msg"))
        XCTAssertEqual(store.outbox.count, 1)
        XCTAssertEqual(makeStore().outbox.count, 1, "A fila sobrevive a reabrir o app")

        await backend.setFails(false)
        await store.flush()
        XCTAssertTrue(store.outbox.isEmpty)
        let reports = await backend.reports
        XCTAssertEqual(reports.count, 1)
    }

    func testBlockHidesPersonEverywhereAndUnfriends() async {
        let mineComment = CheckInComment(itemID: "x", text: "🔥")
        let anaComment = CheckInComment(itemID: "x", text: "oi", authorID: "ana", authorName: "Ana")
        let messages = [RemoteMessage(id: "1", memberID: "ana", date: .now, text: "oi"),
                        RemoteMessage(id: "2", memberID: "bruno", date: .now, text: "bora")]
        let people = [RemoteFriend(id: "ana", name: "Ana", formID: "", code: "A"), RemoteFriend(id: "bruno", name: "Bruno", formID: "", code: "B")]

        await store.block(userID: "ana", name: "Ana")

        XCTAssertEqual(unfriended, ["ana"])
        XCTAssertEqual(store.visible([item("a1", by: "ana"), item("b1", by: "bruno")]).map(\.id), ["b1"])
        XCTAssertEqual(store.visible([mineComment, anaComment]).map(\.text), ["🔥"])
        XCTAssertEqual(store.visible(messages).map(\.id), ["2"])
        XCTAssertEqual(store.visible(people).map(\.id), ["bruno"])
        let blocked = await backend.blocked
        XCTAssertEqual(blocked, ["ana"])
        XCTAssertEqual(makeStore().blocked.map(\.id), ["ana"])
    }

    func testBlockDoesNotChangeLeagueScore() async {
        let league = MockLeague.make()
        let feed = LeagueBoard.feed(league: league, mine: [], activities: [:], me: "Eu", myAvatar: .egg, remote: MockLeagueBackend.build(league.key))
        let before = LeagueBoard.ranking(feed: feed, league: league, me: "Eu", myAvatar: .egg, since: nil)
        guard let someone = feed.first?.memberID else { return XCTFail("A liga de exemplo deveria ter check-ins") }

        await store.block(userID: someone, name: "Alguém")

        XCTAssertFalse(store.visible(feed).contains { $0.memberID == someone })
        let after = LeagueBoard.ranking(feed: feed, league: league, me: "Eu", myAvatar: .egg, since: nil)
        XCTAssertEqual(after.map(\.id), before.map(\.id))
        XCTAssertEqual(after.map(\.score), before.map(\.score))
    }

    func testUnblockShowsAgainWithoutRefriending() async {
        await store.block(userID: "ana", name: "Ana")
        await store.unblock("ana")

        XCTAssertFalse(store.isBlocked("ana"))
        XCTAssertEqual(store.visible([item("a1", by: "ana")]).count, 1)
        let blocked = await backend.blocked
        XCTAssertTrue(blocked.isEmpty)
        XCTAssertEqual(unfriended, ["ana"])
    }

    func testRefreshTakesServerList() async {
        await backend.seed([BlockedUser(id: "rafa", name: "Rafa")])
        await store.refresh()
        XCTAssertEqual(store.blocked.map(\.id), ["rafa"])
    }

    func testAccountDeletionClearsBlocksAndReports() async throws {
        await store.block(userID: "ana", name: "Ana")
        await store.report(ReportedContent(kind: .comment, id: "c", authorID: "bruno"), reason: .other)
        let schema = AppData.schema
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true,
                                                                                          cloudKitDatabase: .none))

        try AccountData.wipeSocial(context: container.mainContext, defaults: defaults)

        for k in ModerationStore.defaultsKeys { XCTAssertNil(defaults.object(forKey: k), k) }
        let fresh = makeStore()
        XCTAssertTrue(fresh.blocked.isEmpty)
        XCTAssertTrue(fresh.hidden.isEmpty)
    }

    func testMockBackendKeepsReportsAndBlocksUntilReset() async throws {
        let keys = [MockModerationBackend.reportsKey, MockModerationBackend.blocksKey]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer { for (k, v) in zip(keys, saved) { UserDefaults.standard.set(v, forKey: k) } }
        MockModerationBackend.reset()
        let mock = MockModerationBackend()

        try await mock.report(content: ReportedContent(kind: .profile, id: "gui", authorID: "gui"), reason: .offensive)
        try await mock.report(content: ReportedContent(kind: .profile, id: "gui", authorID: "gui"), reason: .spam)
        try await mock.block(userID: "gui", name: "Gui")
        XCTAssertEqual(MockModerationBackend.reports.map(\.reason), [.spam])
        let blocked = try await mock.blockedUsers()
        XCTAssertEqual(blocked.map(\.id), ["gui"])

        MockModerationBackend.reset()
        XCTAssertTrue(MockModerationBackend.reports.isEmpty)
        let after = try await mock.blockedUsers()
        XCTAssertTrue(after.isEmpty)
    }
}

private actor FakeModerationBackend: ModerationBackend {
    private(set) var reports: [(ReportedContent, ReportReason)] = []
    private(set) var blocked: [String] = []
    private var users: [BlockedUser] = []
    private var fails = false

    func setFails(_ f: Bool) { fails = f }
    func seed(_ list: [BlockedUser]) { users = list }

    func report(content: ReportedContent, reason: ReportReason) async throws {
        if fails { throw URLError(.notConnectedToInternet) }
        reports.append((content, reason))
    }

    func block(userID: String, name: String) async throws {
        if fails { throw URLError(.notConnectedToInternet) }
        blocked.append(userID)
        users.append(BlockedUser(id: userID, name: name))
    }

    func unblock(userID: String) async throws {
        if fails { throw URLError(.notConnectedToInternet) }
        blocked.removeAll { $0 == userID }
        users.removeAll { $0.id == userID }
    }

    func blockedUsers() async throws -> [BlockedUser] { users }
}
