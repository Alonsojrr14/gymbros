import StoreKit
import SwiftUI

// GymBros Pro (assinatura pela App Store) e o "Vem aí" (recursos que ainda não existem, para medir o interesse).
// Comprar de verdade depende do app na App Store com a conta paga do Apple Developer: até lá `ProStore.enforced`
// fica desligado e nada é bloqueado.

/// O que o Pro libera
enum ProFeature: String, CaseIterable, Identifiable {
    case unlimitedLeagues, scoringLimits, moderators, export, stats, retrospective

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unlimitedLeagues: "Ligas ilimitadas"
        case .scoringLimits: "Limites de pontuação"
        case .moderators: "Moderadores na liga"
        case .export: "Exportar os dados da liga"
        case .stats: "Recordes e constância completos"
        case .retrospective: "Retrospectiva em vídeo"
        }
    }

    var detail: String {
        switch self {
        case .unlimitedLeagues: "Sem Pro, você cria até \(ProStore.freeLeagues) ligas."
        case .scoringLimits: "Teto de pontos por dia, semana, mês e total, por pessoa e por time."
        case .moderators: "Divida a revisão, os pedidos e as remoções com quem você escolher."
        case .export: "Todos os check-ins da liga numa planilha (CSV)."
        case .stats: "Melhor dia, semana, mês e ano, sequências e o seu jeito de treinar."
        case .retrospective: "As fotos do ano num vídeo com os seus números."
        }
    }

    var symbol: String {
        switch self {
        case .unlimitedLeagues: "trophy.fill"
        case .scoringLimits: "gauge.with.dots.needle.67percent"
        case .moderators: "shield.lefthalf.filled"
        case .export: "tablecells"
        case .stats: "flame.fill"
        case .retrospective: "film.stack"
        }
    }
}

@MainActor @Observable
final class ProStore {
    static let shared = ProStore()
    static let productIDs = ["com.alonsoalmeida.gymbros.pro.mensal", "com.alonsoalmeida.gymbros.pro.anual"]
    static let freeLeagues = 2
    /// Liga quando o app estiver na App Store com os produtos cadastrados; desligado, tudo fica liberado
    static let enforced = false

    private(set) var isPro = false
    private(set) var products: [Product] = []

    func allows(_ f: ProFeature) -> Bool { !Self.enforced || isPro }

    func refresh() async {
        products = (try? await Product.products(for: Self.productIDs)) ?? []
        var pro = false
        for await r in Transaction.currentEntitlements {
            if case .verified(let t) = r, Self.productIDs.contains(t.productID), t.revocationDate == nil { pro = true }
        }
        isPro = pro
    }

    func buy(_ p: Product) async throws {
        if case .success(.verified(let t)) = try await p.purchase() { await t.finish() }
        await refresh()
    }
}

/// Benefícios do Pro e a assinatura
struct ProPage: View {
    @State private var store = ProStore.shared
    @State private var error: String?

    var body: some View {
        GMScreen("GymBros Pro", back: true) {
            Text("Para quem organiza as ligas e quer ver tudo da própria constância.").font(.subheadline).foregroundStyle(Theme.dim)
            GMSection {
                ForEach(Array(ProFeature.allCases.enumerated()), id: \.element) { i, f in
                    if i > 0 { GMDivider() }
                    GMRow(icon: f.symbol, iconTint: Theme.accent, title: f.title, subtitle: f.detail)
                }
            }
            if store.isPro {
                GMCard { Label("Você é Pro. Valeu, bro!", systemImage: "checkmark.seal.fill").font(.headline).foregroundStyle(Theme.accent) }
            } else if store.products.isEmpty {
                Text(ProStore.enforced ? "Não deu para carregar os planos agora." : "A assinatura chega com a versão da App Store. Até lá, tudo do Pro já está liberado para você.")
                    .font(.footnote).foregroundStyle(Theme.dim)
            } else {
                ForEach(store.products, id: \.id) { p in
                    GMButton("\(p.displayName) · \(p.displayPrice)", icon: "star.fill") {
                        Task { do { try await store.buy(p) } catch { self.error = error.localizedDescription } }
                    }
                }
                GMButton("Restaurar compras", kind: .ghost) { Task { try? await AppStore.sync(); await store.refresh() } }
            }
            if let error { Text(error).font(.footnote).foregroundStyle(Theme.warning) }
        }
        .task { await store.refresh() }
    }
}

// MARK: - Vem aí

struct ComingFeature: Identifiable {
    let id: String
    let emoji: String
    let title: String
    let detail: String

    static let all = [
        ComingFeature(id: "servidor", emoji: "🌎", title: "Ligas com gente de verdade", detail: "Convites, check-ins e mural chegando para os seus amigos, sem participantes simulados."),
        ComingFeature(id: "parceiros", emoji: "🏢", title: "Check-in automático na academia", detail: "Visita verificada na academia parceira vira check-in sozinha."),
        ComingFeature(id: "premios", emoji: "🎁", title: "Prêmios para o campeão", detail: "Recompensas para quem vencer a semana, o mês ou o desafio."),
        ComingFeature(id: "ligas-publicas", emoji: "📍", title: "Ligas públicas perto de você", detail: "Ache desafios abertos na sua cidade e entre sem código."),
    ]
}

enum ComingFeedback {
    static let key = "featureFeedback"

    static func all(_ d: UserDefaults = .standard) -> [String: Bool] { d.dictionary(forKey: key) as? [String: Bool] ?? [:] }

    static func set(_ id: String, interested: Bool?, _ d: UserDefaults = .standard) {
        var a = all(d)
        a[id] = interested
        d.set(a, forKey: key)
    }
}

/// O que está por vir, com "Quero!" e "Não pra mim"
struct ComingSoonPage: View {
    @State private var votes = ComingFeedback.all()

    var body: some View {
        GMScreen("Vem aí", back: true) {
            Text("Ideias que ainda não existem. Diga o que você quer primeiro: o mais pedido sai antes.").font(.subheadline).foregroundStyle(Theme.dim)
            ForEach(ComingFeature.all) { f in
                GMCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 12) {
                            Text(f.emoji).font(.title)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(f.title).font(.headline)
                                Text(f.detail).font(.subheadline).foregroundStyle(Theme.dim)
                            }
                        }
                        HStack(spacing: 10) {
                            GMButton(votes[f.id] == true ? "Você quer ✅" : "Quero!", kind: votes[f.id] == true ? .primary : .secondary, small: true) { vote(f.id, true) }
                            GMButton(votes[f.id] == false ? "Anotado" : "Não pra mim", kind: .ghost, small: true) { vote(f.id, false) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func vote(_ id: String, _ yes: Bool) {
        let new: Bool? = votes[id] == yes ? nil : yes
        ComingFeedback.set(id, interested: new)
        votes = ComingFeedback.all()
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
