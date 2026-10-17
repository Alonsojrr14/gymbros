import HealthKit

/// Qual animal nasce de cada atividade. A espécie sai da atividade com mais da metade dos minutos que chocaram o ovo;
/// sem atividade principal (ou com "Outro"), nasce o Coelho. Urso e Rato dividem musculação e crossfit
/// (o sorteio entre os dois é fixo pelo id do bro).
enum Hatch {
    /// Fatia mínima dos minutos do ovo para a atividade principal decidir a espécie
    static let majority = 0.5

    /// Espécies candidatas de cada atividade registrada no app
    static func species(for kind: ActivityKind) -> [String] {
        switch kind {
        case .musculacao, .crossfit: ["urso", "rato"]
        case .corrida, .bike, .natacao: ["lobo"]
        case .caminhada, .futebol: ["cachorro"]
        case .volei: ["esquilo"]
        case .lutas, .danca: ["gato"]
        case .yoga: ["coruja"]
        case .outro: ["coelho"]
        }
    }

    /// Atividade importada do Apple Saúde: usa o tipo exato do treino (tênis, escalada, golfe…), não só a categoria
    static func species(forHealth raw: UInt) -> [String] {
        guard let type = HKWorkoutActivityType(rawValue: raw) else { return ["coelho"] }
        return species(for: type)
    }

    static func species(_ r: ActivityRecord) -> [String] {
        r.healthType.map(species(forHealth:)) ?? species(for: r.kind)
    }

    // Todas as atividades do Apple Saúde têm um animal (o switch não tem `default` para tipos conhecidos)
    static func species(for type: HKWorkoutActivityType) -> [String] {
        switch type {
        // Urso e Rato: força e treinos intensos
        case .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining, .crossTraining,
             .highIntensityIntervalTraining, .mixedCardio, .jumpRope, .stairClimbing, .stairs, .stepTraining:
            ["urso", "rato"]
        // Lobo: resistência (correr, pedalar, nadar, remar, esquiar longe)
        case .running, .trackAndField, .cycling, .handCycling, .wheelchairRunPace, .swimming, .waterFitness,
             .rowing, .paddleSports, .crossCountrySkiing, .swimBikeRun, .elliptical, .underwaterDiving:
            ["lobo"]
        // Cachorro: passeio, trilha e esportes de bola em time
        case .walking, .hiking, .wheelchairWalkPace, .soccer, .americanFootball, .australianFootball, .rugby,
             .basketball, .handball, .hockey, .lacrosse, .baseball, .softball, .cricket, .waterPolo, .discSports,
             .play, .equestrianSports, .hunting:
            ["cachorro"]
        // Esquilo: saltos, escalada, raquete e prancha
        case .volleyball, .climbing, .gymnastics, .tennis, .tableTennis, .badminton, .squash, .racquetball,
             .pickleball, .skatingSports, .snowboarding, .downhillSkiing, .snowSports, .surfingSports, .waterSports:
            ["esquilo"]
        // Gato: lutas e dança
        case .martialArts, .boxing, .kickboxing, .wrestling, .fencing, .cardioDance, .socialDance, .barre:
            ["gato"]
        // Coruja: foco, precisão e calma
        case .yoga, .pilates, .flexibility, .mindAndBody, .taiChi, .preparationAndRecovery, .cooldown, .golf,
             .archery, .bowling, .curling, .sailing, .fishing:
            ["coruja"]
        // Coelho: outros e treinos de tudo um pouco
        case .other, .fitnessGaming, .transition:
            ["coelho"]
        // Tipos antigos que a Apple aposentou
        case .dance, .danceInspiredTraining: ["gato"]
        case .mixedMetabolicCardioTraining: ["urso", "rato"]
        @unknown default:
            ["coelho"]
        }
    }
}
