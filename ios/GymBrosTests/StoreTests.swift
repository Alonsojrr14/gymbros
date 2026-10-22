import SwiftData
import XCTest
@testable import GymBros

/// O banco do aparelho abre com o schema versionado, sem migração destrutiva
@MainActor
final class StoreTests: XCTestCase {
    func testDeviceStoreOpensWithCurrentSchema() throws {
        let container = AppData.container
        XCTAssertNil(AppData.recoveredCopy)
        XCTAssertEqual(AppData.schema.version, Schema.Version(5, 0, 0))
        XCTAssertEqual(AppData.schema.entities.count, 19)
        XCTAssertFalse(container.configurations.first?.isStoredInMemoryOnly ?? true)
        _ = try container.mainContext.fetchCount(FetchDescriptor<Activity>())
    }

    func testInMemoryContainerWithMigrationPlan() throws {
        let config = ModelConfiguration(schema: AppData.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: AppData.schema, migrationPlan: AppMigrationPlan.self, configurations: config)
        let ctx = ModelContext(container)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Activity>()), 0)
    }

    /// Banco gravado pela V1 abre na V2 sem perder nada, com o critério suíço padrão
    func testV1StoreMigratesToV2() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("migra-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
        }
        let id = UUID()
        do {
            let v1 = Schema(versionedSchema: SchemaV1.self)
            let container = try ModelContainer(for: v1, configurations: ModelConfiguration(schema: v1, url: url, cloudKitDatabase: .none))
            let ctx = ModelContext(container)
            let l = SchemaV1.League()
            l.uuid = id
            l.name = "Antiga"
            l.tieBreakRaw = LeagueTieBreak.sequencia.rawValue
            ctx.insert(l)
            try ctx.save()
        }
        let container = try ModelContainer(for: AppData.schema, migrationPlan: AppMigrationPlan.self,
                                           configurations: ModelConfiguration(schema: AppData.schema, url: url, cloudKitDatabase: .none))
        let leagues = try ModelContext(container).fetch(FetchDescriptor<League>())
        XCTAssertEqual(leagues.count, 1)
        XCTAssertEqual(leagues.first?.uuid, id)
        XCTAssertEqual(leagues.first?.name, "Antiga")
        XCTAssertEqual(leagues.first?.tieBreak, .sequencia)
        XCTAssertEqual(leagues.first?.swiss, .pontos)
    }

    /// Banco gravado pela V3 abre na V4 com a liga, o check-in e a regra de treinos; as regras novas começam desligadas
    func testV3StoreMigratesToV4() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("migra-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
        }
        let id = UUID()
        let checkIn = UUID()
        do {
            let v3 = Schema(versionedSchema: SchemaV3.self)
            let container = try ModelContainer(for: v3, configurations: ModelConfiguration(schema: v3, url: url, cloudKitDatabase: .none))
            let ctx = ModelContext(container)
            let l = SchemaV3.League()
            l.uuid = id
            l.name = "Da V3"
            l.activityRuleRaw = "only:13"
            ctx.insert(l)
            let c = SchemaV1.LeagueCheckIn()
            c.uuid = checkIn
            c.leagueUUID = id
            c.title = "Treino"
            ctx.insert(c)
            try ctx.save()
        }
        let container = try ModelContainer(for: AppData.schema, migrationPlan: AppMigrationPlan.self,
                                           configurations: ModelConfiguration(schema: AppData.schema, url: url, cloudKitDatabase: .none))
        let ctx = ModelContext(container)
        let league = try XCTUnwrap(ctx.fetch(FetchDescriptor<League>()).first)
        XCTAssertEqual(league.uuid, id)
        XCTAssertEqual(league.activityRule.mode, .only)
        XCTAssertEqual(league.settings, LeagueSettings())
        XCTAssertEqual(league.settings.verification.preset, .off)
        let c = try XCTUnwrap(ctx.fetch(FetchDescriptor<LeagueCheckIn>()).first)
        XCTAssertEqual(c.uuid, checkIn)
        XCTAssertEqual(c.title, "Treino")
        XCTAssertEqual(c.reviewRaw, "")
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<CheckInReview>()), 0)
    }

    /// Banco gravado pela V4 abre na V5 com o check-in (prova e revisão) e o recado; as fotos a mais começam vazias
    func testV4StoreMigratesToV5() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("migra-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
        }
        do {
            let v4 = Schema(versionedSchema: SchemaV4.self)
            let container = try ModelContainer(for: v4, configurations: ModelConfiguration(schema: v4, url: url, cloudKitDatabase: .none))
            let ctx = ModelContext(container)
            let c = SchemaV4.LeagueCheckIn()
            c.title = "Treino"
            c.proofRaw = #"{"deviceRecorded":true}"#
            c.reviewRaw = "pending"
            ctx.insert(c)
            let m = SchemaV1.LeagueMessage()
            m.text = "Bora"
            ctx.insert(m)
            try ctx.save()
        }
        let container = try ModelContainer(for: AppData.schema, migrationPlan: AppMigrationPlan.self,
                                           configurations: ModelConfiguration(schema: AppData.schema, url: url, cloudKitDatabase: .none))
        let ctx = ModelContext(container)
        let c = try XCTUnwrap(ctx.fetch(FetchDescriptor<LeagueCheckIn>()).first)
        XCTAssertEqual(c.title, "Treino")
        XCTAssertTrue(c.proof.deviceRecorded)
        XCTAssertEqual(c.reviewRaw, "pending")
        XCTAssertNil(c.extraPhotosData)
        let m = try XCTUnwrap(ctx.fetch(FetchDescriptor<LeagueMessage>()).first)
        XCTAssertEqual(m.text, "Bora")
        XCTAssertNil(m.photo)
    }
}
