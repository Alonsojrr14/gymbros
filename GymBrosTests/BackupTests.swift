import SwiftData
import XCTest
@testable import GymBros

/// Backup: export -> JSON -> restore em banco em memória, com o estado no servidor das ligas e os ajustes
final class BackupTests: GymTestCase {
    private static let keys = Backup.settingKeys + ["profilePhoto"]
    private var savedDefaults: [String: Any] = [:]
    private let synced = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() async throws {
        try await super.setUp()
        let d = UserDefaults.standard
        savedDefaults = [:]
        for k in Self.keys { if let v = d.object(forKey: k) { savedDefaults[k] = v } }
    }

    override func tearDown() async throws {
        let d = UserDefaults.standard
        for k in Self.keys { d.removeObject(forKey: k) }
        for (k, v) in savedDefaults { d.set(v, forKey: k) }
        try await super.tearDown()
    }

    private func container() throws -> ModelContainer {
        try ModelContainer(for: AppData.schema,
                           configurations: ModelConfiguration(schema: AppData.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }

    private struct Seed {
        let pending: UUID, joined: UUID, pendingCheckIn: UUID, sentCheckIn: UUID
    }

    private func seed(_ ctx: ModelContext) throws -> Seed {
        let own = League(name: "Minha", emoji: "🏆", scoring: .pontos)
        let other = League(name: "Alheia", emoji: "🔥", scoring: .treinos)
        other.joined = true
        other.syncedAt = synced
        let activity = Activity(kind: .corrida, date: .now, minutes: 30, effort: 5)
        let pending = LeagueCheckIn(leagueUUID: own.uuid, activityUUID: activity.uuid, title: "Corrida", note: "", date: .now, photo: nil)
        let sent = LeagueCheckIn(leagueUUID: other.uuid, activityUUID: activity.uuid, title: "Corrida", note: "", date: .now, photo: nil)
        sent.syncedAt = synced
        ctx.insert(own)
        ctx.insert(other)
        ctx.insert(activity)
        ctx.insert(pending)
        ctx.insert(sent)
        try ctx.save()
        return Seed(pending: own.uuid, joined: other.uuid, pendingCheckIn: pending.uuid, sentCheckIn: sent.uuid)
    }

    private func roundTrip(_ backup: Backup) throws -> Backup {
        try Backup.decoder.decode(Backup.self, from: Backup.encoder.encode(backup))
    }

    private func league(_ uuid: UUID, in ctx: ModelContext) throws -> League {
        try XCTUnwrap(ctx.fetch(FetchDescriptor<League>(predicate: #Predicate { $0.uuid == uuid })).first)
    }

    private func checkIn(_ uuid: UUID, in ctx: ModelContext) throws -> LeagueCheckIn {
        try XCTUnwrap(ctx.fetch(FetchDescriptor<LeagueCheckIn>(predicate: #Predicate { $0.uuid == uuid })).first)
    }

    func testRoundTripKeepsSyncStateAndSettings() throws {
        let d = UserDefaults.standard
        d.set(true, forKey: "autoWarmup")
        d.set(15.0, forKey: "barWeight")
        d.set("Treinadora", forKey: "trainerName")
        d.set(Data([1, 2, 3]), forKey: "profilePhoto")
        let source = try container()
        let s = try seed(source.mainContext)
        let backup = try roundTrip(Backup.make(context: source.mainContext))
        XCTAssertEqual(backup.hasSyncState, true)

        d.set(false, forKey: "autoWarmup")
        d.set(20.0, forKey: "barWeight")
        d.set("Outro", forKey: "trainerName")
        d.removeObject(forKey: "profilePhoto")

        let target = try container()
        let ctx = target.mainContext
        ctx.insert(League(name: "Some", emoji: "👻", scoring: .pontos))
        try ctx.save()
        try backup.restore(into: ctx)

        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<League>()), 2)
        let own = try league(s.pending, in: ctx)
        XCTAssertNil(own.syncedAt)
        XCTAssertFalse(own.joined)
        let other = try league(s.joined, in: ctx)
        XCTAssertEqual(other.syncedAt, synced)
        XCTAssertTrue(other.joined)
        XCTAssertNil(try checkIn(s.pendingCheckIn, in: ctx).syncedAt)
        XCTAssertEqual(try checkIn(s.sentCheckIn, in: ctx).syncedAt, synced)

        XCTAssertEqual(d.object(forKey: "autoWarmup") as? Bool, true)
        XCTAssertEqual(d.double(forKey: "barWeight"), 15)
        XCTAssertEqual(d.string(forKey: "trainerName"), "Treinadora")
        XCTAssertEqual(d.data(forKey: "profilePhoto"), Data([1, 2, 3]))
    }

    func testLegacyBackupCountsLeaguesAsSyncedAndJoined() throws {
        let source = try container()
        let s = try seed(source.mainContext)
        var backup = try Backup.make(context: source.mainContext)
        backup.exportedAt = synced
        backup.hasSyncState = nil
        backup.leagues = backup.leagues?.map { var l = $0; l.syncedAt = nil; l.joined = nil; return l }
        backup.checkIns = backup.checkIns?.map { var c = $0; c.syncedAt = nil; return c }
        backup = try roundTrip(backup)
        XCTAssertNil(backup.hasSyncState)

        let target = try container()
        let ctx = target.mainContext
        try backup.restore(into: ctx)

        for uuid in [s.pending, s.joined] {
            let l = try league(uuid, in: ctx)
            XCTAssertEqual(l.syncedAt, synced)
            XCTAssertTrue(l.joined)
        }
        for uuid in [s.pendingCheckIn, s.sentCheckIn] {
            XCTAssertEqual(try checkIn(uuid, in: ctx).syncedAt, synced)
        }
    }
}
