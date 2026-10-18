import SwiftUI
import UIKit

struct GMSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? Theme.accent : Color.white.opacity(0.15))
            .frame(width: 50, height: 30)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle().fill(isOn ? .black : .white).padding(4)
            }
            .onTapGesture(perform: toggle)
            .accessibilityElement()
            .accessibilityValue(isOn ? "Ativado" : "Desativado")
            .accessibilityAddTraits(.isToggle)
            .accessibilityAction { toggle() }
    }

    func toggle() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(duration: 0.25)) { isOn.toggle() }
    }
}

struct GMToggle: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(Theme.dim) }
            }
            Spacer()
            GMSwitch(isOn: $isOn)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle ?? "")
        .accessibilityValue(isOn ? "Ativado" : "Desativado")
        .accessibilityAddTraits(.isToggle)
        .accessibilityAction { GMSwitch(isOn: $isOn).toggle() }
    }
}
