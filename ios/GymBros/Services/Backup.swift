import CoreLocation
import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Cópia completa dos dados em JSON: atividades, rotinas, treinos, exercícios próprios e ajustes
struct Backup: Codable, Sendable {
    var version = 1
    var exportedAt = Date.now
    var settings: [String: String]
    /// Mesmos ajustes com o tipo (Bool, número ou texto); backups antigos só têm `settings`
    var typedSettings: [String: Setting]? = nil
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
        /// Só na cópia da conta
        var photoFront: Data? = nil, photoSide: Data? = nil
    }

    struct NoteDTO: Codable {
        var exerciseID: String, text: String
        var updated: Date? = nil
    }
    var checkIns: [CheckInDTO]? = nil
    var routes: [RouteDTO]? = nil
    var visits: [VisitDTO]? = nil
    var gyms: [GymDTO]? = nil

    struct VisitDTO: Codable {
        var uuid: UUID, gymName: String, start: Date, end: Date?
        var gymUUID: UUID?
    }

    struct GymDTO: Codable {
        var uuid: UUID, name: String, latitude: Double, longitude: Double, radius: Double, createdAt: Date
    }
    var wods: [WodDTO]? = nil
    var prs: [PRDTO]? = nil
    var comments: [CommentDTO]? = nil
    var messages: [MessageDTO]? = nil
    /// Suas decisões como dono de liga com revisão
    var reviews: [ReviewDTO]? = nil

    struct ReviewDTO: Codable {
        var uuid: UUID, leagueUUID: UUID, itemID: String, approved: Bool, date: Date
    }
    /// Foto do perfil (já é pequena: 512 px)
    var profilePhoto: Data? = nil
    /// Ligas e check-ins trazem o estado no servidor (`syncedAt`, `joined`); backups antigos não
    var hasSyncState: Bool? = nil
    /// Só na cópia da conta: todas as chaves de usuário (`AccountData.userKeys`) em property list, com qualquer tipo
    var accountSettings: Data? = nil

    struct CommentDTO: Codable {
        var uuid: UUID, itemID: String, text: String, date: Date
        var authorID: String? = nil, authorName: String? = nil
    }

    struct PRDTO: Codable {
        var uuid: UUID, exerciseID: String, weight: Double, reps: Int, date: Date
    }

    struct RouteDTO: Codable {
        var uuid: UUID, activityUUID: UUID?, kind: String, start: Date, seconds: Int, meters: Double, points: Data
    }

    struct WodDTO: Codable {
        var uuid: UUID, wodID: String, wodName: String, formatName: String, date: Date
        var seconds: Int?, rounds: Int?, reps: Int?, rx: Bool, note: String, activityUUID: UUID?
        var capped: Bool? = nil
    }

    struct LeagueDTO: Codable {
        var uuid: UUID, name: String, emoji: String, scoring: String, start: Date, code: String, isMock: Bool, joinedAt: Date
        var monsterUUID: UUID?
        var end: Date? = nil
        var autoRenew: Bool? = nil, season: Int? = nil, seriesID: UUID? = nil, nextUUID: UUID? = nil
        var weights: String? = nil, tieBreak: String? = nil
        var photoRule: String? = nil, teams: String? = nil, myTeamID: String? = nil
        var activityRule: String? = nil
        var settings: String? = nil
        /// Capa reduzida, só na temporada atual de cada liga (as passadas usam a mesma ao restaurar)
        var cover: Data? = nil
        var syncedAt: Date? = nil, joined: Bool? = nil
        var swiss: String? = nil
    }

    struct MessageDTO: Codable {
        var uuid: UUID, leagueUUID: UUID, text: String, date: Date, syncedAt: Date?
        /// Só na cópia da conta
        var photo: Data? = nil
    }

    /// Fotos ficam de fora para o arquivo não ficar enorme; `hadPhoto` guarda que tinha, para a pontuação das ligas não mudar
    struct CheckInDTO: Codable {
        var uuid: UUID, leagueUUID: UUID, activityUUID: UUID, title: String, note: String, date: Date
        var hadPhoto: Bool? = nil, place: String? = nil
        var syncedAt: Date? = nil
        var proof: String? = nil, review: String? = nil
        /// Fotos a mais do post; só na cópia da conta
        var extraPhotos: Data? = nil
        /// Só na cópia da conta
        var photo: Data? = nil
    }

    struct ActivityDTO: Codable {
        var uuid: UUID, kind: String, date: Date, minutes: Int, effort: Int, note: String
        var healthUUID: String?, source: String?, monsterUUID: UUID?
        var gymUUID: UUID?
        var meters: Double? = nil, kcal: Double? = nil
        var healthType: Int? = nil, healthWritten: String? = nil
        /// Divisão do XP entre os atributos (ActivitySplits)
        var attributes: String? = nil
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
        var supersetNext: Bool? = nil
    }

    struct SessionDTO: Codable {
        var uuid: UUID, title: String, routineUUID: UUID?, start: Date, end: Date?, effort: Int, activityUUID: UUID?
        var sets: [SetDTO]
        var superset: String? = nil
        var deload: Bool? = nil
        var gymUUID: UUID? = nil, currentExerciseID: String? = nil, restEnd: Date? = nil, restTotal: Int? = nil, placeAsked: Bool? = nil
    }

    struct SetDTO: Codable {
        var exerciseID: String, exerciseOrder: Int, index: Int, weight: Double, reps: Int, targetReps: Int, rest: Int, done: Bool
        var warmup: Bool? = nil
    }

    struct CustomDTO: Codable {
        var uuid: UUID, name: String, group: String, equipment: String, type: String, notes: String
    }

    static let settingKeys = ["trainerName", "monsterNick", "lastFormID", "discovered", "bodyGender", "mainMonster", "profileUsername", "profileBio", "exerciseGoals", "autoWarmup", "restNotification", "barWeight", WodPlan.key, "personalGoals"] + BodyProfile.keys

    enum Setting: Codable {
        case bool(Bool), number(Double), text(String)

        init?(_ value: Any?) {
            switch value {
            // NSNumber de Bool vem como CFBoolean
            case let n as NSNumber where CFGetTypeID(n) == CFBooleanGetTypeID(): self = .bool(n.boolValue)
            case let n as NSNumber: self = .number(n.doubleValue)
            case let s as String: self = .text(s)
            default: return nil
            }
        }

        var value: Any {
            switch self {
            case .bool(let b): b
            case .number(let n): n
            case .text(let s): s
            }
        }
    }

    /// `account`: cópia da conta (todas as chaves de usuário e as fotos dos check-ins), em vez do arquivo de backup
    @MainActor
    static func make(context: ModelContext, defaults d: UserDefaults = .standard, account: Bool = false) throws -> Backup {
        Backup(
            settings: Dictionary(uniqueKeysWithValues: settingKeys.compactMap { k in d.string(forKey: k).map { (k, $0) } }),
            typedSettings: Dictionary(uniqueKeysWithValues: settingKeys.compactMap { k in Setting(d.object(forKey: k)).map { (k, $0) } }),
            activities: try context.fetch(FetchDescriptor<Activity>()).map {
                ActivityDTO(uuid: $0.uuid, kind: $0.kindRaw, date: $0.date, minutes: $0.minutes, effort: $0.effort,
                            note: $0.note, healthUUID: $0.healthUUID, source: $0.source, monsterUUID: $0.monsterUUID, gymUUID: $0.gymUUID,
                            meters: $0.meters, kcal: $0.kcal, healthType: $0.healthType, healthWritten: $0.healthWrittenUUID,
                            attributes: ActivitySplits.all()[$0.uuid.uuidString])
            },
            routines: try context.fetch(FetchDescriptor<Routine>()).map { r in
                RoutineDTO(uuid: r.uuid, name: r.name, weekdays: r.weekdaysRaw, order: r.order, items: r.sortedItems.map {
                    ItemDTO(exerciseID: $0.exerciseID, sets: $0.sets, reps: $0.reps, rest: $0.rest, order: $0.order, supersetNext: $0.supersetNext)
                })
            },
            sessions: try context.fetch(FetchDescriptor<WorkoutSession>()).map { s in
                SessionDTO(uuid: s.uuid, title: s.title, routineUUID: s.routineUUID, start: s.start, end: s.end,
                           effort: s.effort, activityUUID: s.activityUUID, sets: s.orderedSets.map {
                    SetDTO(exerciseID: $0.exerciseID, exerciseOrder: $0.exerciseOrder, index: $0.index, weight: $0.weight,
                           reps: $0.reps, targetReps: $0.targetReps, rest: $0.rest, done: $0.done, warmup: $0.warmup)
                }, superset: s.supersetRaw, deload: s.isDeload, gymUUID: s.gymUUID, currentExerciseID: s.currentExerciseID,
                   restEnd: s.restEnd, restTotal: s.restTotal, placeAsked: s.placeAsked)
            },
            customExercises: try context.fetch(FetchDescriptor<CustomExercise>()).map {
                CustomDTO(uuid: $0.uuid, name: $0.name, group: $0.groupRaw, equipment: $0.equipment, type: $0.typeRaw, notes: $0.notes)
            },
            leagues: try context.fetch(FetchDescriptor<League>()).map {
                LeagueDTO(uuid: $0.uuid, name: $0.name, emoji: $0.emoji, scoring: $0.scoringRaw, start: $0.start, code: $0.code,
                          isMock: $0.isMock, joinedAt: $0.joinedAt, monsterUUID: $0.monsterUUID, end: $0.end, autoRenew: $0.autoRenew, season: $0.season, seriesID: $0.seriesID, nextUUID: $0.nextUUID,
                          weights: $0.weightsRaw, tieBreak: $0.tieBreakRaw, photoRule: $0.photoRuleRaw, teams: $0.teamsRaw, myTeamID: $0.myTeamID,
                          activityRule: $0.activityRuleRaw, settings: $0.settingsRaw,
                          cover: account ? $0.cover : $0.isPastSeason ? nil : $0.cover.flatMap { smallCover($0) },
                          syncedAt: $0.syncedAt, joined: $0.joined, swiss: $0.swissRaw)
            },
            monsters: try context.fetch(FetchDescriptor<Monster>()).map {
                MonsterDTO(uuid: $0.uuid, name: $0.name, createdAt: $0.createdAt, isStarter: $0.isStarter, lastFormID: $0.lastFormID, speciesID: $0.speciesID)
            },
            body: try context.fetch(FetchDescriptor<BodyEntry>()).map {
                BodyDTO(uuid: $0.uuid, date: $0.date, weight: $0.weight, waist: $0.waist, chest: $0.chest, arm: $0.arm,
                        thigh: $0.thigh, hip: $0.hip, healthUUID: $0.healthUUID,
                        photoFront: account ? $0.photoFront : nil, photoSide: account ? $0.photoSide : nil)
            },
            notes: try context.fetch(FetchDescriptor<ExerciseNote>()).map { NoteDTO(exerciseID: $0.exerciseID, text: $0.text, updated: $0.updated) },
            checkIns: try context.fetch(FetchDescriptor<LeagueCheckIn>()).map {
                CheckInDTO(uuid: $0.uuid, leagueUUID: $0.leagueUUID, activityUUID: $0.activityUUID, title: $0.title, note: $0.note, date: $0.date,
                           hadPhoto: $0.hasPhoto, place: $0.place, syncedAt: $0.syncedAt, proof: $0.proofRaw, review: $0.reviewRaw,
                           extraPhotos: account ? $0.extraPhotosData : nil, photo: account ? $0.photo : nil)
            },
            routes: try context.fetch(FetchDescriptor<RouteRecord>()).map {
                RouteDTO(uuid: $0.uuid, activityUUID: $0.activityUUID, kind: $0.kindRaw, start: $0.start, seconds: $0.seconds,
                         meters: $0.meters, points: $0.points)
            },
            visits: try context.fetch(FetchDescriptor<GymVisit>()).map {
                VisitDTO(uuid: $0.uuid, gymName: $0.gymName, start: $0.start, end: $0.end, gymUUID: $0.gymUUID)
            },
            gyms: try context.fetch(FetchDescriptor<Gym>()).map {
                GymDTO(uuid: $0.uuid, name: $0.name, latitude: $0.latitude, longitude: $0.longitude, radius: $0.radius, createdAt: $0.createdAt)
            },
            wods: try context.fetch(FetchDescriptor<WodResult>()).map {
                WodDTO(uuid: $0.uuid, wodID: $0.wodID, wodName: $0.wodName, formatName: $0.formatName, date: $0.date,
                       seconds: $0.seconds, rounds: $0.rounds, reps: $0.reps, rx: $0.rx, note: $0.note, activityUUID: $0.activityUUID,
                       capped: $0.capped)
            },
            prs: try context.fetch(FetchDescriptor<PersonalRecord>()).map {
                PRDTO(uuid: $0.uuid, exerciseID: $0.exerciseID, weight: $0.weight, reps: $0.reps, date: $0.date)
            },
            comments: try context.fetch(FetchDescriptor<CheckInComment>()).map {
                CommentDTO(uuid: $0.uuid, itemID: $0.itemID, text: $0.text, date: $0.date, authorID: $0.authorID, authorName: $0.authorName)
            },
            messages: try context.fetch(FetchDescriptor<LeagueMessage>()).map {
                MessageDTO(uuid: $0.uuid, leagueUUID: $0.leagueUUID, text: $0.text, date: $0.date, syncedAt: $0.syncedAt,
                           photo: account ? $0.photo : nil)
            },
            reviews: try context.fetch(FetchDescriptor<CheckInReview>()).map {
                ReviewDTO(uuid: $0.uuid, leagueUUID: $0.leagueUUID, itemID: $0.itemID, approved: $0.approved, date: $0.date)
            },
            profilePhoto: d.data(forKey: "profilePhoto"),
            hasSyncState: true,
            accountSettings: account ? AccountData.settings(d) : nil
        )
    }

    /// Capa em tamanho de miniatura, para o backup continuar pequeno
    private static func smallCover(_ data: Data) -> Data? {
        guard let img = UIImage(data: data) else { return nil }
        let scale = min(1, 640 / max(img.size.width, img.size.height))
        let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        return UIGraphicsImageRenderer(size: size).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }.jpegData(compressionQuality: 0.6)
    }

    /// Substitui todos os dados atuais pelos do backup; se algo falhar, nada muda
    @MainActor
    func restore(into context: ModelContext, defaults d: UserDefaults = .standard) throws {
        defer { PRBook.reload() }
        do {
            try replaceAll(in: context)
            try context.save()
            // Só depois do save: se o restore falhar, a divisão dos atributos continua a das atividades atuais
            ActivitySplits.replace(Dictionary(activities.compactMap { a in a.attributes.map { (a.uuid.uuidString, $0) } }, uniquingKeysWith: { a, _ in a }))
        } catch {
            context.rollback()
            throw error
        }

        if let accountSettings {
            AccountData.apply(accountSettings, to: d)
        } else {
            for k in Backup.settingKeys { d.set(typedSettings?[k]?.value ?? settings[k], forKey: k) }
        }
        // Backup sem foto do perfil (antigo) mantém a atual
        if let profilePhoto { d.set(profilePhoto, forKey: "profilePhoto") }
        // Backups antigos não têm a coleção de monstros
        Roster.ensureStarter(context: context)
    }

    /// Mesclagem ao vivo (IOS-08): aplica só o que mudou de `old` (o banco de agora) para esta cópia. Item igual fica
    /// intacto, com o mesmo objeto no banco: tela aberta mostrando ele não perde o que está mostrando. Item mudado sai e
    /// volta com os dados novos; apagado no outro aparelho sai.
    @MainActor
    func applyChanges(from old: Backup, into context: ModelContext, defaults d: UserDefaults = .standard) throws {
        defer { PRBook.reload() }
        let new = try Backup.jsonObject(self), was = try Backup.jsonObject(old)
        var changed: [String: Set<String>] = [:], gone: [String: Set<String>] = [:]
        var keep: [String: Any] = new
        for (key, id) in Backup.listIDs {
            let n = new[key] as? [[String: Any]] ?? [], o = was[key] as? [[String: Any]] ?? []
            let before = Dictionary(o.compactMap { i in (i[id] as? String).map { ($0, i) } }, uniquingKeysWith: { a, _ in a })
            let after = Set(n.compactMap { $0[id] as? String })
            let diff = n.filter { i in
                guard let k = i[id] as? String else { return false }
                return before[k].map { !BackupMerge.same($0, i) } ?? true
            }
            changed[key] = Set(diff.compactMap { $0[id] as? String })
            gone[key] = Set(before.keys).subtracting(after)
            keep[key] = diff
        }
        let sub = try Backup.decoder.decode(Backup.self, from: JSONSerialization.data(withJSONObject: keep))
        do {
            func drop<T: PersistentModel>(_ type: T.Type, _ key: String, _ id: (T) -> String) throws {
                let out = changed[key, default: []].union(gone[key, default: []])
                guard !out.isEmpty else { return }
                for o in try context.fetch(FetchDescriptor<T>()) where out.contains(id(o)) {
                    // Um de cada vez, filhos antes (a exclusão em lote falha com objetos carregados)
                    if let s = o as? WorkoutSession { for x in s.sets { context.delete(x) } }
                    if let r = o as? Routine { for x in r.items { context.delete(x) } }
                    context.delete(o)
                }
            }
            try drop(Activity.self, "activities") { $0.uuid.uuidString }
            try drop(Routine.self, "routines") { $0.uuid.uuidString }
            try drop(WorkoutSession.self, "sessions") { $0.uuid.uuidString }
            try drop(CustomExercise.self, "customExercises") { $0.uuid.uuidString }
            try drop(LeagueCheckIn.self, "checkIns") { $0.uuid.uuidString }
            try drop(LeagueMessage.self, "messages") { $0.uuid.uuidString }
            try drop(League.self, "leagues") { $0.uuid.uuidString }
            try drop(Monster.self, "monsters") { $0.uuid.uuidString }
            try drop(BodyEntry.self, "body") { $0.uuid.uuidString }
            try drop(ExerciseNote.self, "notes") { $0.exerciseID }
            try drop(WodResult.self, "wods") { $0.uuid.uuidString }
            try drop(RouteRecord.self, "routes") { $0.uuid.uuidString }
            try drop(GymVisit.self, "visits") { $0.uuid.uuidString }
            try drop(Gym.self, "gyms") { $0.uuid.uuidString }
            try drop(PersonalRecord.self, "prs") { $0.uuid.uuidString }
            try drop(CheckInComment.self, "comments") { $0.uuid.uuidString }
            try drop(CheckInReview.self, "reviews") { $0.uuid.uuidString }
            try sub.insertAll(into: context)
            try context.save()
            var splits = ActivitySplits.all()
            for id in gone["activities", default: []] { splits[id] = nil }
            for a in sub.activities { splits[a.uuid.uuidString] = a.attributes }
            ActivitySplits.replace(splits)
        } catch {
            context.rollback()
            throw error
        }
        if let accountSettings {
            AccountData.apply(accountSettings, to: d)
        } else {
            for k in Backup.settingKeys { d.set(typedSettings?[k]?.value ?? settings[k], forKey: k) }
        }
        if let profilePhoto { d.set(profilePhoto, forKey: "profilePhoto") }
        Roster.ensureStarter(context: context)
    }

    /// Listas da cópia que viram modelos no banco e a chave de cada item
    static let listIDs: [String: String] = [
        "activities": "uuid", "routines": "uuid", "sessions": "uuid", "customExercises": "uuid", "checkIns": "uuid",
        "messages": "uuid", "leagues": "uuid", "monsters": "uuid", "body": "uuid", "notes": "exerciseID", "wods": "uuid",
        "routes": "uuid", "visits": "uuid", "gyms": "uuid", "prs": "uuid", "comments": "uuid", "reviews": "uuid",
    ]

    static func jsonObject(_ b: Backup) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: encoder.encode(b)) as? [String: Any] ?? [:]
    }

    /// Todos os modelos do banco, na ordem em que podem sair. Um objeto de cada vez, não em lote: a exclusão em lote age
    /// direto no arquivo e falha com objetos carregados na memória (sessão e séries) quando o banco não está vazio, como ao
    /// aplicar a mesclagem da conta ("mandatory OTO nullify inverse on LoggedSet/session"). Assim o restore segue atômico.
    @MainActor
    static func deleteAll(in context: ModelContext) throws {
        func clear<T: PersistentModel>(_ type: T.Type) throws { for o in try context.fetch(FetchDescriptor<T>()) { context.delete(o) } }
        try clear(LoggedSet.self)
        try clear(WorkoutSession.self)
        try clear(RoutineItem.self)
        try clear(Routine.self)
        try clear(Activity.self)
        try clear(CustomExercise.self)
        try clear(LeagueCheckIn.self)
        try clear(LeagueMessage.self)
        try clear(League.self)
        try clear(Monster.self)
        try clear(BodyEntry.self)
        try clear(ExerciseNote.self)
        try clear(WodResult.self)
        try clear(RouteRecord.self)
        try clear(GymVisit.self)
        try clear(Gym.self)
        try clear(PersonalRecord.self)
        try clear(CheckInComment.self)
        try clear(CheckInReview.self)
    }

    @MainActor
    private func replaceAll(in context: ModelContext) throws {
        try Backup.deleteAll(in: context)
        try insertAll(into: context)
    }

    /// Cria no banco todos os itens desta cópia (o banco não pode ter os mesmos ids)
    @MainActor
    private func insertAll(into context: ModelContext) throws {
        for a in activities {
            let act = Activity(kind: ActivityKind(rawValue: a.kind) ?? .outro, date: a.date, minutes: a.minutes, effort: a.effort, note: a.note)
            act.uuid = a.uuid
            act.healthUUID = a.healthUUID
            act.source = a.source
            act.monsterUUID = a.monsterUUID
            act.gymUUID = a.gymUUID
            act.meters = a.meters
            act.kcal = a.kcal
            act.healthType = a.healthType
            act.healthWrittenUUID = a.healthWritten
            context.insert(act)
        }
        for r in routines {
            let routine = Routine(name: r.name, order: r.order)
            routine.uuid = r.uuid
            routine.weekdaysRaw = r.weekdays
            context.insert(routine)
            for i in r.items {
                let item = RoutineItem(exerciseID: i.exerciseID, sets: i.sets, reps: i.reps, rest: i.rest, order: i.order)
                item.supersetNext = i.supersetNext ?? false
                routine.items.append(item)
            }
        }
        for s in sessions {
            let session = WorkoutSession(title: s.title, routineUUID: s.routineUUID)
            session.uuid = s.uuid
            session.start = s.start
            session.end = s.end
            session.effort = s.effort
            session.supersetRaw = s.superset ?? ""
            session.isDeload = s.deload ?? false
            session.activityUUID = s.activityUUID
            session.gymUUID = s.gymUUID
            session.currentExerciseID = s.currentExerciseID
            session.restEnd = s.restEnd
            if let restTotal = s.restTotal { session.restTotal = restTotal }
            session.placeAsked = s.placeAsked ?? false
            context.insert(session)
            for x in s.sets {
                let set = LoggedSet(exerciseID: x.exerciseID, exerciseOrder: x.exerciseOrder, index: x.index,
                                    weight: x.weight, reps: x.reps, rest: x.rest)
                set.targetReps = x.targetReps
                set.done = x.done
                set.warmup = x.warmup ?? false
                session.sets.append(set)
            }
        }
        for c in customExercises {
            let e = CustomExercise(name: c.name, group: MuscleGroup(rawValue: c.group) ?? .corpo, equipment: c.equipment,
                                   type: ExerciseType(rawValue: c.type) ?? .weighted, notes: c.notes)
            e.uuid = c.uuid
            context.insert(e)
        }
        var restoredLeagues: [League] = []
        for l in leagues ?? [] {
            let league = League(name: l.name, emoji: l.emoji, scoring: LeagueScoring(rawValue: l.scoring) ?? .pontos, start: l.start, isMock: l.isMock)
            league.uuid = l.uuid
            league.code = l.code
            league.joinedAt = l.joinedAt
            league.monsterUUID = l.monsterUUID
            league.end = l.end
            league.autoRenew = l.autoRenew ?? false
            league.season = l.season ?? 1
            league.seriesID = l.seriesID
            league.nextUUID = l.nextUUID
            league.weightsRaw = l.weights ?? ""
            league.tieBreakRaw = l.tieBreak ?? LeagueTieBreak.primeiro.rawValue
            league.photoRuleRaw = l.photoRule ?? PhotoRule.livre.rawValue
            league.activityRuleRaw = l.activityRule ?? ""
            league.settingsRaw = l.settings ?? ""
            league.swissRaw = l.swiss ?? SwissCriterion.pontos.rawValue
            league.teamsRaw = l.teams ?? ""
            league.myTeamID = l.myTeamID
            league.cover = l.cover
            // Backups antigos não sabem o estado no servidor: conta como já enviado e de outra pessoa,
            // para o flush não recriar nem sobrescrever a liga de ninguém
            league.syncedAt = hasSyncState == true ? l.syncedAt : exportedAt
            league.joined = l.joined ?? true
            context.insert(league)
            restoredLeagues.append(league)
        }
        // Temporadas passadas ficam com a capa da temporada atual da mesma liga
        let covers = Dictionary(restoredLeagues.compactMap { l in l.cover.map { (l.seriesKey, $0) } }, uniquingKeysWith: { a, _ in a })
        for l in restoredLeagues where l.cover == nil { l.cover = covers[l.seriesKey] }
        for b in body ?? [] {
            let e = BodyEntry(date: b.date, weight: b.weight)
            e.uuid = b.uuid
            e.waist = b.waist; e.chest = b.chest; e.arm = b.arm; e.thigh = b.thigh; e.hip = b.hip
            e.healthUUID = b.healthUUID
            e.photoFront = b.photoFront
            e.photoSide = b.photoSide
            context.insert(e)
        }
        for n in notes ?? [] {
            let note = ExerciseNote(exerciseID: n.exerciseID, text: n.text)
            if let updated = n.updated { note.updated = updated }
            context.insert(note)
        }
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
        // Lugares que já estão no banco (mesclagem ao vivo aplica só o que mudou) e os desta cópia
        var restoredGyms: [UUID: Gym] = Dictionary(((try? context.fetch(FetchDescriptor<Gym>())) ?? []).map { ($0.uuid, $0) },
                                                   uniquingKeysWith: { a, _ in a })
        for g in gyms ?? [] {
            let gym = Gym(name: g.name, coordinate: CLLocationCoordinate2D(latitude: g.latitude, longitude: g.longitude), radius: g.radius)
            gym.uuid = g.uuid
            gym.createdAt = g.createdAt
            context.insert(gym)
            restoredGyms[g.uuid] = gym
        }
        for v in visits ?? [] {
            // Visitas de backups antigos (sem lugar) ficam no lugar com o mesmo nome. Sem lugar correspondente, a visita
            // fica sem lugar (conta nas idas do mês, com o nome guardado) em vez de apontar para um lugar que não existe.
            let gym = v.gymUUID.flatMap { restoredGyms[$0] } ?? restoredGyms.values.first { $0.name == v.gymName }
            let visit = GymVisit(gym: gym ?? Gym(name: v.gymName, coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0)))
            if gym == nil { visit.gymUUID = nil }
            visit.uuid = v.uuid; visit.start = v.start; visit.end = v.end
            context.insert(visit)
        }
        for c in comments ?? [] {
            let x = CheckInComment(itemID: c.itemID, text: c.text, authorID: c.authorID ?? "me", authorName: c.authorName ?? "")
            x.uuid = c.uuid
            x.date = c.date
            context.insert(x)
        }
        for r in reviews ?? [] {
            let x = CheckInReview(leagueUUID: r.leagueUUID, itemID: r.itemID, approved: r.approved)
            x.uuid = r.uuid
            x.date = r.date
            context.insert(x)
        }
        for m in messages ?? [] {
            let x = LeagueMessage(leagueUUID: m.leagueUUID, text: m.text)
            x.uuid = m.uuid
            x.date = m.date
            x.syncedAt = m.syncedAt
            x.photo = m.photo
            context.insert(x)
        }
        for p in prs ?? [] {
            let r = PersonalRecord(exerciseID: p.exerciseID, weight: p.weight, reps: p.reps, date: p.date)
            r.uuid = p.uuid
            context.insert(r)
        }
        for w in wods ?? [] {
            let r = WodResult(wodID: w.wodID, wodName: w.wodName, formatName: w.formatName)
            r.uuid = w.uuid; r.date = w.date; r.seconds = w.seconds; r.rounds = w.rounds; r.reps = w.reps
            r.rx = w.rx; r.note = w.note; r.activityUUID = w.activityUUID; r.capped = w.capped ?? false
            context.insert(r)
        }
        for c in checkIns ?? [] {
            let ci = LeagueCheckIn(leagueUUID: c.leagueUUID, activityUUID: c.activityUUID, title: c.title, note: c.note, date: c.date, photo: c.photo)
            ci.uuid = c.uuid
            ci.hadPhoto = c.hadPhoto ?? false
            ci.place = c.place
            ci.proofRaw = c.proof ?? ""
            ci.reviewRaw = c.review ?? ""
            ci.extraPhotosData = c.extraPhotos
            ci.syncedAt = hasSyncState == true ? c.syncedAt : exportedAt
            context.insert(ci)
        }
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
