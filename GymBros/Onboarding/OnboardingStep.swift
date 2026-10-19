import SwiftUI

/// Abas da tela principal (mesmos números usados pelo `GMTabBar` em `MainView`)
enum MainTab: Int {
    case home, train, leagues, map, history
}

/// Elementos reais da interface que o tutorial pode destacar
enum OnboardingTarget: String, CaseIterable {
    case monster, logActivity, homeShortcuts
    case trainTab, leaguesTab, mapTab, historyTab, broTab
    case trainToday

    /// Fica na barra de abas, que é a única coisa que pode cobrir os outros alvos
    var isInTabBar: Bool {
        switch self {
        case .trainTab, .leaguesTab, .mapTab, .historyTab, .broTab: true
        default: false
        }
    }
}

/// Formato do recorte, acompanhando o formato real do elemento
enum SpotlightShape: Equatable {
    case rounded(CGFloat)
    case capsule
    case circle
}

struct OnboardingStep: Identifiable, Equatable {
    enum Placement { case auto, above, below }

    enum Interaction: Equatable {
        case explain
        /// Só termina quando a aba abre: tocando no destaque ou em "Avançar"
        case openTab(MainTab)
    }

    let id: String
    let title: String
    let message: String
    var targets: [OnboardingTarget] = []
    /// Aba em que a etapa acontece; o coordenador navega até ela antes de destacar
    var tab: MainTab?
    var placement: Placement = .auto
    var interaction: Interaction = .explain
    var hint: String?
}

extension OnboardingStep {
    static let tour: [OnboardingStep] = [
        OnboardingStep(id: "bro", title: "Este é o seu bro",
                       message: "Ele choca com 60 XP e evolui com os seus treinos. O balão mostra o humor dele: dias sem treinar e ele perde a cor.",
                       targets: [.monster], tab: .home),
        OnboardingStep(id: "registrar", title: "Registre qualquer atividade",
                       message: "Corrida, vôlei, bike, o que você fizer. Duração e esforço viram XP e somam em Força, Resistência, Agilidade e Técnica.",
                       targets: [.logActivity], tab: .home),
        OnboardingStep(id: "aba-treino", title: "Musculação guiada",
                       message: "Rotinas por dia da semana, cargas sugeridas pelo seu histórico e timer de descanso.",
                       targets: [.trainTab], tab: .home, placement: .above,
                       interaction: .openTab(.train), hint: "Toque em Treino para continuar."),
        OnboardingStep(id: "treino-hoje", title: "O treino de hoje",
                       message: "A rotina do dia aparece aqui para começar com um toque. Sem rotina? Use um modelo pronto em Minhas rotinas ou faça um treino livre.",
                       targets: [.trainToday], tab: .train, placement: .below),
        OnboardingStep(id: "ligas", title: "Ligas com a galera",
                       message: "Rankings com amigos: cada check-in de treino pontua e dá XP ao bro que te representa na liga.",
                       targets: [.leaguesTab], tab: .train, placement: .above),
        OnboardingStep(id: "mapa-historico", title: "Mapa e histórico",
                       message: "No Mapa ficam suas academias e os percursos com GPS. No Histórico, todas as atividades, inclusive as do Apple Saúde.",
                       targets: [.mapTab, .historyTab], tab: .train, placement: .above),
        OnboardingStep(id: "voltar-bro", title: "O bro fica no centro",
                       message: "Ele está sempre na barra. É por ele que você volta à tela inicial.",
                       targets: [.broTab], tab: .train, placement: .above,
                       interaction: .openTab(.home), hint: "Toque no bro para voltar ao início."),
        OnboardingStep(id: "atalhos", title: "Amigos, coleção e ajustes",
                       message: "Adicione amigos, veja seus bros e conquistas e, em Ajustes, configure lembretes, Apple Saúde e backup. O tutorial também fica lá.",
                       targets: [.homeShortcuts], tab: .home, placement: .below),
        OnboardingStep(id: "pronto", title: "Bora treinar!",
                       message: "Registre sua primeira atividade e veja seu bro crescer.",
                       tab: .home),
    ]
}
