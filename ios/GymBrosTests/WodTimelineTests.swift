import XCTest
@testable import GymBros

/// Linha do tempo dos WODs: importados ficam todos, com o resultado junto
final class WodTimelineTests: GymTestCase {
    func testImportedKeepResultAndOthersStandAlone() {
        let old = PlannedWod(day: Calendar.current.date(byAdding: .day, value: -40, to: .now)!, name: "WOD do coach", format: .amrap(minutes: 13), lines: ["5 Wall ball"])
        let next = PlannedWod(day: Calendar.current.date(byAdding: .day, value: 2, to: .now)!, name: "WOD de quarta", format: .forTime(capMinutes: 15), lines: [])
        let r = WodResult(wodID: old.wodID, wodName: old.name, formatName: old.format.name)
        r.rounds = 4
        let fran = WodResult(wodID: Wod.benchmarks[0].id, wodName: Wod.benchmarks[0].name, formatName: "For Time")
        fran.seconds = 400
        let e = WodTimelineEntry.build(plans: [old, next], results: [r, fran])
        XCTAssertEqual(e.count, 3)
        XCTAssertEqual(e.first?.id, next.wodID)
        XCTAssertEqual(e.first?.status(), .scheduled)
        XCTAssertEqual(e.first { $0.id == old.wodID }?.status(), .done)
    }

    func testOldPlansAreKept() {
        let saved = UserDefaults.standard.string(forKey: WodPlan.key)
        defer { UserDefaults.standard.set(saved, forKey: WodPlan.key) }
        UserDefaults.standard.removeObject(forKey: WodPlan.key)
        let p = PlannedWod(day: Calendar.current.date(byAdding: .day, value: -90, to: .now)!, name: "Antigo", format: .amrap(minutes: 10), lines: ["x"])
        WodPlan.save(p)
        XCTAssertEqual(WodPlan.all().map(\.id), [p.id])
    }
}
