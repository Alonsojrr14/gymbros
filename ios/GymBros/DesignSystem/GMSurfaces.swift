import SwiftUI

struct GMCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: .rect(cornerRadius: Theme.radius))
    }
}

/// Título pequeno + card + rodapé explicativo (substitui as seções de formulário)
struct GMSection<Content: View>: View {
    var title: String?
    var footer: String?
    var trailing: AnyView?
    @ViewBuilder let content: Content

    init(_ title: String? = nil, footer: String? = nil, trailing: AnyView? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if title != nil || trailing != nil {
                HStack {
                    if let title {
                        Text(title.uppercased()).font(.caption.weight(.bold)).foregroundStyle(Theme.dim).tracking(0.6)
                    }
                    Spacer()
                    trailing
                }
                .padding(.horizontal, 4)
            }
            GMCard { content }
            if let footer {
                Text(footer).font(.caption).foregroundStyle(Theme.dim).padding(.horizontal, 4)
            }
        }
    }
}

struct GMDivider: View {
    var body: some View { Rectangle().fill(Theme.stroke).frame(height: 1) }
}

/// Linha tocável: ícone, título, subtítulo e algo à direita
struct GMRow<Trailing: View>: View {
    var icon: String?
    var iconTint: Color = .white
    /// Quadrado colorido atrás do ícone (GMIconTile), no lugar do fundo discreto
    var tile: Color?
    let title: String
    var subtitle: String?
    var chevron = false
    var action: (() -> Void)?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        let row = HStack(spacing: 12) {
            if let icon, let tile {
                GMIconTile(icon: icon, tint: tile)
            } else if let icon {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(iconTint)
                    .frame(width: 34, height: 34)
                    .background(Theme.raised, in: .rect(cornerRadius: Theme.radiusS))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(Theme.dim) }
            }
            Spacer(minLength: 8)
            trailing
            if chevron { Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.dim) }
        }
        .contentShape(Rectangle())
        if let action {
            Button(action: action) { row }.buttonStyle(GMPress())
        } else {
            row
        }
    }
}

extension GMRow where Trailing == EmptyView {
    init(icon: String? = nil, iconTint: Color = .white, tile: Color? = nil, title: String, subtitle: String? = nil, chevron: Bool = false,
         action: (() -> Void)? = nil) {
        self.init(icon: icon, iconTint: iconTint, tile: tile, title: title, subtitle: subtitle, chevron: chevron, action: action) { EmptyView() }
    }
}

/// Par rótulo/valor (substitui LabeledContent)
struct GMValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(Theme.dim)
            Spacer()
            Text(value).font(.subheadline.weight(.semibold))
        }
    }
}

struct GMEmptyState: View {
    let icon: String
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 40)).foregroundStyle(Theme.dim)
            Text(title).font(.headline)
            if let message { Text(message).font(.subheadline).foregroundStyle(Theme.dim).multilineTextAlignment(.center) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
    }
}
