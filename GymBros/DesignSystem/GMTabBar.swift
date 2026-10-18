import SwiftUI
import UIKit

struct GMTabItem {
    let icon: String
    let title: String
    /// Página que a aba abre
    var tag: Int
    /// Bolinha com número (ex.: amigos treinando agora)
    var badge: Int?
}

/// Barra de abas com o bro no meio: bolinha grande e elevada, já que ele é o centro do app
struct GMTabBar<Center: View>: View {
    let left: [GMTabItem]
    let right: [GMTabItem]
    let centerTag: Int
    @Binding var selection: Int
    @ViewBuilder var center: Center
    @Namespace private var ns
    @State private var bump = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(left, id: \.tag) { tab($0) }
            centerButton
            ForEach(right, id: \.tag) { tab($0) }
        }
        .padding(5)
        .background(.ultraThinMaterial, in: .capsule)
        .overlay(Capsule().stroke(Theme.stroke))
        .padding(.horizontal, 14)
        // Barra compacta: cresce com o texto só até um limite
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private func select(_ t: Int) {
        if t != selection { UISelectionFeedbackGenerator().selectionChanged() }
        withAnimation(.spring(duration: 0.3)) { selection = t }
    }

    private func tab(_ item: GMTabItem) -> some View {
        let on = item.tag == selection
        return Button { select(item.tag) } label: {
            VStack(spacing: 3) {
                Image(systemName: item.icon).font(.system(size: 18, weight: .semibold))
                    .overlay(alignment: .topTrailing) {
                        if let n = item.badge, n > 0 {
                            Text("\(n)").gmFont(9, weight: .heavy, relativeTo: .caption2)
                                .frame(minWidth: 15, minHeight: 15)
                                .background(Theme.badge, in: .circle)
                                .foregroundStyle(.white)
                                .offset(x: 9, y: -6)
                        }
                    }
                Text(item.title).gmFont(10, weight: .semibold, relativeTo: .caption2).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(on ? .black : .white.opacity(0.6))
            .background {
                if on { Capsule().fill(Theme.accent).matchedGeometryEffect(id: "tab", in: ns) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.badge.map { $0 > 0 ? "\(item.title), \($0)" : item.title } ?? item.title)
    }

    private var centerButton: some View {
        let on = centerTag == selection
        return Button {
            select(centerTag)
            withAnimation(.spring(duration: 0.25, bounce: 0.6)) { bump = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { withAnimation(.spring) { bump = false } }
        } label: {
            ZStack {
                Circle().fill(on ? Theme.accent : Theme.card)
                Circle().stroke(AngularGradient(colors: [Theme.accent, Attribute.resistencia.color, Attribute.tecnica.color, Attribute.forca.color, Theme.accent],
                                                center: .center), lineWidth: 3)
                center.frame(width: 48, height: 48).scaleEffect(bump ? 1.18 : 1)
            }
            .frame(width: 66, height: 66)
            .shadow(color: on ? Theme.accent.opacity(0.55) : .black.opacity(0.4), radius: on ? 14 : 8, y: 4)
            .offset(y: -16)
        }
        .buttonStyle(.plain)
        .frame(width: 72, height: 46)
        .accessibilityLabel("Bro")
    }
}
