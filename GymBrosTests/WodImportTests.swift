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
        XCTAssertEqual(WodParser.format(in: "E2MOM de 16 min"), .emom(minutes: 16))
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
