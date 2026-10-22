import SwiftData
import XCTest
@testable import GymBros

/// Apagar um treino tira ele da lista, mas o XP continua com o bro que o recebeu
@MainActor
final class RetiredActivityTests: GymTestCase {
    func testDeletingActivityKeepsTheBroXP() throws {
        let container = try ModelContainer(for: Monster.self, Activity.self, WorkoutSession.self, LoggedSet.self, League.self,
                                           LeagueCheckIn.self, WodResult.self, RouteRecord.self, CheckInComment.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let bro = Monster(isStarter: true)
        context.insert(bro)
        for d in 1...6 {
            let a = Activity(kind: .corrida, date: day(-d), minutes: 60, effort: 7)
            a.monsterUUID = bro.uuid
            context.insert(a)
        }
        try context.save()
        func roster() throws -> Roster {
            Roster(monsters: [bro], activities: try context.fetch(FetchDescriptor<Activity>()), checkIns: [], leagues: [])
        }
        let before = try roster().snapshot(bro.uuid)
        XCTAssertGreaterThan(before.stage, .egg)
        for a in try context.fetch(FetchDescriptor<Activity>()) { deleteActivity(a, context: context) }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Activity>()), 0)
        let after = try roster().snapshot(bro.uuid)
        XCTAssertEqual(after.totalXP, before.totalXP)
        XCTAssertEqual(after.stage, before.stage)
        XCTAssertEqual(RetiredActivities.all().count, 6)
    }
}
