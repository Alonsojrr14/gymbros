import SwiftData
import XCTest
@testable import GymBros

/// O banco do aparelho abre com o schema versionado, sem migração destrutiva
@MainActor
final class StoreTests: XCTestCase {
    func testDeviceStoreOpensWithSchemaV1() throws {
        let container = AppData.container
        XCTAssertNil(AppData.recoveredCopy)
        XCTAssertEqual(AppData.schema.version, Schema.Version(1, 0, 0))
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
}
