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

    @State private var confirmDelete = false

    var body: some View {
        GMModal(editing == nil ? "Novo exercício" : "Editar exercício", confirm: "Salvar",
                confirmEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty, onConfirm: save) {
            GMSection("Nome") {
                GMTextField(placeholder: "Nome do exercício", text: $name, capitalization: .sentences)
            }
            GMSection(footer: "Peso do corpo progride em reps (dá para somar carga extra). Por tempo registra segundos.") {
                GMChoiceChips(title: "Grupo muscular", options: MuscleGroup.allCases.map { ($0, $0.name) }, selection: $group)
                GMDivider()
                GMChoiceChips(title: "Equipamento", options: Exercise.equipments.map { ($0, $0) }, selection: $equipment)
                GMDivider()
                GMChoiceChips(title: "Registro", options: ExerciseType.allCases.map { ($0, $0.name) }, selection: $type)
            }
            GMSection("Descrição (opcional)") {
                GMTextField(placeholder: "Como fazer, ajustes da máquina…", text: $notes, axis: .vertical)
            }
            if editing != nil {
                GMSection(footer: "O histórico de treinos com ele continua salvo.") {
                    GMRow(icon: "trash", iconTint: Theme.danger, title: "Apagar exercício") { confirmDelete = true }
                }
            }
        }
        .gmActions(isPresented: $confirmDelete, title: "Apagar \(name)?", actions: [
            GMAction("Apagar", icon: "trash", destructive: true) {
                if let editing {
                    context.delete(editing)
                    try? context.save()
                }
                dismiss()
            }
        ])
        .onAppear {
            guard let e = editing else { return }
            name = e.name
            group = MuscleGroup(rawValue: e.groupRaw) ?? .corpo
            equipment = e.equipment
            type = ExerciseType(rawValue: e.typeRaw) ?? .weighted
            notes = e.notes
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
