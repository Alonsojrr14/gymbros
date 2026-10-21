import Foundation

// Conversa entre o app do iPhone e o do relógio (WatchConnectivity). O iPhone é a fonte da verdade:
// manda o bro e o treino guiado em andamento; o relógio manda comandos do treino e as atividades gravadas lá.

/// Bro principal como o relógio mostra (app e complicações)
struct WatchBro: Codable, Equatable {
    var name: String
    var formName: String
    var stageName: String
    var moodEmoji: String
    var isEgg: Bool
    var level: Int
    var totalXP: Int
    var progress: Double
    var xpToNext: Int?
    var streak: Int
    var lastActivity: Date?
    var todayXP: Int
    /// Atributos de tudo o que ele já treinou (Attribute.rawValue → valor)
    var attributes: [String: Double]
    var updated: Date

    /// Sequência e XP do dia valendo para `date` (no dia seguinte sem treino, o XP de hoje zera)
    func at(_ date: Date, calendar: Calendar = .current) -> WatchBro {
        var b = self
        b.streak = Mood.liveStreak(streak, lastActivity: lastActivity, now: date, calendar: calendar)
        if !calendar.isDate(updated, inSameDayAs: date) { b.todayXP = 0 }
        return b
    }

    private static let key = "watchBro", spriteKey = "watchSprite"

    static func load() -> (bro: WatchBro, sprite: Data?)? {
        guard let data = WidgetData.defaults?.data(forKey: key),
              let bro = try? JSONDecoder().decode(WatchBro.self, from: data) else { return nil }
        return (bro, WidgetData.defaults?.data(forKey: spriteKey))
    }

    func save(sprite: Data?) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        WidgetData.defaults?.set(data, forKey: WatchBro.key)
        WidgetData.defaults?.set(sprite, forKey: WatchBro.spriteKey)
    }
}

/// Treino guiado em andamento no iPhone (mesmos dados do Live Activity)
struct WatchWorkout: Codable, Equatable {
    var title: String
    var start: Date
    var exercise: String
    var setNumber: Int
    var setCount: Int
    var setText: String
    var doneSets: Int
    var totalSets: Int
    var restEnd: Date?
    var restTotal: Int

    var exerciseDone: Bool { setNumber > setCount }
    var finished: Bool { totalSets > 0 && doneSets >= totalSets }
}

/// Atividade gravada no relógio; vira uma atividade no iPhone e dá XP ao bro
struct WatchActivity: Codable {
    var start: Date
    var minutes: Int
    var effort: Int
    var kcal: Double?
    var meters: Double?
    /// Treino gravado no Saúde pelo relógio (evita importar de novo pelo HealthSync)
    var healthUUID: String?
    /// HKWorkoutActivityType escolhido no relógio (decide a categoria e o XP no iPhone)
    var healthType: Int
}

/// Treino guiado do iPhone gravado também no relógio (batimentos e calorias): o treino do Saúde é do relógio
/// e a atividade (XP) é a do iPhone
struct WatchGuidedSaved: Codable {
    /// Início do treino guiado no iPhone (liga à atividade)
    var start: Date
    var healthUUID: String
    var kcal: Double?
}

/// Métricas da atividade livre gravada no relógio, espelhada no iPhone a cada poucos segundos
struct WatchLiveMetrics: Codable, Equatable {
    var typeID: Int
    var start: Date
    /// Tempo em movimento até `at` (sem as pausas)
    var elapsed: TimeInterval
    var at: Date
    var paused: Bool
    var heartRate: Double?
    var kcal: Double
    var meters: Double?

    func elapsed(now: Date) -> TimeInterval { paused ? elapsed : elapsed + max(now.timeIntervalSince(at), 0) }
}

enum WatchCommand: String {
    case completeSet, skipRest
    /// Musculação escolhida no relógio: começa o treino guiado no iPhone
    case startGuided
}

enum WatchKey {
    static let bro = "bro", sprite = "sprite", workout = "workout"
    static let command = "command", reply = "reply", activity = "activity"
    static let guidedStarted = "guidedStarted", guidedSaved = "guidedSaved"
}
