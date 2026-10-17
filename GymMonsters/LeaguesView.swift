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
        }
    }
}

extension MockLeague {
    static func make() -> League {
        let l = League(name: name, emoji: "🔥", scoring: .pontos,
                       start: Calendar.current.date(byAdding: .day, value: -12, to: .now)!, isMock: true)
        l.code = code
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
                Text("\(pos)º de \(rank.count) · \(league.scoring.name)").font(.caption).foregroundStyle(Theme.dim)
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
    @AppStorage("likes") private var likes = ""
    @State private var tab = 0
    @State private var weekOnly = false
    @State private var checkingIn = false
    @State private var confirmLeave = false
    @State private var leaving = false

    var body: some View {
        let byID = Dictionary(activities.map { ($0.uuid, $0) }, uniquingKeysWith: { a, _ in a })
        let mine = allCheckIns.filter { $0.leagueUUID == league.uuid }
        // Dentro da liga você aparece com o monstro que te representa nela
        let roster = Roster(monsters: monsters, activities: activities, checkIns: allCheckIns, leagues: leagues)
        let rep = roster.snapshot(league.monsterUUID)
        let avatar = rep.form
        let feed = LeagueBoard.feed(league: league, mine: mine, activities: byID, me: trainerName, myAvatar: avatar)
        let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start
        let rank = LeagueBoard.ranking(feed: feed, league: league, me: trainerName, myAvatar: avatar, since: weekOnly ? weekStart : nil)

        GMScreen(league.name, back: true, bottomInset: 170) {
            GMIconButton(icon: "ellipsis") { confirmLeave = true }
        } content: {
            GMCard { header(rep, monster: roster.monster(league.monsterUUID)) }

            GMSegmented(options: [(0, "Ranking"), (1, "Feed")], selection: $tab)

            if tab == 0 {
                GMSegmented(options: [(false, "Desde o início"), (true, "Esta semana")], selection: $weekOnly)
                GMSection(footer: league.scoring.detail) {
                    ForEach(Array(rank.enumerated()), id: \.element.id) { i, r in
                        rankRow(i + 1, r)
                        if i < rank.count - 1 { GMDivider() }
                    }
                }
            } else {
                if feed.isEmpty {
                    GMEmptyState(icon: "camera", title: "Nenhum check-in ainda", message: "Seja o primeiro!")
                }
                ForEach(feed.prefix(80)) { item in
                    GMCard { post(item) }
                }
            }
        }
        .overlay(alignment: .bottom) {
            // Acima da barra de abas
            GMButton("Fazer check-in", icon: "camera.fill") { checkingIn = true }
                .padding(.horizontal, 16)
                .padding(.bottom, 76)
        }
        .gmModal(isPresented: $checkingIn) { CheckInForm(preselected: [league.uuid]) }
        .gmActions(isPresented: $confirmLeave, title: "\(league.emoji) \(league.name)", actions: [
            GMAction("Sair da liga", icon: "rectangle.portrait.and.arrow.right", destructive: true) { leaving = true }
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

    private func header(_ m: Snapshot, monster: Monster?) -> some View {
        HStack(spacing: 14) {
            LivingMonster(form: m.form, progress: m.progress).frame(width: 84, height: 84)
            VStack(alignment: .leading, spacing: 5) {
                Text("\(league.emoji) \(league.name)").font(.headline)
                Text("Código \(league.code) · desde \(league.start.formatted(.dateTime.day().month(.abbreviated)))")
                    .font(.caption)
                    .foregroundStyle(Theme.dim)
                Text("Te representa: \(monster?.displayName(m.form) ?? m.form.name)" +
                     (m.stage == .egg ? " · faltam \(m.xpToNext ?? 0) XP para chocar" : " · Nível \(m.level)"))
                    .font(.caption)
                GMProgressBar(value: m.progress, height: 6)
                ShareLink(item: inviteText) {
                    Label("Convidar", systemImage: "person.badge.plus")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Theme.raised, in: .capsule)
                        .foregroundStyle(.white)
                }
                .buttonStyle(GMPress())
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

    private func post(_ item: FeedItem) -> some View {
        let liked = likes.split(separator: ",").contains { $0 == item.id }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                MonsterSprite(form: item.avatar).frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name).font(.subheadline.bold())
                    Text(item.date.formatted(.relative(presentation: .named)) + (item.place.map { " · 📍 \($0)" } ?? ""))
                        .font(.caption2).foregroundStyle(Theme.dim)
                }
                Spacer()
                Text("+\(item.score)").font(.subheadline.bold().monospacedDigit()).foregroundStyle(Theme.accent)
            }
            Text(item.title).font(.subheadline.weight(.semibold))
            if !item.note.isEmpty { Text(item.note).font(.footnote).foregroundStyle(Theme.dim) }
            if let data = item.photo, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill()
                    .frame(maxHeight: 260).clipShape(.rect(cornerRadius: 12))
            }
            HStack {
                Label("\(item.kind.name) · \(durationText(item.minutes))", systemImage: item.kind.symbol)
                    .font(.caption)
                    .foregroundStyle(Theme.dim)
                Spacer()
                if !item.isMe {
                    Button {
                        var set = Set(likes.split(separator: ",").map(String.init))
                        if liked { set.remove(item.id) } else { set.insert(item.id) }
                        likes = set.sorted().joined(separator: ",")
                    } label: {
                        Text(liked ? "💪 1" : "💪").font(.subheadline)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(liked ? Theme.accent.opacity(0.25) : Theme.raised, in: .capsule)
                    }
                    .buttonStyle(GMPress())
                }
            }
        }
    }
}

// MARK: - Criar e entrar

struct CreateLeagueView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var emoji = "🏆"
    @State private var scoring: LeagueScoring = .pontos
    @State private var withExamples = false
    @State private var rep: UUID? = MainMonster.id

    private let emojis = ["🏆", "🔥", "💪", "🏃", "⚡️", "🦁", "🐉", "⭐️", "🏐", "🧘"]

    var body: some View {
        GMModal("Nova liga", confirm: "Criar", confirmEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty) {
            let l = League(name: name.trimmingCharacters(in: .whitespaces), emoji: emoji, scoring: scoring, isMock: withExamples)
            l.monsterUUID = context.representative(rep)
            context.insert(l)
            try? context.save()
            dismiss()
        } content: {
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
            GMSection("Pontuação", footer: scoring.detail) {
                GMSegmented(options: LeagueScoring.allCases.map { ($0, $0.name) }, selection: $scoring)
            }
            MonsterChoiceSection(choice: $rep)
            GMSection(footer: "Enquanto não há servidor, os convites não chegam em outras pessoas. Ative para ver a liga com participantes simulados.") {
                GMToggle(title: "Participantes de exemplo", isOn: $withExamples)
            }
        }
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

/// Reduz a foto para algo razoável de guardar
func compressedPhoto(_ data: Data) -> Data? {
    guard let img = UIImage(data: data) else { return nil }
    let maxSide: CGFloat = 1280
    let scale = min(1, maxSide / max(img.size.width, img.size.height))
    let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
    let resized = UIGraphicsImageRenderer(size: size).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
    return resized.jpegData(compressionQuality: 0.7)
}

/// Seção reaproveitada no registro de atividade e ao concluir treino: em quais ligas postar
struct LeaguePostSection: View {
    @Binding var selected: Set<UUID>
    @Binding var photo: Data?
    /// Marca todas as ligas por padrão (registro de atividade e fim de treino)
    var selectAllByDefault = true
    @Query(sort: \League.joinedAt) private var leagues: [League]
    @State private var pick: PhotosPickerItem?

    var body: some View {
        if !leagues.isEmpty {
            GMSection("Check-in nas ligas") {
                ForEach(leagues) { l in
                    GMToggle(title: "\(l.emoji) \(l.name)", isOn: Binding(
                        get: { selected.contains(l.uuid) },
                        set: { if $0 { selected.insert(l.uuid) } else { selected.remove(l.uuid) } }
                    ))
                    GMDivider()
                }
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
            }
            .onAppear { if selectAllByDefault && selected.isEmpty { selected = Set(leagues.map(\.uuid)) } }
        }
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
