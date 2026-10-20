import SwiftUI

/// Mapa mental da evolução de uma espécie, um nível por vez e sem rolagem lateral.
/// Começa no Ovo; tocar no Bebê e no Novato desce um nível, o Novato abre os 10 Atletas e cada Atleta, as 10 Lendas dele.
/// A trilha no topo (Ovo › Bebê › Novato › Atleta) volta os níveis; tocar no centro ou numa Lenda abre a ficha.
struct EvolutionMap: View {
    let species: String
    let current: MonsterForm
    let isKnown: (MonsterForm) -> Bool
    let open: (MonsterForm) -> Void
    /// Forma no centro: o Ovo, o Bebê, o Novato ou um Atleta
    @State private var focus: MonsterForm
    @Namespace private var space

    init(species: String, current: MonsterForm, isKnown: @escaping (MonsterForm) -> Bool, open: @escaping (MonsterForm) -> Void) {
        self.species = species
        self.current = current
        self.isKnown = isKnown
        self.open = open
        _focus = State(initialValue: .egg)
    }

    private var baby: MonsterForm { MonsterForm(stage: .baby, attribute: nil, species: species) }
    private var rookie: MonsterForm { MonsterForm(stage: .rookie, attribute: nil, species: species) }
    private var center: MonsterForm { focus }

    /// Atletas na roda: cada atributo ao lado dos híbridos que o misturam
    private var champions: [MonsterForm] {
        let order: [(Attribute, Attribute?)] = [(.forca, nil), (.forca, .resistencia), (.resistencia, nil), (.resistencia, .agilidade),
                                                (.agilidade, nil), (.agilidade, .tecnica), (.tecnica, nil), (.forca, .tecnica),
                                                (.forca, .agilidade), (.resistencia, .tecnica)]
        return order.map { MonsterForm(stage: .champion, attribute: $0.0, attribute2: $0.1, species: species) }.filter(\.hasArt)
    }

    /// Lendas de um Atleta: a pura no topo, as 9 viradas em volta
    private func legends(_ champ: MonsterForm) -> [MonsterForm] {
        [MonsterForm(stage: .ultimate, attribute: champ.attribute, attribute2: champ.attribute2, species: species)]
            + MonsterForm.viradas(from: champ)
    }

    private var children: [MonsterForm] {
        switch focus.stage {
        case .egg: [baby]
        case .baby: [rookie]
        case .rookie: champions
        case .champion: legends(focus)
        default: []
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            trail
            // Um filho só (Bebê → Novato): corrente curta em pé, sem a roda vazia
            let chain = children.count == 1
            GeometryReader { g in
                let side = g.size.width
                let mid = CGPoint(x: side / 2, y: chain ? g.size.height - 70 : side / 2)
                let radius = chain ? g.size.height - 140 : side / 2 - 40
                let kids = children
                ZStack {
                    if !chain {
                        Circle()
                            .stroke(Theme.stroke, style: StrokeStyle(lineWidth: 1, dash: [2, 6]))
                            .frame(width: radius * 2, height: radius * 2)
                            .position(mid)
                    }
                    ForEach(Array(kids.enumerated()), id: \.element.id) { i, f in
                        let p = point(i, of: kids.count, around: mid, radius: radius)
                        Spoke(from: mid, to: p, inset: (46, 28))
                            .stroke(LinearGradient(colors: tints(f), startPoint: .center, endPoint: .trailing),
                                    style: StrokeStyle(lineWidth: f.isVirada ? 1.5 : 2.5, lineCap: .round, dash: f.isVirada ? [3, 5] : []))
                            .opacity(isKnown(f) ? 0.7 : 0.3)
                            .transition(.opacity)
                        node(f, size: 46).position(p)
                            .transition(.scale(scale: 0.2).combined(with: .opacity))
                    }
                    centerNode.position(mid)
                }
                .id(focus.id)
            }
            .aspectRatio(chain ? 1.5 : 1, contentMode: .fit)
            caption
        }
        .animation(.spring(duration: 0.45, bounce: 0.2), value: focus)
    }

    private func point(_ i: Int, of n: Int, around c: CGPoint, radius: CGFloat) -> CGPoint {
        let a = -Double.pi / 2 + Double(i) / Double(max(n, 1)) * 2 * .pi
        return CGPoint(x: c.x + radius * cos(a), y: c.y + radius * sin(a))
    }

    private func tints(_ f: MonsterForm) -> [Color] {
        let c = [f.attribute, f.attribute2].compactMap { $0?.color }
        return c.count > 1 ? c : [(c.first ?? Theme.dim).opacity(0.5), c.first ?? Theme.dim]
    }

    // MARK: Trilha

    private var trail: some View {
        HStack(spacing: 4) {
            crumb(.egg, on: focus.stage == .egg) { focus = .egg }
            if focus.stage >= .baby {
                chevron
                crumb(baby, on: focus.stage == .baby) { focus = baby }
            }
            if focus.stage >= .rookie {
                chevron
                crumb(rookie, on: focus.stage == .rookie) { focus = rookie }
            }
            if focus.stage == .champion {
                chevron
                crumb(focus, on: true) { open(focus) }
            }
            Spacer(minLength: 0)
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.dim).accessibilityHidden(true)
    }

    private func crumb(_ f: MonsterForm, on: Bool = false, action: @escaping () -> Void) -> some View {
        let known = isKnown(f)
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        } label: {
            HStack(spacing: 4) {
                MonsterSprite(form: f, hidden: !known).frame(width: 22, height: 22)
                if on { Text(known ? f.name : "???").font(.caption2.bold()).lineLimit(1) }
            }
            .padding(.leading, 4).padding(.trailing, on ? 9 : 4).padding(.vertical, 3)
            .background(on ? Theme.accent.opacity(0.16) : Theme.raised, in: .capsule)
            .overlay(Capsule().stroke(on ? Theme.accent.opacity(0.5) : .clear, lineWidth: 1))
            .foregroundStyle(.white)
        }
        .buttonStyle(GMPress())
        .accessibilityLabel(known ? f.name : "Forma não descoberta")
    }

    // MARK: Nós

    private var centerNode: some View {
        let f = center
        let known = isKnown(f)
        let tint = f.attribute?.color ?? Theme.accent
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            open(f)
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Circle().fill(tint.opacity(0.22)).frame(width: 96, height: 96).blur(radius: 18)
                    Group {
                        if known { LivingMonster(form: f) } else { MonsterSprite(form: f, hidden: true) }
                    }
                    .frame(width: 70, height: 70)
                    .frame(width: 86, height: 86)
                    .background(Theme.card, in: .circle)
                    .overlay(Circle().stroke(tint.opacity(0.8), lineWidth: 2.5))
                }
                .overlay(alignment: .top) { if current == f { youTag.offset(y: -6) } }
            }
            .foregroundStyle(.white)
        }
        .buttonStyle(GMPress())
        .matchedGeometryEffect(id: f.id, in: space)
        .accessibilityLabel(known ? "\(f.name), \(f.stage.name), no centro" : "Forma não descoberta")
        .accessibilityHint("Abre a ficha")
    }

    private func node(_ f: MonsterForm, size: CGFloat) -> some View {
        let known = isKnown(f)
        let tint = f.attribute?.color ?? Theme.accent
        let isCurrent = current == f || (f.stage == .champion && current.champion == f)
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            if f.stage < .ultimate { focus = f } else { open(f) }
        } label: {
            VStack(spacing: 3) {
                MonsterSprite(form: f, hidden: !known)
                    .frame(width: size - 8, height: size - 8)
                    .frame(width: size, height: size)
                    .background(known ? tint.opacity(0.16) : Theme.raised, in: .circle)
                    .overlay(ring(f, tint: tint, known: known, current: isCurrent))
                    .overlay(alignment: .top) { if current == f { youTag.offset(y: -7) } }
                    .overlay(alignment: .bottomTrailing) {
                        if f.stage == .baby || f.stage == .rookie {
                            Image(systemName: "plus").font(.system(size: 9, weight: .black)).foregroundStyle(.black)
                                .frame(width: 18, height: 18).background(Theme.accent, in: .circle)
                                .overlay(Circle().stroke(Theme.bg, lineWidth: 2))
                                .offset(x: 3, y: 3)
                        }
                    }
                Text(known ? f.name : "???").font(.system(size: 9, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
                    .frame(width: 66)
            }
            .foregroundStyle(.white)
        }
        .buttonStyle(GMPress())
        .matchedGeometryEffect(id: f.id, in: space)
        .accessibilityLabel(known ? "\(f.name), \(f.stage.name)" : "Forma não descoberta")
        .accessibilityHint(f.stage == .champion ? "Mostra as Lendas dele" : f.stage == .rookie ? "Mostra os Atletas" : f.stage == .baby ? "Mostra o Novato" : "Abre a ficha")
    }

    /// Híbrido: anel nas duas cores. Virada: anel tracejado. Seu bro (ou a linha dele): anel verde.
    @ViewBuilder
    private func ring(_ f: MonsterForm, tint: Color, known: Bool, current: Bool) -> some View {
        let colors = [f.attribute, f.attribute2].compactMap { $0?.color }
        if current {
            Circle().stroke(Theme.accent, lineWidth: 2.5)
        } else if colors.count > 1 {
            Circle().stroke(AngularGradient(colors: colors + [colors[0]], center: .center),
                            style: StrokeStyle(lineWidth: 2, dash: f.isVirada ? [3, 3] : []))
                .opacity(known ? 1 : 0.4)
        } else {
            Circle().stroke(known ? tint.opacity(0.7) : Theme.stroke, style: StrokeStyle(lineWidth: 1.5, dash: f.isVirada ? [3, 3] : []))
        }
    }

    private var youTag: some View {
        Text("VOCÊ").gmFont(7, weight: .black, relativeTo: .caption2)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Theme.accent, in: .capsule).foregroundStyle(.black)
    }

    // MARK: Legenda

    private var caption: some View {
        VStack(alignment: .leading, spacing: 8) {
            if focus.stage == .egg {
                Text("Todo bro começa como ovo").font(.subheadline.bold())
                Text("O ovo choca com 60 XP, e os treinos feitos nele decidem a espécie. \(Species.byID(species)?.hatchHint ?? "") Toque no Bebê para continuar.")
                    .font(.caption).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
            } else if focus.stage == .baby {
                Text("\(isKnown(baby) ? baby.name : "???"), o Bebê").font(.subheadline.bold())
                Text("Sai do ovo com 60 XP e vira Novato com 300 XP, com qualquer treino. Toque no Novato para ver os Atletas.")
                    .font(.caption).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
            } else if focus.stage == .champion {
                Text("Lendas de \(isKnown(focus) ? focus.name : "???")").font(.subheadline.bold())
                Text("Na fase Atleta, o treino decide: seguiu no mesmo, sai a Lenda pura. Mudou, sai uma Lenda de virada, que só este Atleta alcança.")
                    .font(.caption).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    legend(dashed: false, "Pura")
                    legend(dashed: true, "Virada")
                }
            } else {
                Text("Atletas de \(isKnown(rookie) ? rookie.name : "???")").font(.subheadline.bold())
                Text("Na fase Novato, o atributo mais treinado escolhe o Atleta. Dois quase empatados viram um híbrido (anel de duas cores). Toque num Atleta para ver as Lendas dele.")
                    .font(.caption).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card, in: .rect(cornerRadius: Theme.radius))
        .animation(nil, value: focus)
    }

    private func legend(dashed: Bool, _ text: String) -> some View {
        HStack(spacing: 6) {
            Path { p in p.move(to: CGPoint(x: 0, y: 1)); p.addLine(to: CGPoint(x: 22, y: 1)) }
                .stroke(Theme.dim, style: StrokeStyle(lineWidth: 2, dash: dashed ? [3, 4] : []))
                .frame(width: 22, height: 2)
            Text(text).font(.caption).foregroundStyle(Theme.dim)
        }
    }
}

/// Raio do centro até um nó, levemente curvo, sem encostar nos círculos
private struct Spoke: Shape {
    let from: CGPoint
    let to: CGPoint
    let inset: (start: CGFloat, end: CGFloat)

    func path(in rect: CGRect) -> Path {
        let dx = to.x - from.x, dy = to.y - from.y
        let len = max(sqrt(dx * dx + dy * dy), 1)
        let ux = dx / len, uy = dy / len
        let a = CGPoint(x: from.x + ux * inset.start, y: from.y + uy * inset.start)
        let b = CGPoint(x: to.x - ux * inset.end, y: to.y - uy * inset.end)
        let bend: CGFloat = 14
        let c = CGPoint(x: (a.x + b.x) / 2 - uy * bend, y: (a.y + b.y) / 2 + ux * bend)
        var p = Path()
        p.move(to: a)
        p.addQuadCurve(to: b, control: c)
        return p
    }
}

extension Species {
    /// "O Lobo nasce de corrida, bike ou natação."
    var hatchHint: String {
        let names = kinds.filter { $0 != .outro }.map { $0.name.lowercased() }
        let article = id == "coruja" ? "A" : "O"
        guard id != Species.standard.id, !names.isEmpty else { return "\(article) \(name) nasce de treinos variados ou de \"Outro\"." }
        let list = names.count > 1 ? names.dropLast().joined(separator: ", ") + " ou " + names.last! : names[0]
        return "\(article) \(name) nasce de \(list)."
    }
}
