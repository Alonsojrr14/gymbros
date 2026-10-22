import Foundation
import SwiftData
import XCTest
@testable import GymBros

/// Os testes rodam dentro do app instalado: tudo o que mexe em Ajustes ou em estado global
/// é guardado antes e devolvido depois, para não bagunçar os dados de verdade.
@MainActor
class GymTestCase: XCTestCase {
    private static let keys = ["exerciseGoals", "deloadUntil", "deloadSnooze", "barCountsBar", RetiredActivities.key, MainMonster.key] + TradeLedger.keys
    private var saved: [String: Any] = [:]
    private var savedPRs: [String: [SetLog]] = [:]

    override func setUp() async throws {
        let d = UserDefaults.standard
        saved = [:]
        for k in Self.keys { if let v = d.object(forKey: k) { saved[k] = v } }
        for k in Self.keys { d.removeObject(forKey: k) }
        savedPRs = PRBook.manual
        PRBook.manual = [:]
    }

    /// UserDefaults só do teste, apagado no fim (no iPhone, o hospedeiro é o app de verdade)
    func scratchDefaults(_ name: String = "teste") -> UserDefaults {
        let suite = "\(name)-\(UUID().uuidString)"
        scratchSuites.append(suite)
        return UserDefaults(suiteName: suite)!
    }

    private var scratchSuites: [String] = []

    override func tearDown() async throws {
        for s in scratchSuites { UserDefaults.standard.removePersistentDomain(forName: s) }
        scratchSuites = []
        let d = UserDefaults.standard
        for k in Self.keys { d.removeObject(forKey: k) }
        for (k, v) in saved { d.set(v, forKey: k) }
        PRBook.manual = savedPRs
    }

    /// Banco em memória, separado do banco do app
    func memoryContext() throws -> ModelContext {
        let container = try ModelContainer(for: Activity.self, WorkoutSession.self, LoggedSet.self, League.self, LeagueCheckIn.self, CheckInReview.self, Routine.self, RoutineItem.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    /// Conta de teste com a atribuição dada (`nil` = sem atribuição, ou seja, USER)
    func signedInAccess(_ assignment: [String]? = nil, userID: String = "tester") async -> AccessStore {
        let user = AuthUser(id: userID, name: "Teste", email: "teste@exemplo.com", provider: .email, token: "")
        let access = AccessStore(currentUser: { user })
        access.backend = MockRoleBackend(assignments: assignment.map { [userID: $0] } ?? [:])
        await access.refresh()
        return access
    }

    /// Treino com `sets` séries iguais de um exercício
    func session(_ id: String, weight: Double, reps: [Int], target: Int, daysAgo: Int = 1, deload: Bool = false) -> SessionLog {
        SessionLog(date: .now.addingTimeInterval(-Double(daysAgo) * 86400),
                   sets: reps.map { SetLog(exerciseID: id, weight: weight, reps: $0, target: target, done: true) },
                   deload: deload)
    }

    func day(_ offset: Int, hour: Int = 10) -> Date {
        let cal = Calendar.current
        return cal.date(byAdding: .hour, value: hour, to: cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: .now))!)!
    }
}
