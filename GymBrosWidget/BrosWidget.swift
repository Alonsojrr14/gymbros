import SwiftUI
import WidgetKit

/// O check-in mais recente das suas ligas, com a foto quando houver
struct BrosWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GymBrosBros", provider: BrosProvider()) { BrosView(entry: $0) }
            .configurationDisplayName("Último treino dos bros")
            .description("O check-in mais recente das suas ligas.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct BrosEntry: TimelineEntry {
    let date: Date
    let post: BrosPost?
}

struct BrosProvider: TimelineProvider {
    func placeholder(in context: Context) -> BrosEntry { BrosEntry(date: .now, post: .placeholder) }
    func getSnapshot(in context: Context, completion: @escaping (BrosEntry) -> Void) {
        completion(BrosEntry(date: .now, post: context.isPreview ? .placeholder : BrosPost.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<BrosEntry>) -> Void) {
        // O app grava a cada atualização; o relógio do "há 20 min" anda sozinho
        completion(Timeline(entries: [BrosEntry(date: .now, post: BrosPost.load())], policy: .after(.now.addingTimeInterval(3600))))
    }
}

private struct BrosView: View {
    let entry: BrosEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let p = entry.post {
                if family == .systemSmall { small(p) } else { medium(p) }
            } else {
                VStack(spacing: 6) {
                    Image("sprite_egg").resizable().interpolation(.none).scaledToFit().frame(width: 44, height: 44)
                    Text("Entre numa liga para ver os treinos dos bros aqui").font(.caption).multilineTextAlignment(.center)
                }
            }
        }
        .foregroundStyle(.white)
        .containerBackground(for: .widget) {
            if let data = entry.post?.photo, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill().overlay(LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom))
            } else {
                Theme.bg
            }
        }
        .widgetURL(URL(string: "gymbros://ligas"))
    }

    private func small(_ p: BrosPost) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if p.photo == nil {
                Image(p.sprite).resizable().interpolation(.none).scaledToFit().frame(width: 48, height: 48)
            }
            Spacer(minLength: 0)
            Text(p.title).font(.subheadline.bold()).lineLimit(2).minimumScaleFactor(0.8)
            Text("\(p.name) · \(p.date, style: .relative)").font(.caption2).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func medium(_ p: BrosPost) -> some View {
        HStack(spacing: 12) {
            Image(p.sprite).resizable().interpolation(.none).scaledToFit().frame(width: 70, height: 70)
            VStack(alignment: .leading, spacing: 4) {
                Text("ÚLTIMO TREINO DOS BROS").font(.caption2.weight(.black)).foregroundStyle(Theme.accent)
                Text(p.title).font(.headline).lineLimit(2).minimumScaleFactor(0.8)
                Text("\(p.name) · \(p.date, style: .relative) atrás").font(.caption).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                Text(p.place).font(.caption2).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}
