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
    var monsters: [MonsterDTO]? = nil
    var body: [BodyDTO]? = nil
    var notes: [NoteDTO]? = nil

    struct BodyDTO: Codable {
        var uuid: UUID, date: Date, weight: Double?, waist: Double?, chest: Double?, arm: Double?, thigh: Double?, hip: Double?
        var healthUUID: String?
    }

    struct NoteDTO: Codable {
        var exerciseID: String, text: String
    }
    var checkIns: [CheckInDTO]? = nil
    var routes: [RouteDTO]? = nil
    var visits: [VisitDTO]? = nil

    struct VisitDTO: Codable {
        var uuid: UUID, gymName: String, start: Date, end: Date?
    }
    var wods: [WodDTO]? = nil

    struct RouteDTO: Codable {
        var uuid: UUID, activityUUID: UUID?, kind: String, start: Date, seconds: Int, meters: Double, points: Data
    }

    struct WodDTO: Codable {
        var uuid: UUID, wodID: String, wodName: String, formatName: String, date: Date
        var seconds: Int?, rounds: Int?, reps: Int?, rx: Bool, note: String, activityUUID: UUID?
    }

    struct LeagueDTO: Codable {
        var uuid: UUID, name: String, emoji: String, scoring: String, start: Date, code: String, isMock: Bool, joinedAt: Date
        var monsterUUID: UUID?
    }

    /// Fotos ficam de fora para o arquivo não ficar enorme
    struct CheckInDTO: Codable {
        var uuid: UUID, leagueUUID: UUID, activityUUID: UUID, title: String, note: String, date: Date
    }

    struct ActivityDTO: Codable {
        var uuid: UUID, kind: String, date: Date, minutes: Int, effort: Int, note: String
        var healthUUID: String?, source: String?, monsterUUID: UUID?
    }

    struct MonsterDTO: Codable {
        var uuid: UUID, name: String, createdAt: Date, isStarter: Bool, lastFormID: String
        var speciesID: String?
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

    static let settingKeys = ["trainerName", "monsterNick", "lastFormID", "discovered", "bodyGender", "mainMonster", "profileUsername", "profileBio"]

    @MainActor
    static func make(context: ModelContext) throws -> Backup {
        let d = UserDefaults.standard
        return Backup(
            settings: Dictionary(uniqueKeysWithValues: settingKeys.compactMap { k in d.string(forKey: k).map { (k, $0) } }),
            activities: try context.fetch(FetchDescriptor<Activity>()).map {
                ActivityDTO(uuid: $0.uuid, kind: $0.kindRaw, date: $0.date, minutes: $0.minutes, effort: $0.effort,
                            note: $0.note, healthUUID: $0.healthUUID, source: $0.source, monsterUUID: $0.monsterUUID)
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
                          isMock: $0.isMock, joinedAt: $0.joinedAt, monsterUUID: $0.monsterUUID)
            },
            monsters: try context.fetch(FetchDescriptor<Monster>()).map {
                MonsterDTO(uuid: $0.uuid, name: $0.name, createdAt: $0.createdAt, isStarter: $0.isStarter, lastFormID: $0.lastFormID, speciesID: $0.speciesID)
            },
            body: try context.fetch(FetchDescriptor<BodyEntry>()).map {
                BodyDTO(uuid: $0.uuid, date: $0.date, weight: $0.weight, waist: $0.waist, chest: $0.chest, arm: $0.arm,
                        thigh: $0.thigh, hip: $0.hip, healthUUID: $0.healthUUID)
            },
            notes: try context.fetch(FetchDescriptor<ExerciseNote>()).map { NoteDTO(exerciseID: $0.exerciseID, text: $0.text) },
            checkIns: try context.fetch(FetchDescriptor<LeagueCheckIn>()).map {
                CheckInDTO(uuid: $0.uuid, leagueUUID: $0.leagueUUID, activityUUID: $0.activityUUID, title: $0.title, note: $0.note, date: $0.date)
            },
            routes: try context.fetch(FetchDescriptor<RouteRecord>()).map {
                RouteDTO(uuid: $0.uuid, activityUUID: $0.activityUUID, kind: $0.kindRaw, start: $0.start, seconds: $0.seconds,
                         meters: $0.meters, points: $0.points)
            },
            visits: try context.fetch(FetchDescriptor<GymVisit>()).map { VisitDTO(uuid: $0.uuid, gymName: $0.gymName, start: $0.start, end: $0.end) },
            wods: try context.fetch(FetchDescriptor<WodResult>()).map {
                WodDTO(uuid: $0.uuid, wodID: $0.wodID, wodName: $0.wodName, formatName: $0.formatName, date: $0.date,
                       seconds: $0.seconds, rounds: $0.rounds, reps: $0.reps, rx: $0.rx, note: $0.note, activityUUID: $0.activityUUID)
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
        try context.delete(model: Monster.self)
        try context.delete(model: BodyEntry.self)
        try context.delete(model: ExerciseNote.self)
        try context.delete(model: WodResult.self)
        try context.delete(model: RouteRecord.self)
        try context.delete(model: GymVisit.self)

        for a in activities {
            let act = Activity(kind: ActivityKind(rawValue: a.kind) ?? .outro, date: a.date, minutes: a.minutes, effort: a.effort, note: a.note)
            act.uuid = a.uuid
            act.healthUUID = a.healthUUID
            act.source = a.source
            act.monsterUUID = a.monsterUUID
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
            league.monsterUUID = l.monsterUUID
            context.insert(league)
        }
        for b in body ?? [] {
            let e = BodyEntry(date: b.date, weight: b.weight)
            e.uuid = b.uuid
            e.waist = b.waist; e.chest = b.chest; e.arm = b.arm; e.thigh = b.thigh; e.hip = b.hip
            e.healthUUID = b.healthUUID
            context.insert(e)
        }
        for n in notes ?? [] { context.insert(ExerciseNote(exerciseID: n.exerciseID, text: n.text)) }
        for m in monsters ?? [] {
            let mon = Monster(name: m.name, isStarter: m.isStarter)
            mon.uuid = m.uuid
            mon.createdAt = m.createdAt
            mon.lastFormID = m.lastFormID
            mon.speciesID = m.speciesID
            context.insert(mon)
        }
        for r in routes ?? [] {
            let route = RouteRecord(kind: ActivityKind(rawValue: r.kind) ?? .corrida, start: r.start)
            route.uuid = r.uuid; route.activityUUID = r.activityUUID; route.seconds = r.seconds; route.meters = r.meters; route.points = r.points
            context.insert(route)
        }
        for v in visits ?? [] {
            let visit = GymVisit(gymName: v.gymName)
            visit.uuid = v.uuid; visit.start = v.start; visit.end = v.end
            context.insert(visit)
        }
        for w in wods ?? [] {
            let r = WodResult(wodID: w.wodID, wodName: w.wodName, formatName: w.formatName)
            r.uuid = w.uuid; r.date = w.date; r.seconds = w.seconds; r.rounds = w.rounds; r.reps = w.reps
            r.rx = w.rx; r.note = w.note; r.activityUUID = w.activityUUID
            context.insert(r)
        }
        for c in checkIns ?? [] {
            let ci = LeagueCheckIn(leagueUUID: c.leagueUUID, activityUUID: c.activityUUID, title: c.title, note: c.note, date: c.date, photo: nil)
            ci.uuid = c.uuid
            context.insert(ci)
        }
        try context.save()

        let d = UserDefaults.standard
        for k in Backup.settingKeys { d.set(settings[k], forKey: k) }
        // Backups antigos não têm a coleção de monstros
        Roster.ensureStarter(context: context)
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
