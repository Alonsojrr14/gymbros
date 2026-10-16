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
        .modelContainer(for: [Activity.self, Routine.self, RoutineItem.self, WorkoutSession.self, LoggedSet.self, CustomExercise.self, League.self, LeagueCheckIn.self, Monster.self])
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
    @Query(sort: \Monster.createdAt) private var monsters: [Monster]
    @Query private var checkIns: [LeagueCheckIn]
    @Query private var leagues: [League]
    @AppStorage("discovered") private var discovered = ""
    @AppStorage("achievementsSeen") private var achievementsSeen = ""
    @AppStorage("trainerName") private var trainerName = ""
    @AppStorage("remindersOn") private var remindersOn = false
    @AppStorage("reminderMinute") private var reminderMinute = 18 * 60
    @AppStorage("reminderRoutineOnly") private var reminderRoutineOnly = false
    @State private var evolution: EvolutionEvent?
    @State private var banner: Banner?
    @State private var tab = 0
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase

    var body: some View {
        let d = derive()
        let roster = d.roster, s = d.main, history = d.history, mainName = d.mainName
        let _ = Exercise.register(customs)
        let logs = sessions.map(\.log)
        let achievements = Achievements.evaluate(.init(activities: activities.map(\.record),
                                                       fromHealth: activities.filter { $0.healthUUID != nil }.count,
                                                       snapshot: d.best, sessions: logs))
        let companion = companionContext(s, logs: logs, name: mainName)
        TabView(selection: $tab) {
            HomeView(snapshot: s, activities: activities, mood: companion.mood, line: Companion.line(companion), monsterName: mainName)
                .tag(0).toolbar(.hidden, for: .tabBar)
            TrainView()
                .tag(1).toolbar(.hidden, for: .tabBar)
            LeaguesView()
                .tag(2).toolbar(.hidden, for: .tabBar)
            HistoryView(snapshot: history, activities: activities)
                .tag(3).toolbar(.hidden, for: .tabBar)
            DexView(snapshot: s, discovered: Set(discovered.split(separator: ",").map(String.init)), achievements: achievements)
                .tag(4).toolbar(.hidden, for: .tabBar)
        }
        .overlay(alignment: .bottom) {
            GMTabBar(items: [
                GMTabItem(icon: "pawprint.fill", title: "Monstro"),
                GMTabItem(icon: "dumbbell.fill", title: "Treino"),
                GMTabItem(icon: "trophy.fill", title: "Ligas"),
                GMTabItem(icon: "list.bullet", title: "Histórico"),
                GMTabItem(icon: "square.grid.3x3.fill", title: "Dex"),
            ], selection: $tab)
            .ignoresSafeArea(.keyboard)
        }
        .task { Roster.ensureStarter(context: context) }
        .task(id: monsters.map { roster.snapshot($0.uuid).form.id + $0.uuid.uuidString }.joined()) { check(roster) }
        .task(id: phase) { if phase == .active { await syncHealth() } }
        .task(id: achievements.filter(\.unlocked).map(\.id)) { announce(achievements) }
        // Widget e lembretes acompanham qualquer mudança relevante
        .task(id: "\(s.totalXP)|\(s.lastActivity?.timeIntervalSince1970 ?? 0)|\(routineKey)|\(remindersOn)|\(reminderMinute)|\(reminderRoutineOnly)|\(mainName)|\(phase == .active)") {
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

    private struct Derived {
        let roster: Roster
        /// Monstro principal, com sequência e humor do jogador (que contam todas as atividades)
        let main: Snapshot
        /// Para conquistas: estágio do monstro mais evoluído
        let best: Snapshot
        /// Para o histórico: XP de cada atividade no monstro que a recebeu
        let history: Snapshot
        let mainName: String
    }

    private func derive() -> Derived {
        let roster = Roster(monsters: monsters, activities: activities, checkIns: checkIns, leagues: leagues)
        let player = Game.snapshot(activities.map(\.record))
        var main = roster.mainSnapshot
        main.streak = player.streak
        main.bestStreak = player.bestStreak
        main.lastActivity = player.lastActivity
        main.todayXP = player.todayXP
        var best = player
        best.form = roster.snapshots.values.map(\.form).max { $0.stage < $1.stage } ?? .egg
        var history = player
        history.xpByActivity = roster.xpByActivity
        return Derived(roster: roster, main: main, best: best, history: history,
                       mainName: roster.main?.displayName(main.form) ?? main.form.name)
    }

    private var routineKey: String { routines.map { "\($0.name)\($0.weekdaysRaw)" }.joined() }

    private var routinesByWeekday: [Int: String] {
        var out: [Int: String] = [:]
        for r in routines {
            for d in r.weekdays where out[d] == nil { out[d] = r.name }
        }
        return out
    }

    private func companionContext(_ s: Snapshot, logs: [SessionLog], name: String) -> Companion.Context {
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
        return Companion.Context(name: name, mood: mood, snapshot: s,
                                 trainedToday: trainedToday, todayRoutine: routinesByWeekday[cal.component(.weekday, from: .now)],
                                 neglected: neglected, daysAway: away)
    }

    private func publish(_ s: Snapshot, companion: Companion.Context) {
        WidgetData(monsterName: companion.name,
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

    /// Descobertas da Dex e cena de evolução, para qualquer monstro da coleção
    private func check(_ roster: Roster) {
        guard !monsters.isEmpty else { return }
        var seen = Set(discovered.split(separator: ",").map(String.init))
        seen.insert(MonsterForm.egg.id)
        for snap in roster.snapshots.values { seen.formUnion(snap.evolutions.map(\.form.id)) }
        discovered = seen.sorted().joined(separator: ",")

        for m in monsters {
            let form = roster.snapshot(m.uuid).form
            let old = MonsterForm.byID(m.lastFormID) ?? .egg
            if old != form, form.stage > old.stage, evolution == nil {
                evolution = EvolutionEvent(from: old, to: form)
            }
            m.lastFormID = form.id
        }
        try? context.save()
    }
}

enum WidgetBridge {
    static func reload() { WidgetCenter.shared.reloadAllTimelines() }
}
