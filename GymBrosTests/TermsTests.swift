import SwiftData
import XCTest
@testable import GymBros

/// Aceite dos termos de uso: guardado com a versão, pedido de novo quando ela muda e apagado com a conta
final class TermsTests: GymTestCase {
    private var defaults: UserDefaults!
    private var suite = ""

    override func setUp() async throws {
        try await super.setUp()
        suite = "TermsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try await super.tearDown()
    }

    func testAcceptStoresVersionAndDate() {
        XCTAssertFalse(Terms.isAccepted(defaults))
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        Terms.accept(defaults, at: date)
        XCTAssertTrue(Terms.isAccepted(defaults))
        XCTAssertEqual(defaults.integer(forKey: Terms.acceptedKey), Terms.version)
        XCTAssertEqual(defaults.object(forKey: Terms.acceptedAtKey) as? Date, date)
    }

    func testNewVersionAsksAgain() {
        Terms.accept(defaults, version: 1)
        XCTAssertTrue(Terms.isAccepted(defaults, version: 1))
        XCTAssertFalse(Terms.isAccepted(defaults, version: 2))
    }

    func testGateWaitsForAcceptance() {
        var ran = 0
        var gate = TermsGate()
        gate.run(defaults: defaults) { ran += 1 }
        XCTAssertEqual(ran, 0)
        XCTAssertTrue(gate.isWaiting)

        Terms.accept(defaults)
        var accepted = TermsGate()
        accepted.run(defaults: defaults) { ran += 1 }
        XCTAssertEqual(ran, 1)
        XCTAssertFalse(accepted.isWaiting)
    }

    func testDeletingAccountForgetsAcceptance() throws {
        let container = try ModelContainer(for: AppData.schema,
                                           configurations: ModelConfiguration(schema: AppData.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        Terms.accept(defaults)
        try AccountData.wipeSocial(context: container.mainContext, defaults: defaults)
        XCTAssertFalse(Terms.isAccepted(defaults))
        XCTAssertNil(defaults.object(forKey: Terms.acceptedAtKey))
    }
}
