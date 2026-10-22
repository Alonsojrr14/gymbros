import SwiftUI

/// Escolha da atividade: todos os tipos do iPhone em linhas compactas que a coroa digital rola,
/// com os usados por último em cima e o resto nas mesmas seções do app do iPhone
struct KindPicker: View {
    @Environment(WorkoutRecorder.self) private var recorder

    var body: some View {
        List {
            let recent = recorder.recent
            if !recent.isEmpty {
                Section("Recentes") {
                    ForEach(recent) { TypeRow(type: $0) }
                }
            }
            ForEach(WorkoutType.Section.allCases, id: \.self) { section in
                Section(section.rawValue) {
                    ForEach(WorkoutType.all.filter { $0.section == section }) { TypeRow(type: $0) }
                }
            }
        }
        .disabled(recorder.phase == .starting)
        .navigationTitle("Registrar")
        .alert(recorder.error ?? "", isPresented: .constant(recorder.error != nil)) {
            Button("OK") { recorder.error = nil }
        }
    }
}

private struct TypeRow: View {
    @Environment(WorkoutRecorder.self) private var recorder
    let type: WorkoutType

    var body: some View {
        Button {
            Task { await recorder.choose(type) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: type.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 32, height: 32)
                    .background(Theme.accent.opacity(0.16), in: .circle)
                Text(type.name)
                    .font(.body)
                    .lineLimit(2).minimumScaleFactor(0.8)
            }
        }
        .listRowBackground(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
        .accessibilityLabel("Começar \(type.name)")
    }
}

/// Atividade em andamento: métricas e controles em páginas lado a lado; depois de encerrar, o esforço
struct RecordingView: View {
    enum Page { case controls, metrics }

    @Environment(WorkoutRecorder.self) private var recorder
    @State private var page = Page.metrics

    var body: some View {
        NavigationStack {
            Group {
                if recorder.phase == .rating {
                    EffortView()
                } else {
                    TabView(selection: $page) {
                        controls.tag(Page.controls)
                        metrics.tag(Page.metrics)
                    }
                    .tabViewStyle(.page)
                }
            }
            .navigationTitle(recorder.kind?.name ?? "")
        }
        .containerBackground(Theme.bg.gradient, for: .navigation)
    }

    private var metrics: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            VStack(alignment: .leading, spacing: 0) {
                Text(Duration.seconds(recorder.elapsed(at: ctx.date)).formatted(.time(pattern: .hourMinuteSecond)))
                    .font(.system(size: 60, weight: .semibold, design: .rounded).monospacedDigit())
                    .lineLimit(1).minimumScaleFactor(0.3)
                    .foregroundStyle(recorder.phase == .paused ? Theme.warning : Theme.accent)
                    .frame(maxHeight: .infinity)
                Metric(symbol: "heart.fill", value: recorder.heartRate.map { "\(Int($0))" } ?? "--", unit: "BPM", tint: Theme.health)
                Metric(symbol: "flame.fill", value: "\(Int(recorder.kcal))", unit: "KCAL", tint: Theme.streak)
                if recorder.kind?.distanceType != nil {
                    Metric(symbol: "point.topleft.down.to.point.bottomright.curvepath",
                           value: String(format: "%.2f", recorder.meters / 1000), unit: "KM", tint: Theme.info)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var controls: some View {
        VStack(spacing: 6) {
            Button {
                recorder.togglePause()
            } label: {
                Label(recorder.phase == .paused ? "Retomar" : "Pausar", systemImage: recorder.phase == .paused ? "play.fill" : "pause.fill")
                    .font(.title3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .tint(Theme.warning)
            Button {
                Task { await recorder.stop() }
            } label: {
                Label("Encerrar", systemImage: "xmark")
                    .font(.title3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .tint(Theme.danger)
        }
        .buttonStyle(.borderedProminent)
    }
}

private struct Metric: View {
    let symbol: String
    let value: String
    let unit: String
    let tint: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value).font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
            Text(unit).font(.caption).foregroundStyle(tint)
            Spacer()
            Image(systemName: symbol).foregroundStyle(tint)
        }
        .lineLimit(1).minimumScaleFactor(0.4)
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Esforço de 1 a 10 na coroa digital, como no iPhone; decide o XP junto com a duração
struct EffortView: View {
    @Environment(WorkoutRecorder.self) private var recorder
    @State private var effort = 6.0
    @State private var saving = false
    @State private var confirmDiscard = false

    var body: some View {
        VStack(spacing: 4) {
            Text("\(Int(effort))")
                .font(.system(size: 120, weight: .bold, design: .rounded).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.3)
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .focusable()
                .digitalCrownRotation($effort, from: 1, through: 10, by: 1, sensitivity: .low, isContinuous: false)
                .accessibilityLabel("Esforço \(Int(effort)) de 10")
            Text("\(effortLabel(Int(effort))) · gire a coroa").font(.caption2).foregroundStyle(Theme.dim)
            HStack(spacing: 6) {
                Button {
                    confirmDiscard = true
                } label: {
                    Image(systemName: "trash").frame(maxHeight: .infinity)
                }
                .tint(Theme.danger)
                .frame(width: 48)
                .accessibilityLabel("Descartar")
                Button {
                    saving = true
                    Task { _ = await recorder.save(effort: Int(effort)) }
                } label: {
                    Label("Salvar", systemImage: "checkmark").font(.headline)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .foregroundStyle(.black)
                .disabled(saving)
            }
            .buttonStyle(.borderedProminent)
            .frame(maxHeight: 48)
        }
        .navigationTitle("Esforço")
        .confirmationDialog("Descartar a atividade?", isPresented: $confirmDiscard) {
            Button("Descartar", role: .destructive) { recorder.discard() }
        }
    }
}
