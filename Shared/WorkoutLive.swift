import ActivityKit
import Foundation

/// Live Activity do treino em andamento (tela de bloqueio e Dynamic Island)
struct WorkoutAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Exercício que a pessoa marcou como "fazendo agora"
        var exercise: String
        /// Próxima série a fazer neste exercício (1…setCount); setCount + 1 quando todas estão feitas
        var setNumber: Int
        var setCount: Int
        /// Carga e reps da próxima série (ex.: "50 kg × 10")
        var setText: String
        var doneSets: Int
        var totalSets: Int
        /// Fim do descanso, enquanto descansa
        var restEnd: Date?
        /// Arte do bro principal
        var sprite: String

        var progress: Double { totalSets == 0 ? 0 : Double(doneSets) / Double(totalSets) }
        var exerciseDone: Bool { setNumber > setCount }
    }

    var title: String
    var start: Date
}

/// Live Activity do WOD em andamento (cronômetro na tela de bloqueio e na Dynamic Island)
struct WodAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Conta para cima (For Time) ou para baixo até `end` (AMRAP, EMOM, Tabata)
        var countsDown: Bool
        /// Início ajustado pelas pausas (o cronômetro mostra agora − start)
        var start: Date
        var end: Date?
        /// Pausado: mostra o tempo parado em texto
        var pausedText: String?
        var rounds: Int
        var showRounds: Bool
        /// Ex.: "Minuto 3 de 20", "Rodada 2/8 · ESFORÇO"
        var label: String
    }

    var name: String
    var format: String
}
