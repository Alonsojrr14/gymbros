import SwiftData
import SwiftUI
import WidgetKit

/// Índice dos Ajustes: cartão do perfil e grupos que levam às telas de cada assunto (SettingsPages.swift)
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("trainerName") private var trainerName = ""
    @AppStorage(NotificationPrefs.pausedKey) private var notificationsPaused = false
    @AppStorage("autoWarmup") private var autoWarmup = true
    @Query(sort: \Monster.createdAt) private var monsters: [Monster]
    @State private var confirmReset = false
    @State private var testBroAdded = false
    @State private var confirmSignOut = false
    @State private var signOutError: String?
    @State private var auth = AuthStore.shared
    @State private var access = AccessStore.shared
    @State private var moderation = ModerationStore.shared
    @State private var music = MusicShareStore.shared
    @State private var permission = NotificationPermission.shared

    var body: some View {
        NavigationStack {
            GMScreen("Ajustes", close: true, bottomInset: 40) {
                NavigationLink { ProfileSettingsPage() } label: { hero }
                    .buttonStyle(GMPress())

                group("App") {
                    link(NotificationSettingsPage()) {
                        GMNavRow(icon: "bell.badge.fill", tint: Theme.badge, title: "Notificações", value: notificationsValue,
                                 valueTint: permission.denied ? Theme.warning : Theme.dim)
                    }
                    GMDivider()
                    link(TrainingSettingsPage()) {
                        GMNavRow(icon: "dumbbell.fill", tint: Theme.streak, title: "Treino", value: autoWarmup ? "Aquecimento ligado" : nil)
                    }
                    GMDivider()
                    link(MusicSettingsPage()) {
                        GMNavRow(icon: "music.note", tint: Theme.health, title: "Música", value: music.sharing ? "Compartilhando" : "Desligado")
                    }
                    if HealthSync.available {
                        GMDivider()
                        link(HealthSettingsPage()) {
                            GMNavRow(icon: "heart.fill", tint: Theme.health, title: "Apple Saúde", value: HealthSync.enabled ? "Importando" : "Desligado")
                        }
                    }
                }

                group("Conta e dados") {
                    if let user = auth.user {
                        link(AccountSettingsPage()) {
                            GMNavRow(icon: "person.crop.circle.fill", tint: Theme.info, title: "Conta",
                                     value: user.provider == .apple ? "Apple" : "E-mail")
                        }
                        GMDivider()
                    }
                    link(BackupSettingsPage()) {
                        GMNavRow(icon: "externaldrive.fill", tint: Attribute.resistencia.color, title: "Backup")
                    }
                    GMDivider()
                    link(PrivacySettingsPage()) {
                        GMNavRow(icon: "hand.raised.fill", tint: Attribute.tecnica.color, title: "Privacidade",
                                 value: moderation.blocked.isEmpty ? nil : "\(moderation.blocked.count) bloqueado\(moderation.blocked.count == 1 ? "" : "s")")
                    }
                }

                group("Ajuda") {
                    link(HowItWorksPage()) {
                        GMNavRow(icon: "questionmark", tint: Attribute.agilidade.color, title: "Como funciona")
                    }
                    GMDivider()
                    Button {
                        OnboardingCoordinator.shared.requestStart()
                        dismiss()
                    } label: {
                        GMNavRow(icon: "sparkles", tint: Theme.accent, title: "Ver tutorial do app")
                    }
                    .buttonStyle(GMPress())
                    if showsDiagnostics {
                        GMDivider()
                        link(DiagnosticsSettingsPage { dismiss() }) {
                            GMNavRow(icon: "ladybug.fill", tint: .gray, title: "Diagnóstico")
                        }
                    }
                }

                #if DEBUG
                GMSection(footer: testBroAdded ? "Bro de teste criado: veja na Box (Meus bros)." : nil) {
                    GMRow(icon: "plus.circle", tile: Theme.accent, title: "Ganhar bro de teste",
                          subtitle: "Um bro já chocado, com treinos de teste") { addTestBro() }
                    GMRow(icon: "arrow.counterclockwise", iconTint: Theme.danger, tile: Theme.danger, title: "Recomeçar jornada") { confirmReset = true }
                }
                #endif

                if auth.user != nil {
                    GMSection(footer: signOutError) {
                        GMRow(icon: "rectangle.portrait.and.arrow.right", tile: Theme.warning, title: "Sair da conta") { confirmSignOut = true }
                    }
                }

                footer
            }
        }
        .task { await permission.refresh() }
        .gmActions(isPresented: $confirmReset, title: "Recomeçar a jornada?",
                   message: Self.resetText + " Não dá para desfazer.",
                   actions: [GMAction("Recomeçar", icon: "arrow.counterclockwise", destructive: true, action: reset)])
        .gmActions(isPresented: $confirmSignOut, title: "Sair da conta?", message: Self.signOutText,
                   actions: [GMAction("Sair", icon: "rectangle.portrait.and.arrow.right", destructive: true) { Task { await signOut() } }])
    }

    private func signOut() async {
        do {
            try await AccountSync.shared.signOut()
        } catch {
            signOutError = "Não deu para salvar seus dados na conta: \(error.localizedDescription) Nada saiu do iPhone; tente de novo."
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    // MARK: Peças

    private var mainMonster: Monster? {
        monsters.first { $0.uuid == MainMonster.id } ?? monsters.first { $0.isStarter }
    }

    /// Você e seu bro, em destaque; abre "Perfil e bro"
    private var hero: some View {
        let form = mainMonster.map { MonsterForm.byID($0.lastFormID) ?? .egg } ?? .egg
        let nameOK = ContentFilter.allows(trainerName)
        return HStack(spacing: 14) {
            Avatar(size: 62)
            VStack(alignment: .leading, spacing: 4) {
                Text(trainerName.isEmpty ? "Treinador" : trainerName)
                    .gmFont(22, weight: .heavy, design: .rounded, relativeTo: .title2)
                    .lineLimit(1).minimumScaleFactor(0.7)
                if !nameOK {
                    Label("Nome não permitido", systemImage: "exclamationmark.triangle.fill").font(.caption.bold()).foregroundStyle(Theme.danger)
                } else if let email = auth.user?.email, !email.isEmpty {
                    Text(email).font(.caption).foregroundStyle(Theme.dim).lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(mainMonster?.displayName(form) ?? form.name).font(.caption.bold())
                    Text("·").foregroundStyle(Theme.dim)
                    Text(form.stage.name).font(.caption).foregroundStyle(Theme.dim)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Theme.raised, in: .capsule)
            }
            Spacer(minLength: 0)
            MonsterSprite(form: form).frame(width: 64, height: 64)
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.dim)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .topTrailing) {
                Theme.card
                Circle().fill(Theme.accent.opacity(0.22)).frame(width: 220).blur(radius: 60).offset(x: 70, y: -90)
            }
            .clipShape(.rect(cornerRadius: Theme.radius))
        }
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.accent.opacity(0.25), lineWidth: 1))
        .foregroundStyle(.white)
        .contentShape(Rectangle())
    }

    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        GMSection(title) { content() }
    }

    private func link<D: View, L: View>(_ destination: D, @ViewBuilder label: () -> L) -> some View {
        NavigationLink { destination } label: { label() }.buttonStyle(GMPress())
    }

    private var footer: some View {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? ""
        return VStack(spacing: 4) {
            Text("GymBros").gmFont(15, weight: .black, design: .rounded, relativeTo: .subheadline).foregroundStyle(Theme.accent)
            Text("Versão \(version)\(build.isEmpty ? "" : " (\(build))")").font(.caption2).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private var notificationsValue: String {
        if permission.denied { return "Desligadas no iPhone" }
        if notificationsPaused { return "Pausadas" }
        return "\(NotificationPrefs.enabledCount()) de \(NotificationTopic.allCases.count)"
    }

    private var showsDiagnostics: Bool {
        #if DEBUG
        true
        #else
        access.can(.diagnosticsRead)
        #endif
    }

    // MARK: Textos (também usados nas telas de Conta e Backup)

    static var accountFooter: String {
        (Backend.mode == .mock ? "Login e servidor simulados neste iPhone. " : "")
            + "Treinos, bros e o resto do progresso são da conta: ao sair, saem do iPhone e voltam quando você entra de novo."
    }

    static var backupFooter: String {
        "Seus dados são da sua conta e voltam quando você entra nela. O backup é uma cópia extra em arquivo: guarde no Arquivos, no próprio iPhone. Ele inclui dados do Apple Saúde, por isso não sugerimos o iCloud Drive."
            + (Backend.mode == .mock ? " Nesta versão o servidor é simulado neste iPhone: se o app for apagado, só o backup recupera tudo." : "")
    }

    static let signOutText = "Seus treinos, bros e o resto do progresso ficam salvos na conta e saem deste iPhone. Tudo volta quando você entrar de novo."

    static let deleteAccountText = "Apaga a conta e tudo dela, na conta e neste iPhone: treinos, bros, rotinas, medidas, fotos, recordes, ligas, check-ins, recados, mensagens, amizades, bloqueios e denúncias. Você volta para a tela de entrar. Não dá para desfazer."

    /// O que "Recomeçar jornada" faz (mostrado na confirmação)
    static let resetText = "Apaga as atividades e tudo ligado a elas (treinos guiados, check-ins no perfil e nas ligas, percursos, WODs), os bros, as conquistas já vistas e os carinhos do widget, e devolve um ovo novo. Você continua nas ligas, agora representado pelo ovo novo e com placar zerado."

    #if DEBUG
    /// Para testar o X1 com mais de um bro: um ovo novo com 8 corridas de teste nos últimos dias, que o fazem chocar (Lobo)
    private func addTestBro() {
        let bro = Monster()
        bro.createdAt = .now
        context.insert(bro)
        let cal = Calendar.current
        for day in 1...8 {
            let date = cal.date(byAdding: .day, value: -day, to: cal.startOfDay(for: .now))!.addingTimeInterval(7 * 3600)
            let run = Activity(kind: .corrida, date: date, minutes: 60, effort: 7, note: "Treino de teste do bro")
            run.monsterUUID = bro.uuid
            context.insert(run)
        }
        try? context.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        testBroAdded = true
    }
    #endif

    private func reset() {
        // Tudo que depende das atividades sai junto, para nada ficar apontando para atividade apagada
        let ids = Set(((try? context.fetch(FetchDescriptor<Activity>())) ?? []).map(\.uuid))
        let posts = (try? context.fetch(FetchDescriptor<LeagueCheckIn>())) ?? []
        let postIDs = Set(posts.map(\.uuid.uuidString))
        ((try? context.fetch(FetchDescriptor<CheckInComment>())) ?? []).filter { postIDs.contains($0.itemID) }.forEach(context.delete)
        posts.forEach(LeagueOutbox.retract)
        posts.forEach(context.delete)
        ((try? context.fetch(FetchDescriptor<RouteRecord>())) ?? []).filter { $0.activityUUID.map(ids.contains) ?? true }.forEach(context.delete)
        ((try? context.fetch(FetchDescriptor<WodResult>())) ?? []).filter { $0.activityUUID.map(ids.contains) ?? false }.forEach(context.delete)
        // O treino em andamento (ainda sem atividade) continua
        ((try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []).filter { $0.activityUUID.map(ids.contains) ?? false }.forEach(context.delete)
        try? context.delete(model: Activity.self)
        try? context.save()
        RetiredActivities.clear()
        for k in TradeLedger.keys { UserDefaults.standard.removeObject(forKey: k) }
        // Só treinos do Saúde feitos daqui para frente alimentam o ovo novo
        HealthSync.lastSync = .now
        // Volta a ter um monstro só: o ovo inicial novo, que passa a representar você nas ligas
        try? context.delete(model: Monster.self)
        try? context.save()
        MainMonster.id = nil
        let d = UserDefaults.standard
        for k in ["monsterNick", "lastFormID", "discovered", "achievementsSeen"] { d.removeObject(forKey: k) }
        ActivitySplits.replace([:])
        WidgetData.defaults?.removeObject(forKey: "pets")
        WidgetCenter.shared.reloadAllTimelines()
        Roster.ensureStarter(context: context)
        PRBook.reload()
        dismiss()
    }
}
