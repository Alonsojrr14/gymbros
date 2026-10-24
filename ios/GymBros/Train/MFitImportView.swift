import SwiftData
import SwiftUI

/// Importa e sincroniza os treinos do MFIT em "Minhas rotinas".
/// Login → prévia → materializa (Routine/RoutineItem + CustomExercise + vídeo). Idempotente por sourceID.
/// Com "manter conectado", a conta fica no Keychain e o app sincroniza sozinho.
struct MFitImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var mail = ""
    @State private var senha = ""
    @State private var keepConnected = true
    @State private var connected = MFitCredentials.isStored
    @State private var phase: Phase = .form
    @State private var plans: [MFitPlan] = []
    @State private var savedDays = 0
    @State private var error: String?
    @AppStorage(MFitSync.lastSyncKey) private var lastSync = 0.0

    enum Phase: Equatable { case form, loading, preview, saving, done }

    var body: some View {
        GMModal("MFIT") {
            switch phase {
            case .form:
                if connected { connectedSection } else { formSection }
            case .loading:
                loadingView
            case .preview, .saving:
                previewSection
            case .done:
                doneSection
            }
            if let error {
                GMCard { Label(error, systemImage: "exclamationmark.triangle.fill").font(.subheadline).foregroundStyle(Theme.danger) }
            }
        }
    }

    // MARK: Estados

    private var intro: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.and.arrow.down.on.square.fill").font(.title).foregroundStyle(Theme.accent)
            Text("Traga os treinos do seu personal do MFIT. Eles viram rotinas aqui, com os vídeos e a prescrição.")
                .font(.subheadline).foregroundStyle(Theme.dim)
        }
    }

    private var formSection: some View {
        Group {
            GMCard { intro }
            GMSection("Entrar no MFIT", footer: "Usamos sua conta só para buscar os seus treinos.") {
                GMTextField(placeholder: "E-mail do MFIT", text: $mail)
                GMSecureField(placeholder: "Senha do MFIT", text: $senha)
            }
            GMCard {
                GMToggle(title: "Manter conectado", subtitle: "Sincroniza sozinho quando o personal atualizar", isOn: $keepConnected)
            }
            GMButton("Buscar treinos", icon: "magnifyingglass",
                     enabled: !mail.isEmpty && !senha.isEmpty) { Task { await load() } }
        }
    }

    private var connectedSection: some View {
        Group {
            GMCard { intro }
            GMSection("Conectado", footer: lastSync > 0 ? "Última sincronização: \(syncText)" : nil) {
                GMRow(icon: "checkmark.seal.fill", iconTint: Theme.accent, title: "Conta MFIT conectada",
                      subtitle: "Sincroniza automaticamente")
            }
            GMButton("Sincronizar agora", icon: "arrow.triangle.2.circlepath") { Task { await syncNow() } }
            GMButton("Desconectar", icon: "xmark.circle", kind: .secondary) {
                MFitCredentials.clear()
                connected = false
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView().tint(Theme.accent).scaleEffect(1.3)
            Text("Buscando seus treinos…").font(.subheadline).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }

    private var previewSection: some View {
        Group {
            Text("Confira e adicione às suas rotinas").font(.headline)
            ForEach(plans, id: \.sourceID) { plan in
                GMCard {
                    Text(plan.name.isEmpty ? "Plano" : plan.name).font(.headline)
                    let meta = [plan.goal, plan.difficulty].filter { !$0.isEmpty }.joined(separator: " · ")
                    if !meta.isEmpty { Text(meta).font(.caption).foregroundStyle(Theme.dim) }
                    ForEach(plan.days, id: \.sourceID) { day in
                        HStack(spacing: 10) {
                            if !day.weekday.isEmpty {
                                Text(String(day.weekday.prefix(3)).uppercased())
                                    .font(.caption2.bold()).foregroundStyle(Theme.accent)
                                    .frame(width: 34, height: 22)
                                    .background(Theme.accent.opacity(0.15), in: .capsule)
                            }
                            Text(day.name).font(.subheadline.weight(.medium))
                            Spacer()
                            Text("\(day.exerciseCount)").font(.caption).foregroundStyle(Theme.dim)
                        }
                    }
                }
            }
            GMButton(phase == .saving ? "Adicionando…" : "Adicionar às minhas rotinas", icon: "checkmark",
                     enabled: phase != .saving) { Task { await save() } }
        }
    }

    private var doneSection: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 52)).foregroundStyle(Theme.accent)
            Text("\(savedDays) rotina(s) em Minhas rotinas").font(.headline)
            if keepConnected || connected {
                Text("Sincronização automática ativada.").font(.subheadline).foregroundStyle(Theme.dim)
            }
            GMButton("Fechar") { dismiss() }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var syncText: String {
        Date(timeIntervalSince1970: lastSync).formatted(date: .abbreviated, time: .shortened)
    }

    // MARK: Ações

    private func load() async {
        error = nil
        phase = .loading
        do {
            let client = MFitClient()
            try await client.login(mail: mail, senha: senha)
            plans = try await client.importPlans()
            phase = plans.isEmpty ? .form : .preview
            if plans.isEmpty { error = "Nenhum treino encontrado nessa conta." }
        } catch {
            self.error = error.localizedDescription
            phase = .form
        }
    }

    private func save() async {
        phase = .saving
        MFitMaterializer(context: context).materializeAll(plans)
        savedDays = plans.reduce(0) { $0 + $1.days.count }
        if keepConnected {
            MFitCredentials.save(mail: mail, senha: senha)
            connected = true
        }
        lastSync = Date.now.timeIntervalSince1970
        senha = ""
        phase = .done
    }

    private func syncNow() async {
        error = nil
        phase = .loading
        do {
            let count = try await MFitSync.sync(context: context)
            savedDays = count
            phase = .done
        } catch {
            self.error = error.localizedDescription
            phase = .form
        }
    }
}
