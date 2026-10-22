import SwiftData
import XCTest
@testable import GymBros

/// Gera os vetores de teste compartilhados com o app Android (engenharia/plano/estrategia-testes.md §6).
/// Só roda com `TEST_RUNNER_GYMBROS_GOLDEN=1 xcodebuild test …`: os JSON saem como anexos do resultado e vão para
/// `GymBrosTests/Fixtures/`. Os números são os do Swift de hoje; o Android tem de chegar aos mesmos, bit a bit.
/// Banco em memória e UserDefaults de teste: nada do aparelho é lido nem gravado.
final class GoldenVectorsTests: GymTestCase {
    private let cal = League.rulesCalendar

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(ProcessInfo.processInfo.environment["GYMBROS_GOLDEN"] == "1", "gerador desligado")
    }

    private func attach(_ name: String, _ object: Any) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        let a = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        a.name = "gymbros-golden-\(name).json"
        a.lifetime = .keepAlways
        add(a)
    }

    /// Double exato: o padrão de bits em decimal (o Android compara `toRawBits()`)
    private func bits(_ d: Double) -> String { String(d.bitPattern) }

    private func iso(_ d: Date) -> String { ISO8601DateFormatter().string(from: d) }

    private func stamp(_ d: Date) -> String { Swiss.dayStamp(d, calendar: cal) }

    // MARK: Grupo A

    func testGroupA() throws {
        var xp: [[String: Any]] = []
        for kind in ActivityKind.allCases {
            for minutes in [-5, 0, 1, 5, 29, 30, 45, 60, 61, 90, 239, 240, 241, 600] {
                for effort in [0, 1, 3, 5, 6, 7, 10, 11] {
                    xp.append(["kind": kind.rawValue, "minutes": minutes, "effort": effort,
                               "xp": Game.xp(kind: kind, minutes: minutes, effort: effort)])
                }
            }
        }
        var random: [[String: Any]] = []
        for seed in ["", "LIGA01", "pose-2026-10-22", "uidA-LIGA01-2026-1-5", "çãé-ü-🏋️", UUID(uuidString: "6F9619FF-8B86-D011-B42D-00CF4FC964FF")!.uuidString] {
            var r = SeededRandom(seed: seed)
            random.append(["seed": seed, "next": (0..<8).map { _ in bits(r.next()) }])
        }
        var pair: [[String: Any]] = []
        for n in 2...11 {
            for k in 0..<6 {
                var r = SeededRandom(seed: "pair-\(n)-\(k)")
                let ranked = (0..<n).map { "p\($0)" }
                var met: [String: [String: Int]] = [:]
                for i in 0..<n { for j in (i + 1)..<max(n, i + 1) where r.next() < 0.45 {
                    let c = Int(r.next() * 3) + 1
                    met[ranked[i], default: [:]][ranked[j]] = c
                    met[ranked[j], default: [:]][ranked[i]] = c
                } }
                var byes: [String: Int] = [:]
                for p in ranked where r.next() < 0.3 { byes[p] = Int(r.next() * 3) + 1 }
                let out = Swiss.pair(ranked: ranked, met: met, byes: byes)
                pair.append(["ranked": ranked, "met": met, "byes": byes,
                             "pairs": out.pairs.map { [$0.0, $0.1] }, "bye": out.bye as Any? ?? NSNull()])
            }
        }
        var photo: [[String: Any]] = []
        for rule in PhotoRule.allCases { for score in [0, 1, 2, 3, 29, 30, 301] { for has in [true, false] {
            photo.append(["rule": rule.rawValue, "score": score, "hasPhoto": has, "out": rule.apply(score, hasPhoto: has)])
        } } }
        try attach("A", ["version": 1, "xp": xp, "random": random, "pair": pair, "photo": photo])
    }

    // MARK: Grupo L (ligas: pontos de um check-in)

    func testGroupL() throws {
        let catalog = WorkoutType.all.map { ["id": Int($0.id) as Int, "name": $0.name, "section": $0.section.rawValue, "kind": $0.kind.rawValue] as [String: Any] }
        var kcal: [[String: Any]] = []
        for kind in ActivityKind.allCases { for minutes in [0, 1, 30, 60, 241, 600] { for effort in [-1, 0, 1, 5, 10, 12] {
            kcal.append(["kind": kind.rawValue, "minutes": minutes, "effort": effort,
                         "kcal": bits(HealthSync.activeKcal(kind: kind, minutes: minutes, effort: effort, weight: LeagueScoring.referenceWeight))])
        } } }
        let ids = WorkoutType.all.map(\.id)
        let sections = WorkoutType.Section.allCases.map(\.rawValue)
        var cases: [[String: Any]] = []
        var r = SeededRandom(seed: "league-score")
        func pick<T>(_ list: [T]) -> T { list[Int(r.next() * Double(list.count))] }
        for _ in 0..<600 {
            let league = League(name: "L", emoji: "🏆", scoring: pick(LeagueScoring.allCases))
            var weights: [String: String] = [:]
            if r.next() < 0.5 { for a in Attribute.allCases where r.next() < 0.5 { weights[a.rawValue] = bits(pick([0.0, 0.5, 1.5, 2.0, 3.0])) } }
            league.attributeWeights = Dictionary(uniqueKeysWithValues: weights.map { (Attribute(rawValue: $0.key)!, Double(bitPattern: UInt64($0.value)!)) })
            let mode = pick(LeagueActivityRuleMode.allCases)
            let ruleIDs = Set((0..<Int(r.next() * 4)).map { _ in pick(ids) })
            league.activityRule = LeagueActivityRule(mode: mode, workoutTypeIDs: ruleIDs)
            league.photoRule = pick(PhotoRule.allCases)
            var settings = league.settings
            settings.pointRules = (0..<Int(r.next() * 4)).map { _ in
                var rule = ActivityPointRule()
                if r.next() < 0.5 { rule.workoutTypeIDs = [pick(ids)] } else { rule.sections = [pick(sections)] }
                rule.method = pick([.perCheckIn, .perAmount])
                rule.points = pick([-5, 1, 2, 10])
                rule.every = pick([0, 1, 5, 30])
                rule.metric = pick([.minutes, .km, .kcal])
                return rule
            }
            league.settings = settings
            let kind = pick(ActivityKind.allCases)
            let typeID: UInt? = r.next() < 0.2 ? nil : pick(ids)
            let input = ScoreInput(kind: kind, minutes: pick([0, 1, 20, 45, 60, 90, 240, 400]), effort: pick([1, 3, 5, 8, 10]),
                                   meters: r.next() < 0.5 ? nil : pick([0.0, 999.9, 5_000.4, 10_000.0, 21_097.5]),
                                   kcal: r.next() < 0.6 ? nil : pick([0.0, 99.5, 250.4, 412.4, 800.5]), workoutTypeID: typeID)
            let hasPhoto = r.next() < 0.5
            cases.append([
                "scoring": league.scoring.rawValue, "weights": weights, "weightsRaw": league.weightsRaw,
                "activityRule": league.activityRule.rawValue, "photoRule": league.photoRule.rawValue,
                "pointRules": settings.pointRules.map { ["workoutTypeIDs": $0.workoutTypeIDs.map { Int($0) }, "sections": $0.sections, "method": $0.method.rawValue,
                                                          "points": $0.points, "every": $0.every, "metric": $0.metric.rawValue] as [String: Any] },
                "input": ["kind": kind.rawValue, "minutes": input.minutes, "effort": input.effort,
                          "meters": input.meters.map(bits) as Any? ?? NSNull(), "kcal": input.kcal.map(bits) as Any? ?? NSNull(),
                          "workoutTypeID": typeID.map { Int($0) } as Any? ?? NSNull()],
                "hasPhoto": hasPhoto,
                "score": league.score(input, hasPhoto: hasPhoto),
            ])
        }
        try attach("L", ["version": 1, "catalog": catalog, "kcal": kcal, "score": cases])
    }

    // MARK: Grupo B

    func testGroupB() throws {
        // Snapshot do bro: dias no fuso de Brasília, atividades perto da meia-noite, tetos 150/300, galhos e viradas
        var snapshots: [[String: Any]] = []
        let base = cal.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 12))!
        for k in 0..<12 {
            var r = SeededRandom(seed: "snapshot-\(k)")
            var records: [ActivityRecord] = []
            var json: [[String: Any]] = []
            let count = 5 + Int(r.next() * 60)
            for i in 0..<count {
                let kind = ActivityKind.allCases[Int(r.next() * Double(ActivityKind.allCases.count))]
                let dayOffset = Int(r.next() * 40)
                // Horas de 0 a 23 com minutos: inclui 23h50 e 0h10
                let minuteOfDay = [5, 10, 600, 720, 1100, 1430, 1435][Int(r.next() * 7)]
                let date = cal.date(byAdding: .minute, value: dayOffset * 1440 + minuteOfDay - 720, to: base)!
                let minutes = [0, 10, 30, 45, 60, 90, 120, 240, 300][Int(r.next() * 9)]
                let effort = 1 + Int(r.next() * 10)
                let share = r.next() < 0.2 ? Roster.leagueShare : 1.0
                var weights: [Attribute: Double]? = nil
                if r.next() < 0.3 {
                    let a = Attribute.allCases[Int(r.next() * 4)], b = Attribute.allCases[Int(r.next() * 4)]
                    weights = a == b ? [a: 1] : [a: 0.62, b: 0.38]
                }
                let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012ld", k * 1000 + i))!
                var rec = ActivityRecord(id: id, kind: kind, date: date, minutes: minutes, effort: effort)
                rec.weights = weights
                rec.share = share
                records.append(rec)
                json.append(["id": id.uuidString, "kind": kind.rawValue, "date": iso(date), "minutes": minutes, "effort": effort,
                             "share": bits(share), "weights": weights.map { w in Dictionary(uniqueKeysWithValues: w.map { ($0.key.rawValue, bits($0.value)) }) } as Any? ?? NSNull()])
            }
            let now = cal.date(byAdding: .day, value: 38, to: base)!.addingTimeInterval(3600 * 11)
            let s = Game.snapshot(records, now: now, calendar: cal)
            snapshots.append([
                "records": json, "now": iso(now),
                "totalXP": s.totalXP, "todayXP": s.todayXP, "streak": s.streak, "bestStreak": s.bestStreak,
                "form": s.form.key, "evolutions": s.evolutions.map(\.form.key),
                "xpByActivity": records.map { s.xpByActivity[$0.id] ?? 0 },
                "lifetimeAttributes": Dictionary(uniqueKeysWithValues: s.lifetimeAttributes.map { ($0.key.rawValue, bits($0.value)) }),
                "hatchAttributes": Dictionary(uniqueKeysWithValues: s.hatchAttributes.map { ($0.key.rawValue, bits($0.value)) }),
            ])
        }
        // Rodada suíça inteira, no calendário de Brasília e com `now` fixo
        var tables: [[String: Any]] = []
        for k in 0..<10 {
            var r = SeededRandom(seed: "table-\(k)")
            let n = 2 + Int(r.next() * 8)
            let members = (0..<n).map { "u\(k)x\($0)" }
            let start = cal.date(byAdding: .day, value: -Int(r.next() * 20) - 1, to: base)!
            let now = base.addingTimeInterval(3600 * (r.next() < 0.5 ? 1 : 22))
            var tallies: [Date: [String: SwissTally]] = [:]
            var talliesJSON: [String: [String: [Int]]] = [:]
            var day = cal.startOfDay(for: start)
            while day <= now {
                for m in members where r.next() < 0.6 {
                    let t = SwissTally(score: Int(r.next() * 80), checkIns: Int(r.next() * 3))
                    tallies[day, default: [:]][m] = t
                    talliesJSON[stamp(day), default: [:]][m] = [t.score, t.checkIns]
                }
                day = cal.date(byAdding: .day, value: 1, to: day)!
            }
            var joined: [String: Date] = [:]
            for m in members where r.next() < 0.2 { joined[m] = cal.date(byAdding: .day, value: Int(r.next() * 10), to: start)! }
            let criterion = SwissCriterion.allCases[k % 3]
            let t = Swiss.table(members: members, tallies: tallies, start: start, end: nil, now: now, seed: "SEED\(k)",
                                criterion: criterion, identity: [:], joined: joined, calendar: cal)
            tables.append([
                "members": members, "start": iso(start), "now": iso(now), "seed": "SEED\(k)", "criterion": criterion.rawValue,
                "joined": joined.mapValues(iso), "tallies": talliesJSON,
                "rounds": t.rounds.map { r in ["day": stamp(r.day), "finished": r.finished,
                                               "matches": r.matches.map { [$0.a, $0.b as Any? ?? NSNull(), bits($0.pointsA), bits($0.pointsB)] }] },
                "points": t.points.mapValues(bits),
            ])
        }
        try attach("B", ["version": 1, "timeZone": cal.timeZone.identifier, "snapshot": snapshots, "swissTable": tables])
    }

    // MARK: Grupo C

    @MainActor
    func testGroupC() throws {
        let container = try ModelContainer(for: AppData.schema,
                                           configurations: ModelConfiguration(schema: AppData.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let ctx = container.mainContext
        let when = Date(timeIntervalSince1970: 1_800_000_000.75)
        let a = Activity(kind: .corrida, date: when, minutes: 42, effort: 7, note: "Parque")
        a.meters = 8_400
        ctx.insert(a)
        let routine = Routine(name: "Treino A")
        ctx.insert(routine)
        ctx.insert(Monster(name: "Bro", isStarter: true))
        let league = League(name: "Liga", emoji: "🏆", scoring: .pontos, start: when)
        var settings = LeagueSettings()
        settings.reviewSince = when
        settings.weekStart = 2
        league.settings = settings
        ctx.insert(league)
        try ctx.save()
        let d = scratchDefaults("golden")
        d.set("ABC234", forKey: "friendCode")
        d.set("Treinadora", forKey: "trainerName")
        var backup = try Backup.make(context: ctx, defaults: d, account: true)
        backup.exportedAt = when
        let raw = try Backup.encoder.encode(backup)
        let packed = try (raw as NSData).compressed(using: .zlib) as Data
        let sample: [String: Any] = ["texto": "olá", "inteiro": 42, "real": 2.5, "sim": true, "nao": false,
                                     "data": Date(timeIntervalSince1970: 1_800_000_000), "bytes": Data([1, 2, 3]),
                                     "lista": [1, "x", 2.5], "dicionario": ["k": 1]]
        let plist = try PropertyListSerialization.data(fromPropertyList: sample, format: .binary, options: 0)
        try attach("C", [
            "version": 1,
            "backupJSON": String(decoding: raw, as: UTF8.self),
            "backupDeflateBase64": packed.base64EncodedString(),
            "backupBytes": raw.count,
            "accountSettingsBase64": backup.accountSettings?.base64EncodedString() ?? "",
            "plistSampleBase64": plist.base64EncodedString(),
            "leagueSettingsRaw": settings.rawValue,
            "reviewSinceUnix": bits(when.timeIntervalSince1970),
        ])
    }
}
