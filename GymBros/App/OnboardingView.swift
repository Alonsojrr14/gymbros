import SwiftUI

struct OnboardingView: View {
    @AppStorage("trainerName") private var trainerName = ""
    @AppStorage("lastFormID") private var lastFormID = ""
    @State private var name = ""
    @State private var received = false
    /// Último passo: explica o treino ao vivo (vem ligado; dá para desligar aqui, em Mapa > Ajustes ou em cada treino)
    @State private var liveStep = false
    @State private var shareLive = LiveShare.defaultOn
    @State private var agreed = Terms.isAccepted()
    private let askConsent = !Terms.isAccepted()
    @FocusState private var focused: Bool

    private var nameOK: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if liveStep { liveView.transition(.opacity) } else { eggView.transition(.opacity) }
        }
        .onAppear { focused = true }
    }

    private var liveView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 54, weight: .bold)).foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text("Treine ao vivo com os amigos")
                .gmFont(28, weight: .heavy, design: .rounded, relativeTo: .title).multilineTextAlignment(.center)
            Text("Enquanto você está num treino, seus amigos veem no mapa onde você está treinando, a atividade e o exercício atual, e podem mandar força ou chamar para treinar junto. Fora do treino, nada é compartilhado.")
                .multilineTextAlignment(.center).foregroundStyle(Theme.dim)
                .padding(.horizontal, 32)
            GMToggle(title: "Compartilhar treino ao vivo", subtitle: "Dá para mudar em cada treino, no chip \"Ao vivo\", ou em Mapa > Ajustes.", isOn: $shareLive)
                .padding(16)
                .background(Theme.card, in: .rect(cornerRadius: Theme.radiusL))
                .padding(.horizontal, 24)
            Spacer()
            GMButton("Começar a jornada", action: start)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
        }
    }

    private var eggView: some View {
        VStack(spacing: 28) {
            Spacer()
            Text(received ? "Este ovo é seu!" : "GymBros")
                .gmFont(34, weight: .heavy, design: .rounded, relativeTo: .largeTitle).lineLimit(1).minimumScaleFactor(0.6)
                .contentTransition(.numericText())

            LivingMonster(form: .egg, progress: received ? 0.4 : 0.1)
                .frame(width: 180, height: 180)
                .scaleEffect(received ? 1.1 : 0.9)

            Text(received
                 ? "Dentro dele está o seu bro, seu parceiro de treino. Ele choca com seus treinos: musculação, corrida, vôlei, o que você fizer conta. E o jeito que você treina decide no que ele vai se transformar."
                 : "Todo treinador começa com um ovo. Como você se chama?")
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.dim)
                .padding(.horizontal, 32)

            if !received {
                TextField("Seu nome", text: $name)
                    .focused($focused)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .padding()
                    .background(Theme.card, in: .rect(cornerRadius: Theme.radiusM))
                    .padding(.horizontal, 32)
                    // O ✓ do teclado só fecha o teclado; avançar é pelo botão
                    .onSubmit { focused = false }
                if askConsent { LegalConsent(accepted: $agreed).padding(.horizontal, 24) }
            }
            Spacer()

            Button(action: received ? { withAnimation(.snappy) { liveStep = true } } : receive) {
                Text(received ? "Continuar" : "Receber meu ovo")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.accent, in: .rect(cornerRadius: Theme.radiusL))
                    .foregroundStyle(.black)
            }
            .disabled(!nameOK || !agreed)
            .opacity(nameOK && agreed ? 1 : 0.5)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
    }

    private func receive() {
        guard nameOK, agreed else { return }
        Terms.accept()
        focused = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.spring(duration: 0.6)) { received = true }
    }

    private func start() {
        UserDefaults.standard.set(shareLive, forKey: LiveShare.key)
        lastFormID = MonsterForm.egg.id
        trainerName = name.trimmingCharacters(in: .whitespaces)
    }
}
