import Foundation
import MuscleMap

enum MuscleGroup: String, CaseIterable, Identifiable {
    case peito, costas, ombros, biceps, triceps, antebraco, quadriceps, posterior, gluteos, panturrilha, abdomen, corpo

    var id: String { rawValue }

    var name: String {
        switch self {
        case .peito: "Peito"
        case .costas: "Costas"
        case .ombros: "Ombros"
        case .biceps: "Bíceps"
        case .triceps: "Tríceps"
        case .antebraco: "Antebraço"
        case .quadriceps: "Quadríceps"
        case .posterior: "Posterior"
        case .gluteos: "Glúteos"
        case .panturrilha: "Panturrilha"
        case .abdomen: "Abdômen"
        case .corpo: "Corpo todo"
        }
    }

    /// Grupos em que um salto de 5 kg é normal
    var heavy: Bool { [.costas, .quadriceps, .posterior, .gluteos, .panturrilha].contains(self) }

    /// Músculos padrão, para exercícios personalizados
    var muscles: MuscleTargets {
        switch self {
        case .peito: MuscleTargets(primary: [.chest], secondary: [.deltoids, .triceps])
        case .costas: MuscleTargets(primary: [.upperBack], secondary: [.biceps, .trapezius])
        case .ombros: MuscleTargets(primary: [.deltoids], secondary: [.trapezius, .triceps])
        case .biceps: MuscleTargets(primary: [.biceps], secondary: [.forearm])
        case .triceps: MuscleTargets(primary: [.triceps], secondary: [])
        case .antebraco: MuscleTargets(primary: [.forearm], secondary: [])
        case .quadriceps: MuscleTargets(primary: [.quadriceps], secondary: [.gluteal, .hamstring])
        case .posterior: MuscleTargets(primary: [.hamstring], secondary: [.gluteal, .lowerBack])
        case .gluteos: MuscleTargets(primary: [.gluteal], secondary: [.hamstring])
        case .panturrilha: MuscleTargets(primary: [.calves], secondary: [])
        case .abdomen: MuscleTargets(primary: [.abs], secondary: [.obliques])
        case .corpo: MuscleTargets(primary: [.quadriceps, .chest, .upperBack], secondary: [.deltoids, .gluteal, .abs])
        }
    }

    var symbol: String {
        switch self {
        case .peito, .ombros, .triceps: "figure.arms.open"
        case .costas: "figure.rower"
        case .biceps, .antebraco: "dumbbell.fill"
        case .quadriceps, .posterior, .gluteos, .panturrilha: "figure.step.training"
        case .abdomen: "figure.core.training"
        case .corpo: "figure.cross.training"
        }
    }
}

enum ExerciseType: String, CaseIterable, Identifiable {
    /// Carga × repetições
    case weighted
    /// Peso do corpo: progride em repetições (carga extra opcional)
    case bodyweight
    /// Medido em segundos (prancha, isometria)
    case time

    var id: String { rawValue }

    var name: String {
        switch self {
        case .weighted: "Carga × reps"
        case .bodyweight: "Peso do corpo"
        case .time: "Por tempo"
        }
    }
}

struct Exercise: Identifiable, Hashable {
    let id: String
    let name: String
    let group: MuscleGroup
    let equipment: String
    var type: ExerciseType = .weighted
    /// Movimento de CrossFit (aparece na seção própria da biblioteca)
    var crossfit = false

    var increment: Double { group.heavy && equipment != "Halteres" ? 5 : 2.5 }

    var isCustom: Bool { id.hasPrefix("custom-") }
    /// Fotos embutidas no app (funcionam sem internet)
    var hasPhotos: Bool { ExerciseData.withPhotos.contains(id) }
    /// Fotos carregadas da internet (free-exercise-db) e guardadas em cache
    var remotePhotos: [URL]? {
        ExerciseExtraData.remote[id].map { folder in
            (0...1).compactMap { URL(string: "https://cdn.jsdelivr.net/gh/yuhonas/free-exercise-db@main/exercises/\(folder)/\($0).jpg") }
        }
    }
    var hasAnyPhoto: Bool { hasPhotos || remotePhotos != nil }

    /// Exercícios da biblioteca original que também são clássicos do CrossFit
    static let crossfitAlso: Set<String> = ["burpee", "thruster", "clean", "kettlebell-swing", "farmer-walk", "agachamento-frontal",
                                             "levantamento-terra", "barra-fixa", "flexao", "agachamento-livre-corpo", "abdominal",
                                             "desenvolvimento", "agachamento", "paralelas", "prancha"]
    var isCrossfit: Bool { crossfit || Exercise.crossfitAlso.contains(id) }

    /// Usa barra olímpica (polia e máquina não)
    var usesBar: Bool { equipment == "Barra" }
    /// A carga anotada já inclui a barra? CrossFit sempre; musculação conforme o ajuste (padrão: só anilhas)
    var weightIncludesBar: Bool { !usesBar || isCrossfit || UserDefaults.standard.bool(forKey: "barCountsBar") }
    /// Rótulo da carga na série
    var weightUnit: String { usesBar ? (weightIncludesBar ? "kg total" : "kg anilhas") : "kg" }
    var muscles: MuscleTargets { ExerciseData.muscles[id] ?? ExerciseExtraData.muscles[id] ?? group.muscles }
    /// Instruções em português (biblioteca original)
    var instructions: [String] { ExerciseInstructions.steps[id] ?? [] }
    /// Instruções originais em inglês, traduzidas na hora
    var englishInstructions: [String] { ExerciseExtraData.steps[id] ?? [] }
    /// Busca no YouTube de como fazer o exercício
    var videoURL: URL? {
        let q = "como fazer \(name) \(crossfit ? "crossfit" : "exercício")"
        return URL(string: "https://www.youtube.com/results?search_query=" + (q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""))
    }

    static func byID(_ id: String) -> Exercise? { index[id] ?? custom[id] }

    /// Exercícios criados pelo usuário (atualizado a partir do SwiftData)
    static var custom: [String: Exercise] = [:]

    static var all: [Exercise] { builtIn + custom.values.sorted { $0.name < $1.name } }

    static let equipments = ["Barra", "Halteres", "Máquina", "Polia", "Peso do corpo", "Kettlebell", "Elástico", "Corda", "Caixa", "Argola", "Bola", "Outro"]

    static func name(_ id: String) -> String { index[id]?.name ?? id }

    private static let index = Dictionary((library + extra).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    /// Biblioteca completa embutida (original + extras + CrossFit)
    static var builtIn: [Exercise] { library + extra }

    static let library: [Exercise] = [
        // Peito
        .init(id: "supino-reto", name: "Supino reto", group: .peito, equipment: "Barra"),
        .init(id: "supino-reto-halter", name: "Supino reto com halteres", group: .peito, equipment: "Halteres"),
        .init(id: "supino-inclinado", name: "Supino inclinado", group: .peito, equipment: "Barra"),
        .init(id: "supino-inclinado-halter", name: "Supino inclinado com halteres", group: .peito, equipment: "Halteres"),
        .init(id: "supino-declinado", name: "Supino declinado", group: .peito, equipment: "Barra"),
        .init(id: "supino-maquina", name: "Supino na máquina", group: .peito, equipment: "Máquina"),
        .init(id: "crucifixo", name: "Crucifixo", group: .peito, equipment: "Halteres"),
        .init(id: "peck-deck", name: "Peck deck", group: .peito, equipment: "Máquina"),
        .init(id: "crossover", name: "Crossover", group: .peito, equipment: "Polia"),
        .init(id: "flexao", name: "Flexão", group: .peito, equipment: "Peso do corpo", type: .bodyweight),
        .init(id: "paralelas", name: "Paralelas (mergulho)", group: .peito, equipment: "Peso do corpo", type: .bodyweight),
        // Costas
        .init(id: "barra-fixa", name: "Barra fixa", group: .costas, equipment: "Peso do corpo", type: .bodyweight),
        .init(id: "puxada-frente", name: "Puxada frontal", group: .costas, equipment: "Polia"),
        .init(id: "puxada-triangulo", name: "Puxada com triângulo", group: .costas, equipment: "Polia"),
        .init(id: "remada-curvada", name: "Remada curvada", group: .costas, equipment: "Barra"),
        .init(id: "remada-unilateral", name: "Remada unilateral", group: .costas, equipment: "Halteres"),
        .init(id: "remada-baixa", name: "Remada baixa", group: .costas, equipment: "Polia"),
        .init(id: "remada-cavalinho", name: "Remada cavalinho", group: .costas, equipment: "Barra"),
        .init(id: "remada-maquina", name: "Remada na máquina", group: .costas, equipment: "Máquina"),
        .init(id: "pulldown", name: "Pulldown braço reto", group: .costas, equipment: "Polia"),
        .init(id: "levantamento-terra", name: "Levantamento terra", group: .costas, equipment: "Barra"),
        .init(id: "hiperextensao", name: "Hiperextensão lombar", group: .costas, equipment: "Peso do corpo", type: .bodyweight),
        // Ombros
        .init(id: "desenvolvimento", name: "Desenvolvimento militar", group: .ombros, equipment: "Barra"),
        .init(id: "desenvolvimento-halter", name: "Desenvolvimento com halteres", group: .ombros, equipment: "Halteres"),
        .init(id: "desenvolvimento-maquina", name: "Desenvolvimento na máquina", group: .ombros, equipment: "Máquina"),
        .init(id: "elevacao-lateral", name: "Elevação lateral", group: .ombros, equipment: "Halteres"),
        .init(id: "elevacao-lateral-polia", name: "Elevação lateral na polia", group: .ombros, equipment: "Polia"),
        .init(id: "elevacao-frontal", name: "Elevação frontal", group: .ombros, equipment: "Halteres"),
        .init(id: "crucifixo-inverso", name: "Crucifixo inverso", group: .ombros, equipment: "Halteres"),
        .init(id: "face-pull", name: "Face pull", group: .ombros, equipment: "Polia"),
        .init(id: "encolhimento", name: "Encolhimento", group: .ombros, equipment: "Halteres"),
        // Bíceps
        .init(id: "rosca-direta", name: "Rosca direta", group: .biceps, equipment: "Barra"),
        .init(id: "rosca-alternada", name: "Rosca alternada", group: .biceps, equipment: "Halteres"),
        .init(id: "rosca-martelo", name: "Rosca martelo", group: .biceps, equipment: "Halteres"),
        .init(id: "rosca-scott", name: "Rosca Scott", group: .biceps, equipment: "Barra"),
        .init(id: "rosca-concentrada", name: "Rosca concentrada", group: .biceps, equipment: "Halteres"),
        .init(id: "rosca-polia", name: "Rosca na polia", group: .biceps, equipment: "Polia"),
        // Tríceps
        .init(id: "triceps-pulley", name: "Tríceps pulley", group: .triceps, equipment: "Polia"),
        .init(id: "triceps-corda", name: "Tríceps corda", group: .triceps, equipment: "Polia"),
        .init(id: "triceps-testa", name: "Tríceps testa", group: .triceps, equipment: "Barra"),
        .init(id: "triceps-frances", name: "Tríceps francês", group: .triceps, equipment: "Halteres"),
        .init(id: "supino-fechado", name: "Supino fechado", group: .triceps, equipment: "Barra"),
        .init(id: "mergulho-banco", name: "Mergulho no banco", group: .triceps, equipment: "Peso do corpo", type: .bodyweight),
        // Antebraço
        .init(id: "rosca-punho", name: "Rosca de punho", group: .antebraco, equipment: "Barra"),
        .init(id: "farmer-walk", name: "Caminhada do fazendeiro", group: .antebraco, equipment: "Halteres", type: .time),
        // Quadríceps
        .init(id: "agachamento", name: "Agachamento livre", group: .quadriceps, equipment: "Barra"),
        .init(id: "agachamento-frontal", name: "Agachamento frontal", group: .quadriceps, equipment: "Barra"),
        .init(id: "agachamento-smith", name: "Agachamento no Smith", group: .quadriceps, equipment: "Máquina"),
        .init(id: "agachamento-goblet", name: "Agachamento goblet", group: .quadriceps, equipment: "Halteres"),
        .init(id: "hack", name: "Agachamento hack", group: .quadriceps, equipment: "Máquina"),
        .init(id: "leg-press", name: "Leg press 45°", group: .quadriceps, equipment: "Máquina"),
        .init(id: "cadeira-extensora", name: "Cadeira extensora", group: .quadriceps, equipment: "Máquina"),
        .init(id: "afundo", name: "Afundo", group: .quadriceps, equipment: "Halteres"),
        .init(id: "bulgaro", name: "Agachamento búlgaro", group: .quadriceps, equipment: "Halteres"),
        .init(id: "agachamento-livre-corpo", name: "Agachamento sem carga", group: .quadriceps, equipment: "Peso do corpo", type: .bodyweight),
        // Posterior
        .init(id: "stiff", name: "Stiff", group: .posterior, equipment: "Barra"),
        .init(id: "terra-romeno", name: "Terra romeno", group: .posterior, equipment: "Barra"),
        .init(id: "mesa-flexora", name: "Mesa flexora", group: .posterior, equipment: "Máquina"),
        .init(id: "cadeira-flexora", name: "Cadeira flexora", group: .posterior, equipment: "Máquina"),
        .init(id: "good-morning", name: "Good morning", group: .posterior, equipment: "Barra"),
        // Glúteos
        .init(id: "elevacao-pelvica", name: "Elevação pélvica", group: .gluteos, equipment: "Barra"),
        .init(id: "cadeira-abdutora", name: "Cadeira abdutora", group: .gluteos, equipment: "Máquina"),
        .init(id: "gluteo-polia", name: "Glúteo na polia", group: .gluteos, equipment: "Polia"),
        .init(id: "cadeira-adutora", name: "Cadeira adutora", group: .gluteos, equipment: "Máquina"),
        // Panturrilha
        .init(id: "panturrilha-pe", name: "Panturrilha em pé", group: .panturrilha, equipment: "Máquina"),
        .init(id: "panturrilha-sentado", name: "Panturrilha sentado", group: .panturrilha, equipment: "Máquina"),
        .init(id: "panturrilha-leg", name: "Panturrilha no leg press", group: .panturrilha, equipment: "Máquina"),
        // Abdômen
        .init(id: "prancha", name: "Prancha", group: .abdomen, equipment: "Peso do corpo", type: .time),
        .init(id: "prancha-lateral", name: "Prancha lateral", group: .abdomen, equipment: "Peso do corpo", type: .time),
        .init(id: "abdominal", name: "Abdominal supra", group: .abdomen, equipment: "Peso do corpo", type: .bodyweight),
        .init(id: "abdominal-infra", name: "Abdominal infra", group: .abdomen, equipment: "Peso do corpo", type: .bodyweight),
        .init(id: "elevacao-pernas", name: "Elevação de pernas na barra", group: .abdomen, equipment: "Peso do corpo", type: .bodyweight),
        .init(id: "abdominal-polia", name: "Abdominal na polia", group: .abdomen, equipment: "Polia"),
        .init(id: "roda-abdominal", name: "Roda abdominal", group: .abdomen, equipment: "Peso do corpo", type: .bodyweight),
        // Corpo todo
        .init(id: "burpee", name: "Burpee", group: .corpo, equipment: "Peso do corpo", type: .bodyweight),
        .init(id: "kettlebell-swing", name: "Kettlebell swing", group: .corpo, equipment: "Kettlebell"),
        .init(id: "thruster", name: "Thruster", group: .corpo, equipment: "Barra"),
        .init(id: "clean", name: "Power clean", group: .corpo, equipment: "Barra"),
    ]
}
