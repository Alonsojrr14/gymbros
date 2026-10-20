import AudioToolbox
import SwiftData
import SwiftUI

// Modo WOD (CrossFit): benchmarks clássicos, cronômetros For Time / AMRAP / EMOM / Tabata
// e histórico de resultados. Cada WOD concluído vira uma atividade de crossfit (XP).

enum WodFormat: Codable, Hashable {
    case forTime(capMinutes: Int?)
    case amrap(minutes: Int)
    case emom(minutes: Int)
    case tabata(rounds: Int)
    /// Blocos com descanso entre eles ("AMRAP 3' / descanso 2'" três vezes): minutos de cada bloco e segundos de descanso
    case intervals(blocks: [Int], rest: Int, emom: Bool)
    /// E2MOM, E3MOM, "a cada 2' durante 10'": um trabalho no começo de cada intervalo (minutos 0 = sem fim)
    case every(seconds: Int, minutes: Int)

    var name: String {
        switch self {
        case .forTime: "For Time"
        case .amrap(let m): "AMRAP \(m) min"
        case .emom(let m): "EMOM \(m) min"
        case .every(let sec, let m): "A cada \(WodFormat.restText(sec))" + (m > 0 ? " · \(m) min" : "")
        case .tabata(let r): "Tabata \(r)×(20s/10s)"
        case .intervals(let b, let rest, let emom):
            (Set(b).count == 1 ? "\(b.count)× \(emom ? "EMOM" : "AMRAP") \(b[0])'" : "\(emom ? "EMOM" : "AMRAP") " + b.map { "\($0)'" }.joined(separator: "+"))
                + (rest > 0 ? " · descanso \(WodFormat.restText(rest))" : "")
        }
    }

    static func restText(_ s: Int) -> String { s % 60 == 0 ? "\(s / 60)'" : "\(s)s" }

    var detail: String {
        switch self {
        case .forTime(let cap): "Complete tudo o mais rápido possível" + (cap.map { " (limite de \($0) min)" } ?? "")
        case .amrap: "O máximo de rodadas e repetições no tempo"
        case .emom: "No começo de cada minuto, faça o trabalho; descanse o que sobrar"
        case .every(let sec, _): "No começo de cada intervalo de \(WodFormat.restText(sec)), faça o trabalho; descanse o que sobrar"
        case .tabata: "20 segundos de esforço máximo, 10 de descanso"
        case .intervals(let b, _, let emom):
            emom ? "\(b.count) blocos de EMOM com descanso entre eles" : "\(b.count) blocos: o máximo de rodadas em cada um, com descanso entre eles"
        }
    }

    /// Resultados de For Time: menor é melhor; nos outros, maior é melhor
    var lowerIsBetter: Bool { if case .forTime = self { true } else { false } }

    var totalSeconds: Int? {
        switch self {
        case .forTime(let cap): cap.map { $0 * 60 }
        case .amrap(let m), .emom(let m): m * 60
        case .tabata(let r): r * 30
        case .intervals(let b, let rest, _): b.reduce(0, +) * 60 + rest * max(b.count - 1, 0)
        case .every(_, let m): m > 0 ? m * 60 : nil
        }
    }

    /// Blocos de trabalho e descanso em sequência, em segundos
    var segments: [WodSegment] {
        guard case .intervals(let b, let rest, _) = self else { return [] }
        return b.enumerated().flatMap { i, m in
            [WodSegment(block: i, rest: false, seconds: m * 60)] + (i < b.count - 1 && rest > 0 ? [WodSegment(block: i, rest: true, seconds: rest)] : [])
        }
    }

    /// Trecho em que está aos `elapsed` segundos e quanto falta nele
    func segment(at elapsed: Int) -> (segment: WodSegment, remaining: Int)? {
        var t = elapsed
        for seg in segments {
            if t < seg.seconds { return (seg, seg.seconds - t) }
            t -= seg.seconds
        }
        return segments.last.map { ($0, 0) }
    }
}

struct WodSegment: Hashable {
    let block: Int
    let rest: Bool
    let seconds: Int
}

struct Wod: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let category: String
    let format: WodFormat
    let lines: [String]
    /// Exercícios da biblioteca que aparecem no WOD (para ver como fazer)
    var exercises: [String] = []
    /// Resto do treino do coach (aquecimento, força, skill…): entra no registro junto com o WOD
    var parts: [WodPart] = []

    static let benchmarks: [Wod] = [
        Wod(id: "fran", name: "Fran", category: "Girls", format: .forTime(capMinutes: 10),
            lines: ["21-15-9 repetições de:", "Thruster (43/30 kg)", "Pull-up"], exercises: ["thruster", "cf-kipping-pull-up"]),
        Wod(id: "grace", name: "Grace", category: "Girls", format: .forTime(capMinutes: 10),
            lines: ["30 clean and jerks (61/43 kg)"], exercises: ["cf-clean-jerk"]),
        Wod(id: "isabel", name: "Isabel", category: "Girls", format: .forTime(capMinutes: 10),
            lines: ["30 snatches (61/43 kg)"], exercises: ["cf-snatch"]),
        Wod(id: "diane", name: "Diane", category: "Girls", format: .forTime(capMinutes: 15),
            lines: ["21-15-9 repetições de:", "Levantamento terra (102/70 kg)", "Handstand push-up"], exercises: ["levantamento-terra", "cf-hspu"]),
        Wod(id: "elizabeth", name: "Elizabeth", category: "Girls", format: .forTime(capMinutes: 15),
            lines: ["21-15-9 repetições de:", "Squat clean (61/43 kg)", "Ring dip"], exercises: ["cf-squat-clean", "cf-ring-dip"]),
        Wod(id: "helen", name: "Helen", category: "Girls", format: .forTime(capMinutes: 20),
            lines: ["3 rodadas de:", "400 m de corrida", "21 kettlebell swings (24/16 kg)", "12 pull-ups"],
            exercises: ["esteira", "kettlebell-swing", "cf-kipping-pull-up"]),
        Wod(id: "cindy", name: "Cindy", category: "Girls", format: .amrap(minutes: 20),
            lines: ["5 pull-ups", "10 flexões", "15 agachamentos"], exercises: ["cf-kipping-pull-up", "flexao", "agachamento-livre-corpo"]),
        Wod(id: "annie", name: "Annie", category: "Girls", format: .forTime(capMinutes: 15),
            lines: ["50-40-30-20-10 repetições de:", "Double unders", "Abdominal (sit-up)"], exercises: ["cf-double-under", "abdominal-completo"]),
        Wod(id: "karen", name: "Karen", category: "Girls", format: .forTime(capMinutes: 15),
            lines: ["150 wall balls (9/6 kg)"], exercises: ["cf-wall-ball"]),
        Wod(id: "jackie", name: "Jackie", category: "Girls", format: .forTime(capMinutes: 15),
            lines: ["1000 m de remo", "50 thrusters (20/15 kg)", "30 pull-ups"], exercises: ["cf-row-cal", "thruster", "cf-kipping-pull-up"]),
        Wod(id: "nancy", name: "Nancy", category: "Girls", format: .forTime(capMinutes: 20),
            lines: ["5 rodadas de:", "400 m de corrida", "15 overhead squats (43/30 kg)"], exercises: ["esteira", "cf-overhead-squat"]),
        Wod(id: "kelly", name: "Kelly", category: "Girls", format: .forTime(capMinutes: 35),
            lines: ["5 rodadas de:", "400 m de corrida", "30 box jumps (60/50 cm)", "30 wall balls (9/6 kg)"],
            exercises: ["esteira", "cf-box-jump", "cf-wall-ball"]),
        Wod(id: "chelsea", name: "Chelsea", category: "Girls", format: .emom(minutes: 30),
            lines: ["A cada minuto:", "5 pull-ups", "10 flexões", "15 agachamentos"], exercises: ["cf-kipping-pull-up", "flexao", "agachamento-livre-corpo"]),
        Wod(id: "murph", name: "Murph", category: "Heróis", format: .forTime(capMinutes: 60),
            lines: ["1 milha (1,6 km) de corrida", "100 pull-ups", "200 flexões", "300 agachamentos", "1 milha (1,6 km) de corrida",
                    "Com colete de 9/6 kg; dá para dividir as repetições"],
            exercises: ["esteira", "cf-kipping-pull-up", "flexao", "agachamento-livre-corpo"]),
        Wod(id: "dt", name: "DT", category: "Heróis", format: .forTime(capMinutes: 20),
            lines: ["5 rodadas de:", "12 levantamentos terra (70/47 kg)", "9 hang power cleans", "6 push jerks"],
            exercises: ["levantamento-terra", "cf-hang-power-clean", "cf-push-jerk"]),
    ]

    static func byID(_ id: String) -> Wod? { benchmarks.first { $0.id == id } }
}

func clock(_ s: Int) -> String {
    s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
}

// MARK: - Lista

struct WodListView: View {
    @Query(sort: \WodResult.date, order: .reverse) private var results: [WodResult]
    @State private var running: Wod?
    @State private var custom = false
    @State private var importing = false

    var body: some View {
        GMScreen("WODs", subtitle: "CrossFit: benchmarks e cronômetro", back: true) {
            GMButton("WOD livre (monte o seu)", icon: "timer", kind: .secondary) { custom = true }
            GMButton("Importar treino do coach", icon: "doc.on.clipboard", kind: .secondary) { importing = true }
            NavigationLink { WodTimelineView() } label: {
                GMRow(icon: "clock.arrow.circlepath", iconTint: Theme.accent, title: "Meus WODs", subtitle: "Linha do tempo", chevron: true)
                    .padding(12).background(Theme.card, in: .rect(cornerRadius: Theme.radius))
            }
            .buttonStyle(GMPress())
            ForEach(["Girls", "Heróis"], id: \.self) { cat in
                GMSection(cat) {
                    let list = Wod.benchmarks.filter { $0.category == cat }
                    ForEach(list) { w in
                        NavigationLink { WodDetailView(wod: w) } label: {
                            GMRow(icon: "flame.fill", iconTint: Theme.streak, title: w.name, subtitle: w.format.name, chevron: true) {
                                if let best = best(w) { Text(best.text).font(.subheadline.bold().monospacedDigit()).foregroundStyle(Theme.accent) }
                            }
                        }
                        .buttonStyle(GMPress())
                        if w.id != list.last?.id { GMDivider() }
                    }
                }
            }
            if !results.isEmpty {
                GMSection("Últimos resultados") {
                    ForEach(results.prefix(10)) { r in
                        GMValueRow(label: "\(r.wodName) · \(r.date.formatted(.dateTime.day().month(.abbreviated)))", value: r.text + (r.rx ? " RX" : ""))
                    }
                }
            }
        }
        .gmModal(isPresented: $custom) { CustomWodView() }
        .gmModal(isPresented: $importing) { ImportWodView() }
    }

    private func best(_ w: Wod) -> WodResult? { results.filter { $0.wodID == w.id }.max { $0.score < $1.score } }
}

struct WodDetailView: View {
    let wod: Wod
    @Query(sort: \WodResult.date, order: .reverse) private var all: [WodResult]
    @State private var running = false
    @State private var info: Exercise?

    var body: some View {
        let results = all.filter { $0.wodID == wod.id }
        let best = results.max { $0.score < $1.score }
        GMScreen(wod.name, subtitle: wod.format.name, back: true) {
            GMCard {
                Text(wod.format.detail).font(.caption).foregroundStyle(Theme.dim)
                ForEach(wod.lines, id: \.self) { Text($0).font(.headline) }
            }
            if !wod.exercises.isEmpty {
                GMSection("Movimentos") {
                    ForEach(wod.exercises.compactMap(Exercise.byID)) { e in
                        GMRow(title: e.name, chevron: true, action: { info = e }) { ExerciseThumb(exercise: e, size: 36) }
                    }
                }
            }
            GMButton("Começar", icon: "play.fill") { running = true }
            if let best {
                GMSection("Seu recorde") {
                    GMValueRow(label: best.date.formatted(date: .abbreviated, time: .omitted), value: best.text + (best.rx ? " RX" : ""))
                }
            }
            if !results.isEmpty {
                GMSection("Histórico") {
                    ForEach(results) { r in GMValueRow(label: r.date.formatted(date: .abbreviated, time: .omitted), value: r.text + (r.rx ? " RX" : "")) }
                }
            }
        }
        .gmModal(isPresented: $running) { WodTimerView(wod: wod) }
        .gmModal(item: $info) { ExerciseInfoView(exercise: $0) }
    }
}

/// WOD montado na hora: formato e tempo
struct CustomWodView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var kind = 1
    @State private var minutes = 12
    @State private var rounds = 8
    @State private var lines = ""
    @State private var start: Wod?

    var body: some View {
        GMModal("WOD livre", confirm: "Montar", onConfirm: {
            let format: WodFormat = switch kind {
            case 0: .forTime(capMinutes: minutes)
            case 1: .amrap(minutes: minutes)
            case 2: .emom(minutes: minutes)
            default: .tabata(rounds: rounds)
            }
            start = Wod(id: "livre", name: "WOD livre", category: "Livre", format: format,
                        lines: lines.split(separator: "\n").map(String.init))
        }) {
            GMSection("Formato") {
                GMChoiceChips(options: [(0, "For Time"), (1, "AMRAP"), (2, "EMOM"), (3, "Tabata")], selection: $kind)
                if kind == 3 {
                    GMStepper(title: "Rodadas", value: $rounds, range: 1...20)
                } else {
                    GMStepper(title: kind == 0 ? "Limite" : "Duração", value: $minutes, range: 1...90, format: { "\($0) min" })
                }
            }
            GMSection("Movimentos (opcional)", footer: "Um por linha, ex.: 10 burpees") {
                GMTextField(placeholder: "10 burpees\n15 kettlebell swings", text: $lines, axis: .vertical)
            }
        }
        .gmModal(item: $start) { WodTimerView(wod: $0) }
    }
}

// MARK: - Cronômetro

struct WodTimerView: View {
    let wod: Wod
    @Environment(\.dismiss) private var dismiss
    @State private var run = WodRun.shared
    @State private var finished: FinishedWod?
    @State private var lastTick = -1
    @State private var confirmQuit = false
    @State private var choosingPlace = false

    /// Com um WOD já em andamento, é ele que aparece (um treino por vez)
    private var s: WodRunState { run.state ?? WodRunState(wod: wod) }
    private var current: Wod { s.wod }
    private var parts: [WodPart] { current.parts }
    /// Treino do coach com partes, ainda sem "Começar treino": mostra o treino todo
    private var overview: Bool { !parts.isEmpty && s.sessionStart == nil }

    private func update(_ change: (inout WodRunState) -> Void) {
        var st = s
        change(&st)
        run.state = st
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
            let now = ctx.date
            let e = s.elapsed(now)
            VStack(spacing: 16) {
                header(now)
                HStack(spacing: 8) {
                    Button { choosingPlace = true } label: {
                        Label(GymLocation.shared.gym(s.gymID)?.name ?? (s.placeAsked ? "Sem local" : "Onde você está?"), systemImage: "mappin.and.ellipse")
                            .font(.caption.bold()).lineLimit(1)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(s.gymID != nil ? Theme.accent.opacity(0.18) : Theme.raised, in: .capsule)
                            .foregroundStyle(s.gymID != nil ? Theme.accent : .white)
                    }
                    .buttonStyle(GMPress())
                    LiveShareChip(workoutID: s.liveID)
                }
                if !parts.isEmpty && !overview { progress(now) }
                if overview {
                    overviewList
                    GMButton("Começar treino", icon: "play.fill") {
                        update { $0.sessionStart = .now; $0.phase = 0; $0.phaseStart = .now }
                    }
                } else if !s.onWod {
                    partView(now)
                } else {
                    wodView(now, e)
                }
            }
            .padding(16)
            .onChange(of: Int(e)) { _, sec in tick(sec) }
            // Live Activity: atualiza quando muda o que ele não calcula sozinho (pausa, rodadas, minuto/fase)
            .task(id: liveKey(e)) { await publishLive(e) }
            .onChange(of: s.countdownEnd.map { $0 <= now } ?? false, initial: true) { _, done in
                if done && s.startedAt == nil { begin() }
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .onAppear {
            run.open(wod)
            UIApplication.shared.isIdleTimerDisabled = true
            // Voltou depois do fim (minimizado ou com o app fechado): encerra na hora
            tick(Int(s.elapsed(.now)))
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .gmSheet(isPresented: $choosingPlace) { close in
            GymChooserView { g in
                update { $0.gymID = g?.uuid; $0.placeAsked = true }
                close()
            }
        }
        .task {
            guard !s.placeAsked else { return }
            switch await PlaceDetector.detect() {
            case .known(let g): update { $0.gymID = g.uuid; $0.placeAsked = true }
            case .ask: choosingPlace = true
            }
        }
        .gmActions(isPresented: $confirmQuit, title: "Sair do treino?",
                   message: s.sessionStart == nil && s.startedAt == nil ? nil : "O tempo não será salvo.", actions: [
            GMAction("Sair sem salvar", icon: "xmark", destructive: true) {
                run.end()
                dismiss()
            }
        ])
        .gmModal(item: $finished) { f in
            WodResultForm(wod: current, seconds: f.seconds, rounds: s.rounds, blockRounds: s.blockRounds, loads: s.loads, gymID: s.gymID, capped: f.capped,
                          startedAt: f.startedAt, openedAt: s.sessionStart ?? s.openedAt) {
                run.end()
                dismiss()
            }
        }
    }

    struct FinishedWod: Identifiable {
        let seconds: Int
        /// For Time encerrado pelo limite
        var capped = false
        /// Início real (o tempo de pausa não está em `seconds`)
        var startedAt: Date?
        var id: Int { seconds }
    }

    private func header(_ now: Date) -> some View {
        HStack {
            GMIconButton(icon: "chevron.down", label: "Minimizar treino") { dismiss() }
            Spacer()
            VStack(spacing: 2) {
                Text(current.name).font(.headline)
                if let start = s.sessionStart {
                    Label("Treino \(clock(Int(now.timeIntervalSince(start))))", systemImage: "stopwatch")
                        .font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(Theme.accent)
                } else {
                    Text(current.format.name).font(.caption).foregroundStyle(Theme.dim)
                }
            }
            Spacer()
            GMIconButton(icon: "xmark", label: "Sair do treino") { confirmQuit = true }
        }
    }

    // MARK: Treino completo

    /// Etapas do treino (partes e o WOD) com o relógio geral; toque numa etapa para pular para ela
    private func progress(_ now: Date) -> some View {
        // Feitas encolhem para o ✓; a atual fica no centro
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(0...parts.count, id: \.self) { i in
                        let title = i < parts.count ? parts[i].title : "WOD"
                        let done = i < s.phase, here = i == s.phase
                        Button { go(to: i) } label: {
                            Group {
                                if done {
                                    Image(systemName: "checkmark").frame(width: 14)
                                } else {
                                    Text(title)
                                }
                            }
                            .font(.caption.bold()).lineLimit(1)
                            .padding(.horizontal, done ? 9 : 12).padding(.vertical, 7)
                            .background(here ? Theme.accent : done ? Theme.accent.opacity(0.15) : Theme.raised, in: .capsule)
                            .foregroundStyle(here ? .black : done ? Theme.accent : Theme.dim)
                        }
                        .buttonStyle(GMPress())
                        .disabled(s.startedAt != nil)
                        .accessibilityLabel(done ? "\(title), feito" : title)
                        .id(i)
                    }
                }
                .padding(.horizontal, 2)
            }
            .scrollClipDisabled()
            .onAppear { proxy.scrollTo(s.phase, anchor: .center) }
            .onChange(of: s.phase) { _, p in withAnimation(.snappy) { proxy.scrollTo(p, anchor: .center) } }
        }
    }

    private func go(to i: Int) {
        guard s.startedAt == nil, i != s.phase else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        update { $0.phase = i; $0.phaseStart = .now; $0.partTimerStart = nil; $0.sessionStart = $0.sessionStart ?? .now }
    }

    private var loadsBinding: Binding<[WodLoad]> {
        Binding(get: { s.loads }, set: { v in update { $0.loads = v } })
    }

    private var overviewList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, p in partCard(p) }
                wodCard
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func partCard(_ p: WodPart) -> some View {
        GMCard {
            Text(p.title.uppercased()).font(.caption.weight(.bold)).foregroundStyle(Theme.dim)
            ForEach(Array(p.lines.enumerated()), id: \.offset) { Text($0.element).font(.subheadline) }
        }
    }

    @ViewBuilder
    private var wodCard: some View {
        if !current.lines.isEmpty {
            GMCard {
                if !parts.isEmpty { Text("WOD · \(current.format.name)").font(.caption.weight(.bold)).foregroundStyle(Theme.accent) }
                if chipper && s.startedAt != nil {
                    // Chipper: risca cada movimento ao terminar
                    ForEach(Array(current.lines.enumerated()), id: \.offset) { i, line in
                        let done = s.checked.contains(i)
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            update { if let k = $0.checked.firstIndex(of: i) { $0.checked.remove(at: k) } else { $0.checked.append(i) } }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: done ? "checkmark.circle.fill" : "circle").foregroundStyle(done ? Theme.accent : Theme.dim)
                                Text(line).font(.subheadline.weight(.semibold)).strikethrough(done).foregroundStyle(done ? Theme.dim : .white)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(GMPress())
                    }
                } else {
                    ForEach(Array(current.lines.enumerated()), id: \.offset) { Text($0.element).font(.subheadline.weight(.semibold)) }
                }
            }
        }
    }

    private var chipper: Bool { WodScheme.isChipper(current) }

    /// Movimentos de cada bloco do WOD em blocos (nil se as linhas não baterem com os blocos)
    private var blockGroups: [[String]]? {
        guard case .intervals(let b, _, _) = current.format else { return nil }
        let g = WodScheme.blocks(current.lines)
        return g.count == b.count ? g : nil
    }

    /// Blocos lado a lado: o atual em destaque (no descanso, o próximo), os feitos apagados
    private func blockList(_ groups: [[String]], now: Date, _ e: TimeInterval) -> some View {
        let seg = s.startedAt == nil ? nil : current.format.segment(at: Int(e))?.segment
        let active = seg.map { $0.rest ? $0.block + 1 : $0.block } ?? 0
        guard case .intervals(let b, let rest, let emom) = current.format else { return AnyView(EmptyView()) }
        return AnyView(ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(groups.indices, id: \.self) { i in
                        let here = i == active, done = i < active
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("BLOCO \(i + 1)").font(.caption.weight(.heavy))
                                Spacer()
                                Text("\(emom ? "EMOM" : "AMRAP") \(b[i])'").font(.caption.weight(.bold)).foregroundStyle(Theme.dim)
                            }
                            .foregroundStyle(here ? Theme.accent : Theme.dim)
                            ForEach(Array(groups[i].enumerated()), id: \.offset) { _, line in
                                Text(line).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                            }
                            if i < groups.count - 1 && rest > 0 {
                                Spacer(minLength: 0)
                                Label("Descanso \(WodFormat.restText(rest))", systemImage: "pause.circle")
                                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.warning.opacity(seg?.rest == true && seg?.block == i ? 1 : 0.6))
                            }
                        }
                        .padding(14)
                        .frame(width: 230, alignment: .topLeading)
                        .frame(maxHeight: .infinity, alignment: .topLeading)
                        .background(Theme.card, in: .rect(cornerRadius: Theme.radius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(here ? Theme.accent : .clear, lineWidth: 2))
                        .opacity(done ? 0.45 : 1)
                        .id(i)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .scrollClipDisabled()
            .onChange(of: active, initial: true) { _, i in withAnimation(.snappy) { proxy.scrollTo(i, anchor: .leading) } }
        })
    }

    @ViewBuilder
    private func partView(_ now: Date) -> some View {
        let p = parts[s.phase]
        VStack(spacing: 4) {
            Text(p.title).font(.title3.bold())
            big(clock(Int(now.timeIntervalSince(s.phaseStart ?? now))))
            Text("nesta parte").font(.caption).foregroundStyle(Theme.dim)
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(p.lines.enumerated()), id: \.offset) { Text($0.element).font(.headline) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Theme.card, in: .rect(cornerRadius: Theme.radius))
                PartTimerCard(lines: p.lines, start: Binding(get: { s.partTimerStart }, set: { v in update { $0.partTimerStart = v } }), now: now)
                WodLoadsEditor(loads: loadsBinding, part: s.phase, lines: p.lines)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        let next = s.phase + 1 < parts.count ? parts[s.phase + 1].title : nil
        GMButton(next.map { "Próxima: \($0)" } ?? "Ir para o WOD", icon: next == nil ? "flame.fill" : "forward.fill") {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            update { $0.phase += 1; $0.phaseStart = .now; $0.partTimerStart = nil }
        }
    }

    // MARK: WOD

    @ViewBuilder
    private func wodView(_ now: Date, _ e: TimeInterval) -> some View {
        if let groups = blockGroups {
            blockList(groups, now: now, e)
        } else if !current.lines.isEmpty {
            ScrollView { wodCard }.scrollBounceBehavior(.basedOnSize).frame(maxHeight: s.startedAt == nil ? 260 : 180)
        }
        Spacer(minLength: 0)
        if let end = s.countdownEnd, end > now {
            Text("\(Int(end.timeIntervalSince(now).rounded(.up)))")
                .gmFont(120, weight: .heavy, design: .rounded, relativeTo: .largeTitle)
                .lineLimit(1).minimumScaleFactor(0.4)
                .foregroundStyle(Theme.accent)
            Text("Prepare-se").font(.title3.bold())
        } else {
            display(e, now)
        }
        Spacer(minLength: 0)
        controls(e)
    }

    @ViewBuilder
    private func display(_ e: TimeInterval, _ now: Date) -> some View {
        let sec = Int(e)
        switch current.format {
        case .forTime(let cap):
            big(clock(sec))
            Text(cap.map { "limite \($0):00" } ?? "cronômetro").foregroundStyle(Theme.dim)
            if chipper {
                Text("\(s.checked.count) de \(current.lines.count) feitos").font(.title3.bold())
            } else {
                roundCounter(now)
            }
        case .amrap(let m):
            big(clock(max(m * 60 - sec, 0)))
            Text("restantes de \(m):00").foregroundStyle(Theme.dim)
            roundCounter(now)
        case .emom(let m):
            let minute = min(sec / 60 + 1, m)
            big(clock(60 - sec % 60))
            Text("Minuto \(minute) de \(m)").font(.title3.bold())
        case .every(let every, let m):
            big(clock(every - sec % every))
            Text("Intervalo \(sec / every + 1)" + (m > 0 ? " de \(max(m * 60 / every, 1))" : "")).font(.title3.bold())
            Text("a cada \(clock(every))").foregroundStyle(Theme.dim)
        case .tabata(let r):
            let round = min(sec / 30 + 1, r)
            let work = sec % 30 < 20
            big(clock(work ? 20 - sec % 30 : 30 - sec % 30))
                .foregroundStyle(work ? Theme.accent : Theme.warning)
            Text(work ? "ESFORÇO" : "DESCANSO").font(.title2.weight(.heavy)).foregroundStyle(work ? Theme.accent : Theme.warning)
            Text("Rodada \(round) de \(r)").foregroundStyle(Theme.dim)
        case .intervals(let b, _, let emom):
            segmentBar(sec)
            if let (seg, remaining) = current.format.segment(at: sec) {
                big(clock(remaining)).foregroundStyle(seg.rest ? Theme.warning : .white)
                if seg.rest {
                    Text("DESCANSO").font(.title2.weight(.heavy)).foregroundStyle(Theme.warning)
                    Text("Próximo: bloco \(seg.block + 2) de \(b.count)").foregroundStyle(Theme.dim)
                } else {
                    Text("Bloco \(seg.block + 1) de \(b.count)").font(.title3.bold())
                    if emom {
                        Text("Minuto \(min((seg.seconds - remaining) / 60 + 1, b[seg.block])) de \(b[seg.block])").foregroundStyle(Theme.dim)
                    } else {
                        roundCounter(now)
                    }
                }
            }
        }
    }

    /// Linha do tempo do WOD em blocos: trabalho em verde, descanso em amarelo, preenchendo com o tempo
    private func segmentBar(_ sec: Int) -> some View {
        let segs = current.format.segments
        let total = max(segs.reduce(0) { $0 + $1.seconds }, 1)
        return GeometryReader { geo in
            let gap: CGFloat = 4
            let width = geo.size.width - gap * CGFloat(max(segs.count - 1, 0))
            HStack(spacing: gap) {
                ForEach(Array(segs.enumerated()), id: \.offset) { i, seg in
                    let startAt = segs.prefix(i).reduce(0) { $0 + $1.seconds }
                    let fill = min(max(Double(sec - startAt) / Double(seg.seconds), 0), 1)
                    let tint = seg.rest ? Theme.warning : Theme.accent
                    Capsule().fill(tint.opacity(0.2))
                        .overlay(alignment: .leading) {
                            Capsule().fill(tint).frame(width: width * CGFloat(seg.seconds) / CGFloat(total) * fill)
                        }
                        .frame(width: width * CGFloat(seg.seconds) / CGFloat(total))
                }
            }
        }
        .frame(height: 8)
        .padding(.horizontal, 8)
        .accessibilityHidden(true)
    }

    private func big(_ text: String) -> some View {
        Text(text)
            .gmFont(92, weight: .heavy, design: .rounded, mono: true, relativeTo: .largeTitle)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .contentTransition(.numericText())
    }

    @ViewBuilder
    private func roundCounter(_ now: Date) -> some View {
        if s.startedAt == nil {
            if let total = current.format.totalSeconds {
                Text("\(durationText(max(total / 60, 1))) no total").font(.subheadline).foregroundStyle(Theme.dim).padding(.top, 8)
            }
        } else {
            counterRow(now)
        }
    }

    private func counterRow(_ now: Date) -> some View {
        HStack(spacing: 14) {
            GMIconButton(icon: "minus", size: 44, label: "Tirar rodada") { update { $0.removeRound() } }
            VStack(spacing: 0) {
                Text("\(s.roundsShown(now))").font(.largeTitle.bold().monospacedDigit())
                Text(roundsCaption(now)).font(.caption).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
            }
            .frame(minWidth: 80)
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                update { $0.addRound() }
            } label: {
                Image(systemName: "plus").font(.title2.bold()).frame(width: 64, height: 64)
                    .background(Theme.accent, in: .circle).foregroundStyle(.black)
            }
            .buttonStyle(GMPress())
        }
        .padding(.top, 8)
    }

    /// For Time em rodadas (RFT) mostra a meta; escada (21-15-9) mostra as reps da rodada atual
    private func roundsCaption(_ now: Date) -> String {
        let done = s.roundsShown(now)
        guard case .forTime = current.format else { return "rodadas" }
        if let ladder = WodScheme.ladder(current.lines) {
            return done < ladder.count ? "rodadas de \(ladder.count)\nagora: \(ladder[done]) reps" : "rodadas de \(ladder.count)\nterminou!"
        }
        if let n = WodScheme.rounds(current.lines) { return done < n ? "rodadas de \(n)" : "rodadas de \(n)\nterminou!" }
        return "rodadas"
    }

    @ViewBuilder
    private func controls(_ e: TimeInterval) -> some View {
        if s.startedAt == nil {
            GMButton(s.countdownEnd == nil ? (parts.isEmpty ? "Começar (10 s)" : "Começar WOD (10 s)") : "Começando…",
                     icon: "play.fill", enabled: s.countdownEnd == nil) {
                update { $0.countdownEnd = Date.now.addingTimeInterval(10) }
            }
        } else {
            HStack(spacing: 10) {
                GMButton(s.pausedAt == nil ? "Pausar" : "Continuar", icon: s.pausedAt == nil ? "pause.fill" : "play.fill", kind: .secondary) {
                    update {
                        if let p = $0.pausedAt { $0.pausedTotal += Date.now.timeIntervalSince(p); $0.pausedAt = nil } else { $0.pausedAt = .now }
                    }
                }
                GMButton("Terminar", icon: "flag.checkered") { finish(e) }
            }
        }
    }

    // MARK: Live Activity

    private var showsRounds: Bool {
        switch current.format {
        case .forTime, .amrap: true
        case .intervals(_, _, let emom): !emom
        default: false
        }
    }

    private func label(_ e: TimeInterval) -> String {
        let sec = Int(e)
        switch current.format {
        case .forTime(let cap): return cap.map { "Limite \($0):00" } ?? "For Time"
        case .amrap(let m): return "AMRAP \(m) min"
        case .emom(let m): return "Minuto \(min(sec / 60 + 1, m)) de \(m)"
        case .every(let every, let m): return "Intervalo \(sec / every + 1)" + (m > 0 ? " de \(max(m * 60 / every, 1))" : "")
        case .tabata(let r): return "Rodada \(min(sec / 30 + 1, r)) de \(r) · " + (sec % 30 < 20 ? "ESFORÇO" : "DESCANSO")
        case .intervals(let b, _, _):
            guard let seg = current.format.segment(at: sec)?.segment else { return current.format.name }
            return seg.rest ? "Descanso · próximo bloco \(seg.block + 2) de \(b.count)" : "Bloco \(seg.block + 1) de \(b.count)"
        }
    }

    private func liveKey(_ e: TimeInterval) -> String {
        "\(s.startedAt?.timeIntervalSince1970 ?? 0)|\(s.pausedAt != nil)|\(s.roundsShown(.now))|\(label(e))|\(s.pausedTotal)"
    }

    private func publishLive(_ e: TimeInterval) async {
        guard s.startedAt != nil, finished == nil else { return }
        let start = Date.now.addingTimeInterval(-e)
        var end: Date?
        let sec = Int(e)
        switch current.format {
        case .forTime: end = nil
        // EMOM e Tabata: contagem até o fim do minuto/fase atual; blocos: até o fim do bloco ou descanso; AMRAP: até o fim do tempo
        case .emom: end = start.addingTimeInterval(TimeInterval((sec / 60 + 1) * 60))
        case .every(let every, _): end = start.addingTimeInterval(TimeInterval((sec / every + 1) * every))
        case .tabata: end = start.addingTimeInterval(TimeInterval(sec / 30 * 30 + (sec % 30 < 20 ? 20 : 30)))
        case .intervals: end = current.format.segment(at: sec).map { start.addingTimeInterval(TimeInterval(sec + $0.remaining)) }
        case .amrap: end = current.format.totalSeconds.map { start.addingTimeInterval(TimeInterval($0)) }
        }
        let state = WodAttributes.ContentState(
            countsDown: end != nil, start: start, end: end,
            pausedText: s.pausedAt != nil ? clock(Int(e)) : nil,
            rounds: s.roundsShown(.now), showRounds: showsRounds, label: label(e))
        await LiveWod.show(name: current.name, format: current.format.name, state: state)
    }

    // MARK: Lógica

    private func begin() {
        // Contagem que acabou com a tela fechada: o WOD começou no fim dela
        update { $0.startedAt = min($0.countdownEnd ?? .now, .now) }
        beep(long: true)
    }

    /// Avisos sonoros e vibração nas viradas (minuto do EMOM, troca do Tabata e dos blocos, fim do tempo)
    private func tick(_ sec: Int) {
        guard s.startedAt != nil, s.pausedAt == nil, sec != lastTick else { return }
        lastTick = sec
        if let total = current.format.totalSeconds, sec >= total { return finish(TimeInterval(total)) }
        switch current.format {
        case .emom:
            if sec > 0 && sec % 60 == 0 { beep(long: true) } else if sec % 60 >= 57 { beep(long: false) }
        case .every(let every, _):
            if sec > 0 && sec % every == 0 { beep(long: true) } else if sec % every >= every - 3 { beep(long: false) }
        case .tabata:
            if sec % 30 == 0 || sec % 30 == 20 { beep(long: true) }
        case .amrap(let m):
            if m * 60 - sec <= 3 { beep(long: false) }
        case .intervals(_, _, let emom):
            guard let (seg, remaining) = current.format.segment(at: sec) else { break }
            let into = seg.seconds - remaining
            if sec > 0 && into == 0 { beep(long: true) }
            else if remaining <= 3 || (emom && !seg.rest && into % 60 >= 57) { beep(long: false) }
            else if emom && !seg.rest && into > 0 && into % 60 == 0 { beep(long: true) }
        case .forTime:
            break
        }
    }

    private func finish(_ e: TimeInterval) {
        guard finished == nil else { return }
        let total = current.format.totalSeconds.map { min(e, TimeInterval($0)) } ?? e
        update { st in
            if st.pausedAt == nil { st.pausedAt = st.startedAt?.addingTimeInterval(total + st.pausedTotal) ?? .now }
        }
        Task { await LiveWod.end() }
        beep(long: true)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        // For Time que chegou no limite: é CAP, não "terminou no tempo-limite"
        var capped = false
        if case .forTime(let cap?) = current.format, Int(total) >= cap * 60 { capped = true }
        finished = FinishedWod(seconds: max(Int(total), 1), capped: capped, startedAt: s.startedAt)
    }

    private func beep(long: Bool) {
        AudioServicesPlaySystemSound(long ? 1005 : 1057)
        UIImpactFeedbackGenerator(style: long ? .heavy : .light).impactOccurred()
    }
}

// MARK: - Resultado

struct WodResultForm: View {
    let wod: Wod
    let seconds: Int
    let rounds: Int
    /// Rodadas contadas em cada bloco (WOD em blocos)
    var blockRounds: [Int] = []
    /// Cargas registradas durante o treino (ajustáveis aqui)
    var loads: [WodLoad] = []
    var gymID: UUID? = nil
    /// For Time encerrado pelo limite
    var capped = false
    /// Início real do WOD (com pausas, `seconds` sozinho não diz quando começou)
    var startedAt: Date? = nil
    /// Quando o treino abriu (antes do aquecimento): a atividade cobre o treino completo, não só o WOD
    var openedAt: Date? = nil
    let onDone: () -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var roundsDone = 0
    @State private var extraReps = 0
    @State private var rx = true
    @State private var effort = 8
    @State private var note = ""
    @State private var leagues: Set<UUID> = []
    @State private var photo: Data?
    @State private var blocked = false
    @State private var minutes = 0
    /// O que foi feito em cada parte do treino (cargas, reps), na ordem de `wod.parts`
    @State private var partResults: [String] = []
    @State private var loadsDone: [WodLoad] = []
    @State private var blocksDone: [Int] = []
    @State private var blockReps: [Int] = []

    private var wodStart: Date { startedAt ?? Date.now.addingTimeInterval(-TimeInterval(seconds)) }
    private var start: Date { min(openedAt ?? wodStart, wodStart) }
    private var wodMinutes: Int { max(seconds / 60, 1) }

    var body: some View {
        GMModal("Resultado", confirm: "Salvar", confirmEnabled: hasPostDestination(leagues), onConfirm: save) {
            GMCard {
                Text(wod.name).font(.title2.weight(.heavy))
                switch wod.format {
                case .forTime where capped:
                    Text("CAP").gmFont(48, weight: .heavy, design: .rounded, relativeTo: .largeTitle).foregroundStyle(Theme.warning)
                    Text("Tempo esgotado no limite de \(clock(seconds)): não conta como terminado.").font(.caption).foregroundStyle(Theme.dim)
                    GMStepper(title: "Repetições feitas", value: $extraReps, range: 0...2000)
                case .forTime:
                    Text(clock(seconds)).gmFont(48, weight: .heavy, design: .rounded, mono: true, relativeTo: .largeTitle).lineLimit(1).minimumScaleFactor(0.5).foregroundStyle(Theme.accent)
                case .amrap:
                    GMStepper(title: "Rodadas", value: $roundsDone, range: 0...200)
                    GMStepper(title: "Repetições extras", value: $extraReps, range: 0...500)
                case .intervals(let b, _, false):
                    ForEach(b.indices, id: \.self) { i in
                        if i > 0 { GMDivider() }
                        Text("Bloco \(i + 1) · AMRAP \(b[i])'").font(.subheadline.weight(.bold))
                        GMStepper(title: "Rodadas", value: binding($blocksDone, i), range: 0...200)
                        GMStepper(title: "Repetições extras", value: binding($blockReps, i), range: 0...500)
                    }
                default:
                    Text("Concluído em \(clock(seconds))").font(.headline).foregroundStyle(Theme.accent)
                }
            }
            if !wod.parts.isEmpty {
                GMSection("Treino completo", footer: "As cargas registradas e as observações vão para o post junto com o WOD.") {
                    ForEach(Array(wod.parts.enumerated()), id: \.offset) { i, part in
                        if i > 0 { GMDivider() }
                        Text(part.title).font(.subheadline.weight(.bold))
                        Text(part.lines.joined(separator: "\n")).font(.caption).foregroundStyle(Theme.dim)
                        GMTextField(placeholder: "Observação da parte (opcional)", text: Binding(
                            get: { partResults.indices.contains(i) ? partResults[i] : "" },
                            set: { if partResults.indices.contains(i) { partResults[i] = $0 } }), axis: .vertical)
                    }
                }
            }
            ForEach(Array(wod.parts.enumerated()), id: \.offset) { i, part in
                if !WodLoads.weighted(part.lines).isEmpty || loadsDone.contains(where: { $0.part == i }) {
                    WodLoadsEditor(loads: $loadsDone, part: i, lines: part.lines, title: "Cargas · \(part.title)")
                }
            }
            WodLoadsEditor(loads: $loadsDone, part: wod.parts.count, lines: wod.lines, title: wod.parts.isEmpty ? "Cargas" : "Cargas · WOD")
            GMSection("Duração do treino", footer: "Do começo do treino até agora. O WOD em si levou \(durationText(wodMinutes)).") {
                GMStepper(value: $minutes, range: 1...Game.maxMinutes, step: 5, format: durationText)
                    .frame(maxWidth: .infinity)
            }
            GMSection(footer: "RX: com as cargas e movimentos prescritos, sem adaptação.") {
                GMToggle(title: "RX", isOn: $rx)
            }
            GMSection { GMEffortPicker(value: $effort) }
            GMSection("Observação") {
                GMTextField(placeholder: "Carga usada, adaptações…", text: $note, axis: .vertical)
                if blocked { ContentBlockedNote() }
            }
            LeaguePostSection(selected: $leagues, photo: $photo)
        }
        .onAppear {
            roundsDone = rounds
            loadsDone = loads
            if case .intervals(let b, _, _) = wod.format {
                blocksDone = b.indices.map { blockRounds.indices.contains($0) ? blockRounds[$0] : 0 }
                blockReps = Array(repeating: 0, count: b.count)
            }
            partResults = Array(repeating: "", count: wod.parts.count)
            minutes = min(max(Int(Date.now.timeIntervalSince(start) / 60), wodMinutes), Game.maxMinutes)
        }
        .onChange(of: note + partResults.joined()) { blocked = false }
    }

    private func save() {
        let post = postText
        if !leagues.isEmpty && !ContentFilter.allows(post) {
            blocked = true
            return
        }
        let r = WodResult(wodID: wod.id, wodName: wod.name, formatName: wod.format.name)
        switch wod.format {
        case .forTime:
            r.seconds = seconds
            if capped { r.capped = true; r.reps = extraReps }
        case .amrap: r.rounds = roundsDone; r.reps = extraReps
        case .intervals(_, _, false): r.rounds = blocksDone.reduce(0, +); r.reps = blockReps.reduce(0, +)
        default: break
        }
        r.rx = rx
        r.note = note
        // Começa quando o treino abriu (aquecimento, força…); `seconds` é só o tempo ativo do WOD
        let activity = Activity(kind: .crossfit, date: start, minutes: max(minutes, wodMinutes), effort: effort, note: "\(wod.name) · \(r.text)")
        activity.gymUUID = gymID
        context.insert(activity)
        r.activityUUID = activity.uuid
        context.insert(r)
        WodLoads.save(loadsDone, title: wod.parts.isEmpty ? wod.name : "\(wod.name) · cargas", activity: activity, context: context)
        ActivitySplits.stamp(activity, context: context)
        postCheckIns(activity: activity, leagues: leagues, title: "\(wod.name) · \(r.text)\(rx ? " RX" : "")", note: post, photo: photo, context: context)
        try? context.save()
        PRBook.reload()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
        onDone()
    }

    private func binding(_ list: Binding<[Int]>, _ i: Int) -> Binding<Int> {
        Binding(get: { list.wrappedValue.indices.contains(i) ? list.wrappedValue[i] : 0 },
                set: { if list.wrappedValue.indices.contains(i) { list.wrappedValue[i] = $0 } })
    }

    /// Post com o treino completo: cada parte com o que foi feito, depois a observação
    private var postText: String {
        let parts = wod.parts.enumerated().compactMap { i, p -> String? in
            let typed = partResults.indices.contains(i) ? partResults[i].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            let done = [WodLoads.text(loadsDone.filter { $0.part == i }), typed].filter { !$0.isEmpty }.joined(separator: " · ")
            return done.isEmpty ? nil : "\(p.title): \(done)"
        }
        let wodLoads = WodLoads.text(loadsDone.filter { $0.part == wod.parts.count })
        var blocks: [String] = []
        if case .intervals(_, _, false) = wod.format {
            blocks = blocksDone.indices.map { i in
                let reps = blockReps.indices.contains(i) ? blockReps[i] : 0
                return "Bloco \(i + 1): \(blocksDone[i]) rodadas" + (reps > 0 ? " + \(reps)" : "")
            }
        }
        return (parts + blocks + (wodLoads.isEmpty ? [] : ["Cargas do WOD: " + wodLoads]) + [note.trimmingCharacters(in: .whitespacesAndNewlines)]).filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
