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
        case .futebol: "figure.soccer"
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
        case .rookie: "Novato"
        case .champion: "Atleta"
        case .ultimate: "Lenda"
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
/// A Lenda guarda também o galho do Atleta de onde veio: se for diferente do galho dela, é uma Lenda de virada.
struct MonsterForm: Hashable, Identifiable {
    let stage: Stage
    let attribute: Attribute?
    /// Segundo atributo das formas híbridas (dois atributos empatados na fase)
    var attribute2: Attribute?
    /// Galho do Atleta de origem, só nas Lendas de virada (nil nas Lendas puras e nos outros estágios)
    var origin: Attribute?
    var origin2: Attribute?
    var species: String = Species.standard.id

    init(stage: Stage, attribute: Attribute?, attribute2: Attribute? = nil,
         origin: Attribute? = nil, origin2: Attribute? = nil, species: String = Species.standard.id) {
        self.stage = stage
        (self.attribute, self.attribute2) = Self.ordered(attribute, attribute2)
        let o = Self.ordered(origin, origin2)
        let virada = stage == .ultimate && o.0 != nil && (o.0 != self.attribute || o.1 != self.attribute2)
        (self.origin, self.origin2) = virada ? o : (nil, nil)
        self.species = stage == .egg ? Species.standard.id : species
    }

    /// Dupla sempre na mesma ordem (força, resistência, agilidade, técnica)
    private static func ordered(_ a: Attribute?, _ b: Attribute?) -> (Attribute?, Attribute?) {
        guard let a, let b, a != b else { return (a, nil) }
        let order = Attribute.allCases
        return order.firstIndex(of: a)! > order.firstIndex(of: b)! ? (b, a) : (a, b)
    }

    var isHybrid: Bool { attribute2 != nil }
    var isVirada: Bool { origin != nil }

    /// Chave da forma dentro da espécie (ex.: "champion_forca", "champion_forca_resistencia",
    /// "ultimate_forca_to_resistencia")
    var key: String {
        guard let a = attribute else { return "\(stage)" }
        let branch = [a, attribute2].compactMap { $0 }.map(\.rawValue).joined(separator: "_")
        guard let o = origin else { return "\(stage)_\(branch)" }
        let from = [o, origin2].compactMap { $0 }.map(\.rawValue).joined(separator: "_")
        return "\(stage)_\(from)_to_\(branch)"
    }

    /// Atleta de onde a Lenda veio (para a Lenda pura, o do mesmo galho)
    var champion: MonsterForm? {
        guard stage == .ultimate else { return nil }
        return isVirada ? MonsterForm(stage: .champion, attribute: origin, attribute2: origin2, species: species)
                        : MonsterForm(stage: .champion, attribute: attribute, attribute2: attribute2, species: species)
    }

    /// Lenda pura da linha (a de virada sem arte usa ela)
    var lineage: MonsterForm {
        guard isVirada else { return self }
        return MonsterForm(stage: .ultimate, attribute: origin, attribute2: origin2, species: species)
    }

    /// Forma que aparece no app: híbrido sem arte segue a forma normal do dominante.
    /// A virada aparece mesmo sem arte (fica sem imagem até a arte chegar).
    var resolved: MonsterForm { isVirada || hasArt ? self : single }

    /// Arte para onde não dá para mostrar um espaço vazio (widget, Live Activity): a virada sem arte usa a da Lenda pura da linha
    var spriteWithFallback: String { isVirada && !hasArt ? lineage.resolved.sprite : sprite }

    /// A espécie padrão mantém os ids antigos, para não perder descobertas do BroBook
    var id: String { species == Species.standard.id ? key : "\(species)/\(key)" }

    static let egg = MonsterForm(stage: .egg, attribute: nil)

    static func all(species: String = Species.standard.id) -> [MonsterForm] {
        Stage.allCases.flatMap { s in
            s.branches ? Attribute.allCases.map { MonsterForm(stage: s, attribute: $0, species: species) }
                       : [MonsterForm(stage: s, attribute: nil, species: species)]
        }
    }

    static var all: [MonsterForm] { all() }

    /// As 12 formas híbridas de uma espécie (6 duplas × Atleta e Lenda)
    static func hybrids(species: String = Species.standard.id) -> [MonsterForm] {
        [Stage.champion, .ultimate].flatMap { st in
            Attribute.pairs.map { MonsterForm(stage: st, attribute: $0.0, attribute2: $0.1, species: species) }
        }
    }

    /// Os 10 galhos possíveis numa fase: os 4 atributos sozinhos e as 6 duplas
    static let branches: [(Attribute, Attribute?)] = Attribute.allCases.map { ($0, nil) } + Attribute.pairs.map { ($0.0, $0.1) }

    /// As Lendas de virada que saem de um Atleta (as 9 saídas diferentes do galho dele)
    static func viradas(from champion: MonsterForm) -> [MonsterForm] {
        branches.map { MonsterForm(stage: .ultimate, attribute: $0.0, attribute2: $0.1,
                                   origin: champion.attribute, origin2: champion.attribute2, species: champion.species) }
            .filter(\.isVirada)
    }

    /// As 90 Lendas de virada de uma espécie (10 Atletas × 9 saídas)
    static func viradas(species: String = Species.standard.id) -> [MonsterForm] {
        branches.flatMap { viradas(from: MonsterForm(stage: .champion, attribute: $0.0, attribute2: $0.1, species: species)) }
    }

    static func byID(_ id: String) -> MonsterForm? {
        let parts = id.split(separator: "/").map(String.init)
        let species = parts.count == 2 ? parts[0] : Species.standard.id
        if id.contains("_to_") { return viradas(species: species).first { $0.id == id } }
        return (all(species: species) + hybrids(species: species)).first { $0.id == id }
    }

    func with(species: String) -> MonsterForm {
        MonsterForm(stage: stage, attribute: attribute, attribute2: attribute2, origin: origin, origin2: origin2, species: species)
    }

    /// Sem o segundo atributo (forma normal do dominante)
    var single: MonsterForm { MonsterForm(stage: stage, attribute: attribute, species: species) }

    /// Tem arte no app (híbridos e viradas chegam aos poucos)
    var hasArt: Bool {
        guard isHybrid || isVirada else { return true }
        #if canImport(UIKit)
        return UIImage(named: sprite) != nil
        #else
        return false
        #endif
    }

    var speciesInfo: Species { Species.byID(species) ?? .standard }
    var name: String {
        if stage == .egg { return "Ovo" }
        return speciesInfo.names[key] ?? Species.viradaNames[species]?[key] ?? (isHybrid ? "Híbrido" : key)
    }
    var sprite: String { stage == .egg ? "sprite_egg" : speciesInfo.sprite(key) }

    /// Mantido para quem ainda usa (widget); todas as formas têm arte própria agora
    var hue: Double { 0 }
}

/// Espécie de monstro: nomes e artes de cada forma, e a afinidade que a faz chocar
struct Species: Identifiable {
    let id: String
    let name: String
    /// Nome de cada forma, pela chave (baby, rookie, champion_forca…)
    let names: [String: String]
    /// Prefixo das artes: sprite_<prefixo><chave>. A padrão usa os nomes antigos (sem prefixo)
    let spritePrefix: String

    func sprite(_ key: String) -> String { "sprite_\(spritePrefix)\(key)" }

    static let standard = Species(
        id: "coelho", name: "Coelho",
        names: ["baby": "Gymbro", "rookie": "Cutebro",
                "champion_forca": "Halterobro", "champion_resistencia": "Maratobro",
                "champion_agilidade": "Saltabro", "champion_tecnica": "Zenbro",
                "ultimate_forca": "Trebobro", "ultimate_resistencia": "Fôlegobro",
                "ultimate_agilidade": "Relampabro", "ultimate_tecnica": "Mestrebro"]
            .merging(zip(hybridKeys, ["Crossbro", "Golpebro", "Arrancobro", "Chuteirabro", "Nadobro", "Gingabro",
                                      "Hércubro", "Titãbro", "Olimpibro", "Tufãobro", "Marébro", "Piruetabro"])) { a, _ in a },
        spritePrefix: ""
    )

    /// Para incluir uma espécie: nomes das 10 formas, nomes dos 12 híbridos (únicos: nenhum repete outra forma)
    /// e artes "sprite_<id>_<chave>" no app e no widget.
    /// Uma espécie só nasce e aparece no BroBook quando as artes dela estão no app (`isReady`).
    static let all: [Species] = [standard] + [
        make("urso", "Urso", ["Pelucibro", "Ursabro", "Supinobro", "Trilhabro", "Rolabro", "Sumobro",
                                      "Grizzlibro", "Montanhabro", "Avalanchebro", "Kodiabro"],
             ["Burpeebro", "Patadabro", "Arremessobro", "Mateirobro", "Salmãobro", "Meialuabro",
              "Colossobro", "Brutobro", "Gigantebro", "Nevascabro", "Polarbro", "Aurorabro"]),
        make("rato", "Rato", ["Queijibro", "Ratibro", "Marombabro", "Rodibro", "Fuxibro", "Labiribro",
                                      "Ratazanabro", "Esteirabro", "Sombrabro", "Engenhobro"],
             ["Bigodefitbro", "Mordidabro", "Gorgonzolabro", "Bueirobro", "Esgotobro", "Arraiabro",
              "Metrôbro", "Presabro", "Parmesãobro", "Ventaniabro", "Correntezabro", "Piãobro"]),
        make("lobo", "Lobo", ["Uivibro", "Lobinbro", "Alfabro", "Trotebro", "Caçabro", "Matilhabro",
                                             "Fenribro", "Luabro", "Ventobro", "Ancestrabro"],
             ["Caninobro", "Investidabro", "Cumebro", "Rastrobro", "Riachobro", "Crepúsculobro",
              "Lobisombro", "Ragnarbro", "Cordilheirabro", "Vendavalbro", "Fiordebro", "Eclipsebro"]),
        make("cachorro", "Cachorro", ["Filhotibro", "Caramelbro", "Pitbulbro", "Galgobro", "Frisbeebro", "Pastorbro",
                                                     "Mastibro", "Huskybro", "Agilitybro", "Guiabro"],
             ["Viralatabro", "Boxerbro", "Bulldogbro", "Gandulabro", "Labradorbro", "Poodlebro",
              "Cérberobro", "Dobermanbro", "Sãobernardobro", "Salukibro", "Terranovabro", "Borderbro"]),
        make("esquilo", "Esquilo", ["Nozibro", "Esquilbro", "Quebranozbro", "Galhobro", "Pulabro", "Acrobabro",
                                                 "Carvalhobro", "Florestabro", "Voadorbro", "Parkourbro"],
             ["Bolotabro", "Ouriçobro", "Torabro", "Copabro", "Cachoeirabro", "Cipóbro",
              "Sequoiabro", "Espinheirobro", "Jequitibro", "Redemoinhobro", "Cascatabro", "Trapezistabro"]),
        make("gato", "Gato", ["Novelbro", "Bichanobro", "Garrabro", "Rondabro", "Telhadobro", "Ronrobro",
                                          "Jubabro", "Panterabro", "Linxbro", "Esfingebro"],
             ["Miaufitbro", "Unhadabro", "Pumabro", "Gatunobro", "Molhadobro", "Muretabro",
              "Tigrebro", "Smilodonbro", "Leãobro", "Guepardobro", "Onçabro", "Bastetbro"]),
        make("coruja", "Coruja", ["Penugbro", "Corujabro", "Rapinabro", "Noturnbro", "Planabro", "Sabiobro",
                                             "Harpiabro", "Luarbro", "Rasantebro", "Oraculobro"],
             ["Madrugabro", "Bicadabro", "Mochobro", "Revoadabro", "Martimbro", "Plumabro",
              "Grifobro", "Falcãobro", "Atenabro", "Ciclonebro", "Albatrozbro", "Fênixbro"]),
    ]

    /// Ordem dos híbridos nas listas de nomes: Atletas e depois Lendas, na ordem de `Attribute.pairs`
    static let hybridKeys = [Stage.champion, .ultimate].flatMap { st in Attribute.pairs.map { "\(st)_\($0.0.rawValue)_\($0.1.rawValue)" } }

    /// Ordem das formas nas listas de nomes acima
    static let keys = ["baby", "rookie", "champion_forca", "champion_resistencia", "champion_agilidade", "champion_tecnica",
                       "ultimate_forca", "ultimate_resistencia", "ultimate_agilidade", "ultimate_tecnica"]

    private static func make(_ id: String, _ name: String, _ names: [String], _ hybrids: [String]) -> Species {
        Species(id: id, name: name, names: Dictionary(uniqueKeysWithValues: zip(keys + hybridKeys, names + hybrids)),
                spritePrefix: "\(id)_")
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

    /// Tem pelo menos uma arte híbrida no app (o BroBook só mostra a seção nesse caso)
    var hasHybrids: Bool { MonsterForm.hybrids(species: id).contains(where: \.hasArt) }

    /// Atividades do app que fazem nascer esta espécie (as do Apple Saúde estão todas em `Hatch`)
    var kinds: [ActivityKind] { ActivityKind.allCases.filter { Hatch.species(for: $0).contains(id) } }

    /// Espécie de um ovo que acabou de chocar: a atividade com mais da metade dos minutos treinados no ovo decide
    /// (minutos, não XP: senão corrida, que rende quase o dobro de XP por minuto, venceria a musculação);
    /// sem atividade principal, nasce a espécie padrão. Entre candidatas (Urso e Rato), escolhe de forma
    /// estável pelo id do bro.
    static func hatch(records: [ActivityRecord], seed: UUID) -> Species {
        var votes: [[String]: Double] = [:]
        for r in records { votes[Hatch.species(r), default: 0] += Double(max(r.minutes, 0)) }
        let total = votes.values.reduce(0, +)
        guard total > 0, let (ids, top) = votes.max(by: { $0.value < $1.value }), top / total > Hatch.majority else { return standard }
        let matches = catalog.filter { ids.contains($0.id) }
        guard !matches.isEmpty else { return standard }
        var rng = SeededRandom(seed: seed.uuidString)
        return matches[Int(rng.next() * Double(matches.count)) % matches.count]
    }
}

struct ActivityRecord: Identifiable, Hashable {
    let id: UUID
    let kind: ActivityKind
    let date: Date
    let minutes: Int
    let effort: Int
    /// Tipo exato do treino no Apple Saúde (decide a espécie com mais precisão que a categoria)
    var healthType: UInt?
    /// Divisão do XP entre os atributos calculada para este treino; nil = tabela fixa da categoria
    var weights: [Attribute: Double]?
    /// Parte do XP que vai para este bro: 1 no principal, `Roster.leagueShare` no que só representa uma liga
    var share: Double = 1

    var split: [Attribute: Double] { weights ?? kind.weights }
}

struct Evolution: Identifiable {
    let date: Date
    let form: MonsterForm
    var id: String { form.id + "\(date.timeIntervalSince1970)" }
}

/// XP que um dono deu a um bro (quem treinou e quanto)
struct OwnerXP: Codable, Hashable, Sendable {
    let name: String
    let xp: Int
}

/// Ponto de partida de um bro que chegou por troca: a forma e o XP que ele tinha. Os treinos do novo dono
/// continuam dali (a fase atual recomeça na chegada). O XP de antes é dos donos anteriores, não seu.
struct SnapshotBase: Codable, Hashable {
    let formID: String
    let xp: Int
    /// Atributos de tudo o que ele já treinou (rawValue → valor)
    let attributes: [String: Double]
    let date: Date
    /// Quem treinou o bro antes e quanto XP cada um deu, do primeiro dono ao último (soma = `xp`)
    var history: [OwnerXP]?

    var form: MonsterForm { MonsterForm.byID(formID) ?? .egg }
    var owners: [OwnerXP] { history ?? [OwnerXP(name: "Dono anterior", xp: xp)] }
}

struct Snapshot {
    var totalXP = 0
    var form = MonsterForm.egg
    /// Atributos acumulados desde a última evolução: decidem o próximo galho
    var stageAttributes: [Attribute: Double] = [:]
    var lifetimeAttributes: [Attribute: Double] = [:]
    /// XP que veio com o bro numa troca, de quem o treinou antes (vazio se ele sempre foi seu)
    var inherited: [OwnerXP] = []
    var inheritedXP: Int { inherited.reduce(0) { $0 + $1.xp } }
    /// XP que você deu a ele com os seus treinos
    var myXP: Int { totalXP - inheritedXP }
    /// Quando ele chegou por troca
    var arrivedAt: Date?
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
        return MonsterForm(stage: next, attribute: a, attribute2: b,
                           origin: form.attribute, origin2: form.attribute2, species: form.species).resolved
    }
}

enum Game {
    static let maxMinutes = 240
    /// Para o bro, cada treino conta no máximo 2 h 30 (as ligas seguem com `maxMinutes`)
    static let broMaxMinutes = 150

    /// Minutos que contam para o bro: sem o trecho que cai em cima de um treino anterior (dois treinos não acontecem
    /// ao mesmo tempo) e até `broMaxMinutes`. `busyUntil` é onde termina o treino mais longo já contado; como os treinos
    /// vêm em ordem de início, tudo o que veio antes e passa de `start` cobre exatamente [start, busyUntil).
    static func broMinutes(start: Date, minutes: Int, busyUntil: Date?) -> Int {
        let total = max(minutes, 0)
        guard let busy = busyUntil, busy > start else { return min(total, broMaxMinutes) }
        let covered = Int((busy.timeIntervalSince(start) / 60).rounded(.up))
        return min(max(total - covered, 0), broMaxMinutes)
    }
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

    /// Igual a `snapshot`, mas guarda o resultado: as telas recalculam a cada render com os mesmos registros.
    /// A chave é o conteúdo inteiro (na mesma ordem), o dia de hoje (sequência e XP do dia) e o calendário.
    static func cachedSnapshot(_ records: [ActivityRecord], base: SnapshotBase? = nil, now: Date = .now, calendar: Calendar = .current) -> Snapshot {
        SnapshotCache.shared.value(for: .init(records: records, base: base, day: calendar.startOfDay(for: now), calendar: calendar)) {
            snapshot(records, base: base, now: now, calendar: calendar)
        }
    }

    static func snapshot(_ records: [ActivityRecord], base: SnapshotBase? = nil, now: Date = .now, calendar: Calendar = .current) -> Snapshot {
        var s = Snapshot()
        if let base {
            s.form = base.form
            s.totalXP = base.xp
            s.lifetimeAttributes = Dictionary(uniqueKeysWithValues: base.attributes.compactMap { k, v in Attribute(rawValue: k).map { ($0, v) } })
            s.evolutions = [Evolution(date: base.date, form: base.form)]
            s.inherited = base.owners
            s.arrivedAt = base.date
        }
        var dayTotals: [Date: Int] = [:]
        var dayGained: [Date: Int] = [:]
        var busyUntil: Date?

        for r in records.sorted(by: { $0.date < $1.date }) {
            let minutes = broMinutes(start: r.date, minutes: r.minutes, busyUntil: busyUntil)
            let end = r.date.addingTimeInterval(Double(max(r.minutes, 0)) * 60)
            busyUntil = max(busyUntil ?? end, end)
            let raw = minutes > 0 ? Int((Double(xp(kind: r.kind, minutes: minutes, effort: r.effort)) * r.share).rounded()) : 0
            let day = calendar.startOfDay(for: r.date)
            let before = dayTotals[day, default: 0]
            let full = max(min(raw, dailySoftCap - before), 0)
            let gainedBefore = dayGained[day, default: 0]
            let gained = min(full + (raw - full) / 3, max(dailyHardCap - gainedBefore, 0))
            dayTotals[day] = before + raw
            dayGained[day] = gainedBefore + gained
            s.xpByActivity[r.id] = gained
            s.totalXP += gained

            for (attr, w) in r.split {
                s.stageAttributes[attr, default: 0] += Double(gained) * w
                s.lifetimeAttributes[attr, default: 0] += Double(gained) * w
            }

            // Vários estágios numa atividade só: a fase nova ainda está vazia, então o galho usa a anterior
            var carried: [Attribute: Double] = [:]
            while let next = s.stage.next, s.totalXP >= next.threshold {
                let attrs = s.stageAttributes.isEmpty ? carried : s.stageAttributes
                if s.stage == .egg { s.hatchAttributes = attrs }
                if next.branches {
                    // A Lenda continua a linha do Atleta: galho diferente do dele vira Lenda de virada, só dele
                    let (a, b) = branch(attrs)
                    s.form = MonsterForm(stage: next, attribute: a, attribute2: b, origin: s.form.attribute, origin2: s.form.attribute2)
                } else {
                    s.form = MonsterForm(stage: next, attribute: nil)
                }
                s.evolutions.append(Evolution(date: r.date, form: s.form))
                carried = attrs
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

/// Memória dos últimos snapshots calculados (poucos: um por bro, mais o do jogador)
final class SnapshotCache: @unchecked Sendable {
    static let shared = SnapshotCache()

    struct Key: Hashable {
        let records: [ActivityRecord]
        var base: SnapshotBase?
        let day: Date
        let calendar: Calendar
    }

    private let limit = 24
    private var store: [Key: Snapshot] = [:]
    private var order: [Key] = []
    private let lock = NSLock()

    func value(for key: Key, compute: () -> Snapshot) -> Snapshot {
        lock.lock()
        if let hit = store[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()
        let s = compute()
        lock.lock()
        defer { lock.unlock() }
        if store[key] == nil {
            store[key] = s
            order.append(key)
            if order.count > limit { store[order.removeFirst()] = nil }
        }
        return s
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        store = [:]
        order = []
    }
}
