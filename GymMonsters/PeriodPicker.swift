import SwiftUI

/// Calendário de intervalo: o primeiro toque marca o início, o segundo o fim
struct GMRangeCalendar: View {
    @Binding var start: Date
    @Binding var end: Date?
    /// Dias antes deste ficam bloqueados
    var minDate: Date? = nil
    @State private var month = Date.now

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = GMDateText.locale
        c.firstWeekday = 1
        return c
    }

    var body: some View {
        let first = cal.date(from: cal.dateComponents([.year, .month], from: month))!
        let days = cal.range(of: .day, in: .month, for: first)!.count
        let lead = (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
        let cells: [Date?] = Array(repeating: nil, count: lead) + (0..<days).map { cal.date(byAdding: .day, value: $0, to: first) }
        VStack(spacing: 12) {
            HStack {
                GMIconButton(icon: "chevron.left", size: 36) { shift(-1) }
                Spacer()
                Text(first.formatted(.dateTime.month(.wide).year()).capitalizedFirst).font(.headline)
                Spacer()
                GMIconButton(icon: "chevron.right", size: 36) { shift(1) }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                ForEach(Array(["D", "S", "T", "Q", "Q", "S", "S"].enumerated()), id: \.offset) { _, d in
                    Text(d).font(.caption.bold()).foregroundStyle(Theme.dim)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day { cell(day) } else { Color.clear.frame(height: 40) }
                }
            }
        }
        .onAppear { month = start }
    }

    private func cell(_ day: Date) -> some View {
        let d = cal.startOfDay(for: day)
        let s = cal.startOfDay(for: start)
        let e = end.map { cal.startOfDay(for: $0) }
        let isStart = d == s, isEnd = d == e
        let inside = e.map { d > s && d < $0 } ?? false
        let blocked = minDate.map { d < cal.startOfDay(for: $0) } ?? false
        return Button { tap(d) } label: {
            Text("\(cal.component(.day, from: day))")
                .font(.subheadline.weight(isStart || isEnd ? .bold : .medium).monospacedDigit())
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                // Faixa entre início e fim
                .background(alignment: .center) {
                    if inside || ((isStart || isEnd) && e != nil && s != e) {
                        Rectangle().fill(Theme.accent.opacity(0.22))
                            .padding(.leading, isStart ? 20 : 0)
                            .padding(.trailing, isEnd ? 20 : 0)
                    }
                }
                .background((isStart || isEnd) ? Theme.accent : .clear, in: .circle)
                .overlay(Circle().stroke(cal.isDateInToday(day) && !(isStart || isEnd) ? Theme.accent : .clear, lineWidth: 1.5))
                .foregroundStyle(isStart || isEnd ? .black : blocked ? Theme.dim.opacity(0.35) : .white)
        }
        .buttonStyle(GMPress())
        .disabled(blocked)
    }

    private func tap(_ d: Date) {
        UISelectionFeedbackGenerator().selectionChanged()
        // Já tem início e fim, ou tocou antes do início: recomeça a escolha
        if end != nil || d < cal.startOfDay(for: start) {
            start = d
            end = nil
        } else {
            end = d
        }
    }

    private func shift(_ n: Int) {
        withAnimation(.snappy) { month = cal.date(byAdding: .month, value: n, to: month) ?? month }
    }
}

/// Linha "Período" do formulário da liga; toca e escolhe no calendário
struct LeaguePeriodField: View {
    @Binding var start: Date
    @Binding var end: Date
    @Binding var hasEnd: Bool
    /// Primeiro dia permitido: hoje (ou o início original, ao editar uma liga que já começou)
    var minDate: Date = Calendar.current.startOfDay(for: .now)
    @State private var open = false
    @State private var draftStart = Date.now
    @State private var draftEnd: Date?
    @State private var draftHasEnd = true

    private var cal: Calendar { .current }

    var body: some View {
        Button {
            draftStart = start
            draftEnd = hasEnd ? end : nil
            draftHasEnd = hasEnd
            open = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.body.weight(.semibold))
                    .frame(width: 40, height: 40)
                    .background(Theme.raised, in: .rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.range(start, hasEnd ? end : nil)).font(.subheadline.weight(.bold))
                    Text(Self.detail(start, hasEnd ? end : nil)).font(.caption).foregroundStyle(Theme.dim)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.dim)
            }
            .contentShape(Rectangle())
            .foregroundStyle(.white)
        }
        .buttonStyle(GMPress())
        .gmSheet(isPresented: $open) { close in sheet(close) }
    }

    private func sheet(_ close: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Período da liga").font(.headline)
                Spacer()
                GMSegmented(options: [(true, "Com fim"), (false, "Sem fim")], selection: $draftHasEnd).frame(width: 180)
            }
            if draftHasEnd {
                GMRangeCalendar(start: $draftStart, end: $draftEnd, minDate: minDate)
                // Atalhos discretos, numa linha só
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach([(7, "1 sem"), (14, "2 sem"), (30, "30 dias"), (60, "60 dias")], id: \.0) { n, label in
                            shortcut(label) { draftEnd = cal.date(byAdding: .day, value: n - 1, to: cal.startOfDay(for: draftStart)) }
                        }
                        shortcut("Fim do mês") {
                            draftEnd = cal.date(byAdding: .day, value: -1, to: cal.dateInterval(of: .month, for: draftStart)!.end)
                        }
                    }
                }
                Text(draftEnd == nil ? "Agora toque no último dia, ou use um atalho." : Self.range(draftStart, draftEnd) + " · " + Self.detail(draftStart, draftEnd))
                    .font(.caption).foregroundStyle(Theme.dim)
            } else {
                GMCalendar(selection: $draftStart, minDate: minDate)
                Text("Começa em \(draftStart.formatted(.dateTime.day().month(.wide))) e não tem data de fim.").font(.caption).foregroundStyle(Theme.dim)
            }
            GMButton("Confirmar", enabled: !draftHasEnd || draftEnd != nil) {
                start = cal.startOfDay(for: draftStart)
                hasEnd = draftHasEnd
                if let e = draftEnd { end = e }
                close()
            }
        }
    }

    private func shortcut(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: { UISelectionFeedbackGenerator().selectionChanged(); action() }) {
            Text(title).font(.caption.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Theme.raised, in: .capsule)
                .foregroundStyle(.white)
        }
        .buttonStyle(GMPress())
    }

    static func range(_ s: Date, _ e: Date?) -> String {
        let f = Date.FormatStyle.dateTime.day().month(.abbreviated)
        guard let e else { return "A partir de \(s.formatted(f))" }
        return "\(s.formatted(f)) → \(e.formatted(f))"
    }

    static func detail(_ s: Date, _ e: Date?) -> String {
        let cal = Calendar.current
        let begins = League.startsText(s)
        guard let e else { return "sem data de fim · \(begins)".capitalizedFirst }
        let n = (cal.dateComponents([.day], from: cal.startOfDay(for: s), to: cal.startOfDay(for: e)).day ?? 0) + 1
        return n == 1 ? "1 dia · \(begins)" : "\(n) dias · \(begins)"
    }
}
