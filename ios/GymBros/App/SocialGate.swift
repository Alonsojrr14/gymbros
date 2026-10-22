import SwiftUI

/// Ligas, amigos, mapa de amigos, perfil público e mural: a conta (obrigatória para abrir o app) precisa ter aceitado
/// os termos de uso e ter a permissão (enquanto as roles não chegam, nada aparece).
struct SocialGate<Content: View>: View {
    let permission: Permission
    @ViewBuilder var content: Content
    @State private var auth = AuthStore.shared
    @State private var access = AccessStore.shared
    @AppStorage(Terms.acceptedKey) private var acceptedTerms = 0

    init(requires permission: Permission, @ViewBuilder content: () -> Content) {
        self.permission = permission
        self.content = content()
    }

    var body: some View {
        if auth.isSignedIn && acceptedTerms >= Terms.version {
            if access.can(permission) {
                content
            } else if access.isLoading {
                ProgressView().tint(Theme.accent).frame(maxWidth: .infinity).padding(.vertical, 40)
            } else {
                GMCard { GMEmptyState(icon: "lock.fill", title: "Sem acesso", message: "Sua conta não tem permissão para ver isto.") }
            }
        } else if auth.isSignedIn {
            TermsPrompt()
        }
    }
}
