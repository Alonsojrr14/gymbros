import SwiftData
import XCTest
@testable import GymBros

/// Treino informado no registro de atividade (esqueceu de dar Começar)
@MainActor
final class ManualWorkoutTests: GymTestCase {
    private func context() throws -> ModelContext {
        ModelContext(try ModelContainer(for: AppData.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    func testRoutineBecomesFinishedSession() throws {
        let ctx = try context()
        let a = Activity(kind: .musculacao, date: .now.addingTimeInterval(-3600), minutes: 50, effort: 7)
        ctx.insert(a)
        var d = ManualWorkoutDraft()
        d.mode = .routine
        d.title = "Peito"
        d.items = [.init(exerciseID: "supino-reto", sets: 3, reps: 8, weight: 60)]
        d.save(for: a, context: ctx)
        let s = try XCTUnwrap(try ctx.fetch(FetchDescriptor<WorkoutSession>()).first)
        XCTAssertEqual(s.activityUUID, a.uuid)
        XCTAssertNotNil(s.end)
        XCTAssertEqual(s.doneWorkSets.count, 3)
        XCTAssertEqual(s.volume, 3 * 8 * 60)
    }

    func testWodResult() throws {
        let ctx = try context()
        let a = Activity(kind: .crossfit, date: .now, minutes: 20, effort: 8)
        ctx.insert(a)
        var d = ManualWorkoutDraft()
        d.mode = .wod
        d.wodID = Wod.benchmarks.first { if case .forTime = $0.format { true } else { false } }!.id
        d.minutesDone = 7
        d.secondsDone = 30
        d.save(for: a, context: ctx)
        let r = try XCTUnwrap(try ctx.fetch(FetchDescriptor<WodResult>()).first)
        XCTAssertEqual(r.seconds, 450)
        XCTAssertEqual(r.activityUUID, a.uuid)
    }
}
