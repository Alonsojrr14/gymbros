import SwiftData
import XCTest
@testable import GymBros

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

    func testLeaguePeriodFromCalendar() {
        let l = League(name: "P", emoji: "🏆", scoring: .pontos)
        // Começa daqui a 3 dias e termina 10 dias depois: fim no último segundo do dia
        l.setPeriod(start: day(3, hour: 15), end: day(12, hour: 8))
        let cal = Calendar.current
        XCTAssertEqual(l.start, cal.startOfDay(for: day(3)))
        XCTAssertEqual(l.durationDays, 10)
        XCTAssertEqual(cal.component(.hour, from: l.end!), 23)
        XCTAssertFalse(l.hasStarted)
        XCTAssertEqual(l.daysToStart, 3)
        XCTAssertFalse(l.isOver)
        // Fim antes do início vira um dia só
        l.setPeriod(start: day(0), end: day(-5))
        XCTAssertEqual(l.durationDays, 1)
        l.setPeriod(start: day(0), end: nil)
        XCTAssertNil(l.end)
    }

    func testStartTextsUseSingularAndRelativeDays() {
        XCTAssertEqual(League.startsText(day(0)), "começa hoje")
        XCTAssertEqual(League.startsText(day(1)), "começa amanhã")
        XCTAssertEqual(League.startsText(day(5)), "começa em 5 dias")
        XCTAssertEqual(League.startsText(day(-2)), "já começou")
        XCTAssertEqual(LeaguePeriodField.detail(day(0), day(0)), "1 dia · começa hoje")
        XCTAssertEqual(LeaguePeriodField.detail(day(1), day(30)), "30 dias · começa amanhã")
        XCTAssertEqual(LeaguePeriodField.detail(day(0), nil), "Sem data de fim · começa hoje")
    }

    func testRenewalStartsNextSeasonRightAfterTheEnd() throws {
        let ctx = try memoryContext()
        let old = League(name: "Bros", emoji: "🔥", scoring: .treinos)
        old.setPeriod(start: day(-7), end: day(-1))   // 7 dias, acabou ontem
        old.autoRenew = true
        ctx.insert(old)
        LeagueRenewal.run(context: ctx)
        let all = try ctx.fetch(FetchDescriptor<League>())
        XCTAssertEqual(all.count, 2)
        let next = try XCTUnwrap(all.first { $0.uuid == old.nextUUID })
        XCTAssertEqual(next.name, "Bros")
        XCTAssertEqual(next.season, 2)
        XCTAssertEqual(next.seriesKey, old.seriesKey)
        XCTAssertEqual(next.code, old.code)
        XCTAssertEqual(next.durationDays, 7)
        XCTAssertEqual(next.start, Calendar.current.startOfDay(for: day(0)), "Começa no dia seguinte ao fim")
        XCTAssertTrue(next.autoRenew)
        XCTAssertTrue(old.isPastSeason)
        // Rodar de novo não cria outra
        LeagueRenewal.run(context: ctx)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<League>()).count, 2)
    }

    func testRenewalSkipsSeasonsMissedWithAppClosed() {
        let old = League(name: "Bros", emoji: "🔥", scoring: .pontos)
        old.setPeriod(start: day(-30), end: day(-24))   // 7 dias; passaram ~3 temporadas
        let next = LeagueRenewal.makeNext(after: old)
        XCTAssertLessThanOrEqual(next.start, Date.now)
        XCTAssertFalse(next.isOver, "A nova temporada inclui hoje")
        XCTAssertEqual(next.durationDays, 7)
        XCTAssertEqual(next.season, 5)
    }

    func testLeagueWithoutRenewalIsNotRenewed() throws {
        let ctx = try memoryContext()
        let old = League(name: "Uma vez", emoji: "🏆", scoring: .pontos)
        old.setPeriod(start: day(-7), end: day(-1))
        ctx.insert(old)
        LeagueRenewal.run(context: ctx)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<League>()).count, 1)
        XCTAssertFalse(old.autoRenew, "Vem desligada")
    }

    // MARK: Aquecimento, troca em superset, modo fone e WOD

    func testWarmupStaysOutOfTotalsEverywhere() throws {
        let ctx = try memoryContext()
        let s = makeSession(ctx, [("agachamento", 2)])
        let w = LoggedSet(exerciseID: "agachamento", exerciseOrder: 0, index: 0, weight: 40, reps: 10, rest: 60)
        w.warmup = true
        w.done = true
        s.sets.append(w)
        markDone(s, "agachamento")
        XCTAssertEqual(s.workSets.count, 2)
        XCTAssertEqual(s.doneWorkSets.count, 1)
        XCTAssertEqual(s.volume, 200, "Só 20 × 10 da série de trabalho")
        let st = LiveWorkout.state(for: s)
        XCTAssertEqual(st.doneSets, 1)
        XCTAssertEqual(st.totalSets, 2)
    }

    func testPartialSwapInSupersetDoesNotLinkOldToNew() throws {
        let ctx = try memoryContext()
        let s = makeSession(ctx, [("supino-reto", 3), ("barra-fixa", 3)])
        s.setLinkedNext("supino-reto", true)
        s.orderedSets.first { $0.exerciseID == "supino-reto" }?.done = true
        s.swapPending("supino-reto", to: "supino-maquina", suggestion: Suggestion(weight: 50, reps: 10, reason: ""))
        XCTAssertEqual(s.exerciseIDs, ["supino-reto", "supino-maquina", "barra-fixa"])
        XCTAssertFalse(s.linkedNext("supino-reto"), "O antigo (já feito) sai do superset")
        XCTAssertEqual(s.group(of: "supino-maquina"), ["supino-maquina", "barra-fixa"], "O novo segue no superset com o próximo")
        XCTAssertEqual(s.orderedSets.filter { $0.exerciseID == "supino-maquina" }.map(\.weight), [50, 50])
        XCTAssertEqual(s.currentExerciseID, "supino-maquina")
    }

    func testFullSwapTakesThePlaceAndTheLink() throws {
        let ctx = try memoryContext()
        let s = makeSession(ctx, [("supino-reto", 2), ("barra-fixa", 2)])
        s.setLinkedNext("supino-reto", true)
        s.swapPending("supino-reto", to: "supino-maquina", suggestion: Suggestion(weight: 40, reps: 8, reason: ""))
        XCTAssertEqual(s.exerciseIDs, ["supino-maquina", "barra-fixa"])
        XCTAssertEqual(s.group(of: "barra-fixa"), ["supino-maquina", "barra-fixa"])
    }

    func testTenSecondCueSpeaksOncePerRest() {
        var cue = TenSecondCue()
        let t0 = Date.now
        let end = t0.addingTimeInterval(90)
        XCTAssertFalse(cue.check(end: end, now: t0))
        // O laço pode pular o segundo 10 exato (10,9 → 9,1): avisa mesmo assim, uma vez só
        XCTAssertFalse(cue.check(end: end, now: end.addingTimeInterval(-10.9)))
        XCTAssertTrue(cue.check(end: end, now: end.addingTimeInterval(-9.1)))
        XCTAssertFalse(cue.check(end: end, now: end.addingTimeInterval(-8.6)))
        XCTAssertFalse(cue.check(end: end, now: end.addingTimeInterval(-9.5)))
        // Descanso que já começa com menos de 10 s não avisa
        let short = t0.addingTimeInterval(200)
        XCTAssertFalse(cue.check(end: short, now: short.addingTimeInterval(-8)))
        XCTAssertFalse(cue.check(end: nil, now: t0))
        // +15 s: descanso novo, novo aviso
        let longer = end.addingTimeInterval(15)
        XCTAssertFalse(cue.check(end: longer, now: end.addingTimeInterval(-9)))
        XCTAssertTrue(cue.check(end: longer, now: longer.addingTimeInterval(-9.8)))
    }

    func testForTimeCapIsNotAFinishTime() {
        let finished = WodResult(wodID: "fran", wodName: "Fran", formatName: "For Time")
        finished.seconds = 9 * 60 + 50
        let cap = WodResult(wodID: "fran", wodName: "Fran", formatName: "For Time")
        cap.seconds = 600
        cap.capped = true
        cap.reps = 80
        XCTAssertEqual(cap.text, "CAP · 80 reps")
        XCTAssertGreaterThan(finished.score, cap.score, "Qualquer tempo terminado vale mais que estourar o limite")
        let worseCap = WodResult(wodID: "fran", wodName: "Fran", formatName: "For Time")
        worseCap.seconds = 600
        worseCap.capped = true
        worseCap.reps = 60
        XCTAssertGreaterThan(cap.score, worseCap.score)
    }
}
