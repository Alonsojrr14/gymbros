import XCTest
@testable import GymMonsters

/// Sugestão de carga: progressão linear, deload por falhas, objetivos, PR e aquecimento
final class ProgressionTests: GymTestCase {
    // supino-reto: peito com barra → incremento 2,5 kg; agachamento: quadríceps com barra → 5 kg

    func testFirstTimeWithoutHistorySuggestsNoLoad() {
        let s = Progression.suggest(exerciseID: "supino-reto", sets: 3, reps: 10, history: [])
        XCTAssertEqual(s.weight, 0)
        XCTAssertEqual(s.reps, 10)
    }

    func testCompletingAllSetsAddsIncrement() {
        let h = [session("supino-reto", weight: 60, reps: [10, 10, 10], target: 10)]
        XCTAssertEqual(Progression.suggest(exerciseID: "supino-reto", sets: 3, reps: 10, history: h).weight, 62.5)
        let squat = [session("agachamento", weight: 100, reps: [8, 8, 8], target: 8)]
        XCTAssertEqual(Progression.suggest(exerciseID: "agachamento", sets: 3, reps: 8, history: squat).weight, 105)
    }

    func testMissingRepsKeepsLoad() {
        let h = [session("supino-reto", weight: 60, reps: [10, 10, 7], target: 10)]
        let s = Progression.suggest(exerciseID: "supino-reto", sets: 3, reps: 10, history: h)
        XCTAssertEqual(s.weight, 60)
        XCTAssertEqual(s.reps, 10)
    }

    func testThreeMissesInARowDeloadsTenPercent() {
        let h = (1...3).reversed().map { session("agachamento", weight: 100, reps: [8, 8, 6], target: 8, daysAgo: $0 * 2) }
        // 90 kg arredondado para baixo no incremento de 5
        XCTAssertEqual(Progression.suggest(exerciseID: "agachamento", sets: 3, reps: 8, history: h).weight, 90)
    }

    func testHigherTargetKeepsLoad() {
        let h = [session("supino-reto", weight: 60, reps: [8, 8, 8], target: 8)]
        let s = Progression.suggest(exerciseID: "supino-reto", sets: 3, reps: 10, history: h)
        XCTAssertEqual(s.weight, 60)
        XCTAssertEqual(s.reps, 10)
    }

    func testBodyweightAndTimeProgressByRepsAndSeconds() {
        let push = [session("flexao", weight: 0, reps: [12, 12, 12], target: 12)]
        XCTAssertEqual(Progression.suggest(exerciseID: "flexao", sets: 3, reps: 12, history: push).reps, 13)
        let plank = [session("prancha", weight: 0, reps: [45, 45, 45], target: 45)]
        XCTAssertEqual(Progression.suggest(exerciseID: "prancha", sets: 3, reps: 45, history: plank).reps, 50)
    }

    // MARK: Objetivo e dupla progressão

    func testGoalStartsAtBottomOfRange() {
        TrainingGoal.set(.hipertrofia, for: "supino-reto")
        XCTAssertEqual(TrainingGoal.of("supino-reto"), .hipertrofia)
        XCTAssertEqual(Progression.suggest(exerciseID: "supino-reto", sets: 3, reps: 10, history: []).reps, 8)
    }

    func testDoubleProgressionAddsRepThenLoad() {
        TrainingGoal.set(.hipertrofia, for: "supino-reto")
        let mid = [session("supino-reto", weight: 40, reps: [9, 9, 9], target: 9)]
        let a = Progression.suggest(exerciseID: "supino-reto", sets: 3, reps: 9, history: mid)
        XCTAssertEqual(a.weight, 40)
        XCTAssertEqual(a.reps, 10)

        let top = [session("supino-reto", weight: 40, reps: [12, 12, 12], target: 12)]
        let b = Progression.suggest(exerciseID: "supino-reto", sets: 3, reps: 12, history: top)
        XCTAssertEqual(b.weight, 42.5)
        XCTAssertEqual(b.reps, 8)

        let miss = [session("supino-reto", weight: 40, reps: [10, 10, 8], target: 10)]
        let c = Progression.suggest(exerciseID: "supino-reto", sets: 3, reps: 10, history: miss)
        XCTAssertEqual(c.weight, 40)
        XCTAssertEqual(c.reps, 10)
    }

    func testRemovingGoalGoesBackToFixedReps() {
        TrainingGoal.set(.forca, for: "agachamento")
        TrainingGoal.set(nil, for: "agachamento")
        XCTAssertNil(TrainingGoal.of("agachamento"))
    }

    // MARK: PR e deload

    func testFirstTimeUsesManualPR() {
        // 100 × 5 → 1RM ~116,7 → 10 reps ~87,5 → 92 % ~80,5 → 80 (incremento 5)
        PRBook.manual = ["agachamento": [SetLog(exerciseID: "agachamento", weight: 100, reps: 5, target: 5, done: true)]]
        let s = Progression.suggest(exerciseID: "agachamento", sets: 3, reps: 10, history: [])
        XCTAssertEqual(s.weight, 80)
        XCTAssertTrue(s.reason.contains("PR"))
    }

    func testDeloadSessionsDoNotCountAsReference() {
        let h = [session("supino-reto", weight: 60, reps: [10, 10, 10], target: 10, daysAgo: 8),
                 session("supino-reto", weight: 42.5, reps: [10, 10], target: 10, daysAgo: 1, deload: true)]
        XCTAssertEqual(Progression.suggest(exerciseID: "supino-reto", sets: 3, reps: 10, history: h).weight, 62.5)
    }

    // MARK: Aquecimento, 1RM e recordes

    func testWarmupIsLighterThanWorkAndRespectsBar() {
        let w = Progression.warmup(work: 100, increment: 5, minimum: 20)
        XCTAssertEqual(w.map(\.weight), [40, 60, 80])
        XCTAssertEqual(w.map(\.reps), [10, 6, 3])
        // Carga baixa: tudo daria a barra vazia ou mais, então não há aquecimento
        XCTAssertTrue(Progression.warmup(work: 20, increment: 2.5, minimum: 20).isEmpty)
        XCTAssertTrue(Progression.warmup(work: 0, increment: 2.5).isEmpty)
    }

    func testOneRMEpley() {
        XCTAssertEqual(Progression.oneRM(weight: 100, reps: 1), 100)
        XCTAssertEqual(Progression.oneRM(weight: 90, reps: 10)!, 120, accuracy: 0.01)
        XCTAssertNil(Progression.oneRM(weight: 50, reps: 15))
        XCTAssertNil(Progression.oneRM(weight: 0, reps: 5))
    }

    func testRecordsDetectHeavierLoad() {
        let before = [session("supino-reto", weight: 60, reps: [10, 10], target: 10, daysAgo: 5)]
        let now = session("supino-reto", weight: 65, reps: [8, 8], target: 8, daysAgo: 0)
        XCTAssertFalse(Progression.records(in: now, history: before).isEmpty)
        let same = session("supino-reto", weight: 60, reps: [10, 10], target: 10, daysAgo: 0)
        XCTAssertTrue(Progression.records(in: same, history: before).isEmpty)
    }
}
