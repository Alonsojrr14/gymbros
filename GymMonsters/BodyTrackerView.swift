import Charts
import SwiftData
import SwiftUI

struct BodyTrackerView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BodyEntry.date, order: .reverse) private var entries: [BodyEntry]
    @State private var adding = false
    @State private var editing: BodyEntry?
    @State private var menu: BodyEntry?
    @State private var measure: Measure?
    @State private var importing = false
    @State private var message: String?

    var body: some View {
        let weights = entries.filter { $0.weight != nil }.reversed()
        GMScreen("Peso e medidas", back: true) {
            GMIconButton(icon: "plus") { adding = true }
        } content: {
            GMSection("Peso (kg)") {
                if let last = weights.last?.weight {
                    HStack(alignment: .firstTextBaseline) {
                        Text(Progression.fmt(last)).font(.system(size: 40, weight: .heavy, design: .rounded))
                        Text("kg").foregroundStyle(Theme.dim)
                        Spacer()
                        if let first = weights.first?.weight, weights.count > 1 {
                            let diff = last - first
                            Text((diff >= 0 ? "+" : "") + Progression.fmt((diff * 10).rounded() / 10) + " kg no período")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.dim)
                        }
                    }
                }
                if weights.count >= 2 {
                    Chart(Array(weights), id: \.uuid) { e in
                        LineMark(x: .value("Data", e.date), y: .value("Peso", e.weight ?? 0))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(Theme.accent)
                        PointMark(x: .value("Data", e.date), y: .value("Peso", e.weight ?? 0))
                            .foregroundStyle(Theme.accent)
                            .symbolSize(20)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 200)
                } else {
                    Text(weights.isEmpty ? "Registre seu peso para acompanhar a evolução." : "O gráfico aparece a partir do segundo registro.")
                        .font(.subheadline).foregroundStyle(Theme.dim)
                }
                GMButton("Importar peso do Apple Saúde", icon: "heart", kind: .secondary, small: true) {
                    Task { await importHealth() }
                }
                if let message { Text(message).font(.caption).foregroundStyle(Theme.dim) }
            }

            let withMeasures = entries.filter(\.hasMeasures)
            if !withMeasures.isEmpty {
                GMSection("Medidas (cm)") {
                    ForEach(Measure.allCases) { m in
                        let series = withMeasures.compactMap { e in m.value(e).map { (e.date, $0) } }
                        if let latest = series.first {
                            GMRow(title: m.name, subtitle: series.count > 1 ? variation(series) : nil, chevron: series.count > 1,
                                  action: series.count > 1 ? { measure = m } : nil) {
                                Text("\(Progression.fmt(latest.1)) cm").font(.subheadline.bold().monospacedDigit())
                            }
                        }
                    }
                }
            }

            if !entries.isEmpty {
                GMSection("Registros") {
                    ForEach(entries) { e in
                        GMRow(title: e.date.formatted(.dateTime.day().month(.abbreviated).year()),
                              subtitle: summary(e), action: { menu = e }) {
                            if e.healthUUID != nil { Image(systemName: "heart.fill").font(.caption2).foregroundStyle(.pink) }
                        }
                        if e.id != entries.last?.id { GMDivider() }
                    }
                }
            }
        }
        .gmModal(isPresented: $adding) { BodyEntryForm(entry: nil) }
        .gmModal(item: $editing) { BodyEntryForm(entry: $0) }
        .gmActions(isPresented: Binding(get: { menu != nil }, set: { if !$0 { menu = nil } }),
                   title: menu.map { $0.date.formatted(date: .long, time: .omitted) }, actions: [
            GMAction("Editar", icon: "pencil") { editing = menu },
            GMAction("Apagar", icon: "trash", destructive: true) {
                if let e = menu { context.delete(e); try? context.save() }
            },
        ])
        .gmSheet(isPresented: Binding(get: { measure != nil }, set: { if !$0 { measure = nil } })) { _ in
            if let m = measure {
                let series = entries.compactMap { e in m.value(e).map { (date: e.date, v: $0) } }.reversed()
                VStack(alignment: .leading, spacing: 12) {
                    Text(m.name).font(.headline)
                    Chart(Array(series), id: \.date) { p in
                        LineMark(x: .value("Data", p.date), y: .value("cm", p.v)).foregroundStyle(Theme.accent)
                        PointMark(x: .value("Data", p.date), y: .value("cm", p.v)).foregroundStyle(Theme.accent)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 200)
                }
            }
        }
    }

    private func summary(_ e: BodyEntry) -> String {
        var parts: [String] = []
        if let w = e.weight { parts.append("\(Progression.fmt(w)) kg") }
        for m in Measure.allCases { if let v = m.value(e) { parts.append("\(m.name.lowercased()) \(Progression.fmt(v))") } }
        return parts.joined(separator: " · ")
    }

    private func variation(_ series: [(Date, Double)]) -> String {
        guard let new = series.first?.1, let old = series.last?.1 else { return "" }
        let d = ((new - old) * 10).rounded() / 10
        return (d >= 0 ? "+" : "") + Progression.fmt(d) + " cm desde o primeiro registro"
    }

    private func importHealth() async {
        do {
            let n = try await HealthSync.importBodyMass(context: context)
            message = n == 0 ? "Nada novo no Saúde." : "\(n) registro\(n == 1 ? "" : "s") de peso importado\(n == 1 ? "" : "s")."
        } catch {
            message = "Não consegui ler o Saúde: \(error.localizedDescription)"
        }
    }
}

struct BodyEntryForm: View {
    let entry: BodyEntry?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \BodyEntry.date, order: .reverse) private var entries: [BodyEntry]
    @State private var date = Date.now
    @State private var weight: Double?
    @State private var values: [Measure: Double] = [:]

    var body: some View {
        GMModal(entry == nil ? "Novo registro" : "Editar registro", confirm: "Salvar",
                confirmEnabled: weight != nil || !values.isEmpty, onConfirm: save) {
            GMSection { GMDateTimePicker(date: $date) }
            GMSection("Peso") {
                GMDecimalField(title: "Peso", value: $weight, step: 0.1, start: lastWeight)
            }
            GMSection("Medidas (opcional)", footer: "Meça sempre no mesmo horário e do mesmo jeito, para comparar.") {
                ForEach(Measure.allCases) { m in
                    GMDecimalField(title: m.name, value: Binding(get: { values[m] }, set: { values[m] = $0 }),
                                   step: 0.5, unit: "cm", start: lastValue(m))
                    if m != Measure.allCases.last { GMDivider() }
                }
            }
        }
        .onAppear {
            guard let e = entry else { return }
            date = e.date
            weight = e.weight
            for m in Measure.allCases { values[m] = m.value(e) }
        }
    }

    private var lastWeight: Double { entries.compactMap(\.weight).first ?? 70 }
    private func lastValue(_ m: Measure) -> Double { entries.compactMap { m.value($0) }.first ?? 80 }

    private func save() {
        let e = entry ?? BodyEntry(date: date)
        e.date = date
        e.weight = weight
        for m in Measure.allCases { m.set(e, values[m]) }
        if entry == nil { context.insert(e) }
        try? context.save()
        dismiss()
    }
}

// MARK: - Anilhas

struct PlateCalculatorView: View {
    @State var total: Double
    @AppStorage("barWeight") private var bar: Double = 20

    var body: some View {
        let r = Plates.perSide(total: total, bar: bar)
        VStack(spacing: 16) {
            Text("Calculadora de anilhas").font(.headline)
            GMDecimalField(title: "Carga total", value: Binding(get: { total }, set: { total = $0 ?? 0 }), step: 2.5, start: 60)
            GMChoiceChips(title: "Barra", options: Plates.bars.map { ($0, $0 == 0 ? "Sem barra" : "\(Progression.fmt($0)) kg") }, selection: $bar)
            GMCard {
                Text("De cada lado").font(.caption.bold()).foregroundStyle(Theme.dim)
                if r.plates.isEmpty {
                    Text(total <= bar ? "Só a barra." : "—").font(.headline)
                } else {
                    HStack(alignment: .center, spacing: 3) {
                        // Desenho da barra com as anilhas, da maior (perto do centro) para a menor
                        Rectangle().fill(Color.white.opacity(0.4)).frame(width: 30, height: 8)
                        ForEach(Array(r.plates.enumerated()), id: \.offset) { _, p in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(color(p))
                                .frame(width: 12, height: 30 + CGFloat(p) * 3)
                        }
                        Rectangle().fill(Color.white.opacity(0.4)).frame(width: 16, height: 8)
                    }
                    .frame(maxWidth: .infinity)
                    Text(r.plates.map { Progression.fmt($0) }.joined(separator: " + ") + " kg")
                        .font(.headline.monospacedDigit())
                }
                if r.rest > 0.01 {
                    Text("Faltam \(Progression.fmt(r.rest)) kg que não fecham com as anilhas comuns.")
                        .font(.caption).foregroundStyle(Theme.dim)
                }
            }
        }
    }

    private func color(_ p: Double) -> Color {
        switch p {
        case 25: .red
        case 20: .blue
        case 15: .yellow
        case 10: .green
        default: .white.opacity(0.8)
        }
    }
}
