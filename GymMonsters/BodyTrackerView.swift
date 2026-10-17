import Charts
import PhotosUI
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
    @State private var comparing = false

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

            let withPhotos = entries.filter { $0.photoFront != nil || $0.photoSide != nil }
            GMSection("Fotos de progresso", footer: withPhotos.isEmpty ? "Adicione fotos de frente e de lado num registro (+ lá em cima). Mesmo lugar, luz e pose ajudam a comparar." : nil) {
                if !withPhotos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(withPhotos) { e in
                                Button { editing = e } label: {
                                    VStack(spacing: 4) {
                                        if let d = e.photoFront ?? e.photoSide, let img = UIImage(data: d) {
                                            Color.clear.frame(width: 84, height: 112)
                                                .overlay { Image(uiImage: img).resizable().scaledToFill() }
                                                .clipShape(.rect(cornerRadius: 10))
                                        }
                                        Text(e.date.formatted(.dateTime.day().month(.abbreviated))).font(.caption2).foregroundStyle(Theme.dim)
                                    }
                                }
                                .buttonStyle(GMPress())
                            }
                        }
                    }
                    if withPhotos.count >= 2 {
                        GMButton("Comparar antes e depois", icon: "slider.horizontal.below.rectangle") { comparing = true }
                    }
                }
            }

            if !entries.isEmpty {
                GMSection("Registros") {
                    ForEach(entries) { e in
                        GMRow(title: e.date.formatted(.dateTime.day().month(.abbreviated).year()),
                              subtitle: summary(e), action: { menu = e }) {
                            if e.photoFront != nil || e.photoSide != nil { Image(systemName: "camera.fill").font(.caption2).foregroundStyle(Theme.dim) }
                            if e.healthUUID != nil { Image(systemName: "heart.fill").font(.caption2).foregroundStyle(.pink) }
                        }
                        if e.id != entries.last?.id { GMDivider() }
                    }
                }
            }
        }
        .gmModal(isPresented: $adding) { BodyEntryForm(entry: nil) }
        .gmModal(isPresented: $comparing) { ProgressCompareView() }
        .gmModal(item: $editing) { BodyEntryForm(entry: $0) }
        .gmActions(isPresented: Binding(get: { menu != nil }, set: { if !$0 { menu = nil } }),
                   title: menu.map { $0.date.formatted(date: .long, time: .omitted) }, actions: menu.map { e in [
            GMAction("Editar", icon: "pencil") { editing = e },
            GMAction("Apagar", icon: "trash", destructive: true) {
                context.delete(e)
                try? context.save()
            },
        ] } ?? [])
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
    @State private var front: Data?
    @State private var side: Data?
    @State private var pickFront: PhotosPickerItem?
    @State private var pickSide: PhotosPickerItem?

    var body: some View {
        GMModal(entry == nil ? "Novo registro" : "Editar registro", confirm: "Salvar",
                confirmEnabled: weight != nil || !values.isEmpty || front != nil || side != nil, onConfirm: save) {
            GMSection { GMDateTimePicker(date: $date) }
            GMSection("Peso") {
                GMDecimalField(title: "Peso", value: $weight, step: 0.1, start: lastWeight)
            }
            GMSection("Fotos de progresso (opcional)") {
                HStack(spacing: 10) {
                    photoSlot("Frente", data: $front, pick: $pickFront)
                    photoSlot("Lado", data: $side, pick: $pickSide)
                }
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
            front = e.photoFront
            side = e.photoSide
            for m in Measure.allCases { values[m] = m.value(e) }
        }
        .onChange(of: pickFront) { _, item in load(item) { front = $0 } }
        .onChange(of: pickSide) { _, item in load(item) { side = $0 } }
    }

    private func load(_ item: PhotosPickerItem?, _ set: @escaping (Data?) -> Void) {
        Task { if let d = try? await item?.loadTransferable(type: Data.self) { set(compressedPhoto(d)) } }
    }

    private func photoSlot(_ title: String, data: Binding<Data?>, pick: Binding<PhotosPickerItem?>) -> some View {
        PhotosPicker(selection: pick, matching: .images) {
            ZStack {
                if let d = data.wrappedValue, let img = UIImage(data: d) {
                    Color.clear.overlay { Image(uiImage: img).resizable().scaledToFill() }
                } else {
                    Theme.raised
                    VStack(spacing: 6) {
                        Image(systemName: "camera.fill").font(.title3)
                        Text(title).font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Theme.dim)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 170)
            .clipShape(.rect(cornerRadius: 14))
            .overlay(alignment: .bottomLeading) {
                if data.wrappedValue != nil {
                    Text(title).font(.caption2.bold()).padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.black.opacity(0.6), in: .capsule).foregroundStyle(.white).padding(6)
                }
            }
        }
        .buttonStyle(GMPress())
        .overlay(alignment: .topTrailing) {
            if data.wrappedValue != nil {
                Button { data.wrappedValue = nil; pick.wrappedValue = nil } label: {
                    Image(systemName: "xmark").font(.caption2.bold()).frame(width: 26, height: 26)
                        .background(.black.opacity(0.6), in: .circle).foregroundStyle(.white)
                }
                .buttonStyle(GMPress())
                .padding(6)
            }
        }
    }

    private var lastWeight: Double { entries.compactMap(\.weight).first ?? 70 }
    private func lastValue(_ m: Measure) -> Double { entries.compactMap { m.value($0) }.first ?? 80 }

    private func save() {
        let e = entry ?? BodyEntry(date: date)
        e.date = date
        e.weight = weight
        e.photoFront = front
        e.photoSide = side
        for m in Measure.allCases { m.set(e, values[m]) }
        if entry == nil { context.insert(e) }
        try? context.save()
        dismiss()
    }
}

// MARK: - Comparar fotos

/// Antes × depois com uma divisória que se arrasta
struct ProgressCompareView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \BodyEntry.date) private var all: [BodyEntry]
    @State private var beforeID: UUID?
    @State private var afterID: UUID?
    @State private var side = false
    @State private var split: CGFloat = 0.5

    private var entries: [BodyEntry] { all.filter { (side ? $0.photoSide : $0.photoFront) != nil } }

    var body: some View {
        let before = entries.first { $0.uuid == beforeID } ?? entries.first
        let after = entries.first { $0.uuid == afterID } ?? entries.last
        GMModal("Antes e depois", cancel: "Fechar") {
            GMSegmented(options: [(false, "Frente"), (true, "Lado")], selection: $side)
            if let before, let after, before.uuid != after.uuid,
               let a = image(before), let b = image(after) {
                GeometryReader { geo in
                    let w = geo.size.width
                    ZStack(alignment: .leading) {
                        Color.clear.overlay { Image(uiImage: b).resizable().scaledToFill() }.clipped()
                        Color.clear.overlay { Image(uiImage: a).resizable().scaledToFill() }.clipped()
                            .mask(alignment: .leading) { Rectangle().frame(width: w * split) }
                        Rectangle().fill(.white).frame(width: 3).offset(x: w * split - 1.5)
                        Image(systemName: "arrow.left.and.right")
                            .font(.caption.bold()).frame(width: 34, height: 34)
                            .background(.white, in: .circle).foregroundStyle(.black)
                            .offset(x: w * split - 17)
                    }
                    .overlay(alignment: .topLeading) { tag(before) }
                    .overlay(alignment: .topTrailing) { tag(after) }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { split = min(max($0.location.x / w, 0), 1) })
                }
                .frame(height: 460)
                .clipShape(.rect(cornerRadius: Theme.radius))
                if let wa = before.weight, let wb = after.weight {
                    let d = ((wb - wa) * 10).rounded() / 10
                    Text("\(Progression.fmt(wa)) kg → \(Progression.fmt(wb)) kg (\(d >= 0 ? "+" : "")\(Progression.fmt(d)) kg) em \(days(before, after)) dias")
                        .font(.subheadline.weight(.semibold))
                }
            } else {
                GMEmptyState(icon: "camera", title: "Precisa de duas fotos", message: "Registre fotos de \(side ? "lado" : "frente") em dois dias diferentes.")
            }
            if entries.count >= 2 {
                GMSection("Antes") { picker(selection: $beforeID, current: before) }
                GMSection("Depois") { picker(selection: $afterID, current: after) }
            }
        }
    }

    private func image(_ e: BodyEntry) -> UIImage? { (side ? e.photoSide : e.photoFront).flatMap(UIImage.init(data:)) }

    private func tag(_ e: BodyEntry) -> some View {
        Text(e.date.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits)))
            .font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 4)
            .background(.black.opacity(0.6), in: .capsule).foregroundStyle(.white).padding(10)
    }

    private func days(_ a: BodyEntry, _ b: BodyEntry) -> Int {
        Calendar.current.dateComponents([.day], from: a.date, to: b.date).day ?? 0
    }

    private func picker(selection: Binding<UUID?>, current: BodyEntry?) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(entries) { e in
                    Button { selection.wrappedValue = e.uuid } label: {
                        VStack(spacing: 3) {
                            if let img = image(e) {
                                Color.clear.frame(width: 60, height: 80)
                                    .overlay { Image(uiImage: img).resizable().scaledToFill() }
                                    .clipShape(.rect(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(current?.uuid == e.uuid ? Theme.accent : .clear, lineWidth: 3))
                            }
                            Text(e.date.formatted(.dateTime.day().month(.abbreviated))).font(.caption2).foregroundStyle(Theme.dim)
                        }
                    }
                    .buttonStyle(GMPress())
                }
            }
        }
    }
}

// MARK: - Anilhas

struct PlateCalculatorView: View {
    @State var total: Double
    @AppStorage("barWeight") private var bar: Double = 20

    var body: some View {
        let r = Plates.perSide(total: total, bar: bar)
        let side = r.plates.reduce(0, +)
        VStack(alignment: .leading, spacing: 16) {
            Text("Calculadora de anilhas").font(.headline).frame(maxWidth: .infinity)
            GMDecimalField(title: "Carga total", value: Binding(get: { total }, set: { total = max($0 ?? 0, 0) }), step: 2.5, start: 60,
                           clearable: false)
            GMRuler(value: $total, range: 0...300, step: 2.5)
            GMChoiceChips(title: "Barra", options: Plates.bars.map { ($0, $0 == 0 ? "Sem barra" : "\(Progression.fmt($0)) kg") }, selection: $bar)

            GMCard {
                barbell(r.plates)
                if total <= bar {
                    Text(bar == 0 ? "Escolha uma carga." : total < bar ? "A carga é menor que a barra (\(Progression.fmt(bar)) kg)."
                                                         : "Só a barra: \(Progression.fmt(bar)) kg, sem anilhas.")
                        .font(.subheadline.weight(.semibold))
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        line("Barra", bar == 0 ? "—" : "\(Progression.fmt(bar)) kg")
                        line("Em cada lado", "\(Progression.fmt(side)) kg")
                        Text(grouped(r.plates)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                        GMDivider()
                        line("Total", "\(Progression.fmt(bar)) + 2 × \(Progression.fmt(side)) = \(Progression.fmt(bar + side * 2)) kg")
                    }
                    if r.rest > 0.01 {
                        Text("Sobram \(Progression.fmt(r.rest)) kg que não fecham com as anilhas comuns (25, 20, 15, 10, 5, 2,5 e 1,25 kg).")
                            .font(.caption).foregroundStyle(Theme.dim)
                    }
                }
            }
        }
    }

    /// Barra inteira, com as anilhas espelhadas e o peso escrito embaixo de cada uma
    private func barbell(_ plates: [Double]) -> some View {
        HStack(alignment: .center, spacing: 2) {
            Rectangle().fill(Color.white.opacity(0.4)).frame(width: 10, height: 8)
            ForEach(Array(plates.reversed().enumerated()), id: \.offset) { _, p in plate(p) }
            Rectangle().fill(Color.white.opacity(0.4)).frame(maxWidth: .infinity).frame(height: 8)
            ForEach(Array(plates.enumerated()), id: \.offset) { _, p in plate(p) }
            Rectangle().fill(Color.white.opacity(0.4)).frame(width: 10, height: 8)
        }
        .frame(height: 130)
    }

    private func plate(_ p: Double) -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color(p))
                .frame(width: 14, height: 30 + CGFloat(p) * 3)
            Text(Progression.fmt(p)).font(.system(size: 9, weight: .bold).monospacedDigit()).foregroundStyle(Theme.dim)
        }
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(Theme.dim)
            Spacer()
            Text(value).font(.subheadline.weight(.semibold).monospacedDigit())
        }
    }

    /// "1 de 25 kg + 1 de 15 kg"
    private func grouped(_ plates: [Double]) -> String {
        var counts: [(Double, Int)] = []
        for p in plates {
            if let i = counts.firstIndex(where: { $0.0 == p }) { counts[i].1 += 1 } else { counts.append((p, 1)) }
        }
        return counts.map { "\($0.1) de \(Progression.fmt($0.0)) kg" }.joined(separator: " + ")
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
