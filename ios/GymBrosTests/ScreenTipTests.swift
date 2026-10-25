import XCTest
@testable import GymBros

/// Dicas por tela: catálogo, formato da chave `tipsSeen` (o Android usa o mesmo) e quando mostrar
final class ScreenTipTests: GymTestCase {
    func testCatalogHasStableUniqueKebabIDsAndShortCards() {
        let ids = ScreenTip.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        for tip in ScreenTip.all {
            XCTAssertNotNil(tip.id.range(of: "^[a-z0-9]+(-[a-z0-9]+)*$", options: .regularExpression), tip.id)
            XCTAssertFalse(tip.id.contains(","), tip.id)
            XCTAssertTrue((2...4).contains(tip.cards.count), "\(tip.id) tem \(tip.cards.count) cartões")
            for c in tip.cards {
                XCTAssertFalse(c.title.isEmpty)
                XCTAssertFalse(c.symbol.isEmpty)
                XCTAssertLessThanOrEqual(c.text.count, 200, "\(tip.id): \(c.title)")
            }
        }
    }

    func testParseIgnoresEmptiesSpacesAndRepeats() {
        XCTAssertEqual(ScreenTips.parse(nil), [])
        XCTAssertEqual(ScreenTips.parse(""), [])
        XCTAssertEqual(ScreenTips.parse("box"), ["box"])
        XCTAssertEqual(ScreenTips.parse(" box, ,brobook,,box ,x1,"), ["box", "brobook", "x1"])
        XCTAssertEqual(ScreenTips.encode(["box", "", "x1", "box"]), "box,x1")
    }

    func testNotSeenShowsAndMarkingHidesForGood() {
        let d = scratchDefaults("tips")
        XCTAssertTrue(ScreenTips.shouldShow(.box, d))
        XCTAssertFalse(ScreenTips.shouldShow(.box, blocked: true, d))

        ScreenTips.markSeen("box", d)
        ScreenTips.markSeen("x1", d)
        ScreenTips.markSeen("box", d)
        XCTAssertEqual(d.string(forKey: ScreenTips.key), "box,x1")
        XCTAssertFalse(ScreenTips.shouldShow(.box, d))
        XCTAssertFalse(ScreenTips.shouldShow(.duels, d))
        XCTAssertTrue(ScreenTips.shouldShow(.brobook, d))
    }

    func testResetShowsEverythingAgain() {
        let d = scratchDefaults("tips")
        for tip in ScreenTip.all { ScreenTips.markSeen(tip.id, d) }
        XCTAssertEqual(ScreenTips.seen(d), Set(ScreenTip.all.map(\.id)))
        ScreenTips.reset(d)
        XCTAssertNil(d.object(forKey: ScreenTips.key))
        XCTAssertTrue(ScreenTip.all.allSatisfy { ScreenTips.shouldShow($0, d) })
    }

    /// Vem de outro aparelho com espaços ou ids que este app ainda não conhece: lê o que entende e não perde o resto
    func testUnknownIDsSurviveMarking() {
        let d = scratchDefaults("tips")
        d.set("dica-nova, box", forKey: ScreenTips.key)
        XCTAssertFalse(ScreenTips.shouldShow(.box, d))
        ScreenTips.markSeen("feed", d)
        XCTAssertEqual(d.string(forKey: ScreenTips.key), "dica-nova,box,feed")
    }

    func testKeyGoesWithTheAccountCopy() {
        XCTAssertTrue(AccountData.userKeys.contains(ScreenTips.key))
    }

    func testCenterNeverShowsUnderXCTest() {
        let center = ScreenTipCenter()
        center.defaults = scratchDefaults("tips")
        XCTAssertFalse(center.isEnabled)
        XCTAssertFalse(center.claim(.box))
        center.finish(.box)
        XCTAssertTrue(ScreenTips.hasSeen("box", center.defaults))
        XCTAssertNil(center.showing)
    }
}
