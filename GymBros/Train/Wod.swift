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

    var name: String {
        switch self {
        case .forTime: "For Time"
        case .amrap(let m): "AMRAP \(m) min"
        case .emom(let m): "EMOM \(m) min"
        case .tabata(let r): "Tabata \(r)×(20s/10s)"
        }
    }

    var detail: String {
        switch self {
        case .forTime(let cap): "Complete tudo o mais rápido possível" + (cap.map { " (limite de \($0) min)" } ?? "")
        case .amrap: "O máximo de rodadas e repetições no tempo"
        case .emom: "No começo de cada minuto, faça o trabalho; descanse o que sobrar"
        case .tabata: "20 segundos de esforço máximo, 10 de descanso"
        }
    }

    /// Resultados de For Time: menor é melhor; nos outros, maior é melhor
    var lowerIsBetter: Bool { if case .forTime = self { true } else { false } }

    var totalSeconds: Int? {
        switch self {
        case .forTime(let cap): cap.map { $0 * 60 }
        case .amrap(let m), .emom(let m): m * 60
        case .tabata(let r): r * 30
        }
    }
}

struct Wod: Identifiable, Hashable {
    let id: String
    let name: String
    let category: String
    let format: WodFormat
    let lines: [String]
    /// Exercícios da biblioteca que aparecem no WOD (para ver como fazer)
    var exercises: [String] = []

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
    @State private var startedAt: Date?
    @State private var pausedAt: Date?
    @State private var pausedTotal: TimeInterval = 0
    @State private var countdownEnd: Date?
    @State private var counter = WodCounter()
    @State private var finished: FinishedWod?
    @State private var lastTick = -1
    @State private var confirmQuit = false
    @State private var gymID: UUID?
    @State private var choosingPlace = false
    @State private var placeAsked = false

    private func elapsed(_ now: Date) -> TimeInterval {
        guard let startedAt else { return 0 }
        return (pausedAt ?? now).timeIntervalSince(startedAt) - pausedTotal
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
            let now = ctx.date
            let e = elapsed(now)
            VStack(spacing: 18) {
                HStack {
                    GMIconButton(icon: "xmark") { if startedAt == nil { dismiss() } else { confirmQuit = true } }
                    Spacer()
                    VStack(spacing: 0) {
                        Text(wod.name).font(.headline)
                        Text(wod.format.name).font(.caption).foregroundStyle(Theme.dim)
                    }
                    Spacer()
                    Color.clear.frame(width: 40, height: 40)
                }
                Button { choosingPlace = true } label: {
                    Label(GymLocation.shared.gym(gymID)?.name ?? (placeAsked ? "Sem local" : "Onde você está?"), systemImage: "mappin.and.ellipse")
                        .font(.caption.bold())
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(gymID != nil ? Theme.accent.opacity(0.18) : Theme.raised, in: .capsule)
                        .foregroundStyle(gymID != nil ? Theme.accent : .white)
                }
                .buttonStyle(GMPress())
                if !wod.lines.isEmpty {
                    GMCard { ForEach(wod.lines, id: \.self) { Text($0).font(.subheadline.weight(.semibold)) } }
                }
                Spacer()
                if let end = countdownEnd, end > now {
                    Text("\(Int(end.timeIntervalSince(now).rounded(.up)))")
                        .gmFont(120, weight: .heavy, design: .rounded, relativeTo: .largeTitle)
                        .lineLimit(1).minimumScaleFactor(0.4)
                        .foregroundStyle(Theme.accent)
                    Text("Prepare-se").font(.title3.bold())
                } else {
                    display(e)
                }
                Spacer()
                controls(e)
            }
            .padding(16)
            .onChange(of: Int(e)) { _, sec in tick(sec) }
            // Live Activity: atualiza quando muda o que ele não calcula sozinho (pausa, rodadas, minuto/fase)
            .task(id: liveKey(e)) { await publishLive(e) }
            .onChange(of: countdownEnd.map { $0 <= now } ?? false) { _, done in
                if done && startedAt == nil { begin() }
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            let c = counter
            WorkoutIntentBridge.addRound = {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                c.rounds += 1
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            WorkoutIntentBridge.addRound = nil
            Task { await LiveWod.end() }
        }
        .gmSheet(isPresented: $choosingPlace) { close in
            GymChooserView { g in
                gymID = g?.uuid
                placeAsked = true
                close()
            }
        }
        .task {
            guard !placeAsked else { return }
            switch await PlaceDetector.detect() {
            case .known(let g): gymID = g.uuid; placeAsked = true
            case .ask: choosingPlace = true
            }
        }
        .gmActions(isPresented: $confirmQuit, title: "Sair do WOD?", message: "O tempo não será salvo.", actions: [
            GMAction("Sair sem salvar", icon: "xmark", destructive: true) { dismiss() }
        ])
        .gmModal(item: $finished) { f in
            WodResultForm(wod: wod, seconds: f.seconds, rounds: counter.rounds, gymID: gymID, capped: f.capped, startedAt: f.startedAt) { dismiss() }
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

    // MARK: Mostrador por formato

    @ViewBuilder
    private func display(_ e: TimeInterval) -> some View {
        let s = Int(e)
        switch wod.format {
        case .forTime(let cap):
            big(clock(s))
            Text(cap.map { "limite \($0):00" } ?? "cronômetro").foregroundStyle(Theme.dim)
            roundCounter
        case .amrap(let m):
            big(clock(max(m * 60 - s, 0)))
            Text("restantes de \(m):00").foregroundStyle(Theme.dim)
            roundCounter
        case .emom(let m):
            let minute = min(s / 60 + 1, m)
            big(clock(60 - s % 60))
            Text("Minuto \(minute) de \(m)").font(.title3.bold())
        case .tabata(let r):
            let round = min(s / 30 + 1, r)
            let work = s % 30 < 20
            big(clock(work ? 20 - s % 30 : 30 - s % 30))
                .foregroundStyle(work ? Theme.accent : Theme.warning)
            Text(work ? "ESFORÇO" : "DESCANSO").font(.title2.weight(.heavy)).foregroundStyle(work ? Theme.accent : Theme.warning)
            Text("Rodada \(round) de \(r)").foregroundStyle(Theme.dim)
        }
    }

    private func big(_ text: String) -> some View {
        Text(text)
            .gmFont(92, weight: .heavy, design: .rounded, mono: true, relativeTo: .largeTitle)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .contentTransition(.numericText())
    }

    private var roundCounter: some View {
        HStack(spacing: 14) {
            GMIconButton(icon: "minus", size: 44, label: "Tirar rodada") { counter.rounds = max(counter.rounds - 1, 0) }
            VStack(spacing: 0) {
                Text("\(counter.rounds)").font(.largeTitle.bold().monospacedDigit())
                Text("rodadas").font(.caption).foregroundStyle(Theme.dim)
            }
            .frame(minWidth: 80)
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                counter.rounds += 1
            } label: {
                Image(systemName: "plus").font(.title2.bold()).frame(width: 64, height: 64)
                    .background(Theme.accent, in: .circle).foregroundStyle(.black)
            }
            .buttonStyle(GMPress())
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func controls(_ e: TimeInterval) -> some View {
        if startedAt == nil {
            GMButton(countdownEnd == nil ? "Começar (10 s)" : "Começando…", icon: "play.fill", enabled: countdownEnd == nil) {
                countdownEnd = Date.now.addingTimeInterval(10)
            }
        } else {
            HStack(spacing: 10) {
                GMButton(pausedAt == nil ? "Pausar" : "Continuar", icon: pausedAt == nil ? "pause.fill" : "play.fill", kind: .secondary) {
                    if let p = pausedAt { pausedTotal += Date.now.timeIntervalSince(p); pausedAt = nil } else { pausedAt = .now }
                }
                GMButton("Terminar", icon: "flag.checkered") { finish(e) }
            }
        }
    }

    // MARK: Live Activity

    private var showsRounds: Bool {
        switch wod.format { case .forTime, .amrap: true; default: false }
    }

    private func label(_ e: TimeInterval) -> String {
        let s = Int(e)
        switch wod.format {
        case .forTime(let cap): return cap.map { "Limite \($0):00" } ?? "For Time"
        case .amrap(let m): return "AMRAP \(m) min"
        case .emom(let m): return "Minuto \(min(s / 60 + 1, m)) de \(m)"
        case .tabata(let r): return "Rodada \(min(s / 30 + 1, r)) de \(r) · " + (s % 30 < 20 ? "ESFORÇO" : "DESCANSO")
        }
    }

    private func liveKey(_ e: TimeInterval) -> String {
        "\(startedAt?.timeIntervalSince1970 ?? 0)|\(pausedAt != nil)|\(counter.rounds)|\(label(e))|\(pausedTotal)"
    }

    private func publishLive(_ e: TimeInterval) async {
        guard startedAt != nil, finished == nil else { return }
        let start = Date.now.addingTimeInterval(-e)
        var end: Date?
        if case .forTime = wod.format { end = nil } else {
            // EMOM e Tabata: contagem até o fim do minuto/fase atual; AMRAP: até o fim do tempo
            let s = Int(e)
            switch wod.format {
            case .emom: end = start.addingTimeInterval(TimeInterval((s / 60 + 1) * 60))
            case .tabata: end = start.addingTimeInterval(TimeInterval(s / 30 * 30 + (s % 30 < 20 ? 20 : 30)))
            default: end = wod.format.totalSeconds.map { start.addingTimeInterval(TimeInterval($0)) }
            }
        }
        let state = WodAttributes.ContentState(
            countsDown: end != nil, start: start, end: end,
            pausedText: pausedAt != nil ? clock(Int(e)) : nil,
            rounds: counter.rounds, showRounds: showsRounds, label: label(e))
        await LiveWod.show(name: wod.name, format: wod.format.name, state: state)
    }

    // MARK: Lógica

    private func begin() {
        startedAt = .now
        beep(long: true)
    }

    /// Avisos sonoros e vibração nas viradas (minuto do EMOM, troca do Tabata, fim do tempo)
    private func tick(_ sec: Int) {
        guard startedAt != nil, pausedAt == nil, sec != lastTick else { return }
        lastTick = sec
        switch wod.format {
        case .emom(let m):
            if sec > 0 && sec % 60 == 0 { sec >= m * 60 ? finish(TimeInterval(sec)) : beep(long: true) }
            else if sec % 60 >= 57 { beep(long: false) }
        case .tabata(let r):
            if sec >= r * 30 { finish(TimeInterval(sec)) }
            else if sec % 30 == 0 || sec % 30 == 20 { beep(long: true) }
        case .amrap(let m):
            if sec >= m * 60 { finish(TimeInterval(sec)) } else if m * 60 - sec <= 3 { beep(long: false) }
        case .forTime(let cap):
            if let cap, sec >= cap * 60 { finish(TimeInterval(sec)) }
        }
    }

    private func finish(_ e: TimeInterval) {
        guard finished == nil else { return }
        pausedAt = .now
        Task { await LiveWod.end() }
        beep(long: true)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        // For Time que chegou no limite: é CAP, não "terminou no tempo-limite"
        var capped = false
        if case .forTime(let cap?) = wod.format, Int(e) >= cap * 60 { capped = true }
        finished = FinishedWod(seconds: max(Int(e), 1), capped: capped, startedAt: startedAt)
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
    var gymID: UUID? = nil
    /// For Time encerrado pelo limite
    var capped = false
    /// Início real do WOD (com pausas, `seconds` sozinho não diz quando começou)
    var startedAt: Date? = nil
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

    var body: some View {
        GMModal("Resultado", confirm: "Salvar", onConfirm: save) {
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
                default:
                    Text("Concluído em \(clock(seconds))").font(.headline).foregroundStyle(Theme.accent)
                }
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
        .onAppear { roundsDone = rounds }
        .onChange(of: note) { blocked = false }
    }

    private func save() {
        if !leagues.isEmpty && !ContentFilter.allows(note) {
            blocked = true
            return
        }
        let r = WodResult(wodID: wod.id, wodName: wod.name, formatName: wod.format.name)
        switch wod.format {
        case .forTime:
            r.seconds = seconds
            if capped { r.capped = true; r.reps = extraReps }
        case .amrap: r.rounds = roundsDone; r.reps = extraReps
        default: break
        }
        r.rx = rx
        r.note = note
        // Data = início real; `seconds` é só o tempo ativo (sem as pausas)
        let activity = Activity(kind: .crossfit, date: startedAt ?? Date.now.addingTimeInterval(-TimeInterval(seconds)),
                                minutes: max(seconds / 60, 1), effort: effort, note: "\(wod.name) · \(r.text)")
        activity.gymUUID = gymID
        context.insert(activity)
        r.activityUUID = activity.uuid
        context.insert(r)
        postCheckIns(activity: activity, leagues: leagues, title: "\(wod.name) · \(r.text)\(rx ? " RX" : "")", note: note, photo: photo, context: context)
        try? context.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
        onDone()
    }
}
