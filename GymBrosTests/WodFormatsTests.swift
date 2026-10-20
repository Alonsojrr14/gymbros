import SwiftData
import XCTest
@testable import GymBros

/// Formatos do CrossFit além do AMRAP simples: E2MOM, RFT, escada, chipper, e as cargas registradas no treino
final class WodFormatsTests: GymTestCase {
    func testEveryFormats() {
        XCTAssertEqual(WodParser.format(in: "E2MOM 10'"), .every(seconds: 120, minutes: 10))
        XCTAssertEqual(WodParser.format(in: "DURANTE 10' A CADA 2'"), .every(seconds: 120, minutes: 10))
        XCTAssertEqual(WodParser.format(in: "A CADA 2,00"), .every(seconds: 120, minutes: 0))
        XCTAssertEqual(WodParser.format(in: "Every 90s for 12 min"), .every(seconds: 90, minutes: 12))
        XCTAssertEqual(WodParser.format(in: "EMOM 12'"), .emom(minutes: 12))
        XCTAssertEqual(WodFormat.every(seconds: 120, minutes: 10).totalSeconds, 600)
        XCTAssertNil(WodFormat.every(seconds: 120, minutes: 0).totalSeconds)
    }

    func testRoundsAndLadder() {
        XCTAssertEqual(WodScheme.rounds(["5 rodadas de:", "400 m de corrida"]), 5)
        XCTAssertEqual(WodScheme.rounds(["3 rounds for time", "10 burpees"]), 3)
        XCTAssertNil(WodScheme.rounds(["10 burpees"]))
        XCTAssertEqual(WodScheme.ladder(["21-15-9 repetições de:", "Thruster"]), [21, 15, 9])
        XCTAssertNil(WodScheme.ladder(["10 wall balls 9/6kg"]))
    }

    func testChipper() {
        let chipper = Wod(id: "c", name: "c", category: "Coach", format: .forTime(capMinutes: 30),
                          lines: ["50 wall balls", "40 burpees", "30 kettlebell swings", "20 pull-ups"])
        XCTAssertTrue(WodScheme.isChipper(chipper))
        XCTAssertFalse(WodScheme.isChipper(Wod.byID("fran")!))
        XCTAssertFalse(WodScheme.isChipper(Wod.byID("helen")!))
    }

    func testLoadReps() {
        XCTAssertEqual(WodLoads.reps(in: ["Back squat 5x3 @75%"]), 3)
        XCTAssertEqual(WodLoads.reps(in: ["A cada 2,00", "5 reps"]), 5)
        XCTAssertEqual(WodLoads.reps(in: ["5-4-3-2-1/reps"]), 5)
        XCTAssertEqual(WodLoads.reps(in: ["Push jerks"]), 5)
    }

    func testNextSetProgresses() {
        let first = WodLoads.next(after: [], exerciseID: "levantamento-terra", reps: 5, history: [])
        XCTAssertEqual(first.reps, 5)
        let next = WodLoads.next(after: [WodSet(weight: 80, reps: 5)], exerciseID: "levantamento-terra", reps: 5, history: [])
        XCTAssertEqual(next, WodSet(weight: 85, reps: 5))
    }

    @MainActor
    func testLoadsBecomeSessionSets() throws {
        let container = try ModelContainer(for: AppData.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let a = Activity(kind: .crossfit, date: .now, minutes: 60, effort: 8, note: "WOD")
        context.insert(a)
        WodLoads.save([WodLoad(exerciseID: "levantamento-terra", part: 1, sets: [WodSet(weight: 80, reps: 5), WodSet(weight: 85, reps: 5)]),
                       WodLoad(exerciseID: "cf-push-jerk", part: 2, sets: [])],
                      title: "WOD · cargas", activity: a, context: context)
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].activityUUID, a.uuid)
        XCTAssertEqual(sessions[0].log.sets.map(\.weight), [60, 65])
        XCTAssertTrue(sessions[0].sets.allSatisfy(\.done))
    }

    func testCoachPrintPartsHaveTimers() {
        let force = ["A cada 2,00", "5 reps- ?", "Progressão de carga"]
        XCTAssertEqual(force.lazy.compactMap(WodParser.format(in:)).first, .every(seconds: 120, minutes: 0))
        XCTAssertEqual(WodParser.format(in: "Durante 10' a cada 2'"), .every(seconds: 120, minutes: 10))
    }
}

final class WodBlockGroupsTests: GymTestCase {
    func testTecnofitBlocks() {
        let lines = ["AMRAP 3'", "5 Wall ball", "7 Kettlebell swing (1 KB)", "9 Push up", "Descanso 2'",
                     "AMRAP 3'", "3 Devil press (2 DB)", "Descanso 2'", "AMRAP 3'", "5 Burpees"]
        XCTAssertEqual(WodScheme.blocks(lines), [["5 Wall ball", "7 Kettlebell swing (1 KB)", "9 Push up"], ["3 Devil press (2 DB)"], ["5 Burpees"]])
    }
}

final class WodBarTests: GymTestCase {
    func testPerSide() {
        XCTAssertEqual(WodSet(weight: 80, reps: 5, bar: 20).perSide, 30)
        XCTAssertEqual(WodSet(weight: 35, reps: 5, bar: 15).perSide, 10)
    }

    func testFirstSetCountsBar() {
        let s = WodLoads.next(after: [], exerciseID: "cf-push-jerk", reps: 2, history: [], bar: 15)
        XCTAssertEqual(s.bar, 15)
        XCTAssertGreaterThanOrEqual(s.weight, 15)
        let n = WodLoads.next(after: [WodSet(weight: 50, reps: 2, bar: 15)], exerciseID: "cf-push-jerk", reps: 2, history: [])
        XCTAssertEqual(n.bar, 15)
        XCTAssertEqual(n.weight, 52.5)
    }

    @MainActor
    func testStrengthOnlySessionStoresPlates() throws {
        let container = try ModelContainer(for: AppData.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let a = Activity(kind: .crossfit, date: .now, minutes: 60, effort: 8, note: "WOD")
        context.insert(a)
        WodLoads.save([WodLoad(exerciseID: "levantamento-terra", part: 1, sets: [WodSet(weight: 100, reps: 5, bar: 20)])],
                      title: "x", activity: a, context: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LoggedSet>()).map(\.weight), [80])
    }

    @MainActor
    func testCrossfitSessionStoresTotal() throws {
        let container = try ModelContainer(for: AppData.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let a = Activity(kind: .crossfit, date: .now, minutes: 60, effort: 8, note: "WOD")
        context.insert(a)
        WodLoads.save([WodLoad(exerciseID: "cf-push-jerk", part: 2, sets: [WodSet(weight: 60, reps: 2, bar: 20)])],
                      title: "x", activity: a, context: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LoggedSet>()).map(\.weight), [60])
    }
}
