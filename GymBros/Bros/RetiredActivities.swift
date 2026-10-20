import Foundation
import SwiftData

/// Atividades apagadas que continuam valendo XP para os bros que as receberam: apagar um treino tira ele da lista,
/// dos números e das ligas, mas não faz o bro voltar de forma. Guardado na conta (`AccountData.userKeys`).
enum RetiredActivities {
    static let key = "retiredActivities"

    struct Entry: Codable, Equatable {
        let id: UUID
        let kind: String
        let date: Date
        let minutes: Int
        let effort: Int
        var healthType: UInt?
        /// Divisão dos atributos como estava (`ActivitySplits`)
        var weights: String?
        /// Bros que receberam o XP
        let owners: [UUID]
        /// Parte do XP de cada um (id → parte); nil nas guardadas antes da regra das partes (tudo)
        var shares: [String: Double]?

        var record: ActivityRecord {
            ActivityRecord(id: id, kind: ActivityKind(rawValue: kind) ?? .outro, date: date, minutes: minutes, effort: effort,
                           healthType: healthType, weights: weights.flatMap(AttributeSplit.decode))
        }
    }

    static func all(_ defaults: UserDefaults = .standard) -> [Entry] {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
    }

    static func save(_ list: [Entry], _ defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(list), forKey: key)
    }

    static func clear(_ defaults: UserDefaults = .standard) { defaults.removeObject(forKey: key) }

    /// Guarda o XP da atividade antes de apagá-la, para os mesmos bros que o receberam
    @MainActor
    static func retire(_ a: Activity, context: ModelContext, defaults: UserDefaults = .standard) {
        let id = a.uuid
        let monsters = (try? context.fetch(FetchDescriptor<Monster>())) ?? []
        let leagues = (try? context.fetch(FetchDescriptor<League>())) ?? []
        let posts = (try? context.fetch(FetchDescriptor<LeagueCheckIn>(predicate: #Predicate { $0.activityUUID == id }))) ?? []
        let starter = monsters.first { $0.isStarter } ?? monsters.first
        let shares = Roster.shares(leagueIDs: Set(posts.map(\.leagueUUID)), owner: a.monsterUUID, known: Set(monsters.map(\.uuid)),
                                   leagueMonster: Dictionary(leagues.map { ($0.uuid, $0.monsterUUID) }, uniquingKeysWith: { x, _ in x }),
                                   starter: starter?.uuid)
        guard !shares.isEmpty else { return }
        var list = all(defaults).filter { $0.id != id }
        list.append(Entry(id: id, kind: a.kindRaw, date: a.date, minutes: a.minutes, effort: a.effort, healthType: a.healthType.map(UInt.init),
                          weights: ActivitySplits.all()[id.uuidString], owners: shares.keys.sorted { $0.uuidString < $1.uuidString },
                          shares: Dictionary(uniqueKeysWithValues: shares.map { ($0.key.uuidString, $0.value) })))
        save(list, defaults)
    }
}
