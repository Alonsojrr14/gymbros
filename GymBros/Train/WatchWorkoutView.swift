import HealthKit
import Observation
import SwiftUI

/// Atividade começada no relógio, espelhada no iPhone (HKWorkoutSession mirroring): tempo, batimentos e calorias
/// ao vivo, com pausar e encerrar daqui. O esforço e o salvar continuam no relógio.
@MainActor @Observable
final class MirroredWorkout: NSObject {
    static let shared = MirroredWorkout()

    private(set) var session: HKWorkoutSession?
    private(set) var metrics: WatchLiveMetrics?
    private(set) var ended = false
    var minimized = false

    var active: Bool { session != nil }
    var paused: Bool { metrics?.paused ?? false }

    var type: WorkoutType {
        let id = metrics.map { UInt($0.typeID) } ?? session?.workoutConfiguration.activityType.rawValue
        return WorkoutType.byID(id) ?? .other
    }

    /// Precisa estar instalado antes do relógio começar (o iOS abre o app em segundo plano para entregar a sessão)
    func install() {
        HealthSync.store.workoutSessionMirroringStartHandler = { session in
            Task { @MainActor in MirroredWorkout.shared.attach(session) }
        }
    }

    private func attach(_ s: HKWorkoutSession) {
        session = s
        s.delegate = self
        metrics = nil
        ended = false
        minimized = false
    }

    func togglePause() {
        guard let session, !ended else { return }
        if paused { session.resume() } else { session.pause() }
    }

    func end() { session?.end() }

    private func detach() {
        session = nil
        metrics = nil
        ended = false
    }
}

extension MirroredWorkout: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            switch toState {
            case .ended, .stopped: self.ended = true
            case .paused: self.metrics?.paused = true
            case .running: self.metrics?.paused = false
            default: break
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        guard let last = data.last, let m = try? JSONDecoder().decode(WatchLiveMetrics.self, from: last) else { return }
        Task { @MainActor in self.metrics = m }
    }

    /// O relógio salvou ou descartou: a tela fecha
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: Error?) {
        Task { @MainActor in self.detach() }
    }
}

struct WatchWorkoutView: View {
    @State private var live = MirroredWorkout.shared
    @State private var confirmEnd = false

    var body: some View {
        let type = live.type
        VStack(spacing: 18) {
            HStack {
                GMIconButton(icon: "chevron.down", label: "Minimizar") { live.minimized = true }
                Spacer()
                Label("No Apple Watch", systemImage: "applewatch")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.dim)
            }
            Spacer()
            Image(systemName: type.symbol)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 88, height: 88)
                .background(Theme.accent.opacity(0.15), in: .circle)
            Text(type.name).font(.title2.bold())
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let seconds = live.metrics?.elapsed(now: ctx.date) ?? live.session.map { ctx.date.timeIntervalSince($0.startDate ?? ctx.date) } ?? 0
                Text(Duration.seconds(seconds).formatted(.time(pattern: .hourMinuteSecond)))
                    .font(.system(size: 64, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(live.paused ? Theme.warning : Theme.accent)
                    .contentTransition(.numericText())
            }
            HStack(spacing: 10) {
                tile("heart.fill", live.metrics?.heartRate.map { "\(Int($0))" } ?? "--", "bpm", Theme.health)
                tile("flame.fill", "\(Int(live.metrics?.kcal ?? 0))", "kcal", Theme.streak)
                if let m = live.metrics?.meters {
                    tile("point.topleft.down.to.point.bottomright.curvepath", String(format: "%.2f", m / 1000), "km", Theme.info)
                }
            }
            Spacer()
            if live.ended {
                Label("Escolha o esforço no relógio para salvar", systemImage: "applewatch.radiowaves.left.and.right")
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.dim)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 8)
            } else {
                HStack(spacing: 10) {
                    GMButton(live.paused ? "Retomar" : "Pausar", icon: live.paused ? "play.fill" : "pause.fill", kind: .secondary) {
                        live.togglePause()
                    }
                    GMButton("Encerrar", icon: "stop.fill", kind: .danger) { confirmEnd = true }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Theme.bg.ignoresSafeArea())
        .gmActions(isPresented: $confirmEnd, title: "Encerrar \(type.name)?",
                   message: "Depois você escolhe o esforço no relógio e o XP vai para o seu bro.",
                   actions: [GMAction("Encerrar", icon: "stop.fill") { live.end() }])
    }

    private func tile(_ symbol: String, _ value: String, _ unit: String, _ tint: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(value).font(.title2.bold().monospacedDigit())
            Text(unit).font(.caption).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Theme.card, in: .rect(cornerRadius: Theme.radiusM))
        .accessibilityElement(children: .combine)
    }
}

/// Atividade do relógio minimizada: pílula acima da barra de abas para voltar à tela
struct WatchWorkoutPill: View {
    @State private var live = MirroredWorkout.shared

    var body: some View {
        if live.active && live.minimized {
            Button { live.minimized = false } label: {
                HStack(spacing: 8) {
                    Image(systemName: live.type.symbol)
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(Duration.seconds(live.metrics?.elapsed(now: ctx.date) ?? 0).formatted(.time(pattern: .hourMinuteSecond)))
                            .monospacedDigit()
                    }
                    Image(systemName: "applewatch").foregroundStyle(Theme.dim)
                }
                .font(.subheadline.bold())
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.ultraThinMaterial, in: .capsule)
            }
            .buttonStyle(GMPress())
            .accessibilityLabel("\(live.type.name) no relógio, abrir")
        }
    }
}
