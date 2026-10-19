import SwiftUI

/// Ficha de uma forma no BroBook, num sheet: arte, tipos, números, descrição, como conseguir e linha evolutiva.
/// As formas da linha evolutiva abrem a ficha delas aqui mesmo.
struct DexEntryView: View {
    let snapshot: Snapshot
    let isKnown: (MonsterForm) -> Bool
    @State private var form: MonsterForm
    @Environment(\.dismiss) private var dismiss

    init(form: MonsterForm, snapshot: Snapshot, isKnown: @escaping (MonsterForm) -> Bool) {
        self.snapshot = snapshot
        self.isKnown = isKnown
        _form = State(initialValue: form)
    }

    private var known: Bool { isKnown(form) }
    private var tint: Color { known ? form.attribute?.color ?? Theme.accent : Theme.dim }
    private var tint2: Color { known ? form.attribute2?.color ?? tint : Theme.dim }
    private var number: String { String(format: "Nº %03d", DexView.allForms.firstIndex(of: form) ?? 0) }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                hero
                identity
                stats
                if let mine = mineText { mineCard(mine) }
                flavor
                howTo
                evolution
            }
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(Theme.bg)
        .animation(.snappy, value: form)
        .sensoryFeedback(.selection, trigger: form)
    }

    // MARK: Topo

    private var hero: some View {
        ZStack {
            LinearGradient(colors: [tint.opacity(0.45), tint2.opacity(0.18), Theme.bg], startPoint: .top, endPoint: .bottom)
            PixelGrid().opacity(0.06)
            Circle().fill(tint.opacity(0.35)).frame(width: 220).blur(radius: 60).offset(y: 20)
            Group {
                if known { LivingMonster(form: form) } else { MonsterSprite(form: form, hidden: true) }
            }
            .frame(width: 168, height: 168)
            .shadow(color: .black.opacity(0.35), radius: 12, y: 10)
            .offset(y: 14)
            .id(form)
            .transition(.scale(scale: 0.85).combined(with: .opacity))
        }
        .frame(height: 280)
        .overlay(alignment: .topLeading) {
            Text(number)
                .gmFont(15, weight: .heavy, mono: true, relativeTo: .subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.black.opacity(0.25), in: .capsule)
                .padding(.top, 22).padding(.leading, 20)
        }
        .overlay(alignment: .topTrailing) {
            GMIconButton(icon: "xmark", size: 34, label: "Fechar") { dismiss() }
                .padding(.top, 18).padding(.trailing, 18)
        }
    }

    private var identity: some View {
        VStack(spacing: 10) {
            Text(known ? form.name : "???")
                .gmFont(34, weight: .heavy, design: .rounded, relativeTo: .largeTitle)
                .contentTransition(.opacity)
            HStack(spacing: 8) {
                let types = [form.attribute, form.attribute2].compactMap { $0 }
                if types.isEmpty || !known {
                    typePill(form.stage == .egg ? "Ovo" : known ? "Sem galho" : "???", icon: "circle.dotted", color: Theme.raised, text: .white)
                } else {
                    ForEach(types) { a in typePill(a.name, icon: a.symbol, color: a.color, text: .black) }
                }
            }
            if !known {
                Label("Ainda não descoberta", systemImage: "eye.slash").font(.caption.bold()).foregroundStyle(Theme.dim)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, -6)
    }

    private func typePill(_ text: String, icon: String, color: Color, text textColor: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(textColor)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(color, in: .capsule)
    }

    /// Três números lado a lado, num cartão de ficha
    private var stats: some View {
        HStack(spacing: 0) {
            stat(form.stage == .egg ? "—" : known ? form.speciesInfo.name : "???", "Espécie")
            Divider().frame(height: 34).overlay(Theme.stroke)
            stat(form.stage.name, "Fase")
            Divider().frame(height: 34).overlay(Theme.stroke)
            stat(form.stage.threshold.formatted(), "XP para chegar")
        }
        .padding(.vertical, 14)
        .background(Theme.card, in: .rect(cornerRadius: Theme.radius))
        .padding(.horizontal, 20)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: Seu bro

    private var mineText: String? {
        if snapshot.form == form {
            if let next = snapshot.xpToNext { return "Seu bro está nesta forma · nível \(snapshot.level) · faltam \(next.formatted()) XP para \(form.stage == .egg ? "chocar" : "evoluir")" }
            return "Seu bro está nesta forma · nível \(snapshot.level) · forma final"
        }
        if let e = snapshot.evolutions.first(where: { $0.form == form }) {
            return "Seu bro passou por aqui em \(e.date.formatted(date: .abbreviated, time: .omitted))"
        }
        return nil
    }

    private func mineCard(_ text: String) -> some View {
        HStack(spacing: 12) {
            LivingMonster(form: snapshot.form, progress: snapshot.progress).frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 6) {
                Text(text).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                if snapshot.form == form, snapshot.xpToNext != nil { GMProgressBar(value: snapshot.progress, height: 5) }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.12), in: .rect(cornerRadius: Theme.radius))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.accent.opacity(0.45), lineWidth: 1))
        .padding(.horizontal, 20)
    }

    // MARK: Texto

    private var flavor: some View {
        Text(known ? DexEntry.about(form) : "Você ainda não encontrou esta forma. Treine para descobrir quem ela é.")
            .font(.body)
            .foregroundStyle(.white.opacity(0.85))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 28)
    }

    private var howTo: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("Como conseguir")
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.subheadline.bold())
                    .foregroundStyle(tint == Theme.dim ? Theme.accent : tint)
                    .frame(width: 32, height: 32)
                    .background((tint == Theme.dim ? Theme.accent : tint).opacity(0.15), in: .circle)
                Text(DexEntry.howTo(form)).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }
            let kinds = DexEntry.kinds(form)
            if !kinds.isEmpty {
                Text(form.stage == .baby ? "Treinos que chocam" : "Treinos que mais ajudam").font(.caption.bold()).foregroundStyle(Theme.dim)
                GMFlow {
                    ForEach(kinds, id: \.self) { k in
                        Label(k.name, systemImage: k.symbol)
                            .font(.caption.bold())
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Theme.raised, in: .capsule)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: Theme.radius))
        .padding(.horizontal, 20)
    }

    private func heading(_ text: String) -> some View {
        Text(text.uppercased()).font(.caption.weight(.bold)).foregroundStyle(Theme.dim).tracking(0.6)
    }

    // MARK: Evolução

    /// Vem de ↓ esta forma ↓ pode virar. Quando a evolução depende do atributo, cada galho tem a sua linha.
    private var evolution: some View {
        let before = DexEntry.previous(form), after = DexEntry.next(form)
        return VStack(alignment: .leading, spacing: 10) {
            heading("Evolução")
            if !before.isEmpty {
                evoGroup("Vem de", before)
                down
            }
            evoRow(form, current: true)
                .background(tint.opacity(0.1), in: .rect(cornerRadius: Theme.radius))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(tint.opacity(0.6), lineWidth: 1.5))
            if !after.isEmpty {
                down
                evoGroup(after.count > 1 ? "Pode virar · depende do que você treinar" : "Pode virar", after)
            }
        }
        .padding(.horizontal, 20)
    }

    private var down: some View {
        Image(systemName: "arrow.down")
            .font(.subheadline.bold())
            .foregroundStyle(Theme.dim)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    /// Galhos de um atributo só primeiro; os híbridos (dois atributos) num bloco à parte
    private func evoGroup(_ title: String, _ forms: [MonsterForm]) -> some View {
        let singles = forms.filter { !$0.isHybrid }, hybrids = forms.filter(\.isHybrid)
        return VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.bold()).foregroundStyle(Theme.dim).padding(.leading, 4)
            rows(singles)
            if !hybrids.isEmpty {
                Text("Híbridos · dois atributos quase empatados").font(.caption.bold()).foregroundStyle(Theme.dim)
                    .padding(.leading, 4).padding(.top, 6)
                rows(hybrids)
            }
        }
    }

    private func rows(_ forms: [MonsterForm]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(forms.enumerated()), id: \.element) { i, f in
                if i > 0 { GMDivider().padding(.leading, 74) }
                evoRow(f, current: false)
            }
        }
        .background(Theme.card, in: .rect(cornerRadius: Theme.radius))
    }

    private func evoRow(_ f: MonsterForm, current: Bool) -> some View {
        let seen = isKnown(f)
        let colors = [f.attribute, f.attribute2].compactMap { $0?.color }
        let color = colors.first ?? Theme.accent
        return Button {
            form = f
        } label: {
            HStack(spacing: 12) {
                MonsterSprite(form: f, hidden: !seen)
                    .frame(width: 40, height: 40)
                    .frame(width: 50, height: 50)
                    .background(color.opacity(seen ? 0.18 : 0.06), in: .circle)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(seen ? f.name : "???").font(.subheadline.bold())
                        if current {
                            Text("ESTA").gmFont(9, weight: .black, relativeTo: .caption2)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(color, in: .capsule)
                                .foregroundStyle(.black)
                        }
                    }
                    condition(f)
                }
                Spacer(minLength: 0)
                if !current { Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.dim) }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .overlay(alignment: .leading) {
                if !colors.isEmpty {
                    LinearGradient(colors: colors.count > 1 ? colors : [color, color.opacity(0.4)], startPoint: .top, endPoint: .bottom)
                        .frame(width: 3).clipShape(.capsule).padding(.vertical, 12)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(GMPress())
        .disabled(current)
        .accessibilityLabel(seen ? "\(f.name), \(f.stage.name)" : "Forma não descoberta")
    }

    /// O que leva a esta forma: atributo(s) do galho, espécie do bebê ou só o XP
    @ViewBuilder
    private func condition(_ f: MonsterForm) -> some View {
        HStack(spacing: 6) {
            switch f.stage {
            case .egg:
                Text("Início").foregroundStyle(Theme.dim)
            case .baby:
                Text(f.speciesInfo.name).foregroundStyle(Theme.accent)
                let kinds = f.speciesInfo.kinds.filter { $0 != .outro }.prefix(3).map(\.name)
                Text(kinds.isEmpty ? "treinos variados" : kinds.joined(separator: ", ")).foregroundStyle(Theme.dim).lineLimit(1)
            case .rookie:
                Text("\(f.stage.name) · \(f.stage.threshold.formatted()) XP").foregroundStyle(Theme.dim)
            case .champion, .ultimate:
                ForEach([f.attribute, f.attribute2].compactMap { $0 }) { a in
                    Label(a.name, systemImage: a.symbol).foregroundStyle(a.color)
                }
                Text("· \(f.stage.threshold.formatted()) XP").foregroundStyle(Theme.dim)
            }
        }
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

/// Grade de pixels bem fraquinha no fundo da arte (combina com o pixel art dos bros)
private struct PixelGrid: View {
    var body: some View {
        Canvas { ctx, size in
            let step: CGFloat = 12
            var path = Path()
            for x in stride(from: 0, through: size.width, by: step) { path.addRect(CGRect(x: x, y: 0, width: 1, height: size.height)) }
            for y in stride(from: 0, through: size.height, by: step) { path.addRect(CGRect(x: 0, y: y, width: size.width, height: 1)) }
            ctx.fill(path, with: .color(.white))
        }
        .accessibilityHidden(true)
    }
}

/// Textos e ligações da ficha (sem tela, para dar para testar)
enum DexEntry {
    static func about(_ f: MonsterForm) -> String {
        switch f.stage {
        case .egg: return "Alguma coisa se mexe aqui dentro. Os primeiros treinos decidem quem vai sair."
        case .baby: return "\(f.name) acabou de chocar e já quer ir pro treino. Ainda não sabe do que mais gosta."
        case .rookie: return "\(f.name) já pegou o ritmo. O que você treinar daqui pra frente decide o caminho dele."
        case .champion, .ultimate:
            let traits = [f.attribute, f.attribute2].compactMap { $0 }.map(trait)
            let lead = f.stage == .ultimate ? "\(f.name) é uma forma final." : "\(f.name) encontrou o próprio estilo."
            return ([lead] + traits).joined(separator: " ")
        }
    }

    private static func trait(_ a: Attribute) -> String {
        switch a {
        case .forca: "Vive entre anilhas e barras e fica mais forte a cada série pesada."
        case .resistencia: "Não para nunca: quanto mais longo o treino, mais animado fica."
        case .agilidade: "Rápido e explosivo, adora sprint, salto e mudança de direção."
        case .tecnica: "Movimento limpo e controle total: prefere fazer certo a fazer muito."
        }
    }

    static func howTo(_ f: MonsterForm) -> String {
        switch f.stage {
        case .egg:
            return "Todo bro começa como ovo. Choca com \(Stage.baby.threshold) XP."
        case .baby:
            let sp = f.speciesInfo
            let names = sp.kinds.filter { $0 != .outro }.map { $0.name.lowercased() }
            let list = names.count > 1 ? names.dropLast().joined(separator: ", ") + " ou " + names.last! : names.first ?? ""
            return sp.id == Species.standard.id || list.isEmpty
                ? "Choca do ovo com \(Stage.baby.threshold) XP quando os treinos do ovo são variados ou de \"Outro\"."
                : "Choca do ovo com \(Stage.baby.threshold) XP quando os treinos do ovo são de \(list) (e parecidos no Apple Saúde)."
        case .rookie:
            return "Evolui do bebê com \(Stage.rookie.threshold.formatted()) XP, com qualquer treino."
        case .champion, .ultimate:
            let from = f.stage == .champion ? "do Novato" : "de qualquer Atleta"
            let rule: String
            if let a = f.attribute, let b = f.attribute2 {
                rule = "se \(a.name) e \(b.name) forem os atributos mais treinados, quase empatados (até 10% de diferença)"
            } else {
                rule = "se \(f.attribute?.name ?? "") for o atributo mais treinado"
            }
            return "Evolui \(from) com \(f.stage.threshold.formatted()) XP, \(rule) desde a última evolução."
        }
    }

    /// Treinos que mais dão o(s) atributo(s) da forma; para o bebê, os que chocam a espécie
    static func kinds(_ f: MonsterForm) -> [ActivityKind] {
        if f.stage == .baby { return f.speciesInfo.kinds.filter { $0 != .outro } }
        let attrs = [f.attribute, f.attribute2].compactMap { $0 }
        guard !attrs.isEmpty else { return [] }
        let score = { (k: ActivityKind) in attrs.map { k.weights[$0] ?? 0 }.reduce(0, +) }
        return ActivityKind.allCases.filter { $0 != .outro && score($0) >= 0.3 }.sorted { score($0) > score($1) }
    }

    private static func champions(_ species: String) -> [MonsterForm] {
        Attribute.allCases.map { MonsterForm(stage: .champion, attribute: $0, species: species) }
            + MonsterForm.hybrids(species: species).filter { $0.stage == .champion && $0.hasArt }
    }

    static func previous(_ f: MonsterForm) -> [MonsterForm] {
        switch f.stage {
        case .egg: []
        case .baby: [.egg]
        case .rookie: [MonsterForm(stage: .baby, attribute: nil, species: f.species)]
        case .champion: [MonsterForm(stage: .rookie, attribute: nil, species: f.species)]
        case .ultimate: champions(f.species)
        }
    }

    static func next(_ f: MonsterForm) -> [MonsterForm] {
        switch f.stage {
        case .egg: Species.all.filter(\.isReady).map { MonsterForm(stage: .baby, attribute: nil, species: $0.id) }
        case .baby: [MonsterForm(stage: .rookie, attribute: nil, species: f.species)]
        case .rookie: champions(f.species)
        case .champion:
            Attribute.allCases.map { MonsterForm(stage: .ultimate, attribute: $0, species: f.species) }
                + MonsterForm.hybrids(species: f.species).filter { $0.stage == .ultimate && $0.hasArt }
        case .ultimate: []
        }
    }
}
