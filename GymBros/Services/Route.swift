import CoreLocation
import MapKit
import SwiftData
import SwiftUI

// Corrida, caminhada e bike com GPS: percurso no mapa, distância, tempo e ritmo.
// Continua gravando com a tela bloqueada (localização em segundo plano).

func kmText(_ meters: Double) -> String {
    String(format: "%.2f km", meters / 1000).replacingOccurrences(of: ".", with: ",")
}

/// Ritmo (min/km) para corrida e caminhada; velocidade (km/h) para bike
func paceText(kind: ActivityKind, meters: Double, seconds: Int) -> String {
    guard meters > 20, seconds > 0 else { return "–" }
    if kind == .bike {
        return String(format: "%.1f km/h", meters / 1000 / (Double(seconds) / 3600)).replacingOccurrences(of: ".", with: ",")
    }
    let perKm = Double(seconds) / (meters / 1000)
    return String(format: "%d'%02d\" /km", Int(perKm) / 60, Int(perKm) % 60)
}

@MainActor
@Observable
final class RouteTracker: NSObject, CLLocationManagerDelegate {
    let kind: ActivityKind
    private let manager = CLLocationManager()
    private(set) var coords: [CLLocationCoordinate2D] = []
    private(set) var meters: Double = 0
    private(set) var start: Date?
    private(set) var pausedAt: Date?
    private var pausedTotal: TimeInterval = 0
    private var last: CLLocation?
    private(set) var current: CLLocation?

    init(kind: ActivityKind) {
        self.kind = kind
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = kind == .bike ? .otherNavigation : .fitness
        manager.distanceFilter = 5
    }

    func elapsed(_ now: Date = .now) -> Int {
        guard let start else { return 0 }
        return max(Int((pausedAt ?? now).timeIntervalSince(start) - pausedTotal), 0)
    }

    func prepare() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func begin() {
        start = .now
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.startUpdatingLocation()
    }

    func togglePause() {
        if let p = pausedAt {
            pausedTotal += Date.now.timeIntervalSince(p)
            pausedAt = nil
            last = nil
        } else {
            pausedAt = .now
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        if pausedAt == nil { pausedAt = .now }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for loc in locations { self.add(loc) }
        }
    }

    private func add(_ loc: CLLocation) {
        current = loc
        // Só grava com boa precisão, com o treino rodando e não pausado
        guard start != nil, pausedAt == nil, loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < 30 else { return }
        if let last {
            let d = loc.distance(from: last)
            // Ignora saltos impossíveis do GPS (mais de 15 m/s)
            if d / max(loc.timestamp.timeIntervalSince(last.timestamp), 1) > 15 { return }
            meters += d
        }
        last = loc
        coords.append(loc.coordinate)
    }
}

// MARK: - Tela de gravação

struct RouteRunView: View {
    let kind: ActivityKind
    @Environment(\.dismiss) private var dismiss
    @State private var tracker: RouteTracker
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var finishing = false
    @State private var confirmQuit = false
    /// Id deste percurso para a escolha do ao vivo
    @State private var liveID = UUID().uuidString

    init(kind: ActivityKind) {
        self.kind = kind
        _tracker = State(initialValue: RouteTracker(kind: kind))
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let secs = tracker.elapsed(ctx.date)
            ZStack(alignment: .bottom) {
                Map(position: $camera) {
                    UserAnnotation()
                    if tracker.coords.count > 1 {
                        MapPolyline(coordinates: tracker.coords).stroke(Theme.accent, lineWidth: 6)
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .ignoresSafeArea()

                GMCard(padding: 18) { VStack(spacing: 14) {
                    LiveShareChip(workoutID: liveID)
                    HStack {
                        stat(clock(secs), "tempo")
                        stat(kmText(tracker.meters), "distância")
                        stat(paceText(kind: kind, meters: tracker.meters, seconds: secs), kind == .bike ? "velocidade" : "ritmo")
                    }
                    if tracker.start == nil {
                        GMButton("Começar \(kind.name.lowercased())", icon: "play.fill") { tracker.begin() }
                    } else {
                        HStack(spacing: 10) {
                            GMButton(tracker.pausedAt == nil ? "Pausar" : "Continuar", icon: tracker.pausedAt == nil ? "pause.fill" : "play.fill",
                                     kind: .secondary) { tracker.togglePause() }
                            GMButton("Terminar", icon: "flag.checkered") {
                                tracker.stop()
                                finishing = true
                            }
                        }
                    }
                } }
                .padding(12)
            }
            .overlay(alignment: .topLeading) {
                GMIconButton(icon: "xmark") { if tracker.start == nil { dismiss() } else { confirmQuit = true } }
                    .padding(16)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .onAppear {
            tracker.prepare()
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            tracker.stop()
            LiveShare.end(liveID)
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .gmActions(isPresented: $confirmQuit, title: "Sair sem salvar?", message: "O percurso será descartado.", actions: [
            GMAction("Sair sem salvar", icon: "xmark", destructive: true) { dismiss() }
        ])
        .gmModal(isPresented: $finishing) {
            RouteFinishView(tracker: tracker) { dismiss() }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.heavy).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity)
    }
}

struct RouteFinishView: View {
    let tracker: RouteTracker
    let onDone: () -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var effort = 6
    @State private var leagues: Set<UUID> = []
    @State private var photo: Data?

    var body: some View {
        let secs = tracker.elapsed()
        GMModal("\(tracker.kind.name) concluída", confirm: "Salvar", confirmEnabled: hasPostDestination(leagues), onConfirm: save) {
            if tracker.coords.count > 1 {
                RouteMap(coords: tracker.coords).frame(height: 220).clipShape(.rect(cornerRadius: Theme.radiusL))
            }
            GMCard {
                HStack {
                    stat(clock(secs), "tempo")
                    stat(kmText(tracker.meters), "distância")
                    stat(paceText(kind: tracker.kind, meters: tracker.meters, seconds: secs), tracker.kind == .bike ? "velocidade" : "ritmo")
                }
            }
            GMSection { GMEffortPicker(value: $effort) }
            LeaguePostSection(selected: $leagues, photo: $photo)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.monospacedDigit())
            Text(label).font(.caption).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity)
    }

    private func save() {
        let secs = tracker.elapsed()
        let start = tracker.start ?? .now
        let activity = Activity(kind: tracker.kind, date: start, minutes: max(secs / 60, 1), effort: effort,
                                note: kmText(tracker.meters) + " · " + paceText(kind: tracker.kind, meters: tracker.meters, seconds: secs))
        activity.meters = tracker.meters
        context.insert(activity)
        let route = RouteRecord(kind: tracker.kind, start: start)
        route.activityUUID = activity.uuid
        route.seconds = secs
        route.meters = tracker.meters
        route.points = RouteRecord.encode(tracker.coords)
        context.insert(route)
        ActivitySplits.stamp(activity, context: context)
        postCheckIns(activity: activity, leagues: leagues, title: "\(tracker.kind.name) · \(kmText(tracker.meters))", note: "", photo: photo, context: context)
        try? context.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
        onDone()
    }
}

/// Mapa estático de um percurso, enquadrado nele
struct RouteMap: View {
    let coords: [CLLocationCoordinate2D]

    var body: some View {
        Map(initialPosition: .rect(rect)) {
            MapPolyline(coordinates: coords).stroke(Theme.accent, lineWidth: 5)
            if let first = coords.first { Annotation("", coordinate: first) { Circle().fill(.white).frame(width: 12, height: 12) } }
            if let last = coords.last { Annotation("", coordinate: last) { Circle().fill(Theme.accent).frame(width: 14, height: 14) } }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .allowsHitTesting(false)
    }

    private var rect: MKMapRect {
        let points = coords.map(MKMapPoint.init)
        var r = points.reduce(MKMapRect.null) { $0.union(MKMapRect(origin: $1, size: MKMapSize(width: 1, height: 1))) }
        r = r.insetBy(dx: -r.size.width * 0.2 - 300, dy: -r.size.height * 0.2 - 300)
        return r
    }
}

// MARK: - Lugar de treino no mapa (criar ou editar)

struct GymEditorView: View {
    /// nil = lugar novo
    let gym: Gym?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var center: CLLocationCoordinate2D?
    @State private var radius = 100.0
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var locating = false
    @State private var suggestions: [(name: String, meters: Double)] = []
    @State private var confirmDelete = false

    var body: some View {
        GMModal(gym == nil ? "Novo lugar" : "Editar lugar", confirm: "Salvar", confirmEnabled: center != nil, onConfirm: save) {
            // Mapa em destaque: tocar marca o lugar; o botão no canto usa onde você está
            MapReader { proxy in
                Map(position: $camera) {
                    UserAnnotation()
                    if let center {
                        MapCircle(center: center, radius: radius).foregroundStyle(Theme.accent.opacity(0.2)).stroke(Theme.accent, lineWidth: 2)
                        Annotation(name, coordinate: center) {
                            Image(systemName: "dumbbell.fill").font(.caption.bold()).padding(8).background(Theme.accent, in: .circle).foregroundStyle(.black)
                        }
                    }
                }
                .onTapGesture { point in
                    if let c = proxy.convert(point, from: .local) { center = c; Task { await suggest(CLLocation(latitude: c.latitude, longitude: c.longitude)) } }
                }
            }
            .frame(height: 320)
            .clipShape(.rect(cornerRadius: Theme.radius))
            .overlay(alignment: .top) {
                Text(center == nil ? "Toque no mapa para marcar o lugar" : "Toque em outro ponto para mover")
                    .font(.caption.bold())
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Theme.bg.opacity(0.9), in: .capsule)
                    .padding(10)
            }
            .overlay(alignment: .bottomTrailing) {
                Button { Task { await useCurrent() } } label: {
                    Label(locating ? "Buscando…" : "Estou aqui", systemImage: "location.fill")
                        .font(.caption.bold())
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(Theme.accent, in: .capsule)
                        .foregroundStyle(.black)
                }
                .buttonStyle(GMPress())
                .disabled(locating)
                .padding(10)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("RAIO").font(.caption.weight(.bold)).foregroundStyle(Theme.dim).tracking(0.6).padding(.horizontal, 4)
                GMSegmented(options: [(50.0, "50 m"), (100.0, "100 m"), (150.0, "150 m"), (250.0, "250 m")], selection: $radius)
                Text("100 m cobre uma academia comum. Aumente se o GPS da região for impreciso.")
                    .font(.caption).foregroundStyle(Theme.dim).padding(.horizontal, 4)
            }

            GMSection("Nome") {
                GMTextField(placeholder: "Ex.: Smart Fit Paulista", text: $name)
            }

            if !suggestions.isEmpty {
                GMSection("Academias aqui perto") {
                    ForEach(suggestions, id: \.name) { s in
                        Button { name = s.name } label: {
                            HStack {
                                Image(systemName: "dumbbell.fill").font(.caption).foregroundStyle(Theme.dim).frame(width: 22)
                                Text(s.name).font(.subheadline).lineLimit(1)
                                Spacer()
                                Text(s.meters < 1000 ? "\(Int(s.meters)) m" : kmText(s.meters)).font(.caption.monospacedDigit()).foregroundStyle(Theme.dim)
                                Image(systemName: name == s.name ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(name == s.name ? Theme.accent : Theme.dim)
                            }
                            .contentShape(Rectangle())
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(GMPress())
                        if s.name != suggestions.last?.name { GMDivider() }
                    }
                }
            }

            if let gym {
                GMButton("Apagar \(gym.name)", icon: "trash", kind: .secondary) { confirmDelete = true }
                Text("O histórico de treinos continua; só o lugar some.").font(.caption).foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity)
            }
        }
        .gmActions(isPresented: $confirmDelete, title: "Apagar \(gym?.name ?? "")?", actions: [
            GMAction("Apagar lugar", icon: "trash", destructive: true) {
                if let gym { GymLocation.shared.delete(gym) }
                dismiss()
            }
        ])
        .onAppear {
            guard let g = gym else { return }
            name = g.name
            center = g.coordinate
            radius = g.radius
            camera = .region(MKCoordinateRegion(center: g.coordinate, latitudinalMeters: 600, longitudinalMeters: 600))
        }
    }

    private func useCurrent() async {
        locating = true
        if let loc = await GymLocation.shared.currentLocation() {
            center = loc.coordinate
            withAnimation { camera = .region(MKCoordinateRegion(center: loc.coordinate, latitudinalMeters: 600, longitudinalMeters: 600)) }
            await suggest(loc)
        }
        locating = false
    }

    private func suggest(_ loc: CLLocation) async {
        suggestions = await GymLocation.shared.suggestions(near: loc)
        if name.isEmpty, let first = suggestions.first, first.meters < 150 { name = first.name }
    }

    private func save() {
        guard let center else { return }
        if let gym {
            gym.name = name.trimmingCharacters(in: .whitespaces).isEmpty ? gym.name : name
            gym.latitude = center.latitude
            gym.longitude = center.longitude
            gym.radius = radius
            try? AppData.container.mainContext.save()
            GymLocation.shared.startMonitoring()
        } else {
            GymLocation.shared.add(name: name, at: center, radius: radius)
        }
        dismiss()
    }
}

// MARK: - "Onde você está treinando?"

/// Ao começar um treino num lugar desconhecido: escolhe um lugar salvo, salva um novo ou segue sem lugar
struct GymChooserView: View {
    let onPick: (Gym?) -> Void
    @State private var here: CLLocation?
    @State private var nearby: [(gym: Gym, meters: Double)] = []
    @State private var suggestions: [(name: String, meters: Double)] = []
    @State private var newName = ""
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Onde você está treinando?").font(.headline)
            if loading {
                HStack { Spacer(); Text("Procurando…").foregroundStyle(Theme.dim); Spacer() }.padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if !nearby.isEmpty {
                            Text("Seus lugares por perto").font(.caption.bold()).foregroundStyle(Theme.dim)
                            ForEach(nearby, id: \.gym.uuid) { n in
                                GMRow(icon: "dumbbell.fill", iconTint: Theme.accent, title: n.gym.name, subtitle: distance(n.meters),
                                      action: { onPick(n.gym) }) { EmptyView() }
                            }
                        }
                        if here != nil {
                            Text("Salvar um lugar novo aqui").font(.caption.bold()).foregroundStyle(Theme.dim).padding(.top, 6)
                            if !suggestions.isEmpty {
                                GMFlow {
                                    ForEach(suggestions, id: \.name) { s in
                                        GMChip(title: "\(s.name) · \(distance(s.meters))", selected: newName == s.name) { newName = s.name }
                                    }
                                }
                            }
                            GMTextField(placeholder: "Nome do lugar", text: $newName)
                            GMButton("Salvar e usar este lugar", icon: "plus", enabled: !newName.trimmingCharacters(in: .whitespaces).isEmpty) {
                                if let here { onPick(GymLocation.shared.add(name: newName, at: here.coordinate)) }
                            }
                        } else {
                            Text("Não consegui sua localização. Confira a permissão em Ajustes do iPhone → GymBros → Localização.")
                                .font(.caption).foregroundStyle(Theme.dim)
                        }
                    }
                }
                .frame(maxHeight: 420)
            }
            GMButton("Não estou numa academia", kind: .ghost) { onPick(nil) }
        }
        .task {
            here = await GymLocation.shared.currentLocation()
            if let here {
                nearby = GymLocation.shared.nearby(here)
                suggestions = await GymLocation.shared.suggestions(near: here)
                if let first = suggestions.first, first.meters < 150 { newName = first.name }
            }
            loading = false
        }
    }

    private func distance(_ m: Double) -> String { m < 1000 ? "\(Int(m)) m" : kmText(m) }
}

/// Identifica o lugar ao começar um treino: lugar conhecido é escolhido sozinho; senão, pergunta
@MainActor
enum PlaceDetector {
    enum Result { case known(Gym), ask }

    static func detect() async -> Result {
        if let g = GymLocation.shared.insideGym { return .known(g) }
        guard let loc = await GymLocation.shared.currentLocation() else { return .ask }
        if let g = GymLocation.shared.gym(containing: loc) { return .known(g) }
        return .ask
    }
}
