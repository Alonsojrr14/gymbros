import SwiftData
import SwiftUI

// Perfil público: o que outras pessoas veem de você (e você delas). O mesmo card aparece na prévia
// do seu perfil ("Como seus amigos te veem") e no perfil de um amigo. Partes que a pessoa escondeu
// em "O que aparece para os outros" chegam como nil.

struct PublicProfile: Codable, Identifiable, Sendable {
    struct Bro: Codable, Sendable {
        let name: String
        let formID: String
        let level: Int
        let progress: Double

        var form: MonsterForm { MonsterForm.byID(formID) ?? .egg }
    }

    struct Stats: Codable, Sendable {
        /// Atividades postadas (no perfil ou em ligas); as não postadas são privadas e não contam
        let checkIns: Int
        /// Dias com alguma atividade postada
        let activeDays: Int
        /// Ligas em que a pessoa está agora (sem temporadas passadas)
        let leagues: Int
    }

    struct Badge: Codable, Hashable, Sendable {
        let title: String
        let symbol: String
    }

    let id: String
    let name: String
    var username = ""
    var bio = ""
    var photoURL: URL?
    var bro: Bro?
    var stats: Stats?
    var achievements: [Badge]?
    /// Check-ins postados no perfil, do mais novo para o mais antigo
    var posts: [RemoteCheckIn] = []
    /// Check-ins recentes em ligas públicas (para o Feed; as privadas não chegam)
    var leaguePosts: [RemoteCheckIn] = []
}

extension PublicProfile {
    /// Números públicos: só o que foi postado (perfil ou ligas) conta; atividade não postada fica privada.
    /// Ligas = as que você está agora (temporadas passadas da mesma liga não contam de novo).
    static func stats(activities: [Activity], checkIns: [LeagueCheckIn], leagues: [League]) -> Stats {
        let existing = Set(activities.map(\.uuid))
        let posted = Set(checkIns.map(\.activityUUID)).intersection(existing)
        let days = Set(activities.filter { posted.contains($0.uuid) }.map { Calendar.current.startOfDay(for: $0.date) })
        return .init(checkIns: posted.count, activeDays: days.count, leagues: leagues.filter { !$0.isPastSeason }.count)
    }

    /// O seu perfil público, respeitando o que você escondeu em "O que aparece para os outros".
    /// Texto barrado pelo filtro de palavras sobe vazio (o apelido do bro volta ao nome da forma).
    @MainActor
    static func mine(roster: Roster, activities: [Activity], checkIns: [LeagueCheckIn], leagues: [League], unlocked: [Achievement]) -> PublicProfile {
        let d = UserDefaults.standard
        func shows(_ key: String) -> Bool { d.object(forKey: key) == nil || d.bool(forKey: key) }
        func text(_ key: String) -> String { ContentFilter.publishable(d.string(forKey: key) ?? "") }
        let s = roster.mainSnapshot
        let broName = ContentFilter.publishable(roster.main?.displayName(s.form) ?? "")
        return PublicProfile(
            id: "me", name: text("trainerName"), username: text("profileUsername"), bio: text("profileBio"),
            bro: shows("publicMonster") ? .init(name: broName.isEmpty ? s.form.name : broName, formID: s.form.id, level: s.level, progress: s.progress) : nil,
            stats: shows("publicStats") ? stats(activities: activities, checkIns: checkIns, leagues: leagues) : nil,
            achievements: shows("publicAchievements") ? unlocked.map { .init(title: $0.title, symbol: $0.symbol) } : nil)
    }
}

/// Bolinha com a foto ou, sem foto, a inicial
struct PersonAvatar: View {
    let name: String
    var photo: Data?
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let photo, let img = UIImage(data: photo) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Text(name.prefix(1).uppercased().isEmpty ? "?" : name.prefix(1).uppercased())
                    .font(.system(size: size * 0.42, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.accent)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .overlay(Circle().stroke(Theme.stroke, lineWidth: 1))
    }
}

/// Bro, números e conquistas do perfil público. `showHeader` põe foto, nome e bio no topo (prévia do seu perfil).
struct PublicProfileCard: View {
    let profile: PublicProfile
    var photo: Data?
    var showHeader = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showHeader {
                HStack(spacing: 12) {
                    PersonAvatar(name: profile.name, photo: photo, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.name.isEmpty ? "Treinador" : profile.name).font(.headline)
                        if !profile.username.isEmpty { Text("@\(profile.username)").font(.caption).foregroundStyle(Theme.dim) }
                        if !profile.bio.isEmpty { Text(profile.bio).font(.caption) }
                    }
                }
            }
            if let b = profile.bro {
                if showHeader { GMDivider() }
                HStack(spacing: 12) {
                    LivingMonster(form: b.form, progress: b.progress).frame(width: 60, height: 60)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(b.name).font(.subheadline.bold())
                        Text(b.form.stage == .egg ? "Ovo" : "\(b.form.speciesInfo.name) · \(b.form.stage.name) · Nível \(b.level)")
                            .font(.caption).foregroundStyle(Theme.dim)
                    }
                }
            }
            if let s = profile.stats {
                if showHeader || profile.bro != nil { GMDivider() }
                HStack {
                    stat("\(s.checkIns)", "Check-ins")
                    stat("\(s.activeDays)", "Dias ativos")
                    stat("\(s.leagues)", "Ligas")
                }
            }
            if let a = profile.achievements, !a.isEmpty {
                if showHeader || profile.bro != nil || profile.stats != nil { GMDivider() }
                Text("Conquistas · \(a.count)").font(.caption.bold()).foregroundStyle(Theme.dim)
                GMFlow {
                    ForEach(a.prefix(6), id: \.self) { b in
                        Label(b.title, systemImage: b.symbol)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Theme.trophy.opacity(0.15), in: .capsule)
                            .foregroundStyle(Theme.trophy)
                    }
                }
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.monospacedDigit())
            Text(label).font(.caption).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Perfil do amigo

struct FriendProfileView: View {
    let friend: RemoteFriend
    @Environment(\.dismiss) private var dismiss
    @State private var store = FriendsStore.shared
    @Query(sort: \League.joinedAt) private var leagues: [League]
    @State private var menu = false
    @State private var confirmRemove = false
    @State private var moderation: ModerationRequest?
    @State private var mod = ModerationStore.shared
    @State private var chatting = false
    @State private var dueling = false
    @State private var cheered = false
    @State private var terms = TermsGate()
    /// Lido para a tela atualizar quando você esconde os treinos ou silencia
    @AppStorage(FriendPrefs.key) private var friendPrefsRaw = ""

    private var live: LiveFriend? { FriendsLive.find(friend.id).flatMap { $0.isLive ? $0 : nil } }

    var body: some View {
        let profile = store.profiles[friend.id]
        NavigationStack {
        ScrollView {
            VStack(spacing: 18) {
                header(profile)
                if store.friendIDs.contains(friend.id) { friendActions }
                let prefs = friendPrefsRaw.isEmpty ? FriendPrefs() : FriendPrefs.of(friend.id)
                if prefs.hideMine || prefs.muted {
                    Text([prefs.hideMine ? "Seus treinos estão escondidos de \(friend.name) (nas ligas em comum continuam aparecendo)." : nil,
                          prefs.muted ? "Notificações de \(friend.name) silenciadas." : nil].compactMap { $0 }.joined(separator: " "))
                        .font(.caption).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                }
                GMButton("Desafiar para um X1", icon: "bolt.shield.fill", kind: .secondary) { dueling = true }
                if mod.isHidden(.profile, friend.id) {
                    GMEmptyState(icon: "flag", title: "Perfil denunciado",
                                 message: "Você não vê mais o conteúdo deste perfil. " + ModerationStore.reviewNote)
                } else if let profile {
                    if profile.bro != nil || profile.stats != nil || !(profile.achievements ?? []).isEmpty {
                        GMCard { PublicProfileCard(profile: profile, showHeader: false) }
                    }
                    commonLeagues
                    let posts = mod.visible(feed(profile))
                    GMSection("Posts · \(posts.count)", footer: posts.isEmpty ? "\(friend.name) ainda não postou nada no perfil." : nil) {
                        PostsCalendar(posts: posts)
                    }
                } else {
                    ProgressView().padding(.top, 40)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .background(Theme.bg.ignoresSafeArea())
        .safeAreaInset(edge: .top) {
            HStack {
                GMIconButton(icon: "chevron.left") { dismiss() }
                Spacer()
                GMIconButton(icon: "ellipsis") { menu = true }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Theme.bg)
        }
        .toolbar(.hidden, for: .navigationBar)
        }
        .task { await store.loadProfile(friend.id) }
        .gmActions(isPresented: $menu, title: friend.name, actions: menuActions)
        .gmActions(isPresented: $confirmRemove, title: "Desfazer amizade com \(friend.name)?",
                   message: "Vocês continuam nas mesmas ligas.", actions: [
            GMAction("Desfazer amizade", icon: "person.badge.minus", destructive: true) {
                Task { await store.remove(friend.id) }
                dismiss()
            }
        ])
        .moderation($moderation) { dismiss() }
        .termsGate($terms)
        .gmModal(isPresented: $chatting) { NavigationStack { ConversationView(peerID: friend.id) } }
        .gmSheet(isPresented: $dueling) { close in
            DuelComposer(opponent: DuelPerson(id: friend.id, name: friend.name, formID: friend.formID)) { close() }
        }
    }

    private var menuActions: [GMAction] {
        var list: [GMAction] = []
        if store.friendIDs.contains(friend.id) {
            let prefs = FriendPrefs.of(friend.id)
            let id = friend.id
            list.append(prefs.hideMine
                ? GMAction("Mostrar meus treinos para \(friend.name)", icon: "eye") { Task { await store.setHideMine(id, false) } }
                : GMAction("Esconder meus treinos de \(friend.name)", icon: "eye.slash") { Task { await store.setHideMine(id, true) } })
            list.append(prefs.muted
                ? GMAction("Reativar notificações de \(friend.name)", icon: "bell") { FriendPrefs.set(id) { $0.muted = false } }
                : GMAction("Silenciar \(friend.name)", icon: "bell.slash") { FriendPrefs.set(id) { $0.muted = true } })
            list.append(GMAction("Desfazer amizade", icon: "person.badge.minus", destructive: true) { confirmRemove = true })
        }
        let target = ModerationTarget(userID: friend.id, userName: friend.name, content: mod.isHidden(.profile, friend.id) ? nil : .profile,
                                      id: friend.id)
        return list + target.actions { moderation = $0 }
    }

    private func header(_ p: PublicProfile?) -> some View {
        VStack(spacing: 10) {
            PersonAvatar(name: friend.name, photo: ProfilePhotos.shared.photo(friend.id), size: 110)
            VStack(spacing: 2) {
                HStack(spacing: 6) {
                    Text(friend.name).font(.title2.weight(.heavy))
                    if live != nil { GMOnlineDot(size: 10) }
                }
                if let u = p?.username, !u.isEmpty { Text("@\(u)").font(.subheadline).foregroundStyle(Theme.dim) }
                if let live { Text("\(live.kind.name) agora · \(live.place)").font(.caption.weight(.semibold)).foregroundStyle(Theme.dim) }
                if let b = p?.bio, !b.isEmpty { Text(b).font(.subheadline).multilineTextAlignment(.center).padding(.top, 4) }
            }
        }
        .padding(.top, 8)
    }

    /// Conversa e força direto do perfil (só entre amigos)
    private var friendActions: some View {
        HStack(spacing: 10) {
            GMButton("Mensagem", icon: "bubble.left.fill", kind: .secondary) { chatting = true }
            GMButton(cheered ? "Força enviada" : "Mandar força", icon: cheered ? "checkmark" : "bolt.heart.fill", enabled: !cheered) {
                terms.run {
                    Task {
                        do {
                            try await InboxStore.shared.cheer(friend.id)
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            withAnimation(.snappy) { cheered = true }
                        } catch {}
                    }
                }
            }
        }
    }

    /// Ligas suas em que a pessoa também está
    @ViewBuilder
    private var commonLeagues: some View {
        let common = leagues.filter { l in !l.isPastSeason && LeagueRemoteStore.shared.remote(l).member(friend.id) != nil }
        if !common.isEmpty {
            GMSection("Ligas em comum") {
                ForEach(common) { l in
                    NavigationLink { LeagueDetailView(league: l) } label: {
                        HStack(spacing: 12) {
                            Text(l.emoji).font(.title3).frame(width: 38, height: 38).background(Theme.raised, in: .circle)
                            Text(l.name).font(.subheadline.weight(.semibold))
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.dim)
                        }
                        .contentShape(Rectangle())
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(GMPress())
                    if l.id != common.last?.id { GMDivider() }
                }
            }
        }
    }

    private func feed(_ p: PublicProfile) -> [FeedItem] {
        let avatar = p.bro?.form ?? friend.form
        return p.posts.map { r in
            var f = FeedItem(id: r.id, memberID: friend.id, name: friend.name, avatar: avatar, isMe: false, date: r.date, title: r.title, note: r.note,
                             kind: r.kind, minutes: r.minutes, score: Game.xp(kind: r.kind, minutes: r.minutes, effort: r.effort), photo: nil,
                             hasPhoto: r.hasPhoto, effort: r.effort)
            f.comments = CommentScope(league: CloudType.profileFeed, owner: friend.id, isPublic: false, member: true)
            return f
        }
    }
}
