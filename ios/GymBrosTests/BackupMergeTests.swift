import SwiftData
import XCTest
@testable import GymBros

/// Mesclagem da cópia da conta entre aparelhos (IOS-08): uma linha da tabela do desenho por teste
final class BackupMergeTests: GymTestCase {
    private let a = "00000000-0000-0000-0000-00000000000A", b = "00000000-0000-0000-0000-00000000000B",
                c = "00000000-0000-0000-0000-00000000000C"

    private func activity(_ id: String, minutes: Int = 30, note: String = "") -> String {
        #"{"uuid":"\#(id)","kind":"corrida","date":"2026-10-20T12:00:00Z","minutes":\#(minutes),"effort":5,"note":"\#(note)"}"#
    }

    private func backup(_ activities: [String], exported: String = "2026-10-20T12:00:00Z", settings: String = "{}",
                        body: String = "[]") throws -> Backup {
        let json = #"{"version":1,"exportedAt":"\#(exported)","settings":\#(settings),"activities":[\#(activities.joined(separator: ","))],"routines":[],"sessions":[],"customExercises":[],"body":\#(body)}"#
        return try Backup.decoder.decode(Backup.self, from: Data(json.utf8))
    }

    private func minutes(_ b: Backup) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: b.activities.map { ($0.uuid.uuidString, $0.minutes) })
    }

    func testEditedOnTheOtherDeviceComesIn() throws {
        let base = try backup([activity(a)])
        let out = try BackupMerge.merge(local: base, remote: try backup([activity(a, minutes: 45)]), base: base)
        XCTAssertEqual(minutes(out.backup), [a: 45])
        XCTAssertTrue(out.conflicts.isEmpty)
    }

    func testEditedHereStays() throws {
        let base = try backup([activity(a)])
        let out = try BackupMerge.merge(local: try backup([activity(a, minutes: 60)]), remote: base, base: base)
        XCTAssertEqual(minutes(out.backup), [a: 60])
    }

    func testEditedOnBothKeepsTheNewerCopyAndReportsIt() throws {
        let base = try backup([activity(a)])
        let local = try backup([activity(a, minutes: 60)], exported: "2026-10-21T12:00:00Z")
        let remote = try backup([activity(a, minutes: 45)], exported: "2026-10-22T12:00:00Z")
        let out = try BackupMerge.merge(local: local, remote: remote, base: base)
        XCTAssertEqual(minutes(out.backup), [a: 45])
        XCTAssertEqual(out.conflicts, ["activities:\(a)"])
    }

    func testDeletedOnTheOtherDeviceGoes() throws {
        let base = try backup([activity(a), activity(b)])
        let out = try BackupMerge.merge(local: base, remote: try backup([activity(a)]), base: base)
        XCTAssertEqual(minutes(out.backup), [a: 30])
    }

    func testDeletedHereDoesNotComeBack() throws {
        let base = try backup([activity(a), activity(b)])
        let out = try BackupMerge.merge(local: try backup([activity(a)]), remote: base, base: base)
        XCTAssertEqual(minutes(out.backup), [a: 30])
    }

    func testDeletedThereButEditedHereStays() throws {
        let base = try backup([activity(a), activity(b)])
        let out = try BackupMerge.merge(local: try backup([activity(a), activity(b, minutes: 90)]), remote: try backup([activity(a)]), base: base)
        XCTAssertEqual(minutes(out.backup), [a: 30, b: 90])
    }

    func testNewOnBothSidesAreKept() throws {
        let base = try backup([activity(a)])
        let out = try BackupMerge.merge(local: try backup([activity(a), activity(b)]), remote: try backup([activity(a), activity(c)]), base: base)
        XCTAssertEqual(minutes(out.backup), [a: 30, b: 30, c: 30])
        XCTAssertEqual(out.backup.activities.map(\.uuid.uuidString), [a, b, c])
    }

    func testWithoutBaseItIsAUnionAndNothingIsDeleted() throws {
        let out = try BackupMerge.merge(local: try backup([activity(a), activity(b)]), remote: try backup([activity(c)]), base: nil)
        XCTAssertEqual(Set(minutes(out.backup).keys), [a, b, c])
    }

    func testLocalPhotoSurvivesTheCloudCopyWithoutPhotos() throws {
        let photo = Data([1, 2, 3]).base64EncodedString()
        let base = try backup([], body: #"[{"uuid":"\#(a)","date":"2026-10-20T12:00:00Z","weight":80,"photoFront":"\#(photo)"}]"#)
        // O outro aparelho corrigiu o peso; a cópia da nuvem não leva fotos
        let remote = try backup([], body: #"[{"uuid":"\#(a)","date":"2026-10-20T12:00:00Z","weight":79.5}]"#)
        let out = try BackupMerge.merge(local: base, remote: remote, base: base)
        XCTAssertEqual(out.backup.body?.first?.weight, 79.5)
        XCTAssertEqual(out.backup.body?.first?.photoFront, Data([1, 2, 3]))
    }

    func testCloudCopyWithoutPhotosIsNotAChange() throws {
        let photo = Data([9]).base64EncodedString()
        let local = try backup([], body: #"[{"uuid":"\#(a)","date":"2026-10-20T12:00:00Z","weight":80,"photoFront":"\#(photo)"}]"#)
        let remote = try backup([], body: #"[{"uuid":"\#(a)","date":"2026-10-20T12:00:00Z","weight":80}]"#)
        let out = try BackupMerge.merge(local: local, remote: remote, base: local)
        XCTAssertEqual(out.backup.body?.first?.photoFront, Data([9]))
        XCTAssertTrue(out.conflicts.isEmpty)
    }

    func testSettingsMergeKeyByKey() throws {
        let base = try backup([], settings: #"{"trainerName":"Ana","bodyGender":"f"}"#)
        let local = try backup([], settings: #"{"trainerName":"Ana B","bodyGender":"f"}"#)
        let remote = try backup([], settings: #"{"trainerName":"Ana","bodyGender":"m","profileBio":"oi"}"#)
        let out = try BackupMerge.merge(local: local, remote: remote, base: base)
        XCTAssertEqual(out.backup.settings, ["trainerName": "Ana B", "bodyGender": "m", "profileBio": "oi"])
    }

    func testRegistriesAreUnited() {
        let out = BackupMerge.mergeDict([RetiredActivities.key: ["x", "y"]], [RetiredActivities.key: ["y", "z"]], [RetiredActivities.key: ["y"]],
                                        newerIsLocal: true)
        XCTAssertEqual(out?[RetiredActivities.key] as? [String], ["x", "y", "z"])
    }

    func testMergingTheSameCopyChangesNothing() throws {
        let x = try backup([activity(a), activity(b, note: "corrida leve")], settings: #"{"trainerName":"Ana"}"#)
        let out = try BackupMerge.merge(local: x, remote: x, base: x)
        XCTAssertEqual(try Backup.encoder.encode(out.backup), try Backup.encoder.encode(x))
        let twice = try BackupMerge.merge(local: out.backup, remote: x, base: x)
        XCTAssertEqual(try Backup.encoder.encode(twice.backup), try Backup.encoder.encode(out.backup))
    }
}

/// Aplicar a mesclagem num banco que já tem dados (sair da conta, abrir o app): antes o `restore` só rodava com o banco vazio
final class BackupRestoreOverDataTests: GymTestCase {
    @MainActor
    func testRestoreOverAPopulatedStoreWithWorkoutsAndSets() throws {
        let container = try ModelContainer(for: AppData.schema,
                                           configurations: ModelConfiguration(schema: AppData.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let ctx = container.mainContext
        let session = WorkoutSession(title: "Treino A", routineUUID: nil)
        session.end = .now
        ctx.insert(session)
        for i in 0..<3 { session.sets.append(LoggedSet(exerciseID: "supino", exerciseOrder: 0, index: i, weight: 60, reps: 10, rest: 90)) }
        let routine = Routine(name: "Treino A")
        ctx.insert(routine)
        routine.items.append(RoutineItem(exerciseID: "supino", sets: 3, reps: 10, rest: 90, order: 0))
        try ctx.save()
        // Objetos carregados no contexto, como no app aberto
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<LoggedSet>()).count, 3)
        let d = scratchDefaults("restore")
        let copy = try Backup.make(context: ctx, defaults: d, account: true)

        try copy.restore(into: ctx, defaults: d)

        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<LoggedSet>()), 3)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Routine>()), 1)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<RoutineItem>()), 1)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<WorkoutSession>()).first?.sets.count, 3)
    }
}

/// Mesclagem ao vivo: só o que mudou no outro aparelho entra; o resto continua com o mesmo objeto no banco
final class BackupApplyChangesTests: GymTestCase {
    @MainActor
    func testOnlyChangedItemsAreReplaced() throws {
        let container = try ModelContainer(for: AppData.schema,
                                           configurations: ModelConfiguration(schema: AppData.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let ctx = container.mainContext
        let kept = Activity(kind: .corrida, date: .now, minutes: 30, effort: 5)
        let edited = Activity(kind: .yoga, date: .now, minutes: 20, effort: 3)
        let deleted = Activity(kind: .bike, date: .now, minutes: 40, effort: 6)
        for a in [kept, edited, deleted] { ctx.insert(a) }
        let session = WorkoutSession(title: "Treino A", routineUUID: nil)
        session.end = .now
        ctx.insert(session)
        for i in 0..<3 { session.sets.append(LoggedSet(exerciseID: "supino", exerciseOrder: 0, index: i, weight: 60, reps: 10, rest: 90)) }
        try ctx.save()
        let d = scratchDefaults("aplicar")
        let before = try Backup.make(context: ctx, defaults: d, account: true)

        // O outro aparelho: editou uma, apagou outra, criou uma nova e mexeu nas séries do treino
        var json = try Backup.jsonObject(before)
        var acts = json["activities"] as! [[String: Any]]
        acts = acts.compactMap { a in
            if a["uuid"] as? String == deleted.uuid.uuidString { return nil }
            var a = a
            if a["uuid"] as? String == edited.uuid.uuidString { a["minutes"] = 50 }
            return a
        }
        let newID = UUID().uuidString
        acts.append(["uuid": newID, "kind": "natacao", "date": ISO8601DateFormatter().string(from: .now), "minutes": 45, "effort": 7, "note": ""])
        json["activities"] = acts
        var sessions = json["sessions"] as! [[String: Any]]
        var sets = sessions[0]["sets"] as! [[String: Any]]
        sets[0]["reps"] = 12
        sessions[0]["sets"] = sets
        json["sessions"] = sessions
        let remote = try Backup.decoder.decode(Backup.self, from: JSONSerialization.data(withJSONObject: json))
        let keptID = kept.persistentModelID

        try remote.applyChanges(from: before, into: ctx, defaults: d)

        let all = try ctx.fetch(FetchDescriptor<Activity>())
        XCTAssertEqual(Set(all.map(\.uuid.uuidString)), [kept.uuid.uuidString, edited.uuid.uuidString, newID])
        XCTAssertEqual(all.first { $0.uuid == edited.uuid }?.minutes, 50)
        // A que não mudou é o mesmo objeto (tela aberta com ela continua funcionando)
        XCTAssertEqual(all.first { $0.uuid == kept.uuid }?.persistentModelID, keptID)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<LoggedSet>()), 3)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<WorkoutSession>()).first?.sets.map(\.reps).sorted(), [10, 10, 12])
    }

    @MainActor
    func testSameCopyChangesNothing() throws {
        let container = try ModelContainer(for: AppData.schema,
                                           configurations: ModelConfiguration(schema: AppData.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let ctx = container.mainContext
        let a = Activity(kind: .corrida, date: .now, minutes: 30, effort: 5)
        ctx.insert(a)
        try ctx.save()
        let d = scratchDefaults("aplicar")
        let copy = try Backup.make(context: ctx, defaults: d, account: true)
        let id = a.persistentModelID
        try copy.applyChanges(from: copy, into: ctx, defaults: d)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Activity>()).map(\.persistentModelID), [id])
    }
}
