import MuscleMap
import SwiftData
import SwiftUI

extension Muscle {
    var ptName: String {
        switch self {
        case .abs: "Abdômen"
        case .biceps: "Bíceps"
        case .calves: "Panturrilha"
        case .chest: "Peito"
        case .deltoids: "Ombros"
        case .forearm: "Antebraço"
        case .gluteal: "Glúteos"
        case .hamstring: "Posterior de coxa"
        case .lowerBack: "Lombar"
        case .obliques: "Oblíquos"
        case .quadriceps: "Quadríceps"
        case .trapezius: "Trapézio"
        case .triceps: "Tríceps"
        case .upperBack: "Costas"
        case .adductors: "Adutores"
        case .neck: "Pescoço"
        default: displayName
        }
    }

    /// Músculos que entram no mapa e na lista do que ficou sem treino
    static let tracked: [Muscle] = [.trapezius, .deltoids, .chest, .upperBack, .biceps, .triceps, .forearm,
                                    .abs, .obliques, .lowerBack, .gluteal, .quadriceps, .hamstring, .adductors, .calves]
}

enum BodyStyle {
    static let dark = BodyViewStyle(defaultFillColor: Color(white: 0.24), strokeColor: Color(white: 0.12), strokeWidth: 0.5,
                                    headColor: Color(white: 0.32), hairColor: Color(white: 0.16))
    static let scale = HeatmapColorScale(colors: [Color(white: 0.3), .yellow, .orange, .red])
}

/// Frente e costas lado a lado
struct BodyPair: View {
    let intensities: [Muscle: Double]
    var highlight: [Muscle: Color] = [:]
    @AppStorage("bodyGender") private var genderRaw = BodyGender.male.rawValue

    var body: some View {
        let gender = BodyGender(rawValue: genderRaw) ?? .male
        HStack(spacing: 4) {
            ForEach([BodySide.front, .back], id: \.self) { side in
                highlighted(BodyView(gender: gender, side: side, style: BodyStyle.dark)
                    .heatmap(intensities.map { MuscleIntensity(muscle: $0.key, intensity: $0.value) }, colorScale: BodyStyle.scale))
            }
        }
    }

    private func highlighted(_ view: BodyView) -> BodyView {
        highlight.reduce(view) { v, h in v.highlight(h.key, color: h.value) }
    }
}

/// Volume relativo por músculo: série feita conta 1 no músculo principal e 0,5 nos secundários
func muscleLoad(_ sets: [SetLog]) -> [Muscle: Double] {
    var load: [Muscle: Double] = [:]
    for s in sets where s.done {
        let m = Exercise.byID(s.exerciseID)?.muscles ?? MuscleTargets(primary: [], secondary: [])
        for p in m.primary { load[p, default: 0] += 1 }
        for x in m.secondary { load[x, default: 0] += 0.5 }
    }
    return load
}

func normalized(_ load: [Muscle: Double]) -> [Muscle: Double] {
    let top = load.values.max() ?? 0
    guard top > 0 else { return [:] }
    return load.mapValues { 0.25 + 0.75 * $0 / top }
}

// MARK: - Mapa muscular do período

struct MuscleMapView: View {
    let sessions: [WorkoutSession]
    @State private var days = 7
    @AppStorage("bodyGender") private var genderRaw = BodyGender.male.rawValue

    var body: some View {
        let since = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .distantPast
        let sets = sessions.filter { days == 0 || $0.start >= since }.flatMap(\.log.sets)
        let load = muscleLoad(sets)
        let missing = Muscle.tracked.filter { (load[$0] ?? 0) == 0 }
        GMScreen("Mapa muscular", back: true) {
            GMSegmented(options: [(7, "7 dias"), (30, "30 dias"), (0, "Tudo")], selection: $days)
            GMCard {
                BodyPair(intensities: normalized(load)).frame(height: 320)
                GMSegmented(options: [(BodyGender.male.rawValue, "Masculina"), (BodyGender.female.rawValue, "Feminina")],
                            selection: $genderRaw)
            }
            if !load.isEmpty {
                GMSection("Séries por músculo") {
                    ForEach(load.sorted { $0.value > $1.value }, id: \.key) { m, v in
                        GMValueRow(label: m.ptName, value: Progression.fmt((v * 2).rounded() / 2))
                    }
                }
            }
            GMSection("Sem treino no período", footer: "Série principal conta 1, músculo auxiliar conta meia.") {
                Text(missing.isEmpty ? "Você treinou todos os grupos no período. 💪" : missing.map(\.ptName).joined(separator: ", "))
                    .font(.subheadline)
            }
        }
    }
}

// MARK: - Detalhe do exercício

/// Alterna a foto inicial e a final, como uma animação
struct ExerciseAnimation: View {
    let exerciseID: String
    @State private var frame = 0

    var body: some View {
        Image("ex_\(exerciseID)_\(frame)")
            .resizable()
            .scaledToFit()
            .clipShape(.rect(cornerRadius: 14))
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1.1))
                    withAnimation(.easeInOut(duration: 0.25)) { frame = 1 - frame }
                }
            }
    }
}

struct ExerciseInfoView: View {
    let exercise: Exercise
    @Environment(\.dismiss) private var dismiss
    @Query private var customs: [CustomExercise]
    @Query private var notes: [ExerciseNote]
    @State private var editing = false

    var body: some View {
        let m = exercise.muscles
        GMModal(exercise.name, cancel: "Fechar") {
            if exercise.hasPhotos {
                ExerciseAnimation(exerciseID: exercise.id)
            }
            GMCard {
                GMValueRow(label: "Grupo", value: exercise.group.name)
                GMValueRow(label: "Equipamento", value: exercise.equipment)
                GMValueRow(label: "Registro", value: exercise.type.name)
            }
            let steps = exercise.instructions
            if !steps.isEmpty {
                GMSection("Como fazer") {
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(i + 1)").font(.subheadline.bold()).foregroundStyle(Theme.accent)
                            Text(step).font(.subheadline)
                        }
                    }
                }
            }
            if let note = notes.first(where: { $0.exerciseID == exercise.id }), !note.text.isEmpty {
                GMSection("Sua nota") { Text(note.text).font(.subheadline) }
            }
            if let notes = Exercise.customNotes[exercise.id], !notes.isEmpty {
                GMSection("Descrição") { Text(notes).font(.subheadline) }
            }
            GMSection("Músculos", footer: exercise.hasPhotos ? "Fotos: free-exercise-db (domínio público)." : nil) {
                BodyPair(intensities: Dictionary(m.primary.map { ($0, 1.0) } + m.secondary.map { ($0, 0.45) },
                                                 uniquingKeysWith: max))
                    .frame(height: 260)
                Text("Principal: " + m.primary.map(\.ptName).joined(separator: ", ")).font(.caption)
                if !m.secondary.isEmpty {
                    Text("Auxiliar: " + m.secondary.map(\.ptName).joined(separator: ", ")).font(.caption).foregroundStyle(Theme.dim)
                }
            }
            if exercise.isCustom {
                GMButton("Editar exercício", icon: "pencil", kind: .secondary) { editing = true }
            }
        }
        .gmModal(isPresented: $editing) {
            CustomExerciseForm(editing: customs.first { $0.exerciseID == exercise.id })
        }
    }
}
