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
        }
    }

    private func reset() {
        try? context.delete(model: Activity.self)
        try? context.save()
        monsterNick = ""
        discovered = ""
        lastFormID = ""
        trainerName = ""
        dismiss()
    }
}
