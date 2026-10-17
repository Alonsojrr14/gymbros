import SwiftData
import XCTest
@testable import GymMonsters

/// Nomes das formas (todos únicos) e carga na barra automática pelo tipo de treino
final class NamesAndBarTests: GymTestCase {
    func testEveryFormHasUniqueName() {
        var seen: [String: String] = [:]
        for sp in Species.all {
            for form in MonsterForm.all(species: sp.id) + MonsterForm.hybrids(species: sp.id) where form.stage != .egg {
                XCTAssertNotEqual(form.name, form.key, "\(sp.id)/\(form.key) sem nome")
                XCTAssertFalse(form.name.contains(" "), "\(form.name): nome com a espécie no fim")
                if let other = seen[form.name] { XCTFail("\(form.name) repetido: \(other) e \(form.id)") }
                seen[form.name] = form.id
            }
        }
        XCTAssertEqual(seen.count, Species.all.count * 22)
    }

    func testBarWeightFollowsWorkoutType() throws {
        let ctx = try memoryContext()
        let squat = try XCTUnwrap(Exercise.byID("agachamento"))
        let lifting = WorkoutSession(title: "Perna", routineUUID: nil)
        ctx.insert(lifting)
        lifting.sets.append(LoggedSet(exerciseID: "agachamento", exerciseOrder: 0, index: 0, weight: 60, reps: 8, rest: 90))
        XCTAssertFalse(lifting.isCrossfit)
        XCTAssertFalse(squat.weightIncludesBar(in: lifting), "musculação: só anilhas, mesmo no agachamento")
        XCTAssertEqual(squat.weightUnit(in: lifting), "kg anilhas")

        let wod = WorkoutSession(title: "WOD", routineUUID: nil)
        ctx.insert(wod)
        wod.sets.append(LoggedSet(exerciseID: "cf-squat-clean", exerciseOrder: 0, index: 0, weight: 60, reps: 5, rest: 60))
        wod.sets.append(LoggedSet(exerciseID: "agachamento", exerciseOrder: 1, index: 0, weight: 80, reps: 5, rest: 60))
        XCTAssertTrue(wod.isCrossfit)
        XCTAssertTrue(squat.weightIncludesBar(in: wod), "CrossFit: total com a barra")
        XCTAssertEqual(squat.weightUnit(in: wod), "kg total")
    }
}
