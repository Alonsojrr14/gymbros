import HealthKit
import Observation
import WatchKit

/// Sessão de treino do HealthKit no relógio, com batimentos, calorias e distância. Dois modos:
/// - livre: atividade escolhida no relógio, espelhada no iPhone; ao salvar vai para o Saúde e para o iPhone (XP);
/// - guiado: acompanha o treino guiado do iPhone; termina quando ele termina lá e só manda o treino do Saúde.
@MainActor @Observable
final class WorkoutRecorder: NSObject {
    static let shared = WorkoutRecorder()

    enum Phase { case idle, starting, running, paused, rating }

    private(set) var phase = Phase.idle
    private(set) var kind: WorkoutType?
    private(set) var guided = false
    private(set) var heartRate: Double?
    private(set) var kcal: Double = 0
    private(set) var meters: Double = 0
    var error: String?

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    /// Treino do iPhone que esta sessão acompanha (modo guiado)
    private var guidedStart: Date?
    private var guidedDoneSets = 0
    private var lastSent = Date.distantPast
    /// Treino do iPhone que já fez o relógio começar a gravar sozinho (não começa de novo depois de encerrar)
    private var autoStarted: Date?
    /// Encerrando por aqui: o aviso de sessão encerrada não pede o esforço de novo
    private var stopping = false

    var isActive: Bool { phase != .idle }
    /// Atividade livre: a tela de gravação toma o app; no guiado continua a tela do treino
    var isFree: Bool { isActive && !guided }

    private static let recentKey = "recentWorkoutTypes"

    /// Tipos usados por último (mais recente primeiro), como no app Exercício
    var recent: [WorkoutType] {
        (UserDefaults.standard.array(forKey: Self.recentKey) as? [Int] ?? []).compactMap { WorkoutType.byID($0) }
    }

    private func remember(_ type: WorkoutType) {
        let ids = [type.id] + recent.map(\.id).filter { $0 != type.id }
        UserDefaults.standard.set(ids.prefix(5).map { Int($0) }, forKey: Self.recentKey)
    }

    /// Tempo em movimento (sem as pausas)
    func elapsed(at date: Date) -> TimeInterval { builder?.elapsedTime(at: date) ?? 0 }

    /// Musculação escolhida aqui: começa o treino guiado no iPhone; sem iPhone por perto, grava como atividade livre
    func choose(_ type: WorkoutType) async {
        guard phase == .idle else { return }
        if type.type == .traditionalStrengthTraining, await PhoneLink.shared.send(.startGuided) != nil {
            remember(type)
            await startGuided()
        } else {
            await start(type)
        }
    }

    /// Treino guiado começou no iPhone (ou pelo relógio): grava junto até ele terminar lá
    func startGuided() async {
        guard phase == .idle, let type = WorkoutType.byID(HKWorkoutActivityType.traditionalStrengthTraining.rawValue) else { return }
        guided = true
        await begin(type, mirror: false)
        if phase == .running, let w = PhoneLink.shared.workout { phoneWorkoutChanged(w) }
    }

    func start(_ type: WorkoutType) async {
        guard phase == .idle else { return }
        guided = false
        await begin(type, mirror: true)
        if phase == .running { remember(type) }
    }

    private func begin(_ type: WorkoutType, mirror: Bool) async {
        phase = .starting
        error = nil
        let samples: Set<HKSampleType> = WorkoutType.distanceTypes
            .union([HKQuantityType(.activeEnergyBurned), HKQuantityType(.heartRate)])
        do {
            try await store.requestAuthorization(toShare: samples.union([HKObjectType.workoutType()]),
                                                 read: Set(samples).union([HKObjectType.workoutType()]))
            let config = HKWorkoutConfiguration()
            config.activityType = type.type
            config.locationType = type.outdoor ? .outdoor : .indoor
            if type.type == .swimming {
                config.swimmingLocationType = .pool
                config.lapLength = HKQuantity(unit: .meter(), doubleValue: 25)
            }
            let session = try HKWorkoutSession(healthStore: store, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            self.kind = type
            let now = Date.now
            session.startActivity(with: now)
            try await builder.beginCollection(at: now)
            phase = .running
            WKInterfaceDevice.current().play(.start)
            // O iPhone abre a tela ao vivo desta atividade
            if mirror { try? await session.startMirroringToCompanionDevice() }
        } catch {
            reset()
            self.error = "Não deu para começar: libere o GymBros em Saúde no relógio."
        }
    }

    /// O treino guiado do iPhone mudou: começa a gravar junto se ainda não grava; liga a sessão a ele;
    /// quando ele some (concluído ou descartado), encerra aqui
    func phoneWorkoutChanged(_ w: WatchWorkout?) {
        if phase == .idle, let w, w.start != autoStarted {
            autoStarted = w.start
            Task { await startGuided() }
            return
        }
        guard guided, phase == .running || phase == .paused else { return }
        if let w {
            if guidedStart != w.start {
                guidedStart = w.start
                PhoneLink.shared.sendInfo([WatchKey.guidedStarted: w.start])
            }
            guidedDoneSets = w.doneSets
        } else if guidedStart != nil {
            Task { await endGuided() }
        }
    }

    private func endGuided() async {
        guard let session, let builder, !stopping else { return }
        stopping = true
        let start = guidedStart
        // Aviso atrasado do mesmo treino não recomeça a gravação
        autoStarted = start
        session.end()
        try? await builder.endCollection(at: .now)
        // Sem nenhuma série feita, o iPhone não salva atividade: o treino do Saúde também não fica
        if guidedDoneSets > 0, let start, let workout = try? await builder.finishWorkout() {
            let saved = WatchGuidedSaved(start: start, healthUUID: workout.uuid.uuidString, kcal: kcal > 0 ? kcal : nil)
            if let data = try? JSONEncoder().encode(saved) { PhoneLink.shared.sendInfo([WatchKey.guidedSaved: data]) }
        } else {
            builder.discardWorkout()
        }
        reset()
    }

    #if DEBUG
    /// `-demoRecording running|rating`: atividade de exemplo para ver as telas
    func applyLaunchArguments() {
        guard let mode = UserDefaults.standard.string(forKey: "demoRecording") else { return }
        kind = WorkoutType.byID(HKWorkoutActivityType.running.rawValue)
        heartRate = 148
        kcal = 312
        meters = 5420
        phase = mode == "rating" ? .rating : .running
    }
    #endif

    func togglePause() {
        guard let session else { return }
        if phase == .running { session.pause() } else if phase == .paused { session.resume() }
    }

    /// Para a sessão e pede o esforço antes de salvar
    func stop() async {
        guard let session, let builder, phase == .running || phase == .paused, !stopping else { return }
        stopping = true
        session.end()
        await finishCollection(builder)
    }

    private func finishCollection(_ builder: HKLiveWorkoutBuilder) async {
        try? await builder.endCollection(at: .now)
        phase = .rating
        WKInterfaceDevice.current().play(.stop)
    }

    func save(effort: Int) async -> WatchActivity? {
        guard let builder, let kind else { return nil }
        let workout = try? await builder.finishWorkout()
        let start = builder.startDate ?? workout?.startDate ?? .now
        let duration = workout?.duration ?? builder.elapsedTime
        let activity = WatchActivity(start: start, minutes: max(Int((duration / 60).rounded()), 1),
                                     effort: effort, kcal: kcal > 0 ? kcal : nil, meters: meters > 0 ? meters : nil,
                                     healthUUID: workout?.uuid.uuidString, healthType: Int(kind.id))
        PhoneLink.shared.send(activity)
        WKInterfaceDevice.current().play(.success)
        reset()
        return activity
    }

    func discard() {
        if phase == .running || phase == .paused { session?.end() }
        builder?.discardWorkout()
        reset()
    }

    private func reset() {
        session = nil
        builder = nil
        kind = nil
        guided = false
        guidedStart = nil
        guidedDoneSets = 0
        stopping = false
        heartRate = nil
        kcal = 0
        meters = 0
        phase = .idle
    }

    private func collect(_ b: HKLiveWorkoutBuilder) {
        if let hr = b.statistics(for: HKQuantityType(.heartRate))?.mostRecentQuantity() {
            heartRate = hr.doubleValue(for: .count().unitDivided(by: .minute()))
        }
        kcal = b.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
        if let type = kind?.distanceType {
            meters = b.statistics(for: type)?.sumQuantity()?.doubleValue(for: .meter()) ?? 0
        }
        if Date.now.timeIntervalSince(lastSent) >= 2 { sendMetrics() }
    }

    /// Métricas para a tela ao vivo do iPhone (só na atividade livre, que é espelhada)
    private func sendMetrics() {
        guard !guided, let session, let builder, let kind, phase == .running || phase == .paused else { return }
        lastSent = .now
        let m = WatchLiveMetrics(typeID: Int(kind.id), start: builder.startDate ?? .now, elapsed: builder.elapsedTime(at: .now), at: .now,
                                 paused: phase == .paused, heartRate: heartRate, kcal: kcal, meters: kind.distanceType == nil ? nil : meters)
        guard let data = try? JSONEncoder().encode(m) else { return }
        Task { try? await session.sendToRemoteWorkoutSession(data: data) }
    }

    private func sessionChanged(to state: HKWorkoutSessionState) {
        switch state {
        case .running where phase == .paused: phase = .running
        case .paused where phase == .running: phase = .paused
        // Encerrada pelo iPhone (tela espelhada): pede o esforço aqui
        case .ended where !guided && !stopping && (phase == .running || phase == .paused):
            stopping = true
            if let builder { Task { await finishCollection(builder) } }
        default: break
        }
        sendMetrics()
    }
}

extension WorkoutRecorder: HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in self.sessionChanged(to: toState) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in self.error = error.localizedDescription }
    }

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Task { @MainActor in self.collect(workoutBuilder) }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
