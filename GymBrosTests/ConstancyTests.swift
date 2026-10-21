import XCTest
@testable import GymBros

/// Metas pessoais com cadência e recordes de constância
@MainActor
final class ConstancyTests: GymTestCase {
    private let cal = Calendar.current

    private func activity(daysAgo: Int, hour: Int = 10, minutes: Int = 60, kind: ActivityKind = .musculacao) -> Activity {
        let day = cal.date(byAdding: .day, value: -daysAgo, to: cal.startOfDay(for: .now))!
        return Activity(kind: kind, date: cal.date(byAdding: .hour, value: hour, to: day)!, minutes: minutes, effort: 6)
    }

    func testWeeklyGoalStreakKeepsCurrentWeekOpen() {
        let week = cal.dateInterval(of: .weekOfYear, for: .now)!.start
        let start = cal.date(byAdding: .weekOfYear, value: -3, to: week)!
        var g = PersonalGoal(metric: .checkIns, amount: 2, cadence: .weekly)
        g.start = start
        // 2 treinos em cada uma das 3 semanas passadas; nenhum nesta
        let acts = (1...3).flatMap { w -> [Activity] in
            let d = cal.date(byAdding: .weekOfYear, value: -w, to: week)!
            return [0, 1].map { i in Activity(kind: .musculacao, date: cal.date(byAdding: .hour, value: 10 + i * 24, to: d)!, minutes: 60, effort: 6) }
        }
        let periods = g.periods(acts)
        XCTAssertEqual(periods.count, 4)
        XCTAssertFalse(periods.last!.met)
        // A semana atual ainda não acabou: não quebra a sequência
        XCTAssertEqual(g.streak(periods), 3)
        XCTAssertEqual(g.bestStreak(periods), 3)
    }

    func testOnlySelectedActivitiesCount() {
        var g = PersonalGoal(metric: .minutes, amount: 60, cadence: .daily)
        g.activityTypes = [WorkoutType.of(.corrida).id]
        g.start = cal.startOfDay(for: .now)
        let acts = [activity(daysAgo: 0, minutes: 40, kind: .corrida), activity(daysAgo: 0, minutes: 90, kind: .musculacao)]
        XCTAssertEqual(g.periods(acts).last?.value, 40)
    }

    func testDaysActiveCountsDistinctDays() {
        let g = PersonalGoal(metric: .daysActive, amount: 200, cadence: .yearly)
        let acts = [activity(daysAgo: 0), activity(daysAgo: 0, hour: 18), activity(daysAgo: 1)]
        XCTAssertEqual(g.value(acts), 2)
    }

    func testTargetDateGoalIsOnePeriod() {
        var g = PersonalGoal(metric: .checkIns, amount: 3, cadence: .weekly, targetDate: cal.date(byAdding: .day, value: 10, to: .now))
        g.start = cal.date(byAdding: .day, value: -5, to: cal.startOfDay(for: .now))!
        let p = g.periods([activity(daysAgo: 1), activity(daysAgo: 2), activity(daysAgo: 3), activity(daysAgo: 30)])
        XCTAssertEqual(p.count, 1)
        XCTAssertEqual(p[0].value, 3)
        XCTAssertTrue(p[0].met)
    }

    func testOldWeeklyGoalsBecomeGoals() {
        let d = scratchDefaults("metas")
        d.set(5, forKey: "goalWeekly")
        d.set(240, forKey: "goalMinutes")
        let goals = PersonalGoals.all(d)
        XCTAssertEqual(goals.map(\.amount), [5, 240])
        XCTAssertEqual(goals.map(\.metric), [.checkIns, .minutes])
        PersonalGoals.save([goals[0]], d)
        XCTAssertEqual(PersonalGoals.all(d).count, 1)
        // Texto, para ir no backup
        XCTAssertNotNil(d.string(forKey: PersonalGoals.key))
    }

    func testTemplatesAreValid() {
        let t = PersonalGoals.templates
        XCTAssertEqual(t.count, 11)
        XCTAssertTrue(t.allSatisfy { $0.amount > 0 && !$0.name.isEmpty })
        XCTAssertTrue(t.flatMap(\.activityTypes).allSatisfy { WorkoutType.byID($0) != nil })
    }

    func testConstancyRunsAndHabits() {
        let acts = [activity(daysAgo: 0, hour: 6), activity(daysAgo: 1, hour: 22), activity(daysAgo: 2), activity(daysAgo: 10, minutes: 120)]
        let c = Constancy.of(acts)
        XCTAssertEqual(c.daily.current?.length, 3)
        XCTAssertEqual(c.daily.best?.length, 3)
        XCTAssertTrue(c.daily.current?.ongoing == true)
        XCTAssertEqual(c.bestDay?.minutes, 120)
        XCTAssertEqual(c.earlyBird, 1)
        XCTAssertEqual(c.nightOwl, 1)
        XCTAssertGreaterThanOrEqual(c.weekly.best?.length ?? 0, 1)
    }
}
