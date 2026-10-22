import FirebaseFirestore
import Foundation
import Observation
import UIKit

/// Fotos de perfil que os outros veem: a miniatura (160 px) em `avatars/{uid}` e a versão dela (`avatarVersion`) no perfil
/// público. A sua só sobe com "Foto do perfil" ligada em "O que aparece para os outros"; desligar tira do ar.
///
/// Para não gastar o limite do plano grátis (leituras e tráfego): os apps escutam só a versão, que vem no perfil (poucos
/// bytes), guardam cada foto no aparelho e só baixam de novo quando a versão muda. A escuta fica ligada só com a tela aberta.
@MainActor @Observable
final class ProfilePhotos {
    static let shared = ProfilePhotos()
    /// Mostrar a sua foto para os outros (padrão: sim, como o rodapé do perfil sempre disse)
    static let showKey = "publicPhoto"
    private static let publishedKey = "publishedAvatar"
    /// Lado maior da miniatura: nítida no avatar grande do perfil (110 pt) e leve nas listas
    nonisolated static let side: CGFloat = 160

    private(set) var photos: [String: Data] = [:]
    @ObservationIgnored private var versions: [String: String] = [:]
    @ObservationIgnored private var listeners: [ListenerRegistration] = []
    @ObservationIgnored private var followed: [String] = []

    private var db: Firestore? { Backend.mode == .firebase ? Fire.db : nil }

    /// Fotos de outras pessoas guardadas no aparelho (Caches: o sistema pode limpar; baixa de novo se precisar)
    private nonisolated static var folder: URL {
        URL.cachesDirectory.appending(path: "Avatars", directoryHint: .isDirectory)
    }

    private nonisolated static func file(_ id: String, _ version: String) -> URL {
        folder.appending(path: "\(id.filter { $0.isLetter || $0.isNumber })-\(version.filter { $0.isLetter || $0.isNumber }).jpg")
    }

    /// Foto de alguém (nil se a pessoa não tem, escondeu ou ainda não chegou)
    func photo(_ id: String) -> Data? { photos[id] }

    /// Escuta as versões das fotos de quem aparece na tela (amigos, pedidos, sugestões). Trocou ou escondeu: muda na hora.
    /// Escuta o perfil público (uma escuta por lote de 10, limite do `in`), não a foto.
    func follow(_ ids: [String]) {
        let ids = Array(Set(ids.filter { !$0.isEmpty && $0 != "me" })).sorted()
        guard let db, ids != followed else { return }
        stop()
        followed = ids
        listeners = stride(from: 0, to: ids.count, by: 10).map { start in
            let chunk = Array(ids[start..<min(start + 10, ids.count)])
            return db.collection(FireCollection.profiles).whereField(FieldPath.documentID(), in: chunk).addSnapshotListener { [weak self] snap, _ in
                guard let snap else { return }
                let found = Dictionary(snap.documents.map { ($0.documentID, $0.data()["avatarVersion"] as? String ?? "") },
                                       uniquingKeysWith: { a, _ in a })
                Task { @MainActor in
                    for id in chunk { self?.update(id, version: found[id] ?? "") }
                }
            }
        }
    }

    /// Tela fechada ou app em segundo plano: para de escutar
    func stop() {
        listeners.forEach { $0.remove() }
        listeners = []
        followed = []
    }

    private func update(_ id: String, version: String) {
        guard versions[id] != version || (photos[id] == nil && !version.isEmpty) else { return }
        versions[id] = version
        guard !version.isEmpty else {
            photos[id] = nil
            return
        }
        let url = Self.file(id, version)
        if let saved = try? Data(contentsOf: url) {
            photos[id] = saved
            return
        }
        guard let db else { return }
        Task {
            guard let data = try? await db.collection("avatars").document(id).getDocument().data()?["data"] as? Data,
                  versions[id] == version else { return }
            photos[id] = data
            // Guarda a versão nova e apaga as antigas da pessoa
            let fm = FileManager.default
            try? fm.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            let prefix = "\(id.filter { $0.isLetter || $0.isNumber })-"
            for old in (try? fm.contentsOfDirectory(atPath: Self.folder.path)) ?? [] where old.hasPrefix(prefix) {
                try? fm.removeItem(at: Self.folder.appending(path: old))
            }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Outra conta: esquece tudo, inclusive as fotos guardadas
    func reset() {
        stop()
        photos = [:]
        versions = [:]
        try? FileManager.default.removeItem(at: Self.folder)
    }

    /// Publica (ou tira do ar) a sua foto se mudou desde o último envio: a miniatura e a versão no perfil
    func publish() async {
        guard let db, let me = Backend.myID, AccessStore.shared.can(.profileUpdate) else { return }
        let d = UserDefaults.standard
        let show = d.object(forKey: Self.showKey) == nil || d.bool(forKey: Self.showKey)
        let thumb = show ? d.data(forKey: "profilePhoto").flatMap(Self.thumbnail) : nil
        let version = thumb.map(\.stableHash) ?? ""
        let fingerprint = "\(me):\(version)"
        guard d.string(forKey: Self.publishedKey) != fingerprint else { return }
        let ref = db.collection("avatars").document(me)
        do {
            if let thumb { try await ref.setData(["data": thumb, "updatedAt": FieldValue.serverTimestamp()]) } else { try await ref.delete() }
            // A versão vai por último: quem escuta só baixa depois que a foto nova já está lá
            try await db.collection(FireCollection.profiles).document(me).setData(["avatarVersion": version], merge: true)
            d.set(fingerprint, forKey: Self.publishedKey)
        } catch {}
    }

    /// 160 px no lado maior, JPEG: ~10 KB, bem dentro do limite das regras (150 KB)
    nonisolated static func thumbnail(_ data: Data) -> Data? {
        guard let img = UIImage(data: data) else { return nil }
        let scale = min(1, side / max(img.size.width, img.size.height))
        let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let out = UIGraphicsImageRenderer(size: size, format: format).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
        return out.jpegData(compressionQuality: 0.75)
    }
}

private extension Data {
    /// Resumo estável entre aberturas e aparelhos (o `hashValue` muda a cada execução)
    var stableHash: String { String(reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1) }, radix: 16) }
}
