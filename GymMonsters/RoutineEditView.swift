import SwiftData
import SwiftUI

struct RoutineEditView: View {
    @Bindable var routine: Routine
    @Environment(\.modelContext) private var context
    @State private var picking = false

    var body: some View {
        List {
            Section("Nome") {
                TextField("Nome da rotina", text: $routine.name)
            }
            Section("Dias") {
                HStack(spacing: 6) {
                    ForEach(weekdaySymbols, id: \.0) { day, label in
                        let on = routine.weekdays.contains(day)
                        Button {
                            if on { routine.weekdays.remove(day) } else { routine.weekdays.insert(day) }
                        } label: {
                            Text(label)
                                .font(.caption.bold())
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .background(on ? Theme.accent : .white.opacity(0.07), in: .rect(cornerRadius: 8))
                                .foregroundStyle(on ? .black : .white)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !routine.items.isEmpty {
                Section("O que essa rotina treina") {
                    let sets = routine.items.flatMap { item in
                        (0..<item.sets).map { _ in SetLog(exerciseID: item.exerciseID, weight: 0, reps: 0, target: 0, done: true) }
                    }
                    BodyPair(intensities: normalized(muscleLoad(sets)))
                        .frame(height: 220)
                }
            }
            Section {
                ForEach(routine.sortedItems) { item in
                    ItemEditor(item: item)
                }
                .onDelete { idx in
                    let items = routine.sortedItems
                    idx.map { items[$0] }.forEach(context.delete)
                    renumber()
                }
                .onMove { from, to in
                    var items = routine.sortedItems
                    items.move(fromOffsets: from, toOffset: to)
                    for (i, it) in items.enumerated() { it.order = i }
                }
                Button { picking = true } label: { Label("Adicionar exercício", systemImage: "plus") }
            } header: {
                Text("Exercícios")
            } footer: {
                Text("A carga não fica na rotina: o app sugere a cada treino a partir do seu histórico.")
            }
        }
        .navigationTitle(routine.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .sheet(isPresented: $picking) {
            ExercisePicker { ex in
                let item = RoutineItem(exerciseID: ex.id, sets: 3, reps: ex.type == .time ? 30 : 10,
                                       rest: 90, order: routine.items.count)
                routine.items.append(item)
            }
        }
        .onDisappear { try? context.save() }
    }

    private func renumber() {
        for (i, it) in routine.sortedItems.enumerated() { it.order = i }
    }
}

private struct ItemEditor: View {
    @Bindable var item: RoutineItem

    var body: some View {
        let ex = Exercise.byID(item.exerciseID)
        VStack(alignment: .leading, spacing: 8) {
            Text(ex?.name ?? item.exerciseID).font(.subheadline.weight(.semibold))
            HStack(spacing: 14) {
                MiniStepper(label: "séries", value: $item.sets, range: 1...10, step: 1)
                MiniStepper(label: ex?.type == .time ? "seg" : "reps", value: $item.reps, range: 1...300, step: ex?.type == .time ? 5 : 1)
                MiniStepper(label: "desc.", value: $item.rest, range: 0...600, step: 15, format: { "\($0)s" })
            }
        }
        .padding(.vertical, 4)
    }
}

struct MiniStepper: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    var format: (Int) -> String = { "\($0)" }

    var body: some View {
        HStack(spacing: 4) {
            Button { value = max(value - step, range.lowerBound) } label: { Image(systemName: "minus") }
            VStack(spacing: 0) {
                Text(format(value)).font(.subheadline.bold().monospacedDigit())
                Text(label).font(.caption2).foregroundStyle(Theme.dim)
            }
            .frame(minWidth: 40)
            Button { value = min(value + step, range.upperBound) } label: { Image(systemName: "plus") }
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
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

    private func matches(_ e: Exercise) -> Bool {
        search.isEmpty || e.name.localizedStandardContains(search) || e.group.name.localizedStandardContains(search)
            || e.equipment.localizedStandardContains(search)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { creating = true } label: { Label("Criar exercício", systemImage: "plus") }
                }
                let mine = customs.map(\.exercise).filter(matches).sorted { $0.name < $1.name }
                if !mine.isEmpty {
                    Section("Meus exercícios") {
                        ForEach(mine) { row($0) }
                    }
                }
                ForEach(MuscleGroup.allCases) { g in
                    let items = Exercise.library.filter { $0.group == g && matches($0) }
                    if !items.isEmpty {
                        Section(g.name) {
                            ForEach(items) { row($0) }
                        }
                    }
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Buscar exercício")
            .navigationTitle("Exercícios")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(onPick == nil ? "OK" : "Cancelar") { dismiss() } } }
            .sheet(item: $info) { ExerciseInfoView(exercise: $0) }
            .sheet(isPresented: $creating) {
                CustomExerciseForm(onCreate: { e in
                    if let onPick {
                        onPick(e)
                        dismiss()
                    }
                })
            }
        }
    }

    private func row(_ e: Exercise) -> some View {
        HStack(spacing: 12) {
            ExerciseThumb(exercise: e)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.name).foregroundStyle(.white)
                Text(e.equipment).font(.caption).foregroundStyle(Theme.dim)
            }
            Spacer()
            if onPick != nil {
                Button { info = e } label: { Image(systemName: "info.circle") }
                    .buttonStyle(.borderless)
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
            } else {
                Image(systemName: exercise.group.symbol)
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(Theme.dim)
            }
        }
        .frame(width: size, height: size)
        .background(.white.opacity(0.06))
        .clipShape(.rect(cornerRadius: 8))
    }
}
