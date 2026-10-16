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
    let onPick: (Exercise) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private func matches(_ e: Exercise) -> Bool {
        search.isEmpty || e.name.localizedStandardContains(search) || e.group.name.localizedStandardContains(search)
            || e.equipment.localizedStandardContains(search)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(MuscleGroup.allCases) { g in
                    let items = Exercise.library.filter { $0.group == g && matches($0) }
                    if !items.isEmpty {
                        Section(g.name) {
                            ForEach(items) { e in
                                Button {
                                    onPick(e)
                                    dismiss()
                                } label: {
                                    HStack {
                                        Text(e.name).foregroundStyle(.white)
                                        Spacer()
                                        Text(e.equipment).font(.caption).foregroundStyle(Theme.dim)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Buscar exercício")
            .navigationTitle("Exercícios")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
        }
    }
}
