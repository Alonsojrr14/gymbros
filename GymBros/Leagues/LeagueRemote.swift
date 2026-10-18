import Foundation
import Observation
import SwiftData

// Contrato entre o app e o servidor das ligas. Quem responde é escolhido em Backend.swift:
// MockLeagueBackend (participantes, check-ins, times e recados simulados e determinísticos) ou
// CloudKitLeagueBackend. Os tipos Remote*/Outgoing*/LeagueDraft são Codable e têm o formato do servidor.
//
// O que é seu continua no aparelho (League, LeagueCheckIn, LeagueMessage) e funciona como caixa de saída:
// `syncedAt` fica nil até o servidor aceitar; LeagueRemoteStore.flush manda tudo o que está pendente.

/// O que o servidor precisa saber de uma liga para responder
struct LeagueKey: Hashable, Sendable {
    let uuid: UUID
    let code: String
    let start: Date
    let end: Date?
    let isMock: Bool
    let teams: [LeagueTeam]
}

extension League {
    var key: LeagueKey { LeagueKey(uuid: uuid, code: code, start: start, end: end, isMock: isMock, teams: teams) }
}

struct RemoteMember: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    /// `MonsterForm.id` do bro que representa a pessoa na liga
    let formID: String
    var teamID: String?

    var form: MonsterForm { MonsterForm.byID(formID) ?? .egg }
}

struct RemoteCheckIn: Codable, Identifiable, Sendable {
    let id: String
    let memberID: String
    let date: Date
    let kindRaw: String
    let minutes: Int
    let effort: Int
    var meters: Double?
    var kcal: Double?
    let title: String
    var note = ""
    /// Teve foto (a imagem em si virá por URL quando houver servidor)
    var hasPhoto = false
    var photoURL: URL?

    var kind: ActivityKind { ActivityKind(rawValue: kindRaw) ?? .outro }
    var input: ScoreInput { ScoreInput(kind: kind, minutes: minutes, effort: effort, meters: meters, kcal: kcal) }
}

struct RemoteTeam: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    var memberIDs: [String] = []
}

/// Recado no mural da liga
struct RemoteMessage: Codable, Identifiable, Sendable {
    let id: String
    let memberID: String
    let date: Date
    let text: String
}

struct RemoteLeague: Sendable {
    var members: [RemoteMember] = []
    var checkIns: [RemoteCheckIn] = []
    var teams: [RemoteTeam] = []
    var messages: [RemoteMessage] = []

    static let empty = RemoteLeague()

    func member(_ id: String) -> RemoteMember? { members.first { $0.id == id } }
}

/// Recado seu ainda não confirmado pelo servidor
struct OutgoingMessage: Codable, Sendable {
    let id: UUID
    let date: Date
    let text: String
}

/// Seu check-in a publicar numa liga (o id é o do LeagueCheckIn: publicar de novo atualiza)
struct OutgoingCheckIn: Codable, Sendable {
    let id: UUID
    let date: Date
    let kindRaw: String
    let minutes: Int
    let effort: Int
    var meters: Double?
    var kcal: Double?
    let title: String
    let note: String
    let hasPhoto: Bool
    var photo: Data?
}

extension OutgoingCheckIn {
    /// O que sobe do check-in. De atividade do Saúde, só tipo, data e duração; kcal, distância e esforço de lá ficam no aparelho.
    init(_ c: LeagueCheckIn, activity a: Activity) {
        self.init(id: c.uuid, date: c.date, kindRaw: a.kindRaw, minutes: a.minutes, effort: a.publishableEffort,
                  meters: a.publishableMeters, kcal: a.publishableKcal, title: c.title, note: c.note, hasPhoto: c.hasPhoto, photo: c.photo)
    }
}

/// Liga como o servidor guarda: regras e times. Serve para criar e para entrar por código.
struct LeagueDraft: Codable, Sendable {
    let uuid: UUID
    let code: String
    let name: String
    let emoji: String
    let scoring: String
    let weights: String
    let tieBreak: String
    let photoRule: String
    let teams: String
    let start: Date
    let end: Date?
    let autoRenew: Bool
}

/// Como você aparece numa liga
struct Membership: Codable, Sendable {
    let name: String
    let formID: String
    let teamID: String?
}

protocol LeagueBackend: Sendable {
    /// Estado atual da liga (outros participantes, check-ins deles, times, mural)
    func fetch(_ league: LeagueKey, now: Date) async throws -> RemoteLeague
    /// Publica seus recados no mural; devolve os ids aceitos
    func send(_ messages: [OutgoingMessage], to league: LeagueKey) async throws -> [UUID]
    /// Cria a liga (você é o dono)
    func create(_ league: LeagueDraft) async throws
    /// Acha a liga pelo código; nil = não existe
    func join(code: String) async throws -> LeagueDraft?
    /// Seu nome, bro e time na liga
    func setMembership(_ membership: Membership, in league: LeagueKey) async throws
    /// Publica (ou atualiza) seus check-ins; devolve os ids aceitos
    func publish(_ checkIns: [OutgoingCheckIn], to league: LeagueKey) async throws -> [UUID]
    /// Tira check-ins seus da liga
    func retract(_ checkInIDs: [UUID], from league: LeagueKey) async throws
    /// Sai da liga (some do ranking; seus check-ins saem junto)
    func leave(_ league: LeagueKey) async throws
}

// MARK: - Cache

@MainActor @Observable
final class LeagueRemoteStore {
    static let shared = LeagueRemoteStore()

    var backend: any LeagueBackend = MockLeagueBackend()
    var access: AccessStore = .shared
    private(set) var cache: [LeagueKey: RemoteLeague] = [:]
    /// Último erro de sincronização (para mostrar se precisar)
    private(set) var lastError: String?

    /// A liga de exemplo é sempre simulada, mesmo com servidor ligado
    private func backend(for key: LeagueKey) -> any LeagueBackend { key.isMock ? MockLeagueBackend() : backend }

    /// O que já se sabe da liga. Sem resposta ainda, o exemplo é calculado na hora (para não piscar vazio).
    func remote(_ league: League) -> RemoteLeague {
        let key = league.key
        if let r = cache[key] { return r }
        return backend(for: key) is MockLeagueBackend ? MockLeagueBackend.build(key) : .empty
    }

    /// Esquece o que veio do servidor (conta excluída)
    func reset() {
        cache = [:]
        lastError = nil
    }

    func refresh(_ leagues: [League]) async {
        for l in leagues {
            let key = l.key
            if let r = try? await backend(for: key).fetch(key, now: .now) { cache[key] = r }
        }
    }

    private var flushing: Task<Void, Never>?

    /// Manda tudo o que está na caixa de saída (um envio por vez): ligas e seu lugar nelas, check-ins (novos, editados e apagados) e recados
    func flush(context: ModelContext) async {
        let previous = flushing
        let task = Task {
            await previous?.value
            await send(context: context)
        }
        flushing = task
        await task.value
    }

    private func send(context: ModelContext) async {
        let leagues = ((try? context.fetch(FetchDescriptor<League>())) ?? []).filter { !$0.isMock }
        let keys = Dictionary(leagues.map { ($0.uuid, $0.key) }, uniquingKeysWith: { a, _ in a })
        let monsters = (try? context.fetch(FetchDescriptor<Monster>())) ?? []
        let name = ContentFilter.publishable(UserDefaults.standard.string(forKey: "trainerName") ?? "")
        // Sem permissão, fica pendente. Retirar o que é seu nunca é bloqueado.
        let newLeagues = leagues.filter { $0.syncedAt == nil && !$0.isPastSeason && canSync($0) }.map { l in
            let last = monsters.first { $0.uuid == l.monsterUUID }?.lastFormID ?? ""
            let form = last.isEmpty ? MonsterForm.egg.id : last
            return (id: l.uuid, draft: l.joined ? nil : l.draft, key: l.key,
                    membership: Membership(name: name, formID: form, teamID: l.myTeamID))
        }

        let activities = Dictionary(((try? context.fetch(FetchDescriptor<Activity>())) ?? []).map { ($0.uuid, $0) }, uniquingKeysWith: { a, _ in a })
        let pending = access.can(.checkInsPublish)
            ? (try? context.fetch(FetchDescriptor<LeagueCheckIn>(predicate: #Predicate { $0.syncedAt == nil }))) ?? [] : []
        let checkIns = Dictionary(grouping: pending, by: \.leagueUUID).compactMap { leagueID, list -> (key: LeagueKey, out: [OutgoingCheckIn])? in
            guard let key = leagueID == ProfileFeed.id ? .profileFeed : keys[leagueID] else { return nil }
            return (key, list.compactMap { c in
                guard let a = activities[c.activityUUID] else { return nil }
                return OutgoingCheckIn(c, activity: a)
            })
        }

        let msgs = access.can(.messagesPublish)
            ? (try? context.fetch(FetchDescriptor<LeagueMessage>(predicate: #Predicate { $0.syncedAt == nil }))) ?? [] : []
        let messages = Dictionary(grouping: msgs, by: \.leagueUUID).compactMap { leagueID, list -> (key: LeagueKey, out: [OutgoingMessage])? in
            guard let key = keys[leagueID] else { return nil }
            return (key, list.map { OutgoingMessage(id: $0.uuid, date: $0.date, text: $0.text) })
        }

        do {
            for l in newLeagues {
                if let draft = l.draft { try await backend.create(draft) }
                try await backend.setMembership(l.membership, in: l.key)
                let id = l.id
                let fresh = (try? context.fetch(FetchDescriptor<League>(predicate: #Predicate { $0.uuid == id }))) ?? []
                for league in fresh where !league.isDeleted { league.syncedAt = .now }
            }

            for (key, out) in checkIns {
                let accepted = try await backend.publish(out, to: key)
                let fresh = (try? context.fetch(FetchDescriptor<LeagueCheckIn>(predicate: #Predicate { accepted.contains($0.uuid) }))) ?? []
                for c in fresh where !c.isDeleted { c.syncedAt = .now }
            }

            for (leagueID, ids) in LeagueOutbox.retractions {
                if let key = leagueID == ProfileFeed.id ? .profileFeed : keys[leagueID] { try await backend.retract(ids, from: key) }
                LeagueOutbox.clear(ids, from: leagueID)
            }

            for (key, out) in messages {
                let accepted = try await backend.send(out, to: key)
                let fresh = (try? context.fetch(FetchDescriptor<LeagueMessage>(predicate: #Predicate { accepted.contains($0.uuid) }))) ?? []
                for m in fresh where !m.isDeleted { m.syncedAt = .now }
            }
            lastError = nil
        } catch {
            // Fica na caixa de saída e tenta de novo na próxima vez
            lastError = error.localizedDescription
        }
        try? context.save()
    }

    /// Lugar na liga; quem criou também publica as regras
    private func canSync(_ league: League) -> Bool {
        access.can(.leaguesJoin) && (league.joined || access.can(.leaguesCreate) && access.can(.leaguesUpdate, on: league))
    }

    private var flushTask: Task<Void, Never>?

    /// Manda a caixa de saída daqui a pouco (junta várias mudanças seguidas num envio só)
    func scheduleFlush() {
        flushTask?.cancel()
        flushTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await flush(context: AppData.container.mainContext)
        }
    }

    /// Sair da liga no servidor (as temporadas saem junto)
    func leave(_ league: League) async {
        guard !league.isMock else { return }
        try? await backend.leave(league.key)
    }

    /// Procura a liga pelo código no servidor
    func join(code: String) async throws -> LeagueDraft? { try await backend.join(code: code) }
}

/// Check-ins seus que precisam sair do servidor (apagados aqui depois de publicados)
enum LeagueOutbox {
    private static let key = "pendingRetractions"

    static var retractions: [UUID: [UUID]] {
        let raw = UserDefaults.standard.dictionary(forKey: key) as? [String: [String]] ?? [:]
        return raw.reduce(into: [:]) { acc, kv in
            if let l = UUID(uuidString: kv.key) { acc[l] = kv.value.compactMap(UUID.init(uuidString:)) }
        }
    }

    /// Chame antes de apagar um check-in: se ele já tinha subido, entra na fila para sair
    static func retract(_ c: LeagueCheckIn) {
        guard c.syncedAt != nil else { return }
        var raw = UserDefaults.standard.dictionary(forKey: key) as? [String: [String]] ?? [:]
        raw[c.leagueUUID.uuidString, default: []].append(c.uuid.uuidString)
        UserDefaults.standard.set(raw, forKey: key)
    }

    static func clear(_ league: UUID) {
        var raw = UserDefaults.standard.dictionary(forKey: key) as? [String: [String]] ?? [:]
        raw[league.uuidString] = nil
        UserDefaults.standard.set(raw, forKey: key)
    }

    /// Tira da fila só o que já saiu do servidor (o que entrou durante o envio fica)
    static func clear(_ ids: [UUID], from league: UUID) {
        var raw = UserDefaults.standard.dictionary(forKey: key) as? [String: [String]] ?? [:]
        let sent = Set(ids.map(\.uuidString))
        let left = (raw[league.uuidString] ?? []).filter { !sent.contains($0) }
        raw[league.uuidString] = left.isEmpty ? nil : left
        UserDefaults.standard.set(raw, forKey: key)
    }
}

extension LeagueKey {
    /// Destino dos posts do perfil no servidor (funciona como uma liga só sua)
    static let profileFeed = LeagueKey(uuid: ProfileFeed.id, code: CloudType.profileFeed, start: .distantPast, end: nil, isMock: false, teams: [])
}

extension League {
    /// Liga de outra pessoa, achada pelo código
    convenience init(draft d: LeagueDraft) {
        self.init(name: d.name, emoji: d.emoji, scoring: LeagueScoring(rawValue: d.scoring) ?? .pontos, start: d.start)
        code = d.code
        weightsRaw = d.weights
        tieBreakRaw = d.tieBreak
        photoRuleRaw = d.photoRule
        teamsRaw = d.teams
        end = d.end
        autoRenew = d.autoRenew
        joined = true
    }

    var draft: LeagueDraft {
        LeagueDraft(uuid: seriesKey, code: code, name: name, emoji: emoji, scoring: scoringRaw, weights: weightsRaw, tieBreak: tieBreakRaw,
                    photoRule: photoRuleRaw, teams: teamsRaw, start: start, end: end, autoRenew: autoRenew)
    }
}

// MARK: - Servidor simulado

struct MockLeagueBackend: LeagueBackend {
    func fetch(_ league: LeagueKey, now: Date) async throws -> RemoteLeague { Self.build(league, now: now) }

    /// Sem servidor, tudo é aceito e fica só no aparelho
    func send(_ messages: [OutgoingMessage], to league: LeagueKey) async throws -> [UUID] { messages.map(\.id) }
    func create(_ league: LeagueDraft) async throws {}
    /// Só existe a liga de exemplo (tratada no app pelo código AMIGOS)
    func join(code: String) async throws -> LeagueDraft? { nil }
    func setMembership(_ membership: Membership, in league: LeagueKey) async throws {}
    func publish(_ checkIns: [OutgoingCheckIn], to league: LeagueKey) async throws -> [UUID] { checkIns.map(\.id) }
    func retract(_ checkInIDs: [UUID], from league: LeagueKey) async throws {}
    func leave(_ league: LeagueKey) async throws {}

    static func build(_ league: LeagueKey, now: Date = .now) -> RemoteLeague {
        var teams = league.teams.map { RemoteTeam(id: $0.id, name: $0.name) }
        guard league.isMock else { return RemoteLeague(teams: teams) }
        // Distribui os participantes simulados entre os times, começando por um time sorteado
        var rng = SeededRandom(seed: "\(league.uuid)-times")
        let offset = Int(rng.next() * 100)
        let members = FakeMember.all.enumerated().map { i, m in
            RemoteMember(id: m.id, name: m.name, formID: m.form.id, teamID: teams.isEmpty ? nil : teams[(i + offset) % teams.count].id)
        }
        for m in members { if let t = teams.firstIndex(where: { $0.id == m.teamID }) { teams[t].memberIDs.append(m.id) } }

        let checkIns = MockLeague.checkIns(league: league, now: now).map { f in
            var photo = SeededRandom(seed: "\(f.id)-foto")
            return RemoteCheckIn(id: f.id, memberID: f.member.id, date: f.date, kindRaw: f.kind.rawValue, minutes: f.minutes, effort: f.effort,
                                 meters: f.meters, title: f.title, hasPhoto: photo.next() < 0.75)
        }
        return RemoteLeague(members: members, checkIns: checkIns, teams: teams,
                            messages: messages(league, members: members, teams: teams, now: now))
    }

    private static let phrases = [
        "Bora que hoje tem! 💪", "Quem vai amanhã cedo?", "Hoje foi pesado 🥵", "Tô sentindo até a alma",
        "Alguém segura essa liga", "Fim de semana sem desculpa, hein", "Meu bro tá quase evoluindo 👀",
        "Choveu mas eu fui 🌧️", "Descanso também é treino 😴", "Essa semana eu viro o jogo",
        "Quem topa um treino junto sábado?", "Primeira vez que não pulo a segunda-feira 🎉",
    ]

    private static let teamPhrases = ["Vamos, %@! 🔥", "%@ não para!", "Só mais um check-in e a gente passa, %@"]

    /// Até um recado por pessoa por dia, sempre igual para o mesmo dia
    private static func messages(_ league: LeagueKey, members: [RemoteMember], teams: [RemoteTeam], now: Date) -> [RemoteMessage] {
        let cal = Calendar.current
        var out: [RemoteMessage] = []
        var day = cal.startOfDay(for: league.start)
        let last = min(now, league.end ?? now)
        while day <= last {
            for m in members {
                var rng = SeededRandom(seed: "\(league.uuid)-\(m.id)-\(Int(day.timeIntervalSince1970))-mural")
                guard rng.next() < 0.3 else { continue }
                guard let date = cal.date(byAdding: .minute, value: 7 * 60 + Int(rng.next() * 15 * 60), to: day), date <= now else { continue }
                let team = teams.first { $0.id == m.teamID }
                let text: String
                if let team, rng.next() < 0.35 {
                    text = String(format: teamPhrases[Int(rng.next() * Double(teamPhrases.count)) % teamPhrases.count], team.name)
                } else {
                    text = phrases[Int(rng.next() * Double(phrases.count)) % phrases.count]
                }
                out.append(RemoteMessage(id: "\(m.id)-\(Int(day.timeIntervalSince1970))-msg", memberID: m.id, date: date, text: text))
            }
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }
        return out
    }
}
