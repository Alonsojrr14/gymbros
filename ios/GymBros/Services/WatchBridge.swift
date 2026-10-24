import HealthKit
import SwiftData
import SwiftUI
import WatchConnectivity

/// Ponte com o app do relógio: manda o bro principal e o treino guiado em andamento;
/// recebe "série feita"/"pular descanso", o começo de treino pelo relógio e as atividades gravadas lá.
@MainActor
final class WatchBridge: NSObject {
    static let shared = WatchBridge()

    private var bro: WatchBro?
    private var sprite: Data?
    private var spriteKey = ""
    private var workout: WatchWorkout?
    /// Treino começado pelo relógio com o iPhone em segundo plano: abre a tela do treino ao voltar
    private(set) var openWorkoutOnActive = false

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func update(bro: WatchBro, sprite name: String, hue: Double) {
        let key = "\(name)|\(hue)"
        if key != spriteKey {
            sprite = Self.render(name, hue: hue)
            spriteKey = key
        }
        guard bro != self.bro else { return }
        self.bro = bro
        push()
    }

    func update(workout: WatchWorkout?) {
        guard workout != self.workout else { return }
        self.workout = workout
        push()
    }

    static func workout(_ title: String, start: Date, state: WorkoutAttributes.ContentState, restTotal: Int) -> WatchWorkout {
        WatchWorkout(title: title, start: start, exercise: state.exercise, setNumber: state.setNumber, setCount: state.setCount,
                     setText: state.setText, doneSets: state.doneSets, totalSets: state.totalSets, restEnd: state.restEnd,
                     restTotal: restTotal)
    }

    /// Treino guiado começou no iPhone: abre o app no relógio, que grava batimentos e calorias junto
    func startOnWatch() {
        guard WCSession.isSupported(), WCSession.default.isPaired, WCSession.default.isWatchAppInstalled else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor
        HealthSync.store.startWatchApp(with: config) { _, _ in }
    }

    func consumeOpenRequest() -> Bool {
        defer { openWorkoutOnActive = false }
        return openWorkoutOnActive
    }

    /// Musculação escolhida no relógio: começa a rotina do dia (ou um treino livre) e abre a tela do treino
    private func startFromWatch() async -> String {
        guard AuthStore.shared.isSignedIn else { return "Entre na sua conta no iPhone." }
        let ctx = AppData.container.mainContext
        let session = LiveWorkout.runningSession ?? {
            let today = Calendar.current.component(.weekday, from: .now)
            let routines = (try? ctx.fetch(FetchDescriptor<Routine>(sortBy: [SortDescriptor(\.order)]))) ?? []
            return LiveWorkout.startSession(routine: routines.first { $0.weekdays.contains(today) }, fromWatch: true)
        }()
        await LiveWorkout.refresh(session)
        if UIApplication.shared.applicationState == .active {
            // A aba Treino pode ainda não existir no primeiro aviso; o segundo abre o treino
            NotificationCenter.default.post(name: NotificationRouter.startWorkout, object: nil)
            try? await Task.sleep(for: .milliseconds(400))
            NotificationCenter.default.post(name: NotificationRouter.startWorkout, object: nil)
        } else {
            openWorkoutOnActive = true
        }
        return session.title
    }

    // MARK: Treino guiado gravado também no relógio

    private static let watchStartsKey = "watchGuidedStarts"

    /// Inícios de treinos guiados que o relógio está gravando: o treino do Saúde vem de lá (não exporta outro).
    /// Com folga de segundos: a cópia da conta guarda a data sem as frações, e a atividade volta dela depois de sincronizar
    nonisolated static func isRecordedOnWatch(_ date: Date) -> Bool {
        let t = date.timeIntervalSince1970
        return (UserDefaults.standard.array(forKey: watchStartsKey) as? [Double] ?? []).contains { abs($0 - t) < 2 }
    }

    private func markRecordedOnWatch(_ start: Date) {
        let weekAgo = Date.now.addingTimeInterval(-7 * 86400).timeIntervalSince1970
        let list = (UserDefaults.standard.array(forKey: Self.watchStartsKey) as? [Double] ?? []).filter { $0 > weekAgo }
        UserDefaults.standard.set(Array(Set(list + [start.timeIntervalSince1970])), forKey: Self.watchStartsKey)
    }

    private func link(_ saved: WatchGuidedSaved) {
        let ctx = AppData.container.mainContext
        let from = saved.start.addingTimeInterval(-2), to = saved.start.addingTimeInterval(2)
        if let a = try? ctx.fetch(FetchDescriptor<Activity>(predicate: #Predicate { $0.date > from && $0.date < to && $0.healthUUID == nil })).first {
            // O iPhone já tinha gravado o treino no Saúde: fica só o do relógio, com batimentos
            if let old = a.healthWrittenUUID, old != saved.healthUUID { HealthSync.deleteWritten(old) }
            a.healthWrittenUUID = saved.healthUUID
            if let kcal = saved.kcal, kcal > 0 { a.kcal = kcal }
            try? ctx.save()
        } else {
            // Treino descartado no iPhone: o do Saúde não volta como importado
            HealthSync.ignored.insert(saved.healthUUID)
        }
    }

    private func push() {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        guard s.activationState == .activated, s.isPaired, s.isWatchAppInstalled else { return }
        let enc = JSONEncoder()
        var ctx: [String: Any] = [:]
        if let bro, let d = try? enc.encode(bro) { ctx[WatchKey.bro] = d }
        if let sprite { ctx[WatchKey.sprite] = sprite }
        if let workout, let d = try? enc.encode(workout) { ctx[WatchKey.workout] = d }
        try? s.updateApplicationContext(ctx)
        // Relógio acordado: chega na hora (o contexto pode esperar o sistema)
        if s.isReachable { s.sendMessage(ctx, replyHandler: nil) }
    }

    /// Arte do bro já com a cor do galho, pequena o bastante para o contexto do WatchConnectivity
    private static func render(_ name: String, hue: Double) -> Data? {
        let view = Image(name).resizable().interpolation(.none).hueRotation(.degrees(hue)).frame(width: 160, height: 160)
        let r = ImageRenderer(content: view)
        r.scale = 1
        return r.uiImage?.pngData()
    }

    private func save(_ w: WatchActivity) {
        guard AuthStore.shared.isSignedIn else { return }
        let ctx = AppData.container.mainContext
        let all = (try? ctx.fetch(FetchDescriptor<Activity>())) ?? []
        // O HealthSync pode ter importado o mesmo treino antes: fica a importada, com o esforço escolhido no relógio
        if let existing = all.first(where: { ($0.healthUUID != nil && $0.healthUUID == w.healthUUID) || $0.date == w.start }) {
            existing.effort = w.effort
            existing.source = "Apple Watch"
            _ = ActivitySplits.stamp(existing, context: ctx)
        } else {
            let kind = WorkoutType.byID(w.healthType)?.kind ?? .outro
            let a = Activity(kind: kind, date: w.start, minutes: w.minutes, effort: w.effort, note: w.kcal.map { "\(Int($0)) kcal" } ?? "")
            a.healthUUID = w.healthUUID
            a.healthType = w.healthType
            a.kcal = w.kcal
            a.meters = w.meters
            a.source = "Apple Watch"
            ctx.insert(a)
            _ = ActivitySplits.stamp(a, context: ctx)
        }
        try? ctx.save()
    }
}

extension WatchBridge: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.push() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// Troca de relógio: ativa de novo para o novo par
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.push() }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let command = (message[WatchKey.command] as? String).flatMap(WatchCommand.init)
        Task { @MainActor in
            let text = switch command {
            case .completeSet: await LiveWorkout.completeNextSet()
            case .skipRest: await LiveWorkout.skipRest()
            case .startGuided: await self.startFromWatch()
            case nil: ""
            }
            replyHandler([WatchKey.reply: text])
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let dec = JSONDecoder()
        if let data = userInfo[WatchKey.activity] as? Data, let activity = try? dec.decode(WatchActivity.self, from: data) {
            Task { @MainActor in self.save(activity) }
        }
        if let start = userInfo[WatchKey.guidedStarted] as? Date {
            Task { @MainActor in self.markRecordedOnWatch(start) }
        }
        if let data = userInfo[WatchKey.guidedSaved] as? Data, let saved = try? dec.decode(WatchGuidedSaved.self, from: data) {
            Task { @MainActor in self.link(saved) }
        }
    }
}
