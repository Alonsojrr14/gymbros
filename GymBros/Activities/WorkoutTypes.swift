import HealthKit
import SwiftData
import SwiftUI

extension WorkoutType {
    var kind: ActivityKind { HealthSync.kind(for: type) }

    /// O tipo equivalente às categorias antigas do app
    static func of(_ kind: ActivityKind) -> WorkoutType { byID(HealthSync.activityType(kind).rawValue) ?? other }

    /// Os 12 de sempre, na ordem da grade antiga (atalhos de quem ainda não tem histórico)
    static let classics: [WorkoutType] = ActivityKind.allCases.map(of)
}

extension Activity {
    /// Tipo escolhido (ou importado do Saúde); sem ele, o equivalente da categoria
    var workoutType: WorkoutType { WorkoutType.byID(healthType) ?? .of(kind) }
    var typeName: String { workoutType.name }
    var typeSymbol: String { workoutType.symbol }
}

// MARK: - Seletor

/// Atalhos com o que você mais faz e "Todas" para os ~80 tipos do Apple Saúde, com busca
struct ActivityTypePicker: View {
    @Binding var type: UInt
    @Query(sort: \Activity.date, order: .reverse) private var history: [Activity]
    /// Tipos escolhidos por último (ids, mais recente primeiro): entram nos atalhos mesmo antes de salvar
    @AppStorage("recentWorkoutTypes") private var recentRaw = ""
    @State private var browsing = false
    /// Atalhos fixados ao abrir a tela: escolher não reordena nada
    @State private var slots: [UInt] = []

    private var recent: [UInt] { recentRaw.split(separator: ",").compactMap { UInt($0) } }

    /// Os 7 mais frequentes: treinos salvos recentemente + escolhas recentes; os clássicos completam
    private func ranked() -> [UInt] {
        var score: [UInt: Double] = [:]
        for a in history.prefix(60) { score[a.workoutType.id, default: 0] += 1 }
        for (i, id) in recent.prefix(10).enumerated() { score[id, default: 0] += 2 - Double(i) * 0.15 }
        let classics = WorkoutType.classics.map(\.id)
        let used = score.keys.sorted { a, b in
            score[a]! != score[b]! ? score[a]! > score[b]! : (classics.firstIndex(of: a) ?? 99, a) < (classics.firstIndex(of: b) ?? 99, b)
        }
        var out: [UInt] = []
        for id in used + classics where WorkoutType.byID(id) != nil && !out.contains(id) && out.count < 7 { out.append(id) }
        return out
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(slots.compactMap { WorkoutType.byID($0) }) { t in
                tile(t.name, t.symbol, on: t.id == type) { type = t.id }
            }
            tile("Todas", "magnifyingglass", on: false) { browsing = true }
                .accessibilityHint("Abre a lista com todos os tipos de treino")
        }
        .onAppear {
            guard slots.isEmpty else { return }
            slots = ranked()
            place(type)
        }
        .onChange(of: type) { _, t in
            place(t)
            remember(t)
        }
        .sheet(isPresented: $browsing) {
            WorkoutTypeList(selection: $type)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(Theme.radiusXL)
                .presentationBackground(Theme.bg)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }

    /// Escolhido fora dos atalhos: fica no último lugar (e continua lá se você trocar de novo)
    private func place(_ t: UInt) {
        guard !slots.contains(t), !slots.isEmpty else { return }
        slots[slots.count - 1] = t
    }

    private func remember(_ t: UInt) {
        recentRaw = ([t] + recent.filter { $0 != t }).prefix(10).map(String.init).joined(separator: ",")
    }

    private func tile(_ name: String, _ symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.title2).frame(height: 30)
                Text(name).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 66)
            .background(on ? Theme.accent.opacity(0.2) : Theme.raised, in: .rect(cornerRadius: Theme.radiusM))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusM).stroke(on ? Theme.accent : .clear, lineWidth: 1.5))
            .foregroundStyle(on ? Theme.accent : .white)
        }
        .buttonStyle(GMPress())
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Todos os tipos, por seção, com busca
struct WorkoutTypeList: View {
    @Binding var selection: UInt
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            let found = WorkoutType.search(query)
            List {
                ForEach(WorkoutType.Section.allCases, id: \.self) { section in
                    let items = found.filter { $0.section == section }
                    if !items.isEmpty {
                        SwiftUI.Section(section.rawValue) {
                            ForEach(items) { t in row(t) }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .overlay {
                if found.isEmpty { ContentUnavailableView.search(text: query) }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Buscar treino")
            .navigationTitle("Tipo de treino")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } }
            }
        }
    }

    private func row(_ t: WorkoutType) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            selection = t.id
            dismiss()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: t.symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(t.id == selection ? .black : Theme.accent)
                    .frame(width: 36, height: 36)
                    .background(t.id == selection ? Theme.accent : Theme.accent.opacity(0.15), in: .rect(cornerRadius: Theme.radiusS))
                Text(t.name).foregroundStyle(.white)
                Spacer()
                if t.id == selection { Image(systemName: "checkmark").font(.body.bold()).foregroundStyle(Theme.accent) }
            }
        }
        .listRowBackground(Theme.card)
        .accessibilityAddTraits(t.id == selection ? .isSelected : [])
    }
}
