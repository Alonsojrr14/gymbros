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
func shareWorkoutStory(_ session: WorkoutSession, context: ModelContext, photo chosen: UIImage? = nil) {
    let finished = ((try? context.fetch(FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.start)]))) ?? [])
        .filter { $0.end != nil && $0.start < session.start }
    let records = Progression.records(in: session.log, history: finished.map(\.log))
    let place = GymLocation.shared.gym(session.gymUUID)?.name
    // Foto do check-in desse treino, se tiver
    var photo = chosen
    if photo == nil, let id = session.activityUUID {
        let posts = (try? context.fetch(FetchDescriptor<LeagueCheckIn>(predicate: #Predicate { $0.activityUUID == id }))) ?? []
        photo = posts.compactMap(\.photo).first.flatMap(UIImage.init(data:))
    }
    let card = WorkoutStoryCard(session: session, records: records, place: place, sprite: WidgetData.load()?.sprite ?? "sprite_baby", photo: photo)
    let renderer = ImageRenderer(content: card)
    renderer.scale = 3
    guard let img = renderer.uiImage else { return }
    presentShare([img], delay: 0.1)
}

/// Arte 9:16 (1080 × 1920): a foto do check-in ocupa a tela toda e o treino vem por cima
struct WorkoutStoryCard: View {
    let session: WorkoutSession
    let records: [String]
    let place: String?
    let sprite: String
    var photo: UIImage?

    private var work: [LoggedSet] { session.orderedSets.filter { $0.done && !$0.warmup } }
    private var minutes: Int { max(Int(((session.end ?? .now).timeIntervalSince(session.start)) / 60), 1) }
    private var volume: Double { work.reduce(0) { $0 + $1.weight * Double($1.reps) } }

    /// Melhor série de cada exercício
    private var lines: [(String, String, Int)] {
        session.exerciseIDs.compactMap { id in
            let s = work.filter { $0.exerciseID == id }
            guard let best = s.max(by: { ($0.weight, $0.reps) < ($1.weight, $1.reps) }) else { return nil }
            let text = best.weight > 0 ? "\(Progression.fmt(best.weight)) kg × \(best.reps)"
                : Exercise.byID(id)?.type == .time ? "\(best.reps) s" : "\(best.reps) reps"
            return (Exercise.name(id), text, s.count)
        }
    }

    var body: some View {
        ZStack {
            background
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("GymBros").font(.system(size: 20, weight: .black, design: .rounded)).foregroundStyle(Theme.accent)
                    Spacer()
                    Text(session.start.formatted(.dateTime.day().month(.abbreviated).year()))
                        .font(.caption.bold())
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.black.opacity(0.45), in: .capsule)
                }
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let place {
                            Label(place, systemImage: "mappin.and.ellipse").font(.caption.bold()).foregroundStyle(Theme.accent)
                        }
                        Text(session.title).font(.system(size: 30, weight: .heavy, design: .rounded)).lineLimit(2).minimumScaleFactor(0.6)
                    }
                    Spacer(minLength: 0)
                    Image(sprite).resizable().interpolation(.none).scaledToFit().frame(width: 78, height: 78)
                        .shadow(color: .black.opacity(0.5), radius: 6)
                }
                HStack(spacing: 8) {
                    stat(durationText(minutes), "duração")
                    stat("\(work.count)", "séries")
                    stat(volume > 0 ? "\(Progression.fmt((volume / 10).rounded() * 10)) kg" : "–", "volume")
                }
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(lines.prefix(photo == nil ? 8 : 5), id: \.0) { name, best, count in
                        HStack {
                            Text(name).font(.footnote.weight(.semibold)).lineLimit(1)
                            Spacer()
                            Text("\(count)× \(best)").font(.footnote.monospacedDigit()).foregroundStyle(.white.opacity(0.85))
                        }
                    }
                    let shown = photo == nil ? 8 : 5
                    if lines.count > shown {
                        Text("+\(lines.count - shown) exercício\(lines.count - shown == 1 ? "" : "s")").font(.caption2).foregroundStyle(.white.opacity(0.6))
                    }
                }
                .padding(12)
                .background(.black.opacity(0.5), in: .rect(cornerRadius: Theme.radiusL))
                if !records.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("RECORDES 🏆").font(.caption2.weight(.black)).foregroundStyle(Theme.trophy)
                        ForEach(records.prefix(2), id: \.self) { Text($0).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7) }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.black.opacity(0.5), in: .rect(cornerRadius: Theme.radiusL))
                }
            }
            .padding(.horizontal, 20)
            // Margens seguras dos Stories (perfil em cima, resposta embaixo)
            .padding(.top, 56)
            .padding(.bottom, 64)
        }
        .frame(width: 360, height: 640)
        .clipped()
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var background: some View {
        if let photo {
            Color.black
                .overlay { Image(uiImage: photo).resizable().scaledToFill() }
                .clipped()
            // Escurece de baixo para cima para o texto ler bem sobre a foto
            LinearGradient(stops: [.init(color: .black.opacity(0.35), location: 0), .init(color: .clear, location: 0.18),
                                   .init(color: .clear, location: 0.35), .init(color: .black.opacity(0.85), location: 0.75),
                                   .init(color: .black.opacity(0.95), location: 1)],
                           startPoint: .top, endPoint: .bottom)
        } else {
            LinearGradient(colors: [Theme.accent.opacity(0.45), Theme.bg, Theme.bg], startPoint: .top, endPoint: .bottom)
                .overlay(alignment: .center) {
                    Image(sprite).resizable().interpolation(.none).scaledToFit().frame(width: 220).opacity(0.25).offset(y: -90)
                }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(.black.opacity(0.5), in: .rect(cornerRadius: Theme.radiusM))
    }
}
