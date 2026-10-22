import Foundation
import HealthKit

// Metas pessoais com cadência e recordes de constância, derivados das atividades.
// As metas ficam em `personalGoals` (JSON no UserDefaults, vai com a conta).

enum GoalMetric: String, Codable, CaseIterable, Identifiable {
    case checkIns, daysActive, minutes, distance, calories

    var id: String { rawValue }

    var name: String {
        switch self {
        case .checkIns: "Treinos"
        case .daysActive: "Dias ativos"
        case .minutes: "Minutos"
        case .distance: "Distância"
        case .calories: "Calorias"
        }
    }

    /// "4 treinos", "200 dias ativos", "3 h", "8 km", "1000 kcal"
    func format(_ v: Double) -> String {
        let n = Int(v.rounded())
        switch self {
        case .checkIns: return "\(n) treino\(n == 1 ? "" : "s")"
        case .daysActive: return "\(n) dia\(n == 1 ? "" : "s") ativo\(n == 1 ? "" : "s")"
        case .minutes: return hoursText(n)
        case .distance: return (v == v.rounded() ? "\(n)" : v.formatted(.number.precision(.fractionLength(1)))) + " km"
        case .calories: return "\(n) kcal"
        }
    }

    /// Passo do stepper do alvo
    var step: Double {
        switch self {
        case .checkIns, .daysActive: 1
        case .minutes: 15
        case .distance: 1
        case .calories: 50
        }
    }
}

enum GoalCadence: String, Codable, CaseIterable, Identifiable {
    case daily, weekly, monthly, yearly

    var id: String { rawValue }

    var name: String {
        switch self {
        case .daily: "Dia"
        case .weekly: "Semana"
        case .monthly: "Mês"
        case .yearly: "Ano"
        }
    }

    /// "por dia", "por semana"…
    var per: String {
        switch self {
        case .daily: "por dia"
        case .weekly: "por semana"
        case .monthly: "por mês"
        case .yearly: "por ano"
        }
    }

    /// "dia", "semana" no plural: "3 semanas"
    func count(_ n: Int) -> String {
        switch self {
        case .daily: "\(n) dia\(n == 1 ? "" : "s")"
        case .weekly: "\(n) semana\(n == 1 ? "" : "s")"
        case .monthly: n == 1 ? "1 mês" : "\(n) meses"
        case .yearly: "\(n) ano\(n == 1 ? "" : "s")"
        }
    }

    var component: Calendar.Component {
        switch self {
        case .daily: .day
        case .weekly: .weekOfYear
        case .monthly: .month
        case .yearly: .year
        }
    }
}

struct PersonalGoal: Codable, Hashable, Identifiable {
    var id = UUID()
    var name = ""
    var emoji = "🎯"
    var metric = GoalMetric.checkIns
    var amount: Double = 4
    var cadence = GoalCadence.weekly
    /// Meta com prazo: conta tudo do início até a data (sem repetir por período)
    var targetDate: Date?
    var start = Calendar.current.startOfDay(for: .now)
    /// Tipos de treino que contam (`WorkoutType.id`); vazio = todos
    var activityTypes: [UInt] = []

    var title: String { name.isEmpty ? "\(metric.format(amount)) \(targetDate == nil ? cadence.per : "até \(targetDate!.formatted(.dateTime.day().month(.abbreviated)))")" : name }

    var summary: String {
        let what = activityTypes.isEmpty ? "" : " · " + activityTypes.compactMap { WorkoutType.byID($0)?.name }.prefix(3).joined(separator: ", ")
        if let targetDate { return "\(metric.format(amount)) até \(targetDate.formatted(.dateTime.day().month(.abbreviated).year()))" + what }
        return "\(metric.format(amount)) \(cadence.per)" + what
    }

    func counts(_ a: Activity) -> Bool { activityTypes.isEmpty || activityTypes.contains(a.workoutType.id) }

    /// Quanto as atividades somam na métrica (dias ativos = dias distintos)
    func value(_ list: [Activity], calendar: Calendar = .current) -> Double {
        let l = list.filter(counts)
        switch metric {
        case .checkIns: return Double(l.count)
        case .daysActive: return Double(Set(l.map { calendar.startOfDay(for: $0.date) }).count)
        case .minutes: return Double(l.reduce(0) { $0 + $1.minutes })
        case .distance: return l.reduce(0) { $0 + ($1.meters ?? 0) } / 1000
        case .calories:
            return l.reduce(0) { $0 + ($1.kcal ?? HealthSync.activeKcal(kind: $1.kind, minutes: $1.minutes, effort: $1.effort, weight: LeagueScoring.referenceWeight)) }
        }
    }

    struct Period: Identifiable {
        let start: Date
        let end: Date
        let value: Double
        let met: Bool
        var id: Date { start }
    }

    /// Períodos desde o início da meta até o atual (o último é o que está acontecendo)
    func periods(_ activities: [Activity], now: Date = .now, calendar: Calendar = .current) -> [Period] {
        if let targetDate {
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: targetDate))!
            let v = value(activities.filter { $0.date >= start && $0.date < end }, calendar: calendar)
            return [Period(start: start, end: end, value: v, met: v >= amount)]
        }
        guard var interval = calendar.dateInterval(of: cadence.component, for: start) else { return [] }
        var out: [Period] = []
        while interval.start <= now {
            let v = value(activities.filter { interval.contains($0.date) }, calendar: calendar)
            out.append(Period(start: interval.start, end: interval.end, value: v, met: v >= amount))
            guard let next = calendar.dateInterval(of: cadence.component, for: interval.end) else { break }
            interval = next
        }
        return out
    }

    /// Sequência atual: períodos seguidos batendo a meta. O período atual só soma quando bater, e não quebra antes de acabar.
    func streak(_ periods: [Period]) -> Int {
        var list = periods
        if let last = list.last, !last.met { list.removeLast() }
        var n = 0
        for p in list.reversed() { if p.met { n += 1 } else { break } }
        return n
    }

    func bestStreak(_ periods: [Period]) -> Int {
        var best = 0, cur = 0
        for p in periods { cur = p.met ? cur + 1 : 0; best = max(best, cur) }
        return best
    }
}

@MainActor
enum PersonalGoals {
    static let key = "personalGoals"

    static func all(_ defaults: UserDefaults = .standard) -> [PersonalGoal] {
        if let text = defaults.string(forKey: key), let list = try? JSONDecoder().decode([PersonalGoal].self, from: Data(text.utf8)) { return list }
        // Primeira vez: as duas metas que já existiam viram metas da lista
        let weekly = defaults.object(forKey: "goalWeekly") as? Int ?? 4
        let minutes = defaults.object(forKey: "goalMinutes") as? Int ?? 180
        return [PersonalGoal(emoji: "💪", metric: .checkIns, amount: Double(weekly), cadence: .weekly),
                PersonalGoal(emoji: "⏱️", metric: .minutes, amount: Double(minutes), cadence: .weekly)]
    }

    static func save(_ list: [PersonalGoal], _ defaults: UserDefaults = .standard) {
        // Texto (não Data): o backup só leva textos, números e sim/não
        defaults.set((try? JSONEncoder().encode(list)).flatMap { String(data: $0, encoding: .utf8) }, forKey: key)
    }

    /// Modelos prontos (os mesmos temas do GymRats, em km)
    static var templates: [PersonalGoal] {
        let y = Calendar.current.component(.year, from: .now)
        let endOfYear = Calendar.current.date(from: DateComponents(year: y, month: 12, day: 31))
        let t = { (h: HKWorkoutActivityType) in UInt(h.rawValue) }
        return [
            PersonalGoal(name: "O clássico do bro", emoji: "💪", metric: .checkIns, amount: 4, cadence: .weekly),
            PersonalGoal(name: "Corre que dá tempo", emoji: "🏃", metric: .distance, amount: 8, cadence: .weekly, activityTypes: [t(.running)]),
            PersonalGoal(name: "Modo fera ativado", emoji: "🏋️", metric: .checkIns, amount: 3, cadence: .weekly, activityTypes: [t(.traditionalStrengthTraining), t(.functionalStrengthTraining)]),
            PersonalGoal(name: "Zen e flexível", emoji: "🧘", metric: .checkIns, amount: 1, cadence: .daily, activityTypes: [t(.yoga)]),
            PersonalGoal(name: "Rumo aos 42 km", emoji: "🏃‍♀️", metric: .distance, amount: 32, cadence: .weekly, activityTypes: [t(.running)]),
            PersonalGoal(name: "Queima total", emoji: "🔥", metric: .calories, amount: 1000, cadence: .daily),
            PersonalGoal(name: "Momentos de calma", emoji: "🧠", metric: .checkIns, amount: 1, cadence: .monthly, activityTypes: [t(.mindAndBody)]),
            PersonalGoal(name: "Estica aí", emoji: "🤸", metric: .checkIns, amount: 3, cadence: .weekly, activityTypes: [t(.flexibility)]),
            PersonalGoal(name: "Intensidade no intervalo", emoji: "⚡", metric: .checkIns, amount: 2, cadence: .weekly, activityTypes: [t(.highIntensityIntervalTraining)]),
            PersonalGoal(name: "Constância é tudo", emoji: "👑", metric: .checkIns, amount: 1, cadence: .weekly),
            PersonalGoal(name: "#200", emoji: "🗓️", metric: .daysActive, amount: 200, cadence: .yearly, targetDate: endOfYear,
                         start: Calendar.current.date(from: DateComponents(year: y, month: 1, day: 1)) ?? .now),
        ]
    }
}

// MARK: - Recordes de constância

struct StreakRun {
    let length: Int
    let start: Date
    let end: Date
    /// Ainda valendo (termina no período atual ou no anterior)
    let ongoing: Bool
}

struct Constancy {
    var daily: (current: StreakRun?, best: StreakRun?)
    var weekly: (current: StreakRun?, best: StreakRun?)
    var monthly: (current: StreakRun?, best: StreakRun?)
    /// Mais minutos num dia
    var bestDay: (date: Date, minutes: Int)?
    /// Mais dias ativos numa semana, num mês, num ano
    var bestWeek: (start: Date, days: Int)?
    var bestMonth: (start: Date, days: Int)?
    var bestYear: (start: Date, days: Int)?
    /// Dia da semana (1 = domingo) e hora com mais dias diferentes de treino
    var topWeekday: (weekday: Int, days: Int)?
    var topHour: (hour: Int, days: Int)?
    var earlyBird = 0
    var nightOwl = 0

    /// Madrugador: treino que começou antes das 7 h; coruja: a partir das 21 h
    static let earlyHour = 7, lateHour = 21

    static func of(_ activities: [Activity], now: Date = .now, calendar cal: Calendar = .current) -> Constancy {
        let days = Set(activities.map { cal.startOfDay(for: $0.date) })
        func runs(_ comp: Calendar.Component) -> (StreakRun?, StreakRun?) {
            let keys = Set(days.compactMap { cal.dateInterval(of: comp, for: $0)?.start })
            guard !keys.isEmpty, let nowKey = cal.dateInterval(of: comp, for: now)?.start,
                  let prevKey = cal.date(byAdding: comp, value: -1, to: nowKey) else { return (nil, nil) }
            var all: [StreakRun] = []
            for k in keys.sorted() {
                guard let prev = cal.date(byAdding: comp, value: -1, to: k), !keys.contains(prev) else { continue }
                var n = 1, cur = k
                while let next = cal.date(byAdding: comp, value: 1, to: cur), keys.contains(next) { n += 1; cur = next }
                all.append(StreakRun(length: n, start: k, end: cur, ongoing: cur == nowKey || cur == prevKey))
            }
            let best = all.max { ($0.length, $0.end) < ($1.length, $1.end) }
            return (all.first { $0.ongoing }, best)
        }
        var c = Constancy(daily: runs(.day), weekly: runs(.weekOfYear), monthly: runs(.month))
        let byDay = Dictionary(grouping: activities) { cal.startOfDay(for: $0.date) }
        if let d = byDay.max(by: { $0.value.reduce(0) { $0 + $1.minutes } < $1.value.reduce(0) { $0 + $1.minutes } }) {
            c.bestDay = (d.key, d.value.reduce(0) { $0 + $1.minutes })
        }
        func best(_ comp: Calendar.Component) -> (Date, Int)? {
            Dictionary(grouping: days) { cal.dateInterval(of: comp, for: $0)?.start ?? $0 }
                .max { ($0.value.count, $0.key) < ($1.value.count, $1.key) }.map { ($0.key, $0.value.count) }
        }
        c.bestWeek = best(.weekOfYear)
        c.bestMonth = best(.month)
        c.bestYear = best(.year)
        c.topWeekday = Dictionary(grouping: days) { cal.component(.weekday, from: $0) }.max { $0.value.count < $1.value.count }.map { ($0.key, $0.value.count) }
        let hourDays = Dictionary(grouping: activities) { cal.component(.hour, from: $0.date) }.mapValues { Set($0.map { cal.startOfDay(for: $0.date) }).count }
        c.topHour = hourDays.max { $0.value < $1.value }.map { ($0.key, $0.value) }
        c.earlyBird = activities.filter { cal.component(.hour, from: $0.date) < earlyHour }.count
        c.nightOwl = activities.filter { cal.component(.hour, from: $0.date) >= lateHour }.count
        return c
    }
}
