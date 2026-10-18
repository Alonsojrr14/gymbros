import SwiftUI

struct GMAction: Identifiable {
    let id = UUID()
    let title: String
    var icon: String?
    var destructive = false
    let action: () -> Void

    init(_ title: String, icon: String? = nil, destructive: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.destructive = destructive
        self.action = action
    }
}

/// Camada própria por cima de tudo: fundo escurecido + conteúdo animado.
/// Usa um fullScreenCover transparente sem a animação do sistema, para funcionar em qualquer tela.
private struct GMOverlayHost<Content: View>: View {
    @Binding var isPresented: Bool
    var center = false
    let content: (_ close: @escaping (_ then: (() -> Void)?) -> Void) -> Content
    @State private var shown = false
    @State private var drag: CGFloat = 0
    /// Ação escolhida, que espera a camada sair de verdade
    @State private var pending: (() -> Void)?

    var body: some View {
        ZStack(alignment: center ? .center : .bottom) {
            Color.black.opacity(shown ? 0.55 : 0)
                .ignoresSafeArea()
                .onTapGesture { close(nil) }
            if shown {
                content(close)
                    .offset(y: max(drag, 0))
                    .gesture(center ? nil : DragGesture().onChanged { drag = $0.translation.height }.onEnded { v in
                        if v.translation.height > 120 { close(nil) } else { withAnimation(.spring) { drag = 0 } }
                    })
                    .transition(center ? .scale(scale: 0.9).combined(with: .opacity) : .move(edge: .bottom))
            }
        }
        .presentationBackground(.clear)
        .onAppear { withAnimation(.spring(duration: 0.35, bounce: 0.15)) { shown = true } }
        // A ação só roda quando a camada saiu de verdade: com um tempo fixo, abrir outra camada
        // (ex.: menu → confirmação) às vezes pegava a anterior ainda saindo e sobrava uma camada
        // transparente por cima, engolindo os toques
        .onDisappear {
            guard let p = pending else { return }
            pending = nil
            DispatchQueue.main.async(execute: p)
        }
    }

    private func close(_ then: (() -> Void)?) {
        pending = then
        withAnimation(.easeOut(duration: 0.2)) { shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { isPresented = false }
        }
    }
}

struct GMSheetCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(.white.opacity(0.25)).frame(width: 38, height: 5).padding(.top, 10).padding(.bottom, 14)
            content
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: UnevenRoundedRectangle(topLeadingRadius: Theme.radiusXL, topTrailingRadius: Theme.radiusXL))
        .ignoresSafeArea(edges: .bottom)
    }
}

extension View {
    /// Bottom sheet com conteúdo livre
    func gmSheet<C: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping (_ close: @escaping () -> Void) -> C) -> some View {
        fullScreenCover(isPresented: isPresented) {
            GMOverlayHost(isPresented: isPresented) { close in GMSheetCard { content { close(nil) } } }
        }
        // Só a abertura desta camada fica sem a animação do iOS (ela tem a própria);
        // sem o `value`, isso desligava a animação de todas as telas abaixo
        .transaction(value: isPresented.wrappedValue) { $0.disablesAnimations = true }
    }

    /// Bottom sheet de ações (substitui Menu e confirmationDialog)
    func gmActions(isPresented: Binding<Bool>, title: String? = nil, message: String? = nil, actions: [GMAction]) -> some View {
        fullScreenCover(isPresented: isPresented) {
            GMOverlayHost(isPresented: isPresented) { close in
                GMSheetCard {
                    VStack(spacing: 10) {
                        if let title { Text(title).font(.headline).multilineTextAlignment(.center) }
                        if let message {
                            Text(message).font(.subheadline).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                        }
                        if title != nil || message != nil { Spacer().frame(height: 4) }
                        ForEach(actions) { a in
                            GMButton(a.title, icon: a.icon, kind: a.destructive ? .danger : .secondary) { close(a.action) }
                        }
                        GMButton("Cancelar", kind: .ghost) { close(nil) }
                    }
                }
            }
        }
        // Só a abertura desta camada fica sem a animação do iOS (ela tem a própria);
        // sem o `value`, isso desligava a animação de todas as telas abaixo
        .transaction(value: isPresented.wrappedValue) { $0.disablesAnimations = true }
    }

    /// Diálogo central com campo de texto (substitui alert com TextField)
    func gmPrompt(isPresented: Binding<Bool>, title: String, message: String? = nil, placeholder: String,
                  text: Binding<String>, confirm: String = "Salvar", onConfirm: @escaping () -> Void) -> some View {
        fullScreenCover(isPresented: isPresented) {
            GMOverlayHost(isPresented: isPresented, center: true) { close in
                VStack(spacing: 14) {
                    Text(title).font(.headline)
                    if let message { Text(message).font(.subheadline).foregroundStyle(Theme.dim).multilineTextAlignment(.center) }
                    GMTextField(placeholder: placeholder, text: text, axis: .vertical)
                    HStack(spacing: 10) {
                        GMButton("Cancelar", kind: .secondary) { close(nil) }
                        GMButton(confirm) { close(onConfirm) }
                    }
                }
                .padding(20)
                .background(Theme.card, in: .rect(cornerRadius: Theme.radiusXL))
                .padding(.horizontal, 28)
            }
        }
        // Só a abertura desta camada fica sem a animação do iOS (ela tem a própria);
        // sem o `value`, isso desligava a animação de todas as telas abaixo
        .transaction(value: isPresented.wrappedValue) { $0.disablesAnimations = true }
    }
}
