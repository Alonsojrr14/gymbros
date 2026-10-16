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
        .modelContainer(for: Activity.self)
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
    @AppStorage("lastFormID") private var lastFormID = ""
    @AppStorage("discovered") private var discovered = ""
    @State private var evolution: EvolutionEvent?

    private var snapshot: Snapshot { Game.snapshot(activities.map(\.record)) }

    var body: some View {
        let s = snapshot
        TabView {
            HomeView(snapshot: s, activities: activities)
                .tabItem { Label("Monstro", systemImage: "pawprint.fill") }
            HistoryView(snapshot: s, activities: activities)
                .tabItem { Label("Histórico", systemImage: "list.bullet") }
            DexView(snapshot: s, discovered: Set(discovered.split(separator: ",").map(String.init)))
                .tabItem { Label("Dex", systemImage: "square.grid.3x3.fill") }
        }
        .task(id: s.form.id) { check(s) }
        .fullScreenCover(item: $evolution) { e in
            EvolutionView(from: e.from, to: e.to) { evolution = nil }
        }
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
