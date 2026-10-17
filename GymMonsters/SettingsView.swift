import SwiftData
import SwiftUI
import UserNotifications

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
    @AppStorage("barCountsBar") private var barCountsBar = false
    @State private var healthOn = HealthSync.enabled
    @State private var healthStatus: String?
    @State private var syncing = false
    @State private var exportDoc: BackupDocument?
    @State private var exporting = false
    @State private var importing = false
    @State private var pendingRestore: Backup?
    @State private var backupMessage: String?

    var body: some View {
        GMModal("Ajustes", cancel: "Fechar") {
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
                GMToggle(title: "Notificação no fim do descanso",
                         subtitle: "O Live Activity já mostra o descanso; ligue só se quiser o alerta também", isOn: $restNotification)
            }
            GMSection("Carga na barra", footer: "Na musculação é comum anotar só as anilhas. Exercícios de CrossFit sempre contam o total com a barra; polia e máquina não têm barra.") {
                GMSegmented(options: [(false, "Só anilhas"), (true, "Total com barra")], selection: $barCountsBar)
            }

            if HealthSync.available {
                GMSection("Apple Saúde", footer: "Corridas, caminhadas, vôlei e outros treinos do iPhone ou Apple Watch viram atividades automaticamente ao abrir o app (na primeira vez, os últimos \(HealthSync.firstImportDays) dias). Treinos que coincidem com algo já registrado aqui não contam duas vezes. Só leitura.") {
                    GMToggle(title: "Importar treinos do Saúde", isOn: $healthOn)
                        .onChange(of: healthOn) { _, on in Task { await toggleHealth(on) } }
                    if healthOn {
                        GMButton(syncing ? "Sincronizando…" : "Sincronizar agora", icon: "arrow.triangle.2.circlepath",
                                 kind: .secondary, small: true, enabled: !syncing) { Task { await syncNow() } }
                    }
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

            GMSection(footer: "Apaga todas as atividades e bros e devolve um ovo novo. Ligas e rotinas continuam.") {
                GMRow(icon: "arrow.counterclockwise", iconTint: Theme.danger, title: "Recomeçar jornada") { confirmReset = true }
            }
            GMSection("Como funciona") {
                Text("Cada atividade rende XP pela duração, tipo e esforço, e soma em Força, Resistência, Agilidade e Técnica. Acima de 150 XP no mesmo dia o ganho cai, com teto de 300 por dia. Nas evoluções para Champion e Ultimate, o atributo que você mais treinou na fase decide a forma.")
                    .font(.footnote)
                    .foregroundStyle(Theme.dim)
            }
        }
        .gmActions(isPresented: $confirmReset, title: "Recomeçar a jornada?",
                   message: "Apaga atividades e bros e devolve um ovo novo.",
                   actions: [GMAction("Recomeçar", icon: "arrow.counterclockwise", destructive: true, action: reset)])
        .gmActions(isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
                   title: "Restaurar backup?", message: restoreTitle,
                   actions: [GMAction("Substituir tudo", icon: "square.and.arrow.down", destructive: true) {
                       guard let b = pendingRestore else { return }
                       do {
                           try b.restore(into: context)
                           backupMessage = "Backup restaurado: \(b.activities.count) atividades."
                       } catch {
                           backupMessage = "Falha ao restaurar: \(error.localizedDescription)"
                       }
                       pendingRestore = nil
                   }])
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

    private func reset() {
        try? context.delete(model: Activity.self)
        try? context.save()
        // Só treinos do Saúde feitos daqui para frente alimentam o ovo novo
        HealthSync.lastSync = .now
        // Volta a ter um monstro só: o novo ovo inicial é criado ao reabrir
        try? context.delete(model: Monster.self)
        try? context.save()
        MainMonster.id = nil
        UserDefaults.standard.removeObject(forKey: "monsterNick")
        discovered = ""
        lastFormID = ""
        trainerName = ""
        dismiss()
    }
}
