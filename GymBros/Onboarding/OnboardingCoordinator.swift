import CryptoKit
import Foundation
import Observation
import os

enum OnboardingState: Equatable {
    case notPresented
    /// Fechou o app no meio: na próxima abertura retoma desta etapa
    case inProgress(step: String)
    case completed
    case dismissed
}

/// Estado do tutorial por conta: quem entra numa conta nova no mesmo aparelho também recebe o tutorial.
/// A conta entra na chave só como hash; sem conta, vale a chave do aparelho.
struct OnboardingPersistence {
    static let key = "onboardingTour"
    var defaults: UserDefaults = .standard
    var account: String?

    private var storageKey: String {
        guard let account else { return Self.key }
        let digest = SHA256.hash(data: Data(account.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return Self.key + "." + digest
    }

    var state: OnboardingState {
        get {
            switch defaults.string(forKey: storageKey) {
            case nil: .notPresented
            case "completed": .completed
            case "dismissed": .dismissed
            case let raw?: raw.hasPrefix("step:") ? .inProgress(step: String(raw.dropFirst(5))) : .notPresented
            }
        }
        nonmutating set {
            switch newValue {
            case .notPresented: defaults.removeObject(forKey: storageKey)
            case .inProgress(let step): defaults.set("step:" + step, forKey: storageKey)
            case .completed: defaults.set("completed", forKey: storageKey)
            case .dismissed: defaults.set("dismissed", forKey: storageKey)
            }
        }
    }
}

@MainActor @Observable
final class OnboardingCoordinator {
    static let shared = OnboardingCoordinator()

    let steps: [OnboardingStep]
    let registry: OnboardingTargetRegistry
    private(set) var persistence: OnboardingPersistence
    private(set) var index: Int?
    /// Esperando o elemento da etapa aparecer na tela (troca de aba, layout assentando)
    private(set) var locating = false
    /// Pedido explícito (Ajustes): começa do início mesmo se já concluído
    private(set) var startRequested = false
    /// Alvo que a tela com rolagem deve trazer para o centro (fora da barra de abas)
    private(set) var scrollTarget: OnboardingTarget?
    @ObservationIgnored var settleDelay: Duration = .milliseconds(350)
    @ObservationIgnored var locateTimeout: Duration = .seconds(2)
    @ObservationIgnored private var locateTask: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "com.alonsoalmeida.gymbros", category: "onboarding")
    #if DEBUG
    @ObservationIgnored private var launchOverride: OnboardingState?
    #endif

    init(steps: [OnboardingStep] = OnboardingStep.tour, registry: OnboardingTargetRegistry? = nil,
         persistence: OnboardingPersistence = OnboardingPersistence()) {
        self.steps = steps
        self.registry = registry ?? .shared
        self.persistence = persistence
    }

    var isActive: Bool { index != nil }
    var current: OnboardingStep? { index.map { steps[$0] } }
    var isLast: Bool { index == steps.count - 1 }

    /// Destaque da etapa atual, lido ao vivo do registro (acompanha rolagem e mudanças de layout)
    var spotlight: OnboardingTargetRegistry.Entry? {
        guard let current, !locating else { return nil }
        return registry.spotlight(for: current.targets)
    }

    func requestStart() {
        startRequested = true
    }

    /// `modalOpen`: algo cobre a tela principal. `busy`: operação em andamento (treino), que só um pedido explícito atravessa.
    func startIfEligible(modalOpen: Bool, busy: Bool) {
        guard !isActive, !modalOpen else { return }
        #if DEBUG
        if let launchOverride {
            persistence.state = launchOverride
            self.launchOverride = nil
        }
        #endif
        if startRequested {
            startRequested = false
            go(to: 0, direction: 1)
            return
        }
        guard !busy else { return }
        switch persistence.state {
        case .notPresented:
            go(to: 0, direction: 1)
        case .inProgress(let id):
            go(to: steps.firstIndex { $0.id == id } ?? 0, direction: 1)
        case .completed, .dismissed:
            break
        }
    }

    func next() {
        guard let index else { return }
        if index + 1 < steps.count { go(to: index + 1, direction: 1) } else { finish() }
    }

    func back() {
        guard let index, index > 0 else { return }
        go(to: index - 1, direction: -1)
    }

    func skip() {
        end(as: .dismissed)
    }

    func finish() {
        end(as: .completed)
    }

    /// Login, logout ou troca de conta: o tutorial em andamento para (sem marcar nada) e o estado passa a ser o da conta nova
    func setAccount(_ id: String?) {
        guard persistence.account != id else { return }
        suspend()
        persistence.account = id
    }

    /// Some da tela sem decisão do usuário (tela principal saiu): para sem mudar o estado salvo, para retomar depois
    func suspend() {
        registry.tracking = false
        locateTask?.cancel()
        locateTask = nil
        locating = false
        scrollTarget = nil
        index = nil
    }

    /// A aba mudou: conclui a etapa que pedia para abrir exatamente essa aba
    func tabDidChange(to tab: MainTab?) {
        guard let current, case .openTab(let wanted) = current.interaction, wanted == tab else { return }
        next()
    }

    private func end(as state: OnboardingState) {
        suspend()
        persistence.state = state
    }

    private func go(to i: Int, direction: Int) {
        guard steps.indices.contains(i) else { return finish() }
        locateTask?.cancel()
        registry.tracking = true
        index = i
        let step = steps[i]
        persistence.state = .inProgress(step: step.id)
        guard !step.targets.isEmpty else {
            locating = false
            return
        }
        locating = true
        scrollTarget = step.targets.first { !$0.isInTabBar }
        locateTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: settleDelay)
            let deadline = ContinuousClock.now.advanced(by: locateTimeout)
            while !Task.isCancelled {
                if registry.spotlight(for: step.targets) != nil {
                    locating = false
                    return
                }
                if ContinuousClock.now >= deadline { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !Task.isCancelled, index == i else { return }
            log.error("Etapa \(step.id, privacy: .public) sem elemento visível; pulando. \(self.registry.diagnose(step.targets), privacy: .public)")
            skipUnavailable(from: i, direction: direction)
        }
    }

    private func skipUnavailable(from i: Int, direction: Int) {
        let j = i + direction
        if steps.indices.contains(j) {
            go(to: j, direction: direction)
        } else if direction < 0 {
            go(to: i + 1, direction: 1)
        } else {
            finish()
        }
    }

    #if DEBUG
    /// Ajustes → Desenvolvimento: volta ao estado de primeira utilização e abre o tutorial do início
    func restartForTesting() {
        end(as: .notPresented)
        requestStart()
    }

    /// Ajustes → Desenvolvimento: só zera, para testar o gatilho automático na próxima abertura
    func resetForTesting() {
        end(as: .notPresented)
    }

    /// `-onboardingReset` zera o estado; `-onboardingStep <id>` abre direto numa etapa (capturas de tela).
    /// Aplicado na primeira checagem, quando a conta da sessão já é conhecida.
    func applyLaunchArguments(_ args: [String] = ProcessInfo.processInfo.arguments) {
        if args.contains("-onboardingReset") { launchOverride = .notPresented }
        if let i = args.firstIndex(of: "-onboardingStep"), args.indices.contains(i + 1) {
            launchOverride = .inProgress(step: args[i + 1])
        }
    }
    #endif
}
