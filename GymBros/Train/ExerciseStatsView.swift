import SwiftData
import Charts
import SwiftUI

struct ExerciseStatsList: View {
    /// Treinos concluídos, do mais novo ao mais antigo
    let sessions: [WorkoutSession]

    private var rows: [(id: String, count: Int, best: String)] {
        var count: [String: Int] = [:]
        var sets: [String: [SetLog]] = [:]
        for s in sessions {
            let log = s.log
            for id in Set(log.sets.map(\.exerciseID)) { count[id, default: 0] += 1 }
            for set in log.sets where set.done { sets[set.exerciseID, default: []].append(set) }
        }
        return count.keys.sorted { count[$0]! > count[$1]! }.map { id in
            let done = sets[id] ?? []
            let best: String
            if let orm = Progression.bestOneRM(done) {
                best = "1RM ~\(Progression.fmt(orm.rounded())) kg"
            } else if let w = done.map(\.weight).max(), w > 0 {
                best = "máx. \(Progression.fmt(w)) kg"
            } else {
                best = "máx. \(done.map(\.reps).max() ?? 0)\(Exercise.byID(id)?.type == .time ? " s" : " reps")"
            }
            return (id, count[id]!, best)
        }
    }

    var body: some View {
        GMScreen("Exercícios e recordes", back: true) {
            if rows.isEmpty {
                GMEmptyState(icon: "chart.line.uptrend.xyaxis", title: "Sem recordes ainda",
                             message: "Conclua um treino guiado para ver seus recordes aqui.")
            } else {
                GMCard {
                    ForEach(rows, id: \.id) { r in
                        NavigationLink {
                            ExerciseDetailView(exerciseID: r.id, sessions: sessions)
                        } label: {
                            GMRow(title: Exercise.name(r.id), subtitle: "\(r.count) treino\(r.count == 1 ? "" : "s")", chevron: true) {
                                Text(r.best).font(.subheadline.bold().monospacedDigit()).foregroundStyle(Theme.accent)
                            }
                        }
                        .buttonStyle(GMPress())
                        if r.id != rows.last?.id { GMDivider() }
                    }
                }
            }
        }
    }
}

struct ExerciseDetailView: View {
    let exerciseID: String
    let sessions: [WorkoutSession]
    @Query(sort: \PersonalRecord.date) private var allPRs: [PersonalRecord]

    private var prs: [PersonalRecord] { allPRs.filter { $0.exerciseID == exerciseID } }
    @State private var goal: TrainingGoal?
    @State private var goalLoaded = false

    private struct Point: Identifiable {
        let date: Date
        let value: Double
        let sets: [SetLog]
        var id: Date { date }
    }

    /// Gráfico em kg só para exercício de carga (peso do corpo e tempo seguem em reps/segundos, mesmo com carga extra
    /// em algum treino, para não virar escala de 1RM com zeros). Personalizado sem tipo conhecido: pelo que já teve carga.
    private var weighted: Bool {
        if let type = Exercise.byID(exerciseID)?.type { return type == .weighted }
        return !prs.isEmpty || sessions.contains { $0.sets.contains { $0.exerciseID == exerciseID && $0.weight > 0 } }
    }

    /// Séries feitas por treino (no de carga, só as com carga: série sem carga anotada não vira ponto zero)
    private var sessionSets: [(date: Date, sets: [SetLog])] {
        let w = weighted
        return sessions.reversed().compactMap { s in
            let sets = s.log.sets.filter { $0.exerciseID == exerciseID && $0.done && (!w || $0.weight > 0) }
            return sets.isEmpty ? nil : (s.start, sets)
        }
    }

    /// Escala do gráfico de carga: 1RM estimado quando todo ponto tem 1RM; se algum não tem (só séries acima de 12 reps
    /// ou sem carga), todos usam a maior carga. Nunca mistura as duas no mesmo gráfico.
    private var usesOneRM: Bool {
        sessionSets.allSatisfy { Progression.bestOneRM($0.sets) != nil }
            && prs.allSatisfy { Progression.oneRM(weight: $0.weight, reps: $0.reps) != nil }
    }

    private func prValue(_ p: PersonalRecord) -> Double {
        usesOneRM ? (Progression.oneRM(weight: p.weight, reps: p.reps) ?? p.weight) : p.weight
    }

    private var points: [Point] {
        let orm = usesOneRM
        return sessionSets.map { d, sets in
            let v = weighted
                ? (orm ? (Progression.bestOneRM(sets) ?? 0) : (sets.map(\.weight).max() ?? 0))
                : Double(sets.map(\.reps).max() ?? 0)
            return Point(date: d, value: v, sets: sets)
        }
    }

    /// Melhor 1RM estimado de verdade (só séries de até 12 reps, treinos e PRs)
    private var bestOneRM: Double? {
        (sessionSets.compactMap { Progression.bestOneRM($0.sets) } + prs.compactMap { Progression.oneRM(weight: $0.weight, reps: $0.reps) }).max()
    }

    var body: some View {
        let pts = points
        GMScreen(Exercise.name(exerciseID), back: true) {
            if Exercise.byID(exerciseID)?.type == .weighted {
                GMSection("Objetivo", footer: goal.map { "Faixa de \($0.range.lowerBound)–\($0.range.upperBound) reps: +1 rep por treino até o topo, depois sobe a carga e volta ao início. Descanso sugerido de \(clock($0.rest))." }
                          ?? "Sem objetivo: reps fixas da rotina, carga sobe quando completa todas.") {
                    GMChoiceChips(options: [(nil as TrainingGoal?, "Nenhum")] + TrainingGoal.allCases.map { ($0 as TrainingGoal?, $0.name) },
                                  selection: Binding(get: { goal }, set: { goal = $0; TrainingGoal.set($0, for: exerciseID) }))
                }
                .onAppear { if !goalLoaded { goalLoaded = true; goal = TrainingGoal.of(exerciseID) } }
            }
            GMSection(weighted ? (usesOneRM ? "1RM estimado (kg)" : "Maior carga (kg)") : (Exercise.byID(exerciseID)?.type == .time ? "Melhor tempo (s)" : "Mais reps")) {
                let manual = weighted ? prs : []
                if pts.count + manual.count >= 2 {
                    Chart {
                        ForEach(pts) { p in
                            LineMark(x: .value("Data", p.date), y: .value("Valor", p.value))
                                .interpolationMethod(.monotone)
                                .foregroundStyle(Theme.accent)
                            PointMark(x: .value("Data", p.date), y: .value("Valor", p.value))
                                .foregroundStyle(Theme.accent)
                        }
                        // PRs registrados à mão
                        ForEach(manual) { p in
                            PointMark(x: .value("Data", p.date), y: .value("Valor", prValue(p)))
                                .symbol(.diamond)
                                .symbolSize(90)
                                .foregroundStyle(Theme.trophy)
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 200)
                    if !manual.isEmpty {
                        Label("PR registrado na sessão de PR", systemImage: "diamond.fill").font(.caption).foregroundStyle(Theme.trophy)
                    }
                } else {
                    Text("O gráfico aparece a partir do segundo treino.").foregroundStyle(Theme.dim)
                }
                if weighted, let best = bestOneRM {
                    GMDivider()
                    GMValueRow(label: "Melhor 1RM estimado", value: "\(Progression.fmt((best * 10).rounded() / 10)) kg")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Calculadora (reps × carga)").font(.subheadline).foregroundStyle(Theme.dim)
                        Text(Progression.repTable(oneRM: best, increment: Exercise.byID(exerciseID)?.increment ?? 2.5)
                            .map { "\($0.reps)×\(Progression.fmt($0.weight))" }
                            .joined(separator: "   "))
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                    }
                }
            }
            if !prs.isEmpty {
                GMSection("PRs registrados") {
                    ForEach(prs.reversed()) { p in
                        HStack {
                            Text(p.date.formatted(.dateTime.day().month(.abbreviated).year())).font(.caption).foregroundStyle(Theme.dim)
                            Spacer()
                            Text("🏆 \(Progression.fmt(p.weight)) kg × \(p.reps)").font(.subheadline.monospacedDigit().weight(.semibold))
                        }
                    }
                }
            }
            GMSection("Histórico") {
                ForEach(pts.reversed()) { p in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.date.formatted(.dateTime.day().month(.abbreviated).year())).font(.caption).foregroundStyle(Theme.dim)
                        Text(p.sets.map { $0.weight > 0 ? "\(Progression.fmt($0.weight))×\($0.reps)" : "\($0.reps)" }.joined(separator: ", "))
                            .font(.subheadline.monospacedDigit())
                    }
                }
            }
        }
    }
}
