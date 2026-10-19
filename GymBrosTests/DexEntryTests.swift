import XCTest
@testable import GymBros

/// Ficha do BroBook: linha evolutiva e textos de como conseguir
final class DexEntryTests: GymTestCase {
    func testChain() {
        let rookie = MonsterForm(stage: .rookie, attribute: nil)
        let champ = MonsterForm(stage: .champion, attribute: .forca)
        XCTAssertEqual(DexEntry.previous(rookie), [MonsterForm(stage: .baby, attribute: nil)])
        XCTAssertTrue(DexEntry.next(rookie).contains(champ))
        XCTAssertTrue(DexEntry.previous(MonsterForm(stage: .ultimate, attribute: .tecnica)).contains(champ))
        XCTAssertTrue(DexEntry.next(MonsterForm(stage: .ultimate, attribute: .tecnica)).isEmpty)
        XCTAssertEqual(DexEntry.next(.egg).count, Species.all.filter(\.isReady).count)
    }

    func testHowTo() {
        XCTAssertTrue(DexEntry.howTo(MonsterForm(stage: .champion, attribute: .forca)).contains("Força for o atributo mais treinado"))
        XCTAssertTrue(DexEntry.howTo(MonsterForm(stage: .ultimate, attribute: .forca, attribute2: .tecnica)).contains("Força e Técnica"))
        XCTAssertEqual(DexEntry.kinds(MonsterForm(stage: .champion, attribute: .forca)).first, .musculacao)
    }
}
