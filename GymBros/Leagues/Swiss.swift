import Foundation

// Rodada suíça diária: todo dia cada membro da liga enfrenta alguém com pontuação suíça parecida.
// Tudo é derivado do feed e dos membros, de forma determinística, para todos os aparelhos chegarem
// ao mesmo pareamento. Só rodadas de dias encerrados contam pontos suíços e dão bônus no placar.

/// Como se decide o confronto do dia
enum SwissCriterion: String, CaseIterable, Identifiable, Codable {
    case pontos, checkins, presenca

    var id: String { rawValue }

    var name: String {
        switch self {
        case .pontos: "Mais pontos no dia"
        case .checkins: "Mais check-ins no dia"
        case .presenca: "Presença"
        }
    }

    var detail: String {
        switch self {
        case .pontos: "Vence quem somar mais na liga no dia."
        case .checkins: "Vence quem fizer mais check-ins válidos no dia."
        case .presenca: "Treinou e o outro não: vitória. Os dois treinaram: empate."
        }
    }

    func value(_ t: SwissTally) -> Int {
        switch self {
        case .pontos: t.score
        case .checkins: t.checkIns
        case .presenca: t.trained ? 1 : 0
        }
    }

    /// Pontos suíços de cada lado: ninguém treinou = 0 para os dois; empate = ½ para cada
    func result(_ a: SwissTally, _ b: SwissTally) -> (Double, Double) {
        guard a.trained || b.trained else { return (0, 0) }
        let va = value(a), vb = value(b)
        if va == vb { return (0.5, 0.5) }
        return va > vb ? (1, 0) : (0, 1)
    }
}

/// O que uma pessoa fez num dia da liga
struct SwissTally: Hashable, Sendable {
    var score = 0
    /// Check-ins que valem pela regra de foto
    var checkIns = 0

    var trained: Bool { checkIns > 0 }
}

enum SwissResult: String, Sendable {
    case vitoria, empate, derrota, folga

    var letter: String {
        switch self {
        case .vitoria: "V"
        case .empate: "E"
        case .derrota: "D"
        case .folga: "F"
        }
    }

    var name: String {
        switch self {
        case .vitoria: "Vitória"
        case .empate: "Empate"
        case .derrota: "Derrota"
        case .folga: "Folga"
        }
    }
}

struct SwissMatch: Hashable, Sendable {
    let a: String
    /// nil = folga
    let b: String?
    var tallyA = SwissTally()
    var tallyB = SwissTally()
    var pointsA = 0.0
    var pointsB = 0.0

    var isBye: Bool { b == nil }

    func involves(_ id: String) -> Bool { a == id || b == id }

    func opponent(of id: String) -> String? { a == id ? b : a }

    func points(of id: String) -> Double { a == id ? pointsA : pointsB }

    func tally(of id: String) -> SwissTally { a == id ? tallyA : tallyB }

    func opponentTally(of id: String) -> SwissTally { a == id ? tallyB : tallyA }

    func result(of id: String) -> SwissResult {
        if isBye { return .folga }
        let mine = points(of: id), theirs = a == id ? pointsB : pointsA
        if mine == theirs { return mine > 0 ? .empate : .derrota }
        return mine > theirs ? .vitoria : .derrota
    }
}

struct SwissRound: Sendable {
    let day: Date
    let matches: [SwissMatch]
    /// O dia já acabou: o resultado vale pontos suíços e bônus
    let finished: Bool

    func match(of id: String) -> SwissMatch? { matches.first { $0.involves(id) } }
}

/// Bônus no placar da liga, em unidades da métrica. Folga vale como vitória.
enum SwissBonus {
    static let table: [LeagueScoring: (win: Int, draw: Int)] = [
        .pontos: (10, 5),
        .minutos: (5, 2),
        .distancia: (500, 250),
        .calorias: (50, 25),
        .treinos: (1, 0),
        .dias: (1, 0),
        .atividades: (10, 5),
    ]

    static func value(_ result: SwissResult, scoring: LeagueScoring) -> Int {
        let b = table[scoring] ?? (0, 0)
        switch result {
        case .vitoria, .folga: return b.win
        case .empate: return b.draw
        case .derrota: return 0
        }
    }
}

struct SwissTable: Sendable {
    var rounds: [SwissRound] = []

    static let empty = SwissTable()

    /// Pontos suíços acumulados nas rodadas encerradas
    var points: [String: Double] {
        rounds.filter(\.finished).reduce(into: [:]) { acc, r in
            for m in r.matches {
                acc[m.a, default: 0] += m.isBye ? 1 : m.pointsA
                if let b = m.b { acc[b, default: 0] += m.pointsB }
            }
        }
    }

    /// Rodada de hoje, ainda em andamento
    var today: SwissRound? { rounds.last.flatMap { $0.finished ? nil : $0 } }

    /// Rodadas encerradas de alguém, da mais recente para a mais antiga
    func history(of id: String, limit: Int = 7) -> [(day: Date, result: SwissResult)] {
        Array(rounds.reversed().lazy.filter(\.finished).compactMap { r in r.match(of: id).map { (r.day, $0.result(of: id)) } }.prefix(limit))
    }

    /// Bônus de cada um nas rodadas encerradas a partir de `since` (dia do confronto), com o fim do último dia que rendeu bônus
    func bonuses(scoring: LeagueScoring, since: Date? = nil, until: Date? = nil, calendar: Calendar = .current) -> [String: (total: Int, last: Date)] {
        var out: [String: (total: Int, last: Date)] = [:]
        for r in rounds where r.finished && (since.map { r.day >= calendar.startOfDay(for: $0) } ?? true) && (until.map { r.day < $0 } ?? true) {
            let end = calendar.date(byAdding: .second, value: -1, to: calendar.date(byAdding: .day, value: 1, to: r.day)!)!
            for m in r.matches {
                for id in [m.a] + (m.b.map { [$0] } ?? []) {
                    let v = SwissBonus.value(m.result(of: id), scoring: scoring)
                    guard v > 0 else { continue }
                    out[id] = ((out[id]?.total ?? 0) + v, end)
                }
            }
        }
        return out
    }
}

enum Swiss {
    /// Dia da rodada num fuso fixo (Brasília), não no do aparelho: quem está em outro fuso precisa chegar ao mesmo
    /// pareamento, e um check-in às 23h30 em Manaus cairia em dias diferentes em cada aparelho
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Sao_Paulo") ?? .current
        return c
    }()

    /// Todas as rodadas da liga, do primeiro dia até hoje (ou até o fim).
    /// `identity` troca ids locais pelos ids globais no desempate e no sorteio (ex.: "me" → seu id no servidor).
    /// `joined`: quando cada um entrou; só é pareado a partir desse dia (sem data = desde o início).
    static func table(members: [String], tallies: [Date: [String: SwissTally]], start: Date, end: Date?, now: Date, seed: String,
                      criterion: SwissCriterion, identity: [String: String] = [:], joined: [String: Date] = [:],
                      calendar: Calendar = .current) -> SwissTable {
        let players = Array(Set(members))
        guard players.count >= 2 else { return .empty }
        let key = { (id: String) in identity[id] ?? id }
        let today = calendar.startOfDay(for: now)
        let last = min(today, end.map { calendar.startOfDay(for: $0) } ?? today)
        var day = calendar.startOfDay(for: start)
        var points: [String: Double] = [:]
        var met: [String: [String: Int]] = [:]
        var byes: [String: Int] = [:]
        var rounds: [SwissRound] = []
        let firstDay = joined.mapValues { calendar.startOfDay(for: $0) }
        while day <= last {
            let active = players.filter { (firstDay[$0] ?? day) <= day }
            guard active.count >= 2 else {
                day = calendar.date(byAdding: .day, value: 1, to: day)!
                continue
            }
            let ranked: [String]
            if rounds.isEmpty {
                let stamp = dayStamp(day, calendar: calendar)
                let hash = Dictionary(uniqueKeysWithValues: active.map { id in
                    var r = SeededRandom(seed: "\(key(id))-\(seed)-\(stamp)")
                    return (id, r.next())
                })
                ranked = active.sorted { hash[$0]! != hash[$1]! ? hash[$0]! < hash[$1]! : key($0) < key($1) }
            } else {
                ranked = active.sorted { (points[$0] ?? 0) != (points[$1] ?? 0) ? (points[$0] ?? 0) > (points[$1] ?? 0) : key($0) < key($1) }
            }
            let (pairs, bye) = pair(ranked: ranked, met: met, byes: byes)
            let finished = day < today
            let dayTallies = tallies[day] ?? [:]
            var matches: [SwissMatch] = pairs.map { a, b in
                let ta = dayTallies[a] ?? SwissTally(), tb = dayTallies[b] ?? SwissTally()
                let (pa, pb) = criterion.result(ta, tb)
                return SwissMatch(a: a, b: b, tallyA: ta, tallyB: tb, pointsA: pa, pointsB: pb)
            }
            if let bye { matches.append(SwissMatch(a: bye, b: nil, tallyA: dayTallies[bye] ?? SwissTally(), pointsA: 1)) }
            rounds.append(SwissRound(day: day, matches: matches, finished: finished))
            if finished {
                for m in matches {
                    points[m.a, default: 0] += m.pointsA
                    if let b = m.b {
                        points[b, default: 0] += m.pointsB
                        met[m.a, default: [:]][b, default: 0] += 1
                        met[b, default: [:]][m.a, default: 0] += 1
                    } else {
                        byes[m.a, default: 0] += 1
                    }
                }
            }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return SwissTable(rounds: rounds)
    }

    /// Pareia na ordem do ranking (melhor primeiro). Com número ímpar, folga quem folgou menos, do fim da lista.
    /// Procura um pareamento sem revanche; se não houver, aceita a revanche com quem enfrentou menos vezes.
    static func pair(ranked: [String], met: [String: [String: Int]], byes: [String: Int]) -> (pairs: [(String, String)], bye: String?) {
        var list = ranked
        var bye: String?
        if list.count % 2 == 1 {
            let fewest = list.map { byes[$0] ?? 0 }.min() ?? 0
            if let i = list.lastIndex(where: { (byes[$0] ?? 0) == fewest }) { bye = list.remove(at: i) }
        }
        var budget = 5_000
        if let pairs = withoutRematch(list, met: met, budget: &budget) { return (pairs, bye) }
        return (fewestRematches(list, met: met), bye)
    }

    private static func withoutRematch(_ list: [String], met: [String: [String: Int]], budget: inout Int) -> [(String, String)]? {
        guard let first = list.first else { return [] }
        for j in list.indices.dropFirst() where (met[first]?[list[j]] ?? 0) == 0 {
            budget -= 1
            guard budget >= 0 else { return nil }
            var rest = list
            rest.remove(at: j)
            rest.removeFirst()
            if let tail = withoutRematch(rest, met: met, budget: &budget) { return [(first, list[j])] + tail }
        }
        return nil
    }

    private static func fewestRematches(_ list: [String], met: [String: [String: Int]]) -> [(String, String)] {
        var left = list
        var out: [(String, String)] = []
        while left.count >= 2 {
            let first = left.removeFirst()
            let j = left.indices.min { (met[first]?[left[$0]] ?? 0, $0) < (met[first]?[left[$1]] ?? 0, $1) }!
            out.append((first, left.remove(at: j)))
        }
        return out
    }

    /// "2026-10-18" no calendário da rodada (`Swiss.calendar`): igual em qualquer aparelho
    static func dayStamp(_ day: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    /// "4", "4,5"
    static func format(_ points: Double) -> String {
        points == points.rounded() ? "\(Int(points))" : String(format: "%.1f", points).replacingOccurrences(of: ".", with: ",")
    }
}

extension League {
    /// Calendário de todas as regras de liga (dias, semanas, tetos, campeões, temporadas): o mesmo fuso fixo da rodada
    /// suíça, para todo aparelho chegar ao mesmo placar, esteja onde estiver
    static var rulesCalendar: Calendar { Swiss.calendar }

    /// A partir de quando você entra na rodada suíça: quem criou a liga está nela desde o início
    var swissJoinedAt: Date { joined || isMock ? joinedAt : min(joinedAt, start) }
}
