import XCTest
@testable import GymBros

/// Caixa de entrada: não lidos, convites, bloqueio, só entre amigos e notificações filtradas pelas preferências
final class InboxTests: GymTestCase {
    private var defaults: UserDefaults!
    private var suite = ""
    private var backend: FakeInboxBackend!
    private var store: InboxStore!
    private var moderation: ModerationStore!
    private var notified: [InboxNotice] = []

    override func setUp() async throws {
        try await super.setUp()
        suite = "InboxTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        backend = FakeInboxBackend()
        notified = []
        moderation = ModerationStore(defaults: defaults)
        moderation.backend = SilentModerationBackend()
        moderation.access = await signedInAccess()
        moderation.unfriend = { _ in }
        store = InboxStore(defaults: defaults)
        store.backend = backend
        store.access = await signedInAccess()
        store.moderation = moderation
        store.friendRequests = { [] }
        store.friendIDs = { ["bruno", "ana"] }
        store.notify = { [weak self] in self?.notified.append($0) }
        store.duelNotices = { [weak self] in self?.duels ?? [] }
    }

    private var duels: [DuelNotice] = []

    private func duel(_ id: String, iChallenged: Bool, phase: DuelPhase, accepted: Date? = nil, score: DuelScore? = nil) -> DuelNotice {
        let created = Date.now.addingTimeInterval(-3600)
        return DuelNotice(id: id, opponent: DuelPerson(id: "bruno", name: "Bruno", formID: ""), iChallenged: iChallenged, metric: .treinos,
                          phase: phase, createdAt: created, acceptedAt: accepted, endsAt: accepted?.addingTimeInterval(86400),
                          expiresAt: created.addingTimeInterval(86400), score: score)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try await super.tearDown()
    }

    private func incoming(_ id: String, from peer: String, kind: DirectKind = .text, minutesAgo: Double = 1) -> DirectMessage {
        DirectMessage(id: id, peerID: peer, outgoing: false, date: .now.addingTimeInterval(-minutesAgo * 60), kind: kind, text: "oi",
                      invite: kind == .invite ? TrainInvite(kindRaw: ActivityKind.corrida.rawValue, place: "Parque", when: nil) : nil)
    }

    // MARK: Notificações

    func testFirstFetchOnlyMarksAndLaterMessagesNotify() async {
        backend.state.messages = [incoming("a", from: "bruno")]
        await store.refresh()
        XCTAssertTrue(notified.isEmpty, "A primeira busca da conta não toca o histórico")
        backend.state.messages.append(incoming("b", from: "ana", kind: .cheer))
        await store.refresh()
        XCTAssertEqual(notified.map(\.id), ["b"])
        XCTAssertEqual(notified.first?.topic, .cheers)
        await store.refresh()
        XCTAssertEqual(notified.count, 1, "Nada é notificado duas vezes")
    }

    func testTopicOffAndPauseSilence() async {
        await store.refresh()
        defaults.set(false, forKey: NotificationTopic.cheers.key)
        backend.state.messages = [incoming("c", from: "bruno", kind: .cheer), incoming("d", from: "bruno")]
        await store.refresh()
        XCTAssertEqual(notified.map(\.id), ["d"], "Força desligada; mensagem continua")

        defaults.set(true, forKey: NotificationPrefs.pausedKey)
        backend.state.messages.append(incoming("e", from: "ana"))
        await store.refresh()
        XCTAssertEqual(notified.map(\.id), ["d"], "Pausado: nada toca")
        XCTAssertEqual(store.unreadMessages, 3, "Mas tudo continua na caixa de entrada")
    }

    func testOpenConversationIsNotNotifiedAndCountsAsRead() async {
        await store.refresh()
        store.openPeer = "bruno"
        backend.state.messages = [incoming("f", from: "bruno", minutesAgo: 0)]
        await store.refresh()
        XCTAssertTrue(notified.isEmpty)
        XCTAssertEqual(store.unread("bruno"), 0)
    }

    func testOldItemsDoNotNotify() async {
        await store.refresh()
        backend.state.messages = [incoming("g", from: "bruno", minutesAgo: 8 * 60)]
        await store.refresh()
        XCTAssertTrue(notified.isEmpty, "Mais de 6 h: só aparece na caixa")
    }

    // MARK: Lido

    func testUnreadAndMarkRead() async {
        backend.state.messages = [incoming("h", from: "bruno", minutesAgo: 3), incoming("i", from: "bruno", minutesAgo: 2), incoming("j", from: "ana", kind: .cheer)]
        backend.state.events = [InboxEvent(id: UUID().uuidString, kind: .reaction, actorID: "ana", actorName: "Ana", actorFormID: "",
                                           date: .now.addingTimeInterval(-30), text: "🔥", targetID: "x")]
        await store.refresh()
        XCTAssertEqual(store.unread("bruno"), 2)
        XCTAssertEqual(store.unreadMessages, 3)
        XCTAssertEqual(store.unreadActivity, 1, "Força conta nas mensagens, não duas vezes")
        XCTAssertEqual(store.badge, 4)
        store.markRead("bruno")
        store.markActivitySeen()
        XCTAssertEqual(store.badge, 1)
        XCTAssertEqual(store.conversations.first?.peer.id, "ana", "Mais recente primeiro")
    }

    // MARK: Convites

    func testInviteAnswer() async throws {
        let invite = incoming("k", from: "ana", kind: .invite)
        backend.state.messages = [invite]
        await store.refresh()
        XCTAssertNil(store.answer(to: invite))
        XCTAssertTrue(store.activity.contains { $0.kind == .invite && $0.targetID == "k" })
        try await store.reply(to: invite, accepted: true)
        XCTAssertEqual(store.answer(to: invite), true)
        XCTAssertEqual(backend.sent.last?.replyTo, "k")
    }

    // MARK: Regras de envio

    func testOnlyFriendsAndFilteredWords() async throws {
        await store.refresh()
        do {
            try await store.send(.text, to: "estranho", text: "oi")
            XCTFail("Não é amigo")
        } catch { XCTAssertEqual(error as? InboxError, .notFriend) }
        try await store.cheer("bruno")
        XCTAssertEqual(backend.sent.map(\.kind), [.cheer])
    }

    func testBlockedPeerDisappearsAndCannotReceive() async throws {
        backend.state.messages = [incoming("l", from: "bruno")]
        await store.refresh()
        await moderation.block(userID: "bruno", name: "Bruno")
        XCTAssertTrue(store.conversations.isEmpty)
        XCTAssertEqual(store.badge, 0)
        do {
            try await store.send(.text, to: "bruno", text: "oi")
            XCTFail("Bloqueado")
        } catch { XCTAssertEqual(error as? InboxError, .blocked) }
    }

    func testReportedMessageIsHidden() async {
        backend.state.messages = [incoming("m", from: "ana"), incoming("n", from: "ana")]
        await store.refresh()
        await moderation.report(ReportedContent(kind: .directMessage, id: "m", authorID: "ana"), reason: .spam)
        XCTAssertEqual(store.messages(with: "ana").map(\.id), ["n"])
    }

    func testWithoutPermissionNothingIsSent() async {
        store.access = await signedInAccess([])
        do {
            try await store.cheer("bruno")
            XCTFail("Sem permissão")
        } catch {}
        XCTAssertTrue(backend.sent.isEmpty)
    }

    // MARK: X1

    func testDuelEventsFollowWhoChallenged() {
        let now = Date.now
        let list = InboxStore.events(from: [
            duel("recebido", iChallenged: false, phase: .pending(expires: now.addingTimeInterval(3600))),
            duel("aceito", iChallenged: true, phase: .active(ends: now.addingTimeInterval(3600)), accepted: now.addingTimeInterval(-60)),
            duel("recusado-meu", iChallenged: true, phase: .declined),
            duel("recusado-por-mim", iChallenged: false, phase: .declined),
            duel("expirado-meu", iChallenged: true, phase: .expired),
            duel("fim", iChallenged: false, phase: .finished(ended: now.addingTimeInterval(-10)), accepted: now.addingTimeInterval(-90000),
                 score: DuelScore(mine: 3, theirs: 1)),
        ], firstSeen: { _ in now })
        let kinds = Dictionary(grouping: list, by: { $0.targetID ?? "" }).mapValues { Set($0.map(\.kind)) }
        XCTAssertEqual(kinds["recebido"], [.duelChallenge])
        XCTAssertNil(list.first { $0.targetID == "recebido" }?.accepted, "Pendente: botões na linha")
        XCTAssertEqual(kinds["aceito"], [.duelAccepted])
        XCTAssertEqual(kinds["recusado-meu"], [.duelDeclined])
        XCTAssertEqual(kinds["recusado-por-mim"], [.duelChallenge], "Quem recusou não é avisado da recusa")
        XCTAssertEqual(list.first { $0.targetID == "recusado-por-mim" }?.accepted, false)
        XCTAssertEqual(kinds["expirado-meu"], [.duelExpired])
        XCTAssertEqual(kinds["fim"], [.duelChallenge, .duelResult])
        XCTAssertTrue(list.allSatisfy { $0.topic == .duels })
    }

    func testDuelNotifiesOnceAndRespectsTopic() async {
        await store.refresh()
        duels = [duel("d1", iChallenged: false, phase: .pending(expires: .now.addingTimeInterval(3600)))]
        await store.refresh()
        XCTAssertEqual(notified.map(\.id), ["x1-recebido-d1"])
        XCTAssertEqual(store.unreadActivity, 1)
        await store.refresh()
        XCTAssertEqual(notified.count, 1)

        defaults.set(false, forKey: NotificationTopic.duels.key)
        duels.append(duel("d2", iChallenged: false, phase: .pending(expires: .now.addingTimeInterval(3600))))
        await store.refresh()
        XCTAssertEqual(notified.count, 1, "Tópico X1 desligado")
    }

    // MARK: Preferências

    func testTopicsStartOnAndCount() {
        XCTAssertTrue(NotificationTopic.allCases.allSatisfy { NotificationPrefs.isOn($0, defaults: defaults) })
        defaults.set(false, forKey: NotificationTopic.reactions.key)
        XCTAssertEqual(NotificationPrefs.enabledCount(defaults), NotificationTopic.allCases.count - 1)
        XCTAssertTrue(Set(NotificationPrefs.defaultsKeys).isSubset(of: Set(AccountData.userKeys)), "Preferências vão com a conta")
        XCTAssertTrue(Set(InboxStore.defaultsKeys).isSubset(of: Set(AccountData.userKeys)))
    }

    func testStableSeededUUID() {
        XCTAssertEqual(UUID(seed: "a"), UUID(seed: "a"))
        XCTAssertNotEqual(UUID(seed: "a"), UUID(seed: "b"))
    }
}

final class FakeInboxBackend: InboxBackend, @unchecked Sendable {
    var state = InboxState()
    var sent: [DirectMessage] = []

    func fetch() async throws -> InboxState { state }

    func send(_ message: DirectMessage) async throws -> DirectMessage {
        sent.append(message)
        state.messages.append(message)
        return message
    }
}

private struct SilentModerationBackend: ModerationBackend {
    func report(content: ReportedContent, reason: ReportReason) async throws {}
    func block(userID: String, name: String) async throws {}
    func unblock(userID: String) async throws {}
    func blockedUsers() async throws -> [BlockedUser] { [] }
}
