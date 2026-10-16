import SwiftUI

struct OnboardingView: View {
    @AppStorage("trainerName") private var trainerName = ""
    @AppStorage("lastFormID") private var lastFormID = ""
    @State private var name = ""
    @State private var received = false
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 28) {
                Spacer()
                Text(received ? "Este ovo é seu!" : "GymMonsters")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .contentTransition(.numericText())

                LivingMonster(form: .egg, progress: received ? 0.4 : 0.1)
                    .frame(width: 180, height: 180)
                    .scaleEffect(received ? 1.1 : 0.9)

                Text(received
                     ? "Ele choca com seus treinos. Musculação, corrida, vôlei, o que você fizer conta. E o jeito que você treina decide no que ele vai se transformar."
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
                        .background(Theme.card, in: .rect(cornerRadius: 14))
                        .padding(.horizontal, 32)
                        // O ✓ do teclado só fecha o teclado; avançar é pelo botão
                        .onSubmit { focused = false }
                }
                Spacer()

                Button(action: received ? start : receive) {
                    Text(received ? "Começar a jornada" : "Receber meu ovo")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Theme.accent, in: .rect(cornerRadius: 16))
                        .foregroundStyle(.black)
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
        }
        .onAppear { focused = true }
    }

    private func receive() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        focused = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.spring(duration: 0.6)) { received = true }
    }

    private func start() {
        lastFormID = MonsterForm.egg.id
        trainerName = name.trimmingCharacters(in: .whitespaces)
    }
}
