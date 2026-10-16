import SwiftData
import SwiftUI

@main
struct GymMonstersApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        .modelContainer(for: [Activity.self, Routine.self, RoutineItem.self, WorkoutSession.self, LoggedSet.self, CustomExercise.self])
    }
}

struct RootView: View {
    @AppStorage("trainerName") private var trainerName = ""

    var body: some View {
        if trainerName.isEmpty {
            OnboardingView()
        } else {
            MainView()
        }
    }
}

struct EvolutionEvent: Identifiable {
    let from: MonsterForm
    let to: MonsterForm
    var id: String { from.id + to.id }
}

struct MainView: View {
    @Query(sort: \Activity.date, order: .reverse) private var activities: [Activity]
    @Query private var customs: [CustomExercise]
    @AppStorage("lastFormID") private var lastFormID = ""
    @AppStorage("discovered") private var discovered = ""
    @State private var evolution: EvolutionEvent?
    @State private var healthNotice: String?
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase

    private var snapshot: Snapshot { Game.snapshot(activities.map(\.record)) }

    var body: some View {
        let s = snapshot
        let _ = Exercise.register(customs)
        TabView {
            HomeView(snapshot: s, activities: activities)
                .tabItem { Label("Monstro", systemImage: "pawprint.fill") }
            TrainView()
                .tabItem { Label("Treino", systemImage: "dumbbell.fill") }
            HistoryView(snapshot: s, activities: activities)
                .tabItem { Label("Histórico", systemImage: "list.bullet") }
            DexView(snapshot: s, discovered: Set(discovered.split(separator: ",").map(String.init)))
                .tabItem { Label("Dex", systemImage: "square.grid.3x3.fill") }
        }
        .task(id: s.form.id) { check(s) }
        .task(id: phase) { if phase == .active { await syncHealth() } }
        .overlay(alignment: .top) {
            if let healthNotice {
                Label(healthNotice, systemImage: "heart.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: .capsule)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { withAnimation { self.healthNotice = nil } }
            }
        }
        .fullScreenCover(item: $evolution) { e in
            EvolutionView(from: e.from, to: e.to) { evolution = nil }
        }
    }

    private func syncHealth() async {
        guard HealthSync.enabled else { return }
        guard let r = try? await HealthSync.sync(context: context), !r.imported.isEmpty else { return }
        let snap = Game.snapshot(activities.map(\.record))
        let xp = r.imported.reduce(0) { $0 + (snap.xpByActivity[$1.uuid] ?? 0) }
        let n = r.imported.count
        withAnimation { healthNotice = "\(n) treino\(n == 1 ? "" : "s") do Saúde · +\(xp) XP" }
        try? await Task.sleep(for: .seconds(4))
        withAnimation { healthNotice = nil }
    }

    private func check(_ s: Snapshot) {
        var seen = Set(discovered.split(separator: ",").map(String.init))
        seen.insert(MonsterForm.egg.id)
        seen.formUnion(s.evolutions.map(\.form.id))
        discovered = seen.sorted().joined(separator: ",")

        let old = MonsterForm.byID(lastFormID) ?? .egg
        if old != s.form, s.form.stage > old.stage {
            evolution = EvolutionEvent(from: old, to: s.form)
        }
        lastFormID = s.form.id
    }
}
