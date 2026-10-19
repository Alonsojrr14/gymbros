import XCTest
@testable import GymBros

/// Roteiro, gatilho de primeira utilização, persistência e recorte do tutorial
@MainActor
final class OnboardingTests: XCTestCase {
    private var defaults: UserDefaults!
    private var registry: OnboardingTargetRegistry!
    private let suite = "OnboardingTests"

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
        registry = OnboardingTargetRegistry()
        registry.bounds = CGRect(x: 0, y: 0, width: 390, height: 844)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    private func coordinator(_ steps: [OnboardingStep] = OnboardingStep.tour) -> OnboardingCoordinator {
        let c = OnboardingCoordinator(steps: steps, registry: registry, persistence: OnboardingPersistence(defaults: defaults))
        c.settleDelay = .zero
        c.locateTimeout = .milliseconds(60)
        return c
    }

    private func showAllTargets() {
        for t in OnboardingTarget.allCases {
            registry.update(t, .init(frame: CGRect(x: 20, y: 200, width: 100, height: 44), shape: .capsule))
        }
    }

    func testScriptHasStableUniqueIDsAndEndsWithoutTarget() {
        let ids = OnboardingStep.tour.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(OnboardingStep.tour.last!.targets.isEmpty)
        for step in OnboardingStep.tour where step.interaction != .explain {
            XCTAssertNotNil(step.hint, "\(step.id) pede um toque e precisa dizer qual")
        }
    }

    func testPersistenceRoundTrip() {
        let p = OnboardingPersistence(defaults: defaults)
        XCTAssertEqual(p.state, .notPresented)
        for s in [OnboardingState.inProgress(step: "ligas"), .completed, .dismissed, .notPresented] {
            p.state = s
            XCTAssertEqual(p.state, s)
        }
    }

    func testFirstRunStartsAndCompletionIsNotShownAgain() {
        showAllTargets()
        let c = coordinator()
        c.startIfEligible(modalOpen: false, busy: false)
        XCTAssertEqual(c.index, 0)
        while c.isActive { c.next() }
        XCTAssertEqual(c.persistence.state, .completed)
        c.startIfEligible(modalOpen: false, busy: false)
        XCTAssertFalse(c.isActive)
    }

    func testSkipEndsCleanlyAndIsRemembered() {
        let c = coordinator()
        c.startIfEligible(modalOpen: false, busy: false)
        c.skip()
        XCTAssertFalse(c.isActive)
        XCTAssertNil(c.current)
        XCTAssertFalse(c.locating)
        XCTAssertEqual(c.persistence.state, .dismissed)
        c.startIfEligible(modalOpen: false, busy: false)
        XCTAssertFalse(c.isActive)
    }

    func testDoesNotStartOverModalsOrRunningWorkout() {
        let c = coordinator()
        c.startIfEligible(modalOpen: true, busy: false)
        XCTAssertFalse(c.isActive)
        c.startIfEligible(modalOpen: false, busy: true)
        XCTAssertFalse(c.isActive)
        c.requestStart()
        c.startIfEligible(modalOpen: true, busy: true)
        XCTAssertFalse(c.isActive, "pedido explícito ainda espera a tela principal ficar livre")
        c.startIfEligible(modalOpen: false, busy: true)
        XCTAssertEqual(c.index, 0)
        XCTAssertFalse(c.startRequested)
    }

    func testExplicitRequestRestartsAfterCompletion() {
        let c = coordinator()
        c.persistence.state = .completed
        c.requestStart()
        c.startIfEligible(modalOpen: false, busy: false)
        XCTAssertEqual(c.index, 0)
    }

    func testResumesFromSavedStep() {
        let c = coordinator()
        c.persistence.state = .inProgress(step: "ligas")
        c.startIfEligible(modalOpen: false, busy: false)
        XCTAssertEqual(c.current?.id, "ligas")
        c.skip()
        c.persistence.state = .inProgress(step: "etapa-que-saiu")
        c.startIfEligible(modalOpen: false, busy: false)
        XCTAssertEqual(c.index, 0)
    }

    func testForwardBackAndProgress() {
        let c = coordinator()
        c.requestStart()
        c.startIfEligible(modalOpen: false, busy: false)
        c.back()
        XCTAssertEqual(c.index, 0)
        c.next(); c.next()
        XCTAssertEqual(c.index, 2)
        XCTAssertEqual(c.persistence.state, .inProgress(step: OnboardingStep.tour[2].id))
        c.back()
        XCTAssertEqual(c.index, 1)
        XCTAssertFalse(c.isLast)
    }

    func testOpeningTheRequestedTabCompletesInteractiveStep() throws {
        let c = coordinator()
        c.persistence.state = .inProgress(step: "aba-treino")
        c.startIfEligible(modalOpen: false, busy: false)
        c.tabDidChange(to: .leagues)
        XCTAssertEqual(c.current?.id, "aba-treino")
        c.tabDidChange(to: .train)
        XCTAssertEqual(c.current?.id, "treino-hoje")
        c.tabDidChange(to: .home)
        XCTAssertEqual(c.current?.id, "treino-hoje", "etapa explicativa não avança por troca de aba")
    }

    func testMissingTargetIsSkippedInsteadOfHighlightingSomethingElse() async throws {
        let steps = [OnboardingStep(id: "a", title: "A", message: "", targets: [.logActivity]),
                     OnboardingStep(id: "b", title: "B", message: "", targets: [.trainToday]),
                     OnboardingStep(id: "c", title: "C", message: "")]
        registry.update(.logActivity, .init(frame: CGRect(x: 10, y: 10, width: 50, height: 50), shape: .circle))
        let c = coordinator(steps)
        c.requestStart()
        c.startIfEligible(modalOpen: false, busy: false)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertFalse(c.locating)
        XCTAssertNotNil(c.spotlight)
        c.next()
        XCTAssertNil(c.spotlight)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(c.current?.id, "c")
        c.back()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(c.current?.id, "a", "voltando, a etapa sem elemento também é pulada")
    }

    func testRegistryRejectsOffscreenAndUnionsTargets() {
        registry.update(.mapTab, .init(frame: CGRect(x: 200, y: 780, width: 60, height: 44), shape: .capsule))
        registry.update(.historyTab, .init(frame: CGRect(x: 270, y: 780, width: 60, height: 44), shape: .capsule))
        XCTAssertEqual(registry.spotlight(for: [.mapTab, .historyTab])?.frame, CGRect(x: 200, y: 780, width: 130, height: 44))
        XCTAssertNil(registry.spotlight(for: [.mapTab, .leaguesTab]))
        registry.update(.monster, .init(frame: CGRect(x: 0, y: 900, width: 100, height: 100), shape: .rounded(20)))
        XCTAssertNil(registry.spotlight(for: [.monster]))
        registry.update(.monster, nil)
        XCTAssertNil(registry.spotlight(for: [.monster]))
    }

    func testHoleKeepsTheElementShape() {
        let frame = CGRect(x: 100, y: 100, width: 66, height: 46)
        let circle = OnboardingTargetRegistry.Entry(frame: frame, shape: .circle).hole(padding: 6)
        XCTAssertEqual(circle.rect.width, circle.rect.height)
        XCTAssertEqual(circle.radius, circle.rect.width / 2)
        XCTAssertTrue(circle.rect.contains(frame))
        let capsule = OnboardingTargetRegistry.Entry(frame: frame, shape: .capsule).hole(padding: 6)
        XCTAssertEqual(capsule.radius, 29)
        let path = SpotlightCutout(hole: capsule.rect, radius: capsule.radius).path(in: CGRect(x: 0, y: 0, width: 390, height: 844))
        XCTAssertFalse(path.contains(CGPoint(x: frame.midX, y: frame.midY), eoFill: true), "o centro do recorte não é pintado")
        XCTAssertTrue(path.contains(CGPoint(x: 10, y: 10), eoFill: true))
    }

    func testEachAccountGetsItsOwnFirstRun() {
        let c = coordinator()
        c.setAccount("conta-a")
        c.startIfEligible(modalOpen: false, busy: false)
        c.next()
        c.setAccount("conta-b")
        XCTAssertFalse(c.isActive, "trocar de conta fecha o tutorial da conta anterior")
        XCTAssertEqual(c.persistence.state, .notPresented)
        c.startIfEligible(modalOpen: false, busy: false)
        XCTAssertEqual(c.index, 0)
        c.skip()
        c.setAccount("conta-a")
        XCTAssertEqual(c.persistence.state, .inProgress(step: OnboardingStep.tour[1].id))
        c.startIfEligible(modalOpen: false, busy: false)
        XCTAssertEqual(c.index, 1, "a conta A retoma de onde parou")
        c.setAccount("conta-b")
        c.startIfEligible(modalOpen: false, busy: false)
        XCTAssertFalse(c.isActive, "a conta B já pulou")
        XCTAssertFalse(defaults.dictionaryRepresentation().keys.contains { $0.contains("conta-") }, "a conta não vai em texto puro")
    }

    func testSuspendKeepsProgressForLater() {
        let c = coordinator()
        c.startIfEligible(modalOpen: false, busy: false)
        c.next()
        c.suspend()
        XCTAssertFalse(c.isActive)
        c.startIfEligible(modalOpen: false, busy: false)
        XCTAssertEqual(c.index, 1)
    }

    #if DEBUG
    func testLaunchArgumentsApplyToTheSignedInAccount() {
        let c = coordinator()
        c.applyLaunchArguments(["app", "-onboardingStep", "ligas"])
        c.setAccount("conta-a")
        c.startIfEligible(modalOpen: false, busy: false)
        XCTAssertEqual(c.current?.id, "ligas")
    }

    func testDevelopmentRestartReturnsToFirstRun() {
        let c = coordinator()
        c.persistence.state = .completed
        c.restartForTesting()
        XCTAssertEqual(c.persistence.state, .notPresented)
        c.startIfEligible(modalOpen: false, busy: false)
        XCTAssertEqual(c.index, 0)
        c.resetForTesting()
        XCTAssertFalse(c.isActive)
        XCTAssertEqual(c.persistence.state, .notPresented)
    }
    #endif

    func testTargetUnderTabBarIsNotHighlightedUntilScrolledAbove() {
        registry.tabBar = CGRect(x: 14, y: 760, width: 362, height: 70)
        registry.update(.logActivity, .init(frame: CGRect(x: 16, y: 770, width: 358, height: 50), shape: .rounded(14)))
        XCTAssertNil(registry.spotlight(for: [.logActivity]))
        registry.update(.logActivity, .init(frame: CGRect(x: 16, y: 500, width: 358, height: 50), shape: .rounded(14)))
        XCTAssertNotNil(registry.spotlight(for: [.logActivity]))
    }

    func testTabBarTargetsIgnoreTheBarItself() {
        registry.tabBar = CGRect(x: 14, y: 760, width: 362, height: 70)
        registry.update(.trainTab, .init(frame: CGRect(x: 20, y: 770, width: 60, height: 50), shape: .capsule))
        XCTAssertNotNil(registry.spotlight(for: [.trainTab]))
    }

    func testStepAsksToScrollToItsScreenTarget() {
        let c = coordinator()
        c.startIfEligible(modalOpen: false, busy: false)
        c.next()
        XCTAssertEqual(c.current?.id, "registrar")
        XCTAssertEqual(c.scrollTarget, .logActivity)
        c.skip()
        XCTAssertNil(c.scrollTarget)
    }
}
