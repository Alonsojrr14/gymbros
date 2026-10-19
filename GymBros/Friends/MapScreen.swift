import CoreLocation
import MapKit
import SwiftData
import SwiftUI

/// Aba Mapa: academia, frequência, atividades ao ar livre e percursos
struct MapScreen: View {
    @Query(sort: \RouteRecord.start, order: .reverse) private var routes: [RouteRecord]
    @Query(sort: \GymVisit.start, order: .reverse) private var visits: [GymVisit]
    @Query(sort: \Gym.createdAt) private var gyms: [Gym]
    @Query private var activities: [Activity]
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var editing: GymEdit?
    @State private var outdoor: ActivityKind?
    @State private var route: RouteRecord?
    @State private var here: CLLocation?
    /// Lendo a posição pelo cartão de status
    @State private var locating = false
    @State private var arrival = GymLocation.shared.notifyArrival
    @State private var autoFinish = GymLocation.shared.autoFinish
    @State private var settings = false
    // Prévia "Strava": amigos treinando agora
    @State private var showFriends = true
    @State private var friend: LiveFriend?
    @State private var cheered: Set<String> = []
    @State private var chat: LiveFriend?
    @State private var tick = Date.now
    @AppStorage(LiveShare.key) private var shareLive = LiveShare.defaultOn

    var body: some View {
        NavigationStack {
            GMScreen("Mapa", avatar: true) {
                GMIconButton(icon: "gearshape") { settings = true }
            } content: {
                bigMap
                if needsAlways { permissionBanner }
                SocialGate(requires: .friendsRead) { friendsSection }
                monthStats
                outdoorSection
                gymSection
                if !routes.isEmpty { routesSection }
            }
            .gmSheet(isPresented: $settings) { _ in settingsSheet }
            .gmModal(item: $editing) { GymEditorView(gym: $0.gym) }
            .gmModal(item: $outdoor) { RouteRunView(kind: $0) }
            .gmModal(item: $chat) { f in NavigationStack { ConversationView(peerID: f.id) } }
            .gmSheet(isPresented: Binding(get: { route != nil }, set: { if !$0 { route = nil } })) { _ in
                if let r = route { routeDetail(r) }
            }
            .gmSheet(isPresented: Binding(get: { friend != nil }, set: { if !$0 { friend = nil } })) { close in
                if let f = friend {
                    LiveFriendCard(friend: f, cheered: $cheered, onMessage: {
                        close()
                        // A conversa abre depois que o card termina de fechar
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { chat = f }
                    })
                }
            }
            .task {
                here = await GymLocation.shared.currentLocation()
                focusPlaces()
            }
            // Amigos em movimento (corrida) andam no mapa
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2))
                    tick = .now
                }
            }
        }
    }

    // MARK: Mapa

    private var bigMap: some View {
        Map(position: $camera) {
            UserAnnotation()
            ForEach(gyms) { g in
                MapCircle(center: g.coordinate, radius: g.radius).foregroundStyle(Theme.accent.opacity(0.18)).stroke(Theme.accent, lineWidth: 2)
                Annotation(g.name, coordinate: g.coordinate) {
                    Image(systemName: "dumbbell.fill").font(.caption.bold()).padding(8).background(Theme.accent, in: .circle).foregroundStyle(.black)
                }
            }
            ForEach(routes.prefix(10)) { r in
                MapPolyline(coordinates: r.coordinates).stroke(color(r.kind).opacity(0.85), lineWidth: 4)
            }
            if showFriends, let b = friendsBase {
                ForEach(FriendsLive.all.filter { $0.moves && $0.isLive }) { f in
                    MapPolyline(coordinates: f.trail(base: b, at: tick)).stroke(f.color, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
                ForEach(FriendsLive.all) { f in
                    Annotation(f.name, coordinate: f.coordinate(base: b, at: tick)) {
                        FriendPin(friend: f, date: tick).onTapGesture { focus(f); friend = f }
                    }
                    .annotationTitles(.hidden)
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: 340)
        .clipShape(.rect(cornerRadius: Theme.radius))
        .overlay(alignment: .topTrailing) {
            GMIconButton(icon: "scope", size: 36, label: "Minha localização") { Task { await focusMe() } }.padding(10)
        }
        .overlay(alignment: .topLeading) { friendsToggle.padding(10) }
        .overlay(alignment: .bottom) { statusPill.padding(10) }
    }

    /// Onde você está agora, por cima do mapa. Tocar atualiza a posição e leva o mapa à academia mais próxima
    private var statusPill: some View {
        let inside = GymLocation.shared.insideGym
        let nearest = here.flatMap { h in gyms.map { ($0, $0.location.distance(from: h)) }.min { $0.1 < $1.1 } }
        return Button { Task { await goNearest() } } label: { HStack(spacing: 10) {
            ZStack {
                if locating {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: inside != nil ? "figure.strengthtraining.traditional" : "location.fill")
                        .font(.subheadline.bold())
                }
            }
                .frame(width: 34, height: 34)
                .background(inside != nil ? Theme.accent : Theme.raised, in: .circle)
                .foregroundStyle(inside != nil ? .black : .white)
            VStack(alignment: .leading, spacing: 1) {
                if let inside {
                    Text("Você está na \(inside.name)").font(.subheadline.bold()).lineLimit(1)
                    Text(LiveWorkout.hasRunning ? "Treino em andamento" : "Bora treinar 💪").font(.caption).foregroundStyle(Theme.accent)
                } else if let (g, m) = nearest {
                    Text(g.name).font(.subheadline.bold()).lineLimit(1)
                    Text("Lugar mais próximo · \(distance(m))").font(.caption).foregroundStyle(Theme.dim)
                } else {
                    Text(gyms.isEmpty ? "Nenhum lugar salvo" : "Procurando você…").font(.subheadline.bold())
                    Text(gyms.isEmpty ? "Ao começar um treino, o app pergunta onde você está" : "Permita a localização para ver a distância")
                        .font(.caption).foregroundStyle(Theme.dim).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if !gyms.isEmpty || here == nil {
                Image(systemName: "arrow.clockwise").font(.caption.bold()).foregroundStyle(Theme.dim)
            }
        }
        .padding(10)
        .background(Theme.bg.opacity(0.92), in: .rect(cornerRadius: Theme.radiusL))
        .foregroundStyle(.white)
        .contentShape(Rectangle())
        }
        .buttonStyle(GMPress())
        .disabled(locating)
    }

    /// Lê a posição de novo e enquadra a academia mais próxima (sem academia salva, centraliza em você)
    private func goNearest() async {
        locating = true
        if let h = await GymLocation.shared.currentLocation() { here = h }
        locating = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let h = here, let g = gyms.min(by: { $0.location.distance(from: h) < $1.location.distance(from: h) }) {
            withAnimation { camera = .region(MKCoordinateRegion(center: g.coordinate, latitudinalMeters: 800, longitudinalMeters: 800)) }
        } else if !gyms.isEmpty {
            focusPlaces()
        } else {
            await focusMe()
        }
    }

    private var needsAlways: Bool { !gyms.isEmpty && GymLocation.shared.authorization != .authorizedAlways }

    private var permissionBanner: some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
                Text("Permita a localização \"Sempre\" para avisar ao chegar e encerrar o treino ao sair com o app fechado.")
                    .font(.caption).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.dim)
            }
            .padding(12)
            .background(Theme.warning.opacity(0.1), in: .rect(cornerRadius: Theme.radiusM))
            .foregroundStyle(.white)
        }
        .buttonStyle(GMPress())
    }

    /// Números do mês, em linha
    private var monthStats: some View {
        let month = Calendar.current.dateInterval(of: .month, for: .now)!
        let monthVisits = visits.filter { month.contains($0.start) }
        let km = routes.filter { month.contains($0.start) }.reduce(0) { $0 + $1.meters }
        return HStack(spacing: 8) {
            chip("\(monthVisits.count)", "idas à academia")
            chip(avgMinutes(monthVisits).map { durationText($0) } ?? "–", "tempo médio")
            chip(km > 0 ? kmText(km) : "–", "ao ar livre")
        }
    }

    private func chip(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundStyle(Theme.dim).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.card, in: .rect(cornerRadius: Theme.radiusL))
    }

    // MARK: Amigos ao vivo (prévia)

    /// Os amigos simulados ficam em volta de onde você treina (ou de onde você está)
    private var friendsBase: CLLocationCoordinate2D? {
        (here.flatMap { h in gyms.min { $0.location.distance(from: h) < $1.location.distance(from: h) } } ?? gyms.first)?.coordinate
            ?? here?.coordinate
    }

    private var friendsToggle: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.snappy) { showFriends.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill").font(.caption.bold())
                Text(showFriends ? "\(FriendsLive.liveCount) ao vivo" : "Amigos").font(.caption.bold())
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(showFriends ? Theme.accent : Theme.bg.opacity(0.85), in: .capsule)
            .foregroundStyle(showFriends ? .black : .white)
        }
        .buttonStyle(GMPress())
    }

    private var friendsSection: some View {
        let list = FriendsLive.all.sorted { ($0.isLive ? 0 : 1, $0.start ?? .distantFuture) < ($1.isLive ? 0 : 1, $1.start ?? .distantFuture) }
        return GMSection("Amigos agora", footer: "Prévia com amigos simulados. Quando as ligas tiverem servidor, aparecem seus amigos de verdade: só quem ligar \"Compartilhar treino ao vivo\".") {
            ForEach(list) { f in
                Button { focus(f); friend = f } label: { LiveFriendRow(friend: f, date: tick).foregroundStyle(.white) }
                    .buttonStyle(GMPress())
                if f.id != list.last?.id { GMDivider() }
            }
        }
    }

    private func focus(_ f: LiveFriend) {
        guard let b = friendsBase else { return }
        showFriends = true
        withAnimation { camera = .region(MKCoordinateRegion(center: f.coordinate(base: b, at: .now), latitudinalMeters: 700, longitudinalMeters: 700)) }
    }

    /// Ajustes de localização, fora da lista de lugares
    private var settingsSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Localização").font(.headline)
            GMToggle(title: "Avisar ao chegar", subtitle: "Sugere começar o treino do dia quando você chega num lugar salvo", isOn: $arrival)
                .onChange(of: arrival) { _, v in GymLocation.shared.notifyArrival = v }
            GMDivider()
            GMToggle(title: "Encerrar treino ao sair", subtitle: "Salva o treino em andamento (mais de 10 min) quando você sai do lugar", isOn: $autoFinish)
                .onChange(of: autoFinish) { _, v in GymLocation.shared.autoFinish = v }
            GMDivider()
            GMToggle(title: "Compartilhar treino ao vivo", subtitle: "Padrão dos próximos treinos: amigos veem onde você treina e o exercício atual, só durante o treino. Cada treino pode mudar no chip \"Ao vivo\". Ainda não envia nada: chega quando o app tiver servidor", isOn: $shareLive)
            GMDivider()
            Text("Ao começar musculação ou CrossFit, o app reconhece o lugar ou pergunta onde você está. Fora de um treino ao vivo, a localização fica só no seu iPhone.")
                .font(.caption).foregroundStyle(Theme.dim)
        }
    }

    /// Centraliza no lugar mais próximo de você (ou no primeiro salvo)
    private func focusPlaces() {
        let target = here.flatMap { h in gyms.min { $0.location.distance(from: h) < $1.location.distance(from: h) } } ?? gyms.first
        guard let g = target else { return }
        withAnimation { camera = .region(MKCoordinateRegion(center: g.coordinate, latitudinalMeters: 1500, longitudinalMeters: 1500)) }
    }

    /// Botão do mapa: centraliza onde você está agora (lê a posição de novo, você pode ter andado)
    private func focusMe() async {
        if let h = await GymLocation.shared.currentLocation() { here = h }
        withAnimation {
            camera = here.map { .region(MKCoordinateRegion(center: $0.coordinate, latitudinalMeters: 1500, longitudinalMeters: 1500)) }
                ?? .userLocation(fallback: .automatic)
        }
    }

    private func color(_ k: ActivityKind) -> Color {
        switch k {
        case .bike: .orange
        case .caminhada: .cyan
        default: Theme.accent
        }
    }

    // MARK: Lugares de treino

    private var gymSection: some View {
        // Mais visitados primeiro; conta visitas detectadas e treinos registrados no lugar
        let sorted = gyms.sorted { count($0) > count($1) }
        return GMSection("Lugares de treino", trailing: AnyView(
            GMTextButton(title: "Adicionar", icon: "plus", small: true) { editing = GymEdit(gym: nil) }
        )) {
            if sorted.isEmpty {
                Text("Nenhum lugar ainda. Toque em Adicionar ou comece um treino na academia.").font(.subheadline).foregroundStyle(Theme.dim)
            }
            ForEach(sorted) { g in
                gymRow(g)
                if g.id != sorted.last?.id { GMDivider() }
            }
        }
    }

    private func gymRow(_ g: Gym) -> some View {
        let inside = GymLocation.shared.insideID == g.uuid
        let last = lastDate(g)
        return HStack(spacing: 12) {
            // Tocar no ícone centraliza no mapa
            Button {
                withAnimation { camera = .region(MKCoordinateRegion(center: g.coordinate, latitudinalMeters: 800, longitudinalMeters: 800)) }
            } label: {
                Image(systemName: inside ? "figure.strengthtraining.traditional" : "dumbbell.fill")
                    .font(.subheadline.bold())
                    .frame(width: 40, height: 40)
                    .background(inside ? Theme.accent : Theme.raised, in: .circle)
                    .foregroundStyle(inside ? .black : .white)
            }
            .buttonStyle(GMPress())
            Button { editing = GymEdit(gym: g) } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(g.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text("\(count(g)) treino\(count(g) == 1 ? "" : "s")" + (last.map { " · último \($0.formatted(.dateTime.day().month(.abbreviated)))" } ?? ""))
                            .font(.caption).foregroundStyle(Theme.dim)
                    }
                    Spacer()
                    if let h = here { Text(distance(g.location.distance(from: h))).font(.caption.monospacedDigit()).foregroundStyle(Theme.dim) }
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.dim)
                }
                .contentShape(Rectangle())
                .foregroundStyle(.white)
            }
            .buttonStyle(GMPress())
        }
    }

    private func count(_ g: Gym) -> Int {
        max(visits.filter { $0.gymUUID == g.uuid }.count, activities.filter { $0.gymUUID == g.uuid }.count)
    }

    private func lastDate(_ g: Gym) -> Date? {
        (visits.filter { $0.gymUUID == g.uuid }.map(\.start) + activities.filter { $0.gymUUID == g.uuid }.map(\.date)).max()
    }

    private func avgMinutes(_ list: [GymVisit]) -> Int? {
        let d = list.compactMap(\.minutes).filter { $0 >= 5 }
        return d.isEmpty ? nil : d.reduce(0, +) / d.count
    }

    private func distance(_ m: Double) -> String { m < 1000 ? "\(Int(m)) m" : kmText(m) }

    // MARK: Ao ar livre

    private var outdoorSection: some View {
        let month = Calendar.current.dateInterval(of: .month, for: .now)!
        let monthRoutes = routes.filter { month.contains($0.start) }
        return GMSection("Começar ao ar livre", footer: "Grava o percurso pelo GPS. Embaixo de cada um, o total do mês.") {
            HStack(spacing: 10) {
                ForEach([ActivityKind.corrida, .caminhada, .bike]) { k in
                    Button { outdoor = k } label: {
                        VStack(spacing: 6) {
                            Image(systemName: k.symbol).font(.title2).frame(height: 30)
                            Text(k.name).font(.caption.weight(.semibold))
                            Text(kmText(monthRoutes.filter { $0.kind == k }.reduce(0) { $0 + $1.meters }))
                                .font(.caption2.monospacedDigit()).foregroundStyle(Theme.dim)
                        }
                        .frame(maxWidth: .infinity, minHeight: 88)
                        .background(Theme.raised, in: .rect(cornerRadius: Theme.radiusM))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(GMPress())
                }
            }
        }
    }

    private var routesSection: some View {
        GMSection("Percursos") {
            ForEach(routes.prefix(20)) { r in
                Button { route = r } label: {
                    HStack(spacing: 12) {
                        RouteMap(coords: r.coordinates).frame(width: 64, height: 64).clipShape(.rect(cornerRadius: Theme.radiusM))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(r.kind.name) · \(kmText(r.meters))").font(.subheadline.weight(.semibold))
                            Text("\(r.start.formatted(.dateTime.day().month(.abbreviated).hour().minute())) · \(clock(r.seconds)) · \(paceText(kind: r.kind, meters: r.meters, seconds: r.seconds))")
                                .font(.caption).foregroundStyle(Theme.dim)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.dim)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(GMPress())
                if r.id != routes.prefix(20).last?.id { GMDivider() }
            }
        }
    }

    private func routeDetail(_ r: RouteRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(r.kind.name) · \(kmText(r.meters))").font(.headline)
            RouteMap(coords: r.coordinates).frame(height: 300).clipShape(.rect(cornerRadius: Theme.radiusL))
            HStack {
                stat(clock(r.seconds), "tempo")
                stat(kmText(r.meters), "distância")
                stat(paceText(kind: r.kind, meters: r.meters, seconds: r.seconds), r.kind == .bike ? "velocidade" : "ritmo")
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity)
    }
}

struct GymEdit: Identifiable {
    let gym: Gym?
    var id: String { gym?.uuid.uuidString ?? "novo" }
}
