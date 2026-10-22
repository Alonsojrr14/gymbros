import AVFoundation
import CryptoKit
import ImageIO
import SwiftUI

// Prova de um check-in: de onde veio a foto (câmera do app ou galeria), a hora e o local gravados nela,
// se o treino foi gravado por aparelho e a pose do dia. Vai junto do check-in (`LeagueCheckIn.proofRaw`)
// para as regras de verificação darem o mesmo resultado em todos os aparelhos.

struct PhotoProof: Codable, Hashable, Sendable {
    enum Source: String, Codable, Sendable { case camera, library }

    var source: Source
    /// Câmera do app: a hora em que tirou. Galeria: a hora gravada na foto (EXIF); nil = a foto não tem
    var takenAt: Date?
    /// A foto tem local gravado (GPS no EXIF)
    var hasLocation = false

    /// A hora da foto da galeria serve como verificada: existe, é do mesmo dia do treino e não é do futuro
    func timeIsValid(for workout: Date, now: Date = .now, calendar: Calendar = .current) -> Bool {
        if source == .camera { return true }
        guard let takenAt else { return false }
        return takenAt <= now.addingTimeInterval(60) && calendar.isDate(takenAt, inSameDayAs: workout)
    }

    /// Lê a hora e o local gravados na foto original, antes de ela ser reduzida (a redução tira o EXIF)
    static func library(_ data: Data) -> PhotoProof {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else {
            return PhotoProof(source: .library)
        }
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any]
        let raw = (exif?[kCGImagePropertyExifDateTimeOriginal] ?? exif?[kCGImagePropertyExifDateTimeDigitized] ?? tiff?[kCGImagePropertyTIFFDateTime]) as? String
        let offset = (exif?[kCGImagePropertyExifOffsetTimeOriginal] ?? exif?[kCGImagePropertyExifOffsetTime]) as? String
        return PhotoProof(source: .library, takenAt: raw.flatMap { exifDate($0, offset: offset) },
                          hasLocation: gps?[kCGImagePropertyGPSLatitude] != nil)
    }

    /// "2026:10:21 07:42:10" com o fuso "-03:00" (sem fuso, o do aparelho)
    static func exifDate(_ s: String, offset: String?) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = offset == nil ? "yyyy:MM:dd HH:mm:ss" : "yyyy:MM:dd HH:mm:ssxxx"
        return f.date(from: offset.map { s + $0 } ?? s)
    }

    /// "Tirada na câmera do app", "Da galeria · tirada 21/10 07:42", "Da galeria, sem hora gravada"
    var label: String {
        switch source {
        case .camera: return "Tirada na câmera do app"
        case .library:
            guard let takenAt else { return "Da galeria, sem hora gravada" }
            return "Da galeria · tirada \(takenAt.formatted(.dateTime.day().month(.twoDigits).hour().minute()))"
        }
    }
}

/// O que vai junto do check-in como prova
struct CheckInProof: Codable, Hashable, Sendable {
    var photo: PhotoProof?
    /// Gravado por aparelho (Apple Saúde, Apple Watch ou GPS do app)
    var deviceRecorded = false
    /// Nome do aparelho ou app que gravou, quando houver
    var device: String?
    /// Pose do dia que estava na câmera quando tirou a foto
    var pose: String?
    /// Academia da visita verificada pela localização durante o treino
    var gymVisit: String?
    /// Outras atividades do mesmo dia que vão juntas neste check-in (as suas, pelo uuid)
    var grouped: [UUID] = []
    /// As mesmas atividades agrupadas, com o que os outros aparelhos precisam para pontuar
    var groupedParts: [ScorePart] = []

    init(photo: PhotoProof? = nil, deviceRecorded: Bool = false, device: String? = nil, pose: String? = nil) {
        self.photo = photo
        self.deviceRecorded = deviceRecorded
        self.device = device
        self.pose = pose
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        photo = try c.decodeIfPresent(PhotoProof.self, forKey: .photo)
        deviceRecorded = try c.decodeIfPresent(Bool.self, forKey: .deviceRecorded) ?? false
        device = try c.decodeIfPresent(String.self, forKey: .device)
        pose = try c.decodeIfPresent(String.self, forKey: .pose)
        gymVisit = try c.decodeIfPresent(String.self, forKey: .gymVisit)
        grouped = try c.decodeIfPresent([UUID].self, forKey: .grouped) ?? []
        groupedParts = try c.decodeIfPresent([ScorePart].self, forKey: .groupedParts) ?? []
    }

    init(rawValue: String) {
        self = (try? JSONDecoder().decode(CheckInProof.self, from: Data(rawValue.utf8))) ?? CheckInProof()
    }

    var rawValue: String {
        guard self != CheckInProof() else { return "" }
        let e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        return (try? e.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    /// Linhas para o detalhe do check-in
    var lines: [String] {
        var out: [String] = []
        if let photo { out.append(photo.label) }
        if deviceRecorded { out.append(device.map { "Gravado no \($0)" } ?? "Gravado por aparelho") }
        if let gymVisit { out.append("📍 Visita verificada na \(gymVisit)") }
        if let p = DailyPose.byID(pose) { out.append("\(p.emoji) Pose do dia: \(p.name)") }
        return out
    }
}

/// Lembra de onde veio cada foto escolhida, pelo conteúdo já reduzido: as telas guardam só `Data`
/// e a prova é recuperada na hora de postar.
@MainActor
enum PhotoProofs {
    private static var byHash: [String: PhotoProof] = [:]
    private static var poses: [String: String] = [:]

    private static func key(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    static func register(_ data: Data, proof: PhotoProof, pose: String? = nil) {
        let k = key(data)
        byHash[k] = proof
        poses[k] = pose
    }

    static func proof(for data: Data?) -> PhotoProof? {
        guard let data else { return nil }
        // Foto sem registro (ex.: já estava no post): conta como da galeria, sem hora
        return byHash[key(data)] ?? PhotoProof(source: .library)
    }

    static func pose(for data: Data?) -> String? { data.flatMap { poses[key($0)] } }
}

extension Activity {
    /// Gravada por aparelho: veio do Apple Saúde, do Apple Watch ou do GPS do app
    var isDeviceRecorded: Bool { source != nil }
}

extension PostSubject {
    @MainActor
    init(activity a: Activity) {
        self.init(workoutTypeID: a.workoutType.id, date: a.date, minutes: a.minutes, deviceRecorded: a.isDeviceRecorded,
                  place: GymLocation.shared.gym(a.gymUUID)?.name ?? GymLocation.shared.placeNow,
                  gymVisit: GymLocation.shared.visit(from: a.date, minutes: a.minutes)?.gymName)
    }
}

extension CheckInProof {
    /// Prova gravada no check-in: a pose só fica quando a liga cobra
    init(subject s: PostSubject, league: League?, pose: String?, device: String?) {
        self.init(photo: s.photo, deviceRecorded: s.deviceRecorded, device: s.deviceRecorded ? device : nil,
                  pose: league?.settings.posesEnabled == true ? pose : nil)
        gymVisit = s.gymVisit
    }
}

extension League {
    /// O check-in espera o dono aprovar: só em liga com revisão, e o do próprio dono (ou de um moderador) já entra aprovado
    @MainActor
    func needsReview(fromMe: Bool) -> Bool { settings.reviewRequired && !(fromMe && canModerate) }

    /// Dono ou moderador: revisa check-ins, remove check-ins e membros, aceita pedidos de entrada
    @MainActor
    var canModerate: Bool { isMine || settings.mods.contains(LeagueBoard.selfID) }
}

// MARK: - Câmera do app

/// Câmera de foto do check-in, com a pose do dia por cima quando alguma liga cobra
struct CheckInCamera: View {
    var pose: DailyPose?
    let onPhoto: (Data) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var camera = CameraModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if camera.denied {
                VStack(spacing: 12) {
                    Image(systemName: "camera.fill").font(.largeTitle).foregroundStyle(Theme.dim)
                    Text("A câmera está desligada").font(.headline)
                    Text("Libere o acesso nos Ajustes do iPhone para tirar a foto do check-in.")
                        .font(.subheadline).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                    GMButton("Abrir Ajustes", icon: "gear", full: false, small: true) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
                .padding(32)
            } else {
                CameraPreview(session: camera.session).ignoresSafeArea()
            }
            VStack {
                HStack {
                    GMIconButton(icon: "xmark", size: 40, label: "Fechar") { dismiss() }
                    Spacer()
                    if !camera.denied {
                        GMIconButton(icon: "arrow.triangle.2.circlepath.camera", size: 40, label: "Trocar câmera") { camera.flip() }
                    }
                }
                .padding(16)
                if let pose {
                    Text("\(pose.emoji) Pose do dia: \(pose.name)")
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.black.opacity(0.65), in: .capsule)
                        .foregroundStyle(.white)
                        .accessibilityLabel("Pose do dia: \(pose.name)")
                }
                Spacer()
                if !camera.denied {
                    Button {
                        camera.capture { data in
                            onPhoto(data)
                            dismiss()
                        }
                    } label: {
                        Circle().fill(.white).frame(width: 72, height: 72)
                            .overlay(Circle().stroke(.black.opacity(0.3), lineWidth: 3).padding(5))
                    }
                    .buttonStyle(GMPress())
                    .accessibilityLabel("Tirar foto")
                    .disabled(camera.busy)
                    .padding(.bottom, 30)
                }
            }
        }
        .task { await camera.start() }
        .onDisappear { camera.stop() }
    }
}

@MainActor @Observable
private final class CameraModel: NSObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var position: AVCaptureDevice.Position = .back
    private var done: ((Data) -> Void)?
    var denied = false
    var busy = false

    func start() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { denied = true; return }
        default: denied = true; return
        }
        configure()
        let s = session
        Task.detached { s.startRunning() }
    }

    func stop() {
        let s = session
        Task.detached { s.stopRunning() }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        session.inputs.forEach(session.removeInput)
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
           let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
            session.addInput(input)
        }
        if !session.outputs.contains(output), session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
    }

    func flip() {
        position = position == .back ? .front : .back
        configure()
    }

    func capture(_ done: @escaping (Data) -> Void) {
        guard !busy else { return }
        busy = true
        self.done = done
        output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = photo.fileDataRepresentation()
        Task { @MainActor in
            busy = false
            if let data { done?(data) }
            done = nil
        }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.layer.session = session
        v.layer.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        override var layer: AVCaptureVideoPreviewLayer { super.layer as! AVCaptureVideoPreviewLayer }
    }
}

/// Uma atividade agrupada num check-in, com o que vale para pontuar (o mesmo que sobe de um check-in sozinho)
struct ScorePart: Codable, Hashable, Sendable {
    var kindRaw: String
    var minutes: Int
    var effort: Int
    var meters: Double?
    var kcal: Double?
    var workoutTypeID: UInt?

    var input: ScoreInput {
        let kind = ActivityKind(rawValue: kindRaw) ?? .outro
        return ScoreInput(kind: kind, minutes: minutes, effort: effort, meters: meters, kcal: kcal, workoutTypeID: workoutTypeID ?? WorkoutType.of(kind).id)
    }
}

extension Activity {
    var scorePart: ScorePart {
        let i = scoreInput
        return ScorePart(kindRaw: kindRaw, minutes: i.minutes, effort: i.effort, meters: i.meters, kcal: i.kcal, workoutTypeID: i.workoutTypeID)
    }
}

extension League {
    /// Pontos de um check-in com todas as atividades dele: a principal e as agrupadas do mesmo dia
    func score(_ parts: [ScoreInput], hasPhoto: Bool) -> Int { parts.reduce(0) { $0 + score($1, hasPhoto: hasPhoto) } }
}

