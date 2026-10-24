import Foundation
import SwiftData

/// Vídeo de demonstração de um exercício, vindo de uma importação (hoje: MFIT).
/// Guardado por exerciseID para aparecer no detalhe do exercício, tanto em exercícios
/// casados com o catálogo quanto nos personalizados criados na importação.
@Model
final class ExerciseMedia {
    var exerciseID: String = ""
    var videoURL: String = ""

    init(exerciseID: String, videoURL: String) {
        self.exerciseID = exerciseID
        self.videoURL = videoURL
    }
}
