import XCTest
@testable import GymBros

/// Sessão no Keychain: gravar, sobrescrever e apagar
final class KeychainTests: XCTestCase {
    private let account = "test-\(UUID().uuidString)"

    override func tearDown() {
        Keychain.delete(account)
        super.tearDown()
    }

    func testSaveOverwriteAndDelete() {
        XCTAssertNil(Keychain.load(account))
        XCTAssertTrue(Keychain.save(Data("a".utf8), for: account))
        XCTAssertEqual(Keychain.load(account), Data("a".utf8))
        XCTAssertTrue(Keychain.save(Data("b".utf8), for: account))
        XCTAssertEqual(Keychain.load(account), Data("b".utf8))
        Keychain.delete(account)
        XCTAssertNil(Keychain.load(account))
    }
}
