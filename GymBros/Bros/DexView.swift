import SwiftUI

struct DexView: View {
    let snapshot: Snapshot
    let discovered: Set<String>
    let achievements: [Achievement]
    /// Aberta pela tela do bro: voltar em vez da bolinha do perfil
    var modal = false
    @State private var tab = 0
    @State private var entry: MonsterForm?

    var body: some View {
        NavigationStack {
            GMScreen("Bros", subtitle: subtitle, back: modal, avatar: !modal) {
                hero
                GMSegmented(options: [(0, "Meus bros"), (1, "BroBook"), (2, "Conquistas")], selection: $tab)
                switch tab {
                case 0: MyBrosList()
                case 1: monsters
                default: trophies
                }
            }
            .sheet(item: $entry) {
                DexEntryView(form: $0, snapshot: snapshot, isKnown: { [revealAll, discovered] f in revealAll || discovered.contains(f.id) })
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(Theme.radiusXL)
                    .presentationBackground(Theme.bg)
                    .preferredColorScheme(.dark)
                    .tint(Theme.accent)
            }
        }
    }

    private var subtitle: String {
        switch tab {
        case 0: "Seu principal e os que te representam nas ligas"
        case 1: "Todas as formas de todas as espécies"
        default: "Marcas que você já bateu e as que faltam"
        }
    }

    // MARK: Coleção

    private var knownCount: Int { DexView.allForms.filter { discovered.contains($0.id) }.count }
    private var dexProgress: Double { Double(knownCount) / Double(max(DexView.allForms.count, 1)) }
    private var hatchedSpecies: Int {
        Species.all.filter { sp in discovered.contains(MonsterForm(stage: .baby, attribute: nil, species: sp.id).id) }.count
    }
    private var unlocked: Int { achievements.filter(\.unlocked).count }

    /// Seu bro em destaque, o anel do BroBook e os números da coleção
    private var hero: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(Theme.track, lineWidth: 7)
                Circle().trim(from: 0, to: dexProgress)
                    .stroke(AngularGradient(colors: [Theme.accent, Attribute.resistencia.color, Attribute.tecnica.color, Theme.accent], center: .center),
                            style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                LivingMonster(form: snapshot.form, progress: snapshot.progress).frame(width: 68, height: 68)
            }
            .frame(width: 96, height: 96)
            .animation(.spring(duration: 0.6), value: dexProgress)
            VStack(alignment: .leading, spacing: 8) {
                Text("\(Int((dexProgress * 100).rounded())) % do BroBook")
                    .gmFont(24, weight: .heavy, design: .rounded, relativeTo: .title2)
                stat("sparkles", Theme.accent, "\(knownCount) de \(DexView.allForms.count) formas")
                stat("pawprint.fill", Attribute.agilidade.color, "\(hatchedSpecies) de \(Species.all.filter(\.isReady).count) espécies chocadas")
                stat("trophy.fill", Theme.trophy, "\(unlocked) de \(achievements.count) conquistas")
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .topLeading) {
                Theme.card
                Circle().fill(Theme.accent.opacity(0.2)).frame(width: 200).blur(radius: 60).offset(x: -60, y: -70)
                Circle().fill(Attribute.tecnica.color.opacity(0.14)).frame(width: 180).blur(radius: 60).offset(x: 220, y: 40)
            }
            .clipShape(.rect(cornerRadius: Theme.radius))
        }
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(.white.opacity(0.08), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private func stat(_ icon: String, _ tint: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption.bold()).foregroundStyle(tint).frame(width: 16)
            Text(text).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
        }
    }

    // MARK: Conquistas

    private var trophies: some View {
        VStack(alignment: .leading, spacing: 14) {
            GMCard {
                HStack {
                    Text("Desbloqueadas").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(unlocked)/\(achievements.count)").font(.subheadline.bold().monospacedDigit()).foregroundStyle(Theme.trophy)
                }
                GMProgressBar(value: Double(unlocked) / Double(max(achievements.count, 1)), tint: Theme.trophy)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(achievements.sorted { ($0.unlocked ? 0 : 1, -$0.progress) < ($1.unlocked ? 0 : 1, -$1.progress) }) { a in
                    trophy(a)
                }
            }
        }
    }

    private func trophy(_ a: Achievement) -> some View {
        VStack(spacing: 8) {
            Image(systemName: a.symbol)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(a.unlocked ? .black : Theme.dim)
                .frame(width: 54, height: 54)
                .background {
                    if a.unlocked {
                        Circle().fill(LinearGradient(colors: [Theme.trophy, Theme.streak], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .shadow(color: Theme.trophy.opacity(0.45), radius: 10)
                    } else {
                        Circle().fill(Theme.raised)
                    }
                }
            Text(a.title).font(.subheadline.bold()).multilineTextAlignment(.center)
            Text(a.detail).font(.caption).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
            Spacer(minLength: 0)
            if a.unlocked {
                Label("Feito", systemImage: "checkmark.seal.fill").font(.caption2.bold()).foregroundStyle(Theme.trophy)
            } else {
                HStack(spacing: 6) {
                    GMProgressBar(value: a.progress, tint: Theme.trophy, height: 5)
                    Text("\(Int(a.progress * 100))%").gmFont(10, weight: .bold, mono: true, relativeTo: .caption2).foregroundStyle(Theme.dim)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 176)
        .background(Theme.card, in: .rect(cornerRadius: Theme.radius))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(a.unlocked ? Theme.trophy.opacity(0.4) : .clear, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    /// Todas as formas de todas as espécies com arte (o ovo conta uma vez)
    static var allForms: [MonsterForm] {
        [.egg] + Species.catalog.flatMap { MonsterForm.all(species: $0.id).filter { $0.stage != .egg } + MonsterForm.hybrids(species: $0.id).filter(\.hasArt) }
    }

    @State private var speciesID = Species.standard.id
    /// Modo de visualização: mostra todas as formas sem silhueta (não conta como descoberta)
    @AppStorage("dexRevealAll") private var revealAll = false

    private func isKnown(_ f: MonsterForm) -> Bool { revealAll || discovered.contains(f.id) }

    private var monsters: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("ESPÉCIES").font(.caption.weight(.bold)).foregroundStyle(Theme.dim).tracking(0.6)
                Spacer()
                GMChip(title: revealAll ? "Revelando" : "Revelar todas", icon: revealAll ? "eye.fill" : "eye.slash", selected: revealAll) {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.snappy) { revealAll.toggle() }
                }
                .accessibilityHint("Mostra todas as formas, sem contar como descoberta")
            }
            .padding(.horizontal, 4)
            speciesPicker
            if let sp = Species.byID(speciesID), sp.isReady {
                tree(sp)
            }
        }
    }

    // MARK: Espécies

    private func forms(_ sp: Species) -> [MonsterForm] {
        MonsterForm.all(species: sp.id).filter { $0.stage != .egg } + MonsterForm.hybrids(species: sp.id).filter(\.hasArt)
    }
    private func found(_ sp: Species) -> [MonsterForm] { forms(sp).filter { isKnown($0) } }

    private var speciesPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Species.all.filter(\.isReady)) { sp in speciesCard(sp) }
            }
            .padding(.horizontal, 2)
        }
    }

    private func speciesCard(_ sp: Species) -> some View {
        let ready = sp.isReady
        let seen = found(sp).count, total = forms(sp).count
        // Sempre o bebê, que representa a espécie sem puxar para nenhum galho
        let baby = MonsterForm(stage: .baby, attribute: nil, species: sp.id)
        let selected = speciesID == sp.id
        return Button {
            guard ready else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.snappy) { speciesID = sp.id }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle().fill(selected ? Theme.accent.opacity(0.22) : Theme.raised).blur(radius: selected ? 10 : 0)
                    if ready { MonsterSprite(form: baby, hidden: !isKnown(baby)).padding(6) } else {
                        Image(systemName: "lock.fill").font(.title3.bold()).foregroundStyle(Theme.dim)
                    }
                }
                .frame(width: 68, height: 68)
                Text(sp.name).font(.caption.bold()).lineLimit(1)
                if ready {
                    GMProgressBar(value: Double(seen) / Double(max(total, 1)), tint: seen == total ? Theme.trophy : Theme.accent, height: 4)
                        .padding(.horizontal, 10)
                    Text("\(seen)/\(total)").gmFont(10, weight: .semibold, mono: true, relativeTo: .caption2).foregroundStyle(Theme.dim)
                } else {
                    Text("Em breve").font(.caption2).foregroundStyle(Theme.dim)
                }
            }
            .frame(width: 100)
            .padding(.vertical, 12)
            .background(Theme.card, in: .rect(cornerRadius: Theme.radius))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(selected ? Theme.accent : Theme.stroke, lineWidth: selected ? 2 : 1))
            .opacity(ready ? 1 : 0.45)
        }
        .buttonStyle(GMPress())
        .accessibilityLabel(ready ? "\(sp.name), \(seen) de \(total) formas" : "\(sp.name), em breve")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// De onde a espécie nasce (as atividades do app; as do Apple Saúde seguem a mesma ideia)
    private func hatchText(_ sp: Species) -> String {
        let names = sp.kinds.filter { $0 != .outro }.map { $0.name.lowercased() }
        let list = names.count > 1 ? names.dropLast().joined(separator: ", ") + " ou " + names.last! : names.first ?? ""
        return sp.id == Species.standard.id
            ? "Nasce quando o ovo choca com \"Outro\" ou com treinos variados, sem atividade principal"
            : "Nasce quando o ovo choca com \(list) (e parecidos no Apple Saúde)"
    }

    // MARK: Árvore

    private func tree(_ sp: Species) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Cabeçalho da espécie: nome, de onde nasce e as atividades
            GMCard {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(sp.name).gmFont(26, weight: .heavy, design: .rounded, relativeTo: .title)
                        Text(hatchText(sp)).font(.caption).foregroundStyle(Theme.dim)
                    }
                    Spacer()
                    Text("\(found(sp).count)/\(forms(sp).count)")
                        .font(.subheadline.bold().monospacedDigit())
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Theme.accent.opacity(0.15), in: .capsule)
                        .foregroundStyle(Theme.accent)
                }
                let kinds = sp.kinds.filter { $0 != .outro }
                if !kinds.isEmpty {
                    GMFlow {
                        ForEach(kinds, id: \.self) { k in
                            Label(k.name, systemImage: k.symbol)
                                .font(.caption2.bold())
                                .padding(.horizontal, 9).padding(.vertical, 5)
                                .background(Theme.raised, in: .capsule)
                        }
                    }
                }
            }

            section("Começo", "Todo bro passa por aqui")
            GMCard {
                HStack(spacing: 2) {
                    node(.egg, size: 60)
                    connector(Theme.dim)
                    node(MonsterForm(stage: .baby, attribute: nil, species: sp.id), size: 60)
                    connector(Theme.dim)
                    node(MonsterForm(stage: .rookie, attribute: nil, species: sp.id), size: 60)
                }
            }

            section("Galhos", "O atributo mais treinado em cada fase escolhe o galho")
            ForEach(Attribute.allCases) { a in
                branch(colors: [a.color]) {
                    Label(a.name, systemImage: a.symbol).foregroundStyle(a.color)
                } champion: { MonsterForm(stage: .champion, attribute: a, species: sp.id) }
                  ultimate: { MonsterForm(stage: .ultimate, attribute: a, species: sp.id) }
            }

            // Híbridos: dois atributos quase empatados na fase (aparecem quando houver arte)
            if sp.hasHybrids {
                section("Formas híbridas", "Os dois atributos mais treinados quase empatados (até 10% de diferença)")
                ForEach(Array(Attribute.pairs.enumerated()), id: \.offset) { _, pair in
                    let (a, b) = pair
                    let champ = MonsterForm(stage: .champion, attribute: a, attribute2: b, species: sp.id)
                    if champ.hasArt {
                        branch(colors: [a.color, b.color]) {
                            HStack(spacing: 4) {
                                Image(systemName: a.symbol).foregroundStyle(a.color)
                                Text("+").foregroundStyle(Theme.dim)
                                Image(systemName: b.symbol).foregroundStyle(b.color)
                                Text("\(a.name) e \(b.name)").foregroundStyle(.white)
                            }
                        } champion: { champ }
                          ultimate: { MonsterForm(stage: .ultimate, attribute: a, attribute2: b, species: sp.id) }
                    }
                }
            }
        }
    }

    private func section(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).font(.caption.weight(.bold)).foregroundStyle(Theme.dim).tracking(0.6)
            Text(detail).font(.caption).foregroundStyle(Theme.dim)
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    /// Um galho: faixa na cor do atributo, nome no topo e Atleta → Lenda
    private func branch<L: View>(colors: [Color], @ViewBuilder label: () -> L,
                                 champion: () -> MonsterForm, ultimate: () -> MonsterForm) -> some View {
        let tint = colors.first ?? Theme.accent
        return VStack(alignment: .leading, spacing: 10) {
            label().font(.caption.bold())
            HStack(spacing: 2) {
                node(champion(), size: 76, tint: tint)
                connector(tint)
                node(ultimate(), size: 76, tint: colors.last ?? tint)
            }
        }
        .padding(14)
        .padding(.leading, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: Theme.radius))
        .overlay(alignment: .leading) {
            LinearGradient(colors: colors.count > 1 ? colors : [tint, tint.opacity(0.4)], startPoint: .top, endPoint: .bottom)
                .frame(width: 4)
                .clipShape(.capsule)
                .padding(.vertical, 14)
                .padding(.leading, 6)
        }
    }

    private func connector(_ tint: Color) -> some View {
        Image(systemName: "chevron.right")
            .font(.caption2.bold())
            .foregroundStyle(tint.opacity(0.7))
            .accessibilityHidden(true)
    }

    private func node(_ f: MonsterForm, size: CGFloat, tint: Color = Theme.accent) -> some View {
        let known = isKnown(f)
        let current = snapshot.form == f
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            entry = f
        } label: { nodeLabel(f, size: size, tint: tint, known: known, current: current) }
        .buttonStyle(GMPress())
        .accessibilityLabel(known ? "\(f.name), \(f.stage.name)\(current ? ", seu bro atual" : "")" : "Forma não descoberta")
        .accessibilityHint("Abre a ficha")
    }

    private func nodeLabel(_ f: MonsterForm, size: CGFloat, tint: Color, known: Bool, current: Bool) -> some View {
        VStack(spacing: 4) {
            ZStack {
                if known { Circle().fill(tint.opacity(0.16)).frame(width: size * 0.95, height: size * 0.95).blur(radius: 8) }
                MonsterSprite(form: f, hidden: !known).frame(width: size, height: size)
            }
            Text(known ? f.name : "???").font(.caption.bold()).lineLimit(1).minimumScaleFactor(0.7)
            Text(f.stage == .egg ? "início" : "\(f.stage.name) · \(f.stage.threshold) XP")
                .gmFont(9, mono: true, relativeTo: .caption2).foregroundStyle(Theme.dim).lineLimit(1).minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(current ? Theme.accent.opacity(0.12) : .clear, in: .rect(cornerRadius: Theme.radiusM))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusM).stroke(current ? Theme.accent : .clear, lineWidth: 1.5))
        .overlay(alignment: .top) {
            if current {
                Text("VOCÊ").gmFont(8, weight: .black, relativeTo: .caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.accent, in: .capsule)
                    .foregroundStyle(.black)
                    .offset(y: -7)
            }
        }
        .contentShape(Rectangle())
    }
}
