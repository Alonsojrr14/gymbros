import SwiftUI

struct HomeView: View {
    let snapshot: Snapshot
    let activities: [Activity]
    @AppStorage("trainerName") private var trainerName = ""
    @AppStorage("monsterNick") private var monsterNick = ""
    @State private var logging = false
    @State private var settings = false

    private var monsterName: String {
        snapshot.stage == .egg || monsterNick.isEmpty ? snapshot.form.name : monsterNick
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    monsterCard
                    if snapshot.stage != .egg { attributesCard }
                    Button { logging = true } label: {
                        Label("Registrar atividade", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Theme.accent, in: .rect(cornerRadius: 16))
                            .foregroundStyle(.black)
                    }
                    if !activities.isEmpty { recentCard }
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("Olá, \(trainerName)")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if snapshot.streak > 0 {
                        Label("\(snapshot.streak)", systemImage: "flame.fill")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.orange)
                            .font(.subheadline.bold())
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { settings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $logging) { LogActivityView(snapshot: snapshot) }
            .sheet(isPresented: $settings) { SettingsView() }
        }
    }

    private var monsterCard: some View {
        VStack(spacing: 14) {
            LivingMonster(form: snapshot.form, progress: snapshot.progress)
                .frame(height: 200)
                .padding(.top, 8)

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
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.dim)
            }

            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: snapshot.progress)
                    .tint(Theme.accent)
                    .scaleEffect(y: 1.6)
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
                ActivityRow(activity: a, xp: snapshot.xpByActivity[a.uuid] ?? 0)
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
