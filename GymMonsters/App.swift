import MuscleMap
import SwiftData
import SwiftUI
import WidgetKit

@main
struct GymMonstersApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        .modelContainer(for: [Activity.self, Routine.self, RoutineItem.self, WorkoutSession.self, LoggedSet.self, CustomExercise.self, League.self, LeagueCheckIn.self])
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

struct Banner: Equatable {
    let symbol: String
    let text: String
}

struct MainView: View {
    @Query(sort: \Activity.date, order: .reverse) private var activities: [Activity]
    @Query private var customs: [CustomExercise]
    @Query(sort: \Routine.order) private var routines: [Routine]
    @Query(filter: #Predicate<WorkoutSession> { $0.end != nil }, sort: \WorkoutSession.start) private var sessions: [WorkoutSession]
    @AppStorage("lastFormID") private var lastFormID = ""
    @AppStorage("discovered") private var discovered = ""
    @AppStorage("achievementsSeen") private var achievementsSeen = ""
    @AppStorage("trainerName") private var trainerName = ""
    @AppStorage("monsterNick") private var monsterNick = ""
    @AppStorage("remindersOn") private var remindersOn = false
    @AppStorage("reminderMinute") private var reminderMinute = 18 * 60
    @AppStorage("reminderRoutineOnly") private var reminderRoutineOnly = false
    @State private var evolution: EvolutionEvent?
    @State private var banner: Banner?
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase

    var body: some View {
        let s = Game.snapshot(activities.map(\.record))
        let _ = Exercise.register(customs)
        let logs = sessions.map(\.log)
        let achievements = Achievements.evaluate(.init(activities: activities.map(\.record),
                                                       fromHealth: activities.filter { $0.healthUUID != nil }.count,
                                                       snapshot: s, sessions: logs))
        let companion = companionContext(s, logs: logs)
        TabView {
            HomeView(snapshot: s, activities: activities, mood: companion.mood, line: Companion.line(companion))
                .tabItem { Label("Monstro", systemImage: "pawprint.fill") }
            TrainView()
                .tabItem { Label("Treino", systemImage: "dumbbell.fill") }
            LeaguesView()
                .tabItem { Label("Ligas", systemImage: "trophy.fill") }
            HistoryView(snapshot: s, activities: activities)
                .tabItem { Label("Histórico", systemImage: "list.bullet") }
            DexView(snapshot: s, discovered: Set(discovered.split(separator: ",").map(String.init)), achievements: achievements)
                .tabItem { Label("Dex", systemImage: "square.grid.3x3.fill") }
        }
        .task(id: s.form.id) { check(s) }
        .task(id: phase) { if phase == .active { await syncHealth() } }
        .task(id: achievements.filter(\.unlocked).map(\.id)) { announce(achievements) }
        // Widget e lembretes acompanham qualquer mudança relevante
        .task(id: "\(s.totalXP)|\(s.lastActivity?.timeIntervalSince1970 ?? 0)|\(routineKey)|\(remindersOn)|\(reminderMinute)|\(reminderRoutineOnly)|\(monsterNick)|\(phase == .active)") {
            publish(s, companion: companion)
        }
        .overlay(alignment: .top) {
            if let banner {
                Label(banner.text, systemImage: banner.symbol)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: .capsule)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { withAnimation { self.banner = nil } }
            }
        }
        .fullScreenCover(item: $evolution) { e in
            EvolutionView(from: e.from, to: e.to) { evolution = nil }
        }
    }

    private var routineKey: String { routines.map { "\($0.name)\($0.weekdaysRaw)" }.joined() }

    private var routinesByWeekday: [Int: String] {
        var out: [Int: String] = [:]
        for r in routines {
            for d in r.weekdays where out[d] == nil { out[d] = r.name }
        }
        return out
    }

    private func companionContext(_ s: Snapshot, logs: [SessionLog]) -> Companion.Context {
        let cal = Calendar.current
        let trainedToday = activities.contains { cal.isDateInToday($0.date) }
        let away = s.lastActivity.map { cal.dateComponents([.day], from: cal.startOfDay(for: $0), to: cal.startOfDay(for: .now)).day ?? 0 } ?? 0
        let weekAgo = Date.now.addingTimeInterval(-7 * 86400)
        let recent = logs.filter { $0.date >= weekAgo }
        // Só sugere músculos esquecidos para quem já usa o treino guiado
        let main: [Muscle] = [.quadriceps, .upperBack, .chest, .deltoids, .hamstring, .gluteal, .biceps, .triceps, .abs, .calves]
        let hit = Set(muscleLoad(recent.flatMap(\.sets)).keys)
        let neglected = logs.isEmpty ? [] : main.filter { !hit.contains($0) }
        let mood = Mood.of(isEgg: s.stage == .egg, lastActivity: s.lastActivity, todayXP: s.todayXP, streak: s.streak)
        return Companion.Context(name: monsterNick.isEmpty ? s.form.name : monsterNick, mood: mood, snapshot: s,
                                 trainedToday: trainedToday, todayRoutine: routinesByWeekday[cal.component(.weekday, from: .now)],
                                 neglected: neglected, daysAway: away)
    }

    private func publish(_ s: Snapshot, companion: Companion.Context) {
        WidgetData(monsterName: s.stage == .egg || monsterNick.isEmpty ? s.form.name : monsterNick,
                   formName: s.form.name, stageName: s.stage.name, sprite: s.form.sprite, hue: s.form.hue,
                   isEgg: s.stage == .egg, level: s.level, totalXP: s.totalXP, progress: s.progress, xpToNext: s.xpToNext,
                   streak: s.streak, lastActivity: s.lastActivity, todayXP: s.todayXP, todayRoutine: routinesByWeekday,
                   updated: .now).save()
        WidgetBridge.reload()
        Reminders.schedule(enabled: remindersOn, minuteOfDay: reminderMinute, onlyRoutineDays: reminderRoutineOnly,
                           routines: routinesByWeekday, name: companion.name, streak: s.streak,
                           trainedToday: companion.trainedToday, isEgg: s.stage == .egg)
    }

    private func announce(_ list: [Achievement]) {
        let seen = Set(achievementsSeen.split(separator: ",").map(String.init))
        let new = list.filter { $0.unlocked && !seen.contains($0.id) }
        guard !new.isEmpty else { return }
        achievementsSeen = (seen.union(new.map(\.id))).sorted().joined(separator: ",")
        let text = new.count == 1 ? "Conquista: \(new[0].title)" : "\(new.count) conquistas novas!"
        show(Banner(symbol: "trophy.fill", text: text))
    }

    private func show(_ b: Banner) {
        withAnimation { banner = b }
        Task {
            try? await Task.sleep(for: .seconds(4))
            withAnimation { if banner == b { banner = nil } }
        }
    }

    private func syncHealth() async {
        guard HealthSync.enabled else { return }
        guard let r = try? await HealthSync.sync(context: context), !r.imported.isEmpty else { return }
        let snap = Game.snapshot(activities.map(\.record))
        let xp = r.imported.reduce(0) { $0 + (snap.xpByActivity[$1.uuid] ?? 0) }
        let n = r.imported.count
        show(Banner(symbol: "heart.fill", text: "\(n) treino\(n == 1 ? "" : "s") do Saúde · +\(xp) XP"))
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

enum WidgetBridge {
    static func reload() { WidgetCenter.shared.reloadAllTimelines() }
}
