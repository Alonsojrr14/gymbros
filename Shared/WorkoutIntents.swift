import AppIntents
import Foundation

// Botões do Live Activity. Rodam no processo do app (o iOS abre o app em segundo plano se preciso);
// o app registra o que cada um faz ao iniciar.

enum WorkoutIntentBridge {
    @MainActor static var completeSet: (@MainActor () async -> Void)?
    @MainActor static var skipRest: (@MainActor () async -> Void)?
}

struct CompleteSetIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Série feita"
    static var description = IntentDescription("Marca a próxima série do exercício atual e começa o descanso.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        await WorkoutIntentBridge.completeSet?()
        return .result()
    }
}

struct SkipRestIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pular descanso"

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        await WorkoutIntentBridge.skipRest?()
        return .result()
    }
}
