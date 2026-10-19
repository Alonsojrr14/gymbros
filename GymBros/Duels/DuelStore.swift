import Foundation
import Observation
import SwiftData

// Estado do X1 no app e o contrato com o servidor. Quem responde é escolhido em Backend.swift:
// MockDuelBackend (pessoas simuladas no aparelho) ou CloudKitDuelBackend.

protocol DuelBackend: Sendable {
    /// X1 em que você está (desafiou ou foi desafiado), dos últimos 30 dias
    func duels(now: Date) async throws -> [RemoteDuel]
    /// Desafia alguém; devolve o desafio criado
    func challenge(_ opponent: DuelPerson, from me: DuelPerson, metric: DuelMetric, now: Date) async throws -> RemoteDuel
    /// Aceita ou recusa um desafio recebido; ao aceitar, `me` leva o bro que vai te representar
    func respond(to duelID: String, accept: Bool, as me: DuelPerson, now: Date) async throws
    /// Informa o seu valor no X1 (calculado das suas atividades)
    func report(_ value: Int, for duelID: String, now: Date) async throws
}

/// X1 visto pela caixa de entrada (ver `DuelStore.notices`)
struct DuelNotice: Identifiable, Equatable {
    let id: String
    let opponent: DuelPerson
    /// Você desafiou (false: você foi desafiado)
    let iChallenged: Bool
    let metric: DuelMetric
    let phase: DuelPhase
    let createdAt: Date
    let acceptedAt: Date?
    let endsAt: Date?
    let expiresAt: Date
    /// Placar final (só encerrados)
    let score: DuelScore?

    var resultText: String? { score.map { Duels.summary($0, opponent: opponent.name, metric: metric) } }
}

@MainActor @Observable
final class DuelStore {
    static let shared = DuelStore()

    var backend: any DuelBackend = MockDuelBackend()
    var moderation: ModerationStore = .shared
    /// Suas atividades (trocado nos testes)
    var activities: @MainActor () -> [DuelActivity] = {
        ((try? AppData.container.mainContext.fetch(FetchDescriptor<Activity>())) ?? []).map(\.duelActivity)
    }
    /// Você como aparece para o adversário
    var me: @MainActor () -> DuelPerson = {
        let monsters = (try? AppData.container.mainContext.fetch(FetchDescriptor<Monster>())) ?? []
        let main = monsters.first { $0.uuid == MainMonster.id } ?? monsters.first { $0.isStarter }
        return DuelPerson(id: "me", name: UserDefaults.standard.string(forKey: "trainerName") ?? "", formID: main?.lastFormID ?? MonsterForm.egg.id)
    }
    /// Bros da coleção que podem lutar (ovo não entra no X1), na ordem da coleção
    var fighters: @MainActor () -> [Monster] = {
        let monsters = (try? AppData.container.mainContext.fetch(FetchDescriptor<Monster>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        return monsters.filter { (MonsterForm.byID($0.lastFormID) ?? .egg).stage != .egg }
    }
    /// Quem te representa em cada X1 (id do X1 → bro), só no aparelho
    static let fightersKey = "duelMonsters"
    /// Lido direto do UserDefaults: vai com a conta (`AccountData.userKeys`) e some ao sair dela
    private var representatives: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: Self.fightersKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: Self.fightersKey) }
    }
    private(set) var all: [RemoteDuel] = []
    private(set) var loaded = false
    private(set) var lastError: String?
    /// Quem recusou seu desafio por ter te bloqueado (o servidor avisa ao desafiar)
    private(set) var blockedBy: Set<String> = []
    /// Último valor seu informado por X1 (não reenvia o mesmo)
    private var reportedByMe: [String: Int] = [:]

    /// Sem os de quem você bloqueou
    var duels: [RemoteDuel] {
        let blocked = blockedIDs
        return all.filter { !blocked.contains($0.opponent(of: "me").id) }
    }

    func refresh(now: Date = .now) async {
        do {
            all = try await backend.duels(now: now).map(local)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        loaded = true
        await reportMine(now: now)
    }

    /// Manda o seu valor dos X1 em andamento (e do que acabou de acabar) quando mudou
    private func reportMine(now: Date) async {
        let acts = activities()
        for d in all where d.acceptedAt != nil {
            if case let .finished(ended) = d.phase(now: now), now.timeIntervalSince(ended) > 3600 { continue }
            let v = Duels.myValue(d, activities: acts, now: now)
            guard reportedByMe[d.id] != v else { continue }
            if (try? await backend.report(v, for: d.id, now: now)) != nil { reportedByMe[d.id] = v }
        }
    }

    /// Bro sugerido: o principal, se já chocou; senão o primeiro chocado
    func defaultFighter() -> Monster? {
        let list = fighters()
        return list.first { $0.uuid == MainMonster.id } ?? list.first
    }

    /// Você no X1 com um bro específico (o nome é o seu; o bro, o escolhido)
    func person(with monster: UUID?) -> DuelPerson {
        var p = me()
        if let m = fighters().first(where: { $0.uuid == monster }) { p.formID = m.lastFormID }
        return p
    }

    /// Bro que te representa num X1 (nil: o X1 é de antes da escolha)
    func representative(_ duelID: String) -> Monster? {
        guard let id = representatives[duelID].flatMap(UUID.init) else { return nil }
        return fighters().first { $0.uuid == id }
    }

    func refusal(_ opponentID: String, now: Date = .now) -> DuelRefusal? {
        if fighters().isEmpty { return .noHatchedBro }
        return Duels.refusal(me: "me", opponent: opponentID, duels: all, blocked: blockedIDs, blockedBy: blockedBy, now: now)
    }

    func challenge(_ opponent: DuelPerson, metric: DuelMetric, monster: UUID? = nil, now: Date = .now) async throws {
        if let r = refusal(opponent.id, now: now) { throw r }
        let fighter = monster ?? defaultFighter()?.uuid
        do {
            let duel = try await backend.challenge(opponent, from: person(with: fighter), metric: metric, now: now)
            if let fighter { representatives[duel.id] = fighter.uuidString }
            all.append(local(duel))
        } catch DuelRefusal.blocked {
            blockedBy.insert(opponent.id)
            throw DuelRefusal.blocked
        }
    }

    func respond(_ duel: RemoteDuel, accept: Bool, monster: UUID? = nil, now: Date = .now) async throws {
        if accept, fighters().isEmpty { throw DuelRefusal.noHatchedBro }
        if accept, let r = Duels.acceptRefusal(duel, me: "me", duels: all, blocked: blockedIDs, now: now) { throw r }
        let fighter = monster ?? defaultFighter()?.uuid
        try await backend.respond(to: duel.id, accept: accept, as: person(with: fighter), now: now)
        if accept, let fighter { representatives[duel.id] = fighter.uuidString }
        if let i = all.firstIndex(where: { $0.id == duel.id }) {
            all[i].answer = accept ? .accepted : .declined
            all[i].answeredAt = now
            all[i] = local(all[i])
        }
    }

    func duel(_ id: String) -> RemoteDuel? { all.first { $0.id == id } }

    func score(_ duel: RemoteDuel, now: Date = .now) -> DuelScore { Duels.score(duel, activities: activities(), now: now) }

    func records(now: Date = .now) -> [DuelRecord] { Duels.records(duels, activities: activities(), now: now) }

    /// Para a caixa de entrada: os X1 que te envolvem, com o que uma notificação precisa
    func notices(now: Date = .now) -> [DuelNotice] {
        let acts = activities()
        return duels.map { d in
            let phase = d.phase(now: now)
            var score: DuelScore?
            if case .finished = phase { score = Duels.score(d, activities: acts, now: now) }
            return DuelNotice(id: d.id, opponent: d.opponent(of: "me"), iChallenged: d.challenger.id == "me", metric: d.metric, phase: phase,
                              createdAt: d.createdAt, acceptedAt: d.acceptedAt, endsAt: d.endsAt, expiresAt: d.expiresAt, score: score)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    func reset() {
        all = []
        blockedBy = []
        reportedByMe = [:]
        loaded = false
        lastError = nil
    }

    private var blockedIDs: Set<String> { Set(moderation.blocked.map(\.id)) }

    /// Seu id no servidor vira "me", como no resto do app
    private func local(_ d: RemoteDuel) -> RemoteDuel {
        guard let me = Cloud.knownID else { return withFighter(d) }
        func swap(_ p: DuelPerson) -> DuelPerson { p.id == me ? DuelPerson(id: "me", name: p.name, formID: p.formID) : p }
        var out = RemoteDuel(id: d.id, challenger: swap(d.challenger), challenged: swap(d.challenged), metric: d.metric, createdAt: d.createdAt,
                             answer: d.answer, answeredAt: d.answeredAt)
        out.reported = Dictionary(d.reported.map { ($0.key == me ? "me" : $0.key, $0.value) }, uniquingKeysWith: { a, _ in a })
        return withFighter(out)
    }

    /// O seu lado mostra a forma atual do bro escolhido (ele pode ter evoluído durante o X1)
    private func withFighter(_ d: RemoteDuel) -> RemoteDuel {
        guard let m = representative(d.id) else { return d }
        var out = d
        if out.challenger.id == "me" { out.challenger.formID = m.lastFormID }
        if out.challenged.id == "me" { out.challenged.formID = m.lastFormID }
        return out
    }
}

// MARK: - Servidor simulado

struct MockDuelBackend: DuelBackend {
    func duels(now: Date) async throws -> [RemoteDuel] { await MockDuelServer.shared.duels(now: now) }

    func challenge(_ opponent: DuelPerson, from me: DuelPerson, metric: DuelMetric, now: Date) async throws -> RemoteDuel {
        try await MockDuelServer.shared.challenge(opponent, from: me, metric: metric, now: now)
    }

    func respond(to duelID: String, accept: Bool, as me: DuelPerson, now: Date) async throws {
        try await MockDuelServer.shared.respond(to: duelID, accept: accept, now: now)
    }

    func report(_ value: Int, for duelID: String, now: Date) async throws {}
}

/// X1 sem servidor: seus desafios e respostas ficam no aparelho. As pessoas simuladas (amigos e gente das ligas de
/// exemplo) respondem sozinhas alguns segundos depois (aceitam na maioria das vezes), treinam durante o X1 e, de vez em
/// quando, desafiam você. Tudo determinístico pelo id do desafio.
actor MockDuelServer {
    static let shared = MockDuelServer()
    static let key = "mockDuels"

    struct State: Codable {
        var sent: [RemoteDuel] = []
        var answers: [String: Reply] = [:]
        var blockedBy: [String] = []
    }

    struct Reply: Codable {
        let answer: DuelAnswer
        let date: Date
    }

    private let defaults: UserDefaults
    /// Pessoas simuladas também desafiam você (desligado nos testes que não tratam disso)
    private let simulatedIncoming: Bool

    init(defaults: UserDefaults = .standard, simulatedIncoming: Bool = true) {
        self.defaults = defaults
        self.simulatedIncoming = simulatedIncoming
    }

    /// Lido do aparelho a cada vez: trocar de conta troca o servidor simulado (AccountSync.socialKeys)
    private var state: State {
        get { defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(State.self, from: $0) } ?? State() }
        set { if let data = try? JSONEncoder().encode(newValue) { defaults.set(data, forKey: Self.key) } }
    }

    /// Quem existe no "servidor"
    static var people: [DuelPerson] {
        MockFriendsBackend.directory.map { DuelPerson(id: $0.id, name: $0.name, formID: $0.formID) }
    }

    func duels(now: Date) -> [RemoteDuel] {
        var out = state.sent.map { simulate($0, now: now) }
        out += incoming(existing: out, now: now)
        return out
    }

    func challenge(_ opponent: DuelPerson, from me: DuelPerson, metric: DuelMetric, now: Date) throws -> RemoteDuel {
        guard let person = Self.people.first(where: { $0.id == opponent.id }) else { throw DuelRefusal.notFound }
        if state.blockedBy.contains(opponent.id) { throw DuelRefusal.blocked }
        if duels(now: now).contains(where: { $0.isPair("me", opponent.id) && $0.isOpen(now: now) }) { throw DuelRefusal.alreadyOpen }
        let duel = RemoteDuel(id: UUID().uuidString, challenger: me, challenged: person, metric: metric, createdAt: now)
        state.sent.append(duel)
        return duel
    }

    func respond(to duelID: String, accept: Bool, now: Date) throws {
        let all = duels(now: now)
        guard let duel = all.first(where: { $0.id == duelID }) else { throw DuelRefusal.notPending }
        if accept, let r = Duels.acceptRefusal(duel, me: "me", duels: all, blocked: [], now: now) { throw r }
        guard duel.challenged.id == "me", case .pending = duel.phase(now: now) else { throw DuelRefusal.notPending }
        state.answers[duelID] = Reply(answer: accept ? .accepted : .declined, date: now)
    }

    /// Para testes: faz uma pessoa simulada agir como quem te bloqueou
    func setBlockedBy(_ ids: [String]) {
        state.blockedBy = ids
    }

    func reset() { defaults.removeObject(forKey: Self.key) }

    /// Resposta automática de uma pessoa simulada: entre 3 e 9 s depois, aceita em 80% das vezes
    static func reply(to duel: RemoteDuel) -> Reply {
        var rng = SeededRandom(seed: "\(duel.id)-x1")
        let delay = 3 + rng.next() * 6
        return Reply(answer: rng.next() < 0.8 ? .accepted : .declined, date: duel.createdAt.addingTimeInterval(delay))
    }

    /// Quanto a pessoa simulada já fez: 1 a 3 treinos espalhados pela janela, o total sorteado pela métrica
    static func simulatedValue(_ duel: RemoteDuel, now: Date) -> Int {
        guard let start = duel.acceptedAt else { return 0 }
        var rng = SeededRandom(seed: "\(duel.id)-placar")
        let range: ClosedRange<Double> = switch duel.metric {
        case .xp: 60...260
        case .treinos: 1...3
        case .minutos: 40...150
        case .distancia: 3_000...14_000
        case .calorias: 250...950
        }
        let sessions = 1 + Int(rng.next() * 3)
        let total = range.lowerBound + rng.next() * (range.upperBound - range.lowerBound)
        var value = 0
        for _ in 0..<sessions {
            let at = start.addingTimeInterval(rng.next() * Duels.window)
            if at <= now { value += duel.metric == .treinos ? 1 : Int(total / Double(sessions)) }
        }
        return value
    }

    private func simulate(_ duel: RemoteDuel, now: Date) -> RemoteDuel {
        var d = duel
        let other = d.opponent(of: "me").id
        if d.answer == nil, d.challenger.id == "me" {
            let r = Self.reply(to: d)
            if r.date <= now, r.date < d.expiresAt {
                d.answer = r.answer
                d.answeredAt = r.date
            }
        }
        d.reported[other] = Self.simulatedValue(d, now: now)
        return d
    }

    /// Desafios das pessoas simuladas: até um por dia, nos últimos 3 dias
    private func incoming(existing: [RemoteDuel], now: Date) -> [RemoteDuel] {
        guard simulatedIncoming else { return [] }
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var out: [RemoteDuel] = []
        let people = Self.people
        for back in (0...3).reversed() {
            guard let day = cal.date(byAdding: .day, value: -back, to: today) else { continue }
            let stamp = Int(day.timeIntervalSince1970 / 86_400)
            var rng = SeededRandom(seed: "x1-\(stamp)")
            guard rng.next() < 0.7, !people.isEmpty else { continue }
            let person = people[Int(rng.next() * Double(people.count)) % people.count]
            let metric = DuelMetric.allCases[Int(rng.next() * Double(DuelMetric.allCases.count)) % DuelMetric.allCases.count]
            let at = day.addingTimeInterval((8 + rng.next() * 12) * 3600)
            guard at <= now else { continue }
            let busy = (existing + out).contains { $0.isPair("me", person.id) && $0.createdAt <= at && $0.isOpen(now: at) }
            guard !busy, !state.blockedBy.contains(person.id) else { continue }
            var duel = RemoteDuel(id: "x1-\(person.id)-\(stamp)", challenger: person, challenged: DuelPerson(id: "me", name: "", formID: ""),
                                  metric: metric, createdAt: at)
            if let reply = state.answers[duel.id] {
                duel.answer = reply.answer
                duel.answeredAt = reply.date
            }
            out.append(simulate(duel, now: now))
        }
        return out
    }
}
