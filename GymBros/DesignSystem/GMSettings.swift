import SwiftUI

// Peças das telas de ajustes: quadradinho de ícone colorido, linha de navegação com valor à direita,
// interruptor com ícone e o contador vermelho/verde de não lidos.

/// Quadrado colorido com ícone preto (identidade de cada grupo de ajustes)
struct GMIconTile: View {
    let icon: String
    var tint: Color = Theme.accent
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.45, weight: .bold))
            .foregroundStyle(.black)
            .frame(width: size, height: size)
            .background(tint.gradient, in: .rect(cornerRadius: Theme.radiusS))
            .accessibilityHidden(true)
    }
}

/// Linha que leva a outra tela: ícone colorido, título, valor atual e seta. Use como label de NavigationLink.
struct GMNavRow: View {
    let icon: String
    var tint: Color = Theme.accent
    let title: String
    var value: String?
    var valueTint: Color = Theme.dim
    var badge = 0

    var body: some View {
        HStack(spacing: 12) {
            GMIconTile(icon: icon, tint: tint)
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            Spacer(minLength: 8)
            if badge > 0 { GMCountBadge(count: badge) }
            if let value {
                Text(value).font(.subheadline).foregroundStyle(valueTint).lineLimit(1)
            }
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.dim)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Interruptor com ícone colorido à esquerda
struct GMIconToggle: View {
    let icon: String
    var tint: Color = Theme.accent
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            GMIconTile(icon: icon, tint: tint)
            GMToggle(title: title, subtitle: subtitle, isOn: $isOn)
        }
    }
}

/// Contador de não lidos (bolinha com número)
struct GMCountBadge: View {
    let count: Int
    var tint: Color = Theme.badge

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .gmFont(11, weight: .heavy, mono: true, relativeTo: .caption2)
            .padding(.horizontal, 6)
            .frame(minWidth: 20, minHeight: 20)
            .background(tint, in: .capsule)
            .foregroundStyle(tint == Theme.accent ? .black : .white)
            .accessibilityLabel("\(count) não lidas")
    }
}

extension View {
    /// Contador no canto de um botão redondo (ex.: sino da caixa de entrada)
    func gmCountBadge(_ count: Int) -> some View {
        overlay(alignment: .topTrailing) {
            if count > 0 {
                GMCountBadge(count: count)
                    .overlay(Capsule().stroke(Theme.bg, lineWidth: 2))
                    .offset(x: 6, y: -4)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: count)
    }
}
