import XCTest
@testable import GymBros

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

    func testLegendTurnsWithinChampionLine() {
        // Vira Halterobro na musculação e passa a fase Atleta só correndo: Lenda de virada da linha da Força
        let lifting = (0..<25).map { rec(.musculacao, 120, day: -100 + $0, effort: 8) }
        let running = (0..<75).map { rec(.corrida, 120, day: -75 + $0, effort: 8) }
        let s = Game.snapshot(lifting + running)
        let virada = MonsterForm(stage: .ultimate, attribute: .resistencia, origin: .forca)
        XCTAssertEqual(s.form, virada)
        XCTAssertTrue(virada.isVirada)
        XCTAssertEqual(virada.name, "Estivabro")
        XCTAssertEqual(virada.champion, MonsterForm(stage: .champion, attribute: .forca))
        XCTAssertNotEqual(virada, MonsterForm(stage: .ultimate, attribute: .resistencia))
        // Sem arte ainda: aparece mesmo assim (sem imagem); só o widget usa a arte da Lenda pura da linha
        XCTAssertEqual(virada.resolved, virada)
        XCTAssertEqual(virada.spriteWithFallback, virada.hasArt ? virada.sprite : MonsterForm(stage: .ultimate, attribute: .forca).sprite)
        let before = Game.snapshot(lifting + running.prefix(10))
        XCTAssertEqual(before.stage, .champion)
        XCTAssertEqual(before.nextForm, virada)
        // Mesmo treino na fase Atleta: Lenda pura
        let pure = Game.snapshot((0..<60).map { rec(.musculacao, 120, day: -60 + $0, effort: 8) })
        XCTAssertEqual(pure.form, MonsterForm(stage: .ultimate, attribute: .forca))
        XCTAssertFalse(pure.form.isVirada)
    }

    func testEveryChampionHasItsOwnTenLegends() {
        var names: [String] = []
        for sp in Species.all {
            let viradas = MonsterForm.viradas(species: sp.id)
            XCTAssertEqual(viradas.count, 90, sp.id)
            for f in viradas {
                XCTAssertNotNil(Species.viradaNames[sp.id]?[f.key], f.id)
                XCTAssertEqual(MonsterForm.byID(f.id), f, f.id)
            }
            let pures = MonsterForm.all(species: sp.id).filter { $0.stage == .ultimate }
                + MonsterForm.hybrids(species: sp.id).filter { $0.stage == .ultimate }
            names += (viradas + pures).map(\.name)
        }
        XCTAssertEqual(names.count, 800)
        XCTAssertEqual(Set(names).count, 800)
        let halter = MonsterForm(stage: .champion, attribute: .forca)
        XCTAssertEqual(MonsterForm.viradas(from: halter).count, 9)
        XCTAssertEqual(MonsterForm(stage: .ultimate, attribute: .forca, attribute2: .resistencia, origin: .forca).name, "Strongmanbro")
        XCTAssertEqual(MonsterForm(stage: .ultimate, attribute: .forca, attribute2: .resistencia).name, "Hércubro")
    }

    func testHybridBranchNeedsNearTie() {
        let tie = Game.branch([.forca: 100, .resistencia: 95])
        XCTAssertEqual(tie.0, .forca)
        XCTAssertEqual(tie.1, .resistencia)
        XCTAssertNil(Game.branch([.forca: 100, .resistencia: 80]).1)
        XCTAssertNil(Game.branch([:]).1)
    }

    func testHatchFollowsMainActivity() {
        let seed = UUID()
        func hatch(_ items: [(ActivityKind, Int)], health: UInt? = nil) -> String {
            let recs = items.map { k, minutes in
                var r = ActivityRecord(id: UUID(), kind: k, date: .now, minutes: minutes, effort: 5)
                r.healthType = health
                return r
            }
            return Species.hatch(records: recs, seed: seed).id
        }
        // Atividade com mais da metade dos minutos do ovo decide (a espécie, se a arte estiver pronta)
        XCTAssertTrue(["urso", "rato", "coelho"].contains(hatch([(.musculacao, 40), (.crossfit, 20)])))
        // Musculação 60 min e corrida 40 min: vence a musculação (por XP, a corrida venceria)
        XCTAssertTrue(["urso", "rato", "coelho"].contains(hatch([(.musculacao, 60), (.corrida, 40)])))
        XCTAssertTrue(["lobo", "coelho"].contains(hatch([(.corrida, 61)])))
        XCTAssertTrue(["coruja", "coelho"].contains(hatch([(.outro, 61)], health: 21)), "golfe no Saúde é Coruja")  // 21 = golf
        // Sem atividade principal, "Outro" ou ovo vazio: Coelho
        XCTAssertEqual(hatch([(.corrida, 30), (.yoga, 30)]), Species.standard.id)
        XCTAssertEqual(hatch([(.outro, 60)]), Species.standard.id)
        XCTAssertEqual(hatch([]), Species.standard.id)
    }

    func testEveryActivityHasAnimal() {
        let ids = Set(Species.all.map(\.id))
        for k in ActivityKind.allCases { XCTAssertFalse(Hatch.species(for: k).isEmpty, k.rawValue) }
        // Todo animal nasce de alguma atividade do app
        XCTAssertEqual(Set(ActivityKind.allCases.flatMap { Hatch.species(for: $0) }), ids)
    }

    func testMainAlwaysGetsXPAndLeagueRepGetsAShare() {
        let starter = UUID(), main = UUID(), rep = UUID(), gone = UUID()
        let league = UUID(), league2 = UUID(), orphan = UUID(), mine = UUID()
        let known: Set<UUID> = [starter, main, rep]
        let reps: [UUID: UUID?] = [league: rep, league2: rep, orphan: gone, mine: main]
        func shares(_ ids: Set<UUID>, _ owner: UUID?) -> [UUID: Double] {
            Roster.shares(leagueIDs: ids, owner: owner, known: known, leagueMonster: reps, starter: starter)
        }
        // Liga marcada: o principal leva tudo e o representante (uma vez só) um pouco menos
        XCTAssertEqual(shares([league, league2], main), [main: 1, rep: Roster.leagueShare])
        // Sem liga (ou liga sem representante válido): só o principal
        XCTAssertEqual(shares([], main), [main: 1])
        XCTAssertEqual(shares([orphan, UUID()], main), [main: 1])
        // O principal também representa a liga: recebe uma vez, inteiro
        XCTAssertEqual(shares([mine, league], main), [main: 1, rep: Roster.leagueShare])
        XCTAssertEqual(shares([mine], main), [main: 1])
        // Dono que não existe mais: vai para o inicial
        XCTAssertEqual(shares([], gone), [starter: 1])
    }

    func testLeagueShareGivesLessXP() {
        var full = ActivityRecord(id: UUID(), kind: .corrida, date: day(-1), minutes: 60, effort: 6)
        let a = Game.snapshot([full]).totalXP
        full.share = Roster.leagueShare
        let b = Game.snapshot([full]).totalXP
        XCTAssertLessThan(b, a)
        XCTAssertGreaterThan(b, 0)
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
