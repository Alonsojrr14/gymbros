import SwiftUI
import UIKit

struct GMChip: View {
    let title: String
    var icon: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon) }
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(selected ? Theme.accent : Theme.raised, in: .capsule)
            .foregroundStyle(selected ? .black : .white)
        }
        .buttonStyle(GMPress())
    }
}

/// Abas segmentadas com destaque deslizante
struct GMSegmented<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.0) { value, label in
                let on = value == selection
                Button {
                    withAnimation(.spring(duration: 0.3)) { selection = value }
                } label: {
                    Text(label)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .foregroundStyle(on ? .black : .white.opacity(0.75))
                        .background {
                            if on { Capsule().fill(Theme.accent).matchedGeometryEffect(id: "seg", in: ns) }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Theme.card, in: .capsule)
    }
}

struct GMChoiceChips<T: Hashable>: View {
    var title: String?
    let options: [(T, String)]
    @Binding var selection: T

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { Text(title).font(.subheadline.weight(.semibold)) }
            GMFlow {
                ForEach(options, id: \.0) { value, label in
                    GMChip(title: label, selected: selection == value) {
                        UISelectionFeedbackGenerator().selectionChanged()
                        selection = value
                    }
                }
            }
        }
    }
}
