import SwiftData
import SwiftUI

// Notificações de cada liga: mural (tudo, só quando marcam você, nada), check-ins dos outros, reações e comentários,
// campeões e moderação. Ficam por série de liga (todas as temporadas) em `notify.leagues` no UserDefaults
// (vai com a conta). Os eventos entram na aba Notificações e viram notificação no tópico "Ligas".

enum MuralNotify: String, Codable, CaseIterable, Identifiable {
    case all, mentions, none

    var id: String { rawValue }

    var name: String {
        switch self {
        case .all: "Tudo"
        case .mentions: "Quando me marcam"
        case .none: "Nada"
        }
    }
}

struct LeagueNotifyPrefs: Codable, Hashable {
    var mural = MuralNotify.all
    /// Check-in novo de outra pessoa
    var checkIns = false
    /// Reações e comentários nos seus check-ins desta liga
    var reactions = true
    /// Campeão da semana, do mês e do ano
    var winners = true
    /// Pedidos de entrada, check-ins para revisar e check-in seu removido
    var moderation = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LeagueNotifyPrefs()
        mural = try c.decodeIfPresent(MuralNotify.self, forKey: .mural) ?? d.mural
        checkIns = try c.decodeIfPresent(Bool.self, forKey: .checkIns) ?? d.checkIns
        reactions = try c.decodeIfPresent(Bool.self, forKey: .reactions) ?? d.reactions
        winners = try c.decodeIfPresent(Bool.self, forKey: .winners) ?? d.winners
        moderation = try c.decodeIfPresent(Bool.self, forKey: .moderation) ?? d.moderation
    }

    static let key = "notify.leagues"

    static func of(_ league: League, defaults: UserDefaults = .standard) -> LeagueNotifyPrefs {
        let all = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        return all[league.seriesKey.uuidString].flatMap { try? JSONDecoder().decode(LeagueNotifyPrefs.self, from: Data($0.utf8)) } ?? LeagueNotifyPrefs()
    }

    func save(for league: League, defaults: UserDefaults = .standard) {
        var all = defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
        all[league.seriesKey.uuidString] = (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) }
        defaults.set(all, forKey: Self.key)
    }
}

/// Ajuste das notificações de uma liga
struct LeagueNotificationsView: View {
    let league: League
    @State private var prefs = LeagueNotifyPrefs()
    @State private var loaded = false

    var body: some View {
        GMModal("Notificações da liga") {
            Text("Valem para \(league.emoji) \(league.name), em todas as temporadas. Para desligar tudo das ligas, use Ajustes → Notificações.")
                .font(.footnote).foregroundStyle(Theme.dim)
            GMSection("Mural", footer: prefs.mural == .mentions ? "Avisa quando um recado tiver @ seguido do seu usuário ou do seu nome." : nil) {
                GMSegmented(options: MuralNotify.allCases.map { ($0, $0.name) }, selection: $prefs.mural)
            }
            GMSection {
                GMToggle(title: "Check-ins", subtitle: "Quando alguém posta um check-in", isOn: $prefs.checkIns)
                GMDivider()
                GMToggle(title: "Reações e comentários", subtitle: "Nos seus check-ins desta liga", isOn: $prefs.reactions)
                GMDivider()
                GMToggle(title: "Campeões", subtitle: league.format == .club ? "Quem venceu a semana, o mês e o ano" : "Quem venceu o desafio", isOn: $prefs.winners)
                GMDivider()
                GMToggle(title: "Moderação", subtitle: league.canModerate ? "Pedidos para entrar e check-ins para revisar" : "Quando um check-in seu é removido",
                         isOn: $prefs.moderation)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            prefs = LeagueNotifyPrefs.of(league)
        }
        .onChange(of: prefs) { _, p in p.save(for: league) }
    }
}

// MARK: - Eventos

@MainActor
enum LeagueNotices {
    /// Mural e check-ins só das últimas 24 h (a lista não enche com o histórico da liga)
    static let recentWindow: TimeInterval = 24 * 3600

    /// Eventos das ligas para a aba Notificações, já filtrados pelas preferências de cada liga
    static func events(context: ModelContext, now: Date = .now, defaults: UserDefaults = .standard) -> [InboxEvent] {
        let leagues = ((try? context.fetch(FetchDescriptor<League>())) ?? []).filter { !$0.isPastSeason }
        guard !leagues.isEmpty else { return [] }
        let checkIns = (try? context.fetch(FetchDescriptor<LeagueCheckIn>())) ?? []
        let activities = Dictionary(((try? context.fetch(FetchDescriptor<Activity>())) ?? []).map { ($0.uuid, $0) }, uniquingKeysWith: { a, _ in a })
        let me = defaults.string(forKey: "trainerName") ?? ""
        let user = defaults.string(forKey: "profileUsername") ?? ""
        var out: [InboxEvent] = []
        for l in leagues {
            let prefs = LeagueNotifyPrefs.of(l, defaults: defaults)
            let remote = LeagueRemoteStore.shared.remote(l)
            let mine = checkIns.filter { $0.leagueUUID == l.uuid }
            let feed = LeagueBoard.feed(league: l, mine: mine, activities: activities, me: me, myAvatar: .egg, remote: remote)
            let place = "\(l.emoji) \(l.name)"
            func event(_ id: String, _ kind: InboxEvent.Kind, actor: (id: String, name: String, form: String), date: Date,
                       text: String = "", detail: String = "") -> InboxEvent {
                InboxEvent(id: id, kind: kind, actorID: actor.id, actorName: actor.name, actorFormID: actor.form, date: date,
                           text: text, detail: detail.isEmpty ? place : detail, targetID: l.uuid.uuidString)
            }
            let league = (id: "liga", name: place, form: MonsterForm.egg.id)
            if prefs.moderation {
                // Seus check-ins removidos pelo dono
                for c in mine where c.reviewRaw == ReviewState.denied {
                    out.append(event("liga-removido-\(c.uuid)", .leagueRemoved, actor: league, date: c.syncedAt ?? c.date,
                                     text: c.date.formatted(.dateTime.day().month(.abbreviated))))
                }
                if l.canModerate {
                    for f in feed where f.pending && !f.isMe {
                        out.append(event("liga-revisao-\(f.id)", .leagueReview, actor: (f.memberID, f.name, f.avatar.id), date: f.date, text: f.title))
                    }
                    for m in remote.requests {
                        out.append(event("liga-pedido-\(l.uuid)-\(m.id)", .leagueRequest, actor: (m.id, m.name, m.formID), date: m.joinedAt ?? now))
                    }
                }
            }
            if prefs.winners && !l.settings.rankingsDisabled {
                if l.format == .club {
                    // Só o último campeão de cada período (semana, mês, ano)
                    let wins = ClubWinners.all(league: l, feed: feed, me: me, myAvatar: .egg, remote: remote, now: now)
                    for p in WinPeriod.allCases {
                        guard let w = wins.first(where: { $0.period == p }), let top = w.winners.first else { continue }
                        out.append(event("liga-campeao-\(l.seriesKey)-\(w.id)", .leagueWinner,
                                         actor: (top.id, namesList(w.winners), top.avatar.id), date: w.end, text: p.title(w.start).lowercased()))
                    }
                } else if l.isOver, let end = l.end {
                    let rank = LeagueBoard.ranking(feed: feed, league: l, me: me, myAvatar: .egg, since: nil, remote: remote)
                    if let top = rank.first, top.score > 0 {
                        let winners = rank.filter { $0.score == top.score }
                        out.append(event("liga-campeao-\(l.uuid)", .leagueWinner, actor: (top.id, namesList(winners), top.avatar.id), date: end,
                                         text: "o desafio"))
                    }
                }
            }
            let since = now.addingTimeInterval(-recentWindow)
            if prefs.mural != .none {
                for m in remote.messages where m.date >= since {
                    let mention = mentions(m.text, user: user, name: me)
                    guard prefs.mural == .all || mention, let who = remote.member(m.memberID) else { continue }
                    out.append(event("liga-mural-\(m.id)", .leagueMural, actor: (who.id, who.name, who.formID), date: m.date, text: m.text,
                                     detail: mention ? "marcou você em \(place)" : place))
                }
            }
            if prefs.checkIns {
                for f in feed where !f.isMe && f.date >= since {
                    out.append(event("liga-checkin-\(f.id)", .leagueCheckIn, actor: (f.memberID, f.name, f.avatar.id), date: f.date, text: f.title))
                }
            }
        }
        return out
    }

    /// Seus check-ins nas ligas em que reações e comentários estão desligados
    static func mutedCheckIns(context: ModelContext, defaults: UserDefaults = .standard) -> Set<String> {
        let leagues = (try? context.fetch(FetchDescriptor<League>())) ?? []
        let muted = Set(leagues.filter { !LeagueNotifyPrefs.of($0, defaults: defaults).reactions }.map(\.uuid))
        guard !muted.isEmpty else { return [] }
        return Set(((try? context.fetch(FetchDescriptor<LeagueCheckIn>())) ?? []).filter { muted.contains($0.leagueUUID) }.map(\.uuid.uuidString))
    }

    /// "@zero" ou "@Zero Silva" no texto (sem diferenciar maiúsculas e acentos)
    static func mentions(_ text: String, user: String, name: String) -> Bool {
        let t = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return [user, name].filter { !$0.isEmpty }.contains { t.contains("@" + $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)) }
    }
}

/// Texto com as @menções em destaque (mural e comentários)
func mentionText(_ text: String) -> AttributedString {
    var a = AttributedString(text)
    for word in text.split(separator: " ") where word.hasPrefix("@") && word.count > 1 {
        if let r = a.range(of: String(word)) { a[r].foregroundColor = Theme.accent; a[r].inlinePresentationIntent = .stronglyEmphasized }
    }
    return a
}
