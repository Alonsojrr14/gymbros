import SwiftUI

/// Pixel art do monstro, sem suavização. `hidden` mostra só a silhueta (BroBook).
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
                .keyframeAnimator(initialValue: Motion(), repeating: true) { view, m in
                    view
                        .scaleEffect(x: m.scaleX, y: m.scaleY, anchor: .bottom)
                        .rotationEffect(.degrees(m.rotation), anchor: .bottom)
                        .offset(y: m.offsetY)
                } keyframes: { _ in
                    let m = MotionScript.of(form.species)
                    KeyframeTrack(\.scaleX) { for (v, d) in m.scaleX { CubicKeyframe(v, duration: d) } }
                    KeyframeTrack(\.scaleY) { for (v, d) in m.scaleY { CubicKeyframe(v, duration: d) } }
                    KeyframeTrack(\.offsetY) { for (v, d) in m.offsetY { CubicKeyframe(v, duration: d) } }
                    KeyframeTrack(\.rotation) { for (v, d) in m.rotation { CubicKeyframe(v, duration: d) } }
                }
        }
    }
}

/// Pose do monstro num instante da animação ociosa
struct Motion {
    var scaleX = 1.0
    var scaleY = 1.0
    var offsetY = 0.0
    var rotation = 0.0
}

/// Roteiro da animação ociosa: passos (valor, duração) para cada eixo. Cada espécie tem o seu.
struct MotionScript {
    typealias Steps = [(Double, Double)]
    var scaleX: Steps = [(1, 1)]
    var scaleY: Steps = [(1, 1)]
    var offsetY: Steps = [(0, 1)]
    var rotation: Steps = [(0, 1)]

    static func of(_ species: String) -> MotionScript {
        switch species {
        case "urso":
            // Respiração lenta e pesada, balançando o corpo
            MotionScript(scaleX: [(1.04, 1.4), (1, 1.4)], rotation: [(-2, 1.4), (2, 1.4)])
        case "rato":
            // Agitado: pulinhos curtos e rápidos, depois uma pausa
            MotionScript(offsetY: [(-5, 0.12), (0, 0.12), (-4, 0.12), (0, 0.12), (0, 1.4)])
        case "lobo":
            // Estufa o peito, orgulhoso
            MotionScript(scaleY: [(1.05, 1.2), (1, 1.0)], rotation: [(-1.5, 1.2), (0, 1.0)])
        case "cachorro":
            // Balança de um lado para o outro, como abanando o rabo
            MotionScript(rotation: [(4, 0.18), (-4, 0.18), (4, 0.18), (0, 0.18), (0, 1.0)])
        case "esquilo":
            // Saltinho com inclinação
            MotionScript(offsetY: [(-10, 0.25), (0, 0.25), (0, 1.3)], rotation: [(-5, 0.25), (0, 0.25), (0, 1.3)])
        case "gato":
            // Espreguiçada lenta
            MotionScript(scaleX: [(1, 1.2), (0.96, 0.8), (1.03, 0.5), (1, 0.5)],
                         scaleY: [(1, 1.2), (1.07, 0.8), (0.97, 0.5), (1, 0.5)])
        case "coruja":
            // Flutua, como se planasse
            MotionScript(offsetY: [(-8, 1.3), (0, 1.3)], rotation: [(2, 1.3), (-2, 1.3)])
        default:
            // Coelho: respira e dá um pulinho de leve
            MotionScript(scaleY: [(1.03, 1.0), (0.98, 1.0)], offsetY: [(-3, 1.0), (0, 1.0)])
        }
    }
}
