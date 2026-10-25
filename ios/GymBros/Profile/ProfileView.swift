import PhotosUI
import SwiftData
import SwiftUI

// Perfil: parte pública (o que amigos veem nas ligas) e privada (calendário, estatísticas, metas)

/// Foto do perfil; sem foto, a inicial do nome
struct Avatar: View {
    var size: CGFloat = 40
    @AppStorage("profilePhoto") private var photo: Data?
    @AppStorage("trainerName") private var name = ""

    var body: some View { PersonAvatar(name: name, photo: photo, size: size) }
}

/// Bolinha no topo das abas; abre o perfil
struct ProfileAvatarButton: View {
    @State private var open = false

    var body: some View {
        Button { open = true } label: { Avatar(size: 40) }
            .buttonStyle(GMPress())
            .gmModal(isPresented: $open) { ProfileView() }
    }
}

struct ProfileView: View {
    @Query(sort: \Activity.date, order: .reverse) private var activities: [Activity]
    @Query private var checkIns: [LeagueCheckIn]
    @Query(sort: \Monster.createdAt) private var monsters: [Monster]
    @Query private var leagues: [League]
    @Query(filter: #Predicate<WorkoutSession> { $0.end != nil }, sort: \WorkoutSession.start) private var sessions: [WorkoutSession]
    @AppStorage("profilePhoto") private var photo: Data?
    @AppStorage("trainerName") private var name = ""
    @AppStorage("profileUsername") private var username = ""
    @AppStorage("profileBio") private var bio = ""
    @AppStorage("publicMonster") private var showMonster = true
    @AppStorage("publicStats") private var showStats = true
    @AppStorage("publicAchievements") private var showAchievements = true
    @AppStorage("publicBros") private var showBros = true
    @AppStorage("discovered") private var discovered = ""

    @State private var tab = 1
    @State private var pick: PhotosPickerItem?
    @State private var settings = false
    @State private var logging = false
    @State private var editing = false
    @State private var day: Date?
    @State private var retro = false

    private var roster: Roster { Roster(monsters: monsters, activities: activities, checkIns: checkIns, leagues: leagues) }
    private var activeDays: Int { Set(activities.map { Calendar.current.startOfDay(for: $0.date) }).count }
    private var totalMinutes: Int { activities.reduce(0) { $0 + $1.minutes } }

    var body: some View {
        NavigationStack {
            GMScreen("", close: true, large: false, bottomInset: 110) {
                GMIconButton(icon: "gearshape", label: "Ajustes") { settings = true }
            } content: {
                header.frame(maxWidth: .infinity)
                GMSegmented(options: [(0, "Público"), (1, "Privado")], selection: $tab)
                if tab == 0 {
                    SocialGate(requires: .profileUpdate) { publicPart }
                } else {
                    privatePart
                }
            }
            .overlay(alignment: .bottomTrailing) {
                GMFloatingButton(label: "Registrar atividade") { logging = true }
                    .padding(20)
            }
            .gmModal(isPresented: $settings) { SettingsView() }
            .gmModal(isPresented: $editing) { EditProfileView() }
            .gmModal(isPresented: $retro) { RetrospectiveView() }
            .gmModal(isPresented: $logging) { LogActivityView(snapshot: roster.mainSnapshot) }
            .gmSheet(isPresented: Binding(get: { day != nil }, set: { if !$0 { day = nil } })) { _ in dayDetail }
            .onChange(of: pick) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self) {
                        photo = avatarPhoto(data)
                        await ProfilePhotos.shared.publish()
                    }
                }
            }
        }
    }

    // MARK: Cabeçalho

    private var header: some View {
        VStack(spacing: 10) {
            PhotosPicker(selection: $pick, matching: .images) {
                Avatar(size: 110)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "camera.fill")
                            .font(.caption.bold())
                            .frame(width: 32, height: 32)
                            .background(Theme.accent, in: .circle)
                            .foregroundStyle(.black)
                    }
            }
            .buttonStyle(GMPress())
            VStack(spacing: 2) {
                Text(name.isEmpty ? "Treinador" : name).font(.title2.weight(.heavy))
                if !username.isEmpty { Text("@\(username)").font(.subheadline).foregroundStyle(Theme.dim) }
                if !bio.isEmpty { Text(bio).font(.subheadline).multilineTextAlignment(.center).padding(.top, 4) }
            }
            GMButton("Editar perfil", icon: "pencil", kind: .secondary, full: false, small: true) { editing = true }
                .padding(.top, 2)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.monospacedDigit())
            Text(label).font(.caption).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Privado

    private var privatePart: some View {
        VStack(spacing: 18) {
            HStack {
                stat("\(activities.count)", "Atividades")
                stat("\(activeDays)", "Dias ativos")
                stat(hoursText(totalMinutes), "Duração")
            }
            HStack(spacing: 0) {
                pill("medal", "Recordes") { ExerciseStatsList(sessions: sessions.reversed()) }
                pill("bolt", "Estatísticas") { ProfileStatsView() }
                pill("target", "Metas") { GoalsView() }
            }
            .padding(6)
            .background(Theme.card, in: .capsule)

            calendar

            NavigationLink { ConstancyView() } label: {
                GMCard { GMRow(icon: "flame.fill", iconTint: Theme.streak, title: "Sequências e recordes", subtitle: "Dias, semanas e meses seguidos; melhor dia, semana, mês e ano", chevron: true) }
            }
            .buttonStyle(GMPress())
            GMCard {
                GMRow(icon: "film.stack", iconTint: Theme.accent, title: "Retrospectiva em vídeo", subtitle: "As fotos dos seus check-ins do ano, com os seus números", chevron: true) { retro = true }
            }

            DuelHistorySection()

            titles

            HStack(spacing: 10) {
                NavigationLink { AllActivitiesView() } label: {
                    Text("Ver todas as atividades").font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18).padding(.vertical, 11)
                        .background(Theme.raised, in: .capsule)
                        .foregroundStyle(.white)
                }
                .buttonStyle(GMPress())
                NavigationLink { BodyTrackerView() } label: {
                    Label("Peso", systemImage: "scalemass").font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18).padding(.vertical, 11)
                        .background(Theme.raised, in: .capsule)
                        .foregroundStyle(.white)
                }
                .buttonStyle(GMPress())
            }
        }
    }

    /// Vitórias de semana, mês e ano nos clubes
    @ViewBuilder
    private var titles: some View {
        let byID = Dictionary(activities.map { ($0.uuid, $0) }, uniquingKeysWith: { a, _ in a })
        let wins = ClubWinners.myWins(leagues: leagues, checkIns: checkIns, activities: byID, me: name, avatar: .egg)
        if !wins.isEmpty {
            GMSection("Títulos nos clubes", footer: "Cada semana, mês e ano que você terminou em primeiro num clube (empate divide o título).") {
                HStack {
                    ForEach(WinPeriod.allCases) { p in
                        VStack(spacing: 2) {
                            Text("🏆 \(wins[p] ?? 0)").font(.headline.monospacedDigit())
                            Text(p.name).font(.caption).foregroundStyle(Theme.dim)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(p.wins(wins[p] ?? 0))
                    }
                }
            }
        }
    }

    private func pill<D: View>(_ icon: String, _ title: String, @ViewBuilder destination: @escaping () -> D) -> some View {
        NavigationLink(destination: destination) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(.white)
        }
        .buttonStyle(GMPress())
    }

    // MARK: Calendário com fotos

    private var calendar: some View {
        let photos = photosByActivity
        return ActivityCalendar(marks: activities.map { CalendarMark(id: $0.uuid.uuidString, date: $0.date, kind: $0.kind, photo: photos[$0.uuid]) }) { day = $0 }
    }

    /// Foto do check-in de cada atividade (a primeira, se foi postada em várias ligas)
    private var photosByActivity: [UUID: Data] {
        var out: [UUID: Data] = [:]
        for c in checkIns { if let p = c.photo, out[c.activityUUID] == nil { out[c.activityUUID] = p } }
        return out
    }

    private var dayDetail: some View {
        let items = activities.filter { a in day.map { d in Calendar.current.isDate(a.date, inSameDayAs: d) } ?? false }
        let xp = roster.xpByActivity
        let photos = photosByActivity
        return VStack(alignment: .leading, spacing: 12) {
            Text(day.map { GMDateText.day($0) } ?? "").font(.headline)
            ForEach(items) { a in
                ActivityRow(activity: a, xp: xp[a.uuid] ?? 0)
                if let p = photos[a.uuid], let img = UIImage(data: p) {
                    Image(uiImage: img).resizable().scaledToFill().frame(height: 180).frame(maxWidth: .infinity)
                        .clipShape(.rect(cornerRadius: Theme.radiusL))
                }
            }
        }
    }

    // MARK: Público

    private var publicPart: some View {
        let r = roster
        let s = r.mainSnapshot
        let best = Achievements.evaluate(.init(activities: activities.map(\.record),
                                               fromHealth: activities.filter { $0.healthUUID != nil }.count,
                                               snapshot: Game.cachedSnapshot(activities.map(\.record)), sessions: sessions.map(\.log),
                                               species: Set(r.snapshots.values.filter { $0.stage > .egg }.map(\.form.species)).count,
                                               ultimates: r.snapshots.values.filter { $0.stage == .ultimate }.count,
                                               discovered: discovered.split(separator: ",").count, dexTotal: DexView.allForms.count))
            .filter(\.unlocked)
        return VStack(spacing: 18) {
            Text("É assim que seus amigos te veem").font(.caption).foregroundStyle(Theme.dim)
            GMCard {
                PublicProfileCard(profile: PublicProfile(
                    id: "me", name: name, username: username, bio: bio,
                    bro: showMonster ? .init(name: r.main?.displayName(s.form) ?? s.form.name, formID: s.form.id, level: s.level, progress: s.progress) : nil,
                    stats: showStats ? publicStats : nil,
                    achievements: showAchievements ? best.map { .init(title: $0.title, symbol: $0.symbol) } : nil,
                    bros: showBros ? PublicProfile.bros(roster: r, activities: activities, checkIns: checkIns,
                                                        discovered: Set(discovered.split(separator: ",").map(String.init))) : nil
                ), showHeader: false)
            }
            postsCalendar(avatar: s.form)
        }
    }
}

extension ProfileView {
    /// Números públicos: só o que foi postado (perfil ou ligas) conta; atividade não postada fica privada.
    /// Ligas = as que você está agora (temporadas passadas da mesma liga não contam de novo).
    var publicStats: PublicProfile.Stats {
        PublicProfile.stats(activities: activities, checkIns: checkIns, leagues: leagues)
    }

    /// Check-ins postados no perfil, em calendário (igual ao que os amigos veem)
    @ViewBuilder
    func postsCalendar(avatar: MonsterForm) -> some View {
        let byID = Dictionary(activities.map { ($0.uuid, $0) }, uniquingKeysWith: { a, _ in a })
        let posts: [FeedItem] = checkIns.filter { $0.leagueUUID == ProfileFeed.id }.sorted { $0.date > $1.date }.compactMap { c in
            guard let a = byID[c.activityUUID] else { return nil }
            return FeedItem(id: c.uuid.uuidString, memberID: "me", name: name, avatar: avatar, isMe: true, date: c.date, title: c.title,
                            note: c.note, kind: a.kind, minutes: a.minutes, score: Game.xp(kind: a.kind, minutes: a.minutes, effort: a.effort),
                            photo: c.photo, place: c.place, hasPhoto: c.hasPhoto, effort: a.effort)
        }
        GMSection("Posts · \(posts.count)", footer: posts.isEmpty ? "Ao registrar uma atividade, marque \"Meu perfil\" em \"Postar em\"." : nil) {
            PostsCalendar(posts: posts)
        }
    }
}

/// Nome, @usuário, bio e o que aparece para os outros. Nome, @usuário e bio só valem ao salvar:
/// passam pelo filtro de palavras e, com conta, pelo aceite dos termos.
struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("trainerName") private var savedName = ""
    @AppStorage("profileUsername") private var savedUsername = ""
    @AppStorage("profileBio") private var savedBio = ""
    @AppStorage("publicMonster") private var showMonster = true
    @AppStorage("publicStats") private var showStats = true
    @AppStorage("publicAchievements") private var showAchievements = true
    @AppStorage("publicBros") private var showBros = true
    @AppStorage(ProfilePhotos.showKey) private var showPhoto = true
    @State private var name = ""
    @State private var username = ""
    @State private var bio = ""
    @State private var loaded = false
    @State private var blocked = false
    @State private var terms = TermsGate()

    var body: some View {
        GMModal("Editar perfil", confirm: "Salvar", onConfirm: save) {
            GMSection("Perfil público", footer: "A foto você troca tocando nela, no topo do perfil.") {
                GMTextField(placeholder: "Seu nome", text: $name, capitalization: .words)
                GMTextField(placeholder: "@usuário", text: Binding(
                    get: { username },
                    set: { username = $0.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." } }
                ), capitalization: .never)
                GMTextField(placeholder: "Bio (ex.: Rato de academia desde 2019)", text: $bio, axis: .vertical)
                if blocked { ContentBlockedNote() }
            }
            GMSection("O que aparece para os outros",
                      footer: "Nome, @usuário, bio e os posts do perfil sempre aparecem. Em \"Bros e atributos\", os atributos somam todos os seus treinos, mas só aparece o percentual de cada um. Peso, medidas, recordes, metas, notas e as atividades que você não postou ficam sempre privados.") {
                GMToggle(title: "Foto do perfil", isOn: $showPhoto)
                GMDivider()
                GMToggle(title: "Bro principal", isOn: $showMonster)
                GMDivider()
                GMToggle(title: "Números (check-ins, dias, ligas)", isOn: $showStats)
                GMDivider()
                GMToggle(title: "Conquistas", isOn: $showAchievements)
                GMDivider()
                GMToggle(title: "Bros e atributos", isOn: $showBros)
            }
            BodyProfileSection()
        }
        .termsGate($terms)
        .onChange(of: name + username + bio) { blocked = false }
        // Foto trocada ou escondida: os outros veem a mudança na hora
        .onChange(of: showPhoto) { Task { await ProfilePhotos.shared.publish() } }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            name = savedName
            username = savedUsername
            bio = savedBio
        }
    }

    private func save() {
        guard ContentFilter.allows(name, username, bio) else { blocked = true; return }
        let write = {
            savedName = name
            savedUsername = username
            savedBio = bio
            dismiss()
        }
        terms.run(write)
    }
}

/// Foto do perfil quadrada e pequena
func avatarPhoto(_ data: Data) -> Data? {
    guard let img = UIImage(data: data) else { return nil }
    let side = min(img.size.width, img.size.height)
    let crop = CGRect(x: (img.size.width - side) / 2, y: (img.size.height - side) / 2, width: side, height: side)
    let target = CGSize(width: 512, height: 512)
    let out = UIGraphicsImageRenderer(size: target).image { _ in
        img.draw(in: CGRect(x: -crop.minX * 512 / side, y: -crop.minY * 512 / side,
                            width: img.size.width * 512 / side, height: img.size.height * 512 / side))
    }
    return out.jpegData(compressionQuality: 0.8)
}

func hoursText(_ minutes: Int) -> String {
    minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
}

// MARK: - Todas as atividades

struct AllActivitiesView: View {
    @Query(sort: \Activity.date, order: .reverse) private var activities: [Activity]

    var body: some View {
        let groups = Dictionary(grouping: activities) { Calendar.current.startOfDay(for: $0.date) }
        GMScreen("Atividades", back: true) {
            if activities.isEmpty { GMEmptyState(icon: "figure.run", title: "Nenhuma atividade ainda") }
            ForEach(groups.keys.sorted(by: >), id: \.self) { d in
                GMSection(GMDateText.day(d)) {
                    ForEach(groups[d]!) { a in ActivityRow(activity: a, xp: Game.xp(kind: a.kind, minutes: a.minutes, effort: a.effort)) }
                }
            }
        }
    }
}

// MARK: - Estatísticas

struct ProfileStatsView: View {
    @Query(sort: \Activity.date) private var activities: [Activity]

    var body: some View {
        let s = Game.cachedSnapshot(activities.map(\.record))
        let byKind = Dictionary(grouping: activities, by: \.kind)
        let maxMinutes = byKind.values.map { $0.reduce(0) { $0 + $1.minutes } }.max() ?? 1
        let weeks = max(Double(Calendar.current.dateComponents([.day], from: activities.first?.date ?? .now, to: .now).day ?? 0) / 7, 1)
        let attrSum = max(s.lifetimeAttributes.values.reduce(0, +), 1)

        GMScreen("Estatísticas", back: true) {
            GMCard {
                HStack {
                    big("\(s.bestStreak)", "melhor sequência")
                    big(String(format: "%.1f", Double(activities.count) / weeks).replacingOccurrences(of: ".", with: ","), "treinos/semana")
                    big(hoursText(activities.map(\.minutes).max() ?? 0), "maior treino")
                }
            }

            GMSection("Últimas 16 semanas") { heatmap }

            GMSection("Por atividade") {
                ForEach(byKind.keys.sorted { (byKind[$0]?.count ?? 0) > (byKind[$1]?.count ?? 0) }) { k in
                    let items = byKind[k] ?? []
                    let minutes = items.reduce(0) { $0 + $1.minutes }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label(k.name, systemImage: k.symbol).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(items.count)× · \(hoursText(minutes))").font(.caption.monospacedDigit()).foregroundStyle(Theme.dim)
                        }
                        GMProgressBar(value: Double(minutes) / Double(maxMinutes), height: 6)
                    }
                }
            }

            GMSection("Atributos treinados") {
                ForEach(Attribute.allCases) { a in
                    let v = s.lifetimeAttributes[a] ?? 0
                    HStack {
                        Label(a.name, systemImage: a.symbol).foregroundStyle(a.color).font(.subheadline.weight(.semibold))
                            .frame(width: 130, alignment: .leading)
                        GMProgressBar(value: v / attrSum, tint: a.color, height: 6)
                        Text("\(Int((v / attrSum * 100).rounded()))%").font(.caption.monospacedDigit()).frame(width: 40, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func big(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.heavy).monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    /// Grade de semanas × dias, com a cor pela quantidade de minutos
    private var heatmap: some View {
        let cal = Calendar.current
        let minutes = Dictionary(grouping: activities) { cal.startOfDay(for: $0.date) }.mapValues { $0.reduce(0) { $0 + $1.minutes } }
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: .now)!.start
        return HStack(spacing: 3) {
            ForEach(0..<16, id: \.self) { w in
                VStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { d in
                        let day = cal.date(byAdding: .day, value: d - (15 - w) * 7, to: thisWeek)!
                        let m = minutes[day] ?? 0
                        RoundedRectangle(cornerRadius: Theme.radiusXS)
                            .fill(day > .now ? Color.clear : m == 0 ? Theme.raised : Theme.accent.opacity(min(0.3 + Double(m) / 120, 1)))
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
    }
}

// MARK: - Metas

