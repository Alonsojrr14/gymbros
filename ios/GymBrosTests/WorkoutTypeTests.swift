import XCTest
@testable import GymBros

/// Tipos de treino do Apple Saúde no registro de atividade
final class WorkoutTypeTests: GymTestCase {
    func testCatalog() {
        XCTAssertEqual(Set(WorkoutType.all.map(\.id)).count, WorkoutType.all.count)
        XCTAssertGreaterThanOrEqual(WorkoutType.all.count, 80)
        // As 12 categorias antigas voltam para elas mesmas
        for k in ActivityKind.allCases { XCTAssertEqual(WorkoutType.of(k).kind, k, k.name) }
    }

    func testSearch() {
        XCTAssertEqual(WorkoutType.search("beach").first?.name, "Tênis")
        XCTAssertTrue(WorkoutType.search("jiu").contains { $0.name == "Artes marciais" })
        XCTAssertTrue(WorkoutType.search("natacao").contains { $0.name == "Natação" })
        XCTAssertEqual(WorkoutType.search("").count, WorkoutType.all.count)
    }
}
