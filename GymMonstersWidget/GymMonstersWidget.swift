import SwiftUI
import WidgetKit

private let bg = Color(red: 0.05, green: 0.06, blue: 0.08)
private let accent = Color(red: 0.64, green: 0.90, blue: 0.21)
private let dim = Color.white.opacity(0.55)

struct Entry: TimelineEntry {
    let date: Date
    let data: WidgetData

    var mood: Mood { Mood.of(isEgg: data.isEgg, lastActivity: data.lastActivity, todayXP: data.todayXP, streak: data.streak, now: date) }
    var streak: Int { Mood.liveStreak(data.streak, lastActivity: data.lastActivity, now: date) }
    var trainedToday: Bool { data.lastActivity.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false }

    var line: String {
        let routine = data.todayRoutine[Calendar.current.component(.weekday, from: date)]
        switch mood {
        case .ovo: return data.totalXP == 0 ? "Toc toc…" : "Tá esquentando aqui!"
        case .exausto: return "Hoje já deu!"
        case .animado: return "\(streak) dias seguidos! 🔥"
        case .feliz:
            if !trainedToday, let routine { return "Hoje: \(routine)" }
            return trainedToday ? "Treino feito 💪" : "Bora treinar?"
        case .entediado: return routine.map { "Hoje: \($0)" } ?? "Tô entediado…"
        case .triste: return "Senti sua falta…"
        }
    }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now, data: .placeholder) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: .now, data: WidgetData.load() ?? .placeholder))
    }

    /// O humor muda com a virada do dia, então há uma entrada para cada meia-noite dos próximos dias
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let data = WidgetData.load() ?? .placeholder
        let cal = Calendar.current
        var entries = [Entry(date: .now, data: data)]
        for d in 1...3 {
            if let day = cal.date(byAdding: .day, value: d, to: cal.startOfDay(for: .now)) {
                entries.append(Entry(date: day.addingTimeInterval(60), data: data))
            }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct Sprite: View {
    let data: WidgetData
    let mood: Mood

    var body: some View {
        Image(data.sprite)
            .resizable()
            .interpolation(.none)
            .scaledToFit()
            .hueRotation(.degrees(data.hue))
            .saturation(mood == .triste ? 0.35 : mood == .entediado ? 0.7 : 1)
    }
}

struct XPBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                Capsule().fill(accent).frame(width: max(g.size.width * progress, 4))
            }
        }
        .frame(height: 6)
    }
}

struct WidgetView: View {
    let entry: Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .systemMedium: medium
        default: small
        }
    }

    private var d: WidgetData { entry.data }

    private var small: some View {
        VStack(spacing: 6) {
            HStack {
                Text(entry.mood.emoji)
                Spacer()
                if entry.streak > 0 {
                    Label("\(entry.streak)", systemImage: "flame.fill").foregroundStyle(.orange)
                }
            }
            .font(.caption.bold())
            Sprite(data: d, mood: entry.mood).frame(maxHeight: .infinity)
            Text(d.monsterName).font(.caption.bold()).lineLimit(1)
            if let e = d.event(at: entry.date) {
                Text(e).font(.system(size: 10, weight: .semibold)).foregroundStyle(accent).lineLimit(1).minimumScaleFactor(0.7)
            }
            XPBar(progress: d.progress)
        }
        .foregroundStyle(.white)
        .containerBackground(bg, for: .widget)
    }

    private var medium: some View {
        HStack(spacing: 14) {
            Sprite(data: d, mood: entry.mood).frame(width: 110)
            VStack(alignment: .leading, spacing: 6) {
                Text(d.monsterName).font(.headline)
                Text(d.isEgg ? d.stageName : "\(d.stageName) · Nível \(d.level)")
                    .font(.caption)
                    .foregroundStyle(dim)
                if let e = d.event(at: entry.date) {
                    Text(e).font(.caption.bold()).foregroundStyle(accent).lineLimit(2)
                } else {
                    Text("\(entry.mood.emoji) \(entry.line)").font(.caption).lineLimit(2)
                }
                Spacer(minLength: 0)
                XPBar(progress: d.progress)
                HStack {
                    Text(d.xpToNext.map { d.isEgg ? "\($0) XP para chocar" : "\($0) XP para evoluir" } ?? "forma final")
                    Spacer()
                    if entry.streak > 0 {
                        Label("\(entry.streak)", systemImage: "flame.fill").foregroundStyle(.orange)
                    }
                }
                .font(.caption2.bold())
                .foregroundStyle(dim)
            }
        }
        .foregroundStyle(.white)
        .containerBackground(bg, for: .widget)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(entry.mood.emoji) \(d.monsterName)").font(.headline).lineLimit(1)
            Text(d.event(at: entry.date) ?? (d.isEgg ? "\(d.xpToNext ?? 0) XP para chocar" : "Nível \(d.level)\(entry.streak > 0 ? " · 🔥\(entry.streak)" : "")"))
                .font(.caption)
                .lineLimit(1)
            Gauge(value: d.progress) {}.gaugeStyle(.accessoryLinearCapacity)
        }
        .containerBackground(.clear, for: .widget)
    }

    private var circular: some View {
        Gauge(value: d.progress) {
            Text("Nv")
        } currentValueLabel: {
            Text(d.isEgg ? "🥚" : "\(d.level)")
        }
        .gaugeStyle(.accessoryCircular)
        .containerBackground(.clear, for: .widget)
    }
}

@main
struct GymMonstersWidgets: WidgetBundle {
    var body: some Widget {
        PetWidget()
        GymMonstersWidget()
        WorkoutLiveActivity()
        WodLiveActivity()
        if #available(iOS 18.0, *) {
            CompleteSetControl()
            SkipRestControl()
        }
    }
}

struct GymMonstersWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GymMonsters", provider: Provider()) { WidgetView(entry: $0) }
            .configurationDisplayName("Status do bro")
            .description("Humor, nível e sequência do seu bro.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}
