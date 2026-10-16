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
        List {
            if rows.isEmpty {
                Text("Conclua um treino para ver seus recordes aqui.").foregroundStyle(Theme.dim)
            }
            ForEach(rows, id: \.id) { r in
                NavigationLink {
                    ExerciseDetailView(exerciseID: r.id, sessions: sessions)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Exercise.name(r.id)).font(.subheadline.weight(.semibold))
                            Text("\(r.count) treino\(r.count == 1 ? "" : "s")").font(.caption).foregroundStyle(Theme.dim)
                        }
                        Spacer()
                        Text(r.best).font(.subheadline.bold().monospacedDigit()).foregroundStyle(Theme.accent)
                    }
                }
            }
        }
        .navigationTitle("Exercícios")
    }
}

struct ExerciseDetailView: View {
    let exerciseID: String
    let sessions: [WorkoutSession]

    private struct Point: Identifiable {
        let date: Date
        let value: Double
        let sets: [SetLog]
        var id: Date { date }
    }

    private var weighted: Bool {
        sessions.contains { $0.sets.contains { $0.exerciseID == exerciseID && $0.weight > 0 } }
    }

    private var points: [Point] {
        sessions.reversed().compactMap { s in
            let sets = s.log.sets.filter { $0.exerciseID == exerciseID && $0.done }
            guard !sets.isEmpty else { return nil }
            let v = weighted
                ? (Progression.bestOneRM(sets) ?? sets.map(\.weight).max() ?? 0)
                : Double(sets.map(\.reps).max() ?? 0)
            return Point(date: s.start, value: v, sets: sets)
        }
    }

    var body: some View {
        let pts = points
        List {
            Section(weighted ? "1RM estimado (kg)" : (Exercise.byID(exerciseID)?.type == .time ? "Melhor tempo (s)" : "Mais reps")) {
                if pts.count >= 2 {
                    Chart(pts) { p in
                        LineMark(x: .value("Data", p.date), y: .value("Valor", p.value))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(Theme.accent)
                        PointMark(x: .value("Data", p.date), y: .value("Valor", p.value))
                            .foregroundStyle(Theme.accent)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 200)
                } else {
                    Text("O gráfico aparece a partir do segundo treino.").foregroundStyle(Theme.dim)
                }
                if weighted, let best = pts.map(\.value).max() {
                    LabeledContent("Melhor 1RM estimado", value: "\(Progression.fmt((best * 10).rounded() / 10)) kg")
                    LabeledContent("Calculadora") {
                        Text([12, 10, 8, 5, 3].map { r in "\(r)×\(Progression.fmt(((best / (1 + Double(r) / 30)) / 2.5).rounded() * 2.5))" }
                            .joined(separator: "  "))
                            .font(.caption.monospacedDigit())
                    }
                }
            }
            Section("Histórico") {
                ForEach(pts.reversed()) { p in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.date.formatted(.dateTime.day().month(.abbreviated).year())).font(.caption).foregroundStyle(Theme.dim)
                        Text(p.sets.map { $0.weight > 0 ? "\(Progression.fmt($0.weight))×\($0.reps)" : "\($0.reps)" }.joined(separator: ", "))
                            .font(.subheadline.monospacedDigit())
                    }
                }
            }
        }
        .navigationTitle(Exercise.name(exerciseID))
        .navigationBarTitleDisplayMode(.inline)
    }
}
