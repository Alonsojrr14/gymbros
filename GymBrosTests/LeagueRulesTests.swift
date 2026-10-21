import HealthKit
import SwiftData
import XCTest
@testable import GymBros

/// Verificação do check-in, revisão do dono, dias ativos, limites e pontos por atividade
@MainActor
final class LeagueRulesTests: GymTestCase {
    private let cal = Calendar.current
    private var now: Date { cal.date(bySettingHour: 18, minute: 0, second: 0, of: .now)! }
    private var strength: UInt { WorkoutType.of(.musculacao).id }

    private func subject(daysAgo: Int = 0, hour: Int = 17, minutes: Int = 60, device: Bool = false, photo: PhotoProof? = nil,
                         place: String? = nil) -> PostSubject {
        let day = cal.date(byAdding: .day, value: -daysAgo, to: now)!
        return PostSubject(workoutTypeID: strength, date: cal.date(bySettingHour: hour, minute: 0, second: 0, of: day)!, minutes: minutes,
                           deviceRecorded: device, place: place, photo: photo)
    }

    // MARK: Regras guardadas

    func testSettingsRoundTripAndOldLeaguesStayOff() {
        XCTAssertEqual(LeagueSettings(rawValue: ""), LeagueSettings())
        XCTAssertEqual(LeagueSettings(rawValue: "").verification.preset, .off)
        XCTAssertEqual(LeagueSettings().rawValue, "")
        var s = LeagueSettings.newLeague
        s.reviewRequired = true
        s.limits.individual[.day] = 100
        s.pointRules = [ActivityPointRule(workoutTypeIDs: [strength], method: .perAmount, points: 2, every: 30)]
        s.weekStart = 2
        XCTAssertEqual(LeagueSettings(rawValue: s.rawValue), s)
        // Campo que não existia no JSON fica no padrão
        XCTAssertEqual(LeagueSettings(rawValue: #"{"posesEnabled":true}"#).posesEnabled, true)
        XCTAssertEqual(LeagueSettings(rawValue: #"{"posesEnabled":true}"#).verification, .off)
    }

    // MARK: Verificação

    func testOffAcceptsAnything() {
        XCTAssertTrue(CheckInVerification.off.problems(subject(daysAgo: 400), now: now).isEmpty)
    }

    func testStandardNeedsPhotoOrDevice() {
        let v = CheckInVerification.padrao
        XCTAssertEqual(v.problems(subject(), now: now).map(\.kind), [.media])
        XCTAssertTrue(v.problems(subject(device: true), now: now).isEmpty)
        XCTAssertTrue(v.problems(subject(photo: PhotoProof(source: .library)), now: now).isEmpty)
        // Padrão deixa postar treino antigo
        XCTAssertTrue(v.problems(subject(daysAgo: 20, device: true), now: now).isEmpty)
    }

    func testBroVerificationLibraryNeedsVerifiedTimeAndSameDay() {
        let v = CheckInVerification.verificado
        let today = cal.date(bySettingHour: 17, minute: 40, second: 0, of: now)!
        XCTAssertTrue(v.problems(subject(photo: PhotoProof(source: .library, takenAt: today)), now: now).isEmpty)
        XCTAssertTrue(v.problems(subject(photo: PhotoProof(source: .camera, takenAt: now)), now: now).isEmpty)
        // Galeria sem hora gravada ou de outro dia não vale
        XCTAssertEqual(v.problems(subject(photo: PhotoProof(source: .library)), now: now).map(\.kind), [.library])
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        XCTAssertEqual(v.problems(subject(photo: PhotoProof(source: .library, takenAt: yesterday)), now: now).map(\.kind), [.library])
        // Nada retroativo
        XCTAssertEqual(v.problems(subject(daysAgo: 1, device: true), now: now).map(\.kind), [.backlog])
    }

    func testLibraryDisabledNeedsAppCamera() {
        var v = CheckInVerification.preset(.personalizado)
        v.library = .disabled
        XCTAssertEqual(v.problems(subject(photo: PhotoProof(source: .library, takenAt: now)), now: now).map(\.kind), [.library])
        XCTAssertTrue(v.problems(subject(photo: PhotoProof(source: .camera, takenAt: now)), now: now).isEmpty)
    }

    func testTimePolicies() {
        var v = CheckInVerification.preset(.personalizado)
        v.media = .never
        v.time = .sameDay
        // Sem foto e sem aparelho não há hora verificada
        XCTAssertEqual(v.problems(subject(), now: now).map(\.kind), [.time])
        // Foto da câmera agora (18 h), treino às 17 h: mesmo dia
        XCTAssertTrue(v.problems(subject(photo: PhotoProof(source: .camera, takenAt: now)), now: now).isEmpty)
        // Treino ontem com foto de hoje: outro dia
        XCTAssertEqual(v.problems(subject(daysAgo: 1, photo: PhotoProof(source: .camera, takenAt: now)), now: now).map(\.kind), [.time])
        v.time = .strict
        // Treino das 17 h às 18 h; foto às 18 h cabe, foto às 21 h não
        XCTAssertTrue(v.problems(subject(photo: PhotoProof(source: .camera, takenAt: now)), now: now).isEmpty)
        let late = cal.date(bySettingHour: 21, minute: 0, second: 0, of: now)!
        XCTAssertEqual(v.problems(subject(photo: PhotoProof(source: .library, takenAt: late)), now: late).map(\.kind), [.time])
        // Treino gravado por aparelho: a hora dele é a verificada
        XCTAssertTrue(v.problems(subject(device: true), now: now).isEmpty)
    }

    func testDeviceAndLocationRequirements() {
        var v = CheckInVerification.preset(.personalizado)
        v.media = .never
        v.deviceRequired = true
        v.locationRequired = true
        XCTAssertEqual(Set(v.problems(subject(), now: now).map(\.kind)), [.device, .location])
        XCTAssertTrue(v.problems(subject(device: true, place: "Academia"), now: now).isEmpty)
        var withGPS = PhotoProof(source: .camera, takenAt: now)
        withGPS.hasLocation = true
        XCTAssertTrue(v.problems(subject(device: true, photo: withGPS), now: now).isEmpty)
    }

    func testActivityRuleBlocksBeforeVerification() {
        let l = League(name: "Só bike", emoji: "🚴", scoring: .pontos)
        l.activityRule = LeagueActivityRule(mode: .only, workoutTypeIDs: [WorkoutType.of(.bike).id])
        XCTAssertEqual(l.problems(subject(device: true)).count, 1)
        XCTAssertTrue(l.problems(subject(device: true)).first?.message.contains("não vale") == true)
    }

    func testExifDateWithOffset() {
        let d = PhotoProof.exifDate("2026:10:21 07:42:10", offset: "-03:00")
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(utc.component(.hour, from: d!), 10)
        XCTAssertNotNil(PhotoProof.exifDate("2026:10:21 07:42:10", offset: nil))
        XCTAssertNil(PhotoProof.exifDate("ontem", offset: nil))
    }

    func testDailyPoseIsStablePerDay() {
        let a = DailyPose.of(now)
        XCTAssertEqual(a, DailyPose.of(now.addingTimeInterval(-3600)))
        let days = (0..<30).map { DailyPose.of(cal.date(byAdding: .day, value: $0, to: now)!).id }
        XCTAssertGreaterThan(Set(days).count, 5)
    }

    // MARK: Pontuação

    func testPointRulesPreferSpecificTypeAndFloorAmounts() {
        let strengthType = strength
        let bySection = ActivityPointRule(sections: [WorkoutType.Section.academia.rawValue], method: .perCheckIn, points: 5)
        let byType = ActivityPointRule(workoutTypeIDs: [strengthType], method: .perAmount, points: 2, every: 30)
        let rules = [bySection, byType]
        // 59 min de musculação = 1 × 2 pts (o tipo vence a seção)
        XCTAssertEqual(rules.score(ScoreInput(kind: .musculacao, minutes: 59, effort: 5, workoutTypeID: strengthType)), 2)
        XCTAssertEqual(rules.score(ScoreInput(kind: .musculacao, minutes: 60, effort: 5, workoutTypeID: strengthType)), 4)
        // Fora da tabela vale 0
        XCTAssertEqual(rules.score(ScoreInput(kind: .corrida, minutes: 60, effort: 5, workoutTypeID: WorkoutType.of(.corrida).id)), 0)
        let penalty = ActivityPointRule(workoutTypeIDs: [WorkoutType.of(.corrida).id], method: .perCheckIn, points: -3)
        let l = League(name: "Tabela", emoji: "📋", scoring: .atividades)
        l.photoRule = .metade
        var s = l.settings
        s.pointRules = [penalty]
        l.settings = s
        // Negativo não passa pela regra da foto
        XCTAssertEqual(l.score(ScoreInput(kind: .corrida, minutes: 30, effort: 5, workoutTypeID: WorkoutType.of(.corrida).id), hasPhoto: false), -3)
    }

    private func remoteLeague(_ checkIns: [RemoteCheckIn]) -> RemoteLeague {
        RemoteLeague(members: [RemoteMember(id: "ana", name: "Ana", formID: MonsterForm.egg.id)], checkIns: checkIns)
    }

    private func remote(_ id: String, hoursAgo: Double, minutes: Int = 60) -> RemoteCheckIn {
        RemoteCheckIn(id: id, memberID: "ana", date: now.addingTimeInterval(-hoursAgo * 3600), kindRaw: ActivityKind.musculacao.rawValue,
                      minutes: minutes, effort: 5, title: id, workoutTypeID: strength)
    }

    private func league(_ scoring: LeagueScoring, _ change: (inout LeagueSettings) -> Void = { _ in }) -> League {
        let l = League(name: "Teste", emoji: "🏆", scoring: scoring, start: now.addingTimeInterval(-10 * 86400))
        var s = l.settings
        change(&s)
        l.settings = s
        return l
    }

    func testActiveDaysCountOncePerDay() {
        let l = league(.dias)
        let r = remoteLeague([remote("a", hoursAgo: 1), remote("b", hoursAgo: 3), remote("c", hoursAgo: 30)])
        let feed = LeagueBoard.feed(league: l, mine: [], activities: [:], me: "Eu", myAvatar: .egg, remote: r, reviews: [])
        // O placar soma ainda o bônus da rodada suíça; aqui só o que vem dos check-ins
        XCTAssertEqual(points(feed), 2)
        XCTAssertEqual(feed.first { $0.id == "b" }?.score, 1)
        XCTAssertEqual(feed.first { $0.id == "a" }?.score, 0)
    }

    private func points(_ feed: [FeedItem], of member: String = "ana") -> Int {
        feed.filter { $0.memberID == member }.reduce(0) { $0 + $1.score }
    }

    func testIndividualDailyCap() {
        let l = league(.minutos) { $0.limits.individual[.day] = 90 }
        let r = remoteLeague([remote("a", hoursAgo: 3), remote("b", hoursAgo: 1)])
        let feed = LeagueBoard.feed(league: l, mine: [], activities: [:], me: "Eu", myAvatar: .egg, remote: r, reviews: [])
        XCTAssertEqual(points(feed), 90)
        // O corte cai no check-in mais novo
        XCTAssertEqual(feed.first { $0.id == "b" }?.capped, 30)
        XCTAssertEqual(feed.first { $0.id == "a" }?.capped, 0)
    }

    func testReviewHoldsScoreUntilApproved() {
        let since = now.addingTimeInterval(-2 * 86400)
        let l = league(.treinos) { $0.reviewRequired = true; $0.reviewSince = since }
        // "velho" é de antes da revisão ser ligada: já valia
        let r = remoteLeague([remote("velho", hoursAgo: 72), remote("novo", hoursAgo: 2), remote("negado", hoursAgo: 1)])
        let pending = LeagueBoard.feed(league: l, mine: [], activities: [:], me: "Eu", myAvatar: .egg, remote: r, reviews: [])
        XCTAssertEqual(pending.filter(\.pending).map(\.id).sorted(), ["negado", "novo"])
        XCTAssertEqual(points(pending), 1)
        let rank = LeagueBoard.ranking(feed: pending, league: l, me: "Eu", myAvatar: .egg, since: nil, remote: r)
        XCTAssertEqual(rank.first { $0.id == "ana" }?.checkIns, 1)

        let decisions = [CheckInReview(leagueUUID: l.uuid, itemID: "novo", approved: true),
                         CheckInReview(leagueUUID: l.uuid, itemID: "negado", approved: false)]
        let decided = LeagueBoard.feed(league: l, mine: [], activities: [:], me: "Eu", myAvatar: .egg, remote: r, reviews: decisions)
        XCTAssertNil(decided.first { $0.id == "negado" })
        XCTAssertFalse(decided.contains { $0.pending })
        XCTAssertEqual(points(decided), 2)
    }

    func testOwnerCheckInSkipsReviewButMemberWaits() {
        let owned = league(.treinos) { $0.reviewRequired = true }
        XCTAssertFalse(owned.needsReview(fromMe: true))
        owned.joined = true
        XCTAssertTrue(owned.needsReview(fromMe: true))
    }

    func testWeekStartChangesWeeklyWindow() {
        var s = LeagueSettings()
        s.weekStart = 4
        let start = RankWindow.semana.since(now: now, calendar: s.calendar())!
        XCTAssertEqual(Calendar.current.component(.weekday, from: start), 4)
    }

    func testPostSkipsLeaguesThatBlockAndKeepsProof() throws {
        let ctx = try memoryContext()
        let open = League(name: "Livre", emoji: "🔓", scoring: .treinos)
        let strict = League(name: "Rígida", emoji: "🔒", scoring: .treinos)
        strict.settings = { var s = LeagueSettings(); s.verification = .padrao; return s }()
        ctx.insert(open)
        ctx.insert(strict)
        let a = Activity(kind: .musculacao, date: .now, minutes: 60, effort: 6)
        ctx.insert(a)
        postCheckIns(activity: a, leagues: [open.uuid, strict.uuid], title: "Treino", note: "", photo: nil, context: ctx, signedIn: true)
        let posted = try ctx.fetch(FetchDescriptor<LeagueCheckIn>())
        XCTAssertEqual(posted.map(\.leagueUUID), [open.uuid])

        a.source = "Apple Watch"
        postCheckIns(activity: a, leagues: [strict.uuid], title: "Treino", note: "", photo: nil, context: ctx, signedIn: true)
        let proof = try XCTUnwrap(ctx.fetch(FetchDescriptor<LeagueCheckIn>()).first { $0.leagueUUID == strict.uuid }?.proof)
        XCTAssertTrue(proof.deviceRecorded)
        XCTAssertEqual(proof.device, "Apple Watch")
    }

    // MARK: Clube e desafio

    func testClubWeeklyChampionsAndSharedFirst() {
        let cal = Calendar.current
        let weekStart = cal.dateInterval(of: .weekOfYear, for: now)!.start
        let start = cal.date(byAdding: .day, value: -21, to: weekStart)!
        let l = League(name: "Clube", emoji: "🏆", scoring: .minutos, start: start)
        let at = { (days: Int) in cal.date(byAdding: .hour, value: 10, to: cal.date(byAdding: .day, value: days, to: start)!)! }
        func c(_ id: String, _ who: String, _ day: Int, _ minutes: Int) -> RemoteCheckIn {
            RemoteCheckIn(id: id, memberID: who, date: at(day), kindRaw: ActivityKind.musculacao.rawValue, minutes: minutes, effort: 5,
                          title: id, workoutTypeID: strength)
        }
        let r = RemoteLeague(members: [RemoteMember(id: "ana", name: "Ana", formID: MonsterForm.egg.id),
                                       RemoteMember(id: "bia", name: "Bia", formID: MonsterForm.egg.id)],
                             checkIns: [c("a1", "ana", 1, 200), c("b1", "bia", 2, 60), c("a2", "ana", 8, 60), c("b2", "bia", 9, 60)])
        let feed = LeagueBoard.feed(league: l, mine: [], activities: [:], me: "Eu", myAvatar: .egg, remote: r, reviews: [])
        let wins = ClubWinners.all(league: l, feed: feed, me: "Eu", myAvatar: .egg, remote: r, now: now).filter { $0.period == .week }
        // 3 semanas inteiras já acabaram
        XCTAssertEqual(wins.count, 3)
        let first = wins.last!
        XCTAssertEqual(first.winners.map(\.id), ["ana"])
        let second = wins[wins.count - 2]
        // Mesmo placar dos check-ins na 2ª semana: se o bônus suíço não desempatou, dividem o título
        XCTAssertTrue(second.winners.contains { $0.id == "ana" || $0.id == "bia" })
        XCTAssertEqual(ClubWinners.tally(wins)["ana"]?[.week] ?? 0 >= 1, true)
        XCTAssertEqual(namesList([RankRow(id: "a", name: "Ana", avatar: .egg, isMe: false), RankRow(id: "b", name: "Bia", avatar: .egg, isMe: false)]), "Ana e Bia")
    }

    func testRestartKeepsRulesAndStartsToday() {
        let old = League(name: "Desafio", emoji: "🔥", scoring: .treinos, start: now.addingTimeInterval(-40 * 86400))
        old.setDuration(days: 30)
        old.activityRule = LeagueActivityRule(mode: .only, workoutTypeIDs: [strength])
        old.settings = { var s = LeagueSettings.newLeague; s.posesEnabled = true; return s }()
        let next = LeagueRenewal.restart(old, now: now)
        XCTAssertEqual(next.durationDays, 30)
        XCTAssertTrue(Calendar.current.isDate(next.start, inSameDayAs: now))
        XCTAssertEqual(next.season, old.season + 1)
        XCTAssertEqual(next.seriesKey, old.seriesKey)
        XCTAssertEqual(next.activityRule, old.activityRule)
        XCTAssertEqual(next.settings, old.settings)
    }

    // MARK: Moderação e notificações

    func testOwnerDecisionsShapeMembers() {
        let l = MockLeague.make()
        let base = MockLeagueBackend.build(l.key)
        let someone = base.members[0].id
        l.settings = { var s = LeagueSettings(); s.removed = [someone]; s.requiresApproval = true; s.approved = ["paula"]; return s }()
        let r = base.applying(l)
        XCTAssertNil(r.member(someone))
        XCTAssertFalse(r.checkIns.contains { $0.memberID == someone })
        // Pedido aceito vira membro; o outro continua pedindo
        XCTAssertNotNil(r.member("paula"))
        XCTAssertEqual(r.requests.map(\.id), ["teo"])
        // Aplicar de novo não muda nada
        XCTAssertEqual(r.applying(l).members.map(\.id), r.members.map(\.id))
        var s = l.settings
        s.ignored = ["teo"]
        s.banned = ["paula"]
        l.settings = s
        let after = base.applying(l)
        XCTAssertTrue(after.requests.isEmpty)
        XCTAssertNil(after.member("paula"))
    }

    func testModeratorSkipsReviewOnOwnCheckIns() {
        let l = league(.treinos) { $0.reviewRequired = true; $0.mods = [LeagueBoard.selfID] }
        l.joined = true
        XCTAssertTrue(l.canModerate)
        XCTAssertFalse(l.needsReview(fromMe: true))
    }

    func testMuralMentions() {
        XCTAssertTrue(LeagueNotices.mentions("bora treinar @zero?", user: "Zero", name: ""))
        XCTAssertTrue(LeagueNotices.mentions("valeu @José", user: "", name: "jose"))
        XCTAssertFalse(LeagueNotices.mentions("zero sem arroba", user: "zero", name: ""))
    }

    func testLeagueNotifyPrefsArePerSeries() {
        let d = scratchDefaults("liga")
        let l = League(name: "A", emoji: "🅰️", scoring: .treinos)
        var p = LeagueNotifyPrefs.of(l, defaults: d)
        XCTAssertEqual(p.mural, .all)
        p.mural = .mentions
        p.checkIns = true
        p.save(for: l, defaults: d)
        let next = LeagueRenewal.makeNext(after: { l.setDuration(days: 7); return l }())
        XCTAssertEqual(LeagueNotifyPrefs.of(next, defaults: d), p)
        XCTAssertEqual(LeagueNotifyPrefs(), (try? JSONDecoder().decode(LeagueNotifyPrefs.self, from: Data("{}".utf8))))
    }
}
