import SwiftData
import SwiftUI

// Campeões do clube: o ranking de cada semana, mês e ano que já acabou, derivado do feed (igual em todos os
// aparelhos). Empate no primeiro lugar é dividido. No desafio, o fim traz a classificação final e o resumo.

enum WinPeriod: String, CaseIterable, Identifiable {
    case week, month, year

    var id: String { rawValue }

    var name: String {
        switch self {
        case .week: "Semana"
        case .month: "Mês"
        case .year: "Ano"
        }
    }

    /// "2 vitórias semanais"
    func wins(_ n: Int) -> String {
        let adj = switch self {
        case .week: n == 1 ? "semanal" : "semanais"
        case .month: n == 1 ? "mensal" : "mensais"
        case .year: n == 1 ? "anual" : "anuais"
        }
        return "\(n) vitória\(n == 1 ? "" : "s") \(adj)"
    }

    var component: Calendar.Component {
        switch self {
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
    }

    /// "Semana de 6 out", "Outubro de 2026", "2026"
    func title(_ start: Date) -> String {
        switch self {
        case .week: "Semana de \(start.formatted(.dateTime.day().month(.abbreviated)))"
        case .month: { let s = start.formatted(.dateTime.month(.wide).year()); return s.prefix(1).uppercased() + s.dropFirst() }()
        case .year: start.formatted(.dateTime.year())
        }
    }
}

struct PeriodWin: Identifiable {
    let period: WinPeriod
    let start: Date
    let end: Date
    /// Quem fez o maior placar do período (mais de um = dividiram o primeiro lugar)
    let winners: [RankRow]
    let score: Int

    var id: String { "\(period.rawValue)-\(start.timeIntervalSince1970)" }
}

@MainActor
enum ClubWinners {
    /// Campeões de cada semana, mês e ano encerrados desde o início do clube, do mais recente para o mais antigo
    static func all(league: League, feed: [FeedItem], me: String, myAvatar: MonsterForm, remote: RemoteLeague? = nil,
                    swiss: SwissTable? = nil, now: Date = .now) -> [PeriodWin] {
        let cal = league.settings.calendar()
        let remote = (remote ?? LeagueRemoteStore.shared.remote(league)).applying(league)
        let swiss = swiss ?? LeagueBoard.swiss(league: league, feed: feed, remote: remote, now: now)
        let limit = min(now, league.end ?? now)
        var out: [PeriodWin] = []
        for period in WinPeriod.allCases {
            guard var interval = cal.dateInterval(of: period.component, for: league.start) else { continue }
            while interval.end <= limit {
                let rank = LeagueBoard.ranking(feed: feed, league: league, me: me, myAvatar: myAvatar, since: interval.start,
                                               until: interval.end, remote: remote, swiss: swiss)
                if let top = rank.first, top.score > 0 {
                    out.append(PeriodWin(period: period, start: interval.start, end: interval.end,
                                         winners: rank.filter { $0.score == top.score }, score: top.score))
                }
                guard let next = cal.dateInterval(of: period.component, for: interval.end) else { break }
                interval = next
            }
        }
        return out.sorted { $0.end > $1.end }
    }

    /// Vitórias de cada pessoa, por período
    static func tally(_ wins: [PeriodWin]) -> [String: [WinPeriod: Int]] {
        var out: [String: [WinPeriod: Int]] = [:]
        for w in wins { for r in w.winners { out[r.id, default: [:]][w.period, default: 0] += 1 } }
        return out
    }

    /// Suas vitórias em todos os clubes (para o perfil)
    static func myWins(leagues: [League], checkIns: [LeagueCheckIn], activities: [UUID: Activity], me: String, avatar: MonsterForm) -> [WinPeriod: Int] {
        var out: [WinPeriod: Int] = [:]
        for l in leagues where l.format == .club && !l.settings.rankingsDisabled {
            let feed = LeagueBoard.feed(league: l, mine: checkIns.filter { $0.leagueUUID == l.uuid }, activities: activities, me: me, myAvatar: avatar)
            for (p, n) in tally(all(league: l, feed: feed, me: me, myAvatar: avatar))["me"] ?? [:] { out[p, default: 0] += n }
        }
        return out
    }
}

/// "Ana", "Ana e Bruno", "Ana, Bruno e Carla"
func namesList(_ rows: [RankRow]) -> String {
    let names = rows.map { $0.isMe ? "você" : $0.name }
    guard names.count > 1 else { return names.first ?? "" }
    return names.dropLast().joined(separator: ", ") + " e " + names.last!
}

/// Campeões do clube, por semana, mês e ano
struct ClubWinnersSection: View {
    let league: League
    let wins: [PeriodWin]
    @State private var period: WinPeriod = .week
    @State private var all = false

    var body: some View {
        let list = wins.filter { $0.period == period }
        let shown = all ? list : Array(list.prefix(6))
        GMSection("Campeões", footer: list.isEmpty ? "Quando a primeira \(period == .week ? "semana" : period == .month ? "mês" : "ano") do clube acabar, o campeão aparece aqui." : "Empate no primeiro lugar divide o título.") {
            GMSegmented(options: WinPeriod.allCases.map { ($0, $0.name) }, selection: $period)
            ForEach(shown) { w in
                GMDivider()
                HStack(spacing: 12) {
                    MonsterSprite(form: w.winners[0].avatar).frame(width: 36, height: 36)
                        .overlay(alignment: .topTrailing) { Text("👑").font(.caption2).offset(x: 5, y: -5) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(period.title(w.start)).font(.caption).foregroundStyle(Theme.dim)
                        Text(namesList(w.winners).prefix(1).uppercased() + namesList(w.winners).dropFirst())
                            .font(.subheadline.weight(.semibold)).lineLimit(2)
                    }
                    Spacer()
                    Text(league.scoring.short(w.score)).font(.subheadline.bold().monospacedDigit()).foregroundStyle(Theme.accent)
                }
                .accessibilityElement(children: .combine)
            }
            if list.count > 6 {
                GMDivider()
                GMRow(icon: all ? "chevron.up" : "chevron.down", iconTint: Theme.accent, title: all ? "Mostrar menos" : "Ver os \(list.count)") { all.toggle() }
            }
        }
        .onChange(of: period) { all = false }
    }
}

/// Fim do desafio: classificação final, parabéns e o resumo, com uma arte para compartilhar
struct ChallengeFinalCard: View {
    let league: League
    let rank: [RankRow]
    let feed: [FeedItem]

    private var winners: [RankRow] {
        guard let top = rank.first, top.score > 0 else { return [] }
        return rank.filter { $0.score == top.score }
    }

    /// "1.240 pts em 30 dias, somados por 8 bros. Mandaram bem."
    private var summary: String {
        let counted = feed.filter { !$0.pending && $0.date >= league.start && $0.date <= (league.end ?? .now) }
        let total = league.scoring == .treinos ? counted.count : counted.reduce(0) { $0 + $1.score }
        let people = rank.count
        return "\(league.scoring.format(total)) em \(league.durationDays) dia\(league.durationDays == 1 ? "" : "s"), somados por \(people) bro\(people == 1 ? "" : "s"). Mandaram bem."
    }

    private var congrats: String {
        guard !winners.isEmpty else { return "Ninguém pontuou neste desafio." }
        return winners.count > 1 ? "Parabéns a \(namesList(winners)) por dividirem o primeiro lugar." : "Parabéns a \(namesList(winners)) pelo primeiro lugar."
    }

    var body: some View {
        GMCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Classificação final").font(.caption.weight(.bold)).foregroundStyle(Theme.dim).tracking(0.6)
                Text(congrats).font(.headline)
                Text(summary).font(.subheadline).foregroundStyle(Theme.dim)
                ShareLink(item: art, preview: SharePreview("\(league.emoji) \(league.name)", image: art)) {
                    Label("Compartilhar resultado", systemImage: "square.and.arrow.up").font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(Theme.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var art: Image {
        // Colagem com as fotos do desafio (até 6, as mais recentes)
        let photos = feed.filter { $0.date >= league.start && $0.date <= (league.end ?? .now) }.flatMap { ($0.photo.map { [$0] } ?? []) + $0.extraPhotos }
        let r = ImageRenderer(content: FinalArt(league: league, podium: Array(rank.prefix(3)), congrats: congrats, summary: summary,
                                                photos: Array(photos.prefix(6)).compactMap(UIImage.init(data:))))
        r.scale = 3
        return r.uiImage.map { Image(uiImage: $0) } ?? Image(systemName: "trophy")
    }
}

/// Arte 9:16 do resultado, para stories
private struct FinalArt: View {
    let league: League
    let podium: [RankRow]
    let congrats: String
    let summary: String
    var photos: [UIImage] = []

    var body: some View {
        VStack(spacing: 22) {
            if photos.isEmpty {
                Text(league.emoji).font(.system(size: 64))
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(96), spacing: 6), count: 3), spacing: 6) {
                    ForEach(Array(photos.enumerated()), id: \.offset) { i, img in
                        Image(uiImage: img).resizable().scaledToFill().frame(width: 96, height: 96).clipped()
                            .clipShape(.rect(cornerRadius: 10)).rotationEffect(.degrees(Double((i % 3) - 1) * 3))
                    }
                }
            }
            Text(league.name).gmFont(30, weight: .heavy, design: .rounded, relativeTo: .title).multilineTextAlignment(.center)
            Text("Classificação final").font(.headline).foregroundStyle(Theme.accent)
            HStack(alignment: .bottom, spacing: 14) {
                ForEach(Array(podium.enumerated()), id: \.element.id) { i, r in
                    VStack(spacing: 6) {
                        Text(["🥇", "🥈", "🥉"][i]).font(.title)
                        MonsterSprite(form: r.avatar).frame(width: i == 0 ? 90 : 64, height: i == 0 ? 90 : 64)
                        Text(r.isMe ? "Você" : r.name).font(.subheadline.bold()).lineLimit(1)
                        Text(league.scoring.short(r.score)).font(.caption.monospacedDigit()).foregroundStyle(Theme.dim)
                    }
                    .frame(width: 96)
                }
            }
            Text(congrats).font(.title3.bold()).multilineTextAlignment(.center)
            Text(summary).font(.body).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
            Text("GymBros").font(.system(size: 22, weight: .black, design: .rounded)).foregroundStyle(Theme.accent)
        }
        .padding(32)
        .frame(width: 360, height: 640)
        .background(Theme.bg)
        .foregroundStyle(.white)
    }
}

extension LeagueRenewal {
    /// Recomeça um desafio encerrado hoje, com as mesmas pessoas, regras, times e duração; o antigo vira temporada anterior
    static func restart(_ old: League, now: Date = .now) -> League {
        let cal = Calendar.current
        let days = max(old.durationDays, 1)
        let next = makeNext(after: old, now: now)
        next.setPeriod(start: cal.startOfDay(for: now), end: cal.date(byAdding: .day, value: days - 1, to: cal.startOfDay(for: now)))
        next.autoRenew = old.autoRenew
        next.season = old.season + 1
        return next
    }
}
