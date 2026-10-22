import SwiftData
import SwiftUI

// MARK: - Central de trocas

/// Trocas de bros com amigos: as que chegaram, as que você mandou e as que já aconteceram
struct TradeHubView: View {
    @State private var store = TradeStore.shared
    @State private var composing = false
    @State private var confirming: TradeProposal?
    @State private var problem: String?
    @State private var busy = false

    var body: some View {
        GMScreen("Trocas", subtitle: "Troque bros com amigos, 1 por 1. Ovos não entram.", close: true, bottomInset: 40) {
            GMIconButton(icon: "plus", label: "Nova troca") { composing = true }
        } content: {
            TimelineView(.periodic(from: .now, by: 30)) { ctx in content(now: ctx.date) }
        }
        .task {
            while !Task.isCancelled {
                await store.refresh()
                // Logo depois de propor, a resposta pode chegar em segundos
                let fresh = store.sent().contains { Date.now.timeIntervalSince($0.createdAt) < 120 }
                try? await Task.sleep(for: .seconds(fresh ? 3 : 30))
            }
        }
        .gmSheet(isPresented: $composing) { close in TradeComposer { close() } }
        .gmActions(isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                   title: confirming.map { "Trocar \($0.mine.name) por \($0.theirs.name)?" },
                   message: confirming.map { "\($0.mine.name) vai para \($0.friend.name) com o XP dele, e \($0.theirs.name) chega com \($0.theirs.xp.formatted()) XP. Não dá para desfazer." },
                   // A ação roda depois que a folha fecha (e zera `confirming`): a proposta vai capturada
                   actions: confirming.map { p in [GMAction("Trocar", icon: "arrow.left.arrow.right") { answer(p, true) }] } ?? [])
        .gmActions(isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } }), title: "Troca", message: problem, actions: [])
        // Cena da troca em tela cheia (TradeSwapScene)
        .fullScreenCover(isPresented: Binding(get: { store.arrived != nil }, set: { if !$0 { store.arrived = nil } })) {
            if let a = store.arrived {
                TradeArrivedView(bro: a.bro, proposal: a.proposal)
                    .preferredColorScheme(.dark)
                    .tint(Theme.accent)
            }
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let incoming = store.incoming(now: now), sent = store.sent(now: now), done = store.done(), ready = store.ready()
        if let e = store.lastError {
            GMEmptyState(icon: "icloud.slash", title: "Trocas indisponíveis", message: e)
        }
        if !ready.isEmpty {
            label("Chegou para você", count: ready.count, tint: Theme.accent)
            ForEach(ready) { p in
                TradeReadyCard(proposal: p) { store.receive(p) }
            }
        }
        if !incoming.isEmpty {
            label("Te ofereceram", count: incoming.count, tint: Theme.trophy)
            ForEach(incoming) { p in
                TradeOfferCard(proposal: p, now: now, busy: busy) { accept in
                    if accept { confirming = p } else { answer(p, false) }
                }
            }
        }
        if !sent.isEmpty {
            GMSection("Esperando resposta") {
                ForEach(sent) { p in
                    sentRow(p, now: now)
                    if p.id != sent.last?.id { GMDivider() }
                }
            }
        }
        if incoming.isEmpty && sent.isEmpty && ready.isEmpty && store.loaded {
            TradeIdleCard { composing = true }
        }
        if !done.isEmpty {
            GMSection("Trocas feitas") {
                ForEach(done.prefix(20)) { p in
                    doneRow(p)
                    if p.id != done.prefix(20).last?.id { GMDivider() }
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
    }

    private func sentRow(_ p: TradeProposal, now: Date) -> some View {
        HStack(spacing: 10) {
            TradePair(give: p.mine, get: p.theirs, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("Aguardando \(p.friend.name)").font(.subheadline.weight(.semibold)).lineLimit(1)
                Text("\(p.mine.name) por \(p.theirs.name) · \(DuelsView.remaining(p.expiresAt, now: now))")
                    .font(.caption).foregroundStyle(Theme.dim).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button {
                Task {
                    try? await store.cancel(p)
                }
            } label: {
                Text("Cancelar").font(.caption.bold()).foregroundStyle(Theme.danger)
            }
            .buttonStyle(GMPress())
        }
    }

    private func doneRow(_ p: TradeProposal) -> some View {
        HStack(spacing: 10) {
            TradePair(give: p.mine, get: p.theirs, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(p.mine.name) por \(p.theirs.name)").font(.subheadline.weight(.semibold)).lineLimit(1)
                Text("com \(p.friend.name) · \((p.answeredAt ?? p.createdAt).formatted(.dateTime.day().month(.abbreviated)))")
                    .font(.caption).foregroundStyle(Theme.dim).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func answer(_ p: TradeProposal, _ accept: Bool) {
        busy = true
        Task {
            defer { busy = false }
            do {
                try await store.respond(p, accept: accept)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                problem = error.localizedDescription
            }
        }
    }
}

// MARK: - Peças

/// O seu bro e o do amigo, com as setas da troca no meio (miniatura das listas)
struct TradePair: View {
    let give: TradeBro
    let get: TradeBro
    var size: CGFloat = 34

    var body: some View {
        HStack(spacing: 2) {
            MonsterSprite(form: give.form).frame(width: size, height: size)
            Image(systemName: "arrow.left.arrow.right").font(.system(size: size * 0.32, weight: .bold)).foregroundStyle(Theme.trophy)
            MonsterSprite(form: get.form).frame(width: size, height: size)
        }
        .accessibilityHidden(true)
    }
}

/// Um bro na troca: sprite, nome, estágio e XP. `tag` explica por que não dá para escolher.
struct TradeBroCard: View {
    let form: MonsterForm
    let name: String
    let xp: Int
    var selected = false
    var tag: String?

    var body: some View {
        let tint = form.attribute?.color ?? Theme.accent
        VStack(spacing: 3) {
            MonsterSprite(form: form, hidden: false).frame(width: 52, height: 52).padding(.top, 8)
            Text(name).font(.caption.bold()).lineLimit(1).minimumScaleFactor(0.7)
            Text(form.stage == .egg ? " " : "\(form.stage.name) · \(xp.formatted()) XP")
                .gmFont(9, weight: .semibold, mono: true, relativeTo: .caption2).foregroundStyle(Theme.dim).lineLimit(1).minimumScaleFactor(0.6)
            // A etiqueta ocupa o mesmo espaço com ou sem texto: os cards da grade ficam da mesma altura
            Text(tag ?? " ").font(.system(size: 9, weight: .heavy)).foregroundStyle(Theme.trophy)
                .padding(.horizontal, 6).padding(.vertical, 2).background(tag == nil ? .clear : Theme.trophy.opacity(0.15), in: .capsule)
        }
        .padding(.horizontal, 4).padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(selected ? tint.opacity(0.2) : Theme.raised, in: .rect(cornerRadius: Theme.radiusM))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusM).stroke(selected ? tint : .clear, lineWidth: 2))
        .opacity(tag == nil ? 1 : 0.45)
        .foregroundStyle(.white)
    }
}

/// Você dá × você recebe, lado a lado com as setas no meio
struct TradeVersus: View {
    let give: (form: MonsterForm, name: String, xp: Int)
    let get: (form: MonsterForm, name: String, xp: Int)
    var friend: String
    /// De quem é o XP do bro que você recebe ("de Bruno", "de Lia e Bruno")
    var getOwners: [OwnerXP] = []

    var body: some View {
        HStack(spacing: 0) {
            side("Você dá", give, tint: Theme.danger, owners: nil)
            ZStack {
                Circle().fill(Theme.trophy.opacity(0.25)).frame(width: 56, height: 56).blur(radius: 12)
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(.black)
                    .frame(width: 42, height: 42)
                    .background(LinearGradient(colors: [Theme.trophy, Theme.streak], startPoint: .topLeading, endPoint: .bottomTrailing), in: .circle)
            }
            .frame(width: 56)
            side("Você recebe", get, tint: Theme.accent, owners: getOwners.isEmpty ? nil : getOwners)
        }
        .padding(.vertical, 12)
        .background(Theme.raised, in: .rect(cornerRadius: Theme.radiusL))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Você dá \(give.name) e recebe \(get.name) de \(friend)")
    }

    private func side(_ title: String, _ b: (form: MonsterForm, name: String, xp: Int), tint: Color, owners: [OwnerXP]?) -> some View {
        VStack(spacing: 4) {
            Text(title.uppercased()).font(.system(size: 9, weight: .heavy)).foregroundStyle(tint).tracking(0.5)
            LivingMonster(form: b.form).frame(width: 64, height: 64)
            Text(b.name).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.7)
            Text("\(b.form.stage.name) · \(b.xp.formatted()) XP").font(.caption2).foregroundStyle(Theme.dim).lineLimit(1)
            if let owners {
                let names = owners.map(\.name)
                Text("XP de " + (names.count <= 2 ? names.joined(separator: " e ") : "\(names.last!) e mais \(names.count - 1)"))
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.trophy).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Troca sua que o amigo aceitou: o bro dele só chega quando você toca em Receber (e aí vem a cena da troca)
struct TradeReadyCard: View {
    let proposal: TradeProposal
    let receive: () -> Void

    var body: some View {
        GMCard {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.accent)
                Text("\(proposal.friend.name) aceitou a troca").font(.subheadline.weight(.bold))
                Spacer()
            }
            TradeVersus(give: (proposal.mine.form, proposal.mine.name, proposal.mine.xp),
                        get: (proposal.theirs.form, proposal.theirs.name, proposal.theirs.xp),
                        friend: proposal.friend.name, getOwners: proposal.theirs.history)
            GMButton("Receber \(proposal.theirs.name)", icon: "gift.fill", action: receive)
        }
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.accent.opacity(0.5), lineWidth: 1.5))
    }
}

/// Proposta que chegou: o que você recebe, o que dá, o prazo e os botões
struct TradeOfferCard: View {
    let proposal: TradeProposal
    let now: Date
    let busy: Bool
    let answer: (Bool) -> Void

    var body: some View {
        let p = proposal
        let left = p.expiresAt.timeIntervalSince(now) / TradeProposal.window
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                MonsterSprite(form: p.friend.form).frame(width: 28, height: 28)
                Text("\(p.friend.name) quer trocar").font(.headline).lineLimit(1)
                Spacer(minLength: 0)
                Text(p.createdAt.formatted(.relative(presentation: .named))).font(.caption2).foregroundStyle(Theme.dim)
            }
            TradeVersus(give: (p.mine.form, p.mine.name, p.mine.xp), get: (p.theirs.form, p.theirs.name, p.theirs.xp), friend: p.friend.name,
                        getOwners: p.theirs.history)
            VStack(alignment: .leading, spacing: 4) {
                GMProgressBar(value: left, tint: left < 0.25 ? Theme.danger : Theme.trophy, height: 6)
                Text("Você tem \(DuelsView.remaining(p.expiresAt, now: now)) para responder.").font(.caption).foregroundStyle(Theme.dim)
            }
            HStack(spacing: 10) {
                GMButton("Recusar", kind: .secondary, enabled: !busy) { answer(false) }
                GMButton("Trocar", icon: "arrow.left.arrow.right", enabled: !busy) { answer(true) }
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
    }
}

/// Sem troca rolando: o seu bro e um "?", como funciona e o botão
struct TradeIdleCard: View {
    let start: () -> Void

    var body: some View {
        let me = TradeStore.shared.me()
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 0) {
                VStack(spacing: 6) {
                    LivingMonster(form: me.form).frame(width: 68, height: 68)
                    Text("Seu bro").font(.caption.bold())
                }
                .frame(maxWidth: .infinity)
                Image(systemName: "arrow.left.arrow.right").font(.title3.weight(.black)).foregroundStyle(Theme.trophy)
                VStack(spacing: 6) {
                    Image(systemName: "questionmark").font(.system(size: 28, weight: .black)).foregroundStyle(Theme.dim)
                        .frame(width: 68, height: 68)
                        .background(Circle().strokeBorder(Theme.dim.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
                    Text("Do amigo").font(.caption.bold()).foregroundStyle(Theme.dim)
                }
                .frame(maxWidth: .infinity)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Nenhuma troca rolando").font(.title3.bold())
                Text("Escolha um bro de um amigo, ofereça um seu e espere ele aceitar.").font(.subheadline).foregroundStyle(Theme.dim)
            }
            VStack(alignment: .leading, spacing: 10) {
                rule("person.2.fill", "Só entre amigos, 1 bro por 1 bro. Ovos não entram.")
                rule("sparkles", "O bro chega com a forma e o XP que tinha. Esse XP fica marcado como de quem o treinou, separado do que ele ganhar com você.")
                rule("hourglass", "O amigo tem 48 h para responder. O principal e quem está em liga ou X1 não entram.")
            }
            GMButton("Propor troca", icon: "arrow.left.arrow.right", action: start)
        }
        .padding(16)
        .background {
            ZStack {
                Theme.card
                RadialGradient(colors: [Theme.trophy.opacity(0.12), .clear], center: .top, startRadius: 10, endRadius: 260)
            }
            .clipShape(.rect(cornerRadius: Theme.radius))
        }
    }

    private func rule(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.caption.bold()).foregroundStyle(Theme.trophy)
                .frame(width: 28, height: 28).background(Theme.trophy.opacity(0.14), in: .circle)
            Text(text).font(.subheadline).foregroundStyle(.white.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Propor troca

/// Numa folha só: amigo → bro dele → seu bro → conferir e mandar
struct TradeComposer: View {
    let done: () -> Void
    @State private var friend: RemoteFriend?
    @State private var theirs: TradeBro?
    @State private var mine: Monster?
    @State private var friendBros: [TradeBro] = []
    @State private var loading = false
    @State private var query = ""
    @State private var problem: String?
    @State private var busy = false
    @State private var store = TradeStore.shared

    private let columns = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Group {
                if let friend, let theirs, let mine { review(friend, theirs, mine) }
                else if let friend, theirs != nil { mineStep(friend) }
                else if let friend { theirsStep(friend) }
                else { friendStep }
            }
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
        .animation(.snappy, value: [friend?.id ?? "", theirs?.id ?? "", mine?.uuid.uuidString ?? ""])
    }

    private var step: Int { mine != nil ? 4 : theirs != nil ? 3 : friend != nil ? 2 : 1 }

    private var header: some View {
        HStack {
            if step > 1 {
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    if mine != nil { mine = nil } else if theirs != nil { theirs = nil } else { friend = nil; friendBros = [] }
                    problem = nil
                } label: { Image(systemName: "chevron.left").font(.headline).foregroundStyle(Theme.accent) }
                .buttonStyle(GMPress())
                .accessibilityLabel("Voltar")
            }
            Spacer()
            Text(["Trocar com quem?", "O que você quer?", "O que você dá?", "Conferir troca"][step - 1]).font(.headline)
            Spacer()
            Text("\(step)/4").font(.caption.bold().monospacedDigit()).foregroundStyle(Theme.dim)
        }
    }

    // 1. Amigo

    private var friendStep: some View {
        let friends = FriendsStore.shared.friends.filter {
            query.isEmpty || $0.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
                .contains(query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil))
        }
        return VStack(alignment: .leading, spacing: 10) {
            if FriendsStore.shared.friends.isEmpty {
                GMEmptyState(icon: "person.2", title: "Sem amigos ainda", message: "Troca é só entre amigos. Adicione alguém pelo código de amigo.")
            } else {
                if FriendsStore.shared.friends.count > 6 { GMSearchField(placeholder: "Buscar amigo", text: $query) }
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(friends) { f in
                            Button {
                                UISelectionFeedbackGenerator().selectionChanged()
                                friend = f
                                Task { await load(f) }
                            } label: {
                                HStack(spacing: 12) {
                                    MonsterSprite(form: f.form).frame(width: 36, height: 36).frame(width: 42)
                                    Text(f.name).font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.dim)
                                }
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                                .foregroundStyle(.white)
                            }
                            .buttonStyle(GMPress())
                            if f.id != friends.last?.id { GMDivider().padding(.leading, 54) }
                        }
                    }
                    .padding(.horizontal, 12)
                    .background(Theme.raised, in: .rect(cornerRadius: Theme.radiusM))
                }
                .frame(maxHeight: 420)
            }
        }
    }

    private func load(_ f: RemoteFriend) async {
        loading = true
        friendBros = await store.bros(of: f.id)
        loading = false
    }

    // 2. Bro do amigo

    private func theirsStep(_ f: RemoteFriend) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bros de \(f.name)").font(.subheadline).foregroundStyle(Theme.dim)
            if loading {
                ProgressView().tint(Theme.accent).frame(maxWidth: .infinity).padding(30)
            } else {
                grid(friendBros.map { b in
                    (id: b.id, card: TradeBroCard(form: b.form, name: b.name, xp: b.xp, tag: b.isEgg ? "Ovo não troca" : nil), enabled: !b.isEgg,
                     pick: { theirs = b })
                })
            }
        }
    }

    // 3. Seu bro

    private func mineStep(_ f: RemoteFriend) -> some View {
        let mineList = store.myBros()
        let free = mineList.filter { store.refusal($0.monster) == nil }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Da sua Box").font(.subheadline).foregroundStyle(Theme.dim)
            if free.isEmpty {
                Label("Nenhum bro seu pode entrar agora. Ovos, o principal e quem está em liga, X1 ou outra troca ficam de fora.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.bold()).foregroundStyle(Theme.trophy)
            }
            grid(mineList.map { m, b in
                let r = store.refusal(m)
                return (id: b.id, card: TradeBroCard(form: b.form, name: b.name, xp: b.xp, tag: r?.tag), enabled: r == nil, pick: { mine = m })
            })
        }
    }

    /// Grade de 3 colunas (não lazy) com rolagem: funciona igual com 2 ou 40 bros
    private func grid(_ items: [(id: String, card: TradeBroCard, enabled: Bool, pick: () -> Void)]) -> some View {
        ScrollView {
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                ForEach(0..<(items.count + columns - 1) / columns, id: \.self) { row in
                    GridRow {
                        ForEach(0..<columns, id: \.self) { c in
                            let i = row * columns + c
                            if i < items.count {
                                Button {
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    items[i].pick()
                                } label: { items[i].card }
                                .buttonStyle(GMPress())
                                .disabled(!items[i].enabled)
                            } else {
                                Color.clear.frame(height: 1)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxHeight: 420)
    }

    // 4. Conferir

    private func review(_ f: RemoteFriend, _ t: TradeBro, _ m: Monster) -> some View {
        let mineBro = store.myBros().first { $0.monster.uuid == m.uuid }?.bro
        return VStack(alignment: .leading, spacing: 14) {
            if let mineBro {
                TradeVersus(give: (mineBro.form, mineBro.name, mineBro.xp), get: (t.form, t.name, t.xp), friend: f.name, getOwners: t.history)
            }
            VStack(alignment: .leading, spacing: 8) {
                note("sparkles", "\(t.name) chega com \(t.xp.formatted()) XP de quem o treinou antes. Na ficha dele, esse XP fica separado do que ele ganhar com você.")
                note("arrow.uturn.right", "\(mineBro?.name ?? "O seu bro") vai para \(f.name) com o XP dele.")
                note("hourglass", "\(f.name) tem 48 h para aceitar. Até lá, dá para cancelar.")
            }
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill").font(.caption.bold()).foregroundStyle(Theme.danger)
            }
            GMButton(busy ? "Enviando…" : "Propor troca a \(f.name)", icon: "paperplane.fill", enabled: !busy) {
                busy = true
                Task {
                    defer { busy = false }
                    do {
                        try await store.propose(to: f, give: m, get: t)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        done()
                    } catch {
                        problem = error.localizedDescription
                    }
                }
            }
        }
    }

    private func note(_ icon: String, _ text: String) -> some View {
        Label { Text(text).font(.caption).foregroundStyle(.white.opacity(0.85)) } icon: {
            Image(systemName: icon).font(.caption.bold()).foregroundStyle(Theme.trophy)
        }
    }
}
