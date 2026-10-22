import XCTest
@testable import GymBros

/// Treino do coach: texto mandado pelo coach vira WOD com formato, movimentos e partes
final class WodImportTests: GymTestCase {
    func testMessageWithSections() {
        let d = WodParser.parse("""
            *TREINO SEXTA 17/10* 🔥🔥
            AQUECIMENTO
            3 rounds
            - 10 air squats
            - 200m run
            B) Força:
            Back squat 5x5 @75%
            *WOD*
            AMRAP 15'
            10 wall balls 9/6kg
            10 burpees 💪
            """)
        XCTAssertEqual(d.format, .amrap(minutes: 15))
        XCTAssertFalse(d.guessed)
        XCTAssertEqual(d.lines, ["10 wall balls 9/6kg", "10 burpees"])
        XCTAssertEqual(d.parts.map(\.title), ["Aquecimento", "Força"])
        XCTAssertEqual(d.parts.first?.lines, ["3 rounds", "10 air squats", "200m run"])
    }

    func testFormatOnHeaderLineAndTimeCap() {
        let d = WodParser.parse("""
            WOD: For Time - TC 12min
            21-15-9
            Thruster 43/30kg
            Pull-up
            """)
        XCTAssertEqual(d.format, .forTime(capMinutes: 12))
        XCTAssertEqual(d.lines, ["21-15-9", "Thruster 43/30kg", "Pull-up"])
        XCTAssertTrue(d.parts.isEmpty)
    }

    func testFormats() {
        XCTAssertEqual(WodParser.format(in: "EMOM 10"), .emom(minutes: 10))
        XCTAssertEqual(WodParser.format(in: "E2MOM de 16 min"), .every(seconds: 120, minutes: 16))
        XCTAssertEqual(WodParser.format(in: "20' AMRAP"), .amrap(minutes: 20))
        XCTAssertEqual(WodParser.format(in: "Tabata 6 rounds"), .tabata(rounds: 6))
        XCTAssertEqual(WodParser.format(in: "3 rounds for time"), .forTime(capMinutes: nil))
        XCTAssertNil(WodParser.format(in: "10 burpees"))
        XCTAssertNil(WodParser.format(in: "Força total no agachamento"))
    }

    func testFormatLineWithMovementStays() {
        let d = WodParser.parse("3 rounds for time:\n400m run\n21 KB swings")
        XCTAssertEqual(d.format, .forTime(capMinutes: nil))
        XCTAssertEqual(d.lines, ["3 rounds for time:", "400m run", "21 KB swings"])
    }

    func testNumberedSectionsAndCapOnOwnLine() {
        let d = WodParser.parse("""
            Bom dia, galera! Treino de hoje 👇
            1. Mobilidade
            Quadril 2'
            2. Skill: Double unders
            3. Metcon
            For time
            Cap: 15'
            5 rounds:
            12 deadlift 60/40
            """)
        XCTAssertEqual(d.format, .forTime(capMinutes: 15))
        XCTAssertEqual(d.parts.map(\.title), ["Aquecimento", "Skill"])
        XCTAssertEqual(d.lines, ["5 rounds:", "12 deadlift 60/40"])
    }

    func testNoFormatIsGuessed() {
        let d = WodParser.parse("50 double unders\n30 sit-ups")
        XCTAssertTrue(d.guessed)
        XCTAssertEqual(d.lines, ["50 double unders", "30 sit-ups"])
    }

    func testPlanPendingUntilResult() {
        let saved = UserDefaults.standard.string(forKey: WodPlan.key)
        defer { UserDefaults.standard.set(saved, forKey: WodPlan.key) }
        UserDefaults.standard.removeObject(forKey: WodPlan.key)
        let p = PlannedWod(day: Calendar.current.startOfDay(for: .now), name: "WOD", format: .amrap(minutes: 12), lines: ["10 burpees"])
        WodPlan.save(p)
        XCTAssertEqual(WodPlan.pending(done: []), p)
        XCTAssertNil(WodPlan.pending(done: [p.wodID]))
        XCTAssertNil(WodPlan.pending(on: .now.addingTimeInterval(86_400), done: []))
        WodPlan.delete(p)
        XCTAssertTrue(WodPlan.all().isEmpty)
    }
}

/// Print exportado do app do box (Tecnofit): tudo em maiúsculas, blocos com descanso, zeros à esquerda e erros de digitação
final class WodBoxExportTests: GymTestCase {
    private let tecnofit = """
        WOD 19/10/2026
        WOD 1
        TIME CAP 15'
        AMRAP 3'
        5 WALL BALL
        7 KETTLEBELL SWING (1KB)
        9 PUSH UP
        REST 2'
        AMRAP 3'
        03 DEVIL PRESS (2DB)
        06 AVANÇO COM DUMBEL
        9 AIR SQUAT
        REST 2'
        AMRAP 3'
        5 BURPEERS
        7 BICEPS (2DB)
        9 REMADA COSTA (2DB)
        TECNOFIT
        """

    func testBlocksAndLines() {
        let d = WodParser.parse(tecnofit)
        XCTAssertEqual(d.format, .intervals(blocks: [3, 3, 3], rest: 120, emom: false))
        XCTAssertFalse(d.guessed)
        XCTAssertTrue(d.parts.isEmpty)
        XCTAssertEqual(d.lines, ["AMRAP 3'", "5 Wall ball", "7 Kettlebell swing (1 KB)", "9 Push up", "Descanso 2'",
                                 "AMRAP 3'", "3 Devil press (2 DB)", "6 Avanço com dumbbell", "9 Air squat", "Descanso 2'",
                                 "AMRAP 3'", "5 Burpees", "7 Biceps (2 DB)", "9 Remada costa (2 DB)"])
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d.day!)
        XCTAssertEqual([c.year, c.month, c.day], [2026, 10, 19])
    }

    func testBlocksTimeline() {
        let f = WodParser.parse(tecnofit).format
        XCTAssertEqual(f.totalSeconds, 13 * 60)
        XCTAssertEqual(f.name, "3× AMRAP 3' · descanso 2'")
        XCTAssertEqual(f.segment(at: 0)?.segment, WodSegment(block: 0, rest: false, seconds: 180))
        XCTAssertEqual(f.segment(at: 200)?.segment.rest, true)
        XCTAssertEqual(f.segment(at: 200)?.remaining, 100)
        XCTAssertEqual(f.segment(at: 300)?.segment, WodSegment(block: 1, rest: false, seconds: 180))
        XCTAssertEqual(f.segment(at: 600)?.segment.block, 2)
    }

    func testBlocksInOneLine() {
        let d = WodParser.parse("WOD\n3x AMRAP 4' descanso 1'\n10 burpees\n10 wall balls")
        XCTAssertEqual(d.format, .intervals(blocks: [4, 4, 4], rest: 60, emom: false))
    }

    func testOldPlanGetsBlocks() {
        let p = PlannedWod(day: .now, name: "WOD", format: .amrap(minutes: 13), lines: WodParser.parse(tecnofit).lines)
        XCTAssertEqual(p.wod.format, .intervals(blocks: [3, 3, 3], rest: 120, emom: false))
    }

    func testRoundsPerBlock() {
        var st = WodRunState(wod: Wod(id: "x", name: "x", category: "Coach", format: WodParser.parse(tecnofit).format, lines: []))
        let start = Date(timeIntervalSince1970: 1000)
        st.startedAt = start
        st.addRound(start.addingTimeInterval(10))
        st.addRound(start.addingTimeInterval(20))
        st.addRound(start.addingTimeInterval(200))
        st.addRound(start.addingTimeInterval(310))
        XCTAssertEqual(st.blockRounds, [2, 1, 0])
        XCTAssertEqual(st.roundsShown(start.addingTimeInterval(320)), 1)
    }

    func testMovementsIdentified() {
        let d = WodParser.parse(tecnofit)
        XCTAssertEqual(WodMovements.ids(d.lines), ["cf-wall-ball", "kettlebell-swing", "flexao", "cf-devil-press", "afundo",
                                                   "agachamento-livre-corpo", "burpee", "rosca-alternada", "remada-curvada-halter"])
    }

    func testIdentifyVariants() {
        XCTAssertEqual(WodMovements.identify("21 KB swings 24/16kg"), ["kettlebell-swing"])
        XCTAssertEqual(WodMovements.identify("10 Thrusters + 10 pull-ups"), ["thruster", "cf-kipping-pull-up"])
        XCTAssertEqual(WodMovements.identify("15 T2B"), ["cf-toes-to-bar"])
        XCTAssertEqual(WodMovements.identify("5 squat cleans 60/40"), ["cf-squat-clean"])
        XCTAssertEqual(WodMovements.identify("10 box jump over"), ["cf-box-jump-over"])
        XCTAssertEqual(WodMovements.identify("400m run"), ["esteira"])
        XCTAssertEqual(WodMovements.identify("10 flexões de braço"), ["flexao"])
        XCTAssertEqual(WodMovements.identify("Descanso 2'"), [])
    }

    func testEveryAliasExists() {
        XCTAssertEqual(WodMovements.allIDs.filter { Exercise.byID($0) == nil }, [])
    }

    func testDateIgnoresLoads() {
        XCTAssertNil(WodParser.date(in: "10 wall balls 9/6kg"))
        XCTAssertNotNil(WodParser.date(in: "Treino sexta 17/10"))
    }

    /// Dois prints da mesma tela do app do box, escolhidos de baixo para cima
    func testMergeScreenshots() {
        let bottom = ["11:45", "Wod - 19/10/2026", "TIME CAP 10'", "5 - 4 - 3 - 2 - 1/REPS", "DURANTE 10' A CADA 2'", "2 REPS",
                      "PUSH JERKS", "COMEÇANDO COM A CARGA ENCONTRADA", "Metcon", "WOD 1", "TIME CAP 15'", "AMRAP 3'", "5 WALL BALL",
                      "7 KETTLEBELL SWING (1KB)", "9 PUSH UP", "REST 2'", "AMRAP 3'", "03 DEVIL PRESS (2DB)", "06 AVANÇO COM DUMBEL",
                      "9 AIR SQUAT", "REST 2'", "AMRAP 3'", "5 BURPEERS", "7 BICEPS (2DB)", "9 REMADA COSTA (2DB)", "Ações", "Check-In", "0", "0", "0"]
        let top = ["CROSS", "Wod - 19/10/2026", "Warmup", "AQUECIMENTO MMSS/II", "AQUECIMENTO ESPECÍFICO", "DL / SHOUD, APENAS BARRA - 3X-8",
                   "Skill", "FORÇA (DEADLIFT)", "A CADA 2,00", "5 REPS- ?", "5 REPS- ?", "PROGRESSÃO DE CARGA", "LPO (powerlifting)",
                   "ENCONTRAR CARGA PRA SHOUDER", "TIME CAP 10'", "5 - 4 - 3 - 2 - 1/REPS", "DURANTE 10' A CADA 2'", "2 REPS", "PUSH JERKS",
                   "COMEÇANDO COM A CARGA ENCONTRADA", "Metcon", "WOD 1 Check-In", "0", "0", "0"]
        let merged = WodOCR.merge([bottom, top].map { $0.filter { $0.range(of: "^\\d{1,2}:\\d{2}$", options: .regularExpression) == nil } })
        XCTAssertEqual(merged.filter { $0 == "PUSH JERKS" }.count, 1)
        XCTAssertEqual(merged.filter { $0 == "Wod - 19/10/2026" }.count, 1)
        let d = WodParser.parse(merged.joined(separator: "\n"))
        XCTAssertEqual(d.format, .intervals(blocks: [3, 3, 3], rest: 120, emom: false))
        XCTAssertEqual(d.parts.map(\.title), ["Aquecimento", "Força (Deadlift)", "LPO (Powerlifting)"])
        XCTAssertEqual(d.parts[2].lines.first, "Encontrar carga pra shoulder")
        XCTAssertEqual(d.parts.last?.lines.last, "Começando com a carga encontrada")
        XCTAssertEqual(d.lines.first, "AMRAP 3'")
        XCTAssertEqual(d.lines.last, "9 Remada costa (2 DB)")
        XCTAssertEqual(Calendar.current.component(.day, from: d.day!), 19)
    }
}
