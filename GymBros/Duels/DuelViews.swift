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
    /// Desafio aceito esperando a escolha do bro (quando você tem mais de um)
    @State private var accepting: RemoteDuel?
    @Query private var leagues: [League]

    var body: some View {
        GMScreen("X1", subtitle: "Desafie qualquer pessoa: vence quem fizer mais nas 24 h depois do aceite", close: true, bottomInset: 40) {
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
        .gmSheet(isPresented: Binding(get: { accepting != nil }, set: { if !$0 { accepting = nil } })) { close in
            if let d = accepting {
                FighterChoice(title: "Quem vai lutar contra \(d.challenger.name)?", confirm: "Aceitar X1") { id in
                    close()
                    send(d, accept: true, monster: id)
                }
            }
        }
        .termsGate($terms)
    }

    /// Amigos e gente das suas ligas (só para achar a pessoa; o X1 não tem nada a ver com a liga)
    private var candidates: (friends: [DuelPerson], others: [DuelPerson]) {
        var seen = Set<String>()
        let friends = FriendsStore.shared.friends.filter { seen.insert($0.id).inserted }
            .map { DuelPerson(id: $0.id, name: $0.name, formID: $0.formID) }
        var others: [DuelPerson] = []
        for l in leagues where !l.isPastSeason {
            for m in LeagueRemoteStore.shared.remote(l).members where seen.insert(m.id).inserted && !ModerationStore.shared.isBlocked(m.id) {
                others.append(DuelPerson(id: m.id, name: m.name, formID: m.form.id))
            }
        }
        return (friends.sorted { $0.name < $1.name }, others.sorted { $0.name < $1.name })
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let duels = store.duels
        let incoming = duels.filter { $0.challenged.id == "me" && $0.isPending(now: now) }
        let active = duels.filter { $0.acceptedAt != nil && $0.isOpen(now: now) }
        let sent = duels.filter { $0.challenger.id == "me" && $0.isPending(now: now) }
        let records = store.records(now: now)

        tallyCard(records)

        if let e = store.lastError {
            GMEmptyState(icon: "icloud.slash", title: "X1 indisponível", message: e)
        } else if duels.isEmpty && store.loaded {
            GMEmptyState(icon: "bolt.shield", title: "Nenhum X1 ainda",
                         message: "Escolha alguém, a métrica e mande o desafio. Vale qualquer atividade que vocês registrarem.")
            GMButton("Novo X1", icon: "bolt.fill") { picking = true }
        }
        if !incoming.isEmpty {
            GMSection("Desafios recebidos") {
                ForEach(incoming) { d in
                    incomingRow(d, now: now)
                    if d.id != incoming.last?.id { GMDivider() }
                }
            }
        }
        if !active.isEmpty {
            GMSection("Valendo agora") {
                ForEach(active) { d in
                    DuelScoreboard(duel: d, score: store.score(d, now: now), now: now)
                    if d.id != active.last?.id { GMDivider() }
                }
            }
        }
        if !sent.isEmpty {
            GMSection("Esperando resposta") {
                ForEach(sent) { d in
                    sentRow(d, now: now)
                    if d.id != sent.last?.id { GMDivider() }
                }
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

    private func tallyCard(_ records: [DuelRecord]) -> some View {
        let t = Duels.tally(records)
        return HStack(spacing: 10) {
            tally("\(t.v)", "Vitórias", Theme.accent)
            tally("\(t.e)", "Empates", .white)
            tally("\(t.d)", "Derrotas", Theme.danger)
        }
    }

    private func tally(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).gmFont(26, weight: .heavy, design: .rounded, mono: true, relativeTo: .title).foregroundStyle(tint)
            Text(label).font(.caption).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.card, in: .rect(cornerRadius: Theme.radius))
        .accessibilityElement(children: .combine)
    }

    private func incomingRow(_ d: RemoteDuel, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                MonsterSprite(form: d.challenger.form).frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(d.challenger.name) te desafiou").font(.subheadline.weight(.semibold))
                    Label(d.metric.name, systemImage: d.metric.symbol).font(.caption.bold()).foregroundStyle(Theme.trophy)
                    Text("Expira em \(Self.remaining(d.expiresAt, now: now))").font(.caption).foregroundStyle(Theme.dim)
                }
                Spacer()
            }
            HStack(spacing: 10) {
                GMButton("Recusar", kind: .secondary, small: true, enabled: !busy) { respond(d, accept: false) }
                GMButton("Aceitar", icon: "bolt.fill", small: true, enabled: !busy) { respond(d, accept: true) }
            }
        }
    }

    private func sentRow(_ d: RemoteDuel, now: Date) -> some View {
        HStack(spacing: 12) {
            MonsterSprite(form: d.challenged.form).frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("Aguardando \(d.challenged.name)").font(.subheadline.weight(.semibold))
                Text("\(d.metric.name) · expira em \(Self.remaining(d.expiresAt, now: now))").font(.caption).foregroundStyle(Theme.dim)
            }
            Spacer()
            ProgressView().tint(Theme.dim)
        }
    }

    private func respond(_ d: RemoteDuel, accept: Bool) {
        guard accept else { return send(d, accept: false, monster: nil) }
        // Ovo não luta; com mais de um bro chocado, você escolhe quem vai
        switch store.fighters().count {
        case 0: problem = DuelRefusal.noHatchedBro.errorDescription
        case 1: send(d, accept: true, monster: store.fighters().first?.uuid)
        default: accepting = d
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

// MARK: - Placar ao vivo

struct DuelScoreboard: View {
    let duel: RemoteDuel
    let score: DuelScore
    let now: Date

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                side(name: "Você", form: DuelStore.shared.me().form, value: score.mine, ahead: score.mine > score.theirs)
                VStack(spacing: 2) {
                    Image(systemName: "bolt.fill").font(.title3).foregroundStyle(Theme.trophy)
                    Text(duel.endsAt.map { "faltam \(DuelsView.remaining($0, now: now))" } ?? "").font(.caption2).foregroundStyle(Theme.dim)
                }
                .fixedSize()
                let other = duel.opponent(of: "me")
                side(name: other.name, form: other.form, value: score.theirs, ahead: score.theirs > score.mine)
            }
            Label(duel.metric.name, systemImage: duel.metric.symbol).font(.caption2.bold()).foregroundStyle(Theme.dim)
        }
        .accessibilityElement(children: .combine)
    }

    private func side(name: String, form: MonsterForm, value: Int, ahead: Bool) -> some View {
        VStack(spacing: 4) {
            MonsterSprite(form: form).frame(width: 44, height: 44)
            Text(name).font(.caption.bold()).lineLimit(1)
            Text(duel.metric.short(value))
                .font(.headline.monospacedDigit())
                .foregroundStyle(ahead ? Theme.accent : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
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

/// Escolher quem desafiar: busca, recentes, amigos e gente das suas ligas; quem não dá para desafiar vai para o fim
struct DuelPeoplePicker: View {
    let friends: [DuelPerson]
    let others: [DuelPerson]
    let pick: (DuelPerson) -> Void
    @State private var query = ""

    private var store: DuelStore { .shared }

    /// Últimos adversários, mais recentes primeiro
    private var recent: [DuelPerson] {
        var seen = Set<String>()
        return store.duels.sorted { $0.createdAt > $1.createdAt }.map { $0.opponent(of: "me") }
            .filter { seen.insert($0.id).inserted }.prefix(8).map { $0 }
    }

    private func matches(_ p: DuelPerson) -> Bool {
        query.isEmpty || p.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .contains(query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil))
    }

    var body: some View {
        let free = { (list: [DuelPerson]) in list.filter { matches($0) && store.refusal($0.id) == nil } }
        let busy = (friends + others).filter { matches($0) && store.refusal($0.id) != nil }
        let f = free(friends), o = free(others)
        VStack(alignment: .leading, spacing: 12) {
            Text("Desafiar quem?").font(.headline).frame(maxWidth: .infinity)
            if friends.isEmpty && others.isEmpty {
                GMEmptyState(icon: "person.2", title: "Ninguém por aqui", message: "Adicione amigos ou entre numa liga para achar gente para desafiar.")
            } else {
                GMSearchField(placeholder: "Buscar pelo nome", text: $query)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if query.isEmpty && !recent.isEmpty { recentStrip }
                        group("Amigos", f)
                        group("Das suas ligas", o)
                        if !busy.isEmpty {
                            group("Com X1 aberto ou indisponível", busy, enabled: false)
                        }
                        if f.isEmpty && o.isEmpty && busy.isEmpty {
                            Text("Ninguém com esse nome.").font(.subheadline).foregroundStyle(Theme.dim).frame(maxWidth: .infinity).padding(.top, 20)
                        }
                    }
                    .padding(.bottom, 8)
                }
                .scrollDismissesKeyboard(.immediately)
                .frame(maxHeight: 460)
            }
        }
    }

    /// Revanche: quem você já enfrentou, em bolinhas
    private var recentStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("Revanche")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(recent) { p in
                        let ok = store.refusal(p.id) == nil
                        Button { pick(p) } label: {
                            VStack(spacing: 4) {
                                MonsterSprite(form: p.form)
                                    .frame(width: 40, height: 40)
                                    .frame(width: 54, height: 54)
                                    .background(Theme.raised, in: .circle)
                                    .overlay(Circle().stroke(ok ? Theme.trophy.opacity(0.7) : .clear, lineWidth: 1.5))
                                Text(p.name).font(.caption2.bold()).lineLimit(1).frame(width: 60)
                            }
                            .foregroundStyle(.white)
                            .opacity(ok ? 1 : 0.4)
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
    private func group(_ title: String, _ list: [DuelPerson], enabled: Bool = true) -> some View {
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
        Button { pick(p) } label: {
            HStack(spacing: 12) {
                MonsterSprite(form: p.form).frame(width: 34, height: 34).frame(width: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.name).font(.subheadline.weight(.semibold))
                    if !enabled, let r = store.refusal(p.id) {
                        Text(r.errorDescription ?? "").font(.caption2).foregroundStyle(Theme.dim)
                    }
                }
                Spacer()
                if enabled {
                    Image(systemName: "bolt.fill").font(.caption.bold()).foregroundStyle(.black)
                        .frame(width: 28, height: 28).background(Theme.trophy, in: .circle)
                }
            }
            .padding(.vertical, 8)
            .foregroundStyle(.white)
            .contentShape(Rectangle())
            .opacity(enabled ? 1 : 0.45)
        }
        .buttonStyle(GMPress())
        .disabled(!enabled)
        .accessibilityLabel(enabled ? "Desafiar \(p.name)" : p.name)
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
            MonsterSprite(form: DuelStore.shared.me().form).frame(width: 32, height: 32)
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
                ForEach(DuelStore.shared.fighters()) { m in
                    let form = MonsterForm.byID(m.lastFormID) ?? .egg
                    let on = selection == m.uuid
                    let tint = form.attribute?.color ?? Theme.accent
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.snappy) { selection = m.uuid }
                    } label: {
                        VStack(spacing: 4) {
                            MonsterSprite(form: form).frame(width: 46, height: 46)
                            Text(m.displayName(form)).font(.caption.bold()).lineLimit(1).minimumScaleFactor(0.7)
                            Text(form.stage.name).gmFont(9, mono: true, relativeTo: .caption2).foregroundStyle(Theme.dim)
                        }
                        .frame(width: 84)
                        .padding(.vertical, 8)
                        .background(on ? tint.opacity(0.18) : Theme.raised, in: .rect(cornerRadius: Theme.radiusM))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radiusM).stroke(on ? tint : .clear, lineWidth: 1.5))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(GMPress())
                    .accessibilityLabel("\(m.displayName(form)), \(form.stage.name)")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }
}

/// Folha para escolher o bro antes de aceitar um desafio
struct FighterChoice: View {
    let title: String
    let confirm: String
    let done: (UUID?) -> Void
    @State private var selection = DuelStore.shared.defaultFighter()?.uuid

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline).frame(maxWidth: .infinity)
            Text("Ovos não entram no X1.").font(.caption).foregroundStyle(Theme.dim).frame(maxWidth: .infinity)
            FighterPicker(selection: $selection)
            GMButton(confirm, icon: "bolt.fill", enabled: selection != nil) { done(selection) }
        }
    }
}
