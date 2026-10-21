import SwiftUI

// Treino ao vivo: enquanto você treina, os amigos veem no mapa onde você está, a atividade e o exercício atual.
// Ligado por padrão (o onboarding explica e deixa desligar); o padrão muda em Mapa > Ajustes, e cada treino pode
// mudar só para ele no chip "Ao vivo" ao começar. O envio vai junto com o status ao vivo, quando houver servidor.

enum LiveShare {
    /// Padrão para os próximos treinos (Mapa > Ajustes)
    static let key = "shareLive"
    /// Escolha feita num treino específico (id do treino → compartilha), só enquanto ele está aberto
    static let overridesKey = "shareLiveWorkouts"
    static let defaultsKeys = [key, overridesKey]
    static let defaultOn = true

    static func isOn(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) as? Bool ?? defaultOn
    }

    /// Este treino compartilha? Sem escolha própria, vale o padrão
    static func isSharing(_ workoutID: String, defaults: UserDefaults = .standard) -> Bool {
        overrides(defaults)[workoutID] ?? isOn(defaults)
    }

    static func set(_ on: Bool, for workoutID: String, defaults: UserDefaults = .standard) {
        if !on { Task { @MainActor in LivePresence.shared.end(workoutID) } }
        var o = overrides(defaults)
        o[workoutID] = on
        defaults.set(o, forKey: overridesKey)
    }

    /// Treino encerrado ou descartado: a escolha dele não vale mais
    static func end(_ workoutID: String, defaults: UserDefaults = .standard) {
        Task { @MainActor in LivePresence.shared.end(workoutID) }
        var o = overrides(defaults)
        guard o.removeValue(forKey: workoutID) != nil else { return }
        defaults.set(o, forKey: overridesKey)
    }

    private static func overrides(_ defaults: UserDefaults) -> [String: Bool] {
        defaults.dictionary(forKey: overridesKey) as? [String: Bool] ?? [:]
    }
}

/// Chip ao lado do lugar, no começo de cada treino: toque liga ou desliga o ao vivo só para este treino
struct LiveShareChip: View {
    let workoutID: String
    @State private var on: Bool

    init(workoutID: String) {
        self.workoutID = workoutID
        _on = State(initialValue: LiveShare.isSharing(workoutID))
    }

    var body: some View {
        Button {
            on.toggle()
            LiveShare.set(on, for: workoutID)
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            Label(on ? "Ao vivo para amigos" : "Só você", systemImage: on ? "dot.radiowaves.left.and.right" : "eye.slash")
                .font(.caption.bold())
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(on ? Theme.accent.opacity(0.18) : Theme.raised, in: .capsule)
                .foregroundStyle(on ? Theme.accent : .white)
        }
        .buttonStyle(GMPress())
        .accessibilityLabel(on ? "Treino ao vivo para amigos, ligado" : "Treino ao vivo para amigos, desligado")
        .accessibilityHint("Toque para \(on ? "não compartilhar" : "compartilhar") a sua localização neste treino")
    }
}
