import AppIntents
import SwiftUI
import WidgetKit

// Controles da Central de Controle / tela de bloqueio / Botão de Ação (iOS 18+)

@available(iOS 18.0, *)
struct CompleteSetControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "GymBrosCompleteSet") {
            ControlWidgetButton(action: CompleteSetIntent()) {
                Label("Série feita", systemImage: "checkmark.circle.fill")
            }
        }
        .displayName("Série feita")
        .description("Marca a próxima série do treino e começa o descanso.")
    }
}

@available(iOS 18.0, *)
struct SkipRestControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "GymBrosSkipRest") {
            ControlWidgetButton(action: SkipRestIntent()) {
                Label("Pular descanso", systemImage: "forward.fill")
            }
        }
        .displayName("Pular descanso")
        .description("Termina o descanso do treino.")
    }
}
