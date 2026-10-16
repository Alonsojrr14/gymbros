import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Cópia completa dos dados em JSON: atividades, rotinas, treinos, exercícios próprios e ajustes
struct Backup: Codable {
    var version = 1
    var exportedAt = Date.now
    var settings: [String: String]
    var activities: [ActivityDTO]
    var routines: [RoutineDTO]
    var sessions: [SessionDTO]
    var customExercises: [CustomDTO]
    var leagues: [LeagueDTO]? = nil
    var checkIns: [CheckInDTO]? = nil

    struct LeagueDTO: Codable {
        var uuid: UUID, name: String, emoji: String, scoring: String, start: Date, code: String, isMock: Bool, joinedAt: Date
    }

    /// Fotos ficam de fora para o arquivo não ficar enorme
    struct CheckInDTO: Codable {
        var uuid: UUID, leagueUUID: UUID, activityUUID: UUID, title: String, note: String, date: Date
    }

    struct ActivityDTO: Codable {
        var uuid: UUID, kind: String, date: Date, minutes: Int, effort: Int, note: String
        var healthUUID: String?, source: String?
    }

    struct RoutineDTO: Codable {
        var uuid: UUID, name: String, weekdays: String, order: Int
        var items: [ItemDTO]
    }

    struct ItemDTO: Codable {
        var exerciseID: String, sets: Int, reps: Int, rest: Int, order: Int
    }

    struct SessionDTO: Codable {
        var uuid: UUID, title: String, routineUUID: UUID?, start: Date, end: Date?, effort: Int, activityUUID: UUID?
        var sets: [SetDTO]
    }

    struct SetDTO: Codable {
        var exerciseID: String, exerciseOrder: Int, index: Int, weight: Double, reps: Int, targetReps: Int, rest: Int, done: Bool
    }

    struct CustomDTO: Codable {
        var uuid: UUID, name: String, group: String, equipment: String, type: String, notes: String
    }

    static let settingKeys = ["trainerName", "monsterNick", "lastFormID", "discovered", "bodyGender"]

    @MainActor
    static func make(context: ModelContext) throws -> Backup {
        let d = UserDefaults.standard
        return Backup(
            settings: Dictionary(uniqueKeysWithValues: settingKeys.compactMap { k in d.string(forKey: k).map { (k, $0) } }),
            activities: try context.fetch(FetchDescriptor<Activity>()).map {
                ActivityDTO(uuid: $0.uuid, kind: $0.kindRaw, date: $0.date, minutes: $0.minutes, effort: $0.effort,
                            note: $0.note, healthUUID: $0.healthUUID, source: $0.source)
            },
            routines: try context.fetch(FetchDescriptor<Routine>()).map { r in
                RoutineDTO(uuid: r.uuid, name: r.name, weekdays: r.weekdaysRaw, order: r.order, items: r.sortedItems.map {
                    ItemDTO(exerciseID: $0.exerciseID, sets: $0.sets, reps: $0.reps, rest: $0.rest, order: $0.order)
                })
            },
            sessions: try context.fetch(FetchDescriptor<WorkoutSession>()).map { s in
                SessionDTO(uuid: s.uuid, title: s.title, routineUUID: s.routineUUID, start: s.start, end: s.end,
                           effort: s.effort, activityUUID: s.activityUUID, sets: s.orderedSets.map {
                    SetDTO(exerciseID: $0.exerciseID, exerciseOrder: $0.exerciseOrder, index: $0.index, weight: $0.weight,
                           reps: $0.reps, targetReps: $0.targetReps, rest: $0.rest, done: $0.done)
                })
            },
            customExercises: try context.fetch(FetchDescriptor<CustomExercise>()).map {
                CustomDTO(uuid: $0.uuid, name: $0.name, group: $0.groupRaw, equipment: $0.equipment, type: $0.typeRaw, notes: $0.notes)
            },
            leagues: try context.fetch(FetchDescriptor<League>()).map {
                LeagueDTO(uuid: $0.uuid, name: $0.name, emoji: $0.emoji, scoring: $0.scoringRaw, start: $0.start, code: $0.code,
                          isMock: $0.isMock, joinedAt: $0.joinedAt)
            },
            checkIns: try context.fetch(FetchDescriptor<LeagueCheckIn>()).map {
                CheckInDTO(uuid: $0.uuid, leagueUUID: $0.leagueUUID, activityUUID: $0.activityUUID, title: $0.title, note: $0.note, date: $0.date)
            }
        )
    }

    /// Substitui todos os dados atuais pelos do backup
    @MainActor
    func restore(into context: ModelContext) throws {
        try context.delete(model: LoggedSet.self)
        try context.delete(model: WorkoutSession.self)
        try context.delete(model: RoutineItem.self)
        try context.delete(model: Routine.self)
        try context.delete(model: Activity.self)
        try context.delete(model: CustomExercise.self)
        try context.delete(model: LeagueCheckIn.self)
        try context.delete(model: League.self)

        for a in activities {
            let act = Activity(kind: ActivityKind(rawValue: a.kind) ?? .outro, date: a.date, minutes: a.minutes, effort: a.effort, note: a.note)
            act.uuid = a.uuid
            act.healthUUID = a.healthUUID
            act.source = a.source
            context.insert(act)
        }
        for r in routines {
            let routine = Routine(name: r.name, order: r.order)
            routine.uuid = r.uuid
            routine.weekdaysRaw = r.weekdays
            context.insert(routine)
            for i in r.items {
                routine.items.append(RoutineItem(exerciseID: i.exerciseID, sets: i.sets, reps: i.reps, rest: i.rest, order: i.order))
            }
        }
        for s in sessions {
            let session = WorkoutSession(title: s.title, routineUUID: s.routineUUID)
            session.uuid = s.uuid
            session.start = s.start
            session.end = s.end
            session.effort = s.effort
            session.activityUUID = s.activityUUID
            context.insert(session)
            for x in s.sets {
                let set = LoggedSet(exerciseID: x.exerciseID, exerciseOrder: x.exerciseOrder, index: x.index,
                                    weight: x.weight, reps: x.reps, rest: x.rest)
                set.targetReps = x.targetReps
                set.done = x.done
                session.sets.append(set)
            }
        }
        for c in customExercises {
            let e = CustomExercise(name: c.name, group: MuscleGroup(rawValue: c.group) ?? .corpo, equipment: c.equipment,
                                   type: ExerciseType(rawValue: c.type) ?? .weighted, notes: c.notes)
            e.uuid = c.uuid
            context.insert(e)
        }
        for l in leagues ?? [] {
            let league = League(name: l.name, emoji: l.emoji, scoring: LeagueScoring(rawValue: l.scoring) ?? .pontos, start: l.start, isMock: l.isMock)
            league.uuid = l.uuid
            league.code = l.code
            league.joinedAt = l.joinedAt
            context.insert(league)
        }
        for c in checkIns ?? [] {
            let ci = LeagueCheckIn(leagueUUID: c.leagueUUID, activityUUID: c.activityUUID, title: c.title, note: c.note, date: c.date, photo: nil)
            ci.uuid = c.uuid
            context.insert(ci)
        }
        try context.save()

        let d = UserDefaults.standard
        for k in Backup.settingKeys { d.set(settings[k], forKey: k) }
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
