import SwiftUI

/// Tela inteira menos o recorte. Preenchida com a regra par-ímpar, o recorte fica realmente vazio:
/// o que aparece ali é a interface de baixo, sem nenhuma camada por cima.
struct SpotlightCutout: Shape {
    var hole: CGRect
    var radius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>> {
        get { .init(.init(hole.midX, hole.midY), .init(radius, .init(hole.width, hole.height))) }
        set {
            let w = newValue.second.second.first, h = newValue.second.second.second
            hole = CGRect(x: newValue.first.first - w / 2, y: newValue.first.second - h / 2, width: w, height: h)
            radius = newValue.second.first
        }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path(rect)
        if hole.width > 0.5, hole.height > 0.5 {
            let r = max(0, min(radius, hole.width / 2, hole.height / 2))
            p.addRoundedRect(in: hole, cornerSize: CGSize(width: r, height: r), style: .continuous)
        }
        return p
    }
}

extension OnboardingTargetRegistry.Entry {
    /// Recorte com folga em volta do elemento, no formato dele
    func hole(padding p: CGFloat = 6) -> (rect: CGRect, radius: CGFloat) {
        switch shape {
        case .rounded(let r):
            return (frame.insetBy(dx: -p, dy: -p), r + p)
        case .capsule:
            let rect = frame.insetBy(dx: -p, dy: -p)
            return (rect, min(rect.width, rect.height) / 2)
        case .circle:
            let d = max(frame.width, frame.height) + 2 * p
            return (CGRect(x: frame.midX - d / 2, y: frame.midY - d / 2, width: d, height: d), d / 2)
        }
    }
}

/// Camada do tutorial sobre a tela principal: vinheta com recorte e o cartão da etapa
struct OnboardingOverlay: View {
    @State private var tour = OnboardingCoordinator.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let step = tour.current, let index = tour.index {
            let hole = tour.spotlight?.hole()
            GeometryReader { safe in
                let origin = safe.frame(in: .global).origin
                ZStack {
                    GeometryReader { full in
                        let fullFrame = full.frame(in: .global)
                        SpotlightBackdrop(hole: hole.map { ($0.rect.offsetBy(dx: -fullFrame.minX, dy: -fullFrame.minY), $0.radius) },
                                          size: full.size, passThrough: step.interaction != .explain)
                            .onAppear { OnboardingTargetRegistry.shared.bounds = fullFrame }
                            .onChange(of: fullFrame) { _, f in OnboardingTargetRegistry.shared.bounds = f }
                    }
                    .ignoresSafeArea()

                    if !tour.locating {
                        cardLayer(step: step, index: index,
                                  hole: hole.map { $0.rect.offsetBy(dx: -origin.x, dy: -origin.y) }, size: safe.size)
                            .id(step.id)
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
            }
            .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.1), value: step.id)
            .animation(.easeOut(duration: 0.2), value: tour.locating)
        }
    }

    @ViewBuilder
    private func cardLayer(step: OnboardingStep, index: Int, hole: CGRect?, size: CGSize) -> some View {
        let card = OnboardingTooltip(step: step, number: index + 1, total: tour.steps.count, isLast: tour.isLast,
                                     onBack: index > 0 ? { tour.back() } : nil,
                                     onNext: { tour.next() },
                                     onSkip: tour.isLast ? nil : { tour.skip() })
            .padding(.horizontal, 16)
        let gap: CGFloat = 14
        if let hole {
            let above = hole.minY - gap, below = size.height - hole.maxY - gap
            let roomy: CGFloat = 200
            let placeBelow = switch step.placement {
            case .auto: below >= above
            case .below: below >= roomy || below >= above
            case .above: !(above >= roomy || above >= below)
            }
            VStack(spacing: 0) {
                if placeBelow {
                    Color.clear.frame(height: max(hole.maxY + gap, 0))
                    card.frame(maxHeight: max(below - 8, 0), alignment: .top)
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                    card.frame(maxHeight: max(above - 8, 0), alignment: .bottom)
                    Color.clear.frame(height: max(size.height - hole.minY + gap, 0))
                }
            }
            .frame(width: size.width, height: size.height)
        } else {
            card.frame(maxHeight: .infinity)
        }
    }
}

/// Vinheta escurecida com recorte. Nas etapas explicativas bloqueia toques em tudo (inclusive no recorte);
/// nas que pedem um toque, o recorte deixa o toque passar para o elemento real.
private struct SpotlightBackdrop: View {
    let hole: (rect: CGRect, radius: CGFloat)?
    let size: CGSize
    let passThrough: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let rect = hole?.rect ?? CGRect(x: size.width / 2, y: size.height / 2, width: 0, height: 0)
        let radius = hole?.radius ?? 0
        let reach = max(size.width, size.height)
        ZStack {
            SpotlightCutout(hole: rect, radius: radius)
                .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
            SpotlightCutout(hole: rect, radius: radius)
                .fill(RadialGradient(colors: [.clear, .black.opacity(0.4)], center: .center,
                                     startRadius: reach * 0.2, endRadius: reach * 0.75),
                      style: FillStyle(eoFill: true))
            if hole != nil {
                RoundedRectangle(cornerRadius: radius + 1, style: .continuous)
                    .stroke(Theme.accent.opacity(0.9), lineWidth: 2)
                    .frame(width: rect.width + 2, height: rect.height + 2)
                    .position(x: rect.midX, y: rect.midY)
                    .allowsHitTesting(false)
                if passThrough && !reduceMotion {
                    RoundedRectangle(cornerRadius: radius + 1, style: .continuous)
                        .stroke(Theme.accent, lineWidth: 2)
                        .frame(width: rect.width + 2, height: rect.height + 2)
                        .phaseAnimator([false, true]) { ring, grown in
                            ring.scaleEffect(grown ? 1.12 : 1).opacity(grown ? 0 : 0.8)
                        } animation: { grown in grown ? .easeOut(duration: 1.1) : nil }
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                }
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.12), value: rect)
        .contentShape(SpotlightCutout(hole: passThrough ? rect : .zero, radius: radius), eoFill: true)
        .onTapGesture {}
        .accessibilityHidden(true)
    }
}

struct OnboardingTooltip: View {
    let step: OnboardingStep
    let number: Int
    let total: Int
    let isLast: Bool
    let onBack: (() -> Void)?
    let onNext: () -> Void
    let onSkip: (() -> Void)?
    @AccessibilityFocusState private var focused: Bool

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }.scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: 440)
        .background(Theme.card, in: .rect(cornerRadius: Theme.radiusXL, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusXL, style: .continuous).stroke(Theme.stroke))
        .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { (onSkip ?? onNext)() }
        .onAppear { focused = true }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    ForEach(1...total, id: \.self) { i in
                        Capsule().fill(i == number ? Theme.accent : Theme.track)
                            .frame(width: i == number ? 16 : 6, height: 6)
                    }
                }
                .accessibilityHidden(true)
                Text("\(number) de \(total)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.dim)
                    .accessibilityLabel("Etapa \(number) de \(total)")
                Spacer(minLength: 0)
                if let onSkip {
                    Button("Pular", action: onSkip)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.dim)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                        .accessibilityLabel("Pular tutorial")
                }
            }
            Text(step.title)
                .gmFont(22, weight: .heavy, design: .rounded, relativeTo: .title2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focused)
            Text(step.message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            if let hint = step.hint {
                Label(hint, systemImage: "hand.tap.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                if let onBack { GMButton("Voltar", kind: .secondary, full: false, action: onBack) }
                Spacer(minLength: 0)
                GMButton(isLast ? "Concluir" : "Avançar", icon: isLast ? "checkmark" : nil, full: false, action: onNext)
            }
        }
        .padding(18)
    }
}
