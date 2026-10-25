import XCTest
@testable import GymBros

/// "Bros e atributos" do perfil público contra o vetor compartilhado com o Android (`Fixtures/gymbros-public-bros.json`)
final class PublicBrosTests: GymTestCase {
    private func load() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "gymbros-public-bros", withExtension: "json"))
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    func testAttributesMatchVector() throws {
        for c in try load()["attributes"] as! [[String: Any]] {
            let values = (c["values"] as! [String: NSNumber]).reduce(into: [Attribute: Double]()) { $0[Attribute(rawValue: $1.key)!] = $1.value.doubleValue }
            let percent = PublicProfile.Bros.percentages(values)
            XCTAssertEqual(percent, c["percent"] as? [String: Int], "\(c)")
            XCTAssertEqual(PublicProfile.Bros.dominant(percent)?.rawValue, c["dominant"] as? String, "\(c)")
            if let percent { XCTAssertEqual(percent.values.reduce(0, +), 100) }
        }
    }

    func testFavoriteMatchesVector() throws {
        for c in try load()["favorite"] as! [[String: Any]] {
            let got = PublicProfile.Bros.favorite((c["kinds"] as! [String]).map { ActivityKind(rawValue: $0)! })
            let expected = c["favorite"] as? [String: Any]
            XCTAssertEqual(got?.kind, expected?["kind"] as? String, "\(c)")
            XCTAssertEqual(got?.count, expected?["count"] as? Int, "\(c)")
        }
    }

    func testTopMatchesVector() throws {
        for c in try load()["top"] as! [[String: Any]] {
            XCTAssertEqual(PublicProfile.Bros.topIndex(c["xp"] as! [Int]), c["index"] as? Int, "\(c)")
        }
    }

    /// Perfil antigo sem `bros` continua abrindo; e o que sobe volta igual
    func testOldProfilesDecodeAndNewRoundTrips() throws {
        let old = try JSONDecoder().decode(PublicProfile.Extra.self, from: Data(#"{"stats":{"checkIns":1,"activeDays":1,"leagues":0}}"#.utf8))
        XCTAssertNil(old.bros)
        let bros = PublicProfile.Bros(top: .init(name: "Rex", formID: MonsterForm.egg.id, level: 3), dexFound: 4, dexTotal: 80,
                                      favorite: .init(kind: "corrida", count: 7), attributes: ["forca": 10, "resistencia": 70, "agilidade": 20, "tecnica": 0])
        let back = try JSONDecoder().decode(PublicProfile.Extra.self, from: JSONEncoder().encode(PublicProfile.Extra(bros: bros))).bros
        XCTAssertEqual(back?.top?.name, "Rex")
        XCTAssertEqual(back?.favorite?.activity, .corrida)
        XCTAssertEqual(back?.dominant, .resistencia)
        XCTAssertEqual(back?.dexFound, 4)
    }
}
