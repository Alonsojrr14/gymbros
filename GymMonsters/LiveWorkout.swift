import ActivityKit
import Foundation
import SwiftData
import UIKit
import UserNotifications

/// Container único do app, compartilhado com os botões do Live Activity (que rodam no processo do app)
@MainActor
enum AppData {
    static let container: ModelContainer = {
        try! ModelContainer(for: Activity.self, Routine.self, RoutineItem.self, WorkoutSession.self, LoggedSet.self,
                            CustomExercise.self, League.self, LeagueCheckIn.self, Monster.self, BodyEntry.self, ExerciseNote.self)
    }()
}

/// Treino em andamento: séries, descanso e o Live Activity (tela de bloqueio e Dynamic Island)
@MainActor
enum LiveWorkout {
    private static var current: ActivityKit.Activity<WorkoutAttributes>? {
        ActivityKit.Activity<WorkoutAttributes>.activities.first
    }

    static var enabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    // MARK: Estado

    /// Exercício "fazendo agora": o marcado, ou o primeiro que ainda tem série a fazer
    static func currentExercise(_ s: WorkoutSession) -> String? {
        let ids = s.exerciseIDs
        if let c = s.currentExerciseID, ids.contains(c) { return c }
        return ids.first { id in !s.orderedSets.filter { $0.exerciseID == id }.allSatisfy(\.done) } ?? ids.last
    }

    static func state(for s: WorkoutSession) -> WorkoutAttributes.ContentState {
        let cur = currentExercise(s)
        let sets = cur.map { id in s.orderedSets.filter { $0.exerciseID == id } } ?? []
        let next = sets.firstIndex { !$0.done }
        return WorkoutAttributes.ContentState(
            exercise: cur.map(Exercise.name) ?? "Treino livre",
            setNumber: (next ?? sets.count) + 1,
            setCount: sets.count,
            setText: next.map { setText(sets[$0]) } ?? "",
            doneSets: s.sets.filter(\.done).count,
            totalSets: s.sets.count,
            restEnd: s.restEnd.flatMap { $0 > .now ? $0 : nil },
            sprite: WidgetData.load()?.sprite ?? "sprite_baby"
        )
    }

    // MARK: Live Activity

    static func refresh(_ s: WorkoutSession) async {
        await show(title: s.title, start: s.start, state: state(for: s))
    }

    /// Começa (ou atualiza, se já existe) o Live Activity do treino
    static func show(title: String, start: Date, state: WorkoutAttributes.ContentState) async {
        guard enabled else { return }
        let content = ActivityContent(state: state, staleDate: nil)
        if let activity = current, activity.attributes.start == start {
            await activity.update(content)
            return
        }
        // Outro treino ainda aparecendo: encerra antes de começar este
        await endAll()
        _ = try? ActivityKit.Activity.request(attributes: WorkoutAttributes(title: title, start: start), content: content, pushType: nil)
    }

    static func endAll() async {
        for a in ActivityKit.Activity<WorkoutAttributes>.activities {
            await a.end(nil, dismissalPolicy: .immediate)
        }
    }

    // MARK: Descanso

    static func startRest(_ s: WorkoutSession, seconds: Int, keepTotal: Bool = false) {
        guard seconds > 0 else { return }
        s.restEnd = Date.now.addingTimeInterval(TimeInterval(seconds))
        s.restTotal = keepTotal ? max(s.restTotal, seconds) : seconds
        // Aviso mesmo com o app em segundo plano
        let content = UNMutableNotificationContent()
        content.title = "Descanso acabou"
        content.body = "Bora para a próxima série 💪"
        content.sound = .default
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["rest"])
        center.add(UNNotificationRequest(identifier: "rest", content: content,
                                         trigger: UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)))
    }

    static func cancelRest(_ s: WorkoutSession) {
        s.restEnd = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["rest"])
    }

    // MARK: Botões do Live Activity

    private static func running() -> WorkoutSession? {
        let ctx = AppData.container.mainContext
        return try? ctx.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.end == nil },
                                                              sortBy: [SortDescriptor(\.start, order: .reverse)])).first
    }

    /// "✓ Série feita": marca a próxima série do exercício atual e começa o descanso
    static func completeNextSet() async {
        guard let s = running(), let id = currentExercise(s) else { return }
        let sets = s.orderedSets.filter { $0.exerciseID == id }
        guard let set = sets.first(where: { !$0.done }) else { return }
        set.done = true
        // Exercício terminado: o próximo que falta vira o atual
        if sets.allSatisfy(\.done) {
            let ids = s.exerciseIDs
            if let i = ids.firstIndex(of: id) {
                s.currentExerciseID = (ids[(i + 1)...] + ids[..<i]).first { e in
                    !s.orderedSets.filter { $0.exerciseID == e }.allSatisfy(\.done)
                } ?? id
            }
        }
        startRest(s, seconds: set.rest)
        try? AppData.container.mainContext.save()
        await refresh(s)
    }

    static func skipRest() async {
        guard let s = running() else { return }
        cancelRest(s)
        try? AppData.container.mainContext.save()
        await refresh(s)
    }
}
