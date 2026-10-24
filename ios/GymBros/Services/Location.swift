import CoreLocation
import MapKit
import SwiftData
import UserNotifications

/// Lugares de treino: identifica onde a pessoa está, avisa ao chegar e encerra o treino ao sair.
/// Usa o CLMonitor do iOS 17 (até 20 lugares), que acorda o app em segundo plano ao entrar/sair de um raio.
@MainActor
final class GymLocation: NSObject, CLLocationManagerDelegate {
    static let shared = GymLocation()

    let manager = CLLocationManager()
    private var monitorTask: Task<Void, Never>?
    /// Um só CLMonitor("gymbros") no processo: criar outro com o mesmo nome antes de o anterior sumir derruba o app
    /// (asserção do CoreLocation em CLMonitor.init). Acontecia ao entrar na conta, com várias chamadas seguidas.
    private var monitorMaker: Task<CLMonitor, Never>?
    private var oneShot: CheckedContinuation<CLLocation?, Never>?

    /// Treinos com menos tempo que isso não são encerrados ao sair (evita falso alarme do GPS)
    static let minWorkoutMinutes = 10.0
    /// Até onde procurar lugares salvos e academias por perto ao perguntar
    static let nearbyMeters = 3000.0

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    private var ctx: ModelContext { AppData.container.mainContext }

    // MARK: Lugares

    var gyms: [Gym] { (try? ctx.fetch(FetchDescriptor<Gym>(sortBy: [SortDescriptor(\.createdAt)]))) ?? [] }

    /// Visita registrada pela localização que cruza o treino (de `start` até `minutes` depois)
    func visit(from start: Date, minutes: Int) -> GymVisit? {
        let end = start.addingTimeInterval(TimeInterval(max(minutes, 1) * 60))
        let visits = (try? ctx.fetch(FetchDescriptor<GymVisit>(predicate: #Predicate { $0.start <= end }))) ?? []
        return visits.last { ($0.end ?? .now) >= start }
    }

    func gym(_ id: UUID?) -> Gym? {
        guard let id else { return nil }
        return try? ctx.fetch(FetchDescriptor<Gym>(predicate: #Predicate { $0.uuid == id })).first
    }

    @discardableResult
    func add(name: String, at coordinate: CLLocationCoordinate2D, radius: Double = 100) -> Gym {
        let g = Gym(name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "Academia" : name, coordinate: coordinate, radius: radius)
        ctx.insert(g)
        try? ctx.save()
        startMonitoring()
        requestAlways()
        return g
    }

    func delete(_ g: Gym) {
        if insideID == g.uuid { insideID = nil }
        ctx.delete(g)
        try? ctx.save()
        startMonitoring()
    }

    /// Lugar salvo que contém a localização (o mais próximo, se houver mais de um)
    func gym(containing loc: CLLocation) -> Gym? {
        gyms.map { ($0, $0.location.distance(from: loc)) }
            .filter { $0.1 <= max($0.0.radius, loc.horizontalAccuracy) }
            .min { $0.1 < $1.1 }?.0
    }

    /// Lugares salvos por perto, do mais próximo ao mais distante
    func nearby(_ loc: CLLocation) -> [(gym: Gym, meters: Double)] {
        gyms.map { ($0, $0.location.distance(from: loc)) }.filter { $0.1 <= Self.nearbyMeters }.sorted { $0.1 < $1.1 }
    }

    /// Academias reais por perto, pelo mapa da Apple (para sugerir o nome de um lugar novo)
    func suggestions(near loc: CLLocation) async -> [(name: String, meters: Double)] {
        let req = MKLocalPointsOfInterestRequest(center: loc.coordinate, radius: 400)
        req.pointOfInterestFilter = MKPointOfInterestFilter(including: [.fitnessCenter])
        guard let items = try? await MKLocalSearch(request: req).start().mapItems else { return [] }
        return items.compactMap { item in
            guard let name = item.name, let l = item.placemark.location else { return nil }
            return (name, l.distance(from: loc))
        }
        .sorted { $0.1 < $1.1 }
        .prefix(5).map { $0 }
    }

    // MARK: Preferências

    var notifyArrival: Bool {
        get { UserDefaults.standard.object(forKey: "gymNotifyArrival") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "gymNotifyArrival") }
    }

    var autoFinish: Bool {
        get { UserDefaults.standard.object(forKey: "gymAutoFinish") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "gymAutoFinish") }
    }

    /// Lugar em que está agora (último evento de entrada)
    var insideID: UUID? {
        get { UserDefaults.standard.string(forKey: "gymInsideID").flatMap(UUID.init) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: "gymInsideID") }
    }

    var insideGym: Gym? { gym(insideID) }

    /// Chegada recente ainda sem treino começado (o app oferece começar ao abrir)
    var pendingArrival: Date? {
        get { UserDefaults.standard.object(forKey: "gymArrival") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "gymArrival") }
    }

    /// Nome do lugar para check-ins feitos agora
    var placeNow: String? { insideGym?.name }

    var authorization: CLAuthorizationStatus { manager.authorizationStatus }

    func requestAlways() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        manager.requestAlwaysAuthorization()
    }

    // MARK: Localização atual

    func currentLocation() async -> CLLocation? {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        return await withCheckedContinuation { c in
            oneShot?.resume(returning: nil)
            oneShot = c
            manager.requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let loc = locations.last
        Task { @MainActor in
            self.oneShot?.resume(returning: loc)
            self.oneShot = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.oneShot?.resume(returning: nil)
            self.oneShot = nil
        }
    }

    // MARK: Monitoramento

    /// Precisa rodar a cada abertura do app (inclusive quando o iOS o acorda em segundo plano)
    func startMonitoring() {
        migrateSingleGym()
        monitorTask?.cancel()
        let list = recentGyms(limit: 20)
        // Criado na primeira vez, de forma síncrona no MainActor: chamadas seguidas reaproveitam o mesmo
        let maker = monitorMaker ?? Task { await CLMonitor("gymbros") }
        monitorMaker = maker
        monitorTask = Task { @MainActor in
            let monitor = await maker.value
            guard !Task.isCancelled else { return }
            for id in await monitor.identifiers { await monitor.remove(id) }
            for g in list {
                await monitor.add(CLMonitor.CircularGeographicCondition(center: g.coordinate, radius: g.radius),
                                  identifier: g.uuid.uuidString, assuming: insideID == g.uuid ? .satisfied : .unsatisfied)
            }
            guard !list.isEmpty else { return }
            do {
                for try await event in await monitor.events {
                    guard let id = UUID(uuidString: event.identifier), let g = self.gym(id) else { continue }
                    switch event.state {
                    case .satisfied: await self.arrived(g)
                    case .unsatisfied: await self.left(g)
                    default: break
                    }
                }
            } catch {}
        }
    }

    /// O iOS monitora até 20 lugares: os visitados mais recentemente
    private func recentGyms(limit: Int) -> [Gym] {
        let visits = (try? ctx.fetch(FetchDescriptor<GymVisit>(sortBy: [SortDescriptor(\.start, order: .reverse)]))) ?? []
        let last = Dictionary(visits.compactMap { v in v.gymUUID.map { ($0, v.start) } }, uniquingKeysWith: { a, _ in a })
        return gyms.sorted { (last[$0.uuid] ?? $0.createdAt) > (last[$1.uuid] ?? $1.createdAt) }.prefix(limit).map { $0 }
    }

    /// Versões anteriores guardavam uma academia só, fora do banco
    private func migrateSingleGym() {
        guard let data = UserDefaults.standard.data(forKey: "gym") else { return }
        struct Old: Codable { var name: String; var latitude: Double; var longitude: Double; var radius: Double }
        if let old = try? JSONDecoder().decode(Old.self, from: data) {
            let g = Gym(name: old.name, coordinate: CLLocationCoordinate2D(latitude: old.latitude, longitude: old.longitude), radius: old.radius)
            ctx.insert(g)
            for v in (try? ctx.fetch(FetchDescriptor<GymVisit>())) ?? [] where v.gymUUID == nil { v.gymUUID = g.uuid }
            if UserDefaults.standard.bool(forKey: "gymInside") { insideID = g.uuid }
            try? ctx.save()
        }
        UserDefaults.standard.removeObject(forKey: "gym")
    }

    private func arrived(_ g: Gym) async {
        guard insideID != g.uuid else { return }
        insideID = g.uuid
        ctx.insert(GymVisit(gym: g))
        try? ctx.save()
        guard notifyArrival, !NotificationPrefs.paused(), LiveWorkout.runningSession == nil else { return }
        pendingArrival = .now
        let routine = Self.todayTrainingName()
        notify(id: "gym-arrival", title: "Chegou na \(g.name) 💪",
               body: routine.map { "Começar \($0)? Toque para abrir o treino." } ?? "Bora treinar? Toque para começar.",
               category: "ARRIVAL")
    }

    private func left(_ g: Gym) async {
        // Fecha a visita aberta deste lugar (com mais de um lugar, a última aberta pode ser de outro)
        let gid: UUID? = g.uuid
        if let open = try? ctx.fetch(FetchDescriptor<GymVisit>(predicate: #Predicate { $0.end == nil && $0.gymUUID == gid },
                                                               sortBy: [SortDescriptor(\.start, order: .reverse)])).first {
            open.end = .now
            try? ctx.save()
        }
        // Já tinha entrado em outro lugar: só fecha a visita deste
        guard insideID == g.uuid else { return }
        insideID = nil
        pendingArrival = nil
        // Encerra só o treino daquele lugar (ou sem lugar definido)
        guard autoFinish, let s = LiveWorkout.runningSession, LiveWorkout.concluding != s.uuid, s.gymUUID == nil || s.gymUUID == g.uuid,
              Date.now.timeIntervalSince(s.start) >= Self.minWorkoutMinutes * 60 else { return }
        let summary = await LiveWorkout.autoFinish(s, place: g.name)
        notify(id: "gym-finished", title: "Treino encerrado ao sair da \(g.name)", body: summary, category: nil)
    }

    private func notify(id: String, title: String, body: String, category: String?) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        if let category { c.categoryIdentifier = category }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: c, trigger: nil))
    }

    /// O WOD do coach agendado para hoje vem antes da rotina do dia
    static func todayTrainingName() -> String? {
        WodPlan.pendingToday().map { "\($0.name) (\($0.format.name))" } ?? todayRoutineName()
    }

    static func todayRoutineName() -> String? {
        let day = Calendar.current.component(.weekday, from: .now)
        let routines = (try? AppData.container.mainContext.fetch(FetchDescriptor<Routine>(sortBy: [SortDescriptor(\.order)]))) ?? []
        return routines.first { $0.weekdays.contains(day) }?.name
    }
}

/// Toques nas notificações (ex.: "Começar treino" ao chegar num lugar de treino)
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()
    static let startWorkout = Notification.Name("gymbros.startWorkout")

    func install() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let start = UNNotificationAction(identifier: "START", title: "Começar treino", options: [.foreground])
        center.setNotificationCategories(Set([UNNotificationCategory(identifier: "ARRIVAL", actions: [start], intentIdentifiers: [])]
                                             + SocialNotifier.categories))
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        // Força, convites, mensagens e reações: abre a caixa de entrada ou responde pelo botão
        if await SocialNotifier.handle(response) { return }
        // Troca aceita ou oferta nova: abre a tela de trocas (receber o bro é lá)
        if response.notification.request.content.userInfo["trade"] != nil {
            await MainActor.run { TradeStore.shared.openHub = true }
            return
        }
        if response.notification.request.content.categoryIdentifier == "ARRIVAL" {
            await MainActor.run { NotificationCenter.default.post(name: NotificationRouter.startWorkout, object: nil) }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // Mensagem da conversa que está aberta na tela não aparece por cima dela
        let peer = notification.request.content.userInfo["peer"] as? String
        if let peer, await MainActor.run(body: { InboxStore.shared.openPeer == peer }) { return [] }
        return [.banner, .sound]
    }
}
