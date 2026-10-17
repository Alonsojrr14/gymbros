import SwiftUI

struct DexView: View {
    let snapshot: Snapshot
    let discovered: Set<String>
    let achievements: [Achievement]
    @State private var tab = 0

    var body: some View {
        NavigationStack {
            GMScreen(tab == 0 ? "Dex" : "Conquistas",
                     subtitle: tab == 0 ? "\(discovered.count) de \(DexView.allForms.count) formas descobertas"
                                        : "\(achievements.filter(\.unlocked).count) de \(achievements.count) desbloqueadas",
                     avatar: true) {
                GMSegmented(options: [(0, "Bros"), (1, "Conquistas")], selection: $tab)
                if tab == 0 { monsters } else { trophies }
            }
        }
    }

    private var trophies: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(achievements.sorted { ($0.unlocked ? 0 : 1, -$0.progress) < ($1.unlocked ? 0 : 1, -$1.progress) }) { a in
                VStack(spacing: 8) {
                    Image(systemName: a.symbol)
                        .font(.system(size: 30))
                        .foregroundStyle(a.unlocked ? Color.yellow : Theme.dim)
                        .frame(height: 38)
                    Text(a.title).font(.subheadline.bold()).multilineTextAlignment(.center)
                    Text(a.detail).font(.caption).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                    if !a.unlocked {
                        GMProgressBar(value: a.progress, height: 6)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 150)
                .background(Theme.card, in: .rect(cornerRadius: 18))
                .opacity(a.unlocked ? 1 : 0.7)
            }
        }

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
            GMCard { GMToggle(title: "Revelar todas", subtitle: "Mostra todas as formas, sem contar como descoberta", isOn: $revealAll) }
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
                ForEach(Species.all) { sp in speciesCard(sp) }
            }
            .padding(.horizontal, 2)
        }
    }

    private func speciesCard(_ sp: Species) -> some View {
        let ready = sp.isReady
        let seen = found(sp)
        // Sempre o bebê, que representa a espécie sem puxar para nenhum galho
        let baby = MonsterForm(stage: .baby, attribute: nil, species: sp.id)
        let selected = speciesID == sp.id
        return Button {
            guard ready else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.snappy) { speciesID = sp.id }
        } label: {
            VStack(spacing: 6) {
                Group {
                    if ready { MonsterSprite(form: baby, hidden: !isKnown(baby)) } else {
                        Image(systemName: "questionmark").font(.title.bold()).foregroundStyle(Theme.dim)
                    }
                }
                .frame(width: 64, height: 64)
                Text(sp.name).font(.caption.bold())
                if ready {
                    Text("\(seen.count)/\(forms(sp).count)").font(.caption2.monospacedDigit()).foregroundStyle(Theme.dim)
                } else {
                    Text("Em breve").font(.caption2).foregroundStyle(Theme.dim)
                }
                if let a = sp.affinity {
                    Image(systemName: a.symbol).font(.caption2).foregroundStyle(ready ? a.color : Theme.dim)
                } else {
                    Image(systemName: "circle.grid.cross").font(.caption2).foregroundStyle(Theme.dim)
                }
            }
            .frame(width: 92)
            .padding(.vertical, 12)
            .background(Theme.card, in: .rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(selected ? Theme.accent : .clear, lineWidth: 2))
            .opacity(ready ? 1 : 0.45)
        }
        .buttonStyle(GMPress())
    }

    // MARK: Árvore

    private func tree(_ sp: Species) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(sp.name).font(.title2.weight(.heavy))
                    Text(sp.affinity.map { "Nasce de ovos chocados com treinos de \($0.name)" } ?? "Nasce quando nenhuma outra espécie combina")
                        .font(.caption).foregroundStyle(Theme.dim)
                }
                Spacer()
            }

            // Ovo → Bebê → Rookie
            GMCard {
                HStack(spacing: 4) {
                    node(.egg, size: 64)
                    arrow
                    node(MonsterForm(stage: .baby, attribute: nil, species: sp.id), size: 64)
                    arrow
                    node(MonsterForm(stage: .rookie, attribute: nil, species: sp.id), size: 64)
                }
            }

            Text("O atributo mais treinado em cada fase escolhe o galho")
                .font(.caption).foregroundStyle(Theme.dim).padding(.horizontal, 4)

            // Um galho por atributo: Champion → Ultimate
            ForEach(Attribute.allCases) { a in
                GMCard {
                    HStack(spacing: 6) {
                        VStack(spacing: 4) {
                            Image(systemName: a.symbol).font(.title3).foregroundStyle(a.color)
                            Text(a.name).font(.caption2.bold()).foregroundStyle(a.color).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(width: 62)
                        node(MonsterForm(stage: .champion, attribute: a, species: sp.id), size: 76)
                        arrow
                        node(MonsterForm(stage: .ultimate, attribute: a, species: sp.id), size: 76)
                    }
                }
            }

            // Híbridos: dois atributos quase empatados na fase (aparecem quando houver arte)
            if sp.hasHybrids {
                Text("Formas híbridas").font(.headline).padding(.top, 6)
                Text("Quando os dois atributos mais treinados ficam quase empatados (diferença de até 10%)")
                    .font(.caption).foregroundStyle(Theme.dim)
                ForEach(Array(Attribute.pairs.enumerated()), id: \.offset) { _, pair in
                    let (a, b) = pair
                    let champ = MonsterForm(stage: .champion, attribute: a, attribute2: b, species: sp.id)
                    if champ.hasArt {
                        GMCard {
                            HStack(spacing: 6) {
                                VStack(spacing: 2) {
                                    HStack(spacing: 2) {
                                        Image(systemName: a.symbol).foregroundStyle(a.color)
                                        Image(systemName: b.symbol).foregroundStyle(b.color)
                                    }
                                    .font(.subheadline)
                                    Text("\(a.name) + \(b.name)").font(.system(size: 9, weight: .bold)).multilineTextAlignment(.center)
                                }
                                .frame(width: 62)
                                node(champ, size: 76)
                                arrow
                                node(MonsterForm(stage: .ultimate, attribute: a, attribute2: b, species: sp.id), size: 76)
                            }
                        }
                    }
                }
            }
        }
    }

    private var arrow: some View {
        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.dim)
    }

    private func node(_ f: MonsterForm, size: CGFloat) -> some View {
        let known = isKnown(f)
        let current = snapshot.form == f
        return VStack(spacing: 4) {
            MonsterSprite(form: f, hidden: !known).frame(width: size, height: size)
            Text(known ? f.name : "???").font(.caption.bold()).lineLimit(1).minimumScaleFactor(0.7)
            Text(f.stage == .egg ? "início" : "\(f.stage.name) · \(f.stage.threshold) XP")
                .font(.system(size: 9).monospacedDigit()).foregroundStyle(Theme.dim).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(current ? Theme.accent.opacity(0.12) : .clear, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(current ? Theme.accent : .clear, lineWidth: 1.5))
    }
}
