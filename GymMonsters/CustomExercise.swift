import SwiftData
import SwiftUI

@Model
final class CustomExercise {
    var uuid: UUID = UUID()
    var name: String = ""
    var groupRaw: String = MuscleGroup.corpo.rawValue
    var equipment: String = "Outro"
    var typeRaw: String = ExerciseType.weighted.rawValue
    var notes: String = ""

    init(name: String, group: MuscleGroup, equipment: String, type: ExerciseType, notes: String) {
        self.name = name
        self.groupRaw = group.rawValue
        self.equipment = equipment
        self.typeRaw = type.rawValue
        self.notes = notes
    }

    var exerciseID: String { "custom-\(uuid.uuidString)" }

    var exercise: Exercise {
        Exercise(id: exerciseID, name: name, group: MuscleGroup(rawValue: groupRaw) ?? .corpo,
                 equipment: equipment, type: ExerciseType(rawValue: typeRaw) ?? .weighted)
    }
}

extension Exercise {
    static func register(_ customs: [CustomExercise]) {
        custom = Dictionary(customs.map { ($0.exerciseID, $0.exercise) }, uniquingKeysWith: { a, _ in a })
        customNotes = Dictionary(customs.map { ($0.exerciseID, $0.notes) }, uniquingKeysWith: { a, _ in a })
    }

    static var customNotes: [String: String] = [:]
}

struct CustomExerciseForm: View {
    var editing: CustomExercise?
    var onCreate: ((Exercise) -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var group: MuscleGroup = .peito
    @State private var equipment = "Máquina"
    @State private var type: ExerciseType = .weighted
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nome do exercício", text: $name)
                }
                Section {
                    Picker("Grupo muscular", selection: $group) {
                        ForEach(MuscleGroup.allCases) { Text($0.name).tag($0) }
                    }
                    Picker("Equipamento", selection: $equipment) {
                        ForEach(Exercise.equipments, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Registro", selection: $type) {
                        ForEach(ExerciseType.allCases) { Text($0.name).tag($0) }
                    }
                } footer: {
                    Text("Peso do corpo progride em reps (dá para somar carga extra). Por tempo registra segundos.")
                }
                Section("Descrição (opcional)") {
                    TextField("Como fazer, ajustes da máquina…", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
                if let editing {
                    Section {
                        Button("Apagar exercício", role: .destructive) {
                            context.delete(editing)
                            try? context.save()
                            dismiss()
                        }
                    } footer: {
                        Text("O histórico de treinos com ele continua salvo.")
                    }
                }
            }
            .navigationTitle(editing == nil ? "Novo exercício" : "Editar exercício")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar", action: save)
                        .bold()
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                guard let e = editing else { return }
                name = e.name
                group = MuscleGroup(rawValue: e.groupRaw) ?? .corpo
                equipment = e.equipment
                type = ExerciseType(rawValue: e.typeRaw) ?? .weighted
                notes = e.notes
            }
        }
    }

    private func save() {
        let clean = name.trimmingCharacters(in: .whitespaces)
        if let e = editing {
            e.name = clean
            e.groupRaw = group.rawValue
            e.equipment = equipment
            e.typeRaw = type.rawValue
            e.notes = notes
        } else {
            let e = CustomExercise(name: clean, group: group, equipment: equipment, type: type, notes: notes)
            context.insert(e)
            try? context.save()
            // Registra já, para a tela que chamou conseguir usar o exercício na hora
            Exercise.custom[e.exerciseID] = e.exercise
            onCreate?(e.exercise)
        }
        try? context.save()
        dismiss()
    }
}
