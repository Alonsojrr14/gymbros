import Observation
import SwiftUI

/// Onde estão, em coordenadas globais, os elementos marcados com `.onboardingTarget`.
/// As posições são sempre guardadas (telas criadas antes do tutorial começar também precisam estar lá),
/// mas só invalidam a interface enquanto o tutorial está ativo.
@MainActor @Observable
final class OnboardingTargetRegistry {
    static let shared = OnboardingTargetRegistry()

    struct Entry: Equatable {
        var frame: CGRect
        var shape: SpotlightShape
    }

    @ObservationIgnored private var entries: [OnboardingTarget: Entry] = [:]
    private var revision = 0
    @ObservationIgnored var tracking = false {
        didSet { if tracking { revision &+= 1 } }
    }
    /// Área visível do app (global); um elemento fora dela não pode ser destacado
    var bounds: CGRect = .zero

    func update(_ target: OnboardingTarget, _ entry: Entry?) {
        guard entries[target] != entry else { return }
        entries[target] = entry
        if tracking { revision &+= 1 }
    }

    /// Recorte que cobre todos os alvos, ou nil se algum não estiver inteiro na tela
    func spotlight(for targets: [OnboardingTarget]) -> Entry? {
        _ = revision
        let found = targets.compactMap { entries[$0] }
        guard !found.isEmpty, found.count == targets.count else { return nil }
        let rect = found.dropFirst().reduce(found[0].frame) { $0.union($1.frame) }
        guard rect.width > 1, rect.height > 1 else { return nil }
        if !bounds.isEmpty, !bounds.insetBy(dx: -1, dy: -1).contains(rect) { return nil }
        return Entry(frame: rect, shape: found.count == 1 ? found[0].shape : .rounded(Theme.radiusL))
    }

    func diagnose(_ targets: [OnboardingTarget]) -> String {
        targets.map { "\($0.rawValue): \(entries[$0].map { "\($0.frame)" } ?? "não registrado")" }.joined(separator: ", ") + " · tela \(bounds)"
    }
}

private struct OnboardingVisibleKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Falso nas abas escondidas: elas continuam vivas, mas seus elementos não podem ser destacados
    var onboardingVisible: Bool {
        get { self[OnboardingVisibleKey.self] }
        set { self[OnboardingVisibleKey.self] = newValue }
    }
}

private struct SpotlightTargetModifier: ViewModifier {
    let target: OnboardingTarget?
    let shape: SpotlightShape
    @Environment(\.onboardingVisible) private var visible

    func body(content: Content) -> some View {
        content.background {
            if let target, visible {
                GeometryReader { proxy in
                    let frame = proxy.frame(in: .global)
                    Color.clear
                        .onAppear { report(target, frame) }
                        .onChange(of: frame) { _, f in report(target, f) }
                        .onDisappear { OnboardingTargetRegistry.shared.update(target, nil) }
                }
            }
        }
    }

    private func report(_ target: OnboardingTarget, _ frame: CGRect) {
        OnboardingTargetRegistry.shared.update(target, .init(frame: frame, shape: shape))
    }
}

extension View {
    /// Marca o elemento real que uma etapa do tutorial destaca
    func onboardingTarget(_ target: OnboardingTarget?, shape: SpotlightShape = .rounded(Theme.radiusL)) -> some View {
        modifier(SpotlightTargetModifier(target: target, shape: shape))
    }
}
