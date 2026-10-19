import SwiftData
import XCTest
@testable import GymBros

/// O banco do aparelho abre com o schema versionado, sem migração destrutiva
@MainActor
final class StoreTests: XCTestCase {
    func testDeviceStoreOpensWithCurrentSchema() throws {
        let container = AppData.container
        XCTAssertNil(AppData.recoveredCopy)
        XCTAssertEqual(AppData.schema.version, Schema.Version(2, 0, 0))
        XCTAssertEqual(AppData.schema.entities.count, 18)
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
}
