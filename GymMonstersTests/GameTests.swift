import XCTest
@testable import GymMonsters

/// XP, limites por dia, evolução, galhos híbridos e sequência
final class GameTests: GymTestCase {
    private func rec(_ kind: ActivityKind, _ minutes: Int, day: Int, effort: Int = 5) -> ActivityRecord {
        ActivityRecord(id: UUID(), kind: kind, date: self.day(day), minutes: minutes, effort: effort)
    }

    func testXPFormula() {
        // 60 min × MET 5 × intensidade 1,0 / 10
        XCTAssertEqual(Game.xp(kind: .musculacao, minutes: 60, effort: 5), 30)
        XCTAssertGreaterThan(Game.xp(kind: .musculacao, minutes: 60, effort: 9), 30)
        XCTAssertEqual(Game.xp(kind: .musculacao, minutes: 0, effort: 5), 0)
        // Duração acima do máximo não rende mais
        XCTAssertEqual(Game.xp(kind: .corrida, minutes: 600, effort: 5), Game.xp(kind: .corrida, minutes: Game.maxMinutes, effort: 5))
    }

    func testDailyHardCap() {
        let s = Game.snapshot((0..<6).map { _ in rec(.corrida, 240, day: 0, effort: 10) })
        XCTAssertLessThanOrEqual(s.totalXP, Game.dailyHardCap)
    }

    func testEggHatchesAtThreshold() {
        XCTAssertEqual(Game.snapshot([]).stage, .egg)
        // 3 dias de 60 min de musculação no esforço 10 (~42 XP cada) passam dos 60 XP
        let s = Game.snapshot((0..<3).map { rec(.musculacao, 60, day: -$0, effort: 10) })
        XCTAssertGreaterThanOrEqual(s.totalXP, Stage.baby.threshold)
        XCTAssertGreaterThanOrEqual(s.stage, .baby)
        XCTAssertFalse(s.evolutions.isEmpty)
    }

    func testStrengthOnlyBranchesToForca() {
        let s = Game.snapshot((0..<60).map { rec(.musculacao, 120, day: -$0, effort: 8) })
        XCTAssertGreaterThanOrEqual(s.stage, .champion)
        XCTAssertEqual(s.form.attribute, .forca)
        XCTAssertNil(s.form.attribute2)
    }

    func testHybridBranchNeedsNearTie() {
        let tie = Game.branch([.forca: 100, .resistencia: 95])
        XCTAssertEqual(tie.0, .forca)
        XCTAssertEqual(tie.1, .resistencia)
        XCTAssertNil(Game.branch([.forca: 100, .resistencia: 80]).1)
        XCTAssertNil(Game.branch([:]).1)
    }

    func testStreakCountsUntilYesterday() {
        let cal = Calendar.current
        let days: Set<Date> = [cal.startOfDay(for: day(-1)), cal.startOfDay(for: day(-2)), cal.startOfDay(for: day(-4))]
        XCTAssertEqual(Game.streak(days: days, now: .now, calendar: cal), 2)
        XCTAssertEqual(Game.bestStreak(days: days, calendar: cal), 2)
    }
}
