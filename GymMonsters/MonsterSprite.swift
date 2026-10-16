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

/// Monstro "vivo": respira de leve; o ovo dá tremidinhas.
/// phaseAnimator anima só os efeitos abaixo, sem arrastar tamanho e posição da view junto.
struct LivingMonster: View {
    let form: MonsterForm
    var progress: Double = 0

    var body: some View {
        if form.stage == .egg {
            // Parado, e de tempos em tempos uma tremidinha, como se algo se mexesse dentro.
            // Quanto mais perto de chocar, mais frequente e mais forte.
            let pause = max(3.2 - 2.2 * progress, 1.0)
            let amp = 5 + 7 * progress
            MonsterSprite(form: form)
                .keyframeAnimator(initialValue: 0.0, repeating: true) { view, angle in
                    view.rotationEffect(.degrees(angle), anchor: .bottom)
                } keyframes: { _ in
                    LinearKeyframe(0, duration: pause)
                    CubicKeyframe(amp, duration: 0.07)
                    CubicKeyframe(-amp * 0.9, duration: 0.1)
                    CubicKeyframe(amp * 0.6, duration: 0.1)
                    CubicKeyframe(-amp * 0.35, duration: 0.09)
                    CubicKeyframe(0, duration: 0.09)
                }
        } else {
            MonsterSprite(form: form)
                .phaseAnimator([false, true]) { view, up in
                    view
                        .scaleEffect(x: 1, y: up ? 1.03 : 0.98, anchor: .bottom)
                        .offset(y: up ? -3 : 0)
                } animation: { _ in .easeInOut(duration: 1.2) }
        }
    }
}
