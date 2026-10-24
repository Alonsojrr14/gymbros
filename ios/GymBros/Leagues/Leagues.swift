import Foundation
import SwiftData

// Grupos no estilo GymRats: clubes são contínuos e desafios têm prazo, ambos alimentados por
// check-ins de qualquer tipo de atividade. Os outros participantes, times e o mural vêm de LeagueRemoteStore
// (por enquanto simulados, ver LeagueRemote.swift). Ao entrar, você escolhe quem te representa (um bro
// seu ou um ovo novo). Toda atividade dá XP inteiro ao principal (o dono gravado nela, ou o bro inicial); postada
// em ligas, dá também um pouco menos a quem representa você em cada uma (Roster.shares).

/// Um clube não termina; um desafio tem início e fim definidos. O tipo é derivado do período
/// para manter compatibilidade com ligas já gravadas antes desta distinção existir.
enum LeagueFormat: String, CaseIterable, Identifiable {
    case club, challenge

    var id: String { rawValue }

    var name: String {
        switch self {
        case .club: "Clube"
        case .challenge: "Desafio"
        }
    }

    var detail: String {
        switch self {
        case .club: "Grupo permanente, com rankings da semana e do mês."
        case .challenge: "Competição com data para começar, acabar e coroar um vencedor."
        }
    }
}

enum LeagueActivityRuleMode: String, CaseIterable, Identifiable {
    case all, only, except

    var id: String { rawValue }

    var name: String {
        switch self {
        case .all: "Todos"
        case .only: "Somente estes"
        case .except: "Todos, exceto:"
        }
    }
}

/// Regra persistida como `modo:ids`, por exemplo `only:1,2`. Vazia significa que todos valem.
struct LeagueActivityRule: Hashable {
    var mode: LeagueActivityRuleMode = .all
    var workoutTypeIDs: Set<UInt> = []

    init(mode: LeagueActivityRuleMode = .all, workoutTypeIDs: Set<UInt> = []) {
        self.mode = mode
        self.workoutTypeIDs = workoutTypeIDs
    }

    init(rawValue: String) {
        let parts = rawValue.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let mode = LeagueActivityRuleMode(rawValue: String(parts[0])) else { return }
        self.mode = mode
        workoutTypeIDs = Set(parts[1].split(separator: ",").compactMap { UInt($0) })
    }

    var rawValue: String {
        guard mode != .all else { return "" }
        return mode.rawValue + ":" + workoutTypeIDs.sorted().map(String.init).joined(separator: ",")
    }

    func accepts(_ workoutTypeID: UInt?) -> Bool {
        guard let workoutTypeID else { return true }
        return switch mode {
        case .all: true
        case .only: workoutTypeIDs.contains(workoutTypeID)
        case .except: !workoutTypeIDs.contains(workoutTypeID)
        }
    }

    var detail: String {
        switch mode {
        case .all: "Qualquer treino vale pontos."
        case .only: workoutTypeIDs.isEmpty ? "Escolha pelo menos um treino que vale pontos." : "Só os \(workoutTypeIDs.count) treino(s) selecionados valem pontos."
        case .except: workoutTypeIDs.isEmpty ? "Nenhum treino foi excluído." : "Os \(workoutTypeIDs.count) treino(s) selecionados não valem pontos."
        }
    }
}

/// O que um check-in precisa para virar pontos em qualquer modo
struct ScoreInput {
    var kind: ActivityKind
    var minutes: Int
    var effort: Int
    /// Distância do GPS do app, quando houver
    var meters: Double? = nil
    /// Calorias informadas no check-in; sem elas, estima com o peso de referência
    var kcal: Double? = nil
    /// Tipo específico do catálogo do Apple Saúde, quando conhecido (ex.: bike, skate ou musculação).
    var workoutTypeID: UInt? = nil
}

extension Activity {
    /// Importada do Apple Saúde: kcal, distância e o esforço derivado delas não saem do aparelho (guideline 5.1.3).
    /// Só o `healthUUID` marca a origem: o tipo exato (`healthType`) também é gravado nas atividades do app.
    var isFromHealth: Bool { healthUUID != nil }
    /// Gravada no Apple Watch: kcal e distância vêm dos sensores (HealthKit do relógio), mesmo sem treino importado.
    /// O esforço não: é o que a pessoa escolheu no relógio.
    var isWatchMeasured: Bool { source == "Apple Watch" }
    /// Esforço que pode ser publicado: o do Saúde vem das kcal de lá, então sobe o neutro
    var publishableEffort: Int { isFromHealth ? 5 : effort }
    /// Distância que pode ser publicada (só a do GPS do app)
    var publishableMeters: Double? { isFromHealth || isWatchMeasured ? nil : meters }
    /// Calorias que podem ser publicadas: nenhuma do Apple Saúde. No app, `kcal` só vem de lá (importação, relógio, ou o
    /// treino guiado gravado também no relógio, que ganha `healthWrittenUUID` e as kcal do relógio)
    var publishableKcal: Double? { isFromHealth || isWatchMeasured || healthWrittenUUID != nil ? nil : kcal }

    /// Mesmos dados que os outros participantes recebem, para o placar ser igual em todos os aparelhos
    var scoreInput: ScoreInput {
        ScoreInput(kind: kind, minutes: minutes, effort: publishableEffort, meters: publishableMeters, kcal: publishableKcal,
                   workoutTypeID: workoutType.id)
    }
}

enum LeagueScoring: String, CaseIterable, Identifiable, Codable {
    case pontos, treinos, dias, minutos, distancia, calorias, atividades

    var id: String { rawValue }

    var name: String {
        switch self {
        case .pontos: "Pontos"
        case .treinos: "Treinos"
        case .dias: "Dias ativos"
        case .atividades: "Por atividade"
        case .minutos: "Minutos"
        case .distancia: "Distância"
        case .calorias: "Calorias"
        }
    }

    var detail: String {
        switch self {
        case .pontos: "Cada check-in vale o XP da atividade: duração × tipo × esforço. Justo entre corrida, musculação, yoga…"
        case .treinos: "Cada check-in vale 1. Ganha quem treina mais vezes."
        case .dias: "Cada dia com pelo menos um check-in vale 1: dois treinos no mesmo dia contam um dia só."
        case .atividades: "Você monta a tabela: cada tipo de treino vale pontos por vez ou por quantidade (minutos, km, kcal), e pode até tirar pontos. Treino fora da tabela vale 0."
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
            // Na ordem fixa dos atributos: somar na ordem de um Dictionary (que muda a cada execução) podia mudar o último bit
            // e, na borda do arredondamento, o placar (ND-9). A mesma ordem do app Android.
            let factor = Attribute.allCases.reduce(0.0) { acc, a in i.kind.weights[a].map { acc + $0 * (weights[a] ?? 1) } ?? acc }
            return Int((Double(xp) * factor).rounded())
        case .treinos, .dias: return 1
        // Vem da tabela da liga (League.score)
        case .atividades: return 0
        case .minutos: return min(i.minutes, Game.maxMinutes)
        case .distancia: return Int(i.meters ?? 0)
        case .calorias:
            let kcal = i.kcal ?? HealthSync.activeKcal(kind: i.kind, minutes: i.minutes, effort: i.effort, weight: Self.referenceWeight)
            return Int(kcal.rounded())
        }
    }

    /// Placar com unidade: "120 pts", "3 treinos", "1 h 20 min", "12,4 km", "830 kcal". `count` decide o plural (padrão: `v`).
    func format(_ v: Int, count: Int? = nil) -> String {
        switch self {
        case .pontos, .atividades: "\(v) pts"
        case .treinos: "\(v) treino\((count ?? v) == 1 ? "" : "s")"
        case .dias: "\(v) dia\((count ?? v) == 1 ? "" : "s")"
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

    func since(now: Date = .now, calendar: Calendar = League.rulesCalendar) -> Date? {
        switch self {
        case .liga: nil
        case .semana: calendar.dateInterval(of: .weekOfYear, for: now)?.start
        case .mes: calendar.dateInterval(of: .month, for: now)?.start
        }
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
        let cal = League.rulesCalendar
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
        l.activityRuleRaw = old.activityRuleRaw
        l.settingsRaw = old.settingsRaw
        l.swissRaw = old.swissRaw
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

    var input: ScoreInput { ScoreInput(kind: kind, minutes: minutes, effort: effort, meters: meters, workoutTypeID: WorkoutType.of(kind).id) }
}

enum MockLeague {
    static let name = "Liga dos Bros"
    static let code = "AMIGOS"

    /// Quem pede para entrar na liga de exemplo quando a aprovação está ligada (simulados)
    static let requesters = [
        RemoteMember(id: "paula", name: "Paula", formID: MonsterForm(stage: .rookie, attribute: nil, species: "gato").id),
        RemoteMember(id: "teo", name: "Téo", formID: MonsterForm.egg.id),
    ]

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
    var score: Int
    var photo: Data?
    var place: String? = nil
    var hasPhoto = false
    var effort = 5
    var teamID: String? = nil
    /// Modo da liga, para o placar com unidade; nil = post do perfil (vale XP)
    var scoring: LeagueScoring? = nil
    /// Esperando o dono aprovar: aparece no feed, mas ainda não pontua
    var pending = false
    var proof = CheckInProof()
    /// Pontos cortados pelo teto da liga
    var capped = 0
    /// Liga do check-in (nil = perfil)
    var leagueID: UUID?
    /// Post de amigo vindo de uma liga pública em que você não está ("🔥 Liga"); nil = perfil
    var postedIn: String?
    /// Fotos a mais do post (a primeira é `photo`)
    var extraPhotos: [Data] = []
    /// Quem pode ver os comentários deste post (a regra do servidor confere pela liga)
    var comments = CommentScope.profile
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
    /// Pontos suíços das rodadas encerradas; nil = nenhuma rodada encerrada ainda
    var swiss: Double?
    /// Bônus das rodadas suíças que entrou no placar da janela
    var bonus = 0
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
    var score: Int
    let members: Int
    /// Bro do time: cresce com a média de XP dos membros e evolui pelo atributo que o time mais treina
    let form: MonsterForm
    let progress: Double
}

@MainActor
enum LeagueBoard {
    static func feed(league: League, mine: [LeagueCheckIn], activities: [UUID: Activity], me: String, myAvatar: MonsterForm,
                     remote: RemoteLeague? = nil, reviews: [CheckInReview]? = nil) -> [FeedItem] {
        let remote = (remote ?? LeagueRemoteStore.shared.remote(league)).applying(league)
        let settings = league.settings
        var items: [FeedItem] = mine.compactMap { c in
            guard let a = activities[c.activityUUID], c.reviewRaw != ReviewState.denied else { return nil }
            // Atividades do mesmo dia agrupadas neste check-in somam junto
            let extra = c.proof.grouped.compactMap { activities[$0] }
            var f = FeedItem(id: c.uuid.uuidString, memberID: "me", name: me, avatar: myAvatar, isMe: true, date: c.date, title: c.title, note: c.note,
                             kind: a.kind, minutes: a.minutes + extra.reduce(0) { $0 + $1.minutes },
                             score: league.score([a.scoreInput] + extra.map(\.scoreInput), hasPhoto: c.hasPhoto), photo: c.photo,
                             place: c.place, hasPhoto: c.hasPhoto, effort: a.effort, teamID: league.myTeamID, scoring: league.scoring)
            f.pending = settings.reviewRequired && c.reviewRaw == ReviewState.pending
            f.proof = c.proof
            f.leagueID = league.uuid
            f.comments = CommentScope(league: league, owner: "me")
            f.extraPhotos = Array(c.photos.dropFirst())
            return f
        }
        // Decisões do dono sobre os check-ins dos outros (as que vieram do servidor e as tomadas aqui)
        let decided = Dictionary((reviews ?? Self.reviews(league)).map { ($0.itemID, $0.approved) }, uniquingKeysWith: { _, b in b })
        items += remote.checkIns.compactMap { r in
            guard let m = remote.member(r.memberID), decided[r.id] != false else { return nil }
            let extra = r.proof?.groupedParts ?? []
            var f = FeedItem(id: r.id, memberID: m.id, name: m.name, avatar: m.form, isMe: false, date: r.date, title: r.title, note: r.note,
                             kind: r.kind, minutes: r.minutes + extra.reduce(0) { $0 + $1.minutes },
                             score: league.score([r.input] + extra.map(\.input), hasPhoto: r.hasPhoto), photo: nil,
                             place: r.place, hasPhoto: r.hasPhoto, effort: r.effort, teamID: m.teamID, scoring: league.scoring)
            f.proof = r.proof ?? CheckInProof()
            f.leagueID = league.uuid
            f.comments = CommentScope(league: league, owner: m.id)
            // Check-in de antes da revisão ser ligada já valia
            f.pending = settings.reviewRequired && decided[r.id] == nil && r.date >= (settings.reviewSince ?? .distantPast)
            return f
        }
        for i in items.indices where items[i].pending { items[i].score = 0 }
        // Dias ativos: só o primeiro check-in de cada pessoa em cada dia vale
        if league.scoring == .dias {
            let cal = League.rulesCalendar
            var seen = Set<String>()
            for i in items.indices.sorted(by: { items[$0].date < items[$1].date }) where items[i].score > 0 {
                let k = "\(items[i].memberID)|\(cal.startOfDay(for: items[i].date).timeIntervalSince1970)"
                if !seen.insert(k).inserted { items[i].score = 0 }
            }
        }
        // Teto por pessoa, dentro do período da liga
        if settings.limits.individual.values.contains(where: { $0 > 0 }) {
            let inLeague = items.filter { $0.date >= league.start && $0.date <= (league.end ?? .distantFuture) }
            let cut = ScoringLimits.apply(settings.limits.individual, to: inLeague, group: { $0.memberID }, calendar: settings.calendar())
            for i in items.indices { if let c = cut[items[i].id] { items[i].score -= c; items[i].capped = c } }
        }
        return items.sorted { $0.date > $1.date }
    }

    /// Decisões de revisão gravadas para a liga
    static func reviews(_ league: League) -> [CheckInReview] {
        let id = league.uuid
        return (try? league.modelContext?.fetch(FetchDescriptor<CheckInReview>(predicate: #Predicate { $0.leagueUUID == id }))) ?? []
    }

    /// Placar dos times: soma do placar de cada membro na janela, com o teto por time da liga
    static func teams(league: League, ranking: [RankRow], feed: [FeedItem], remote: RemoteLeague? = nil, since: Date? = nil) -> [TeamRow] {
        let remote = (remote ?? LeagueRemoteStore.shared.remote(league)).applying(league)
        let byMember = Dictionary(ranking.map { ($0.id, $0.score) }, uniquingKeysWith: +)
        let inLeague = feed.filter { $0.date >= league.start && $0.date <= (league.end ?? .distantFuture) }
        let caps = league.settings.limits.team
        // Corte do teto: do mais antigo para o mais novo, por time; só o que caiu na janela sai do placar dela
        let cut = ScoringLimits.apply(caps, to: inLeague, group: { $0.teamID }, calendar: league.settings.calendar())
        let cutInWindow = Dictionary(inLeague.filter { f in since.map { f.date >= $0 } ?? true }.compactMap { f in
            cut[f.id].flatMap { c in f.teamID.map { ($0, c) } }
        }, uniquingKeysWith: +)
        return remote.teams.map { t in
            let ids = t.memberIDs + (league.myTeamID == t.id ? ["me"] : [])
            let (form, progress) = teamBro(ids.map { id in inLeague.filter { $0.memberID == id } })
            let total = ids.reduce(0) { $0 + (byMember[$1] ?? 0) } - (cutInWindow[t.id] ?? 0)
            return TeamRow(id: t.id, name: t.name, isMine: league.myTeamID == t.id, score: total,
                           members: ids.count, form: form, progress: progress)
        }
        // Empate: pelo id do time, igual em todo aparelho
        .sorted { $0.score != $1.score ? $0.score > $1.score : $0.id < $1.id }
    }

    /// Média do XP de cada membro (time grande não leva vantagem) e atributos somados
    private static func teamBro(_ members: [[FeedItem]]) -> (MonsterForm, Double) {
        guard !members.isEmpty else { return (.egg, 0) }
        var attrs: [Attribute: Double] = [:]
        var xp = 0
        for items in members {
            let s = Game.snapshot(items.map { ActivityRecord(id: UUID(), kind: $0.kind, date: $0.date, minutes: $0.minutes, effort: $0.effort) },
                                   calendar: League.rulesCalendar)
            xp += s.totalXP
            attrs.merge(s.lifetimeAttributes, uniquingKeysWith: +)
        }
        let avg = xp / members.count
        let stage = Stage.allCases.last { avg >= $0.threshold } ?? .egg
        let progress = stage.next.map { min(max(Double(avg - stage.threshold) / Double($0.threshold - stage.threshold), 0), 1) } ?? 1
        guard stage.branches, !attrs.isEmpty else { return (MonsterForm(stage: stage, attribute: nil), progress) }
        let (a, b) = Game.branch(attrs)
        let f = MonsterForm(stage: stage, attribute: a, attribute2: b)
        return (f.resolved, progress)
    }

    /// Seu id no servidor (o mesmo que os outros aparelhos veem), para o pareamento suíço ser igual em todos
    static var selfID: String { Backend.myID ?? "me" }

    /// Rodadas suíças da liga, derivadas do feed e dos membros
    static func swiss(league: League, feed: [FeedItem], remote: RemoteLeague? = nil, now: Date = .now) -> SwissTable {
        let remote = (remote ?? LeagueRemoteStore.shared.remote(league)).applying(league)
        let cal = Swiss.calendar
        var tallies: [Date: [String: SwissTally]] = [:]
        for f in feed where f.date >= league.start && f.date <= (league.end ?? .distantFuture) && f.date <= now {
            let day = cal.startOfDay(for: f.date)
            var t = tallies[day]?[f.memberID] ?? SwissTally()
            t.score += f.score
            if league.photoRule.apply(1, hasPhoto: f.hasPhoto) > 0 { t.checkIns += 1 }
            tallies[day, default: [:]][f.memberID] = t
        }
        var joined = ["me": league.swissJoinedAt]
        for m in remote.members { joined[m.id] = m.joinedAt }
        return Swiss.table(members: ["me"] + remote.members.map(\.id), tallies: tallies, start: league.start, end: league.end, now: now,
                           seed: league.code.isEmpty ? league.uuid.uuidString : league.code, criterion: league.swiss,
                           identity: ["me": selfID], joined: joined, calendar: cal)
    }

    /// `until` fecha a janela (campeões de semanas, meses e anos que já acabaram)
    static func ranking(feed: [FeedItem], league: League, me: String, myAvatar: MonsterForm, since: Date?, until: Date? = nil,
                        remote: RemoteLeague? = nil, swiss: SwissTable? = nil) -> [RankRow] {
        let remote = (remote ?? LeagueRemoteStore.shared.remote(league)).applying(league)
        let swiss = swiss ?? Self.swiss(league: league, feed: feed, remote: remote)
        var rows: [String: RankRow] = [:]
        var days: [String: Set<Date>] = [:]
        // Todo mundo aparece, mesmo zerado
        rows["me"] = RankRow(id: "me", name: me, avatar: myAvatar, isMe: true)
        for m in remote.members { rows[m.id] = RankRow(id: m.id, name: m.name, avatar: m.form, isMe: false) }
        let cal = League.rulesCalendar
        // Do mais antigo para o mais novo: o último check-in que pontuou é quando a pessoa chegou ao placar
        // Check-in esperando revisão ainda não conta, nem como check-in
        for f in feed.reversed() where !f.pending && (since.map { f.date >= $0 } ?? true) && (until.map { f.date < $0 } ?? true)
            && f.date >= league.start && f.date <= (league.end ?? .distantFuture) {
            var r = rows[f.memberID] ?? RankRow(id: f.memberID, name: f.name, avatar: f.avatar, isMe: f.isMe)
            r.score += f.score
            r.checkIns += 1
            if f.score > 0 { r.reachedAt = f.date }
            rows[f.memberID] = r
            days[f.memberID, default: []].insert(cal.startOfDay(for: f.date))
        }
        for (id, d) in days { rows[id]?.bestStreak = Game.bestStreak(days: d, calendar: cal) }
        for (id, b) in swiss.bonuses(scoring: league.scoring, since: since, until: until, calendar: Swiss.calendar) {
            guard var r = rows[id] else { continue }
            r.score += b.total
            r.bonus = b.total
            r.reachedAt = max(r.reachedAt ?? .distantPast, b.last)
            rows[id] = r
        }
        for (id, p) in swiss.points { rows[id]?.swiss = p }
        // Último desempate pelo id global (o seu é o do servidor): "eu primeiro" punha cada um na frente no próprio aparelho
        let global = { (r: RankRow) in r.isMe ? selfID : r.id }
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
            return global(a) < global(b)
        }
        for i in sorted.indices where sorted[i].score > 0 {
            sorted[i].tied = (i > 0 && sorted[i - 1].score == sorted[i].score) || (i < sorted.count - 1 && sorted[i + 1].score == sorted[i].score)
        }
        return sorted
    }
}
