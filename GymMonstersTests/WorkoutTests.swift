import SwiftData
import XCTest
@testable import GymMonsters

/// Superset, deload por semanas seguidas e ranking das ligas (com banco em memória)
final class WorkoutTests: GymTestCase {
    private func makeSession(_ ctx: ModelContext, _ plan: [(String, Int)]) -> WorkoutSession {
        let s = WorkoutSession(title: "Teste", routineUUID: nil)
        ctx.insert(s)
        for (order, (id, n)) in plan.enumerated() {
            for k in 0..<n { s.sets.append(LoggedSet(exerciseID: id, exerciseOrder: order, index: k, weight: 20, reps: 10, rest: 90)) }
        }
        return s
    }

    private func markDone(_ s: WorkoutSession, _ id: String) {
        s.orderedSets.first { $0.exerciseID == id && !$0.done }?.done = true
    }

    func testSupersetAlternatesWithoutRest() throws {
        let ctx = try memoryContext()
        let s = makeSession(ctx, [("supino-reto", 2), ("barra-fixa", 2), ("agachamento", 2)])
        s.setLinkedNext("supino-reto", true)
        XCTAssertEqual(s.group(of: "barra-fixa"), ["supino-reto", "barra-fixa"])
        XCTAssertEqual(s.group(of: "agachamento"), ["agachamento"])

        markDone(s, "supino-reto")
        XCTAssertFalse(s.advance(after: "supino-reto"), "Dentro do superset não descansa")
        XCTAssertEqual(s.currentExerciseID, "barra-fixa")

        markDone(s, "barra-fixa")
        XCTAssertTrue(s.advance(after: "barra-fixa"), "Fechou a volta: descansa")
        XCTAssertEqual(s.currentExerciseID, "supino-reto")

        markDone(s, "supino-reto"); s.advance(after: "supino-reto")
        markDone(s, "barra-fixa")
        XCTAssertTrue(s.advance(after: "barra-fixa"))
        XCTAssertEqual(s.currentExerciseID, "agachamento", "Superset completo: vai para o próximo exercício")
    }

    func testWithoutSupersetRestsAndStaysUntilDone() throws {
        let ctx = try memoryContext()
        let s = makeSession(ctx, [("supino-reto", 2), ("agachamento", 1)])
        markDone(s, "supino-reto")
        XCTAssertTrue(s.advance(after: "supino-reto"))
        XCTAssertEqual(s.currentExerciseID, "supino-reto")
        markDone(s, "supino-reto")
        s.advance(after: "supino-reto")
        XCTAssertEqual(s.currentExerciseID, "agachamento")
    }

    func testWarmupSetsStayOutOfTheLog() throws {
        let ctx = try memoryContext()
        let s = makeSession(ctx, [("agachamento", 3)])
        let w = LoggedSet(exerciseID: "agachamento", exerciseOrder: 0, index: 0, weight: 40, reps: 10, rest: 60)
        w.warmup = true
        s.sets.append(w)
        XCTAssertEqual(s.log.sets.count, 3)
        XCTAssertTrue(s.log.sets.allSatisfy { $0.weight == 20 })
    }

    func testDeloadStreakCountsConsecutiveWeeks() throws {
        let ctx = try memoryContext()
        let cal = Calendar.current
        var sessions: [WorkoutSession] = []
        func add(weeksAgo: Int, deload: Bool = false) {
            let s = WorkoutSession(title: "S", routineUUID: nil)
            s.start = cal.date(byAdding: .weekOfYear, value: -weeksAgo, to: .now)!
            s.end = s.start.addingTimeInterval(3600)
            s.isDeload = deload
            ctx.insert(s)
            sessions.append(s)
        }
        for w in 0..<5 { add(weeksAgo: w) }
        XCTAssertEqual(Deload.streak(sessions), 5)
        XCTAssertTrue(Deload.shouldSuggest(sessions))

        Deload.snooze()
        XCTAssertFalse(Deload.shouldSuggest(sessions), "Adiado não sugere de novo")

        // Semana de deload no meio corta a contagem
        sessions.removeAll()
        for w in 0..<3 { add(weeksAgo: w) }
        add(weeksAgo: 3, deload: true)
        for w in 4..<7 { add(weeksAgo: w) }
        XCTAssertEqual(Deload.streak(sessions), 3)
    }

    func testDeloadActivationLastsUntilEndOfWeek() {
        XCTAssertFalse(Deload.active)
        Deload.start()
        XCTAssertTrue(Deload.active)
        Deload.stop()
        XCTAssertFalse(Deload.active)
    }

    func testLeagueRankingRespectsPeriodAndScoring() throws {
        let ctx = try memoryContext()
        let league = League(name: "Teste", emoji: "🏆", scoring: .treinos, start: day(-10))
        league.setDuration(days: 8)   // terminou anteontem
        ctx.insert(league)
        var acts: [UUID: Activity] = [:]
        var mine: [LeagueCheckIn] = []
        for offset in [-9, -5, -1] {   // o último fica depois do fim
            let a = Activity(kind: .musculacao, date: day(offset), minutes: 60, effort: 6)
            ctx.insert(a)
            acts[a.uuid] = a
            mine.append(LeagueCheckIn(leagueUUID: league.uuid, activityUUID: a.uuid, title: "T", note: "", date: a.date, photo: nil))
        }
        let avatar = MonsterForm(stage: .egg, attribute: nil)
        let feed = LeagueBoard.feed(league: league, mine: mine, activities: acts, me: "Eu", myAvatar: avatar)
        XCTAssertEqual(feed.count, 3)
        let rank = LeagueBoard.ranking(feed: feed, league: league, me: "Eu", myAvatar: avatar, since: nil)
        XCTAssertEqual(rank.first { $0.isMe }?.score, 2, "Só os 2 check-ins dentro do período contam")
        XCTAssertTrue(league.isOver)
        XCTAssertEqual(league.durationDays, 8)
    }
}
