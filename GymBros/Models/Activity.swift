import Foundation
import SwiftData
import SwiftUI

@Model
final class Activity {
    var uuid: UUID = UUID()
    var kindRaw: String = ActivityKind.outro.rawValue
    var date: Date = Date.now
    var minutes: Int = 0
    var effort: Int = 5
    var note: String = ""
    /// UUID do treino no app Saúde, quando importado de lá
    var healthUUID: String?
    /// Tipo do treino no Apple Saúde (HKWorkoutActivityType), para o ovo saber o animal exato
    var healthType: Int?
    /// App ou aparelho de origem (ex.: "Apple Watch de Zero")
    var source: String?
    /// Monstro que recebe o XP quando a atividade não é postada em nenhuma liga
    var monsterUUID: UUID?
    /// Lugar de treino (academia) onde foi feita
    var gymUUID: UUID?
    /// Treino que o GymBros gravou no app Saúde para esta atividade
    var healthWrittenUUID: String?
    /// Distância em metros (GPS do app ou Apple Saúde)
    var meters: Double?
    /// Calorias ativas vindas do Apple Saúde
    var kcal: Double?

    init(kind: ActivityKind, date: Date, minutes: Int, effort: Int, note: String = "") {
        self.kindRaw = kind.rawValue
        self.date = date
        self.minutes = minutes
        self.effort = effort
        self.note = note
        self.monsterUUID = MainMonster.id
    }

    var kind: ActivityKind { ActivityKind(rawValue: kindRaw) ?? .outro }

    var record: ActivityRecord {
        ActivityRecord(id: uuid, kind: kind, date: date, minutes: minutes, effort: effort, healthType: healthType.map(UInt.init))
    }
}

// MARK: - Tema

extension Attribute {
    var color: Color {
        switch self {
        case .forca: Color(red: 1.0, green: 0.45, blue: 0.30)
        case .resistencia: Color(red: 0.35, green: 0.70, blue: 1.0)
        case .agilidade: Color(red: 0.98, green: 0.82, blue: 0.20)
        case .tecnica: Color(red: 0.72, green: 0.52, blue: 1.0)
        }
    }
}

func effortLabel(_ e: Int) -> String {
    switch e {
    case ...3: "Leve"
    case 4...6: "Moderado"
    case 7...8: "Intenso"
    default: "Máximo"
    }
}

func durationText(_ minutes: Int) -> String {
    minutes < 60 ? "\(minutes) min" : minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
}
