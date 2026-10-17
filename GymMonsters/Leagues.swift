import Foundation
import SwiftData

// Ligas no estilo GymRats: cada liga é um ranking contínuo alimentado por check-ins de
// qualquer tipo de atividade. Por enquanto não há servidor: só existe você, e a liga de
// exemplo tem participantes simulados. Cada liga em que você entra dá um ovo próprio,
// que cresce só com os check-ins daquela liga; o parceiro (Gymmon inicial) ganha com tudo.

enum LeagueScoring: String, CaseIterable, Identifiable, Codable {
    case pontos, treinos, minutos

    var id: String { rawValue }

    var name: String {
        switch self {
        case .pontos: "Pontos"
        case .treinos: "Treinos"
        case .minutos: "Minutos"
        }
    }

    var detail: String {
        switch self {
        case .pontos: "Cada check-in vale o XP da atividade: duração × tipo × esforço. Justo entre corrida, musculação, yoga…"
        case .treinos: "Cada check-in vale 1. Ganha quem treina mais vezes."
        case .minutos: "Soma do tempo de todos os check-ins."
        }
    }

    func score(kind: ActivityKind, minutes: Int, effort: Int) -> Int {
        switch self {
        case .pontos: Game.xp(kind: kind, minutes: minutes, effort: effort)
        case .treinos: 1
        case .minutos: min(minutes, Game.maxMinutes)
        }
    }
}

@Model
final class League {
    var uuid: UUID = UUID()
    var name: String = ""
    var emoji: String = "🏆"
    var scoringRaw: String = LeagueScoring.pontos.rawValue
    var start: Date = Date.now
    var code: String = ""
    /// Liga de exemplo, com participantes simulados
    var isMock: Bool = false
    var joinedAt: Date = Date.now
    /// Monstro que representa o jogador nesta liga (recebe o XP dos check-ins dela)
    var monsterUUID: UUID?
    /// Último dia da liga (fim do dia); nil = sem fim
    var end: Date?
    /// Capa da liga
    @Attribute(.externalStorage) var cover: Data?

    init(name: String, emoji: String, scoring: LeagueScoring, start: Date = .now, isMock: Bool = false) {
        self.name = name
        self.emoji = emoji
        self.scoringRaw = scoring.rawValue
        self.start = Calendar.current.startOfDay(for: start)
        self.isMock = isMock
        self.code = League.newCode()
    }

    var scoring: LeagueScoring { LeagueScoring(rawValue: scoringRaw) ?? .pontos }

    var isOver: Bool { end.map { $0 < .now } ?? false }

    /// Dias que faltam, contando hoje (nil = sem fim)
    var daysLeft: Int? {
        guard let end else { return nil }
        let cal = Calendar.current
        return max(0, (cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: end)).day ?? 0) + 1)
    }

    /// Define a duração em dias a partir do início (0 = sem fim)
    func setDuration(days: Int) {
        let cal = Calendar.current
        end = days > 0 ? cal.date(byAdding: .second, value: -1, to: cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: start))!) : nil
    }

    var durationDays: Int {
        guard let end else { return 0 }
        let cal = Calendar.current
        return (cal.dateComponents([.day], from: cal.startOfDay(for: start), to: cal.startOfDay(for: end)).day ?? 0) + 1
    }

    static func newCode() -> String {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).map { _ in chars.randomElement()! })
    }
}

@Model
final class LeagueCheckIn {
    var uuid: UUID = UUID()
    var leagueUUID: UUID = UUID()
    var activityUUID: UUID = UUID()
    var title: String = ""
    var note: String = ""
    var date: Date = Date.now
    @Attribute(.externalStorage) var photo: Data?
    /// Onde foi (ex.: nome da academia), quando postado de lá
    var place: String?

    init(leagueUUID: UUID, activityUUID: UUID, title: String, note: String, date: Date, photo: Data?) {
        self.leagueUUID = leagueUUID
        self.activityUUID = activityUUID
        self.title = title
        self.note = note
        self.date = date
        self.photo = photo
    }
}

// MARK: - Participantes simulados

struct FakeMember: Identifiable {
    let id: String
    let name: String
    let form: MonsterForm
    let kinds: [ActivityKind]
    /// Chance de treinar num dia qualquer
    let frequency: Double
    let minutes: ClosedRange<Int>
    let titles: [ActivityKind: [String]]

    static let all: [FakeMember] = [
        FakeMember(id: "ana", name: "Ana", form: MonsterForm(stage: .champion, attribute: .resistencia),
                   kinds: [.corrida, .corrida, .bike], frequency: 0.7, minutes: 30...70,
                   titles: [.corrida: ["Corridinha matinal ☀️", "Longão de domingo", "Intervalado no parque"], .bike: ["Pedal com a galera 🚴"]]),
        FakeMember(id: "bruno", name: "Bruno", form: MonsterForm(stage: .champion, attribute: .forca),
                   kinds: [.musculacao, .musculacao, .crossfit], frequency: 0.8, minutes: 50...90,
                   titles: [.musculacao: ["Dia de perna 🦵", "Peito e tríceps", "Costas pesadas"], .crossfit: ["WOD do dia", "Crossfit sofrido 🥵"]]),
        FakeMember(id: "carla", name: "Carla", form: MonsterForm(stage: .rookie, attribute: nil),
                   kinds: [.yoga, .danca, .caminhada], frequency: 0.55, minutes: 30...60,
                   titles: [.yoga: ["Yoga pra começar o dia", "Alongamento 🧘"], .danca: ["Aula de dança 💃"], .caminhada: ["Caminhada com o dog 🐶"]]),
        FakeMember(id: "diego", name: "Diego", form: MonsterForm(stage: .champion, attribute: .agilidade),
                   kinds: [.futebol, .volei, .crossfit], frequency: 0.5, minutes: 45...100,
                   titles: [.futebol: ["Pelada de quinta ⚽", "Futsal com a firma"], .volei: ["Vôlei de praia 🏐"], .crossfit: ["Crossfit cedinho"]]),
        FakeMember(id: "fe", name: "Fê", form: MonsterForm(stage: .baby, attribute: nil),
                   kinds: [.natacao, .bike, .lutas], frequency: 0.45, minutes: 40...75,
                   titles: [.natacao: ["Natação 🏊‍♀️"], .bike: ["Spinning"], .lutas: ["Muay thai", "Treino de jiu-jitsu 🥋"]]),
    ]
}

struct FakeCheckIn {
    let id: String
    let member: FakeMember
    let date: Date
    let kind: ActivityKind
    let minutes: Int
    let effort: Int
    let title: String
}

enum MockLeague {
    static let name = "Liga dos Bros"
    static let code = "AMIGOS"

    /// Check-ins simulados, determinísticos: o mesmo dia gera sempre o mesmo resultado
    static func checkIns(league: League, now: Date = .now) -> [FakeCheckIn] {
        let cal = Calendar.current
        var out: [FakeCheckIn] = []
        var day = cal.startOfDay(for: league.start)
        let now = min(now, league.end ?? now)
        while day <= now {
            for m in FakeMember.all {
                var rng = SeededRandom(seed: "\(league.uuid)-\(m.id)-\(Int(day.timeIntervalSince1970))")
                guard rng.next() < m.frequency else { continue }
                let hour = 6 + Int(rng.next() * 15)
                guard let date = cal.date(byAdding: .minute, value: hour * 60 + Int(rng.next() * 60), to: day), date <= now else { continue }
                let kind = m.kinds[Int(rng.next() * Double(m.kinds.count)) % m.kinds.count]
                let minutes = m.minutes.lowerBound + Int(rng.next() * Double(m.minutes.count))
                out.append(FakeCheckIn(id: "\(m.id)-\(Int(day.timeIntervalSince1970))", member: m, date: date, kind: kind,
                                       minutes: minutes / 5 * 5, effort: 5 + Int(rng.next() * 4),
                                       title: { let t = m.titles[kind] ?? [kind.name]; return t[Int(rng.next() * Double(t.count)) % t.count] }()))
            }
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }
        return out
    }
}

/// Gerador estável entre execuções (o hash padrão do Swift muda a cada abertura do app)
struct SeededRandom {
    private var state: UInt64

    init(seed: String) {
        var h: UInt64 = 0xcbf29ce484222325
        for b in seed.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        state = h
    }

    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
}

// MARK: - Ranking e feed

struct FeedItem: Identifiable {
    let id: String
    let memberID: String
    let name: String
    let avatar: MonsterForm
    let isMe: Bool
    let date: Date
    let title: String
    let note: String
    let kind: ActivityKind
    let minutes: Int
    let score: Int
    let photo: Data?
    var place: String? = nil
}

struct RankRow: Identifiable {
    let id: String
    let name: String
    let avatar: MonsterForm
    let isMe: Bool
    let score: Int
    let checkIns: Int
}

enum LeagueBoard {
    static func feed(league: League, mine: [LeagueCheckIn], activities: [UUID: Activity], me: String, myAvatar: MonsterForm) -> [FeedItem] {
        let s = league.scoring
        var items: [FeedItem] = mine.compactMap { c in
            guard let a = activities[c.activityUUID] else { return nil }
            return FeedItem(id: c.uuid.uuidString, memberID: "me", name: me, avatar: myAvatar, isMe: true, date: c.date, title: c.title, note: c.note,
                            kind: a.kind, minutes: a.minutes, score: s.score(kind: a.kind, minutes: a.minutes, effort: a.effort), photo: c.photo,
                            place: c.place)
        }
        if league.isMock {
            items += MockLeague.checkIns(league: league).map { f in
                FeedItem(id: f.id, memberID: f.member.id, name: f.member.name, avatar: f.member.form, isMe: false, date: f.date, title: f.title, note: "",
                         kind: f.kind, minutes: f.minutes, score: s.score(kind: f.kind, minutes: f.minutes, effort: f.effort), photo: nil)
            }
        }
        return items.sorted { $0.date > $1.date }
    }

    static func ranking(feed: [FeedItem], league: League, me: String, myAvatar: MonsterForm, since: Date?) -> [RankRow] {
        var rows: [String: RankRow] = [:]
        // Todo mundo aparece, mesmo zerado
        rows["me"] = RankRow(id: "me", name: me, avatar: myAvatar, isMe: true, score: 0, checkIns: 0)
        if league.isMock {
            for m in FakeMember.all { rows[m.id] = RankRow(id: m.id, name: m.name, avatar: m.form, isMe: false, score: 0, checkIns: 0) }
        }
        for f in feed where (since.map { f.date >= $0 } ?? true) && f.date >= league.start && f.date <= (league.end ?? .distantFuture) {
            let r = rows[f.memberID] ?? RankRow(id: f.memberID, name: f.name, avatar: f.avatar, isMe: f.isMe, score: 0, checkIns: 0)
            rows[f.memberID] = RankRow(id: r.id, name: r.name, avatar: r.avatar, isMe: r.isMe, score: r.score + f.score, checkIns: r.checkIns + 1)
        }
        return rows.values.sorted { ($0.score, $0.isMe ? 1 : 0) > ($1.score, $1.isMe ? 1 : 0) }
    }
}
