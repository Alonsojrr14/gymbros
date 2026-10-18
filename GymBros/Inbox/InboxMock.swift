import Foundation
import SwiftData

// MARK: - Servidor simulado

/// Guarda as conversas no aparelho e faz os amigos simulados agirem: algumas mensagens de exemplo na primeira vez,
/// resposta em alguns segundos ao que você manda, reações nos seus check-ins dos últimos dias e aviso quando
/// um amigo do mapa começa a treinar (uma vez por dia).
struct MockInboxBackend: InboxBackend {
    private static let key = "mockInbox"

    private struct Stored: Codable {
        var messages: [DirectMessage] = []
        var seeded = false
    }

    private static func load() -> Stored {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(Stored.self, from: $0) } ?? Stored()
    }

    private static func save(_ s: Stored) {
        UserDefaults.standard.set(try? JSONEncoder().encode(s), forKey: key)
    }

    /// Volta ao começo (conversas de exemplo de novo)
    static func reset() { UserDefaults.standard.removeObject(forKey: key) }

    func fetch() async throws -> InboxState {
        try await Task.sleep(for: .milliseconds(150))
        return await MainActor.run { Self.snapshot(now: .now) }
    }

    func send(_ message: DirectMessage) async throws -> DirectMessage {
        try await Task.sleep(for: .milliseconds(200))
        var s = Self.load()
        s.messages.append(message)
        if let reply = Self.reply(to: message, history: s.messages) { s.messages.append(reply) }
        Self.save(s)
        return message
    }

    // MARK: Estado

    @MainActor
    static func snapshot(now: Date) -> InboxState {
        var s = load()
        if !s.seeded {
            s.messages += seed(now: now)
            s.seeded = true
            save(s)
        }
        let peers = MockFriendsBackend.directory.map { InboxPeer(id: $0.id, name: $0.name, formID: $0.formID) }
        // As respostas simuladas ficam guardadas com a hora em que "chegam"
        return InboxState(messages: s.messages.filter { $0.date <= now }, events: liveStarts(now: now) + reactions(now: now), peers: peers)
    }

    private static func ago(_ minutes: Double, _ now: Date) -> Date { now.addingTimeInterval(-minutes * 60) }

    /// Primeira abertura: força do Bruno, convite da Ana e um papo com o Diego
    private static func seed(now: Date) -> [DirectMessage] {
        let cal = Calendar.current
        let tomorrow7 = cal.date(byAdding: .hour, value: 7, to: cal.startOfDay(for: now.addingTimeInterval(86400)))
        return [
            DirectMessage(id: "seed-diego-1", peerID: "diego", outgoing: false, date: ago(26 * 60, now), text: "Quinta tem pelada, cola? ⚽"),
            DirectMessage(id: "seed-diego-2", peerID: "diego", outgoing: true, date: ago(25 * 60, now), text: "Fechou, tô dentro!"),
            DirectMessage(id: "seed-diego-3", peerID: "diego", outgoing: false, date: ago(25 * 60 - 3, now), text: "Boa! 19h na quadra do bairro"),
            DirectMessage(id: "seed-bruno-1", peerID: "bruno", outgoing: false, date: ago(95, now), kind: .cheer,
                          text: "Vi teu check-in, tá voando! 💪"),
            DirectMessage(id: "seed-ana-1", peerID: "ana", outgoing: false, date: ago(40, now), kind: .invite, text: "Longão leve, ritmo de conversa 🏃‍♀️",
                          invite: TrainInvite(kindRaw: ActivityKind.corrida.rawValue, place: "Parque", when: tomorrow7)),
        ]
    }

    private static let cheerBacks = ["Valeu, mano! Tamo junto 💪", "Opa, recebido! Bora que bora 🔥", "Valeu! Hoje foi pesado 😮‍💨",
                                     "Força de volta pra você! 💪"]
    private static let texts: [String: [String]] = [
        "bruno": ["Supino hoje saiu 85 kg 🔥", "Bora treinar junto essa semana?", "Fechou!"],
        "ana": ["Hoje foi 10 km em 52 min 🏃‍♀️", "Bora! Me avisa o horário", "Haha verdade"],
        "diego": ["Pelada quinta, não esquece ⚽", "Fechou!", "Kkkkk"],
        "fe": ["Tô saindo da piscina agora 🏊‍♀️", "Bora!", "Amanhã cedo eu topo"],
        "carla": ["Yoga hoje foi top 🧘‍♀️", "Combinado ☕️", "Haha sim"],
    ]

    /// O que o amigo simulado responde, uns segundos depois
    private static func reply(to m: DirectMessage, history: [DirectMessage]) -> DirectMessage? {
        guard FriendsLive.simulated.contains(where: { $0.id == m.peerID }) || texts[m.peerID] != nil else { return nil }
        var rng = SeededRandom(seed: m.id)
        let at = m.date.addingTimeInterval(3 + rng.next() * 5)
        let id = "reply-\(m.id)"
        switch m.kind {
        case .cheer:
            return DirectMessage(id: id, peerID: m.peerID, outgoing: false, date: at, kind: .cheer,
                                 text: cheerBacks[Int(rng.next() * Double(cheerBacks.count)) % cheerBacks.count])
        case .invite:
            let yes = rng.next() < 0.75
            return DirectMessage(id: id, peerID: m.peerID, outgoing: false, date: at, kind: .inviteReply, replyTo: m.id, accepted: yes)
        case .inviteReply:
            guard m.accepted == true else { return nil }
            return DirectMessage(id: id, peerID: m.peerID, outgoing: false, date: at, text: "Fechou, te vejo lá 🤝")
        case .text:
            let pool = texts[m.peerID] ?? ["Boa!"]
            let n = history.filter { $0.peerID == m.peerID && $0.outgoing }.count
            return DirectMessage(id: id, peerID: m.peerID, outgoing: false, date: at, text: pool[n % pool.count])
        }
    }

    // MARK: Atividade

    /// Amigos do mapa que estão treinando agora; o id muda por dia (avisa uma vez por dia)
    @MainActor
    private static func liveStarts(now: Date) -> [InboxEvent] {
        let day = Int(Calendar.current.startOfDay(for: now).timeIntervalSince1970)
        return FriendsLive.all.compactMap { f in
            guard let start = f.start else { return nil }
            return InboxEvent(id: "live-\(f.id)-\(day)", kind: .liveStart, actorID: f.id, actorName: f.name, actorFormID: f.form.id,
                              date: start, text: f.kind.name, detail: f.place)
        }
    }

    private static let emojis = ["💪", "🔥", "👏", "🏆", "❤️"]
    private static let comments = ["Monstro! 🔥", "Bora que bora!", "Que treino, hein", "Inspirou aqui 👏", "Tá voando!"]

    /// Seus check-ins dos últimos 3 dias ganham 1 a 3 reações ou comentários de amigos, sempre os mesmos
    @MainActor
    private static func reactions(now: Date) -> [InboxEvent] {
        let ctx = AppData.container.mainContext
        let since = now.addingTimeInterval(-3 * 86400)
        let mine = ((try? ctx.fetch(FetchDescriptor<LeagueCheckIn>())) ?? []).filter { $0.date >= since }
        let friends = FriendsStore.shared.friends.filter { f in FriendsLive.simulated.contains { $0.id == f.id } }
        guard !friends.isEmpty else { return [] }
        var out: [InboxEvent] = []
        for c in mine {
            var rng = SeededRandom(seed: "reacao-\(c.uuid.uuidString)")
            let count = 1 + Int(rng.next() * 3)
            var used = Set<String>()
            for i in 0..<count {
                let f = friends[Int(rng.next() * Double(friends.count)) % friends.count]
                guard used.insert(f.id).inserted else { continue }
                let date = c.date.addingTimeInterval(120 + rng.next() * 80 * 60)
                guard date <= now else { continue }
                let comment = rng.next() < 0.35
                let text = comment ? comments[Int(rng.next() * Double(comments.count)) % comments.count]
                                   : emojis[Int(rng.next() * Double(emojis.count)) % emojis.count]
                out.append(InboxEvent(id: UUID(seed: "reacao-\(c.uuid.uuidString)-\(i)").uuidString, kind: comment ? .comment : .reaction,
                                      actorID: f.id, actorName: f.name, actorFormID: f.formID, date: date, text: text,
                                      detail: c.title.isEmpty ? "Check-in" : c.title, targetID: c.uuid.uuidString))
            }
        }
        return out
    }
}
