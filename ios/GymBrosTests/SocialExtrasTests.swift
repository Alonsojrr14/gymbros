import XCTest
@testable import GymBros

/// Por amigo (esconder, silenciar), Deck dos Bros, QR e conversa arquivada/limpa
@MainActor
final class SocialExtrasTests: GymTestCase {
    private func defaults() -> UserDefaults { scratchDefaults("social") }

    func testFriendPrefsPerFriend() {
        let d = defaults()
        XCTAssertEqual(FriendPrefs.of("ana", d), FriendPrefs())
        FriendPrefs.set("ana", { $0.hideMine = true }, defaults: d)
        FriendPrefs.set("bruno", { $0.muted = true }, defaults: d)
        XCTAssertTrue(FriendPrefs.of("ana", d).hideMine)
        XCTAssertTrue(FriendPrefs.of("bruno", d).muted)
        XCTAssertEqual(FriendPrefs.hiddenFrom(d), ["ana"])
        // Voltar ao padrão tira a pessoa da lista
        FriendPrefs.set("ana", { $0.hideMine = false }, defaults: d)
        XCTAssertEqual(FriendPrefs.hiddenFrom(d), [])
        XCTAssertNotNil(d.string(forKey: FriendPrefs.key))
    }

    func testFriendQRCode() {
        XCTAssertEqual(FriendQR.link("ABC123"), "gymbros://amigo/ABC123")
        XCTAssertEqual(FriendQR.code(in: "gymbros://amigo/abc123"), "ABC123")
        XCTAssertEqual(FriendQR.code(in: " XYZ789 "), "XYZ789")
        XCTAssertNil(FriendQR.code(in: "https://exemplo.com"))
        XCTAssertNotNil(FriendQR.image(FriendQR.link("ABC123")))
    }

    func testDeckShowsOthersUnseenAndRemembersSeen() {
        let l = MockLeague.make()
        let cards = BroDeck.cards(leagues: [l], checkIns: [], activities: [], me: "Eu", includeSeen: true)
        XCTAssertFalse(cards.isEmpty, "a liga de exemplo tem check-ins dos últimos dias")
        XCTAssertTrue(cards.allSatisfy { !$0.item.isMe && $0.item.date >= .now.addingTimeInterval(-3 * 86400) })
        // Do mais antigo para o mais novo
        XCTAssertEqual(cards.map(\.item.date), cards.map(\.item.date).sorted())
        let before = BroDeck.seen()
        defer { UserDefaults.standard.set(Array(before), forKey: BroDeck.seenKey) }
        BroDeck.markSeen([cards[0].id])
        XCTAssertFalse(BroDeck.cards(leagues: [l], checkIns: [], activities: [], me: "Eu").contains { $0.id == cards[0].id })
    }

    func testArchivedConversationComesBackWithNewMessage() {
        let d = defaults()
        let store = InboxStore(defaults: d)
        let peer = InboxPeer(id: "ana", name: "Ana", formID: MonsterForm.egg.id)
        let old = Conversation(peer: peer, last: DirectMessage(id: "1", peerID: "ana", outgoing: false, date: .now.addingTimeInterval(-60)), unread: 0)
        store.archive("ana")
        XCTAssertTrue(store.isArchived(old))
        let newer = Conversation(peer: peer, last: DirectMessage(id: "2", peerID: "ana", outgoing: false, date: .now.addingTimeInterval(60)), unread: 1)
        XCTAssertFalse(store.isArchived(newer))
        store.unarchive("ana")
        XCTAssertFalse(store.isArchived(old))
        store.clear("ana")
        XCTAssertGreaterThan(store.cleared("ana"), .now.addingTimeInterval(-5))
        XCTAssertEqual(store.cleared("bruno"), .distantPast)
    }

    func testReactionMessagesHaveTheirOwnTopic() {
        let m = DirectMessage(id: "r", peerID: "ana", outgoing: false, date: .now, kind: .reaction, text: "💪", replyTo: "1")
        XCTAssertEqual(m.topic, .reactions)
        XCTAssertEqual(m.preview, "Reagiu 💪")
        XCTAssertTrue(InboxNotice(message: m, peer: InboxPeer(id: "ana", name: "Ana", formID: "")).title.contains("reagiu"))
    }
}
