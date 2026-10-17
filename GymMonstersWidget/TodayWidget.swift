import SwiftUI
import WidgetKit

private let accent = Color(red: 0.64, green: 0.90, blue: 0.21)
private let bg = Color(red: 0.05, green: 0.06, blue: 0.08)

/// Treino do dia com botão de começar (abre o app já no treino)
struct TodayWorkoutWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GymBrosToday", provider: Provider()) { TodayView(entry: $0) }
            .configurationDisplayName("Treino do dia")
            .description("A rotina de hoje e um botão para começar.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct TodayView: View {
    let entry: Entry
    @Environment(\.widgetFamily) private var family

    private var routine: String? { entry.data.todayRoutine[Calendar.current.component(.weekday, from: entry.date)] }

    var body: some View {
        let start = URL(string: "gymbros://start")!
        Group {
            if family == .systemSmall {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(entry.trainedToday ? "FEITO ✅" : "HOJE").font(.caption2.weight(.black)).foregroundStyle(accent)
                        Spacer()
                        Image(entry.data.sprite).resizable().interpolation(.none).scaledToFit().frame(width: 34, height: 34)
                    }
                    Text(routine ?? "Treino livre").font(.headline).lineLimit(2).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    button(start)
                }
            } else {
                HStack(spacing: 14) {
                    Image(entry.data.sprite).resizable().interpolation(.none).scaledToFit().frame(width: 84, height: 84)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.trainedToday ? "TREINO FEITO HOJE ✅" : "TREINO DE HOJE").font(.caption2.weight(.black)).foregroundStyle(accent)
                        Text(routine ?? "Treino livre").font(.title3.bold()).lineLimit(2).minimumScaleFactor(0.7)
                        if entry.streak > 0 {
                            Text("🔥 \(entry.streak) dia\(entry.streak == 1 ? "" : "s") seguidos").font(.caption).foregroundStyle(.white.opacity(0.7))
                        }
                        Spacer(minLength: 0)
                        button(start)
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .containerBackground(bg, for: .widget)
        .widgetURL(start)
    }

    private func button(_ url: URL) -> some View {
        Link(destination: url) {
            Label(entry.trainedToday ? "Treinar de novo" : "Começar", systemImage: "play.fill")
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(accent, in: .capsule)
                .foregroundStyle(.black)
        }
    }
}
