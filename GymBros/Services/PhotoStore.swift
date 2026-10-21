import CloudKit
import Foundation

// Fotos dos check-ins ficam fora do Firestore: no plano grátis do Firebase não existe Cloud Storage. Elas vão para o
// banco público do CloudKit (grátis, cresce com o número de usuários) e o check-in no Firestore guarda só o nome
// do registro. Ler o banco público não precisa de conta do iCloud; gravar precisa (sem ela, o check-in sobe sem a foto).
// Quando o Firebase passar para o plano Blaze, basta outro PhotoStore com o Cloud Storage: as ligas não mudam.

protocol PhotoStore: Sendable {
    /// Sobe a foto e devolve a referência guardada no check-in
    func upload(_ data: Data, id: String) async throws -> String
    /// Arquivos locais das fotos (baixa o que ainda não está no cache)
    func files(for refs: [String]) async -> [String: URL]
    func delete(_ refs: [String]) async throws
}

/// Antes da conta paga do Apple Developer não há iCloud: a foto não sobe (o check-in sobe sem ela)
struct NoPhotoStore: PhotoStore {
    func upload(_ data: Data, id: String) async throws -> String { throw CloudError.noAccount }
    func files(for refs: [String]) async -> [String: URL] { [:] }
    func delete(_ refs: [String]) async throws {}
}

/// Um registro `Photo` por foto no banco público do container do app (esquema em docs/firebase.md)
struct CloudKitPhotoStore: PhotoStore {
    static let type = "Photo"

    private var db: CKDatabase { Cloud.db }

    /// Cache das fotos baixadas (o sistema pode limpar; aí baixa de novo)
    static var cache: URL { URL.cachesDirectory.appending(path: "Photos", directoryHint: .isDirectory) }

    private func cached(_ ref: String) -> URL { Self.cache.appending(path: ref + ".jpg") }

    func upload(_ data: Data, id: String) async throws -> String {
        let ref = "photo-" + id
        let url = FileManager.default.temporaryDirectory.appending(path: ref + ".jpg")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let r = CKRecord(recordType: Self.type, recordID: CKRecord.ID(recordName: ref))
        r["image"] = CKAsset(fileURL: url)
        _ = try await db.modifyRecords(saving: [r], deleting: [], savePolicy: .allKeys)
        // Quem postou já tem a foto: não precisa baixar de volta
        try? FileManager.default.createDirectory(at: Self.cache, withIntermediateDirectories: true)
        try? data.write(to: cached(ref))
        return ref
    }

    func files(for refs: [String]) async -> [String: URL] {
        var out: [String: URL] = [:]
        var missing: [String] = []
        for ref in Set(refs) {
            if FileManager.default.fileExists(atPath: cached(ref).path) { out[ref] = cached(ref) } else { missing.append(ref) }
        }
        try? FileManager.default.createDirectory(at: Self.cache, withIntermediateDirectories: true)
        // O CloudKit aceita até 400 registros por pedido
        for start in stride(from: 0, to: missing.count, by: 200) {
            let ids = missing[start..<min(start + 200, missing.count)].map { CKRecord.ID(recordName: $0) }
            guard let found = try? await db.records(for: ids, desiredKeys: ["image"]) else { continue }
            for (id, result) in found {
                guard let file = (try? result.get())?["image"] as? CKAsset, let src = file.fileURL else { continue }
                let dst = cached(id.recordName)
                try? FileManager.default.removeItem(at: dst)
                if (try? FileManager.default.copyItem(at: src, to: dst)) != nil { out[id.recordName] = dst }
            }
        }
        return out
    }

    func delete(_ refs: [String]) async throws {
        guard !refs.isEmpty else { return }
        for ref in refs { try? FileManager.default.removeItem(at: cached(ref)) }
        for start in stride(from: 0, to: refs.count, by: 300) {
            let ids = refs[start..<min(start + 300, refs.count)].map { CKRecord.ID(recordName: $0) }
            _ = try await db.modifyRecords(saving: [], deleting: ids)
        }
    }
}
