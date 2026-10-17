import CoreLocation
import SwiftData
import UserNotifications

/// "Minha academia": raio no mapa, aviso ao chegar e fim automático do treino ao sair.
/// Usa o CLMonitor do iOS 17, que acorda o app em segundo plano ao entrar/sair do raio.
@MainActor
final class GymLocation: NSObject, CLLocationManagerDelegate {
    static let shared = GymLocation()

    struct Gym: Codable, Equatable {
        var name: String
        var latitude: Double
        var longitude: Double
        var radius: Double

        var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    }

    let manager = CLLocationManager()
    private var monitorTask: Task<Void, Never>?
    private var oneShot: CheckedContinuation<CLLocation?, Never>?

    /// Treinos com menos tempo que isso não são encerrados ao sair (evita falso alarme do GPS)
    static let minWorkoutMinutes = 10.0

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    // MARK: Configuração

    var gym: Gym? {
        get { UserDefaults.standard.data(forKey: "gym").flatMap { try? JSONDecoder().decode(Gym.self, from: $0) } }
        set {
            UserDefaults.standard.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: "gym")
            startMonitoring()
        }
    }

    var notifyArrival: Bool {
        get { UserDefaults.standard.object(forKey: "gymNotifyArrival") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "gymNotifyArrival") }
    }

    var autoFinish: Bool {
        get { UserDefaults.standard.object(forKey: "gymAutoFinish") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "gymAutoFinish") }
    }

    /// Está dentro do raio agora (último evento recebido)
    var inside: Bool {
        get { UserDefaults.standard.bool(forKey: "gymInside") }
        set { UserDefaults.standard.set(newValue, forKey: "gymInside") }
    }

    /// Chegada recente ainda sem treino começado (o app oferece começar ao abrir)
    var pendingArrival: Date? {
        get { UserDefaults.standard.object(forKey: "gymArrival") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "gymArrival") }
    }

    /// Nome do local para check-ins feitos agora (só quando está na academia)
    var placeNow: String? { inside ? gym?.name : nil }

    var authorization: CLAuthorizationStatus { manager.authorizationStatus }

    func requestAlways() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        manager.requestAlwaysAuthorization()
    }

    /// Localização atual uma vez (para marcar a academia)
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
        monitorTask?.cancel()
        monitorTask = Task { @MainActor in
            let monitor = await CLMonitor("gymbros")
            for id in await monitor.identifiers { await monitor.remove(id) }
            guard let gym = self.gym else { return }
            await monitor.add(CLMonitor.CircularGeographicCondition(center: gym.coordinate, radius: gym.radius),
                              identifier: "gym", assuming: self.inside ? .satisfied : .unsatisfied)
            do {
                for try await event in await monitor.events {
                    switch event.state {
                    case .satisfied: await self.arrived()
                    case .unsatisfied: await self.left()
                    default: break
                    }
                }
            } catch {}
        }
    }

    private func arrived() async {
        guard !inside else { return }
        inside = true
        let ctx = AppData.container.mainContext
        ctx.insert(GymVisit(gymName: gym?.name ?? "Academia"))
        try? ctx.save()
        guard notifyArrival, LiveWorkout.runningSession == nil else { return }
        pendingArrival = .now
        let routine = Self.todayRoutineName()
        notify(id: "gym-arrival", title: "Chegou na \(gym?.name ?? "academia") 💪",
               body: routine.map { "Começar \($0)? Toque para abrir o treino." } ?? "Bora treinar? Toque para começar.",
               category: "ARRIVAL")
    }

    private func left() async {
        guard inside else { return }
        inside = false
        pendingArrival = nil
        let ctx = AppData.container.mainContext
        if let open = try? ctx.fetch(FetchDescriptor<GymVisit>(predicate: #Predicate { $0.end == nil },
                                                               sortBy: [SortDescriptor(\.start, order: .reverse)])).first {
            open.end = .now
            try? ctx.save()
        }
        guard autoFinish, let s = LiveWorkout.runningSession,
              Date.now.timeIntervalSince(s.start) >= Self.minWorkoutMinutes * 60 else { return }
        let summary = await LiveWorkout.autoFinish(s, place: gym?.name)
        notify(id: "gym-finished", title: "Treino encerrado ao sair da academia", body: summary, category: nil)
    }

    private func notify(id: String, title: String, body: String, category: String?) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        if let category { c.categoryIdentifier = category }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: c, trigger: nil))
    }

    static func todayRoutineName() -> String? {
        let day = Calendar.current.component(.weekday, from: .now)
        let routines = (try? AppData.container.mainContext.fetch(FetchDescriptor<Routine>(sortBy: [SortDescriptor(\.order)]))) ?? []
        return routines.first { $0.weekdays.contains(day) }?.name
    }
}

/// Toques nas notificações (ex.: "Começar treino" ao chegar na academia)
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()
    static let startWorkout = Notification.Name("gymbros.startWorkout")

    func install() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let start = UNNotificationAction(identifier: "START", title: "Começar treino", options: [.foreground])
        center.setNotificationCategories([UNNotificationCategory(identifier: "ARRIVAL", actions: [start], intentIdentifiers: [])])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if response.notification.request.content.categoryIdentifier == "ARRIVAL" {
            await MainActor.run { NotificationCenter.default.post(name: NotificationRouter.startWorkout, object: nil) }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

/// Uma ida à academia: da entrada à saída do raio
@Model
final class GymVisit {
    var uuid: UUID = UUID()
    var gymName: String = ""
    var start: Date = Date.now
    var end: Date?

    init(gymName: String) {
        self.gymName = gymName
    }

    var minutes: Int? { end.map { max(Int($0.timeIntervalSince(start) / 60), 0) } }
}
