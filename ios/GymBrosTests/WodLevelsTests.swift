import XCTest
@testable import GymBros

/// Treino de 20/10/2026 do app do box: seções do app (Warmup/Skill/Metcon) com títulos do coach dentro,
/// níveis do Metcon (SCALE/AMADOR), "A CADA 1'30"", alternativas com / e entre parênteses
final class WodLevelsTests: GymTestCase {
    private let top = ["CROSS", "Wod - 20/10/2026", "Warmup", "AQUECIMENTO MMSS/II", "Skill", "FORÇA ()", "PULL UP STRICT", "2 A 4 REPS",
                       "A CADA 1'30\"", "TIME CAP 12'", "(OU ISOMETRIA )", "CONDICIONAMENTO", "5 A 10 ROUNDS", "30 DU / 60 SU", "1 COMPLEX",
                       "1 POWER CLEAN + 1 FRONT SQUAT", "1 HANG SQUAT CLEAN + 1 FRONT SQUAT", "Metcon", "SCALE", "5 ROUNDS",
                       "8 DUMBEL POWER SNATCH", "8 BOX JUMP OVER", "8 RELEASE PUSH UP", "Check-In", "AMADOR", "0", "0", "0"]
    private let bottom = ["Wod - 20/10/2026", "5 A 10 ROUNDS", "30 DU / 60 SU", "1 COMPLEX", "1 POWER CLEAN + 1 FRONT SQUAT",
                          "1 HANG SQUAT CLEAN + 1 FRONT SQUAT", "Metcon", "SCALE", "5 ROUNDS", "8 DUMBEL POWER SNATCH", "8 BOX JUMP OVER",
                          "8 RELEASE PUSH UP", "AMADOR", "5 A 10 ROUNDS", "8 DUMBEL POWER SNATCH", "8 BOX JUMP OVER",
                          "8 HSPU (RELEASE PUSH UP)", "Ações", "Check-in", "Ranking", "Dicas", "Fazer check-in", "Ver Ranking", "Nenhuma",
                          "0", "0", "0"]

    private var text: String { WodOCR.merge([top, bottom]).joined(separator: "\n") }

    func testSectionsInsideTheAppSections() {
        let d = WodParser.parse(text)
        XCTAssertEqual(d.baseParts.map(\.title), ["Aquecimento", "Força", "Condicionamento"])
        XCTAssertFalse(d.parts.contains { $0.title.hasPrefix("Outro nível") }, "os outros níveis ficam para trocar no treino, não viram parte")
        XCTAssertEqual(d.parts[0].lines, ["Aquecimento MMSS/MMII"])
        XCTAssertEqual(d.parts[1].lines, ["Pull up strict", "2 a 4 reps", "A cada 1'30\"", "Time cap 12'", "(ou isometria)"])
        XCTAssertEqual(d.parts[2].lines.first, "5 a 10 rounds")
        XCTAssertFalse(d.lines.contains { ["Ranking", "Dicas", "Nenhuma", "Ver ranking", "Fazer check-in"].contains($0) })
        XCTAssertEqual(Calendar.current.component(.day, from: d.day!), 20)
    }

    func testLevelsBecomeVariants() {
        let d = WodParser.parse(text)
        XCTAssertEqual(d.variants.map(\.title), ["Scale", "Amador"])
        XCTAssertEqual(d.variants[0].lines, ["5 rounds", "8 Dumbbell power snatch", "8 Box jump over", "8 Release push up"])
        XCTAssertEqual(d.variants[1].lines, ["5 a 10 rounds", "8 Dumbbell power snatch", "8 Box jump over", "8 HSPU (release push up)"])
        XCTAssertTrue(d.variants.map(\.title).contains(d.level ?? ""))
        XCTAssertEqual(d.lines, d.variants.first { $0.title == d.level }?.lines)
        XCTAssertFalse(d.guessed, "rounds sem cronômetro é For Time")
        XCTAssertEqual(d.format, .forTime(capMinutes: nil))
    }

    func testPickingALevel() {
        let d = WodParser.parse(text).picking("Amador")
        XCTAssertEqual(d.level, "Amador")
        XCTAssertEqual(d.lines.last, "8 HSPU (release push up)")
        XCTAssertEqual(d.parts.map(\.title), ["Aquecimento", "Força", "Condicionamento"])
    }

    /// WOD importado antes da troca de nível (o outro nível salvo como parte): vira nível de novo, dá para trocar no treino
    func testOldPlanMigratesOtherLevelToLevels() {
        WodLevel.preferred = "Scale"
        defer { WodLevel.preferred = nil }
        let p = PlannedWod(day: .now, name: "Crossfit", format: .forTime(capMinutes: nil),
                           lines: ["5 rounds", "8 Dumbbell power snatch", "8 Box jump over", "8 Release push up"],
                           parts: [WodPart(title: "Força", lines: ["Pull up strict"]),
                                   WodPart(title: "Outro nível: Amador", lines: ["5 a 10 rounds", "8 HSPU (release push up)", "Ver Banking"])])
        let w = p.wod
        XCTAssertEqual(w.parts.map(\.title), ["Força"])
        XCTAssertEqual(w.levels?.map(\.title), ["Scale", "Amador"])
        XCTAssertEqual(w.level, "Scale")
        let amador = w.with(level: "Amador")
        XCTAssertEqual(amador.level, "Amador")
        XCTAssertEqual(amador.lines, ["5 a 10 rounds", "8 HSPU (release push up)"], "o botão lido do print sai")
        XCTAssertEqual(amador.format, .forTime(capMinutes: nil))
        XCTAssertEqual(amador.with(level: "Scale").lines, w.lines)
    }

    func testRankingButtonNoise() {
        XCTAssertTrue(WodParser.isNoise("Ver Banking"))
        XCTAssertTrue(WodParser.isNoise("Ver Ranking"))
    }

    func testComplexIsBrokenIntoItsMovements() {
        let lines = WodParser.expandComplexes(["5 a 10 rounds", "30 DU / 60 SU", "1 Complex", "1 Power clean + 1 front squat",
                                               "1 Hang squat clean + 1 front squat"])
        let mark = WodParser.complexMark
        XCTAssertEqual(lines, ["5 a 10 rounds", "30 DU / 60 SU", "1 Complex: 4 movimentos seguidos, sem soltar a barra",
                               mark + "1 Power clean", mark + "1 Front squat", mark + "1 Hang squat clean", mark + "1 Front squat"])
        XCTAssertEqual(WodParser.expandComplexes(lines), lines, "abrir de novo não muda nada")
        XCTAssertEqual(WodParser.expandComplexes(["Complex: 1 clean + 1 push jerk"]),
                       ["Complex: 2 movimentos seguidos, sem soltar a barra", mark + "1 Clean", mark + "1 Push jerk"])
        XCTAssertEqual(WodParser.expandComplexes(["Complex"]), ["Complex"], "sem os movimentos, fica como veio")
        XCTAssertEqual(Set(WodMovements.ids(lines)), Set(WodMovements.ids(["1 Power clean + 1 front squat", "1 Hang squat clean + 1 front squat",
                                                                       "30 DU / 60 SU"])))
    }

    func testRepsOfEachMovementInTheLine() {
        XCTAssertEqual(WodLoads.reps(of: "cf-double-under", in: ["30 DU / 60 SU"]), 30)
        XCTAssertEqual(WodLoads.reps(of: "pular-corda", in: ["30 DU / 60 SU"]), 60)
        XCTAssertFalse(WodLoads.isWeighted("pular-corda"))
        let rope = WodLoads.next(after: [], exerciseID: "pular-corda", reps: 60, history: [])
        XCTAssertEqual(rope, WodSet(weight: 0, reps: 60), "sem peso conta só as repetições")
        XCTAssertEqual(WodLoads.setText(rope, "pular-corda", spaced: true), "60 reps")
        XCTAssertTrue(WodLoads.tracked(["30 DU / 60 SU"], bodyweight: true).contains("pular-corda"))
        XCTAssertFalse(WodLoads.tracked(["30 DU / 60 SU"], bodyweight: false).contains("pular-corda"))
    }

    func testPercentOfPR() {
        XCTAssertEqual(WodLoads.percents(in: ["5x3 @ 75% do PR"]), [0.75])
        XCTAssertEqual(WodLoads.percents(in: ["70-75-80% 1RM"]), [0.70, 0.75, 0.80])
        XCTAssertEqual(WodLoads.percents(in: ["3 reps 65%/70%/75%"]), [0.65, 0.70, 0.75])
        XCTAssertEqual(WodLoads.percents(in: ["5 Wall ball", "100% esforço? 5%"]), [1.0])
        XCTAssertTrue(WodLoads.percents(in: ["Progressão de carga"]).isEmpty)
        let manual = [SetLog(exerciseID: "levantamento-terra", weight: 100, reps: 1, target: 1, done: true)]
        let orm = WodLoads.oneRM("levantamento-terra", history: [], manual: manual)
        XCTAssertNotNil(orm)
        let pct = [0.70, 0.80]
        let s1 = WodLoads.next(after: [], exerciseID: "levantamento-terra", reps: 5, history: [], percents: pct, oneRM: orm)
        let s2 = WodLoads.next(after: [s1], exerciseID: "levantamento-terra", reps: 5, history: [], percents: pct, oneRM: orm)
        let s3 = WodLoads.next(after: [s1, s2], exerciseID: "levantamento-terra", reps: 5, history: [], percents: pct, oneRM: orm)
        XCTAssertEqual(s1.weight / orm!, 0.70, accuracy: 0.03)
        XCTAssertEqual(s2.weight / orm!, 0.80, accuracy: 0.03)
        XCTAssertEqual(s3.weight, s2.weight, "depois do último %, repete")
        XCTAssertNil(WodLoads.oneRM("levantamento-terra", history: [], manual: []))
    }

    func testEveryMinutesAndSeconds() {
        XCTAssertEqual(WodParser.format(in: "A CADA 1'30\" DURANTE 12'"), .every(seconds: 90, minutes: 12))
        XCTAssertEqual(WodParser.format(in: "a cada 1min30"), .every(seconds: 90, minutes: 0))
        XCTAssertEqual(WodParser.format(in: "5 A 10 ROUNDS"), .forTime(capMinutes: nil))
        XCTAssertEqual(WodParser.format(in: "5 rounds"), .forTime(capMinutes: nil))
    }

    func testMovements() {
        XCTAssertEqual(WodMovements.identify("30 DU / 60 SU"), ["cf-double-under", "pular-corda"])
        XCTAssertEqual(WodMovements.identify("8 HSPU (RELEASE PUSH UP)"), ["cf-hspu"])
        XCTAssertEqual(WodMovements.identify("8 DUMBEL POWER SNATCH"), ["cf-dumbbell-snatch"])
        XCTAssertEqual(WodMovements.identify("PULL UP STRICT"), ["barra-fixa"])
        XCTAssertEqual(WodMovements.identify("1 HANG SQUAT CLEAN + 1 FRONT SQUAT"), ["cf-squat-clean", "agachamento-frontal"])
        XCTAssertEqual(WodMovements.identify("8 RELEASE PUSH UP"), ["flexao"])
        XCTAssertEqual(WodMovements.identify("9 REMADA COSTA (2DB)"), ["remada-curvada-halter"], "equipamento entre parênteses ainda conta")
    }
}

/// Navegar entre as partes do treino não zera o relógio de nenhuma: voltar numa anterior só mostra o tempo feito lá
final class WodPartClockTests: XCTestCase {
    private var wod: Wod {
        Wod(id: "t", name: "T", category: "Coach", format: .forTime(capMinutes: nil), lines: ["5 burpees"],
            parts: [WodPart(title: "Aquecimento", lines: []), WodPart(title: "Força", lines: []), WodPart(title: "Condicionamento", lines: [])])
    }

    func testViewingDoesNotMoveTheClock() {
        var s = WodRunState(wod: wod)
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        s.work(on: 0, now: t0)
        // Toque na força só para ver o que vem: o aquecimento continua correndo
        s.view(1)
        XCTAssertEqual(s.phase, 1)
        XCTAssertEqual(s.working, 0)
        XCTAssertEqual(s.partElapsed(0, now: t0.addingTimeInterval(120)), 120)
        XCTAssertEqual(s.partElapsed(1, now: t0.addingTimeInterval(120)), 0)
    }

    func testEachPartKeepsItsTimeAndCanContinue() {
        var s = WodRunState(wod: wod)
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        s.work(on: 0, now: t0)
        s.work(on: 1, now: t0.addingTimeInterval(300))
        s.work(on: 2, now: t0.addingTimeInterval(900))
        s.view(1)
        let now = t0.addingTimeInterval(1060)
        XCTAssertEqual(s.partElapsed(0, now: now), 300)
        XCTAssertEqual(s.partElapsed(1, now: now), 600, "a força mostra o que foi feito lá, parado")
        XCTAssertEqual(s.partElapsed(2, now: now), 160, "o condicionamento não parou enquanto você olhava a força")
        // Continuar no aquecimento: segue dos 300 s e o condicionamento para
        s.view(0)
        s.work(on: 0, now: now)
        XCTAssertEqual(s.working, 0)
        XCTAssertEqual(s.partElapsed(0, now: now.addingTimeInterval(60)), 360)
        XCTAssertEqual(s.partElapsed(2, now: now.addingTimeInterval(60)), 160)
        // Avança para o WOD: o aquecimento fecha
        s.work(on: 3, now: now.addingTimeInterval(100))
        XCTAssertEqual(s.partElapsed(0, now: now.addingTimeInterval(500)), 400)
        XCTAssertTrue(s.onWod)
    }

    func testResetPart() {
        var s = WodRunState(wod: wod)
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        s.work(on: 0, now: t0)
        s.work(on: 1, now: t0.addingTimeInterval(10))
        s.resetPart(1, now: t0.addingTimeInterval(20))
        XCTAssertEqual(s.partElapsed(1, now: t0.addingTimeInterval(25)), 5, "a em andamento recomeça do zero")
        s.resetPart(0)
        XCTAssertEqual(s.partElapsed(0, now: t0.addingTimeInterval(25)), 0)
    }

    func testOldRunStateStillDecodes() throws {
        let old = #"{"wod":{"id":"t","name":"T","category":"Coach","format":{"forTime":{}},"lines":[],"exercises":[],"parts":[]},"openedAt":0,"pausedTotal":0,"rounds":0,"placeAsked":false,"liveID":"x","phase":1,"blockRounds":[],"loads":[],"checked":[]}"#
        let s = try JSONDecoder().decode(WodRunState.self, from: Data(old.utf8))
        XCTAssertEqual(s.working, 1)
        XCTAssertNil(s.partSeconds)
    }
}
