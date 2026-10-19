import Foundation
import HealthKit
import SwiftData

// Como o XP de cada treino se divide entre os atributos.
// A tabela de `ActivityKind.weights` é só o ponto de partida: o tipo exato do Apple Saúde, as séries do treino de
// musculação (reps, descanso, exercício), os movimentos e o formato do WOD, a duração, o esforço e o ritmo mexem na divisão.
// Ela é calculada uma vez, quando a atividade é salva, e fica guardada (ActivitySplits): mudar estas regras depois não
// reescreve a história dos bros. Atividades de antes disso seguem a tabela fixa.

enum AttributeSplit {
    typealias Weights = [Attribute: Double]

    /// Uma série de trabalho feita
    struct SetSignal: Hashable {
        var exerciseID: String
        var reps: Int
        var rest: Int
    }

    /// WOD feito: formato e exercícios reconhecidos
    struct WodSignal: Hashable {
        var format: WodFormat
        var exercises: [String]
    }

    struct Signals: Hashable {
        var kind: ActivityKind
        var minutes: Int
        var effort: Int
        var meters: Double? = nil
        var healthType: UInt? = nil
        var sets: [SetSignal] = []
        var wod: WodSignal? = nil
    }

    static func split(_ s: Signals) -> Weights {
        var w = s.healthType.flatMap(health) ?? s.kind.weights
        if let detail = detail(s) { w = mix(w, 0.25, detail, 0.75) }
        w = intensity(w, s)
        return tidy(w)
    }

    // MARK: Detalhe do treino

    private static func detail(_ s: Signals) -> Weights? {
        if !s.sets.isEmpty {
            return average(s.sets.map { set in
                var w = movement(set.exerciseID, reps: set.reps)
                // Descanso curto vira condicionamento
                if set.rest > 0, set.rest <= 45 { w = shift(w, to: .resistencia, 0.25) }
                return w
            })
        }
        if let wod = s.wod {
            let moves = wod.exercises.map { movement($0, reps: nil) }
            let format = wodFormat(wod.format)
            return moves.isEmpty ? format : mix(average(moves), 0.6, format, 0.4)
        }
        return nil
    }

    /// Tipo de movimento de um exercício da biblioteca
    enum Pattern: Equatable {
        /// Arranco, arremesso, ginástica avançada: coordenação acima de tudo
        case skill
        /// Saltos e movimentos explosivos
        case plyo
        /// Máquinas de cardio, corda, remo, corrida
        case cardio
        /// Carregar peso andando
        case carry
        /// Prancha, isometria
        case isometric
        /// Peso do corpo comum
        case bodyweight
        /// Máquina ou polia: carga guiada
        case machine
        /// Barra, halteres, kettlebell
        case free
    }

    private static let skillWords = ["snatch", "clean", "jerk", "overhead-squat", "pistol", "hspu", "handstand", "muscle-up",
                                     "turkish", "l-sit", "rope-climb", "toes-to-bar", "knees-to-elbows", "kipping", "ring-dip"]
    private static let plyoWords = ["salto", "jump", "pliometrica", "burpee", "tuck", "double-under", "mountain-climber"]
    private static let cardioWords = ["esteira", "remo", "row-cal", "bike", "ski", "corda-naval", "pular-corda", "eliptico", "escada"]
    private static let carryWords = ["farmer", "sandbag", "sled", "carry"]

    static func pattern(_ id: String) -> Pattern {
        let e = Exercise.byID(id)
        if skillWords.contains(where: id.contains) { return .skill }
        if plyoWords.contains(where: id.contains) { return .plyo }
        if cardioWords.contains(where: id.contains) { return .cardio }
        if carryWords.contains(where: id.contains) { return .carry }
        switch e?.type {
        case .time: return .isometric
        case .bodyweight: return .bodyweight
        default: break
        }
        if let eq = e?.equipment, ["Máquina", "Polia", "Smith"].contains(where: eq.contains) { return .machine }
        return .free
    }

    /// Divisão de um movimento; `reps` nil = sem a série (WOD), usa a faixa do meio
    static func movement(_ id: String, reps: Int?) -> Weights {
        switch pattern(id) {
        case .skill: return [.tecnica: 0.6, .forca: 0.25, .agilidade: 0.15]
        case .plyo: return [.agilidade: 0.6, .resistencia: 0.25, .forca: 0.15]
        case .cardio: return [.resistencia: 0.8, .agilidade: 0.2]
        case .carry: return [.forca: 0.55, .resistencia: 0.45]
        case .isometric: return [.tecnica: 0.5, .resistencia: 0.3, .forca: 0.2]
        case .bodyweight:
            guard let reps else { return [.forca: 0.4, .resistencia: 0.3, .tecnica: 0.3] }
            return reps <= 10 ? [.forca: 0.55, .tecnica: 0.3, .resistencia: 0.15]
                              : [.resistencia: 0.5, .forca: 0.3, .tecnica: 0.2]
        case .machine, .free:
            let free = pattern(id) == .free
            // Peso livre pede mais controle que máquina
            let tech = free ? 0.15 : 0.05
            switch reps ?? 10 {
            case ...5: return [.forca: 1 - tech, .tecnica: tech]
            case 6...12: return [.forca: 0.8 - tech, .resistencia: 0.2, .tecnica: tech]
            case 13...20: return [.forca: 0.45, .resistencia: 0.55 - tech, .tecnica: tech]
            default: return [.resistencia: 0.7, .forca: 0.3 - tech, .tecnica: tech]
            }
        }
    }

    private static func wodFormat(_ f: WodFormat) -> Weights {
        switch f {
        case .emom: return [.forca: 0.4, .tecnica: 0.3, .resistencia: 0.3]
        case .tabata: return [.agilidade: 0.5, .resistencia: 0.5]
        case .amrap(let m), .forTime(capMinutes: let m?):
            if m >= 15 { return [.resistencia: 0.6, .forca: 0.2, .agilidade: 0.2] }
            if m <= 8 { return [.agilidade: 0.4, .forca: 0.3, .resistencia: 0.3] }
            return [.resistencia: 0.4, .forca: 0.3, .agilidade: 0.3]
        case .forTime(capMinutes: nil): return [.resistencia: 0.4, .forca: 0.3, .agilidade: 0.3]
        }
    }

    // MARK: Duração, esforço e ritmo

    private static func intensity(_ base: Weights, _ s: Signals) -> Weights {
        var w = base
        // Treino longo puxa resistência (até +25% a partir de 1h15)
        if s.minutes >= 75 { w = shift(w, to: .resistencia, min(0.25, Double(s.minutes - 60) / 240)) }
        // Curto e no talo: explosão (na musculação, força). Com séries ou WOD, o detalhe já disse como foi
        if s.sets.isEmpty, s.wod == nil, s.minutes <= 25, s.effort >= 8 { w = shift(w, to: s.kind == .musculacao ? .forca : .agilidade, 0.12) }
        // Leve e controlado: técnica (menos na caminhada, que já é leve por natureza)
        if s.effort <= 3, s.kind != .caminhada { w = shift(w, to: .tecnica, 0.1) }

        guard let m = s.meters, m >= 300, s.minutes > 0 else { return w }
        let km = m / 1000, hours = Double(s.minutes) / 60
        switch s.kind {
        case .corrida:
            let pace = Double(s.minutes * 60) / km // segundos por km
            if pace < 270 { w = shift(w, to: .agilidade, 0.25) } else if pace < 330 { w = shift(w, to: .agilidade, 0.1) }
            if km >= 15 { w = shift(w, to: .resistencia, 0.15) }
        case .caminhada:
            if km / hours >= 6.5 { w = shift(w, to: .agilidade, 0.1) }
            if km >= 12 { w = shift(w, to: .forca, 0.1) }
        case .bike:
            if km / hours >= 30 { w = shift(w, to: .agilidade, 0.15) }
            if km >= 60 { w = shift(w, to: .resistencia, 0.1) }
        case .natacao:
            let per100 = Double(s.minutes * 60) / (m / 100)
            if per100 < 120 { w = shift(w, to: .tecnica, 0.1); w = shift(w, to: .agilidade, 0.1) }
            if m >= 2000 { w = shift(w, to: .resistencia, 0.15) }
        default: break
        }
        return w
    }

    // MARK: Tipo exato do Apple Saúde

    /// Mais fino que a categoria do app (basquete não é futebol, pilates não é yoga)
    static func health(_ raw: UInt) -> Weights? {
        guard let t = HKWorkoutActivityType(rawValue: raw) else { return nil }
        switch t {
        case .traditionalStrengthTraining: return [.forca: 0.8, .tecnica: 0.2]
        case .functionalStrengthTraining: return [.forca: 0.5, .agilidade: 0.2, .tecnica: 0.2, .resistencia: 0.1]
        case .coreTraining: return [.forca: 0.4, .tecnica: 0.4, .resistencia: 0.2]
        case .crossTraining: return [.forca: 0.4, .resistencia: 0.4, .agilidade: 0.2]
        case .highIntensityIntervalTraining: return [.resistencia: 0.4, .agilidade: 0.4, .forca: 0.2]
        case .mixedCardio: return [.resistencia: 0.7, .agilidade: 0.3]
        case .jumpRope: return [.agilidade: 0.5, .resistencia: 0.3, .tecnica: 0.2]
        case .hiking: return [.resistencia: 0.7, .forca: 0.3]
        case .trackAndField: return [.agilidade: 0.6, .forca: 0.2, .tecnica: 0.2]
        case .handCycling: return [.resistencia: 0.6, .forca: 0.4]
        case .waterFitness: return [.resistencia: 0.6, .tecnica: 0.2, .agilidade: 0.2]
        case .waterPolo: return [.resistencia: 0.4, .agilidade: 0.3, .tecnica: 0.3]
        case .basketball: return [.agilidade: 0.5, .resistencia: 0.3, .tecnica: 0.2]
        case .handball: return [.agilidade: 0.5, .resistencia: 0.3, .forca: 0.2]
        case .rugby: return [.forca: 0.4, .resistencia: 0.3, .agilidade: 0.3]
        case .americanFootball: return [.forca: 0.4, .agilidade: 0.4, .resistencia: 0.2]
        case .hockey: return [.agilidade: 0.5, .resistencia: 0.3, .tecnica: 0.2]
        case .boxing: return [.agilidade: 0.4, .resistencia: 0.3, .forca: 0.3]
        case .kickboxing: return [.agilidade: 0.5, .resistencia: 0.3, .forca: 0.2]
        case .wrestling: return [.forca: 0.5, .resistencia: 0.3, .tecnica: 0.2]
        case .fencing: return [.agilidade: 0.5, .tecnica: 0.5]
        case .socialDance: return [.tecnica: 0.6, .agilidade: 0.4]
        case .barre: return [.tecnica: 0.4, .forca: 0.3, .resistencia: 0.3]
        case .pilates: return [.tecnica: 0.6, .forca: 0.4]
        case .taiChi: return [.tecnica: 0.8, .agilidade: 0.2]
        case .tennis, .badminton, .pickleball, .racquetball, .squash: return [.agilidade: 0.6, .tecnica: 0.4]
        case .tableTennis: return [.agilidade: 0.5, .tecnica: 0.5]
        case .climbing: return [.forca: 0.5, .tecnica: 0.4, .resistencia: 0.1]
        case .rowing, .paddleSports: return [.resistencia: 0.7, .forca: 0.3]
        case .surfingSports: return [.tecnica: 0.5, .agilidade: 0.3, .resistencia: 0.2]
        case .skatingSports: return [.tecnica: 0.5, .agilidade: 0.5]
        case .snowSports, .crossCountrySkiing, .downhillSkiing, .snowboarding: return [.tecnica: 0.4, .agilidade: 0.3, .resistencia: 0.3]
        case .golf: return [.tecnica: 1]
        case .stairClimbing, .stairs: return [.resistencia: 0.7, .forca: 0.3]
        case .elliptical: return [.resistencia: 1]
        case .stepTraining: return [.resistencia: 0.6, .agilidade: 0.4]
        default: return nil
        }
    }

    // MARK: Contas

    /// Leva `amount` (0…1) do total para `attr`, tirando dos outros na proporção de cada um
    static func shift(_ w: Weights, to attr: Attribute, _ amount: Double) -> Weights {
        let total = w.values.reduce(0, +)
        guard total > 0 else { return [attr: 1] }
        var out = w.mapValues { $0 / total * (1 - amount) }
        out[attr, default: 0] += amount
        return out
    }

    private static func mix(_ a: Weights, _ wa: Double, _ b: Weights, _ wb: Double) -> Weights {
        var out = a.mapValues { $0 * wa }
        for (k, v) in b { out[k, default: 0] += v * wb }
        return out
    }

    private static func average(_ list: [Weights]) -> Weights {
        guard !list.isEmpty else { return [:] }
        var out: Weights = [:]
        for w in list { for (k, v) in w { out[k, default: 0] += v / Double(list.count) } }
        return out
    }

    /// Soma 1, sem migalhas (< 3%), com duas casas
    static func tidy(_ w: Weights) -> Weights {
        let total = w.values.reduce(0, +)
        guard total > 0 else { return [.forca: 0.25, .resistencia: 0.25, .agilidade: 0.25, .tecnica: 0.25] }
        let kept = w.filter { $0.value / total >= 0.03 }
        let sum = kept.values.reduce(0, +)
        var out = kept.mapValues { ($0 / sum * 100).rounded() / 100 }
        // Arredondamento: o resto vai para o maior
        if let top = out.max(by: { $0.value < $1.value })?.key { out[top]! += 1 - out.values.reduce(0, +) }
        return out
    }

    // MARK: Texto guardado

    static func encode(_ w: Weights) -> String {
        Attribute.allCases.compactMap { a in w[a].map { "\(a.rawValue):\(String(format: "%.2f", $0))" } }.joined(separator: ",")
    }

    static func decode(_ s: String) -> Weights? {
        let w: Weights = s.split(separator: ",").reduce(into: [:]) { acc, pair in
            let p = pair.split(separator: ":")
            if p.count == 2, let a = Attribute(rawValue: String(p[0])), let v = Double(p[1]) { acc[a] = v }
        }
        return w.isEmpty ? nil : w
    }
}

// MARK: - Divisão guardada de cada atividade

/// Divisão calculada quando a atividade foi salva, por id. Fica fora do SwiftData para não mexer no schema publicado;
/// vai junto no backup. Sem entrada, a atividade usa a tabela fixa da categoria (como sempre foi).
enum ActivitySplits {
    static let key = "activitySplits"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: String]?

    static func all() -> [String: String] {
        lock.lock(); defer { lock.unlock() }
        if let cache { return cache }
        let loaded = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        cache = loaded
        return loaded
    }

    static func weights(_ id: UUID) -> AttributeSplit.Weights? { all()[id.uuidString].flatMap(AttributeSplit.decode) }

    static func set(_ w: AttributeSplit.Weights?, for id: UUID) {
        var d = all()
        d[id.uuidString] = w.map(AttributeSplit.encode)
        replace(d)
    }

    static func replace(_ d: [String: String]) {
        lock.lock()
        cache = d
        lock.unlock()
        UserDefaults.standard.set(d, forKey: key)
    }

    /// Calcula e guarda a divisão da atividade, com o detalhe do treino ligado a ela (séries ou WOD), se houver
    @MainActor
    @discardableResult
    static func stamp(_ a: Activity, context: ModelContext) -> AttributeSplit.Weights {
        let id = a.uuid
        var s = AttributeSplit.Signals(kind: a.kind, minutes: a.minutes, effort: a.effort, meters: a.meters,
                                       healthType: a.healthType.map(UInt.init))
        if let session = try? context.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.activityUUID == id })).first {
            s.sets = session.doneWorkSets.map { AttributeSplit.SetSignal(exerciseID: $0.exerciseID, reps: $0.reps, rest: $0.rest) }
        }
        if let r = try? context.fetch(FetchDescriptor<WodResult>(predicate: #Predicate { $0.activityUUID == id })).first,
           let wod = Wod.byID(r.wodID) ?? WodPlan.all().first(where: { $0.wodID == r.wodID })?.wod {
            s.wod = AttributeSplit.WodSignal(format: wod.format, exercises: wod.exercises.isEmpty ? WodMovements.ids(wod.lines) : wod.exercises)
        }
        let w = AttributeSplit.split(s)
        set(w, for: id)
        return w
    }
}
