import Foundation
import SwiftData
import XCTest
@testable import GymBros

final class DemoAccountTests: GymTestCase {
    private var defaults: UserDefaults!
    private let suite = "DemoAccountTests"
    private let demo = AuthUser(id: "email-" + DemoAccount.email, name: DemoAccount.name, email: DemoAccount.email, provider: .email, token: "")
    private let other = AuthUser(id: "email-outra@exemplo.com", name: "Outra", email: "outra@exemplo.com", provider: .email, token: "")

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        UserDefaults().removePersistentDomain(forName: suite)
        try await super.tearDown()
    }

    private func leagues(_ context: ModelContext) throws -> [League] { try context.fetch(FetchDescriptor<League>()) }

    func testDemoJoinsExampleLeagueOnce() throws {
        let context = try memoryContext()
        let rep = UUID()
        XCTAssertTrue(DemoAccount.seedIfNeeded(user: demo, context: context, representative: rep, mode: .mock, defaults: defaults))
        let joined = try leagues(context)
        XCTAssertEqual(joined.map(\.code), [MockLeague.code])
        XCTAssertEqual(joined.first?.monsterUUID, rep)
        XCTAssertTrue(joined.first?.isMock == true)
        XCTAssertFalse(MockLeagueBackend.build(joined[0].key).members.isEmpty, "a liga de exemplo tem participantes simulados")

        // Saiu da liga: não volta sozinha
        context.delete(joined[0])
        try context.save()
        XCTAssertFalse(DemoAccount.seedIfNeeded(user: demo, context: context, representative: rep, mode: .mock, defaults: defaults))
        XCTAssertTrue(try leagues(context).isEmpty)
    }

    func testAlreadyInExampleLeagueDoesNotDuplicate() throws {
        let context = try memoryContext()
        let l = MockLeague.make()
        l.monsterUUID = UUID()
        context.insert(l)
        try context.save()
        XCTAssertFalse(DemoAccount.seedIfNeeded(user: demo, context: context, representative: UUID(), mode: .mock, defaults: defaults))
        XCTAssertEqual(try leagues(context).count, 1)
    }

    func testOnlyDemoAccountInMockMode() throws {
        let context = try memoryContext()
        XCTAssertFalse(DemoAccount.seedIfNeeded(user: other, context: context, representative: UUID(), mode: .mock, defaults: defaults))
        XCTAssertFalse(DemoAccount.seedIfNeeded(user: nil, context: context, representative: UUID(), mode: .mock, defaults: defaults))
        XCTAssertFalse(DemoAccount.seedIfNeeded(user: demo, context: context, representative: UUID(), mode: .cloudKit, defaults: defaults))
        XCTAssertTrue(try leagues(context).isEmpty)
    }

    func testDemoSignInUsesFixedCredentialsAndName() async throws {
        XCTAssertNoThrow(try AuthStore.validate(email: DemoAccount.email, password: DemoAccount.password))
        let user = try await MockAuthBackend().signIn(email: DemoAccount.email, password: DemoAccount.password)
        XCTAssertEqual(user.name, DemoAccount.name)
        XCTAssertTrue(DemoAccount.isDemo(user))
    }

    /// A marca vai na cópia da conta e sai do aparelho junto com ela
    func testSeededFlagBelongsToAccount() {
        XCTAssertTrue(AccountData.userKeys.contains(DemoAccount.seededKey))
    }
}
