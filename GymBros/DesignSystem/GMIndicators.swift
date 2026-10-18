import SwiftUI

struct GMProgressBar: View {
    let value: Double
    var tint: Color = Theme.accent
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule().fill(tint).frame(width: max(g.size.width * min(max(value, 0), 1), value > 0 ? height : 0))
            }
        }
        .frame(height: height)
        .animation(.spring(duration: 0.5), value: value)
    }
}

struct GMBadge: View {
    let text: String
    var tint: Color = Theme.accent

    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.2), in: .capsule)
            .foregroundStyle(tint)
    }
}

/// Ponto de "online": verde, com uma névoa que sai dele e se desfaz, sem parar
struct GMOnlineDot: View {
    var size: CGFloat = 8
    var color = Theme.online
    @State private var breathe = false

    var body: some View {
        ZStack {
            // Névoa: borrada, cresce e some
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .blur(radius: size * 0.25)
                .scaleEffect(breathe ? 1.6 : 1)
                .opacity(breathe ? 0 : 0.6)
            // Brilho fixo em volta
            Circle()
                .fill(color.opacity(0.25))
                .frame(width: size * 1.3, height: size * 1.3)
                .blur(radius: size * 0.15)
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .shadow(color: color.opacity(0.6), radius: size * 0.2)
        }
        .frame(width: size * 1.6, height: size * 1.6)
        .onAppear {
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { breathe = true }
        }
        .accessibilityLabel("Online")
    }
}
