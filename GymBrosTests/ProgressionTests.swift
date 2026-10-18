import XCTest
@testable import GymBros

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

    // MARK: Correções do domínio de treino

    func testFiveKiloStepOnlyForBarbellInHeavyGroups() {
        XCTAssertEqual(Exercise.byID("agachamento")?.increment, 5)
        XCTAssertEqual(Exercise.byID("levantamento-terra")?.increment, 5)
        // Máquina, polia e halteres de grupo pesado sobem de 2,5
        XCTAssertEqual(Exercise.byID("cadeira-extensora")?.increment, 2.5)
        XCTAssertEqual(Exercise.byID("leg-press")?.increment, 2.5)
        XCTAssertEqual(Exercise.byID("remada-baixa")?.increment, 2.5)
        XCTAssertEqual(Exercise.byID("remada-unilateral")?.increment, 2.5)
        XCTAssertEqual(Exercise.byID("supino-reto")?.increment, 2.5)
    }

    func testFormatKeepsQuarterKiloPlates() {
        XCTAssertEqual(Progression.fmt(1.25), "1,25")
        XCTAssertEqual(Progression.fmt(2.5), "2,5")
        XCTAssertEqual(Progression.fmt(82.5), "82,5")
        XCTAssertEqual(Progression.fmt(20), "20")
        XCTAssertEqual(Progression.fmt(116.6667), "116,7")
    }

    func testRepCalculatorRoundsToExerciseIncrement() {
        // 1RM 100: 5 reps = 85,7 → 85 nos dois; 12 reps = 71,4 → 72,5 (passo 2,5) ou 70 (passo 5)
        let fine = Dictionary(uniqueKeysWithValues: Progression.repTable(oneRM: 100, increment: 2.5).map { ($0.reps, $0.weight) })
        let coarse = Dictionary(uniqueKeysWithValues: Progression.repTable(oneRM: 100, increment: 5).map { ($0.reps, $0.weight) })
        XCTAssertEqual(fine[5], 85)
        XCTAssertEqual(coarse[5], 85)
        XCTAssertEqual(fine[12], 72.5)
        XCTAssertEqual(coarse[12], 70)
    }

    func testBestMarkDoesNotMixOneRMWithRawLoad() {
        // 60 × 15 não tem 1RM; antes valia a carga bruta (60) contra o 1RM de 70 × 5 (81,7). Agora conta como 60 × 12 (84).
        let high = SetLog(exerciseID: "supino-reto", weight: 60, reps: 15, target: 15, done: true)
        let low = SetLog(exerciseID: "supino-reto", weight: 70, reps: 5, target: 5, done: true)
        XCTAssertEqual(PRBook.best([low, high])?.reps, 15)
        XCTAssertTrue(PRBook.beats(high, low))
        XCTAssertFalse(PRBook.beats(low, high))
        // Mesma marca não é PR novo
        XCTAssertFalse(PRBook.beats(low, low))
    }

    func testAutoFinishEffortIsAverageOfRecentWorkouts() {
        XCTAssertEqual(Progression.estimatedEffort(recent: []), 7)
        XCTAssertEqual(Progression.estimatedEffort(recent: [8, 6, 7]), 7)
        XCTAssertEqual(Progression.estimatedEffort(recent: [10, 10, 9]), 10)
        // Só os 10 últimos
        XCTAssertEqual(Progression.estimatedEffort(recent: Array(repeating: 2, count: 5) + Array(repeating: 9, count: 10)), 9)
    }

    func testDeloadAppliesToAnyPrescription() {
        let d = Deload.apply(Suggestion(weight: 100, reps: 10, reason: ""), sets: 3, exerciseID: "supino-reto")
        XCTAssertEqual(d.suggestion.weight, 70)
        XCTAssertEqual(d.suggestion.reps, 10)
        XCTAssertEqual(d.sets, 2)
        // Incremento de 5: 70 % de 105 = 73,5 → 75
        XCTAssertEqual(Deload.apply(Suggestion(weight: 105, reps: 5, reason: ""), sets: 1, exerciseID: "agachamento").suggestion.weight, 75)
    }

    func testCustomExerciseNameResolves() {
        let saved = Exercise.custom
        defer { Exercise.custom = saved }
        let id = "custom-TESTE"
        Exercise.custom[id] = Exercise(id: id, name: "Remada no cabo da academia", group: .costas, equipment: "Polia")
        XCTAssertEqual(Exercise.name(id), "Remada no cabo da academia")
        XCTAssertEqual(Exercise.name("custom-APAGADO"), "Exercício personalizado")
        XCTAssertEqual(Exercise.name("supino-reto"), "Supino reto")
    }

    func testSwapAlternativesPutSameEquipmentFirst() {
        let base = Exercise.byID("supino-reto")!
        let list = SwapExerciseView.ranked(base: base, candidates: Exercise.builtIn, exclude: [], history: [])
        XCTAssertFalse(list.isEmpty)
        XCTAssertFalse(list.contains { $0.id == base.id })
        XCTAssertTrue(list.allSatisfy { $0.group == .peito })
        // Sem histórico: todas as de barra antes das outras
        let firstOther = list.firstIndex { $0.equipment != "Barra" } ?? list.count
        XCTAssertTrue(list[..<firstOther].allSatisfy { $0.equipment == "Barra" })
        XCTAssertFalse(list[firstOther...].contains { $0.equipment == "Barra" })
        // Já feito vem antes de tudo
        let done = [session("crucifixo", weight: 14, reps: [12], target: 12)]
        XCTAssertEqual(SwapExerciseView.ranked(base: base, candidates: Exercise.builtIn, exclude: [], history: done).first?.id, "crucifixo")
    }

    // MARK: Rampa feita à mão

    private func ramped(_ pairs: [(Double, Int)], target: Int = 10) -> SessionLog {
        SessionLog(date: .now.addingTimeInterval(-86400),
                   sets: pairs.map { SetLog(exerciseID: "agachamento", weight: $0.0, reps: $0.1, target: target, done: true) })
    }

    func testManualRampIsNotWork() {
        // 30×10, 50×10, 70×10, 70×10 numa rotina de 4 séries: só as duas de 70 são trabalho
        let s = Progression.suggest(exerciseID: "agachamento", sets: 4, reps: 8, history: [ramped([(30, 10), (50, 10), (70, 10), (70, 10)])])
        XCTAssertEqual(s.weight, 75)
        XCTAssertEqual(s.sets, 2, "carga nova vai nas mesmas 2 séries pesadas, não nas 4")
        XCTAssertEqual(s.ramp.map(\.weight), [30, 50])
    }

    func testLoadAndSetsDoNotRiseTogether() {
        // Subiu carga: mantém 2 pesadas, mesmo a rotina pedindo 3 sem rampa
        let up = Progression.suggest(exerciseID: "agachamento", sets: 3, reps: 8, history: [ramped([(70, 10), (70, 10)])])
        XCTAssertEqual(up.weight, 75)
        XCTAssertEqual(up.sets, 2)
        // Mesma carga (faltou rep): pode somar uma série, até o que a rotina pede
        let same = Progression.suggest(exerciseID: "agachamento", sets: 3, reps: 10, history: [ramped([(70, 10), (70, 7)])])
        XCTAssertEqual(same.weight, 70)
        XCTAssertEqual(same.sets, 3)
    }

    func testPyramidCloseToTopCountsAsWork() {
        // 60, 65, 70: todas acima de 80 % da maior, são trabalho
        let s = Progression.suggest(exerciseID: "agachamento", sets: 3, reps: 8, history: [ramped([(60, 10), (65, 10), (70, 10)])])
        XCTAssertTrue(s.ramp.isEmpty)
        XCTAssertEqual(s.sets, 3)
    }
}
