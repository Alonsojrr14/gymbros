import PhotosUI
import SwiftData
import SwiftUI

// MARK: - Lista de ligas

struct LeaguesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \League.joinedAt) private var leagues: [League]
    @Query private var checkIns: [LeagueCheckIn]
    @Query private var activities: [Activity]
    @AppStorage("trainerName") private var trainerName = ""
    @Query(sort: \Monster.createdAt) private var monsters: [Monster]
    @Query private var allLeagues: [League]
    @State private var creating = false
    @State private var joining = false
    @State private var joinCode = ""
    @State private var proOpen = false

    var body: some View {
        let roster = Roster(monsters: monsters, activities: activities, checkIns: checkIns, leagues: allLeagues)
        NavigationStack {
            GMScreen("Ligas", avatar: true) {
                SocialGate(requires: .leaguesRead) {
                    if leagues.filter({ !$0.isPastSeason }).isEmpty {
                        GMEmptyState(icon: "trophy", title: "Nenhuma liga", message: "Crie uma liga e chame os amigos, ou entre com um código.")
                    }
                    ForEach(leagues.filter { !$0.isPastSeason }) { l in
                        NavigationLink { LeagueDetailView(league: l) } label: {
                            GMCard { LeagueRow(league: l, mine: checkIns.filter { $0.leagueUUID == l.uuid }, roster: roster, me: trainerName) }
                        }
                        .buttonStyle(GMPress())
                    }
                    PendingJoinsSection()
                    GMSection(footer: "Cada liga é um ranking de check-ins, de qualquer atividade. Ao entrar, você escolhe quem te representa: um bro seu ou um ovo novo. Os check-ins da liga dão XP para ele (um pouco menos que para o seu principal, que sempre recebe tudo).") {
                        GMRow(icon: "plus.circle", iconTint: Theme.accent, title: "Criar liga", chevron: true) {
                            // Sem Pro (quando valer), até \(ProStore.freeLeagues) ligas suas
                            let mine = leagues.filter { $0.isMine && !$0.isMock && !$0.isPastSeason }.count
                            if ProStore.shared.allows(.unlimitedLeagues) || mine < ProStore.freeLeagues { creating = true } else { proOpen = true }
                        }
                        GMDivider()
                        GMRow(icon: "ticket", iconTint: Theme.accent, title: "Entrar com código", chevron: true) { joinCode = ""; joining = true }
                        if !leagues.contains(where: { $0.code == MockLeague.code }) {
                            GMDivider()
                            GMRow(icon: "sparkles", iconTint: Theme.accent, title: "Experimentar a liga de exemplo", chevron: true) {
                                joinCode = MockLeague.code
                                joining = true
                            }
                        }
                    }
                }
            }
            .gmModal(isPresented: $creating) { CreateLeagueView() }
            .onReceive(NotificationCenter.default.publisher(for: StartIntentRouter.createLeague)) { _ in creating = true }
            .onReceive(NotificationCenter.default.publisher(for: StartIntentRouter.joinLeague)) { _ in joinCode = ""; joining = true }
            .gmModal(isPresented: $proOpen) { NavigationStack { ProPage() } }
            .gmModal(isPresented: $joining) { JoinLeagueView(code: joinCode) }
            .task {
                // Ligas de exemplo antigas não tinham data de fim
                for l in leagues where l.isMock && l.end == nil { l.setDuration(days: 30) }
                try? context.save()
                DemoAccount.seedIfNeeded(user: AuthStore.shared.user, context: context, representative: MainMonster.id)
                LeagueRenewal.run(context: context)
                await PendingJoins.check(context: context)
                await LeagueRemoteStore.shared.refresh(leagues)
                BrosWidgetFeed.update(context: context)
            }
        }
    }
}

extension MockLeague {
    static func make() -> League {
        let l = League(name: name, emoji: "🔥", scoring: .pontos,
                       start: Calendar.current.date(byAdding: .day, value: -12, to: .now)!, isMock: true)
        l.code = code
        l.setDuration(days: 30)
        l.teams = [LeagueTeam(id: LeagueTeams.legacyID(0), name: "Time Verde"), LeagueTeam(id: LeagueTeams.legacyID(1), name: "Time Roxo")]
        return l
    }
}

private struct LeagueRow: View {
    let league: League
    let mine: [LeagueCheckIn]
    let roster: Roster
    let me: String
    @Query private var activities: [Activity]

    var body: some View {
        let byID = Dictionary(activities.map { ($0.uuid, $0) }, uniquingKeysWith: { a, _ in a })
        let egg = roster.snapshot(league.monsterUUID)
        let feed = LeagueBoard.feed(league: league, mine: mine, activities: byID, me: me, myAvatar: egg.form)
        let rank = LeagueBoard.ranking(feed: feed, league: league, me: me, myAvatar: egg.form, since: nil)
        let pos = (rank.firstIndex { $0.isMe } ?? 0) + 1
        HStack(spacing: 12) {
            Text(league.emoji).font(.largeTitle)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(league.name).font(.headline)
                    if league.isMock { GMBadge(text: "Exemplo", tint: .white) }
                    if league.autoRenew { Image(systemName: "arrow.triangle.2.circlepath").font(.caption2.bold()).foregroundStyle(Theme.dim) }
                }
                Text((league.season > 1 ? "T\(league.season) · " : "") + "\(pos)º de \(rank.count) · " + (league.isOver ? "encerrado" : league.daysLeft.map { $0 == 1 ? "último dia" : "faltam \($0) dias" } ?? "clube"))
                    .font(.caption).foregroundStyle(Theme.dim)
            }
            Spacer()
            MonsterSprite(form: egg.form).frame(width: 44, height: 44)
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.dim)
        }
    }
}


// MARK: - Detalhe

struct LeagueDetailView: View {
    let league: League
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allCheckIns: [LeagueCheckIn]
    @Query private var activities: [Activity]
    @Query(sort: \Monster.createdAt) private var monsters: [Monster]
    @Query private var leagues: [League]
    @AppStorage("trainerName") private var trainerName = ""
    @State private var tab = 0
    @State private var window: RankWindow = .liga
    @State private var checkingIn = false
    @State private var menu = false
    @State private var editing = false
    @State private var leaving = false
    @State private var opened: FeedItem?
    @State private var teamChoice: TeamRow?
    @State private var noInvite = false
    @State private var profile: RemoteFriend?
    @State private var reviewing = false
    @State private var restarting = false
    @State private var memberMenu: RankRow?
    @State private var confirmBan: RankRow?
    @State private var choosingSuccessor = false
    @State private var notifying = false
    /// Planilha exportada, para a folha de compartilhar
    @State private var exported: IDBoxURL?
    @State private var postingDaily = false
    @State private var dailySession: WorkoutSession?
    @Query(filter: #Predicate<WorkoutSession> { $0.end != nil }, sort: \WorkoutSession.start) private var finishedSessions: [WorkoutSession]
    @Query private var messages: [LeagueMessage]
    /// Decisões de revisão: lidas aqui para a tela atualizar quando o dono aprova ou nega
    @Query private var reviews: [CheckInReview]

    var body: some View {
        let byID = Dictionary(activities.map { ($0.uuid, $0) }, uniquingKeysWith: { a, _ in a })
        let mine = allCheckIns.filter { $0.leagueUUID == league.uuid }
        // Dentro da liga você aparece com o bro que te representa nela
        let roster = Roster(monsters: monsters, activities: activities, checkIns: allCheckIns, leagues: leagues)
        let rep = roster.snapshot(league.monsterUUID)
        let avatar = rep.form
        let feed = LeagueBoard.feed(league: league, mine: mine, activities: byID, me: trainerName, myAvatar: avatar,
                                    reviews: reviews.filter { $0.leagueUUID == league.uuid })
        let swiss = LeagueBoard.swiss(league: league, feed: feed)
        let total = LeagueBoard.ranking(feed: feed, league: league, me: trainerName, myAvatar: avatar, since: nil, swiss: swiss)
        let since = window.since(calendar: league.settings.calendar())
        let rank = window == .liga ? total : LeagueBoard.ranking(feed: feed, league: league, me: trainerName, myAvatar: avatar, since: since, swiss: swiss)
        let settings = league.settings
        let toReview = league.canModerate ? feed.filter { $0.pending && !$0.isMe } : []
        let remote = LeagueRemoteStore.shared.remote(league)
        // Campeões de cada semana, mês e ano: só nos clubes com ranking
        let clubWins = league.format == .club && !settings.rankingsDisabled && tab == 1
            ? ClubWinners.all(league: league, feed: feed, me: trainerName, myAvatar: avatar, swiss: swiss) : []
        let tally = ClubWinners.tally(clubWins)

        GMScreen(league.name, back: true, large: false, bottomInset: 170) {
            if canInvite {
                ShareLink(item: inviteText) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .accessibilityLabel("Convidar")
                        .background(Theme.raised, in: .circle)
                        .foregroundStyle(.white)
                }
                .buttonStyle(GMPress())
            } else {
                GMIconButton(icon: "person.badge.plus", label: "Convidar") { noInvite = true }
            }
            GMIconButton(icon: "ellipsis", label: "Opções da liga") { menu = true }
        } content: {
            cover
            if league.isOver && league.format == .challenge && !settings.rankingsDisabled {
                ChallengeFinalCard(league: league, rank: total, feed: feed)
            }
            if !settings.rankingsDisabled { stats(total) }
            if !toReview.isEmpty {
                GMCard {
                    GMRow(icon: "checkmark.seal", iconTint: Theme.accent,
                          title: toReview.count == 1 ? "1 check-in para revisar" : "\(toReview.count) check-ins para revisar",
                          subtitle: "Aprove ou negue antes de pontuar", chevron: true) { reviewing = true }
                }
            }
            if let w = settings.dailyWorkout, w.isToday {
                DailyWorkoutCard(workout: w) { dailySession = LiveWorkout.startSession(routine: w.routine) }
            }
            if let parent = settings.parentClub, let club = leagues.first(where: { $0.seriesKey == parent && !$0.isPastSeason }) {
                Text("Desafio do clube \(club.emoji) \(club.name)").font(.caption.weight(.semibold)).foregroundStyle(Theme.dim)
            }
            if league.canModerate { LeagueRequestsSection(league: league, requests: remote.requests) }
            GMSegmented(options: [(0, "Check-ins"), (1, settings.rankingsDisabled ? "Metas" : "Ranking"), (2, "Mural")], selection: $tab)
            if tab == 0 {
                // Só a lista esconde denunciados e bloqueados; ranking e times contam todo mundo
                timeline(ModerationStore.shared.visible(feed))
            } else if tab == 2 {
                LeagueMuralView(league: league, avatar: avatar)
            } else {
                GMCard { repCard(rep, monster: roster.monster(league.monsterUUID)) }
                if !settings.rankingsDisabled { SwissRoundSection(league: league, table: swiss, people: total) }
                GMSegmented(options: RankWindow.allCases.map { ($0, $0.name) }, selection: $window)
                let teams = LeagueBoard.teams(league: league, ranking: rank, feed: feed, since: since)
                LeagueGoalsCard(league: league, people: rank, teams: teams)
                if settings.rankingsDisabled {
                    if settings.individualGoal == 0 && settings.teamGoal == 0 {
                        GMEmptyState(icon: "flag.checkered", title: "Sem ranking", message: "Esta liga não mostra quem está na frente. O dono pode definir uma meta nas regras.")
                    }
                } else {
                    teamsSection(teams)
                    GMSection(footer: rankFooter) {
                        ForEach(Array(rank.enumerated()), id: \.element.id) { i, r in
                            Button {
                                guard !r.isMe else { return }
                                if league.canModerate { memberMenu = r } else { profile = RemoteFriend(id: r.id, name: r.name, formID: r.avatar.id, code: "") }
                            } label: { rankRow(i + 1, r, wins: tally[r.id] ?? [:], mod: settings.mods.contains(r.id)) }
                                .buttonStyle(GMPress())
                                .accessibilityHint(r.isMe ? "" : "Abrir o perfil")
                            if i < rank.count - 1 { GMDivider() }
                        }
                    }
                    if league.format == .club {
                        ClubWinnersSection(league: league, wins: clubWins)
                        ClubChallengesSection(club: league)
                    }
                    pastSeasons(byID: byID, avatar: avatar)
                }
                rulesSection
            }
        }
        .overlay(alignment: .bottomTrailing) {
            // Liga que ainda não começou não aceita check-in (ficaria fora do período)
            if !league.isOver && league.hasStarted {
                // Acima da barra de abas
                GMFloatingButton(label: "Novo check-in") { checkingIn = true }
                .padding(.trailing, 20)
                .padding(.bottom, 90)
            }
        }
        .gmModal(isPresented: $checkingIn) { CheckInForm(preselected: [league.uuid]) }
        .gmModal(isPresented: $editing) { CreateLeagueView(league: league) }
        .gmModal(item: $opened) { CheckInDetailView(item: $0) }
        .gmModal(item: $profile) { FriendProfileView(friend: $0) }
        .gmModal(isPresented: $reviewing) { LeagueReviewQueue(league: league, items: toReview) }
        .gmModal(isPresented: $notifying) { LeagueNotificationsView(league: league) }
        .gmModal(isPresented: $postingDaily) { DailyWorkoutEditor(league: league) }
        .gmModal(item: $dailySession) { s in WorkoutView(session: s, history: finishedSessions.map(\.log)) }
        .gmSheet(isPresented: Binding(get: { exported != nil }, set: { if !$0 { exported = nil } })) { close in
            VStack(spacing: 14) {
                Text("Planilha pronta").font(.headline)
                Text("Todos os check-ins da liga, com quem, quando, treino, minutos e pontos.").font(.subheadline).foregroundStyle(Theme.dim)
                if let url = exported?.url {
                    ShareLink(item: url) { Label("Compartilhar CSV", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }
                        .buttonStyle(GMPress()).padding(.vertical, 12).background(Theme.accent, in: .capsule).foregroundStyle(.black)
                }
            }
        }
        .task(id: league.key) {
            await LeagueRemoteStore.shared.refresh([league])
        }
        .gmActions(isPresented: Binding(get: { teamChoice != nil }, set: { if !$0 { teamChoice = nil } }),
                   title: teamChoice.map { "Entrar no \($0.name)?" } ?? "",
                   message: "Seus check-ins passam a somar para este time. Dá para trocar depois.", actions: teamChoice.map { team in [
            GMAction("Entrar no time", icon: "person.3.fill") {
                league.myTeamID = team.id
                league.syncedAt = nil
                LeagueRemoteStore.shared.scheduleFlush()
                try? context.save()
            }
        ] } ?? [])
        .gmActions(isPresented: $noInvite, title: "Liga de exemplo",
                   message: "Os participantes desta liga são simulados e o código dela só existe neste iPhone, então ainda não dá para convidar ninguém. Convites chegam quando o app tiver servidor.",
                   actions: [])
        .gmActions(isPresented: $menu, title: "\(league.emoji) \(league.name)", actions:
            (AccessStore.shared.can(.leaguesUpdate, on: league) ? [GMAction("Editar liga", icon: "pencil") { editing = true }] : [])
            + (canRestart ? [GMAction("Reiniciar desafio", icon: "arrow.counterclockwise") { restarting = true }] : [])
            + [GMAction("Notificações da liga", icon: "bell") { notifying = true }]
            + (league.canModerate && !league.isOver ? [GMAction("Treino do dia", icon: "list.clipboard") { postingDaily = true }] : [])
            + (league.canModerate && ProStore.shared.allows(.export) ? [GMAction("Exportar dados (CSV)", icon: "tablecells") { exportCSV() }] : []) + [
            GMAction("Sair da liga", icon: "rectangle.portrait.and.arrow.right", destructive: true) { leaving = true },
        ])
        .gmActions(isPresented: Binding(get: { memberMenu != nil }, set: { if !$0 { memberMenu = nil } }),
                   title: memberMenu?.name, actions: memberMenu.map(memberActions) ?? [])
        .gmActions(isPresented: Binding(get: { confirmBan != nil }, set: { if !$0 { confirmBan = nil } }),
                   title: confirmBan.map { "Banir \($0.name)?" } ?? "",
                   message: "Sai da liga com os check-ins e não volta nem pelo código. Dá para desbanir em Editar liga.", actions: [
            GMAction("Banir da liga", icon: "hand.raised.fill", destructive: true) {
                if let r = confirmBan { league.moderate { s in s.banned.append(r.id); s.mods.removeAll { $0 == r.id } } }
                try? context.save()
            }
        ])
        .gmModal(isPresented: $choosingSuccessor) {
            LeagueSuccessorPicker(league: league, members: LeagueRemoteStore.shared.remote(league).members) { id in
                let key = league.key
                Task { try? await LeagueRemoteStore.shared.backend.transfer(key, to: id) }
                leaveLeague()
            }
        }
        .gmActions(isPresented: $restarting, title: "Reiniciar o desafio?",
                   message: "Começa hoje um desafio novo com as mesmas pessoas, regras e duração (\(league.durationDays) dias). Os check-ins zeram; este fica guardado como temporada anterior, com o campeão.",
                   actions: [
            GMAction("Reiniciar", icon: "arrow.counterclockwise") {
                let next = LeagueRenewal.restart(league)
                context.insert(next)
                league.nextUUID = next.uuid
                try? context.save()
                LeagueRemoteStore.shared.scheduleFlush()
                dismiss()
            }
        ])
        .gmActions(isPresented: $leaving, title: "Sair de \(league.name)?",
                   message: "Os check-ins desta liga somem. Suas atividades e seus bros continuam.", actions: [
            GMAction("Sair", icon: "rectangle.portrait.and.arrow.right", destructive: true) {
                if league.isMine && !league.isMock && !LeagueRemoteStore.shared.remote(league).members.isEmpty {
                    choosingSuccessor = true
                } else {
                    leaveLeague()
                }
            }
        ])
    }

    /// Ações do dono (ou moderador) sobre outra pessoa da liga
    private func memberActions(_ r: RankRow) -> [GMAction] {
        let isMod = league.settings.mods.contains(r.id)
        var list = [GMAction("Ver perfil", icon: "person.crop.circle") { profile = RemoteFriend(id: r.id, name: r.name, formID: r.avatar.id, code: "") }]
        // Só o dono escolhe moderadores e bane
        if league.isMine && (isMod || ProStore.shared.allows(.moderators)) {
            list.append(isMod ? GMAction("Tirar de moderador", icon: "shield.slash") { league.moderate { $0.mods.removeAll { $0 == r.id } } }
                              : GMAction("Tornar moderador", icon: "shield") { league.moderate { $0.mods.append(r.id) } })
        }
        list.append(GMAction("Remover da liga", icon: "person.fill.xmark", destructive: true) {
            league.moderate { s in s.removed.append(r.id); s.mods.removeAll { $0 == r.id } }
            try? context.save()
        })
        if league.isMine { list.append(GMAction("Banir da liga", icon: "hand.raised.fill", destructive: true) { confirmBan = r }) }
        return list
    }

    private func leaveLeague() {
        do {
                // Sai de todas as temporadas da liga
                let series = leagues.filter { $0.seriesKey == league.seriesKey }
                let ids = Set(series.map(\.uuid))
                let gone = allCheckIns.filter { ids.contains($0.leagueUUID) }
                // Comentários dos check-ins que somem
                let goneIDs = Set(gone.map(\.uuid.uuidString))
                ((try? context.fetch(FetchDescriptor<CheckInComment>())) ?? []).filter { goneIDs.contains($0.itemID) }.forEach(context.delete)
                gone.forEach(context.delete)
                messages.filter { ids.contains($0.leagueUUID) }.forEach(context.delete)
                // No servidor, sair leva junto seus check-ins
                if !league.isMock {
                    let key = league.key
                    Task { try? await LeagueRemoteStore.shared.backend.leave(key) }
                }
                ids.forEach(LeagueOutbox.clear)
                series.forEach(context.delete)
                try? context.save()
                dismiss()
        }
    }

    /// Temporadas anteriores da mesma liga, com o campeão de cada uma
    @ViewBuilder
    private func pastSeasons(byID: [UUID: Activity], avatar: MonsterForm) -> some View {
        let past = leagues.filter { $0.seriesKey == league.seriesKey && $0.season < league.season }.sorted { $0.season > $1.season }
        if !past.isEmpty {
            GMSection("Temporadas anteriores") {
                ForEach(past) { p in
                    let feed = LeagueBoard.feed(league: p, mine: allCheckIns.filter { $0.leagueUUID == p.uuid }, activities: byID, me: trainerName, myAvatar: avatar)
                    let rank = LeagueBoard.ranking(feed: feed, league: p, me: trainerName, myAvatar: avatar, since: nil)
                    let pos = (rank.firstIndex { $0.isMe } ?? 0) + 1
                    NavigationLink { LeagueDetailView(league: p) } label: {
                        HStack(spacing: 12) {
                            Text("T\(p.season)").font(.subheadline.bold().monospacedDigit())
                                .frame(width: 40, height: 40).background(Theme.raised, in: .circle)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rank.first.map { "🏆 \($0.isMe ? "Você" : $0.name) · \(p.scoring.format($0.score))" } ?? "Sem check-ins").font(.subheadline.weight(.semibold))
                                Text("\(p.start.formatted(.dateTime.day().month(.abbreviated))) – \((p.end ?? p.start).formatted(.dateTime.day().month(.abbreviated))) · você ficou em \(pos)º")
                                    .font(.caption).foregroundStyle(Theme.dim)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.dim)
                        }
                        .contentShape(Rectangle())
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(GMPress())
                    if p.id != past.last?.id { GMDivider() }
                }
            }
        }
    }

    /// CSV com os check-ins da liga (dono e moderadores)
    private func exportCSV() {
        let byID = Dictionary(activities.map { ($0.uuid, $0) }, uniquingKeysWith: { a, _ in a })
        let feed = LeagueBoard.feed(league: league, mine: allCheckIns.filter { $0.leagueUUID == league.uuid }, activities: byID,
                                    me: trainerName, myAvatar: .egg)
        let url = LeagueExport.csv(league: league, feed: feed)
        exported = url.map(IDBoxURL.init)
    }

    /// Só o dono, num desafio que já acabou e ainda não tem a próxima temporada
    private var canRestart: Bool {
        league.format == .challenge && league.isOver && !league.isPastSeason && AccessStore.shared.can(.leaguesUpdate, on: league)
    }

    /// Liga criada com participantes de exemplo: o código não existe para mais ninguém (a de exemplo, AMIGOS, qualquer um abre)
    private var canInvite: Bool { !league.isMock || league.code == MockLeague.code }

    private var inviteText: String {
        "Entra na minha liga \(league.emoji) \(league.name) no GymBros! Código: \(league.code)"
    }

    private var period: String {
        let f = Date.FormatStyle.dateTime.day().month(.abbreviated)
        guard let end = league.end else { return "Desde \(league.start.formatted(f)) · sem fim" }
        return "\(league.start.formatted(f)) – \(end.formatted(f))"
    }

    // MARK: Capa

    private var cover: some View {
        ZStack(alignment: .bottomLeading) {
            if let data = league.cover, let img = UIImage(data: data) {
                Color.clear.overlay { Image(uiImage: img).resizable().scaledToFill().allowsHitTesting(false) }
            } else {
                LinearGradient(colors: [Theme.accent.opacity(0.55), Theme.card], startPoint: .topTrailing, endPoint: .bottomLeading)
                    .overlay(alignment: .topTrailing) {
                        Text(league.emoji).font(.system(size: 90)).rotationEffect(.degrees(12)).padding(.trailing, 18).padding(.top, 10)
                    }
            }
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if league.isMock { GMBadge(text: "Exemplo", tint: .white) }
                    if league.season > 1 || league.autoRenew { GMBadge(text: "Temporada \(league.season)", tint: .white) }
                    if league.isOver { GMBadge(text: "Encerrada", tint: .white) }
                }
                Text("\(league.emoji) \(league.name)").gmFont(26, weight: .heavy, design: .rounded, relativeTo: .title).lineLimit(2)
                    .minimumScaleFactor(0.6)
                Text(canInvite ? "\(period) · código \(league.code)" : "\(period) · participantes simulados").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
            }
            .padding(16)
        }
        .frame(height: 190)
        .frame(maxWidth: .infinity)
        .clipShape(.rect(cornerRadius: Theme.radius))
    }

    // MARK: Líder, você e dias

    private func stats(_ rank: [RankRow]) -> some View {
        let leader = rank.first
        let mePos = (rank.firstIndex { $0.isMe } ?? 0) + 1
        let me = rank.first { $0.isMe }
        return HStack(alignment: .top, spacing: 0) {
            if let leader {
                statPerson(label: league.isOver ? "Campeão" : "Líder", row: leader, crown: true,
                           line: leader.score > 0 ? scoreText(leader.score) : "ninguém pontuou")
            }
            Rectangle().fill(Theme.stroke).frame(width: 1, height: 96)
            if let me {
                statPerson(label: "Você · \(mePos)º", row: me, crown: false,
                           line: mePos == 1 || leader == nil ? scoreText(me.score) : "\(scoreText(me.score)) · −\(leader!.score - me.score)")
            }
            Rectangle().fill(Theme.stroke).frame(width: 1, height: 96)
            VStack(spacing: 4) {
                if !league.hasStarted {
                    Text(league.daysToStart == 1 ? "Começa" : "Começa em").font(.caption.weight(.semibold)).foregroundStyle(Theme.dim)
                    if league.daysToStart == 1 {
                        Text("amanhã").gmFont(24, weight: .heavy, design: .rounded, relativeTo: .title2).lineLimit(1).minimumScaleFactor(0.5).frame(height: 50)
                        Text(" ").font(.caption2)
                    } else {
                        big("\(league.daysToStart)")
                        Text("dias").font(.caption2).foregroundStyle(Theme.dim)
                    }
                } else if league.isOver {
                    Text("Fim").font(.caption.weight(.semibold)).foregroundStyle(Theme.dim)
                    Text("🏁").font(.system(size: 38)).frame(height: 50)
                    Text("liga encerrada").font(.caption2).foregroundStyle(Theme.dim)
                } else if let d = league.daysLeft {
                    if d == 1 {
                        Text("Termina").font(.caption.weight(.semibold)).foregroundStyle(Theme.dim)
                        Text("hoje").gmFont(28, weight: .heavy, design: .rounded, relativeTo: .title).lineLimit(1).minimumScaleFactor(0.5).frame(height: 50).foregroundStyle(Theme.accent)
                        Text("último dia").font(.caption2).foregroundStyle(Theme.dim)
                    } else {
                        Text("Faltam").font(.caption.weight(.semibold)).foregroundStyle(Theme.dim)
                        big("\(d)").foregroundStyle(d <= 3 ? Theme.accent : .white)
                        Text("dias").font(.caption2).foregroundStyle(Theme.dim)
                    }
                } else {
                    Text("Duração").font(.caption.weight(.semibold)).foregroundStyle(Theme.dim)
                    big("∞")
                    Text("sem data de fim").font(.caption2).foregroundStyle(Theme.dim)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 14)
        .background(Theme.card, in: .rect(cornerRadius: Theme.radius))
        .onTapGesture { withAnimation { tab = 1 } }
    }

    private func big(_ text: String) -> some View {
        Text(text).gmFont(40, weight: .heavy, design: .rounded, mono: true, relativeTo: .largeTitle)
            .lineLimit(1).minimumScaleFactor(0.5).frame(height: 50)
    }

    private func statPerson(label: String, row: RankRow, crown: Bool, line: String) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(Theme.dim)
            MonsterSprite(form: row.avatar)
                .frame(width: 50, height: 50)
                .overlay(alignment: .topTrailing) { if crown { Text("👑").font(.caption).offset(x: 6, y: -6) } }
            Text(row.isMe ? (row.name.isEmpty ? "Você" : row.name) : row.name).font(.subheadline.bold()).lineLimit(1)
            Text(line).font(.caption2.monospacedDigit()).foregroundStyle(row.isMe ? Theme.accent : Theme.dim).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
    }

    private func scoreText(_ v: Int) -> String { league.scoring.format(v) }

    /// Regras da liga para quem participa: verificação, revisão, pose, limites e início da semana
    @ViewBuilder
    private var rulesSection: some View {
        let s = league.settings
        let lines = s.verification.bullets.filter { _ in s.verification.preset != .off }
            + (s.reviewRequired ? ["O dono aprova cada check-in antes de pontuar"] : [])
            + (s.posesEnabled ? ["Pose do dia na foto: hoje, \(DailyPose.today.emoji) \(DailyPose.today.name)"] : [])
            + s.limits.summary
            + (league.scoring == .atividades ? s.pointRules.map { "\($0.targetName): \($0.summary)" } : [])
            + (s.weekStart.map { ["A semana começa no \(LeagueGoalsSection.weekday($0).lowercased())"] } ?? [])
        if !lines.isEmpty {
            GMSection("Regras") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(lines, id: \.self) { Text("• " + $0).font(.subheadline) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var rankFooter: String {
        var parts = [league.scoring.detail]
        if league.photoRule != .livre { parts.append(league.photoRule.detail) }
        let w = league.attributeWeights
        if league.scoring == .pontos && !w.isEmpty {
            parts.append("Pesos: " + Attribute.allCases.compactMap { a in w[a].map { "\(a.name) \(weightText($0))" } }.joined(separator: ", ") + ".")
        }
        parts.append(league.tieBreak.detail)
        return parts.joined(separator: " ")
    }

    // MARK: Linha do tempo

    @ViewBuilder
    private func timeline(_ feed: [FeedItem]) -> some View {
        if feed.isEmpty {
            GMEmptyState(icon: "camera", title: "Nenhum check-in ainda", message: league.isOver ? "A liga acabou sem check-ins." : "Toque no + e seja o primeiro!")
        }
        let cal = Calendar.current
        let days = Dictionary(grouping: feed.prefix(120)) { cal.startOfDay(for: $0.date) }
        ForEach(days.keys.sorted(by: >), id: \.self) { day in
            let items = (days[day] ?? []).sorted { $0.date > $1.date }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(dayTitle(day)).font(.headline)
                    Spacer()
                    if !items.isEmpty {
                        Text("\(items.count) check-in\(items.count == 1 ? "" : "s")").font(.caption).foregroundStyle(Theme.dim)
                    }
                }
                if !items.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                            timelineRow(item, first: i == 0, last: i == items.count - 1)
                        }
                    }
                    .padding(.horizontal, 12)
                    .background(Theme.card, in: .rect(cornerRadius: Theme.radius))
                }
            }
        }
    }

    private func dayTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Hoje" }
        if cal.isDateInYesterday(day) { return "Ontem" }
        let s = day.formatted(.dateTime.weekday(.wide).day().month(.wide))
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    private func timelineRow(_ item: FeedItem, first: Bool, last: Bool) -> some View {
        Button { opened = item } label: {
            HStack(spacing: 12) {
                // Trilho da linha do tempo
                VStack(spacing: 0) {
                    Rectangle().fill(first ? .clear : Theme.stroke).frame(width: 2)
                    Circle().fill(item.isMe ? Theme.accent : Theme.dim).frame(width: 9, height: 9)
                    Rectangle().fill(last ? .clear : Theme.stroke).frame(width: 2)
                }
                .frame(width: 10)
                thumb(item).frame(width: 58, height: 58).clipShape(.rect(cornerRadius: Theme.radiusM))
                    .overlay(alignment: .bottomTrailing) {
                        if !item.extraPhotos.isEmpty {
                            Text("+\(item.extraPhotos.count)").font(.caption2.bold()).padding(.horizontal, 5).padding(.vertical, 2)
                                .background(.black.opacity(0.65), in: .capsule).foregroundStyle(.white).padding(3)
                        }
                    }
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                    HStack(spacing: 5) {
                        MonsterSprite(form: item.avatar).frame(width: 20, height: 20)
                        Text(item.isMe ? "Você" : item.name).font(.caption.weight(.semibold))
                            .foregroundStyle(item.isMe ? Theme.accent : .white)
                        Text("· \(durationText(item.minutes))").font(.caption).foregroundStyle(Theme.dim)
                    }
                    if let place = item.place {
                        Text("📍 \(place)").font(.caption2).foregroundStyle(Theme.dim).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(item.date.formatted(.dateTime.hour().minute())).font(.caption.monospacedDigit()).foregroundStyle(Theme.dim)
                    if item.pending {
                        Text("em revisão").font(.caption.weight(.semibold)).foregroundStyle(Theme.dim)
                    } else {
                        Text((item.score < 0 ? "−" : "+") + league.scoring.short(abs(item.score))).font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(item.score < 0 ? .red : Theme.accent)
                    }
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .foregroundStyle(.white)
        }
        .buttonStyle(GMPress())
    }

    @ViewBuilder
    private func thumb(_ item: FeedItem) -> some View {
        if let data = item.photo, let img = UIImage(data: data) {
            Color.clear.overlay { Image(uiImage: img).resizable().scaledToFill() }
        } else if item.hasPhoto {
            // Foto de outro participante: chega por URL quando houver servidor
            LinearGradient(colors: [Theme.accent.opacity(0.35), Theme.raised], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay { Image(systemName: item.kind.symbol).font(.title2).foregroundStyle(.white) }
                .overlay(alignment: .bottomTrailing) { Image(systemName: "camera.fill").font(.caption2).padding(5).foregroundStyle(.white.opacity(0.8)) }
        } else {
            Image(systemName: item.kind.symbol)
                .font(.title2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(item.isMe ? Theme.accent.opacity(0.22) : Theme.raised)
                .foregroundStyle(item.isMe ? Theme.accent : .white)
        }
    }

    // MARK: Ranking

    @ViewBuilder
    private func teamsSection(_ teams: [TeamRow]) -> some View {
        if !teams.isEmpty {
            GMSection("Times", footer: league.myTeamID == nil ? "Toque num time para entrar. O bro do time cresce com a média de XP dos membros e evolui pelo atributo que o time mais treina." : "O bro do time cresce com a média de XP dos membros e evolui pelo atributo que o time mais treina.") {
                ForEach(Array(teams.enumerated()), id: \.element.id) { i, t in
                    Button { if !t.isMine && !league.isOver { teamChoice = t } } label: {
                        HStack(spacing: 12) {
                            Text(i < 3 ? ["🥇", "🥈", "🥉"][i] : "\(i + 1)º").font(i < 3 ? .title3 : .subheadline.bold()).frame(width: 32)
                            LivingMonster(form: t.form, progress: t.progress).frame(width: 44, height: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(t.name).font(.subheadline.weight(t.isMine ? .bold : .semibold))
                                    if t.isMine { GMBadge(text: "Seu time", tint: Theme.accent) }
                                }
                                Text("\(t.members) pessoa\(t.members == 1 ? "" : "s") · bro \(t.form.stage.name.lowercased())").font(.caption).foregroundStyle(Theme.dim)
                            }
                            Spacer()
                            Text(league.scoring.short(t.score)).font(.headline.monospacedDigit()).foregroundStyle(t.isMine ? Theme.accent : .white)
                        }
                        .contentShape(Rectangle())
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(GMPress())
                    if i < teams.count - 1 { GMDivider() }
                }
            }
        }
    }

    private func repCard(_ m: Snapshot, monster: Monster?) -> some View {
        HStack(spacing: 14) {
            LivingMonster(form: m.form, progress: m.progress).frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 5) {
                Text("Te representa nesta liga").font(.caption).foregroundStyle(Theme.dim)
                Text(monster?.displayName(m.form) ?? m.form.name).font(.headline)
                Text(m.stage == .egg ? "Faltam \(m.xpToNext ?? 0) XP para chocar" : "Nível \(m.level)").font(.caption)
                GMProgressBar(value: m.progress, height: 6)
            }
        }
    }

    private func rankRow(_ pos: Int, _ r: RankRow, wins: [WinPeriod: Int] = [:], mod: Bool = false) -> some View {
        HStack(spacing: 12) {
            Text(pos <= 3 ? ["🥇", "🥈", "🥉"][pos - 1] : "\(pos)º")
                .font(pos <= 3 ? .title3 : .subheadline.bold())
                .frame(width: 32)
            MonsterSprite(form: r.avatar).frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(r.isMe ? "\(r.name) (você)" : r.name).font(.subheadline.weight(r.isMe ? .bold : .semibold))
                    if mod { GMBadge(text: "Mod", tint: Theme.accent) }
                }
                Text("\(r.checkIns) check-in\(r.checkIns == 1 ? "" : "s")" + (swissNote(r).map { " · \($0)" } ?? "") + (r.tied ? " · \(tieNote(r))" : ""))
                    .font(.caption).foregroundStyle(Theme.dim)
                if !wins.isEmpty {
                    Text("🏆 " + WinPeriod.allCases.compactMap { p in wins[p].map { p.wins($0) } }.joined(separator: " · "))
                        .font(.caption2.weight(.semibold)).foregroundStyle(Theme.accent)
                }
            }
            Spacer()
            Text(league.scoring.short(r.score)).font(.headline.monospacedDigit()).foregroundStyle(r.isMe ? Theme.accent : .white)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .foregroundStyle(.white)
    }

    /// Pontos suíços, discretos, só depois da primeira rodada encerrada
    private func swissNote(_ r: RankRow) -> String? {
        r.swiss.map { "suíço \(Swiss.format($0))" }
    }

    /// Por que ficou nessa posição no empate
    private func tieNote(_ r: RankRow) -> String {
        switch league.tieBreak {
        case .primeiro: r.reachedAt.map { "empate · chegou \($0.formatted(.dateTime.day().month(.abbreviated).hour().minute()))" } ?? "empate"
        case .sequencia: "empate · \(r.bestStreak) dia\(r.bestStreak == 1 ? "" : "s") seguido\(r.bestStreak == 1 ? "" : "s")"
        case .checkins: "empate"
        }
    }
}

/// "2×", "0,5×"
func weightText(_ v: Double) -> String {
    (v == v.rounded() ? "\(Int(v))" : v.formatted(.number.precision(.fractionLength(1)))) + "×"
}

// MARK: - Criar, editar e entrar

/// Cria uma liga nova ou edita uma existente
struct CreateLeagueView: View {
    var league: League? = nil
    /// Clube em que o desafio novo é criado (as pessoas do clube participam)
    var parentClub: League? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var emoji = "🏆"
    @State private var scoring: LeagueScoring = .pontos
    @State private var format: LeagueFormat = .challenge
    @State private var activityRuleMode: LeagueActivityRuleMode = .all
    @State private var selectedWorkoutTypes: Set<UInt> = []
    @State private var choosingWorkoutTypes = false
    /// Peso de cada atributo em meios (2 = 1×), para o stepper andar de 0,5 em 0,5
    @State private var halves: [Attribute: Int] = Dictionary(uniqueKeysWithValues: Attribute.allCases.map { ($0, 2) })
    @State private var tieBreak: LeagueTieBreak = .primeiro
    @State private var photoRule: PhotoRule = .livre
    @State private var swiss: SwissCriterion = .pontos
    @State private var teams: [LeagueTeam] = []
    @State private var start = Calendar.current.startOfDay(for: .now)
    @State private var end: Date = Calendar.current.date(byAdding: .day, value: 29, to: Calendar.current.startOfDay(for: .now))!
    @State private var hasEnd = true
    @State private var autoRenew = false
    @State private var cover: Data?
    @State private var coverPick: PhotosPickerItem?
    @State private var withExamples = false
    /// Verificação, revisão, pose, tabela de pontos, limites e metas (liga nova já vem com a verificação padrão)
    @State private var settings = LeagueSettings.newLeague
    @State private var rep: UUID? = MainMonster.id
    @State private var loaded = false
    @State private var blocked = false

    /// Exemplo com o peso atual: quanto vale 1 h de corrida e de musculação, esforço 6
    private var weightsFooter: String {
        let w = halves.mapValues { Double($0) / 2 }
        let ex = [ActivityKind.corrida, .musculacao, .yoga].map { k in
            "\(k.name) \(LeagueScoring.pontos.score(ScoreInput(kind: k, minutes: 60, effort: 6), weights: w))"
        }
        return "Multiplica a parte de cada atributo nos pontos; 0× tira o atributo da conta. 1 h em esforço 6 vale: " + ex.joined(separator: " · ") + " pts."
    }

    private let emojis = ["🏆", "🔥", "💪", "🏃", "⚡️", "🦁", "🐉", "⭐️", "🏐", "🧘"]
    private var cal: Calendar { .current }
    private var activityRule: LeagueActivityRule { LeagueActivityRule(mode: activityRuleMode, workoutTypeIDs: selectedWorkoutTypes) }
    private var activitySelectionTitle: String {
        guard !selectedWorkoutTypes.isEmpty else { return "Escolher treinos" }
        return "\(selectedWorkoutTypes.count) treino\(selectedWorkoutTypes.count == 1 ? "" : "s") selecionado\(selectedWorkoutTypes.count == 1 ? "" : "s")"
    }

    /// Nomes dos escolhidos para a linha do formulário: "Core, Musculação +3"
    private var activitySelectionNames: String {
        let names = WorkoutType.all.filter { selectedWorkoutTypes.contains($0.id) }.map(\.name)
        guard !names.isEmpty else { return activityRuleMode == .only ? "Apenas estes entram no ranking" : "Estes ficam fora do ranking" }
        return names.prefix(2).joined(separator: ", ") + (names.count > 2 ? " +\(names.count - 2)" : "")
    }

    var body: some View {
        GMModal(parentClub.map { "Desafio no \($0.name)" } ?? (league == nil ? "Novo grupo" : "Editar grupo"), confirm: league == nil ? "Criar" : "Salvar",
                confirmEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty && (activityRuleMode != .only || !selectedWorkoutTypes.isEmpty), onConfirm: save) {
            GMSection("Nome") {
                GMTextField(placeholder: "Nome da liga", text: $name)
                if blocked { ContentBlockedNote() }
                GMFlow {
                    ForEach(emojis, id: \.self) { e in
                        Button { emoji = e } label: {
                            Text(e).font(.title)
                                .frame(width: 48, height: 48)
                                .background(emoji == e ? Theme.accent.opacity(0.3) : Theme.raised, in: .rect(cornerRadius: Theme.radiusM))
                        }
                        .buttonStyle(GMPress())
                    }
                }
            }
            GMSection("Capa") {
                PhotosPicker(selection: $coverPick, matching: .images) {
                    ZStack {
                        if let cover, let img = UIImage(data: cover) {
                            Color.clear.overlay { Image(uiImage: img).resizable().scaledToFill().allowsHitTesting(false) }
                        } else {
                            Theme.raised
                            Label("Escolher foto de capa", systemImage: "photo").font(.subheadline.weight(.semibold))
                        }
                    }
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
                    .clipShape(.rect(cornerRadius: Theme.radiusM))
                    .foregroundStyle(.white)
                }
                .buttonStyle(GMPress())
                .onChange(of: coverPick) { _, item in
                    Task { if let data = try? await item?.loadTransferable(type: Data.self) { cover = compressedPhoto(data) } }
                }
                if cover != nil {
                    GMButton("Tirar capa", kind: .secondary, small: true) { cover = nil; coverPick = nil }
                }
            }
            if parentClub == nil {
                GMSection("Tipo", footer: format.detail) {
                    GMSegmented(options: LeagueFormat.allCases.map { ($0, $0.name) }, selection: $format)
                }
            }
            GMSection("Quem vê os posts", footer: settings.isPrivate
                      ? "Os posts ficam só aqui dentro: não aparecem no Feed nem nos stories de ninguém, nem dos seus amigos."
                      : "Os posts também aparecem no Feed dos amigos de quem postou, mesmo de quem não está na liga.") {
                GMSegmented(options: [(false, "Pública"), (true, "Privada")], selection: $settings.isPrivate)
            }
            if format == .challenge {
                GMSection("Período", footer: "Ganha quem estiver na frente no último dia. Check-ins fora do período não contam.") {
                    // Não deixa começar no passado; ao editar, mantém o início que a liga já tinha
                    LeaguePeriodField(start: $start, end: $end, hasEnd: $hasEnd,
                                      minDate: min(cal.startOfDay(for: .now), league.map { cal.startOfDay(for: $0.start) } ?? .distantFuture),
                                      allowsOpenEnded: false)
                }
                GMSection(footer: "Quando acabar, começa outra temporada com o mesmo nome, pessoas e duração, e os check-ins zeram. As temporadas passadas ficam guardadas na liga, com o campeão de cada uma.") {
                    GMToggle(title: "Renovar automaticamente", subtitle: "Nova temporada ao fim de cada período", isOn: $autoRenew)
                }
            }
            GMSection("Pontuação", footer: scoring.detail) {
                GMChoiceChips(options: LeagueScoring.allCases.map { ($0, $0.name) }, selection: $scoring)
            }
            if scoring == .atividades {
                LeaguePointsSection(rules: $settings.pointRules)
            }
            GMSection("Treinos que valem", footer: activityRule.detail) {
                GMSegmented(options: LeagueActivityRuleMode.allCases.map { ($0, $0.name) }, selection: $activityRuleMode)
                if activityRuleMode != .all {
                    GMDivider()
                    GMRow(icon: "checklist", iconTint: Theme.accent, title: activitySelectionTitle,
                          subtitle: activitySelectionNames, chevron: true) {
                        choosingWorkoutTypes = true
                    }
                }
            }
            if scoring == .pontos {
                GMSection("Peso por atributo", footer: weightsFooter) {
                    ForEach(Attribute.allCases) { a in
                        HStack(spacing: 10) {
                            Image(systemName: a.symbol).foregroundStyle(a.color).frame(width: 22)
                            GMStepper(title: a.name, value: Binding(get: { halves[a] ?? 2 }, set: { halves[a] = $0 }), range: 0...6,
                                      format: { weightText(Double($0) / 2) })
                        }
                        if a != Attribute.allCases.last { GMDivider() }
                    }
                }
            }
            GMSection("Desempate", footer: tieBreak.detail) {
                GMSegmented(options: LeagueTieBreak.allCases.map { ($0, $0.name) }, selection: $tieBreak)
            }
            GMSection("Foto do treino", footer: photoRule == .metade && scoring == .treinos
                      ? photoRule.detail + " No modo Treinos cada check-in vale 1 e a metade arredonda para cima: para cobrar a foto, use Obrigatória."
                      : photoRule.detail) {
                GMSegmented(options: PhotoRule.allCases.map { ($0, $0.name) }, selection: $photoRule)
            }
            LeagueVerificationSection(settings: $settings)
            LeagueProofSection(settings: $settings)
            if ProStore.shared.allows(.scoringLimits) {
                LeagueLimitsSection(limits: $settings.limits, scoring: scoring, hasTeams: !teams.isEmpty)
            } else {
                ProLockedRow(feature: .scoringLimits)
            }
            LeagueGoalsSection(settings: $settings, scoring: scoring, hasTeams: !teams.isEmpty)
            GMSection("Entrada", footer: "Com aprovação, quem entra pelo código ou pelo link manda um pedido e você aprova ou ignora.") {
                GMToggle(title: "Novos membros precisam de aprovação", isOn: $settings.requiresApproval)
            }
            if let league {
                LeagueBannedSection(settings: $settings,
                                    names: Dictionary((LeagueRemoteStore.shared.cache[league.key]?.members ?? []).map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a }))
            }
            GMSection("Rodada suíça", footer: "Todo dia cada pessoa enfrenta alguém com pontuação suíça parecida. " + swiss.detail) {
                GMChoiceChips(options: SwissCriterion.allCases.map { ($0, $0.name) }, selection: $swiss)
            }
            GMSection("Times", footer: teams.isEmpty ? "Divida a liga em times: o placar do time é a soma dos membros, e cada time tem um bro que evolui junto." : "O placar do time é a soma dos membros. Cada pessoa escolhe o time no Ranking da liga e pode trocar depois. Renomear um time não tira ninguém dele.") {
                GMToggle(title: "Competir em times", isOn: Binding(get: { !teams.isEmpty }, set: { teams = $0 ? [LeagueTeam(name: "Time Verde"), LeagueTeam(name: "Time Roxo")] : [] }))
                ForEach(teams) { t in
                    GMDivider()
                    HStack(spacing: 8) {
                        GMTextField(placeholder: "Nome do time", text: Binding(
                            get: { teams.first { $0.id == t.id }?.name ?? "" },
                            set: { v in if let i = teams.firstIndex(where: { $0.id == t.id }) { teams[i].name = v } }))
                        if teams.count > 2 {
                            GMIconButton(icon: "minus", label: "Remover time") { teams.removeAll { $0.id == t.id } }
                        }
                    }
                }
                if !teams.isEmpty && teams.count < 4 {
                    GMDivider()
                    GMRow(icon: "plus.circle", iconTint: Theme.accent, title: "Adicionar time") { teams.append(LeagueTeam(name: "Time \(teams.count + 1)")) }
                }
            }
            if league == nil {
                MonsterChoiceSection(choice: $rep)
            }
            if league == nil && parentClub == nil {
                GMSection(footer: "Enquanto não há servidor, os convites não chegam em outras pessoas. Ative para ver a liga com participantes simulados.") {
                    GMToggle(title: "Participantes de exemplo", isOn: $withExamples)
                }
            }
        }
        .onChange(of: name + teams.map(\.name).joined()) { blocked = false }
        .onChange(of: format) { _, value in
            hasEnd = value == .challenge
            if value == .club { autoRenew = false }
        }
        .gmSheet(isPresented: $choosingWorkoutTypes) { close in
            LeagueWorkoutTypePicker(selection: $selectedWorkoutTypes, mode: activityRuleMode, close: close)
        }
        .onAppear {
            if !loaded, league == nil, let club = parentClub {
                loaded = true
                format = .challenge
                emoji = club.emoji
                scoring = club.scoring
                teams = club.teams
                var s = club.settings
                s.parentClub = club.seriesKey
                s.dailyWorkout = nil
                settings = s
                withExamples = club.isMock
                return
            }
            guard !loaded, let l = league else { return }
            loaded = true
            name = l.name
            emoji = l.emoji
            scoring = l.scoring
            format = l.format
            activityRuleMode = l.activityRule.mode
            selectedWorkoutTypes = l.activityRule.workoutTypeIDs
            tieBreak = l.tieBreak
            photoRule = l.photoRule
            swiss = l.swiss
            teams = l.teams
            settings = l.settings
            for (a, v) in l.attributeWeights { halves[a] = Int((v * 2).rounded()) }
            start = l.start
            hasEnd = l.end != nil
            autoRenew = l.autoRenew
            if let e = l.end { end = cal.startOfDay(for: e) }
            cover = l.cover
        }
    }

    private func save() {
        let access = AccessStore.shared
        guard league.map({ access.can(.leaguesUpdate, on: $0) }) ?? access.can(.leaguesCreate) else { return dismiss() }
        guard ContentFilter.allows(name) && teams.allSatisfy({ ContentFilter.allows($0.name) }) else { blocked = true; return }
        let l = league ?? League(name: "", emoji: emoji, scoring: scoring, isMock: withExamples)
        l.name = name.trimmingCharacters(in: .whitespaces)
        l.emoji = emoji
        l.scoringRaw = scoring.rawValue
        l.activityRule = activityRule
        l.attributeWeights = halves.mapValues { Double($0) / 2 }
        l.tieBreak = tieBreak
        l.photoRule = photoRule
        l.swiss = swiss
        l.settings = settings
        // Time sem nome sai da lista (quem estava nele fica sem time)
        l.teams = teams
        l.cover = cover
        l.setPeriod(start: start, end: format == .challenge ? end : nil)
        l.autoRenew = format == .challenge && autoRenew
        if league == nil {
            l.monsterUUID = context.representative(rep)
            context.insert(l)
        }
        l.syncedAt = nil
        try? context.save()
        LeagueRemoteStore.shared.scheduleFlush()
        dismiss()
    }
}

/// Escolha dos treinos da regra "Somente estes" / "Todos, exceto:": grade por seção, com busca e os escolhidos no topo
struct LeagueWorkoutTypePicker: View {
    @Binding var selection: Set<UInt>
    var mode: LeagueActivityRuleMode = .only
    /// Título no topo; sem ele, vem da regra
    var title: String?
    let close: () -> Void
    @State private var query = ""

    private var types: [WorkoutType] { WorkoutType.search(query) }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
    /// Na exclusão, o escolhido sai do ranking: o destaque fica vermelho
    private var tint: Color { mode == .except ? Theme.danger : Theme.accent }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title ?? (mode == .except ? "Não valem pontos" : "Valem pontos")).font(.title3.bold())
                    Text(countText).font(.subheadline).foregroundStyle(Theme.dim).contentTransition(.numericText())
                }
                Spacer()
                GMButton("Pronto", full: false, small: true, action: close)
            }
            search
            if !selection.isEmpty { chosenStrip }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(WorkoutType.Section.allCases, id: \.self) { section in
                        let items = types.filter { $0.section == section }
                        if !items.isEmpty { sectionView(section, items) }
                    }
                }
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .overlay {
                if types.isEmpty { ContentUnavailableView.search(text: query) }
            }
        }
        .frame(height: UIScreen.main.bounds.height * 0.78)
        .animation(.snappy(duration: 0.25), value: selection)
    }

    private var countText: String {
        switch selection.count {
        case 0: "Nenhum escolhido"
        case 1: "1 escolhido"
        case let n: "\(n) escolhidos"
        }
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.dim)
            TextField("", text: $query, prompt: Text("Buscar treino").foregroundStyle(Theme.dim))
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.dim) }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Theme.raised, in: .capsule)
    }

    /// Escolhidos, na ordem do catálogo; tocar tira
    private var chosenStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(WorkoutType.all.filter { selection.contains($0.id) }) { t in
                    Button { toggle(t.id) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: t.symbol)
                            Text(t.name).lineLimit(1)
                            Image(systemName: "xmark").font(.caption2.bold()).opacity(0.6)
                        }
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(tint.opacity(0.18), in: .capsule)
                        .foregroundStyle(tint)
                    }
                    .buttonStyle(GMPress())
                    .accessibilityLabel("Tirar \(t.name)")
                }
                Button("Limpar") { selection.removeAll() }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.dim)
                    .padding(.horizontal, 8)
            }
        }
        .scrollClipDisabled()
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func sectionView(_ section: WorkoutType.Section, _ items: [WorkoutType]) -> some View {
        let on = items.filter { selection.contains($0.id) }.count
        let all = on == items.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(section.rawValue).font(.subheadline.weight(.semibold))
                if on > 0 { Text("\(on)").font(.caption.bold()).foregroundStyle(tint).monospacedDigit() }
                Spacer()
                Button(all ? "Tirar todos" : "Marcar todos") {
                    UISelectionFeedbackGenerator().selectionChanged()
                    if all { selection.subtract(items.map(\.id)) } else { selection.formUnion(items.map(\.id)) }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.dim)
            }
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(items) { tile($0) }
            }
        }
    }

    private func tile(_ t: WorkoutType) -> some View {
        let on = selection.contains(t.id)
        return Button { toggle(t.id) } label: {
            VStack(spacing: 6) {
                Image(systemName: t.symbol).font(.title3).frame(height: 26)
                Text(t.name).font(.caption.weight(.semibold)).lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 78)
            .background(on ? tint.opacity(0.18) : Theme.raised, in: .rect(cornerRadius: Theme.radiusM))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusM).stroke(on ? tint : .clear, lineWidth: 1.5))
            .overlay(alignment: .topTrailing) {
                if on {
                    Image(systemName: mode == .except ? "minus.circle.fill" : "checkmark.circle.fill")
                        .font(.footnote).foregroundStyle(tint).padding(6)
                }
            }
            .foregroundStyle(on ? tint : .white)
        }
        .buttonStyle(GMPress())
        .accessibilityLabel(t.name)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func toggle(_ id: UInt) {
        UISelectionFeedbackGenerator().selectionChanged()
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }
}

struct JoinLeagueView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var leagues: [League]
    @State private var code: String
    @State private var message: String?
    @State private var rep: UUID? = MainMonster.id
    /// Achada pelo código: mostra a prévia antes de entrar
    @State private var found: LeagueDraft?

    init(code: String = "") { _code = State(initialValue: code) }

    private var needsApproval: Bool { found.map { LeagueSettings(rawValue: $0.settings ?? "").requiresApproval } ?? false }

    var body: some View {
        GMModal("Entrar numa liga", confirm: found == nil ? "Procurar" : needsApproval ? "Pedir para entrar" : "Entrar",
                confirmEnabled: code.trimmingCharacters(in: .whitespaces).count >= 6, onConfirm: found == nil ? look : join) {
            GMSection("Código", footer: message ?? "Peça o código para quem criou a liga. Para testar, use \(MockLeague.code).") {
                GMTextField(placeholder: "Código da liga", text: $code, capitalization: .characters)
                    .font(.title3.monospaced())
                    .autocorrectionDisabled()
            }
            if let found {
                LeaguePreviewCard(draft: found)
                MonsterChoiceSection(choice: $rep)
            }
        }
        .onChange(of: code) { found = nil; message = nil }
        .task { if code.count >= 6 { look() } }
    }

    private var cleanCode: String { code.trimmingCharacters(in: .whitespaces).uppercased() }

    /// Acha a liga e mostra a prévia (tipo, pontuação, regras, se precisa de aprovação)
    private func look() {
        let c = cleanCode
        if leagues.contains(where: { $0.code == c }) {
            message = "Você já está nessa liga."
        } else if c == MockLeague.code {
            found = MockLeague.make().draft
        } else if PendingJoins.all().contains(where: { $0.code == c }) {
            message = "Você já pediu para entrar. Espere o dono aprovar."
        } else {
            message = "Procurando…"
            Task {
                do {
                    guard let d = try await LeagueRemoteStore.shared.join(code: c) else {
                        message = Backend.mode == .mock ? "Liga não encontrada. Sem servidor, só a liga de exemplo (\(MockLeague.code)) existe."
                                                        : "Liga não encontrada. Confira o código."
                        return
                    }
                    let banned = LeagueSettings(rawValue: d.settings ?? "").banned.contains(LeagueBoard.selfID)
                    message = banned ? "Você foi banido desta liga." : nil
                    found = banned ? nil : d
                } catch {
                    message = "Não deu para procurar agora: \(error.localizedDescription)"
                }
            }
        }
    }

    private func join() {
        guard let d = found else { return }
        if d.code == MockLeague.code {
            let l = MockLeague.make()
            l.monsterUUID = context.representative(rep)
            context.insert(l)
            try? context.save()
            return dismiss()
        }
        if needsApproval {
            // O pedido vai para o dono; a liga entra no aparelho quando ele aceitar
            let name = ContentFilter.publishable(UserDefaults.standard.string(forKey: "trainerName") ?? "")
            let monster = rep
            Task {
                do {
                    try await LeagueRemoteStore.shared.backend.requestJoin(code: d.code, membership: Membership(name: name, formID: MonsterForm.egg.id, teamID: nil))
                    PendingJoins.add(PendingJoin(code: d.code, name: d.name, emoji: d.emoji, date: .now, monsterUUID: monster))
                    dismiss()
                } catch {
                    message = "Não deu para mandar o pedido: \(error.localizedDescription)"
                }
            }
            return
        }
        let l = League(draft: d)
        l.monsterUUID = context.representative(rep)
        context.insert(l)
        try? context.save()
        LeagueRemoteStore.shared.scheduleFlush()
        dismiss()
    }
}

// MARK: - Check-in

/// Publica a mesma atividade em uma ou mais ligas. Sem termos aceitos e permissão nada é publicado (nem depois de sair
/// da conta, quando a sessão acabou), nem texto barrado pelo filtro. `signedIn` substitui essa checagem (testes).
@MainActor
func postCheckIns(activity: Activity, leagues: Set<UUID>, title: String, note: String, photo: Data?, context: ModelContext,
                  signedIn: Bool? = nil, grouped: [Activity] = [], extraPhotos: [Data] = []) {
    guard signedIn ?? Terms.canPublish, ContentFilter.allows(title, note) else { return }
    var subject = PostSubject(activity: activity)
    subject.photo = PhotoProofs.proof(for: photo)
    let configured = (try? context.fetch(FetchDescriptor<League>())) ?? []
    for id in leagues {
        let league = configured.first { $0.uuid == id }
        // Não posta onde as regras da liga barram (a tela já mostra o motivo e desmarca)
        if let league, !league.problems(subject).isEmpty { continue }
        let c = LeagueCheckIn(leagueUUID: id, activityUUID: activity.uuid,
                              title: title.isEmpty ? activity.typeName : title, note: note, date: activity.date, photo: photo)
        c.place = subject.place
        var proof = CheckInProof(subject: subject, league: league, pose: PhotoProofs.pose(for: photo), device: activity.source)
        // Outras atividades do mesmo dia no mesmo check-in
        let sameDay = grouped.filter { $0.uuid != activity.uuid && League.rulesCalendar.isDate($0.date, inSameDayAs: activity.date) }
        proof.grouped = sameDay.map(\.uuid)
        proof.groupedParts = sameDay.map(\.scorePart)
        c.proof = proof
        if photo != nil && !extraPhotos.isEmpty { c.photos = [photo!] + extraPhotos }
        if let league { c.reviewRaw = league.needsReview(fromMe: true) ? ReviewState.pending : "" }
        context.insert(c)
    }
    LeagueRemoteStore.shared.scheduleFlush()
}

/// Deixa os check-ins da atividade exatamente nos destinos escolhidos, com o mesmo post em todos.
/// Sem termos aceitos e permissão (ou sem sessão) os posts ficam como estão: nem republica nem apaga.
/// Texto barrado pelo filtro só impede publicar e republicar; tirar destinos apaga sempre.
@MainActor
func syncCheckIns(activity: Activity, destinations: Set<UUID>, title: String, note: String, photo: Data?, place: String?, context: ModelContext,
                  signedIn: Bool? = nil) {
    guard signedIn ?? Terms.canPublish else { return }
    let id = activity.uuid
    var subject = PostSubject(activity: activity)
    subject.place = place
    subject.photo = PhotoProofs.proof(for: photo)
    let configured = (try? context.fetch(FetchDescriptor<League>())) ?? []
    let eligibleDestinations = destinations.filter { destination in
        configured.first(where: { $0.uuid == destination }).map { $0.problems(subject).isEmpty } ?? true
    }
    let existing = (try? context.fetch(FetchDescriptor<LeagueCheckIn>(predicate: #Predicate { $0.activityUUID == id }))) ?? []
    let t = title.trimmingCharacters(in: .whitespaces).isEmpty ? activity.typeName : title.trimmingCharacters(in: .whitespaces)
    for c in existing where !eligibleDestinations.contains(c.leagueUUID) {
        LeagueOutbox.retract(c)
        context.delete(c)
    }
    guard ContentFilter.allows(title, note) else { return LeagueRemoteStore.shared.scheduleFlush() }
    let kept = Set(existing.filter { eligibleDestinations.contains($0.leagueUUID) }.map(\.leagueUUID))
    for c in existing where eligibleDestinations.contains(c.leagueUUID) {
        c.title = t
        c.note = note
        // Foto trocada: nova prova (a mesma foto continua com a prova de antes)
        if photo != c.photo { c.proof = CheckInProof(subject: subject, league: configured.first { $0.uuid == c.leagueUUID },
                                                     pose: PhotoProofs.pose(for: photo), device: activity.source) }
        c.setPhoto(photo)
        c.place = place
        c.date = activity.date
        // Editado: publica de novo
        c.syncedAt = nil
    }
    for d in eligibleDestinations.subtracting(kept) {
        let league = configured.first { $0.uuid == d }
        let c = LeagueCheckIn(leagueUUID: d, activityUUID: id, title: t, note: note, date: activity.date, photo: photo)
        c.place = place
        c.proof = CheckInProof(subject: subject, league: league, pose: PhotoProofs.pose(for: photo), device: activity.source)
        if let league { c.reviewRaw = league.needsReview(fromMe: true) ? ReviewState.pending : "" }
        context.insert(c)
    }
    LeagueRemoteStore.shared.scheduleFlush()
}

/// Reduz a foto para algo razoável de guardar
func compressedPhoto(_ data: Data) -> Data? {
    guard let img = UIImage(data: data) else { return nil }
    let maxSide: CGFloat = 1280
    let scale = min(1, maxSide / max(img.size.width, img.size.height))
    let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
    let resized = UIGraphicsImageRenderer(size: size).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
    return resized.jpegData(compressionQuality: 0.7)
}

/// Toda atividade vai para pelo menos um lugar (perfil ou liga) quando a conta pode postar: é lá que a foto e o post
/// moram. Sem conta que posta (termos não aceitos, sem permissão), salvar continua liberado e fica só no histórico.
@MainActor
func hasPostDestination(_ selected: Set<UUID>) -> Bool { !Terms.canPublish || !selected.isEmpty }

/// Seção reaproveitada no registro de atividade, no fim do treino e na edição: onde postar o check-in e a foto
struct LeaguePostSection: View {
    @Binding var selected: Set<UUID>
    @Binding var photo: Data?
    /// Fotos além da primeira (até 4); quem não passa fica com uma foto só
    var extras: Binding<[Data]>? = nil
    /// Marca perfil e todas as ligas por padrão (registro de atividade e fim de treino)
    var selectAllByDefault = true
    /// Atividade importada do Apple Saúde: avisa o que vai no post
    var fromHealth = false
    /// O treino postado: liga que não aceita o tipo dele ou cujas regras de verificação ele não cumpre aparece bloqueada, com o motivo
    var subject: PostSubject? = nil
    @Query(sort: \League.joinedAt) private var allLeagues: [League]
    @State private var pick: PhotosPickerItem?
    @State private var extraPicks: [PhotosPickerItem] = []
    @State private var shooting = false
    @State private var shootingExtra = false
    @AppStorage(Terms.acceptedKey) private var acceptedTerms = 0
    @State private var terms = TermsGate()

    /// Ligas em andamento, mais as encerradas ou futuras em que já está postado (para poder tirar).
    /// Liga que ainda não começou não aceita check-in: ficaria fora do período e não contaria.
    private var signedIn: Bool { AuthStore.shared.isSignedIn && acceptedTerms >= Terms.version && AccessStore.shared.can(.checkInsPublish) }
    private var leagues: [League] {
        guard signedIn else { return [] }
        return allLeagues.filter { ($0.hasStarted && !$0.isOver) || selected.contains($0.uuid) }
    }
    private var everything: Set<UUID> {
        guard signedIn else { return [] }
        return Set(leagues.filter { !$0.isOver && $0.hasStarted && accepts($0) }.map(\.uuid)).union([ProfileFeed.id])
    }

    /// O treino com a foto que está no formulário agora
    private var current: PostSubject? {
        guard var s = subject else { return nil }
        s.photo = PhotoProofs.proof(for: photo)
        // Visita na academia registrada pela localização durante o treino
        if s.gymVisit == nil { s.gymVisit = GymLocation.shared.visit(from: s.date, minutes: s.minutes)?.gymName }
        return s
    }

    private func problems(_ l: League) -> [VerificationProblem] { current.map { l.problems($0) } ?? [] }
    private func accepts(_ l: League) -> Bool { problems(l).isEmpty }

    /// Pose do dia, quando alguma liga marcada cobra
    private var pose: DailyPose? {
        leagues.contains { selected.contains($0.uuid) && $0.settings.posesEnabled } ? DailyPose.today : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if signedIn {
                GMSection("Postar em", footer: selected.isEmpty ? "Escolha pelo menos um lugar para salvar." : postFooter,
                          trailing: AnyView(allButton)) {
                    destination(id: ProfileFeed.id, title: "Meu perfil", subtitle: "Aparece no seu perfil público") { Avatar(size: 38) }
                    ForEach(leagues) { l in
                        GMDivider()
                        destination(id: l.uuid, title: l.name, subtitle: leagueSubtitle(l), enabled: accepts(l)) {
                            Text(l.emoji).font(.title3).frame(width: 38, height: 38).background(Theme.raised, in: .circle)
                        }
                    }
                }
            } else if AuthStore.shared.isSignedIn && acceptedTerms >= Terms.version {
                GMSection("Postar em") {
                    Text(AccessStore.shared.isLoading ? "Conferindo sua conta…" : "Sua conta não pode postar agora. A atividade fica só no seu histórico.")
                        .font(.footnote)
                        .foregroundStyle(Theme.dim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                GMSection("Postar em") {
                    Text("Para postar no perfil e nas ligas, aceite os termos de uso. Sem isso, a atividade fica só no seu histórico.")
                        .font(.footnote)
                        .foregroundStyle(Theme.dim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    GMButton("Ler e aceitar os termos", icon: "doc.text", kind: .secondary, small: true) {
                        terms.run { if selectAllByDefault && selected.isEmpty { selected = everything } }
                    }
                }
            }
            photoSection
        }
        .termsGate($terms)
        .onAppear {
            if selectAllByDefault && selected.isEmpty { selected = everything }
        }
        // Mudou o treino ou a foto: sai das ligas em que ele não vale mais
        .onChange(of: blockedIDs) { _, blocked in selected.subtract(blocked) }
        .onChange(of: pick) { _, item in
            Task {
                guard let data = try? await item?.loadTransferable(type: Data.self), let small = compressedPhoto(data) else { return }
                // A hora e o local da foto saem do arquivo original: a versão reduzida não tem EXIF
                PhotoProofs.register(small, proof: PhotoProof.library(data))
                photo = small
            }
        }
        .gmModal(isPresented: $shooting) {
            CheckInCamera(pose: pose) { data in
                guard let small = compressedPhoto(data) else { return }
                PhotoProofs.register(small, proof: PhotoProof(source: .camera, takenAt: .now), pose: pose?.id)
                photo = small
            }
        }
        .gmModal(isPresented: $shootingExtra) {
            CheckInCamera(pose: pose) { data in
                if let small = compressedPhoto(data), extras?.wrappedValue.count ?? 4 < 4 { extras?.wrappedValue.append(small) }
            }
        }
        .onChange(of: extraPicks) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self), let small = compressedPhoto(data),
                       extras?.wrappedValue.count ?? 4 < 4 { extras?.wrappedValue.append(small) }
                }
                extraPicks = []
            }
        }
    }

    private var blockedIDs: Set<UUID> { Set(leagues.filter { !accepts($0) }.map(\.uuid)) }

    /// Aviso quando falta a foto em liga que cobra
    private var postFooter: String? {
        let health = fromHealth ? "Do Apple Saúde, o post leva só tipo, data e duração." : nil
        let text = [health, photoWarning].compactMap { $0 }.joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    private var photoWarning: String? {
        guard photo == nil else { return nil }
        let strict = leagues.filter { selected.contains($0.uuid) && $0.photoRule != .livre }
        guard !strict.isEmpty else { return nil }
        let zero = strict.filter { $0.photoRule == .obrigatoria }.map(\.name)
        let half = strict.filter { $0.photoRule == .metade }.map(\.name)
        let parts = (zero.isEmpty ? [] : ["não pontua em \(zero.joined(separator: ", "))"])
            + (half.isEmpty ? [] : ["vale metade em \(half.joined(separator: ", "))"])
        return "📷 Sem foto, o check-in " + parts.joined(separator: " e ") + "."
    }

    /// Marca tudo; se já está tudo marcado, desmarca
    private var allButton: some View {
        let all = everything.isSubset(of: selected)
        return Button(all ? "Desmarcar" : "Marcar todos") {
            if all { selected.removeAll() } else { selected.formUnion(everything) }
            UISelectionFeedbackGenerator().selectionChanged()
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(Theme.accent)
    }

    private func leagueSubtitle(_ l: League) -> String {
        if let p = problems(l).first {
            return p.fix == "escolha outro treino" ? p.message : "\(p.message) Para postar aqui: \(p.fix)."
        }
        if l.isOver { return "Encerrada" }
        if !l.hasStarted { return "Liga · \(League.startsText(l.start))" }
        let days = l.daysLeft.map { $0 == 1 ? "último dia" : "faltam \($0) dias" } ?? "sem fim"
        return "Liga · \(days)"
    }

    private func destination<Icon: View>(id: UUID, title: String, subtitle: String, enabled: Bool = true,
                                         @ViewBuilder icon: () -> Icon) -> some View {
        let on = enabled && selected.contains(id)
        return Button { toggle(id) } label: {
            HStack(spacing: 12) {
                icon()
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(subtitle).font(.caption).foregroundStyle(Theme.dim)
                }
                Spacer()
                Image(systemName: enabled ? (on ? "checkmark.circle.fill" : "circle") : "nosign")
                    .font(.system(size: 24))
                    .foregroundStyle(on ? Theme.accent : Theme.dim)
            }
            .contentShape(Rectangle())
            .foregroundStyle(.white)
            .opacity(enabled ? 1 : 0.5)
        }
        .buttonStyle(GMPress())
        .disabled(!enabled)
    }

    @ViewBuilder
    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FOTO").font(.caption.weight(.bold)).foregroundStyle(Theme.dim).tracking(0.6).padding(.horizontal, 4)
            if let pose {
                HStack(spacing: 10) {
                    Text(pose.emoji).font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pose do dia: \(pose.name)").font(.subheadline.weight(.semibold))
                        Text("Sem a pose do dia na foto, o check-in não pontua.").font(.caption).foregroundStyle(Theme.dim)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: .rect(cornerRadius: Theme.radius))
            }
            if let photo, let img = UIImage(data: photo) {
                PhotosPicker(selection: $pick, matching: .images) {
                    // Foto em retrato transborda o quadro: sem isso, a parte cortada ainda pega os toques das linhas de cima
                    Color.clear
                        .frame(height: 200)
                        .overlay { Image(uiImage: img).resizable().scaledToFill().allowsHitTesting(false) }
                        .clipShape(.rect(cornerRadius: Theme.radius))
                        .contentShape(.rect(cornerRadius: Theme.radius))
                        .overlay(alignment: .bottomLeading) {
                            Label("Trocar", systemImage: "arrow.triangle.2.circlepath")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(.black.opacity(0.6), in: .capsule)
                                .foregroundStyle(.white)
                                .padding(10)
                        }
                }
                .buttonStyle(GMPress())
                .overlay(alignment: .bottomTrailing) {
                    if let label = PhotoProofs.proof(for: photo)?.label {
                        Text(label).font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(.black.opacity(0.6), in: .capsule)
                            .foregroundStyle(.white)
                            .padding(10)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    Button {
                        // Tirou a principal: a próxima extra sobe
                        if var e = extras?.wrappedValue, !e.isEmpty { self.photo = e.removeFirst(); extras?.wrappedValue = e } else { self.photo = nil }
                        pick = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .frame(width: 30, height: 30)
                            .background(.black.opacity(0.6), in: .circle)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(GMPress())
                    .padding(10)
                }
                if let extras { extraStrip(extras) }
            } else {
                HStack(spacing: 10) {
                    Button { shooting = true } label: { photoTile(icon: "camera.fill", title: "Tirar foto") }
                        .buttonStyle(GMPress())
                    PhotosPicker(selection: $pick, matching: .images) { photoTile(icon: "photo.on.rectangle", title: "Da galeria") }
                        .buttonStyle(GMPress())
                }
            }
        }
    }

    /// Até 4 fotos a mais: miniaturas com X e os botões de câmera e galeria
    private func extraStrip(_ extras: Binding<[Data]>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(extras.wrappedValue.enumerated()), id: \.offset) { i, data in
                    Color.clear.frame(width: 72, height: 72)
                        .overlay { if let img = UIImage(data: data) { Image(uiImage: img).resizable().scaledToFill() } }
                        .clipShape(.rect(cornerRadius: Theme.radiusM))
                        .overlay(alignment: .topTrailing) {
                            Button { extras.wrappedValue.remove(at: i) } label: {
                                Image(systemName: "xmark").font(.caption2.bold()).frame(width: 22, height: 22)
                                    .background(.black.opacity(0.6), in: .circle).foregroundStyle(.white)
                            }
                            .buttonStyle(GMPress())
                            .padding(3)
                            .accessibilityLabel("Tirar foto \(i + 2)")
                        }
                }
                if extras.wrappedValue.count < 4 {
                    Button { shootingExtra = true } label: { miniTile("camera.fill") }.buttonStyle(GMPress()).accessibilityLabel("Tirar mais uma foto")
                    PhotosPicker(selection: $extraPicks, maxSelectionCount: 4 - extras.wrappedValue.count, matching: .images) { miniTile("plus") }
                        .buttonStyle(GMPress())
                        .accessibilityLabel("Mais fotos da galeria")
                }
            }
        }
    }

    private func miniTile(_ icon: String) -> some View {
        Image(systemName: icon).font(.title3)
            .frame(width: 72, height: 72)
            .foregroundStyle(Theme.dim)
            .background(Theme.card, in: .rect(cornerRadius: Theme.radiusM))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusM).strokeBorder(Theme.dim.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
    }

    private func photoTile(icon: String, title: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title2)
            Text(title).font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, minHeight: 110)
        .foregroundStyle(Theme.dim)
        .background(Theme.card, in: .rect(cornerRadius: Theme.radius))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.dim.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
    }

    private func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

struct CheckInForm: View {
    let preselected: Set<UUID>
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Activity.date, order: .reverse) private var activities: [Activity]
    @Query private var checkIns: [LeagueCheckIn]

    @State private var useExisting = false
    @State private var existing: UUID?
    /// Outras atividades do mesmo dia que vão juntas no check-in
    @State private var extras: Set<UUID> = []
    @State private var kind: ActivityKind = .musculacao
    @State private var type = WorkoutType.of(.musculacao).id
    @State private var minutes = 60
    @State private var effort = 6
    @State private var date = Date.now
    @State private var title = ""
    @State private var note = ""
    @State private var leagues: Set<UUID>
    @State private var photo: Data?
    @State private var extraPhotos: [Data] = []
    @State private var blocked = false
    @State private var terms = TermsGate()

    init(preselected: Set<UUID>) {
        self.preselected = preselected
        _leagues = State(initialValue: preselected)
    }

    private var recent: [Activity] {
        let since = Date.now.addingTimeInterval(-7 * 86400)
        return activities.filter { $0.date >= since }
    }

    var body: some View {
        GMModal("Check-in", confirm: "Postar", confirmEnabled: !leagues.isEmpty && !(useExisting && existing == nil), onConfirm: confirm) {
            GMSegmented(options: [(false, "Nova atividade"), (true, "Já registrada")], selection: $useExisting)
            if useExisting {
                GMSection("Atividades recentes", footer: "Treinos guiados e os importados do Apple Saúde aparecem aqui. Atividades do mesmo dia podem ir juntas num check-in só: toque em mais de uma.") {
                    if recent.isEmpty { Text("Nada registrado nos últimos 7 dias.").foregroundStyle(Theme.dim) }
                    ForEach(recent) { a in
                        let posted = checkIns.contains { $0.activityUUID == a.uuid && leagues.contains($0.leagueUUID) }
                        let on = existing == a.uuid || extras.contains(a.uuid)
                        GMRow(icon: a.typeSymbol, title: a.typeName,
                              subtitle: "\(durationText(a.minutes)) · \(a.date.formatted(.dateTime.weekday().day().hour().minute()))",
                              action: { pickActivity(a) }) {
                            if posted { Text("já postada").font(.caption2).foregroundStyle(Theme.dim) }
                            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(on ? Theme.accent : Theme.dim)
                        }
                        if a.id != recent.last?.id { GMDivider() }
                    }
                }
            } else {
                GMSection("Atividade") { ActivityTypePicker(type: $type) }
                    .onChange(of: type) { _, t in kind = WorkoutType.byID(t)?.kind ?? .outro }
                GMSection {
                    GMStepper(title: "Duração", value: $minutes, range: 5...Game.maxMinutes, step: 5, format: durationText)
                    GMDivider()
                    GMEffortPicker(value: $effort)
                }
                GMSection("Quando") { GMDateTimePicker(date: $date) }
            }
            GMSection("Post") {
                GMTextField(placeholder: "Título (ex.: Dia de perna 🦵)", text: $title)
                GMTextField(placeholder: "Descrição (opcional)", text: $note, axis: .vertical)
                if blocked { ContentBlockedNote() }
            }
            LeaguePostSection(selected: $leagues, photo: $photo, extras: $extraPhotos, selectAllByDefault: false, subject: postedSubject)
        }
        .termsGate($terms)
        .onChange(of: title + note) { blocked = false }
    }

    /// Primeira atividade escolhida é a principal; outras do mesmo dia entram juntas; de outro dia, recomeça a escolha
    private func pickActivity(_ a: Activity) {
        UISelectionFeedbackGenerator().selectionChanged()
        guard let id = existing, let first = activities.first(where: { $0.uuid == id }) else { existing = a.uuid; extras = []; return }
        if a.uuid == id {
            // Tirou a principal: a próxima agrupada vira a principal
            existing = extras.first
            if let e = existing { extras.remove(e) }
        } else if Calendar.current.isDate(a.date, inSameDayAs: first.date) {
            if extras.contains(a.uuid) { extras.remove(a.uuid) } else { extras.insert(a.uuid) }
        } else {
            existing = a.uuid
            extras = []
        }
    }

    /// O que vai ser postado: a atividade escolhida ou a nova
    private var postedSubject: PostSubject? {
        if useExisting { return existing.flatMap { id in activities.first { $0.uuid == id } }.map(PostSubject.init(activity:)) }
        return PostSubject(workoutTypeID: type, date: date, minutes: minutes, place: GymLocation.shared.placeNow)
    }

    private func confirm() {
        guard ContentFilter.allows(title, note) else { blocked = true; return }
        terms.run(post)
    }

    private func post() {
        let activity: Activity
        if useExisting, let id = existing, let a = activities.first(where: { $0.uuid == id }) {
            activity = a
        } else {
            activity = Activity(kind: kind, date: date, minutes: minutes, effort: effort, note: title)
            activity.healthType = Int(type)
            context.insert(activity)
            ActivitySplits.stamp(activity, context: context)
        }
        // Não posta duas vezes a mesma atividade na mesma liga
        let already = Set(checkIns.filter { $0.activityUUID == activity.uuid }.map(\.leagueUUID))
        let grouped = useExisting ? activities.filter { extras.contains($0.uuid) } : []
        postCheckIns(activity: activity, leagues: leagues.subtracting(already), title: title, note: note, photo: photo, context: context,
                     grouped: grouped, extraPhotos: extraPhotos)
        try? context.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
