import XCTest
import HealthKit
@testable import GymBros

/// Divisão do XP entre atributos de acordo com o treino feito
final class AttributeSplitTests: GymTestCase {
    private func sets(_ id: String, reps: Int, rest: Int = 120, count: Int = 4) -> [AttributeSplit.SetSignal] {
        Array(repeating: .init(exerciseID: id, reps: reps, rest: rest), count: count)
    }

    private func sum(_ w: [Attribute: Double]) -> Double { w.values.reduce(0, +) }

    func testPlainActivityKeepsCategoryTable() {
        let w = AttributeSplit.split(.init(kind: .musculacao, minutes: 50, effort: 6))
        XCTAssertEqual(w, ActivityKind.musculacao.weights)
    }

    func testHeavyVersusLightStrength() {
        let heavy = AttributeSplit.split(.init(kind: .musculacao, minutes: 50, effort: 7, sets: sets("agachamento", reps: 3)))
        let light = AttributeSplit.split(.init(kind: .musculacao, minutes: 50, effort: 7, sets: sets("cadeira-flexora", reps: 20, rest: 40)))
        XCTAssertGreaterThan(heavy[.forca]!, 0.8)
        XCTAssertGreaterThan(light[.resistencia]!, light[.forca]!)
        XCTAssertEqual(sum(heavy), 1, accuracy: 0.001)
        XCTAssertEqual(sum(light), 1, accuracy: 0.001)
    }

    func testOlympicLiftingIsTechnique() {
        let w = AttributeSplit.split(.init(kind: .musculacao, minutes: 60, effort: 7, sets: sets("cf-snatch", reps: 2)))
        XCTAssertGreaterThan(w[.tecnica]!, 0.35)
    }

    func testRunPaceAndDistance() {
        let fast = AttributeSplit.split(.init(kind: .corrida, minutes: 20, effort: 8, meters: 5000))
        let long = AttributeSplit.split(.init(kind: .corrida, minutes: 110, effort: 5, meters: 18000))
        XCTAssertGreaterThan(fast[.agilidade]!, 0.4)
        XCTAssertGreaterThan(long[.resistencia]!, 0.85)
    }

    func testWodFormatAndMovements() {
        let gym = AttributeSplit.split(.init(kind: .crossfit, minutes: 12, effort: 8,
                                             wod: .init(format: .amrap(minutes: 12), exercises: ["cf-hspu", "cf-pistol", "cf-toes-to-bar"])))
        let engine = AttributeSplit.split(.init(kind: .crossfit, minutes: 30, effort: 7,
                                                wod: .init(format: .forTime(capMinutes: 30), exercises: ["cf-row-cal", "esteira"])))
        XCTAssertGreaterThan(gym[.tecnica] ?? 0, 0.25)
        XCTAssertGreaterThan(engine[.resistencia]!, 0.6)
    }

    func testHealthTypeIsMoreSpecific() {
        let basket = AttributeSplit.split(.init(kind: .futebol, minutes: 60, effort: 6, healthType: HKWorkoutActivityType.basketball.rawValue))
        XCTAssertNotNil(basket[.tecnica])
        let pilates = AttributeSplit.split(.init(kind: .yoga, minutes: 50, effort: 5, healthType: HKWorkoutActivityType.pilates.rawValue))
        XCTAssertNotNil(pilates[.forca])
    }

    func testEncodeRoundTrip() {
        let w: [Attribute: Double] = [.forca: 0.62, .tecnica: 0.38]
        XCTAssertEqual(AttributeSplit.decode(AttributeSplit.encode(w)), w)
    }

    func testGameUsesStoredSplit() {
        var r = ActivityRecord(id: UUID(), kind: .musculacao, date: .now, minutes: 60, effort: 6)
        r.weights = [.tecnica: 1]
        let s = Game.snapshot([r])
        XCTAssertNil(s.lifetimeAttributes[.forca])
        XCTAssertGreaterThan(s.lifetimeAttributes[.tecnica]!, 0)
    }
}
