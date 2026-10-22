import HealthKit
import XCTest
@testable import GymBros

/// Modos de pontuação, peso por atributo, janela do ranking e desempate
final class LeagueTests: GymTestCase {
    private let corrida = ScoreInput(kind: .corrida, minutes: 60, effort: 5, meters: 10_000)
    private let musculacao = ScoreInput(kind: .musculacao, minutes: 60, effort: 5)

    private func item(_ member: String, score: Int, hoursAgo: Double, isMe: Bool = false) -> FeedItem {
        FeedItem(id: UUID().uuidString, memberID: member, name: member, avatar: .egg, isMe: isMe,
                 date: .now.addingTimeInterval(-hoursAgo * 3600), title: "", note: "", kind: .corrida, minutes: 30, score: score, photo: nil)
    }

    private func league(_ tie: LeagueTieBreak = .primeiro) -> League {
        let l = League(name: "Teste", emoji: "🏆", scoring: .pontos, start: .now.addingTimeInterval(-30 * 86400))
        l.tieBreak = tie
        return l
    }

    func testWeightsDefaultToXP() {
        XCTAssertEqual(LeagueScoring.pontos.score(corrida), Game.xp(kind: .corrida, minutes: 60, effort: 5))
        let ones = Dictionary(uniqueKeysWithValues: Attribute.allCases.map { ($0, 1.0) })
        XCTAssertEqual(LeagueScoring.pontos.score(corrida, weights: ones), LeagueScoring.pontos.score(corrida))
    }

    func testWeightsScaleOnlyTheirAttribute() {
        // Musculação é 80% força: força 2× → 1,8× os pontos
        let xp = Double(Game.xp(kind: .musculacao, minutes: 60, effort: 5))
        XCTAssertEqual(LeagueScoring.pontos.score(musculacao, weights: [.forca: 2]), Int((xp * 1.8).rounded()))
        // Zerar força e técnica zera a musculação; corrida não muda
        XCTAssertEqual(LeagueScoring.pontos.score(musculacao, weights: [.forca: 0, .tecnica: 0]), 0)
        XCTAssertEqual(LeagueScoring.pontos.score(corrida, weights: [.forca: 0, .tecnica: 0]), LeagueScoring.pontos.score(corrida))
    }

    func testWeightsRoundTrip() {
        let l = league()
        l.attributeWeights = [.forca: 2, .resistencia: 1, .tecnica: 0.5]
        // 1× não é guardado
        XCTAssertEqual(l.attributeWeights, [.forca: 2, .tecnica: 0.5])
        XCTAssertEqual(l.weightsRaw, "forca:2,tecnica:0.5")
    }

    func testMetricModes() {
        XCTAssertEqual(LeagueScoring.distancia.score(corrida), 10_000)
        XCTAssertEqual(LeagueScoring.distancia.score(musculacao), 0)
        XCTAssertEqual(LeagueScoring.distancia.format(12_345), "12 km")
        XCTAssertEqual(LeagueScoring.distancia.format(4_260), "4,3 km")
        // Calorias informadas têm prioridade sobre a estimativa
        var real = musculacao
        real.kcal = 412.4
        XCTAssertEqual(LeagueScoring.calorias.score(real), 412)
        XCTAssertGreaterThan(LeagueScoring.calorias.score(musculacao), 0)
    }

    func testMonthWindowStartsOnFirstDay() {
        let cal = Calendar.current
        let since = RankWindow.mes.since()!
        XCTAssertEqual(cal.component(.day, from: since), 1)
        XCTAssertNil(RankWindow.liga.since())
    }

    func testTieBreakFirstToReachScore() {
        let feed = [item("ana", score: 10, hoursAgo: 1), item("bia", score: 10, hoursAgo: 5)].sorted { $0.date > $1.date }
        let rank = LeagueBoard.ranking(feed: feed, league: league(.primeiro), me: "Eu", myAvatar: .egg, since: nil)
        XCTAssertEqual(rank.prefix(2).map(\.id), ["bia", "ana"])
        XCTAssertTrue(rank[0].tied && rank[1].tied)
        // Quem está zerado não aparece como empatado
        XCTAssertFalse(rank.first { $0.isMe }!.tied)
    }

    func testTieBreakStreak() {
        let feed = [item("ana", score: 10, hoursAgo: 1),
                    item("bia", score: 5, hoursAgo: 2), item("bia", score: 5, hoursAgo: 26)].sorted { $0.date > $1.date }
        let rank = LeagueBoard.ranking(feed: feed, league: league(.sequencia), me: "Eu", myAvatar: .egg, since: nil)
        XCTAssertEqual(rank.first?.id, "bia")
        XCTAssertEqual(rank.first?.bestStreak, 2)
    }

    func testTieBreakCheckIns() {
        let feed = [item("ana", score: 10, hoursAgo: 1),
                    item("bia", score: 5, hoursAgo: 2), item("bia", score: 5, hoursAgo: 3)].sorted { $0.date > $1.date }
        let rank = LeagueBoard.ranking(feed: feed, league: league(.checkins), me: "Eu", myAvatar: .egg, since: nil)
        XCTAssertEqual(rank.first?.id, "bia")
    }

    /// Dias, semanas, tetos e campeões no fuso de Brasília em qualquer aparelho (como a rodada suíça)
    func testLeagueRulesUseBrasiliaTime() {
        XCTAssertEqual(League.rulesCalendar.timeZone.identifier, "America/Sao_Paulo")
        XCTAssertEqual(League.rulesCalendar.identifier, .gregorian)
        XCTAssertEqual(league().settings.calendar().timeZone.identifier, "America/Sao_Paulo")
        XCTAssertEqual(league().start, League.rulesCalendar.startOfDay(for: league().start))
    }

    /// Empate total: decide o id global, não "eu primeiro" (cada aparelho punha o dono na frente)
    func testFinalTieBreakIsTheSameOnEveryDevice() {
        let feed = [item("aaa", score: 10, hoursAgo: 2), item("me", score: 10, hoursAgo: 2, isMe: true)]
        let rank = LeagueBoard.ranking(feed: feed, league: league(.checkins), me: "Eu", myAvatar: .egg, since: nil)
        let order = rank.filter { $0.score > 0 }.map { $0.isMe ? LeagueBoard.selfID : $0.id }
        XCTAssertEqual(order, order.sorted())
    }

    func testPhotoRule() {
        let l = league()
        let full = l.score(corrida)
        l.photoRule = .metade
        XCTAssertEqual(l.score(corrida, hasPhoto: false), (full + 1) / 2)
        XCTAssertEqual(l.score(corrida, hasPhoto: true), full)
        l.photoRule = .obrigatoria
        XCTAssertEqual(l.score(corrida, hasPhoto: false), 0)
    }

    func testLeagueFormatIsDerivedFromPeriod() {
        let club = League(name: "Clube", emoji: "🏆", scoring: .pontos)
        XCTAssertEqual(club.format, .club)

        club.setDuration(days: 30)
        XCTAssertEqual(club.format, .challenge)

        club.setDuration(days: 0)
        XCTAssertEqual(club.format, .club)
    }

    func testActivityRuleAcceptsOnlyConfiguredWorkoutTypes() {
        let strength = WorkoutType.of(.musculacao)
        let crossfit = WorkoutType.of(.crossfit)
        let bike = WorkoutType.of(.bike)
        let rule = LeagueActivityRule(mode: .only, workoutTypeIDs: [strength.id, crossfit.id])
        XCTAssertTrue(rule.accepts(strength.id))
        XCTAssertTrue(rule.accepts(crossfit.id))
        XCTAssertFalse(rule.accepts(bike.id))
        XCTAssertEqual(LeagueActivityRule(rawValue: rule.rawValue), rule)
    }

    func testDisallowedWorkoutScoresZero() {
        let l = league()
        l.activityRule = LeagueActivityRule(mode: .except, workoutTypeIDs: [WorkoutType.of(.bike).id])
        var bike = corrida
        bike.workoutTypeID = WorkoutType.of(.bike).id
        XCTAssertEqual(l.score(bike), 0)
    }

    func testRemoteCheckInKeepsSpecificWorkoutType() {
        // Skate é "outro" na categoria: sem o tipo no check-in, outro aparelho não saberia que é skate
        let skate = WorkoutType.byID(UInt(HKWorkoutActivityType.skatingSports.rawValue))!
        let l = league()
        l.activityRule = LeagueActivityRule(mode: .except, workoutTypeIDs: [skate.id])
        let remote = RemoteCheckIn(id: "1", memberID: "m", date: .now, kindRaw: skate.kind.rawValue, minutes: 60, effort: 5,
                                   title: "Pista", workoutTypeID: skate.id)
        XCTAssertEqual(l.score(remote.input), 0)
        // Check-in antigo, sem o tipo: vale o padrão da categoria
        var old = remote
        old.workoutTypeID = nil
        XCTAssertGreaterThan(l.score(old.input), 0)
    }

    func testHalfPhotoNeverZeroesAScore() {
        // Modo Treinos: 1 sem foto não pode virar 0 (arredonda para cima)
        XCTAssertEqual(PhotoRule.metade.apply(1, hasPhoto: false), 1)
        XCTAssertEqual(PhotoRule.metade.apply(5, hasPhoto: false), 3)
        XCTAssertEqual(PhotoRule.metade.apply(0, hasPhoto: false), 0)
        let l = League(name: "T", emoji: "🏆", scoring: .treinos)
        l.photoRule = .metade
        XCTAssertEqual(l.score(musculacao, hasPhoto: false), 1)
    }

    func testRestoredCheckInKeepsPhotoScore() {
        // Backup não traz a imagem, mas o check-in lembra que tinha foto
        let c = LeagueCheckIn(leagueUUID: UUID(), activityUUID: UUID(), title: "", note: "", date: .now, photo: nil)
        XCTAssertFalse(c.hasPhoto)
        c.hadPhoto = true
        XCTAssertTrue(c.hasPhoto)
        // Editar sem foto nenhuma guardada não apaga o "tinha foto"; tirar uma foto de verdade apaga
        c.setPhoto(nil)
        XCTAssertTrue(c.hasPhoto)
        c.setPhoto(Data([1]))
        c.setPhoto(nil)
        XCTAssertFalse(c.hasPhoto)
    }

    func testTeamIDsAreStable() {
        let l = league()
        let verde = LeagueTeam(name: "Verde"), roxo = LeagueTeam(name: "Roxo"), azul = LeagueTeam(name: "Azul")
        l.teams = [verde, LeagueTeam(name: " "), roxo, azul]
        XCTAssertEqual(l.teamNames, ["Verde", "Roxo", "Azul"])
        l.myTeamID = roxo.id
        // Renomear e reordenar não troca de time
        l.teams = [azul, LeagueTeam(id: roxo.id, name: "Roxo Power"), verde]
        XCTAssertEqual(l.myTeamID, roxo.id)
        XCTAssertEqual(l.teams.first { $0.id == l.myTeamID }?.name, "Roxo Power")
        // Tirar outro time também não
        l.teams = [LeagueTeam(id: roxo.id, name: "Roxo Power"), verde]
        XCTAssertEqual(l.myTeamID, roxo.id)
        // Tirar o seu time tira você dele
        l.teams = [verde, azul]
        XCTAssertNil(l.myTeamID)
    }

    func testLegacyTeamsKeepPositionalIDs() {
        // Formato antigo: só os nomes, id = posição
        let l = league()
        l.teamsRaw = "Verde\nRoxo"
        l.myTeamID = "t1"
        XCTAssertEqual(l.teams.map(\.id), ["t0", "t1"])
        XCTAssertEqual(l.teams.first { $0.id == l.myTeamID }?.name, "Roxo")
        // Ao salvar de novo, o id do formato antigo vira o id fixo do time
        var t = l.teams
        t.swapAt(0, 1)
        t[0].name = "Roxo 2"
        l.teams = t
        XCTAssertEqual(l.teamsRaw, "t1\tRoxo 2\nt0\tVerde")
        XCTAssertEqual(l.myTeamID, "t1")
    }

    func testRankingUsesInjectedRemote() {
        let l = league()
        var remote = RemoteLeague()
        remote.members = [RemoteMember(id: "zeca", name: "Zeca", formID: MonsterForm.egg.id)]
        let rank = LeagueBoard.ranking(feed: [], league: l, me: "Eu", myAvatar: .egg, since: nil, remote: remote)
        XCTAssertEqual(Set(rank.map(\.id)), ["me", "zeca"])
    }

    func testSimulatedPeopleHaveSameBroEverywhere() {
        for f in FriendsLive.simulated {
            XCTAssertEqual(f.form, FakeMember.byID(f.id)?.form, f.id)
        }
    }

    func testMockBackendIsStableAndSplitsTeams() {
        let l = league()
        l.isMock = true
        l.teams = [LeagueTeam(name: "Verde"), LeagueTeam(name: "Roxo")]
        let a = MockLeagueBackend.build(l.key), b = MockLeagueBackend.build(l.key)
        XCTAssertEqual(a.checkIns.map(\.id), b.checkIns.map(\.id))
        XCTAssertEqual(a.messages.map(\.text), b.messages.map(\.text))
        XCTAssertEqual(a.teams.count, 2)
        // Todo participante simulado tem time, e os times ficam equilibrados
        XCTAssertEqual(a.teams.flatMap(\.memberIDs).count, FakeMember.all.count)
        XCTAssertLessThanOrEqual(abs(a.teams[0].memberIDs.count - a.teams[1].memberIDs.count), 1)
        XCTAssertFalse(a.messages.isEmpty)
        // Liga sem participantes simulados só tem os times
        l.isMock = false
        XCTAssertTrue(MockLeagueBackend.build(l.key).members.isEmpty)
    }

    func testTeamScoreIsSumOfMembers() {
        let l = league()
        let roxo = LeagueTeam(name: "Roxo")
        l.teams = [LeagueTeam(name: "Verde"), roxo]
        l.myTeamID = roxo.id
        let feed = [item("me", score: 30, hoursAgo: 1, isMe: true)]
        let rank = LeagueBoard.ranking(feed: feed, league: l, me: "Eu", myAvatar: .egg, since: nil)
        let teams = LeagueBoard.teams(league: l, ranking: rank, feed: feed, remote: MockLeagueBackend.build(l.key))
        XCTAssertEqual(teams.first?.id, roxo.id)
        XCTAssertEqual(teams.first?.score, 30)
        XCTAssertTrue(teams.first?.isMine ?? false)
        XCTAssertEqual(teams.last?.score, 0)
    }

    // MARK: Caixa de saída

    func testDraftRoundTripKeepsRules() {
        let l = league(.sequencia)
        l.code = "ABC123"
        l.photoRule = .metade
        l.attributeWeights = [.forca: 2]
        let joined = League(draft: l.draft)
        XCTAssertEqual(joined.code, "ABC123")
        XCTAssertEqual(joined.tieBreak, .sequencia)
        XCTAssertEqual(joined.photoRule, .metade)
        XCTAssertEqual(joined.attributeWeights, [.forca: 2])
        XCTAssertTrue(joined.joined)
        XCTAssertNil(joined.syncedAt)
    }

    func testOnlyPublishedCheckInsAreRetracted() {
        let leagueID = UUID()
        LeagueOutbox.clear(leagueID)
        let draft = LeagueCheckIn(leagueUUID: leagueID, activityUUID: UUID(), title: "", note: "", date: .now, photo: nil)
        LeagueOutbox.retract(draft)
        XCTAssertNil(LeagueOutbox.retractions[leagueID], "nunca subiu: não precisa sair do servidor")
        let sent = LeagueCheckIn(leagueUUID: leagueID, activityUUID: UUID(), title: "", note: "", date: .now, photo: nil)
        sent.syncedAt = .now
        LeagueOutbox.retract(sent)
        XCTAssertEqual(LeagueOutbox.retractions[leagueID], [sent.uuid])
        LeagueOutbox.clear(leagueID)
    }
}
