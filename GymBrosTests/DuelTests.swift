import XCTest
@testable import GymBros

/// X1 global: entre quaisquer duas pessoas, sem liga; métrica escolhida por quem desafia; 24 h depois do aceite
final class DuelTests: GymTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let hour: TimeInterval = 3600

    private func person(_ id: String) -> DuelPerson { DuelPerson(id: id, name: id.capitalized, formID: MonsterForm.egg.id) }

    private func act(_ date: Date, minutes: Int = 30, meters: Double? = nil) -> DuelActivity {
        DuelActivity(date: date, kind: .corrida, minutes: minutes, effort: 5, meters: meters)
    }

    private func duel(_ id: String = "d1", from: String = "me", to: String = "bruno", metric: DuelMetric = .treinos, created: Date? = nil,
                      answer: DuelAnswer? = nil, answered: Date? = nil, theirs: Int? = nil) -> RemoteDuel {
        var d = RemoteDuel(id: id, challenger: person(from), challenged: person(to), metric: metric, createdAt: created ?? t0,
                           answer: answer, answeredAt: answered)
        if let theirs { d.reported[from == "me" ? to : from] = theirs }
        return d
    }

    private func refusal(_ opponent: String = "bruno", duels: [RemoteDuel] = [], blocked: Set<String> = [], blockedBy: Set<String> = [],
                         now: Date? = nil) -> DuelRefusal? {
        Duels.refusal(me: "me", opponent: opponent, duels: duels, blocked: blocked, blockedBy: blockedBy, now: now ?? t0)
    }

    // MARK: Janela e placar

    func testAcceptedDuelLasts24HoursFromAcceptance() {
        let d = duel(answer: .accepted, answered: t0 + 2 * hour)
        XCTAssertEqual(d.phase(now: t0 + 3 * hour), .active(ends: t0 + 26 * hour))
        XCTAssertEqual(d.phase(now: t0 + 26 * hour - 1), .active(ends: t0 + 26 * hour))
        XCTAssertEqual(d.phase(now: t0 + 26 * hour), .finished(ended: t0 + 26 * hour))
    }

    func testMyValueCountsAnyActivityOnlyInTheWindow() {
        let d = duel(answer: .accepted, answered: t0 + hour, theirs: 1)
        let acts = [act(t0), act(t0 + 2 * hour), act(t0 + 10 * hour), act(t0 + 24 * hour), act(t0 + 25 * hour)]
        XCTAssertEqual(Duels.score(d, activities: acts, now: t0 + 30 * hour), DuelScore(mine: 3, theirs: 1))
        XCTAssertEqual(Duels.score(d, activities: acts, now: t0 + 3 * hour).mine, 1, "ao vivo só até agora")
        XCTAssertEqual(Duels.myValue(duel(), activities: acts, now: t0 + 30 * hour), 0, "sem aceite não há placar")
    }

    func testMetricsMeasureDifferentThings() {
        let a = act(t0 + 2 * hour, minutes: 45, meters: 7_500)
        func value(_ m: DuelMetric) -> Int { Duels.myValue(duel(metric: m, answer: .accepted, answered: t0), activities: [a], now: t0 + 30 * hour) }
        XCTAssertEqual(value(.treinos), 1)
        XCTAssertEqual(value(.minutos), 45)
        XCTAssertEqual(value(.distancia), 7_500)
        XCTAssertEqual(value(.xp), Game.xp(kind: .corrida, minutes: 45, effort: 5))
        XCTAssertGreaterThan(value(.calorias), 0, "sem kcal do Saúde, estimada")
    }

    func testWinnerDrawAndLoss() {
        XCTAssertEqual(DuelScore(mine: 3, theirs: 1).result, .vitoria)
        XCTAssertEqual(DuelScore(mine: 1, theirs: 3).result, .derrota)
        XCTAssertEqual(DuelScore(mine: 2, theirs: 2).result, .empate)
        XCTAssertEqual(Duels.summary(DuelScore(mine: 3, theirs: 1), opponent: "Bruno", metric: .treinos), "Você venceu Bruno no X1 · 3 a 1 treinos")
        XCTAssertEqual(Duels.summary(DuelScore(mine: 1, theirs: 1), opponent: "Ana", metric: .treinos), "Você empatou com Ana no X1 · 1 a 1 treino")
        XCTAssertEqual(Duels.summary(DuelScore(mine: 30, theirs: 90), opponent: "Ana", metric: .minutos), "Você perdeu para Ana no X1 · 30 min a 1 h 30 min")
    }

    func testRecordsAndTally() {
        let won = duel("a", answer: .accepted, answered: t0, theirs: 0)
        let lost = duel("b", to: "ana", answer: .accepted, answered: t0, theirs: 5)
        let active = duel("c", to: "carla", answer: .accepted, answered: t0 + 20 * hour)
        let declined = duel("d", to: "diego", answer: .declined, answered: t0)
        let records = Duels.records([won, lost, active, declined], activities: [act(t0 + hour)], now: t0 + 25 * hour)
        XCTAssertEqual(Set(records.map(\.id)), ["a", "b"])
        let t = Duels.tally(records)
        XCTAssertEqual([t.v, t.e, t.d], [1, 0, 1])
    }

    // MARK: Regras

    func testFastRefreshOnlyRightAfterYouChallenge() {
        XCTAssertEqual(Duels.refreshInterval([duel()], now: t0 + 10), 3)
        XCTAssertEqual(Duels.refreshInterval([duel()], now: t0 + Duels.fastWindow + 1), 30)
        XCTAssertEqual(Duels.refreshInterval([duel(from: "bruno", to: "me")], now: t0 + 10), 30)
        XCTAssertEqual(Duels.refreshInterval([], now: t0), 30)
    }

    func testPendingChallengeExpiresAfter24Hours() {
        let d = duel()
        XCTAssertEqual(d.phase(now: t0 + 23 * hour), .pending(expires: t0 + 24 * hour))
        XCTAssertEqual(d.phase(now: t0 + 24 * hour), .expired)
        XCTAssertEqual(Duels.acceptRefusal(duel(from: "bruno", to: "me"), me: "me", duels: [], blocked: [], now: t0 + 25 * hour), .notPending)
        XCTAssertNil(Duels.acceptRefusal(duel(from: "bruno", to: "me"), me: "me", duels: [], blocked: [], now: t0 + hour))
    }

    func testOnlyOneOpenDuelPerPair() {
        XCTAssertNil(refusal())
        XCTAssertEqual(refusal(duels: [duel()]), .alreadyOpen)
        XCTAssertEqual(refusal(duels: [duel(from: "bruno", to: "me")]), .alreadyOpen, "vale nos dois sentidos")
        XCTAssertNil(refusal("ana", duels: [duel()]))
        XCTAssertNil(refusal(duels: [duel(answer: .accepted, answered: t0)], now: t0 + 25 * hour), "encerrado libera")
        XCTAssertNil(refusal(duels: [duel()], now: t0 + 24 * hour), "expirado libera")
        let active = duel("a", answer: .accepted, answered: t0)
        let incoming = duel("b", from: "bruno", to: "me", created: t0 + hour)
        XCTAssertEqual(Duels.acceptRefusal(incoming, me: "me", duels: [active, incoming], blocked: [], now: t0 + 2 * hour), .alreadyOpen)
        // Desafios cruzados quase juntos: só o mais antigo pode ser aceito
        let mine = duel("c", created: t0)
        let theirs = duel("d", from: "bruno", to: "me", created: t0 + 60)
        XCTAssertEqual(Duels.acceptRefusal(theirs, me: "me", duels: [mine, theirs], blocked: [], now: t0 + hour), .alreadyOpen)
        let older = duel("e", from: "bruno", to: "me", created: t0)
        let newer = duel("f", created: t0 + 60)
        XCTAssertNil(Duels.acceptRefusal(older, me: "me", duels: [older, newer], blocked: [], now: t0 + hour))
    }

    func testHealthActivityCountsWithoutHealthData() {
        let a = Activity(kind: .corrida, date: t0, minutes: 30, effort: 9)
        a.healthUUID = "hk-1"
        a.meters = 5_000
        a.kcal = 400
        let d = a.duelActivity
        XCTAssertEqual(d.effort, 5)
        XCTAssertNil(d.meters)
        XCTAssertNil(d.kcal)
    }

    func testAnyoneCanBeChallengedButYourselfAndBlocked() {
        XCTAssertNil(refusal("alguem-de-fora-das-ligas"), "não precisa estar numa liga")
        XCTAssertEqual(refusal("me"), .yourself)
        XCTAssertEqual(refusal(blocked: ["bruno"]), .blocked)
        XCTAssertEqual(refusal(blockedBy: ["bruno"]), .blocked)
        XCTAssertEqual(Duels.acceptRefusal(duel(from: "bruno", to: "me"), me: "me", duels: [], blocked: ["bruno"], now: t0), .blocked)
    }

    // MARK: Servidor simulado

    private func mockServer(incoming: Bool = false) -> (MockDuelServer, UserDefaults) {
        let defaults = UserDefaults(suiteName: "duel-tests-\(UUID().uuidString)")!
        let people = MockFriendsBackend.directory.map { DuelPerson(id: $0.id, name: $0.name, formID: $0.formID) }
        return (MockDuelServer(defaults: defaults, simulatedIncoming: incoming, people: { people }), defaults)
    }

    func testSimulatedPersonAnswersAndTrains() async throws {
        let (server, _) = mockServer()
        let d = try await server.challenge(person("bruno"), from: person("me"), metric: .treinos, now: t0)
        let reply = MockDuelServer.reply(to: d)
        XCTAssertGreaterThanOrEqual(reply.date.timeIntervalSince(t0), 3)
        XCTAssertLessThanOrEqual(reply.date.timeIntervalSince(t0), 9)
        let before = await server.duels(now: t0 + 2).first { $0.id == d.id }
        XCTAssertNil(before?.answer)
        let after = await server.duels(now: t0 + 10).first { $0.id == d.id }
        XCTAssertEqual(after?.answer, reply.answer)
        if reply.answer == .accepted {
            let end = await server.duels(now: t0 + 30 * hour).first { $0.id == d.id }
            XCTAssertGreaterThan(end?.reported["bruno"] ?? 0, 0, "a pessoa simulada treina durante o X1")
        }
    }

    func testSimulatedPeopleMostlyAccept() {
        let accepted = (0..<200).filter { i in
            MockDuelServer.reply(to: RemoteDuel(id: "d\(i)", challenger: person("me"), challenged: person("ana"), metric: .xp, createdAt: t0)).answer == .accepted
        }.count
        XCTAssertGreaterThan(accepted, 120)
        XCTAssertLessThan(accepted, 200)
    }

    func testMockServerEnforcesPairBlockAndUnknown() async throws {
        let (server, _) = mockServer()
        _ = try await server.challenge(person("ana"), from: person("me"), metric: .xp, now: t0)
        do {
            _ = try await server.challenge(person("ana"), from: person("me"), metric: .minutos, now: t0 + 1)
            XCTFail("segundo X1 aberto com a mesma pessoa")
        } catch { XCTAssertEqual(error as? DuelRefusal, .alreadyOpen) }
        await server.setBlockedBy(["carla"])
        do {
            _ = try await server.challenge(person("carla"), from: person("me"), metric: .xp, now: t0)
            XCTFail("quem te bloqueou")
        } catch { XCTAssertEqual(error as? DuelRefusal, .blocked) }
        do {
            _ = try await server.challenge(person("zeca"), from: person("me"), metric: .xp, now: t0)
            XCTFail("pessoa que não existe")
        } catch { XCTAssertEqual(error as? DuelRefusal, .notFound) }
    }

    func testIncomingChallengeCanBeAnsweredAndPersists() async throws {
        var found: (MockDuelServer, UserDefaults, RemoteDuel, Date)?
        for k in 0..<30 where found == nil {
            let now = Date.now.addingTimeInterval(Double(k) * 86_400)
            let (server, defaults) = mockServer(incoming: true)
            if let d = await server.duels(now: now).first(where: { $0.challenged.id == "me" && $0.isPending(now: now) }) {
                found = (server, defaults, d, now)
            }
        }
        guard let (server, defaults, incoming, now) = found else { return XCTFail("As pessoas simuladas deveriam desafiar você às vezes") }
        XCTAssertTrue(MockFriendsBackend.directory.contains { $0.id == incoming.challenger.id })
        try await server.respond(to: incoming.id, accept: true, now: now)
        let people = MockFriendsBackend.directory.map { DuelPerson(id: $0.id, name: $0.name, formID: $0.formID) }
        let again = await MockDuelServer(defaults: defaults, people: { people }).duels(now: now).first { $0.id == incoming.id }
        XCTAssertEqual(again?.answer, .accepted)
    }

    func testSimulatedPeopleAlwaysHaveAChallengeWaiting() async {
        let cal = Calendar.current
        for k in 0..<10 {
            let now = cal.startOfDay(for: .now).addingTimeInterval(Double(k) * 86_400 + Double(k % 24) * 3600 + 600)
            let (server, _) = mockServer(incoming: true)
            let pending = await server.duels(now: now).filter { $0.challenged.id == "me" && $0.isPending(now: now) }
            XCTAssertFalse(pending.isEmpty, "sem desafio esperando em \(now)")
        }
    }

    func testEachBroFightsOneDuelAtATime() {
        var sent = duel("a", from: "me", to: "bruno", created: t0)
        var active = duel("b", from: "carla", to: "me", created: t0)
        active.answer = .accepted
        active.answeredAt = t0 + 60
        let waiting = duel("c", from: "diego", to: "me", created: t0)
        let reps = ["a": "bro-1", "b": "bro-2"]
        XCTAssertEqual(Duels.busyFighters([sent, active, waiting], representatives: reps, now: t0 + 3600), ["bro-1", "bro-2"])
        // Acabou ou foi recusado: o bro fica livre de novo
        sent.answer = .declined
        sent.answeredAt = t0 + 60
        XCTAssertEqual(Duels.busyFighters([sent, active], representatives: reps, now: t0 + Duels.window + 3600), [])
    }
}
