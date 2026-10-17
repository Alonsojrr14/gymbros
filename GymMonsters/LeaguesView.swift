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

    var body: some View {
        let roster = Roster(monsters: monsters, activities: activities, checkIns: checkIns, leagues: allLeagues)
        NavigationStack {
            GMScreen("Ligas", avatar: true) {
                if leagues.isEmpty {
                    GMEmptyState(icon: "trophy", title: "Nenhuma liga", message: "Crie uma liga e chame os amigos, ou entre com um código.")
                }
                ForEach(leagues) { l in
                    NavigationLink { LeagueDetailView(league: l) } label: {
                        GMCard { LeagueRow(league: l, mine: checkIns.filter { $0.leagueUUID == l.uuid }, roster: roster, me: trainerName) }
                    }
                    .buttonStyle(GMPress())
                }
                GMSection(footer: "Cada liga é um ranking de check-ins, de qualquer atividade. Ao entrar, você escolhe quem te representa: um bro seu ou um ovo novo. Os check-ins da liga dão XP só para ele.") {
                    GMRow(icon: "plus.circle", iconTint: Theme.accent, title: "Criar liga", chevron: true) { creating = true }
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
            .gmModal(isPresented: $creating) { CreateLeagueView() }
            .gmModal(isPresented: $joining) { JoinLeagueView(code: joinCode) }
            .task {
                // Ligas de exemplo antigas não tinham data de fim
                for l in leagues where l.isMock && l.end == nil { l.setDuration(days: 30) }
                try? context.save()
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
                    if league.isMock { GMBadge(text: "exemplo", tint: .white) }
                }
                Text("\(pos)º de \(rank.count) · " + (league.isOver ? "encerrada" : league.daysLeft.map { $0 == 1 ? "último dia" : "faltam \($0) dias" } ?? league.scoring.name))
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
    @State private var weekOnly = false
    @State private var checkingIn = false
    @State private var menu = false
    @State private var editing = false
    @State private var leaving = false
    @State private var opened: FeedItem?

    var body: some View {
        let byID = Dictionary(activities.map { ($0.uuid, $0) }, uniquingKeysWith: { a, _ in a })
        let mine = allCheckIns.filter { $0.leagueUUID == league.uuid }
        // Dentro da liga você aparece com o bro que te representa nela
        let roster = Roster(monsters: monsters, activities: activities, checkIns: allCheckIns, leagues: leagues)
        let rep = roster.snapshot(league.monsterUUID)
        let avatar = rep.form
        let feed = LeagueBoard.feed(league: league, mine: mine, activities: byID, me: trainerName, myAvatar: avatar)
        let total = LeagueBoard.ranking(feed: feed, league: league, me: trainerName, myAvatar: avatar, since: nil)
        let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start
        let rank = weekOnly ? LeagueBoard.ranking(feed: feed, league: league, me: trainerName, myAvatar: avatar, since: weekStart) : total

        GMScreen(league.name, back: true, large: false, bottomInset: 170) {
            ShareLink(item: inviteText) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(Theme.raised, in: .circle)
                    .foregroundStyle(.white)
            }
            .buttonStyle(GMPress())
            GMIconButton(icon: "ellipsis") { menu = true }
        } content: {
            cover
            stats(total)
            GMSegmented(options: [(0, "Check-ins"), (1, "Ranking")], selection: $tab)
            if tab == 0 {
                timeline(feed)
            } else {
                GMCard { repCard(rep, monster: roster.monster(league.monsterUUID)) }
                GMSegmented(options: [(false, "Liga toda"), (true, "Esta semana")], selection: $weekOnly)
                GMSection(footer: league.scoring.detail) {
                    ForEach(Array(rank.enumerated()), id: \.element.id) { i, r in
                        rankRow(i + 1, r)
                        if i < rank.count - 1 { GMDivider() }
                    }
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !league.isOver {
                // Acima da barra de abas
                Button { checkingIn = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 26, weight: .bold))
                        .frame(width: 62, height: 62)
                        .background(Theme.accent, in: .circle)
                        .foregroundStyle(.black)
                        .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
                }
                .buttonStyle(GMPress())
                .padding(.trailing, 20)
                .padding(.bottom, 90)
            }
        }
        .gmModal(isPresented: $checkingIn) { CheckInForm(preselected: [league.uuid]) }
        .gmModal(isPresented: $editing) { CreateLeagueView(league: league) }
        .gmModal(item: $opened) { CheckInDetailView(item: $0) }
        .gmActions(isPresented: $menu, title: "\(league.emoji) \(league.name)", actions: [
            GMAction("Editar liga", icon: "pencil") { editing = true },
            GMAction("Sair da liga", icon: "rectangle.portrait.and.arrow.right", destructive: true) { leaving = true },
        ])
        .gmActions(isPresented: $leaving, title: "Sair de \(league.name)?",
                   message: "Os check-ins desta liga somem. Suas atividades e seus bros continuam.", actions: [
            GMAction("Sair", icon: "rectangle.portrait.and.arrow.right", destructive: true) {
                mine.forEach(context.delete)
                context.delete(league)
                try? context.save()
                dismiss()
            }
        ])
    }

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
                Color.clear.overlay { Image(uiImage: img).resizable().scaledToFill() }
            } else {
                LinearGradient(colors: [Theme.accent.opacity(0.55), Theme.card], startPoint: .topTrailing, endPoint: .bottomLeading)
                    .overlay(alignment: .topTrailing) {
                        Text(league.emoji).font(.system(size: 90)).rotationEffect(.degrees(12)).padding(.trailing, 18).padding(.top, 10)
                    }
            }
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if league.isMock { GMBadge(text: "exemplo", tint: .white) }
                    if league.isOver { GMBadge(text: "encerrada", tint: .white) }
                }
                Text("\(league.emoji) \(league.name)").font(.system(size: 26, weight: .heavy, design: .rounded)).lineLimit(2)
                Text("\(period) · código \(league.code)").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
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
                Text(league.isOver ? "Fim" : "Faltam").font(.caption.weight(.semibold)).foregroundStyle(Theme.dim)
                if league.isOver {
                    Text("🏁").font(.system(size: 38)).frame(height: 50)
                    Text("liga encerrada").font(.caption2).foregroundStyle(Theme.dim)
                } else if let d = league.daysLeft {
                    Text("\(d)").font(.system(size: 40, weight: .heavy, design: .rounded).monospacedDigit()).frame(height: 50)
                        .foregroundStyle(d <= 3 ? Theme.accent : .white)
                    Text(d == 1 ? "último dia" : "dias").font(.caption2).foregroundStyle(Theme.dim)
                } else {
                    Text("∞").font(.system(size: 40, weight: .heavy, design: .rounded)).frame(height: 50)
                    Text("sem data de fim").font(.caption2).foregroundStyle(Theme.dim)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 14)
        .background(Theme.card, in: .rect(cornerRadius: Theme.radius))
        .onTapGesture { withAnimation { tab = 1 } }
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

    private func scoreText(_ v: Int) -> String {
        switch league.scoring {
        case .pontos: "\(v) pts"
        case .treinos: "\(v) treino\(v == 1 ? "" : "s")"
        case .minutos: durationText(v)
        }
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
            let items = days[day]!.sorted { $0.date > $1.date }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(dayTitle(day)).font(.headline)
                    Spacer()
                    Text("\(items.count) check-in\(items.count == 1 ? "" : "s")").font(.caption).foregroundStyle(Theme.dim)
                }
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
                thumb(item).frame(width: 58, height: 58).clipShape(.rect(cornerRadius: 12))
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
                    Text("+\(item.score)").font(.subheadline.bold().monospacedDigit()).foregroundStyle(Theme.accent)
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
        } else {
            Image(systemName: item.kind.symbol)
                .font(.title2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(item.isMe ? Theme.accent.opacity(0.22) : Theme.raised)
                .foregroundStyle(item.isMe ? Theme.accent : .white)
        }
    }

    // MARK: Ranking

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

    private func rankRow(_ pos: Int, _ r: RankRow) -> some View {
        HStack(spacing: 12) {
            Text(pos <= 3 ? ["🥇", "🥈", "🥉"][pos - 1] : "\(pos)º")
                .font(pos <= 3 ? .title3 : .subheadline.bold())
                .frame(width: 32)
            MonsterSprite(form: r.avatar).frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.isMe ? "\(r.name) (você)" : r.name).font(.subheadline.weight(r.isMe ? .bold : .semibold))
                Text("\(r.checkIns) check-in\(r.checkIns == 1 ? "" : "s")").font(.caption).foregroundStyle(Theme.dim)
            }
            Spacer()
            Text("\(r.score)").font(.headline.monospacedDigit()).foregroundStyle(r.isMe ? Theme.accent : .white)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Criar, editar e entrar

/// Cria uma liga nova ou edita uma existente
struct CreateLeagueView: View {
    var league: League? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var emoji = "🏆"
    @State private var scoring: LeagueScoring = .pontos
    @State private var days = 30
    @State private var cover: Data?
    @State private var coverPick: PhotosPickerItem?
    @State private var withExamples = false
    @State private var rep: UUID? = MainMonster.id
    @State private var loaded = false

    private let emojis = ["🏆", "🔥", "💪", "🏃", "⚡️", "🦁", "🐉", "⭐️", "🏐", "🧘"]
    private let durations = [(7, "1 semana"), (14, "2 semanas"), (30, "30 dias"), (60, "60 dias"), (90, "90 dias"), (0, "Sem fim")]

    var body: some View {
        GMModal(league == nil ? "Nova liga" : "Editar liga", confirm: league == nil ? "Criar" : "Salvar",
                confirmEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty, onConfirm: save) {
            GMSection("Nome") {
                GMTextField(placeholder: "Nome da liga", text: $name)
                GMFlow {
                    ForEach(emojis, id: \.self) { e in
                        Button { emoji = e } label: {
                            Text(e).font(.title)
                                .frame(width: 48, height: 48)
                                .background(emoji == e ? Theme.accent.opacity(0.3) : Theme.raised, in: .rect(cornerRadius: 12))
                        }
                        .buttonStyle(GMPress())
                    }
                }
            }
            GMSection("Capa") {
                PhotosPicker(selection: $coverPick, matching: .images) {
                    ZStack {
                        if let cover, let img = UIImage(data: cover) {
                            Color.clear.overlay { Image(uiImage: img).resizable().scaledToFill() }
                        } else {
                            Theme.raised
                            Label("Escolher foto de capa", systemImage: "photo").font(.subheadline.weight(.semibold))
                        }
                    }
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
                    .clipShape(.rect(cornerRadius: 14))
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
            GMSection("Duração", footer: endText) {
                GMChoiceChips(options: durations, selection: $days)
            }
            GMSection("Pontuação", footer: scoring.detail) {
                GMSegmented(options: LeagueScoring.allCases.map { ($0, $0.name) }, selection: $scoring)
            }
            if league == nil {
                MonsterChoiceSection(choice: $rep)
                GMSection(footer: "Enquanto não há servidor, os convites não chegam em outras pessoas. Ative para ver a liga com participantes simulados.") {
                    GMToggle(title: "Participantes de exemplo", isOn: $withExamples)
                }
            }
        }
        .onAppear {
            guard !loaded, let l = league else { return }
            loaded = true
            name = l.name
            emoji = l.emoji
            scoring = l.scoring
            days = l.durationDays
            cover = l.cover
        }
    }

    private var endText: String {
        guard days > 0 else { return "A liga segue até alguém encerrar." }
        let start = league?.start ?? Calendar.current.startOfDay(for: .now)
        let end = Calendar.current.date(byAdding: .day, value: days - 1, to: start)!
        return "Começa em \(start.formatted(.dateTime.day().month(.abbreviated))) e termina em \(end.formatted(.dateTime.day().month(.abbreviated).year())). Ganha quem estiver na frente no último dia."
    }

    private func save() {
        let l = league ?? League(name: "", emoji: emoji, scoring: scoring, isMock: withExamples)
        l.name = name.trimmingCharacters(in: .whitespaces)
        l.emoji = emoji
        l.scoringRaw = scoring.rawValue
        l.cover = cover
        l.setDuration(days: days)
        if league == nil {
            l.monsterUUID = context.representative(rep)
            context.insert(l)
        }
        try? context.save()
        dismiss()
    }
}

struct JoinLeagueView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var leagues: [League]
    @State private var code: String
    @State private var message: String?
    @State private var rep: UUID? = MainMonster.id

    init(code: String = "") { _code = State(initialValue: code) }

    var body: some View {
        GMModal("Entrar numa liga", confirm: "Entrar", confirmEnabled: code.count >= 4, onConfirm: join) {
            GMSection("Código", footer: message ?? "Peça o código para quem criou a liga. Para testar, use \(MockLeague.code).") {
                GMTextField(placeholder: "Código da liga", text: $code, capitalization: .characters)
                    .font(.title3.monospaced())
                    .autocorrectionDisabled()
            }
            MonsterChoiceSection(choice: $rep)
        }
    }

    private func join() {
        let c = code.trimmingCharacters(in: .whitespaces).uppercased()
        if leagues.contains(where: { $0.code == c }) {
            message = "Você já está nessa liga."
        } else if c == MockLeague.code {
            let l = MockLeague.make()
            l.monsterUUID = context.representative(rep)
            context.insert(l)
            try? context.save()
            dismiss()
        } else {
            message = "Liga não encontrada. Convites entre pessoas chegam quando o app tiver servidor."
        }
    }
}

// MARK: - Check-in

/// Publica a mesma atividade em uma ou mais ligas
@MainActor
func postCheckIns(activity: Activity, leagues: Set<UUID>, title: String, note: String, photo: Data?, context: ModelContext) {
    let place = GymLocation.shared.gym(activity.gymUUID)?.name ?? GymLocation.shared.placeNow
    for id in leagues {
        let c = LeagueCheckIn(leagueUUID: id, activityUUID: activity.uuid,
                              title: title.isEmpty ? activity.kind.name : title, note: note, date: activity.date, photo: photo)
        c.place = place
        context.insert(c)
    }
}

/// Deixa os check-ins da atividade exatamente nos destinos escolhidos, com o mesmo post em todos
@MainActor
func syncCheckIns(activity: Activity, destinations: Set<UUID>, title: String, note: String, photo: Data?, place: String?, context: ModelContext) {
    let id = activity.uuid
    let existing = (try? context.fetch(FetchDescriptor<LeagueCheckIn>(predicate: #Predicate { $0.activityUUID == id }))) ?? []
    let t = title.trimmingCharacters(in: .whitespaces).isEmpty ? activity.kind.name : title.trimmingCharacters(in: .whitespaces)
    for c in existing where !destinations.contains(c.leagueUUID) { context.delete(c) }
    let kept = Set(existing.filter { destinations.contains($0.leagueUUID) }.map(\.leagueUUID))
    for c in existing where destinations.contains(c.leagueUUID) {
        c.title = t
        c.note = note
        c.photo = photo
        c.place = place
        c.date = activity.date
    }
    for d in destinations.subtracting(kept) {
        let c = LeagueCheckIn(leagueUUID: d, activityUUID: id, title: t, note: note, date: activity.date, photo: photo)
        c.place = place
        context.insert(c)
    }
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

/// Seção reaproveitada no registro de atividade, no fim do treino e na edição: onde postar o check-in e a foto
struct LeaguePostSection: View {
    @Binding var selected: Set<UUID>
    @Binding var photo: Data?
    /// Marca perfil e todas as ligas por padrão (registro de atividade e fim de treino)
    var selectAllByDefault = true
    @Query(sort: \League.joinedAt) private var allLeagues: [League]
    @State private var pick: PhotosPickerItem?

    /// Ligas ativas, mais as encerradas em que já está postado (para poder tirar)
    private var leagues: [League] { allLeagues.filter { !$0.isOver || selected.contains($0.uuid) } }
    private var everything: Set<UUID> { Set(leagues.filter { !$0.isOver }.map(\.uuid)).union([ProfileFeed.id]) }

    var body: some View {
        GMSection("Postar check-in em", footer: selected.isEmpty ? "Sem destino: a atividade fica só no seu histórico." : nil) {
            GMFlow {
                GMChip(title: "Meu perfil", icon: "person.crop.circle", selected: selected.contains(ProfileFeed.id)) { toggle(ProfileFeed.id) }
                ForEach(leagues) { l in
                    GMChip(title: "\(l.emoji) \(l.name)" + (l.isOver ? " (encerrada)" : ""), selected: selected.contains(l.uuid)) { toggle(l.uuid) }
                }
            }
            if !leagues.isEmpty {
                HStack(spacing: 8) {
                    GMButton("Todos", kind: .secondary, full: false, small: true) { selected.formUnion(everything) }
                    GMButton("Nenhum", kind: .ghost, full: false, small: true) { selected.removeAll() }
                }
            }
            GMDivider()
            PhotosPicker(selection: $pick, matching: .images) {
                HStack(spacing: 12) {
                    Image(systemName: "photo")
                        .font(.body.weight(.semibold))
                        .frame(width: 34, height: 34)
                        .background(Theme.raised, in: .rect(cornerRadius: 10))
                    Text(photo == nil ? "Adicionar foto" : "Trocar foto").font(.subheadline.weight(.semibold))
                    Spacer()
                    if let photo, let img = UIImage(data: photo) {
                        Image(uiImage: img).resizable().scaledToFill().frame(width: 44, height: 44).clipShape(.rect(cornerRadius: 8))
                    }
                }
                .foregroundStyle(.white)
            }
            .buttonStyle(GMPress())
            .onChange(of: pick) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self) { photo = compressedPhoto(data) }
                }
            }
            if photo != nil {
                GMButton("Tirar foto", kind: .ghost, full: false, small: true) { photo = nil; pick = nil }
            }
        }
        .onAppear { if selectAllByDefault && selected.isEmpty { selected = everything } }
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
    @State private var kind: ActivityKind = .musculacao
    @State private var minutes = 60
    @State private var effort = 6
    @State private var date = Date.now
    @State private var title = ""
    @State private var note = ""
    @State private var leagues: Set<UUID>
    @State private var photo: Data?

    init(preselected: Set<UUID>) {
        self.preselected = preselected
        _leagues = State(initialValue: preselected)
    }

    private var recent: [Activity] {
        let since = Date.now.addingTimeInterval(-7 * 86400)
        return activities.filter { $0.date >= since }
    }

    var body: some View {
        GMModal("Check-in", confirm: "Postar", confirmEnabled: !leagues.isEmpty && !(useExisting && existing == nil), onConfirm: post) {
            GMSegmented(options: [(false, "Nova atividade"), (true, "Já registrada")], selection: $useExisting)
            if useExisting {
                GMSection("Atividades recentes", footer: "Treinos guiados e os importados do Apple Saúde aparecem aqui.") {
                    if recent.isEmpty { Text("Nada registrado nos últimos 7 dias.").foregroundStyle(Theme.dim) }
                    ForEach(recent) { a in
                        let posted = checkIns.contains { $0.activityUUID == a.uuid && leagues.contains($0.leagueUUID) }
                        GMRow(icon: a.kind.symbol, title: a.kind.name,
                              subtitle: "\(durationText(a.minutes)) · \(a.date.formatted(.dateTime.weekday().day().hour().minute()))",
                              action: { existing = a.uuid }) {
                            if posted { Text("já postada").font(.caption2).foregroundStyle(Theme.dim) }
                            Image(systemName: existing == a.uuid ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(existing == a.uuid ? Theme.accent : Theme.dim)
                        }
                        if a.id != recent.last?.id { GMDivider() }
                    }
                }
            } else {
                GMSection("Atividade") { ActivityKindGrid(kind: $kind) }
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
            }
            LeaguePostSection(selected: $leagues, photo: $photo, selectAllByDefault: false)
        }
    }

    private func post() {
        let activity: Activity
        if useExisting, let id = existing, let a = activities.first(where: { $0.uuid == id }) {
            activity = a
        } else {
            activity = Activity(kind: kind, date: date, minutes: minutes, effort: effort, note: title)
            context.insert(activity)
        }
        // Não posta duas vezes a mesma atividade na mesma liga
        let already = Set(checkIns.filter { $0.activityUUID == activity.uuid }.map(\.leagueUUID))
        postCheckIns(activity: activity, leagues: leagues.subtracting(already), title: title, note: note, photo: photo, context: context)
        try? context.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
