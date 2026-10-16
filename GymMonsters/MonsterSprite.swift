import SwiftUI

/// Pixel art do monstro, sem suavização. `hidden` mostra só a silhueta (Dex).
struct MonsterSprite: View {
    let form: MonsterForm
    var hidden = false

    var body: some View {
        Image(form.sprite)
            .resizable()
            .interpolation(.none)
            .scaledToFit()
            .hueRotation(.degrees(form.hue))
            .colorMultiply(hidden ? .black : .white)
            .opacity(hidden ? 0.6 : 1)
    }
}

/// Monstro "vivo": respira; o ovo balança mais forte conforme se aproxima de chocar
struct LivingMonster: View {
    let form: MonsterForm
    var progress: Double = 0
    @State private var phase = false

    var body: some View {
        MonsterSprite(form: form)
            .scaleEffect(x: 1, y: form.stage == .egg ? 1 : (phase ? 1.03 : 0.97), anchor: .bottom)
            .rotationEffect(.degrees(form.stage == .egg ? (phase ? 1 : -1) * (2 + 10 * progress) : 0), anchor: .bottom)
            .offset(y: form.stage == .egg ? 0 : (phase ? -4 : 0))
            .animation(
                form.stage == .egg
                    ? .easeInOut(duration: max(0.9 - 0.6 * progress, 0.25)).repeatForever(autoreverses: true)
                    : .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                value: phase
            )
            .onAppear { phase = true }
    }
}
