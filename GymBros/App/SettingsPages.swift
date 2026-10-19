import SwiftData
import SwiftUI
import UserNotifications

// Telas dentro de Ajustes (SettingsView é o índice). Cada uma é empurrada no NavigationStack do índice.

// MARK: - Perfil e bro

struct ProfileSettingsPage: View {
    @AppStorage("trainerName") private var trainerName = ""
    @Query(sort: \Monster.createdAt) private var monsters: [Monster]

    private var mainMonster: Monster? {
        monsters.first { $0.uuid == MainMonster.id } ?? monsters.first { $0.isStarter }
    }

    var body: some View {
        GMScreen("Perfil e bro", back: true, bottomInset: 40) {
            GMSection("Treinador", footer: ContentFilter.allows(trainerName) ? "É o nome que aparece para os amigos e nas ligas." : "Esse nome tem palavras que não são permitidas e não aparece para os outros. Escolha outro.") {
                GMTextField(placeholder: "Seu nome", text: $trainerName, capitalization: .words)
            }
            GMSection("Bro principal", footer: "Vazio usa o nome da forma atual.") {
                if let m = mainMonster {
                    HStack(spacing: 12) {
                        MonsterSprite(form: MonsterForm.byID(m.lastFormID) ?? .egg).frame(width: 44, height: 44)
                        GMTextField(placeholder: "Apelido", text: Binding(get: { m.name }, set: { m.name = $0 }), capitalization: .words)
                    }
                }
            }
        }
    }
}

// MARK: - Notificações

struct NotificationSettingsPage: View {
    @AppStorage(NotificationPrefs.pausedKey) private var paused = false
    @AppStorage("remindersOn") private var remindersOn = false
    @AppStorage("reminderMinute") private var reminderMinute = 18 * 60
    @AppStorage("reminderRoutineOnly") private var reminderRoutineOnly = false
    @AppStorage("restNotification") private var restNotification = false
    @AppStorage("weeklySummary") private var weeklySummary = true
    @AppStorage("gymNotifyArrival") private var arrival = true
    @State private var permission = NotificationPermission.shared

    var body: some View {
        GMScreen("Notificações", back: true, bottomInset: 40) {
            if !permission.allowed { NotificationPermissionCard() }

            GMSection(footer: paused ? "Nada toca até você religar. Mensagens e convites continuam chegando na caixa de entrada." : nil) {
                GMIconToggle(icon: paused ? "moon.fill" : "bell.fill", tint: paused ? Attribute.tecnica.color : Theme.badge,
                             title: "Pausar todas", subtitle: "Silencia lembretes e avisos sociais", isOn: $paused)
            }

            GMSection("Amigos", footer: "Quem você bloqueou nunca gera notificação. Tudo continua aparecendo no sino da tela inicial.") {
                ForEach(NotificationTopic.allCases) { t in
                    TopicToggle(topic: t, onEnable: askPermission)
                    if t != NotificationTopic.allCases.last { GMDivider() }
                }
            }
            .disabled(paused)
            .opacity(paused ? 0.45 : 1)

            GMSection("Treino", footer: "O lembrete só chega nos dias em que você ainda não treinou. O Live Activity já mostra o descanso; o alerta é para quem quer o aviso também.") {
                GMIconToggle(icon: "alarm.fill", tint: Theme.streak, title: "Lembrete para treinar",
                             subtitle: remindersOn ? "Seu bro te chama no horário escolhido" : nil, isOn: $remindersOn)
                    .onChange(of: remindersOn) { _, on in if on { askPermission() } }
                if remindersOn {
                    GMTimeField(date: Binding(
                        get: { Calendar.current.date(byAdding: .minute, value: reminderMinute, to: Calendar.current.startOfDay(for: .now))! },
                        set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); reminderMinute = (c.hour ?? 18) * 60 + (c.minute ?? 0) }
                    ))
                    GMToggle(title: "Só em dias de rotina", isOn: $reminderRoutineOnly)
                }
                GMDivider()
                GMIconToggle(icon: "calendar", tint: Theme.info, title: "Resumo da semana",
                             subtitle: "Domingo às 19h: treinos, tempo, PRs e ligas", isOn: $weeklySummary)
                    .onChange(of: weeklySummary) { _, on in if on { askPermission() } }
                GMDivider()
                GMIconToggle(icon: "timer", tint: Theme.accent, title: "Fim do descanso", isOn: $restNotification)
                    .onChange(of: restNotification) { _, on in if on { askPermission() } }
                GMDivider()
                GMIconToggle(icon: "mappin.and.ellipse", tint: Theme.health, title: "Chegada no lugar de treino",
                             subtitle: "Oferece começar o treino do dia", isOn: $arrival)
            }
            .disabled(paused)
            .opacity(paused ? 0.45 : 1)
        }
        .task { await permission.refresh() }
    }

    private func askPermission() {
        guard permission.status == .notDetermined else { return }
        Task { await permission.request() }
    }
}

/// Um tópico social com a chave própria no UserDefaults
private struct TopicToggle: View {
    let topic: NotificationTopic
    let onEnable: () -> Void
    @AppStorage private var isOn: Bool

    init(topic: NotificationTopic, onEnable: @escaping () -> Void) {
        self.topic = topic
        self.onEnable = onEnable
        _isOn = AppStorage(wrappedValue: true, topic.key)
    }

    var body: some View {
        GMIconToggle(icon: topic.icon, tint: topic.tint, title: topic.title, subtitle: topic.subtitle, isOn: $isOn)
            .onChange(of: isOn) { _, on in if on { onEnable() } }
    }
}

// MARK: - Treino

struct TrainingSettingsPage: View {
    @AppStorage("autoWarmup") private var autoWarmup = true
    @AppStorage("gymAutoFinish") private var autoFinish = true

    var body: some View {
        GMScreen("Treino", back: true, bottomInset: 40) {
            GMSection("Aquecimento", footer: "Ao começar uma rotina, o primeiro exercício com carga ganha 3 séries leves (40 %, 60 % e 80 % da carga). Elas não contam para recordes, progressão nem volume. No menu ⋯ de cada exercício dá para adicionar ou tirar.") {
                GMIconToggle(icon: "flame.fill", tint: Theme.streak, title: "Aquecimento automático", isOn: $autoWarmup)
            }
            GMSection("Lugares de treino", footer: "Com um lugar salvo no Mapa, o treino em andamento termina sozinho quando você sai de lá (depois de pelo menos alguns minutos).") {
                GMIconToggle(icon: "figure.walk.departure", tint: Theme.health, title: "Encerrar treino ao sair", isOn: $autoFinish)
            }
        }
    }
}

// MARK: - Apple Saúde

struct MusicSettingsPage: View {
    @State private var store = MusicShareStore.shared
    @State private var on = MusicShareStore.shared.sharing

    var body: some View {
        GMScreen("Música", back: true, bottomInset: 40) {
            GMSection(footer: "Enquanto você treina ao vivo, seus amigos veem a música que está tocando. Só a música atual: nada do seu histórico ou da sua biblioteca é enviado. Desligado, nada é lido.") {
                GMIconToggle(icon: "music.note", tint: Theme.health, title: "Mostrar o que estou ouvindo", isOn: $on)
                    .onChange(of: on) { _, v in
                        Task {
                            await store.setSharing(v)
                            if on != store.sharing { on = store.sharing }
                        }
                    }
            }
            if store.availableSources.count > 1 {
                GMSection("Serviço") {
                    ForEach(store.availableSources) { s in
                        GMRow(icon: s == store.source ? "checkmark.circle.fill" : "circle", title: s.name) {
                            Task { await store.setSource(s) }
                        }
                    }
                }
            }
            if store.sharing {
                GMSection("Agora", footer: Backend.mode == .mock ? "Nesta versão sem servidor, só você vê; os amigos veem quando o app tiver servidor." : nil) {
                    Label(store.current?.line ?? "Nada tocando no \(store.source.name)", systemImage: "headphones")
                        .font(.subheadline)
                        .foregroundStyle(store.current == nil ? Theme.dim : .white)
                }
            }
            if let m = store.message {
                Text(m).font(.footnote).foregroundStyle(Theme.warning).padding(.horizontal, 4)
            }
        }
        .task {
            while !Task.isCancelled {
                await store.refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }
}

struct HealthSettingsPage: View {
    @Environment(\.modelContext) private var context
    @State private var healthOn = HealthSync.enabled
    @State private var healthWrite = HealthSync.writeEnabled
    @State private var status: String?
    @State private var syncing = false

    var body: some View {
        GMScreen("Apple Saúde", back: true, bottomInset: 40) {
            GMSection("Importar", footer: "Corridas, caminhadas, vôlei e outros treinos do iPhone ou Apple Watch viram atividades automaticamente ao abrir o app (na primeira vez, os últimos \(HealthSync.firstImportDays) dias). Treinos que coincidem com algo já registrado aqui não contam duas vezes.") {
                GMIconToggle(icon: "heart.fill", tint: Theme.health, title: "Importar treinos do Saúde", isOn: $healthOn)
                    .onChange(of: healthOn) { _, on in Task { await toggleHealth(on) } }
                if healthOn {
                    GMButton(syncing ? "Sincronizando…" : "Sincronizar agora", icon: "arrow.triangle.2.circlepath",
                             kind: .secondary, small: true, enabled: !syncing) { Task { await syncNow() } }
                }
            }
            GMSection("Gravar", footer: "O que você registra aqui (musculação, WOD, corrida…) vai para o Saúde com calorias estimadas e conta nos anéis do Fitness.") {
                GMIconToggle(icon: "figure.run.circle.fill", tint: Theme.accent, title: "Gravar treinos no Saúde", subtitle: "Daqui para frente", isOn: $healthWrite)
                    .onChange(of: healthWrite) { _, on in Task { await toggleWrite(on) } }
            }
            if let status {
                Text(status).font(.footnote).foregroundStyle(Theme.dim).padding(.horizontal, 4)
            }
        }
    }

    private func toggleHealth(_ on: Bool) async {
        guard on else {
            HealthSync.enabled = false
            status = "Desligado. O que já foi importado continua."
            return
        }
        do {
            try await HealthSync.requestAccess()
            HealthSync.enabled = true
            await syncNow()
        } catch {
            healthOn = false
            status = "Não consegui acesso ao Saúde: \(error.localizedDescription)"
        }
    }

    private func toggleWrite(_ on: Bool) async {
        guard on else {
            HealthSync.writeEnabled = false
            status = "Não grava mais. O que já foi para o Saúde continua lá."
            return
        }
        do {
            try await HealthSync.requestWrite()
            HealthSync.writeEnabled = true
            status = "Pronto: os próximos treinos registrados aqui vão para o Saúde."
        } catch {
            healthWrite = false
            status = "Não consegui permissão para gravar: \(error.localizedDescription)"
        }
    }

    private func syncNow() async {
        syncing = true
        defer { syncing = false }
        do {
            let r = try await HealthSync.sync(context: context)
            var parts = [r.imported.isEmpty ? "Nenhum treino novo" : "\(r.imported.count) treino(s) importado(s)"]
            if r.skippedOverlap > 0 { parts.append("\(r.skippedOverlap) já registrado(s) aqui") }
            status = parts.joined(separator: ", ") + ". Se esperava algo, confira em Ajustes do iPhone → Saúde → Acesso a Dados → GymBros."
        } catch {
            status = "Falha ao sincronizar: \(error.localizedDescription)"
        }
    }
}

// MARK: - Backup

struct BackupSettingsPage: View {
    @Environment(\.modelContext) private var context
    @State private var exportDoc: BackupDocument?
    @State private var exporting = false
    @State private var importing = false
    @State private var pendingRestore: Backup?
    @State private var message: String?

    var body: some View {
        GMScreen("Backup", back: true, bottomInset: 40) {
            GMSection(footer: SettingsView.backupFooter) {
                GMRow(icon: "square.and.arrow.up", tile: Theme.info, title: "Exportar backup", subtitle: "Arquivo .json com tudo", chevron: true) { export() }
                GMDivider()
                GMRow(icon: "square.and.arrow.down", tile: Theme.warning, title: "Restaurar backup", subtitle: "Substitui os dados atuais", chevron: true) { importing = true }
            }
            if let message {
                Text(message).font(.footnote).foregroundStyle(Theme.dim).padding(.horizontal, 4)
            }
        }
        .gmActions(isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
                   title: "Restaurar backup?", message: restoreTitle,
                   actions: pendingRestore.map { b in [GMAction("Substituir tudo", icon: "square.and.arrow.down", destructive: true) {
                       do {
                           try b.restore(into: context)
                           message = "Backup restaurado: \(b.activities.count) atividades."
                           // Os lugares mudaram: volta a monitorar os restaurados
                           if GymLocation.shared.insideGym == nil { GymLocation.shared.insideID = nil }
                           GymLocation.shared.startMonitoring()
                       } catch {
                           message = "Falha ao restaurar: \(error.localizedDescription)"
                       }
                       pendingRestore = nil
                   }] } ?? [])
        .fileExporter(isPresented: $exporting, document: exportDoc, contentType: .json,
                      defaultFilename: "GymBros-\(Date.now.formatted(.iso8601.year().month().day()))") { result in
            if case .success = result { message = "Backup salvo." }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                pendingRestore = try Backup.decoder.decode(Backup.self, from: Data(contentsOf: url))
            } catch {
                message = "Não consegui ler o arquivo: \(error.localizedDescription)"
            }
        }
    }

    private var restoreTitle: String {
        guard let b = pendingRestore else { return "" }
        return "De \(b.exportedAt.formatted(date: .abbreviated, time: .shortened)), com \(b.activities.count) atividades. Isso substitui todos os dados atuais."
    }

    private func export() {
        do {
            exportDoc = BackupDocument(data: try Backup.encoder.encode(Backup.make(context: context)))
            exporting = true
        } catch {
            message = "Falha ao exportar: \(error.localizedDescription)"
        }
    }
}

// MARK: - Conta

struct AccountSettingsPage: View {
    @State private var auth = AuthStore.shared
    @State private var access = AccessStore.shared
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var message: String?

    var body: some View {
        GMScreen("Conta", back: true, bottomInset: 40) {
            if let user = auth.user {
                GMSection(footer: message ?? SettingsView.accountFooter) {
                    GMRow(icon: user.provider == .apple ? "apple.logo" : "envelope.fill", tile: user.provider == .apple ? .white : Theme.info,
                          title: user.name.isEmpty ? "Sua conta" : user.name, subtitle: user.email)
                    GMDivider()
                    GMValueRow(label: "Entrou com", value: user.provider == .apple ? "Apple" : "E-mail")
                    GMDivider()
                    GMValueRow(label: "Função", value: rolesText)
                }
                GMSection("Zona de perigo") {
                    GMRow(icon: "person.crop.circle.badge.xmark", iconTint: Theme.danger, tile: Theme.danger, title: deleting ? "Excluindo…" : "Excluir conta",
                          subtitle: "Apaga a conta e todos os dados") {
                        if !deleting { confirmDelete = true }
                    }
                }
            }
        }
        .gmActions(isPresented: $confirmDelete, title: "Excluir sua conta?", message: SettingsView.deleteAccountText,
                   actions: [GMAction("Excluir conta", icon: "trash", destructive: true) { Task { await deleteAccount() } }])
    }

    private var rolesText: String {
        if access.isLoading { return "Conferindo…" }
        let titles = AppRole.allCases.filter(access.roles.contains).map(\.title)
        return titles.isEmpty ? "Nenhuma" : titles.joined(separator: ", ")
    }

    private func deleteAccount() async {
        deleting = true
        defer { deleting = false }
        do {
            try await AccountSync.shared.deleteAccount()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            message = "Não deu para excluir a conta: \(error.localizedDescription) Nada foi apagado; tente de novo."
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

// MARK: - Privacidade

struct PrivacySettingsPage: View {
    @State private var moderation = ModerationStore.shared
    @State private var privacy = false
    @State private var terms = false
    @State private var blockedList = false

    var body: some View {
        GMScreen("Privacidade", back: true, bottomInset: 40) {
            GMSection(footer: "Seus dados ficam na sua conta. Sem anúncios e sem rastreamento.") {
                GMRow(icon: "hand.raised.fill", tile: Theme.info, title: "Política de privacidade", chevron: true) { privacy = true }
                GMDivider()
                GMRow(icon: "doc.text.fill", tile: Attribute.tecnica.color, title: "Termos de uso", chevron: true) { terms = true }
            }
            GMSection(footer: "Desligado por padrão. Ligado, só a música que está tocando aparece para os amigos enquanto você treina ao vivo.") {
                NavigationLink { MusicSettingsPage() } label: {
                    GMNavRow(icon: "music.note", tint: Theme.health, title: "Mostrar o que estou ouvindo",
                             value: MusicShareStore.shared.sharing ? "Ligado" : "Desligado")
                }
                .buttonStyle(GMPress())
            }
            GMSection(footer: "Quem você bloqueia não aparece em feeds, mural, comentários, amigos, mapa e mensagens, e não te gera notificação.") {
                GMRow(icon: "hand.raised.slash.fill", tile: Theme.danger, title: "Usuários bloqueados",
                      subtitle: moderation.blocked.isEmpty ? nil : "\(moderation.blocked.count)", chevron: true) { blockedList = true }
            }
        }
        .gmModal(isPresented: $privacy) { PrivacyPolicyView() }
        .gmModal(isPresented: $terms) { TermsView() }
        .gmModal(isPresented: $blockedList) { BlockedUsersView() }
    }
}

// MARK: - Como funciona

struct HowItWorksPage: View {
    var body: some View {
        GMScreen("Como funciona", back: true, bottomInset: 40) {
            GMSection("XP e atributos") {
                Text("Cada atividade rende XP pela duração, tipo e esforço, e soma em Força, Resistência, Agilidade e Técnica. Acima de 150 XP no mesmo dia o ganho cai, com teto de 300 por dia.")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.85))
            }
            GMSection("Evolução") {
                Text("Nas evoluções para Atleta e Lenda, o atributo que você mais treinou na fase decide a forma.")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.85))
            }
            GMSection("Amigos") {
                Text("Mande força para quem está treinando, chame para treinar junto e converse pelas mensagens. Reações nos seus check-ins chegam no sino da tela inicial.")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.85))
            }
        }
    }
}

// MARK: - Diagnóstico e desenvolvimento

struct DiagnosticsSettingsPage: View {
    @Environment(\.dismiss) private var dismiss
    @State private var access = AccessStore.shared
    @State private var moderation = ModerationStore.shared
    #if DEBUG
    @State private var tourState = OnboardingCoordinator.shared.persistence.state
    #endif
    /// Fecha os Ajustes inteiros (o tutorial abre na tela principal)
    let closeSettings: () -> Void

    var body: some View {
        GMScreen("Diagnóstico", back: true, bottomInset: 40) {
            if access.can(.diagnosticsRead) {
                GMSection(footer: "Visível só para a role DEVELOPER.") {
                    GMValueRow(label: "Backend", value: Backend.mode == .mock ? "Simulado" : "CloudKit")
                    GMDivider()
                    GMValueRow(label: "Origem das roles", value: roleSourceText)
                    GMDivider()
                    GMValueRow(label: "Moderação pendente", value: "\(moderation.outbox.count)")
                    GMDivider()
                    GMValueRow(label: "Erro das ligas", value: LeagueRemoteStore.shared.lastError ?? "Nenhum")
                    GMDivider()
                    GMValueRow(label: "Caixa de entrada", value: InboxStore.shared.lastError ?? "OK")
                }
            }
            #if DEBUG
            GMSection("Desenvolvimento", footer: "Só existe em builds de desenvolvimento. Não cria nem apaga dados. Estado do tutorial: \(Self.describe(tourState)).") {
                GMRow(icon: "play.circle", iconTint: Theme.accent, title: "Testar onboarding", subtitle: "Volta à primeira utilização e abre do início") {
                    OnboardingCoordinator.shared.restartForTesting()
                    closeSettings()
                }
                GMDivider()
                GMRow(icon: "arrow.counterclockwise", title: "Mostrar na próxima abertura", subtitle: "Só zera o estado, para testar o gatilho automático") {
                    OnboardingCoordinator.shared.resetForTesting()
                    tourState = OnboardingCoordinator.shared.persistence.state
                }
                GMDivider()
                GMRow(icon: "tray.2", title: "Recomeçar mensagens simuladas", subtitle: "Volta as conversas de exemplo") {
                    MockInboxBackend.reset()
                    UserDefaults.standard.removeObject(forKey: InboxStore.notifiedKey)
                    Task { await InboxStore.shared.refresh() }
                }
            }
            #endif
        }
    }

    private var roleSourceText: String {
        guard case let .resolved(_, _, source) = access.context else { return "Carregando" }
        switch source {
        case .assigned: return "Atribuição"
        case .standard: return "Padrão (USER)"
        case .fallback: return "Falha na consulta (só USER)"
        }
    }

    #if DEBUG
    private static func describe(_ state: OnboardingState) -> String {
        switch state {
        case .notPresented: "não apresentado"
        case .inProgress(let step): "em andamento (\(step))"
        case .completed: "concluído"
        case .dismissed: "pulado"
        }
    }
    #endif
}
