import SwiftData
import XCTest
@testable import GymBros

/// Troca de bros: o que chega vem com a forma e o XP que tinha; o que sai leva o XP dos treinos antigos
@MainActor
final class TradeTests: GymTestCase {
    private func context() throws -> ModelContext {
        let container = try ModelContainer(for: Monster.self, Activity.self, WorkoutSession.self, LoggedSet.self, League.self,
                                           LeagueCheckIn.self, WodResult.self, RouteRecord.self, CheckInComment.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    func testArrivingBroKeepsFormAndXPAndLeavingOneTakesItsXP() throws {
        let ctx = try context()
        let leaving = Monster()
        ctx.insert(leaving)
        for d in 1...6 {
            let a = Activity(kind: .corrida, date: day(-d), minutes: 60, effort: 7)
            a.monsterUUID = leaving.uuid
            ctx.insert(a)
        }
        try ctx.save()
        let lobo = MonsterForm(stage: .champion, attribute: .forca, species: "lobo")
        var p = TradeProposal(id: "t1", from: TradePerson(id: "me", name: "Eu", formID: ""), to: TradePerson(id: "bruno", name: "Bruno", formID: ""),
                              give: TradeBro(id: leaving.uuid.uuidString, name: "Ovo", formID: MonsterForm.egg.id, xp: 0),
                              get: TradeBro(id: "bruno-1", name: lobo.name, formID: lobo.id, xp: 1500, attributes: ["forca": 900, "resistencia": 300]),
                              createdAt: .now)
        XCTAssertNil(TradeLedger.apply(p, context: ctx), "só troca aceita muda a Box")
        p.answer = .accepted
        p.answeredAt = .now
        let bro = try XCTUnwrap(TradeLedger.apply(p, context: ctx))
        XCTAssertNil(TradeLedger.apply(p, context: ctx), "aplica uma vez só")
        let monsters = try ctx.fetch(FetchDescriptor<Monster>())
        XCTAssertEqual(monsters.map(\.uuid), [bro.uuid])
        let roster = Roster(monsters: monsters, activities: try ctx.fetch(FetchDescriptor<Activity>()), checkIns: [], leagues: [])
        let s = roster.snapshot(bro.uuid)
        XCTAssertEqual(s.form, lobo)
        XCTAssertEqual(s.totalXP, 1500, "os treinos do bro que saiu não passam para quem chegou")
        // O XP que veio é do Bruno; o seu começa do zero
        XCTAssertEqual(s.inherited, [OwnerXP(name: "Bruno", xp: 1500)])
        XCTAssertEqual(s.myXP, 0)
        // Daqui pra frente, evolui com os treinos do novo dono
        let next = Game.snapshot([ActivityRecord(id: UUID(), kind: .musculacao, date: .now, minutes: 60, effort: 6)],
                                 base: TradeLedger.bases()[bro.uuid])
        XCTAssertGreaterThan(next.totalXP, 1500)
        XCTAssertEqual(next.inheritedXP, 1500)
        XCTAssertEqual(next.myXP, next.totalXP - 1500)
        XCTAssertEqual(next.form.species, "lobo")
    }

    func testEggsCannotBeTraded() {
        XCTAssertTrue(TradeBro(id: "x", name: "Ovo", formID: MonsterForm.egg.id, xp: 0).isEgg)
        XCTAssertTrue(MockTradeServer.bros(of: "bruno").allSatisfy { $0.isEgg || $0.xp >= $0.form.stage.threshold })
    }

    func testDuelsOnlyBetweenFriends() {
        let store = DuelStore.shared
        let saved = store.friendIDs
        defer { store.friendIDs = saved }
        store.friendIDs = { ["bruno"] }
        XCTAssertEqual(store.personRefusal("desconhecido"), .notFriend)
        XCTAssertNil(store.personRefusal("bruno"))
    }
}
