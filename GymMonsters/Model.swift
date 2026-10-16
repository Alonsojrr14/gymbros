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
    /// App ou aparelho de origem (ex.: "Apple Watch de Zero")
    var source: String?
    /// Monstro que recebe o XP quando a atividade não é postada em nenhuma liga
    var monsterUUID: UUID?

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
        ActivityRecord(id: uuid, kind: kind, date: date, minutes: minutes, effort: effort)
    }
}

// MARK: - Tema

enum Theme {
    static let bg = Color(red: 0.05, green: 0.06, blue: 0.08)
    static let card = Color(red: 0.10, green: 0.11, blue: 0.14)
    static let accent = Color(red: 0.64, green: 0.90, blue: 0.21)
    static let dim = Color.white.opacity(0.55)
}

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
