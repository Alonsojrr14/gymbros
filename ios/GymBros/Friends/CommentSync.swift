import FirebaseFirestore
import Foundation
import SwiftData

// Comentários e reações dos check-ins, compartilhados pela coleção `comments` do Firestore (só no modo `.firebase`).
// Cada documento tem o id do CheckInComment, quem escreveu (`user`, `userName`), o post (`item`) e o dono dele (`owner`).
// Quem vê o post vê os comentários de todo mundo, mesmo de quem não é seu amigo (o amigo do seu amigo).

@MainActor
enum CommentSync {
    static let collection = "comments"
    /// Comentários dos outros já baixados: se somem do servidor (apagados ou removidos pela moderação), saem daqui também
    static let pulledKey = "comments.pulled"

    private static var enabled: Bool { Backend.mode == .firebase && AuthStore.shared.isSignedIn }

    /// Grava o seu comentário (ou reação) aqui e no servidor
    @discardableResult
    static func add(_ text: String, to itemID: String, owner: String, context: ModelContext) -> CheckInComment {
        let c = CheckInComment(itemID: itemID, text: text)
        context.insert(c)
        try? context.save()
        publish(c, owner: owner)
        return c
    }

    /// Apaga o seu comentário aqui e no servidor
    static func remove(_ c: CheckInComment, context: ModelContext) {
        retract(c)
        context.delete(c)
        try? context.save()
    }

    /// Sobe o seu comentário (ou reação). `owner` é o `memberID` do dono do post ("me" = você).
    static func publish(_ c: CheckInComment, owner: String) {
        guard enabled, c.isMine, let me = try? Fire.me() else { return }
        let data: [String: Any] = [
            "user": me,
            "userName": UserDefaults.standard.string(forKey: "trainerName") ?? "",
            "item": c.itemID,
            "owner": owner == "me" ? me : owner,
            "text": c.text,
            "date": Timestamp(date: c.date),
        ]
        let id = c.uuid.uuidString
        Task { try? await Fire.db.collection(collection).document(id).setData(data) }
    }

    /// Tira do servidor um comentário seu que foi apagado aqui
    static func retract(_ c: CheckInComment) {
        guard enabled, c.isMine else { return }
        let id = c.uuid.uuidString
        Task { try? await Fire.db.collection(collection).document(id).delete() }
    }

    /// Baixa os comentários dos outros nesses posts (e nos comentários deles, para as reações) e guarda como CheckInComment
    static func pull(_ itemIDs: [String], context: ModelContext) async {
        guard enabled, !itemIDs.isEmpty, let me = try? Fire.me() else { return }
        var docs: [QueryDocumentSnapshot] = []
        let ids = Array(Set(itemIDs))
        for start in stride(from: 0, to: ids.count, by: 30) {
            let chunk = Array(ids[start..<min(start + 30, ids.count)])
            guard let found = try? await Fire.db.collection(collection).whereField("item", in: chunk).getDocuments().documents else { return }
            docs += found
        }
        let local = (try? context.fetch(FetchDescriptor<CheckInComment>())) ?? []
        let byID = Dictionary(local.map { ($0.uuid.uuidString, $0) }, uniquingKeysWith: { a, _ in a })
        var pulled = Set(UserDefaults.standard.stringArray(forKey: pulledKey) ?? [])
        var remote = Set<String>()
        for d in docs {
            let x = d.data()
            guard let user = x["user"] as? String, user != me, let uuid = UUID(uuidString: d.documentID),
                  let item = x["item"] as? String, let text = x["text"] as? String else { continue }
            remote.insert(d.documentID)
            pulled.insert(d.documentID)
            guard byID[d.documentID] == nil else { continue }
            let c = CheckInComment(itemID: item, text: text, authorID: user, authorName: x["userName"] as? String ?? "")
            c.uuid = uuid
            c.date = (x["date"] as? Timestamp)?.dateValue() ?? .now
            context.insert(c)
        }
        // Sumiu do servidor: apagado por quem escreveu, pelo dono do post ou pela moderação
        let asked = Set(ids)
        for c in local where !c.isMine && asked.contains(c.itemID) && pulled.contains(c.uuid.uuidString) && !remote.contains(c.uuid.uuidString) {
            context.delete(c)
            pulled.remove(c.uuid.uuidString)
        }
        UserDefaults.standard.set(Array(pulled.suffix(3000)), forKey: pulledKey)
        try? context.save()
    }
}
