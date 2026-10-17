import Foundation
#if canImport(UIKit)
import UIKit
#endif

// Regras do jogo. Tudo aqui é função pura do histórico de atividades: nada fica guardado
// além do log, então editar ou apagar uma atividade recalcula XP, nível e evolução na hora.

enum Attribute: String, CaseIterable, Codable, Identifiable {
    case forca, resistencia, agilidade, tecnica

    /// As 6 duplas possíveis das formas híbridas
    static let pairs: [(Attribute, Attribute)] = [(.forca, .resistencia), (.forca, .agilidade), (.forca, .tecnica),
                                                  (.resistencia, .agilidade), (.resistencia, .tecnica), (.agilidade, .tecnica)]

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

/// Uma forma = estágio + galho (atributo) + espécie. O ovo é igual para todas as espécies.
struct MonsterForm: Hashable, Identifiable {
    let stage: Stage
    let attribute: Attribute?
    /// Segundo atributo das formas híbridas (dois atributos empatados na fase)
    var attribute2: Attribute?
    var species: String = Species.standard.id

    init(stage: Stage, attribute: Attribute?, attribute2: Attribute? = nil, species: String = Species.standard.id) {
        self.stage = stage
        // Dupla sempre na mesma ordem (força, resistência, agilidade, técnica)
        if let a = attribute, let b = attribute2, a != b {
            let order = Attribute.allCases
            let swap = order.firstIndex(of: a)! > order.firstIndex(of: b)!
            self.attribute = swap ? b : a
            self.attribute2 = swap ? a : b
        } else {
            self.attribute = attribute
            self.attribute2 = nil
        }
        self.species = stage == .egg ? Species.standard.id : species
    }

    var isHybrid: Bool { attribute2 != nil }

    /// Chave da forma dentro da espécie (ex.: "champion_forca", "champion_forca_resistencia")
    var key: String {
        guard let a = attribute else { return "\(stage)" }
        return attribute2.map { "\(stage)_\(a.rawValue)_\($0.rawValue)" } ?? "\(stage)_\(a.rawValue)"
    }

    /// A espécie padrão mantém os ids antigos, para não perder descobertas da Dex
    var id: String { species == Species.standard.id ? key : "\(species)/\(key)" }

    static let egg = MonsterForm(stage: .egg, attribute: nil)

    static func all(species: String = Species.standard.id) -> [MonsterForm] {
        Stage.allCases.flatMap { s in
            s.branches ? Attribute.allCases.map { MonsterForm(stage: s, attribute: $0, species: species) }
                       : [MonsterForm(stage: s, attribute: nil, species: species)]
        }
    }

    static var all: [MonsterForm] { all() }

    /// As 12 formas híbridas de uma espécie (6 duplas × Champion e Ultimate)
    static func hybrids(species: String = Species.standard.id) -> [MonsterForm] {
        [Stage.champion, .ultimate].flatMap { st in
            Attribute.pairs.map { MonsterForm(stage: st, attribute: $0.0, attribute2: $0.1, species: species) }
        }
    }

    static func byID(_ id: String) -> MonsterForm? {
        let parts = id.split(separator: "/").map(String.init)
        let species = parts.count == 2 ? parts[0] : Species.standard.id
        return (all(species: species) + hybrids(species: species)).first { $0.id == id }
    }

    func with(species: String) -> MonsterForm { MonsterForm(stage: stage, attribute: attribute, attribute2: attribute2, species: species) }

    /// Sem o segundo atributo (forma normal do dominante)
    var single: MonsterForm { MonsterForm(stage: stage, attribute: attribute, species: species) }

    /// Tem arte no app (híbridos chegam aos poucos; sem arte, o bro usa a forma normal)
    var hasArt: Bool {
        guard isHybrid else { return true }
        #if canImport(UIKit)
        return UIImage(named: sprite) != nil
        #else
        return false
        #endif
    }

    var speciesInfo: Species { Species.byID(species) ?? .standard }
    var name: String {
        if stage == .egg { return "Ovo" }
        if let a = attribute, let b = attribute2 {
            let theme = Species.hybridNames[stage]?[a.rawValue + "_" + b.rawValue] ?? "Híbrido"
            return species == Species.standard.id ? theme : "\(theme) \(speciesInfo.name)"
        }
        return speciesInfo.names[key] ?? key
    }
    var sprite: String { stage == .egg ? "sprite_egg" : speciesInfo.sprite(key) }

    /// Mantido para quem ainda usa (widget); todas as formas têm arte própria agora
    var hue: Double { 0 }
}

/// Espécie de monstro: nomes e artes de cada forma, e a afinidade que a faz chocar
struct Species: Identifiable {
    let id: String
    let name: String
    /// Atributo que, dominando os treinos que chocaram o ovo, faz nascer esta espécie (nil = padrão)
    let affinity: Attribute?
    /// Nome de cada forma, pela chave (baby, rookie, champion_forca…)
    let names: [String: String]
    /// Prefixo das artes: sprite_<prefixo><chave>. A padrão usa os nomes antigos (sem prefixo)
    let spritePrefix: String

    func sprite(_ key: String) -> String { "sprite_\(spritePrefix)\(key)" }

    static let standard = Species(
        id: "coelho", name: "Coelho", affinity: nil,
        names: ["baby": "Gymbro", "rookie": "Cutebro",
                "champion_forca": "Halterobro", "champion_resistencia": "Maratobro",
                "champion_agilidade": "Saltabro", "champion_tecnica": "Zenbro",
                "ultimate_forca": "Trebobro", "ultimate_resistencia": "Fôlegobro",
                "ultimate_agilidade": "Relampabro", "ultimate_tecnica": "Mestrebro"],
        spritePrefix: ""
    )

    /// Para incluir uma espécie: nomes das 10 formas + artes "sprite_<id>_<chave>" no app e no widget.
    /// Uma espécie só nasce e aparece na Dex quando as artes dela estão no app (`isReady`).
    static let all: [Species] = [standard] + [
        make("urso", "Urso", .forca, ["Pelucibro", "Ursabro", "Supinobro", "Trilhabro", "Rolabro", "Sumobro",
                                      "Grizzlibro", "Montanhabro", "Avalanchebro", "Kodiabro"]),
        make("rato", "Rato", .forca, ["Queijibro", "Ratibro", "Marombabro", "Rodibro", "Fuxibro", "Labiribro",
                                      "Ratazanabro", "Esteirabro", "Sombrabro", "Engenhobro"]),
        make("lobo", "Lobo", .resistencia, ["Uivibro", "Lobinbro", "Alfabro", "Trotebro", "Caçabro", "Matilhabro",
                                             "Fenribro", "Luabro", "Ventobro", "Ancestrabro"]),
        make("cachorro", "Cachorro", .resistencia, ["Filhotibro", "Caramelbro", "Pitbulbro", "Galgobro", "Frisbeebro", "Pastorbro",
                                                     "Mastibro", "Huskybro", "Agilitybro", "Guiabro"]),
        make("esquilo", "Esquilo", .agilidade, ["Nozibro", "Esquilbro", "Quebranozbro", "Galhobro", "Pulabro", "Acrobabro",
                                                 "Carvalhobro", "Florestabro", "Voadorbro", "Parkourbro"]),
        make("gato", "Gato", .agilidade, ["Novelbro", "Bichanobro", "Garrabro", "Rondabro", "Telhadobro", "Ronrobro",
                                          "Jubabro", "Panterabro", "Linxbro", "Esfingebro"]),
        make("coruja", "Coruja", .tecnica, ["Penugbro", "Corujabro", "Rapinabro", "Noturnbro", "Planabro", "Sabiobro",
                                             "Harpiabro", "Luarbro", "Rasantebro", "Oraculobro"]),
    ]

    /// Ordem das formas nas listas de nomes acima
    static let keys = ["baby", "rookie", "champion_forca", "champion_resistencia", "champion_agilidade", "champion_tecnica",
                       "ultimate_forca", "ultimate_resistencia", "ultimate_agilidade", "ultimate_tecnica"]

    private static func make(_ id: String, _ name: String, _ affinity: Attribute, _ names: [String]) -> Species {
        Species(id: id, name: name, affinity: affinity, names: Dictionary(uniqueKeysWithValues: zip(keys, names)), spritePrefix: "\(id)_")
    }

    /// Espécies com arte pronta
    static var catalog: [Species] { all.filter(\.isReady) }

    /// Tem as 10 artes no app
    var isReady: Bool {
        if id == Species.standard.id { return true }
        #if canImport(UIKit)
        return Species.keys.allSatisfy { UIImage(named: sprite($0)) != nil }
        #else
        return false
        #endif
    }

    static func byID(_ id: String) -> Species? { all.first { $0.id == id } }

    /// Nomes das formas híbridas por dupla (nas outras espécies levam o nome da espécie junto)
    static let hybridNames: [Stage: [String: String]] = [
        .champion: ["forca_resistencia": "Crossbro", "forca_agilidade": "Golpebro", "forca_tecnica": "Arrancobro",
                    "resistencia_agilidade": "Trilhabro", "resistencia_tecnica": "Nadobro", "agilidade_tecnica": "Gingabro"],
        .ultimate: ["forca_resistencia": "Hércubro", "forca_agilidade": "Titãbro", "forca_tecnica": "Olimpibro",
                    "resistencia_agilidade": "Ventobro", "resistencia_tecnica": "Marébro", "agilidade_tecnica": "Acrobro"],
    ]

    /// Tem pelo menos uma arte híbrida no app (a Dex só mostra a seção nesse caso)
    var hasHybrids: Bool { MonsterForm.hybrids(species: id).contains(where: \.hasArt) }

    /// Espécie de um ovo que acabou de chocar, pelos treinos que o chocaram.
    /// Entre várias espécies com a mesma afinidade, escolhe de forma estável pelo id do monstro.
    static func hatch(attributes: [Attribute: Double], seed: UUID) -> Species {
        guard !attributes.isEmpty else { return standard }
        let dominant = Game.dominant(attributes)
        let matches = catalog.filter { $0.affinity == dominant }
        guard !matches.isEmpty else { return standard }
        var rng = SeededRandom(seed: seed.uuidString)
        return matches[Int(rng.next() * Double(matches.count)) % matches.count]
    }
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
    /// Atributos dos treinos que chocaram o ovo (definem a espécie)
    var hatchAttributes: [Attribute: Double] = [:]
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
        guard next.branches else { return MonsterForm(stage: next, attribute: nil, species: form.species) }
        let (a, b) = Game.branch(stageAttributes)
        let f = MonsterForm(stage: next, attribute: a, attribute2: b, species: form.species)
        return f.hasArt ? f : f.single
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

    /// O 2º atributo precisa ter pelo menos 90% do 1º para virar híbrido
    static let hybridRatio = 0.9

    /// Galho da evolução: o dominante e, se o segundo estiver quase empatado, ele também
    static func branch(_ attrs: [Attribute: Double]) -> (Attribute, Attribute?) {
        let a = dominant(attrs)
        let top = attrs[a] ?? 0
        let rest = Attribute.allCases.filter { $0 != a }
        guard top > 0, let b = rest.max(by: { (attrs[$0] ?? 0) < (attrs[$1] ?? 0) }),
              (attrs[b] ?? 0) >= top * hybridRatio else { return (a, nil) }
        return (a, b)
    }

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
                if s.stage == .egg { s.hatchAttributes = s.stageAttributes }
                if next.branches {
                    let (a, b) = branch(s.stageAttributes)
                    s.form = MonsterForm(stage: next, attribute: a, attribute2: b)
                } else {
                    s.form = MonsterForm(stage: next, attribute: nil)
                }
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
