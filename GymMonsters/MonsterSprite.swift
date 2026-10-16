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

/// Monstro "vivo": respira de leve. O ovo fica parado.
/// phaseAnimator anima só os efeitos abaixo, sem arrastar tamanho e posição da view junto.
struct LivingMonster: View {
    let form: MonsterForm
    var progress: Double = 0

    var body: some View {
        if form.stage == .egg {
            MonsterSprite(form: form)
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
