import SwiftUI
import UIKit

/// Tocar fora de um campo fecha o teclado, no app inteiro (o teclado numérico não tem tecla de confirmar)
final class GMKeyboardDismisser: NSObject, UIGestureRecognizerDelegate {
    static let shared = GMKeyboardDismisser()

    func install() {
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
