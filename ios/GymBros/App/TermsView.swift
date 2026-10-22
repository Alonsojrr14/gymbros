import SwiftUI

/// Termos de uso (EULA). O mesmo texto vai para a web em docs/termos.md.
/// Mudou algo que a pessoa precisa aceitar de novo: suba `version`.
enum Terms {
    static let url = URL(string: "https://alonsojrr14.github.io/gymbros/termos/")!
    static let updated = "19 de outubro de 2026"
    static let version = 2
    static let acceptedKey = "termsAcceptedVersion", acceptedAtKey = "termsAcceptedAt"
    static let defaultsKeys = [acceptedKey, acceptedAtKey]

    static let sections: [(title: String, text: String)] = [
        ("Resumo", "Estes termos valem para ligas, amigos, recados, comentários, check-ins e o perfil público do GymBros, e complementam o Contrato de Licença de Usuário Final padrão da Apple. O GymBros usa uma conta: treinos, bros e o resto do progresso ficam vinculados a ela. O aceite destes termos e da política de privacidade é pedido no primeiro acesso, antes de receber o seu ovo."),
        ("Tolerância zero", "O GymBros não tolera conteúdo ofensivo nem usuários abusivos. É proibido publicar ofensas, assédio, ameaças, discurso de ódio ou discriminação, nudez ou conteúdo sexual, violência, spam e qualquer coisa ilegal, seja em check-ins, fotos, recados, comentários, nome, @usuário ou bio."),
        ("Filtro de palavras", "Antes de enviar, o app confere o texto contra uma lista de termos ofensivos. Se encontrar algum, nada é enviado e você pode ajustar o texto. O filtro não pega tudo, por isso as denúncias continuam valendo."),
        ("Denunciar e bloquear", "Em check-ins, fotos, comentários, recados e perfis de outras pessoas, use \"Denunciar\" para mandar o conteúdo para análise: ele some na hora para você. Use \"Bloquear\" para não ver mais nada de alguém: a amizade é desfeita e a pessoa some de feeds, comentários, mural, amigos e mapa. Para desbloquear, vá em Ajustes > Privacidade > Usuários bloqueados."),
        ("Análise em até 24 h", "Toda denúncia é analisada em até 24 horas. Conteúdo que viola estes termos é removido para todos, e quem o publicou é expulso: a conta é suspensa ou excluída e deixa de aparecer em ligas e amigos."),
        ("O que você publica", "Você é responsável pelo que publica e precisa ter direito de usar as fotos e os textos que envia. O que você publica aparece para quem participa das suas ligas e para os seus amigos. Com o treino ao vivo ligado (o padrão), você aceita que os seus amigos vejam onde você está treinando enquanto o treino durar; dá para desligar em cada treino, no chip \"Ao vivo\", ou em Mapa > Ajustes. Ao convidar um amigo para treinar junto numa academia salva, você aceita enviar a ele o nome e a localização (coordenadas) dessa academia. Dá para apagar posts, recados e comentários a qualquer momento, ou a conta inteira em Ajustes > Conta."),
        ("Saúde", "O GymBros não substitui orientação médica ou de um profissional de educação física. Treine dentro dos seus limites."),
        ("Idade", "O GymBros não é direcionado a menores de 13 anos."),
        ("Mudanças", "Se estes termos mudarem, o app pede um novo aceite na próxima vez que você abrir."),
        ("Privacidade", "O que o app guarda e para quê está na política de privacidade, em Ajustes > Privacidade."),
        ("Contato", "Para denunciar algo fora do app ou tirar dúvidas, abra uma issue em github.com/Alonsojrr14/gymbros."),
    ]

    static func isAccepted(_ defaults: UserDefaults = .standard, version: Int = version) -> Bool {
        defaults.integer(forKey: acceptedKey) >= version
    }

    static func accept(_ defaults: UserDefaults = .standard, version: Int = version, at date: Date = .now) {
        defaults.set(version, forKey: acceptedKey)
        defaults.set(date, forKey: acceptedAtKey)
    }

    /// Conta, termos aceitos e permissão: só assim um check-in é publicado
    @MainActor static var canPublish: Bool { AuthStore.shared.isSignedIn && isAccepted() && AccessStore.shared.can(.checkInsPublish) }
}

struct TermsView: View {
    var body: some View {
        GMModal("Termos de uso") { TermsText() }
    }
}

private struct TermsText: View {
    var body: some View {
        ForEach(Terms.sections, id: \.title) { section in
            GMSection(section.title) {
                Text(section.text)
                    .font(.footnote)
                    .foregroundStyle(Theme.dim)
            }
        }
        GMSection(footer: "Atualizados em \(Terms.updated).") {
            Link(destination: Terms.url) {
                Label("Ver na web", systemImage: "link").font(.subheadline.weight(.semibold))
            }
        }
    }
}

/// Aceite dos termos de uso e da política de privacidade: uma caixa para cada documento.
/// A caixa (e o texto) só marca e desmarca; o documento abre só pelo link sublinhado.
struct LegalConsent: View {
    @Binding var accepted: Bool
    @State private var agreed: Set<LegalDoc> = []
    @State private var open: LegalDoc?

    var body: some View {
        VStack(spacing: 10) {
            ForEach(LegalDoc.allCases) { row($0) }
        }
        .gmModal(item: $open) { doc in
            switch doc {
            case .terms: TermsView()
            case .privacy: PrivacyPolicyView()
            }
        }
        .onChange(of: agreed) { _, a in accepted = a.count == LegalDoc.allCases.count }
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "gymbros-legal", let doc = LegalDoc(rawValue: url.host() ?? "") else { return .systemAction }
            open = doc
            return .handled
        })
    }

    private func row(_ doc: LegalDoc) -> some View {
        let on = agreed.contains(doc)
        return HStack(spacing: 12) {
            Image(systemName: on ? "checkmark.square.fill" : "square")
                .font(.title2)
                .foregroundStyle(on ? Theme.accent : .white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 44, height: 44)
            Text(label(doc))
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6).padding(.horizontal, 8)
        .background(Theme.card, in: .rect(cornerRadius: Theme.radiusL))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusL).stroke(on ? Theme.accent.opacity(0.6) : Theme.stroke))
        .contentShape(Rectangle())
        .onTapGesture {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.snappy) { if on { agreed.remove(doc) } else { agreed.insert(doc) } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Li e concordo com \(doc.article) \(doc.title)")
        .accessibilityValue(on ? "Marcado" : "Desmarcado")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Ler \(doc.article) \(doc.title)") { open = doc }
    }

    /// "Li e concordo com os Termos de uso", com o nome do documento como link
    private func label(_ doc: LegalDoc) -> AttributedString {
        var text = AttributedString("Li e concordo com \(doc.article) ")
        var link = AttributedString(doc.title)
        link.link = URL(string: "gymbros-legal://\(doc.rawValue)")
        link.foregroundColor = Theme.accent
        link.underlineStyle = .single
        text.append(link)
        return text
    }
}

enum LegalDoc: String, CaseIterable, Identifiable {
    case terms, privacy
    var id: String { rawValue }
    var title: String { self == .terms ? "Termos de uso" : "Política de privacidade" }
    var article: String { self == .terms ? "os" : "a" }
}

/// Aceite pedido antes de publicar (folha do TermsGate)
struct TermsAcceptView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var accepted = false

    var body: some View {
        GMModal("Termos e privacidade") {
            ConsentIntro()
            LegalConsent(accepted: $accepted)
            GMButton("Aceitar e continuar", icon: "checkmark", enabled: accepted) {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                Terms.accept()
                dismiss()
            }
        }
    }
}

/// Na entrada do app, para quem já tem ovo e ainda não aceitou esta versão (sem botão de fechar)
struct TermsRequiredView: View {
    @State private var accepted = false

    var body: some View {
        GMScreen("Termos e privacidade", subtitle: Terms.version > 1 ? "Os termos mudaram. Leia e aceite para continuar." : nil,
                 bottomInset: 40) {
            ConsentIntro()
            LegalConsent(accepted: $accepted)
            GMButton("Aceitar e continuar", icon: "checkmark", enabled: accepted) {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                Terms.accept()
            }
        }
    }
}

private struct ConsentIntro: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "checkmark.shield.fill").font(.system(size: 36)).foregroundStyle(Theme.accent)
            Text("Antes de continuar").gmFont(22, weight: .heavy, design: .rounded, relativeTo: .title2)
            Text("Abra cada documento para ler e marque que concorda. O GymBros tem tolerância zero para conteúdo ofensivo e abuso.")
                .font(.subheadline).foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Roda uma ação de publicar só depois do aceite dos termos (pede uma vez por versão).
/// Uso: `@State private var terms = TermsGate()`, `terms.run { ... }` e `.termsGate($terms)`.
struct TermsGate {
    fileprivate var pending: (() -> Void)?
    fileprivate var asking = false

    mutating func run(defaults: UserDefaults = .standard, _ action: @escaping () -> Void) {
        if Terms.isAccepted(defaults) {
            action()
        } else {
            pending = action
            asking = true
        }
    }

    var isWaiting: Bool { asking }
}

extension View {
    /// A ação espera a tela dos termos fechar: assim ela pode fechar ou abrir outras telas sem conflito
    func termsGate(_ gate: Binding<TermsGate>) -> some View {
        fullScreenCover(isPresented: gate.asking, onDismiss: {
            let action = gate.wrappedValue.pending
            gate.wrappedValue.pending = nil
            if Terms.isAccepted() { action?() }
        }) {
            TermsAcceptView().preferredColorScheme(.dark).tint(Theme.accent)
        }
    }
}

/// No lugar do conteúdo social, enquanto os termos não foram aceitos
struct TermsPrompt: View {
    var message = "Ligas, amigos e o perfil público seguem regras de convivência, com tolerância zero para conteúdo ofensivo e abuso."
    @State private var gate = TermsGate()

    var body: some View {
        GMCard {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.shield").font(.system(size: 40)).foregroundStyle(Theme.accent)
                Text("Aceite os termos para continuar").font(.headline)
                Text(message).font(.subheadline).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                GMButton("Ler e aceitar os termos", icon: "doc.text") { gate.run {} }
            }
            .frame(maxWidth: .infinity)
        }
        .termsGate($gate)
    }
}
