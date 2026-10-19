import Foundation
import SwiftData

/// Schema da primeira versão publicada: igual ao store que já está nos aparelhos
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [Activity.self, Routine.self, RoutineItem.self, WorkoutSession.self, LoggedSet.self,
         CustomExercise.self, SchemaV1.League.self, LeagueCheckIn.self, Monster.self, BodyEntry.self, ExerciseNote.self,
         WodResult.self, RouteRecord.self, GymVisit.self, Gym.self, CheckInComment.self, PersonalRecord.self,
         LeagueMessage.self]
    }

    /// League como foi publicada na V1 (congelada: não mexer)
    @Model
    final class League {
        var uuid: UUID = UUID()
        var name: String = ""
        var emoji: String = "🏆"
        var scoringRaw: String = LeagueScoring.pontos.rawValue
        var start: Date = Date.now
        var code: String = ""
        var isMock: Bool = false
        var joinedAt: Date = Date.now
        var monsterUUID: UUID?
        var end: Date?
        @Attribute(.externalStorage) var cover: Data?
        var autoRenew: Bool = false
        var season: Int = 1
        var seriesID: UUID?
        var nextUUID: UUID?
        var weightsRaw: String = ""
        var tieBreakRaw: String = LeagueTieBreak.primeiro.rawValue
        var photoRuleRaw: String = PhotoRule.livre.rawValue
        var teamsRaw: String = ""
        var syncedAt: Date?
        var joined: Bool = false
        var myTeamID: String?

        init() {}
    }
}

/// V2: `League.swissRaw` (critério da rodada suíça)
enum SchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [Activity.self, Routine.self, RoutineItem.self, WorkoutSession.self, LoggedSet.self,
         CustomExercise.self, League.self, LeagueCheckIn.self, Monster.self, BodyEntry.self, ExerciseNote.self,
         WodResult.self, RouteRecord.self, GymVisit.self, Gym.self, CheckInComment.self, PersonalRecord.self,
         LeagueMessage.self]
    }
}

enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self] }
    static var stages: [MigrationStage] { [.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)] }
}

/// Container único do app, compartilhado com os botões do Live Activity (que rodam no processo do app)
@MainActor
enum AppData {
    static let schema = Schema(versionedSchema: SchemaV2.self)

    /// Cópia do banco que não abriu (migração que falhou); o app começa com um banco novo em vez de fechar ao abrir
    private(set) static var recoveredCopy: URL?

    static let container: ModelContainer = {
        let config = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        if let c = try? ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: config) {
            protect(config.url)
            return c
        }
        recoveredCopy = setAside(config.url)
        if let c = try? ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: config) {
            protect(config.url)
            return c
        }
        // Último recurso: roda sem gravar, mas abre
        return try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }()

    /// Arquivos do SQLite: o banco e os auxiliares do journal
    private static func files(_ url: URL) -> [URL] {
        [url, URL(fileURLWithPath: url.path + "-wal"), URL(fileURLWithPath: url.path + "-shm")]
    }

    /// Dados de saúde e localização: só legíveis depois do primeiro desbloqueio do aparelho
    private static func protect(_ url: URL) {
        for f in files(url) where FileManager.default.fileExists(atPath: f.path) {
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: f.path)
        }
    }

    /// Move o banco com problema para o lado (ex.: default-erro-1760000000.store), sem apagar nada
    private static func setAside(_ url: URL) -> URL? {
        let stamp = Int(Date.now.timeIntervalSince1970)
        let base = url.deletingPathExtension().lastPathComponent
        let dest = url.deletingLastPathComponent().appendingPathComponent("\(base)-erro-\(stamp).\(url.pathExtension)")
        var moved = false
        for (from, to) in zip(files(url), files(dest)) where FileManager.default.fileExists(atPath: from.path) {
            moved = (try? FileManager.default.moveItem(at: from, to: to)) != nil || moved
        }
        return moved ? dest : nil
    }
}
