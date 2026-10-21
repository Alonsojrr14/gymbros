import SwiftUI

/// Bro principal: a arte ocupa o que sobra da tela; embaixo, XP até evoluir, sequência e XP de hoje
struct BroPage: View {
    @Environment(PhoneLink.self) private var link

    var body: some View {
        if let bro = link.bro?.at(.now) {
            VStack(spacing: 5) {
                BroArt(image: link.sprite)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
                Text("\(bro.moodEmoji) \(bro.formName) · Nv \(bro.level)")
                    .font(.footnote).foregroundStyle(Theme.dim)
                    .lineLimit(1).minimumScaleFactor(0.6)
                XPBar(progress: bro.progress,
                      text: bro.xpToNext.map { "\($0) XP para \(bro.isEgg ? "chocar" : "evoluir")" } ?? "\(bro.stageName) · fase máxima")
                HStack(spacing: 6) {
                    Stat(symbol: "flame.fill", value: "\(bro.streak)", label: bro.streak == 1 ? "dia" : "dias", tint: Theme.streak)
                    Stat(symbol: "bolt.fill", value: "\(bro.todayXP)", label: "XP hoje", tint: Theme.accent)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .navigationTitle(bro.name)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "iphone.gen3")
                    .resizable().scaledToFit()
                    .frame(maxHeight: .infinity)
                    .foregroundStyle(Theme.accent)
                Text("Abra o GymBros no iPhone").font(.headline).multilineTextAlignment(.center)
                Text("O seu bro aparece aqui.").font(.caption2).foregroundStyle(Theme.dim)
            }
            .minimumScaleFactor(0.7)
            .navigationTitle("GymBros")
        }
    }
}

struct BroArt: View {
    let image: UIImage?

    var body: some View {
        if let image {
            Image(uiImage: image).resizable().interpolation(.none).scaledToFit()
                .accessibilityHidden(true)
        } else {
            Image(systemName: "figure.strengthtraining.traditional")
                .resizable().scaledToFit().padding(6).foregroundStyle(Theme.accent)
        }
    }
}

/// Barra de XP com o quanto falta escrito dentro (uma linha a menos na tela)
private struct XPBar: View {
    let progress: Double
    let text: String

    var body: some View {
        GeometryReader { g in
            Capsule().fill(Theme.track)
                .overlay(alignment: .leading) {
                    Capsule().fill(Theme.accent.opacity(0.85)).frame(width: max(g.size.height, g.size.width * progress))
                }
        }
        .frame(height: 18)
        .overlay {
            Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 1)
                .lineLimit(1).minimumScaleFactor(0.6).padding(.horizontal, 8)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct Stat: View {
    let symbol: String
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(value).font(.body.monospacedDigit().weight(.semibold))
            Text(label).font(.caption2).foregroundStyle(Theme.dim)
        }
        .lineLimit(1).minimumScaleFactor(0.6)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background(Theme.card, in: .capsule)
        .accessibilityElement(children: .combine)
    }
}

/// Os quatro atributos dividindo a tela em faixas iguais; barras relativas ao maior
struct AttributesPage: View {
    @Environment(PhoneLink.self) private var link

    private static let attributes: [(id: String, name: String, symbol: String, color: Color)] = [
        ("forca", "Força", "dumbbell.fill", Color(red: 1.0, green: 0.45, blue: 0.30)),
        ("resistencia", "Resistência", "heart.fill", Color(red: 0.35, green: 0.70, blue: 1.0)),
        ("agilidade", "Agilidade", "bolt.fill", Color(red: 0.98, green: 0.82, blue: 0.20)),
        ("tecnica", "Técnica", "sparkles", Color(red: 0.72, green: 0.52, blue: 1.0)),
    ]

    var body: some View {
        let values = link.bro?.attributes ?? [:]
        let top = max(values.values.max() ?? 0, 1)
        VStack(spacing: 6) {
            ForEach(Self.attributes, id: \.id) { a in
                let v = values[a.id] ?? 0
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Label(a.name, systemImage: a.symbol).foregroundStyle(a.color)
                        Spacer()
                        Text("\(Int(v.rounded()))").monospacedDigit().foregroundStyle(Theme.dim)
                    }
                    .font(.footnote).lineLimit(1).minimumScaleFactor(0.7)
                    GeometryReader { g in
                        Capsule().fill(Theme.track)
                            .overlay(alignment: .leading) {
                                Capsule().fill(a.color).frame(width: max(g.size.height, g.size.width * v / top))
                            }
                    }
                    .frame(maxHeight: 8)
                }
                .frame(maxHeight: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
        .navigationTitle("Atributos")
    }
}
