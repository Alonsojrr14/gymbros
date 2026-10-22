import XCTest
@testable import GymBros

/// Rodada suíça diária: pareamento, resultado por critério, pontos e bônus no ranking
final class SwissTests: GymTestCase {
    private var cal: Calendar { .current }

    private func start(_ daysAgo: Int) -> Date { cal.date(byAdding: .day, value: -daysAgo, to: cal.startOfDay(for: .now))! }

    private func table(_ members: [String], daysAgo: Int, tallies: [Date: [String: SwissTally]] = [:],
                       criterion: SwissCriterion = .pontos, identity: [String: String] = [:]) -> SwissTable {
        Swiss.table(members: members, tallies: tallies, start: start(daysAgo), end: nil, now: .now, seed: "LIGA01",
                    criterion: criterion, identity: identity)
    }

    private func pairs(_ r: SwissRound) -> Set<Set<String>> {
        Set(r.matches.compactMap { m in m.b.map { Set([m.a, $0]) } })
    }

    func testPairsNeighboursInRankOrder() {
        let p = Swiss.pair(ranked: ["a", "b", "c", "d"], met: [:], byes: [:])
        XCTAssertEqual(p.pairs.map { [$0.0, $0.1] }, [["a", "b"], ["c", "d"]])
        XCTAssertNil(p.bye)
    }

    func testAvoidsRematchWhenPossible() {
        let met = ["a": ["b": 1], "b": ["a": 1], "c": ["d": 1], "d": ["c": 1]]
        let p = Swiss.pair(ranked: ["a", "b", "c", "d"], met: met, byes: [:])
        XCTAssertEqual(p.pairs.map { [$0.0, $0.1] }, [["a", "c"], ["b", "d"]])
    }

    func testRematchWhenUnavoidable() {
        let p = Swiss.pair(ranked: ["a", "b"], met: ["a": ["b": 3], "b": ["a": 3]], byes: [:])
        XCTAssertEqual(p.pairs.map { [$0.0, $0.1] }, [["a", "b"]])
    }

    func testFourPlayersMeetEveryoneBeforeRepeating() {
        let t = table(["a", "b", "c", "d"], daysAgo: 3)
        let finished = t.rounds.filter(\.finished)
        XCTAssertEqual(finished.count, 3)
        XCTAssertEqual(Set(finished.flatMap(pairs)).count, 6)
    }

    func testByeRotatesBeforeAnyoneRepeats() {
        let t = table(["a", "b", "c"], daysAgo: 3)
        let byes = t.rounds.filter(\.finished).compactMap { $0.matches.first(where: \.isBye)?.a }
        XCTAssertEqual(byes.count, 3)
        XCTAssertEqual(Set(byes), ["a", "b", "c"])
        XCTAssertEqual(t.points, ["a": 1, "b": 1, "c": 1])
    }

    func testOddPlayerByeGoesToLowestWithFewestByes() {
        let p = Swiss.pair(ranked: ["a", "b", "c"], met: [:], byes: ["c": 1])
        XCTAssertEqual(p.bye, "b")
    }

    func testPairingIsDeterministicAndUsesGlobalIDs() {
        let mine = table(["me", "b", "c", "d", "e"], daysAgo: 5, identity: ["me": "z"])
        let theirs = table(["e", "d", "c", "b", "z"], daysAgo: 5)
        XCTAssertEqual(mine.rounds.count, theirs.rounds.count)
        for (x, y) in zip(mine.rounds, theirs.rounds) {
            let renamed = Set(pairs(x).map { Set($0.map { $0 == "me" ? "z" : $0 }) })
            XCTAssertEqual(renamed, pairs(y))
            XCTAssertEqual(x.matches.first(where: \.isBye).map { $0.a == "me" ? "z" : $0.a }, y.matches.first(where: \.isBye)?.a)
        }
    }

    /// O seu id no pareamento é o do servidor do modo atual (no Firebase, o uid), não o do iCloud:
    /// com "me" no seu aparelho e o uid nos outros, o sorteio e os desempates saíam diferentes
    func testSelfIDIsTheServerIDOfTheCurrentMode() {
        XCTAssertEqual(LeagueBoard.selfID, Backend.myID ?? "me")
    }

    func testFewerThanTwoMembersHasNoRound() {
        XCTAssertTrue(table(["me"], daysAgo: 3).rounds.isEmpty)
    }

    func testResultByCriterion() {
        let none = SwissTally(), one = SwissTally(score: 30, checkIns: 1), two = SwissTally(score: 20, checkIns: 2)
        XCTAssertEqual(SwissCriterion.pontos.result(one, two).0, 1)
        XCTAssertEqual(SwissCriterion.checkins.result(one, two).1, 1)
        XCTAssertEqual(SwissCriterion.presenca.result(one, two).0, 0.5)
        XCTAssertEqual(SwissCriterion.presenca.result(one, none).0, 1)
        for c in SwissCriterion.allCases {
            XCTAssertEqual(c.result(none, none).0, 0)
            XCTAssertEqual(c.result(none, none).1, 0)
        }
    }

    func testTodayIsInProgressAndDoesNotScore() {
        let today = cal.startOfDay(for: .now)
        let t = table(["a", "b"], daysAgo: 0, tallies: [today: ["a": SwissTally(score: 50, checkIns: 1)]])
        XCTAssertEqual(t.rounds.count, 1)
        XCTAssertFalse(t.rounds[0].finished)
        XCTAssertEqual(t.today?.match(of: "a")?.tally(of: "a").score, 50)
        XCTAssertTrue(t.points.isEmpty)
        XCTAssertTrue(t.bonuses(scoring: .pontos).isEmpty)
    }

    func testBonusTable() {
        XCTAssertEqual(SwissBonus.value(.vitoria, scoring: .pontos), 10)
        XCTAssertEqual(SwissBonus.value(.folga, scoring: .distancia), 500)
        XCTAssertEqual(SwissBonus.value(.empate, scoring: .minutos), 2)
        XCTAssertEqual(SwissBonus.value(.empate, scoring: .treinos), 0)
        XCTAssertEqual(SwissBonus.value(.derrota, scoring: .calorias), 0)
    }

    func testPointsAndHistoryAccumulate() {
        let d2 = start(2), d1 = start(1)
        let t = table(["a", "b"], daysAgo: 2, tallies: [d2: ["a": SwissTally(score: 10, checkIns: 1), "b": SwissTally(score: 10, checkIns: 1)],
                                                         d1: ["a": SwissTally(score: 5, checkIns: 1)]])
        XCTAssertEqual(t.points, ["a": 1.5, "b": 0.5])
        XCTAssertEqual(t.history(of: "a").map(\.result), [.vitoria, .empate])
        XCTAssertEqual(t.bonuses(scoring: .pontos)["a"]?.total, 15)
        XCTAssertEqual(t.bonuses(scoring: .pontos)["b"]?.total, 5)
        XCTAssertEqual(t.bonuses(scoring: .pontos, since: d1)["a"]?.total, 10)
        XCTAssertNil(t.bonuses(scoring: .pontos, since: d1)["b"])
    }

    private func item(_ member: String, score: Int, at date: Date, isMe: Bool = false) -> FeedItem {
        FeedItem(id: UUID().uuidString, memberID: member, name: member, avatar: .egg, isMe: isMe,
                 date: date, title: "", note: "", kind: .corrida, minutes: 30, score: score, photo: nil, hasPhoto: true)
    }

    func testRankingAddsBonusByRoundDay() {
        let league = League(name: "Suíço", emoji: "🏆", scoring: .pontos, start: start(2))
        let remote = RemoteLeague(members: [RemoteMember(id: "ana", name: "Ana", formID: MonsterForm.egg.id)])
        let feed = [item("me", score: 30, at: day(-1), isMe: true), item("ana", score: 40, at: day(0, hour: 0))].sorted { $0.date > $1.date }
        let all = LeagueBoard.ranking(feed: feed, league: league, me: "Eu", myAvatar: .egg, since: nil, remote: remote)
        let me = all.first { $0.isMe }!
        XCTAssertEqual(me.score, 40)
        XCTAssertEqual(me.bonus, 10)
        XCTAssertEqual(me.swiss, 1)
        XCTAssertEqual(all.first { $0.id == "ana" }?.score, 40)
        XCTAssertEqual(all.first { $0.id == "ana" }?.swiss, 0)
        // A rodada de ontem não entra numa janela que começa hoje
        let fromToday = LeagueBoard.ranking(feed: feed, league: league, me: "Eu", myAvatar: .egg, since: cal.startOfDay(for: .now), remote: remote)
        XCTAssertEqual(fromToday.first { $0.isMe }?.score, 0)
    }

    func testPhotoRuleDecidesValidCheckIns() {
        let league = League(name: "Foto", emoji: "🏆", scoring: .treinos, start: start(1))
        league.photoRule = .obrigatoria
        league.swiss = .presenca
        let remote = RemoteLeague(members: [RemoteMember(id: "ana", name: "Ana", formID: MonsterForm.egg.id)])
        var noPhoto = item("ana", score: 0, at: day(-1))
        noPhoto.hasPhoto = false
        let t = LeagueBoard.swiss(league: league, feed: [noPhoto, item("me", score: 1, at: day(-1), isMe: true)], remote: remote)
        XCTAssertEqual(t.points["me"], 1)
        XCTAssertEqual(t.points["ana"], 0)
    }

    func testLateJoinerIsPairedOnlyFromJoinDay() {
        let t = Swiss.table(members: ["a", "b", "c"], tallies: [:], start: start(5), end: nil, now: .now, seed: "LIGA01",
                            criterion: .pontos, joined: ["c": start(2)])
        XCTAssertEqual(t.rounds.count, 6)
        for r in t.rounds where r.day < start(2) {
            XCTAssertNil(r.match(of: "c"))
            XCTAssertFalse(r.matches.contains(where: \.isBye))
        }
        for r in t.rounds where r.day >= start(2) { XCTAssertNotNil(r.match(of: "c")) }
        XCTAssertEqual(t.history(of: "c", limit: 30).count, 2)
        XCTAssertEqual(t.history(of: "a", limit: 30).count, 5)
    }

    func testNoRoundWhileOnlyOneMember() {
        let t = Swiss.table(members: ["a", "b"], tallies: [:], start: start(4), end: nil, now: .now, seed: "LIGA01",
                            criterion: .pontos, joined: ["b": start(1)])
        XCTAssertEqual(t.rounds.map(\.day), [start(1), start(0)])
    }

    func testJoiningMockLeagueLateHasNoPastRounds() {
        let league = League(name: "Amigos", emoji: "🔥", scoring: .pontos, start: start(12), isMock: true)
        league.joinedAt = .now
        let remote = RemoteLeague(members: FakeMember.all.map { RemoteMember(id: $0.id, name: $0.name, formID: $0.form.id) })
        let t = LeagueBoard.swiss(league: league, feed: [], remote: remote)
        XCTAssertTrue(t.history(of: "me", limit: 30).isEmpty)
        XCTAssertTrue(t.rounds.filter(\.finished).allSatisfy { $0.match(of: "me") == nil })
        XCTAssertNotNil(t.today?.match(of: "me"))
        let rows = LeagueBoard.ranking(feed: [], league: league, me: "Eu", myAvatar: .egg, since: nil, remote: remote, swiss: t)
        XCTAssertEqual(rows.first { $0.isMe }?.bonus, 0)
        XCTAssertNil(rows.first { $0.isMe }?.swiss)
    }

    func testRemoteMemberJoinDateIsRespected() {
        let league = League(name: "Suíço", emoji: "🏆", scoring: .pontos, start: start(3))
        let remote = RemoteLeague(members: [RemoteMember(id: "ana", name: "Ana", formID: MonsterForm.egg.id),
                                             RemoteMember(id: "bia", name: "Bia", formID: MonsterForm.egg.id, joinedAt: day(-1))])
        let t = LeagueBoard.swiss(league: league, feed: [], remote: remote)
        XCTAssertEqual(t.history(of: "bia", limit: 30).count, 1)
        XCTAssertEqual(t.history(of: "me", limit: 30).count, 3)
    }

    func testCreatorCountsFromLeagueStart() {
        let league = League(name: "Minha", emoji: "🏆", scoring: .pontos, start: start(3))
        league.joinedAt = .now
        XCTAssertEqual(league.swissJoinedAt, league.start)
        league.joined = true
        XCTAssertEqual(league.swissJoinedAt, league.joinedAt)
    }
}
