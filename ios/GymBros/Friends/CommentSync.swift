import FirebaseFirestore
import Foundation
import SwiftData

// Comentários e reações dos check-ins, compartilhados pela coleção `comments` do Firestore (só no modo `.firebase`).
// Cada documento tem o id do CheckInComment, quem escreveu (`user`, `userName`), o post (`item`), o dono dele (`owner`),
// a liga do post (`league`, "profile" no perfil) e se ela é pública (`feed`). O servidor só deixa ler quem pode ver o post:
// membros da liga, amigos de quem postou numa liga pública, ou qualquer conta nos posts do perfil (perfil público).
// Por isso toda consulta diz a liga (e, fora das suas ligas, o dono e `feed`).

/// Quem pode ver os comentários de um post: a liga dele e como você chega até ele
struct CommentScope: Hashable {
    let league: String
    /// Dono do post ("me" = você)
    let owner: String
    let isPublic: Bool
    /// Você está na liga (senão, só vê por ser amigo de quem postou numa liga pública)
    let member: Bool

    static let profile = CommentScope(league: CloudType.profileFeed, owner: "me", isPublic: false, member: true)

    @MainActor
    init(league: League, owner: String) {
        self.init(league: league.code, owner: owner, isPublic: !league.settings.isPrivate, member: true)
    }

    init(league: String, owner: String, isPublic: Bool, member: Bool) {
        self.league = league
        self.owner = owner
        self.isPublic = isPublic
        self.member = member
    }
}

@MainActor
enum CommentSync {
    static let collection = "comments"
    /// Comentários dos outros já baixados: se somem do servidor (apagados ou removidos pela moderação), saem daqui também
    static let pulledKey = "comments.pulled"

    private static var enabled: Bool { Backend.mode == .firebase && AuthStore.shared.isSignedIn }

    /// Grava o seu comentário (ou reação) aqui e no servidor
    @discardableResult
    static func add(_ text: String, to itemID: String, owner: String, scope: CommentScope, context: ModelContext) -> CheckInComment {
        let c = CheckInComment(itemID: itemID, text: text)
        context.insert(c)
        try? context.save()
        publish(c, owner: owner, scope: scope)
        return c
    }

    /// Apaga o seu comentário aqui e no servidor
    static func remove(_ c: CheckInComment, context: ModelContext) {
        retract(c)
        context.delete(c)
        try? context.save()
    }

    /// Sobe o seu comentário (ou reação). `owner` é o `memberID` do dono do post ("me" = você).
    static func publish(_ c: CheckInComment, owner: String, scope: CommentScope) {
        guard enabled, c.isMine, let me = try? Fire.me() else { return }
        let data: [String: Any] = [
            "user": me,
            "userName": UserDefaults.standard.string(forKey: "trainerName") ?? "",
            "item": c.itemID,
            "owner": owner == "me" ? me : owner,
            "text": c.text,
            "date": Timestamp(date: c.date),
            "league": scope.league,
            "feed": scope.isPublic,
            // Quem postou (nas reações a um comentário, `owner` é quem comentou)
            "poster": scope.owner == "me" ? me : scope.owner,
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
    static func pull(_ items: [(id: String, scope: CommentScope)], context: ModelContext) async {
        guard enabled, !items.isEmpty, let me = try? Fire.me() else { return }
        var docs: [QueryDocumentSnapshot] = []
        // Só os posts consultados com sucesso: num erro, os comentários guardados não somem
        var asked = Set<String>()
        // Uma consulta por liga (e, fora das suas ligas, por dono): é o que a regra do servidor consegue conferir
        for (scope, group) in Dictionary(grouping: items, by: \.scope) {
            let groupIDs = Array(Set(group.map(\.id)))
            for start in stride(from: 0, to: groupIDs.count, by: 30) {
                let chunk = Array(groupIDs[start..<min(start + 30, groupIDs.count)])
                var q: Query = Fire.db.collection(collection).whereField("league", isEqualTo: scope.league)
                if !scope.member && scope.league != CloudType.profileFeed {
                    q = q.whereField("poster", isEqualTo: scope.owner == "me" ? me : scope.owner).whereField("feed", isEqualTo: true)
                }
                guard let found = try? await q.whereField("item", in: chunk).getDocuments().documents else { continue }
                docs += found
                asked.formUnion(chunk)
            }
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
        for c in local where !c.isMine && asked.contains(c.itemID) && pulled.contains(c.uuid.uuidString) && !remote.contains(c.uuid.uuidString) {
            context.delete(c)
            pulled.remove(c.uuid.uuidString)
        }
        UserDefaults.standard.set(Array(pulled.suffix(3000)), forKey: pulledKey)
        try? context.save()
    }
}
