import PhotosUI
import SwiftData
import SwiftUI

/// Detalhe de uma atividade: dados, onde foi publicada (perfil e ligas) e ações
struct ActivityDetailView: View {
    let activity: Activity
    let snapshot: Snapshot
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var posts: [LeagueCheckIn]
    @Query(sort: \League.joinedAt) private var leagues: [League]
    @Query private var routes: [RouteRecord]
    @AppStorage("trainerName") private var trainerName = ""
    @State private var editing = false
    @State private var confirmDelete = false
    @State private var opened: FeedItem?
    @State private var showRoute = false
    @State private var storyPick: PhotosPickerItem?
    @Query private var sessions: [WorkoutSession]

    init(activity: Activity, snapshot: Snapshot) {
        self.activity = activity
        self.snapshot = snapshot
        let id = activity.uuid
        _posts = Query(filter: #Predicate<LeagueCheckIn> { $0.activityUUID == id })
        _routes = Query(filter: #Predicate<RouteRecord> { $0.activityUUID == id })
        _sessions = Query(filter: #Predicate<WorkoutSession> { $0.activityUUID == id })
    }

    private var photo: Data? { posts.compactMap(\.photo).first }
    private var place: String? { posts.compactMap(\.place).first ?? GymLocation.shared.gym(activity.gymUUID)?.name }
    private var title: String { posts.first?.title ?? (activity.note.isEmpty ? activity.typeName : activity.note) }

    var body: some View {
        GMScreen(activity.typeName, back: true) {
            GMIconButton(icon: "pencil", label: "Editar atividade") { editing = true }
        } content: {
            if let data = photo, let img = UIImage(data: data) {
                Color.clear
                    .frame(height: 260)
                    .overlay { Image(uiImage: img).resizable().scaledToFill().allowsHitTesting(false) }
                    .clipShape(.rect(cornerRadius: Theme.radius))
            }
            GMCard {
                HStack(spacing: 12) {
                    Image(systemName: activity.typeSymbol)
                        .font(.title2)
                        .frame(width: 48, height: 48)
                        .background(Theme.raised, in: .rect(cornerRadius: Theme.radiusM))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.headline)
                        Text(activity.date.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()))
                            .font(.caption).foregroundStyle(Theme.dim)
                    }
                    Spacer()
                    Text("+\(snapshot.xpByActivity[activity.uuid] ?? 0) XP").font(.headline.monospacedDigit()).foregroundStyle(Theme.accent)
                }
                GMDivider()
                GMValueRow(label: "Duração", value: durationText(activity.minutes))
                GMValueRow(label: "Esforço", value: "\(activity.effort)/10 · \(effortLabel(activity.effort))")
                if let place { GMValueRow(label: "Local", value: place) }
                if activity.healthUUID != nil { GMValueRow(label: "Origem", value: "Apple Saúde") }
                if let r = routes.first {
                    GMDivider()
                    Button { showRoute = true } label: {
                        HStack {
                            RouteMap(coords: r.coordinates).frame(width: 56, height: 56).clipShape(.rect(cornerRadius: Theme.radiusS))
                            Text("Ver percurso · \(kmText(r.meters))").font(.subheadline.weight(.semibold))
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.dim)
                        }
                        .contentShape(Rectangle())
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(GMPress())
                }
                if let n = posts.first?.note, !n.isEmpty {
                    GMDivider()
                    Text(n).font(.subheadline)
                }
            }

            GMSection("Publicado em", footer: posts.isEmpty ? "Ainda não foi postada. Toque no lápis para postar no perfil ou numa liga." : "Toque para abrir o post.") {
                let sorted = posts.sorted { order($0) < order($1) }
                if sorted.isEmpty {
                    Text("Nenhum destino").font(.subheadline).foregroundStyle(Theme.dim)
                }
                ForEach(sorted) { c in
                    Button { opened = item(c) } label: { destinationRow(c) }
                        .buttonStyle(GMPress())
                    if c.id != sorted.last?.id { GMDivider() }
                }
            }

            if let s = sessions.first {
                GMSection("Treino") {
                    NavigationLink { SessionDetailView(session: s) } label: {
                        GMRow(icon: "list.bullet.rectangle", title: "Ver séries", subtitle: "\(s.sets.filter { $0.done && !$0.warmup }.count) séries · \(s.exerciseIDs.count) exercícios", chevron: true)
                    }
                    .buttonStyle(GMPress())
                    GMDivider()
                    GMRow(icon: "square.and.arrow.up", iconTint: Theme.accent, title: "Compartilhar nos Stories",
                          subtitle: photo == nil ? "Arte com o treino, o bro e os recordes" : "Arte com a foto do check-in") {
                        shareWorkoutStory(s, context: context)
                    }
                    GMDivider()
                    PhotosPicker(selection: $storyPick, matching: .images) {
                        GMRow(icon: "photo.on.rectangle", title: "Stories com outra foto", chevron: true)
                    }
                    .buttonStyle(GMPress())
                    .onChange(of: storyPick) { _, item in
                        Task {
                            if let data = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                                shareWorkoutStory(s, context: context, photo: img)
                            }
                            storyPick = nil
                        }
                    }
                }
            }
            if sessions.isEmpty {
                GMSection("Compartilhar") {
                    GMRow(icon: "square.and.arrow.up", iconTint: Theme.accent, title: "Compartilhar nos Stories",
                          subtitle: routes.isEmpty ? "Arte com a atividade e as calorias" : "Arte com distância, pace e o trajeto") {
                        shareActivityStory(activity, context: context)
                    }
                    GMDivider()
                    PhotosPicker(selection: $storyPick, matching: .images) {
                        GMRow(icon: "photo.on.rectangle", title: "Stories com outra foto", chevron: true)
                    }
                    .buttonStyle(GMPress())
                    .onChange(of: storyPick) { _, item in
                        Task {
                            if let data = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                                shareActivityStory(activity, context: context, photo: img)
                            }
                            storyPick = nil
                        }
                    }
                }
            }
            GMButton("Apagar atividade", icon: "trash", kind: .secondary) { confirmDelete = true }
        }
        .gmModal(isPresented: $editing) { LogActivityView(snapshot: snapshot, editing: activity) }
        .gmModal(item: $opened) { CheckInDetailView(item: $0) }
        .gmSheet(isPresented: $showRoute) { _ in
            if let r = routes.first {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(r.kind.name) · \(kmText(r.meters))").font(.headline)
                    RouteMap(coords: r.coordinates).frame(height: 280).clipShape(.rect(cornerRadius: Theme.radiusL))
                    Text("\(clock(r.seconds)) · \(paceText(kind: r.kind, meters: r.meters, seconds: r.seconds))")
                        .font(.subheadline.monospacedDigit()).foregroundStyle(Theme.dim)
                }
            }
        }
        .gmActions(isPresented: $confirmDelete, title: "Apagar atividade?",
                   message: "Os check-ins dela no perfil e nas ligas também somem.", actions: [
            GMAction("Apagar", icon: "trash", destructive: true) {
                // Sai da tela antes de apagar, para ela não ler uma atividade que já não existe
                let a = activity, ctx = context
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { deleteActivity(a, context: ctx) }
            }
        ])
    }

    /// Perfil primeiro, depois as ligas na ordem em que você entrou
    private func order(_ c: LeagueCheckIn) -> Int {
        c.leagueUUID == ProfileFeed.id ? -1 : (leagues.firstIndex { $0.uuid == c.leagueUUID } ?? 999)
    }

    private func destinationRow(_ c: LeagueCheckIn) -> some View {
        let league = leagues.first { $0.uuid == c.leagueUUID }
        let isProfile = c.leagueUUID == ProfileFeed.id
        return HStack(spacing: 12) {
            if isProfile {
                Avatar(size: 40)
            } else {
                Text(league?.emoji ?? "🏆").font(.title2).frame(width: 40, height: 40).background(Theme.raised, in: .circle)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(isProfile ? "Meu perfil" : league?.name ?? "Liga removida").font(.subheadline.weight(.semibold))
                Text(isProfile ? "Visível no seu perfil público" : league.map { l in
                    l.isOver ? "Liga encerrada" : "+" + l.scoring.format(l.score(activity.scoreInput, hasPhoto: c.hasPhoto))
                } ?? "")
                    .font(.caption).foregroundStyle(Theme.dim)
            }
            Spacer()
            if c.photo != nil { Image(systemName: "photo").foregroundStyle(Theme.dim) }
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.dim)
        }
        .contentShape(Rectangle())
        .foregroundStyle(.white)
    }

    private func item(_ c: LeagueCheckIn) -> FeedItem {
        let league = leagues.first { $0.uuid == c.leagueUUID }
        let score = league?.score(activity.scoreInput, hasPhoto: c.hasPhoto)
            ?? Game.xp(kind: activity.kind, minutes: activity.minutes, effort: activity.effort)
        return FeedItem(id: c.uuid.uuidString, memberID: "me", name: trainerName, avatar: snapshot.form, isMe: true, date: c.date,
                        title: c.title, note: c.note, kind: activity.kind, minutes: activity.minutes, score: score, photo: c.photo, place: c.place,
                        hasPhoto: c.hasPhoto, effort: activity.effort, scoring: league?.scoring)
    }
}

/// Apaga a atividade e tudo ligado a ela (treino guiado, check-ins e seus comentários, percurso, resultado de WOD)
@MainActor
func deleteActivity(_ a: Activity, context: ModelContext) {
    let id = a.uuid
    let linked = (try? context.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.activityUUID == id }))) ?? []
    linked.forEach(context.delete)
    if let h = a.healthUUID { HealthSync.ignored.insert(h) }
    HealthSync.deleteWritten(a.healthWrittenUUID)
    let posts = (try? context.fetch(FetchDescriptor<LeagueCheckIn>(predicate: #Predicate { $0.activityUUID == id }))) ?? []
    let postIDs = Set(posts.map(\.uuid.uuidString))
    if !postIDs.isEmpty {
        ((try? context.fetch(FetchDescriptor<CheckInComment>())) ?? []).filter { postIDs.contains($0.itemID) }.forEach(context.delete)
    }
    posts.forEach(LeagueOutbox.retract)
    posts.forEach(context.delete)
    let wods = (try? context.fetch(FetchDescriptor<WodResult>(predicate: #Predicate { $0.activityUUID == id }))) ?? []
    wods.forEach(context.delete)
    let route = (try? context.fetch(FetchDescriptor<RouteRecord>(predicate: #Predicate { $0.activityUUID == id }))) ?? []
    route.forEach(context.delete)
    context.delete(a)
    try? context.save()
    ActivitySplits.set(nil, for: id)
}
