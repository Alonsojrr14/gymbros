import SwiftData
import SwiftUI
import UserNotifications
import WidgetKit

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("trainerName") private var trainerName = ""
    @Query(sort: \Monster.createdAt) private var monsters: [Monster]
    @AppStorage("lastFormID") private var lastFormID = ""
    @AppStorage("discovered") private var discovered = ""
    @State private var confirmReset = false
    @AppStorage("remindersOn") private var remindersOn = false
    @AppStorage("reminderMinute") private var reminderMinute = 18 * 60
    @AppStorage("reminderRoutineOnly") private var reminderRoutineOnly = false
    @AppStorage("restNotification") private var restNotification = false
    @AppStorage("weeklySummary") private var weeklySummary = true
    @AppStorage("autoWarmup") private var autoWarmup = true
    @State private var healthOn = HealthSync.enabled
    @State private var healthWrite = HealthSync.writeEnabled
    @State private var healthStatus: String?
    @State private var syncing = false
    @State private var exportDoc: BackupDocument?
    @State private var exporting = false
    @State private var importing = false
    @State private var pendingRestore: Backup?
    @State private var backupMessage: String?

    var body: some View {
        GMModal("Ajustes") {
            GMSection("Treinador") {
                GMTextField(placeholder: "Seu nome", text: $trainerName, capitalization: .words)
            }
            GMSection("Bro principal", footer: "Vazio usa o nome da forma atual.") {
                GMTextField(placeholder: "Apelido", text: Binding(
                    get: { mainMonster?.name ?? "" },
                    set: { mainMonster?.name = $0 }
                ), capitalization: .words)
            }
            GMSection("Lembretes", footer: "Seu bro te chama no horário escolhido, só nos dias em que você ainda não treinou.") {
                GMToggle(title: "Lembrete para treinar", isOn: $remindersOn)
                    .onChange(of: remindersOn) { _, on in
                        if on { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in } }
                    }
                if remindersOn {
                    GMDivider()
                    GMTimeField(date: Binding(
                        get: { Calendar.current.date(byAdding: .minute, value: reminderMinute, to: Calendar.current.startOfDay(for: .now))! },
                        set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); reminderMinute = (c.hour ?? 18) * 60 + (c.minute ?? 0) }
                    ))
                    GMDivider()
                    GMToggle(title: "Só em dias de rotina", isOn: $reminderRoutineOnly)
                }
                GMDivider()
                GMToggle(title: "Resumo da semana", subtitle: "Domingo às 19h: treinos, tempo, PRs e sua posição nas ligas", isOn: $weeklySummary)
                    .onChange(of: weeklySummary) { _, on in
                        if on { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in } }
                    }
                GMDivider()
                GMToggle(title: "Notificação no fim do descanso",
                         subtitle: "O Live Activity já mostra o descanso; ligue só se quiser o alerta também", isOn: $restNotification)
            }
            GMSection("Aquecimento", footer: "Ao começar uma rotina, o primeiro exercício com carga ganha 3 séries leves (40 %, 60 % e 80 % da carga). Elas não contam para recordes, progressão nem volume. No menu ⋯ de cada exercício dá para adicionar ou tirar.") {
                GMToggle(title: "Aquecimento automático", isOn: $autoWarmup)
            }

            if HealthSync.available {
                GMSection("Apple Saúde", footer: "Corridas, caminhadas, vôlei e outros treinos do iPhone ou Apple Watch viram atividades automaticamente ao abrir o app (na primeira vez, os últimos \(HealthSync.firstImportDays) dias). Treinos que coincidem com algo já registrado aqui não contam duas vezes. Gravando, o que você registra aqui (musculação, WOD, corrida…) vai para o Saúde com calorias estimadas e conta nos anéis do Fitness.") {
                    GMToggle(title: "Importar treinos do Saúde", isOn: $healthOn)
                        .onChange(of: healthOn) { _, on in Task { await toggleHealth(on) } }
                    if healthOn {
                        GMButton(syncing ? "Sincronizando…" : "Sincronizar agora", icon: "arrow.triangle.2.circlepath",
                                 kind: .secondary, small: true, enabled: !syncing) { Task { await syncNow() } }
                    }
                    GMDivider()
                    GMToggle(title: "Gravar treinos no Saúde", subtitle: "Daqui para frente; conta nos anéis", isOn: $healthWrite)
                        .onChange(of: healthWrite) { _, on in Task { await toggleWrite(on) } }
                    if let healthStatus {
                        Text(healthStatus).font(.footnote).foregroundStyle(Theme.dim)
                    }
                }
            }

            GMSection("Backup", footer: "Os dados ficam só neste iPhone. Exporte de vez em quando e guarde no Arquivos ou iCloud Drive: se o app for apagado, é assim que você recupera tudo.") {
                GMRow(icon: "square.and.arrow.up", title: "Exportar backup", chevron: true) { export() }
                GMDivider()
                GMRow(icon: "square.and.arrow.down", title: "Restaurar backup", chevron: true) { importing = true }
                if let backupMessage {
                    Text(backupMessage).font(.footnote).foregroundStyle(Theme.dim)
                }
            }

            GMSection(footer: Self.resetText + " Rotinas, lugares, medidas e seu nome continuam.") {
                GMRow(icon: "arrow.counterclockwise", iconTint: Theme.danger, title: "Recomeçar jornada") { confirmReset = true }
            }
            GMSection("Como funciona") {
                Text("Cada atividade rende XP pela duração, tipo e esforço, e soma em Força, Resistência, Agilidade e Técnica. Acima de 150 XP no mesmo dia o ganho cai, com teto de 300 por dia. Nas evoluções para Champion e Ultimate, o atributo que você mais treinou na fase decide a forma.")
                    .font(.footnote)
                    .foregroundStyle(Theme.dim)
            }
        }
        .gmActions(isPresented: $confirmReset, title: "Recomeçar a jornada?",
                   message: Self.resetText + " Não dá para desfazer.",
                   actions: [GMAction("Recomeçar", icon: "arrow.counterclockwise", destructive: true, action: reset)])
        .gmActions(isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
                   title: "Restaurar backup?", message: restoreTitle,
                   actions: pendingRestore.map { b in [GMAction("Substituir tudo", icon: "square.and.arrow.down", destructive: true) {
                       do {
                           try b.restore(into: context)
                           backupMessage = "Backup restaurado: \(b.activities.count) atividades."
                           // Os lugares mudaram: volta a monitorar os restaurados
                           if GymLocation.shared.insideGym == nil { GymLocation.shared.insideID = nil }
                           GymLocation.shared.startMonitoring()
                       } catch {
                           backupMessage = "Falha ao restaurar: \(error.localizedDescription)"
                       }
                       pendingRestore = nil
                   }] } ?? [])
        .fileExporter(isPresented: $exporting, document: exportDoc, contentType: .json,
                      defaultFilename: "GymBros-\(Date.now.formatted(.iso8601.year().month().day()))") { result in
            if case .success = result { backupMessage = "Backup salvo." }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                pendingRestore = try Backup.decoder.decode(Backup.self, from: Data(contentsOf: url))
            } catch {
                backupMessage = "Não consegui ler o arquivo: \(error.localizedDescription)"
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
            backupMessage = "Falha ao exportar: \(error.localizedDescription)"
        }
    }

    private func toggleHealth(_ on: Bool) async {
        guard on else {
            HealthSync.enabled = false
            healthStatus = "Desligado. O que já foi importado continua."
            return
        }
        do {
            try await HealthSync.requestAccess()
            HealthSync.enabled = true
            await syncNow()
        } catch {
            healthOn = false
            healthStatus = "Não consegui acesso ao Saúde: \(error.localizedDescription)"
        }
    }

    private func toggleWrite(_ on: Bool) async {
        guard on else {
            HealthSync.writeEnabled = false
            healthStatus = "Não grava mais. O que já foi para o Saúde continua lá."
            return
        }
        do {
            try await HealthSync.requestWrite()
            HealthSync.writeEnabled = true
            healthStatus = "Pronto: os próximos treinos registrados aqui vão para o Saúde."
        } catch {
            healthWrite = false
            healthStatus = "Não consegui permissão para gravar: \(error.localizedDescription)"
        }
    }

    private func syncNow() async {
        syncing = true
        defer { syncing = false }
        do {
            let r = try await HealthSync.sync(context: context)
            var parts = [r.imported.isEmpty ? "Nenhum treino novo" : "\(r.imported.count) treino(s) importado(s)"]
            if r.skippedOverlap > 0 { parts.append("\(r.skippedOverlap) já registrado(s) aqui") }
            healthStatus = parts.joined(separator: ", ") + ". Se esperava algo, confira em Ajustes do iPhone → Saúde → Acesso a Dados → GymBros."
        } catch {
            healthStatus = "Falha ao sincronizar: \(error.localizedDescription)"
        }
    }

    private var mainMonster: Monster? {
        monsters.first { $0.uuid == MainMonster.id } ?? monsters.first { $0.isStarter }
    }

    /// O que "Recomeçar jornada" faz (mesmo texto no rodapé e na confirmação)
    static let resetText = "Apaga as atividades e tudo ligado a elas (treinos guiados, check-ins no perfil e nas ligas, percursos, WODs), os bros, as conquistas já vistas e os carinhos do widget, e devolve um ovo novo. Você continua nas ligas, agora representado pelo ovo novo e com placar zerado."

    private func reset() {
        // Tudo que depende das atividades sai junto, para nada ficar apontando para atividade apagada
        let ids = Set(((try? context.fetch(FetchDescriptor<Activity>())) ?? []).map(\.uuid))
        let posts = (try? context.fetch(FetchDescriptor<LeagueCheckIn>())) ?? []
        let postIDs = Set(posts.map(\.uuid.uuidString))
        ((try? context.fetch(FetchDescriptor<CheckInComment>())) ?? []).filter { postIDs.contains($0.itemID) }.forEach(context.delete)
        posts.forEach(context.delete)
        ((try? context.fetch(FetchDescriptor<RouteRecord>())) ?? []).filter { $0.activityUUID.map(ids.contains) ?? true }.forEach(context.delete)
        ((try? context.fetch(FetchDescriptor<WodResult>())) ?? []).filter { $0.activityUUID.map(ids.contains) ?? false }.forEach(context.delete)
        // O treino em andamento (ainda sem atividade) continua
        ((try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []).filter { $0.activityUUID.map(ids.contains) ?? false }.forEach(context.delete)
        try? context.delete(model: Activity.self)
        try? context.save()
        // Só treinos do Saúde feitos daqui para frente alimentam o ovo novo
        HealthSync.lastSync = .now
        // Volta a ter um monstro só: o ovo inicial novo, que passa a representar você nas ligas
        try? context.delete(model: Monster.self)
        try? context.save()
        MainMonster.id = nil
        let d = UserDefaults.standard
        for k in ["monsterNick", "lastFormID", "discovered", "achievementsSeen"] { d.removeObject(forKey: k) }
        WidgetData.defaults?.removeObject(forKey: "pets")
        WidgetCenter.shared.reloadAllTimelines()
        Roster.ensureStarter(context: context)
        PRBook.reload()
        dismiss()
    }
}
