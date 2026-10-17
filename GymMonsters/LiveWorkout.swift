import ActivityKit
import Foundation
import SwiftData
import UIKit
import UserNotifications

/// Container único do app, compartilhado com os botões do Live Activity (que rodam no processo do app)
@MainActor
enum AppData {
    static let schema = Schema([Activity.self, Routine.self, RoutineItem.self, WorkoutSession.self, LoggedSet.self,
                                CustomExercise.self, League.self, LeagueCheckIn.self, Monster.self, BodyEntry.self, ExerciseNote.self,
                                WodResult.self, RouteRecord.self, GymVisit.self, Gym.self, CheckInComment.self, PersonalRecord.self,
                                LeagueMessage.self])

    /// Cópia do banco que não abriu (migração que falhou); o app começa com um banco novo em vez de fechar ao abrir
    private(set) static var recoveredCopy: URL?

    static let container: ModelContainer = {
        let config = ModelConfiguration(schema: schema)
        if let c = try? ModelContainer(for: schema, configurations: config) {
            protect(config.url)
            return c
        }
        recoveredCopy = setAside(config.url)
        if let c = try? ModelContainer(for: schema, configurations: config) {
            protect(config.url)
            return c
        }
        // Último recurso: roda sem gravar, mas abre
        return try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
    }()

    /// Arquivos do SQLite: o banco e os auxiliares do journal
    private static func files(_ url: URL) -> [URL] {
        [url, URL(fileURLWithPath: url.path + "-wal"), URL(fileURLWithPath: url.path + "-shm")]
    }

    /// Dados de saúde e localização: só legíveis depois do primeiro desbloqueio do aparelho
    private static func protect(_ url: URL) {
        for f in files(url) where FileManager.default.fileExists(atPath: f.path) {
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: f.path)
        }
    }

    /// Move o banco com problema para o lado (ex.: default-erro-1760000000.store), sem apagar nada
    private static func setAside(_ url: URL) -> URL? {
        let stamp = Int(Date.now.timeIntervalSince1970)
        let base = url.deletingPathExtension().lastPathComponent
        let dest = url.deletingLastPathComponent().appendingPathComponent("\(base)-erro-\(stamp).\(url.pathExtension)")
        var moved = false
        for (from, to) in zip(files(url), files(dest)) where FileManager.default.fileExists(atPath: from.path) {
            moved = (try? FileManager.default.moveItem(at: from, to: to)) != nil || moved
        }
        return moved ? dest : nil
    }
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
            setText: next.map { (sets[$0].warmup ? "Aquecimento · " : "") + setText(sets[$0]) } ?? "",
            // Totais só com séries de trabalho, como na conclusão (aquecimento fica de fora)
            doneSets: s.doneWorkSets.count,
            totalSets: s.workSets.count,
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
        // Número entre as séries do mesmo tipo (trabalho ou aquecimento), como na tela
        let same = sets.filter { $0.warmup == set.warmup }
        let number = (same.firstIndex { $0 === set } ?? 0) + 1
        // Superset passa direto para o próximo do bloco; senão descansa e, se acabou, vai para o próximo exercício
        let rest = s.advance(after: id)
        if rest { startRest(s, seconds: set.rest) } else { cancelRest(s) }
        try? AppData.container.mainContext.save()
        await refresh(s)
        HeadphoneControl.shared.refresh()
        var msg = "\(Exercise.name(id)): \(set.warmup ? "aquecimento" : "série \(number) de \(same.count)") feita." + (rest ? " Descanso de \(spoken(set.rest))." : "")
        if let next = s.currentExerciseID, next != id { msg += rest ? " Próximo: \(Exercise.name(next))." : " Superset: agora \(Exercise.name(next))." }
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
    /// Faz o mesmo que o "Salvar" da conclusão com os padrões dela: posta no perfil e nas ligas ativas, com os recordes;
    /// o esforço é a média dos últimos treinos; mudança na rotina vira oferta pendente na aba Treino.
    static func autoFinish(_ s: WorkoutSession, place: String?) async -> String {
        let ctx = AppData.container.mainContext
        cancelRest(s)
        await endAll()
        HeadphoneControl.shared.stop()
        // Como na conclusão: só série de trabalho conta (só aquecimento não salva)
        let done = s.doneWorkSets
        guard !done.isEmpty else {
            ctx.delete(s)
            try? ctx.save()
            return "Nenhuma série marcada, então o treino foi descartado."
        }
        let finished = (try? ctx.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.end != nil },
                                                                      sortBy: [SortDescriptor(\.start)]))) ?? []
        let efforts = ((try? ctx.fetch(FetchDescriptor<Activity>(sortBy: [SortDescriptor(\.date)]))) ?? [])
            .filter { $0.kind == .musculacao }.map(\.effort)
        let effort = Progression.estimatedEffort(recent: efforts)
        let minutes = max(Int(Date.now.timeIntervalSince(s.start) / 60), 1)
        let activity = Activity(kind: .musculacao, date: s.start, minutes: minutes, effort: effort, note: s.title + (place.map { " · 📍 \($0)" } ?? ""))
        activity.gymUUID = s.gymUUID
        ctx.insert(activity)
        // Mesmo destino padrão da conclusão: perfil e ligas em andamento, com os recordes no texto
        let records = Progression.records(in: s.log, history: finished.map(\.log))
        let leagues = ((try? ctx.fetch(FetchDescriptor<League>())) ?? []).filter { !$0.isOver && $0.hasStarted }
        postCheckIns(activity: activity, leagues: Set(leagues.map(\.uuid)).union([ProfileFeed.id]), title: s.title,
                     note: records.isEmpty ? "" : "🏆 " + records.joined(separator: " · "), photo: nil, context: ctx)
        s.end = .now
        s.effort = effort
        s.activityUUID = activity.uuid
        // Não dá para perguntar agora: guarda a oferta de atualizar a rotina para a aba Treino
        var routineNote = ""
        if let id = s.routineUUID,
           let r = try? ctx.fetch(FetchDescriptor<Routine>(predicate: #Predicate { $0.uuid == id })).first,
           !s.routineChanges(r).isEmpty {
            PendingRoutineUpdate.sessionUUID = s.uuid
            routineNote = " A rotina \(r.name) mudou: abra a aba Treino para atualizar."
        }
        try? ctx.save()
        let xp = Game.xp(kind: .musculacao, minutes: minutes, effort: effort)
        return "\(s.title): \(durationText(minutes)), \(done.count) séries. +\(xp) XP pro seu bro." + routineNote
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
        let deload = Deload.active
        session.isDeload = deload
        // Ligado por padrão; `bool` também lê o "1"/"0" que a restauração do backup grava como texto
        let autoWarmup = UserDefaults.standard.object(forKey: "autoWarmup") == nil || UserDefaults.standard.bool(forKey: "autoWarmup")
        var warmedUp = false
        for (i, item) in (routine?.sortedItems ?? []).enumerated() {
            var sug = Progression.suggest(exerciseID: item.exerciseID, sets: item.sets, reps: item.reps, history: history)
            // Séries pesadas pelo histórico (a rampa feita à mão não conta como trabalho)
            var count = sug.sets ?? item.sets
            let ramp = sug.ramp
            // Deload: 70 % da carga e um terço a menos de séries
            if deload { (sug, count) = Deload.apply(sug, sets: count, exerciseID: item.exerciseID) }
            var k = 0
            func warm(_ w: Double, _ reps: Int) {
                let set = LoggedSet(exerciseID: item.exerciseID, exerciseOrder: i, index: k, weight: w, reps: reps, rest: 60)
                set.warmup = true
                session.sets.append(set)
                k += 1
            }
            // Aquecimento automático no primeiro exercício com carga; ele substitui a rampa feita à mão (não soma)
            if autoWarmup, !warmedUp, let ex = Exercise.byID(item.exerciseID), ex.type == .weighted, sug.weight >= 20 {
                warmedUp = true
                for w in Progression.warmup(work: sug.weight, increment: ex.increment, minimum: ex.usesBar && ex.weightIncludesBar ? 20 : 0) {
                    warm(w.weight, w.reps)
                }
            } else {
                // Sua rampa da última vez volta como aquecimento (fica de fora de volume e progressão)
                for r in ramp where r.weight < sug.weight { warm(r.weight, r.reps) }
            }
            for _ in 0..<count {
                session.sets.append(LoggedSet(exerciseID: item.exerciseID, exerciseOrder: i, index: k,
                                              weight: sug.weight, reps: sug.reps, rest: item.rest))
                k += 1
            }
            if item.supersetNext { session.setLinkedNext(item.exerciseID, true) }
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
