import PhotosUI
import SwiftData
import SwiftUI

// Perfil: parte pública (o que amigos veem nas ligas) e privada (calendário, estatísticas, metas)

/// Foto do perfil; sem foto, a inicial do nome
struct Avatar: View {
    var size: CGFloat = 40
    @AppStorage("profilePhoto") private var photo: Data?
    @AppStorage("trainerName") private var name = ""

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
    @Environment(\.dismiss) private var dismiss
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
    @AppStorage("discovered") private var discovered = ""

    @State private var tab = 1
    @State private var pick: PhotosPickerItem?
    @State private var settings = false
    @State private var logging = false
    @State private var month = Date.now
    @State private var day: Date?

    private var roster: Roster { Roster(monsters: monsters, activities: activities, checkIns: checkIns, leagues: leagues) }
    private var activeDays: Int { Set(activities.map { Calendar.current.startOfDay(for: $0.date) }).count }
    private var totalMinutes: Int { activities.reduce(0) { $0 + $1.minutes } }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(spacing: 18) {
                        header
                        GMSegmented(options: [(0, "Público"), (1, "Privado")], selection: $tab)
                        if tab == 0 { publicPart } else { privatePart }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 110)
                }
                .scrollDismissesKeyboard(.immediately)

                Button { logging = true } label: {
                    Image(systemName: "plus")
                        .font(.title2.bold())
                        .frame(width: 62, height: 62)
                        .background(Theme.accent, in: .circle)
                        .foregroundStyle(.black)
                        .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
                }
                .buttonStyle(GMPress())
                .padding(20)
            }
            .background(Theme.bg.ignoresSafeArea())
            .safeAreaInset(edge: .top) {
                HStack {
                    GMIconButton(icon: "xmark") { dismiss() }
                    Spacer()
                    GMIconButton(icon: "gearshape") { settings = true }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Theme.bg)
            }
            .toolbar(.hidden, for: .navigationBar)
            .gmKeyboardDone()
            .gmModal(isPresented: $settings) { SettingsView() }
            .gmModal(isPresented: $logging) { LogActivityView(snapshot: roster.mainSnapshot) }
            .gmSheet(isPresented: Binding(get: { day != nil }, set: { if !$0 { day = nil } })) { _ in dayDetail }
            .onChange(of: pick) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self) { photo = avatarPhoto(data) }
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
            HStack {
                stat("\(activities.count)", "Check-ins")
                stat("\(activeDays)", "Dias ativos")
                stat(hoursText(totalMinutes), "Duração")
            }
            .padding(.top, 4)
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
            HStack(spacing: 0) {
                pill("medal", "Recordes") { ExerciseStatsList(sessions: sessions.reversed()) }
                pill("bolt", "Estatísticas") { ProfileStatsView() }
                pill("target", "Metas") { GoalsView() }
            }
            .padding(6)
            .background(Theme.card, in: .capsule)

            calendar

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
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: month))!
        let count = cal.range(of: .day, in: .month, for: start)!.count
        let lead = (cal.component(.weekday, from: start) + 6) % 7
        let cells: [Date?] = Array(repeating: nil, count: lead) + (0..<count).map { cal.date(byAdding: .day, value: $0, to: start) }
        let byDay = Dictionary(grouping: activities) { cal.startOfDay(for: $0.date) }
        let photos = photosByActivity
        let isCurrent = cal.isDate(start, equalTo: .now, toGranularity: .month)

        return VStack(spacing: 12) {
            HStack {
                GMIconButton(icon: "chevron.left", size: 34) { shift(-1) }
                Spacer()
                Text(monthTitle(start)).font(.title3.weight(.heavy))
                Spacer()
                GMIconButton(icon: "chevron.right", size: 34, tint: isCurrent ? Theme.dim : .white) { if !isCurrent { shift(1) } }
            }
            HStack {
                ForEach(["Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb"], id: \.self) {
                    Text($0).font(.caption).foregroundStyle(Theme.dim).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 8) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, d in
                    if let d {
                        let items = byDay[cal.startOfDay(for: d)] ?? []
                        dayCell(d, items: items, photos: items.compactMap { photos[$0.uuid] })
                    } else {
                        Color.clear.frame(height: 48)
                    }
                }
            }
            .padding(10)
            .background(Theme.card, in: .rect(cornerRadius: 20))
        }
    }

    /// Foto do check-in de cada atividade (a primeira, se foi postada em várias ligas)
    private var photosByActivity: [UUID: Data] {
        var out: [UUID: Data] = [:]
        for c in checkIns { if let p = c.photo, out[c.activityUUID] == nil { out[c.activityUUID] = p } }
        return out
    }

    private func dayCell(_ d: Date, items: [Activity], photos: [Data]) -> some View {
        let today = Calendar.current.isDateInToday(d)
        return Button {
            if !items.isEmpty { day = d }
        } label: {
            ZStack {
                if let first = photos.first, let img = UIImage(data: first) {
                    Image(uiImage: img).resizable().scaledToFill().frame(width: 42, height: 42).clipShape(.circle)
                    if photos.count > 1, let img2 = UIImage(data: photos[1]) {
                        Image(uiImage: img2).resizable().scaledToFill().frame(width: 26, height: 26).clipShape(.circle)
                            .overlay(Circle().stroke(Theme.card, lineWidth: 2))
                            .offset(x: 14, y: 14)
                    }
                } else if let a = items.first {
                    Circle().fill(Theme.accent.opacity(0.9)).frame(width: 42, height: 42)
                    Image(systemName: a.kind.symbol).font(.subheadline.bold()).foregroundStyle(.black)
                    if items.count > 1 {
                        Text("\(items.count)").font(.system(size: 10, weight: .heavy)).foregroundStyle(.black)
                            .frame(width: 18, height: 18).background(.white, in: .circle).offset(x: 15, y: -15)
                    }
                } else {
                    Text("\(Calendar.current.component(.day, from: d))")
                        .font(.body.weight(today ? .heavy : .regular).monospacedDigit())
                        .foregroundStyle(today ? Theme.accent : .white)
                }
            }
            .frame(height: 48)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(GMPress())
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
                        .clipShape(.rect(cornerRadius: 14))
                }
            }
        }
    }

    private func shift(_ n: Int) {
        withAnimation(.snappy) { month = Calendar.current.date(byAdding: .month, value: n, to: month) ?? month }
    }

    private func monthTitle(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = GMDateText.locale
        f.dateFormat = "MMMM 'de' yyyy"
        return f.string(from: d).capitalizedFirst
    }

    // MARK: Público

    private var publicPart: some View {
        let r = roster
        let s = r.mainSnapshot
        let best = Achievements.evaluate(.init(activities: activities.map(\.record),
                                               fromHealth: activities.filter { $0.healthUUID != nil }.count,
                                               snapshot: Game.snapshot(activities.map(\.record)), sessions: sessions.map(\.log),
                                               species: Set(r.snapshots.values.filter { $0.stage > .egg }.map(\.form.species)).count,
                                               ultimates: r.snapshots.values.filter { $0.stage == .ultimate }.count,
                                               discovered: discovered.split(separator: ",").count, dexTotal: DexView.allForms.count))
            .filter(\.unlocked)
        return VStack(spacing: 18) {
            GMSection("Como seus amigos te veem") {
                HStack(spacing: 12) {
                    Avatar(size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name.isEmpty ? "Treinador" : name).font(.headline)
                        if !username.isEmpty { Text("@\(username)").font(.caption).foregroundStyle(Theme.dim) }
                        if !bio.isEmpty { Text(bio).font(.caption) }
                    }
                }
                if showMonster {
                    GMDivider()
                    HStack(spacing: 12) {
                        LivingMonster(form: s.form, progress: s.progress).frame(width: 60, height: 60)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.main?.displayName(s.form) ?? s.form.name).font(.subheadline.bold())
                            Text(s.stage == .egg ? "Ovo" : "\(s.form.speciesInfo.name) · \(s.stage.name) · Nível \(s.level)")
                                .font(.caption).foregroundStyle(Theme.dim)
                        }
                    }
                }
                if showStats {
                    GMDivider()
                    HStack {
                        stat("\(activities.count)", "Check-ins")
                        stat("\(activeDays)", "Dias ativos")
                        stat("\(leagues.count)", "Ligas")
                    }
                }
                if showAchievements && !best.isEmpty {
                    GMDivider()
                    Text("Conquistas · \(best.count)").font(.caption.bold()).foregroundStyle(Theme.dim)
                    GMFlow {
                        ForEach(best.prefix(6)) { a in
                            Label(a.title, systemImage: a.symbol)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Color.yellow.opacity(0.15), in: .capsule)
                                .foregroundStyle(.yellow)
                        }
                    }
                }
            }

            GMSection("Perfil público") {
                GMTextField(placeholder: "Seu nome", text: $name, capitalization: .words)
                GMTextField(placeholder: "@usuário", text: Binding(
                    get: { username },
                    set: { username = $0.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." } }
                ), capitalization: .never)
                GMTextField(placeholder: "Bio (ex.: Rato de academia desde 2019)", text: $bio, axis: .vertical)
            }

            GMSection("O que aparece para os outros",
                      footer: "Quando as ligas tiverem servidor, é isso que seus amigos vão ver. Peso, medidas, notas e o histórico detalhado ficam sempre privados.") {
                GMToggle(title: "Monstro principal", isOn: $showMonster)
                GMDivider()
                GMToggle(title: "Números (check-ins, dias, ligas)", isOn: $showStats)
                GMDivider()
                GMToggle(title: "Conquistas", isOn: $showAchievements)
            }
        }
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
        let s = Game.snapshot(activities.map(\.record))
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
                        RoundedRectangle(cornerRadius: 3)
                            .fill(day > .now ? Color.clear : m == 0 ? Theme.raised : Theme.accent.opacity(min(0.3 + Double(m) / 120, 1)))
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
    }
}

// MARK: - Metas

struct GoalsView: View {
    @Query(sort: \Activity.date) private var activities: [Activity]
    @Query(sort: \BodyEntry.date, order: .reverse) private var body_: [BodyEntry]
    @AppStorage("goalWeekly") private var weekly = 4
    @AppStorage("goalMinutes") private var minutesGoal = 180
    @AppStorage("goalWeight") private var weightGoal = 0.0

    var body: some View {
        let week = Calendar.current.dateInterval(of: .weekOfYear, for: .now)!
        let thisWeek = activities.filter { week.contains($0.date) }
        let minutes = thisWeek.reduce(0) { $0 + $1.minutes }
        let weight = body_.compactMap(\.weight).first

        GMScreen("Metas", back: true) {
            GMSection("Treinos na semana") {
                ring(Double(thisWeek.count) / Double(weekly), "\(thisWeek.count)/\(weekly)", "treinos")
                GMStepper(title: "Meta", value: $weekly, range: 1...14, format: { "\($0)×" })
            }
            GMSection("Tempo na semana") {
                ring(Double(minutes) / Double(minutesGoal), hoursText(minutes), "de \(hoursText(minutesGoal))")
                GMStepper(title: "Meta", value: $minutesGoal, range: 30...1200, step: 30, format: hoursText)
            }
            GMSection("Peso", footer: "Use Peso e medidas para registrar ou importar do Apple Saúde.") {
                GMDecimalField(title: "Peso alvo", value: Binding(get: { weightGoal > 0 ? weightGoal : nil }, set: { weightGoal = $0 ?? 0 }),
                               step: 0.5, start: weight ?? 70)
                if let weight, weightGoal > 0 {
                    let diff = ((weight - weightGoal) * 10).rounded() / 10
                    Text(diff == 0 ? "Você chegou no peso alvo! 🎯" : "Atual \(Progression.fmt(weight)) kg · faltam \(Progression.fmt(abs(diff))) kg para \(diff > 0 ? "perder" : "ganhar")")
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
    }

    private func ring(_ value: Double, _ big: String, _ small: String) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(Theme.raised, lineWidth: 10)
                Circle().trim(from: 0, to: min(value, 1))
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if value >= 1 { Image(systemName: "checkmark").font(.title2.bold()).foregroundStyle(Theme.accent) }
            }
            .frame(width: 76, height: 76)
            VStack(alignment: .leading, spacing: 2) {
                Text(big).font(.title2.weight(.heavy).monospacedDigit())
                Text(small).font(.caption).foregroundStyle(Theme.dim)
            }
            Spacer()
        }
    }
}
