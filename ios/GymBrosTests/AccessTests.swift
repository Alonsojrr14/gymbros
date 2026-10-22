import SwiftData
import XCTest
@testable import GymBros

/// RBAC: matriz explícita, negação por padrão, sessão e as operações que conferem a permissão antes de agir
final class AccessTests: GymTestCase {
    private static let expected: [AppRole: Set<Permission>] = [
        .user: [.profileRead, .profileUpdate, .friendsRead, .friendsManage, .leaguesRead, .leaguesCreate, .leaguesJoin, .leaguesUpdate,
                .checkInsPublish, .messagesPublish, .commentsCreate, .directMessagesSend, .moderationReport, .moderationBlock],
        .developer: [.diagnosticsRead],
        .admin: [.moderationReview, .moderationRemoveContent, .usersManageRoles],
    ]
    private static let adminOnly: Set<Permission> = [.moderationReview, .moderationRemoveContent, .usersManageRoles]

    private let policy = RolePolicy.standard

    // MARK: Matriz

    func testMatrixMatchesTheDocumentedDecisions() {
        for role in AppRole.allCases {
            XCTAssertEqual(policy.permissions(of: role), Self.expected[role], "\(role.rawValue)")
        }
    }

    /// Permissão nova sem decisão explícita para cada role quebra este teste
    func testEveryPermissionHasAnExplicitDecision() {
        let decided = Self.expected.values.reduce(into: Set<Permission>()) { $0.formUnion($1) }
        XCTAssertEqual(decided, Set(Permission.allCases))
    }

    func testEachRoleIsDeniedEverythingOutsideItsGrants() {
        for role in AppRole.allCases {
            for p in Permission.allCases where !(Self.expected[role] ?? []).contains(p) {
                XCTAssertFalse(policy.allows([role], p), "\(role.rawValue) não deveria ter \(p.rawValue)")
                XCTAssertFalse(policy.allows([role], p, isMine: false))
                XCTAssertFalse(policy.allows([role], p, isMine: true))
            }
        }
    }

    func testDefaultRoleAndDeveloperHaveNoAdminPrivileges() {
        for p in Self.adminOnly {
            XCTAssertFalse(policy.allows([.user], p))
            XCTAssertFalse(policy.allows([.developer], p))
            XCTAssertFalse(policy.allows([.user, .developer], p))
            XCTAssertTrue(policy.allows([.admin], p))
        }
    }

    func testOwnScopeNeedsOwnership() {
        XCTAssertTrue(policy.allows([.user], .leaguesUpdate, isMine: true))
        XCTAssertFalse(policy.allows([.user], .leaguesUpdate, isMine: false))
        XCTAssertTrue(policy.allows([.user], .profileRead, isMine: false))
        XCTAssertFalse(policy.allows([.admin], .leaguesUpdate, isMine: false), "ADMIN não edita liga dos outros sem decisão explícita")
    }

    func testRolesCombine() {
        XCTAssertTrue(policy.allows([.user, .developer], .leaguesRead))
        XCTAssertTrue(policy.allows([.user, .developer], .diagnosticsRead))
        XCTAssertFalse(policy.allows([.developer], .leaguesRead), "DEVELOPER sozinho não herda USER")
    }

    func testGrantingOneRoleLeavesTheOthersUntouched() {
        var grants = policy.grants
        grants[.developer, default: [:]][.leaguesUpdate] = .any
        let changed = RolePolicy(grants: grants)
        XCTAssertEqual(changed.permissions(of: .user), policy.permissions(of: .user))
        XCTAssertEqual(changed.permissions(of: .admin), policy.permissions(of: .admin))
        XCTAssertFalse(changed.allows([.admin], .leaguesUpdate))
    }

    func testRoleWithoutGrantsGetsNothing() {
        let p = RolePolicy(grants: [.user: policy.grants[.user] ?? [:]])
        for permission in Permission.allCases {
            XCTAssertFalse(p.allows([.developer], permission))
            XCTAssertFalse(p.allows([.admin], permission))
        }
    }

    func testUnknownRoleValuesAreDropped() {
        XCTAssertEqual(AppRole.parse(["ROOT", "admin", " ADMIN", "SUPERUSER", ""]), [])
        XCTAssertEqual(AppRole.parse(["USER", "DEVELOPER", "x"]), [.user, .developer])
    }

    // MARK: Sessão

    func testSignedOutDeniesEverything() async {
        let access = AccessStore(currentUser: { nil })
        await access.refresh()
        XCTAssertEqual(access.context, .signedOut)
        for p in Permission.allCases { XCTAssertFalse(access.can(p)) }
    }

    func testMissingAssignmentIsUser() async {
        let access = await signedInAccess(nil)
        XCTAssertEqual(access.context, .resolved(userID: "tester", roles: [.user], source: .standard))
        XCTAssertTrue(access.can(.leaguesRead))
        XCTAssertFalse(access.can(.diagnosticsRead))
    }

    func testInvalidOrEmptyAssignmentGrantsNothing() async {
        for assignment in [["ROOT"], []] {
            let access = await signedInAccess(assignment)
            XCTAssertEqual(access.roles, [])
            XCTAssertFalse(access.isLoading)
            for p in Permission.allCases { XCTAssertFalse(access.can(p), "\(assignment) liberou \(p.rawValue)") }
        }
    }

    func testAssignedRolesAreUsed() async {
        let access = await signedInAccess(["USER", "ADMIN"])
        XCTAssertEqual(access.roles, [.user, .admin])
        XCTAssertTrue(access.can(.moderationReview))
        XCTAssertFalse(access.can(.diagnosticsRead))
    }

    func testBeforeLoadingNothingIsAllowed() {
        let user = AuthUser(id: "a", name: "", email: "", provider: .email, token: "")
        let access = AccessStore(currentUser: { user })
        XCTAssertTrue(access.isLoading)
        for p in Permission.allCases { XCTAssertFalse(access.can(p)) }
    }

    func testFailedLookupFallsBackToUserOnly() async {
        let session = Session("a")
        let backend = SwitchableRoleBackend(["a": ["USER", "ADMIN"]])
        let access = AccessStore(currentUser: { session.user })
        access.backend = backend
        await access.refresh()
        XCTAssertTrue(access.can(.moderationReview))

        await backend.fail()
        await access.refresh()
        XCTAssertEqual(access.context, .resolved(userID: "a", roles: [.user], source: .fallback))
        XCTAssertFalse(access.can(.moderationReview), "Falha na consulta não mantém ADMIN")
        XCTAssertTrue(access.can(.leaguesRead))
    }

    func testSwitchingAccountDropsThePreviousRolesImmediately() async {
        let session = Session("a")
        let access = AccessStore(currentUser: { session.user })
        access.backend = MockRoleBackend(assignments: ["a": ["USER", "ADMIN", "DEVELOPER"]])
        await access.refresh()
        XCTAssertTrue(access.can(.usersManageRoles))

        session.id = "b"
        XCTAssertTrue(access.isLoading)
        for p in Permission.allCases { XCTAssertFalse(access.can(p), "Contexto de A vazou para B em \(p.rawValue)") }

        await access.refresh()
        XCTAssertEqual(access.roles, [.user])
        XCTAssertFalse(access.can(.usersManageRoles))
    }

    func testLogoutClearsTheContext() async {
        let session = Session("a")
        let access = AccessStore(currentUser: { session.user })
        await access.refresh()
        XCTAssertTrue(access.can(.leaguesRead))

        session.id = nil
        XCTAssertFalse(access.can(.leaguesRead))
        await access.refresh()
        XCTAssertEqual(access.context, .signedOut)
    }

    #if DEBUG
    func testDevAccountsResolveToTheirRoles() async {
        let expected: [DevAccount: Set<AppRole>] = [.user: [.user], .developer: [.user, .developer], .admin: [.user, .admin], .disabled: []]
        for account in DevAccount.allCases {
            let access = await signedInAccess(account.assignment, userID: account.id)
            XCTAssertEqual(access.roles, expected[account], account.title)
        }
        let developer = await signedInAccess(DevAccount.developer.assignment)
        XCTAssertFalse(developer.can(.moderationReview))
    }
    #endif

    // MARK: Operações

    func testLeagueOwnership() {
        let mine = League(name: "Minha", emoji: "🏆", scoring: .pontos)
        let theirs = League(draft: mine.draft)
        XCTAssertTrue(mine.isMine)
        XCTAssertFalse(theirs.isMine)
    }

    func testOwnerCanEditOwnLeagueOnly() async {
        let access = await signedInAccess()
        let mine = League(name: "Minha", emoji: "🏆", scoring: .pontos)
        XCTAssertTrue(access.can(.leaguesUpdate, on: mine))
        XCTAssertFalse(access.can(.leaguesUpdate, on: League(draft: mine.draft)))
    }

    func testFlushWithoutPermissionSendsNothingAndKeepsPending() async throws {
        let c = try ModelContainer(for: AppData.schema,
                                   configurations: ModelConfiguration(schema: AppData.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let ctx = c.mainContext
        let league = League(name: "Teste", emoji: "🏆", scoring: .pontos)
        let activity = Activity(kind: .corrida, date: .now, minutes: 30, effort: 5)
        let checkIn = LeagueCheckIn(leagueUUID: league.uuid, activityUUID: activity.uuid, title: "Corrida", note: "", date: .now, photo: nil)
        let message = LeagueMessage(leagueUUID: league.uuid, text: "Bora")
        ctx.insert(league)
        ctx.insert(activity)
        ctx.insert(checkIn)
        ctx.insert(message)
        try ctx.save()

        let backend = CountingLeagueBackend()
        let store = LeagueRemoteStore()
        store.backend = backend
        store.access = await signedInAccess(["ROOT"])
        await store.flush(context: ctx)

        let sent = await backend.count
        XCTAssertEqual(sent, 0)
        XCTAssertNil(league.syncedAt)
        XCTAssertNil(checkIn.syncedAt)
        XCTAssertNil(message.syncedAt)

        store.access = await signedInAccess()
        await store.flush(context: ctx)
        let after = await backend.count
        XCTAssertGreaterThan(after, 0)
        XCTAssertNotNil(checkIn.syncedAt)
    }

    func testModerationWithoutPermissionDoesNothing() async {
        let suite = "AccessTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ModerationStore(defaults: defaults)
        store.backend = MockModerationBackend()
        store.unfriend = { _ in }
        store.access = await signedInAccess([])

        await store.report(ReportedContent(kind: .message, id: "m1", authorID: "ana"), reason: .spam)
        await store.block(userID: "ana", name: "Ana")
        XCTAssertTrue(store.hidden.isEmpty)
        XCTAssertTrue(store.blocked.isEmpty)
        XCTAssertTrue(store.outbox.isEmpty)
    }

    func testAddingFriendWithoutPermissionThrows() async {
        let store = FriendsStore()
        store.access = await signedInAccess([])
        do {
            _ = try await store.add(id: "ana")
            XCTFail("Deveria negar")
        } catch {
            XCTAssertEqual(error as? AccessError, .forbidden(.friendsManage))
        }
    }

    func testAdminActionsCheckTheRoleBeforeTheServer() async {
        let user = AdminActions(access: await signedInAccess())
        do { _ = try await user.reports(); XCTFail() } catch { XCTAssertEqual(error as? AccessError, .forbidden(.moderationReview)) }

        let dev = AdminActions(access: await signedInAccess(["USER", "DEVELOPER"]))
        do { try await dev.remove(ReportedContent(kind: .message, id: "m", authorID: "x")); XCTFail() } catch {
            XCTAssertEqual(error as? AccessError, .forbidden(.moderationRemoveContent))
        }

        let admin = AdminActions(access: await signedInAccess(["ADMIN"]))
        do { _ = try await admin.reports(); XCTFail() } catch { XCTAssertEqual(error as? AccessError, .requiresTrustedServer) }
        do { try await admin.setRoles([.admin], for: "tester"); XCTFail() } catch {
            XCTAssertEqual(error as? AccessError, .forbidden(.usersManageRoles), "Ninguém muda as próprias roles")
        }
    }
}

@MainActor
private final class Session {
    var id: String?
    init(_ id: String?) { self.id = id }
    var user: AuthUser? { id.map { AuthUser(id: $0, name: "", email: "", provider: .email, token: "") } }
}

private actor SwitchableRoleBackend: RoleBackend {
    private let assignments: [String: [String]]
    private var failing = false

    init(_ assignments: [String: [String]]) { self.assignments = assignments }

    func fail() { failing = true }

    func assignment(for userID: String) async throws -> [String]? {
        if failing { throw URLError(.notConnectedToInternet) }
        return assignments[userID]
    }
}

private actor CountingLeagueBackend: LeagueBackend {
    private(set) var count = 0

    func fetch(_ league: LeagueKey, now: Date) async throws -> RemoteLeague { .empty }
    func send(_ messages: [OutgoingMessage], to league: LeagueKey) async throws -> [UUID] { count += messages.count; return messages.map(\.id) }
    func create(_ league: LeagueDraft) async throws { count += 1 }
    func join(code: String) async throws -> LeagueDraft? { nil }
    func setMembership(_ membership: Membership, in league: LeagueKey) async throws { count += 1 }
    func publish(_ checkIns: [OutgoingCheckIn], to league: LeagueKey) async throws -> [UUID] { count += checkIns.count; return checkIns.map(\.id) }
    func retract(_ checkInIDs: [UUID], from league: LeagueKey) async throws {}
    func leave(_ league: LeagueKey) async throws {}
}
