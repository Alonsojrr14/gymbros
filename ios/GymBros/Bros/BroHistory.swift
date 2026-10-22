import SwiftData
import SwiftUI

/// Na Box, embaixo do bro selecionado: o que ele já viveu com você. Números, evoluções, os treinos que deram XP
/// para ele (inclusive os apagados, que continuam valendo) e os X1 em que ele lutou.
struct BroHistory: View {
    let monster: Monster
    let snapshot: Snapshot
    let records: [ActivityRecord]
    /// Atividades que ainda existem, para abrir o detalhe
    let activities: [UUID: Activity]
    @State private var showAll = false
    @State private var duels = DuelStore.shared

    var body: some View {
        let workouts = records.sorted { $0.date > $1.date }
        let retired = Set(RetiredActivities.all().map(\.id))
        let fights = duels.records(of: monster.uuid)
        let open = duels.openDuels(of: monster.uuid)
        let t = Duels.tally(fights)
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                if snapshot.inherited.isEmpty {
                    stat("\(snapshot.totalXP.formatted())", "XP total", Theme.accent)
                } else {
                    stat("\(snapshot.myXP.formatted())", "seu XP", Theme.accent)
                    stat("\(snapshot.inheritedXP.formatted())", "XP herdado", Theme.dim)
                }
                stat("\(workouts.count)", workouts.count == 1 ? "treino" : "treinos", Attribute.resistencia.color)
                stat(fights.isEmpty ? "–" : "\(t.v)-\(t.e)-\(t.d)", "X1 (V-E-D)", Theme.trophy)
            }
            if !snapshot.inherited.isEmpty { xpOrigin }
            if snapshot.evolutions.count > 0 { evolutions }
            if !workouts.isEmpty {
                GMSection("Treinos com ele", footer: retired.isDisjoint(with: workouts.map(\.id)) ? nil
                          : "Treinos apagados saem da sua lista, mas o XP continua com o bro.") {
                    let shown = showAll ? workouts : Array(workouts.prefix(5))
                    ForEach(shown) { r in
                        workoutRow(r, xp: snapshot.xpByActivity[r.id] ?? 0, retired: retired.contains(r.id))
                        if r.id != shown.last?.id { GMDivider() }
                    }
                    if workouts.count > 5 {
                        Button { withAnimation(.snappy) { showAll.toggle() } } label: {
                            Text(showAll ? "Mostrar menos" : "Ver todos (\(workouts.count))").font(.caption.bold()).foregroundStyle(Theme.accent)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(GMPress())
                    }
                }
            }
            if !fights.isEmpty || !open.isEmpty {
                GMSection("X1 que ele lutou") {
                    ForEach(open) { d in
                        HStack(spacing: 12) {
                            GMBadge(text: d.acceptedAt == nil ? "…" : "AO VIVO", tint: Theme.trophy)
                            MonsterSprite(form: d.opponent(of: "me").form).frame(width: 32, height: 32)
                            Text(d.acceptedAt == nil ? "Esperando \(d.opponent(of: "me").name)" : "Contra \(d.opponent(of: "me").name) agora")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                        }
                        GMDivider()
                    }
                    ForEach(fights.prefix(10)) { r in
                        DuelRecordRow(record: r)
                        if r.id != fights.prefix(10).last?.id { GMDivider() }
                    }
                }
            }
            if workouts.isEmpty && fights.isEmpty && open.isEmpty {
                Text("Ainda sem treinos com este bro. Registre um treino com ele como principal ou numa liga que ele representa.")
                    .font(.caption).foregroundStyle(Theme.dim)
            }
        }
    }

    private func stat(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).gmFont(20, weight: .heavy, design: .rounded, mono: true, relativeTo: .title3).foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption2).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Theme.card, in: .rect(cornerRadius: Theme.radiusL))
        .accessibilityElement(children: .combine)
    }

    /// De quem é o XP: barra dividida por dono (os anteriores em tons de cinza, você em verde) e a lista.
    /// Com muitos donos anteriores, os 3 mais recentes e o resto somado.
    private var xpOrigin: some View {
        let total = max(snapshot.totalXP, 1)
        var owners = snapshot.inherited
        if owners.count > 3 {
            let older = owners.dropLast(3)
            owners = [OwnerXP(name: "\(older.count) donos antes", xp: older.reduce(0) { $0 + $1.xp })] + owners.suffix(3)
        }
        let rows = owners.map { (name: "Com \($0.name)", xp: $0.xp, mine: false) } + [(name: "Com você", xp: snapshot.myXP, mine: true)]
        return GMSection("De onde vem o XP", footer: "O XP de antes da troca é de quem treinou o \(snapshot.form.name). Os seus números contam só o que ele ganhou com você.") {
            GeometryReader { g in
                HStack(spacing: 2) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                        Capsule()
                            .fill(r.mine ? Theme.accent : Color.white.opacity(0.18 + 0.12 * Double(i % 3)))
                            .frame(width: max(r.xp > 0 ? 4 : 0, (g.size.width - CGFloat(rows.count - 1) * 2) * CGFloat(r.xp) / CGFloat(total)))
                    }
                }
            }
            .frame(height: 8)
            ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                HStack(spacing: 8) {
                    Circle().fill(r.mine ? Theme.accent : Color.white.opacity(0.18 + 0.12 * Double(i % 3))).frame(width: 8, height: 8)
                    Text(r.name).font(.subheadline.weight(r.mine ? .bold : .regular)).lineLimit(1)
                    Spacer()
                    Text("\(r.xp.formatted()) XP").font(.subheadline.monospacedDigit()).foregroundStyle(r.mine ? Theme.accent : Theme.dim)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// Linha do tempo das formas, da mais antiga para a mais nova
    private var evolutions: some View {
        GMSection("Evoluções") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(snapshot.evolutions.enumerated()), id: \.offset) { i, e in
                        if i > 0 {
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.dim)
                        }
                        VStack(spacing: 3) {
                            MonsterSprite(form: e.form).frame(width: 40, height: 40)
                            Text(e.form.name).font(.system(size: 10, weight: .bold)).lineLimit(1)
                            Text(e.date == snapshot.arrivedAt ? "chegou \(e.date.formatted(.dateTime.day().month(.abbreviated)))"
                                 : e.date.formatted(.dateTime.day().month(.abbreviated)))
                                .gmFont(9, mono: true, relativeTo: .caption2)
                                .foregroundStyle(e.date == snapshot.arrivedAt ? Theme.trophy : Theme.dim)
                        }
                        .frame(width: 74)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func workoutRow(_ r: ActivityRecord, xp: Int, retired: Bool) -> some View {
        let row = HStack(spacing: 12) {
            Image(systemName: r.kind.symbol)
                .font(.subheadline.bold())
                .foregroundStyle(retired ? Theme.dim : Theme.accent)
                .frame(width: 34, height: 34)
                .background(Theme.raised, in: .rect(cornerRadius: Theme.radiusS))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(r.kind.name).font(.subheadline.weight(.semibold))
                    if retired { GMBadge(text: "apagado", tint: Theme.dim) }
                }
                Text("\(r.date.formatted(.dateTime.day().month(.abbreviated).hour().minute())) · \(durationText(r.minutes))")
                    .font(.caption).foregroundStyle(Theme.dim)
            }
            Spacer()
            Text("+\(xp) XP").font(.subheadline.bold().monospacedDigit()).foregroundStyle(xp > 0 ? Theme.accent : Theme.dim)
        }
        .foregroundStyle(.white)
        .contentShape(Rectangle())
        if let a = activities[r.id] {
            NavigationLink { ActivityDetailView(activity: a, snapshot: snapshot) } label: { row }.buttonStyle(GMPress())
        } else {
            row
        }
    }
}
