import SwiftData
import XCTest
@testable import GymBros

/// Fotos a mais, rotinas públicas, ranking dos bros, feed unificado, visita verificada, "Você diz" e treino do dia
@MainActor
final class NowFeaturesTests: GymTestCase {
    func testExtraPhotosRoundTrip() throws {
        let ctx = try memoryContext()
        let c = LeagueCheckIn(leagueUUID: UUID(), activityUUID: UUID(), title: "", note: "", date: .now, photo: nil)
        ctx.insert(c)
        c.photos = [Data([1]), Data([2]), Data([3]), Data([4]), Data([5]), Data([6])]
        // Até 5 no total: a principal e 4 a mais
        XCTAssertEqual(c.photos.count, 5)
        XCTAssertEqual(c.photo, Data([1]))
        XCTAssertTrue(c.hasPhoto)
        c.photos = [Data([9])]
        XCTAssertNil(c.extraPhotosData)
        XCTAssertEqual(c.photos, [Data([9])])
    }

    func testPostKeepsExtraPhotos() throws {
        let ctx = try memoryContext()
        let a = Activity(kind: .musculacao, date: .now, minutes: 60, effort: 6)
        ctx.insert(a)
        postCheckIns(activity: a, leagues: [ProfileFeed.id], title: "Treino", note: "", photo: Data([1]), context: ctx, signedIn: true,
                     extraPhotos: [Data([2]), Data([3])])
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<LeagueCheckIn>()).first?.photos.count, 3)
    }

    func testPublicRoutinesSortAndSaveCopy() async throws {
        let before = UserDefaults.standard.dictionary(forKey: MockRoutinesBackend.savedKey)
        defer { UserDefaults.standard.set(before, forKey: MockRoutinesBackend.savedKey) }
        let store = PublicRoutinesStore()
        await store.refresh()
        XCTAssertFalse(store.all.isEmpty)
        let bySaves = store.sorted(.saved, friends: [])
        XCTAssertEqual(bySaves.map(\.saves), bySaves.map(\.saves).sorted(by: >))
        let friend = try XCTUnwrap(store.all.first?.authorID)
        XCTAssertTrue(store.sorted(.friends, friends: [friend]).allSatisfy { $0.authorID == friend })
        let ctx = try memoryContext()
        let r = try XCTUnwrap(store.all.first)
        await store.saveCopy(r, context: ctx, order: 0)
        let saved = try XCTUnwrap(ctx.fetch(FetchDescriptor<Routine>()).first)
        XCTAssertEqual(saved.name, r.name)
        XCTAssertEqual(saved.items.count, r.items.count)
        XCTAssertEqual(store.all.first { $0.id == r.id }?.saves, r.saves + 1)
    }

    func testFriendsRankingByMetric() {
        let now = Date.now
        func item(_ who: String, _ minutes: Int, hoursAgo: Double) -> FeedItem {
            FeedItem(id: UUID().uuidString, memberID: who, name: who, avatar: .egg, isMe: who == "me", date: now.addingTimeInterval(-hoursAgo * 3600),
                     title: "", note: "", kind: .corrida, minutes: minutes, score: minutes)
        }
        let rows = FriendsRanking.rank(me: [item("me", 30, hoursAgo: 1)], friends: [item("ana", 20, hoursAgo: 1), item("ana", 20, hoursAgo: 2)],
                                       people: [("ana", "Ana", .egg)], myName: "Eu", myAvatar: .egg, metric: .checkIns, since: nil)
        XCTAssertEqual(rows.first?.id, "ana")
        let byMinutes = FriendsRanking.rank(me: [item("me", 50, hoursAgo: 1)], friends: [item("ana", 20, hoursAgo: 1)],
                                            people: [("ana", "Ana", .egg)], myName: "Eu", myAvatar: .egg, metric: .minutes, since: nil)
        XCTAssertEqual(byMinutes.first?.id, "me")
    }

    func testUnifiedFeedMergesSamePostInManyLeagues() throws {
        let ctx = try memoryContext()
        let a = Activity(kind: .musculacao, date: .now, minutes: 60, effort: 6)
        ctx.insert(a)
        let l1 = League(name: "Um", emoji: "1️⃣", scoring: .treinos, start: .now.addingTimeInterval(-86400))
        let l2 = League(name: "Dois", emoji: "2️⃣", scoring: .treinos, start: .now.addingTimeInterval(-86400))
        [l1, l2].forEach(ctx.insert)
        postCheckIns(activity: a, leagues: [l1.uuid, l2.uuid], title: "Peito", note: "", photo: nil, context: ctx, signedIn: true)
        let checkIns = try ctx.fetch(FetchDescriptor<LeagueCheckIn>())
        let feed = UnifiedFeed.build(leagues: [l1, l2], checkIns: checkIns, activities: [a], me: "Eu", friends: [])
        let mine = feed.filter(\.item.isMe)
        XCTAssertEqual(mine.count, 1)
        XCTAssertEqual(mine.first?.places.count, 2)
        XCTAssertEqual(mine.first?.leagueIDs, [l1.uuid, l2.uuid])
    }

    func testVerifiedGymVisitCountsAsProof() {
        let v = CheckInVerification.padrao
        var s = PostSubject(workoutTypeID: WorkoutType.of(.musculacao).id, date: .now.addingTimeInterval(-3600), minutes: 60)
        XCTAssertEqual(v.problems(s).map(\.kind), [.media])
        s.gymVisit = "Academia"
        XCTAssertTrue(v.problems(s).isEmpty)
        XCTAssertTrue(s.hasLocation)
        var strict = CheckInVerification.preset(.personalizado)
        strict.media = .never
        strict.time = .sameDay
        XCTAssertTrue(strict.problems(s).isEmpty)
    }

    func testDailyWorkoutBecomesRoutineAndClubChallengeInherits() {
        let w = DailyWorkout(day: .now, title: "Perna", items: [.init(exerciseID: "agachamento", sets: 4, reps: 8)])
        XCTAssertTrue(w.isToday)
        XCTAssertEqual(w.routine.items.first?.sets, 4)
        var s = LeagueSettings()
        s.dailyWorkout = w
        s.parentClub = UUID()
        XCTAssertEqual(LeagueSettings(rawValue: s.rawValue), s)
    }

    func testWhatsNewOncePerVersion() {
        let before = UserDefaults.standard.string(forKey: WhatsNew.seenKey)
        defer { UserDefaults.standard.set(before, forKey: WhatsNew.seenKey) }
        UserDefaults.standard.removeObject(forKey: WhatsNew.seenKey)
        XCTAssertTrue(WhatsNew.shouldShow)
        WhatsNew.markSeen()
        XCTAssertFalse(WhatsNew.shouldShow)
    }
}
