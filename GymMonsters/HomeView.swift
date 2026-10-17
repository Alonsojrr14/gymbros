import SwiftData
import SwiftUI

struct HomeView: View {
    let snapshot: Snapshot
    let activities: [Activity]
    let mood: Mood
    let line: String
    let monsterName: String
    var onDex: () -> Void = {}
    @AppStorage("trainerName") private var trainerName = ""
    @State private var team = false
    @State private var logging = false
    @State private var settings = false

    var body: some View {
        NavigationStack {
            GMScreen("Olá, \(trainerName)", avatar: true) {
                HStack(spacing: 8) {
                    if snapshot.streak > 0 {
                        Label("\(snapshot.streak)", systemImage: "flame.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .background(Theme.raised, in: .capsule)
                    }
                    GMIconButton(icon: "square.grid.3x3.fill") { onDex() }
                    GMIconButton(icon: "square.stack.3d.up") { team = true }
                    GMIconButton(icon: "gearshape") { settings = true }
                }
            } content: {
                monsterCard
                if snapshot.stage != .egg { attributesCard }
                GMButton("Registrar atividade", icon: "plus.circle.fill") { logging = true }
                if !activities.isEmpty { recentCard }
            }
            .gmModal(isPresented: $logging) { LogActivityView(snapshot: snapshot) }
            .gmModal(isPresented: $settings) { SettingsView() }
            .gmModal(isPresented: $team) { TeamView() }
        }
    }

    private var monsterCard: some View {
        VStack(spacing: 14) {
            SpeechBubble(text: line, emoji: mood.emoji)
            LivingMonster(form: snapshot.form, progress: snapshot.progress)
                // Triste ou entediado, o monstro perde a cor
                .saturation(mood == .triste ? 0.35 : mood == .entediado ? 0.7 : 1)
                .frame(height: 200)

            VStack(spacing: 4) {
                Text(monsterName)
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                HStack(spacing: 8) {
                    Text(snapshot.stage.name)
                    if let a = snapshot.form.attribute {
                        Text("·")
                        Label(a.name, systemImage: a.symbol).foregroundStyle(a.color)
                    }
                    if snapshot.stage != .egg {
                        Text("·")
                        Text("Nível \(snapshot.level)")
                        Text("·")
                        Text(mood.name)
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.dim)
            }

            VStack(alignment: .leading, spacing: 6) {
                GMProgressBar(value: snapshot.progress)
                HStack {
                    Text("\(snapshot.totalXP) XP")
                    Spacer()
                    if let left = snapshot.xpToNext {
                        Text(snapshot.stage == .egg ? "faltam \(left) XP para chocar" : "faltam \(left) XP para evoluir")
                    } else {
                        Text("forma final")
                    }
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.dim)
            }
            .padding(.horizontal, 4)

            if snapshot.stage == .egg {
                Text(snapshot.totalXP == 0
                     ? "Registre seu primeiro treino para aquecer o ovo."
                     : "Ele está se mexendo… continue treinando!")
                    .font(.footnote)
                    .foregroundStyle(Theme.dim)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: .rect(cornerRadius: 22))
    }

    private var attributesCard: some View {
        let attrs = snapshot.stageAttributes
        let maxValue = max(attrs.values.max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Treinos desta fase").font(.headline)
                Spacer()
                if let next = snapshot.nextForm, next.stage.branches, !attrs.isEmpty {
                    HStack(spacing: 4) {
                        Text("tende a virar")
                        Text(next.name).bold().foregroundStyle(next.attribute?.color ?? .white)
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.dim)
                }
            }
            ForEach(Attribute.allCases) { a in
                HStack(spacing: 10) {
                    Image(systemName: a.symbol).foregroundStyle(a.color).frame(width: 20)
                    Text(a.name).font(.subheadline).frame(width: 96, alignment: .leading)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.08))
                            Capsule().fill(a.color)
                                .frame(width: g.size.width * (attrs[a] ?? 0) / maxValue)
                        }
                    }
                    .frame(height: 8)
                    Text("\(Int(attrs[a] ?? 0))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.dim)
                        .frame(width: 34, alignment: .trailing)
                }
            }
            Text(snapshot.nextForm?.stage.branches == true
                 ? "O atributo que você mais treinar até a próxima evolução decide a forma."
                 : "Cada atividade soma em atributos diferentes.")
                .font(.caption)
                .foregroundStyle(Theme.dim)
        }
        .padding(18)
        .background(Theme.card, in: .rect(cornerRadius: 22))
    }

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Últimas atividades").font(.headline)
            ForEach(activities.prefix(3)) { a in
                NavigationLink { ActivityDetailView(activity: a, snapshot: snapshot) } label: {
                    ActivityRow(activity: a, xp: snapshot.xpByActivity[a.uuid] ?? 0).contentShape(Rectangle())
                }
                .buttonStyle(GMPress())
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: 22))
    }
}

struct ActivityRow: View {
    let activity: Activity
    let xp: Int
    @Query private var posts: [LeagueCheckIn]
    @Query private var leagues: [League]

    init(activity: Activity, xp: Int) {
        self.activity = activity
        self.xp = xp
        let id = activity.uuid
        _posts = Query(filter: #Predicate<LeagueCheckIn> { $0.activityUUID == id })
    }

    /// Onde a atividade foi postada (perfil e ligas)
    private var destinations: String? {
        guard !posts.isEmpty else { return nil }
        let ids = Set(posts.map(\.leagueUUID))
        var out: [String] = []
        if ids.contains(ProfileFeed.id) { out.append("👤 Perfil") }
        out += leagues.filter { ids.contains($0.uuid) }.map { "\($0.emoji) \($0.name)" }
        let place = posts.compactMap(\.place).first
        return out.joined(separator: " · ") + (place.map { " · 📍 \($0)" } ?? "")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: activity.kind.symbol)
                .font(.title3)
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.07), in: .rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.kind.name).font(.subheadline.weight(.semibold))
                Text("\(durationText(activity.minutes)) · \(effortLabel(activity.effort)) · \(activity.date.formatted(.dateTime.day().month(.abbreviated)))")
                    .font(.caption)
                    .foregroundStyle(Theme.dim)
                if let destinations {
                    Text(destinations).font(.caption2.weight(.semibold)).foregroundStyle(Theme.accent).lineLimit(1)
                }
            }
            Spacer()
            if activity.healthUUID != nil {
                Image(systemName: "heart.fill").font(.caption2).foregroundStyle(.pink)
            }
            Text("+\(xp) XP")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(Theme.accent)
        }
    }
}

struct SpeechBubble: View {
    let text: String
    let emoji: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(emoji).font(.title3)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.white.opacity(0.07), in: .rect(cornerRadius: 14))
        .overlay(alignment: .bottom) {
            // Pontinha do balão apontando para o monstro
            Triangle().fill(.white.opacity(0.07)).frame(width: 16, height: 8).offset(y: 8)
        }
        .padding(.bottom, 4)
        .contentTransition(.opacity)
        .animation(.default, value: text)
    }
}

private struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
            p.closeSubpath()
        }
    }
}
