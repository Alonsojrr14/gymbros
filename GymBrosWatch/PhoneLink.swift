import Observation
import UIKit
import WatchConnectivity
import WidgetKit

/// Lado do relógio da conversa com o iPhone: recebe o bro e o treino guiado, manda comandos e atividades
@MainActor @Observable
final class PhoneLink: NSObject {
    static let shared = PhoneLink()

    private(set) var bro: WatchBro?
    private(set) var sprite: UIImage?
    private(set) var workout: WatchWorkout?

    override init() {
        super.init()
        if let saved = WatchBro.load() {
            bro = saved.bro
            sprite = saved.sprite.flatMap(UIImage.init(data:))
        }
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Devolve a confirmação do iPhone, ou nil se ele não respondeu
    func send(_ command: WatchCommand) async -> String? {
        let s = WCSession.default
        guard s.activationState == .activated, s.isReachable else { return nil }
        return await withCheckedContinuation { c in
            s.sendMessage([WatchKey.command: command.rawValue],
                          replyHandler: { c.resume(returning: $0[WatchKey.reply] as? String) },
                          errorHandler: { _ in c.resume(returning: nil) })
        }
    }

    /// Entrega garantida: fica na fila até o iPhone receber
    func send(_ activity: WatchActivity) {
        guard let data = try? JSONEncoder().encode(activity) else { return }
        sendInfo([WatchKey.activity: data])
    }

    func sendInfo(_ info: [String: Any]) {
        guard WCSession.default.activationState == .activated else { return }
        WCSession.default.transferUserInfo(info)
    }

    #if DEBUG
    /// `-demoWorkout set|rest|done|splash`: treino de exemplo para ver as telas sem o iPhone
    func applyLaunchArguments() {
        guard let mode = UserDefaults.standard.string(forKey: "demoWorkout") else { return }
        workout = WatchWorkout(title: "Treino A", start: .now.addingTimeInterval(-1500), exercise: "Supino reto com barra",
                               setNumber: 2, setCount: 4, setText: "60 kg × 10", doneSets: mode == "done" ? 12 : 5, totalSets: 12,
                               restEnd: mode == "rest" ? .now.addingTimeInterval(75) : mode == "splash" ? .now.addingTimeInterval(2) : nil, restTotal: 90)
        bro = WatchBro(name: "Rex", formName: "Lobinho", stageName: "Novato", moodEmoji: "🤩", isEgg: false, level: 7, totalXP: 540,
               progress: 0.27, xpToNext: 660, streak: 4, lastActivity: .now, todayXP: 85,
                       attributes: ["forca": 320, "resistencia": 140, "agilidade": 60, "tecnica": 90], updated: .now)
    }
    #endif

    private func apply(_ ctx: [String: Any]) {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "demoWorkout") != nil { return }
        #endif
        let dec = JSONDecoder()
        workout = (ctx[WatchKey.workout] as? Data).flatMap { try? dec.decode(WatchWorkout.self, from: $0) }
        WorkoutRecorder.shared.phoneWorkoutChanged(workout)
        guard let newBro = (ctx[WatchKey.bro] as? Data).flatMap({ try? dec.decode(WatchBro.self, from: $0) }) else { return }
        let spriteData = ctx[WatchKey.sprite] as? Data
        bro = newBro
        sprite = spriteData.flatMap(UIImage.init(data:))
        newBro.save(sprite: spriteData)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

extension PhoneLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let ctx = session.receivedApplicationContext
        Task { @MainActor in self.apply(ctx) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.apply(applicationContext) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.apply(message) }
    }
}
