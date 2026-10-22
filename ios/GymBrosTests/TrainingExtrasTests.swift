import SwiftData
import XCTest
@testable import GymBros

/// Distância × tempo e check-in com várias atividades do mesmo dia
@MainActor
final class TrainingExtrasTests: GymTestCase {
    func testRowerIsDistanceAndKeepsDistanceAimingFaster() {
        XCTAssertEqual(Exercise.byID("remo-ergometro")?.type, .distance)
        let last = SessionLog(date: .now.addingTimeInterval(-86400), sets: [
            SetLog(exerciseID: "remo-ergometro", weight: 2000, reps: 480, target: 480, done: true),
            SetLog(exerciseID: "remo-ergometro", weight: 2000, reps: 465, target: 480, done: true),
        ])
        let s = Progression.suggest(exerciseID: "remo-ergometro", sets: 2, reps: 480, history: [last])
        XCTAssertEqual(s.weight, 2000)
        XCTAssertEqual(s.reps, 465)
        XCTAssertTrue(s.reason.contains("baixar"))
    }

    func testDistanceSetsStayOutOfVolumeAndShowMeters() throws {
        let ctx = try memoryContext()
        let session = WorkoutSession(title: "Treino", routineUUID: nil)
        ctx.insert(session)
        let row = LoggedSet(exerciseID: "remo-ergometro", exerciseOrder: 0, index: 0, weight: 1500, reps: 400, rest: 60)
        row.done = true
        let bench = LoggedSet(exerciseID: "supino-reto", exerciseOrder: 1, index: 0, weight: 60, reps: 10, rest: 90)
        bench.done = true
        session.sets = [row, bench]
        XCTAssertEqual(session.volume, 600)
        XCTAssertEqual(setText(row), "1.500 m em 6:40")
        XCTAssertEqual(meters(10_000), "10 km")
    }

    func testDistanceRecordIsLongestDistance() {
        let before = SessionLog(date: .now.addingTimeInterval(-86400), sets: [SetLog(exerciseID: "remo-ergometro", weight: 1000, reps: 240, target: 240, done: true)])
        let now = SessionLog(date: .now, sets: [SetLog(exerciseID: "remo-ergometro", weight: 2000, reps: 500, target: 240, done: true)])
        XCTAssertEqual(Progression.records(in: now, history: [before]).first, "Remo ergômetro: maior distância, 2.000 m")
    }

    func testGroupedCheckInScoresAllActivities() throws {
        let ctx = try memoryContext()
        let l = League(name: "Minutos", emoji: "⏱️", scoring: .minutos)
        ctx.insert(l)
        let run = Activity(kind: .corrida, date: .now, minutes: 30, effort: 6)
        let gym = Activity(kind: .musculacao, date: .now.addingTimeInterval(-3600), minutes: 50, effort: 6)
        let old = Activity(kind: .yoga, date: .now.addingTimeInterval(-3 * 86400), minutes: 40, effort: 4)
        [run, gym, old].forEach(ctx.insert)
        postCheckIns(activity: run, leagues: [l.uuid], title: "Dia cheio", note: "", photo: nil, context: ctx, signedIn: true, grouped: [gym, old])
        let c = try XCTUnwrap(ctx.fetch(FetchDescriptor<LeagueCheckIn>()).first)
        // Só a do mesmo dia entra junto
        XCTAssertEqual(c.proof.grouped, [gym.uuid])
        XCTAssertEqual(c.proof.groupedParts.count, 1)
        let acts = Dictionary(uniqueKeysWithValues: [run, gym, old].map { ($0.uuid, $0) })
        let feed = LeagueBoard.feed(league: l, mine: [c], activities: acts, me: "Eu", myAvatar: .egg, remote: .empty, reviews: [])
        XCTAssertEqual(feed.first?.score, 80)
        XCTAssertEqual(feed.first?.minutes, 80)
        // Os outros aparelhos pontuam pelas partes que sobem junto
        let remote = RemoteCheckIn(id: "x", memberID: "ana", date: .now, kindRaw: run.kindRaw, minutes: 30, effort: 6, title: "",
                                   proof: c.proof)
        let r = RemoteLeague(members: [RemoteMember(id: "ana", name: "Ana", formID: MonsterForm.egg.id)], checkIns: [remote])
        XCTAssertEqual(LeagueBoard.feed(league: l, mine: [], activities: [:], me: "Eu", myAvatar: .egg, remote: r, reviews: []).first?.score, 80)
    }
}
