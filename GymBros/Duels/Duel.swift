import Foundation

// X1: desafio direto entre dois amigos do GymBros (só amigos: quem não é amigo não desafia nem é desafiado).
// Não tem relação com ligas: não depende de liga, não usa a métrica nem o feed de nenhuma liga e não mexe em placar,
// pontos nem rodada suíça. Quem desafia escolhe a métrica; aceito, vale tudo o que cada um registrar nas 24 h seguintes
// ao aceite (qualquer atividade, inclusive as do Apple Saúde). Cada aparelho calcula o próprio valor das suas
// atividades e informa ao servidor; o do adversário vem do servidor.

enum DuelAnswer: String, Codable, Sendable {
    case accepted, declined
}

/// O que conta no X1
enum DuelMetric: String, Codable, CaseIterable, Identifiable, Sendable {
    case xp, treinos, minutos, distancia, calorias

    var id: String { rawValue }

    var name: String {
        switch self {
        case .xp: "XP"
        case .treinos: "Treinos"
        case .minutos: "Minutos"
        case .distancia: "Distância"
        case .calorias: "Calorias"
        }
    }

    var symbol: String {
        switch self {
        case .xp: "sparkles"
        case .treinos: "checkmark.circle.fill"
        case .minutos: "timer"
        case .distancia: "figure.run"
        case .calorias: "flame.fill"
        }
    }

    /// Uma linha, no cartão da métrica
    var hint: String {
        switch self {
        case .xp: "Justo entre modalidades"
        case .treinos: "Cada atividade vale 1"
        case .minutos: "Tempo de treino"
        case .distancia: "Corrida, bike, natação"
        case .calorias: "Do Saúde ou estimadas"
        }
    }

    var detail: String {
        switch self {
        case .xp: "XP de cada atividade (duração × tipo × esforço): justo entre corrida, musculação, yoga…"
        case .treinos: "Cada atividade registrada vale 1."
        case .minutos: "Soma do tempo de treino."
        case .distancia: "Soma dos quilômetros (corrida, caminhada, bike, natação)."
        case .calorias: "Soma das calorias (do Saúde ou estimadas)."
        }
    }

    /// Valor de uma atividade nesta métrica
    func value(kind: ActivityKind, minutes: Int, effort: Int, meters: Double?, kcal: Double?) -> Int {
        switch self {
        case .xp: Game.xp(kind: kind, minutes: minutes, effort: effort)
        case .treinos: 1
        case .minutos: minutes
        case .distancia: Int(meters ?? 0)
        case .calorias: Int(kcal ?? Double(minutes) * kind.met * 1.2)
        }
    }

    func format(_ v: Int, count: Int? = nil) -> String {
        switch self {
        case .xp: "\(v) XP"
        case .treinos: "\(v) treino\((count ?? v) == 1 ? "" : "s")"
        case .minutos: durationText(v)
        case .distancia: Self.km(v)
        case .calorias: "\(v) kcal"
        }
    }

    /// Só o número, para o placar
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

/// Uma pessoa do X1 (nome e bro como estavam no servidor)
struct DuelPerson: Codable, Hashable, Identifiable, Sendable {
    let id: String
    var name: String
    var formID: String

    var form: MonsterForm { MonsterForm.byID(formID) ?? .egg }
}

/// Desafio como o servidor guarda (o seu id vira "me" no aparelho)
struct RemoteDuel: Codable, Hashable, Identifiable, Sendable {
    let id: String
    var challenger: DuelPerson
    var challenged: DuelPerson
    let metric: DuelMetric
    let createdAt: Date
    var answer: DuelAnswer?
    var answeredAt: Date?
    /// Valor que cada lado informou (id da pessoa → valor na métrica)
    var reported: [String: Int] = [:]

    func involves(_ id: String) -> Bool { challenger.id == id || challenged.id == id }

    func isPair(_ a: String, _ b: String) -> Bool { involves(a) && involves(b) && a != b }

    func opponent(of id: String) -> DuelPerson { challenger.id == id ? challenged : challenger }
    func side(of id: String) -> DuelPerson { challenger.id == id ? challenger : challenged }

    var acceptedAt: Date? { answer == .accepted ? answeredAt : nil }

    var endsAt: Date? { acceptedAt.map { $0.addingTimeInterval(Duels.window) } }

    var expiresAt: Date { createdAt.addingTimeInterval(Duels.window) }

    func phase(now: Date) -> DuelPhase {
        switch answer {
        case .declined: return .declined
        case .accepted:
            guard let end = endsAt else { return .declined }
            return now < end ? .active(ends: end) : .finished(ended: end)
        case nil:
            return now < expiresAt ? .pending(expires: expiresAt) : .expired
        }
    }

    func isPending(now: Date) -> Bool { answer == nil && now < expiresAt }

    /// Pendente dentro do prazo ou em andamento: bloqueia outro X1 entre o mesmo par
    func isOpen(now: Date) -> Bool {
        switch phase(now: now) {
        case .pending, .active: true
        default: false
        }
    }
}

enum DuelPhase: Equatable, Sendable {
    case pending(expires: Date)
    case expired
    case declined
    case active(ends: Date)
    case finished(ended: Date)
}

/// Por que não dá para desafiar ou aceitar
enum DuelRefusal: LocalizedError, Equatable, Sendable {
    case yourself, notFound, blocked, alreadyOpen, notPending, notYours
    /// Só ovos na coleção: ovo não entra no X1
    case noHatchedBro
    /// X1 só entre amigos
    case notFriend
    /// Cada bro luta um X1 por vez
    case fighterBusy, allFightersBusy

    var errorDescription: String? {
        switch self {
        case .yourself: "Não dá para desafiar você mesmo."
        case .notFound: "Não achamos essa pessoa."
        case .blocked: "Não dá para desafiar essa pessoa."
        case .alreadyOpen: "Vocês já têm um X1 aberto."
        case .notPending: "Esse desafio não está mais aberto."
        case .notYours: "Esse desafio não é para você."
        case .noHatchedBro: "Ovos não entram no X1. Choque um ovo (no principal ou numa liga) para lutar."
        case .notFriend: "X1 é só entre amigos. Adicione a pessoa como amiga para desafiar."
        case .fighterBusy: "Esse bro já está num X1. Cada bro luta um X1 por vez."
        case .allFightersBusy: "Todos os seus bros já estão em X1. Cada bro luta um X1 por vez: choque mais ovos para lutar mais."
        }
    }
}

enum DuelResult: String, Sendable {
    case vitoria, empate, derrota

    var letter: String {
        switch self {
        case .vitoria: "V"
        case .empate: "E"
        case .derrota: "D"
        }
    }
}

struct DuelScore: Equatable, Sendable {
    var mine = 0
    var theirs = 0

    var result: DuelResult { mine == theirs ? .empate : mine > theirs ? .vitoria : .derrota }
}

/// Atividade como o X1 enxerga (só o que entra na conta)
struct DuelActivity: Sendable {
    let date: Date
    let kind: ActivityKind
    let minutes: Int
    let effort: Int
    var meters: Double?
    var kcal: Double?
}

extension Activity {
    /// Só o que pode sair do aparelho, como nas ligas: o valor vai ao servidor, e kcal, distância e esforço do Apple Saúde
    /// não podem (guideline 5.1.3). Atividade do Saúde conta com esforço neutro, sem distância e com kcal estimadas.
    var duelActivity: DuelActivity {
        DuelActivity(date: date, kind: kind, minutes: minutes, effort: publishableEffort, meters: publishableMeters, kcal: publishableKcal)
    }
}

enum Duels {
    static let window: TimeInterval = 24 * 60 * 60

    /// Motivo para não poder desafiar `opponent` agora; nil = pode
    static func refusal(me: String, opponent: String, duels: [RemoteDuel], blocked: Set<String>, blockedBy: Set<String>, now: Date) -> DuelRefusal? {
        if opponent == me { return .yourself }
        if blocked.contains(opponent) || blockedBy.contains(opponent) { return .blocked }
        if duels.contains(where: { $0.isPair(me, opponent) && $0.isOpen(now: now) }) { return .alreadyOpen }
        return nil
    }

    /// Motivo para não poder aceitar; nil = pode. Recusar sempre pode enquanto estiver pendente.
    static func acceptRefusal(_ duel: RemoteDuel, me: String, duels: [RemoteDuel], blocked: Set<String>, now: Date) -> DuelRefusal? {
        guard duel.challenged.id == me else { return .notYours }
        guard case .pending = duel.phase(now: now) else { return .notPending }
        if blocked.contains(duel.challenger.id) { return .blocked }
        // Outro X1 aberto do par: um já aceito, ou um pendente mais antigo (desafios cruzados quase juntos: vale o primeiro)
        let other = duels.contains {
            $0.id != duel.id && $0.isPair(me, duel.challenger.id) && $0.isOpen(now: now)
                && ($0.acceptedAt != nil || ($0.createdAt, $0.id) < (duel.createdAt, duel.id))
        }
        return other ? .alreadyOpen : nil
    }

    /// Bros ocupados: cada um luta um X1 por vez. Ocupa quem está num X1 valendo ou num desafio seu ainda sem resposta.
    static func busyFighters(_ duels: [RemoteDuel], representatives: [String: String], me: String = "me", now: Date) -> Set<String> {
        Set(duels.filter { $0.isOpen(now: now) && ($0.acceptedAt != nil || $0.challenger.id == me) }.compactMap { representatives[$0.id] })
    }

    /// Seu valor na janela de 24 h depois do aceite (até agora), com as suas atividades
    static func myValue(_ duel: RemoteDuel, activities: [DuelActivity], now: Date) -> Int {
        guard let start = duel.acceptedAt, let end = duel.endsAt else { return 0 }
        let limit = min(end, now)
        return activities.filter { $0.date >= start && $0.date < end && $0.date <= limit }
            .reduce(0) { $0 + duel.metric.value(kind: $1.kind, minutes: $1.minutes, effort: $1.effort, meters: $1.meters, kcal: $1.kcal) }
    }

    /// Placar: o seu calculado aqui, o do adversário como ele informou
    static func score(_ duel: RemoteDuel, me: String = "me", activities: [DuelActivity], now: Date) -> DuelScore {
        DuelScore(mine: myValue(duel, activities: activities, now: now), theirs: duel.reported[duel.opponent(of: me).id] ?? 0)
    }

    /// Intervalo para buscar respostas: curto só logo depois de você desafiar, quando a resposta pode chegar em segundos
    static func refreshInterval(_ duels: [RemoteDuel], me: String = "me", now: Date) -> TimeInterval {
        let fresh = duels.contains { $0.challenger.id == me && $0.isPending(now: now) && now.timeIntervalSince($0.createdAt) < fastWindow }
        return fresh ? 3 : 30
    }

    static let fastWindow: TimeInterval = 2 * 60

    /// "Você venceu Bruno no X1 · 3 a 1 treinos"
    static func summary(_ score: DuelScore, opponent: String, metric: DuelMetric) -> String {
        let verb = switch score.result {
        case .vitoria: "Você venceu \(opponent)"
        case .derrota: "Você perdeu para \(opponent)"
        case .empate: "Você empatou com \(opponent)"
        }
        return "\(verb) no X1 · \(metric.short(score.mine)) a \(metric.format(score.theirs, count: max(score.mine, score.theirs)))"
    }

    /// X1 seus que já acabaram, do mais recente para o mais antigo
    static func records(_ duels: [RemoteDuel], me: String = "me", activities: [DuelActivity], now: Date) -> [DuelRecord] {
        duels.compactMap { d -> DuelRecord? in
            guard d.involves(me), case let .finished(ended) = d.phase(now: now) else { return nil }
            return DuelRecord(id: d.id, opponent: d.opponent(of: me), ended: ended, score: score(d, me: me, activities: activities, now: now),
                              metric: d.metric)
        }
        .sorted { $0.ended > $1.ended }
    }

    /// Vitórias, empates e derrotas
    static func tally(_ records: [DuelRecord]) -> (v: Int, e: Int, d: Int) {
        records.reduce(into: (0, 0, 0)) { t, r in
            switch r.score.result {
            case .vitoria: t.0 += 1
            case .empate: t.1 += 1
            case .derrota: t.2 += 1
            }
        }
    }
}

/// X1 encerrado
struct DuelRecord: Identifiable, Equatable {
    let id: String
    let opponent: DuelPerson
    let ended: Date
    let score: DuelScore
    let metric: DuelMetric

    var text: String { Duels.summary(score, opponent: opponent.name, metric: metric) }
}
