import Foundation
import Observation

/// WOD em andamento, fora da tela do cronômetro: dá para minimizar e navegar pelo app (como no treino de musculação)
/// e continua depois, mesmo se o app fechar. O relógio é de parede, então o tempo corre com a tela fechada.
struct WodRunState: Codable, Equatable {
    var wod: Wod
    /// Quando o treino abriu: o treino completo (aquecimento, força…) conta daqui, não só o WOD
    var openedAt = Date.now
    var startedAt: Date?
    var pausedAt: Date?
    var pausedTotal: TimeInterval = 0
    var countdownEnd: Date?
    var rounds = 0
    var gymID: UUID?
    var placeAsked = false
    var liveID = UUID().uuidString
    /// "Começar treino": relógio do treino inteiro (aquecimento, força… e o WOD)
    var sessionStart: Date?
    /// Parte na tela (índice em `wod.parts`); igual a `wod.parts.count` é o WOD
    var phase = 0
    /// Começo do trecho atual da parte em andamento (o relógio dela soma `partSeconds` mais o tempo desde aqui)
    var phaseStart: Date?
    /// Parte em andamento: a mais adiantada que você alcançou. Voltar numa anterior só mostra o tempo feito lá
    var workingPhase: Int?
    /// Tempo já feito em cada parte, sem o trecho em andamento
    var partSeconds: [Int: TimeInterval]?
    /// Início do cronômetro de cada parte (força "a cada 2'"…): navegar não zera
    /// Rodadas de cada bloco, nos WODs em blocos
    var blockRounds: [Int] = []
    /// Cargas registradas em cada parte e no WOD
    var loads: [WodLoad] = []
    var partTimers: [Int: Date]?
    /// Linhas riscadas no chipper
    var checked: [Int] = []

    var onWod: Bool { phase >= wod.parts.count }

    var working: Int { workingPhase ?? phase }

    /// Tempo feito na parte `i`; só a parte em andamento corre
    func partElapsed(_ i: Int, now: Date) -> TimeInterval {
        (partSeconds?[i] ?? 0) + (i == working ? max(now.timeIntervalSince(phaseStart ?? now), 0) : 0)
    }

    /// Só mostra a parte `i`: o relógio continua na parte em andamento
    mutating func view(_ i: Int) {
        phase = i
    }

    /// A parte `i` passa a ser a em andamento: o relógio dela continua de onde parou e o da anterior para
    mutating func work(on i: Int, now: Date = .now) {
        sessionStart = sessionStart ?? now
        if phaseStart != nil, i != working {
            partSeconds = (partSeconds ?? [:]).merging([working: partElapsed(working, now: now)]) { $1 }
        }
        if phaseStart == nil || i != working {
            workingPhase = i
            phaseStart = now
        }
        phase = i
    }

    /// Zera o relógio da parte `i` (na em andamento, recomeça agora)
    mutating func resetPart(_ i: Int, now: Date = .now) {
        partSeconds?[i] = nil
        if i == working { phaseStart = now }
    }

    func elapsed(_ now: Date) -> TimeInterval {
        guard let startedAt else { return 0 }
        return (pausedAt ?? now).timeIntervalSince(startedAt) - pausedTotal
    }

    /// Bloco atual do WOD em blocos (nil fora deles ou no descanso)
    func workBlock(_ now: Date) -> Int? {
        guard let seg = wod.format.segment(at: Int(elapsed(now)))?.segment, !seg.rest else { return nil }
        return seg.block
    }

    /// +1 rodada: no WOD em blocos, vai para o bloco em que está
    mutating func addRound(_ now: Date = .now) {
        guard case .intervals(let b, _, _) = wod.format else { return rounds += 1 }
        guard let i = workBlock(now) else { return }
        if blockRounds.count < b.count { blockRounds += Array(repeating: 0, count: b.count - blockRounds.count) }
        blockRounds[i] += 1
    }

    mutating func removeRound(_ now: Date = .now) {
        guard case .intervals = wod.format else { return rounds = max(rounds - 1, 0) }
        guard let i = workBlock(now), blockRounds.indices.contains(i) else { return }
        blockRounds[i] = max(blockRounds[i] - 1, 0)
    }

    func roundsShown(_ now: Date) -> Int {
        guard case .intervals = wod.format else { return rounds }
        return workBlock(now).flatMap { blockRounds.indices.contains($0) ? blockRounds[$0] : 0 } ?? 0
    }
}

@MainActor @Observable
final class WodRun {
    static let shared = WodRun()
    static let key = "activeWod"

    var state: WodRunState? {
        didSet {
            guard state != oldValue else { return }
            UserDefaults.standard.set(state.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.key)
        }
    }

    private init() {
        state = UserDefaults.standard.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(WodRunState.self, from: $0) }
        if state != nil { bridgeRounds() }
    }

    /// Abre este WOD; se já tem um em andamento, é ele que continua (um treino por vez)
    func open(_ wod: Wod) {
        if state == nil { state = WodRunState(wod: wod) }
        bridgeRounds()
    }

    private func bridgeRounds() {
        WorkoutIntentBridge.addRound = { [weak self] in self?.state?.addRound() }
    }

    func end() {
        if let id = state?.liveID { LiveShare.end(id) }
        state = nil
        WorkoutIntentBridge.addRound = nil
        Task { await LiveWod.end() }
    }
}
