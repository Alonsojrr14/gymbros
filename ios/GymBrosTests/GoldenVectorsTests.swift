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

    // MARK: Grupo R (bros: formas, espécies e o plantel)

    func testGroupR() throws {
        // Catálogo de formas de todas as espécies, com nome, arte e a forma que aparece no app
        var forms: [[String: Any]] = []
        for sp in Species.all {
            for f in MonsterForm.all(species: sp.id) + MonsterForm.hybrids(species: sp.id) + MonsterForm.viradas(species: sp.id) {
                forms.append(["id": f.id, "key": f.key, "stage": f.stage.rawValue, "name": f.name, "sprite": f.sprite,
                              "hasArt": f.hasArt, "resolved": f.resolved.id, "spriteWithFallback": f.spriteWithFallback])
            }
        }
        let species = Species.all.map { ["id": $0.id, "name": $0.name, "isReady": $0.isReady] as [String: Any] }
        // Espécie de cada tipo do Apple Saúde (os tipos do catálogo e os vizinhos, inclusive os aposentados)
        var health: [String: [String]] = [:]
        for raw in Array(UInt(0)...UInt(100)) + [3000] { health[String(raw)] = Hatch.species(forHealth: raw) }
        let kindSpecies = Dictionary(uniqueKeysWithValues: ActivityKind.allCases.map { ($0.rawValue, Hatch.species(for: $0)) })
        let symbols = Dictionary(uniqueKeysWithValues: WorkoutType.all.map { (String($0.id), $0.symbol) })
        let classic = Dictionary(uniqueKeysWithValues: ActivityKind.allCases.map { ($0.rawValue, Int(WorkoutType.of($0).id)) })
        // Dia na era (semente da frase do bro), no calendário do aparelho
        let calNow = Calendar.current
        let eraDays: [[String: Any]] = [0.0, 978_307_200, 1_700_000_000, 1_800_000_000, 1_800_050_000, 1_800_080_000].map { t in
            let d = Date(timeIntervalSince1970: t)
            return ["date": iso(d), "ordinality": calNow.ordinality(of: .day, in: .era, for: d) ?? 0]
        }
        // Humor
        var moods: [[String: Any]] = []
        let now = calNow.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 15))!
        for egg in [true, false] { for away in [-1, 0, 1, 2, 3, 4, 9] { for today in [0, 299, 300] { for streak in [0, 2, 3] {
            let last = away < 0 ? nil : calNow.date(byAdding: .hour, value: -24 * away - 14, to: now)
            moods.append(["isEgg": egg, "last": last.map(iso) as Any? ?? NSNull(), "todayXP": today, "streak": streak, "now": iso(now),
                          "mood": Mood.of(isEgg: egg, lastActivity: last, todayXP: today, streak: streak, now: now).rawValue])
        } } } }

        // Plantel: para onde vai o XP (principal, representantes de liga, apagadas, trocas) e a espécie de quem chocou
        func uuid(_ n: Int) -> UUID {
            let h = String(n, radix: 16)
            return UUID(uuidString: "00000000-0000-0000-0000-" + String(repeating: "0", count: 12 - h.count) + h)!
        }
        let d = UserDefaults.standard
        let base = calNow.date(from: DateComponents(year: 2026, month: 5, day: 1, hour: 12))!
        let typeIDs = WorkoutType.all.map(\.id)
        let formIDs = forms.compactMap { $0["id"] as? String }.filter { !$0.contains("_to_") }
        var rosters: [[String: Any]] = []
        for k in 0..<30 {
            var r = SeededRandom(seed: "roster-\(k)")
            func pick<T>(_ list: [T]) -> T { list[Int(r.next() * Double(list.count))] }
            var n = 100_000 * (k + 1)
            func next() -> UUID { n += 1; return uuid(n) }
            let monsters: [Monster] = (0..<(1 + Int(r.next() * 4))).map { i in
                let m = Monster(name: r.next() < 0.3 ? "Apelido \(i)" : "", isStarter: i == 0 && r.next() < 0.85)
                m.uuid = next()
                m.createdAt = base.addingTimeInterval(Double(i) * 3600)
                if r.next() < 0.3 { m.speciesID = pick(Species.all).id }
                return m
            }
            let ghost = next()
            let leagues: [League] = (0..<Int(r.next() * 3)).map { _ in
                let l = League(name: "L", emoji: "🏆", scoring: .pontos)
                l.uuid = next()
                l.monsterUUID = r.next() < 0.15 ? nil : r.next() < 0.1 ? ghost : pick(monsters).uuid
                return l
            }
            var activities: [Activity] = []
            var checkIns: [LeagueCheckIn] = []
            for _ in 0..<Int(r.next() * 70) {
                let date = base.addingTimeInterval(Double(Int(r.next() * 150 * 1440)) * 60)
                let a = Activity(kind: pick(ActivityKind.allCases), date: date, minutes: pick([0, 10, 20, 30, 45, 60, 90, 120, 240, 300]),
                                 effort: 1 + Int(r.next() * 10))
                a.uuid = next()
                if r.next() < 0.3 { a.healthType = Int(pick(typeIDs)) }
                let o = r.next()
                a.monsterUUID = o < 0.3 ? nil : o < 0.4 ? ghost : pick(monsters).uuid
                activities.append(a)
                for l in leagues where r.next() < 0.4 {
                    let c = LeagueCheckIn(leagueUUID: l.uuid, activityUUID: a.uuid, title: "", note: "", date: date, photo: nil)
                    checkIns.append(c)
                }
            }
            // Atividades apagadas que ainda valem XP
            var retired: [RetiredActivities.Entry] = []
            for _ in 0..<Int(r.next() * 4) {
                let owners = monsters.filter { _ in r.next() < 0.6 }.map(\.uuid) + (r.next() < 0.2 ? [ghost] : [])
                var e = RetiredActivities.Entry(id: next(), kind: pick(ActivityKind.allCases).rawValue,
                                                date: base.addingTimeInterval(Double(Int(r.next() * 150 * 1440)) * 60),
                                                minutes: pick([20, 60, 120]), effort: 1 + Int(r.next() * 10), owners: owners)
                if r.next() < 0.4 { e.healthType = pick(typeIDs) }
                if r.next() < 0.4 { e.weights = "forca:0.62,tecnica:0.38" }
                if r.next() < 0.5 { e.shares = Dictionary(uniqueKeysWithValues: owners.map { ($0.uuidString, pick([1.0, Roster.leagueShare])) }) }
                retired.append(e)
            }
            // Bros que chegaram por troca e o que saiu
            var bases: [String: SnapshotBase] = [:]
            for m in monsters.dropFirst() where r.next() < 0.3 {
                bases[m.uuid.uuidString] = SnapshotBase(formID: pick(formIDs), xp: pick([0, 80, 700, 2000, 5000]),
                                                        attributes: ["forca": pick([0.0, 120.5, 900.25]), "tecnica": pick([0.0, 33.75])],
                                                        date: base.addingTimeInterval(Double(Int(r.next() * 60)) * 86400),
                                                        history: r.next() < 0.5 ? nil : [OwnerXP(name: "Ana", xp: 10)])
            }
            let gone = monsters.count > 1 && r.next() < 0.2 ? [monsters.last!.uuid.uuidString] : []
            let mainID: String? = r.next() < 0.5 ? pick(monsters).uuid.uuidString : r.next() < 0.3 ? ghost.uuidString : nil

            RetiredActivities.save(retired, d)
            d.set(try JSONEncoder().encode(bases), forKey: TradeLedger.basesKey)
            d.set(gone, forKey: TradeLedger.goneKey)
            d.set(mainID, forKey: MainMonster.key)
            SnapshotCache.shared.removeAll()
            let roster = Roster(monsters: monsters, activities: activities, checkIns: checkIns, leagues: leagues)

            rosters.append([
                "monsters": monsters.map { ["uuid": $0.uuid.uuidString, "name": $0.name, "createdAt": iso($0.createdAt), "isStarter": $0.isStarter,
                                            "speciesID": $0.speciesID as Any? ?? NSNull()] },
                "leagues": leagues.map { ["uuid": $0.uuid.uuidString, "monsterUUID": $0.monsterUUID?.uuidString as Any? ?? NSNull()] },
                "activities": activities.map { ["uuid": $0.uuid.uuidString, "kind": $0.kindRaw, "date": iso($0.date), "minutes": $0.minutes,
                                                "effort": $0.effort, "healthType": $0.healthType as Any? ?? NSNull(),
                                                "monsterUUID": $0.monsterUUID?.uuidString as Any? ?? NSNull()] },
                "checkIns": checkIns.map { ["leagueUUID": $0.leagueUUID.uuidString, "activityUUID": $0.activityUUID.uuidString] },
                "retiredActivities": String(decoding: try JSONEncoder().encode(retired), as: UTF8.self),
                "tradeBases": String(decoding: try JSONEncoder().encode(bases), as: UTF8.self),
                "tradeGone": gone,
                "mainMonster": mainID as Any? ?? NSNull(),
                "mainID": roster.mainID?.uuidString as Any? ?? NSNull(),
                "main": roster.main?.uuid.uuidString as Any? ?? NSNull(),
                "xpByActivity": Dictionary(uniqueKeysWithValues: roster.xpByActivity.map { ($0.key.uuidString, $0.value) }),
                "snapshots": monsters.map { m -> [String: Any] in
                    let s = roster.snapshot(m.uuid)
                    return ["uuid": m.uuid.uuidString, "form": s.form.id, "totalXP": s.totalXP, "level": s.level,
                            "progress": bits(s.progress), "xpToNext": s.xpToNext as Any? ?? NSNull(),
                            "nextForm": s.nextForm?.id as Any? ?? NSNull(), "displayName": m.displayName(s.form),
                            "evolutions": s.evolutions.map(\.form.id), "inheritedXP": s.inheritedXP,
                            "stageAttributes": Dictionary(uniqueKeysWithValues: s.stageAttributes.map { ($0.key.rawValue, bits($0.value)) }),
                            "lifetimeAttributes": Dictionary(uniqueKeysWithValues: s.lifetimeAttributes.map { ($0.key.rawValue, bits($0.value)) })]
                },
            ])
        }
        SnapshotCache.shared.removeAll()
        try attach("R", ["version": 1, "timeZone": calNow.timeZone.identifier, "forms": forms, "species": species, "health": health,
                         "kindSpecies": kindSpecies, "symbols": symbols, "classicType": classic, "eraDays": eraDays, "moods": moods,
                         "rosters": rosters])
    }

    // MARK: Grupo M (mesclagem da cópia da conta entre aparelhos, IOS-08)

    func testGroupM() throws {
        var cases: [[String: Any]] = []
        let ids = (0..<8).map { "00000000-0000-0000-0000-00000000000\($0)" }
        let exercises = ["supino", "agacho", "remada"]
        let dates = ["2026-10-20T12:00:00Z", "2026-10-21T09:30:00Z", "2026-10-21T09:30:00Z", "2026-10-22T18:00:00Z"]
        for k in 0..<80 {
            var r = SeededRandom(seed: "merge-\(k)")
            func pick<T>(_ list: [T]) -> T { list[Int(r.next() * Double(list.count))] }
            func chance(_ p: Double) -> Bool { r.next() < p }
            // Base: o que os dois aparelhos tinham em comum
            var acts: [String: [String: Any]] = [:]
            for id in ids where chance(0.6) {
                acts[id] = ["uuid": id, "kind": pick(["corrida", "musculacao", "yoga"]), "date": pick(dates), "minutes": pick([20, 30, 45]),
                            "effort": pick([3, 5, 8]), "note": pick(["", "leve", "forte"])]
            }
            var notes: [String: [String: Any]] = [:]
            for e in exercises where chance(0.5) { notes[e] = ["exerciseID": e, "text": pick(["a", "b", "c"])] }
            var settings: [String: String] = [:]
            for key in ["trainerName", "bodyGender", "profileBio"] where chance(0.7) { settings[key] = pick(["Ana", "m", "f", "oi"]) }
            var plist: [String: Any] = [:]
            if chance(0.7) { plist["texto"] = pick(["x", "y"]) }
            if chance(0.7) { plist["numero"] = pick([1, 2, 3]) }
            if chance(0.5) { plist["ligado"] = chance(0.5) }
            if chance(0.5) { plist["quando"] = Date(timeIntervalSince1970: pick([1_800_000_000.0, 1_800_000_500.25])) }
            if chance(0.6) { plist[TradeLedger.goneKey] = ids.prefix(Int(r.next() * 3)).map { $0 } }
            if chance(0.6) { plist[TradeLedger.appliedKey] = (0..<Int(r.next() * 3)).map { "t\($0)" } }
            if chance(0.5) { plist[RetiredActivities.key] = Data(pick(["[]", "[1]"]).utf8) }
            var body: [String: [String: Any]] = [:]
            for id in ids.prefix(3) where chance(0.5) { body[id] = ["uuid": id, "date": pick(dates), "weight": pick([80, 79.5, 81])] }

            // Cada aparelho muda a base do seu jeito: edita, apaga e cria
            func variant(photos: Bool) -> (acts: [String: [String: Any]], notes: [String: [String: Any]], settings: [String: String],
                                            plist: [String: Any], body: [String: [String: Any]]) {
                var a = acts, n = notes, st = settings, pl = plist, b = body
                for id in ids {
                    if a[id] != nil, chance(0.2) { a[id] = nil } else if a[id] != nil, chance(0.3) { a[id]?["minutes"] = pick([50, 60, 90]) }
                    else if a[id] == nil, chance(0.15) {
                        a[id] = ["uuid": id, "kind": "bike", "date": pick(dates), "minutes": pick([30, 40]), "effort": 5, "note": ""]
                    }
                }
                for e in exercises {
                    if n[e] != nil, chance(0.2) { n[e] = nil } else if chance(0.3) { n[e] = ["exerciseID": e, "text": pick(["d", "e"])] }
                }
                for key in ["trainerName", "bodyGender", "profileBio"] {
                    if chance(0.15) { st[key] = nil } else if chance(0.3) { st[key] = pick(["Bia", "x", "tchau"]) }
                }
                if chance(0.3) { pl["texto"] = pick(["z", "w"]) }
                if chance(0.2) { pl["numero"] = nil }
                if chance(0.3) { pl["quando"] = Date(timeIntervalSince1970: 1_800_009_999) }
                if chance(0.5) { pl[TradeLedger.goneKey] = ((pl[TradeLedger.goneKey] as? [String]) ?? []) + [pick(ids)] }
                if chance(0.4) { pl[TradeLedger.appliedKey] = ((pl[TradeLedger.appliedKey] as? [String]) ?? []) + ["t\(Int(r.next() * 5))"] }
                if chance(0.3) { pl[RetiredActivities.key] = Data(pick(["[2]", "[3]"]).utf8) }
                for id in ids.prefix(3) {
                    if b[id] != nil, chance(0.3) { b[id]?["weight"] = pick([78, 82.5]) }
                    if photos, b[id] != nil, chance(0.5) { b[id]?["photoFront"] = Data([UInt8(k), 1, 2]).base64EncodedString() }
                }
                return (a, n, st, pl, b)
            }
            func make(_ v: (acts: [String: [String: Any]], notes: [String: [String: Any]], settings: [String: String], plist: [String: Any],
                            body: [String: [String: Any]]), exported: String) throws -> Backup {
                // Ordem dos itens como no aparelho: a ordem de criação (embaralhada um pouco pelo lado)
                let order = ids.sorted { _, _ in chance(0.3) }
                var json: [String: Any] = ["version": 1, "exportedAt": exported, "settings": v.settings,
                                           "activities": order.compactMap { v.acts[$0] }, "routines": [], "sessions": [], "customExercises": [],
                                           "notes": exercises.compactMap { v.notes[$0] }, "body": ids.compactMap { v.body[$0] }]
                if !v.plist.isEmpty {
                    json["accountSettings"] = try PropertyListSerialization.data(fromPropertyList: v.plist, format: .binary, options: 0).base64EncodedString()
                }
                let data = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
                return try Backup.decoder.decode(Backup.self, from: data)
            }
            let base = try make((acts, notes, settings, plist, body), exported: dates[0])
            let local = try make(variant(photos: true), exported: pick(dates))
            let remote = try make(variant(photos: false), exported: pick(dates))
            let withBase = chance(0.8)
            let out = try BackupMerge.merge(local: local, remote: remote, base: withBase ? base : nil)
            func text(_ b: Backup) throws -> String { String(decoding: try Backup.encoder.encode(b), as: UTF8.self) }
            cases.append(["local": try text(local), "remote": try text(remote), "base": withBase ? try text(base) : NSNull(),
                          "merged": try text(out.backup), "conflicts": out.conflicts])
        }
        try attach("M", ["version": 1, "cases": cases])
    }

    // MARK: Grupo S (divisão do XP entre os atributos ao salvar uma atividade, sem séries nem WOD)

    func testGroupS() throws {
        var cases: [[String: Any]] = []
        for t in WorkoutType.all {
            for minutes in [5, 20, 25, 30, 60, 75, 90, 150, 240] { for effort in [1, 3, 5, 8, 10] { for meters in [nil, 900.0, 5_000, 21_100] as [Double?] {
                let s = AttributeSplit.Signals(kind: t.kind, minutes: minutes, effort: effort, meters: meters, healthType: t.id)
                cases.append(["type": Int(t.id), "kind": t.kind.rawValue, "minutes": minutes, "effort": effort,
                              "meters": meters.map(bits) as Any? ?? NSNull(), "split": AttributeSplit.encode(AttributeSplit.split(s))])
            } } }
        }
        let aliases = Dictionary(uniqueKeysWithValues: WorkoutType.all.map { (String($0.id), $0.aliases) })
        try attach("S", ["version": 1, "cases": cases, "aliases": aliases])
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
