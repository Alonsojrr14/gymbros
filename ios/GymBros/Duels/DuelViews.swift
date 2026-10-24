import SwiftData
import SwiftUI

// MARK: - Tela do X1

/// Todos os seus X1: recebidos, em andamento, enviados e o histórico, com o retrospecto V/E/D
struct DuelsView: View {
    /// Abre já na escolha de quem desafiar
    var startPicking = false
    @State private var store = DuelStore.shared
    @State private var picking = false
    @State private var terms = TermsGate()
    @State private var problem: String?
    @State private var busy = false
    @Query private var leagues: [League]

    var body: some View {
        GMScreen("X1", subtitle: "Desafie um amigo: vence quem fizer mais nas 24 h depois do aceite", close: true, bottomInset: 40) {
            GMIconButton(icon: "plus", label: "Novo X1") { picking = true }
        } content: {
            TimelineView(.periodic(from: .now, by: 30)) { ctx in content(now: ctx.date) }
        }
        .task {
            if startPicking {
                try? await Task.sleep(for: .milliseconds(450))
                picking = true
            }
            while !Task.isCancelled {
                await store.refresh()
                try? await Task.sleep(for: .seconds(Duels.refreshInterval(store.duels, now: .now)))
            }
        }
        // Uma folha só: escolher a pessoa e, no mesmo lugar, a métrica (com voltar)
        .gmSheet(isPresented: $picking) { close in
            DuelChallengeFlow(friends: candidates.friends, others: candidates.others) { close() }
        }
        .gmActions(isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } }), title: "X1", message: problem, actions: [])
        .termsGate($terms)
    }

    /// X1 só entre amigos
    private var candidates: (friends: [DuelPerson], others: [DuelPerson]) {
        var seen = Set<String>()
        let friends = FriendsStore.shared.friends.filter { seen.insert($0.id).inserted }
            .map { DuelPerson(id: $0.id, name: $0.name, formID: $0.formID) }
        return (friends.sorted { $0.name < $1.name }, [])
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let duels = store.duels
        let incoming = duels.filter { $0.challenged.id == "me" && $0.isPending(now: now) }.sorted { $0.createdAt < $1.createdAt }
        let active = duels.filter { $0.acceptedAt != nil && $0.isOpen(now: now) }
            .sorted { ($0.endsAt ?? .distantFuture) < ($1.endsAt ?? .distantFuture) }
        let sent = duels.filter { $0.challenger.id == "me" && $0.isPending(now: now) }
        let records = store.records(now: now)

        DuelRecordCard(tally: Duels.tally(records), form: store.me().form)

        if let e = store.lastError {
            GMEmptyState(icon: "icloud.slash", title: "X1 indisponível", message: e)
        } else {
            if !incoming.isEmpty {
                label("Te desafiaram", count: incoming.count, tint: Theme.trophy)
                ForEach(incoming) { d in
                    DuelInviteCard(duel: d, now: now, busy: busy) { accept, monster in
                        accept ? send(d, accept: true, monster: monster) : send(d, accept: false, monster: nil)
                    }
                }
            }
            if !active.isEmpty {
                label("Valendo agora", count: active.count, tint: Theme.accent)
                ForEach(active) { d in DuelScoreboard(duel: d, score: store.score(d, now: now), now: now) }
            }
            if !sent.isEmpty {
                GMSection("Esperando resposta") {
                    ForEach(sent) { d in
                        sentRow(d, now: now)
                        if d.id != sent.last?.id { GMDivider() }
                    }
                }
            }
            if incoming.isEmpty && active.isEmpty && sent.isEmpty && store.loaded {
                DuelIdleCard(friends: candidates.friends, me: store.me().form, hasHistory: !records.isEmpty) { picking = true }
            }
        }
        if !records.isEmpty {
            GMSection("Encerrados") {
                ForEach(records.prefix(20)) { r in
                    DuelRecordRow(record: r)
                    if r.id != records.prefix(20).last?.id { GMDivider() }
                }
            }
        }
    }

    private func label(_ text: String, count: Int, tint: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(text.uppercased()).font(.caption.weight(.bold)).foregroundStyle(Theme.dim).tracking(0.6)
            if count > 1 { GMBadge(text: "\(count)", tint: tint) }
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    private func sentRow(_ d: RemoteDuel, now: Date) -> some View {
        HStack(spacing: 12) {
            MonsterSprite(form: d.challenged.form).frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("Aguardando \(d.challenged.name)").font(.subheadline.weight(.semibold))
                Label(d.metric.name, systemImage: d.metric.symbol).font(.caption.bold()).foregroundStyle(d.metric.tint)
                Text("Expira em \(Self.remaining(d.expiresAt, now: now))").font(.caption).foregroundStyle(Theme.dim)
            }
            Spacer()
            ProgressView().tint(Theme.dim)
        }
    }

    private func send(_ d: RemoteDuel, accept: Bool, monster: UUID?) {
        let action = {
            busy = true
            Task {
                defer { busy = false }
                do {
                    try await store.respond(d, accept: accept, monster: monster)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } catch {
                    problem = error.localizedDescription
                }
            }
        }
        if accept { terms.run(action) } else { action() }
    }

    /// "5 h 20 min", "12 min"
    static func remaining(_ end: Date, now: Date) -> String {
        durationText(max(1, Int((end.timeIntervalSince(now) / 60).rounded(.up))))
    }
}

// MARK: - Retrospecto

/// Seu bro e o retrospecto V/E/D, com a barra de aproveitamento
struct DuelRecordCard: View {
    let tally: (v: Int, e: Int, d: Int)
    let form: MonsterForm

    var body: some View {
        let total = tally.v + tally.e + tally.d
        GMCard {
            HStack(spacing: 14) {
                LivingMonster(form: form)
                    .frame(width: 64, height: 64)
                    .frame(width: 76, height: 76)
                    .background(Theme.raised, in: .circle)
                    .overlay(Circle().stroke(Theme.trophy.opacity(0.5), lineWidth: 1.5))
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 0) {
                        number(tally.v, "Vitórias", Theme.accent)
                        number(tally.e, "Empates", .white)
                        number(tally.d, "Derrotas", Theme.danger)
                    }
                    if total > 0 {
                        GeometryReader { g in
                            HStack(spacing: 2) {
                                Capsule().fill(Theme.accent).frame(width: g.size.width * Double(tally.v) / Double(total))
                                Capsule().fill(.white.opacity(0.7)).frame(width: g.size.width * Double(tally.e) / Double(total))
                                Capsule().fill(Theme.danger).frame(width: g.size.width * Double(tally.d) / Double(total))
                            }
                        }
                        .frame(height: 6)
                        Text("\(Int((Double(tally.v) / Double(total) * 100).rounded()))% de vitórias em \(total) X1")
                            .font(.caption).foregroundStyle(Theme.dim)
                    } else {
                        Text("Nenhum X1 encerrado ainda").font(.caption).foregroundStyle(Theme.dim)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func number(_ value: Int, _ label: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(value)").gmFont(26, weight: .heavy, design: .rounded, mono: true, relativeTo: .title).foregroundStyle(tint)
            Text(label).font(.caption2).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Desafio recebido

/// Alguém te desafiou: quem, valendo o quê, quanto tempo falta para responder e os botões.
/// O seu lado começa vazio: você escolhe na Box quem vai lutar antes de aceitar.
struct DuelInviteCard: View {
    let duel: RemoteDuel
    let now: Date
    let busy: Bool
    let answer: (_ accept: Bool, _ monster: UUID?) -> Void
    @State private var fighter: UUID?
    @State private var choosing = false

    var body: some View {
        let left = duel.expiresAt.timeIntervalSince(now) / Duels.window
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill").foregroundStyle(Theme.trophy)
                Text("\(duel.challenger.name) te chamou pro X1").font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Text(duel.createdAt.formatted(.relative(presentation: .named))).font(.caption2).foregroundStyle(Theme.dim)
            }
            DuelVersus(left: (duel.challenger.form, duel.challenger.name), right: chosen.map { ($0.form, $0.name) },
                       tint: duel.metric.tint) { choosing = true }
            HStack(spacing: 10) {
                Image(systemName: duel.metric.symbol)
                    .font(.subheadline.bold())
                    .foregroundStyle(.black)
                    .frame(width: 32, height: 32)
                    .background(duel.metric.tint, in: .rect(cornerRadius: Theme.radiusS))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Vale \(duel.metric.name.lowercased())").font(.subheadline.bold())
                    Text(duel.metric.detail).font(.caption).foregroundStyle(Theme.dim).lineLimit(2)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                GMProgressBar(value: left, tint: left < 0.25 ? Theme.danger : Theme.trophy, height: 6)
                Text("Você tem \(DuelsView.remaining(duel.expiresAt, now: now)) para responder. Aceitou, valem as próximas 24 h.")
                    .font(.caption).foregroundStyle(Theme.dim)
            }
            HStack(spacing: 10) {
                GMButton("Recusar", kind: .secondary, enabled: !busy) { answer(false, nil) }
                if fighter == nil {
                    GMButton("Escolher bro", icon: "square.grid.3x3.fill", enabled: !busy) { choosing = true }
                } else {
                    GMButton("Aceitar X1", icon: "bolt.fill", enabled: !busy) { answer(true, fighter) }
                }
            }
        }
        .padding(16)
        .background {
            ZStack {
                Theme.card
                LinearGradient(colors: [Theme.trophy.opacity(0.14), .clear], startPoint: .top, endPoint: .bottom)
            }
            .clipShape(.rect(cornerRadius: Theme.radius))
        }
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.trophy.opacity(0.45), lineWidth: 1.5))
        .gmSheet(isPresented: $choosing) { close in
            FighterBox(title: "Quem vai lutar contra \(duel.challenger.name)?", selection: fighter) { id in
                withAnimation(.snappy) { fighter = id }
                close()
            }
        }
    }

    /// Bro escolhido, com a forma de agora
    private var chosen: (form: MonsterForm, name: String)? {
        guard let m = DuelStore.shared.fighters().first(where: { $0.uuid == fighter }) else { return nil }
        let form = MonsterForm.byID(m.lastFormID) ?? .egg
        return (form, m.displayName(form))
    }
}

/// Dois bros frente a frente com o VS no meio. Sem o da direita, mostra um slot vazio para escolher (`pick`).
struct DuelVersus: View {
    let left: (MonsterForm, String)
    let right: (MonsterForm, String)?
    var tint: Color = Theme.accent
    var size: CGFloat = 64
    var pick: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            side(left.0, left.1)
            ZStack {
                Circle().fill(Theme.trophy.opacity(0.25)).frame(width: 60, height: 60).blur(radius: 14)
                Text("VS").gmFont(16, weight: .black, design: .rounded, relativeTo: .headline)
                    .foregroundStyle(.black)
                    .frame(width: 42, height: 42)
                    .background(LinearGradient(colors: [Theme.trophy, Theme.streak], startPoint: .topLeading, endPoint: .bottomTrailing), in: .circle)
                    .overlay(Circle().stroke(Theme.card, lineWidth: 3))
            }
            .frame(width: 60)
            if let right {
                if let pick {
                    Button(action: pick) { side(right.0, right.1) }.buttonStyle(GMPress()).accessibilityHint("Trocar o bro")
                } else {
                    side(right.0, right.1)
                }
            } else {
                emptySlot
            }
        }
        .padding(.vertical, 10)
        .background {
            LinearGradient(colors: [tint.opacity(0.16), Theme.raised, Theme.accent.opacity(0.16)], startPoint: .leading, endPoint: .trailing)
                .clipShape(.rect(cornerRadius: Theme.radiusL))
        }
        .accessibilityElement(children: pick == nil ? .ignore : .contain)
        .accessibilityLabel("\(left.1) contra \(right?.1 ?? "seu bro")")
    }

    /// Seu lado ainda sem bro: toque para abrir a Box
    private var emptySlot: some View {
        Button { pick?() } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.trophy)
                    .frame(width: size, height: size)
                    .background(Circle().strokeBorder(Theme.trophy.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
                Text("Escolher bro").font(.subheadline.bold()).foregroundStyle(Theme.trophy).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(GMPress())
        .accessibilityLabel("Escolher o bro que vai lutar")
    }

    private func side(_ form: MonsterForm, _ name: String) -> some View {
        VStack(spacing: 6) {
            LivingMonster(form: form).frame(width: size, height: size)
            Text(name).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Placar ao vivo

/// X1 valendo: os dois lados, a barra de cabo de guerra e o tempo que falta
struct DuelScoreboard: View {
    let duel: RemoteDuel
    let score: DuelScore
    let now: Date

    var body: some View {
        let other = duel.opponent(of: "me")
        let total = score.mine + score.theirs
        let share = total == 0 ? 0.5 : Double(score.mine) / Double(total)
        let left = (duel.endsAt?.timeIntervalSince(now) ?? 0) / Duels.window
        let tint: Color = score.mine > score.theirs ? Theme.accent : score.mine < score.theirs ? Theme.danger : .white
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(duel.metric.name, systemImage: duel.metric.symbol).font(.caption.bold()).foregroundStyle(duel.metric.tint)
                Spacer()
                Label(duel.endsAt.map { "faltam \(DuelsView.remaining($0, now: now))" } ?? "", systemImage: "timer")
                    .font(.caption.bold().monospacedDigit()).foregroundStyle(Theme.dim)
            }
            HStack(spacing: 8) {
                side("Você", DuelStore.shared.myForm(in: duel), score.mine, ahead: score.mine > score.theirs)
                Text("×").font(.title3.bold()).foregroundStyle(Theme.dim)
                side(other.name, other.form, score.theirs, ahead: score.theirs > score.mine)
            }
            GeometryReader { g in
                HStack(spacing: 3) {
                    Capsule().fill(Theme.accent).frame(width: max(6, (g.size.width - 3) * share))
                    Capsule().fill(Theme.danger.opacity(0.8))
                }
            }
            .frame(height: 8)
            .animation(.spring(duration: 0.5), value: share)
            HStack {
                Text(status).font(.caption.bold()).foregroundStyle(tint)
                Spacer()
                GMProgressBar(value: left, tint: Theme.dim, height: 4).frame(width: 80)
            }
        }
        .padding(16)
        .background(Theme.card, in: .rect(cornerRadius: Theme.radius))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(tint.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var status: String {
        let diff = abs(score.mine - score.theirs)
        if diff == 0 { return score.mine == 0 ? "Ninguém pontuou ainda: bora treinar" : "Empatado" }
        return score.mine > score.theirs ? "Você está na frente por \(duel.metric.short(diff))" : "Faltam \(duel.metric.short(diff)) para empatar"
    }

    private func side(_ name: String, _ form: MonsterForm, _ value: Int, ahead: Bool) -> some View {
        VStack(spacing: 4) {
            LivingMonster(form: form).frame(width: 52, height: 52)
            Text(name).font(.caption.bold()).lineLimit(1)
            Text(duel.metric.short(value))
                .gmFont(22, weight: .heavy, design: .rounded, mono: true, relativeTo: .title2)
                .foregroundStyle(ahead ? Theme.accent : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Nenhum X1 agora

/// Sem desafio aberto: seu bro esperando um rival, como funciona, atalhos para amigos e o botão de desafiar
struct DuelIdleCard: View {
    let friends: [DuelPerson]
    let me: MonsterForm
    let hasHistory: Bool
    let challenge: () -> Void
    @State private var target: DuelPerson?

    var body: some View {
        let quick = friends.filter { DuelStore.shared.refusal($0.id) == nil }.prefix(4)
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 0) {
                VStack(spacing: 6) {
                    LivingMonster(form: me).frame(width: 72, height: 72)
                    Text("Você").font(.subheadline.bold())
                }
                .frame(maxWidth: .infinity)
                Text("VS").gmFont(16, weight: .black, design: .rounded, relativeTo: .headline)
                    .foregroundStyle(Theme.dim)
                    .frame(width: 42, height: 42)
                    .overlay(Circle().stroke(Theme.dim.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [4, 4])))
                VStack(spacing: 6) {
                    Image(systemName: "questionmark")
                        .font(.system(size: 30, weight: .black))
                        .foregroundStyle(Theme.dim)
                        .frame(width: 72, height: 72)
                        .background(Circle().strokeBorder(Theme.dim.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
                    Text("Rival").font(.subheadline.bold()).foregroundStyle(Theme.dim)
                }
                .frame(maxWidth: .infinity)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(hasHistory ? "Nenhum X1 rolando agora" : "Seu primeiro X1 te espera").font(.title3.bold())
                Text("Desafie um amigo. Vence quem treinar mais nas 24 h depois do aceite.")
                    .font(.subheadline).foregroundStyle(Theme.dim)
            }
            VStack(alignment: .leading, spacing: 10) {
                step(1, "person.2.fill", "Escolha alguém e o que vale: XP, treinos, minutos, distância ou calorias")
                step(2, "hourglass", "A pessoa tem 24 h para aceitar")
                step(3, "trophy.fill", "Aceitou, valem as 24 h seguintes. Qualquer treino conta, até do Apple Saúde")
            }
            if !quick.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("DESAFIO RÁPIDO").font(.caption.weight(.bold)).foregroundStyle(Theme.dim).tracking(0.6)
                    HStack(spacing: 8) {
                        ForEach(Array(quick)) { f in
                            Button { target = f } label: {
                                VStack(spacing: 4) {
                                    MonsterSprite(form: f.form)
                                        .frame(width: 36, height: 36)
                                        .frame(width: 50, height: 50)
                                        .background(Theme.raised, in: .circle)
                                        .overlay(Circle().stroke(Theme.trophy.opacity(0.6), lineWidth: 1.5))
                                    Text(f.name).font(.caption2.bold()).lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)
                                .foregroundStyle(.white)
                            }
                            .buttonStyle(GMPress())
                            .accessibilityLabel("Desafiar \(f.name)")
                        }
                    }
                }
            }
            GMButton("Desafiar alguém", icon: "bolt.fill", action: challenge)
        }
        .padding(16)
        .background {
            ZStack {
                Theme.card
                RadialGradient(colors: [Theme.trophy.opacity(0.12), .clear], center: .top, startRadius: 10, endRadius: 260)
            }
            .clipShape(.rect(cornerRadius: Theme.radius))
        }
        .gmSheet(isPresented: Binding(get: { target != nil }, set: { if !$0 { target = nil } })) { close in
            if let target { DuelComposer(opponent: target) { close() } }
        }
    }

    private func step(_ n: Int, _ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption.bold())
                .foregroundStyle(Theme.trophy)
                .frame(width: 28, height: 28)
                .background(Theme.trophy.opacity(0.14), in: .circle)
            Text(text).font(.subheadline).foregroundStyle(.white.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Passo \(n): \(text)")
    }
}

// MARK: - Desafiar

/// Escolher a métrica e mandar o desafio para uma pessoa
/// Pessoa e métrica na mesma folha: escolher alguém troca o conteúdo, sem fechar e abrir outra
struct DuelChallengeFlow: View {
    let friends: [DuelPerson]
    let others: [DuelPerson]
    let done: () -> Void
    @State private var target: DuelPerson?

    var body: some View {
        ZStack {
            if let target {
                DuelComposer(opponent: target, back: { withAnimation(.snappy) { self.target = nil } }, done: done)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .trailing).combined(with: .opacity)))
            } else {
                DuelPeoplePicker(friends: friends, others: others) { p in
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.snappy) { target = p }
                }
                .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
            }
        }
        .animation(.snappy, value: target)
    }
}

struct DuelComposer: View {
    let opponent: DuelPerson
    /// Voltar para a lista de pessoas (só quando veio dela)
    var back: (() -> Void)?
    var done: () -> Void = {}
    @State private var metric: DuelMetric = .xp
    /// Bro que vai lutar (ovos ficam de fora)
    @State private var fighter: UUID? = DuelStore.shared.defaultFighter()?.uuid
    @State private var terms = TermsGate()
    @State private var problem: String?
    @State private var busy = false

    var body: some View {
        let refusal = DuelStore.shared.refusal(opponent.id)
        VStack(alignment: .leading, spacing: 16) {
            if let back {
                HStack {
                    Button(action: back) {
                        Label("Trocar pessoa", systemImage: "chevron.left").font(.subheadline.bold()).foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(GMPress())
                    Spacer()
                }
            }
            versus
            if DuelStore.shared.fighters().count > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("QUEM VAI LUTAR?").font(.caption.weight(.bold)).foregroundStyle(Theme.dim).tracking(0.6)
                    FighterPicker(selection: $fighter)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("VALE O QUÊ?").font(.caption.weight(.bold)).foregroundStyle(Theme.dim).tracking(0.6)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(DuelMetric.allCases) { m in metricCard(m) }
                }
            }
            HStack(spacing: 6) {
                rule("hourglass", "24 h para aceitar")
                rule("timer", "Vale 24 h")
                rule("heart.fill", "Saúde conta")
            }
            if let message = problem ?? refusal?.errorDescription {
                Label(message, systemImage: "exclamationmark.triangle.fill").font(.caption.bold()).foregroundStyle(Theme.danger)
            }
            GMButton(busy ? "Enviando…" : "Desafiar \(opponent.name)", icon: "bolt.fill", enabled: refusal == nil && !busy) { send() }
        }
        .termsGate($terms)
    }

    /// Você contra a pessoa, com o raio no meio
    private var versus: some View {
        HStack(spacing: 0) {
            fighterView(DuelStore.shared.person(with: fighter).form, "Você")
            ZStack {
                Circle().fill(Theme.trophy.opacity(0.25)).frame(width: 64, height: 64).blur(radius: 14)
                Text("VS").gmFont(18, weight: .black, design: .rounded, relativeTo: .headline)
                    .foregroundStyle(.black)
                    .frame(width: 46, height: 46)
                    .background(LinearGradient(colors: [Theme.trophy, Theme.streak], startPoint: .topLeading, endPoint: .bottomTrailing), in: .circle)
                    .overlay(Circle().stroke(Theme.card, lineWidth: 3))
            }
            .frame(width: 70)
            fighterView(opponent.form, opponent.name)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                Theme.raised
                LinearGradient(colors: [Theme.accent.opacity(0.18), .clear, metric.tint.opacity(0.18)], startPoint: .leading, endPoint: .trailing)
            }
            .clipShape(.rect(cornerRadius: Theme.radiusL))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("X1: você contra \(opponent.name)")
    }

    private func fighterView(_ form: MonsterForm, _ name: String) -> some View {
        VStack(spacing: 6) {
            MonsterSprite(form: form).frame(width: 64, height: 64)
            Text(name).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private func metricCard(_ m: DuelMetric) -> some View {
        let on = metric == m
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.snappy) { metric = m }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: m.symbol)
                    .font(.subheadline.bold())
                    .foregroundStyle(on ? .black : m.tint)
                    .frame(width: 32, height: 32)
                    .background(on ? m.tint : m.tint.opacity(0.15), in: .rect(cornerRadius: Theme.radiusS))
                VStack(alignment: .leading, spacing: 1) {
                    Text(m.name).font(.subheadline.bold())
                    Text(m.hint).font(.caption2).foregroundStyle(Theme.dim).lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(on ? m.tint.opacity(0.12) : Theme.raised, in: .rect(cornerRadius: Theme.radiusM))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusM).stroke(on ? m.tint : .clear, lineWidth: 1.5))
            .foregroundStyle(.white)
        }
        .buttonStyle(GMPress())
        .accessibilityLabel("\(m.name): \(m.detail)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func rule(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption2.bold())
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Theme.raised, in: .capsule)
            .foregroundStyle(Theme.dim)
    }

    private func send() {
        terms.run {
            busy = true
            Task {
                defer { busy = false }
                do {
                    try await DuelStore.shared.challenge(opponent, metric: metric, monster: fighter)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    done()
                } catch {
                    problem = error.localizedDescription
                }
            }
        }
    }
}

/// Escolher quem desafiar: busca, recentes e amigos (X1 só entre amigos); quem não dá para desafiar vai para o fim
struct DuelPeoplePicker: View {
    let friends: [DuelPerson]
    let others: [DuelPerson]
    let pick: (DuelPerson) -> Void
    @State private var query = ""

    private var store: DuelStore { .shared }

    /// Últimos adversários, mais recentes primeiro
    private var recent: [DuelPerson] {
        var seen = Set<String>()
        let friends = store.friendIDs()
        return store.duels.sorted { $0.createdAt > $1.createdAt }.map { $0.opponent(of: "me") }
            .filter { friends.contains($0.id) && seen.insert($0.id).inserted }.prefix(8).map { $0 }
    }

    private func matches(_ p: DuelPerson) -> Bool {
        query.isEmpty || p.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .contains(query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil))
    }

    var body: some View {
        let block = store.fighterBlock()
        let free = { (list: [DuelPerson]) in list.filter { matches($0) && store.personRefusal($0.id) == nil } }
        let taken = (friends + others).filter { matches($0) && store.personRefusal($0.id) != nil }
        let f = free(friends), o = free(others)
        VStack(alignment: .leading, spacing: 12) {
            Text("Desafiar quem?").font(.headline).frame(maxWidth: .infinity)
            if let block { blockBanner(block) }
            if friends.isEmpty && others.isEmpty {
                GMEmptyState(icon: "person.2", title: "Ninguém por aqui", message: "X1 é só entre amigos. Adicione alguém pelo código de amigo para desafiar.")
            } else {
                GMSearchField(placeholder: "Buscar pelo nome", text: $query)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if query.isEmpty && !recent.isEmpty { recentStrip(enabled: block == nil) }
                        group("Amigos", f, enabled: block == nil)
                        group("Das suas ligas", o, enabled: block == nil)
                        group("Já em X1 com você", taken, enabled: false)
                        if f.isEmpty && o.isEmpty && taken.isEmpty {
                            Text("Ninguém com esse nome.").font(.subheadline).foregroundStyle(Theme.dim).frame(maxWidth: .infinity).padding(.top, 20)
                        }
                    }
                    .padding(.bottom, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .frame(maxHeight: 460)
            }
        }
    }

    /// Você não pode desafiar ninguém agora (só ovos ou todos os bros em X1): um aviso só, no topo
    private func blockBanner(_ r: DuelRefusal) -> some View {
        let busy = r == .allFightersBusy
        let fighters = store.fighters().prefix(3)
        return HStack(spacing: 12) {
            ZStack {
                if busy, !fighters.isEmpty {
                    ForEach(Array(fighters.enumerated()), id: \.offset) { i, m in
                        MonsterSprite(form: MonsterForm.byID(m.lastFormID) ?? .egg)
                            .frame(width: 34, height: 34)
                            .offset(x: CGFloat(i) * 10 - CGFloat(fighters.count - 1) * 5)
                    }
                } else {
                    MonsterSprite(form: .egg).frame(width: 34, height: 34)
                }
            }
            .frame(width: 52, height: 52)
            .background(Theme.trophy.opacity(0.14), in: .circle)
            VStack(alignment: .leading, spacing: 3) {
                Text(busy ? "Seus bros estão em X1" : "Seus bros ainda são ovos").font(.subheadline.bold())
                Text(busy ? "Cada bro luta um X1 por vez. Choque mais ovos para lutar mais." : "Ovos não entram no X1. Treine para chocar um.")
                    .font(.caption).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
                if busy, let at = store.nextFighterFree() {
                    Label("Um bro fica livre em \(DuelsView.remaining(at, now: .now))", systemImage: "timer")
                        .font(.caption.bold()).foregroundStyle(Theme.trophy)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.trophy.opacity(0.08), in: .rect(cornerRadius: Theme.radiusL))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusL).stroke(Theme.trophy.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    /// Revanche: quem você já enfrentou, em bolinhas
    private func recentStrip(enabled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            label("Revanche")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(recent) { p in
                        let taken = store.personRefusal(p.id) != nil
                        let ok = enabled && !taken
                        Button { pick(p) } label: {
                            VStack(spacing: 4) {
                                MonsterSprite(form: p.form)
                                    .frame(width: 40, height: 40)
                                    .frame(width: 54, height: 54)
                                    .background(Theme.raised, in: .circle)
                                    .overlay(Circle().stroke(ok ? Theme.trophy.opacity(0.7) : .clear, lineWidth: 1.5))
                                    .overlay(alignment: .bottomTrailing) {
                                        if taken {
                                            Image(systemName: "bolt.fill").font(.system(size: 9, weight: .black)).foregroundStyle(.black)
                                                .frame(width: 18, height: 18).background(Theme.trophy, in: .circle)
                                        }
                                    }
                                Text(p.name).font(.caption2.bold()).lineLimit(1).frame(width: 60)
                            }
                            .foregroundStyle(.white)
                            .opacity(ok || taken ? 1 : 0.5)
                        }
                        .buttonStyle(GMPress())
                        .disabled(!ok)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ list: [DuelPerson], enabled: Bool) -> some View {
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                label("\(title) · \(list.count)")
                VStack(spacing: 0) {
                    ForEach(list) { p in
                        row(p, enabled: enabled)
                        if p.id != list.last?.id { GMDivider().padding(.leading, 52) }
                    }
                }
                .padding(.horizontal, 12)
                .background(Theme.raised, in: .rect(cornerRadius: Theme.radiusM))
            }
        }
    }

    private func row(_ p: DuelPerson, enabled: Bool) -> some View {
        let tag = store.personRefusal(p.id).map(Self.tag)
        return Button { pick(p) } label: {
            HStack(spacing: 12) {
                MonsterSprite(form: p.form).frame(width: 34, height: 34).frame(width: 40)
                Text(p.name).font(.subheadline.weight(.semibold))
                Spacer()
                if let tag {
                    GMBadge(text: tag, tint: Theme.trophy)
                } else if enabled {
                    Image(systemName: "bolt.fill").font(.caption.bold()).foregroundStyle(.black)
                        .frame(width: 28, height: 28).background(Theme.trophy, in: .circle)
                }
            }
            .padding(.vertical, 8)
            .foregroundStyle(.white)
            .contentShape(Rectangle())
            .opacity(enabled || tag != nil ? 1 : 0.6)
        }
        .buttonStyle(GMPress())
        .disabled(!enabled)
        .accessibilityLabel(enabled ? "Desafiar \(p.name)" : tag.map { "\(p.name), \($0)" } ?? p.name)
    }

    /// Motivo curto da pessoa, numa etiqueta
    private static func tag(_ r: DuelRefusal) -> String {
        switch r {
        case .alreadyOpen: "X1 aberto"
        default: "Indisponível"
        }
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased()).font(.caption.weight(.bold)).foregroundStyle(Theme.dim).tracking(0.6).padding(.horizontal, 4)
    }
}

// MARK: - Peças

/// Linha de um X1 encerrado
struct DuelRecordRow: View {
    let record: DuelRecord

    var body: some View {
        HStack(spacing: 12) {
            GMBadge(text: record.score.result.letter, tint: tint)
            MonsterSprite(form: record.opponent.form).frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.text).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                Text(record.ended.formatted(.dateTime.day().month(.abbreviated).hour().minute())).font(.caption).foregroundStyle(Theme.dim)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        switch record.score.result {
        case .vitoria: Theme.accent
        case .derrota: Theme.danger
        case .empate: .white
        }
    }
}

/// Seus últimos X1, no perfil
struct DuelHistorySection: View {
    @State private var store = DuelStore.shared

    var body: some View {
        let records = Array(store.records().prefix(5))
        Group {
            if !records.isEmpty {
                let t = Duels.tally(store.records())
                GMSection("X1", footer: "\(t.v) vitória\(t.v == 1 ? "" : "s"), \(t.e) empate\(t.e == 1 ? "" : "s"), \(t.d) derrota\(t.d == 1 ? "" : "s")") {
                    ForEach(records) { r in
                        DuelRecordRow(record: r)
                        if r.id != records.last?.id { GMDivider() }
                    }
                }
            }
        }
        .task { await store.refresh() }
    }
}

/// Na tela inicial, sempre visível. Ordem: desafios esperando sua resposta (mais antigo primeiro, expira antes),
/// depois os X1 valendo (o que acaba antes primeiro), todos em linhas compactas. Sem nenhum, convida a desafiar alguém.
struct DuelHomeCard: View {
    @State private var store = DuelStore.shared
    @State private var friends = FriendsStore.shared
    @State private var open = false
    @State private var openPicking = false
    @State private var target: DuelPerson?

    private let maxRows = 3

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            let now = ctx.date
            let incoming = store.duels.filter { $0.challenged.id == "me" && $0.isPending(now: now) }.sorted { $0.createdAt < $1.createdAt }
            let active = store.duels.filter { $0.acceptedAt != nil && $0.isOpen(now: now) }
                .sorted { ($0.endsAt ?? .distantFuture) < ($1.endsAt ?? .distantFuture) }
            let rows = incoming.map { ($0, true) } + active.map { ($0, false) }
            GMCard {
                header(Duels.tally(store.records(now: now)))
                if rows.isEmpty {
                    invite
                } else {
                    ForEach(rows.prefix(maxRows), id: \.0.id) { d, pending in
                        Button { open = true } label: {
                            if pending { incomingRow(d, now: now) } else { activeRow(d, now: now) }
                        }
                        .buttonStyle(GMPress())
                    }
                    if rows.count > maxRows {
                        Button { open = true } label: {
                            Text("Ver mais \(rows.count - maxRows)").font(.caption.bold()).foregroundStyle(Theme.accent)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(GMPress())
                    }
                }
            }
        }
        .task { await store.refresh() }
        .gmModal(isPresented: $open) { DuelsView() }
        .gmModal(isPresented: $openPicking) { DuelsView(startPicking: true) }
        .gmSheet(isPresented: Binding(get: { target != nil }, set: { if !$0 { target = nil } })) { close in
            if let target { DuelComposer(opponent: target) { close() } }
        }
    }

    private func header(_ t: (v: Int, e: Int, d: Int)) -> some View {
        Button { open = true } label: {
            HStack(spacing: 8) {
                Label("X1", systemImage: "bolt.shield.fill").font(.headline).foregroundStyle(Theme.trophy)
                Spacer()
                if t.v + t.e + t.d > 0 {
                    Text("\(t.v)V · \(t.e)E · \(t.d)D").font(.caption.bold().monospacedDigit()).foregroundStyle(Theme.dim)
                }
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.dim)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(GMPress())
        .accessibilityLabel("Abrir X1")
    }

    /// Desafio esperando você
    private func incomingRow(_ d: RemoteDuel, now: Date) -> some View {
        HStack(spacing: 10) {
            MonsterSprite(form: d.challenger.form).frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(d.challenger.name) te desafiou").font(.subheadline.weight(.semibold))
                Text("\(d.metric.name) · expira em \(DuelsView.remaining(d.expiresAt, now: now))").font(.caption).foregroundStyle(Theme.dim)
            }
            Spacer()
            Text("Responder").font(.caption.bold())
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Theme.trophy, in: .capsule)
                .foregroundStyle(.black)
        }
        .padding(10)
        .background(Theme.trophy.opacity(0.1), in: .rect(cornerRadius: Theme.radiusM))
        .foregroundStyle(.white)
    }

    /// X1 valendo: você, placar e a pessoa numa linha
    private func activeRow(_ d: RemoteDuel, now: Date) -> some View {
        let s = store.score(d, now: now)
        let other = d.opponent(of: "me")
        let tint: Color = s.mine > s.theirs ? Theme.accent : s.mine < s.theirs ? Theme.danger : .white
        return HStack(spacing: 10) {
            MonsterSprite(form: store.myForm(in: d)).frame(width: 32, height: 32)
            Text("\(d.metric.short(s.mine))").font(.headline.monospacedDigit()).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.7)
            Text("×").font(.subheadline.bold()).foregroundStyle(Theme.dim)
            Text("\(d.metric.short(s.theirs))").font(.headline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            MonsterSprite(form: other.form).frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(other.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: d.metric.symbol)
                    Text(d.endsAt.map { DuelsView.remaining($0, now: now) } ?? "")
                }
                .font(.caption2).foregroundStyle(Theme.dim)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Theme.raised, in: .rect(cornerRadius: Theme.radiusM))
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
    }

    /// Sem X1: chama para desafiar, com atalho para alguns amigos
    private var invite: some View {
        let quick = friends.friends.filter { store.refusal($0.id) == nil }.prefix(4)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Ninguém no X1 com você agora. Desafie alguém: vence quem treinar mais nas 24 h depois do aceite.")
                .font(.subheadline).foregroundStyle(.white.opacity(0.85))
            HStack(spacing: 8) {
                ForEach(Array(quick)) { f in
                    Button { target = DuelPerson(id: f.id, name: f.name, formID: f.formID) } label: {
                        VStack(spacing: 3) {
                            MonsterSprite(form: f.form)
                                .frame(width: 34, height: 34)
                                .frame(width: 46, height: 46)
                                .background(Theme.raised, in: .circle)
                                .overlay(Circle().stroke(Theme.trophy.opacity(0.6), lineWidth: 1.5))
                            Text(f.name).font(.caption2.bold()).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(GMPress())
                    .accessibilityLabel("Desafiar \(f.name)")
                }
                if quick.isEmpty { Spacer() }
            }
            GMButton("Desafiar alguém", icon: "bolt.fill", kind: .secondary, small: true) { openPicking = true }
        }
    }
}

extension DuelMetric {
    var tint: Color {
        switch self {
        case .xp: Theme.accent
        case .treinos: Attribute.tecnica.color
        case .minutos: Attribute.resistencia.color
        case .distancia: Theme.online
        case .calorias: Theme.streak
        }
    }
}

// MARK: - Bro que luta

/// Bros chocados lado a lado para escolher quem vai para o X1
struct FighterPicker: View {
    @Binding var selection: UUID?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                let busy = DuelStore.shared.busyFighters()
                ForEach(DuelStore.shared.fighters()) { m in
                    let form = MonsterForm.byID(m.lastFormID) ?? .egg
                    let on = selection == m.uuid
                    let free = !busy.contains(m.uuid)
                    let tint = form.attribute?.color ?? Theme.accent
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.snappy) { selection = m.uuid }
                    } label: {
                        VStack(spacing: 4) {
                            MonsterSprite(form: form).frame(width: 46, height: 46)
                            Text(m.displayName(form)).font(.caption.bold()).lineLimit(1).minimumScaleFactor(0.7)
                            Text(free ? form.stage.name : "Em X1").gmFont(9, mono: true, relativeTo: .caption2)
                                .foregroundStyle(free ? Theme.dim : Theme.trophy)
                        }
                        .frame(width: 84)
                        .padding(.vertical, 8)
                        .background(on ? tint.opacity(0.18) : Theme.raised, in: .rect(cornerRadius: Theme.radiusM))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radiusM).stroke(on ? tint : .clear, lineWidth: 1.5))
                        .foregroundStyle(.white)
                        .opacity(free ? 1 : 0.4)
                    }
                    .buttonStyle(GMPress())
                    .disabled(!free)
                    .accessibilityLabel("\(m.displayName(form)), \(free ? form.stage.name : "já está num X1")")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }
}

/// A Box dentro do X1: todos os seus bros em slots; ovos aparecem, mas não lutam. Escolha um e confirme.
struct FighterBox: View {
    let title: String
    let done: (UUID) -> Void
    @State private var selection: UUID?

    init(title: String, selection: UUID?, done: @escaping (UUID) -> Void) {
        self.title = title
        self.done = done
        _selection = State(initialValue: selection)
    }

    var body: some View {
        let monsters = DuelStore.shared.allMonsters()
        let busy = DuelStore.shared.busyFighters()
        let fighters = Set(DuelStore.shared.fighters().map(\.uuid)).subtracting(busy)
        let slots = max(8, Int((Double(monsters.count) / 4).rounded(.up)) * 4)
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline).frame(maxWidth: .infinity)
            HStack {
                Label("Box", systemImage: "square.grid.3x3.fill").font(.subheadline.bold())
                Spacer()
                Text("Cada bro luta um X1 por vez").font(.caption).foregroundStyle(Theme.dim)
            }
            // Grid normal (não lazy): a grade lazy montava os slots durante a subida da folha e eles apareciam antes dela
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                ForEach(0..<slots / 4, id: \.self) { row in
                    GridRow {
                        ForEach(row * 4..<row * 4 + 4, id: \.self) { i in
                            if i < monsters.count {
                                slot(monsters[i], canFight: fighters.contains(monsters[i].uuid), busy: busy.contains(monsters[i].uuid))
                            } else {
                                RoundedRectangle(cornerRadius: Theme.radiusM)
                                    .strokeBorder(Theme.stroke, style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                                    .aspectRatio(0.82, contentMode: .fit)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
            }
            if fighters.isEmpty {
                Label((busy.isEmpty ? DuelRefusal.noHatchedBro : .allFightersBusy).errorDescription ?? "", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.bold()).foregroundStyle(Theme.danger)
            }
            GMButton(selectedName.map { "Lutar com \($0)" } ?? "Escolha um bro", icon: "bolt.fill", enabled: selection != nil) {
                if let selection { done(selection) }
            }
        }
    }

    private var selectedName: String? {
        guard let m = DuelStore.shared.fighters().first(where: { $0.uuid == selection }) else { return nil }
        return m.displayName(MonsterForm.byID(m.lastFormID) ?? .egg)
    }

    private func slot(_ m: Monster, canFight: Bool, busy: Bool) -> some View {
        let form = MonsterForm.byID(m.lastFormID) ?? .egg
        let on = selection == m.uuid
        let tint = form.attribute?.color ?? Theme.accent
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.snappy) { selection = m.uuid }
        } label: {
            VStack(spacing: 2) {
                MonsterSprite(form: form).frame(width: 48, height: 48).padding(.top, 8)
                Text(m.displayName(form)).font(.caption2.bold()).lineLimit(1).minimumScaleFactor(0.7)
                Text(busy ? "Em X1" : form.stage.name).gmFont(9, weight: .semibold, mono: true, relativeTo: .caption2)
                    .foregroundStyle(busy ? Theme.trophy : Theme.dim)
                    .padding(.bottom, 6)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .aspectRatio(0.82, contentMode: .fit)
            .background(on ? tint.opacity(0.2) : Theme.raised, in: .rect(cornerRadius: Theme.radiusM))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusM).stroke(on ? tint : .clear, lineWidth: 2))
            .opacity(canFight ? 1 : 0.4)
            .foregroundStyle(.white)
        }
        .buttonStyle(GMPress())
        .disabled(!canFight)
        .accessibilityLabel("\(m.displayName(form)), \(canFight ? form.stage.name : busy ? "já está num X1" : "ovo, não luta")")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
