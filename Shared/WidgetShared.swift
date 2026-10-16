import Foundation

// Compartilhado entre o app e o widget (pasta incluída nos dois alvos)

enum Mood: String, Codable {
    case ovo, animado, feliz, entediado, triste, exausto

    var emoji: String {
        switch self {
        case .ovo: "🥚"
        case .animado: "🤩"
        case .feliz: "😊"
        case .entediado: "🥱"
        case .triste: "😢"
        case .exausto: "🥵"
        }
    }

    var name: String {
        switch self {
        case .ovo: "Chocando"
        case .animado: "Animado"
        case .feliz: "Feliz"
        case .entediado: "Entediado"
        case .triste: "Triste"
        case .exausto: "Exausto"
        }
    }

    /// Humor do dia, só a partir de quando foi o último treino e quanto já treinou hoje
    static func of(isEgg: Bool, lastActivity: Date?, todayXP: Int, streak: Int, now: Date = .now,
                   calendar: Calendar = .current) -> Mood {
        if isEgg { return .ovo }
        guard let last = lastActivity else { return .entediado }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ...0: return todayXP >= 300 ? .exausto : streak >= 3 ? .animado : .feliz
        case 1: return .feliz
        case 2...3: return .entediado
        default: return .triste
        }
    }

    /// Sequência ainda vale se o último treino foi hoje ou ontem
    static func liveStreak(_ streak: Int, lastActivity: Date?, now: Date = .now, calendar: Calendar = .current) -> Int {
        guard let last = lastActivity else { return 0 }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: calendar.startOfDay(for: now)).day ?? 0
        return days <= 1 ? streak : 0
    }
}

/// O que o widget mostra; o app grava a cada mudança
struct WidgetData: Codable {
    var monsterName: String
    var formName: String
    var stageName: String
    var sprite: String
    var hue: Double
    var isEgg: Bool
    var level: Int
    var totalXP: Int
    var progress: Double
    var xpToNext: Int?
    var streak: Int
    var lastActivity: Date?
    var todayXP: Int
    var todayRoutine: [Int: String] // dia da semana → nome da rotina
    var updated: Date

    static let appGroup = "group.com.alonsoalmeida.gymmonsters"
    private static let key = "widgetData"

    static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static func load() -> WidgetData? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetData.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        WidgetData.defaults?.set(data, forKey: WidgetData.key)
    }

    static let placeholder = WidgetData(monsterName: "Gymmon", formName: "Gymmon", stageName: "Bebê", sprite: "sprite_baby", hue: 0,
                                        isEgg: false, level: 4, totalXP: 80, progress: 0.1, xpToNext: 220, streak: 3,
                                        lastActivity: .now, todayXP: 30, todayRoutine: [:], updated: .now)
}
