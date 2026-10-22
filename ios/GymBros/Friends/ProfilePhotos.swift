import FirebaseFirestore
import Foundation
import Observation
import UIKit

/// Fotos de perfil que os outros veem (`avatars/{uid}` no Firestore, uma miniatura de 256 px).
/// A sua só sobe com "Foto do perfil" ligada em "O que aparece para os outros"; desligar tira do ar.
/// Fica fora do Storage (o plano grátis não tem): a miniatura cabe num documento.
@MainActor @Observable
final class ProfilePhotos {
    static let shared = ProfilePhotos()
    /// Mostrar a sua foto para os outros (padrão: sim, como o rodapé do perfil sempre disse)
    static let showKey = "publicPhoto"
    private static let publishedKey = "publishedAvatar"

    private(set) var photos: [String: Data] = [:]
    // Fora da observação: `photo(_:)` é chamado no `body` e não pode disparar outro redesenho
    @ObservationIgnored private var missing: Set<String> = []
    @ObservationIgnored private var loading: Set<String> = []

    private var db: Firestore? { Backend.mode == .firebase ? Fire.db : nil }

    /// Foto de alguém (nil enquanto carrega ou se a pessoa não tem/escondeu)
    func photo(_ id: String) -> Data? {
        if let p = photos[id] { return p }
        load(id)
        return nil
    }

    private func load(_ id: String) {
        guard let db, !id.isEmpty, id != "me", !missing.contains(id), !loading.contains(id) else { return }
        loading.insert(id)
        Task {
            defer { loading.remove(id) }
            let data = try? await db.collection("avatars").document(id).getDocument().data()?["data"] as? Data
            if let data { photos[id] = data } else { missing.insert(id) }
        }
    }

    /// Escuta ao vivo as fotos de quem aparece na tela (amigos, pedidos, sugestões): trocou ou escondeu, muda na hora.
    /// Uma escuta por lote de 10 pessoas (limite do `in` do Firestore)
    @ObservationIgnored private var listeners: [ListenerRegistration] = []
    @ObservationIgnored private var followed: [String] = []

    func follow(_ ids: [String]) {
        let ids = Array(Set(ids.filter { !$0.isEmpty && $0 != "me" })).sorted()
        guard let db, ids != followed else { return }
        followed = ids
        listeners.forEach { $0.remove() }
        listeners = stride(from: 0, to: ids.count, by: 10).map { start in
            let chunk = Array(ids[start..<min(start + 10, ids.count)])
            return db.collection("avatars").whereField(FieldPath.documentID(), in: chunk).addSnapshotListener { [weak self] snap, _ in
                guard let snap else { return }
                Task { @MainActor in
                    guard let self else { return }
                    let found = Dictionary(snap.documents.compactMap { d in (d.data()["data"] as? Data).map { (d.documentID, $0) } },
                                           uniquingKeysWith: { a, _ in a })
                    for id in chunk {
                        if let data = found[id] { self.photos[id] = data; self.missing.remove(id) } else { self.photos[id] = nil; self.missing.insert(id) }
                    }
                }
            }
        }
    }

    /// Esquece o que baixou (outra conta) e para de escutar
    func reset() {
        listeners.forEach { $0.remove() }
        listeners = []
        followed = []
        photos = [:]
        missing = []
    }

    /// Publica (ou tira do ar) a sua foto se mudou desde o último envio
    func publish() async {
        guard let db, let me = Backend.myID, AccessStore.shared.can(.profileUpdate) else { return }
        let d = UserDefaults.standard
        let show = d.object(forKey: Self.showKey) == nil || d.bool(forKey: Self.showKey)
        let thumb = show ? d.data(forKey: "profilePhoto").flatMap(Self.thumbnail) : nil
        let fingerprint = thumb.map { "\(me):\($0.count):\($0.hashValueStable)" } ?? "\(me):none"
        guard d.string(forKey: Self.publishedKey) != fingerprint else { return }
        let ref = db.collection("avatars").document(me)
        do {
            if let thumb { try await ref.setData(["data": thumb, "updatedAt": FieldValue.serverTimestamp()]) } else { try await ref.delete() }
            d.set(fingerprint, forKey: Self.publishedKey)
        } catch {}
    }

    /// 256 px no lado maior, JPEG: cabe com folga no limite das regras (150 KB)
    nonisolated static func thumbnail(_ data: Data) -> Data? {
        guard let img = UIImage(data: data) else { return nil }
        let side: CGFloat = 256
        let scale = min(1, side / max(img.size.width, img.size.height))
        let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let out = UIGraphicsImageRenderer(size: size, format: format).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
        return out.jpegData(compressionQuality: 0.75)
    }
}

private extension Data {
    /// Resumo estável entre aberturas do app (o `hashValue` muda a cada execução)
    var hashValueStable: String { String(reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1) }, radix: 16) }
}
