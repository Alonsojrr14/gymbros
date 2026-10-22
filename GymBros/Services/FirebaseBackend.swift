import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation

// Modo `.firebase`: login (Firebase Auth), amigos, perfil e ligas no Firestore, no plano grátis (Spark).
// O esquema espelha o do CloudKit (docs/cloudkit.md): uma coleção por tipo, cada documento com o `user` que o criou.
// As regras de acesso estão em firestore.rules e os índices em firestore.indexes.json (docs/firebase.md).
// Fotos dos check-ins não vão para o Firestore: ficam no `PhotoStore` (CloudKit), porque o Spark não tem Cloud Storage.
//
// Mensagens diretas e treino ao vivo ficam em FirebaseSocial.swift. Continuam simulados: X1, trocas, denúncias, roles e a cópia da conta
// (ainda no arquivo local do MockAccountDataBackend; o Firestore aceita no máximo 1 MiB por documento).

enum Fire {
    static var db: Firestore { Firestore.firestore() }

    /// Liga o SDK (uma vez, antes de qualquer uso)
    static func configure() {
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
    }

    /// O seu id (uid do Firebase Auth)
    static func me() throws -> String {
        guard let id = Auth.auth().currentUser?.uid else { throw FireError.signedOut }
        return id
    }

    /// Campos opcionais: nil vira null (apaga o campo ao atualizar com merge)
    static func fields(_ values: [String: Any?]) -> [String: Any] {
        values.mapValues { $0 ?? NSNull() }
    }

    static func delete(_ refs: [DocumentReference]) async throws {
        // Lote do Firestore: até 500 operações
        for start in stride(from: 0, to: refs.count, by: 450) {
            let batch = db.batch()
            refs[start..<min(start + 450, refs.count)].forEach { batch.deleteDocument($0) }
            try await batch.commit()
        }
    }

    /// Documentos por id, em blocos de 30 (limite do filtro `in`)
    static func documents(_ collection: String, ids: [String]) async throws -> [QueryDocumentSnapshot] {
        var out: [QueryDocumentSnapshot] = []
        for start in stride(from: 0, to: ids.count, by: 30) {
            let chunk = Array(ids[start..<min(start + 30, ids.count)])
            out += try await db.collection(collection).whereField(FieldPath.documentID(), in: chunk).getDocuments().documents
        }
        return out
    }
}

enum FireError: LocalizedError {
    case signedOut

    var errorDescription: String? {
        switch self {
        case .signedOut: "Entre na sua conta para usar ligas e amigos."
        }
    }
}

/// Coleções do Firestore (mesmos nomes dos tipos do CloudKit)
enum FireCollection {
    static let profiles = "profiles", leagues = "leagues", members = "members", checkIns = "checkIns",
               messages = "messages", friendLinks = "friendLinks", joinRequests = "joinRequests",
               directMessages = "directMessages", live = "live"
}

private extension Dictionary where Key == String, Value == Any {
    func date(_ key: String) -> Date? { (self[key] as? Timestamp)?.dateValue() }
}

// MARK: - Login

struct FirebaseAuthBackend: AuthBackend {
    private func user(_ u: User, name: String? = nil, provider: AuthUser.Provider) async throws -> AuthUser {
        AuthUser(id: u.uid, name: name ?? u.displayName ?? "", email: u.email ?? "", provider: provider,
                 token: try await u.getIDToken())
    }

    func signInWithApple() async throws -> AuthUser {
        let nonce = UUID().uuidString + UUID().uuidString
        let credential = try await AppleIDAuthorization.request(nonce: nonce)
        guard let token = credential.identityToken.flatMap({ String(data: $0, encoding: .utf8) }) else { throw AuthError.cancelled }
        let apple = OAuthProvider.appleCredential(withIDToken: token, rawNonce: nonce, fullName: credential.fullName)
        let result: AuthDataResult
        do {
            result = try await Auth.auth().signIn(with: apple)
        } catch let error as NSError where AuthErrorCode(rawValue: error.code) == .accountExistsWithDifferentCredential {
            // Uma conta por e-mail: o e-mail da Apple já tem conta com senha. Entrando com a senha, a Apple é ligada a ela
            await PendingLink.keep(error.userInfo[AuthErrorUserInfoUpdatedCredentialKey] as? AuthCredential ?? apple)
            throw FirebaseAuthError.linkApple(error.userInfo[AuthErrorUserInfoEmailKey] as? String ?? credential.email ?? "")
        } catch {
            throw Self.mapped(error)
        }
        // A Apple só manda o nome no primeiro login
        let given = [credential.fullName?.givenName, credential.fullName?.familyName].compactMap { $0 }.joined(separator: " ")
        if !given.isEmpty, result.user.displayName == nil {
            let change = result.user.createProfileChangeRequest()
            change.displayName = given
            try? await change.commitChanges()
        }
        return try await user(result.user, name: given.isEmpty ? nil : given, provider: .apple)
    }

    func signIn(email: String, password: String) async throws -> AuthUser {
        let result = try await Self.run { try await Auth.auth().signIn(withEmail: email, password: password) }
        // Veio de "Continuar com a Apple" com o mesmo e-mail: a partir de agora as duas formas entram na mesma conta
        if let apple = await PendingLink.take() { _ = try? await result.user.link(with: apple) }
        return try await user(result.user, provider: .email)
    }

    func signUp(name: String, email: String, password: String) async throws -> AuthUser {
        let result = try await Self.run { try await Auth.auth().createUser(withEmail: email, password: password) }
        let change = result.user.createProfileChangeRequest()
        change.displayName = name
        try? await change.commitChanges()
        Auth.auth().languageCode = "pt-BR"
        try? await result.user.sendEmailVerification()
        return try await user(result.user, name: name, provider: .email)
    }

    func resetPassword(email: String) async throws {
        Auth.auth().languageCode = "pt-BR"
        try await Self.run { try await Auth.auth().sendPasswordReset(withEmail: email) }
    }

    func sendVerification() async throws {
        Auth.auth().languageCode = "pt-BR"
        try await Self.run { try await Auth.auth().currentUser?.sendEmailVerification() }
    }

    func isVerified() async -> Bool? {
        guard let u = Auth.auth().currentUser else { return nil }
        try? await u.reload()
        return Auth.auth().currentUser?.isEmailVerified
    }

    func signOut(_ user: AuthUser) async { try? Auth.auth().signOut() }

    /// O Firebase só exclui o cadastro com login recente (5 min). Sem conferir antes, os dados saíam e a conta ficava.
    func checkCanDelete() async throws {
        guard let last = Auth.auth().currentUser?.metadata.lastSignInDate, Date.now.timeIntervalSince(last) < 4 * 60 else {
            throw FirebaseAuthError.recentLogin
        }
    }

    /// Apaga o que você criou no Firestore e as suas fotos, e por último o cadastro no Firebase Auth
    func deleteAccount(_ user: AuthUser) async throws {
        let me = try Fire.me()
        let db = Fire.db
        var refs: [DocumentReference] = []
        var photos: [String] = []
        for c in [FireCollection.members, FireCollection.checkIns, FireCollection.messages, FireCollection.joinRequests] {
            let docs = try await db.collection(c).whereField("user", isEqualTo: me).getDocuments().documents
            refs += docs.map(\.reference)
            photos += docs.compactMap { $0.data()["photo"] as? String }
        }
        refs += try await db.collection(FireCollection.friendLinks).whereField("from", isEqualTo: me).getDocuments().documents.map(\.reference)
        for c in [FireCollection.blocks, FireCollection.reports, FireCollection.routines, CommentSync.collection] {
            refs += try await db.collection(c).whereField("user", isEqualTo: me).getDocuments().documents.map(\.reference)
        }
        // Mensagens, X1 e trocas ficam com a outra pessoa (são dela também); o seu nome sai junto com o perfil
        refs += [db.collection(FireCollection.profiles).document(me), db.collection(FireCollection.live).document(me),
                 db.collection(FireCollection.tradeBros).document(me)]
        try await Fire.delete(refs)
        try? await Backend.photos.delete(photos)
        try await Self.run { try await Auth.auth().currentUser?.delete() }
    }

    /// Erros do Firebase Auth com as mensagens do app
    private static func run<T>(_ work: () async throws -> T) async throws -> T {
        do { return try await work() } catch { throw mapped(error) }
    }

    private static func mapped(_ error: Error) -> Error {
        switch AuthErrorCode(rawValue: (error as NSError).code) {
        // Com a proteção contra enumeração de e-mails (padrão do Firebase), não dá para saber se é senha ou Apple
        case .emailAlreadyInUse: FirebaseAuthError.emailInUse
        case .wrongPassword, .invalidCredential, .userNotFound: FirebaseAuthError.wrongPassword
        case .invalidEmail: AuthError.invalidEmail
        case .weakPassword: AuthError.shortPassword
        case .requiresRecentLogin: FirebaseAuthError.recentLogin
        case .networkError: FirebaseAuthError.offline
        default: error
        }
    }
}

/// Login da Apple esperando a senha da conta que já usa o mesmo e-mail
@MainActor
enum PendingLink {
    private static var credential: AuthCredential?

    static func keep(_ c: AuthCredential) { credential = c }

    static func take() -> AuthCredential? {
        defer { credential = nil }
        return credential
    }
}

enum FirebaseAuthError: LocalizedError {
    case recentLogin, emailInUse, wrongPassword, offline
    case linkApple(String)

    var errorDescription: String? {
        switch self {
        case .recentLogin: "Por segurança, saia e entre de novo antes de excluir a conta."
        case .emailInUse: "Esse e-mail já tem conta. Entre com a senha ou com a Apple."
        case .wrongPassword: "E-mail ou senha incorretos. Se você criou a conta com a Apple, use “Continuar com a Apple”."
        case .offline: "Sem conexão. Tente de novo."
        case .linkApple(let email):
            "\(email.isEmpty ? "Esse e-mail" : email) já tem conta com senha. Entre com e-mail e senha uma vez: a Apple fica ligada a ela e depois entra direto."
        }
    }
}

// MARK: - Amigos e perfil

/// Amizade = um vínculo em cada direção, como no CloudKit: cada um só grava o próprio (firestore.rules)
struct FirebaseFriendsBackend: FriendsBackend {
    private static let declinedKey = "declinedFriendRequests"

    private var links: CollectionReference { Fire.db.collection(FireCollection.friendLinks) }
    private var profiles: CollectionReference { Fire.db.collection(FireCollection.profiles) }

    private func friend(_ id: String, _ d: [String: Any]) -> RemoteFriend {
        RemoteFriend(id: id, name: d["name"] as? String ?? "", formID: d["broFormID"] as? String ?? MonsterForm.egg.id,
                     code: d["friendCode"] as? String ?? "")
    }

    private func profiles(_ ids: [String]) async throws -> [RemoteFriend] {
        let found = try await Fire.documents(FireCollection.profiles, ids: ids)
        let byID = Dictionary(found.map { ($0.documentID, $0.data()) }, uniquingKeysWith: { a, _ in a })
        return ids.compactMap { id in byID[id].map { friend(id, $0) } }
    }

    func fetch() async throws -> FriendsState {
        let me = try Fire.me()
        async let out = links.whereField("from", isEqualTo: me).getDocuments()
        async let inc = links.whereField("to", isEqualTo: me).getDocuments()
        let sent = Set(try await out.documents.compactMap { $0.data()["to"] as? String })
        let received = Set(try await inc.documents.compactMap { $0.data()["from"] as? String })
        let declined = Set(UserDefaults.standard.stringArray(forKey: Self.declinedKey) ?? [])
        return FriendsState(friends: try await profiles(Array(sent.intersection(received)).sorted()),
                            incoming: try await profiles(Array(received.subtracting(sent).subtracting(declined)).sorted()))
    }

    func add(code: String) async throws -> RemoteFriend {
        guard let d = try await profiles.whereField("friendCode", isEqualTo: code).limit(to: 1).getDocuments().documents.first else {
            throw FriendError.notFound
        }
        return try await add(id: d.documentID)
    }

    func add(id: String) async throws -> RemoteFriend {
        let me = try Fire.me()
        guard id != me else { throw FriendError.yourself }
        try await links.document("\(me)->\(id)").setData(["from": me, "to": id])
        return try await profiles([id]).first ?? RemoteFriend(id: id, name: "", formID: MonsterForm.egg.id, code: "")
    }

    func accept(_ id: String) async throws { _ = try await add(id: id) }

    /// Não dá para apagar o pedido de outra pessoa: só esconde aqui
    func decline(_ id: String) async throws {
        var d = UserDefaults.standard.stringArray(forKey: Self.declinedKey) ?? []
        d.append(id)
        UserDefaults.standard.set(d, forKey: Self.declinedKey)
    }

    func remove(_ id: String) async throws {
        let me = try Fire.me()
        try await links.document("\(me)->\(id)").delete()
    }

    func profile(_ id: String) async throws -> PublicProfile {
        let d = try await profiles.document(id).getDocument().data() ?? [:]
        var p = PublicProfile(id: id, name: d["name"] as? String ?? "", username: d["username"] as? String ?? "",
                              bio: d["bio"] as? String ?? "")
        if let json = d["public"] as? String, let data = json.data(using: .utf8),
           let extra = try? JSONDecoder().decode(PublicProfile.Extra.self, from: data) {
            p.bro = extra.bro
            p.stats = extra.stats
            p.achievements = extra.achievements
        }
        // A pessoa escondeu os treinos de você: sem posts e sem números
        if let hidden = d["hiddenFrom"] as? [String], hidden.contains(try Fire.me()) {
            p.stats = nil
            return p
        }
        let posts = try await Fire.db.collection(FireCollection.checkIns)
            .whereField("league", isEqualTo: CloudType.profileFeed).whereField("user", isEqualTo: id).getDocuments().documents
        let files = await Backend.photos.files(for: posts.compactMap { $0.data()["photo"] as? String })
        p.posts = posts.compactMap { RemoteCheckIn(fire: $0, photos: files) }.sorted { $0.date > $1.date }
        p.leaguePosts = (try? await leaguePosts(id)) ?? []
        return p
    }

    /// Check-ins da pessoa em ligas públicas dos últimos 7 dias. Confere a liga agora: se virou privada depois, sai.
    private func leaguePosts(_ id: String) async throws -> [RemoteCheckIn] {
        let since = Date.now.addingTimeInterval(-7 * 86400)
        let docs = try await Fire.db.collection(FireCollection.checkIns)
            .whereField("user", isEqualTo: id).whereField("feed", isEqualTo: true).getDocuments().documents
            .filter { ($0.data().date("date") ?? .distantPast) >= since }
        let codes = Set(docs.compactMap { $0.data()["league"] as? String })
        let leagues = try await Fire.documents(FireCollection.leagues, ids: Array(codes))
        var open: [String: String] = [:]
        for l in leagues where !LeagueSettings(rawValue: l.data()["settings"] as? String ?? "").isPrivate {
            open[l.documentID] = "\(l.data()["emoji"] as? String ?? "🏆") \(l.data()["name"] as? String ?? "")"
        }
        return docs.compactMap { d -> RemoteCheckIn? in
            guard let code = d.data()["league"] as? String, let label = open[code], var c = RemoteCheckIn(fire: d, photos: [:]) else { return nil }
            c.postedIn = label
            return c
        }
        .sorted { $0.date > $1.date }
    }

    func publish(_ profile: PublicProfile, friendCode: String) async throws {
        let me = try Fire.me()
        let extra = PublicProfile.Extra(bro: profile.bro, stats: profile.stats, achievements: profile.achievements)
        try await profiles.document(me).setData(Fire.fields([
            "name": profile.name, "username": profile.username, "bio": profile.bio, "friendCode": friendCode,
            "broFormID": profile.bro?.formID,
            "public": (try? JSONEncoder().encode(extra)).flatMap { String(data: $0, encoding: .utf8) },
            "hiddenFrom": FriendPrefs.hiddenFrom(),
        ]), merge: true)
    }

    /// Qualquer pessoa logada lê o perfil: o app de quem foi escondido respeita, mas não é sigilo
    func setHidden(from ids: [String]) async throws {
        let me = try Fire.me()
        try await profiles.document(me).setData(["hiddenFrom": ids], merge: true)
    }
}

// MARK: - Ligas

struct FirebaseLeagueBackend: LeagueBackend {
    private var db: Firestore { Fire.db }
    private func col(_ name: String) -> CollectionReference { db.collection(name) }

    func fetch(_ league: LeagueKey, now: Date) async throws -> RemoteLeague {
        let me = try Fire.me()
        let ref = league.code
        async let members = col(FireCollection.members).whereField("league", isEqualTo: ref).getDocuments()
        // Só a temporada atual (do início dela até agora ou até o fim): índice league + date
        async let checkIns = col(FireCollection.checkIns).whereField("league", isEqualTo: ref)
            .whereField("date", isGreaterThanOrEqualTo: league.start).getDocuments()
        async let messages = col(FireCollection.messages).whereField("league", isEqualTo: ref).getDocuments()
        async let requests = col(FireCollection.joinRequests).whereField("league", isEqualTo: ref).getDocuments()

        // Os seus vêm do aparelho; daqui só os dos outros
        let others = try await members.documents.map { $0.data() }.filter { $0["user"] as? String != me }
        var teams = league.teams.map { RemoteTeam(id: $0.id, name: $0.name) }
        let remoteMembers = others.compactMap { d -> RemoteMember? in
            guard let user = d["user"] as? String else { return nil }
            return RemoteMember(id: user, name: d["name"] as? String ?? "", formID: d["formID"] as? String ?? MonsterForm.egg.id,
                                teamID: d["teamID"] as? String, joinedAt: d.date("joinedAt"))
        }
        for m in remoteMembers { if let t = teams.firstIndex(where: { $0.id == m.teamID }) { teams[t].memberIDs.append(m.id) } }
        let end = league.end ?? .distantFuture
        let theirs = try await checkIns.documents.filter { $0.data()["user"] as? String != me }
        let files = await Backend.photos.files(for: theirs.compactMap { $0.data()["photo"] as? String })
        let remoteCheckIns = theirs.compactMap { RemoteCheckIn(fire: $0, photos: files) }.filter { $0.date <= end }
        let remoteMessages = try await messages.documents.compactMap { doc -> RemoteMessage? in
            let d = doc.data()
            guard let user = d["user"] as? String, user != me, let date = d.date("date") else { return nil }
            return RemoteMessage(id: doc.documentID, memberID: user, date: date, text: d["text"] as? String ?? "")
        }.sorted { $0.date < $1.date }
        // Pedidos de quem ainda não é membro (o dono decide; aceitar vira `settings.approved`)
        let memberIDs = Set(remoteMembers.map(\.id))
        let remoteRequests = ((try? await requests.documents) ?? []).compactMap { doc -> RemoteMember? in
            let d = doc.data()
            guard let user = d["user"] as? String, user != me, !memberIDs.contains(user) else { return nil }
            return RemoteMember(id: user, name: d["name"] as? String ?? "", formID: d["formID"] as? String ?? MonsterForm.egg.id,
                                joinedAt: d.date("date"))
        }
        return RemoteLeague(members: remoteMembers, checkIns: remoteCheckIns, teams: teams, messages: remoteMessages, requests: remoteRequests)
    }

    func send(_ messages: [OutgoingMessage], to league: LeagueKey) async throws -> [UUID] {
        let me = try Fire.me()
        let batch = db.batch()
        for m in messages {
            batch.setData(["league": league.code, "user": me, "date": m.date, "text": m.text],
                          forDocument: col(FireCollection.messages).document(m.id.uuidString))
        }
        try await batch.commit()
        return messages.map(\.id)
    }

    func create(_ league: LeagueDraft) async throws {
        let me = try Fire.me()
        try await col(FireCollection.leagues).document(league.code).setData(Fire.fields([
            "code": league.code, "owner": me, "name": league.name, "emoji": league.emoji, "scoring": league.scoring,
            "weights": league.weights, "tieBreak": league.tieBreak, "photoRule": league.photoRule,
            "activityRule": league.activityRule, "settings": league.settings, "swiss": league.swiss, "teams": league.teams,
            "start": league.start, "end": league.end, "autoRenew": league.autoRenew,
        ]), merge: true)
    }

    func join(code: String) async throws -> LeagueDraft? {
        guard let d = try await col(FireCollection.leagues).document(code).getDocument().data(), let start = d.date("start") else { return nil }
        return LeagueDraft(uuid: UUID(), code: code, name: d["name"] as? String ?? code, emoji: d["emoji"] as? String ?? "🏆",
                           scoring: d["scoring"] as? String ?? LeagueScoring.pontos.rawValue, weights: d["weights"] as? String ?? "",
                           tieBreak: d["tieBreak"] as? String ?? LeagueTieBreak.primeiro.rawValue,
                           photoRule: d["photoRule"] as? String ?? PhotoRule.livre.rawValue,
                           activityRule: d["activityRule"] as? String, settings: d["settings"] as? String, teams: d["teams"] as? String ?? "",
                           start: start, end: d.date("end"), autoRenew: d["autoRenew"] as? Bool ?? false,
                           swiss: d["swiss"] as? String)
    }

    func setMembership(_ membership: Membership, in league: LeagueKey) async throws {
        let me = try Fire.me()
        try await col(FireCollection.members).document("\(league.code)-\(me)").setData(Fire.fields([
            "league": league.code, "user": me, "name": membership.name, "formID": membership.formID,
            "teamID": membership.teamID, "joinedAt": membership.joinedAt,
        ]), merge: true)
    }

    /// A foto vai antes para o PhotoStore; se não subir (sem iCloud), o check-in sobe sem ela
    func publish(_ checkIns: [OutgoingCheckIn], to league: LeagueKey) async throws -> [UUID] {
        let me = try Fire.me()
        let batch = db.batch()
        for c in checkIns {
            var photo: String?
            if let data = c.photo { photo = try? await Backend.photos.upload(data, id: c.id.uuidString) }
            batch.setData(Fire.fields([
                "league": league.code, "user": me, "date": c.date, "kind": c.kindRaw, "minutes": c.minutes, "effort": c.effort,
                "meters": c.meters, "kcal": c.kcal, "title": c.title, "note": c.note, "hasPhoto": c.hasPhoto, "photo": photo,
                "workoutType": c.workoutTypeID.map { Int($0) }, "place": c.place, "proof": c.proof.map(\.rawValue),
                // Liga pública: entra no Feed dos amigos (o perfil tem a busca própria)
                "feed": league.code != CloudType.profileFeed && !league.isPrivate,
            ]), forDocument: col(FireCollection.checkIns).document(c.id.uuidString))
        }
        try await batch.commit()
        return checkIns.map(\.id)
    }

    func retract(_ checkInIDs: [UUID], from league: LeagueKey) async throws {
        try await Fire.delete(checkInIDs.map { col(FireCollection.checkIns).document($0.uuidString) })
        try? await Backend.photos.delete(checkInIDs.map { "photo-" + $0.uuidString })
    }

    func leave(_ league: LeagueKey) async throws {
        let me = try Fire.me()
        let mine = try await col(FireCollection.checkIns).whereField("league", isEqualTo: league.code)
            .whereField("user", isEqualTo: me).getDocuments().documents
        try await Fire.delete(mine.map(\.reference) + [col(FireCollection.members).document("\(league.code)-\(me)")])
        try? await Backend.photos.delete(mine.compactMap { $0.data()["photo"] as? String })
    }

    func requestJoin(code: String, membership: Membership) async throws {
        let me = try Fire.me()
        try await col(FireCollection.joinRequests).document("\(code)-pedido-\(me)").setData([
            "league": code, "user": me, "name": membership.name, "formID": membership.formID, "date": Date.now,
        ])
    }

    /// Aceito = o dono pôs você em `approved` nas regras da liga
    func isApproved(code: String) async throws -> Bool {
        let me = try Fire.me()
        guard let d = try await join(code: code) else { return false }
        return LeagueSettings(rawValue: d.settings ?? "").approved.contains(me)
    }

    /// Só o dono atual grava na liga (firestore.rules): passar o `owner` entrega a edição para o novo dono
    func transfer(_ league: LeagueKey, to memberID: String) async throws {
        try await col(FireCollection.leagues).document(league.code).updateData(["owner": memberID])
    }
}

// MARK: - Conversões

extension RemoteCheckIn {
    init?(fire doc: QueryDocumentSnapshot, photos: [String: URL]) {
        let d = doc.data()
        guard let user = d["user"] as? String, let date = d.date("date") else { return nil }
        self.init(id: doc.documentID, memberID: user, date: date, kindRaw: d["kind"] as? String ?? ActivityKind.outro.rawValue,
                  minutes: d["minutes"] as? Int ?? 0, effort: d["effort"] as? Int ?? 5, meters: d["meters"] as? Double,
                  kcal: d["kcal"] as? Double, title: d["title"] as? String ?? "", note: d["note"] as? String ?? "",
                  hasPhoto: d["hasPhoto"] as? Bool ?? false, photoURL: (d["photo"] as? String).flatMap { photos[$0] },
                  workoutTypeID: (d["workoutType"] as? Int).map { UInt($0) }, place: d["place"] as? String,
                  proof: (d["proof"] as? String).map(CheckInProof.init(rawValue:)))
    }
}

extension AppleIDAuthorization {
    /// O Firebase confere o login da Apple pelo hash do nonce
    static func request(nonce: String) async throws -> ASAuthorizationAppleIDCredential {
        try await request(hashedNonce: SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined())
    }
}

/// Quem está logado no Firebase Auth (a sessão dele fica no Keychain e sobrevive a reinstalar o app)
enum FirebaseSession {
    static var uid: String? { Auth.auth().currentUser?.uid }
}
