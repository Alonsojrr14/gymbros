import Foundation
import SwiftData

// Ligas no estilo GymRats: cada liga é um ranking contínuo alimentado por check-ins de
// qualquer tipo de atividade. Os outros participantes, times e o mural vêm de LeagueRemoteStore
// (por enquanto simulados, ver LeagueRemote.swift). Ao entrar, você escolhe quem te representa (um bro
// seu ou um ovo novo). A atividade postada em ligas dá XP só aos representantes delas; sem liga, vai para
// o dono gravado na atividade ou o bro inicial (Roster.owners).

/// O que um check-in precisa para virar pontos em qualquer modo
struct ScoreInput {
    var kind: ActivityKind
    var minutes: Int
    var effort: Int
    /// Distância (GPS ou Apple Saúde), quando houver
    var meters: Double? = nil
    /// Calorias ativas do Apple Saúde, quando houver
    var kcal: Double? = nil
}

extension Activity {
    var scoreInput: ScoreInput { ScoreInput(kind: kind, minutes: minutes, effort: effort, meters: meters, kcal: kcal) }
}

enum LeagueScoring: String, CaseIterable, Identifiable, Codable {
    case pontos, treinos, minutos, distancia, calorias

    var id: String { rawValue }

    var name: String {
        switch self {
        case .pontos: "Pontos"
        case .treinos: "Treinos"
        case .minutos: "Minutos"
        case .distancia: "Distância"
        case .calorias: "Calorias"
        }
    }

    var detail: String {
        switch self {
        case .pontos: "Cada check-in vale o XP da atividade: duração × tipo × esforço. Justo entre corrida, musculação, yoga…"
        case .treinos: "Cada check-in vale 1. Ganha quem treina mais vezes."
        case .minutos: "Soma do tempo de todos os check-ins."
        case .distancia: "Soma dos quilômetros (corrida, caminhada, bike, natação com GPS ou do Apple Saúde). Atividade sem distância não pontua."
        case .calorias: "Soma das calorias ativas: as do Apple Saúde quando houver, senão estimadas pela atividade, duração e esforço."
        }
    }

    /// Peso de referência para estimar calorias de quem não tem o dado do Saúde
    static let referenceWeight = 70.0

    /// Pontos de um check-in. `weights` multiplica a parte de cada atributo (só no modo pontos; vazio = 1× em tudo).
    func score(_ i: ScoreInput, weights: [Attribute: Double] = [:]) -> Int {
        switch self {
        case .pontos:
            let xp = Game.xp(kind: i.kind, minutes: i.minutes, effort: i.effort)
            guard !weights.isEmpty else { return xp }
            let factor = i.kind.weights.reduce(0) { $0 + $1.value * (weights[$1.key] ?? 1) }
            return Int((Double(xp) * factor).rounded())
        case .treinos: return 1
        case .minutos: return min(i.minutes, Game.maxMinutes)
        case .distancia: return Int(i.meters ?? 0)
        case .calorias:
            let kcal = i.kcal ?? HealthSync.activeKcal(kind: i.kind, minutes: i.minutes, effort: i.effort, weight: Self.referenceWeight)
            return Int(kcal.rounded())
        }
    }

    /// Placar com unidade: "120 pts", "3 treinos", "1 h 20 min", "12,4 km", "830 kcal"
    func format(_ v: Int) -> String {
        switch self {
        case .pontos: "\(v) pts"
        case .treinos: "\(v) treino\(v == 1 ? "" : "s")"
        case .minutos: durationText(v)
        case .distancia: Self.km(v)
        case .calorias: "\(v) kcal"
        }
    }

    /// Só o número, para colunas de ranking e o "+" do feed
    func short(_ v: Int) -> String {
        switch self {
        case .minutos: durationText(v)
        case .distancia: Self.km(v)
        default: "\(v)"
        }
    }

    private static func km(_ meters: Int) -> String {
        String(format: meters < 10_000 ? "%.1f km" : "%.0f km", Double(meters) / 1000).replacingOccurrences(of: ".", with: ",")
    }
}

/// Critério quando dois participantes empatam no placar
enum LeagueTieBreak: String, CaseIterable, Identifiable, Codable {
    case primeiro, sequencia, checkins

    var id: String { rawValue }

    var name: String {
        switch self {
        case .primeiro: "Chegou antes"
        case .sequencia: "Sequência"
        case .checkins: "Check-ins"
        }
    }

    var detail: String {
        switch self {
        case .primeiro: "No empate, fica na frente quem chegou primeiro àquela pontuação."
        case .sequencia: "No empate, fica na frente quem treinou mais dias seguidos no período."
        case .checkins: "No empate, fica na frente quem fez mais check-ins."
        }
    }
}

/// Quanto vale um check-in sem foto
enum PhotoRule: String, CaseIterable, Identifiable, Codable {
    case livre, metade, obrigatoria

    var id: String { rawValue }

    var name: String {
        switch self {
        case .livre: "Opcional"
        case .metade: "Vale ½"
        case .obrigatoria: "Obrigatória"
        }
    }

    var detail: String {
        switch self {
        case .livre: "Check-in sem foto vale o mesmo que com foto."
        case .metade: "Check-in sem foto vale metade. A foto é a prova do treino."
        case .obrigatoria: "Check-in sem foto não pontua. A foto é a prova do treino."
        }
    }

    func apply(_ score: Int, hasPhoto: Bool) -> Int {
        guard !hasPhoto else { return score }
        switch self {
        case .livre: return score
        // Arredonda para cima: metade de algo que vale nunca vira zero (no modo Treinos, 1 continua 1)
        case .metade: return (score + 1) / 2
        case .obrigatoria: return 0
        }
    }
}

/// Janela do ranking
enum RankWindow: String, CaseIterable, Identifiable {
    case liga, semana, mes

    var id: String { rawValue }

    var name: String {
        switch self {
        case .liga: "Liga toda"
        case .semana: "Esta semana"
        case .mes: "Este mês"
        }
    }

    func since(now: Date = .now, calendar: Calendar = .current) -> Date? {
        switch self {
        case .liga: nil
        case .semana: calendar.dateInterval(of: .weekOfYear, for: now)?.start
        case .mes: calendar.dateInterval(of: .month, for: now)?.start
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
    /// Renovação automática: ao acabar, começa outra temporada igual
    var autoRenew: Bool = false
    var season: Int = 1
    /// Liga da 1ª temporada (todas as temporadas apontam para ela); nil = esta é a primeira
    var seriesID: UUID?
    /// Temporada seguinte, quando esta já foi renovada
    var nextUUID: UUID?
    /// Multiplicador de cada atributo no modo pontos ("forca:2,tecnica:0"); vazio = 1× em tudo
    var weightsRaw: String = ""
    var tieBreakRaw: String = LeagueTieBreak.primeiro.rawValue
    var photoRuleRaw: String = PhotoRule.livre.rawValue
    /// Times, um por linha: "id\tnome" (formato antigo: só o nome, id = posição); vazio = liga sem times
    var teamsRaw: String = ""
    /// Seu time (`LeagueTeam.id`)
    var myTeamID: String?

    init(name: String, emoji: String, scoring: LeagueScoring, start: Date = .now, isMock: Bool = false) {
        self.name = name
        self.emoji = emoji
        self.scoringRaw = scoring.rawValue
        self.start = Calendar.current.startOfDay(for: start)
        self.isMock = isMock
        self.code = League.newCode()
    }

    var scoring: LeagueScoring { LeagueScoring(rawValue: scoringRaw) ?? .pontos }

    var tieBreak: LeagueTieBreak {
        get { LeagueTieBreak(rawValue: tieBreakRaw) ?? .primeiro }
        set { tieBreakRaw = newValue.rawValue }
    }

    var photoRule: PhotoRule {
        get { PhotoRule(rawValue: photoRuleRaw) ?? .livre }
        set { photoRuleRaw = newValue.rawValue }
    }

    /// Times com id estável: renomear, reordenar ou tirar um time não troca ninguém de time
    var teams: [LeagueTeam] {
        get { LeagueTeams.parse(teamsRaw) }
        set {
            teamsRaw = LeagueTeams.encode(newValue)
            if let t = myTeamID, !teams.contains(where: { $0.id == t }) { myTeamID = nil }
        }
    }

    var teamNames: [String] { teams.map(\.name) }

    var hasTeams: Bool { !teams.isEmpty }

    /// Só os atributos fora de 1×
    var attributeWeights: [Attribute: Double] {
        get {
            weightsRaw.split(separator: ",").reduce(into: [:]) { acc, pair in
                let p = pair.split(separator: ":")
                if p.count == 2, let a = Attribute(rawValue: String(p[0])), let v = Double(p[1]) { acc[a] = v }
            }
        }
        set {
            weightsRaw = Attribute.allCases.compactMap { a in
                newValue[a].flatMap { $0 == 1 ? nil : "\(a.rawValue):\($0.formatted(.number.locale(Locale(identifier: "en_US_POSIX")).grouping(.never)))" }
            }.joined(separator: ",")
        }
    }

    /// Pontos de um check-in nesta liga
    func score(_ i: ScoreInput, hasPhoto: Bool = true) -> Int {
        photoRule.apply(scoring.score(i, weights: scoring == .pontos ? attributeWeights : [:]), hasPhoto: hasPhoto)
    }

    var isOver: Bool { end.map { $0 < .now } ?? false }

    /// Dias que faltam, contando hoje (nil = sem fim)
    var daysLeft: Int? {
        guard let end else { return nil }
        let cal = Calendar.current
        return max(0, (cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: end)).day ?? 0) + 1)
    }

    var hasStarted: Bool { start <= .now }

    /// Identifica a série de temporadas
    var seriesKey: UUID { seriesID ?? uuid }

    /// Já virou temporada passada (existe uma seguinte)
    var isPastSeason: Bool { nextUUID != nil }

    /// Dias até começar (0 se já começou)
    var daysToStart: Int {
        let cal = Calendar.current
        return max(0, cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: start)).day ?? 0)
    }

    /// "começa hoje", "começa amanhã", "começa em 3 dias" (minúsculo, para ir no meio da frase)
    static func startsText(_ start: Date) -> String {
        let cal = Calendar.current
        let n = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: start)).day ?? 0
        switch n {
        case ..<0: return "já começou"
        case 0: return "começa hoje"
        case 1: return "começa amanhã"
        default: return "começa em \(n) dias"
        }
    }

    /// Período escolhido no calendário: do começo do dia de início ao fim do dia final (nil = sem fim)
    func setPeriod(start s: Date, end e: Date?) {
        let cal = Calendar.current
        start = cal.startOfDay(for: s)
        end = e.map { cal.date(byAdding: .second, value: -1, to: cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: max($0, s)))!)! }
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
    /// Foi postado com foto, mesmo que a imagem não esteja mais aqui (backup restaurado não traz as fotos)
    var hadPhoto: Bool = false

    /// Vale como check-in com foto na regra da liga
    var hasPhoto: Bool { photo != nil || hadPhoto }

    init(leagueUUID: UUID, activityUUID: UUID, title: String, note: String, date: Date, photo: Data?) {
        self.leagueUUID = leagueUUID
        self.activityUUID = activityUUID
        self.title = title
        self.note = note
        self.date = date
        self.photo = photo
        self.hadPhoto = photo != nil
    }

    /// Troca a foto do post. Sem imagem guardada (backup restaurado), tirar a foto da edição não apaga o "tinha foto".
    func setPhoto(_ data: Data?) {
        if data == nil && photo == nil { return }
        photo = data
        hadPhoto = data != nil
    }
}

/// O perfil funciona como um destino de check-in, igual a uma liga
enum ProfileFeed {
    static let id = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
}

// MARK: - Renovação

enum LeagueRenewal {
    /// Cria a próxima temporada das ligas com renovação que acabaram. Se o app ficou fechado por
    /// mais de uma temporada, pula direto para a que está acontecendo agora.
    @MainActor
    static func run(context: ModelContext, now: Date = .now) {
        let all = (try? context.fetch(FetchDescriptor<League>())) ?? []
        var created = false
        for old in all where old.autoRenew && old.nextUUID == nil {
            guard let end = old.end, end < now else { continue }
            let next = makeNext(after: old, now: now)
            context.insert(next)
            old.nextUUID = next.uuid
            created = true
        }
        if created { try? context.save() }
    }

    static func makeNext(after old: League, now: Date = .now) -> League {
        let cal = Calendar.current
        let days = max(old.durationDays, 1)
        var start = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: old.end ?? now))!
        var seasons = 1
        // Temporadas que passaram com o app fechado
        while let last = cal.date(byAdding: .day, value: days - 1, to: start), cal.startOfDay(for: last) < cal.startOfDay(for: now) {
            start = cal.date(byAdding: .day, value: days, to: start)!
            seasons += 1
        }
        let l = League(name: old.name, emoji: old.emoji, scoring: old.scoring, start: start, isMock: old.isMock)
        l.setPeriod(start: start, end: cal.date(byAdding: .day, value: days - 1, to: start))
        l.code = old.code
        l.cover = old.cover
        l.monsterUUID = old.monsterUUID
        l.joinedAt = old.joinedAt
        l.weightsRaw = old.weightsRaw
        l.tieBreakRaw = old.tieBreakRaw
        l.photoRuleRaw = old.photoRuleRaw
        l.teamsRaw = old.teamsRaw
        l.myTeamID = old.myTeamID
        l.autoRenew = true
        l.season = old.season + seasons
        l.seriesID = old.seriesKey
        return l
    }
}

// MARK: - Participantes simulados

/// Pessoas simuladas: a mesma pessoa tem o mesmo bro na liga, no mapa (FriendsLive) e nos amigos
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
        FakeMember(id: "ana", name: "Ana", form: MonsterForm(stage: .champion, attribute: .resistencia, species: "lobo"),
                   kinds: [.corrida, .corrida, .bike], frequency: 0.7, minutes: 30...70,
                   titles: [.corrida: ["Corridinha matinal ☀️", "Longão de domingo", "Intervalado no parque"], .bike: ["Pedal com a galera 🚴"]]),
        FakeMember(id: "bruno", name: "Bruno", form: MonsterForm(stage: .champion, attribute: .forca, species: "urso"),
                   kinds: [.musculacao, .musculacao, .crossfit], frequency: 0.8, minutes: 50...90,
                   titles: [.musculacao: ["Dia de perna 🦵", "Peito e tríceps", "Costas pesadas"], .crossfit: ["WOD do dia", "Crossfit sofrido 🥵"]]),
        FakeMember(id: "carla", name: "Carla", form: MonsterForm(stage: .champion, attribute: .tecnica, species: "esquilo"),
                   kinds: [.yoga, .danca, .caminhada], frequency: 0.55, minutes: 30...60,
                   titles: [.yoga: ["Yoga pra começar o dia", "Alongamento 🧘"], .danca: ["Aula de dança 💃"], .caminhada: ["Caminhada com o dog 🐶"]]),
        FakeMember(id: "diego", name: "Diego", form: MonsterForm(stage: .ultimate, attribute: .forca, attribute2: .agilidade, species: "gato"),
                   kinds: [.futebol, .volei, .crossfit], frequency: 0.5, minutes: 45...100,
                   titles: [.futebol: ["Pelada de quinta ⚽", "Futsal com a firma"], .volei: ["Vôlei de praia 🏐"], .crossfit: ["Crossfit cedinho"]]),
        FakeMember(id: "fe", name: "Fê", form: MonsterForm(stage: .rookie, attribute: nil, species: "coruja"),
                   kinds: [.natacao, .bike, .lutas], frequency: 0.45, minutes: 40...75,
                   titles: [.natacao: ["Natação 🏊‍♀️"], .bike: ["Spinning"], .lutas: ["Muay thai", "Treino de jiu-jitsu 🥋"]]),
        // Ainda não são seus amigos: aparecem como sugestão na tela de amigos
        FakeMember(id: "gui", name: "Gui", form: MonsterForm(stage: .rookie, attribute: nil),
                   kinds: [.musculacao, .musculacao, .lutas], frequency: 0.6, minutes: 45...80,
                   titles: [.musculacao: ["Treino A 💪", "Braço hoje", "Leg day sofrido"], .lutas: ["Boxe 🥊"]]),
        FakeMember(id: "lia", name: "Lia", form: MonsterForm(stage: .baby, attribute: nil),
                   kinds: [.corrida, .yoga, .caminhada], frequency: 0.5, minutes: 25...55,
                   titles: [.corrida: ["Primeiros 5 km 🏃‍♀️", "Trote leve"], .yoga: ["Yoga em casa"], .caminhada: ["Caminhada no fim de tarde"]]),
        FakeMember(id: "rafa", name: "Rafa", form: MonsterForm(stage: .ultimate, attribute: .resistencia),
                   kinds: [.bike, .corrida, .bike], frequency: 0.75, minutes: 50...120,
                   titles: [.bike: ["Pedal de 60 km 🚴", "Subida da serra"], .corrida: ["Regenerativo", "Treino de tiro"]]),
    ]

    static func byID(_ id: String) -> FakeMember? { all.first { $0.id == id } }
}

struct FakeCheckIn {
    let id: String
    let member: FakeMember
    let date: Date
    let kind: ActivityKind
    let minutes: Int
    let effort: Int
    let title: String
    var meters: Double? = nil

    var input: ScoreInput { ScoreInput(kind: kind, minutes: minutes, effort: effort, meters: meters) }
}

enum MockLeague {
    static let name = "Liga dos Bros"
    static let code = "AMIGOS"

    /// Check-ins simulados, determinísticos: o mesmo dia gera sempre o mesmo resultado
    static func checkIns(league: LeagueKey, now: Date = .now) -> [FakeCheckIn] {
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
                let mins = minutes / 5 * 5
                let effort = 5 + Int(rng.next() * 4)
                let title = { let t = m.titles[kind] ?? [kind.name]; return t[Int(rng.next() * Double(t.count)) % t.count] }()
                // Sorteado por último para não mudar o que os sorteios anteriores já davam
                let meters = kind.typicalPace.map { Double(mins) / ($0 * (0.85 + rng.next() * 0.3)) * 1000 }
                out.append(FakeCheckIn(id: "\(m.id)-\(Int(day.timeIntervalSince1970))", member: m, date: date, kind: kind,
                                       minutes: mins, effort: effort, title: title, meters: meters))
            }
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }
        return out
    }
}

extension ActivityKind {
    /// Ritmo típico em min/km das atividades que têm distância
    var typicalPace: Double? {
        switch self {
        case .corrida: 6
        case .caminhada: 11
        case .bike: 2.5
        case .natacao: 25
        default: nil
        }
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
    var hasPhoto = false
    var effort = 5
    var teamID: String? = nil
    /// Modo da liga, para o placar com unidade; nil = post do perfil (vale XP)
    var scoring: LeagueScoring? = nil
}

struct RankRow: Identifiable {
    let id: String
    let name: String
    let avatar: MonsterForm
    let isMe: Bool
    var score = 0
    var checkIns = 0
    /// Check-in que levou ao placar atual (desempate "chegou antes")
    var reachedAt: Date?
    /// Mais dias seguidos com check-in na janela (desempate "sequência")
    var bestStreak = 0
    /// Empatado no placar com alguém e decidido pelo desempate
    var tied = false
}

struct LeagueTeam: Hashable, Identifiable, Sendable {
    let id: String
    var name: String

    /// Time novo, com id que não depende da posição
    init(name: String) { self.init(id: LeagueTeams.newID(), name: name) }
    init(id: String, name: String) { self.id = id; self.name = name }
}

/// Formato de `League.teamsRaw`
enum LeagueTeams {
    /// Ids do formato antigo, só com nomes: a posição na lista ("t0", "t1"…)
    static func legacyID(_ index: Int) -> String { "t\(index)" }

    static func newID() -> String { "x" + UUID().uuidString.prefix(8).lowercased() }

    static func parse(_ raw: String) -> [LeagueTeam] {
        raw.split(separator: "\n").map(String.init).enumerated().compactMap { i, line in
            let parts = line.split(separator: "\t", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            let (id, name) = parts.count == 2 ? (parts[0], parts[1]) : (legacyID(i), parts.first ?? "")
            return name.isEmpty || id.isEmpty ? nil : LeagueTeam(id: id, name: name)
        }
    }

    static func encode(_ teams: [LeagueTeam]) -> String {
        teams.compactMap { t in
            let name = t.name.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? nil : "\(t.id)\t\(name)"
        }
        .joined(separator: "\n")
    }
}

struct TeamRow: Identifiable {
    let id: String
    let name: String
    let isMine: Bool
    let score: Int
    let members: Int
    /// Bro do time: cresce com a média de XP dos membros e evolui pelo atributo que o time mais treina
    let form: MonsterForm
    let progress: Double
}

@MainActor
enum LeagueBoard {
    static func feed(league: League, mine: [LeagueCheckIn], activities: [UUID: Activity], me: String, myAvatar: MonsterForm,
                     remote: RemoteLeague? = nil) -> [FeedItem] {
        let remote = remote ?? LeagueRemoteStore.shared.remote(league)
        var items: [FeedItem] = mine.compactMap { c in
            guard let a = activities[c.activityUUID] else { return nil }
            return FeedItem(id: c.uuid.uuidString, memberID: "me", name: me, avatar: myAvatar, isMe: true, date: c.date, title: c.title, note: c.note,
                            kind: a.kind, minutes: a.minutes, score: league.score(a.scoreInput, hasPhoto: c.hasPhoto), photo: c.photo,
                            place: c.place, hasPhoto: c.hasPhoto, effort: a.effort, teamID: league.myTeamID, scoring: league.scoring)
        }
        items += remote.checkIns.compactMap { r in
            guard let m = remote.member(r.memberID) else { return nil }
            return FeedItem(id: r.id, memberID: m.id, name: m.name, avatar: m.form, isMe: false, date: r.date, title: r.title, note: r.note,
                            kind: r.kind, minutes: r.minutes, score: league.score(r.input, hasPhoto: r.hasPhoto), photo: nil,
                            hasPhoto: r.hasPhoto, effort: r.effort, teamID: m.teamID, scoring: league.scoring)
        }
        return items.sorted { $0.date > $1.date }
    }

    /// Placar dos times: soma do placar de cada membro na janela
    static func teams(league: League, ranking: [RankRow], feed: [FeedItem], remote: RemoteLeague? = nil) -> [TeamRow] {
        let remote = remote ?? LeagueRemoteStore.shared.remote(league)
        let byMember = Dictionary(ranking.map { ($0.id, $0.score) }, uniquingKeysWith: +)
        let inLeague = feed.filter { $0.date >= league.start && $0.date <= (league.end ?? .distantFuture) }
        return remote.teams.map { t in
            let ids = t.memberIDs + (league.myTeamID == t.id ? ["me"] : [])
            let (form, progress) = teamBro(ids.map { id in inLeague.filter { $0.memberID == id } })
            return TeamRow(id: t.id, name: t.name, isMine: league.myTeamID == t.id, score: ids.reduce(0) { $0 + (byMember[$1] ?? 0) },
                           members: ids.count, form: form, progress: progress)
        }
        .sorted { ($0.score, $0.isMine ? 1 : 0) > ($1.score, $1.isMine ? 1 : 0) }
    }

    /// Média do XP de cada membro (time grande não leva vantagem) e atributos somados
    private static func teamBro(_ members: [[FeedItem]]) -> (MonsterForm, Double) {
        guard !members.isEmpty else { return (.egg, 0) }
        var attrs: [Attribute: Double] = [:]
        var xp = 0
        for items in members {
            let s = Game.snapshot(items.map { ActivityRecord(id: UUID(), kind: $0.kind, date: $0.date, minutes: $0.minutes, effort: $0.effort) })
            xp += s.totalXP
            attrs.merge(s.lifetimeAttributes, uniquingKeysWith: +)
        }
        let avg = xp / members.count
        let stage = Stage.allCases.last { avg >= $0.threshold } ?? .egg
        let progress = stage.next.map { min(max(Double(avg - stage.threshold) / Double($0.threshold - stage.threshold), 0), 1) } ?? 1
        guard stage.branches, !attrs.isEmpty else { return (MonsterForm(stage: stage, attribute: nil), progress) }
        let (a, b) = Game.branch(attrs)
        let f = MonsterForm(stage: stage, attribute: a, attribute2: b)
        return (f.hasArt ? f : f.single, progress)
    }

    static func ranking(feed: [FeedItem], league: League, me: String, myAvatar: MonsterForm, since: Date?,
                        remote: RemoteLeague? = nil) -> [RankRow] {
        let remote = remote ?? LeagueRemoteStore.shared.remote(league)
        var rows: [String: RankRow] = [:]
        var days: [String: Set<Date>] = [:]
        // Todo mundo aparece, mesmo zerado
        rows["me"] = RankRow(id: "me", name: me, avatar: myAvatar, isMe: true)
        for m in remote.members { rows[m.id] = RankRow(id: m.id, name: m.name, avatar: m.form, isMe: false) }
        let cal = Calendar.current
        // Do mais antigo para o mais novo: o último check-in que pontuou é quando a pessoa chegou ao placar
        for f in feed.reversed() where (since.map { f.date >= $0 } ?? true) && f.date >= league.start && f.date <= (league.end ?? .distantFuture) {
            var r = rows[f.memberID] ?? RankRow(id: f.memberID, name: f.name, avatar: f.avatar, isMe: f.isMe)
            r.score += f.score
            r.checkIns += 1
            if f.score > 0 { r.reachedAt = f.date }
            rows[f.memberID] = r
            days[f.memberID, default: []].insert(cal.startOfDay(for: f.date))
        }
        for (id, d) in days { rows[id]?.bestStreak = Game.bestStreak(days: d, calendar: cal) }
        var sorted = rows.values.sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            switch league.tieBreak {
            case .primeiro:
                // Quem ainda não pontuou fica atrás
                if a.reachedAt != b.reachedAt { return (a.reachedAt ?? .distantFuture) < (b.reachedAt ?? .distantFuture) }
            case .sequencia:
                if a.bestStreak != b.bestStreak { return a.bestStreak > b.bestStreak }
            case .checkins:
                if a.checkIns != b.checkIns { return a.checkIns > b.checkIns }
            }
            return a.isMe != b.isMe ? a.isMe : a.name < b.name
        }
        for i in sorted.indices where sorted[i].score > 0 {
            sorted[i].tied = (i > 0 && sorted[i - 1].score == sorted[i].score) || (i < sorted.count - 1 && sorted[i + 1].score == sorted[i].score)
        }
        return sorted
    }
}
