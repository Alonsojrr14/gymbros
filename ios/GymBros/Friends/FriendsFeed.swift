import SwiftData
import SwiftUI

// Ranking dos bros (você e os amigos, sem precisar de liga) e o feed unificado (ligas e perfis dos amigos num lugar só,
// sem repetir o mesmo check-in postado em várias ligas).

/// Post de amigo no perfil, no mesmo formato do feed das ligas (vale XP). `leagues` junta os das ligas públicas (Feed e stories).
@MainActor
func friendPosts(_ store: FriendsStore = .shared, leagues: Bool = false) -> [FeedItem] {
    store.friends.flatMap { f -> [FeedItem] in
        guard let p = store.profiles[f.id] else { return [] }
        let avatar = p.bro?.form ?? f.form
        return (p.posts + (leagues ? p.leaguePosts : [])).map { r in
            var item = FeedItem(id: r.id, memberID: f.id, name: f.name, avatar: avatar, isMe: false, date: r.date, title: r.title, note: r.note,
                                kind: r.kind, minutes: r.minutes, score: Game.xp(kind: r.kind, minutes: r.minutes, effort: r.effort), photo: nil,
                                hasPhoto: r.hasPhoto, effort: r.effort)
            item.postedIn = r.postedIn
            item.comments = CommentScope(league: r.leagueCode, owner: f.id, isPublic: r.isPublic, member: false)
            return item
        }
    }
}

// MARK: - Ranking dos bros

enum FriendsMetric: String, CaseIterable, Identifiable {
    case xp, checkIns, days, minutes

    var id: String { rawValue }
    var name: String {
        switch self {
        case .xp: "XP"
        case .checkIns: "Treinos"
        case .days: "Dias ativos"
        case .minutes: "Minutos"
        }
    }

    func format(_ v: Int) -> String {
        switch self {
        case .xp: "\(v) XP"
        case .checkIns: "\(v) treino\(v == 1 ? "" : "s")"
        case .days: "\(v) dia\(v == 1 ? "" : "s")"
        case .minutes: durationText(v)
        }
    }
}

struct FriendRank: Identifiable {
    let id: String
    let name: String
    let avatar: MonsterForm
    let isMe: Bool
    let value: Int
}

@MainActor
enum FriendsRanking {
    /// Placar dos posts do perfil (o que os amigos veem de cada um) na janela
    static func rank(me: [FeedItem], friends: [FeedItem], people: [(String, String, MonsterForm)], myName: String, myAvatar: MonsterForm,
                     metric: FriendsMetric, since: Date?) -> [FriendRank] {
        let cal = Calendar.current
        func value(_ items: [FeedItem]) -> Int {
            let w = items.filter { item in since.map { item.date >= $0 } ?? true }
            switch metric {
            case .xp: return w.reduce(0) { $0 + $1.score }
            case .checkIns: return w.count
            case .days: return Set(w.map { cal.startOfDay(for: $0.date) }).count
            case .minutes: return w.reduce(0) { $0 + $1.minutes }
            }
        }
        var rows = [FriendRank(id: "me", name: myName.isEmpty ? "Você" : myName, avatar: myAvatar, isMe: true, value: value(me))]
        for (id, name, form) in people {
            rows.append(FriendRank(id: id, name: name, avatar: form, isMe: false, value: value(friends.filter { $0.memberID == id })))
        }
        return rows.sorted { ($0.value, $0.isMe ? 1 : 0) > ($1.value, $1.isMe ? 1 : 0) }
    }

    /// Placar a partir do que está no aparelho: os seus posts do perfil e os dos amigos
    static func rows(checkIns: [LeagueCheckIn], activities: [Activity], myName: String, myAvatar: MonsterForm, store: FriendsStore,
                     metric: FriendsMetric, since: Date?) -> [FriendRank] {
        let byID = Dictionary(activities.map { ($0.uuid, $0) }, uniquingKeysWith: { a, _ in a })
        // Os seus: o que está no seu perfil, do mesmo jeito que os amigos veem
        let mine: [FeedItem] = checkIns.filter { $0.leagueUUID == ProfileFeed.id }.compactMap { c in
            guard let a = byID[c.activityUUID] else { return nil }
            return FeedItem(id: c.uuid.uuidString, memberID: "me", name: myName, avatar: myAvatar, isMe: true, date: c.date, title: c.title,
                            note: c.note, kind: a.kind, minutes: a.minutes, score: Game.xp(kind: a.kind, minutes: a.minutes, effort: a.effort), photo: c.photo)
        }
        return rank(me: mine, friends: friendPosts(store), people: store.friends.map { ($0.id, $0.name, store.profiles[$0.id]?.bro?.form ?? $0.form) },
                    myName: myName, myAvatar: myAvatar, metric: metric, since: since)
    }
}

struct FriendsRankingView: View {
    @Query private var checkIns: [LeagueCheckIn]
    @Query private var activities: [Activity]
    @Query(sort: \Monster.createdAt) private var monsters: [Monster]
    @Query private var leagues: [League]
    @AppStorage("trainerName") private var name = ""
    @State private var store = FriendsStore.shared
    @State private var metric = FriendsMetric.checkIns
    @State private var window = RankWindow.semana

    var body: some View {
        let roster = Roster(monsters: monsters, activities: activities, checkIns: checkIns, leagues: leagues)
        let rows = FriendsRanking.rows(checkIns: checkIns, activities: activities, myName: name, myAvatar: roster.mainSnapshot.form, store: store,
                                       metric: metric, since: window.since())
        GMScreen("Ranking dos bros", back: true) {
            GMChoiceChips(options: FriendsMetric.allCases.map { ($0, $0.name) }, selection: $metric)
            GMSegmented(options: RankWindow.allCases.map { ($0, $0 == .liga ? "Sempre" : $0.name) }, selection: $window)
            if store.friends.isEmpty {
                GMEmptyState(icon: "person.2", title: "Sem amigos ainda", message: "Adicione amigos para comparar os treinos postados no perfil.")
            } else {
                GMSection(footer: "Conta o que cada um postou no perfil (o que os amigos veem), sem precisar de liga.") {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                        if i > 0 { GMDivider() }
                        HStack(spacing: 12) {
                            Text(i < 3 ? ["🥇", "🥈", "🥉"][i] : "\(i + 1)º").font(i < 3 ? .title3 : .subheadline.bold()).frame(width: 32)
                            MonsterSprite(form: r.avatar).frame(width: 36, height: 36)
                            Text(r.isMe ? "\(r.name) (você)" : r.name).font(.subheadline.weight(r.isMe ? .bold : .semibold))
                            Spacer()
                            Text(metric.format(r.value)).font(.subheadline.bold().monospacedDigit()).foregroundStyle(r.isMe ? Theme.accent : .white)
                        }
                    }
                }
            }
        }
        .task {
            await store.refresh()
            for f in store.friends where store.profiles[f.id] == nil { await store.loadProfile(f.id) }
        }
    }
}

// MARK: - Feed unificado

/// Um check-in no feed unificado, com todos os lugares em que foi postado
struct UnifiedPost: Identifiable {
    var item: FeedItem
    var places: [String]
    var leagueIDs: Set<UUID>
    var fromFriendProfile = false
    var id: String { item.id }
}

@MainActor
enum UnifiedFeed {
    /// Junta ligas e perfis dos amigos; o mesmo treino (pessoa, título e hora iguais) aparece uma vez, com os lugares
    static func build(leagues: [League], checkIns: [LeagueCheckIn], activities: [Activity], me: String, myAvatar: MonsterForm = .egg,
                      friends: [FeedItem]) -> [UnifiedPost] {
        let byID = Dictionary(activities.map { ($0.uuid, $0) }, uniquingKeysWith: { a, _ in a })
        var posts: [String: UnifiedPost] = [:]
        func key(_ f: FeedItem) -> String { "\(f.memberID)|\(f.title)|\(Int(f.date.timeIntervalSince1970 / 60))" }
        // Liga privada não entra: o que é postado nela fica só lá dentro
        for l in leagues where !l.isPastSeason && !l.settings.isPrivate {
            let feed = ModerationStore.shared.visible(LeagueBoard.feed(league: l, mine: checkIns.filter { $0.leagueUUID == l.uuid }, activities: byID,
                                                                        me: me, myAvatar: myAvatar))
            for f in feed {
                let k = key(f)
                if var p = posts[k] {
                    p.places.append("\(l.emoji) \(l.name)")
                    p.leagueIDs.insert(l.uuid)
                    posts[k] = p
                } else {
                    posts[k] = UnifiedPost(item: f, places: ["\(l.emoji) \(l.name)"], leagueIDs: [l.uuid])
                }
            }
        }
        for f in ModerationStore.shared.visible(friends) {
            let k = key(f)
            let place = f.postedIn ?? "Perfil"
            if var p = posts[k] {
                if !p.places.contains(place) { p.places.append(place) }
                posts[k] = p
            } else {
                posts[k] = UnifiedPost(item: f, places: [place], leagueIDs: [], fromFriendProfile: f.postedIn == nil)
            }
        }
        return posts.values.sorted { $0.item.date > $1.item.date }
    }
}

/// Tela de amigos aberta pelo Feed; a tela do bro fecha ela antes de abrir a caixa de entrada
@MainActor @Observable
final class FeedFriends {
    static let shared = FeedFriends()
    var isOpen = false
}

struct UnifiedFeedView: View {
    /// Na barra de abas: bolinha do perfil no lugar da seta de voltar
    var isTab = false
    @Environment(\.modelContext) private var context
    @Query(sort: \League.joinedAt) private var leagues: [League]
    @Query private var checkIns: [LeagueCheckIn]
    @Query private var activities: [Activity]
    @Query(sort: \Monster.createdAt) private var monsters: [Monster]
    @Query(sort: \CheckInComment.date) private var comments: [CheckInComment]
    @AppStorage("trainerName") private var me = ""
    @State private var store = FriendsStore.shared
    @State private var opened: FeedItem?
    @State private var friends = FeedFriends.shared
    @State private var mod = ModerationStore.shared
    /// Post que acabou de levar 💪 pelo toque duplo (o emoji pula em cima da foto)
    @State private var burst: String?

    var body: some View {
        let myAvatar = Roster(monsters: monsters, activities: activities, checkIns: checkIns, leagues: leagues).mainSnapshot.form
        let all = UnifiedFeed.build(leagues: leagues, checkIns: checkIns, activities: activities, me: me, myAvatar: myAvatar, friends: friendPosts(store, leagues: true))
        // Só você e os seus amigos: o resto do pessoal das ligas aparece dentro de cada liga
        let friendIDs = store.friendIDs
        let shown = all.filter { $0.item.isMe || friendIDs.contains($0.item.memberID) }
        let byItem = Dictionary(grouping: mod.visible(comments), by: \.itemID)
        GMScreen("Feed", back: !isTab, avatar: isTab) {
            if isTab {
                GMIconButton(icon: "person.2.fill", label: "Amigos") { friends.isOpen = true }
            }
        } content: {
            BroStories()
            if !store.friends.isEmpty {
                FriendsRankCard(rows: FriendsRanking.rows(checkIns: checkIns, activities: activities, myName: me, myAvatar: myAvatar, store: store,
                                                          metric: .checkIns, since: RankWindow.semana.since()))
            }
            if shown.isEmpty {
                GMEmptyState(icon: "person.2", title: friendIDs.isEmpty ? "Sem amigos ainda" : "Nada por aqui",
                             message: friendIDs.isEmpty ? "Adicione amigos no canto de cima para ver os treinos deles aqui."
                                                        : "Os treinos que você e os seus amigos postarem aparecem aqui.")
            }
            LazyVStack(spacing: 14) {
                ForEach(shown.prefix(150)) { p in post(p, comments: byItem[p.id] ?? []) }
            }
        }
        .gmModal(item: $opened) { CheckInDetailView(item: $0) }
        .gmModal(isPresented: $friends.isOpen) { FriendsView() }
        .task {
            await store.refresh()
            for f in store.friends where store.profiles[f.id] == nil { await store.loadProfile(f.id) }
        }
        // Reações e número de comentários dos posts na tela (os comentários em si só abrem no post)
        .task(id: shown.prefix(60).map(\.id).joined()) { await CommentSync.pull(shown.prefix(60).map { ($0.id, $0.item.comments) }, context: context) }
    }

    // MARK: Post

    private func post(_ p: UnifiedPost, comments: [CheckInComment]) -> some View {
        let f = p.item
        let reactions = comments.filter(\.isReaction)
        let talk = comments.filter { !$0.isReaction }
        let mine = reactions.first { $0.isMine && $0.text == "💪" }
        return VStack(alignment: .leading, spacing: 12) {
            header(p)
            media(f)
                .onTapGesture(count: 2) { if mine == nil { toggleStrength(f, mine: nil) } ; pop(f.id) }
                .onTapGesture { opened = f }
                .overlay {
                    if burst == f.id { Text("💪").font(.system(size: 90)).transition(.scale.combined(with: .opacity)) }
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(f.title).font(.headline).lineLimit(2)
                if !f.note.isEmpty { Text(f.note).font(.subheadline).foregroundStyle(.white.opacity(0.85)).lineLimit(3) }
            }
            .contentShape(Rectangle())
            .onTapGesture { opened = f }
            actions(f, reactions: reactions, talk: talk.count, mine: mine)
        }
        .padding(14)
        .background(Theme.card, in: .rect(cornerRadius: Theme.radius))
        .foregroundStyle(.white)
    }

    private func header(_ p: UnifiedPost) -> some View {
        let f = p.item
        return HStack(spacing: 10) {
            MonsterSprite(form: f.avatar).padding(5)
                .frame(width: 40, height: 40)
                .background(Theme.raised, in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(f.isMe ? "Você" : f.name).font(.subheadline.bold()).lineLimit(1)
                    Text("· \(shortAgo(f.date))").font(.caption).foregroundStyle(Theme.dim)
                }
                Text(p.places.count > 2 ? "\(p.places.prefix(2).joined(separator: " · ")) +\(p.places.count - 2)" : p.places.joined(separator: " · "))
                    .font(.caption).foregroundStyle(Theme.dim).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    /// Foto grande quando tem; sem foto, uma faixa com o tipo e os números do treino
    @ViewBuilder
    private func media(_ f: FeedItem) -> some View {
        let photo = mod.isHidden(.photo, f.id) ? nil : f.photo.flatMap(UIImage.init(data:))
        if let photo {
            Color.clear
                .aspectRatio(4 / 5, contentMode: .fit)
                .overlay { Image(uiImage: photo).resizable().scaledToFill() }
                .overlay(alignment: .bottomLeading) { stats(f).padding(10) }
                .clipShape(.rect(cornerRadius: Theme.radiusL))
                .contentShape(Rectangle())
        } else {
            HStack(spacing: 14) {
                Image(systemName: f.kind.symbol).font(.system(size: 30, weight: .semibold)).foregroundStyle(Theme.accent)
                    .frame(width: 56, height: 56)
                    .background(Theme.accent.opacity(0.15), in: .rect(cornerRadius: Theme.radiusM))
                VStack(alignment: .leading, spacing: 2) {
                    Text(f.kind.name).font(.subheadline.weight(.semibold))
                    Text(statsText(f)).font(.caption).foregroundStyle(Theme.dim)
                }
                Spacer(minLength: 0)
                if f.hasPhoto { Image(systemName: "camera.fill").font(.caption).foregroundStyle(Theme.dim) }
            }
            .padding(12)
            .background(Theme.raised, in: .rect(cornerRadius: Theme.radiusL))
            .contentShape(Rectangle())
        }
    }

    private func stats(_ f: FeedItem) -> some View {
        Label(statsText(f), systemImage: f.kind.symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.ultraThinMaterial, in: .capsule)
            .environment(\.colorScheme, .dark)
    }

    private func statsText(_ f: FeedItem) -> String {
        let effort = f.effort >= 8 ? " · 🔥 pesado" : ""
        return "\(f.kind.name) · \(durationText(f.minutes))" + effort
    }

    private func actions(_ f: FeedItem, reactions: [CheckInComment], talk: Int, mine: CheckInComment?) -> some View {
        HStack(spacing: 16) {
            Button { toggleStrength(f, mine: mine) } label: {
                Label(mine == nil ? "Força" : "Força!", systemImage: mine == nil ? "hand.thumbsup" : "hand.thumbsup.fill")
                    .foregroundStyle(mine == nil ? .white : Theme.accent)
            }
            .accessibilityLabel(mine == nil ? "Mandar força" : "Tirar força")
            // "Comentar 3": o total de comentários do post ao lado
            Button { opened = f } label: {
                HStack(spacing: 6) {
                    Label("Comentar", systemImage: "bubble.right")
                    if talk > 0 {
                        Text("\(talk)").monospacedDigit()
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Theme.raised, in: .capsule)
                    }
                }
            }
            .accessibilityLabel(talk == 0 ? "Comentar" : "Comentar, \(talk) comentário\(talk == 1 ? "" : "s")")
            Spacer(minLength: 0)
            if !reactions.isEmpty {
                Text(summary(reactions)).font(.caption.weight(.semibold)).foregroundStyle(Theme.dim).lineLimit(1)
            }
        }
        .font(.subheadline.weight(.semibold))
        .buttonStyle(GMPress())
    }

    /// "💪 3 ❤️‍🔥 1": os emojis mais usados primeiro
    private func summary(_ list: [CheckInComment]) -> String {
        Dictionary(grouping: list, by: \.text).sorted { $0.value.count > $1.value.count }.prefix(3)
            .map { "\($0.key) \($0.value.count)" }.joined(separator: " ")
    }

    /// Força é uma reação 💪 (o mesmo do deck e do detalhe); de novo, tira
    private func toggleStrength(_ f: FeedItem, mine: CheckInComment?) {
        guard AccessStore.shared.can(.commentsCreate) else { return }
        if let mine { CommentSync.remove(mine, context: context) } else { CommentSync.add("💪", to: f.id, owner: f.memberID, scope: f.comments, context: context) }
        UIImpactFeedbackGenerator(style: mine == nil ? .medium : .light).impactOccurred()
    }

    private func pop(_ id: String) {
        withAnimation(.spring(duration: 0.3)) { burst = id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { withAnimation { if burst == id { burst = nil } } }
    }
}

/// Ranking dos bros da semana no Feed: os 3 primeiros e, se você não estiver entre eles, a sua posição. Toque abre o ranking completo.
struct FriendsRankCard: View {
    let rows: [FriendRank]

    var body: some View {
        let top = Array(rows.prefix(3).enumerated())
        let me = rows.firstIndex { $0.isMe }
        NavigationLink { FriendsRankingView() } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Ranking dos bros · semana", systemImage: "trophy.fill").font(.subheadline.bold())
                    Spacer()
                    Text("Ver tudo").font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.dim)
                }
                ForEach(top, id: \.element.id) { i, r in line(i, r) }
                if let me, me >= 3 {
                    GMDivider()
                    line(me, rows[me])
                }
            }
            .padding(14)
            .background(Theme.card, in: .rect(cornerRadius: Theme.radius))
            .foregroundStyle(.white)
        }
        .buttonStyle(GMPress())
    }

    private func line(_ i: Int, _ r: FriendRank) -> some View {
        HStack(spacing: 10) {
            Text(i < 3 ? ["🥇", "🥈", "🥉"][i] : "\(i + 1)º").font(i < 3 ? .body : .subheadline.bold()).frame(width: 28)
            MonsterSprite(form: r.avatar).frame(width: 28, height: 28)
            Text(r.isMe ? "Você" : r.name).font(.subheadline.weight(r.isMe ? .bold : .semibold)).lineLimit(1)
            Spacer()
            Text(FriendsMetric.checkIns.format(r.value)).font(.subheadline.monospacedDigit())
                .foregroundStyle(r.isMe ? Theme.accent : Theme.dim)
        }
    }
}
