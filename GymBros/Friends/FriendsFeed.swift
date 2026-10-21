import SwiftData
import SwiftUI

// Ranking dos bros (você e os amigos, sem precisar de liga) e o feed unificado (ligas e perfis dos amigos num lugar só,
// sem repetir o mesmo check-in postado em várias ligas).

/// Post de amigo no perfil, no mesmo formato do feed das ligas (vale XP)
@MainActor
func friendPosts(_ store: FriendsStore = .shared) -> [FeedItem] {
    store.friends.flatMap { f -> [FeedItem] in
        guard let p = store.profiles[f.id] else { return [] }
        let avatar = p.bro?.form ?? f.form
        return p.posts.map { r in
            FeedItem(id: r.id, memberID: f.id, name: f.name, avatar: avatar, isMe: false, date: r.date, title: r.title, note: r.note,
                     kind: r.kind, minutes: r.minutes, score: Game.xp(kind: r.kind, minutes: r.minutes, effort: r.effort), photo: nil,
                     hasPhoto: r.hasPhoto, effort: r.effort)
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
        let byID = Dictionary(activities.map { ($0.uuid, $0) }, uniquingKeysWith: { a, _ in a })
        // Os seus: o que está no seu perfil, do mesmo jeito que os amigos veem
        let mine: [FeedItem] = checkIns.filter { $0.leagueUUID == ProfileFeed.id }.compactMap { c in
            guard let a = byID[c.activityUUID] else { return nil }
            return FeedItem(id: c.uuid.uuidString, memberID: "me", name: name, avatar: roster.mainSnapshot.form, isMe: true, date: c.date, title: c.title,
                            note: c.note, kind: a.kind, minutes: a.minutes, score: Game.xp(kind: a.kind, minutes: a.minutes, effort: a.effort), photo: c.photo)
        }
        let rows = FriendsRanking.rank(me: mine, friends: friendPosts(store), people: store.friends.map { ($0.id, $0.name, store.profiles[$0.id]?.bro?.form ?? $0.form) },
                                       myName: name, myAvatar: roster.mainSnapshot.form, metric: metric, since: window.since())
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
    static func build(leagues: [League], checkIns: [LeagueCheckIn], activities: [Activity], me: String, friends: [FeedItem]) -> [UnifiedPost] {
        let byID = Dictionary(activities.map { ($0.uuid, $0) }, uniquingKeysWith: { a, _ in a })
        var posts: [String: UnifiedPost] = [:]
        func key(_ f: FeedItem) -> String { "\(f.memberID)|\(f.title)|\(Int(f.date.timeIntervalSince1970 / 60))" }
        for l in leagues where !l.isPastSeason {
            let feed = ModerationStore.shared.visible(LeagueBoard.feed(league: l, mine: checkIns.filter { $0.leagueUUID == l.uuid }, activities: byID,
                                                                        me: me, myAvatar: .egg))
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
            if var p = posts[k] { p.places.append("Perfil"); posts[k] = p } else {
                posts[k] = UnifiedPost(item: f, places: ["Perfil"], leagueIDs: [], fromFriendProfile: true)
            }
        }
        return posts.values.sorted { $0.item.date > $1.item.date }
    }
}

enum FeedFilter: Hashable {
    case all, friends, league(UUID)
}

struct UnifiedFeedView: View {
    @Query(sort: \League.joinedAt) private var leagues: [League]
    @Query private var checkIns: [LeagueCheckIn]
    @Query private var activities: [Activity]
    @AppStorage("trainerName") private var me = ""
    /// Última escolha das pílulas (fica salva)
    @AppStorage("feed.filter") private var filterRaw = "all"
    @State private var store = FriendsStore.shared
    @State private var opened: FeedItem?

    private var filter: FeedFilter {
        get {
            if filterRaw == "friends" { return .friends }
            if let id = UUID(uuidString: filterRaw) { return .league(id) }
            return .all
        }
    }

    var body: some View {
        let all = UnifiedFeed.build(leagues: leagues, checkIns: checkIns, activities: activities, me: me, friends: friendPosts(store))
        let friendIDs = store.friendIDs
        let shown: [UnifiedPost] = switch filter {
        case .all: all
        case .friends: all.filter { $0.item.isMe || friendIDs.contains($0.item.memberID) }
        case .league(let id): all.filter { $0.leagueIDs.contains(id) }
        }
        GMScreen("Feed", back: true) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    pill("Todos", on: filter == .all) { filterRaw = "all" }
                    pill("Amigos", on: filter == .friends) { filterRaw = "friends" }
                    ForEach(leagues.filter { !$0.isPastSeason }) { l in
                        pill("\(l.emoji) \(l.name)", on: filter == .league(l.uuid)) { filterRaw = l.uuid.uuidString }
                    }
                }
            }
            if shown.isEmpty {
                GMEmptyState(icon: "rectangle.stack", title: "Nada por aqui", message: "Check-ins das suas ligas e dos perfis dos amigos aparecem aqui.")
            }
            ForEach(shown.prefix(150)) { p in
                Button { opened = p.item } label: { row(p) }.buttonStyle(GMPress())
            }
        }
        .gmModal(item: $opened) { CheckInDetailView(item: $0) }
        .task {
            await store.refresh()
            for f in store.friends where store.profiles[f.id] == nil { await store.loadProfile(f.id) }
        }
    }

    private func pill(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(on ? Theme.accent : Theme.raised, in: .capsule)
                .foregroundStyle(on ? .black : .white)
        }
        .buttonStyle(GMPress())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func row(_ p: UnifiedPost) -> some View {
        let f = p.item
        return GMCard {
            HStack(spacing: 12) {
                ZStack {
                    if let data = f.photo, let img = UIImage(data: data) {
                        Color.clear.overlay { Image(uiImage: img).resizable().scaledToFill() }
                    } else {
                        Theme.raised
                        MonsterSprite(form: f.avatar).padding(6)
                    }
                }
                .frame(width: 60, height: 60)
                .clipShape(.rect(cornerRadius: Theme.radiusM))
                VStack(alignment: .leading, spacing: 3) {
                    Text(f.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                    Text("\(f.isMe ? "Você" : f.name) · \(shortAgo(f.date)) · \(durationText(f.minutes))").font(.caption).foregroundStyle(Theme.dim)
                    Text(p.places.count > 1 ? "Em \(p.places.count) lugares: " + p.places.joined(separator: ", ") : p.places.joined())
                        .font(.caption2).foregroundStyle(Theme.dim).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
        }
    }
}
