import SwiftUI
import WidgetKit

struct BroEntry: TimelineEntry {
    let date: Date
    let bro: WatchBro?
    let sprite: UIImage?
}

/// O app do relógio recarrega a cada mudança; a virada do dia zera o XP de hoje e confere a sequência
struct BroProvider: TimelineProvider {
    func placeholder(in context: Context) -> BroEntry { BroEntry(date: .now, bro: .preview, sprite: nil) }

    func getSnapshot(in context: Context, completion: @escaping (BroEntry) -> Void) {
        completion(entry(at: .now) ?? placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BroEntry>) -> Void) {
        let midnight = Calendar.current.startOfDay(for: .now.addingTimeInterval(86400))
        let entries = [entry(at: .now), entry(at: midnight)].compactMap { $0 }
        completion(Timeline(entries: entries.isEmpty ? [BroEntry(date: .now, bro: nil, sprite: nil)] : entries, policy: .never))
    }

    private func entry(at date: Date) -> BroEntry? {
        guard let saved = WatchBro.load() else { return nil }
        return BroEntry(date: date, bro: saved.bro.at(date), sprite: saved.sprite.flatMap(UIImage.init(data:)))
    }
}

struct BroComplicationView: View {
    let entry: BroEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let bro = entry.bro {
            switch family {
            case .accessoryCircular:
                Gauge(value: bro.progress) {
                    EmptyView()
                } currentValueLabel: {
                    art.padding(2)
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(Theme.accent)
            case .accessoryCorner:
                art
                    .widgetLabel {
                        Gauge(value: bro.progress) { Text("Nv \(bro.level)") }
                            .tint(Theme.accent)
                    }
            case .accessoryInline:
                Text("🔥 \(bro.streak) · \(bro.todayXP) XP hoje")
            default:
                HStack(spacing: 6) {
                    art.frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(bro.name).font(.headline).lineLimit(1).widgetAccentable()
                        Text("🔥 \(bro.streak) · \(bro.todayXP) XP hoje").font(.caption2).lineLimit(1)
                        ProgressView(value: bro.progress).tint(Theme.accent)
                    }
                }
            }
        } else {
            Image(systemName: "figure.strengthtraining.traditional")
        }
    }

    @ViewBuilder private var art: some View {
        if let sprite = entry.sprite {
            Image(uiImage: sprite).resizable().interpolation(.none).scaledToFit()
                .widgetAccentable(false)
        } else {
            Image(systemName: "figure.strengthtraining.traditional").resizable().scaledToFit()
        }
    }
}

@main
struct BroComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BroComplication", provider: BroProvider()) { entry in
            BroComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Meu bro")
        .description("Sequência, XP de hoje e quanto falta para evoluir.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

extension WatchBro {
    static let preview = WatchBro(name: "Gymbro", formName: "Gymbro", stageName: "Bebê", moodEmoji: "😊", isEgg: false, level: 4,
                                  totalXP: 80, progress: 0.4, xpToNext: 220, streak: 3, lastActivity: .now, todayXP: 30,
                                  attributes: [:], updated: .now)
}
