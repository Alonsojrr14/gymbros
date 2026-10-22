import Foundation
import Observation
import SwiftData

// Contrato entre o app e o servidor das ligas. Quem responde é escolhido em Backend.swift:
// MockLeagueBackend (participantes, check-ins, times e recados simulados e determinísticos) ou
// CloudKitLeagueBackend. Os tipos Remote*/Outgoing*/LeagueDraft são Codable e têm o formato do servidor.
//
// O que é seu continua no aparelho (League, LeagueCheckIn, LeagueMessage) e funciona como caixa de saída:
// `syncedAt` fica nil até o servidor aceitar; LeagueRemoteStore.flush manda tudo o que está pendente.

/// O que o servidor precisa saber de uma liga para responder
struct LeagueKey: Hashable, Sendable {
    let uuid: UUID
    let code: String
    let start: Date
    let end: Date?
    let isMock: Bool
    let teams: [LeagueTeam]
    /// Liga privada: os check-ins sobem sem a marca de Feed
    var isPrivate = false
}

extension League {
    var key: LeagueKey { LeagueKey(uuid: uuid, code: code, start: start, end: end, isMock: isMock, teams: teams, isPrivate: settings.isPrivate) }
}

struct RemoteMember: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    /// `MonsterForm.id` do bro que representa a pessoa na liga
    let formID: String
    var teamID: String?
    /// Quando entrou na liga; nil = desde o início
    var joinedAt: Date?

    var form: MonsterForm { MonsterForm.byID(formID) ?? .egg }
}

struct RemoteCheckIn: Codable, Identifiable, Sendable {
    let id: String
    let memberID: String
    let date: Date
    let kindRaw: String
    let minutes: Int
    let effort: Int
    var meters: Double?
    var kcal: Double?
    let title: String
    var note = ""
    /// Teve foto (a imagem em si virá por URL quando houver servidor)
    var hasPhoto = false
    var photoURL: URL?
    /// Tipo do catálogo do Saúde (skate, bike…); ausente em check-ins antigos = o tipo padrão da categoria
    var workoutTypeID: UInt?
    /// Onde foi (ex.: academia)
    var place: String?
    /// Origem da foto, aparelho e pose do dia; ausente em check-ins antigos
    var proof: CheckInProof?
    /// Liga pública em que foi postado ("🔥 Liga dos Bros"), para o Feed dos amigos; nil = perfil
    var postedIn: String?

    var kind: ActivityKind { ActivityKind(rawValue: kindRaw) ?? .outro }
    var input: ScoreInput {
        ScoreInput(kind: kind, minutes: minutes, effort: effort, meters: meters, kcal: kcal, workoutTypeID: workoutTypeID ?? WorkoutType.of(kind).id)
    }
}

struct RemoteTeam: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    var memberIDs: [String] = []
}

/// Recado no mural da liga
struct RemoteMessage: Codable, Identifiable, Sendable {
    let id: String
    let memberID: String
    let date: Date
    let text: String
}

struct RemoteLeague: Sendable {
    var members: [RemoteMember] = []
    var checkIns: [RemoteCheckIn] = []
    var teams: [RemoteTeam] = []
    var messages: [RemoteMessage] = []
    /// Quem pediu para entrar (liga com aprovação; só o dono e os moderadores recebem)
    var requests: [RemoteMember] = []

    static let empty = RemoteLeague()

    func member(_ id: String) -> RemoteMember? { members.first { $0.id == id } }

    /// Com as decisões do dono: quem saiu ou foi banido some (com check-ins e recados), pedido aceito vira membro
    /// e os pedidos que sobram são os ainda sem resposta. Aplicar duas vezes dá o mesmo resultado.
    @MainActor
    func applying(_ league: League) -> RemoteLeague {
        let s = league.settings
        let out = Set(s.removed + s.banned)
        var r = self
        var asked = requests
        if league.isMock && s.requiresApproval {
            for m in MockLeague.requesters where !asked.contains(where: { $0.id == m.id }) { asked.append(m) }
        }
        let memberIDs = Set(members.map(\.id))
        for m in asked where s.approved.contains(m.id) && !memberIDs.contains(m.id) && !out.contains(m.id) { r.members.append(m) }
        r.members.removeAll { out.contains($0.id) }
        r.checkIns.removeAll { out.contains($0.memberID) }
        r.messages.removeAll { out.contains($0.memberID) }
        let now = Set(r.members.map(\.id))
        r.requests = asked.filter { !now.contains($0.id) && !s.ignored.contains($0.id) && !s.banned.contains($0.id) && !s.approved.contains($0.id) }
        return r
    }
}

/// Recado seu ainda não confirmado pelo servidor
struct OutgoingMessage: Codable, Sendable {
    let id: UUID
    let date: Date
    let text: String
}

/// Seu check-in a publicar numa liga (o id é o do LeagueCheckIn: publicar de novo atualiza)
struct OutgoingCheckIn: Codable, Sendable {
    let id: UUID
    let date: Date
    let kindRaw: String
    let minutes: Int
    let effort: Int
    var meters: Double?
    var kcal: Double?
    let title: String
    let note: String
    let hasPhoto: Bool
    var photo: Data?
    /// Tipo do catálogo do Saúde, para as regras de "treinos que valem" darem o mesmo resultado em todos os aparelhos
    var workoutTypeID: UInt?
    var place: String?
    /// Origem da foto, aparelho e pose: o dono revisa e as regras da liga conferem com isso
    var proof: CheckInProof?
}

extension OutgoingCheckIn {
    /// O que sobe do check-in. De atividade do Saúde, só tipo, data e duração; kcal, distância e esforço de lá ficam no aparelho.
    init(_ c: LeagueCheckIn, activity a: Activity) {
        self.init(id: c.uuid, date: c.date, kindRaw: a.kindRaw, minutes: a.minutes, effort: a.publishableEffort,
                  meters: a.publishableMeters, kcal: a.publishableKcal, title: c.title, note: c.note, hasPhoto: c.hasPhoto, photo: c.photo,
                  workoutTypeID: a.workoutType.id, place: c.place, proof: c.proof)
    }
}

/// Liga como o servidor guarda: regras e times. Serve para criar e para entrar por código.
struct LeagueDraft: Codable, Sendable {
    let uuid: UUID
    let code: String
    let name: String
    let emoji: String
    let scoring: String
    let weights: String
    let tieBreak: String
    let photoRule: String
    /// Regra de tipos de treino; ausente em ligas anteriores = todos contam.
    var activityRule: String? = nil
    /// `LeagueSettings` em JSON (verificação, revisão, pose, limites, metas, moderação); ausente = nada ligado
    var settings: String? = nil
    let teams: String
    let start: Date
    let end: Date?
    let autoRenew: Bool
    /// Critério da rodada suíça; nil = liga de antes do suíço (mais pontos no dia)
    var swiss: String? = nil
}

/// Como você aparece numa liga
struct Membership: Codable, Sendable {
    let name: String
    let formID: String
    let teamID: String?
    /// Dia em que entrou: a rodada suíça só pareia a pessoa a partir dele
    var joinedAt: Date?
}

protocol LeagueBackend: Sendable {
    /// Estado atual da liga (outros participantes, check-ins deles, times, mural)
    func fetch(_ league: LeagueKey, now: Date) async throws -> RemoteLeague
    /// Publica seus recados no mural; devolve os ids aceitos
    func send(_ messages: [OutgoingMessage], to league: LeagueKey) async throws -> [UUID]
    /// Cria a liga (você é o dono)
    func create(_ league: LeagueDraft) async throws
    /// Acha a liga pelo código; nil = não existe
    func join(code: String) async throws -> LeagueDraft?
    /// Seu nome, bro e time na liga
    func setMembership(_ membership: Membership, in league: LeagueKey) async throws
    /// Publica (ou atualiza) seus check-ins; devolve os ids aceitos
    func publish(_ checkIns: [OutgoingCheckIn], to league: LeagueKey) async throws -> [UUID]
    /// Tira check-ins seus da liga
    func retract(_ checkInIDs: [UUID], from league: LeagueKey) async throws
    /// Sai da liga (some do ranking; seus check-ins saem junto)
    func leave(_ league: LeagueKey) async throws
    /// Pede para entrar numa liga com aprovação: o dono aceita ou ignora
    func requestJoin(code: String, membership: Membership) async throws
    /// Seu pedido foi aceito (a liga já pode entrar no aparelho)
    func isApproved(code: String) async throws -> Bool
    /// Passa a liga para outra pessoa antes de sair (o dono que sai escolhe; sem escolha, sorteia)
    func transfer(_ league: LeagueKey, to memberID: String) async throws
}

/// Servidor sem pedidos de entrada nem troca de dono (os servidores de teste)
extension LeagueBackend {
    func requestJoin(code: String, membership: Membership) async throws {}
    func isApproved(code: String) async throws -> Bool { false }
    func transfer(_ league: LeagueKey, to memberID: String) async throws {}
}

// MARK: - Cache

@MainActor @Observable
final class LeagueRemoteStore {
    static let shared = LeagueRemoteStore()

    var backend: any LeagueBackend = MockLeagueBackend()
    var access: AccessStore = .shared
    private(set) var cache: [LeagueKey: RemoteLeague] = [:]
    /// Último erro de sincronização (para mostrar se precisar)
    private(set) var lastError: String?

    /// A liga de exemplo é sempre simulada, mesmo com servidor ligado
    func backend(for key: LeagueKey) -> any LeagueBackend { key.isMock ? MockLeagueBackend() : backend }

    /// O que já se sabe da liga. Sem resposta ainda, o exemplo é calculado na hora (para não piscar vazio).
    func remote(_ league: League) -> RemoteLeague {
        let key = league.key
        if let r = cache[key] { return r.applying(league) }
        return (backend(for: key) is MockLeagueBackend ? MockLeagueBackend.build(key) : .empty).applying(league)
    }

    /// Esquece o que veio do servidor (conta excluída)
    func reset() {
        cache = [:]
        lastError = nil
    }

    func refresh(_ leagues: [League]) async {
        for l in leagues {
            let key = l.key
            if let r = try? await backend(for: key).fetch(key, now: .now) { cache[key] = r }
        }
    }

    private var flushing: Task<Void, Never>?

    /// Manda tudo o que está na caixa de saída (um envio por vez): ligas e seu lugar nelas, check-ins (novos, editados e apagados) e recados
    func flush(context: ModelContext) async {
        let previous = flushing
        let task = Task {
            await previous?.value
            await send(context: context)
        }
        flushing = task
        await task.value
    }

    private func send(context: ModelContext) async {
        let leagues = ((try? context.fetch(FetchDescriptor<League>())) ?? []).filter { !$0.isMock }
        let keys = Dictionary(leagues.map { ($0.uuid, $0.key) }, uniquingKeysWith: { a, _ in a })
        let monsters = (try? context.fetch(FetchDescriptor<Monster>())) ?? []
        let name = ContentFilter.publishable(UserDefaults.standard.string(forKey: "trainerName") ?? "")
        // Sem permissão, fica pendente. Retirar o que é seu nunca é bloqueado.
        let newLeagues = leagues.filter { $0.syncedAt == nil && !$0.isPastSeason && canSync($0) }.map { l in
            let last = monsters.first { $0.uuid == l.monsterUUID }?.lastFormID ?? ""
            let form = last.isEmpty ? MonsterForm.egg.id : last
            return (id: l.uuid, draft: l.joined ? nil : l.draft, key: l.key,
                    membership: Membership(name: name, formID: form, teamID: l.myTeamID, joinedAt: l.swissJoinedAt))
        }

        let activities = Dictionary(((try? context.fetch(FetchDescriptor<Activity>())) ?? []).map { ($0.uuid, $0) }, uniquingKeysWith: { a, _ in a })
        let pending = access.can(.checkInsPublish)
            ? (try? context.fetch(FetchDescriptor<LeagueCheckIn>(predicate: #Predicate { $0.syncedAt == nil }))) ?? [] : []
        let checkIns = Dictionary(grouping: pending, by: \.leagueUUID).compactMap { leagueID, list -> (key: LeagueKey, out: [OutgoingCheckIn])? in
            guard let key = leagueID == ProfileFeed.id ? .profileFeed : keys[leagueID] else { return nil }
            return (key, list.compactMap { c in
                guard let a = activities[c.activityUUID] else { return nil }
                return OutgoingCheckIn(c, activity: a)
            })
        }

        let msgs = access.can(.messagesPublish)
            ? (try? context.fetch(FetchDescriptor<LeagueMessage>(predicate: #Predicate { $0.syncedAt == nil }))) ?? [] : []
        let messages = Dictionary(grouping: msgs, by: \.leagueUUID).compactMap { leagueID, list -> (key: LeagueKey, out: [OutgoingMessage])? in
            guard let key = keys[leagueID] else { return nil }
            return (key, list.map { OutgoingMessage(id: $0.uuid, date: $0.date, text: $0.text) })
        }

        do {
            for l in newLeagues {
                if let draft = l.draft { try await backend.create(draft) }
                try await backend.setMembership(l.membership, in: l.key)
                let id = l.id
                let fresh = (try? context.fetch(FetchDescriptor<League>(predicate: #Predicate { $0.uuid == id }))) ?? []
                for league in fresh where !league.isDeleted { league.syncedAt = .now }
            }

            for (key, out) in checkIns {
                let accepted = try await backend.publish(out, to: key)
                let fresh = (try? context.fetch(FetchDescriptor<LeagueCheckIn>(predicate: #Predicate { accepted.contains($0.uuid) }))) ?? []
                for c in fresh where !c.isDeleted { c.syncedAt = .now }
            }

            for (leagueID, ids) in LeagueOutbox.retractions {
                if let key = leagueID == ProfileFeed.id ? .profileFeed : keys[leagueID] { try await backend.retract(ids, from: key) }
                LeagueOutbox.clear(ids, from: leagueID)
            }

            for (key, out) in messages {
                let accepted = try await backend.send(out, to: key)
                let fresh = (try? context.fetch(FetchDescriptor<LeagueMessage>(predicate: #Predicate { accepted.contains($0.uuid) }))) ?? []
                for m in fresh where !m.isDeleted { m.syncedAt = .now }
            }
            lastError = nil
        } catch {
            // Fica na caixa de saída e tenta de novo na próxima vez
            lastError = error.localizedDescription
        }
        try? context.save()
    }

    /// Lugar na liga; quem criou também publica as regras
    private func canSync(_ league: League) -> Bool {
        access.can(.leaguesJoin) && (league.joined || access.can(.leaguesCreate) && access.can(.leaguesUpdate, on: league))
    }

    private var flushTask: Task<Void, Never>?

    /// Manda a caixa de saída daqui a pouco (junta várias mudanças seguidas num envio só)
    func scheduleFlush() {
        flushTask?.cancel()
        flushTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await flush(context: AppData.container.mainContext)
        }
    }

    /// Sair da liga no servidor (as temporadas saem junto)
    func leave(_ league: League) async {
        guard !league.isMock else { return }
        try? await backend.leave(league.key)
    }

    /// Procura a liga pelo código no servidor
    func join(code: String) async throws -> LeagueDraft? { try await backend.join(code: code) }
}

/// Check-ins seus que precisam sair do servidor (apagados aqui depois de publicados)
enum LeagueOutbox {
    private static let key = "pendingRetractions"

    static var retractions: [UUID: [UUID]] {
        let raw = UserDefaults.standard.dictionary(forKey: key) as? [String: [String]] ?? [:]
        return raw.reduce(into: [:]) { acc, kv in
            if let l = UUID(uuidString: kv.key) { acc[l] = kv.value.compactMap(UUID.init(uuidString:)) }
        }
    }

    /// Chame antes de apagar um check-in: se ele já tinha subido, entra na fila para sair
    static func retract(_ c: LeagueCheckIn) {
        guard c.syncedAt != nil else { return }
        var raw = UserDefaults.standard.dictionary(forKey: key) as? [String: [String]] ?? [:]
        raw[c.leagueUUID.uuidString, default: []].append(c.uuid.uuidString)
        UserDefaults.standard.set(raw, forKey: key)
    }

    static func clear(_ league: UUID) {
        var raw = UserDefaults.standard.dictionary(forKey: key) as? [String: [String]] ?? [:]
        raw[league.uuidString] = nil
        UserDefaults.standard.set(raw, forKey: key)
    }

    /// Tira da fila só o que já saiu do servidor (o que entrou durante o envio fica)
    static func clear(_ ids: [UUID], from league: UUID) {
        var raw = UserDefaults.standard.dictionary(forKey: key) as? [String: [String]] ?? [:]
        let sent = Set(ids.map(\.uuidString))
        let left = (raw[league.uuidString] ?? []).filter { !sent.contains($0) }
        raw[league.uuidString] = left.isEmpty ? nil : left
        UserDefaults.standard.set(raw, forKey: key)
    }
}

extension LeagueKey {
    /// Destino dos posts do perfil no servidor (funciona como uma liga só sua)
    static let profileFeed = LeagueKey(uuid: ProfileFeed.id, code: CloudType.profileFeed, start: .distantPast, end: nil, isMock: false, teams: [])
}

extension League {
    /// Liga de outra pessoa, achada pelo código
    convenience init(draft d: LeagueDraft) {
        self.init(name: d.name, emoji: d.emoji, scoring: LeagueScoring(rawValue: d.scoring) ?? .pontos, start: d.start)
        code = d.code
        weightsRaw = d.weights
        tieBreakRaw = d.tieBreak
        photoRuleRaw = d.photoRule
        activityRuleRaw = d.activityRule ?? ""
        settingsRaw = d.settings ?? ""
        swissRaw = d.swiss ?? SwissCriterion.pontos.rawValue
        teamsRaw = d.teams
        end = d.end
        autoRenew = d.autoRenew
        joined = true
    }

    var draft: LeagueDraft {
        LeagueDraft(uuid: seriesKey, code: code, name: name, emoji: emoji, scoring: scoringRaw, weights: weightsRaw, tieBreak: tieBreakRaw,
                    photoRule: photoRuleRaw, activityRule: activityRuleRaw, settings: settingsRaw, teams: teamsRaw, start: start, end: end, autoRenew: autoRenew, swiss: swissRaw)
    }
}

// MARK: - Servidor simulado

struct MockLeagueBackend: LeagueBackend {
    func fetch(_ league: LeagueKey, now: Date) async throws -> RemoteLeague { Self.build(league, now: now) }

    /// Sem servidor, tudo é aceito e fica só no aparelho
    func send(_ messages: [OutgoingMessage], to league: LeagueKey) async throws -> [UUID] { messages.map(\.id) }
    func create(_ league: LeagueDraft) async throws {}
    /// Só existe a liga de exemplo (tratada no app pelo código AMIGOS)
    func join(code: String) async throws -> LeagueDraft? { nil }
    func setMembership(_ membership: Membership, in league: LeagueKey) async throws {}
    func publish(_ checkIns: [OutgoingCheckIn], to league: LeagueKey) async throws -> [UUID] { checkIns.map(\.id) }
    func retract(_ checkInIDs: [UUID], from league: LeagueKey) async throws {}
    func leave(_ league: LeagueKey) async throws {}

    static func build(_ league: LeagueKey, now: Date = .now) -> RemoteLeague {
        var teams = league.teams.map { RemoteTeam(id: $0.id, name: $0.name) }
        guard league.isMock else { return RemoteLeague(teams: teams) }
        // Distribui os participantes simulados entre os times, começando por um time sorteado
        var rng = SeededRandom(seed: "\(league.uuid)-times")
        let offset = Int(rng.next() * 100)
        let members = FakeMember.all.enumerated().map { i, m in
            RemoteMember(id: m.id, name: m.name, formID: m.form.id, teamID: teams.isEmpty ? nil : teams[(i + offset) % teams.count].id)
        }
        for m in members { if let t = teams.firstIndex(where: { $0.id == m.teamID }) { teams[t].memberIDs.append(m.id) } }

        let checkIns = MockLeague.checkIns(league: league, now: now).map { f in
            var photo = SeededRandom(seed: "\(f.id)-foto")
            let hasPhoto = photo.next() < 0.75
            // Sorteado depois da foto, para não mudar o que já saía: de onde veio a foto e se um relógio gravou
            var proof = SeededRandom(seed: "\(f.id)-prova")
            let camera = proof.next() < 0.7
            let watch = f.meters != nil && proof.next() < 0.8
            return RemoteCheckIn(id: f.id, memberID: f.member.id, date: f.date, kindRaw: f.kind.rawValue, minutes: f.minutes, effort: f.effort,
                                 meters: f.meters, title: f.title, hasPhoto: hasPhoto,
                                 proof: CheckInProof(photo: hasPhoto ? PhotoProof(source: camera ? .camera : .library,
                                                                                  takenAt: f.date.addingTimeInterval(Double(f.minutes) * 60)) : nil,
                                                     deviceRecorded: watch, device: watch ? "Apple Watch" : nil))
        }
        return RemoteLeague(members: members, checkIns: checkIns, teams: teams,
                            messages: messages(league, members: members, teams: teams, now: now))
    }

    private static let phrases = [
        "Bora que hoje tem! 💪", "Quem vai amanhã cedo?", "Hoje foi pesado 🥵", "Tô sentindo até a alma",
        "Alguém segura essa liga", "Fim de semana sem desculpa, hein", "Meu bro tá quase evoluindo 👀",
        "Choveu mas eu fui 🌧️", "Descanso também é treino 😴", "Essa semana eu viro o jogo",
        "Quem topa um treino junto sábado?", "Primeira vez que não pulo a segunda-feira 🎉",
    ]

    private static let teamPhrases = ["Vamos, %@! 🔥", "%@ não para!", "Só mais um check-in e a gente passa, %@"]

    /// Até um recado por pessoa por dia, sempre igual para o mesmo dia
    private static func messages(_ league: LeagueKey, members: [RemoteMember], teams: [RemoteTeam], now: Date) -> [RemoteMessage] {
        let cal = Calendar.current
        var out: [RemoteMessage] = []
        var day = cal.startOfDay(for: league.start)
        let last = min(now, league.end ?? now)
        while day <= last {
            for m in members {
                var rng = SeededRandom(seed: "\(league.uuid)-\(m.id)-\(Int(day.timeIntervalSince1970))-mural")
                guard rng.next() < 0.3 else { continue }
                guard let date = cal.date(byAdding: .minute, value: 7 * 60 + Int(rng.next() * 15 * 60), to: day), date <= now else { continue }
                let team = teams.first { $0.id == m.teamID }
                let text: String
                if let team, rng.next() < 0.35 {
                    text = String(format: teamPhrases[Int(rng.next() * Double(teamPhrases.count)) % teamPhrases.count], team.name)
                } else {
                    text = phrases[Int(rng.next() * Double(phrases.count)) % phrases.count]
                }
                out.append(RemoteMessage(id: "\(m.id)-\(Int(day.timeIntervalSince1970))-msg", memberID: m.id, date: date, text: text))
            }
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }
        return out
    }
}
