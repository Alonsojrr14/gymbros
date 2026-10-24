import SwiftUI
import UIKit

/// − valor +
struct GMStepper: View {
    var title: String?
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1
    var format: (Int) -> String = { "\($0)" }

    var body: some View {
        HStack(spacing: 10) {
            if let title { Text(title).font(.subheadline.weight(.semibold)); Spacer() }
            stepButton("minus") { value = max(value - step, range.lowerBound) }
            Text(format(value))
                .font(.headline.monospacedDigit())
                .frame(minWidth: 64)
                .contentTransition(.numericText())
            stepButton("plus") { value = min(value + step, range.upperBound) }
        }
    }

    private func stepButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.snappy) { action() }
        } label: {
            Image(systemName: icon)
                .font(.subheadline.bold())
                .frame(width: 36, height: 36)
                .background(Theme.raised, in: .circle)
                .foregroundStyle(.white)
        }
        .buttonStyle(GMPress())
    }
}

/// Stepper compacto em bloco (− valor/rótulo +), para grades e linhas apertadas.
/// Com `editable`, o valor também pode ser digitado (séries do treino).
struct GMCompactStepper: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...Double.greatestFiniteMagnitude
    let step: Double
    let label: Text
    var decimals = false
    var editable = false

    var body: some View {
        HStack(spacing: 2) {
            stepButton("minus") { value = max(value - step, range.lowerBound) }
            VStack(spacing: editable ? -2 : 0) {
                if editable {
                    GMNumberInput(value: $value, range: range, decimals: decimals)
                        .font(.body.bold().monospacedDigit())
                        .frame(width: 52)
                } else {
                    Text(value, format: .number.precision(.fractionLength(0...(decimals ? 2 : 0))))
                        .font(.subheadline.bold().monospacedDigit())
                        .contentTransition(.numericText())
                }
                label.font(.caption2).foregroundStyle(Theme.dim).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: editable ? nil : .infinity)
            stepButton("plus") { value = min(value + step, range.upperBound) }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, editable ? 0 : 4)
        .background(Theme.raised, in: .rect(cornerRadius: Theme.radiusM))
    }

    private func stepButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.snappy) { action() }
        } label: {
            Image(systemName: icon).font(.caption.bold()).frame(width: 28, height: 34).contentShape(Rectangle())
        }
        .buttonStyle(GMPress())
        .foregroundStyle(.white)
        .accessibilityLabel(icon == "minus" ? "Diminuir" : "Aumentar")
    }
}

extension GMCompactStepper {
    /// Versão inteira (séries, reps)
    init(value: Binding<Int>, range: ClosedRange<Int>, step: Int, label: String) {
        self.init(value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0) }),
                  range: Double(range.lowerBound)...Double(range.upperBound), step: Double(step), label: Text(label))
    }
}

/// Esforço de 1 a 10: barras crescentes, toque ou arraste
struct GMEffortPicker: View {
    @Binding var value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Esforço").font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(value)/10 · \(effortLabel(value))").font(.subheadline.monospacedDigit()).foregroundStyle(Theme.dim)
            }
            GeometryReader { g in
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(1...10, id: \.self) { i in
                        RoundedRectangle(cornerRadius: Theme.radiusXS)
                            .fill(i <= value ? color(i) : Theme.track)
                            .frame(height: 12 + CGFloat(i) * 2.6)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    let i = min(max(Int(v.location.x / g.size.width * 10) + 1, 1), 10)
                    if i != value {
                        UISelectionFeedbackGenerator().selectionChanged()
                        value = i
                    }
                })
            }
            .frame(height: 40)
        }
    }

    private func color(_ i: Int) -> Color {
        i <= 3 ? Theme.accent : i <= 6 ? .yellow : i <= 8 ? .orange : .red
    }
}

/// Régua deslizante: arraste para escolher um valor; encaixa no passo e vibra a cada um
struct GMRuler: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...300
    var step: Double = 2.5
    /// Marca maior (com número) a cada quantos passos
    var majorEvery = 4
    @State private var position: Int?

    private static let tick: CGFloat = 12
    private var count: Int { Int(((range.upperBound - range.lowerBound) / step).rounded()) + 1 }
    private func index(_ v: Double) -> Int { min(max(Int(((v - range.lowerBound) / step).rounded()), 0), count - 1) }
    private func valueAt(_ i: Int) -> Double { range.lowerBound + Double(i) * step }

    var body: some View {
        GeometryReader { g in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(0..<count, id: \.self) { i in
                        let major = i % majorEvery == 0
                        VStack(spacing: 4) {
                            Capsule()
                                .fill(major ? Color.white.opacity(0.7) : Color.white.opacity(0.25))
                                .frame(width: 2, height: major ? 26 : 14)
                            Text(major ? Progression.fmt(valueAt(i)) : " ")
                                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Theme.dim)
                                .fixedSize()
                        }
                        .frame(width: GMRuler.tick, height: 50, alignment: .top)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, g.size.width / 2 - GMRuler.tick / 2, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $position, anchor: .center)
            .overlay(alignment: .top) {
                // Ponteiro fixo no centro
                Capsule().fill(Theme.accent).frame(width: 4, height: 34).offset(y: -4)
            }
            .mask(LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .leading, endPoint: .trailing))
        }
        .frame(height: 56)
        .onAppear { position = index(value) }
        .onChange(of: position) { _, i in
            guard let i else { return }
            let v = valueAt(i)
            if v != value {
                UISelectionFeedbackGenerator().selectionChanged()
                value = v
            }
        }
        // Quando o valor muda por outro meio (+, −, digitação), a régua acompanha
        .onChange(of: value) { _, v in
            let i = index(v)
            if i != position { withAnimation(.snappy) { position = i } }
        }
    }
}

/// Número digitável que pode ficar vazio enquanto você digita (apagar não volta ao valor anterior).
/// Vazio ao sair do campo vira o mínimo (0); aceita vírgula ou ponto.
struct GMNumberInput: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...Double.greatestFiniteMagnitude
    var decimals = false
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("0", text: $text)
            .keyboardType(decimals ? .decimalPad : .numberPad)
            .multilineTextAlignment(.center)
            .focused($focused)
            .onAppear { text = Self.format(value, decimals) }
            .onChange(of: value) { _, v in if !focused || Self.parse(text) != v { text = Self.format(v, decimals) } }
            .onChange(of: text) { _, t in
                guard let v = Self.parse(t) else { return }
                let clamped = min(max(v, range.lowerBound), range.upperBound)
                if clamped != value { value = clamped }
            }
            .onChange(of: focused) { _, isOn in
                guard !isOn else { return }
                if Self.parse(text) == nil { value = range.lowerBound }
                text = Self.format(value, decimals)
            }
    }

    static func parse(_ t: String) -> Double? {
        let clean = t.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        return clean.isEmpty ? nil : Double(clean)
    }

    static func format(_ v: Double, _ decimals: Bool) -> String {
        guard decimals else { return String(Int(v.rounded())) }
        return v.formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(GMDateText.locale))
    }
}
