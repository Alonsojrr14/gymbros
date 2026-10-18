import CloudKit
import XCTest
@testable import GymBros

/// Dado do Apple Saúde não sobe para o iCloud (guideline 5.1.3): o check-in publicado leva só o que o app calculou
final class HealthPrivacyTests: GymTestCase {
    private func healthRun() -> Activity {
        let a = Activity(kind: .corrida, date: .now, minutes: 42, effort: 7, note: "512 kcal")
        a.healthUUID = UUID().uuidString
        a.healthType = 37
        a.kcal = 512
        a.meters = 8_400
        return a
    }

    private func checkIn(_ a: Activity) -> LeagueCheckIn {
        LeagueCheckIn(leagueUUID: ProfileFeed.id, activityUUID: a.uuid, title: "Corrida", note: "", date: a.date, photo: nil)
    }

    func testHealthActivityPublishesNoHealthValues() {
        let a = healthRun()
        let out = OutgoingCheckIn(checkIn(a), activity: a)
        XCTAssertNil(out.kcal)
        XCTAssertNil(out.meters)
        XCTAssertEqual(out.minutes, 42)
        XCTAssertEqual(out.effort, 5)
        XCTAssertEqual(out.kindRaw, ActivityKind.corrida.rawValue)
    }

    func testAppActivityKeepsChosenEffort() {
        let a = Activity(kind: .corrida, date: .now, minutes: 30, effort: 8)
        XCTAssertEqual(OutgoingCheckIn(checkIn(a), activity: a).effort, 8)
    }

    func testHealthTypeAloneCountsAsHealth() {
        let a = healthRun()
        a.healthUUID = nil
        XCTAssertTrue(a.isFromHealth)
        XCTAssertNil(OutgoingCheckIn(checkIn(a), activity: a).kcal)
    }

    func testAppGPSDistanceIsPublished() {
        let a = Activity(kind: .corrida, date: .now, minutes: 30, effort: 6)
        a.meters = 5_000
        let out = OutgoingCheckIn(checkIn(a), activity: a)
        XCTAssertEqual(out.meters, 5_000)
        XCTAssertNil(out.kcal)
    }

    func testCloudRecordHasNoHealthValues() {
        let a = healthRun()
        let r = CKRecord(cloud: OutgoingCheckIn(checkIn(a), activity: a), league: CloudType.profileFeed, user: "me")
        XCTAssertNil(r["kcal"])
        XCTAssertNil(r["meters"])
        XCTAssertEqual(r["minutes"] as? Int, 42)
        XCTAssertEqual(r["effort"] as? Int, 5)
    }

    func testOwnScoreMatchesWhatOthersReceive() {
        let a = healthRun()
        let out = OutgoingCheckIn(checkIn(a), activity: a)
        let remote = ScoreInput(kind: a.kind, minutes: out.minutes, effort: out.effort, meters: out.meters, kcal: out.kcal)
        for scoring in LeagueScoring.allCases {
            XCTAssertEqual(scoring.score(a.scoreInput), scoring.score(remote), scoring.rawValue)
        }
        XCTAssertEqual(LeagueScoring.distancia.score(a.scoreInput), 0)
    }
}
