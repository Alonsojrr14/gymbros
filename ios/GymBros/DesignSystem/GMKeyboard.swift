import SwiftUI
import UIKit

/// Tocar fora de um campo fecha o teclado, no app inteiro (o teclado numérico não tem tecla de confirmar)
final class GMKeyboardDismisser: NSObject, UIGestureRecognizerDelegate {
    static let shared = GMKeyboardDismisser()

    /// Topo do teclado na tela (nil = fechado)
    private var keyboardTop: CGFloat?
    private var observing = false

    func install() {
        if !observing {
            observing = true
            let nc = NotificationCenter.default
            nc.addObserver(self, selector: #selector(keyboardChanged(_:)), name: UIResponder.keyboardDidShowNotification, object: nil)
            nc.addObserver(self, selector: #selector(keyboardChanged(_:)), name: UIResponder.keyboardDidChangeFrameNotification, object: nil)
            nc.addObserver(self, selector: #selector(keyboardHidden), name: UIResponder.keyboardWillHideNotification, object: nil)
            nc.addObserver(self, selector: #selector(fieldBegan), name: UITextField.textDidBeginEditingNotification, object: nil)
            nc.addObserver(self, selector: #selector(fieldBegan), name: UITextView.textDidBeginEditingNotification, object: nil)
        }
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows where !(window.gestureRecognizers ?? []).contains(where: { $0.name == "gmDismissKeyboard" }) {
                let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
                tap.name = "gmDismissKeyboard"
                tap.cancelsTouchesInView = false
                tap.delegate = self
                window.addGestureRecognizer(tap)
            }
        }
    }

    @objc private func tapped(_ g: UITapGestureRecognizer) { g.view?.endEditing(true) }

    @objc private func keyboardChanged(_ n: Notification) {
        guard let frame = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
        keyboardTop = frame.minY
        reveal()
    }

    @objc private func keyboardHidden() { keyboardTop = nil }

    /// Trocou de campo com o teclado já aberto: o próximo também precisa aparecer
    @objc private func fieldBegan() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.reveal() }
    }

    /// O campo em foco nunca fica atrás do teclado nem do botão OK: rola a lista que o contém até ele aparecer
    private func reveal() {
        guard let top = keyboardTop, let field = Self.firstResponder() , let window = field.window else { return }
        let okBar: CGFloat = 64
        let rect = field.convert(field.bounds, to: window)
        let overlap = rect.maxY - (top - okBar)
        guard overlap > 0 else { return }
        var view = field.superview
        while let v = view, !(v is UIScrollView && (v as! UIScrollView).isScrollEnabled) { view = v.superview }
        guard let scroll = view as? UIScrollView else { return }
        let maxY = max(scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height, -scroll.adjustedContentInset.top)
        let target = min(scroll.contentOffset.y + overlap, maxY)
        guard target > scroll.contentOffset.y else { return }
        UIView.animate(withDuration: 0.25) { scroll.contentOffset.y = target }
    }

    private static func firstResponder() -> UIView? {
        func find(_ v: UIView) -> UIView? {
            if v.isFirstResponder { return v }
            for s in v.subviews { if let r = find(s) { return r } }
            return nil
        }
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for w in scene.windows where w.isKeyWindow { if let r = find(w) { return r } }
        }
        return nil
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Tocar em outro campo troca de campo em vez de fechar o teclado
        !(touch.view is UITextField || touch.view is UITextView)
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}

/// Botão "OK" próprio logo acima do teclado, enquanto ele estiver aberto
private struct GMKeyboardDone: ViewModifier {
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomTrailing) {
                if visible {
                    Button {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    } label: {
                        Label("OK", systemImage: "keyboard.chevron.compact.down")
                            .font(.subheadline.bold())
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Theme.accent, in: .capsule)
                            .foregroundStyle(.black)
                    }
                    .buttonStyle(GMPress())
                    .padding(.trailing, 14)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                withAnimation(.easeOut(duration: 0.2)) { visible = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                withAnimation(.easeOut(duration: 0.15)) { visible = false }
            }
            .onAppear { GMKeyboardDismisser.shared.install() }
    }
}

extension View {
    func gmKeyboardDone() -> some View { modifier(GMKeyboardDone()) }
}
