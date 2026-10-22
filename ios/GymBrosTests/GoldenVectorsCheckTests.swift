import XCTest
@testable import GymBros

/// Os vetores compartilhados com o Android (`Fixtures/gymbros-golden-*.json`) continuam valendo para o iOS:
/// se uma regra mudar aqui, este teste falha e os vetores têm de ser gerados de novo (GoldenVectorsTests) e o Android acompanhar.
final class GoldenVectorsCheckTests: GymTestCase {
    private func load(_ group: String) throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "gymbros-golden-\(group)", withExtension: "json"),
                                "vetor \(group) fora do bundle de teste")
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func double(_ s: Any?) -> Double { Double(bitPattern: UInt64(s as! String)!) }

    private func date(_ s: Any?) -> Date { ISO8601DateFormatter().date(from: s as! String)! }

    func testGroupAStillHolds() throws {
        let a = try load("A")
        for c in a["xp"] as! [[String: Any]] {
            XCTAssertEqual(Game.xp(kind: ActivityKind(rawValue: c["kind"] as! String)!, minutes: c["minutes"] as! Int, effort: c["effort"] as! Int),
                           c["xp"] as! Int, "\(c)")
        }
        for c in a["random"] as! [[String: Any]] {
            var r = SeededRandom(seed: c["seed"] as! String)
            XCTAssertEqual((c["next"] as! [String]).map { _ in r.next().bitPattern }, (c["next"] as! [String]).map { UInt64($0)! })
        }
        for c in a["pair"] as! [[String: Any]] {
            let out = Swiss.pair(ranked: c["ranked"] as! [String], met: c["met"] as! [String: [String: Int]], byes: c["byes"] as! [String: Int])
            XCTAssertEqual(out.pairs.map { [$0.0, $0.1] }, c["pairs"] as! [[String]])
            XCTAssertEqual(out.bye, c["bye"] as? String)
        }
        for c in a["photo"] as! [[String: Any]] {
            XCTAssertEqual(PhotoRule(rawValue: c["rule"] as! String)!.apply(c["score"] as! Int, hasPhoto: c["hasPhoto"] as! Bool), c["out"] as! Int)
        }
    }

    func testGroupLStillHolds() throws {
        let l = try load("L")
        XCTAssertEqual((l["catalog"] as! [[String: Any]]).map { $0["id"] as! Int }, WorkoutType.all.map { Int($0.id) })
        for c in l["score"] as! [[String: Any]] {
            let league = League(name: "L", emoji: "🏆", scoring: LeagueScoring(rawValue: c["scoring"] as! String)!)
            league.weightsRaw = c["weightsRaw"] as! String
            league.activityRule = LeagueActivityRule(rawValue: c["activityRule"] as! String)
            league.photoRule = PhotoRule(rawValue: c["photoRule"] as! String)!
            var settings = league.settings
            settings.pointRules = (c["pointRules"] as! [[String: Any]]).map { r in
                var rule = ActivityPointRule()
                rule.workoutTypeIDs = (r["workoutTypeIDs"] as! [Int]).map { UInt($0) }
                rule.sections = r["sections"] as! [String]
                rule.method = ActivityPointRule.Method(rawValue: r["method"] as! String)!
                rule.points = r["points"] as! Int
                rule.every = r["every"] as! Int
                rule.metric = ActivityPointRule.Metric(rawValue: r["metric"] as! String)!
                return rule
            }
            league.settings = settings
            let i = c["input"] as! [String: Any]
            let input = ScoreInput(kind: ActivityKind(rawValue: i["kind"] as! String)!, minutes: i["minutes"] as! Int, effort: i["effort"] as! Int,
                                   meters: (i["meters"] as? String).map(double), kcal: (i["kcal"] as? String).map(double),
                                   workoutTypeID: (i["workoutTypeID"] as? Int).map { UInt($0) })
            let got = league.score(input, hasPhoto: c["hasPhoto"] as! Bool), want = c["score"] as! Int
            // ND-9: no modo pontos com pesos a soma segue a ordem de um Dictionary (pode dar 1 de diferença entre execuções)
            XCTAssertLessThanOrEqual(abs(got - want), league.weightsRaw.isEmpty ? 0 : 1, "\(c)")
        }
    }

    func testGroupBStillHolds() throws {
        let b = try load("B")
        let cal = League.rulesCalendar
        XCTAssertEqual(b["timeZone"] as? String, cal.timeZone.identifier)
        for c in b["snapshot"] as! [[String: Any]] {
            let records = (c["records"] as! [[String: Any]]).map { r -> ActivityRecord in
                var rec = ActivityRecord(id: UUID(uuidString: r["id"] as! String)!, kind: ActivityKind(rawValue: r["kind"] as! String)!,
                                         date: date(r["date"]), minutes: r["minutes"] as! Int, effort: r["effort"] as! Int)
                rec.share = double(r["share"])
                rec.weights = (r["weights"] as? [String: String]).map { w in
                    Dictionary(uniqueKeysWithValues: w.map { (Attribute(rawValue: $0.key)!, double($0.value)) })
                }
                return rec
            }
            let s = Game.snapshot(records, now: date(c["now"]), calendar: cal)
            XCTAssertEqual(s.totalXP, c["totalXP"] as! Int)
            XCTAssertEqual(s.todayXP, c["todayXP"] as! Int)
            XCTAssertEqual(s.streak, c["streak"] as! Int)
            XCTAssertEqual(s.bestStreak, c["bestStreak"] as! Int)
            XCTAssertEqual(s.form.key, c["form"] as! String)
            XCTAssertEqual(s.evolutions.map(\.form.key), c["evolutions"] as! [String])
            XCTAssertEqual(records.map { s.xpByActivity[$0.id] ?? 0 }, c["xpByActivity"] as! [Int])
        }
        for c in b["swissTable"] as! [[String: Any]] {
            let start = date(c["start"])
            var tallies: [Date: [String: SwissTally]] = [:]
            var day = cal.startOfDay(for: start)
            let byStamp = c["tallies"] as! [String: [String: [Int]]]
            let now = date(c["now"])
            while day <= now {
                if let t = byStamp[Swiss.dayStamp(day, calendar: cal)] {
                    tallies[day] = t.mapValues { SwissTally(score: $0[0], checkIns: $0[1]) }
                }
                day = cal.date(byAdding: .day, value: 1, to: day)!
            }
            let t = Swiss.table(members: c["members"] as! [String], tallies: tallies, start: start, end: nil, now: now,
                                seed: c["seed"] as! String, criterion: SwissCriterion(rawValue: c["criterion"] as! String)!,
                                identity: [:], joined: (c["joined"] as! [String: String]).mapValues { date($0) }, calendar: cal)
            let rounds = c["rounds"] as! [[String: Any]]
            XCTAssertEqual(t.rounds.count, rounds.count)
            for (r, e) in zip(t.rounds, rounds) {
                XCTAssertEqual(Swiss.dayStamp(r.day, calendar: cal), e["day"] as! String)
                XCTAssertEqual(r.matches.map { [$0.a, $0.b ?? "-"] }, (e["matches"] as! [[Any]]).map { [$0[0] as! String, $0[1] as? String ?? "-"] })
            }
        }
    }
}
