import Foundation
import SwiftData

@Model
final class CustomExercise {
    var uuid: UUID = UUID()
    var name: String = ""
    var groupRaw: String = MuscleGroup.corpo.rawValue
    var equipment: String = "Outro"
    var typeRaw: String = ExerciseType.weighted.rawValue
    var notes: String = ""

    init(name: String, group: MuscleGroup, equipment: String, type: ExerciseType, notes: String) {
        self.name = name
        self.groupRaw = group.rawValue
        self.equipment = equipment
        self.typeRaw = type.rawValue
        self.notes = notes
    }

    var exerciseID: String { "custom-\(uuid.uuidString)" }

    var exercise: Exercise {
        Exercise(id: exerciseID, name: name, group: MuscleGroup(rawValue: groupRaw) ?? .corpo,
                 equipment: equipment, type: ExerciseType(rawValue: typeRaw) ?? .weighted)
    }
}
