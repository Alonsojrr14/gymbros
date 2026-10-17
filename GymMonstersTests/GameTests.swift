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

    func testBalancedHatchIsStandardSpecies() {
        let seed = UUID()
        // Nenhum atributo com 35% do total: nasce Coelho
        XCTAssertEqual(Species.hatch(attributes: [.forca: 25, .resistencia: 25, .agilidade: 25, .tecnica: 25], seed: seed).id, Species.standard.id)
        XCTAssertEqual(Species.hatch(attributes: [.forca: 34, .resistencia: 33, .agilidade: 33], seed: seed).id, Species.standard.id)
        XCTAssertEqual(Species.hatch(attributes: [:], seed: seed).id, Species.standard.id)
        // Com afinidade clara, só nasce espécie dessa afinidade (ou Coelho se nenhuma estiver pronta)
        let yoga = Species.hatch(attributes: [.tecnica: 60], seed: seed)
        XCTAssertTrue(yoga.affinity == .tecnica || yoga.id == Species.standard.id)
    }

    func testXPOwnersFollowLeagues() {
        let starter = UUID(), main = UUID(), rep = UUID(), gone = UUID()
        let league = UUID(), league2 = UUID(), orphan = UUID()
        let known: Set<UUID> = [starter, main, rep]
        let reps: [UUID: UUID?] = [league: rep, league2: rep, orphan: gone]
        func owners(_ ids: Set<UUID>, _ owner: UUID?) -> Set<UUID> {
            Roster.owners(leagueIDs: ids, owner: owner, known: known, leagueMonster: reps, starter: starter)
        }
        // Liga marcada: vai para o representante, uma vez só
        XCTAssertEqual(owners([league, league2], main), [rep])
        // Sem liga (ou só perfil/liga sem representante válido): vai para o dono gravado
        XCTAssertEqual(owners([], main), [main])
        XCTAssertEqual(owners([orphan, UUID()], main), [main])
        // Dono que não existe mais: vai para o inicial
        XCTAssertEqual(owners([], gone), [starter])
    }

    func testStreakCountsUntilYesterday() {
        let cal = Calendar.current
        let days: Set<Date> = [cal.startOfDay(for: day(-1)), cal.startOfDay(for: day(-2)), cal.startOfDay(for: day(-4))]
        XCTAssertEqual(Game.streak(days: days, now: .now, calendar: cal), 2)
        XCTAssertEqual(Game.bestStreak(days: days, calendar: cal), 2)
    }

    func testCachedSnapshotMatchesUncached() {
        SnapshotCache.shared.removeAll()
        let kinds: [ActivityKind] = [.musculacao, .corrida, .yoga, .natacao, .volei]
        let base = (0..<200).map { i in rec(kinds[i % kinds.count], 30 + i % 90, day: -(i / 3), effort: 3 + i % 8) }
        func assertSame(_ a: Snapshot, _ b: Snapshot, file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertEqual(a.totalXP, b.totalXP, file: file, line: line)
            XCTAssertEqual(a.form, b.form, file: file, line: line)
            XCTAssertEqual(a.stageAttributes, b.stageAttributes, file: file, line: line)
            XCTAssertEqual(a.lifetimeAttributes, b.lifetimeAttributes, file: file, line: line)
            XCTAssertEqual(a.hatchAttributes, b.hatchAttributes, file: file, line: line)
            XCTAssertEqual(a.evolutions.map(\.id), b.evolutions.map(\.id), file: file, line: line)
            XCTAssertEqual(a.xpByActivity, b.xpByActivity, file: file, line: line)
            XCTAssertEqual(a.streak, b.streak, file: file, line: line)
            XCTAssertEqual(a.bestStreak, b.bestStreak, file: file, line: line)
            XCTAssertEqual(a.lastActivity, b.lastActivity, file: file, line: line)
            XCTAssertEqual(a.todayXP, b.todayXP, file: file, line: line)
        }
        // Primeira chamada calcula, a segunda vem do cache: as duas iguais ao cálculo direto
        assertSame(Game.cachedSnapshot(base), Game.snapshot(base))
        assertSame(Game.cachedSnapshot(base), Game.snapshot(base))
        assertSame(Game.cachedSnapshot([]), Game.snapshot([]))
        // Editar minutos, esforço ou apagar uma atividade invalida o cache
        var edited = base
        let e = edited[5]
        edited[5] = ActivityRecord(id: e.id, kind: e.kind, date: e.date, minutes: e.minutes + 60, effort: 10)
        assertSame(Game.cachedSnapshot(edited), Game.snapshot(edited))
        XCTAssertNotEqual(Game.cachedSnapshot(edited).totalXP, Game.cachedSnapshot(base).totalXP)
        let removed = Array(base.dropFirst())
        assertSame(Game.cachedSnapshot(removed), Game.snapshot(removed))
        // Outro dia (sequência e XP de hoje dependem dele)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        assertSame(Game.cachedSnapshot(base, now: tomorrow), Game.snapshot(base, now: tomorrow))
        XCTAssertEqual(Game.cachedSnapshot(base, now: tomorrow).todayXP, 0)
    }
}
