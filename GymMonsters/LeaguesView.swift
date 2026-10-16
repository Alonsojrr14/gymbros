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
            List {
                if leagues.isEmpty {
                    ContentUnavailableView("Nenhuma liga", systemImage: "trophy",
                                           description: Text("Crie uma liga e chame os amigos, ou entre com um código."))
                        .listRowBackground(Color.clear)
                }
                ForEach(leagues) { l in
                    NavigationLink { LeagueDetailView(league: l) } label: {
                        LeagueRow(league: l, mine: checkIns.filter { $0.leagueUUID == l.uuid }, roster: roster, me: trainerName)
                    }
                    .listRowBackground(Theme.card)
                }
                Section {
                    Button { creating = true } label: { Label("Criar liga", systemImage: "plus.circle") }
                    Button { joinCode = ""; joining = true } label: { Label("Entrar com código", systemImage: "ticket") }
                    if !leagues.contains(where: { $0.code == MockLeague.code }) {
                        Button { joinCode = MockLeague.code; joining = true } label: {
                            Label("Experimentar a liga de exemplo", systemImage: "sparkles")
                        }
                    }
                } footer: {
                    Text("Cada liga é um ranking de check-ins, de qualquer atividade. Ao entrar, você escolhe quem te representa: um monstro seu ou um ovo novo. Os check-ins da liga dão XP só para ele.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Ligas")
            .sheet(isPresented: $creating) { CreateLeagueView() }
            .sheet(isPresented: $joining) { JoinLeagueView(code: joinCode) }
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
                    if league.isMock { Text("exemplo").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2).background(.white.opacity(0.1), in: .capsule) }
                }
                Text("\(pos)º de \(rank.count) · \(league.scoring.name)").font(.caption).foregroundStyle(Theme.dim)
            }
            Spacer()
            MonsterSprite(form: egg.form).frame(width: 44, height: 44)
        }
        .padding(.vertical, 4)
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

        List {
            Section { header(rep, monster: roster.monster(league.monsterUUID)) }
                .listRowBackground(Theme.card)

            Picker("", selection: $tab) {
                Text("Ranking").tag(0)
                Text("Feed").tag(1)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            if tab == 0 {
                Section {
                    Picker("Período", selection: $weekOnly) {
                        Text("Desde o início").tag(false)
                        Text("Esta semana").tag(true)
                    }
                    .pickerStyle(.segmented)
                    ForEach(Array(rank.enumerated()), id: \.element.id) { i, r in
                        rankRow(i + 1, r)
                    }
                } footer: {
                    Text(league.scoring.detail)
                }
                .listRowBackground(Theme.card)
            } else {
                if feed.isEmpty {
                    Text("Nenhum check-in ainda. Seja o primeiro!").foregroundStyle(Theme.dim).listRowBackground(Theme.card)
                }
                ForEach(feed.prefix(80)) { item in
                    post(item).listRowBackground(Theme.card)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle(league.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button { checkingIn = true } label: {
                Label("Fazer check-in", systemImage: "camera.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.accent, in: .rect(cornerRadius: 16))
                    .foregroundStyle(.black)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
        }
        .toolbar {
            Menu {
                ShareLink(item: inviteText) { Label("Convidar", systemImage: "person.badge.plus") }
                Button("Sair da liga", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { confirmLeave = true }
            } label: { Image(systemName: "ellipsis.circle") }
        }
        .sheet(isPresented: $checkingIn) { CheckInForm(preselected: [league.uuid]) }
        .confirmationDialog("Sair de \(league.name)? Os check-ins e o monstro desta liga somem; suas atividades continuam.",
                            isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Sair", role: .destructive) {
                mine.forEach(context.delete)
                context.delete(league)
                try? context.save()
                dismiss()
            }
        }
    }

    private var inviteText: String {
        "Entra na minha liga \(league.emoji) \(league.name) no GymMonsters! Código: \(league.code)"
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
                ProgressView(value: m.progress).tint(Theme.accent)
            }
        }
        .padding(.vertical, 6)
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
                    Text(item.date.formatted(.relative(presentation: .named))).font(.caption2).foregroundStyle(Theme.dim)
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
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(liked ? Theme.accent.opacity(0.25) : .white.opacity(0.07), in: .capsule)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 6)
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
        NavigationStack {
            Form {
                Section {
                    TextField("Nome da liga", text: $name)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(emojis, id: \.self) { e in
                                Text(e).font(.title)
                                    .padding(6)
                                    .background(emoji == e ? Theme.accent.opacity(0.3) : .clear, in: .rect(cornerRadius: 10))
                                    .onTapGesture { emoji = e }
                            }
                        }
                    }
                }
                Section {
                    Picker("Pontuação", selection: $scoring) {
                        ForEach(LeagueScoring.allCases) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } footer: { Text(scoring.detail) }
                MonsterChoiceSection(choice: $rep)
                Section {
                    Toggle("Participantes de exemplo", isOn: $withExamples)
                } footer: {
                    Text("Enquanto não há servidor, os convites não chegam em outras pessoas. Ative para ver a liga com participantes simulados.")
                }
            }
            .navigationTitle("Nova liga")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Criar") {
                        let l = League(name: name.trimmingCharacters(in: .whitespaces), emoji: emoji, scoring: scoring, isMock: withExamples)
                        l.monsterUUID = context.representative(rep)
                        context.insert(l)
                        try? context.save()
                        dismiss()
                    }
                    .bold()
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
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
        NavigationStack {
            Form {
                Section {
                    TextField("Código da liga", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.title3.monospaced())
                } footer: {
                    Text(message ?? "Peça o código para quem criou a liga. Para testar, use \(MockLeague.code).")
                }
                MonsterChoiceSection(choice: $rep)
            }
            .navigationTitle("Entrar numa liga")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Entrar", action: join).bold().disabled(code.count < 4)
                }
            }
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
    for id in leagues {
        context.insert(LeagueCheckIn(leagueUUID: id, activityUUID: activity.uuid,
                                     title: title.isEmpty ? activity.kind.name : title, note: note, date: activity.date, photo: photo))
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
            Section {
                ForEach(leagues) { l in
                    Toggle("\(l.emoji) \(l.name)", isOn: Binding(
                        get: { selected.contains(l.uuid) },
                        set: { if $0 { selected.insert(l.uuid) } else { selected.remove(l.uuid) } }
                    ))
                }
                PhotosPicker(selection: $pick, matching: .images) {
                    HStack {
                        Label(photo == nil ? "Adicionar foto" : "Trocar foto", systemImage: "photo")
                        Spacer()
                        if let photo, let img = UIImage(data: photo) {
                            Image(uiImage: img).resizable().scaledToFill().frame(width: 44, height: 44).clipShape(.rect(cornerRadius: 8))
                        }
                    }
                }
                .onChange(of: pick) { _, item in
                    Task {
                        if let data = try? await item?.loadTransferable(type: Data.self) { photo = compressedPhoto(data) }
                    }
                }
            } header: {
                Text("Check-in nas ligas")
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
    @State private var effort = 6.0
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
        NavigationStack {
            Form {
                Section {
                    Picker("", selection: $useExisting) {
                        Text("Nova atividade").tag(false)
                        Text("Já registrada").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                if useExisting {
                    Section {
                        if recent.isEmpty { Text("Nada registrado nos últimos 7 dias.").foregroundStyle(Theme.dim) }
                        ForEach(recent) { a in
                            let posted = checkIns.contains { $0.activityUUID == a.uuid && leagues.contains($0.leagueUUID) }
                            Button { existing = a.uuid } label: {
                                HStack {
                                    Image(systemName: a.kind.symbol).frame(width: 28)
                                    VStack(alignment: .leading) {
                                        Text(a.kind.name)
                                        Text("\(durationText(a.minutes)) · \(a.date.formatted(.dateTime.weekday().day().hour().minute()))")
                                            .font(.caption).foregroundStyle(Theme.dim)
                                    }
                                    Spacer()
                                    if posted { Text("já postada").font(.caption2).foregroundStyle(Theme.dim) }
                                    Image(systemName: existing == a.uuid ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(existing == a.uuid ? Theme.accent : Theme.dim)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } header: { Text("Atividades recentes") } footer: {
                        Text("Treinos guiados e os importados do Apple Saúde aparecem aqui.")
                    }
                } else {
                    Section("Atividade") {
                        Picker("Tipo", selection: $kind) {
                            ForEach(ActivityKind.allCases) { Label($0.name, systemImage: $0.symbol).tag($0) }
                        }
                        Stepper(value: $minutes, in: 5...Game.maxMinutes, step: 5) { Text(durationText(minutes)) }
                        VStack(alignment: .leading) {
                            Text("Esforço \(Int(effort))/10 · \(effortLabel(Int(effort)))").font(.subheadline)
                            Slider(value: $effort, in: 1...10, step: 1)
                        }
                        DatePicker("Quando", selection: $date, in: ...Date.now)
                    }
                }
                Section("Post") {
                    TextField("Título (ex.: Dia de perna 🦵)", text: $title)
                    TextField("Descrição (opcional)", text: $note, axis: .vertical)
                }
                LeaguePostSection(selected: $leagues, photo: $photo, selectAllByDefault: false)
            }
            .navigationTitle("Check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Postar", action: post).bold()
                        .disabled(leagues.isEmpty || (useExisting && existing == nil))
                }
            }
        }
    }

    private func post() {
        let activity: Activity
        if useExisting, let id = existing, let a = activities.first(where: { $0.uuid == id }) {
            activity = a
        } else {
            activity = Activity(kind: kind, date: date, minutes: minutes, effort: Int(effort), note: title)
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
