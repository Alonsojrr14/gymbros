import SwiftUI

// MARK: - Chegou

/// Cena da troca: o seu bro se despedaça em ícones de treino que formam um DNA; ele sobe e sai pelo topo
/// (vai para o amigo) enquanto o DNA do bro que chega desce do topo, os dois se cruzam, e o que chegou se
/// reestrutura no novo bro. Fecha com a mensagem e o atalho para a Box (o bro já entrou nela).
struct TradeArrivedView: View {
    let bro: Monster
    let proposal: TradeProposal
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date.now
    @State private var paused = false

    #if DEBUG
    /// `-tradeSceneTime 3.1`: congela a cena num instante (capturas de tela)
    private var frozen: Double? { UserDefaults.standard.object(forKey: "tradeSceneTime") != nil ? UserDefaults.standard.double(forKey: "tradeSceneTime") : nil }
    #else
    private var frozen: Double? { nil }
    #endif

    var body: some View {
        let given = proposal.mine.form
        let arriving = MonsterForm.byID(bro.lastFormID) ?? proposal.theirs.form
        let name = bro.displayName(arriving)
        let mineTint = given.attribute?.color ?? Theme.accent
        let theirTint = arriving.attribute?.color ?? Theme.trophy
        GeometryReader { geo in
            TimelineView(.animation(paused: paused)) { ctx in
                let t = reduceMotion ? SwapTimeline.end : frozen ?? ctx.date.timeIntervalSince(start)
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height * 0.4)
                ZStack {
                    backdrop(t, mine: mineTint, theirs: theirTint)
                    Canvas { c, size in
                        SwapDrawing(t: t, size: size, center: center, given: given, arriving: arriving,
                                    mineTint: mineTint, theirTint: theirTint).draw(in: &c)
                    }
                    .accessibilityHidden(true)
                    if t >= SwapTimeline.reveal {
                        LivingMonster(form: arriving)
                            .frame(width: SwapDrawing.spriteSize, height: SwapDrawing.spriteSize)
                            .scaleEffect(1 + 0.12 * SwapTimeline.bump(t, at: SwapTimeline.reveal + 0.15, width: 0.35))
                            .position(center)
                            .accessibilityLabel(name)
                    }
                    // Clarão onde os dois DNAs se cruzam
                    RadialGradient(colors: [.white.opacity(0.45 * SwapTimeline.bump(t, at: SwapTimeline.cross, width: 0.25)), .clear],
                                   center: .init(x: 0.5, y: (center.y - 90) / max(geo.size.height, 1)), startRadius: 0, endRadius: 230)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                    overlay(t, name: name)
                }
            }
        }
        .ignoresSafeArea()
        .background(Color.black.ignoresSafeArea())
        .task { await haptics() }
    }

    private func backdrop(_ t: Double, mine: Color, theirs: Color) -> some View {
        let after = SwapTimeline.progress(t, SwapTimeline.cross - 0.3, SwapTimeline.cross + 0.4)
        return ZStack {
            Color.black
            RadialGradient(colors: [mine.opacity(0.28 * (1 - after)), .clear], center: .init(x: 0.5, y: 0.4), startRadius: 10, endRadius: 380)
            RadialGradient(colors: [theirs.opacity(0.32 * after), .clear], center: .init(x: 0.5, y: 0.4), startRadius: 10, endRadius: 420)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func overlay(_ t: Double, name: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if t < SwapTimeline.reveal {
                    Button("Pular") { start = Date.now.addingTimeInterval(-SwapTimeline.reveal) }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.white.opacity(0.08), in: .capsule)
                }
            }
            .frame(height: 44)
            .padding(.horizontal, 20)
            .padding(.top, 60)
            Spacer()
            let shown = SwapTimeline.progress(t, SwapTimeline.message, SwapTimeline.message + 0.7)
            VStack(spacing: 10) {
                Text("TROCA FEITA").font(.caption.weight(.heavy)).tracking(1.2).foregroundStyle(Theme.trophy)
                Text("\(name) agora é seu GymBro!")
                    .gmFont(28, weight: .heavy, design: .rounded, relativeTo: .title)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                Text("Continue treinando e evoluindo juntos.")
                    .font(.headline).foregroundStyle(.white.opacity(0.85))
                Text("Veio de \(proposal.friend.name) com \(proposal.theirs.xp.formatted()) XP, que ficam marcados como de quem o treinou. \(proposal.mine.name) foi para \(proposal.friend.name).")
                    .font(.caption).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 28)
            .opacity(shown)
            .offset(y: 18 * (1 - shown))
            GMButton("Ver na Box", icon: "square.grid.3x3.fill") { dismiss() }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 44)
                .opacity(SwapTimeline.progress(t, SwapTimeline.message + 0.5, SwapTimeline.message + 1))
                .allowsHitTesting(t >= SwapTimeline.message)
        }
    }

    /// Toques no momento certo: despedaçar, cruzar e revelar
    private func haptics() async {
        guard !reduceMotion else {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            paused = true
            return
        }
        var marks: [(Double, () -> Void)] = [
            (SwapTimeline.shatter, { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }),
            (SwapTimeline.cross, { UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.9) }),
        ]
        // Batidas de coração cada vez mais rápidas enquanto o DNA que chegou acelera até se fechar
        var beat = SwapTimeline.arrive + 0.1, gap = 0.55
        while beat < SwapTimeline.collapse + 0.7 {
            let strength = 0.35 + 0.6 * SwapTimeline.progress(beat, SwapTimeline.arrive, SwapTimeline.collapse + 0.7)
            marks.append((beat, { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: strength) }))
            beat += gap
            gap = max(gap * 0.8, 0.12)
        }
        marks.append((SwapTimeline.reveal, { UINotificationFeedbackGenerator().notificationOccurred(.success) }))
        marks.sort { $0.0 < $1.0 }
        for (at, play) in marks {
            let wait = at - Date.now.timeIntervalSince(start)
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled else { return }
            play()
        }
        // Depois da revelação nada mais muda no Canvas: o relógio para (o bro continua vivo sozinho)
        let rest = SwapTimeline.end - Date.now.timeIntervalSince(start)
        if rest > 0 { try? await Task.sleep(for: .seconds(rest)) }
        paused = true
    }
}

/// Momentos da cena, em segundos
enum SwapTimeline {
    /// O seu bro na tela, depois tremendo
    static let shatter = 2.2
    static let gather = 2.7
    /// DNA formado: gira um pouco antes de partir
    static let helix = 4.6
    static let leave = 5.6
    static let cross = 7.1
    static let arrive = 8.6
    /// O DNA que chegou gira cada vez mais rápido até se fechar
    static let collapse = 10.0
    static let reveal = 11.7
    static let message = 12.3
    static let end = 13.8

    /// Giro da hélice: constante e, perto de se fechar, acelerando
    static func spin(_ t: Double) -> Double {
        let windup = progress(t, arrive, collapse + 0.4)
        return t * 2.4 + 9 * windup * windup
    }

    static func progress(_ t: Double, _ a: Double, _ b: Double) -> Double { min(max((t - a) / (b - a), 0), 1) }

    /// 0 → 1 → 0 em volta de `at`
    static func bump(_ t: Double, at: Double, width: Double) -> Double { max(1 - abs(t - at) / width, 0) }

    static func easeInOut(_ p: Double) -> Double { p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2 }
    static func easeOut(_ p: Double) -> Double { 1 - pow(1 - p, 3) }
    static func easeIn(_ p: Double) -> Double { p * p * p }
}

/// Um quadro da cena no Canvas: pedaços das artes, ícones de treino e as duas hélices
struct SwapDrawing {
    let t: Double
    let size: CGSize
    let center: CGPoint
    let given: MonsterForm
    let arriving: MonsterForm
    let mineTint: Color
    let theirTint: Color

    static let spriteSize: CGFloat = 220
    private static let grid = 6
    /// Nós de cada fita da hélice
    private static let rungs = 12
    private static let icons = ["dumbbell.fill", "flame.fill", "bolt.fill", "heart.fill", "figure.strengthtraining.traditional",
                                "figure.run", "figure.cross.training", "trophy.fill"]

    private typealias T = SwapTimeline

    func draw(in c: inout GraphicsContext) {
        drawGiven(&c)
        drawHelix(&c, tint: mineTint, salt: 1, centerY: mineHelixY, from: T.gather, visible: t >= T.gather && mineHelixY > -200)
        drawHelix(&c, tint: theirTint, salt: 2, centerY: theirHelixY, from: T.leave, visible: t >= T.leave && t < T.collapse + 1.05)
        drawArriving(&c)
        drawBurst(&c)
    }

    // MARK: Posições

    /// A hélice do seu bro fica no centro e, na troca, sobe até sair pelo topo (devagar no começo:
    /// o cruzamento acontece perto do meio da tela)
    private var mineHelixY: CGFloat {
        let p = T.easeIn(T.progress(t, T.leave, T.arrive))
        return center.y + (-300 - center.y) * p
    }

    /// A do bro que chega desce rápido do topo até o centro, passando pela sua
    private var theirHelixY: CGFloat {
        let p = T.easeOut(T.progress(t, T.leave, T.arrive))
        return (-260) + (center.y + 260) * p
    }

    /// Nó `k` da fita `strand` (0 ou 1) com a hélice girando; `depth` -1…1 dá o efeito de profundidade
    private func node(_ k: Int, strand: Int, centerY: CGFloat) -> (point: CGPoint, depth: Double) {
        let spacing: CGFloat = 21
        let angle = T.spin(t) + Double(k) * 0.55 + Double(strand) * .pi
        let y = centerY + (CGFloat(k) - CGFloat(Self.rungs - 1) / 2) * spacing
        return (CGPoint(x: center.x + CGFloat(cos(angle)) * 50, y: y), sin(angle))
    }

    private func rnd(_ i: Int, _ salt: Int) -> Double {
        let v = sin(Double(i) * 12.9898 + Double(salt) * 78.233) * 43758.5453
        return v - v.rounded(.down)
    }

    private var spriteRect: CGRect {
        CGRect(x: center.x - Self.spriteSize / 2, y: center.y - Self.spriteSize / 2, width: Self.spriteSize, height: Self.spriteSize)
    }

    /// Pedaço `i` da arte e para onde ele voa quando a arte se despedaça
    private func tile(_ i: Int, salt: Int) -> (rect: CGRect, away: CGPoint, spin: Double) {
        let n = Self.grid, side = Self.spriteSize / CGFloat(n)
        let rect = CGRect(x: spriteRect.minX + CGFloat(i % n) * side, y: spriteRect.minY + CGFloat(i / n) * side, width: side, height: side)
        let dx = rect.midX - center.x, dy = rect.midY - center.y
        let len = max(sqrt(dx * dx + dy * dy), 1)
        let dist = 120 + 160 * rnd(i, salt)
        let wobble = (rnd(i, salt + 7) - 0.5) * 0.9
        let ux = dx / len, uy = dy / len
        let away = CGPoint(x: (ux * cos(wobble) - uy * sin(wobble)) * dist, y: (ux * sin(wobble) + uy * cos(wobble)) * dist)
        return (rect, away, (rnd(i, salt + 3) - 0.5) * 4)
    }

    // MARK: Desenho

    private func sprite(_ c: GraphicsContext, _ form: MonsterForm) -> GraphicsContext.ResolvedImage {
        c.resolve(Image(form.spriteWithFallback).interpolation(.none))
    }

    /// Seu bro: respira, treme e se despedaça em pedaços que voam e somem
    private func drawGiven(_ c: inout GraphicsContext) {
        guard t < T.shatter + 1.7 else { return }
        let img = sprite(c, given)
        if t < T.shatter {
            let shake = T.progress(t, T.shatter - 1.0, T.shatter)
            var l = c
            l.translateBy(x: CGFloat(sin(t * 70) * 4 * shake), y: 0)
            l.addFilter(.hueRotation(.degrees(given.hue)))
            l.addFilter(.brightness(0.35 * shake))
            l.draw(img, in: spriteRect)
            return
        }
        let p = T.easeOut(T.progress(t, T.shatter, T.shatter + 1.6))
        for i in 0..<(Self.grid * Self.grid) {
            let piece = tile(i, salt: 11)
            var l = c
            l.opacity = 1 - p
            l.translateBy(x: piece.rect.midX + piece.away.x * p, y: piece.rect.midY + piece.away.y * p)
            l.rotate(by: .radians(piece.spin * p))
            l.translateBy(x: -piece.rect.midX, y: -piece.rect.midY)
            l.clip(to: Path(piece.rect))
            l.addFilter(.hueRotation(.degrees(given.hue)))
            l.addFilter(.brightness(0.35 * (1 - p)))
            l.draw(img, in: spriteRect)
        }
    }

    /// Hélice de ícones de treino. A do seu bro nasce dos pedaços (cada ícone sai de um pedaço e vai para o seu nó);
    /// a do bro que chega, no fim, se fecha no centro para virar a arte dele
    private func drawHelix(_ c: inout GraphicsContext, tint: Color, salt: Int, centerY: CGFloat, from: Double, visible: Bool) {
        guard visible else { return }
        let mine = salt == 1
        let collapse = mine ? 0 : T.easeIn(T.progress(t, T.collapse, T.collapse + 1.0))
        var resolved: [String: GraphicsContext.ResolvedImage] = [:]
        for name in Self.icons {
            var img = c.resolve(Image(systemName: name))
            img.shading = .color(tint)
            resolved[name] = img
        }
        // Degraus
        for k in 0..<Self.rungs {
            let a = node(k, strand: 0, centerY: centerY), b = node(k, strand: 1, centerY: centerY)
            let gathered = mine ? T.progress(t, T.helix - 0.3, T.helix) : 1
            var path = Path()
            path.move(to: mix(a.point, center, collapse))
            path.addLine(to: mix(b.point, center, collapse))
            c.stroke(path, with: .color(tint.opacity(0.28 * gathered * (1 - collapse))), lineWidth: 2)
        }
        for k in 0..<Self.rungs {
            for strand in 0..<2 {
                let i = k * 2 + strand
                let n = node(k, strand: strand, centerY: centerY)
                var point = n.point
                if mine {
                    // Do pedaço da arte até o nó da hélice
                    let start = tile(Int(rnd(i, 5) * Double(Self.grid * Self.grid)) % (Self.grid * Self.grid), salt: 11)
                    let from = CGPoint(x: start.rect.midX + start.away.x * 0.35, y: start.rect.midY + start.away.y * 0.35)
                    let p = T.easeInOut(T.progress(t, T.gather + Double(i) * 0.03, T.helix))
                    point = mix(from, n.point, p)
                }
                point = mix(point, center, collapse)
                let appear = mine ? T.progress(t, T.gather, T.gather + 0.4) : 1
                let scale = (0.75 + 0.3 * (n.depth + 1) / 2) * (1 - 0.6 * collapse)
                let side: CGFloat = 17 * scale
                guard let img = resolved[Self.icons[(i + salt * 3) % Self.icons.count]] else { continue }
                var l = c
                l.opacity = appear * (0.45 + 0.55 * (n.depth + 1) / 2) * (1 - collapse * 0.8)
                l.draw(img, in: CGRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side))
            }
        }
    }

    /// O bro que chega: os pedaços da arte dele voltam de longe e se juntam no centro
    private func drawArriving(_ c: inout GraphicsContext) {
        guard t >= T.collapse + 0.3, t < T.reveal else { return }
        let p = T.easeInOut(T.progress(t, T.collapse + 0.3, T.reveal))
        let img = sprite(c, arriving)
        for i in 0..<(Self.grid * Self.grid) {
            let piece = tile(i, salt: 23)
            var l = c
            l.opacity = p
            l.translateBy(x: piece.rect.midX + piece.away.x * 0.6 * (1 - p), y: piece.rect.midY + piece.away.y * 0.6 * (1 - p))
            l.rotate(by: .radians(piece.spin * (1 - p)))
            l.translateBy(x: -piece.rect.midX, y: -piece.rect.midY)
            l.clip(to: Path(piece.rect))
            l.addFilter(.hueRotation(.degrees(arriving.hue)))
            l.addFilter(.brightness(0.5 * (1 - p)))
            l.draw(img, in: spriteRect)
        }
    }

    /// Onda de luz quando o novo bro se forma
    private func drawBurst(_ c: inout GraphicsContext) {
        let p = T.progress(t, T.reveal, T.reveal + 1.3)
        guard p > 0, p < 1 else { return }
        let r = Self.spriteSize * (0.45 + 0.9 * T.easeOut(p))
        let ring = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        c.stroke(ring, with: .color(theirTint.opacity(0.7 * (1 - p))), lineWidth: 4 * (1 - p) + 1)
    }

    private func mix(_ a: CGPoint, _ b: CGPoint, _ p: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * p, y: a.y + (b.y - a.y) * p)
    }
}

#if DEBUG
/// `-demoTradeScene`: a cena da troca com dois bros de exemplo, sem conta nem amigo
struct TradeSceneDemo: View {
    private let forms = DexView.allForms.filter { $0.stage > .baby && $0.hasArt && $0.attribute != nil }

    var body: some View {
        let mine = forms.first { $0.attribute == .forca } ?? .egg, theirs = forms.first { $0.attribute == .agilidade } ?? mine
        let bro = Monster(name: "Pelucibro")
        let _ = { bro.lastFormID = theirs.id }()
        let me = TradePerson(id: "me", name: "Você", formID: mine.id), friend = TradePerson(id: "f", name: "Bruno", formID: theirs.id)
        TradeArrivedView(bro: bro, proposal: TradeProposal(
            id: "demo", from: me, to: friend,
            give: TradeBro(id: "a", name: "Rex", formID: mine.id, xp: 820),
            get: TradeBro(id: "b", name: "Pelucibro", formID: theirs.id, xp: 1340),
            createdAt: .now, answer: .accepted, answeredAt: .now))
        .preferredColorScheme(.dark)
    }
}
#endif
