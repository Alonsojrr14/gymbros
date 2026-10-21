import Foundation
import Observation
import SwiftData
import UserNotifications

// Troca de bros entre amigos, 1 por 1: você oferece um bro seu e pede um da pessoa; ela aceita ou recusa em até 48 h.
// Ovos não entram. O bro chega com a forma e o XP que tinha (`SnapshotBase`) e evolui dali com os treinos do novo
// dono; o XP dos treinos antigos vai com ele. Quem responde é o TradeBackend (por enquanto o MockTradeBackend).

/// Um bro como aparece na troca (o seu ou o do amigo)
struct TradeBro: Codable, Hashable, Identifiable, Sendable {
    /// `Monster.uuid` no aparelho do dono
    let id: String
    let name: String
    let formID: String
    let xp: Int
    /// Atributos de tudo o que ele treinou (rawValue → valor)
    var attributes: [String: Double] = [:]
    /// De quem é o XP: cada dono que o treinou e quanto, do primeiro ao atual (soma = `xp`)
    var history: [OwnerXP] = []

    var form: MonsterForm { MonsterForm.byID(formID) ?? .egg }
    var isEgg: Bool { form.stage == .egg }
}

struct TradePerson: Codable, Hashable, Sendable {
    let id: String
    let name: String
    let formID: String

    var form: MonsterForm { MonsterForm.byID(formID) ?? .egg }
}

enum TradeAnswer: String, Codable, Sendable { case accepted, declined, canceled }

/// Proposta: `from` dá `give` e recebe `get` de `to`
struct TradeProposal: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let from: TradePerson
    let to: TradePerson
    let give: TradeBro
    let get: TradeBro
    let createdAt: Date
    var answer: TradeAnswer?
    var answeredAt: Date?

    static let window: TimeInterval = 48 * 60 * 60
    var expiresAt: Date { createdAt.addingTimeInterval(Self.window) }
    func isPending(now: Date) -> Bool { answer == nil && now < expiresAt }
    var isDone: Bool { answer == .accepted }

    /// Do ponto de vista de "me": o que eu dou, o que recebo e com quem
    var mine: TradeBro { from.id == "me" ? give : get }
    var theirs: TradeBro { from.id == "me" ? get : give }
    var friend: TradePerson { from.id == "me" ? to : from }
}

enum TradeRefusal: LocalizedError, Equatable {
    case egg, main, league(String), inDuel, busy, notPending, gone

    var errorDescription: String? {
        switch self {
        case .egg: "Ovos não entram em troca."
        case .main: "É o seu principal. Escolha outro principal na Box antes de trocar."
        case .league(let name): "Representa você na liga \(name)."
        case .inDuel: "Está num X1 agora."
        case .busy: "Já está numa troca em andamento."
        case .notPending: "Essa troca não está mais aberta."
        case .gone: "Esse bro não está mais com você."
        }
    }

    /// Curto, para a etiqueta no card do bro
    var tag: String {
        switch self {
        case .egg: "Ovo"
        case .main: "Principal"
        case .league: "Em liga"
        case .inDuel: "Em X1"
        case .busy: "Em troca"
        case .notPending, .gone: "Indisponível"
        }
    }
}

// MARK: - Livro das trocas no aparelho

/// O que as trocas mudam no jogo: de onde parte quem chegou (`bases`) e quem saiu (`gone`), para o XP dos treinos
/// antigos dele não passar para outro bro. Guardado na conta (`AccountData.userKeys`).
enum TradeLedger {
    static let basesKey = "tradeBases"
    static let goneKey = "tradeGone"
    static let appliedKey = "tradeApplied"
    /// Trocas que já viraram notificação (aceita ou oferta nova), para avisar uma vez só
    static let notifiedKey = "tradeNotified"
    static let keys = [basesKey, goneKey, appliedKey, notifiedKey]

    static func bases(_ d: UserDefaults = .standard) -> [UUID: SnapshotBase] {
        let raw = d.data(forKey: basesKey).flatMap { try? JSONDecoder().decode([String: SnapshotBase].self, from: $0) } ?? [:]
        return Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in UUID(uuidString: k).map { ($0, v) } })
    }

    static func gone(_ d: UserDefaults = .standard) -> Set<UUID> {
        Set((d.stringArray(forKey: goneKey) ?? []).compactMap(UUID.init))
    }

    static func applied(_ d: UserDefaults = .standard) -> Set<String> { Set(d.stringArray(forKey: appliedKey) ?? []) }

    /// Troca aceita: o seu bro sai e o do amigo chega, uma vez só por troca
    @MainActor
    static func apply(_ p: TradeProposal, context: ModelContext, defaults d: UserDefaults = .standard) -> Monster? {
        guard p.isDone, !applied(d).contains(p.id) else { return nil }
        if let id = UUID(uuidString: p.mine.id),
           let leaving = try? context.fetch(FetchDescriptor<Monster>(predicate: #Predicate { $0.uuid == id })).first {
            d.set(Array(gone(d).union([id]).map(\.uuidString)), forKey: goneKey)
            context.delete(leaving)
        }
        let got = p.theirs
        let bro = Monster(name: "")
        bro.createdAt = p.answeredAt ?? .now
        bro.lastFormID = got.formID
        bro.speciesID = got.form.species
        context.insert(bro)
        var b = Dictionary(uniqueKeysWithValues: bases(d).map { ($0.key.uuidString, $0.value) })
        let owners = got.history.isEmpty ? [OwnerXP(name: p.friend.name, xp: got.xp)] : got.history
        b[bro.uuid.uuidString] = SnapshotBase(formID: got.formID, xp: got.xp, attributes: got.attributes, date: bro.createdAt, history: owners)
        d.set(try? JSONEncoder().encode(b), forKey: basesKey)
        d.set(Array(applied(d).union([p.id])), forKey: appliedKey)
        try? context.save()
        return bro
    }
}

// MARK: - Servidor

protocol TradeBackend: Sendable {
    /// Bros de um amigo (para escolher o que pedir)
    func bros(of friendID: String) async throws -> [TradeBro]
    /// Trocas em que você está; `mine` são os seus bros que podem entrar (o servidor simulado usa para te propor trocas)
    func proposals(now: Date, mine: [TradeBro], me: TradePerson) async throws -> [TradeProposal]
    func propose(to friend: TradePerson, from me: TradePerson, give: TradeBro, get: TradeBro, now: Date) async throws -> TradeProposal
    func respond(to id: String, accept: Bool, now: Date) async throws
    func cancel(_ id: String, now: Date) async throws
}

@MainActor @Observable
final class TradeStore {
    static let shared = TradeStore()

    var backend: any TradeBackend = MockTradeBackend()
    private(set) var all: [TradeProposal] = []
    private(set) var loaded = false
    private(set) var lastError: String?
    /// Bro que acabou de chegar, para a tela de comemoração
    var arrived: (bro: Monster, proposal: TradeProposal)?
    /// Toque na notificação de troca: abre a tela de trocas
    var openHub = false

    private var context: ModelContext { AppData.container.mainContext }

    /// Você como o amigo te vê
    func me() -> TradePerson {
        let d = DuelStore.shared.me()
        return TradePerson(id: "me", name: d.name, formID: d.formID)
    }

    func incoming(now: Date = .now) -> [TradeProposal] {
        all.filter { $0.to.id == "me" && $0.isPending(now: now) }.sorted { $0.createdAt < $1.createdAt }
    }

    func sent(now: Date = .now) -> [TradeProposal] {
        all.filter { $0.from.id == "me" && $0.isPending(now: now) }.sorted { $0.createdAt > $1.createdAt }
    }

    /// Trocas que você propôs, o amigo aceitou e falta receber: o bro só chega quando você toca em Receber
    func ready() -> [TradeProposal] {
        let applied = TradeLedger.applied()
        return all.filter { $0.isDone && $0.from.id == "me" && !applied.contains($0.id) }
            .sorted { ($0.answeredAt ?? $0.createdAt) < ($1.answeredAt ?? $1.createdAt) }
    }

    func done() -> [TradeProposal] {
        let waiting = Set(ready().map(\.id))
        return all.filter { $0.isDone && !waiting.contains($0.id) }
            .sorted { ($0.answeredAt ?? $0.createdAt) > ($1.answeredAt ?? $1.createdAt) }
    }

    /// Recebe a troca aceita: o seu bro vai, o do amigo chega na Box e a cena da troca começa
    func receive(_ p: TradeProposal) {
        guard ready().contains(where: { $0.id == p.id }), let bro = TradeLedger.apply(p, context: context) else { return }
        arrived = (bro, p)
    }

    /// Seus bros como entram na troca (forma e XP de agora)
    func myBros() -> [(monster: Monster, bro: TradeBro)] {
        let monsters = (try? context.fetch(FetchDescriptor<Monster>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        let roster = Roster(monsters: monsters, activities: (try? context.fetch(FetchDescriptor<Activity>())) ?? [],
                            checkIns: (try? context.fetch(FetchDescriptor<LeagueCheckIn>())) ?? [],
                            leagues: (try? context.fetch(FetchDescriptor<League>())) ?? [])
        let myName = me().name.isEmpty ? "Você" : me().name
        return monsters.map { m in
            let s = roster.snapshot(m.uuid)
            // O XP vai separado por dono: os de antes (se ele veio de troca) e o seu
            let history = s.inherited + (s.myXP > 0 ? [OwnerXP(name: myName, xp: s.myXP)] : [])
            return (m, TradeBro(id: m.uuid.uuidString, name: m.displayName(s.form), formID: s.form.id, xp: s.totalXP,
                                attributes: Dictionary(uniqueKeysWithValues: s.lifetimeAttributes.map { ($0.key.rawValue, $0.value) }),
                                history: history))
        }
    }

    /// Por que este bro seu não pode entrar numa troca agora; nil = pode
    func refusal(_ m: Monster, now: Date = .now) -> TradeRefusal? {
        if (MonsterForm.byID(m.lastFormID) ?? .egg).stage == .egg { return .egg }
        if m.uuid == MainMonster.id || (MainMonster.id == nil && m.isStarter) { return .main }
        let leagues = (try? context.fetch(FetchDescriptor<League>())) ?? []
        if let l = leagues.first(where: { $0.monsterUUID == m.uuid && !$0.isPastSeason }) { return .league(l.name) }
        if DuelStore.shared.busyFighters(now: now).contains(m.uuid) { return .inDuel }
        if sent(now: now).contains(where: { $0.give.id == m.uuid.uuidString }) { return .busy }
        // Aceita e ainda não recebida: ele já é do amigo
        if ready().contains(where: { $0.give.id == m.uuid.uuidString }) { return .busy }
        return nil
    }

    func refresh(now: Date = .now) async {
        do {
            let mine = myBros().filter { refusal($0.monster, now: now) == nil }.map(\.bro)
            all = try await backend.proposals(now: now, mine: mine, me: me())
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        loaded = true
        applyAccepted()
        notifyNew(now: now)
    }

    func bros(of friendID: String) async -> [TradeBro] { (try? await backend.bros(of: friendID)) ?? [] }

    func propose(to friend: RemoteFriend, give m: Monster, get: TradeBro, now: Date = .now) async throws {
        if let r = refusal(m, now: now) { throw r }
        guard !get.isEgg else { throw TradeRefusal.egg }
        guard let mine = myBros().first(where: { $0.monster.uuid == m.uuid })?.bro else { throw TradeRefusal.gone }
        let p = try await backend.propose(to: TradePerson(id: friend.id, name: friend.name, formID: friend.formID), from: me(),
                                          give: mine, get: get, now: now)
        all.append(p)
        // A resposta pode chegar em segundos: confere de novo para avisar mesmo fora da tela de trocas
        Task {
            try? await Task.sleep(for: .seconds(12))
            await refresh()
        }
    }

    func respond(_ p: TradeProposal, accept: Bool, now: Date = .now) async throws {
        guard p.isPending(now: now), p.to.id == "me" else { throw TradeRefusal.notPending }
        if accept {
            guard let m = myBros().first(where: { $0.bro.id == p.get.id })?.monster else { throw TradeRefusal.gone }
            if let r = refusal(m, now: now) { throw r }
        }
        try await backend.respond(to: p.id, accept: accept, now: now)
        if let i = all.firstIndex(where: { $0.id == p.id }) {
            all[i].answer = accept ? .accepted : .declined
            all[i].answeredAt = now
        }
        applyAccepted()
    }

    func cancel(_ p: TradeProposal, now: Date = .now) async throws {
        try await backend.cancel(p.id, now: now)
        all.removeAll { $0.id == p.id }
    }

    /// Trocas que você aceitou e ainda não mudaram a sua Box (ex.: o app fechou no meio). As que você propôs
    /// esperam você tocar em Receber (`receive`)
    private func applyAccepted() {
        for p in all where p.isDone && p.to.id == "me" {
            if let bro = TradeLedger.apply(p, context: context) { arrived = (bro, p) }
        }
    }

    /// Avisa uma vez quando aceitam uma troca sua (falta receber) ou quando um amigo te oferece uma troca
    private func notifyNew(now: Date) {
        let d = UserDefaults.standard
        var seen = Set(d.stringArray(forKey: TradeLedger.notifiedKey) ?? [])
        let fresh = ready().filter { !seen.contains("ok-" + $0.id) }
        let offers = incoming(now: now).filter { !seen.contains("in-" + $0.id) }
        guard !fresh.isEmpty || !offers.isEmpty else { return }
        let on = NotificationPrefs.isOn(.trades)
        for p in fresh {
            seen.insert("ok-" + p.id)
            if on { Self.notify(p, title: "\(p.friend.name) aceitou sua troca! 🤝", body: "Vá em Trocas para receber \(p.theirs.name).") }
        }
        for p in offers {
            seen.insert("in-" + p.id)
            if on {
                Self.notify(p, title: "\(p.friend.name) quer trocar com você",
                            body: "\(p.theirs.name) pelo seu \(p.mine.name). Você tem 48 h para responder.")
            }
        }
        d.set(Array(seen), forKey: TradeLedger.notifiedKey)
    }

    private static func notify(_ p: TradeProposal, title: String, body: String) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        c.threadIdentifier = "trades"
        c.userInfo = ["trade": p.id]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "trade-\(p.id)-\(p.answer == nil ? "in" : "ok")",
                                                                     content: c, trigger: nil))
    }

    func reset() {
        all = []
        loaded = false
        lastError = nil
        arrived = nil
        openHub = false
    }
}

// MARK: - Servidor simulado

struct MockTradeBackend: TradeBackend {
    func bros(of friendID: String) async throws -> [TradeBro] { MockTradeServer.bros(of: friendID) }

    func proposals(now: Date, mine: [TradeBro], me: TradePerson) async throws -> [TradeProposal] {
        await MockTradeServer.shared.proposals(now: now, mine: mine, me: me)
    }

    func propose(to friend: TradePerson, from me: TradePerson, give: TradeBro, get: TradeBro, now: Date) async throws -> TradeProposal {
        await MockTradeServer.shared.propose(to: friend, from: me, give: give, get: get, now: now)
    }

    func respond(to id: String, accept: Bool, now: Date) async throws {
        await MockTradeServer.shared.respond(to: id, accept: accept, now: now)
    }

    func cancel(_ id: String, now: Date) async throws { await MockTradeServer.shared.cancel(id) }
}

/// Trocas sem servidor: as suas propostas ficam no aparelho e os amigos simulados respondem sozinhos (aceitam quase
/// sempre, entre 4 e 10 s). A cada dois dias um amigo te propõe uma troca. Tudo determinístico pelo id.
actor MockTradeServer {
    static let shared = MockTradeServer()
    static let key = "mockTrades"

    struct State: Codable {
        var sent: [TradeProposal] = []
        var answers: [String: TradeAnswer] = [:]
        var answeredAt: [String: Date] = [:]
        var canceled: [String] = []
        /// Propostas dos amigos como chegaram (a sua parte não muda depois)
        var received: [String: TradeProposal] = [:]
    }

    private var state: State {
        get { UserDefaults.standard.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(State.self, from: $0) } ?? State() }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: Self.key) }
    }

    /// De 2 a 5 bros por amigo: o principal dele, outros de espécies e estágios variados e às vezes um ovo
    static func bros(of friendID: String) -> [TradeBro] {
        var rng = SeededRandom(seed: "bros-\(friendID)")
        let species = Species.catalog.map(\.id)
        let main = MockFriendsBackend.directory.first { $0.id == friendID }?.formID
        var out: [TradeBro] = []
        if let main, let f = MonsterForm.byID(main), f.stage != .egg { out.append(bro(friendID, 0, f, &rng)) }
        let count = 2 + Int(rng.next() * 4)
        for i in out.count..<count {
            let sp = species[Int(rng.next() * Double(species.count)) % species.count]
            let roll = rng.next()
            let stage: Stage = roll < 0.15 ? .egg : roll < 0.4 ? .rookie : roll < 0.8 ? .champion : .ultimate
            let b = MonsterForm.branches[Int(rng.next() * Double(MonsterForm.branches.count)) % MonsterForm.branches.count]
            let f = stage.branches ? MonsterForm(stage: stage, attribute: b.0, attribute2: b.1, species: sp).resolved
                : MonsterForm(stage: stage, attribute: nil, species: sp)
            out.append(bro(friendID, i, f, &rng))
        }
        return out
    }

    private static func bro(_ friendID: String, _ i: Int, _ f: MonsterForm, _ rng: inout SeededRandom) -> TradeBro {
        let span = (f.stage.next?.threshold ?? f.stage.threshold + 1800) - f.stage.threshold
        let xp = f.stage.threshold + Int(rng.next() * Double(span) * 0.8)
        var attrs: [String: Double] = [:]
        for a in Attribute.allCases { attrs[a.rawValue] = Double(xp) * 0.1 }
        if let a = f.attribute { attrs[a.rawValue] = Double(xp) * (f.attribute2 == nil ? 0.6 : 0.35) }
        if let b = f.attribute2 { attrs[b.rawValue] = Double(xp) * 0.35 }
        let owner = MockFriendsBackend.directory.first { $0.id == friendID }?.name ?? friendID
        // Alguns bros dos amigos já vieram de outra troca: o XP fica dividido entre dois donos
        let history = rng.next() < 0.3 && xp > 200
            ? [OwnerXP(name: ["Lia", "Caio", "Rafa", "Duda"][Int(rng.next() * 4) % 4], xp: xp * 2 / 3), OwnerXP(name: owner, xp: xp - xp * 2 / 3)]
            : [OwnerXP(name: owner, xp: xp)]
        return TradeBro(id: "\(friendID)-bro-\(i)", name: f.name, formID: f.id, xp: xp, attributes: attrs, history: history)
    }

    func proposals(now: Date, mine: [TradeBro], me: TradePerson) -> [TradeProposal] {
        let st = state
        var out = st.sent.filter { !st.canceled.contains($0.id) }.map { simulate($0, now: now) }
        out += incoming(now: now, mine: mine, me: me)
        return out
    }

    func propose(to friend: TradePerson, from me: TradePerson, give: TradeBro, get: TradeBro, now: Date) -> TradeProposal {
        let p = TradeProposal(id: UUID().uuidString, from: me, to: friend, give: give, get: get, createdAt: now)
        state.sent.append(p)
        return p
    }

    func respond(to id: String, accept: Bool, now: Date) {
        state.answers[id] = accept ? .accepted : .declined
        state.answeredAt[id] = now
    }

    func cancel(_ id: String) { state.canceled.append(id) }

    /// O amigo responde sozinho: 80% aceita, entre 4 e 10 s depois
    private func simulate(_ p: TradeProposal, now: Date) -> TradeProposal {
        var p = p
        var rng = SeededRandom(seed: "\(p.id)-troca")
        let at = p.createdAt.addingTimeInterval(4 + rng.next() * 6)
        if p.answer == nil, at <= now {
            p.answer = rng.next() < 0.8 ? .accepted : .declined
            p.answeredAt = at
        }
        return p
    }

    /// A cada dois dias, um amigo te oferece um bro dele por um seu (só os seus que podem entrar)
    private func incoming(now: Date, mine: [TradeBro], me: TradePerson) -> [TradeProposal] {
        let friends = MockFriendsBackend.load().friends
        guard !friends.isEmpty else { return [] }
        var st = state
        var out: [TradeProposal] = []
        let today = Int(Calendar.current.startOfDay(for: now).timeIntervalSince1970 / 86_400)
        for stamp in Set([today / 2 * 2, (today - 2) / 2 * 2]) {
            let id = "troca-\(stamp)"
            if st.received[id] == nil {
                var rng = SeededRandom(seed: id)
                let friend = friends[Int(rng.next() * Double(friends.count)) % friends.count]
                let offer = Self.bros(of: friend.id).filter { !$0.isEgg }
                let at = Date(timeIntervalSince1970: Double(stamp) * 86_400).addingTimeInterval(9 * 3600)
                guard at <= now, now < at.addingTimeInterval(TradeProposal.window), !offer.isEmpty, !mine.isEmpty else { continue }
                st.received[id] = TradeProposal(id: id, from: TradePerson(id: friend.id, name: friend.name, formID: friend.formID), to: me,
                                                give: offer[Int(rng.next() * Double(offer.count)) % offer.count],
                                                get: mine[Int(rng.next() * Double(mine.count)) % mine.count], createdAt: at)
            }
            guard var p = st.received[id] else { continue }
            p.answer = st.answers[id]
            p.answeredAt = st.answeredAt[id]
            out.append(p)
        }
        state = st
        return out
    }
}
