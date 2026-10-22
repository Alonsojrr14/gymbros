import SwiftUI
import UIKit

struct GMTextField: View {
    let placeholder: String
    @Binding var text: String
    var axis: Axis = .horizontal
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .sentences

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Theme.dim), axis: axis)
            .keyboardType(keyboard)
            .textInputAutocapitalization(capitalization)
            .lineLimit(axis == .vertical ? 2...6 : 1...1)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.raised, in: .rect(cornerRadius: Theme.radiusM))
    }
}

/// Campo de senha com o olho para mostrar ou ocultar o que foi digitado. Fundo de card e padding 14, como o
/// SecureField do login; o teclado continua aberto ao alternar.
struct GMSecureField: View {
    let placeholder: String
    @Binding var text: String
    var contentType: UITextContentType = .password
    @State private var visible = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if visible {
                    TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Theme.dim))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    SecureField("", text: $text, prompt: Text(placeholder).foregroundStyle(Theme.dim))
                }
            }
            .textContentType(contentType)
            .focused($focused)
            Button {
                let wasFocused = focused
                visible.toggle()
                if wasFocused { DispatchQueue.main.async { focused = true } }
            } label: {
                Image(systemName: visible ? "eye.slash" : "eye")
                    .foregroundStyle(Theme.dim)
                    .frame(width: 28, height: 28)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(visible ? "Ocultar senha" : "Mostrar senha")
        }
        .padding(14)
        .background(Theme.card, in: .rect(cornerRadius: Theme.radiusM))
    }
}

struct GMSearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.dim)
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Theme.dim))
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.dim) }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Theme.card, in: .capsule)
    }
}

/// Valor salvo que não fica editável o tempo todo: mostra o valor e só abre o editor pelo lápis
struct GMLockedRow<Editor: View>: View {
    let title: String
    /// Vazio = não informado
    let value: String
    @ViewBuilder var editor: Editor
    @State private var editing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                if !editing {
                    Text(value.isEmpty ? "Não informado" : value)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(value.isEmpty ? Theme.dim : .white)
                        .lineLimit(1)
                }
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.snappy) { editing.toggle() }
                } label: {
                    Image(systemName: editing ? "checkmark" : "pencil")
                        .font(.subheadline.bold())
                        .frame(width: 34, height: 34)
                        .background(editing ? Theme.accent : Theme.raised, in: .circle)
                        .foregroundStyle(editing ? .black : .white)
                }
                .buttonStyle(GMPress())
                .accessibilityLabel(editing ? "Concluir \(title)" : "Editar \(title)")
            }
            if editing { editor }
        }
    }
}

/// Número decimal opcional com − + e digitação (peso, medidas). Vazio mostra "—".
struct GMDecimalField: View {
    let title: String
    @Binding var value: Double?
    var step: Double = 0.5
    var unit: String = "kg"
    /// Valor usado no primeiro + quando ainda está vazio
    var start: Double = 70
    /// Mostra o X para apagar (campos opcionais)
    var clearable = true
    /// false para anos e números que não levam separador de milhar
    var grouping = true

    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(.subheadline.weight(.semibold))
            Spacer()
            stepButton("minus") { value = max((value ?? start) - step, 0) }
            HStack(spacing: 3) {
                TextField("—", value: $value, format: .number.precision(.fractionLength(0...2)).grouping(grouping ? .automatic : .never).locale(GMDateText.locale))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.headline.monospacedDigit())
                    .frame(width: 58)
                Text(unit).font(.caption).foregroundStyle(Theme.dim)
            }
            stepButton("plus") { value = (value.map { $0 + step }) ?? start }
            if clearable, value != nil {
                Button { value = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.dim) }
                    .buttonStyle(GMPress())
            }
        }
    }

    private func stepButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: icon).font(.caption.bold()).frame(width: 32, height: 32)
                .background(Theme.raised, in: .circle).foregroundStyle(.white)
        }
        .buttonStyle(GMPress())
    }
}
