import XCTest
@testable import GymBros

/// Transformador MFIT → GymBros contra capturas reais da conta (vetores em `Fixtures/mfit-*.json`).
/// Sem rede: só decodifica e transforma. O Android terá de chegar ao mesmo resultado.
final class MFitImportTests: GymTestCase {
    private func data(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"),
                                "fixture \(name) fora do bundle de teste")
        return try Data(contentsOf: url)
    }

    func testTransformaPlanoReal() throws {
        let detail = try data("mfit-plan")
        let session = try data("mfit-session")
        let plan = try MFitTransformer.plan(fromDetail: detail, sessions: [167117402: session])

        XCTAssertEqual(plan.source, "mfit")
        XCTAssertEqual(plan.goalCode, 3)
        XCTAssertEqual(plan.difficultyCode, 2)
        XCTAssertEqual(plan.difficulty, "Intermediário")
        XCTAssertFalse(plan.name.contains("&#"), "nome deve vir com HTML decodificado")
        XCTAssertEqual(plan.days.count, 3)

        let ombro = try XCTUnwrap(plan.days.first { $0.sourceID == "167117402" })
        XCTAssertEqual(ombro.weekday, "Terça")
        XCTAssertEqual(ombro.blocks.count, 8)

        let desenv = try XCTUnwrap(ombro.blocks.flatMap(\.exercises).first { $0.name.contains("Desenvolvimento") })
        XCTAssertEqual(desenv.sets.count, 4)
        XCTAssertEqual(desenv.sets.first?.reps, "1x12")
        XCTAssertEqual(desenv.sets.first?.weight, "11")
        XCTAssertEqual(desenv.sets.first?.restSeconds, 90)
        XCTAssertEqual(desenv.category, "strength")

        // Dias sem sessão capturada ficam sem exercícios (no app real, o import busca todas as sessões).
        XCTAssertEqual(plan.days.filter { $0.blocks.isEmpty }.count, 2)
    }

    func testHtmlDecode() {
        XCTAssertEqual(MFitTransformer.htmlDecode("Atualizado &#9940;"), "Atualizado ⛔")
        XCTAssertEqual(MFitTransformer.htmlDecode("A &amp; B"), "A & B")
    }
}
