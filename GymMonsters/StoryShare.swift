import PhotosUI
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

/// Abre a escolha de moldura do story do treino (depois vem o compartilhar do iPhone)
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
    let composer = StoryComposerView(session: session, records: records, place: place,
                                     sprite: WidgetData.load()?.sprite ?? "sprite_baby", photo: photo)
    let vc = UIHostingController(rootView: composer.preferredColorScheme(.dark).tint(Theme.accent))
    vc.modalPresentationStyle = .fullScreen
    // Espera menus e folhas fecharem antes de abrir
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.keyWindow?.rootViewController
        while let next = top?.presentedViewController { top = next }
        top?.present(vc, animated: true)
    }
}

/// Molduras do story
enum StoryFrame: String, CaseIterable, Identifiable {
    case completo, minimo, polaroid, bro

    var id: String { rawValue }

    var name: String {
        switch self {
        case .completo: "Completo"
        case .minimo: "Mínimo"
        case .polaroid: "Polaroid"
        case .bro: "Bro"
        }
    }
}

/// Tela entre "compartilhar" e o compartilhar do iPhone: escolhe a moldura e, se quiser, troca a foto
struct StoryComposerView: View {
    let session: WorkoutSession
    let records: [String]
    let place: String?
    let sprite: String
    @State var photo: UIImage?
    @AppStorage("storyFrame") private var frameRaw = StoryFrame.completo.rawValue
    @State private var pick: PhotosPickerItem?
    @Environment(\.dismiss) private var dismiss

    private var frame: StoryFrame { StoryFrame(rawValue: frameRaw) ?? .completo }

    private func card(_ f: StoryFrame) -> WorkoutStoryCard {
        WorkoutStoryCard(session: session, records: records, place: place, sprite: sprite, photo: photo, frame: f)
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                GMIconButton(icon: "xmark", label: "Fechar") { dismiss() }
                Spacer()
                Text("Story").font(.headline)
                Spacer()
                PhotosPicker(selection: $pick, matching: .images) {
                    Image(systemName: photo == nil ? "photo.badge.plus" : "photo")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .background(Theme.raised, in: .circle)
                        .foregroundStyle(.white)
                }
                .accessibilityLabel(photo == nil ? "Adicionar foto" : "Trocar foto")
            }
            .padding(.horizontal, 16)

            // Prévia no tamanho que cabe na tela, mantendo 9:16
            GeometryReader { geo in
                let scale = min(geo.size.width / 360, geo.size.height / 640)
                card(frame)
                    .scaleEffect(scale)
                    .frame(width: 360 * scale, height: 640 * scale)
                    .clipShape(.rect(cornerRadius: Theme.radiusL))
                    .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(StoryFrame.allCases) { f in
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(.snappy) { frameRaw = f.rawValue }
                        } label: {
                            VStack(spacing: 6) {
                                card(f)
                                    .scaleEffect(0.2)
                                    .frame(width: 72, height: 128)
                                    .clipShape(.rect(cornerRadius: Theme.radiusS))
                                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusS)
                                        .stroke(f == frame ? Theme.accent : Theme.stroke, lineWidth: f == frame ? 3 : 1))
                                Text(f.name).font(.caption.weight(f == frame ? .bold : .regular))
                                    .foregroundStyle(f == frame ? Theme.accent : Theme.dim)
                            }
                        }
                        .buttonStyle(GMPress())
                        .accessibilityLabel("Moldura \(f.name)")
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: 160)

            GMButton("Compartilhar", icon: "square.and.arrow.up") { share() }
                .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
        .background(Theme.bg.ignoresSafeArea())
        .onChange(of: pick) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: data) { photo = img }
            }
        }
    }

    private func share() {
        let renderer = ImageRenderer(content: card(frame))
        renderer.scale = 3
        guard let img = renderer.uiImage else { return }
        presentShare([img], delay: 0.05)
    }
}

/// Arte 9:16 (1080 × 1920): a foto do check-in ocupa a tela toda e o treino vem por cima
struct WorkoutStoryCard: View {
    let session: WorkoutSession
    let records: [String]
    let place: String?
    let sprite: String
    var photo: UIImage?
    var frame: StoryFrame = .completo

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
        Group {
            switch frame {
            case .completo: completo
            case .minimo: minimo
            case .polaroid: polaroid
            case .bro: bro
            }
        }
        .frame(width: 360, height: 640)
        .clipped()
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    // MARK: Completo: foto inteira, tudo por cima

    private var completo: some View {
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
    }

    // MARK: Mínimo: a foto aparece quase inteira, só uma faixa embaixo

    private var minimo: some View {
        ZStack(alignment: .bottom) {
            if let photo {
                Color.black.overlay { Image(uiImage: photo).resizable().scaledToFill() }.clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)
            } else {
                background
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("GymBros").font(.system(size: 13, weight: .black, design: .rounded)).foregroundStyle(Theme.accent)
                        Text(session.title).font(.system(size: 22, weight: .heavy, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
                    }
                    Spacer(minLength: 0)
                    Image(sprite).resizable().interpolation(.none).scaledToFit().frame(width: 48, height: 48)
                }
                Text([durationText(minutes), "\(work.count) séries", volume > 0 ? "\(Progression.fmt((volume / 10).rounded() * 10)) kg" : nil]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 72)
        }
    }

    // MARK: Polaroid: a foto num quadro branco sobre o verde do app

    private var polaroid: some View {
        ZStack {
            LinearGradient(colors: [Theme.accent, Theme.accent.opacity(0.55), Theme.bg], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 18) {
                VStack(spacing: 10) {
                    Group {
                        if let photo {
                            Color.black.overlay { Image(uiImage: photo).resizable().scaledToFill() }
                        } else {
                            Theme.bg.overlay { Image(sprite).resizable().interpolation(.none).scaledToFit().padding(40) }
                        }
                    }
                    .frame(width: 260, height: 300)
                    .clipped()
                    VStack(spacing: 2) {
                        Text(session.title).font(.system(size: 20, weight: .heavy, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
                        Text(session.start.formatted(.dateTime.day().month(.wide)) + (place.map { " · \($0)" } ?? ""))
                            .font(.caption.weight(.semibold)).lineLimit(1)
                    }
                    .foregroundStyle(.black)
                    .padding(.bottom, 8)
                }
                .padding(12)
                .background(.white)
                .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
                .rotationEffect(.degrees(-3))
                HStack(spacing: 8) {
                    stat(durationText(minutes), "duração")
                    stat("\(work.count)", "séries")
                    stat(volume > 0 ? "\(Progression.fmt((volume / 10).rounded() * 10)) kg" : "–", "volume")
                }
                .padding(.horizontal, 30)
                Text("GymBros").font(.system(size: 16, weight: .black, design: .rounded)).foregroundStyle(Theme.accent)
            }
            .padding(.top, 40)
        }
    }

    // MARK: Bro: o bro é o destaque; a foto vira um círculo

    private var bro: some View {
        ZStack {
            RadialGradient(colors: [Theme.accent.opacity(0.45), Theme.bg], center: .center, startRadius: 10, endRadius: 320)
            VStack(spacing: 14) {
                Text("GymBros").font(.system(size: 18, weight: .black, design: .rounded)).foregroundStyle(Theme.accent)
                Spacer(minLength: 0)
                ZStack(alignment: .bottomTrailing) {
                    Image(sprite).resizable().interpolation(.none).scaledToFit().frame(width: 220, height: 220)
                        .shadow(color: Theme.accent.opacity(0.6), radius: 24)
                    if let photo {
                        Image(uiImage: photo).resizable().scaledToFill()
                            .frame(width: 92, height: 92).clipShape(.circle)
                            .overlay(Circle().stroke(.white, lineWidth: 4))
                            .offset(x: 18, y: 10)
                    }
                }
                Text(session.title).font(.system(size: 26, weight: .heavy, design: .rounded)).lineLimit(2).minimumScaleFactor(0.6)
                    .multilineTextAlignment(.center)
                Text(session.start.formatted(.dateTime.day().month(.wide).year())).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                HStack(spacing: 8) {
                    stat(durationText(minutes), "duração")
                    stat("\(work.count)", "séries")
                    stat(volume > 0 ? "\(Progression.fmt((volume / 10).rounded() * 10)) kg" : "–", "volume")
                }
                if let r = records.first {
                    Text("🏆 " + r).font(.caption.weight(.bold)).foregroundStyle(Theme.trophy).lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 56)
            .padding(.bottom, 64)
        }
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
