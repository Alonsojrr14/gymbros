import SwiftUI
import UIKit

// Design system do GymMonsters. O app não usa controles padrão do iOS (Form, List, Picker,
// Toggle, Stepper, Slider, DatePicker, Menu, alert, confirmationDialog, barras de navegação
// e de abas): tudo passa por estes componentes. Ficam com o sistema só o que o iOS não
// deixa substituir: teclado, seletor de fotos, compartilhar, seletor de arquivos e permissões.

extension Theme {
    static let raised = Color.white.opacity(0.06)
    static let stroke = Color.white.opacity(0.08)
    static let danger = Color(red: 1.0, green: 0.38, blue: 0.38)
    static let radius: CGFloat = 20
}

// MARK: - Botões

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
            .background(background, in: .rect(cornerRadius: small ? 12 : 16))
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
    }
}

/// Botão de texto pequeno para cabeçalhos (Salvar, OK…)
struct GMTextButton: View {
    let title: String
    var bold = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(bold ? .headline : .body)
                .foregroundStyle(enabled ? Theme.accent : Theme.dim)
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
        }
        .buttonStyle(GMPress())
        .disabled(!enabled)
    }
}

// MARK: - Superfícies

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
    let title: String
    var subtitle: String?
    var chevron = false
    var action: (() -> Void)?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        let row = HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(iconTint)
                    .frame(width: 34, height: 34)
                    .background(Theme.raised, in: .rect(cornerRadius: 10))
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
    init(icon: String? = nil, iconTint: Color = .white, title: String, subtitle: String? = nil, chevron: Bool = false,
         action: (() -> Void)? = nil) {
        self.init(icon: icon, iconTint: iconTint, title: title, subtitle: subtitle, chevron: chevron, action: action) { EmptyView() }
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

struct GMProgressBar: View {
    let value: Double
    var tint: Color = Theme.accent
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.1))
                Capsule().fill(tint).frame(width: max(g.size.width * min(max(value, 0), 1), value > 0 ? height : 0))
            }
        }
        .frame(height: height)
        .animation(.spring(duration: 0.5), value: value)
    }
}

struct GMBadge: View {
    let text: String
    var tint: Color = Theme.accent

    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.2), in: .capsule)
            .foregroundStyle(tint)
    }
}

// MARK: - Controles

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

struct GMSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? Theme.accent : Color.white.opacity(0.15))
            .frame(width: 50, height: 30)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle().fill(isOn ? .black : .white).padding(4)
            }
            .onTapGesture {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(duration: 0.25)) { isOn.toggle() }
            }
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
    }
}

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
                        RoundedRectangle(cornerRadius: 4)
                            .fill(i <= value ? color(i) : Color.white.opacity(0.1))
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
            .background(Theme.raised, in: .rect(cornerRadius: 12))
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

/// Dia e horário: dois campos que abrem calendário e roleta em bottom sheets nossas
struct GMDateTimePicker: View {
    @Binding var date: Date
    /// Não deixa escolher o futuro (registro de atividade)
    var limitToNow = true

    var body: some View {
        VStack(spacing: 10) {
            GMDateField(date: $date, limitToNow: limitToNow)
            GMDivider()
            GMTimeField(date: $date, limitToNow: limitToNow)
        }
    }
}

enum GMDateText {
    static let locale = Locale(identifier: "pt_BR")

    static func day(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Hoje" }
        if cal.isDateInYesterday(d) { return "Ontem" }
        let sameYear = cal.component(.year, from: d) == cal.component(.year, from: .now)
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = sameYear ? "EEE, d 'de' MMMM" : "d 'de' MMM 'de' yyyy"
        return f.string(from: d).capitalizedFirst
    }

    static func time(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// Linha "Dia · Hoje" que abre o calendário
struct GMDateField: View {
    @Binding var date: Date
    var limitToNow = true
    var title = "Dia"
    @State private var open = false
    @State private var draft = Date.now

    var body: some View {
        fieldRow(icon: "calendar", title: title, value: GMDateText.day(date)) {
            draft = date
            open = true
        }
        .gmSheet(isPresented: $open) { close in
            VStack(spacing: 16) {
                GMCalendar(selection: $draft, maxDate: limitToNow ? .now : nil)
                GMButton("Confirmar") {
                    // Mantém o horário, troca só o dia
                    let cal = Calendar.current
                    let t = cal.dateComponents([.hour, .minute], from: date)
                    let d = cal.date(bySettingHour: t.hour ?? 0, minute: t.minute ?? 0, second: 0, of: draft) ?? draft
                    date = limitToNow ? min(d, .now) : d
                    close()
                }
            }
        }
    }
}

/// Linha "Horário · 14:30" que abre a roleta
struct GMTimeField: View {
    @Binding var date: Date
    var limitToNow = false
    var title = "Horário"
    @State private var open = false
    @State private var hour = 0
    @State private var minute = 0

    var body: some View {
        fieldRow(icon: "clock", title: title, value: GMDateText.time(date)) {
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            hour = c.hour ?? 0
            minute = c.minute ?? 0
            open = true
        }
        .gmSheet(isPresented: $open) { close in
            VStack(spacing: 16) {
                Text(title).font(.headline)
                GMTimeWheel(hour: $hour, minute: $minute)
                GMButton("Confirmar") {
                    let d = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
                    date = limitToNow ? min(d, .now) : d
                    close()
                }
            }
        }
    }
}

private func fieldRow(icon: String, title: String, value: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .frame(width: 34, height: 34)
                .background(Theme.raised, in: .rect(cornerRadius: 10))
            Text(title).font(.subheadline.weight(.semibold))
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Theme.raised, in: .capsule)
        }
        .foregroundStyle(.white)
        .contentShape(Rectangle())
    }
    .buttonStyle(GMPress())
}

/// Calendário mensal próprio, em português, começando no domingo
struct GMCalendar: View {
    @Binding var selection: Date
    var maxDate: Date?
    @State private var month = Date.now

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = GMDateText.locale
        c.firstWeekday = 1
        return c
    }

    var body: some View {
        let start = cal.date(from: cal.dateComponents([.year, .month], from: month))!
        let days = cal.range(of: .day, in: .month, for: start)!.count
        let lead = (cal.component(.weekday, from: start) - cal.firstWeekday + 7) % 7
        let cells: [Date?] = Array(repeating: nil, count: lead) + (0..<days).map { cal.date(byAdding: .day, value: $0, to: start) }
        let canGoForward = maxDate.map { cal.date(byAdding: .month, value: 1, to: start)! <= $0 } ?? true

        VStack(spacing: 14) {
            HStack {
                GMIconButton(icon: "chevron.left", size: 36) { shift(-1) }
                Spacer()
                Text(monthTitle(start)).font(.headline)
                Spacer()
                GMIconButton(icon: "chevron.right", size: 36, tint: canGoForward ? .white : Theme.dim) { if canGoForward { shift(1) } }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                ForEach(Array(["D", "S", "T", "Q", "Q", "S", "S"].enumerated()), id: \.offset) { _, d in
                    Text(d).font(.caption.bold()).foregroundStyle(Theme.dim)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day { dayCell(day) } else { Color.clear.frame(height: 40) }
                }
            }
            if !cal.isDate(selection, inSameDayAs: .now) {
                GMButton("Ir para hoje", kind: .ghost, small: true) {
                    selection = .now
                    month = .now
                }
            }
        }
        .onAppear { month = selection }
    }

    private func dayCell(_ day: Date) -> some View {
        let selected = cal.isDate(day, inSameDayAs: selection)
        let today = cal.isDateInToday(day)
        let disabled = maxDate.map { cal.startOfDay(for: day) > cal.startOfDay(for: $0) } ?? false
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            selection = day
        } label: {
            Text("\(cal.component(.day, from: day))")
                .font(.subheadline.weight(selected || today ? .bold : .medium).monospacedDigit())
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(selected ? Theme.accent : .clear, in: .circle)
                .overlay(Circle().stroke(today && !selected ? Theme.accent : .clear, lineWidth: 1.5))
                .foregroundStyle(selected ? .black : disabled ? Theme.dim.opacity(0.4) : .white)
        }
        .buttonStyle(GMPress())
        .disabled(disabled)
    }

    private func monthTitle(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = GMDateText.locale
        f.dateFormat = "MMMM 'de' yyyy"
        return f.string(from: d).capitalizedFirst
    }

    private func shift(_ n: Int) {
        withAnimation(.snappy) { month = cal.date(byAdding: .month, value: n, to: month) ?? month }
    }
}

/// Roleta de horas e minutos
struct GMTimeWheel: View {
    @Binding var hour: Int
    @Binding var minute: Int

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Theme.raised).frame(height: GMWheel.row)
            HStack(spacing: 0) {
                GMWheel(values: Array(0..<24), selection: $hour)
                Text(":").font(.title.bold())
                GMWheel(values: Array(0..<60), selection: $minute)
            }
            .padding(.horizontal, 40)
        }
    }
}

struct GMWheel: View {
    static let row: CGFloat = 46
    let values: [Int]
    @Binding var selection: Int
    @State private var position: Int?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(values, id: \.self) { v in
                    let on = v == (position ?? selection)
                    Text(String(format: "%02d", v))
                        .font(.system(size: on ? 30 : 24, weight: on ? .bold : .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(on ? .white : Theme.dim)
                        .frame(height: GMWheel.row)
                        .frame(maxWidth: .infinity)
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.vertical, GMWheel.row * 2, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $position, anchor: .center)
        .frame(height: GMWheel.row * 5)
        .mask(LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .top, endPoint: .bottom))
        .onAppear { position = selection }
        .onChange(of: position) { _, v in
            guard let v, v != selection else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            selection = v
        }
    }
}

// MARK: - Estrutura de tela

/// Cabeçalho próprio (substitui a barra de navegação)
struct GMHeader<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    var large = true
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                leading
                if !large {
                    Spacer()
                    Text(title).font(.headline).lineLimit(1)
                }
                Spacer()
                trailing
            }
            .frame(minHeight: 40)
            if large {
                Text(title).font(.system(size: 32, weight: .heavy, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
                if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(Theme.dim) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

/// Tela padrão: cabeçalho próprio + conteúdo rolável. `back` mostra o botão de voltar.
struct GMScreen<Content: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    var back = false
    /// Mostra a bolinha do perfil à esquerda (telas principais das abas)
    var avatar = false
    var large = true
    var bottomInset: CGFloat = 100
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    init(_ title: String, subtitle: String? = nil, back: Bool = false, avatar: Bool = false, large: Bool = true, bottomInset: CGFloat = 100,
         @ViewBuilder trailing: () -> Trailing = { EmptyView() }, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.back = back
        self.avatar = avatar
        self.large = large
        self.bottomInset = bottomInset
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            GMHeader(title: title, subtitle: subtitle, large: large && !back) {
                if back { GMIconButton(icon: "chevron.left") { dismiss() } }
                if avatar { ProfileAvatarButton() }
            } trailing: { trailing }
            if back && large {
                Text(title).font(.system(size: 26, weight: .heavy, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.bottom, 8)
                    .lineLimit(2)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) { content }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, bottomInset)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .background(Theme.bg.ignoresSafeArea())
        .gmKeyboardDone()
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// Tela modal (formulários): fechar à esquerda, título ao centro, ação à direita
struct GMModal<Content: View>: View {
    let title: String
    var cancel = "Cancelar"
    var confirm: String?
    var confirmEnabled = true
    var onConfirm: (() -> Void)?
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    init(_ title: String, cancel: String = "Cancelar", confirm: String? = nil, confirmEnabled: Bool = true,
         onConfirm: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.cancel = cancel
        self.confirm = confirm
        self.confirmEnabled = confirmEnabled
        self.onConfirm = onConfirm
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(title).font(.headline)
                HStack {
                    GMIconButton(icon: "xmark", size: 36) { dismiss() }
                    Spacer()
                    if let confirm, let onConfirm {
                        GMButton(confirm, full: false, small: true, enabled: confirmEnabled, action: onConfirm)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) { content }
                    .padding(16)
                    .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .background(Theme.bg.ignoresSafeArea())
        .gmKeyboardDone()
    }
}

extension View {
    /// Abre uma tela modal inteira (sem o cartão padrão do iOS)
    func gmModal<C: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> C) -> some View {
        fullScreenCover(isPresented: isPresented) { content().preferredColorScheme(.dark).tint(Theme.accent) }
    }

    func gmModal<Item: Identifiable, C: View>(item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> C) -> some View {
        fullScreenCover(item: item) { content($0).preferredColorScheme(.dark).tint(Theme.accent) }
    }
}

// MARK: - Bottom sheet, ações e diálogos

struct GMAction: Identifiable {
    let id = UUID()
    let title: String
    var icon: String?
    var destructive = false
    let action: () -> Void

    init(_ title: String, icon: String? = nil, destructive: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.destructive = destructive
        self.action = action
    }
}

/// Camada própria por cima de tudo: fundo escurecido + conteúdo animado.
/// Usa um fullScreenCover transparente sem a animação do sistema, para funcionar em qualquer tela.
private struct GMOverlayHost<Content: View>: View {
    @Binding var isPresented: Bool
    var center = false
    let content: (_ close: @escaping (_ then: (() -> Void)?) -> Void) -> Content
    @State private var shown = false
    @State private var drag: CGFloat = 0

    var body: some View {
        ZStack(alignment: center ? .center : .bottom) {
            Color.black.opacity(shown ? 0.55 : 0)
                .ignoresSafeArea()
                .onTapGesture { close(nil) }
            if shown {
                content(close)
                    .offset(y: max(drag, 0))
                    .gesture(center ? nil : DragGesture().onChanged { drag = $0.translation.height }.onEnded { v in
                        if v.translation.height > 120 { close(nil) } else { withAnimation(.spring) { drag = 0 } }
                    })
                    .transition(center ? .scale(scale: 0.9).combined(with: .opacity) : .move(edge: .bottom))
            }
        }
        .presentationBackground(.clear)
        .onAppear { withAnimation(.spring(duration: 0.35, bounce: 0.15)) { shown = true } }
    }

    private func close(_ then: (() -> Void)?) {
        withAnimation(.easeOut(duration: 0.2)) { shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { isPresented = false }
            // A ação roda depois que a camada saiu, para poder abrir outra tela em seguida
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { then?() }
        }
    }
}

struct GMSheetCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(.white.opacity(0.25)).frame(width: 38, height: 5).padding(.top, 10).padding(.bottom, 14)
            content
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
        .ignoresSafeArea(edges: .bottom)
    }
}

extension View {
    /// Bottom sheet com conteúdo livre
    func gmSheet<C: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping (_ close: @escaping () -> Void) -> C) -> some View {
        fullScreenCover(isPresented: isPresented) {
            GMOverlayHost(isPresented: isPresented) { close in GMSheetCard { content { close(nil) } } }
        }
        // Só a abertura desta camada fica sem a animação do iOS (ela tem a própria);
        // sem o `value`, isso desligava a animação de todas as telas abaixo
        .transaction(value: isPresented.wrappedValue) { $0.disablesAnimations = true }
    }

    /// Bottom sheet de ações (substitui Menu e confirmationDialog)
    func gmActions(isPresented: Binding<Bool>, title: String? = nil, message: String? = nil, actions: [GMAction]) -> some View {
        fullScreenCover(isPresented: isPresented) {
            GMOverlayHost(isPresented: isPresented) { close in
                GMSheetCard {
                    VStack(spacing: 10) {
                        if let title { Text(title).font(.headline).multilineTextAlignment(.center) }
                        if let message {
                            Text(message).font(.subheadline).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                        }
                        if title != nil || message != nil { Spacer().frame(height: 4) }
                        ForEach(actions) { a in
                            GMButton(a.title, icon: a.icon, kind: a.destructive ? .danger : .secondary) { close(a.action) }
                        }
                        GMButton("Cancelar", kind: .ghost) { close(nil) }
                    }
                }
            }
        }
        // Só a abertura desta camada fica sem a animação do iOS (ela tem a própria);
        // sem o `value`, isso desligava a animação de todas as telas abaixo
        .transaction(value: isPresented.wrappedValue) { $0.disablesAnimations = true }
    }

    /// Diálogo central com campo de texto (substitui alert com TextField)
    func gmPrompt(isPresented: Binding<Bool>, title: String, message: String? = nil, placeholder: String,
                  text: Binding<String>, confirm: String = "Salvar", onConfirm: @escaping () -> Void) -> some View {
        fullScreenCover(isPresented: isPresented) {
            GMOverlayHost(isPresented: isPresented, center: true) { close in
                VStack(spacing: 14) {
                    Text(title).font(.headline)
                    if let message { Text(message).font(.subheadline).foregroundStyle(Theme.dim).multilineTextAlignment(.center) }
                    GMTextField(placeholder: placeholder, text: text, axis: .vertical)
                    HStack(spacing: 10) {
                        GMButton("Cancelar", kind: .secondary) { close(nil) }
                        GMButton(confirm) { close(onConfirm) }
                    }
                }
                .padding(20)
                .background(Theme.card, in: .rect(cornerRadius: 24))
                .padding(.horizontal, 28)
            }
        }
        // Só a abertura desta camada fica sem a animação do iOS (ela tem a própria);
        // sem o `value`, isso desligava a animação de todas as telas abaixo
        .transaction(value: isPresented.wrappedValue) { $0.disablesAnimations = true }
    }
}

// MARK: - Barra de abas

struct GMTabItem {
    let icon: String
    let title: String
}

struct GMTabBar: View {
    let items: [GMTabItem]
    @Binding var selection: Int
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                let on = i == selection
                Button {
                    if !on { UISelectionFeedbackGenerator().selectionChanged() }
                    withAnimation(.spring(duration: 0.3)) { selection = i }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.icon).font(.system(size: 18, weight: .semibold))
                        Text(item.title).font(.system(size: 10, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(on ? .black : .white.opacity(0.6))
                    .background {
                        if on { Capsule().fill(Theme.accent).matchedGeometryEffect(id: "tab", in: ns) }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(.ultraThinMaterial, in: .capsule)
        .overlay(Capsule().stroke(Theme.stroke))
        .padding(.horizontal, 14)
    }
}

// MARK: - Voltar com gesto mesmo sem a barra de navegação

extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}

// MARK: - Escolha por chips (substitui Picker de menu)

/// Layout que quebra linha, para chips
struct GMFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 { x = 0; y += row + spacing; row = 0 }
            x += s.width + spacing
            maxX = max(maxX, x - spacing)
            row = max(row, s.height)
        }
        return CGSize(width: min(maxX, width), height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += row + spacing; row = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            row = max(row, s.height)
        }
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

    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(.subheadline.weight(.semibold))
            Spacer()
            stepButton("minus") { value = max((value ?? start) - step, 0) }
            HStack(spacing: 3) {
                TextField("—", value: $value, format: .number.precision(.fractionLength(0...2)).locale(GMDateText.locale))
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

// MARK: - Teclado

/// Tocar fora de um campo fecha o teclado, no app inteiro (o teclado numérico não tem tecla de confirmar)
final class GMKeyboardDismisser: NSObject, UIGestureRecognizerDelegate {
    static let shared = GMKeyboardDismisser()

    func install() {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows where !(window.gestureRecognizers ?? []).contains(where: { $0.name == "gmDismissKeyboard" }) {
                let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
                tap.name = "gmDismissKeyboard"
                tap.cancelsTouchesInView = false
                tap.delegate = self
                window.addGestureRecognizer(tap)
            }
        }
    }

    @objc private func tapped(_ g: UITapGestureRecognizer) { g.view?.endEditing(true) }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Tocar em outro campo troca de campo em vez de fechar o teclado
        !(touch.view is UITextField || touch.view is UITextView)
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}

/// Botão "OK" próprio logo acima do teclado, enquanto ele estiver aberto
private struct GMKeyboardDone: ViewModifier {
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomTrailing) {
                if visible {
                    Button {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    } label: {
                        Label("OK", systemImage: "keyboard.chevron.compact.down")
                            .font(.subheadline.bold())
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Theme.accent, in: .capsule)
                            .foregroundStyle(.black)
                    }
                    .buttonStyle(GMPress())
                    .padding(.trailing, 14)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                withAnimation(.easeOut(duration: 0.2)) { visible = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                withAnimation(.easeOut(duration: 0.15)) { visible = false }
            }
            .onAppear { GMKeyboardDismisser.shared.install() }
    }
}

extension View {
    func gmKeyboardDone() -> some View { modifier(GMKeyboardDone()) }
}


/// Roleta de duração: minutos e segundos (de 5 em 5)
struct GMDurationWheel: View {
    @Binding var seconds: Int
    var maxMinutes = 10

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Theme.raised).frame(height: GMWheel.row)
            HStack(spacing: 0) {
                GMWheel(values: Array(0...maxMinutes), selection: Binding(get: { seconds / 60 }, set: { seconds = $0 * 60 + seconds % 60 }))
                Text("min").font(.headline).foregroundStyle(Theme.dim)
                GMWheel(values: Array(stride(from: 0, through: 55, by: 5)),
                        selection: Binding(get: { seconds % 60 / 5 * 5 }, set: { seconds = seconds / 60 * 60 + $0 }))
                Text("s").font(.headline).foregroundStyle(Theme.dim)
            }
            .padding(.horizontal, 24)
        }
    }
}
