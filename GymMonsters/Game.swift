import Foundation

// Regras do jogo. Tudo aqui é função pura do histórico de atividades: nada fica guardado
// além do log, então editar ou apagar uma atividade recalcula XP, nível e evolução na hora.

enum Attribute: String, CaseIterable, Codable, Identifiable {
    case forca, resistencia, agilidade, tecnica

    var id: String { rawValue }

    var name: String {
        switch self {
        case .forca: "Força"
        case .resistencia: "Resistência"
        case .agilidade: "Agilidade"
        case .tecnica: "Técnica"
        }
    }

    var symbol: String {
        switch self {
        case .forca: "dumbbell.fill"
        case .resistencia: "heart.fill"
        case .agilidade: "bolt.fill"
        case .tecnica: "sparkles"
        }
    }
}

enum ActivityKind: String, CaseIterable, Codable, Identifiable {
    case musculacao, crossfit, corrida, caminhada, bike, natacao, volei, futebol, lutas, danca, yoga, outro

    var id: String { rawValue }

    var name: String {
        switch self {
        case .musculacao: "Musculação"
        case .crossfit: "Crossfit"
        case .corrida: "Corrida"
        case .caminhada: "Caminhada"
        case .bike: "Bike"
        case .natacao: "Natação"
        case .volei: "Vôlei"
        case .futebol: "Futebol"
        case .lutas: "Lutas"
        case .danca: "Dança"
        case .yoga: "Yoga"
        case .outro: "Outro"
        }
    }

    var symbol: String {
        switch self {
        case .musculacao: "figure.strengthtraining.traditional"
        case .crossfit: "figure.cross.training"
        case .corrida: "figure.run"
        case .caminhada: "figure.walk"
        case .bike: "figure.outdoor.cycle"
        case .natacao: "figure.pool.swim"
        case .volei: "figure.volleyball"
        case .futebol: "figure.indoor.soccer"
        case .lutas: "figure.martial.arts"
        case .danca: "figure.dance"
        case .yoga: "figure.yoga"
        case .outro: "figure.mixed.cardio"
        }
    }

    /// Gasto energético típico (MET) em intensidade moderada
    var met: Double {
        switch self {
        case .musculacao: 5
        case .crossfit: 8
        case .corrida: 9.5
        case .caminhada: 3.5
        case .bike: 7
        case .natacao: 8
        case .volei: 5
        case .futebol: 7
        case .lutas: 9
        case .danca: 5
        case .yoga: 3
        case .outro: 5
        }
    }

    /// Para onde vai o XP da atividade (soma 1)
    var weights: [Attribute: Double] {
        switch self {
        case .musculacao: [.forca: 0.8, .tecnica: 0.2]
        case .crossfit: [.forca: 0.4, .resistencia: 0.4, .agilidade: 0.2]
        case .corrida: [.resistencia: 0.8, .agilidade: 0.2]
        case .caminhada: [.resistencia: 1]
        case .bike: [.resistencia: 0.8, .forca: 0.2]
        case .natacao: [.resistencia: 0.6, .tecnica: 0.4]
        case .volei: [.agilidade: 0.6, .tecnica: 0.4]
        case .futebol: [.agilidade: 0.5, .resistencia: 0.5]
        case .lutas: [.agilidade: 0.4, .tecnica: 0.3, .forca: 0.3]
        case .danca: [.agilidade: 0.5, .tecnica: 0.5]
        case .yoga: [.tecnica: 1]
        case .outro: [.forca: 0.25, .resistencia: 0.25, .agilidade: 0.25, .tecnica: 0.25]
        }
    }
}

enum Stage: Int, CaseIterable, Comparable {
    case egg, baby, rookie, champion, ultimate

    static func < (a: Stage, b: Stage) -> Bool { a.rawValue < b.rawValue }

    var name: String {
        switch self {
        case .egg: "Ovo"
        case .baby: "Bebê"
        case .rookie: "Rookie"
        case .champion: "Champion"
        case .ultimate: "Ultimate"
        }
    }

    /// XP total para chegar neste estágio
    var threshold: Int {
        switch self {
        case .egg: 0
        case .baby: 60
        case .rookie: 300
        case .champion: 1200
        case .ultimate: 3600
        }
    }

    var next: Stage? { Stage(rawValue: rawValue + 1) }
    /// Estágios em que o atributo dominante escolhe o galho
    var branches: Bool { self == .champion || self == .ultimate }
}

struct MonsterForm: Hashable, Identifiable {
    let stage: Stage
    let attribute: Attribute?

    var id: String { attribute.map { "\(stage)_\($0.rawValue)" } ?? "\(stage)" }

    static let egg = MonsterForm(stage: .egg, attribute: nil)

    static var all: [MonsterForm] {
        Stage.allCases.flatMap { s in
            s.branches ? Attribute.allCases.map { MonsterForm(stage: s, attribute: $0) } : [MonsterForm(stage: s, attribute: nil)]
        }
    }

    static func byID(_ id: String) -> MonsterForm? { all.first { $0.id == id } }

    var name: String {
        switch (stage, attribute) {
        case (.egg, _): "Ovo"
        case (.baby, _): "Gymmon"
        case (.rookie, _): "Cutemon"
        case (.champion, .forca): "Halteromon"
        case (.champion, .resistencia): "Maratomon"
        case (.champion, .agilidade): "Saltamon"
        case (.champion, _): "Zenmon"
        case (.ultimate, .forca): "Trebomon"
        case (.ultimate, .resistencia): "Fôlegomon"
        case (.ultimate, .agilidade): "Relampamon"
        case (.ultimate, _): "Mestremon"
        }
    }

    var sprite: String {
        switch stage {
        case .egg: "sprite_egg"
        case .baby: "sprite_baby"
        case .rookie: "sprite_rookie"
        case .champion, .ultimate: "sprite_\(stage)_\((attribute ?? .forca).rawValue)"
        }
    }

    /// Mantido para quem ainda usa (widget); todas as formas têm arte própria agora
    var hue: Double { 0 }
}

struct ActivityRecord: Identifiable {
    let id: UUID
    let kind: ActivityKind
    let date: Date
    let minutes: Int
    let effort: Int
}

struct Evolution: Identifiable {
    let date: Date
    let form: MonsterForm
    var id: String { form.id + "\(date.timeIntervalSince1970)" }
}

struct Snapshot {
    var totalXP = 0
    var form = MonsterForm.egg
    /// Atributos acumulados desde a última evolução: decidem o próximo galho
    var stageAttributes: [Attribute: Double] = [:]
    var lifetimeAttributes: [Attribute: Double] = [:]
    var evolutions: [Evolution] = []
    var xpByActivity: [UUID: Int] = [:]
    var streak = 0
    var bestStreak = 0
    var lastActivity: Date?
    var todayXP = 0

    var stage: Stage { form.stage }
    var level: Int { Game.level(for: totalXP) }

    var progress: Double {
        guard let next = stage.next else { return 1 }
        let span = Double(next.threshold - stage.threshold)
        return min(max(Double(totalXP - stage.threshold) / span, 0), 1)
    }

    var xpToNext: Int? { stage.next.map { max($0.threshold - totalXP, 0) } }

    /// Forma que viria se evoluísse agora
    var nextForm: MonsterForm? {
        guard let next = stage.next else { return nil }
        return MonsterForm(stage: next, attribute: next.branches ? Game.dominant(stageAttributes) : nil)
    }
}

enum Game {
    static let maxMinutes = 240
    /// Acima disso no mesmo dia o XP conta 1/3, até o teto diário
    static let dailySoftCap = 150
    static let dailyHardCap = 300

    static func xp(kind: ActivityKind, minutes: Int, effort: Int) -> Int {
        let m = Double(min(max(minutes, 0), maxMinutes))
        let intensity = 0.6 + 0.08 * Double(min(max(effort, 1), 10))  // esforço 5 = 1,0
        return max(Int((m * kind.met * intensity / 10).rounded()), minutes > 0 ? 1 : 0)
    }

    static func level(for xp: Int) -> Int { Int((Double(xp) / 5).squareRoot()) + 1 }

    static func dominant(_ attrs: [Attribute: Double]) -> Attribute {
        Attribute.allCases.max { (attrs[$0] ?? 0) < (attrs[$1] ?? 0) } ?? .forca
    }

    static func snapshot(_ records: [ActivityRecord], now: Date = .now, calendar: Calendar = .current) -> Snapshot {
        var s = Snapshot()
        var dayTotals: [Date: Int] = [:]
        var dayGained: [Date: Int] = [:]

        for r in records.sorted(by: { $0.date < $1.date }) {
            let raw = xp(kind: r.kind, minutes: r.minutes, effort: r.effort)
            let day = calendar.startOfDay(for: r.date)
            let before = dayTotals[day, default: 0]
            let full = max(min(raw, dailySoftCap - before), 0)
            let gainedBefore = dayGained[day, default: 0]
            let gained = min(full + (raw - full) / 3, max(dailyHardCap - gainedBefore, 0))
            dayTotals[day] = before + raw
            dayGained[day] = gainedBefore + gained
            s.xpByActivity[r.id] = gained
            s.totalXP += gained

            for (attr, w) in r.kind.weights {
                s.stageAttributes[attr, default: 0] += Double(gained) * w
                s.lifetimeAttributes[attr, default: 0] += Double(gained) * w
            }

            while let next = s.stage.next, s.totalXP >= next.threshold {
                s.form = MonsterForm(stage: next, attribute: next.branches ? dominant(s.stageAttributes) : nil)
                s.evolutions.append(Evolution(date: r.date, form: s.form))
                s.stageAttributes = [:]
            }
        }

        s.streak = streak(days: Set(dayTotals.keys), now: now, calendar: calendar)
        s.bestStreak = bestStreak(days: Set(dayTotals.keys), calendar: calendar)
        s.lastActivity = records.map(\.date).max()
        s.todayXP = dayGained[calendar.startOfDay(for: now)] ?? 0
        return s
    }

    /// Maior sequência de dias seguidos já feita
    static func bestStreak(days: Set<Date>, calendar: Calendar) -> Int {
        var best = 0
        for d in days {
            // Só começa a contar no primeiro dia de cada sequência
            guard let prev = calendar.date(byAdding: .day, value: -1, to: d), !days.contains(prev) else { continue }
            var n = 1, cur = d
            while let next = calendar.date(byAdding: .day, value: 1, to: cur), days.contains(next) {
                n += 1
                cur = next
            }
            best = max(best, n)
        }
        return best
    }

    /// Dias seguidos com atividade, terminando hoje ou ontem
    static func streak(days: Set<Date>, now: Date, calendar: Calendar) -> Int {
        var day = calendar.startOfDay(for: now)
        if !days.contains(day) { day = calendar.date(byAdding: .day, value: -1, to: day)! }
        var count = 0
        while days.contains(day) {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }
}
