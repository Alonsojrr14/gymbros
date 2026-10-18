import SwiftUI

/// Leve encolhida ao tocar, em tudo que é tocável
struct GMPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

enum GMButtonKind { case primary, secondary, danger, ghost }

struct GMButton: View {
    let title: String
    var icon: String?
    var kind: GMButtonKind = .primary
    var full = true
    var small = false
    var enabled = true
    let action: () -> Void

    init(_ title: String, icon: String? = nil, kind: GMButtonKind = .primary, full: Bool = true, small: Bool = false,
         enabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.kind = kind
        self.full = full
        self.small = small
        self.enabled = enabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon) }
                Text(title)
            }
            .font(small ? .subheadline.bold() : .headline)
            .frame(maxWidth: full ? .infinity : nil)
            .padding(.vertical, small ? 9 : 15)
            .padding(.horizontal, small ? 14 : 20)
            .background(background, in: .rect(cornerRadius: small ? Theme.radiusM : Theme.radiusL))
            .foregroundStyle(foreground)
            .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(GMPress())
        .disabled(!enabled)
    }

    private var background: Color {
        switch kind {
        case .primary: Theme.accent
        case .secondary: Theme.raised
        case .danger: Theme.danger.opacity(0.15)
        case .ghost: .clear
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary: .black
        case .secondary, .ghost: .white
        case .danger: Theme.danger
        }
    }
}

struct GMIconButton: View {
    let icon: String
    var size: CGFloat = 40
    var tint: Color = .white
    /// Rótulo do VoiceOver; sem ele, vem do ícone (fechar, voltar, ajustes…)
    var label: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.42, weight: .semibold))
                .frame(width: size, height: size)
                .background(Theme.raised, in: .circle)
                .foregroundStyle(tint)
        }
        .buttonStyle(GMPress())
        .accessibilityLabel(label ?? Self.defaultLabel(icon))
    }

    static func defaultLabel(_ icon: String) -> String {
        switch icon {
        case "xmark": "Fechar"
        case "chevron.left": "Voltar"
        case "chevron.right": "Avançar"
        case "ellipsis": "Mais opções"
        case "gearshape", "gearshape.fill": "Ajustes"
        case "person.2.fill", "person.2": "Amigos"
        case "pawprint.fill", "square.stack.3d.up": "Bros"
        case "plus": "Adicionar"
        case "pencil": "Editar"
        case "trash": "Apagar"
        case "square.and.arrow.up": "Compartilhar"
        case "magnifyingglass": "Buscar"
        default: icon.replacingOccurrences(of: ".fill", with: "").replacingOccurrences(of: ".", with: " ")
        }
    }
}

/// Botão redondo de acento que flutua no canto da tela (criar, postar)
struct GMFloatingButton: View {
    var icon = "plus"
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title2.bold())
                .frame(width: 62, height: 62)
                .background(Theme.accent, in: .circle)
                .foregroundStyle(.black)
                .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
        }
        .buttonStyle(GMPress())
        .accessibilityLabel(label)
    }
}

/// Botão de texto em acento, para cabeçalhos de tela ou de seção ("Adicionar", "OK"…)
struct GMTextButton: View {
    let title: String
    var icon: String?
    var bold = false
    /// Tamanho de rótulo de seção (caption)
    var small = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let icon { Label(title, systemImage: icon) } else { Text(title) }
            }
            .font(small ? .caption.bold() : bold ? .headline : .body)
            .foregroundStyle(enabled ? Theme.accent : Theme.dim)
            .padding(.horizontal, small ? 0 : 6)
            .padding(.vertical, small ? 0 : 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(GMPress())
        .disabled(!enabled)
    }
}
