import AVFoundation
import AVKit
import Photos
import SwiftData
import SwiftUI

// Retrospectiva: vídeo feito no iPhone com as fotos dos seus check-ins do ano, abrindo com os números do ano e
// com a marca d'água "@usuário · GymBros". Nada sai do aparelho até você compartilhar.

enum RetroFormat: String, CaseIterable, Identifiable {
    case story, square, portrait

    var id: String { rawValue }
    var name: String {
        switch self {
        case .story: "9:16"
        case .square: "1:1"
        case .portrait: "3:4"
        }
    }

    var size: CGSize {
        switch self {
        case .story: CGSize(width: 1080, height: 1920)
        case .square: CGSize(width: 1080, height: 1080)
        case .portrait: CGSize(width: 1080, height: 1440)
        }
    }
}

enum RetroSpeed: Double, CaseIterable, Identifiable {
    case superSlow = 2.5, slow = 1.6, normal = 1.0, fast = 0.6, superFast = 0.35

    var id: Double { rawValue }
    var name: String {
        switch self {
        case .superSlow: "Bem lento"
        case .slow: "Lento"
        case .normal: "Normal"
        case .fast: "Rápido"
        case .superFast: "Bem rápido"
        }
    }
}

enum RetroVideo {
    static let fps: Int32 = 30

    /// Escreve o vídeo: abertura com os números, uma foto por vez e o fim com a marca
    static func make(photos: [UIImage], intro: [String], title: String, watermark: String, format: RetroFormat,
                     speed: RetroSpeed, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("retrospectiva-\(UUID().uuidString.prefix(6)).mp4")
        let size = format.size
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: size.width, AVVideoHeightKey: size.height,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: size.width, kCVPixelBufferHeightKey as String: size.height,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let slides: [(UIImage, Double)] = [(card(title: title, lines: intro, size: size), 2.4)]
            + photos.map { (frame($0, watermark: watermark, size: size), speed.rawValue) }
            + [(card(title: "Bora pra mais um ano 💪", lines: [watermark], size: size), 1.8)]
        var frameIndex: Int64 = 0
        for (i, (image, seconds)) in slides.enumerated() {
            guard let buffer = pixelBuffer(image, size: size) else { continue }
            for _ in 0..<max(Int(seconds * Double(fps)), 1) {
                while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
                adaptor.append(buffer, withPresentationTime: CMTime(value: frameIndex, timescale: fps))
                frameIndex += 1
            }
            progress(Double(i + 1) / Double(slides.count))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if let error = writer.error { throw error }
        return url
    }

    /// Foto preenchendo o quadro, com a marca d'água embaixo
    private static func frame(_ photo: UIImage, watermark: String, size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }()).image { _ in
            UIColor.black.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            let s = max(size.width / photo.size.width, size.height / photo.size.height)
            let w = photo.size.width * s, h = photo.size.height * s
            photo.draw(in: CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h))
            mark(watermark, size: size)
        }
    }

    /// Quadro de texto (abertura e fim) nas cores do app
    private static func card(title: String, lines: [String], size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }()).image { _ in
            UIColor(Theme.bg).setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            let center = NSMutableParagraphStyle()
            center.alignment = .center
            let titleAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 92, weight: .black), .foregroundColor: UIColor(Theme.accent),
                                                              .paragraphStyle: center]
            let lineAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 54, weight: .bold), .foregroundColor: UIColor.white,
                                                             .paragraphStyle: center]
            var y = size.height * 0.32
            (title as NSString).draw(in: CGRect(x: 60, y: y, width: size.width - 120, height: 240), withAttributes: titleAttrs)
            y += 260
            for l in lines {
                (l as NSString).draw(in: CGRect(x: 60, y: y, width: size.width - 120, height: 90), withAttributes: lineAttrs)
                y += 96
            }
        }
    }

    private static func mark(_ text: String, size: CGSize) {
        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 44, weight: .black), .foregroundColor: UIColor.white]
        let label = NSAttributedString(string: text, attributes: attrs)
        let b = label.size()
        let pad: CGFloat = 26
        let rect = CGRect(x: (size.width - b.width) / 2 - pad, y: size.height - b.height - 120 - pad / 2, width: b.width + pad * 2, height: b.height + pad)
        UIColor.black.withAlphaComponent(0.55).setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2).fill()
        label.draw(at: CGPoint(x: rect.minX + pad, y: rect.minY + pad / 2))
    }

    private static func pixelBuffer(_ image: UIImage, size: CGSize) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height), kCVPixelFormatType_32ARGB,
                            [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary, &buffer)
        guard let buffer, let cg = image.cgImage else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
        ctx?.draw(cg, in: CGRect(origin: .zero, size: size))
        return buffer
    }
}

/// Escolher fotos do ano, velocidade e formato, gerar e compartilhar
struct RetrospectiveView: View {
    @Query(sort: \LeagueCheckIn.date) private var checkIns: [LeagueCheckIn]
    @Query(sort: \Activity.date) private var activities: [Activity]
    @AppStorage("profileUsername") private var username = ""
    @AppStorage("trainerName") private var name = ""
    @State private var year = Calendar.current.component(.year, from: .now)
    @State private var removed: Set<UUID> = []
    @State private var format = RetroFormat.story
    @State private var speed = RetroSpeed.normal
    @State private var progress: Double?
    @State private var video: URL?
    @State private var error: String?
    @State private var saved = false

    /// Uma foto por atividade (a mesma foto postada em várias ligas conta uma vez)
    private var photos: [(id: UUID, data: Data)] {
        var seen = Set<UUID>()
        return checkIns.compactMap { c in
            guard Calendar.current.component(.year, from: c.date) == year, let p = c.photo, seen.insert(c.activityUUID).inserted else { return nil }
            return (c.uuid, p)
        }
    }

    private var years: [Int] {
        let all = Set(checkIns.filter { $0.photo != nil }.map { Calendar.current.component(.year, from: $0.date) })
        return all.isEmpty ? [year] : all.sorted(by: >)
    }

    var body: some View {
        GMModal("Retrospectiva") {
            if let video {
                VideoPlayer(player: AVPlayer(url: video)).frame(height: 420).clipShape(.rect(cornerRadius: Theme.radius))
                HStack(spacing: 10) {
                    ShareLink(item: video) { Label("Compartilhar", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }
                        .buttonStyle(GMPress()).padding(.vertical, 12).background(Theme.accent, in: .capsule).foregroundStyle(.black)
                    GMButton(saved ? "Salvo nas Fotos" : "Salvar nas Fotos", icon: saved ? "checkmark" : "photo.on.rectangle", kind: .secondary,
                             enabled: !saved) { save(video) }
                }
                GMButton("Fazer outro", icon: "arrow.counterclockwise", kind: .ghost) { self.video = nil; saved = false }
            } else {
                GMSection("Ano") {
                    GMChoiceChips(options: years.map { ($0, String($0)) }, selection: $year)
                }
                let list = photos
                GMSection("Fotos · \(list.count - list.filter { removed.contains($0.id) }.count)",
                          footer: list.isEmpty ? "Nenhum check-in com foto em \(year)." : "Toque numa foto para tirar do vídeo.") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                        ForEach(list, id: \.id) { p in
                            let off = removed.contains(p.id)
                            Button {
                                if off { removed.remove(p.id) } else { removed.insert(p.id) }
                            } label: {
                                Color.clear.aspectRatio(1, contentMode: .fit)
                                    .overlay { if let img = UIImage(data: p.data) { Image(uiImage: img).resizable().scaledToFill() } }
                                    .clipShape(.rect(cornerRadius: Theme.radiusS))
                                    .opacity(off ? 0.3 : 1)
                                    .overlay(alignment: .topTrailing) {
                                        Image(systemName: off ? "circle" : "checkmark.circle.fill").foregroundStyle(off ? .white : Theme.accent).padding(4)
                                    }
                            }
                            .buttonStyle(GMPress())
                        }
                    }
                }
                GMSection("Formato") { GMSegmented(options: RetroFormat.allCases.map { ($0, $0.name) }, selection: $format) }
                GMSection("Velocidade") { GMChoiceChips(options: RetroSpeed.allCases.map { ($0, $0.name) }, selection: $speed) }
                if let progress {
                    GMProgressBar(value: progress, height: 8)
                    Text("Gerando o vídeo…").font(.caption).foregroundStyle(Theme.dim)
                } else {
                    GMButton("Gerar vídeo", icon: "film", enabled: list.contains { !removed.contains($0.id) }) { generate() }
                }
                if let error { Text(error).font(.footnote).foregroundStyle(Theme.warning) }
            }
        }
        .onChange(of: year) { removed = [] }
    }

    private var intro: [String] {
        let yearActs = activities.filter { Calendar.current.component(.year, from: $0.date) == year }
        let days = Set(yearActs.map { Calendar.current.startOfDay(for: $0.date) }).count
        let best = Constancy.of(yearActs).daily.best?.length ?? 0
        return ["\(yearActs.count) treinos", "\(days) dias ativos", hoursText(yearActs.reduce(0) { $0 + $1.minutes }) + " de treino",
                "Maior sequência: \(best) dia\(best == 1 ? "" : "s")"]
    }

    private func generate() {
        let images = photos.filter { !removed.contains($0.id) }.compactMap { UIImage(data: $0.data) }
        let mark = (username.isEmpty ? name : "@\(username)") + " · GymBros"
        let intro = intro
        let title = "\(year) no GymBros"
        let (format, speed) = (format, speed)
        progress = 0
        error = nil
        Task {
            do {
                video = try await RetroVideo.make(photos: images, intro: intro, title: title, watermark: mark, format: format, speed: speed) { p in
                    Task { @MainActor in progress = p }
                }
            } catch {
                self.error = "Não deu para gerar o vídeo: \(error.localizedDescription)"
            }
            progress = nil
        }
    }

    private func save(_ url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in error = "Libere o acesso para adicionar fotos nos Ajustes do iPhone." }
                return
            }
            PHPhotoLibrary.shared().performChanges({ PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url) }) { ok, _ in
                Task { @MainActor in if ok { saved = true } else { error = "Não deu para salvar nas Fotos." } }
            }
        }
    }
}
