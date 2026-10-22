import XCTest
@testable import GymBros

/// X1: só bro chocado luta, e você escolhe qual
@MainActor
final class DuelFighterTests: GymTestCase {
    func testEggsCannotFight() async {
        let store = DuelStore.shared
        let saved = store.fighters
        defer { store.fighters = saved }
        store.fighters = { [] }
        XCTAssertEqual(store.refusal("alguem"), .noHatchedBro)
        do {
            try await store.challenge(DuelPerson(id: "alguem", name: "Alguém", formID: ""), metric: .xp)
            XCTFail("Ovo não pode desafiar")
        } catch {
            XCTAssertEqual(error as? DuelRefusal, .noHatchedBro)
        }
    }

    func testChosenBroRepresentsYou() {
        let store = DuelStore.shared
        let saved = store.fighters
        defer { store.fighters = saved }
        let a = Monster(name: "Koda"), b = Monster(name: "Bolt")
        a.lastFormID = MonsterForm(stage: .rookie, attribute: nil).id
        b.lastFormID = MonsterForm(stage: .champion, attribute: .forca).id
        store.fighters = { [a, b] }
        XCTAssertEqual(store.person(with: b.uuid).formID, b.lastFormID)
        XCTAssertNil(store.refusal("alguem").flatMap { $0 == .noHatchedBro ? $0 : nil })
    }
}
