import Foundation
import SwiftData

@Model
final class BodyEntry {
    var uuid: UUID = UUID()
    var date: Date = Date.now
    var weight: Double?
    var waist: Double?
    var chest: Double?
    var arm: Double?
    var thigh: Double?
    var hip: Double?
    /// UUID da amostra no app Saúde, quando importada de lá
    var healthUUID: String?
    /// Fotos de progresso (frente e lado)
    @Attribute(.externalStorage) var photoFront: Data?
    @Attribute(.externalStorage) var photoSide: Data?

    init(date: Date, weight: Double? = nil) {
        self.date = date
        self.weight = weight
    }

    var hasMeasures: Bool { [waist, chest, arm, thigh, hip].contains { $0 != nil } }
}

enum Measure: String, CaseIterable, Identifiable {
    case waist, chest, arm, thigh, hip

    var id: String { rawValue }

    var name: String {
        switch self {
        case .waist: "Cintura"
        case .chest: "Peito"
        case .arm: "Braço"
        case .thigh: "Coxa"
        case .hip: "Quadril"
        }
    }

    func value(_ e: BodyEntry) -> Double? {
        switch self {
        case .waist: e.waist
        case .chest: e.chest
        case .arm: e.arm
        case .thigh: e.thigh
        case .hip: e.hip
        }
    }

    func set(_ e: BodyEntry, _ v: Double?) {
        switch self {
        case .waist: e.waist = v
        case .chest: e.chest = v
        case .arm: e.arm = v
        case .thigh: e.thigh = v
        case .hip: e.hip = v
        }
    }
}

@Model
final class ExerciseNote {
    var exerciseID: String = ""
    var text: String = ""
    var updated: Date = Date.now

    init(exerciseID: String, text: String) {
        self.exerciseID = exerciseID
        self.text = text
    }
}
