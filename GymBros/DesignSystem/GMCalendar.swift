import SwiftUI
import UIKit

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
                .background(Theme.raised, in: .rect(cornerRadius: Theme.radiusS))
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

/// Grade do mês usada pelos calendários do app (GMCalendar e ActivityCalendar): começa no domingo, em português
enum GMMonth {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = GMDateText.locale
        c.firstWeekday = 1
        return c
    }()

    static let weekdays = ["Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb"]

    static func start(of month: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: month))!
    }

    /// Dias do mês, com `nil` antes do dia 1 para alinhar na semana
    static func cells(_ month: Date) -> [Date?] {
        let start = start(of: month)
        let days = calendar.range(of: .day, in: .month, for: start)!.count
        let lead = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: lead) + (0..<days).map { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    static func title(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = GMDateText.locale
        f.dateFormat = "MMMM 'de' yyyy"
        return f.string(from: d).capitalizedFirst
    }

    /// Linha com os nomes dos dias da semana
    static var header: some View {
        HStack(spacing: 4) {
            ForEach(weekdays, id: \.self) {
                Text($0).font(.caption.bold()).foregroundStyle(Theme.dim).lineLimit(1).minimumScaleFactor(0.6).frame(maxWidth: .infinity)
            }
        }
    }
}

/// Calendário mensal próprio, em português, começando no domingo
struct GMCalendar: View {
    @Binding var selection: Date
    var maxDate: Date?
    var minDate: Date? = nil
    @State private var month = Date.now

    private var cal: Calendar { GMMonth.calendar }

    var body: some View {
        let start = GMMonth.start(of: month)
        let cells = GMMonth.cells(month)
        let canGoForward = maxDate.map { cal.date(byAdding: .month, value: 1, to: start)! <= $0 } ?? true

        VStack(spacing: 14) {
            HStack {
                GMIconButton(icon: "chevron.left", size: 36, label: "Mês anterior") { shift(-1) }
                Spacer()
                Text(GMMonth.title(start)).font(.headline)
                Spacer()
                GMIconButton(icon: "chevron.right", size: 36, tint: canGoForward ? .white : Theme.dim, label: "Próximo mês") { if canGoForward { shift(1) } }
            }
            GMMonth.header
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
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
        let disabled = (maxDate.map { cal.startOfDay(for: day) > cal.startOfDay(for: $0) } ?? false)
            || (minDate.map { cal.startOfDay(for: day) < cal.startOfDay(for: $0) } ?? false)
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
            RoundedRectangle(cornerRadius: Theme.radiusM).fill(Theme.raised).frame(height: GMWheel.row)
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

/// Roleta de duração: minutos e segundos (de 5 em 5)
struct GMDurationWheel: View {
    @Binding var seconds: Int
    var maxMinutes = 10

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.radiusM).fill(Theme.raised).frame(height: GMWheel.row)
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
