import Foundation
import SwiftData

/// Schema da primeira versão publicada: igual ao store que já está nos aparelhos
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [Activity.self, Routine.self, RoutineItem.self, WorkoutSession.self, LoggedSet.self,
         CustomExercise.self, SchemaV1.League.self, SchemaV1.LeagueCheckIn.self, Monster.self, BodyEntry.self, ExerciseNote.self,
         WodResult.self, RouteRecord.self, GymVisit.self, Gym.self, CheckInComment.self, PersonalRecord.self,
         SchemaV1.LeagueMessage.self]
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

    /// LeagueMessage como ficou da V1 à V4 (congelado: não mexer)
    @Model
    final class LeagueMessage {
        var uuid: UUID = UUID()
        var leagueUUID: UUID = UUID()
        var text: String = ""
        var date: Date = Date.now
        var syncedAt: Date?

        init() {}
    }

    /// LeagueCheckIn como ficou da V1 à V3 (congelado: não mexer)
    @Model
    final class LeagueCheckIn {
        var uuid: UUID = UUID()
        var leagueUUID: UUID = UUID()
        var activityUUID: UUID = UUID()
        var title: String = ""
        var note: String = ""
        var date: Date = Date.now
        @Attribute(.externalStorage) var photo: Data?
        var place: String?
        var hadPhoto: Bool = false
        var syncedAt: Date?

        init() {}
    }
}

/// V2: `League.swissRaw` (critério da rodada suíça)
enum SchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [Activity.self, Routine.self, RoutineItem.self, WorkoutSession.self, LoggedSet.self,
         CustomExercise.self, SchemaV2.League.self, SchemaV1.LeagueCheckIn.self, Monster.self, BodyEntry.self, ExerciseNote.self,
         WodResult.self, RouteRecord.self, GymVisit.self, Gym.self, CheckInComment.self, PersonalRecord.self,
         SchemaV1.LeagueMessage.self]
    }

    /// League como foi publicada na V2 (congelada: não mexer)
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
        var swissRaw: String = SwissCriterion.pontos.rawValue
        var teamsRaw: String = ""
        var syncedAt: Date?
        var joined: Bool = false
        var myTeamID: String?

        init() {}
    }
}

/// V3: `League.activityRuleRaw` (tipos de treino que pontuam)
enum SchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [Activity.self, Routine.self, RoutineItem.self, WorkoutSession.self, LoggedSet.self,
         CustomExercise.self, SchemaV3.League.self, SchemaV1.LeagueCheckIn.self, Monster.self, BodyEntry.self, ExerciseNote.self,
         WodResult.self, RouteRecord.self, GymVisit.self, Gym.self, CheckInComment.self, PersonalRecord.self,
         SchemaV1.LeagueMessage.self]
    }

    /// League como ficou na V3 (congelada: não mexer)
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
        var activityRuleRaw: String = ""
        var swissRaw: String = SwissCriterion.pontos.rawValue
        var teamsRaw: String = ""
        var syncedAt: Date?
        var joined: Bool = false
        var myTeamID: String?

        init() {}
    }
}

/// V4: `League.settingsRaw` (verificação, revisão, pose, limites, metas, moderação), `LeagueCheckIn.proofRaw`
/// e `reviewRaw`, e as decisões de revisão do dono (`CheckInReview`)
enum SchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [Activity.self, Routine.self, RoutineItem.self, WorkoutSession.self, LoggedSet.self,
         CustomExercise.self, League.self, SchemaV4.LeagueCheckIn.self, Monster.self, BodyEntry.self, ExerciseNote.self,
         WodResult.self, RouteRecord.self, GymVisit.self, Gym.self, CheckInComment.self, PersonalRecord.self,
         SchemaV1.LeagueMessage.self, CheckInReview.self]
    }

    /// LeagueCheckIn como ficou na V4 (congelado: não mexer)
    @Model
    final class LeagueCheckIn {
        var uuid: UUID = UUID()
        var leagueUUID: UUID = UUID()
        var activityUUID: UUID = UUID()
        var title: String = ""
        var note: String = ""
        var date: Date = Date.now
        @Attribute(.externalStorage) var photo: Data?
        var place: String?
        var hadPhoto: Bool = false
        var syncedAt: Date?
        var proofRaw: String = ""
        var reviewRaw: String = ""

        init() {}
    }
}

/// V5: `LeagueCheckIn.extraPhotos` (até 4 fotos a mais por check-in) e `LeagueMessage.photo` (foto no mural)
enum SchemaV5: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [Activity.self, Routine.self, RoutineItem.self, WorkoutSession.self, LoggedSet.self,
         CustomExercise.self, League.self, LeagueCheckIn.self, Monster.self, BodyEntry.self, ExerciseNote.self,
         WodResult.self, RouteRecord.self, GymVisit.self, Gym.self, CheckInComment.self, PersonalRecord.self,
         LeagueMessage.self, CheckInReview.self]
    }
}

/// V6: `MFitImportRecord` (entidade nova — treinos prescritos importados do MFIT; adição pura, como a V4 fez com `CheckInReview`)
enum SchemaV6: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(6, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [Activity.self, Routine.self, RoutineItem.self, WorkoutSession.self, LoggedSet.self,
         CustomExercise.self, League.self, LeagueCheckIn.self, Monster.self, BodyEntry.self, ExerciseNote.self,
         WodResult.self, RouteRecord.self, GymVisit.self, Gym.self, CheckInComment.self, PersonalRecord.self,
         LeagueMessage.self, CheckInReview.self, MFitImportRecord.self]
    }
}

/// V7: `ExerciseMedia` (entidade nova — vídeo de demonstração por exercício, vindo da importação; adição pura)
enum SchemaV7: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(7, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [Activity.self, Routine.self, RoutineItem.self, WorkoutSession.self, LoggedSet.self,
         CustomExercise.self, League.self, LeagueCheckIn.self, Monster.self, BodyEntry.self, ExerciseNote.self,
         WodResult.self, RouteRecord.self, GymVisit.self, Gym.self, CheckInComment.self, PersonalRecord.self,
         LeagueMessage.self, CheckInReview.self, MFitImportRecord.self, ExerciseMedia.self]
    }
}

enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self, SchemaV5.self, SchemaV6.self, SchemaV7.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self),
         .lightweight(fromVersion: SchemaV2.self, toVersion: SchemaV3.self),
         .lightweight(fromVersion: SchemaV3.self, toVersion: SchemaV4.self),
         .lightweight(fromVersion: SchemaV4.self, toVersion: SchemaV5.self),
         .lightweight(fromVersion: SchemaV5.self, toVersion: SchemaV6.self),
         .lightweight(fromVersion: SchemaV6.self, toVersion: SchemaV7.self)]
    }
}

/// Container único do app, compartilhado com os botões do Live Activity (que rodam no processo do app)
@MainActor
enum AppData {
    static let schema = Schema(versionedSchema: SchemaV7.self)

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
