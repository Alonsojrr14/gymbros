import SwiftData
import SwiftUI

// Cargas do treino do coach: cada movimento com peso (terra, push jerk, wall ball…) ganha séries de carga × reps;
// os sem peso (corda, burpee, pull up…) ganham séries só de repetições. "x% do PR" vira a carga sugerida.
// No fim tudo vira um treino com séries de verdade, ligado à atividade: entra na progressão, nos recordes e no "Ver séries".

struct WodSet: Codable, Hashable {
    /// Total levantado, com a barra
    var weight: Double
    var reps: Int
    /// Barra usada (nos exercícios de barra); o resto são as anilhas, metade de cada lado
    var bar: Double? = nil

    var perSide: Double { max((weight - (bar ?? 0)) / 2, 0) }
}

/// Barra do box: 20 kg (masculina), 15 kg (feminina), 10 kg (técnica). Lembra a última usada
enum WodBar {
    static let key = "wodBarWeight"
    static let options: [Double] = [20, 15, 10]

    static var current: Double {
        get { UserDefaults.standard.object(forKey: key) == nil ? 20 : UserDefaults.standard.double(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

struct WodLoad: Codable, Hashable {
    var exerciseID: String
    /// Parte do treino (índice em `wod.parts`; `wod.parts.count` é o WOD)
    var part: Int
    var sets: [WodSet] = []
    /// Tirado da lista: os lidos do treino não voltam sozinhos
    var removed: Bool? = nil
}

enum WodLoads {
    /// Movimentos com carga citados nas linhas
    static func weighted(_ lines: [String]) -> [String] {
        WodMovements.ids(lines).filter(isWeighted)
    }

    /// Movimentos para registrar: com carga e, fora do WOD cronometrado, também os sem peso (só repetições)
    static func tracked(_ lines: [String], bodyweight: Bool) -> [String] {
        bodyweight ? WodMovements.ids(lines) : weighted(lines)
    }

    static func isWeighted(_ id: String) -> Bool { Exercise.byID(id)?.type == .weighted }

    /// Reps escritas junto do movimento ("30 DU / 60 SU" → 30 para double under, 60 para corda)
    static func reps(of id: String, in lines: [String]) -> Int? {
        for line in lines {
            for piece in line.components(separatedBy: CharacterSet(charactersIn: "/,+;")) where WodMovements.ids([piece]).contains(id) {
                let t = piece.trimmingCharacters(in: .whitespaces)
                if let n = Int(t.prefix { $0.isNumber }), n > 0 { return n }
            }
        }
        return nil
    }

    /// Percentuais do PR na prescrição, na ordem: "75% do PR", "@80%", "70-75-80% 1RM", "65%/70%" → [0.75…]
    static func percents(in lines: [String]) -> [Double] {
        guard let re = try? NSRegularExpression(pattern: "(\\d{2,3}(?:\\s*%?\\s*[-/–,e]\\s*\\d{2,3})*)\\s*%") else { return [] }
        var out: [Double] = []
        for line in lines {
            for m in re.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
                guard let r = Range(m.range(at: 1), in: line) else { continue }
                out += line[r].split(whereSeparator: { !$0.isNumber }).compactMap { Double($0) }
                    .filter { (30...110).contains($0) }.map { $0 / 100 }
            }
        }
        return out
    }

    /// 1RM estimado do exercício (PRs registrados à mão e séries dos treinos), como total com a barra
    static func oneRM(_ id: String, history: [SessionLog], manual: [SetLog], bar: Double = WodBar.current) -> Double? {
        let ex = Exercise.byID(id)
        let platesOnly = ex?.usesBar == true && !(ex?.weightIncludesBar ?? true)
        let sets = history.flatMap(\.sets).filter { $0.exerciseID == id && $0.done } + manual.filter { $0.exerciseID == id }
        return sets.compactMap { Progression.oneRM(weight: platesOnly ? $0.weight + bar : $0.weight, reps: $0.reps) }.max()
    }

    /// Carga de `pct` do 1RM, arredondada ao incremento (nunca abaixo da barra)
    static func weight(_ pct: Double, of oneRM: Double, exerciseID: String, bar: Double = WodBar.current) -> Double {
        let ex = Exercise.byID(exerciseID)
        let inc = ex?.increment ?? 2.5
        let w = (pct * oneRM / inc).rounded() * inc
        return ex?.usesBar == true ? max(w, bar) : w
    }

    /// Reps da prescrição ("5 REPS", "3x5", "5-4-3-2-1" → 5); sem número, 5
    static func reps(in lines: [String]) -> Int {
        for line in lines {
            if let m = line.range(of: "\\d+\\s*x\\s*(\\d+)", options: [.regularExpression, .caseInsensitive]),
               let n = Int(line[m].split(whereSeparator: { !$0.isNumber }).last ?? "") { return n }
            if let m = line.range(of: "(\\d+)\\s*(?:reps?|repetições|repeticoes)", options: [.regularExpression, .caseInsensitive]),
               let n = Int(line[m].prefix { $0.isNumber }) { return n }
            if let m = line.range(of: "^(\\d+)(?:\\s*-\\s*\\d+)+", options: .regularExpression),
               let n = Int(line[m].prefix { $0.isNumber }) { return n }
        }
        return 5
    }

    /// Próxima série: com "x% do PR" e o PR conhecido, a carga do percentual desta série; senão repete a anterior.
    /// A primeira vem do histórico ou do PR. Sem peso, só as repetições.
    static func next(after sets: [WodSet], exerciseID: String, reps: Int, history: [SessionLog], bar: Double = WodBar.current,
                     percents: [Double] = [], oneRM: Double? = nil) -> WodSet {
        let ex = Exercise.byID(exerciseID)
        guard isWeighted(exerciseID) else { return WodSet(weight: 0, reps: sets.last?.reps ?? reps) }
        if let oneRM, !percents.isEmpty {
            let pct = percents[min(sets.count, percents.count - 1)]
            return WodSet(weight: weight(pct, of: oneRM, exerciseID: exerciseID, bar: bar), reps: sets.last?.reps ?? reps,
                          bar: ex?.usesBar == true ? (sets.last?.bar ?? bar) : nil)
        }
        if let last = sets.last { return last }
        let s = Progression.suggest(exerciseID: exerciseID, sets: 1, reps: reps, history: history)
        guard ex?.usesBar == true else { return WodSet(weight: s.weight, reps: reps) }
        // Na musculação a carga anotada é só das anilhas: aqui é sempre o total, com a barra
        let total = s.weight > 0 && !(ex?.weightIncludesBar ?? true) ? s.weight + bar : s.weight
        return WodSet(weight: max(total, bar), reps: reps, bar: bar)
    }

    static func text(_ loads: [WodLoad]) -> String {
        loads.filter { !$0.sets.isEmpty }.map { l in
            "\(Exercise.name(l.exerciseID)) " + l.sets.map { setText($0, l.exerciseID) }.joined(separator: ", ")
        }.joined(separator: "; ")
    }

    static func setText(_ s: WodSet, _ id: String, spaced: Bool = false) -> String {
        guard isWeighted(id) else { return "\(s.reps) reps" }
        return spaced ? "\(Progression.fmt(s.weight)) kg × \(s.reps)" : "\(Progression.fmt(s.weight))×\(s.reps)"
    }

    /// Vira um treino com séries feitas, ligado à atividade (progressão, recordes e "Ver séries")
    @MainActor
    static func save(_ loads: [WodLoad], title: String, activity: Activity, context: ModelContext) {
        let filled = loads.filter { !$0.sets.isEmpty }
        guard !filled.isEmpty else { return }
        // Treino sem movimento de CrossFit anota só as anilhas (como na musculação); com, o total
        let totals = filled.contains { Exercise.byID($0.exerciseID)?.crossfit == true }
        let s = WorkoutSession(title: title, routineUUID: nil)
        s.start = activity.date
        s.end = activity.date.addingTimeInterval(Double(max(activity.minutes, 1)) * 60)
        s.effort = activity.effort
        s.activityUUID = activity.uuid
        s.gymUUID = activity.gymUUID
        s.placeAsked = true
        context.insert(s)
        for (i, l) in filled.enumerated() {
            for (k, set) in l.sets.enumerated() {
                let weight = totals || Exercise.byID(l.exerciseID)?.usesBar != true ? set.weight : max(set.weight - (set.bar ?? WodBar.current), 0)
                let logged = LoggedSet(exerciseID: l.exerciseID, exerciseOrder: i, index: k, weight: weight, reps: set.reps, rest: 120)
                logged.done = true
                s.sets.append(logged)
            }
        }
    }
}

/// Séries de uma parte do treino: movimentos com peso (carga × reps) e, fora do WOD cronometrado, os sem peso
/// (só reps), mais os que você adicionar. "x% do PR" na prescrição vira a carga de cada série.
struct WodLoadsEditor: View {
    @Binding var loads: [WodLoad]
    let part: Int
    let lines: [String]
    var title = "Cargas"
    /// Lista também os movimentos sem peso (partes como força e condicionamento); no WOD só os com carga
    var bodyweight = false
    @Query(filter: #Predicate<WorkoutSession> { $0.end != nil }, sort: \WorkoutSession.start) private var sessions: [WorkoutSession]
    @Query private var records: [PersonalRecord]
    @State private var editing: (exercise: String, index: Int)?
    @State private var weight: Double?
    @State private var reps: Double?
    @State private var bar: Double = WodBar.current
    @State private var picking = false
    @State private var registeringPR: IDBox?
    @State private var confirmRemove: String?

    private var exercises: [String] {
        let mine = loads.filter { $0.part == part }
        let removed = Set(mine.filter { $0.removed == true }.map(\.exerciseID))
        var ids = WodLoads.tracked(lines, bodyweight: bodyweight).filter { !removed.contains($0) }
        for l in mine where l.removed != true && !ids.contains(l.exerciseID) { ids.append(l.exerciseID) }
        return ids
    }

    /// Tira o exercício e as séries dele; o lido do treino fica marcado para não voltar
    private func remove(_ id: String) {
        loads.removeAll { $0.exerciseID == id && $0.part == part }
        if WodLoads.tracked(lines, bodyweight: bodyweight).contains(id) {
            loads.append(WodLoad(exerciseID: id, part: part, removed: true))
        }
    }

    private var percents: [Double] { WodLoads.percents(in: lines) }

    private func oneRM(_ id: String) -> Double? {
        WodLoads.oneRM(id, history: sessions.map(\.log), manual: records.map(\.log))
    }

    var body: some View {
        GMSection(title, footer: exercises.isEmpty ? "Nenhum movimento reconhecido. Adicione o que você fez." :
                    "O + repete a série anterior\(percents.isEmpty ? "" : " (ou usa o próximo % do PR)"). Toque numa série para corrigir.") {
            ForEach(exercises, id: \.self) { id in
                if id != exercises.first { GMDivider() }
                row(id)
            }
            if !exercises.isEmpty { GMDivider() }
            GMRow(icon: "plus", iconTint: Theme.accent, title: "Outro exercício", chevron: true) { picking = true }
        }
        .gmModal(isPresented: $picking) {
            ExercisePicker { e in
                guard !exercises.contains(e.id) else { return }
                loads.removeAll { $0.exerciseID == e.id && $0.part == part }
                loads.append(WodLoad(exerciseID: e.id, part: part))
            }
        }
        .gmActions(isPresented: Binding(get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } }),
                   title: "Tirar \(confirmRemove.map(Exercise.name) ?? "exercício")?",
                   message: "As séries registradas dele saem junto.",
                   actions: confirmRemove.map { id in [GMAction("Tirar exercício", icon: "trash", destructive: true) {
                       withAnimation(.snappy) { remove(id) }
                   }] } ?? [])
        .gmModal(item: $registeringPR) { PRSessionView(only: $0.id) }
        .gmSheet(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) { close in
            if let e = editing { editor(e, close: close) }
        }
    }

    private func sets(_ id: String) -> [WodSet] { loads.first { $0.exerciseID == id && $0.part == part }?.sets ?? [] }

    private func setSets(_ id: String, _ sets: [WodSet]) {
        if let i = loads.firstIndex(where: { $0.exerciseID == id && $0.part == part }) { loads[i].sets = sets }
        else { loads.append(WodLoad(exerciseID: id, part: part, sets: sets)) }
    }

    private func row(_ id: String) -> some View {
        let list = sets(id)
        let bars = Set(list.compactMap(\.bar))
        let weighted = WodLoads.isWeighted(id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(Exercise.name(id)).font(.subheadline.weight(.semibold))
                    if !weighted {
                        Text("Sem peso · conta as repetições").font(.caption).foregroundStyle(Theme.dim)
                    } else if let b = bars.first, bars.count == 1 {
                        Text("Total com a barra de \(Progression.fmt(b)) kg").font(.caption).foregroundStyle(Theme.dim)
                    } else if Exercise.byID(id)?.usesBar == true && list.isEmpty {
                        Text("Barra + anilhas").font(.caption).foregroundStyle(Theme.dim)
                    }
                    if weighted && !percents.isEmpty { percentNote(id) }
                }
                Spacer()
                GMIconButton(icon: "trash", size: 30, tint: Theme.dim, label: "Tirar \(Exercise.name(id))") {
                    if list.isEmpty { withAnimation(.snappy) { remove(id) } } else { confirmRemove = id }
                }
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    let reps = WodLoads.reps(of: id, in: lines) ?? WodLoads.reps(in: lines)
                    let n = WodLoads.next(after: list, exerciseID: id, reps: reps, history: sessions.map(\.log),
                                          percents: percents, oneRM: oneRM(id))
                    setSets(id, list + [n])
                } label: {
                    Label(list.isEmpty ? "Série" : "+ série", systemImage: "plus")
                        .labelStyle(.titleOnly)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Theme.accent, in: .capsule)
                        .foregroundStyle(.black)
                }
                .buttonStyle(GMPress())
            }
            if !list.isEmpty {
                GMFlow {
                    ForEach(Array(list.enumerated()), id: \.offset) { k, s in
                        Button { open(id, k, s) } label: {
                            Text("\(k + 1)  \(WodLoads.setText(s, id, spaced: true))")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Theme.raised, in: .capsule)
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(GMPress())
                    }
                }
            }
        }
    }

    /// "75% do PR (100 kg) = 75 kg"; sem PR, atalho para registrar
    @ViewBuilder
    private func percentNote(_ id: String) -> some View {
        let pcts = percents.map { "\(Int(($0 * 100).rounded()))%" }
        let pctText = pcts.count == 1 ? pcts[0] : "\(pcts.first!)–\(pcts.last!)"
        if let orm = oneRM(id) {
            let kgs = percents.map { WodLoads.weight($0, of: orm, exerciseID: id) }
            let kgText = Set(kgs).count == 1 ? "\(Progression.fmt(kgs[0])) kg" : "\(Progression.fmt(kgs.first!))–\(Progression.fmt(kgs.last!)) kg"
            Label("\(pctText) do PR (\(Progression.fmt(orm.rounded())) kg) = \(kgText)", systemImage: "trophy.fill")
                .font(.caption.weight(.semibold)).foregroundStyle(Theme.trophy)
        } else {
            Button { registeringPR = IDBox(id: id) } label: {
                Label("\(pctText) do PR · registre seu PR", systemImage: "trophy")
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.trophy)
            }
            .buttonStyle(GMPress())
            .accessibilityHint("Abre o registro do seu PR de \(Exercise.name(id)) para calcular a carga")
        }
    }

    private func open(_ id: String, _ k: Int, _ s: WodSet) {
        weight = s.weight
        reps = Double(s.reps)
        bar = s.bar ?? WodBar.current
        editing = (id, k)
    }

    private func editor(_ e: (exercise: String, index: Int), close: @escaping () -> Void) -> some View {
        let ex = Exercise.byID(e.exercise)
        let weighted = WodLoads.isWeighted(e.exercise)
        return VStack(alignment: .leading, spacing: 14) {
            Text("\(Exercise.name(e.exercise)) · série \(e.index + 1)").font(.headline)
            if weighted {
                if ex?.usesBar == true {
                    barFields
                } else {
                    GMDecimalField(title: "Carga", value: $weight, step: ex?.increment ?? 2.5, unit: "kg", start: 20, clearable: false)
                }
                GMDivider()
            }
            GMDecimalField(title: "Reps", value: Binding(get: { reps }, set: { reps = $0.map { max(0, $0.rounded()) } }),
                           step: 1, unit: "reps", start: 5, clearable: false)
            GMButton("Salvar") {
                var list = sets(e.exercise)
                if list.indices.contains(e.index) {
                    let usesBar = weighted && ex?.usesBar == true
                    if usesBar { WodBar.current = bar }
                    list[e.index] = WodSet(weight: weighted ? max(weight ?? 0, usesBar ? bar : 0) : 0, reps: Int(reps ?? 0), bar: usesBar ? bar : nil)
                    setSets(e.exercise, list)
                }
                close()
            }
            GMButton("Apagar série", icon: "trash", kind: .danger) {
                var list = sets(e.exercise)
                if list.indices.contains(e.index) { list.remove(at: e.index) }
                setSets(e.exercise, list)
                close()
            }
        }
    }

    /// Barra + anilhas de cada lado = total (dá para digitar qualquer um dos dois)
    @ViewBuilder
    private var barFields: some View {
        let side = max(((weight ?? bar) - bar) / 2, 0)
        GMChoiceChips(title: "Barra", options: WodBar.options.map { ($0, "\(Progression.fmt($0)) kg") }, selection: Binding(
            get: { bar },
            set: { b in weight = b + 2 * side; bar = b }))
        GMDecimalField(title: "Anilhas de cada lado", value: Binding(get: { side }, set: { weight = bar + 2 * max($0 ?? 0, 0) }),
                       step: 1.25, unit: "kg", start: 10, clearable: false)
        HStack(alignment: .firstTextBaseline) {
            Text("Total").font(.subheadline.weight(.semibold))
            Spacer()
            Text("\(Progression.fmt(bar)) + 2 × \(Progression.fmt(side)) =").font(.caption).foregroundStyle(Theme.dim)
            Text("\(Progression.fmt(weight ?? bar)) kg").font(.title3.weight(.heavy).monospacedDigit()).foregroundStyle(Theme.accent)
        }
        GMDecimalField(title: "Ou digite o total", value: Binding(get: { weight }, set: { weight = $0 }),
                       step: 2.5, unit: "kg", start: bar, clearable: false)
    }
}

/// Esquema do WOD lido das linhas: rodadas-alvo (RFT), escada de reps (21-15-9) e chipper
enum WodScheme {
    /// "5 rodadas de:", "3 rounds for time", "RFT 4" → 4
    static func rounds(_ lines: [String]) -> Int? {
        for line in lines {
            let l = line.lowercased()
            if let r = l.range(of: "^(\\d{1,2})\\s*(?:rounds?|rodadas?|rft|x)\\b", options: .regularExpression),
               let n = Int(l[r].prefix { $0.isNumber }), (2...30).contains(n), !l.contains("amrap"), !l.contains("mom") { return n }
            if let r = l.range(of: "\\brft\\s*(\\d{1,2})", options: .regularExpression),
               let n = Int(l[r].filter(\.isNumber)), (2...30).contains(n) { return n }
        }
        return nil
    }

    /// "21-15-9 repetições de:", "50-40-30-20-10" → reps de cada rodada
    static func ladder(_ lines: [String]) -> [Int]? {
        for line in lines {
            guard let r = line.range(of: "^\\d{1,3}(?:\\s*-\\s*\\d{1,3}){2,}", options: .regularExpression) else { continue }
            let reps = line[r].split(separator: "-").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            if reps.count >= 3 { return reps }
        }
        return nil
    }

    /// Linhas de cada bloco do WOD em blocos: "AMRAP 3'" abre um bloco, "Descanso 2'" fica de fora
    static func blocks(_ lines: [String]) -> [[String]] {
        var groups: [[String]] = []
        for line in lines {
            let l = line.lowercased()
            if l.hasPrefix("descanso") || l.hasPrefix("rest") { continue }
            if WodParser.format(in: line) != nil && WodMovements.identify(line).isEmpty && line.count <= 20 {
                groups.append([])
            } else if groups.isEmpty {
                groups.append([line])
            } else {
                groups[groups.count - 1].append(line)
            }
        }
        return groups
    }

    /// For Time de uma passada só por uma lista longa (sem rodadas nem escada): dá para ir riscando
    static func isChipper(_ wod: Wod) -> Bool {
        guard case .forTime = wod.format else { return false }
        return rounds(wod.lines) == nil && ladder(wod.lines) == nil && wod.lines.filter { WodMovements.identify($0).count > 0 }.count >= 3
    }
}

/// Cronômetro dentro de uma parte (força "a cada 2'", skill em EMOM, AMRAP de aquecimento): só aparece se a parte tiver tempo
struct PartTimerCard: View {
    let lines: [String]
    @Binding var start: Date?
    let now: Date

    private var format: WodFormat? { lines.lazy.compactMap(WodParser.format(in:)).first }

    var body: some View {
        if let f = format {
            GMCard {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.name).font(.caption.weight(.bold)).foregroundStyle(Theme.accent)
                        if let start { status(f, Int(now.timeIntervalSince(start))) } else {
                            Text("Cronômetro desta parte").font(.subheadline.weight(.semibold))
                        }
                    }
                    Spacer()
                    GMButton(start == nil ? "Iniciar" : "Zerar", icon: start == nil ? "play.fill" : "arrow.counterclockwise",
                             kind: start == nil ? .primary : .secondary, full: false, small: true) {
                        start = start == nil ? .now : nil
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func status(_ f: WodFormat, _ sec: Int) -> some View {
        switch f {
        case .every(let every, let m) where m == 0 || sec < m * 60:
            Text("Série \(sec / every + 1)\(m > 0 ? " de \(max(m * 60 / every, 1))" : "") · \(clock(every - sec % every))")
                .font(.title3.bold().monospacedDigit())
        case .emom(let m) where sec < m * 60:
            Text("Minuto \(sec / 60 + 1) de \(m) · \(clock(60 - sec % 60))").font(.title3.bold().monospacedDigit())
        case .amrap(let m) where sec < m * 60:
            Text("Faltam \(clock(m * 60 - sec))").font(.title3.bold().monospacedDigit())
        case .forTime(let cap?) where sec < cap * 60:
            Text("\(clock(sec)) de \(cap):00").font(.title3.bold().monospacedDigit())
        case .forTime(nil):
            Text(clock(sec)).font(.title3.bold().monospacedDigit())
        default:
            Text("Tempo esgotado").font(.title3.bold()).foregroundStyle(Theme.warning)
        }
    }
}
