import AppIntents

/// Atalhos do app: aparecem no app Atalhos, na Siri e para o Botão de Ação
struct GymBrosShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CompleteSetIntent(),
                    phrases: ["Série feita no \(.applicationName)", "Terminei a série no \(.applicationName)",
                              "Marcar série no \(.applicationName)"],
                    shortTitle: "Série feita", systemImageName: "checkmark.circle.fill")
        AppShortcut(intent: SkipRestIntent(),
                    phrases: ["Pular descanso no \(.applicationName)", "Acabou o descanso no \(.applicationName)"],
                    shortTitle: "Pular descanso", systemImageName: "forward.fill")
    }
}
