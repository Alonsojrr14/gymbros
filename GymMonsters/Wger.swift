import AVKit
import SwiftUI

// Imagens, vídeos e instruções de exercícios do wger (wger.de), sob CC BY-SA 3.0/4.0 ou CC0.
// A licença exige crédito a cada item: autor, licença e origem aparecem junto do conteúdo e em Créditos.
// Os dados são gerados por tools/wger/build.py.

struct WgerCredit: Decodable, Hashable {
    let license: String
    let licenseURL: String
    let author: String

    var line: String { "\(author) · \(license)" }
}

struct WgerMedia: Decodable, Hashable {
    var asset: String?
    var source: String?
    var url: String?
    let license: String
    let licenseURL: String
    let author: String

    var credit: WgerCredit { WgerCredit(license: license, licenseURL: licenseURL, author: author) }
}

struct WgerEntry: Decodable {
    let wger: Int
    let url: String
    /// "pt" ou "en" (inglês é traduzido no iPhone)
    let language: String
    let steps: [String]
    let text: WgerCredit
    let images: [WgerMedia]
    let videos: [WgerMedia]
}

private struct WgerFile: Decodable {
    struct New: Decodable { let id, name, group, equipment, type: String }
    let exercises: [String: WgerEntry]
    let new: [New]
}

enum WgerLibrary {
    private static let file: WgerFile? = {
        guard let url = Bundle.main.url(forResource: "wger", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WgerFile.self, from: data)
    }()

    static var entries: [String: WgerEntry] { file?.exercises ?? [:] }

    /// Exercícios que vieram só do wger
    static let newExercises: [Exercise] = (file?.new ?? []).compactMap { n in
        guard let g = MuscleGroup(rawValue: n.group), let t = ExerciseType(rawValue: n.type) else { return nil }
        return Exercise(id: n.id, name: n.name, group: g, equipment: n.equipment, type: t)
    }

    /// Nome curto da origem de um link (wger.de, Everkinetic, Commons)
    static func sourceName(_ url: String) -> String {
        url.contains("everkinetic") ? "Everkinetic" : url.contains("wikimedia") ? "Commons" : "wger.de"
    }

    /// Autores e licenças distintos, para a tela de créditos
    static var allCredits: [(WgerCredit, Int)] {
        var count: [WgerCredit: Int] = [:]
        for e in entries.values {
            for m in e.images + e.videos { count[m.credit, default: 0] += 1 }
            if !e.steps.isEmpty { count[e.text, default: 0] += 1 }
        }
        return count.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }
}

extension Exercise {
    var wger: WgerEntry? { WgerLibrary.entries[id] }
    /// Imagens embutidas (posição inicial e final, quando há duas)
    var photoAssets: [String] { wger?.images.compactMap(\.asset) ?? [] }
    var wgerVideo: WgerMedia? { wger?.videos.first }
}

/// Imagens do exercício: alterna entre elas como uma animação, com o crédito embaixo
struct ExercisePhotos: View {
    let exercise: Exercise
    @State private var frame = 0

    var body: some View {
        let assets = exercise.photoAssets
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                // As ilustrações têm fundo branco
                Color.white
                ForEach(Array(assets.enumerated()), id: \.offset) { i, a in
                    Image(a).resizable().scaledToFit().padding(10).opacity(i == frame ? 1 : 0)
                }
            }
            .frame(height: 240)
            .clipShape(.rect(cornerRadius: Theme.radiusM))
            if let img = exercise.wger?.images[safe: frame] {
                CreditLine(prefix: "Imagem", credit: img.credit, source: img.source)
            }
        }
        .task(id: assets.count) {
            guard assets.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation(.easeInOut(duration: 0.25)) { frame = (frame + 1) % assets.count }
            }
        }
    }
}

/// "Imagem: Everkinetic · CC BY-SA 3.0" com links para a licença e a origem
struct CreditLine: View {
    let prefix: String
    let credit: WgerCredit
    var source: String?

    var body: some View {
        HStack(spacing: 4) {
            Text("\(prefix): \(credit.author) ·")
            if let url = URL(string: credit.licenseURL) { Link(credit.license, destination: url).underline() }
            if let s = source, let url = URL(string: s) {
                Text("·")
                Link(WgerLibrary.sourceName(s), destination: url).underline()
            }
        }
        .font(.caption2)
        .foregroundStyle(Theme.dim)
        .tint(Theme.dim)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

/// Vídeo do wger tocando no próprio app
struct WgerVideoView: View {
    let exercise: Exercise
    let video: WgerMedia

    var body: some View {
        GMModal(exercise.name) {
            if let s = video.url, let url = URL(string: s) {
                VideoPlayer(player: AVPlayer(url: url))
                    .frame(height: 420)
                    .clipShape(.rect(cornerRadius: Theme.radiusM))
            }
            CreditLine(prefix: "Vídeo", credit: video.credit, source: exercise.wger?.url)
        }
    }
}

/// Créditos e licenças de tudo o que não foi feito por nós
struct CreditsView: View {
    var body: some View {
        GMModal("Créditos e licenças") {
            GMSection("Exercícios: wger, Everkinetic e Commons", footer: "Imagens, vídeos e instruções de exercícios do projeto wger (wger.de), ilustrações do Everkinetic (github.com/everkinetic/data, de Greg Priday) e fotos do Wikimedia Commons (domínio público, CC0, CC BY e CC BY-SA), sob Creative Commons. Cada imagem mostra o autor e a licença. Instruções em inglês são traduzidas no próprio iPhone; as adaptações seguem a mesma licença (CC BY-SA).") {
                if let url = URL(string: "https://wger.de") {
                    Link(destination: url) { Label("wger.de", systemImage: "link").font(.subheadline.weight(.semibold)) }
                }
                if let url = URL(string: "https://github.com/everkinetic/data") {
                    Link(destination: url) { Label("Everkinetic", systemImage: "link").font(.subheadline.weight(.semibold)) }
                }
                if let url = URL(string: "https://commons.wikimedia.org") {
                    Link(destination: url) { Label("Wikimedia Commons", systemImage: "link").font(.subheadline.weight(.semibold)) }
                }
                GMDivider()
                ForEach(WgerLibrary.allCredits, id: \.0) { credit, n in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(credit.author).font(.subheadline)
                            if let url = URL(string: credit.licenseURL) {
                                Link(credit.license, destination: url).font(.caption).tint(Theme.dim)
                            }
                        }
                        Spacer()
                        Text("\(n) ite\(n == 1 ? "m" : "ns")").font(.caption.monospacedDigit()).foregroundStyle(Theme.dim)
                    }
                }
            }
            GMSection("Mapa muscular: MuscleMap", footer: "Copyright (c) 2026 Melih Colpan. Licença MIT: uso livre, inclusive comercial, mantendo este aviso.") {
                if let url = URL(string: "https://github.com/melihcolpan/MuscleMap") {
                    Link(destination: url) { Label("github.com/melihcolpan/MuscleMap", systemImage: "link").font(.subheadline) }
                }
            }
            GMSection("Vídeos do YouTube", footer: "O botão de vídeo abre uma busca no YouTube; os vídeos são de seus autores.") { EmptyView() }
            GMSection("Bros", footer: "Artes dos bros, telas e textos do GymBros são próprios.") { EmptyView() }
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
