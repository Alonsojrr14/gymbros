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
