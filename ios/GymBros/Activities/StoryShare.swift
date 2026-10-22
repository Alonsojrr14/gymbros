import CoreLocation
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

/// O que vai na arte do story, montado a partir de um treino guiado ou de qualquer atividade
struct StoryData {
    var title: String
    var date: Date
    var place: String?
    /// Números da moldura; só entra o que existe (sem "–")
    var stats: [(value: String, label: String)]
    /// Melhor série de cada exercício (musculação)
    var lines: [(name: String, best: String, sets: Int)] = []
    var records: [String] = []
    /// Trajeto do GPS (corrida, caminhada, bike)
    var route: [CLLocationCoordinate2D] = []
    /// Bros que ganharam XP com a atividade: o principal primeiro, depois quem a representa nas ligas
    var bros: [StoryBro] = []

    /// Bro do destaque (o principal)
    var sprite: String { bros.first?.sprite ?? "sprite_baby" }
    var totalXP: Int { bros.reduce(0) { $0 + $1.xp } }

    /// "+52 XP para o Ursabro", "+130 XP para 3 bros"
    var xpText: String? {
        guard totalXP > 0 else { return nil }
        return bros.count == 1 ? "+\(totalXP) XP para \(bros[0].name)" : "+\(totalXP) XP para \(bros.count) bros"
    }

    /// Linha curta para a moldura mínima
    var summary: String { stats.map { $0.value }.joined(separator: " · ") }

    /// Calorias ativas: o número real do Apple Saúde, ou estimativa pelo peso cadastrado; sem peso, nada
    @MainActor
    static func kcal(_ activity: Activity?, kind: ActivityKind, minutes: Int, effort: Int, context: ModelContext) -> String? {
        if let a = activity, a.healthUUID != nil,
           let m = a.note.firstMatch(of: /(\d+) kcal/), let v = Int(m.1), v > 0 { return "\(v)" }
        let latest = ((try? context.fetch(FetchDescriptor<BodyEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? [])
            .compactMap(\.weight).first
        guard let weight = latest ?? BodyProfile.weight, minutes > 0 else { return nil }
        let k = HealthSync.activeKcal(kind: kind, minutes: minutes, effort: effort, weight: weight)
        return k >= 1 ? "\(Int(k.rounded()))" : nil
    }

    @MainActor
    static func workout(_ session: WorkoutSession, context: ModelContext) -> StoryData {
        let finished = ((try? context.fetch(FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.start)]))) ?? [])
            .filter { $0.end != nil && $0.start < session.start }
        let work = session.orderedSets.filter { $0.done && !$0.warmup }
        let minutes = max(Int(((session.end ?? .now).timeIntervalSince(session.start)) / 60), 1)
        let activity = session.activityUUID.flatMap { id in
            ((try? context.fetch(FetchDescriptor<Activity>(predicate: #Predicate { $0.uuid == id }))) ?? []).first
        }
        var stats: [(String, String)] = [(durationText(minutes), "duração"), ("\(work.count)", "séries")]
        if let k = kcal(activity, kind: session.isCrossfit ? .crossfit : .musculacao, minutes: minutes,
                        effort: activity?.effort ?? session.effort, context: context) {
            stats.append((k, "kcal"))
        }
        let lines: [(String, String, Int)] = session.exerciseIDs.compactMap { id in
            let s = work.filter { $0.exerciseID == id }
            guard let best = s.max(by: { ($0.weight, $0.reps) < ($1.weight, $1.reps) }) else { return nil }
            let text = Exercise.byID(id)?.type == .distance ? "\(meters(best.weight)) em \(clock(best.reps))"
                : best.weight > 0 ? "\(Progression.fmt(best.weight)) kg × \(best.reps)"
                : Exercise.byID(id)?.type == .time ? "\(best.reps) s" : "\(best.reps) reps"
            return (Exercise.name(id), text, s.count)
        }
        return StoryData(title: session.title, date: session.start, place: GymLocation.shared.gym(session.gymUUID)?.name,
                         stats: stats.map { (value: $0.0, label: $0.1) }, lines: lines.map { (name: $0.0, best: $0.1, sets: $0.2) },
                         records: Progression.records(in: session.log, history: finished.map(\.log)),
                         bros: bros(activity, context: context))
    }

    /// Atividade sem treino guiado: corrida com GPS mostra distância, ritmo e o trajeto
    @MainActor
    static func activity(_ a: Activity, context: ModelContext) -> StoryData {
        let id = a.uuid
        let route = ((try? context.fetch(FetchDescriptor<RouteRecord>(predicate: #Predicate { $0.activityUUID == id }))) ?? []).first
        var stats: [(String, String)] = []
        if let r = route, r.meters > 20 {
            stats.append((kmText(r.meters), "distância"))
            let pace = paceText(kind: r.kind, meters: r.meters, seconds: r.seconds)
            if pace != "–" { stats.append((pace.replacingOccurrences(of: " /km", with: ""), r.kind == .bike ? "velocidade" : "pace /km")) }
            stats.append((clock(r.seconds), "tempo"))
        } else {
            stats.append((durationText(a.minutes), "duração"))
        }
        if let k = kcal(a, kind: a.kind, minutes: a.minutes, effort: a.effort, context: context) { stats.append((k, "kcal")) }
        let posts = (try? context.fetch(FetchDescriptor<LeagueCheckIn>(predicate: #Predicate { $0.activityUUID == id }))) ?? []
        let title = posts.first?.title ?? (a.note.isEmpty || a.healthUUID != nil ? a.typeName : a.note)
        return StoryData(title: title, date: a.date,
                         place: posts.compactMap(\.place).first ?? GymLocation.shared.gym(a.gymUUID)?.name,
                         stats: stats.map { (value: $0.0, label: $0.1) }, route: route?.coordinates ?? [],
                         bros: bros(a, context: context))
    }

    /// Quem ganhou XP com a atividade e quanto (regra do Roster: o principal tudo, cada liga um pouco menos).
    /// Sem atividade ou sem XP, só o principal, sem número.
    @MainActor
    static func bros(_ activity: Activity?, context: ModelContext) -> [StoryBro] {
        let monsters = (try? context.fetch(FetchDescriptor<Monster>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        let leagues = (try? context.fetch(FetchDescriptor<League>())) ?? []
        let roster = Roster(monsters: monsters, activities: (try? context.fetch(FetchDescriptor<Activity>())) ?? [],
                            checkIns: (try? context.fetch(FetchDescriptor<LeagueCheckIn>())) ?? [], leagues: leagues)
        let fallback = [StoryBro(sprite: WidgetData.load()?.sprite ?? "sprite_baby", name: "", xp: 0, main: true)]
        guard let activity else { return fallback }
        let id = activity.uuid
        let posted = Set(((try? context.fetch(FetchDescriptor<LeagueCheckIn>(predicate: #Predicate { $0.activityUUID == id }))) ?? []).map(\.leagueUUID))
        let main = monsters.contains { $0.uuid == activity.monsterUUID } ? activity.monsterUUID : roster.mainID
        let list = monsters.compactMap { m -> StoryBro? in
            let snap = roster.snapshot(m.uuid)
            guard let xp = snap.xpByActivity[id], xp > 0 else { return nil }
            let league = leagues.first { $0.monsterUUID == m.uuid && posted.contains($0.uuid) }
            return StoryBro(sprite: snap.form.spriteWithFallback, name: m.displayName(snap.form), xp: xp, main: m.uuid == main,
                            league: m.uuid == main ? nil : league?.emoji)
        }
        .sorted { ($0.main ? 1 : 0, $0.xp) > ($1.main ? 1 : 0, $1.xp) }
        return list.isEmpty ? fallback : list
    }

    /// Foto do check-in da atividade, se tiver
    @MainActor
    static func photo(activityUUID: UUID?, context: ModelContext) -> UIImage? {
        guard let id = activityUUID else { return nil }
        let posts = (try? context.fetch(FetchDescriptor<LeagueCheckIn>(predicate: #Predicate { $0.activityUUID == id }))) ?? []
        return posts.compactMap(\.photo).first.flatMap(UIImage.init(data:))
    }
}

/// Um bro na arte do story, com o XP que ganhou
struct StoryBro: Hashable {
    let sprite: String
    let name: String
    let xp: Int
    /// O principal (recebe o XP inteiro)
    let main: Bool
    /// Emoji da liga em que ele te representou nesta atividade
    var league: String?
}

/// Abre a escolha de moldura do story do treino (depois vem o compartilhar do iPhone)
@MainActor
func shareWorkoutStory(_ session: WorkoutSession, context: ModelContext, photo chosen: UIImage? = nil) {
    presentStory(StoryData.workout(session, context: context),
                 photo: chosen ?? StoryData.photo(activityUUID: session.activityUUID, context: context))
}

/// Story de qualquer atividade (corrida, caminhada, bike, esportes…)
@MainActor
func shareActivityStory(_ activity: Activity, context: ModelContext, photo chosen: UIImage? = nil) {
    presentStory(StoryData.activity(activity, context: context),
                 photo: chosen ?? StoryData.photo(activityUUID: activity.uuid, context: context))
}

@MainActor
private func presentStory(_ data: StoryData, photo: UIImage?) {
    let vc = UIHostingController(rootView: StoryComposerView(data: data, photo: photo).preferredColorScheme(.dark).tint(Theme.accent))
    vc.modalPresentationStyle = .fullScreen
    present(vc, attempts: 20)
}

/// Espera menus, folhas e o seletor de fotos terminarem de fechar: apresentar em cima de quem está saindo
/// falha calado (era o que acontecia no "Stories com outra foto")
@MainActor
private func present(_ vc: UIViewController, attempts: Int) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.keyWindow?.rootViewController
        var busy = top?.isBeingDismissed == true || top?.isBeingPresented == true
        while let next = top?.presentedViewController {
            if next.isBeingDismissed || next.isBeingPresented { busy = true }
            if next.isBeingDismissed { break }
            top = next
        }
        if busy && attempts > 0 { return present(vc, attempts: attempts - 1) }
        top?.present(vc, animated: true)
    }
}

/// Molduras do story
enum StoryFrame: String, CaseIterable, Identifiable {
    case completo, minimo, polaroid, bro, time

    /// "Time" só faz sentido quando mais de um bro ganhou XP
    static func available(_ data: StoryData) -> [StoryFrame] { allCases.filter { $0 != .time || data.bros.count > 1 } }

    var id: String { rawValue }

    var name: String {
        switch self {
        case .completo: "Completo"
        case .minimo: "Mínimo"
        case .polaroid: "Polaroid"
        case .bro: "Bro"
        case .time: "Time"
        }
    }
}

/// Tela entre "compartilhar" e o compartilhar do iPhone: escolhe a moldura e, se quiser, troca a foto
struct StoryComposerView: View {
    let data: StoryData
    @State var photo: UIImage?
    @AppStorage("storyFrame") private var frameRaw = StoryFrame.completo.rawValue
    @State private var pick: PhotosPickerItem?
    @Environment(\.dismiss) private var dismiss

    private var frame: StoryFrame {
        let f = StoryFrame(rawValue: frameRaw) ?? .completo
        return StoryFrame.available(data).contains(f) ? f : .completo
    }

    private func card(_ f: StoryFrame) -> WorkoutStoryCard {
        WorkoutStoryCard(data: data, photo: photo, frame: f)
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
                    ForEach(StoryFrame.available(data)) { f in
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
    let data: StoryData
    var photo: UIImage?
    var frame: StoryFrame = .completo

    private var sprite: String { data.sprite }
    private var place: String? { data.place }
    private var records: [String] { data.records }
    private var lines: [(name: String, best: String, sets: Int)] { data.lines }

    var body: some View {
        Group {
            switch frame {
            case .completo: completo
            case .minimo: minimo
            case .polaroid: polaroid
            case .bro: bro
            case .time: time
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
                    Text(data.date.formatted(.dateTime.day().month(.abbreviated).year()))
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
                        Text(data.title).font(.system(size: 30, weight: .heavy, design: .rounded)).lineLimit(2).minimumScaleFactor(0.6)
                    }
                    Spacer(minLength: 0)
                    broStack(size: 78)
                }
                HStack(spacing: 8) {
                    ForEach(Array(data.stats.prefix(4).enumerated()), id: \.offset) { _, st in stat(st.value, st.label) }
                }
                xpChips
                if !data.route.isEmpty {
                    RouteDrawing(coords: data.route)
                        .frame(height: photo == nil ? 220 : 150)
                        .padding(12)
                        .background(.black.opacity(0.35), in: .rect(cornerRadius: Theme.radiusL))
                }
                if !lines.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(lines.prefix(photo == nil ? 8 : 5), id: \.name) { name, best, count in
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
                }
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
                if !data.route.isEmpty {
                    RouteDrawing(coords: data.route, lineWidth: 4).frame(width: 140, height: 140)
                }
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("GymBros").font(.system(size: 13, weight: .black, design: .rounded)).foregroundStyle(Theme.accent)
                        Text(data.title).font(.system(size: 22, weight: .heavy, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
                    }
                    Spacer(minLength: 0)
                    broStack(size: 48)
                }
                Text(data.stats.map { $0.label == "kcal" ? "\($0.value) kcal" : $0.label == "séries" ? "\($0.value) séries" : $0.value }
                    .joined(separator: " · "))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                if let xp = data.xpText {
                    Text(xp).font(.caption.weight(.heavy)).foregroundStyle(Theme.accent)
                }
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
                    .overlay(alignment: .bottomTrailing) {
                        if !data.route.isEmpty {
                            RouteDrawing(coords: data.route, lineWidth: 3)
                                .frame(width: 96, height: 96).padding(8)
                                .background(.black.opacity(0.45), in: .rect(cornerRadius: 12)).padding(8)
                        }
                    }
                    VStack(spacing: 2) {
                        Text(data.title).font(.system(size: 20, weight: .heavy, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
                        Text(data.date.formatted(.dateTime.day().month(.wide)) + (place.map { " · \($0)" } ?? ""))
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
                    ForEach(Array(data.stats.prefix(4).enumerated()), id: \.offset) { _, st in stat(st.value, st.label) }
                }
                .padding(.horizontal, 30)
                xpChips.padding(.horizontal, 30)
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
                    if !data.route.isEmpty {
                        RouteDrawing(coords: data.route, lineWidth: 5).frame(width: 260, height: 260).opacity(0.55)
                    }
                    broHero
                    if let photo {
                        Image(uiImage: photo).resizable().scaledToFill()
                            .frame(width: 92, height: 92).clipShape(.circle)
                            .overlay(Circle().stroke(.white, lineWidth: 4))
                            .offset(x: 18, y: 10)
                    }
                }
                Text(data.title).font(.system(size: 26, weight: .heavy, design: .rounded)).lineLimit(2).minimumScaleFactor(0.6)
                    .multilineTextAlignment(.center)
                Text(data.date.formatted(.dateTime.day().month(.wide).year())).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                HStack(spacing: 8) {
                    ForEach(Array(data.stats.prefix(4).enumerated()), id: \.offset) { _, st in stat(st.value, st.label) }
                }
                if let xp = data.xpText {
                    Text(xp).font(.subheadline.weight(.heavy)).foregroundStyle(Theme.accent)
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

    // MARK: Time: todos os bros que ganharam XP, cada um com o seu

    /// Até 4 bros em destaque (2 lado a lado, 3 em triângulo, 4 em grade) e, com mais, o "+N bros" embaixo
    private var time: some View {
        let shown = Array(data.bros.prefix(4))
        let extra = data.bros.count - shown.count
        return ZStack {
            if let photo {
                Color.black.overlay { Image(uiImage: photo).resizable().scaledToFill() }.clipped().opacity(0.35)
            }
            RadialGradient(colors: [Theme.accent.opacity(0.4), Theme.bg.opacity(photo == nil ? 1 : 0.6)], center: .center, startRadius: 10, endRadius: 340)
            VStack(spacing: 16) {
                HStack {
                    Text("GymBros").font(.system(size: 18, weight: .black, design: .rounded)).foregroundStyle(Theme.accent)
                    Spacer()
                    Text(data.date.formatted(.dateTime.day().month(.abbreviated))).font(.caption.bold())
                        .padding(.horizontal, 10).padding(.vertical, 5).background(.black.opacity(0.45), in: .capsule)
                }
                Spacer(minLength: 0)
                Text("+\(data.totalXP) XP").font(.system(size: 44, weight: .black, design: .rounded)).foregroundStyle(Theme.accent)
                    .shadow(color: Theme.accent.opacity(0.5), radius: 12)
                Text("\(data.bros.count) bros treinaram junto").font(.subheadline.weight(.bold)).foregroundStyle(.white.opacity(0.85))
                Group {
                    switch shown.count {
                    case 2:
                        HStack(spacing: 14) { ForEach(shown, id: \.self) { teamCard($0, size: 110) } }
                    case 3:
                        VStack(spacing: 12) {
                            teamCard(shown[0], size: 110)
                            HStack(spacing: 14) { teamCard(shown[1], size: 80); teamCard(shown[2], size: 80) }
                        }
                    default:
                        // Grid normal: a arte sai pelo ImageRenderer, que não desenha grades lazy
                        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                            GridRow { teamCard(shown[0], size: 84); teamCard(shown[1], size: 84) }
                            GridRow { teamCard(shown[2], size: 84); teamCard(shown[3], size: 84) }
                        }
                    }
                }
                if extra > 0 {
                    Text("+\(extra) \(extra == 1 ? "bro" : "bros")").font(.caption.weight(.heavy))
                        .padding(.horizontal, 12).padding(.vertical, 6).background(.black.opacity(0.5), in: .capsule)
                }
                Text(data.title).font(.system(size: 22, weight: .heavy, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
                Text(data.stats.map { $0.label == "kcal" ? "\($0.value) kcal" : $0.label == "séries" ? "\($0.value) séries" : $0.value }
                    .joined(separator: " · ")).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.75)).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22)
            .padding(.top, 56)
            .padding(.bottom, 64)
        }
    }

    private func teamCard(_ b: StoryBro, size: CGFloat) -> some View {
        VStack(spacing: 4) {
            Image(b.sprite).resizable().interpolation(.none).scaledToFit().frame(width: size, height: size)
                .shadow(color: (b.main ? Theme.accent : .white).opacity(0.45), radius: 14)
            HStack(spacing: 4) {
                if b.main { Image(systemName: "star.fill").font(.system(size: 9, weight: .black)).foregroundStyle(Theme.accent) }
                if let l = b.league { Text(l).font(.system(size: 11)) }
                Text(b.name).font(.caption.weight(.bold)).lineLimit(1).minimumScaleFactor(0.6)
            }
            Text("+\(b.xp) XP").font(.caption.weight(.heavy).monospacedDigit()).foregroundStyle(b.main ? Theme.accent : .white)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.45), in: .rect(cornerRadius: Theme.radiusL))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusL).stroke(b.main ? Theme.accent.opacity(0.6) : .clear, lineWidth: 1.5))
    }

    // MARK: Bros nas outras molduras

    /// Bro(s) ao lado do título: o principal na frente e até mais 2 atrás, levemente sobrepostos
    private func broStack(size: CGFloat) -> some View {
        let shown = Array(data.bros.prefix(3))
        return ZStack(alignment: .bottomTrailing) {
            ForEach(Array(shown.enumerated().reversed()), id: \.offset) { i, b in
                Image(b.sprite).resizable().interpolation(.none).scaledToFit()
                    .frame(width: i == 0 ? size : size * 0.62, height: i == 0 ? size : size * 0.62)
                    .shadow(color: .black.opacity(0.5), radius: 6)
                    .offset(x: CGFloat(-i) * size * 0.55, y: i == 0 ? 0 : -size * 0.1)
            }
            if data.bros.count > 3 {
                Text("+\(data.bros.count - 3)").font(.system(size: 10, weight: .black))
                    .padding(.horizontal, 5).padding(.vertical, 2).background(Theme.accent, in: .capsule).foregroundStyle(.black)
            }
        }
        .padding(.leading, CGFloat(max(shown.count - 1, 0)) * size * 0.55)
    }

    /// "+52 XP · Ursabro" em chips; com mais de 3 bros, os 2 primeiros e o "+N"
    @ViewBuilder
    private var xpChips: some View {
        let withXP = data.bros.filter { $0.xp > 0 }
        if !withXP.isEmpty {
            let shown = withXP.count > 3 ? Array(withXP.prefix(2)) : withXP
            HStack(spacing: 6) {
                ForEach(shown, id: \.self) { b in
                    HStack(spacing: 5) {
                        Image(b.sprite).resizable().interpolation(.none).scaledToFit().frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("+\(b.xp) XP").font(.caption2.weight(.heavy).monospacedDigit()).foregroundStyle(b.main ? Theme.accent : .white)
                            Text(b.name).font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(.black.opacity(0.5), in: .capsule)
                }
                if withXP.count > shown.count {
                    Text("+\(withXP.count - shown.count) bros").font(.caption2.weight(.heavy))
                        .padding(.horizontal, 8).padding(.vertical, 9).background(.black.opacity(0.5), in: .capsule)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// Destaque da moldura Bro: 1 bro grande; 2 lado a lado; 3 ou mais, o principal grande com os outros menores atrás
    @ViewBuilder
    private var broHero: some View {
        let b = data.bros
        if b.count <= 1 {
            Image(sprite).resizable().interpolation(.none).scaledToFit().frame(width: 220, height: 220)
                .shadow(color: Theme.accent.opacity(0.6), radius: 24)
        } else if b.count == 2 {
            HStack(spacing: -10) {
                ForEach(b, id: \.self) { x in
                    Image(x.sprite).resizable().interpolation(.none).scaledToFit().frame(width: 150, height: 150)
                        .shadow(color: Theme.accent.opacity(0.5), radius: 18)
                }
            }
        } else {
            ZStack {
                Image(b[1].sprite).resizable().interpolation(.none).scaledToFit().frame(width: 110, height: 110).offset(x: -85, y: -20).opacity(0.9)
                Image(b[2].sprite).resizable().interpolation(.none).scaledToFit().frame(width: 110, height: 110).offset(x: 85, y: -20).opacity(0.9)
                Image(b[0].sprite).resizable().interpolation(.none).scaledToFit().frame(width: 190, height: 190)
                    .shadow(color: Theme.accent.opacity(0.6), radius: 24)
                if b.count > 3 {
                    Text("+\(b.count - 3)").font(.caption.weight(.black))
                        .padding(.horizontal, 8).padding(.vertical, 3).background(Theme.accent, in: .capsule).foregroundStyle(.black)
                        .offset(x: 110, y: 60)
                }
            }
            .frame(width: 300, height: 220)
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

/// Trajeto do GPS desenhado como uma linha, sem mapa (proporção real, centralizado)
struct RouteDrawing: View {
    let coords: [CLLocationCoordinate2D]
    var lineWidth: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack {
                Path { p in p.addLines(pts) }
                    .stroke(Theme.accent.opacity(0.35), style: StrokeStyle(lineWidth: lineWidth * 2.6, lineCap: .round, lineJoin: .round))
                    .blur(radius: 4)
                Path { p in p.addLines(pts) }
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                if let first = pts.first { dot(first, .white) }
                if let last = pts.last { dot(last, Theme.accent) }
            }
        }
    }

    private func dot(_ p: CGPoint, _ c: Color) -> some View {
        Circle().fill(c).frame(width: lineWidth * 2.4, height: lineWidth * 2.4)
            .overlay(Circle().stroke(.black.opacity(0.6), lineWidth: 1.5))
            .position(p)
    }

    /// Latitude/longitude → pontos na tela; a longitude encolhe com a latitude para não distorcer
    private func points(in size: CGSize) -> [CGPoint] {
        guard coords.count > 1 else { return [] }
        let k = cos(coords[0].latitude * .pi / 180)
        let xs = coords.map { $0.longitude * k }, ys = coords.map { $0.latitude }
        let minX = xs.min()!, maxX = xs.max()!, minY = ys.min()!, maxY = ys.max()!
        let w = max(maxX - minX, 1e-9), h = max(maxY - minY, 1e-9)
        let pad = lineWidth * 2
        let scale = min((size.width - pad * 2) / w, (size.height - pad * 2) / h)
        let ox = (size.width - w * scale) / 2, oy = (size.height - h * scale) / 2
        return zip(xs, ys).map { CGPoint(x: ox + ($0 - minX) * scale, y: oy + (maxY - $1) * scale) }
    }
}
