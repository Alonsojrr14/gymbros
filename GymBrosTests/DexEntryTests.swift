import XCTest
@testable import GymBros

/// Ficha do BroBook: linha evolutiva e textos de como conseguir
final class DexEntryTests: GymTestCase {
    func testChain() {
        let rookie = MonsterForm(stage: .rookie, attribute: nil)
        let champ = MonsterForm(stage: .champion, attribute: .forca)
        XCTAssertEqual(DexEntry.previous(rookie), [MonsterForm(stage: .baby, attribute: nil)])
        XCTAssertTrue(DexEntry.next(rookie).contains(champ))
        // Linha reta: cada Atleta tem uma Lenda só, e vice-versa
        XCTAssertEqual(DexEntry.previous(MonsterForm(stage: .ultimate, attribute: .forca)), [champ])
        XCTAssertEqual(DexEntry.next(champ).first, MonsterForm(stage: .ultimate, attribute: .forca))
        XCTAssertEqual(DexEntry.previous(MonsterForm(stage: .ultimate, attribute: .resistencia, origin: .forca)), [champ])
        XCTAssertTrue(DexEntry.next(MonsterForm(stage: .ultimate, attribute: .tecnica)).isEmpty)
        XCTAssertEqual(DexEntry.next(.egg).count, Species.all.filter(\.isReady).count)
    }

    func testHowTo() {
        XCTAssertTrue(DexEntry.howTo(MonsterForm(stage: .champion, attribute: .forca)).contains("Força for o atributo mais treinado"))
        XCTAssertTrue(DexEntry.howTo(MonsterForm(stage: .champion, attribute: .forca, attribute2: .tecnica)).contains("Força e Técnica"))
        XCTAssertTrue(DexEntry.howTo(MonsterForm(stage: .ultimate, attribute: .forca, attribute2: .tecnica)).contains("Arrancobro"))
        XCTAssertTrue(DexEntry.howTo(MonsterForm(stage: .ultimate, attribute: .resistencia, origin: .forca)).contains("Halterobro"))
        XCTAssertEqual(DexEntry.kinds(MonsterForm(stage: .champion, attribute: .forca)).first, .musculacao)
    }
}
