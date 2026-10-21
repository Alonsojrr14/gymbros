import SwiftUI
import WatchKit

/// Treino guiado do iPhone no pulso: série atual com o botão "Série feita" embaixo, ou o anel do descanso.
/// Entre o descanso e a próxima série, uma tela de "Bora!" com a série e a carga.
struct TrainingPage: View {
    @Environment(PhoneLink.self) private var link
    @Environment(WorkoutRecorder.self) private var recorder
    @State private var sending = false
    @State private var offline = false
    @State private var splash = false

    var body: some View {
        if let w = link.workout {
            VStack(spacing: 6) {
                if splash, !w.finished, !w.exerciseDone {
                    NextSetSplash(workout: w) { withAnimation { splash = false } }
                        .transition(.scale(scale: 1.15).combined(with: .opacity))
                } else if let end = w.restEnd, end > .now {
                    rest(w, end: end)
                } else {
                    header(w)
                    if w.finished { finished } else { current(w) }
                }
            }
            .navigationTitle(w.title)
            .overlay(alignment: .bottom) {
                if offline {
                    Label("iPhone fora de alcance", systemImage: "iphone.slash")
                        .font(.caption2).padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Theme.danger.opacity(0.9), in: .capsule)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .task(id: w.restEnd) { await alertWhenRestEnds(w.restEnd) }
            // Descanso pulado (aqui ou no iPhone): também passa pela tela de transição
            .onChange(of: w.restEnd) { old, new in
                if let old, old > .now, new == nil { showSplash() }
            }
        }
    }

    private func header(_ w: WatchWorkout) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(w.exerciseDone || w.finished ? "\(w.doneSets)/\(w.totalSets) séries" : "Série \(w.setNumber) de \(w.setCount)")
                Spacer()
                if recorder.guided, let hr = recorder.heartRate {
                    Label("\(Int(hr))", systemImage: "heart.fill").foregroundStyle(Theme.health)
                }
                Text(w.start, style: .timer)
            }
            .font(.caption2.monospacedDigit()).foregroundStyle(Theme.dim)
            ProgressView(value: Double(w.doneSets), total: Double(max(w.totalSets, 1))).tint(Theme.accent)
        }
    }

    private func current(_ w: WatchWorkout) -> some View {
        VStack(spacing: 2) {
            Text(w.exercise)
                .font(.headline).multilineTextAlignment(.center)
                .lineLimit(2).minimumScaleFactor(0.6)
            if !w.exerciseDone {
                Text(w.setText)
                    .font(.system(size: 60, weight: .bold, design: .rounded).monospacedDigit())
                    .lineLimit(1).minimumScaleFactor(0.3)
                    .frame(maxHeight: .infinity)
                Button {
                    Task { await run(.completeSet) }
                } label: {
                    Label("Série feita", systemImage: "checkmark")
                        .font(.headline)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(.black)
                .frame(maxHeight: 52)
                .disabled(sending)
            } else {
                Spacer()
            }
        }
        .frame(maxHeight: .infinity)
    }

    /// Só o anel e o tempo; "Pular" discreto embaixo
    private func rest(_ w: WatchWorkout, end: Date) -> some View {
        VStack(spacing: 6) {
            GeometryReader { g in
                let d = min(g.size.width, g.size.height)
                TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                    let left = min(max(end.timeIntervalSince(ctx.date) / Double(max(w.restTotal, 1)), 0), 1)
                    ZStack {
                        Circle().stroke(Theme.track, lineWidth: 10)
                        Circle().trim(from: 0, to: left)
                            .stroke(Theme.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.5), value: left)
                        Text(timerInterval: ctx.date...max(end, ctx.date), countsDown: true)
                            .font(.system(size: d * 0.32, weight: .bold, design: .rounded).monospacedDigit())
                            .lineLimit(1).minimumScaleFactor(0.5)
                            .frame(width: d * 0.72)
                    }
                    .frame(width: d - 10, height: d - 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Descanso")
            Button {
                Task { await run(.skipRest) }
            } label: {
                Label("Pular", systemImage: "forward.fill")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Theme.card, in: .capsule)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
            .disabled(sending)
        }
    }

    private var finished: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .resizable().scaledToFit()
                .foregroundStyle(Theme.accent)
                .frame(maxHeight: .infinity)
            Text("Treino completo!").font(.headline)
            Text("Conclua no iPhone para ganhar o XP.").font(.caption2).foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center).minimumScaleFactor(0.7)
        }
    }

    private func run(_ command: WatchCommand) async {
        sending = true
        defer { sending = false }
        if await link.send(command) != nil {
            WKInterfaceDevice.current().play(.click)
        } else {
            WKInterfaceDevice.current().play(.failure)
            withAnimation { offline = true }
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation { offline = false }
        }
    }

    /// Fim do descanso: toque no pulso, mesmo com a tela abaixada
    private func alertWhenRestEnds(_ end: Date?) async {
        guard let end, end > .now else { return }
        try? await Task.sleep(for: .seconds(end.timeIntervalSinceNow))
        guard !Task.isCancelled else { return }
        showSplash()
    }

    private func showSplash() {
        WKInterfaceDevice.current().play(.start)
        withAnimation(.spring(duration: 0.35)) { splash = true }
    }
}

/// Transição do descanso para a série: tela verde com a série e a carga; some sozinha ou com um toque
private struct NextSetSplash: View {
    let workout: WatchWorkout
    let done: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            Text("BORA!")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .opacity(0.7)
            Text(workout.setText)
                .font(.system(size: 60, weight: .heavy, design: .rounded).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.3)
                .frame(maxHeight: .infinity)
            Text("Série \(workout.setNumber) de \(workout.setCount)")
                .font(.headline)
            Text(workout.exercise)
                .font(.caption).opacity(0.7)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .foregroundStyle(.black)
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.accent, in: .rect(cornerRadius: 24))
        .contentShape(.rect)
        .onTapGesture(perform: done)
        .task {
            try? await Task.sleep(for: .seconds(2.5))
            done()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
