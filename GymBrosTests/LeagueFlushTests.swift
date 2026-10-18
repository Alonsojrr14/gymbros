import SwiftData
import XCTest
@testable import GymBros

/// LeagueRemoteStore.flush: um envio por vez, syncedAt gravado e itens apagados durante a rede
final class LeagueFlushTests: GymTestCase {
    private static let outboxKey = "pendingRetractions"
    private var savedOutbox: Any?

    override func setUp() async throws {
        try await super.setUp()
        savedOutbox = UserDefaults.standard.object(forKey: Self.outboxKey)
        UserDefaults.standard.removeObject(forKey: Self.outboxKey)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: Self.outboxKey)
        if let savedOutbox { UserDefaults.standard.set(savedOutbox, forKey: Self.outboxKey) }
        try await super.tearDown()
    }

    private func container() throws -> ModelContainer {
        try ModelContainer(for: AppData.schema,
                           configurations: ModelConfiguration(schema: AppData.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }

    private func seed(_ ctx: ModelContext) throws -> (league: League, checkIn: LeagueCheckIn, message: LeagueMessage) {
        let league = League(name: "Teste", emoji: "🏆", scoring: .pontos)
        let activity = Activity(kind: .corrida, date: .now, minutes: 30, effort: 5)
        let checkIn = LeagueCheckIn(leagueUUID: league.uuid, activityUUID: activity.uuid, title: "Corrida", note: "", date: .now, photo: nil)
        let message = LeagueMessage(leagueUUID: league.uuid, text: "Bora")
        ctx.insert(league)
        ctx.insert(activity)
        ctx.insert(checkIn)
        ctx.insert(message)
        try ctx.save()
        return (league, checkIn, message)
    }

    func testConcurrentFlushesSendEachItemOnce() async throws {
        let c = try container()
        let ctx = c.mainContext
        let (league, checkIn, message) = try seed(ctx)
        let retracted = UUID()
        UserDefaults.standard.set([league.uuid.uuidString: [retracted.uuidString]], forKey: Self.outboxKey)

        let backend = RecordingLeagueBackend()
        let store = LeagueRemoteStore()
        store.backend = backend
        store.access = await signedInAccess()

        let first = Task { await store.flush(context: ctx) }
        let second = Task { await store.flush(context: ctx) }
        await store.flush(context: ctx)
        await first.value
        await second.value

        let calls = await backend.calls
        XCTAssertEqual(calls.created, [league.uuid])
        XCTAssertEqual(calls.memberships, 1)
        XCTAssertEqual(calls.published, [checkIn.uuid])
        XCTAssertEqual(calls.retracted, [retracted])
        XCTAssertEqual(calls.sent, [message.uuid])

        XCTAssertNotNil(league.syncedAt)
        XCTAssertNotNil(checkIn.syncedAt)
        XCTAssertNotNil(message.syncedAt)
        XCTAssertTrue(LeagueOutbox.retractions.isEmpty)
        XCTAssertNil(store.lastError)
    }

    func testItemsDeletedDuringAwaitDoNotCrash() async throws {
        let c = try container()
        let ctx = c.mainContext
        let (league, checkIn, message) = try seed(ctx)
        let leagueID = league.persistentModelID, checkInID = checkIn.persistentModelID

        let backend = RecordingLeagueBackend(
            onCreate: { @MainActor in
                if let l = c.mainContext.model(for: leagueID) as? League { c.mainContext.delete(l) }
            },
            onPublish: { @MainActor in
                if let ci = c.mainContext.model(for: checkInID) as? LeagueCheckIn { c.mainContext.delete(ci) }
            })
        let store = LeagueRemoteStore()
        store.backend = backend
        store.access = await signedInAccess()

        await store.flush(context: ctx)

        let calls = await backend.calls
        XCTAssertEqual(calls.published, [checkIn.uuid])
        XCTAssertEqual(calls.sent, [message.uuid])
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<League>()), 0)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<LeagueCheckIn>()), 0)
        XCTAssertNotNil(message.syncedAt)
        XCTAssertNil(store.lastError)
    }
}

/// Servidor que aceita tudo como o MockLeagueBackend, mas anota cada chamada e demora um pouco para dar tempo de outro flush entrar
private actor RecordingLeagueBackend: LeagueBackend {
    struct Calls: Sendable {
        var created: [UUID] = []
        var memberships = 0
        var published: [UUID] = []
        var retracted: [UUID] = []
        var sent: [UUID] = []
    }

    private(set) var calls = Calls()
    private let onCreate: (@MainActor @Sendable () -> Void)?
    private let onPublish: (@MainActor @Sendable () -> Void)?
    private let mock = MockLeagueBackend()

    init(onCreate: (@MainActor @Sendable () -> Void)? = nil, onPublish: (@MainActor @Sendable () -> Void)? = nil) {
        self.onCreate = onCreate
        self.onPublish = onPublish
    }

    private func pause() async { try? await Task.sleep(for: .milliseconds(30)) }

    func fetch(_ league: LeagueKey, now: Date) async throws -> RemoteLeague { try await mock.fetch(league, now: now) }

    func send(_ messages: [OutgoingMessage], to league: LeagueKey) async throws -> [UUID] {
        calls.sent += messages.map(\.id)
        await pause()
        return try await mock.send(messages, to: league)
    }

    func create(_ league: LeagueDraft) async throws {
        calls.created.append(league.uuid)
        await pause()
        await onCreate?()
    }

    func join(code: String) async throws -> LeagueDraft? { nil }

    func setMembership(_ membership: Membership, in league: LeagueKey) async throws {
        calls.memberships += 1
        await pause()
    }

    func publish(_ checkIns: [OutgoingCheckIn], to league: LeagueKey) async throws -> [UUID] {
        calls.published += checkIns.map(\.id)
        await pause()
        await onPublish?()
        return try await mock.publish(checkIns, to: league)
    }

    func retract(_ checkInIDs: [UUID], from league: LeagueKey) async throws {
        calls.retracted += checkInIDs
        await pause()
    }

    func leave(_ league: LeagueKey) async throws {}
}
