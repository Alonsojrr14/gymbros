import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("trainerName") private var trainerName = ""
    @AppStorage("monsterNick") private var monsterNick = ""
    @AppStorage("lastFormID") private var lastFormID = ""
    @AppStorage("discovered") private var discovered = ""
    @State private var confirmReset = false
    @State private var healthOn = HealthSync.enabled
    @State private var healthStatus: String?
    @State private var syncing = false
    @State private var exportDoc: BackupDocument?
    @State private var exporting = false
    @State private var importing = false
    @State private var pendingRestore: Backup?
    @State private var backupMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Treinador") {
                    TextField("Seu nome", text: $trainerName)
                }
                Section {
                    TextField("Apelido do monstro", text: $monsterNick)
                } footer: {
                    Text("Vazio usa o nome da forma atual.")
                }
                if HealthSync.available {
                    Section {
                        Toggle("Importar treinos do Saúde", isOn: $healthOn)
                            .onChange(of: healthOn) { _, on in Task { await toggleHealth(on) } }
                        if healthOn {
                            Button {
                                Task { await syncNow() }
                            } label: {
                                HStack {
                                    Text("Sincronizar agora")
                                    Spacer()
                                    if syncing { ProgressView() }
                                }
                            }
                            .disabled(syncing)
                        }
                        if let healthStatus {
                            Text(healthStatus).font(.footnote).foregroundStyle(Theme.dim)
                        }
                    } header: {
                        Text("Apple Saúde")
                    } footer: {
                        Text("Corridas, caminhadas, vôlei e outros treinos do iPhone ou Apple Watch viram atividades automaticamente ao abrir o app (na primeira vez, os últimos \(HealthSync.firstImportDays) dias). Treinos que coincidem com algo já registrado aqui não contam duas vezes. Só leitura.")
                    }
                }

                Section {
                    Button("Exportar backup", systemImage: "square.and.arrow.up") { export() }
                    Button("Restaurar backup", systemImage: "square.and.arrow.down") { importing = true }
                    if let backupMessage {
                        Text(backupMessage).font(.footnote).foregroundStyle(Theme.dim)
                    }
                } header: {
                    Text("Backup")
                } footer: {
                    Text("Os dados ficam só neste iPhone. Exporte de vez em quando e guarde no Arquivos ou iCloud Drive: se o app for apagado, é assim que você recupera tudo.")
                }

                Section {
                    Button("Recomeçar jornada", role: .destructive) { confirmReset = true }
                } footer: {
                    Text("Apaga todas as atividades e devolve um ovo novo.")
                }
                Section("Como funciona") {
                    Text("Cada atividade rende XP pela duração, tipo e esforço, e soma em Força, Resistência, Agilidade e Técnica. Acima de 150 XP no mesmo dia o ganho cai, com teto de 300 por dia. Nas evoluções para Champion e Ultimate, o atributo que você mais treinou na fase decide a forma.")
                        .font(.footnote)
                        .foregroundStyle(Theme.dim)
                }
            }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
            .confirmationDialog("Apagar tudo e recomeçar com um ovo?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Recomeçar", role: .destructive, action: reset)
            }
            .fileExporter(isPresented: $exporting, document: exportDoc, contentType: .json,
                          defaultFilename: "GymMonsters-\(Date.now.formatted(.iso8601.year().month().day()))") { result in
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
            .confirmationDialog(restoreTitle, isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
                                titleVisibility: .visible) {
                Button("Substituir tudo", role: .destructive) {
                    guard let b = pendingRestore else { return }
                    do {
                        try b.restore(into: context)
                        backupMessage = "Backup restaurado: \(b.activities.count) atividades."
                    } catch {
                        backupMessage = "Falha ao restaurar: \(error.localizedDescription)"
                    }
                    pendingRestore = nil
                }
            }
        }
    }

    private var restoreTitle: String {
        guard let b = pendingRestore else { return "" }
        return "Backup de \(b.exportedAt.formatted(date: .abbreviated, time: .shortened)) com \(b.activities.count) atividades. Isso substitui todos os dados atuais."
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
            healthStatus = parts.joined(separator: ", ") + ". Se esperava algo, confira em Ajustes do iPhone → Saúde → Acesso a Dados → GymMonsters."
        } catch {
            healthStatus = "Falha ao sincronizar: \(error.localizedDescription)"
        }
    }

    private func reset() {
        try? context.delete(model: Activity.self)
        try? context.save()
        // Só treinos do Saúde feitos daqui para frente alimentam o ovo novo
        HealthSync.lastSync = .now
        monsterNick = ""
        discovered = ""
        lastFormID = ""
        trainerName = ""
        dismiss()
    }
}
