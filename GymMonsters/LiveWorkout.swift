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
                            CustomExercise.self, League.self, LeagueCheckIn.self, Monster.self, BodyEntry.self, ExerciseNote.self,
                            WodResult.self, RouteRecord.self, GymVisit.self, Gym.self)
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
        // No fim do descanso o conteúdo fica "velho" e o iOS redesenha mesmo com o app suspenso
        let content = ActivityContent(state: state, staleDate: state.restEnd)
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
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["rest"])
        // Notificação de fim de descanso é opcional (o Live Activity já mostra)
        guard UserDefaults.standard.bool(forKey: "restNotification") else { return }
        let content = UNMutableNotificationContent()
        content.title = "Descanso acabou"
        content.body = "Bora para a próxima série 💪"
        content.sound = .default
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

    /// "✓ Série feita": marca a próxima série do exercício atual e começa o descanso.
    /// Devolve a frase de confirmação (Siri, Botão de Ação, fone).
    @discardableResult
    static func completeNextSet() async -> String {
        guard let s = running(), let id = currentExercise(s) else { return "Nenhum treino em andamento." }
        let sets = s.orderedSets.filter { $0.exerciseID == id }
        guard let set = sets.first(where: { !$0.done }) else { return "\(Exercise.name(id)) já está completo." }
        set.done = true
        let number = (sets.firstIndex { $0 === set } ?? 0) + 1
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
        HeadphoneControl.shared.refresh()
        var msg = "\(Exercise.name(id)): série \(number) de \(sets.count) feita. Descanso de \(spoken(set.rest))."
        if sets.allSatisfy(\.done), let next = s.currentExerciseID, next != id { msg += " Próximo: \(Exercise.name(next))." }
        if s.sets.allSatisfy(\.done) { msg = "Última série feita! Treino completo, é só concluir no app." }
        return msg
    }

    @discardableResult
    static func skipRest() async -> String {
        guard let s = running() else { return "Nenhum treino em andamento." }
        cancelRest(s)
        try? AppData.container.mainContext.save()
        await refresh(s)
        HeadphoneControl.shared.refresh()
        let st = state(for: s)
        return st.exerciseDone ? "Descanso pulado." : "Bora: \(st.exercise), série \(st.setNumber) de \(st.setCount), \(st.setText)."
    }

    /// Tempo falado: "1 minuto e 30 segundos"
    static func spoken(_ seconds: Int) -> String {
        let m = seconds / 60, s = seconds % 60
        let mp = m == 0 ? "" : "\(m) minuto\(m == 1 ? "" : "s")"
        let sp = s == 0 ? "" : "\(s) segundos"
        return [mp, sp].filter { !$0.isEmpty }.joined(separator: " e ")
    }

    /// Encerra e salva o treino sem a tela de conclusão (ex.: ao sair da academia). Devolve o resumo.
    static func autoFinish(_ s: WorkoutSession, place: String?) async -> String {
        let ctx = AppData.container.mainContext
        cancelRest(s)
        await endAll()
        HeadphoneControl.shared.stop()
        let done = s.sets.filter(\.done)
        guard !done.isEmpty else {
            ctx.delete(s)
            try? ctx.save()
            return "Nenhuma série marcada, então o treino foi descartado."
        }
        let minutes = max(Int(Date.now.timeIntervalSince(s.start) / 60), 1)
        let activity = Activity(kind: .musculacao, date: s.start, minutes: minutes, effort: s.effort, note: s.title + (place.map { " · 📍 \($0)" } ?? ""))
        activity.gymUUID = s.gymUUID
        ctx.insert(activity)
        s.end = .now
        s.activityUUID = activity.uuid
        try? ctx.save()
        let xp = Game.xp(kind: .musculacao, minutes: minutes, effort: s.effort)
        return "\(s.title): \(durationText(minutes)), \(done.count) séries. +\(xp) XP pro seu bro."
    }

    /// Começa um treino (de rotina ou livre) já com as cargas sugeridas pelo histórico
    static func startSession(routine: Routine?) -> WorkoutSession {
        let ctx = AppData.container.mainContext
        let finished = (try? ctx.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.end != nil },
                                                                      sortBy: [SortDescriptor(\.start)]))) ?? []
        let history = finished.map(\.log)
        let session = WorkoutSession(title: routine?.name ?? "Treino livre", routineUUID: routine?.uuid)
        // Se já está num lugar conhecido (evento de chegada), usa ele
        if let g = GymLocation.shared.insideGym {
            session.gymUUID = g.uuid
            session.placeAsked = true
        }
        ctx.insert(session)
        for (i, item) in (routine?.sortedItems ?? []).enumerated() {
            let sug = Progression.suggest(exerciseID: item.exerciseID, sets: item.sets, reps: item.reps, history: history)
            for k in 0..<item.sets {
                session.sets.append(LoggedSet(exerciseID: item.exerciseID, exerciseOrder: i, index: k,
                                              weight: sug.weight, reps: sug.reps, rest: item.rest))
            }
        }
        try? ctx.save()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        GymLocation.shared.pendingArrival = nil
        return session
    }

    static var hasRunning: Bool { running() != nil }
    static var runningSession: WorkoutSession? { running() }
}

/// Live Activity do WOD em andamento
@MainActor
enum LiveWod {
    static func show(name: String, format: String, state: WodAttributes.ContentState) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let content = ActivityContent(state: state, staleDate: nil)
        if let a = ActivityKit.Activity<WodAttributes>.activities.first, a.attributes.name == name {
            await a.update(content)
            return
        }
        await end()
        _ = try? ActivityKit.Activity.request(attributes: WodAttributes(name: name, format: format), content: content, pushType: nil)
    }

    static func end() async {
        for a in ActivityKit.Activity<WodAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
    }
}

/// Rodadas do WOD, compartilhadas com o botão "+1 rodada" do Live Activity
@Observable
final class WodCounter {
    var rounds = 0
}
