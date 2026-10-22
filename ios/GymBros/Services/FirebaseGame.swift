import FirebaseFirestore
import Foundation

// Modo `.firebase`, o resto do jogo: X1, trocas de bros, denúncias e bloqueios, roles e ações de admin, rotinas
// públicas e a cópia da conta. Datas que valem regra (criação do X1 e da troca, resposta) são as do servidor
// (`FieldValue.serverTimestamp()`, conferido em firestore.rules com `request.time`): o relógio do aparelho não manda.
// Sem Cloud Functions, o placar do X1 e as trocas confiam no que cada aparelho informa sobre si.

extension Fire {
    static func json<T: Encodable>(_ value: T) -> String? {
        (try? JSONEncoder().encode(value)).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func decode<T: Decodable>(_ type: T.Type, _ raw: Any?) -> T? {
        (raw as? String)?.data(using: .utf8).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    /// Lê o documento com o horário do servidor estimado enquanto a gravação ainda não voltou
    static func data(_ doc: DocumentSnapshot) -> [String: Any] {
        doc.data(with: .estimate) ?? [:]
    }

    static func date(_ raw: Any?) -> Date? { (raw as? Timestamp)?.dateValue() }

    /// "Sem permissão" do Firestore (regra recusou)
    static func denied(_ error: Error) -> Bool {
        (error as NSError).domain == FirestoreErrorDomain && (error as NSError).code == FirestoreErrorCode.Code.permissionDenied.rawValue
    }
}

extension FireCollection {
    static let duels = "duels", trades = "trades", tradeBros = "tradeBros", reports = "reports", blocks = "blocks",
               roles = "roles", routines = "routines", accounts = "accounts", friendCodes = "friendCodes"
}

extension Backend {
    /// O seu id no servidor do modo atual (o app chama você de "me" e troca pelo id real ao falar com o servidor)
    static var myID: String? { mode == .firebase ? FirebaseSession.uid : Cloud.knownID }
}

// MARK: - X1

/// Um documento por X1 em `duels`: quem desafia cria; só o desafiado responde (uma vez) e cada lado só escreve
/// o próprio valor (`score_<uid>`), conferido pelas regras
struct FirebaseDuelBackend: DuelBackend {
    private var col: CollectionReference { Fire.db.collection(FireCollection.duels) }

    func duels(now: Date) async throws -> [RemoteDuel] {
        let me = try Fire.me()
        let since = now.addingTimeInterval(-30 * 86_400)
        let docs = try await col.whereField("participants", arrayContains: me).whereField("createdAt", isGreaterThanOrEqualTo: since)
            .getDocuments().documents
        return docs.compactMap { doc in
            let d = Fire.data(doc)
            guard let from = d["challenger"] as? String, let to = d["challenged"] as? String,
                  let metric = (d["metric"] as? String).flatMap(DuelMetric.init(rawValue:)) else { return nil }
            var duel = RemoteDuel(id: doc.documentID,
                                  challenger: DuelPerson(id: from, name: d["challengerName"] as? String ?? "",
                                                         formID: d["challengerFormID"] as? String ?? MonsterForm.egg.id),
                                  challenged: DuelPerson(id: to, name: d["challengedName"] as? String ?? "",
                                                         formID: d["challengedFormID"] as? String ?? MonsterForm.egg.id),
                                  metric: metric, createdAt: Fire.date(d["createdAt"]) ?? now)
            duel.answer = (d["answer"] as? String).flatMap(DuelAnswer.init(rawValue:))
            duel.answeredAt = Fire.date(d["answeredAt"])
            for u in [from, to] { if let v = d["score_\(u)"] as? Int { duel.reported[u] = v } }
            return duel
        }
    }

    func challenge(_ opponent: DuelPerson, from me: DuelPerson, metric: DuelMetric, now: Date) async throws -> RemoteDuel {
        let my = try Fire.me()
        guard opponent.id != my else { throw DuelRefusal.yourself }
        let ref = col.document("duel-\(UUID().uuidString)")
        do {
            try await ref.setData([
                "challenger": my, "challengerName": me.name, "challengerFormID": me.formID,
                "challenged": opponent.id, "challengedName": opponent.name, "challengedFormID": opponent.formID,
                "participants": [my, opponent.id], "metric": metric.rawValue, "createdAt": FieldValue.serverTimestamp(),
            ])
        } catch let error where Fire.denied(error) {
            // A regra só recusa quem não é seu amigo ou te bloqueou
            throw DuelRefusal.blocked
        }
        return RemoteDuel(id: ref.documentID, challenger: DuelPerson(id: my, name: me.name, formID: me.formID), challenged: opponent,
                          metric: metric, createdAt: now)
    }

    func respond(to duelID: String, accept: Bool, as person: DuelPerson, now: Date) async throws {
        var data: [String: Any] = ["answer": (accept ? DuelAnswer.accepted : .declined).rawValue, "answeredAt": FieldValue.serverTimestamp()]
        // Bro que vai lutar (quem desafiou só sabia o seu bro principal)
        if accept { data["challengedFormID"] = person.formID }
        do { try await col.document(duelID).updateData(data) } catch let error where Fire.denied(error) { throw DuelRefusal.notPending }
    }

    func report(_ value: Int, for duelID: String, now: Date) async throws {
        let me = try Fire.me()
        try await col.document(duelID).updateData(["score_\(me)": value])
    }
}

// MARK: - Trocas

/// Uma proposta por documento em `trades`; os bros que você pode trocar ficam em `tradeBros/{uid}` para os amigos
/// escolherem. Cada aparelho aplica a sua parte da troca aceita (TradeLedger), como no servidor simulado.
struct FirebaseTradeBackend: TradeBackend {
    private var col: CollectionReference { Fire.db.collection(FireCollection.trades) }
    private static let publishedKey = "tradeBrosPublished"

    func bros(of friendID: String) async throws -> [TradeBro] {
        let d = try await Fire.db.collection(FireCollection.tradeBros).document(friendID).getDocument().data()
        return Fire.decode([TradeBro].self, d?["bros"]) ?? []
    }

    func proposals(now: Date, mine: [TradeBro], me: TradePerson) async throws -> [TradeProposal] {
        let my = try Fire.me()
        try await publish(mine, me: my)
        let since = now.addingTimeInterval(-30 * 86_400)
        let docs = try await col.whereField("participants", arrayContains: my).whereField("createdAt", isGreaterThanOrEqualTo: since)
            .getDocuments().documents
        return docs.compactMap { doc in
            let d = Fire.data(doc)
            guard let from = d["from"] as? String, let to = d["to"] as? String,
                  let give = Fire.decode(TradeBro.self, d["give"]), let get = Fire.decode(TradeBro.self, d["get"]) else { return nil }
            // O app chama você de "me"
            func person(_ id: String, _ prefix: String) -> TradePerson {
                TradePerson(id: id == my ? "me" : id, name: d["\(prefix)Name"] as? String ?? "", formID: d["\(prefix)FormID"] as? String ?? MonsterForm.egg.id)
            }
            var p = TradeProposal(id: doc.documentID, from: person(from, "from"), to: person(to, "to"), give: give, get: get,
                                  createdAt: Fire.date(d["createdAt"]) ?? now)
            p.answer = (d["answer"] as? String).flatMap(TradeAnswer.init(rawValue:))
            p.answeredAt = Fire.date(d["answeredAt"])
            return p.answer == .canceled ? nil : p
        }
    }

    /// Só grava a lista quando ela muda
    private func publish(_ mine: [TradeBro], me: String) async throws {
        guard let raw = Fire.json(mine.sorted { $0.id < $1.id }), UserDefaults.standard.string(forKey: Self.publishedKey) != raw else { return }
        try await Fire.db.collection(FireCollection.tradeBros).document(me).setData(["user": me, "bros": raw, "updatedAt": Date.now])
        UserDefaults.standard.set(raw, forKey: Self.publishedKey)
    }

    func propose(to friend: TradePerson, from me: TradePerson, give: TradeBro, get: TradeBro, now: Date) async throws -> TradeProposal {
        let my = try Fire.me()
        let ref = col.document(UUID().uuidString)
        try await ref.setData(Fire.fields([
            "from": my, "fromName": me.name, "fromFormID": me.formID, "to": friend.id, "toName": friend.name, "toFormID": friend.formID,
            "participants": [my, friend.id], "give": Fire.json(give), "get": Fire.json(get),
        ]).merging(["createdAt": FieldValue.serverTimestamp()]) { $1 })
        return TradeProposal(id: ref.documentID, from: me, to: friend, give: give, get: get, createdAt: now)
    }

    func respond(to id: String, accept: Bool, now: Date) async throws {
        do {
            try await col.document(id).updateData(["answer": (accept ? TradeAnswer.accepted : .declined).rawValue,
                                                   "answeredAt": FieldValue.serverTimestamp()])
        } catch let error where Fire.denied(error) {
            throw TradeRefusal.notPending
        }
    }

    func cancel(_ id: String, now: Date) async throws {
        do {
            try await col.document(id).updateData(["answer": TradeAnswer.canceled.rawValue, "answeredAt": FieldValue.serverTimestamp()])
        } catch let error where Fire.denied(error) {
            throw TradeRefusal.notPending
        }
    }
}

// MARK: - Denúncias e bloqueios

/// Denúncia em `reports` (só admins leem, no app ou no console); bloqueio em `blocks/{você}->{pessoa}`.
/// As regras usam o bloqueio: quem te bloqueou não te manda mensagem nem te desafia.
struct FirebaseModerationBackend: ModerationBackend {
    func report(content c: ReportedContent, reason: ReportReason) async throws {
        let me = try Fire.me()
        try await Fire.db.collection(FireCollection.reports).document("\(me)-\(c.key)").setData([
            "user": me, "kind": c.kind.rawValue, "contentID": c.id, "author": c.authorID, "authorName": c.authorName,
            "reason": reason.rawValue, "date": FieldValue.serverTimestamp(),
        ])
    }

    func block(userID: String, name: String) async throws {
        let me = try Fire.me()
        try await Fire.db.collection(FireCollection.blocks).document("\(me)->\(userID)").setData([
            "user": me, "blocked": userID, "name": name, "date": Date.now,
        ])
    }

    func unblock(userID: String) async throws {
        let me = try Fire.me()
        try await Fire.db.collection(FireCollection.blocks).document("\(me)->\(userID)").delete()
    }

    func blockedUsers() async throws -> [BlockedUser] {
        let me = try Fire.me()
        return try await Fire.db.collection(FireCollection.blocks).whereField("user", isEqualTo: me).getDocuments().documents.compactMap { doc in
            let d = doc.data()
            guard let id = d["blocked"] as? String else { return nil }
            return BlockedUser(id: id, name: d["name"] as? String ?? "", date: Fire.date(d["date"]) ?? .now)
        }
    }
}

// MARK: - Roles e admin

/// `roles/{uid}` com a lista `roles` (ex.: ["USER", "ADMIN"]). O primeiro admin é criado à mão no console do Firebase;
/// depois disso, admins dão roles para outras pessoas pelo app (nunca para si mesmos)
struct FirebaseRoleBackend: RoleBackend {
    func assignment(for userID: String) async throws -> [String]? {
        let me = try Fire.me()
        guard me == userID else { throw FireError.signedOut }
        let doc = try await Fire.db.collection(FireCollection.roles).document(me).getDocument()
        return doc.exists ? doc.data()?["roles"] as? [String] ?? [] : nil
    }
}

/// Com as regras dando poder ao role ADMIN, o próprio app faz o papel do "servidor confiável" do contrato
struct FirebaseAdminBackend: AdminBackend {
    func reports() async throws -> [PendingReport] {
        try await Fire.db.collection(FireCollection.reports).order(by: "date", descending: true).limit(to: 200).getDocuments().documents
            .compactMap { doc in
                let d = Fire.data(doc)
                guard let user = d["user"] as? String, let kind = (d["kind"] as? String).flatMap(ReportedContent.Kind.init(rawValue:)),
                      let id = d["contentID"] as? String, let reason = (d["reason"] as? String).flatMap(ReportReason.init(rawValue:)) else { return nil }
                return PendingReport(reporterID: user,
                                     content: ReportedContent(kind: kind, id: id, authorID: d["author"] as? String ?? "",
                                                              authorName: d["authorName"] as? String ?? ""),
                                     reason: reason, date: Fire.date(d["date"]) ?? .now)
            }
    }

    /// Tira do ar para todos. Fotos não moram no Firestore (fotos são do CloudKit de quem postou)
    func remove(_ c: ReportedContent) async throws {
        let db = Fire.db
        switch c.kind {
        case .checkIn: try await db.collection(FireCollection.checkIns).document(c.id).delete()
        case .message: try await db.collection(FireCollection.messages).document(c.id).delete()
        case .directMessage: try await db.collection(FireCollection.directMessages).document(c.id).delete()
        case .profile:
            try await db.collection(FireCollection.profiles).document(c.authorID)
                .setData(["name": "", "username": "", "bio": "", "public": NSNull()], merge: true)
            // A foto do perfil sai junto
            try await db.collection("avatars").document(c.authorID).delete()
        case .comment: try await db.collection(CommentSync.collection).document(c.id).delete()
        case .photo: throw AccessError.requiresTrustedServer
        }
        // Resolvida: as denúncias desse conteúdo saem da fila
        let reports = try await db.collection(FireCollection.reports).whereField("contentID", isEqualTo: c.id).getDocuments().documents
        try await Fire.delete(reports.map(\.reference))
    }

    func setRoles(_ roles: Set<AppRole>, for userID: String) async throws {
        try await Fire.db.collection(FireCollection.roles).document(userID).setData(["roles": roles.map(\.rawValue).sorted()])
    }
}

// MARK: - Rotinas públicas

/// `routines/{id}`: só o autor edita; os outros só mexem em curtidas e cópias salvas, de 1 em 1
struct FirebaseRoutinesBackend: RoutinesBackend {
    private var col: CollectionReference { Fire.db.collection(FireCollection.routines) }

    func fetch() async throws -> [PublicRoutine] {
        let me = try Fire.me()
        return try await col.order(by: "createdAt", descending: true).limit(to: 300).getDocuments().documents.compactMap { doc in
            let d = Fire.data(doc)
            guard let user = d["user"] as? String, let items = Fire.decode([PublicRoutine.Item].self, d["items"]) else { return nil }
            return PublicRoutine(id: doc.documentID, name: d["name"] as? String ?? "", authorID: user == me ? "me" : user,
                                 authorName: d["authorName"] as? String ?? "", authorFormID: d["authorFormID"] as? String ?? MonsterForm.egg.id,
                                 items: items, likes: d["likes"] as? Int ?? 0, saves: d["saves"] as? Int ?? 0,
                                 createdAt: Fire.date(d["createdAt"]) ?? .now)
        }
    }

    func publish(_ r: PublicRoutine) async throws {
        let me = try Fire.me()
        let ref = col.document(r.id)
        let exists = (try? await ref.getDocument().exists) ?? false
        var data: [String: Any] = ["user": me, "name": r.name, "authorName": r.authorName, "authorFormID": r.authorFormID,
                                   "items": Fire.json(r.items) ?? "[]"]
        // Republicar mantém curtidas, cópias e a data
        if !exists { data.merge(["likes": 0, "saves": 0, "createdAt": FieldValue.serverTimestamp()]) { $1 } }
        try await ref.setData(data, merge: true)
    }

    func unpublish(_ id: String) async throws { try await col.document(id).delete() }

    func like(_ id: String, _ on: Bool) async throws {
        try await col.document(id).updateData(["likes": FieldValue.increment(Int64(on ? 1 : -1))])
        // Quem você curtiu fica no aparelho (é o que a tela lê)
        var liked = Set(UserDefaults.standard.stringArray(forKey: MockRoutinesBackend.likedKey) ?? [])
        if on { liked.insert(id) } else { liked.remove(id) }
        UserDefaults.standard.set(Array(liked), forKey: MockRoutinesBackend.likedKey)
    }

    func saved(_ id: String) async throws {
        try await col.document(id).updateData(["saves": FieldValue.increment(Int64(1))])
    }
}

// MARK: - Cópia da conta

/// A cópia da conta (o mesmo `Backup` do arquivo) comprimida e dividida em pedaços de até 900 KB em
/// `accounts/{uid}/chunks/{n}` (o Firestore aceita 1 MiB por documento). Só o dono lê e grava.
/// Na nuvem as fotos ficam de fora (medidas, check-ins, mural): o plano grátis não tem armazenamento de arquivos e o banco
/// tem 1 GiB. A cópia completa, com fotos, continua num arquivo neste iPhone (`local`): sair e entrar de novo aqui não perde
/// nada; num iPhone novo, voltam os dados sem as fotos.
/// Os dados do Saúde vão junto: o Firestore não é iCloud (guideline 5.1.3), e o consentimento vem da permissão do Saúde.
struct FirebaseAccountDataBackend: AccountDataBackend {
    static let chunkSize = 900_000
    private static let uploadedKey = "accountUploadedHash"
    var local = MockAccountDataBackend()

    private func meta(_ id: String) -> DocumentReference { Fire.db.collection(FireCollection.accounts).document(id) }
    private func chunk(_ id: String, _ n: Int) -> DocumentReference { meta(id).collection("chunks").document(String(n)) }

    /// Hash da última cópia da nuvem que este aparelho conhece (enviou ou já mesclou)
    private func knownHash(_ accountID: String) -> String? {
        guard let v = UserDefaults.standard.string(forKey: Self.uploadedKey), v.hasPrefix(accountID + ":") else { return nil }
        return String(v.dropFirst(accountID.count + 1))
    }

    private func known(_ hash: String, _ accountID: String) { UserDefaults.standard.set("\(accountID):\(hash)", forKey: Self.uploadedKey) }

    /// O arquivo local é a base da mesclagem (a última cópia em comum com a nuvem): só é gravado depois que a nuvem
    /// aceitou. Gravar antes faria um envio recusado virar base e, na mesclagem, itens novos daqui pareceriam apagados lá.
    /// O envio é uma transação: só grava se a nuvem ainda for a versão conhecida (senão, `remoteChanged` e mescla antes).
    func upload(_ snapshot: Backup, accountID: String) async throws {
        var light = snapshot
        light.stripPhotos()
        // A data de exportação muda sempre: fora do hash, para não subir de novo o que não mudou
        light.exportedAt = .distantPast
        let raw = try Backup.encoder.encode(light)
        let hash = AccountSync.digest(String(decoding: raw, as: UTF8.self))
        let expected = knownHash(accountID)
        guard expected != hash else {
            try await local.upload(snapshot, accountID: accountID)
            return
        }
        let packed = try (raw as NSData).compressed(using: .zlib) as Data
        let parts = stride(from: 0, to: packed.count, by: Self.chunkSize).map { packed.subdata(in: $0..<min($0 + Self.chunkSize, packed.count)) }
        let metaRef = meta(accountID)
        let chunkRefs = (0..<max(parts.count, 64)).map { chunk(accountID, $0) }
        let fields: [String: Any] = ["user": accountID, "chunks": parts.count, "bytes": raw.count, "hash": hash, "savedAt": snapshot.exportedAt,
                                     "format": 2, "updatedAt": FieldValue.serverTimestamp()]
        _ = try await Fire.db.runTransaction { txn, errorPointer in
            let current: DocumentSnapshot
            do { current = try txn.getDocument(metaRef) } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
            if let remote = current.data()?["hash"] as? String, remote != expected {
                errorPointer?.pointee = AccountSyncError.remoteChanged as NSError
                return nil
            }
            let old = current.data()?["chunks"] as? Int ?? 0
            for (n, part) in parts.enumerated() { txn.setData(["data": part], forDocument: chunkRefs[n]) }
            for n in parts.count..<min(max(old, parts.count), chunkRefs.count) { txn.deleteDocument(chunkRefs[n]) }
            txn.setData(fields, forDocument: metaRef)
            return nil
        }
        known(hash, accountID)
        try await local.upload(snapshot, accountID: accountID)
    }

    private func remoteCopy(_ accountID: String, count: Int) async throws -> Backup? {
        var packed = Data()
        for n in 0..<count {
            guard let part = try await chunk(accountID, n).getDocument().data()?["data"] as? Data else { return nil }
            packed.append(part)
        }
        let raw = try (packed as NSData).decompressed(using: .zlib) as Data
        return try Backup.decoder.decode(Backup.self, from: raw)
    }

    func remoteChange(_ localCopy: Backup, accountID: String) async throws -> AccountRemoteChange? {
        guard let m = try await meta(accountID).getDocument().data(), let hash = m["hash"] as? String,
              let count = m["chunks"] as? Int, count > 0, hash != knownHash(accountID),
              let remote = try await remoteCopy(accountID, count: count) else { return nil }
        let base = try? await local.download(accountID: accountID)
        let r = try BackupMerge.merge(local: localCopy, remote: remote, base: base)
        return AccountRemoteChange(merged: r.backup, hash: hash, conflicts: r.conflicts)
    }

    func acknowledge(_ change: AccountRemoteChange, accountID: String) { known(change.hash, accountID) }

    /// Escuta `accounts/{uid}`: avisa quando a cópia da nuvem não é a conhecida (subida por outro aparelho)
    func watch(accountID: String, onChange: @escaping @Sendable () -> Void) -> (@Sendable () -> Void)? {
        let registration = meta(accountID).addSnapshotListener { snap, _ in
            // Escrita deste aparelho ainda não confirmada não é novidade
            guard let snap, !snap.metadata.hasPendingWrites, let hash = snap.data()?["hash"] as? String,
                  hash != knownHash(accountID) else { return }
            onChange()
        }
        return { registration.remove() }
    }

    /// A cópia deste iPhone é a mesma ou mais nova que a da nuvem. O arquivo guarda a data em segundos (ISO 8601) e o
    /// servidor com fração: comparando direto, a mesma cópia parecia mais velha e as fotos se perdiam ao sair e entrar
    static func isLocalCurrent(_ local: Date, saved: Date) -> Bool {
        local.timeIntervalSince1970.rounded(.down) >= saved.timeIntervalSince1970.rounded(.down)
    }

    /// A cópia deste iPhone (com fotos) quando é a mais nova; senão a da nuvem
    func download(accountID: String) async throws -> Backup? {
        let mine = try? await local.download(accountID: accountID)
        guard let m = try await meta(accountID).getDocument().data(), let count = m["chunks"] as? Int, count > 0 else { return mine }
        if let mine, let saved = Fire.date(m["savedAt"]), Self.isLocalCurrent(mine.exportedAt, saved: saved) { return mine }
        guard let remote = try await remoteCopy(accountID, count: count) else { return mine }
        // A cópia da nuvem vai ser restaurada aqui: passa a ser a versão conhecida (e a base, no próximo envio)
        if let hash = m["hash"] as? String { known(hash, accountID) }
        return remote
    }

    func delete(accountID: String) async throws {
        let count = (try await meta(accountID).getDocument().data()?["chunks"] as? Int) ?? 0
        try await Fire.delete((0..<count).map { chunk(accountID, $0) } + [meta(accountID)])
        try await local.delete(accountID: accountID)
        UserDefaults.standard.removeObject(forKey: Self.uploadedKey)
    }
}

extension Backup {
    /// Sem fotos: medidas, check-ins e mural (a foto do perfil e as capas das ligas são pequenas e ficam)
    mutating func stripPhotos() {
        body = body?.map { var b = $0; b.photoFront = nil; b.photoSide = nil; return b }
        checkIns = checkIns?.map { var c = $0; c.photo = nil; c.extraPhotos = nil; return c }
        messages = messages?.map { var m = $0; m.photo = nil; return m }
    }
}
