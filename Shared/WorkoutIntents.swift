import AppIntents
import Foundation

// Botões do Live Activity. Rodam no processo do app (o iOS abre o app em segundo plano se preciso);
// o app registra o que cada um faz ao iniciar.

enum WorkoutIntentBridge {
    /// Devolvem a frase de confirmação (falada pela Siri / mostrada pelo Botão de Ação)
    @MainActor static var completeSet: (@MainActor () async -> String)?
    @MainActor static var skipRest: (@MainActor () async -> String)?
    @MainActor static var addRound: (@MainActor () -> Void)?
}

struct CompleteSetIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Série feita"
    static var description = IntentDescription("Marca a próxima série do exercício atual e começa o descanso.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let msg = await WorkoutIntentBridge.completeSet?() ?? "Abra um treino no GymBros primeiro."
        return .result(dialog: IntentDialog(stringLiteral: msg))
    }
}

struct SkipRestIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pular descanso"
    static var description = IntentDescription("Termina o descanso e vai para a próxima série.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let msg = await WorkoutIntentBridge.skipRest?() ?? "Abra um treino no GymBros primeiro."
        return .result(dialog: IntentDialog(stringLiteral: msg))
    }
}

struct AddRoundIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "+1 rodada"

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        WorkoutIntentBridge.addRound?()
        return .result()
    }
}
