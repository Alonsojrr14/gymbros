import SwiftData
import SwiftUI

/// Abre a folha de compartilhar do iPhone por cima do que estiver na tela
@MainActor
func presentShare(_ items: [Any], delay: Double = 0.4) {
    let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
    // Espera menus e folhas fecharem antes de abrir
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.keyWindow?.rootViewController
        while let next = top?.presentedViewController { top = next }
        top?.present(vc, animated: true)
    }
}

/// Gera a imagem do treino em formato Stories (1080 × 1920) e abre o compartilhar
@MainActor
func shareWorkoutStory(_ session: WorkoutSession, context: ModelContext) {
    let finished = ((try? context.fetch(FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.start)]))) ?? [])
        .filter { $0.end != nil && $0.start < session.start }
    let records = Progression.records(in: session.log, history: finished.map(\.log))
    let place = GymLocation.shared.gym(session.gymUUID)?.name
    let card = WorkoutStoryCard(session: session, records: records, place: place, sprite: WidgetData.load()?.sprite ?? "sprite_baby")
    let renderer = ImageRenderer(content: card.frame(width: 360, height: 640))
    renderer.scale = 3
    guard let img = renderer.uiImage else { return }
    presentShare([img], delay: 0.1)
}

struct WorkoutStoryCard: View {
    let session: WorkoutSession
    let records: [String]
    let place: String?
    let sprite: String

    private var work: [LoggedSet] { session.orderedSets.filter { $0.done && !$0.warmup } }
    private var minutes: Int { max(Int(((session.end ?? .now).timeIntervalSince(session.start)) / 60), 1) }
    private var volume: Double { work.reduce(0) { $0 + $1.weight * Double($1.reps) } }

    /// Melhor série de cada exercício
    private var lines: [(String, String, Int)] {
        session.exerciseIDs.compactMap { id in
            let s = work.filter { $0.exerciseID == id }
            guard let best = s.max(by: { ($0.weight, $0.reps) < ($1.weight, $1.reps) }) else { return nil }
            return (Exercise.name(id), setText(best), s.count)
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.accent.opacity(0.45), Theme.bg, Theme.bg], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("GymBros").font(.system(size: 18, weight: .black, design: .rounded)).foregroundStyle(Theme.accent)
                    Spacer()
                    Text(session.start.formatted(.dateTime.day().month(.abbreviated).year())).font(.caption.bold()).foregroundStyle(.white.opacity(0.7))
                }
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.title).font(.system(size: 28, weight: .heavy, design: .rounded)).lineLimit(2).minimumScaleFactor(0.6)
                        if let place { Label(place, systemImage: "mappin.and.ellipse").font(.caption.bold()).foregroundStyle(.white.opacity(0.8)) }
                    }
                    Spacer()
                    Image(sprite).resizable().interpolation(.none).scaledToFit().frame(width: 96, height: 96)
                }
                HStack(spacing: 8) {
                    stat(durationText(minutes), "duração")
                    stat("\(work.count)", "séries")
                    stat(volume > 0 ? "\(Progression.fmt((volume / 10).rounded() * 10)) kg" : "–", "volume")
                }
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(lines.prefix(7), id: \.0) { name, best, count in
                        HStack {
                            Text(name).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Spacer()
                            Text("\(count)× · \(best)").font(.subheadline.monospacedDigit()).foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    if lines.count > 7 {
                        Text("+\(lines.count - 7) exercícios").font(.caption).foregroundStyle(.white.opacity(0.6))
                    }
                }
                .padding(14)
                .background(.white.opacity(0.07), in: .rect(cornerRadius: 18))
                if !records.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("RECORDES 🏆").font(.caption.weight(.black)).foregroundStyle(.yellow)
                        ForEach(records.prefix(3), id: \.self) { Text($0).font(.caption.weight(.semibold)).lineLimit(2) }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.yellow.opacity(0.12), in: .rect(cornerRadius: 18))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22)
            .padding(.top, 60)
            .padding(.bottom, 40)
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.white.opacity(0.08), in: .rect(cornerRadius: 14))
    }
}
