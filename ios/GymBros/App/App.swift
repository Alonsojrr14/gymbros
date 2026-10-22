import MuscleMap
import SwiftData
import SwiftUI
import WidgetKit

/// O app está aberto como hospedeiro dos testes (XCTest)
enum AppRuntime {
    static let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}

@main
struct GymBrosApp: App {
    init() {
        // Fotos dos exercícios ficam guardadas depois da primeira vez (funcionam sem internet)
        URLCache.shared = URLCache(memoryCapacity: 40 * 1024 * 1024, diskCapacity: 300 * 1024 * 1024)
        WorkoutIntentBridge.completeSet = { await LiveWorkout.completeNextSet() }
        WorkoutIntentBridge.skipRest = { await LiveWorkout.skipRest() }
        // Rodando os testes no iPhone, o app é só o hospedeiro: não abre telas nem fala com relógio e localização,
        // para os testes (que zeram chaves como as das trocas) não mexerem nos seus bros de verdade
        guard !AppRuntime.isTesting else { Backend.install(); return }
        WatchBridge.shared.activate()
        MirroredWorkout.shared.install()
        _ = WodRun.shared
        GymBrosShortcuts.updateAppShortcutParameters()
        NotificationRouter.shared.install()
        GymLocation.shared.startMonitoring()
        PRBook.reload()
        // Mock ou CloudKit (Backend.mode)
        Backend.install()
        #if DEBUG
        OnboardingCoordinator.shared.applyLaunchArguments()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if AppRuntime.isTesting {
                    // Hospedeiro dos testes: nada de RootView (ela grava a forma de cada bro e sincroniza)
                    Color.black
                } else {
                    #if DEBUG
                    if UserDefaults.standard.bool(forKey: "demoTradeScene") { TradeSceneDemo() } else { RootView() }
                    #else
                    RootView()
                    #endif
                }
            }
                .onAppear { GMKeyboardDismisser.shared.install() }
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        .modelContainer(AppData.container)
    }
}

/// A conta vem antes de tudo: os dados no aparelho são sempre os da conta que entrou (AccountSync)
struct RootView: View {
    @AppStorage("trainerName") private var trainerName = ""
    @AppStorage(Terms.acceptedKey) private var acceptedTerms = 0
    @State private var auth = AuthStore.shared
    @State private var sync = AccountSync.shared
    @Environment(\.scenePhase) private var phase

    var body: some View {
        Group {
            if !auth.isSignedIn {
                LoginView(required: true)
            } else if !sync.isReady(for: auth.user?.id) {
                AccountLoadingView()
            } else if trainerName.isEmpty {
                OnboardingView()
            } else if acceptedTerms < Terms.version {
                // Conta que já tinha ovo, entrou de novo ou termos com versão nova: aceite antes de entrar
                TermsRequiredView()
            } else {
                MainView()
            }
        }
        // Login, logout e troca de conta: as roles da sessão anterior deixam de valer na hora
        .task(id: auth.user?.id) {
            await AccessStore.shared.refresh()
            try? await sync.finishPendingDeletion()
            if let user = auth.user { await sync.enter(user) }
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave).receive(on: DispatchQueue.main)) { _ in
            sync.scheduleUpload()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).receive(on: DispatchQueue.main)) { _ in
            sync.scheduleUpload()
        }
        .onChange(of: phase) { _, p in if p == .background { sync.uploadInBackground() } }
    }
}

struct EvolutionEvent: Identifiable {
    let monster: UUID
    let from: MonsterForm
    let to: MonsterForm
    var id: String { monster.uuidString + from.id + to.id }
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
    @AppStorage("weeklySummary") private var weeklySummary = true
    @AppStorage(NotificationPrefs.pausedKey) private var notificationsPaused = false
    @State private var inbox = InboxStore.shared
    /// Observado só para redesenhar quando "Tornar principal" muda o principal
    @AppStorage(MainMonster.key) private var mainMonster = ""
    /// Fila de cenas: dois bros evoluindo juntos aparecem um depois do outro
    @State private var evolutions: [EvolutionEvent] = []
    @State private var banner: Banner?
    @State private var tab = 0
    @State private var visited: Set<Int> = [0]
    @State private var arrivalPrompt = false
    @State private var recovered = AppData.recoveredCopy != nil
    /// O BroBook abre pela tela do bro (saiu da barra para o bro ficar no centro)
    @State private var dex = false
    @State private var tour = OnboardingCoordinator.shared
    @State private var watchWorkout = MirroredWorkout.shared
    @State private var trades = TradeStore.shared
    @State private var asking = false
    @State private var whatsNew = false
    /// Código de amigo vindo de um QR ou link, esperando você confirmar
    @State private var friendLink: String?
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase

    var body: some View {
        let d = derive()
        let roster = d.roster, s = d.main, history = d.history, mainName = d.mainName
        let _ = Exercise.register(customs)
        let logs = sessions.map(\.log)
        let hatched = roster.snapshots.values.filter { $0.stage > .egg }
        let achievements = Achievements.evaluate(.init(activities: activities.map(\.record),
                                                       fromHealth: activities.filter { $0.healthUUID != nil }.count,
                                                       snapshot: d.best, sessions: logs,
                                                       species: Set(hatched.map(\.form.species)).count,
                                                       ultimates: hatched.filter { $0.stage == .ultimate }.count,
                                                       discovered: discovered.split(separator: ",").count,
                                                       dexTotal: DexView.allForms.count))
        let companion = companionContext(s, logs: logs, name: mainName)
        // Abas próprias: o TabView do iOS joga da 5ª aba em diante num menu "Mais" com seta de voltar.
        // Cada aba é criada na primeira visita e fica viva (guarda rolagem e navegação).
        ZStack {
            page(0) { HomeView(snapshot: s, activities: activities, history: history, mood: companion.mood, line: Companion.line(companion), monsterName: mainName) { dex = true } }
            page(1) { TrainView() }
            page(2) { LeaguesView() }
            page(3) { MapScreen() }
            page(4) { NavigationStack { UnifiedFeedView(isTab: true) } }
        }
        .onChange(of: tab, initial: true) { _, t in
            visited.insert(t)
            tour.tabDidChange(to: MainTab(rawValue: t))
        }
        .overlay(alignment: .bottom) {
            GMTabBar(left: [GMTabItem(icon: "rectangle.stack.fill", title: "Feed", tag: 4, spotlight: .feedTab),
                            GMTabItem(icon: "dumbbell.fill", title: "Treino", tag: 1, spotlight: .trainTab)],
                     right: [GMTabItem(icon: "trophy.fill", title: "Ligas", tag: 2, spotlight: .leaguesTab),
                             GMTabItem(icon: "map.fill", title: "Mapa", tag: 3, badge: FriendsLive.liveCount,
                                       spotlight: .mapTab)],
                     centerTag: 0, selection: $tab, centerSpotlight: .broTab) {
                MonsterSprite(form: s.form)
            }
            .ignoresSafeArea(.keyboard)
        }
        .gmModal(isPresented: $dex) {
            DexView(snapshot: s, discovered: Set(discovered.split(separator: ",").map(String.init)), achievements: achievements, modal: true)
        }
        .task { Roster.ensureStarter(context: context) }
        .task(id: monsters.map { roster.snapshot($0.uuid).form.id + $0.uuid.uuidString }.joined()) { check(roster) }
        .task(id: phase) {
            guard phase == .active else { return }
            // Caixa de saída (ligas, check-ins, recados, denúncias e bloqueios) e o seu perfil público para o servidor;
            // o perfil só depois do aceite dos termos. A sessão pode ter acabado enquanto a tela saía.
            if AuthStore.shared.isSignedIn {
                await AccessStore.shared.refresh()
                LeagueRemoteStore.shared.republishForPrivacy(context: context)
                await LeagueRemoteStore.shared.flush(context: context)
                await ModerationStore.shared.refresh()
                await InboxStore.shared.refresh(context: context)
                BrosWidgetFeed.update(context: context)
                // Troca aceita enquanto o app estava fechado: vira notificação (receber é na tela de trocas)
                await TradeStore.shared.refresh()
                if Terms.isAccepted() {
                    await FriendsStore.shared.publish(PublicProfile.mine(roster: roster, activities: activities, checkIns: checkIns,
                                                                         leagues: leagues, unlocked: achievements.filter(\.unlocked)))
                }
            }
            // Peso mais recente para as estimativas de calorias (perfil físico)
            BodyProfile.remember(weight: ((try? context.fetch(FetchDescriptor<BodyEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? [])
                .compactMap(\.weight).first)
            // Ligas com renovação automática que acabaram ganham a próxima temporada
            LeagueRenewal.run(context: context)
            let running = (try? context.fetchCount(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.end == nil }))) ?? 0
            if running == 0 { await LiveWorkout.endAll() } else if let s = LiveWorkout.runningSession { await LiveWorkout.refresh(s) }
            // Chegou na academia há pouco e ainda não começou: oferece começar
            // Treino começado pelo relógio com o iPhone em segundo plano: abre a tela dele
            if WatchBridge.shared.consumeOpenRequest() {
                tab = 1
                try? await Task.sleep(for: .milliseconds(300))
                NotificationCenter.default.post(name: NotificationRouter.startWorkout, object: nil)
            }
            if running == 0, let arrived = GymLocation.shared.pendingArrival, Date.now.timeIntervalSince(arrived) < 3600 {
                arrivalPrompt = true
            }
            await syncHealth()
        }
        .task(id: achievements.filter(\.unlocked).map(\.id)) { announce(achievements) }
        // Widget e lembretes acompanham qualquer mudança relevante
        .task(id: "\(s.totalXP)|\(s.lastActivity?.timeIntervalSince1970 ?? 0)|\(routineKey)|\(remindersOn)|\(reminderMinute)|\(reminderRoutineOnly)|\(weeklySummary)|\(notificationsPaused)|\(mainName)|\(phase == .active)") {
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
        .overlay { OnboardingOverlay() }
        .animation(.easeInOut(duration: 0.25), value: tour.isActive)
        // Depois do tutorial: o que quer fazer aqui (uma vez) ou o que há de novo nesta versão
        .task(id: tour.isActive) {
            guard !tour.isActive, [.completed, .dismissed].contains(tour.persistence.state) else { return }
            try? await Task.sleep(for: .seconds(1.2))
            if !StartIntentRouter.asked {
                UserDefaults.standard.set(true, forKey: StartIntentRouter.askedKey)
                // Quem já usava o app não precisa da pergunta: vê as novidades
                if activities.isEmpty && leagues.isEmpty { WhatsNew.markSeen(); asking = true; return }
            }
            if WhatsNew.shouldShow { WhatsNew.markSeen(); whatsNew = true }
        }
        .gmSheet(isPresented: $asking) { close in
            StartIntentSheet { intent in
                close()
                guard intent != .solo else { return }
                tab = MainTab.leagues.rawValue
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NotificationCenter.default.post(name: intent == .create ? StartIntentRouter.createLeague : StartIntentRouter.joinLeague, object: nil)
                }
            }
        }
        .gmSheet(isPresented: $whatsNew) { close in WhatsNewView { close() } }
        .onChange(of: AuthStore.shared.user?.id, initial: true) { _, id in tour.setAccount(id) }
        .onDisappear { tour.suspend() }
        .onChange(of: tour.current?.id) {
            guard let t = tour.current?.tab, tab != t.rawValue else { return }
            withAnimation(.spring(duration: 0.3)) { tab = t.rawValue }
        }
        // Tutorial: só com a tela principal livre (sem cena de evolução, avisos ou o BroBook por cima)
        // e, na abertura automática, sem treino em andamento
        .task(id: "\(tour.startRequested)|\(AuthStore.shared.user?.id ?? "")|\(recovered)|\(arrivalPrompt)|\(evolutions.isEmpty)|\(dex)|\(phase == .active)") {
            guard phase == .active else { return }
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            let running = (try? context.fetchCount(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.end == nil }))) ?? 0
            tour.startIfEligible(modalOpen: recovered || arrivalPrompt || !evolutions.isEmpty || dex, busy: running > 0)
        }
        .onReceive(NotificationCenter.default.publisher(for: NotificationRouter.startWorkout)) { _ in tab = 1 }
        // Força, convites e mensagens chegam mesmo com a caixa de entrada fechada (com servidor, por push)
        .task(id: phase) {
            guard phase == .active else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(45))
                if AuthStore.shared.isSignedIn { await InboxStore.shared.refresh(context: context) }
            }
        }
        // Toque numa notificação social: a caixa de entrada abre pela tela inicial
        .onChange(of: inbox.route) { _, r in if r != nil { tab = 0 } }
        // Widget "Treino do dia": gymbros://start abre o treino em andamento ou começa a rotina de hoje
        .onOpenURL { url in
            // QR ou link de amigo: gymbros://amigo/CODIGO pergunta antes de adicionar (um link qualquer não vira amizade sozinho)
            if url.scheme == "gymbros", url.host == "amigo", let code = FriendQR.code(in: url.absoluteString) {
                // Zera antes: o mesmo código de novo (diálogo fechado por outra camada) abre o diálogo outra vez
                friendLink = nil
                Task { @MainActor in friendLink = code }
                return
            }
            guard url.scheme == "gymbros", url.host == "start" else { return }
            tab = 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                NotificationCenter.default.post(name: NotificationRouter.startWorkout, object: nil)
            }
        }
        .gmActions(isPresented: Binding(get: { friendLink != nil }, set: { if !$0 { friendLink = nil } }),
                   title: "Adicionar amigo?",
                   message: "Código \(friendLink ?? ""). Só adicione quem você conhece: quem também te adicionar vê seus treinos ao vivo.",
                   actions: [GMAction("Adicionar", icon: "person.badge.plus") { [friendLink] in
                       guard let code = friendLink else { return }
                       Task { _ = try? await FriendsStore.shared.add(code: code) }
                   }])
        .fullScreenCover(isPresented: Binding(get: { watchWorkout.active && !watchWorkout.minimized },
                                              set: { if !$0 { watchWorkout.minimized = true } })) {
            WatchWorkoutView()
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        .overlay(alignment: .bottom) { WatchWorkoutPill().padding(.bottom, 92) }
        // Toque na notificação de troca
        .gmModal(isPresented: Binding(get: { trades.openHub }, set: { trades.openHub = $0 })) { TradeHubView() }
        .gmActions(isPresented: $recovered, title: "Não deu para abrir seus dados",
                   message: "O app começou do zero para não travar. O arquivo antigo foi guardado (\(AppData.recoveredCopy?.lastPathComponent ?? "")) e dá para voltar com um backup em Ajustes → Backup.",
                   actions: [GMAction("Entendi", icon: "checkmark") {}])
        .gmActions(isPresented: $arrivalPrompt, title: "Chegou na \(GymLocation.shared.insideGym?.name ?? "academia") 💪",
                   message: GymLocation.todayTrainingName().map { "Hoje é dia de \($0)." } ?? "Bora treinar?",
                   actions: [GMAction("Começar treino", icon: "play.fill") {
                       GymLocation.shared.pendingArrival = nil
                       tab = 1
                       DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                           NotificationCenter.default.post(name: NotificationRouter.startWorkout, object: nil)
                       }
                   }])
        // Só o "Continuar" tira da fila; trocar o item fecha a cena e abre a próxima
        .gmModal(item: Binding(get: { evolutions.first }, set: { _ in })) { e in
            EvolutionView(from: e.from, to: e.to) { if !evolutions.isEmpty { evolutions.removeFirst() } }
                .id(e.id)
        }
    }

    @ViewBuilder
    private func page<V: View>(_ i: Int, @ViewBuilder _ content: () -> V) -> some View {
        if visited.contains(i) || tab == i {
            content()
                .opacity(tab == i ? 1 : 0)
                .allowsHitTesting(tab == i)
                .accessibilityHidden(tab != i)
                .environment(\.onboardingVisible, tab == i)
        }
    }

    private struct Derived {
        let roster: Roster
        /// Monstro principal, com sequência e humor do jogador (que contam todas as atividades)
        /// e o XP de cada atividade como no histórico (inclui o que foi para bros de liga)
        let main: Snapshot
        /// Para conquistas: estágio do monstro mais evoluído
        let best: Snapshot
        /// Para o histórico: XP de cada atividade no monstro que a recebeu
        let history: Snapshot
        let mainName: String
    }

    private func derive() -> Derived {
        _ = mainMonster
        let roster = Roster(monsters: monsters, activities: activities, checkIns: checkIns, leagues: leagues)
        let player = Game.cachedSnapshot(activities.map(\.record))
        var main = roster.mainSnapshot
        main.streak = player.streak
        main.bestStreak = player.bestStreak
        main.lastActivity = player.lastActivity
        main.todayXP = player.todayXP
        main.xpByActivity = roster.xpByActivity
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
                   formName: s.form.name, stageName: s.stage.name, sprite: s.form.spriteWithFallback, hue: s.form.hue,
                   isEgg: s.stage == .egg, level: s.level, totalXP: s.totalXP, progress: s.progress, xpToNext: s.xpToNext,
                   streak: s.streak, lastActivity: s.lastActivity, todayXP: s.todayXP, todayRoutine: routinesByWeekday,
                   updated: .now, lastEvolution: s.evolutions.last?.date, lastEvolutionName: s.evolutions.last?.form.name,
                   lastEvolutionHatch: s.evolutions.last?.form.stage == .baby).save()
        WidgetBridge.reload()
        WatchBridge.shared.update(bro: WatchBro(name: companion.name, formName: s.form.name, stageName: s.stage.name,
                                                moodEmoji: companion.mood.emoji, isEgg: s.stage == .egg, level: s.level,
                                                totalXP: s.totalXP, progress: s.progress, xpToNext: s.xpToNext, streak: s.streak,
                                                lastActivity: s.lastActivity, todayXP: s.todayXP,
                                                attributes: Dictionary(uniqueKeysWithValues: s.lifetimeAttributes.map { ($0.key.rawValue, $0.value) }),
                                                updated: .now),
                                  sprite: s.form.spriteWithFallback, hue: s.form.hue)
        Reminders.schedule(enabled: remindersOn && !notificationsPaused, minuteOfDay: reminderMinute, onlyRoutineDays: reminderRoutineOnly,
                           routines: routinesByWeekday, name: companion.name, streak: s.streak,
                           trainedToday: companion.trainedToday, isEgg: s.stage == .egg)
        WeeklySummary.schedule(enabled: weeklySummary && !notificationsPaused, trainer: trainerName)
        Task { await HealthSync.exportPending(context: context) }
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
        await HealthSync.exportPending(context: context)
        guard HealthSync.enabled else { return }
        guard let r = try? await HealthSync.sync(context: context), !r.imported.isEmpty else { return }
        // @Query ainda não tem as importadas: busca de novo e usa a mesma regra do histórico
        let fresh = Roster(monsters: (try? context.fetch(FetchDescriptor<Monster>())) ?? monsters,
                           activities: (try? context.fetch(FetchDescriptor<Activity>())) ?? activities,
                           checkIns: (try? context.fetch(FetchDescriptor<LeagueCheckIn>())) ?? checkIns,
                           leagues: (try? context.fetch(FetchDescriptor<League>())) ?? leagues).xpByActivity
        let xp = r.imported.reduce(0) { $0 + (fresh[$1.uuid] ?? 0) }
        HealthAutoPost.post(r.imported, context: context)
        let n = r.imported.count
        show(Banner(symbol: "heart.fill", text: "\(n) treino\(n == 1 ? "" : "s") do Saúde · +\(xp) XP"))
    }

    /// Descobertas do BroBook e cena de evolução, para qualquer monstro da coleção
    private func check(_ roster: Roster) {
        guard !monsters.isEmpty else { return }
        var seen = Set(discovered.split(separator: ",").map(String.init))
        seen.insert(MonsterForm.egg.id)
        for snap in roster.snapshots.values { seen.formUnion(snap.evolutions.map(\.form.id)) }
        discovered = seen.sorted().joined(separator: ",")

        for m in monsters {
            let form = roster.snapshot(m.uuid).form
            let old = MonsterForm.byID(m.lastFormID) ?? .egg
            if old != form, form.stage > old.stage {
                let e = EvolutionEvent(monster: m.uuid, from: old, to: form)
                if !evolutions.contains(where: { $0.id == e.id }) { evolutions.append(e) }
            }
            m.lastFormID = form.id
            // Fixa a espécie na chocagem: espécies novas no futuro não mudam quem já nasceu
            if m.speciesID == nil, form.stage > .egg { m.speciesID = form.species }
            // Voltou a ser ovo (atividades apagadas): o próximo choco decide a espécie de novo
            if m.speciesID != nil, form.stage == .egg { m.speciesID = nil }
        }
        try? context.save()
    }
}

enum WidgetBridge {
    static func reload() { WidgetCenter.shared.reloadAllTimelines() }
}
