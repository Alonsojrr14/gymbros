import XCTest
@testable import GymBros

final class LiveShareTests: XCTestCase {
    private let suite = "LiveShareTests"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testOnByDefault() {
        XCTAssertTrue(LiveShare.isOn(defaults))
        XCTAssertTrue(LiveShare.isSharing("treino", defaults: defaults))
    }

    func testDefaultTurnedOffInSettings() {
        defaults.set(false, forKey: LiveShare.key)
        XCTAssertFalse(LiveShare.isSharing("treino", defaults: defaults))
    }

    func testEachWorkoutCanChooseAndEndForgetsIt() {
        LiveShare.set(false, for: "a", defaults: defaults)
        XCTAssertFalse(LiveShare.isSharing("a", defaults: defaults))
        XCTAssertTrue(LiveShare.isSharing("b", defaults: defaults), "só o treino escolhido muda")
        LiveShare.end("a", defaults: defaults)
        XCTAssertTrue(LiveShare.isSharing("a", defaults: defaults))

        defaults.set(false, forKey: LiveShare.key)
        LiveShare.set(true, for: "c", defaults: defaults)
        XCTAssertTrue(LiveShare.isSharing("c", defaults: defaults), "pode ligar num treino mesmo com o padrão desligado")
    }

    func testGoesWithTheAccount() {
        XCTAssertTrue(LiveShare.defaultsKeys.allSatisfy(AccountData.userKeys.contains))
    }
}
