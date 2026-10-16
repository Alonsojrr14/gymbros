import SwiftData
import SwiftUI

struct RoutineEditView: View {
    @Bindable var routine: Routine
    @Environment(\.modelContext) private var context
    @State private var picking = false
    @State private var itemMenu: RoutineItem?

    var body: some View {
        GMScreen(routine.name.isEmpty ? "Rotina" : routine.name, back: true) {
            GMSection("Nome") {
                GMTextField(placeholder: "Nome da rotina", text: $routine.name)
            }
            GMSection("Dias") {
                HStack(spacing: 6) {
                    ForEach(weekdaySymbols, id: \.0) { day, label in
                        let on = routine.weekdays.contains(day)
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            if on { routine.weekdays.remove(day) } else { routine.weekdays.insert(day) }
                        } label: {
                            Text(label)
                                .font(.caption.bold())
                                .frame(maxWidth: .infinity, minHeight: 38)
                                .background(on ? Theme.accent : Theme.raised, in: .rect(cornerRadius: 10))
                                .foregroundStyle(on ? .black : .white)
                        }
                        .buttonStyle(GMPress())
                    }
                }
            }
            if !routine.items.isEmpty {
                GMSection("O que essa rotina treina") {
                    let sets = routine.items.flatMap { item in
                        (0..<item.sets).map { _ in SetLog(exerciseID: item.exerciseID, weight: 0, reps: 0, target: 0, done: true) }
                    }
                    BodyPair(intensities: normalized(muscleLoad(sets))).frame(height: 220)
                }
            }
            GMSection("Exercícios", footer: "A carga não fica na rotina: o app sugere a cada treino a partir do seu histórico.") {
                ForEach(routine.sortedItems) { item in
                    ItemEditor(item: item) { itemMenu = item }
                    GMDivider()
                }
                GMRow(icon: "plus", iconTint: Theme.accent, title: "Adicionar exercício") { picking = true }
            }
        }
        .gmModal(isPresented: $picking) {
            ExercisePicker { ex in
                let item = RoutineItem(exerciseID: ex.id, sets: 3, reps: ex.type == .time ? 30 : 10,
                                       rest: 90, order: routine.items.count)
                routine.items.append(item)
            }
        }
        .gmActions(isPresented: Binding(get: { itemMenu != nil }, set: { if !$0 { itemMenu = nil } }),
                   title: itemMenu.map { Exercise.name($0.exerciseID) }, actions: itemActions)
        .onDisappear { try? context.save() }
    }

    private var itemActions: [GMAction] {
        guard let item = itemMenu else { return [] }
        let items = routine.sortedItems
        let i = items.firstIndex { $0.id == item.id } ?? 0
        var list: [GMAction] = []
        if i > 0 { list.append(GMAction("Mover para cima", icon: "arrow.up") { move(i, to: i - 1) }) }
        if i < items.count - 1 { list.append(GMAction("Mover para baixo", icon: "arrow.down") { move(i, to: i + 1) }) }
        list.append(GMAction("Remover da rotina", icon: "trash", destructive: true) {
            context.delete(item)
            renumber()
        })
        return list
    }

    private func move(_ from: Int, to: Int) {
        var items = routine.sortedItems
        items.swapAt(from, to)
        for (i, it) in items.enumerated() { it.order = i }
    }

    private func renumber() {
        for (i, it) in routine.sortedItems.filter({ !$0.isDeleted }).enumerated() { it.order = i }
    }
}

private struct ItemEditor: View {
    @Bindable var item: RoutineItem
    let onMenu: () -> Void

    var body: some View {
        let ex = Exercise.byID(item.exerciseID)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if let ex { ExerciseThumb(exercise: ex, size: 36) }
                Text(ex?.name ?? item.exerciseID).font(.subheadline.weight(.semibold))
                Spacer()
                GMIconButton(icon: "ellipsis", size: 30, action: onMenu)
            }
            HStack(spacing: 8) {
                MiniStepper(label: "séries", value: $item.sets, range: 1...10, step: 1)
                MiniStepper(label: ex?.type == .time ? "seg" : "reps", value: $item.reps, range: 1...300, step: ex?.type == .time ? 5 : 1)
                MiniStepper(label: "descanso", value: $item.rest, range: 0...600, step: 15, format: { "\($0)s" })
            }
        }
    }
}

/// Stepper compacto em coluna (valor + rótulo), para grades de ajustes
struct MiniStepper: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    var format: (Int) -> String = { "\($0)" }

    var body: some View {
        HStack(spacing: 0) {
            button("minus") { value = max(value - step, range.lowerBound) }
            VStack(spacing: 0) {
                Text(format(value)).font(.subheadline.bold().monospacedDigit())
                Text(label).font(.caption2).foregroundStyle(Theme.dim).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            button("plus") { value = min(value + step, range.upperBound) }
        }
        .padding(.vertical, 4)
        .background(Theme.raised, in: .rect(cornerRadius: 12))
    }

    private func button(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: icon).font(.caption.bold()).frame(width: 30, height: 34).contentShape(Rectangle())
        }
        .buttonStyle(GMPress())
        .foregroundStyle(.white)
    }
}

struct ExercisePicker: View {
    /// nil = só navegar pela biblioteca (toque abre os detalhes)
    var onPick: ((Exercise) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Query private var customs: [CustomExercise]
    @State private var search = ""
    @State private var info: Exercise?
    @State private var creating = false
    @State private var filter = 0

    private func matches(_ e: Exercise) -> Bool {
        search.isEmpty || e.name.localizedStandardContains(search) || e.group.name.localizedStandardContains(search)
            || e.equipment.localizedStandardContains(search)
    }

    var body: some View {
        GMModal("Exercícios", cancel: onPick == nil ? "Fechar" : "Cancelar") {
            GMSearchField(placeholder: "Buscar exercício", text: $search)
            GMButton("Criar exercício", icon: "plus", kind: .secondary) { creating = true }
            let mine = customs.map(\.exercise).filter(matches).sorted { $0.name < $1.name }
            if !mine.isEmpty {
                GMSection("Meus exercícios") { rows(mine) }
            }
            GMSegmented(options: [(0, "Todos"), (1, "Academia"), (2, "CrossFit")], selection: $filter)
            let cross = Exercise.builtIn.filter { $0.isCrossfit && matches($0) }
            if filter != 1 && !cross.isEmpty {
                GMSection("CrossFit · \(cross.count)") { rows(cross) }
            }
            if filter != 2 {
                ForEach(MuscleGroup.allCases) { g in
                    let items = Exercise.builtIn.filter { $0.group == g && !$0.crossfit && matches($0) }
                    if !items.isEmpty {
                        GMSection("\(g.name) · \(items.count)") { rows(items) }
                    }
                }
            }
        }
        .gmModal(item: $info) { ExerciseInfoView(exercise: $0) }
        .gmModal(isPresented: $creating) {
            CustomExerciseForm(onCreate: { e in
                if let onPick {
                    onPick(e)
                    dismiss()
                }
            })
        }
    }

    private func rows(_ list: [Exercise]) -> some View {
        ForEach(list) { e in
            row(e)
            if e.id != list.last?.id { GMDivider() }
        }
    }

    private func row(_ e: Exercise) -> some View {
        HStack(spacing: 12) {
            ExerciseThumb(exercise: e)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.name).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Text(e.equipment).font(.caption).foregroundStyle(Theme.dim)
            }
            Spacer()
            if onPick != nil {
                GMIconButton(icon: "info", size: 30) { info = e }
            } else {
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.dim)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let onPick {
                onPick(e)
                dismiss()
            } else {
                info = e
            }
        }
    }
}

struct ExerciseThumb: View {
    let exercise: Exercise
    var size: CGFloat = 44

    var body: some View {
        Group {
            if exercise.hasPhotos {
                Image("ex_\(exercise.id)_0").resizable().scaledToFill()
            } else if let url = exercise.remotePhotos?.first {
                AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: {
                    Image(systemName: exercise.group.symbol).font(.system(size: size * 0.45)).foregroundStyle(Theme.dim)
                }
            } else {
                Image(systemName: exercise.isCrossfit ? "figure.cross.training" : exercise.group.symbol)
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(Theme.dim)
            }
        }
        .frame(width: size, height: size)
        .background(Theme.raised)
        .clipShape(.rect(cornerRadius: 10))
    }
}
