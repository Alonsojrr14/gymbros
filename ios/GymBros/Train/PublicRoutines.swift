import SwiftData
import SwiftUI

// Rotinas públicas: quem quiser publica uma rotina sua; os outros curtem, salvam uma cópia e ordenam por mais salvas,
// mais curtidas, novas ou dos amigos. Contrato `RoutinesBackend`; por enquanto responde o `MockRoutinesBackend`
// (rotinas dos participantes simulados, montadas dos modelos prontos, e as suas guardadas no aparelho).

struct PublicRoutine: Codable, Hashable, Identifiable, Sendable {
    struct Item: Codable, Hashable, Sendable {
        var exerciseID: String
        var sets: Int
        var reps: Int
        var rest: Int
    }

    let id: String
    var name: String
    let authorID: String
    var authorName: String
    var authorFormID: String
    var items: [Item]
    var likes: Int
    var saves: Int
    let createdAt: Date

    var author: MonsterForm { MonsterForm.byID(authorFormID) ?? .egg }
    var setCount: Int { items.reduce(0) { $0 + $1.sets } }
}

enum RoutineSort: String, CaseIterable, Identifiable {
    case saved, liked, newest, friends

    var id: String { rawValue }
    var name: String {
        switch self {
        case .saved: "Mais salvas"
        case .liked: "Mais curtidas"
        case .newest: "Novas"
        case .friends: "Dos amigos"
        }
    }
}

protocol RoutinesBackend: Sendable {
    func fetch() async throws -> [PublicRoutine]
    func publish(_ r: PublicRoutine) async throws
    func unpublish(_ id: String) async throws
    func like(_ id: String, _ on: Bool) async throws
    /// Conta uma cópia salva
    func saved(_ id: String) async throws
}

/// Rotinas dos participantes simulados, a partir dos modelos prontos, mais as suas (no aparelho)
struct MockRoutinesBackend: RoutinesBackend {
    static let publishedKey = "routines.published", likedKey = "routines.liked", savedKey = "routines.saved"

    func fetch() async throws -> [PublicRoutine] {
        let d = UserDefaults.standard
        var out: [PublicRoutine] = []
        let routines = RoutineTemplate.all.flatMap(\.routines)
        for (i, r) in routines.enumerated() {
            let m = FakeMember.all[i % FakeMember.all.count]
            var rng = SeededRandom(seed: "rotina-\(r.name)")
            out.append(PublicRoutine(id: "sim-\(i)", name: r.name, authorID: m.id, authorName: m.name, authorFormID: m.form.id,
                                     items: r.items.map { .init(exerciseID: $0.0, sets: $0.1, reps: $0.2, rest: 90) },
                                     likes: 3 + Int(rng.next() * 60), saves: 1 + Int(rng.next() * 40),
                                     createdAt: .now.addingTimeInterval(-Double(1 + Int(rng.next() * 60)) * 86400)))
        }
        if let data = d.data(forKey: Self.publishedKey), let mine = try? JSONDecoder().decode([PublicRoutine].self, from: data) { out += mine }
        let liked = Set(d.stringArray(forKey: Self.likedKey) ?? [])
        let saved = d.dictionary(forKey: Self.savedKey) as? [String: Int] ?? [:]
        return out.map { r in
            var r = r
            if liked.contains(r.id) { r.likes += 1 }
            r.saves += saved[r.id] ?? 0
            return r
        }
    }

    func publish(_ r: PublicRoutine) async throws {
        let d = UserDefaults.standard
        var mine = (d.data(forKey: Self.publishedKey)).flatMap { try? JSONDecoder().decode([PublicRoutine].self, from: $0) } ?? []
        mine.removeAll { $0.id == r.id }
        mine.append(r)
        d.set(try? JSONEncoder().encode(mine), forKey: Self.publishedKey)
    }

    func unpublish(_ id: String) async throws {
        let d = UserDefaults.standard
        var mine = (d.data(forKey: Self.publishedKey)).flatMap { try? JSONDecoder().decode([PublicRoutine].self, from: $0) } ?? []
        mine.removeAll { $0.id == id }
        d.set(try? JSONEncoder().encode(mine), forKey: Self.publishedKey)
    }

    func like(_ id: String, _ on: Bool) async throws {
        let d = UserDefaults.standard
        var liked = Set(d.stringArray(forKey: Self.likedKey) ?? [])
        if on { liked.insert(id) } else { liked.remove(id) }
        d.set(Array(liked), forKey: Self.likedKey)
    }

    func saved(_ id: String) async throws {
        let d = UserDefaults.standard
        var saved = d.dictionary(forKey: Self.savedKey) as? [String: Int] ?? [:]
        saved[id, default: 0] += 1
        d.set(saved, forKey: Self.savedKey)
    }
}

@MainActor @Observable
final class PublicRoutinesStore {
    static let shared = PublicRoutinesStore()
    var backend: any RoutinesBackend = MockRoutinesBackend()
    private(set) var all: [PublicRoutine] = []

    var liked: Set<String> { Set(UserDefaults.standard.stringArray(forKey: MockRoutinesBackend.likedKey) ?? []) }

    func refresh() async { all = (try? await backend.fetch()) ?? all }

    func sorted(_ s: RoutineSort, friends: Set<String>) -> [PublicRoutine] {
        switch s {
        case .saved: all.sorted { $0.saves > $1.saves }
        case .liked: all.sorted { $0.likes > $1.likes }
        case .newest: all.sorted { $0.createdAt > $1.createdAt }
        case .friends: all.filter { friends.contains($0.authorID) }.sorted { $0.createdAt > $1.createdAt }
        }
    }

    func isPublished(_ r: Routine) -> Bool { all.contains { $0.id == r.uuid.uuidString } }

    func publish(_ r: Routine, name me: String, formID: String) async {
        let p = PublicRoutine(id: r.uuid.uuidString, name: r.name, authorID: "me", authorName: me.isEmpty ? "Você" : me, authorFormID: formID,
                              items: r.sortedItems.map { .init(exerciseID: $0.exerciseID, sets: $0.sets, reps: $0.reps, rest: $0.rest) },
                              likes: 0, saves: 0, createdAt: .now)
        try? await backend.publish(p)
        await refresh()
    }

    func unpublish(_ r: Routine) async {
        try? await backend.unpublish(r.uuid.uuidString)
        await refresh()
    }

    func toggleLike(_ r: PublicRoutine) async {
        try? await backend.like(r.id, !liked.contains(r.id))
        await refresh()
    }

    /// Salva uma cópia nas suas rotinas
    func saveCopy(_ r: PublicRoutine, context: ModelContext, order: Int) async {
        let routine = Routine(name: r.name, order: order)
        context.insert(routine)
        for (i, item) in r.items.enumerated() {
            routine.items.append(RoutineItem(exerciseID: item.exerciseID, sets: item.sets, reps: item.reps, rest: item.rest, order: i))
        }
        try? context.save()
        try? await backend.saved(r.id)
        await refresh()
    }
}

/// Arte da rotina: a imagem do primeiro exercício
struct RoutineArt: View {
    let exerciseID: String?
    var size: CGFloat = 56

    var body: some View {
        if let id = exerciseID, let ex = Exercise.byID(id) {
            ExerciseThumb(exercise: ex, size: size)
        } else {
            Image(systemName: "list.bullet.rectangle").font(.title3).frame(width: size, height: size)
                .background(Theme.raised, in: .rect(cornerRadius: Theme.radiusM)).foregroundStyle(Theme.accent)
        }
    }
}

/// Explorar rotinas públicas
struct PublicRoutinesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Routine.order) private var mine: [Routine]
    @State private var store = PublicRoutinesStore.shared
    @State private var sort = RoutineSort.saved
    @State private var opened: PublicRoutine?

    var body: some View {
        let list = store.sorted(sort, friends: FriendsStore.shared.friendIDs)
        GMScreen("Rotinas públicas", back: true) {
            GMChoiceChips(options: RoutineSort.allCases.map { ($0, $0.name) }, selection: $sort)
            if list.isEmpty {
                GMEmptyState(icon: "person.2", title: sort == .friends ? "Nenhuma rotina dos seus amigos" : "Nenhuma rotina ainda",
                             message: "Publique uma rotina sua pelo menu dela em Treinar.")
            }
            ForEach(list) { r in
                Button { opened = r } label: { row(r) }.buttonStyle(GMPress())
            }
        }
        .task { await store.refresh() }
        .gmModal(item: $opened) { r in PublicRoutineDetail(routine: r, order: mine.count) }
    }

    private func row(_ r: PublicRoutine) -> some View {
        GMCard {
            HStack(spacing: 12) {
                RoutineArt(exerciseID: r.items.first?.exerciseID)
                VStack(alignment: .leading, spacing: 3) {
                    Text(r.name).font(.headline).lineLimit(1)
                    HStack(spacing: 5) {
                        MonsterSprite(form: r.author).frame(width: 18, height: 18)
                        Text(r.authorID == "me" ? "Você" : r.authorName).font(.caption.weight(.semibold))
                    }
                    Text("\(r.items.count) exercícios · \(r.setCount) séries · ❤️ \(r.likes) · 📥 \(r.saves)").font(.caption).foregroundStyle(Theme.dim)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.dim)
            }
            .foregroundStyle(.white)
        }
    }
}

private struct PublicRoutineDetail: View {
    let routine: PublicRoutine
    let order: Int
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var store = PublicRoutinesStore.shared
    @State private var saved = false

    var body: some View {
        let current = store.all.first { $0.id == routine.id } ?? routine
        GMModal(current.name) {
            HStack(spacing: 10) {
                MonsterSprite(form: current.author).frame(width: 36, height: 36)
                Text("por \(current.authorID == "me" ? "você" : current.authorName)").font(.subheadline)
                Spacer()
                Text("❤️ \(current.likes) · 📥 \(current.saves)").font(.subheadline.monospacedDigit()).foregroundStyle(Theme.dim)
            }
            GMSection("Exercícios") {
                ForEach(Array(current.items.enumerated()), id: \.offset) { i, item in
                    if i > 0 { GMDivider() }
                    HStack(spacing: 12) {
                        RoutineArt(exerciseID: item.exerciseID, size: 40)
                        Text(Exercise.name(item.exerciseID)).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(item.sets) × \(item.reps)\(Exercise.byID(item.exerciseID)?.type == .time || Exercise.byID(item.exerciseID)?.type == .distance ? " s" : "")")
                            .font(.subheadline.monospacedDigit()).foregroundStyle(Theme.dim)
                    }
                }
            }
            if current.authorID != "me" {
                HStack(spacing: 10) {
                    GMButton(store.liked.contains(current.id) ? "Curtida" : "Curtir", icon: store.liked.contains(current.id) ? "heart.fill" : "heart",
                             kind: .secondary) { Task { await store.toggleLike(current) } }
                    GMButton(saved ? "Salva nas suas rotinas" : "Salvar cópia", icon: saved ? "checkmark" : "square.and.arrow.down", enabled: !saved) {
                        Task { await store.saveCopy(current, context: context, order: order); saved = true }
                    }
                }
            }
        }
    }
}

/// Números da rotina: última vez, quantas vezes, tempo médio e as últimas 8 semanas
struct RoutineStatsSection: View {
    let routine: Routine
    @Query(filter: #Predicate<WorkoutSession> { $0.end != nil }, sort: \WorkoutSession.start) private var sessions: [WorkoutSession]

    var body: some View {
        let id = routine.uuid
        let done = sessions.filter { $0.routineUUID == id }
        if !done.isEmpty {
            let minutes = done.compactMap { s in s.end.map { Int($0.timeIntervalSince(s.start) / 60) } }
            let avg = minutes.isEmpty ? 0 : minutes.reduce(0, +) / minutes.count
            let cal = Calendar.current
            let weeks: [Int] = (0..<8).reversed().map { back in
                guard let w = cal.dateInterval(of: .weekOfYear, for: cal.date(byAdding: .weekOfYear, value: -back, to: .now)!) else { return 0 }
                return done.filter { w.contains($0.start) }.count
            }
            GMSection("Seus números com esta rotina") {
                HStack {
                    stat(done.last.map { shortAgo($0.start) } ?? "–", "última vez")
                    stat("\(done.count)×", "feita")
                    stat(durationText(avg), "tempo médio")
                }
                GMDivider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Últimas 8 semanas").font(.caption).foregroundStyle(Theme.dim)
                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(Array(weeks.enumerated()), id: \.offset) { _, n in
                            RoundedRectangle(cornerRadius: 3).fill(n > 0 ? Theme.accent : Theme.raised)
                                .frame(height: CGFloat(8 + min(n, 4) * 10))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 50, alignment: .bottom)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Últimas 8 semanas: " + weeks.map(String.init).joined(separator: ", "))
                }
            }
        }
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.headline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            Text(l).font(.caption).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity)
    }
}
