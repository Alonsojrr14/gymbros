import SwiftUI

/// De quem é e o que é. Sem `content`, só dá para bloquear a pessoa.
struct ModerationTarget {
    let userID: String
    let userName: String
    var content: ReportedContent?

    init(userID: String, userName: String, content: ReportedContent.Kind? = nil, id: String = "") {
        self.userID = userID
        self.userName = userName.isEmpty ? "esta pessoa" : userName
        self.content = content.map { ReportedContent(kind: $0, id: id, authorID: userID, authorName: userName) }
    }
}

struct ModerationRequest {
    enum Step { case menu, report, block, thanks }

    let target: ModerationTarget
    var step: Step = .menu
}

extension ModerationTarget {
    /// "Denunciar" e "Bloquear" para pôr num menu que já existe
    func actions(_ open: @escaping (ModerationRequest) -> Void) -> [GMAction] {
        var list: [GMAction] = []
        if let content {
            list.append(GMAction("Denunciar \(content.kind.name)", icon: "flag") { open(.init(target: self, step: .report)) })
        }
        list.append(GMAction("Bloquear \(userName)", icon: "hand.raised.slash", destructive: true) { open(.init(target: self, step: .block)) })
        return list
    }
}

extension View {
    /// Menu de denunciar/bloquear, escolha do motivo, confirmação do bloqueio e o "obrigado".
    /// `onBlocked` roda depois que a camada de confirmação saiu (ex.: fechar o perfil de quem foi bloqueado).
    func moderation(_ request: Binding<ModerationRequest?>, onBlocked: (() -> Void)? = nil) -> some View {
        modifier(ModerationSheets(request: request, onBlocked: onBlocked))
    }
}

private struct ModerationSheets: ViewModifier {
    @Binding var request: ModerationRequest?
    var onBlocked: (() -> Void)?

    func body(content: Content) -> some View {
        let t = request?.target
        content
            .gmActions(isPresented: showing(.menu), title: t?.userName, actions: t?.actions { request = $0 } ?? [])
            .gmActions(isPresented: showing(.report), title: "Denunciar \(t?.content?.kind.name ?? "")",
                       message: "Por que você está denunciando? Quem publicou não fica sabendo.", actions: reasons(t))
            .gmActions(isPresented: showing(.block), title: "Bloquear \(t?.userName ?? "")?",
                       message: "Você deixa de ver tudo o que essa pessoa publica e a amizade é desfeita. Ela não recebe aviso, e a pontuação nas ligas não muda. Dá para desbloquear em Ajustes.",
                       actions: t.map { t in [GMAction("Bloquear", icon: "hand.raised.slash", destructive: true) {
                           Task { await ModerationStore.shared.block(userID: t.userID, name: t.userName) }
                           onBlocked?()
                       }] } ?? [])
            .gmSheet(isPresented: showing(.thanks)) { close in
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.shield.fill").font(.system(size: 40)).foregroundStyle(Theme.accent)
                    Text("Obrigado pela denúncia").font(.headline).multilineTextAlignment(.center)
                    Text("O conteúdo já sumiu para você. " + ModerationStore.reviewNote + " Para não ver mais nada dessa pessoa, use Bloquear.")
                        .font(.subheadline).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                    GMButton("Entendi", action: close)
                }
            }
    }

    private func reasons(_ t: ModerationTarget?) -> [GMAction] {
        guard let t, let c = t.content else { return [] }
        return ReportReason.allCases.map { r in
            GMAction(r.title, icon: r.icon) {
                Task { await ModerationStore.shared.report(c, reason: r) }
                request = ModerationRequest(target: t, step: .thanks)
            }
        }
    }

    private func showing(_ step: ModerationRequest.Step) -> Binding<Bool> {
        Binding(get: { request?.step == step }, set: { if !$0, request?.step == step { request = nil } })
    }
}

// MARK: - Ajustes

struct BlockedUsersView: View {
    @State private var store = ModerationStore.shared

    var body: some View {
        GMModal("Usuários bloqueados") {
            GMSection(footer: "Quem você bloqueia não aparece nos seus feeds, mural, comentários, amigos e mapa. Desbloquear não refaz a amizade: para voltar a ser amigos, adicione a pessoa de novo.") {
                if store.blocked.isEmpty {
                    Text("Ninguém bloqueado.").font(.subheadline).foregroundStyle(Theme.dim)
                }
                ForEach(store.blocked) { u in
                    HStack(spacing: 12) {
                        PersonAvatar(name: u.name, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(u.name).font(.subheadline.weight(.semibold))
                            Text("Desde \(u.date.formatted(.dateTime.day().month(.abbreviated).year()))").font(.caption).foregroundStyle(Theme.dim)
                        }
                        Spacer()
                        GMButton("Desbloquear", kind: .secondary, full: false, small: true) { Task { await store.unblock(u.id) } }
                    }
                    if u.id != store.blocked.last?.id { GMDivider() }
                }
            }
        }
        .task { await store.refresh() }
    }
}
