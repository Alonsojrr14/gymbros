import Foundation
import Observation
import SwiftData

// Contrato entre o app e o servidor das ligas. Hoje quem responde é o MockLeagueBackend,
// com participantes, check-ins, times e recados simulados (determinísticos). Para ligar um
// servidor de verdade: implementar LeagueBackend (HTTP) e trocar LeagueRemoteStore.shared.backend.
// Os tipos Remote* são Codable e já têm o formato que a API deve devolver.
//
// O que é seu continua no aparelho (LeagueCheckIn, LeagueMessage) e funciona como caixa de saída:
// LeagueMessage.syncedAt fica nil até o servidor aceitar.

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

protocol LeagueBackend: Sendable {
    /// Estado atual da liga (outros participantes, check-ins deles, times, mural)
    func fetch(_ league: LeagueKey, now: Date) async throws -> RemoteLeague
    /// Publica seus recados no mural; devolve os ids aceitos
    func send(_ messages: [OutgoingMessage], to league: LeagueKey) async throws -> [UUID]
}

// MARK: - Cache

@MainActor @Observable
final class LeagueRemoteStore {
    static let shared = LeagueRemoteStore()

    var backend: any LeagueBackend = MockLeagueBackend()
    private(set) var cache: [LeagueKey: RemoteLeague] = [:]

    /// O que já se sabe da liga. Sem resposta ainda, o exemplo é calculado na hora (para não piscar vazio).
    func remote(_ league: League) -> RemoteLeague {
        let key = league.key
        if let r = cache[key] { return r }
        return backend is MockLeagueBackend ? MockLeagueBackend.build(key) : .empty
    }

    func refresh(_ leagues: [League]) async {
        for l in leagues {
            let key = l.key
            if let r = try? await backend.fetch(key, now: .now) { cache[key] = r }
        }
    }

    /// Manda os recados pendentes e marca os aceitos
    func flush(context: ModelContext) async {
        let pending = (try? context.fetch(FetchDescriptor<LeagueMessage>(predicate: #Predicate { $0.syncedAt == nil }))) ?? []
        let leagues = (try? context.fetch(FetchDescriptor<League>())) ?? []
        for (leagueID, msgs) in Dictionary(grouping: pending, by: \.leagueUUID) {
            guard let l = leagues.first(where: { $0.uuid == leagueID }) else { continue }
            let out = msgs.map { OutgoingMessage(id: $0.uuid, date: $0.date, text: $0.text) }
            guard let accepted = try? await backend.send(out, to: l.key) else { continue }
            for m in msgs where accepted.contains(m.uuid) { m.syncedAt = .now }
        }
        try? context.save()
    }
}

/// Seu recado no mural de uma liga
@Model
final class LeagueMessage {
    var uuid: UUID = UUID()
    var leagueUUID: UUID = UUID()
    var text: String = ""
    var date: Date = Date.now
    /// Quando o servidor aceitou; nil = na caixa de saída
    var syncedAt: Date?

    init(leagueUUID: UUID, text: String) {
        self.leagueUUID = leagueUUID
        self.text = text
    }
}

// MARK: - Servidor simulado

struct MockLeagueBackend: LeagueBackend {
    func fetch(_ league: LeagueKey, now: Date) async throws -> RemoteLeague { Self.build(league, now: now) }

    /// Sem servidor, tudo é aceito e fica só no aparelho
    func send(_ messages: [OutgoingMessage], to league: LeagueKey) async throws -> [UUID] { messages.map(\.id) }

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
