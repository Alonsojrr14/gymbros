import Foundation
import SwiftData

/// Recorde pessoal registrado à mão (ex.: o que você já levantava antes de usar o app)
@Model
final class PersonalRecord {
    var uuid: UUID = UUID()
    var exerciseID: String = ""
    var weight: Double = 0
    var reps: Int = 1
    var date: Date = Date.now

    init(exerciseID: String, weight: Double, reps: Int, date: Date) {
        self.exerciseID = exerciseID
        self.weight = weight
        self.reps = reps
        self.date = date
    }

    var log: SetLog { SetLog(exerciseID: exerciseID, weight: weight, reps: reps, target: reps, done: true) }
}
