import SwiftUI

// Depois do tutorial, uma pergunta só: o que você quer fazer aqui (criar uma liga, entrar numa com código ou só
// acompanhar seus treinos). E, a cada versão nova, o que mudou.

enum StartIntent: String, CaseIterable, Identifiable {
    case create, join, solo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .create: "Criar uma liga e chamar a galera"
        case .join: "Entrar numa liga com código"
        case .solo: "Só acompanhar meus treinos"
        }
    }

    var detail: String {
        switch self {
        case .create: "Clube ou desafio, com ranking, regras e o bro de cada um."
        case .join: "Alguém te passou um código? Entra direto."
        case .solo: "Treino guiado, metas e o seu bro evoluindo. Dá para entrar em ligas depois."
        }
    }

    var icon: String {
        switch self {
        case .create: "trophy.fill"
        case .join: "ticket.fill"
        case .solo: "figure.strengthtraining.traditional"
        }
    }
}

enum StartIntentRouter {
    static let askedKey = "intent.asked"
    /// A tela de ligas abre criar ou entrar
    static let createLeague = Notification.Name("gymbros.createLeague")
    static let joinLeague = Notification.Name("gymbros.joinLeague")

    static var asked: Bool { UserDefaults.standard.bool(forKey: askedKey) }
}

struct StartIntentSheet: View {
    let pick: (StartIntent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("O que você quer fazer aqui?").font(.title3.bold())
            ForEach(StartIntent.allCases) { i in
                Button { pick(i) } label: {
                    HStack(spacing: 12) {
                        GMIconTile(icon: i.icon, tint: Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(i.title).font(.subheadline.weight(.semibold))
                            Text(i.detail).font(.caption).foregroundStyle(Theme.dim)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.dim)
                    }
                    .padding(12)
                    .background(Theme.raised, in: .rect(cornerRadius: Theme.radius))
                    .foregroundStyle(.white)
                }
                .buttonStyle(GMPress())
            }
        }
    }
}

// MARK: - What's New

struct WhatsNew {
    /// Mude a cada versão com novidades; quem já viu esta não vê de novo
    static let version = "2026.10.21"
    static let seenKey = "whatsNew.seen"

    static let items: [(String, String, String)] = [
        ("checkmark.seal.fill", "Check-in verificado", "Ligas com câmera do app, hora da foto, visita na academia, revisão do dono e pose do dia."),
        ("trophy.fill", "Clubes e desafios", "Campeões da semana, do mês e do ano, desafios dentro do clube e o treino do dia."),
        ("rectangle.stack.fill", "Deck e feed", "Os check-ins que você não viu, um por vez, e o feed de tudo num lugar só."),
        ("person.2.fill", "Rotinas públicas", "Curta e salve as rotinas dos bros; publique as suas."),
        ("flame.fill", "Metas e constância", "Metas com sequência, recordes de constância e a retrospectiva em vídeo."),
        ("figure.run", "Modo guiado", "Uma série por vez, e remo, esteira e bike por distância e tempo."),
    ]

    /// Mostra uma vez por versão, só para quem já usava o app (quem é novo vê o tutorial)
    static var shouldShow: Bool {
        let d = UserDefaults.standard
        return d.string(forKey: seenKey) != version
    }

    static func markSeen() { UserDefaults.standard.set(version, forKey: seenKey) }
}

struct WhatsNewView: View {
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Novidades no GymBros").font(.title3.bold())
            ForEach(WhatsNew.items, id: \.1) { icon, title, detail in
                HStack(alignment: .top, spacing: 12) {
                    GMIconTile(icon: icon, tint: Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.subheadline.weight(.semibold))
                        Text(detail).font(.caption).foregroundStyle(Theme.dim)
                    }
                }
            }
            GMButton("Bora", icon: "checkmark", action: close)
        }
    }
}
