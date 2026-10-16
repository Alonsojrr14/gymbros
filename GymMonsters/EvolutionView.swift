import SwiftUI

/// Cena de evolução no estilo clássico: o monstro pisca alternando com a silhueta
/// da nova forma, cada vez mais rápido, até a revelação.
struct EvolutionView: View {
    let from: MonsterForm
    let to: MonsterForm
    let done: () -> Void

    @State private var showingNew = false
    @State private var flash = false
    @State private var revealed = false

    private var hatching: Bool { from.stage == .egg }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RadialGradient(colors: [(to.attribute?.color ?? Theme.accent).opacity(revealed ? 0.45 : 0.1), .clear],
                           center: .center, startRadius: 10, endRadius: 320)
                .ignoresSafeArea()

            VStack(spacing: 30) {
                Text(revealed ? (hatching ? "O ovo chocou!" : "Evoluiu!") : (hatching ? "O ovo está chocando…" : "\(from.name) está evoluindo…"))
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .contentTransition(.opacity)

                ZStack {
                    MonsterSprite(form: showingNew ? to : from)
                        .brightness(revealed ? 0 : (flash ? 1 : 0.3))
                        .scaleEffect(revealed ? 1.15 : 1)
                }
                .frame(width: 240, height: 240)

                if revealed {
                    VStack(spacing: 6) {
                        Text(to.name).font(.system(size: 34, weight: .heavy, design: .rounded))
                        HStack {
                            Text(to.stage.name)
                            if let a = to.attribute {
                                Text("·")
                                Label(a.name, systemImage: a.symbol).foregroundStyle(a.color)
                            }
                        }
                        .foregroundStyle(Theme.dim)
                    }
                    .transition(.scale.combined(with: .opacity))

                    Button("Continuar", action: done)
                        .font(.headline)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 14)
                        .background(Theme.accent, in: .capsule)
                        .foregroundStyle(.black)
                        .transition(.opacity)
                }
            }
        }
        .task { await run() }
    }

    private func run() async {
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        // Intervalos cada vez menores
        var delay = 0.5
        for _ in 0..<14 {
            try? await Task.sleep(for: .seconds(delay))
            showingNew.toggle()
            flash.toggle()
            haptic.impactOccurred(intensity: 0.5)
            delay = max(delay * 0.82, 0.07)
        }
        showingNew = true
        try? await Task.sleep(for: .seconds(0.2))
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.spring(duration: 0.7, bounce: 0.4)) { revealed = true }
    }
}
