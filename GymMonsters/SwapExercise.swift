import SwiftUI

/// Alternativas para o mesmo músculo: as que você já fez primeiro, depois por equipamento diferente
struct SwapExerciseView: View {
    let current: String
    /// Exercícios que já estão no treino
    let exclude: Set<String>
    let history: [SessionLog]
    let onPick: (Exercise) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var info: Exercise?

    private var base: Exercise? { Exercise.byID(current) }

    private var options: [Exercise] {
        guard let base else { return [] }
        var count: [String: Int] = [:]
        for s in history { for id in Set(s.sets.map(\.exerciseID)) { count[id, default: 0] += 1 } }
        return Exercise.all
            .filter { $0.group == base.group && $0.id != current && !exclude.contains($0.id) }
            .sorted { a, b in
                let ca = count[a.id] ?? 0, cb = count[b.id] ?? 0
                if ca != cb { return ca > cb }
                // Mesmo tipo de carga primeiro (barra por barra, máquina por máquina…)
                let ea = a.equipment == base.equipment, eb = b.equipment == base.equipment
                if ea != eb { return !ea }
                return a.name < b.name
            }
    }

    var body: some View {
        let list = options
        var count: [String: Int] = [:]
        for s in history { for id in Set(s.sets.map(\.exerciseID)) { count[id, default: 0] += 1 } }
        return GMModal("Trocar \(base?.name ?? "")") {
            Text("Aparelho ocupado? Escolha outro de \(base?.group.name.lowercased() ?? "mesmo músculo"). As séries que faltam passam para ele, com a carga sugerida pelo seu histórico.")
                .font(.subheadline).foregroundStyle(Theme.dim)
            if list.isEmpty {
                GMEmptyState(icon: "dumbbell", title: "Nenhuma alternativa")
            }
            GMSection {
                ForEach(list) { ex in
                    HStack(spacing: 12) {
                        Button { info = ex } label: { ExerciseThumb(exercise: ex, size: 44) }
                            .buttonStyle(GMPress())
                        Button {
                            onPick(ex)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ex.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    Text(ex.equipment + ((count[ex.id] ?? 0) > 0 ? " · já fez \(count[ex.id]!)×" : ""))
                                        .font(.caption).foregroundStyle(Theme.dim)
                                }
                                Spacer()
                                Image(systemName: "arrow.triangle.swap").foregroundStyle(Theme.accent)
                            }
                            .contentShape(Rectangle())
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(GMPress())
                    }
                    if ex.id != list.last?.id { GMDivider() }
                }
            }
        }
        .gmModal(item: $info) { ExerciseInfoView(exercise: $0) }
    }
}
