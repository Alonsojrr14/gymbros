import SwiftUI

// Design system do GymBros. O app não usa controles padrão do iOS (Form, List, Picker,
// Toggle, Stepper, Slider, DatePicker, Menu, alert, confirmationDialog, barras de navegação
// e de abas): tudo passa por estes componentes. Ficam com o sistema só o que o iOS não
// deixa substituir: teclado, seletor de fotos, compartilhar, seletor de arquivos e permissões.

// Cores em Shared/Theme.swift. Escala de raios: use só estes valores.
extension Theme {
    /// Barras finas de gráfico e de esforço
    static let radiusXS: CGFloat = 4
    /// Quadrado de ícone, miniaturas
    static let radiusS: CGFloat = 10
    /// Campos, botão pequeno, fotos em lista
    static let radiusM: CGFloat = 12
    /// Botão, blocos dentro de card, mapas
    static let radiusL: CGFloat = 16
    /// Cards (GMCard)
    static let radius: CGFloat = 20
    /// Bottom sheet e diálogo
    static let radiusXL: CGFloat = 28
}

/// Fonte do sistema com tamanho próprio que acompanha o Dynamic Type
private struct GMScaledFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    let mono: Bool

    init(size: CGFloat, weight: Font.Weight, design: Font.Design, mono: Bool, relativeTo style: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
        self.design = design
        self.mono = mono
    }

    func body(content: Content) -> some View {
        let f = Font.system(size: size, weight: weight, design: design)
        content.font(mono ? f.monospacedDigit() : f)
    }
}

extension View {
    /// Igual a `.font(.system(size:weight:design:))`, mas cresce com o Dynamic Type
    func gmFont(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default, mono: Bool = false,
                relativeTo style: Font.TextStyle = .body) -> some View {
        modifier(GMScaledFont(size: size, weight: weight, design: design, mono: mono, relativeTo: style))
    }
}
