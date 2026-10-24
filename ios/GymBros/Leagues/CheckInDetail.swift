import SwiftData
import SwiftUI

/// Tela cheia de um check-in: foto em destaque, autor, título, detalhes e comentários
struct CheckInDetailView: View {
    let item: FeedItem
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var checkIns: [LeagueCheckIn]
    @Query private var leagues: [League]
    @State private var removing = false
    @State private var whoReacted = false
    @Query(sort: \CheckInComment.date) private var allComments: [CheckInComment]
    @AppStorage("trainerName") private var trainerName = ""
    @State private var text = ""
    @State private var menu = false
    @State private var editing: Activity?
    @Query private var activities: [Activity]
    @State private var confirmDelete = false
    @State private var reacting = false
    @State private var commentMenu: CheckInComment?
    @State private var moderation: ModerationRequest?
    /// Perfil público de quem comentou (mesmo sem ser seu amigo)
    @State private var person: RemoteFriend?
    @State private var mod = ModerationStore.shared
    @State private var blocked = false
    @State private var terms = TermsGate()
    @FocusState private var typing: Bool

    private var mine: LeagueCheckIn? { item.isMe ? checkIns.first { $0.uuid.uuidString == item.id } : nil }
    private var comments: [CheckInComment] { allComments.filter { $0.itemID == item.id } }
    /// Dados atuais (o check-in pode ter sido editado depois de aberto)
    private var title: String { mine?.title ?? item.title }
    private var note: String { mine?.note ?? item.note }
    private var photo: Data? { item.isMe ? mine?.photo : mod.isHidden(.photo, item.id) ? nil : item.photo }
    /// Todas as fotos (a principal e as extras)
    private var allPhotos: [Data] { item.isMe ? (mine?.photos ?? []) : photo.map { [$0] + item.extraPhotos } ?? [] }
    /// Denunciado por você ou de alguém que você bloqueou
    private var gone: Bool { !item.isMe && (mod.isHidden(.checkIn, item.id) || mod.isBlocked(item.memberID)) }
    private var target: ModerationTarget { ModerationTarget(userID: item.memberID, userName: item.name, content: .checkIn, id: item.id) }

    var body: some View {
        VStack(spacing: 0) {
            if gone {
                HStack {
                    GMIconButton(icon: "chevron.left", label: "Voltar") { dismiss() }
                    Spacer()
                }
                .padding(16)
                if mod.isBlocked(item.memberID) {
                    GMEmptyState(icon: "hand.raised.slash", title: "Check-in oculto",
                                 message: "Você bloqueou \(item.name.isEmpty ? "esta pessoa" : item.name). Para ver de novo, desbloqueie em Ajustes > Privacidade.")
                } else {
                    GMEmptyState(icon: "flag", title: "Check-in denunciado", message: "Você não vê mais este check-in. " + ModerationStore.reviewNote)
                }
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        hero
                        VStack(alignment: .leading, spacing: 14) {
                            author
                            Text(title).gmFont(26, weight: .heavy, design: .rounded, relativeTo: .title)
                            if !note.isEmpty { Text(note).font(.body).foregroundStyle(.white.opacity(0.85)) }
                            chips
                            if !visibleComments.isEmpty { commentList }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
                composer
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .gmActions(isPresented: $menu, title: title, actions: menuActions)
        .gmActions(isPresented: $confirmDelete, title: "Apagar check-in?",
                   message: "Sai desta liga. A atividade continua no seu histórico.", actions: [
            GMAction("Apagar check-in", icon: "trash", destructive: true) {
                if let c = mine {
                    LeagueOutbox.retract(c)
                    context.delete(c)
                }
                comments.forEach { CommentSync.retract($0); context.delete($0) }
                try? context.save()
                dismiss()
            }
        ])
        // Edita a atividade e o post juntos: destinos (perfil e ligas), título, foto e local
        .gmModal(item: $editing) { LogActivityView(snapshot: Snapshot(), editing: $0) }
        .gmActions(isPresented: Binding(get: { commentMenu != nil }, set: { if !$0 { commentMenu = nil } }), title: "Comentário",
                   actions: commentMenu.map(commentActions) ?? [])
        .gmSheet(isPresented: $whoReacted) { _ in reactedSheet }
        .moderation($moderation) { dismiss() }
        .gmActions(isPresented: $removing, title: "Remover este check-in?",
                   message: "Ele sai da liga e não pontua. \(item.name) fica sabendo que o check-in foi removido.", actions: [
            GMAction("Remover check-in", icon: "xmark.bin", destructive: true) {
                if let league = moderatedLeague {
                    context.insert(CheckInReview(leagueUUID: league.uuid, itemID: item.id, approved: false))
                    try? context.save()
                }
                dismiss()
            }
        ])
        .termsGate($terms)
        .onChange(of: text) { blocked = false }
        .gmModal(item: $person) { FriendProfileView(friend: $0) }
        // Comentários de todo mundo neste check-in, e as reações a eles
        .task {
            await CommentSync.pull([(item.id, item.comments)], context: context)
            await CommentSync.pull(comments.filter { !$0.isReaction }.map { ("c:\($0.uuid.uuidString)", item.comments) }, context: context)
        }
    }

    private func openProfile(_ c: CheckInComment) {
        guard !c.isMine else { return }
        person = RemoteFriend(id: c.authorID, name: c.authorName, formID: "", code: "")
    }

    private var visibleComments: [CheckInComment] { mod.visible(comments) }

    /// Liga do check-in em que você é dono ou moderador
    private var moderatedLeague: League? {
        item.leagueID.flatMap { id in leagues.first { $0.uuid == id } }.flatMap { $0.canModerate ? $0 : nil }
    }

    private var menuActions: [GMAction] {
        var list = [GMAction("Compartilhar", icon: "square.and.arrow.up") { share() }]
        if let c = mine {
            if let a = activities.first(where: { $0.uuid == c.activityUUID }) {
                list.append(GMAction("Editar", icon: "pencil") { editing = a })
            }
            list.append(GMAction("Apagar check-in", icon: "trash", destructive: true) { confirmDelete = true })
        } else if !item.isMe {
            var actions = target.actions { moderation = $0 }
            // Dono e moderadores tiram o check-in da liga (quem postou fica sabendo)
            if moderatedLeague != nil {
                actions.insert(GMAction("Remover check-in da liga", icon: "xmark.bin", destructive: true) { removing = true }, at: 0)
            }
            if item.hasPhoto && !mod.isHidden(.photo, item.id) {
                let photo = ModerationTarget(userID: item.memberID, userName: item.name, content: .photo, id: item.id)
                actions.insert(GMAction("Denunciar foto", icon: "photo") { moderation = ModerationRequest(target: photo, step: .report) }, at: 1)
            }
            list += actions
        }
        return list
    }

    // MARK: Foto

    private var hero: some View {
        ZStack {
            if allPhotos.count > 1 {
                // Várias fotos: passa de lado
                TabView {
                    ForEach(Array(allPhotos.enumerated()), id: \.offset) { _, data in
                        if let img = UIImage(data: data) {
                            ZStack {
                                Color.clear.overlay { Image(uiImage: img).resizable().scaledToFill().blur(radius: 40).opacity(0.7) }
                                Image(uiImage: img).resizable().scaledToFit()
                            }
                        }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
            } else if let data = photo, let img = UIImage(data: data) {
                // Fundo borrado da própria foto, como nos apps de feed
                Color.clear.overlay { Image(uiImage: img).resizable().scaledToFill().blur(radius: 40).opacity(0.7) }
                Image(uiImage: img).resizable().scaledToFit()
            } else {
                LinearGradient(colors: [(item.isMe ? Theme.accent : Color.white).opacity(0.25), Theme.card], startPoint: .top, endPoint: .bottom)
                VStack(spacing: 10) {
                    MonsterSprite(form: item.avatar).frame(width: 150, height: 150)
                    Label(item.kind.name, systemImage: item.kind.symbol).font(.headline).foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: photo == nil ? 300 : 460)
        .clipped()
        .overlay(alignment: .top) {
            HStack {
                GMIconButton(icon: "chevron.left") { dismiss() }
                Spacer()
                GMIconButton(icon: "ellipsis") { menu = true }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        // Pose do dia em que a foto foi tirada, embaixo da foto
        .overlay(alignment: .bottom) {
            if let pose = DailyPose.byID(item.proof.pose) {
                Text("\(pose.emoji) \(pose.name)")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.black.opacity(0.65), in: .capsule)
                    .foregroundStyle(.white)
                    .padding(.bottom, 14)
            }
        }
        .clipShape(.rect(bottomLeadingRadius: Theme.radius, bottomTrailingRadius: Theme.radius))
    }

    // MARK: Autor e detalhes

    private var author: some View {
        HStack(spacing: 12) {
            avatar(me: item.isMe, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.isMe ? (trainerName.isEmpty ? "Você" : trainerName) : item.name).font(.headline)
                Text(when(item.date) + (item.place.map { " · \($0)" } ?? ""))
                    .font(.subheadline).foregroundStyle(Theme.dim).lineLimit(2)
            }
            Spacer()
            Image(systemName: photo == nil ? item.kind.symbol : "photo.fill").font(.title3)
        }
    }

    private var chips: some View {
        VStack(alignment: .leading, spacing: 10) {
            GMFlow {
                chip(icon: "stopwatch", text: durationText(item.minutes))
                chip(icon: item.kind.symbol, text: item.kind.name)
                if item.pending {
                    chip(icon: "clock", text: "Em revisão", tint: Theme.dim)
                } else {
                    chip(icon: "bolt.fill", text: "+" + (item.scoring.map { $0.format(item.score) } ?? "\(item.score) XP"), tint: Theme.accent)
                }
                if let place = item.place { chip(icon: "mappin.and.ellipse", text: place) }
            }
            if item.pending {
                Text("Esperando o dono da liga aprovar: até lá, não pontua.").font(.caption).foregroundStyle(Theme.dim)
            }
            if item.capped > 0, let scoring = item.scoring {
                Text("O teto da liga cortou \(scoring.format(item.capped)) deste check-in.").font(.caption).foregroundStyle(Theme.dim)
            }
            // De onde veio a prova: câmera do app, galeria (com a hora gravada), aparelho, pose do dia
            ForEach(item.proof.lines, id: \.self) { line in
                Label(line, systemImage: "checkmark.seal").font(.caption).foregroundStyle(Theme.dim)
            }
        }
    }

    private func chip(icon: String, text: String, tint: Color = .white) -> some View {
        Label(text, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Theme.raised, in: .capsule)
            .foregroundStyle(tint)
    }

    @ViewBuilder
    private func avatar(me: Bool, size: CGFloat) -> some View {
        if me {
            Avatar(size: size)
        } else {
            MonsterSprite(form: item.avatar).frame(width: size * 0.8, height: size * 0.8)
                .frame(width: size, height: size).background(Theme.raised, in: .circle)
        }
    }

    // MARK: Comentários

    /// Reação ao check-in: comentário só com emoji
    private var reactionComments: [CheckInComment] { visibleComments.filter { isEmojiOnly($0.text) } }

    /// Reações de um comentário (guardadas como comentário no id "c:<comentário>")
    private func reactions(to c: CheckInComment) -> [CheckInComment] { mod.visible(allComments.filter { $0.itemID == "c:\(c.uuid.uuidString)" }) }

    private func summary(_ list: [CheckInComment]) -> String {
        Dictionary(grouping: list, by: \.text).mapValues(\.count).sorted { $0.value > $1.value }
            .map { $0.value > 1 ? "\($0.key) \($0.value)" : $0.key }.joined(separator: " · ")
    }

    private func commentActions(_ c: CheckInComment) -> [GMAction] {
        var list = ["👍", "❤️‍🔥", "💪", "😂"].map { e in
            GMAction("Reagir \(e)", icon: "face.smiling") {
                CommentSync.add(e, to: "c:\(c.uuid.uuidString)", owner: c.authorID, scope: item.comments, context: context)
            }
        }
        if c.isMine {
            list.append(GMAction("Apagar comentário", icon: "trash", destructive: true) {
                reactions(to: c).forEach { CommentSync.retract($0); context.delete($0) }
                CommentSync.remove(c, context: context)
            })
        } else {
            list.append(GMAction("Denunciar comentário", icon: "flag", destructive: true) {
                moderation = ModerationRequest(target: ModerationTarget(userID: c.authorID, userName: c.authorName, content: .comment, id: c.uuid.uuidString))
            })
        }
        return list
    }

    /// Quem reagiu, por emoji
    private var reactedSheet: some View {
        let groups = Dictionary(grouping: reactionComments, by: \.text).sorted { $0.value.count > $1.value.count }
        return VStack(alignment: .leading, spacing: 12) {
            Text("Quem reagiu").font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(groups, id: \.key) { emoji, list in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(emoji) \(list.count)").font(.subheadline.bold())
                            Text(list.map { $0.isMine ? "Você" : $0.authorName }.joined(separator: ", ")).font(.subheadline).foregroundStyle(Theme.dim)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 360)
        }
    }

    private var commentList: some View {
        VStack(alignment: .leading, spacing: 12) {
            GMDivider()
            if !reactionComments.isEmpty {
                Button { whoReacted = true } label: {
                    HStack {
                        Text(summary(reactionComments)).font(.subheadline)
                        Text("· quem reagiu").font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                    }
                }
                .buttonStyle(GMPress())
            }
            ForEach(visibleComments) { c in
                HStack(alignment: .top, spacing: 10) {
                    if c.isMine { Avatar(size: 32) } else {
                        PersonAvatar(name: c.authorName, size: 32).onTapGesture { openProfile(c) }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(c.isMine ? (trainerName.isEmpty ? "Você" : trainerName) : c.authorName).font(.caption.bold())
                                .onTapGesture { openProfile(c) }
                            Text(c.date.formatted(.relative(presentation: .named))).font(.caption2).foregroundStyle(Theme.dim)
                        }
                        Text(mentionText(c.text)).font(isEmojiOnly(c.text) ? .title : .subheadline)
                        let r = reactions(to: c)
                        if !r.isEmpty {
                            Text(summary(r)).font(.caption).padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Theme.raised, in: .capsule)
                        }
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
                // Segurar: reagir; o seu dá para apagar, o dos outros, denunciar
                .onLongPressGesture { commentMenu = c }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 10) {
            if blocked { ContentBlockedNote() }
            if reacting {
                HStack {
                    ForEach(["💪", "🔥", "👏", "😮‍💨", "🏆", "❤️"], id: \.self) { e in
                        Button { send(e); reacting = false } label: { Text(e).font(.system(size: 30)) }
                            .buttonStyle(GMPress())
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 6)
                .background(Theme.card, in: .capsule)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            HStack(spacing: 10) {
                HStack {
                    TextField("", text: $text, prompt: Text("Comentar…").foregroundStyle(Theme.dim), axis: .vertical)
                        .lineLimit(1...4)
                        .focused($typing)
                        .submitLabel(.send)
                        .onSubmit { send(text) }
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button { send(text) } label: {
                            Image(systemName: "arrow.up.circle.fill").font(.title2).foregroundStyle(Theme.accent)
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(Theme.card, in: .capsule)
                Button { withAnimation(.snappy) { reacting.toggle() } } label: {
                    Image(systemName: reacting ? "xmark" : "face.smiling")
                        .font(.title2)
                        .frame(width: 50, height: 50)
                        .background(Theme.card, in: .circle)
                        .foregroundStyle(.white)
                }
                .buttonStyle(GMPress())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Theme.bg)
        .overlay(alignment: .top) { Rectangle().fill(Theme.stroke).frame(height: 1) }
    }

    private func send(_ raw: String) {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        guard AccessStore.shared.can(.commentsCreate) else { return }
        guard ContentFilter.allows(t) else { blocked = true; return }
        terms.run {
            CommentSync.add(t, to: item.id, owner: item.memberID, scope: item.comments, context: context)
            if raw == text { text = "" }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func isEmojiOnly(_ s: String) -> Bool { CheckInComment.isReaction(s) }

    private func when(_ d: Date) -> String {
        let cal = Calendar.current
        let time = d.formatted(.dateTime.hour().minute())
        if cal.isDateInToday(d) { return "Hoje, \(time)" }
        if cal.isDateInYesterday(d) { return "Ontem, \(time)" }
        return "\(d.formatted(.dateTime.weekday().day().month(.abbreviated))), \(time)"
    }

    private func share() {
        var items: [Any] = ["\(title) · \(item.kind.name), \(durationText(item.minutes)) no GymBros 💪"]
        if let data = photo, let img = UIImage(data: data) { items.insert(img, at: 0) }
        presentShare(items)
    }
}
