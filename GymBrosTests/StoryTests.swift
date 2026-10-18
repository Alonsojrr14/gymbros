import CoreLocation
import SwiftData
import XCTest
@testable import GymBros

/// Números da arte do story: calorias só com peso (ou do Apple Saúde), corrida com distância, pace e trajeto
final class StoryTests: GymTestCase {
    private var savedWeight: Any?

    override func setUp() async throws {
        try await super.setUp()
        savedWeight = UserDefaults.standard.object(forKey: BodyProfile.weightKey)
        UserDefaults.standard.removeObject(forKey: BodyProfile.weightKey)
    }

    override func tearDown() async throws {
        if let savedWeight { UserDefaults.standard.set(savedWeight, forKey: BodyProfile.weightKey) }
        else { UserDefaults.standard.removeObject(forKey: BodyProfile.weightKey) }
        try await super.tearDown()
    }

    private func context() throws -> ModelContext {
        let c = try ModelContainer(for: Activity.self, BodyEntry.self, RouteRecord.self, LeagueCheckIn.self, WorkoutSession.self, LoggedSet.self,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(c)
    }

    func testNoWeightMeansNoCalories() throws {
        let ctx = try context()
        let a = Activity(kind: .musculacao, date: day(0), minutes: 60, effort: 6)
        ctx.insert(a)
        let s = StoryData.activity(a, context: ctx)
        XCTAssertFalse(s.stats.contains { $0.label == "kcal" }, "Sem peso cadastrado, não aparece")
        XCTAssertFalse(s.stats.contains { $0.value == "–" })
    }

    func testWeightGivesEstimatedCalories() throws {
        let ctx = try context()
        ctx.insert(BodyEntry(date: day(-1), weight: 80))
        let a = Activity(kind: .musculacao, date: day(0), minutes: 60, effort: 6)
        ctx.insert(a)
        let kcal = StoryData.activity(a, context: ctx).stats.first { $0.label == "kcal" }
        XCTAssertNotNil(kcal)
        XCTAssertGreaterThan(Int(kcal!.value) ?? 0, 100)
    }

    func testHealthCaloriesWinOverEstimate() throws {
        let ctx = try context()
        let a = Activity(kind: .corrida, date: day(0), minutes: 30, effort: 5, note: "312 kcal")
        a.healthUUID = "X"
        ctx.insert(a)
        XCTAssertEqual(StoryData.activity(a, context: ctx).stats.first { $0.label == "kcal" }?.value, "312")
    }

    func testRunShowsDistancePaceAndRoute() throws {
        let ctx = try context()
        let a = Activity(kind: .corrida, date: day(0), minutes: 30, effort: 6)
        ctx.insert(a)
        let r = RouteRecord(kind: .corrida, start: a.date)
        r.activityUUID = a.uuid
        r.meters = 5000
        r.seconds = 1500   // 5'00" /km
        r.points = RouteRecord.encode([CLLocationCoordinate2D(latitude: -3.73, longitude: -38.52),
                                       CLLocationCoordinate2D(latitude: -3.74, longitude: -38.50)])
        ctx.insert(r)
        let s = StoryData.activity(a, context: ctx)
        XCTAssertEqual(s.stats.first?.label, "distância")
        XCTAssertEqual(s.stats.first { $0.label == "pace /km" }?.value, "5'00\"")
        XCTAssertEqual(s.route.count, 2)
    }
}
