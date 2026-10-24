import SwiftUI

/// Cabeçalho próprio (substitui a barra de navegação)
struct GMHeader<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    var large = true
    /// Título pequeno na barra (telas sem título grande)
    var inlineTitle = true
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Título no centro da tela, não entre os botões (seta de um lado só o empurrava)
            ZStack {
                if !large && inlineTitle {
                    Text(title).font(.headline).lineLimit(1).padding(.horizontal, 100)
                }
                HStack(spacing: 10) {
                    leading
                    Spacer()
                    trailing
                }
            }
            .frame(minHeight: 40)
            if large {
                Text(title).gmFont(32, weight: .heavy, design: .rounded, relativeTo: .largeTitle).lineLimit(1).minimumScaleFactor(0.5)
                if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(Theme.dim) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

/// Tela padrão: cabeçalho próprio + conteúdo rolável. `back` mostra o botão de voltar.
struct GMScreen<Content: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    var back = false
    /// Mostra a bolinha do perfil à esquerda (telas principais das abas)
    var avatar = false
    /// Mostra o X para fechar (tela apresentada com gmModal, sem formulário)
    var close = false
    var large = true
    var bottomInset: CGFloat = 100
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss
    @State private var tour = OnboardingCoordinator.shared

    init(_ title: String, subtitle: String? = nil, back: Bool = false, avatar: Bool = false, close: Bool = false, large: Bool = true,
         bottomInset: CGFloat = 100,
         @ViewBuilder trailing: () -> Trailing = { EmptyView() }, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.back = back
        self.avatar = avatar
        self.close = close
        self.large = large
        self.bottomInset = bottomInset
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Com seta, o título grande fica embaixo; não repete o pequeno na barra
            GMHeader(title: title, subtitle: subtitle, large: large && !back, inlineTitle: !(back && large)) {
                if back { GMIconButton(icon: "chevron.left") { dismiss() } }
                if avatar { ProfileAvatarButton() }
                if close { GMIconButton(icon: "xmark", label: "Fechar") { dismiss() } }
            } trailing: { trailing }
            if back && large {
                Text(title).gmFont(26, weight: .heavy, design: .rounded, relativeTo: .title)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.bottom, 8)
                    .lineLimit(2)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) { content }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, bottomInset)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: tour.scrollTarget) { _, target in
                    guard let target else { return }
                    withAnimation(.snappy) { proxy.scrollTo(OnboardingScroll.id(target), anchor: .center) }
                }
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .gmKeyboardDone()
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// Tela modal (formulários): fechar à esquerda, título ao centro, ação à direita
struct GMModal<Content: View>: View {
    let title: String
    var confirm: String?
    var confirmEnabled = true
    var onConfirm: (() -> Void)?
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    init(_ title: String, confirm: String? = nil, confirmEnabled: Bool = true,
         onConfirm: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.confirm = confirm
        self.confirmEnabled = confirmEnabled
        self.onConfirm = onConfirm
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(title).font(.headline)
                HStack {
                    GMIconButton(icon: "xmark", size: 36, label: "Fechar") { dismiss() }
                    Spacer()
                    if let confirm, let onConfirm {
                        GMButton(confirm, full: false, small: true, enabled: confirmEnabled, action: onConfirm)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) { content }
                    .padding(16)
                    .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Theme.bg.ignoresSafeArea())
        .gmKeyboardDone()
    }
}

extension View {
    /// Abre uma tela modal inteira (sem o cartão padrão do iOS)
    func gmModal<C: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> C) -> some View {
        fullScreenCover(isPresented: isPresented) { content().preferredColorScheme(.dark).tint(Theme.accent) }
    }

    func gmModal<Item: Identifiable, C: View>(item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> C) -> some View {
        fullScreenCover(item: item) { content($0).preferredColorScheme(.dark).tint(Theme.accent) }
    }
}
