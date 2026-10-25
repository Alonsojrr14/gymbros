import Observation
import SwiftUI
import UIKit

/// Uma dica por vez no app inteiro
@MainActor @Observable
final class ScreenTipCenter {
    static let shared = ScreenTipCenter()

    private(set) var showing: String?
    @ObservationIgnored var defaults: UserDefaults = .standard
    @ObservationIgnored var delay: Duration = .milliseconds(700)

    /// Nunca sob XCTest; `-screenTipsOff` desliga em testes de interface e capturas de tela
    var isEnabled: Bool {
        !AppRuntime.isTesting && !ProcessInfo.processInfo.arguments.contains("-screenTipsOff")
    }

    func canShow(_ tip: ScreenTip) -> Bool {
        isEnabled && ScreenTips.shouldShow(tip, blocked: showing != nil || OnboardingCoordinator.shared.isActive, defaults)
    }

    func claim(_ tip: ScreenTip) -> Bool {
        guard canShow(tip) else { return false }
        showing = tip.id
        return true
    }

    /// Fechou de qualquer jeito (Entendi, Pular, toque fora ou arrastar): conta como vista
    func finish(_ tip: ScreenTip) {
        ScreenTips.markSeen(tip.id, defaults)
        if showing == tip.id { showing = nil }
    }

    func reset() {
        ScreenTips.reset(defaults)
    }
}

extension View {
    /// Mostra a dica da tela na primeira vez que ela aparece. `blocked`: a tela está abrindo outra folha ou modal.
    func screenTip(_ tip: ScreenTip, blocked: Bool = false) -> some View {
        modifier(ScreenTipModifier(tip: tip, blocked: blocked))
    }
}

private struct ScreenTipModifier: ViewModifier {
    let tip: ScreenTip
    let blocked: Bool
    @Environment(\.onboardingVisible) private var visible
    @Environment(\.scenePhase) private var phase
    @State private var anchor = ScreenTipAnchor()
    @State private var presented = false
    @State private var appearances = 0
    @State private var center = ScreenTipCenter.shared
    @State private var tour = OnboardingCoordinator.shared

    func body(content: Content) -> some View {
        content
            .background(ScreenTipProbe(anchor: anchor).frame(width: 0, height: 0).accessibilityHidden(true))
            .onAppear { appearances += 1 }
            .task(id: "\(appearances)|\(visible)|\(blocked)|\(tour.isActive)|\(phase == .active)|\(center.showing ?? "")") {
                guard center.isEnabled, appearances > 0, visible, !blocked, phase == .active, !presented, center.canShow(tip) else { return }
                try? await Task.sleep(for: center.delay)
                guard !Task.isCancelled, anchor.isFree, center.claim(tip) else { return }
                presented = true
            }
            .gmSheet(isPresented: $presented) { close in ScreenTipSheet(tip: tip, close: close) }
            .onChange(of: presented) { _, on in if !on { center.finish(tip) } }
    }
}

/// Onde a tela está na hierarquia do UIKit, para saber se ela está mesmo à vista
@MainActor
private final class ScreenTipAnchor {
    weak var view: UIView?

    /// Na janela e sem nada apresentado por cima (folha, modal, menu, outra dica)
    var isFree: Bool {
        guard let view, view.window != nil else { return false }
        guard var vc = sequence(first: view as UIResponder, next: \.next).first(where: { $0 is UIViewController }) as? UIViewController else {
            return false
        }
        while let parent = vc.parent { vc = parent }
        return vc.presentedViewController == nil && !vc.isBeingDismissed
    }
}

private struct ScreenTipProbe: UIViewRepresentable {
    let anchor: ScreenTipAnchor

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.isUserInteractionEnabled = false
        v.isAccessibilityElement = false
        anchor.view = v
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        anchor.view = uiView
    }
}

// MARK: - Folha

struct ScreenTipSheet: View {
    let tip: ScreenTip
    let close: () -> Void
    @State private var index = 0
    @AccessibilityFocusState private var focused: Int?

    private var isLast: Bool { index == tip.cards.count - 1 }

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }.scrollBounceBehavior(.basedOnSize)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill").font(.caption.bold()).foregroundStyle(Theme.accent)
                Text("DICA · \(tip.screen.uppercased())").font(.caption.weight(.bold)).foregroundStyle(Theme.dim).tracking(0.6)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Dica da tela \(tip.screen)")

            // Todos os cartões empilhados: a folha fica com a altura do maior e não pula ao trocar
            ZStack(alignment: .topLeading) {
                ForEach(Array(tip.cards.enumerated()), id: \.offset) { i, card in
                    cardView(card, at: i)
                        .opacity(i == index ? 1 : 0)
                        .offset(x: i == index ? 0 : (i < index ? -24 : 24))
                        .accessibilityHidden(i != index)
                        .allowsHitTesting(i == index)
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { v in
                guard abs(v.translation.width) > abs(v.translation.height), abs(v.translation.width) > 50 else { return }
                go(v.translation.width < 0 ? index + 1 : index - 1)
            })

            if tip.cards.count > 1 { pageDots }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { secondaryButton; primaryButton }
                VStack(spacing: 10) { primaryButton; secondaryButton }
            }
        }
        .padding(.horizontal, 4)
        .onAppear { focused = 0 }
    }

    private func cardView(_ card: ScreenTipCard, at i: Int) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: card.symbol)
                .font(.title2.weight(.bold))
                .foregroundStyle(.black)
                .frame(width: 52, height: 52)
                .background(Theme.accent.gradient, in: .rect(cornerRadius: Theme.radiusM))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(card.title).font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(card.text).font(.subheadline).foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(card.title). \(card.text)")
        .accessibilityValue(tip.cards.count > 1 ? "\(i + 1) de \(tip.cards.count)" : "")
        .accessibilityFocused($focused, equals: i)
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(tip.cards.indices, id: \.self) { i in
                Capsule().fill(i == index ? Theme.accent : Theme.track)
                    .frame(width: i == index ? 18 : 7, height: 7)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.snappy, value: index)
        .accessibilityElement()
        .accessibilityLabel("Dica \(index + 1) de \(tip.cards.count)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: go(index + 1)
            case .decrement: go(index - 1)
            @unknown default: break
            }
        }
    }

    @ViewBuilder
    private var secondaryButton: some View {
        if isLast && index > 0 {
            GMButton("Voltar", icon: "chevron.left", kind: .ghost) { go(index - 1) }
        } else if !isLast {
            GMButton("Pular", kind: .ghost, action: close)
                .accessibilityHint("Fecha a dica e não mostra de novo")
        }
    }

    private var primaryButton: some View {
        GMButton(isLast ? "Entendi" : "Avançar", icon: isLast ? "checkmark" : "chevron.right") {
            if isLast { close() } else { go(index + 1) }
        }
    }

    private func go(_ i: Int) {
        guard tip.cards.indices.contains(i), i != index else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.snappy(duration: 0.28)) { index = i }
        focused = i
    }
}
