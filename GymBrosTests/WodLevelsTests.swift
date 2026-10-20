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
        XCTAssertEqual(d.parts.last?.title.hasPrefix("Outro nível"), true)
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
        XCTAssertTrue(d.parts.contains { $0.title == "Outro nível: Scale" })
        XCTAssertFalse(d.parts.contains { $0.title == "Outro nível: Amador" })
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
