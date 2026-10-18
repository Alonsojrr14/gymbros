import CloudKit
import Foundation

// Onde moram os dados compartilhados (ligas, amigos, perfil público, login).
//
// Hoje: `.mock`. O app é assinado com o Personal Team, que não tem iCloud; tudo de outras pessoas é simulado.
// Com a conta paga do Apple Developer:
//   1. Em Signing & Capabilities, adicione iCloud → CloudKit com o container `Backend.containerID`
//      (e Sign in with Apple, se quiser o login da Apple de verdade).
//   2. Troque `mode` para `.cloudKit`.
//   3. Crie o esquema no CloudKit Dashboard (docs/cloudkit.md: tipos de registro, índices e permissões).
// Nada mais muda: as telas falam só com os contratos (AuthBackend, LeagueBackend, FriendsBackend).

enum BackendMode {
    /// Dados simulados no aparelho (pessoas, ligas e perfis de exemplo)
    case mock
    /// CloudKit, banco público do container do app
    case cloudKit
}

enum Backend {
    /// Troque aqui quando o app tiver iCloud
    static let mode: BackendMode = .mock
    static let containerID = "iCloud.com.alonsoalmeida.gymbros"

    /// Liga os contratos ao backend escolhido. Chamado uma vez, ao abrir o app.
    @MainActor
    static func install() {
        switch mode {
        case .mock:
            AuthStore.shared.backend = MockAuthBackend()
            LeagueRemoteStore.shared.backend = MockLeagueBackend()
            FriendsStore.shared.backend = MockFriendsBackend()
        case .cloudKit:
            AuthStore.shared.backend = CloudKitAuthBackend()
            LeagueRemoteStore.shared.backend = CloudKitLeagueBackend()
            FriendsStore.shared.backend = CloudKitFriendsBackend()
        }
    }
}

// MARK: - Base

/// Acesso ao banco público e ao seu id de usuário do iCloud (guardado depois da primeira vez)
enum Cloud {
    static var container: CKContainer { CKContainer(identifier: Backend.containerID) }
    static var db: CKDatabase { container.publicCloudDatabase }

    private static let userKey = "cloudUserID"

    /// Seu id no iCloud (recordName do usuário). Falha sem conta do iCloud no aparelho.
    static func me() async throws -> String {
        if let id = UserDefaults.standard.string(forKey: userKey) { return id }
        guard try await container.accountStatus() == .available else { throw CloudError.noAccount }
        let id = try await container.userRecordID().recordName
        UserDefaults.standard.set(id, forKey: userKey)
        return id
    }

    static func forgetMe() { UserDefaults.standard.removeObject(forKey: userKey) }

    /// Consulta com todos os resultados (segue o cursor)
    static func query(_ type: String, _ predicate: NSPredicate, sort: [NSSortDescriptor] = []) async throws -> [CKRecord] {
        let q = CKQuery(recordType: type, predicate: predicate)
        q.sortDescriptors = sort
        var (results, cursor) = try await db.records(matching: q)
        var out = results.compactMap { try? $0.1.get() }
        while let c = cursor {
            (results, cursor) = try await db.records(continuingMatchFrom: c)
            out += results.compactMap { try? $0.1.get() }
        }
        return out
    }

    /// Salva sobrescrevendo (o app é a fonte da verdade do que é seu)
    static func save(_ records: [CKRecord]) async throws -> [String] {
        guard !records.isEmpty else { return [] }
        let (saved, _) = try await db.modifyRecords(saving: records, deleting: [], savePolicy: .allKeys)
        return saved.compactMap { id, r in (try? r.get()) != nil ? id.recordName : nil }
    }

    static func delete(_ names: [String]) async throws {
        guard !names.isEmpty else { return }
        _ = try await db.modifyRecords(saving: [], deleting: names.map { CKRecord.ID(recordName: $0) })
    }

    /// Registro novo ou o existente com o mesmo nome (para atualizar campos)
    static func record(_ type: String, _ name: String) async -> CKRecord {
        let id = CKRecord.ID(recordName: name)
        return (try? await db.record(for: id)) ?? CKRecord(recordType: type, recordID: id)
    }
}

enum CloudError: LocalizedError {
    case noAccount

    var errorDescription: String? {
        switch self {
        case .noAccount: "Entre no iCloud nos Ajustes do iPhone para usar ligas e amigos."
        }
    }
}

/// Tipos de registro do banco público (esquema em docs/cloudkit.md)
enum CloudType {
    static let profile = "Profile", league = "League", member = "Member", checkIn = "CheckIn",
               message = "Message", friendLink = "FriendLink"
    /// Liga reservada aos posts do perfil
    static let profileFeed = "profile"
}

// MARK: - Login

/// Com CloudKit, a conta é a do iCloud do aparelho: "Continuar com a Apple" usa o id do iCloud.
/// E-mail e senha não existem nesse modo (não há servidor próprio para guardar senhas).
struct CloudKitAuthBackend: AuthBackend {
    func signInWithApple() async throws -> AuthUser {
        let id = try await Cloud.me()
        let name = UserDefaults.standard.string(forKey: "trainerName") ?? ""
        return AuthUser(id: id, name: name, email: "", provider: .apple, token: id)
    }

    func signIn(email: String, password: String) async throws -> AuthUser { throw AuthError.appleOnly }
    func signUp(name: String, email: String, password: String) async throws -> AuthUser { throw AuthError.appleOnly }
    func signOut(_ user: AuthUser) async { Cloud.forgetMe() }
}

// MARK: - Ligas

struct CloudKitLeagueBackend: LeagueBackend {
    /// A liga no servidor é identificada pelo código (o mesmo em todas as temporadas)
    private func leagueRef(_ key: LeagueKey) -> String { key.code }

    func fetch(_ league: LeagueKey, now: Date) async throws -> RemoteLeague {
        let me = try await Cloud.me()
        let ref = leagueRef(league)
        let byLeague = NSPredicate(format: "league == %@", ref)
        async let members = Cloud.query(CloudType.member, byLeague)
        // Só a temporada atual (do início dela até agora ou até o fim)
        async let checkIns = Cloud.query(CloudType.checkIn, NSPredicate(format: "league == %@ AND date >= %@", ref, league.start as NSDate))
        async let messages = Cloud.query(CloudType.message, byLeague, sort: [NSSortDescriptor(key: "date", ascending: true)])

        // Os seus vêm do aparelho; daqui só os dos outros
        let others = try await members.filter { $0["user"] as? String != me }
        var teams = league.teams.map { RemoteTeam(id: $0.id, name: $0.name) }
        let remoteMembers = others.map { r in
            RemoteMember(id: r["user"] as? String ?? r.recordID.recordName, name: r["name"] as? String ?? "",
                         formID: r["formID"] as? String ?? MonsterForm.egg.id, teamID: r["teamID"] as? String)
        }
        for m in remoteMembers { if let t = teams.firstIndex(where: { $0.id == m.teamID }) { teams[t].memberIDs.append(m.id) } }
        let end = league.end ?? .distantFuture
        let remoteCheckIns = try await checkIns.filter { $0["user"] as? String != me }.compactMap { r -> RemoteCheckIn? in
            guard let user = r["user"] as? String, let date = r["date"] as? Date, date <= end else { return nil }
            return RemoteCheckIn(cloud: r, user: user, date: date)
        }
        let remoteMessages = try await messages.filter { $0["user"] as? String != me }.compactMap { r -> RemoteMessage? in
            guard let user = r["user"] as? String, let date = r["date"] as? Date else { return nil }
            return RemoteMessage(id: r.recordID.recordName, memberID: user, date: date, text: r["text"] as? String ?? "")
        }
        return RemoteLeague(members: remoteMembers, checkIns: remoteCheckIns, teams: teams, messages: remoteMessages)
    }

    func send(_ messages: [OutgoingMessage], to league: LeagueKey) async throws -> [UUID] {
        let me = try await Cloud.me()
        let records = messages.map { m -> CKRecord in
            let r = CKRecord(recordType: CloudType.message, recordID: CKRecord.ID(recordName: m.id.uuidString))
            r["league"] = leagueRef(league)
            r["user"] = me
            r["date"] = m.date
            r["text"] = m.text
            return r
        }
        return try await Cloud.save(records).compactMap(UUID.init(uuidString:))
    }

    func create(_ league: LeagueDraft) async throws {
        let me = try await Cloud.me()
        let r = await Cloud.record(CloudType.league, league.code)
        r["code"] = league.code
        r["owner"] = me
        r["name"] = league.name
        r["emoji"] = league.emoji
        r["scoring"] = league.scoring
        r["weights"] = league.weights
        r["tieBreak"] = league.tieBreak
        r["photoRule"] = league.photoRule
        r["teams"] = league.teams
        r["start"] = league.start
        r["end"] = league.end
        r["autoRenew"] = league.autoRenew ? 1 : 0
        _ = try await Cloud.save([r])
    }

    func join(code: String) async throws -> LeagueDraft? {
        guard let r = try? await Cloud.db.record(for: CKRecord.ID(recordName: code)), let start = r["start"] as? Date else { return nil }
        return LeagueDraft(uuid: UUID(), code: code, name: r["name"] as? String ?? code, emoji: r["emoji"] as? String ?? "🏆",
                           scoring: r["scoring"] as? String ?? LeagueScoring.pontos.rawValue, weights: r["weights"] as? String ?? "",
                           tieBreak: r["tieBreak"] as? String ?? LeagueTieBreak.primeiro.rawValue,
                           photoRule: r["photoRule"] as? String ?? PhotoRule.livre.rawValue, teams: r["teams"] as? String ?? "",
                           start: start, end: r["end"] as? Date, autoRenew: (r["autoRenew"] as? Int ?? 0) == 1)
    }

    func setMembership(_ membership: Membership, in league: LeagueKey) async throws {
        let me = try await Cloud.me()
        let r = await Cloud.record(CloudType.member, "\(leagueRef(league))-\(me)")
        r["league"] = leagueRef(league)
        r["user"] = me
        r["name"] = membership.name
        r["formID"] = membership.formID
        r["teamID"] = membership.teamID
        _ = try await Cloud.save([r])
    }

    func publish(_ checkIns: [OutgoingCheckIn], to league: LeagueKey) async throws -> [UUID] {
        let me = try await Cloud.me()
        var temp: [URL] = []
        defer { temp.forEach { try? FileManager.default.removeItem(at: $0) } }
        let records = checkIns.map { c -> CKRecord in
            let r = CKRecord(cloud: c, league: leagueRef(league), user: me)
            if let photo = c.photo {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(c.id).jpg")
                if (try? photo.write(to: url)) != nil {
                    r["photo"] = CKAsset(fileURL: url)
                    temp.append(url)
                }
            }
            return r
        }
        return try await Cloud.save(records).compactMap(UUID.init(uuidString:))
    }

    func retract(_ checkInIDs: [UUID], from league: LeagueKey) async throws {
        try await Cloud.delete(checkInIDs.map(\.uuidString))
    }

    func leave(_ league: LeagueKey) async throws {
        let me = try await Cloud.me()
        let mine = try await Cloud.query(CloudType.checkIn, NSPredicate(format: "league == %@ AND user == %@", leagueRef(league), me))
        try await Cloud.delete(mine.map(\.recordID.recordName) + ["\(leagueRef(league))-\(me)"])
    }
}

// MARK: - Amigos e perfil

/// Amizade = um vínculo em cada direção. Cada um só escreve o próprio (permissão padrão do banco público):
/// pedir é criar "eu → você"; aceitar é criar "você ← eu" de volta; desfazer é apagar o seu.
struct CloudKitFriendsBackend: FriendsBackend {
    private static let declinedKey = "declinedFriendRequests"

    private func link(_ from: String, _ to: String) -> CKRecord {
        let r = CKRecord(recordType: CloudType.friendLink, recordID: CKRecord.ID(recordName: "\(from)->\(to)"))
        r["from"] = from
        r["to"] = to
        return r
    }

    private func friend(_ r: CKRecord) -> RemoteFriend {
        RemoteFriend(id: r.recordID.recordName, name: r["name"] as? String ?? "", formID: r["broFormID"] as? String ?? MonsterForm.egg.id,
                     code: r["friendCode"] as? String ?? "")
    }

    private func profiles(_ ids: [String]) async throws -> [RemoteFriend] {
        guard !ids.isEmpty else { return [] }
        let found = try await Cloud.db.records(for: ids.map { CKRecord.ID(recordName: $0) })
        return ids.compactMap { id in (try? found[CKRecord.ID(recordName: id)]?.get()).map(friend) }
    }

    func fetch() async throws -> FriendsState {
        let me = try await Cloud.me()
        async let out = Cloud.query(CloudType.friendLink, NSPredicate(format: "from == %@", me))
        async let inc = Cloud.query(CloudType.friendLink, NSPredicate(format: "to == %@", me))
        let sent = Set(try await out.compactMap { $0["to"] as? String })
        let received = Set(try await inc.compactMap { $0["from"] as? String })
        let declined = Set(UserDefaults.standard.stringArray(forKey: Self.declinedKey) ?? [])
        return FriendsState(friends: try await profiles(Array(sent.intersection(received)).sorted()),
                            incoming: try await profiles(Array(received.subtracting(sent).subtracting(declined)).sorted()))
    }

    func add(code: String) async throws -> RemoteFriend {
        guard let r = try await Cloud.query(CloudType.profile, NSPredicate(format: "friendCode == %@", code)).first else {
            throw FriendError.notFound
        }
        return try await add(id: r.recordID.recordName)
    }

    func add(id: String) async throws -> RemoteFriend {
        let me = try await Cloud.me()
        guard id != me else { throw FriendError.yourself }
        _ = try await Cloud.save([link(me, id)])
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
        let me = try await Cloud.me()
        try await Cloud.delete(["\(me)->\(id)"])
    }

    func profile(_ id: String) async throws -> PublicProfile {
        let r = try await Cloud.db.record(for: CKRecord.ID(recordName: id))
        var p = PublicProfile(id: id, name: r["name"] as? String ?? "", username: r["username"] as? String ?? "",
                              bio: r["bio"] as? String ?? "")
        if let json = r["public"] as? String, let data = json.data(using: .utf8),
           let extra = try? JSONDecoder().decode(PublicProfile.Extra.self, from: data) {
            p.bro = extra.bro
            p.stats = extra.stats
            p.achievements = extra.achievements
        }
        let posts = try await Cloud.query(CloudType.checkIn, NSPredicate(format: "league == %@ AND user == %@", CloudType.profileFeed, id),
                                          sort: [NSSortDescriptor(key: "date", ascending: false)])
        p.posts = posts.compactMap { r in
            guard let date = r["date"] as? Date else { return nil }
            return RemoteCheckIn(cloud: r, user: id, date: date)
        }
        return p
    }

    func publish(_ profile: PublicProfile, friendCode: String) async throws {
        let me = try await Cloud.me()
        let r = await Cloud.record(CloudType.profile, me)
        r["name"] = profile.name
        r["username"] = profile.username
        r["bio"] = profile.bio
        r["friendCode"] = friendCode
        r["broFormID"] = profile.bro?.formID
        let extra = PublicProfile.Extra(bro: profile.bro, stats: profile.stats, achievements: profile.achievements)
        r["public"] = (try? JSONEncoder().encode(extra)).flatMap { String(data: $0, encoding: .utf8) }
        _ = try await Cloud.save([r])
    }
}

// MARK: - Conversões

extension PublicProfile {
    /// O que o perfil mostra além de nome e bio (vai num campo JSON; nil = escondido pela pessoa)
    struct Extra: Codable {
        var bro: Bro?
        var stats: Stats?
        var achievements: [Badge]?
    }
}

extension RemoteCheckIn {
    init(cloud r: CKRecord, user: String, date: Date) {
        self.init(id: r.recordID.recordName, memberID: user, date: date, kindRaw: r["kind"] as? String ?? ActivityKind.outro.rawValue,
                  minutes: r["minutes"] as? Int ?? 0, effort: r["effort"] as? Int ?? 5, meters: r["meters"] as? Double, kcal: r["kcal"] as? Double,
                  title: r["title"] as? String ?? "", note: r["note"] as? String ?? "", hasPhoto: (r["hasPhoto"] as? Int ?? 0) == 1,
                  photoURL: (r["photo"] as? CKAsset)?.fileURL)
    }
}

extension CKRecord {
    convenience init(cloud c: OutgoingCheckIn, league: String, user: String) {
        self.init(recordType: CloudType.checkIn, recordID: CKRecord.ID(recordName: c.id.uuidString))
        self["league"] = league
        self["user"] = user
        self["date"] = c.date
        self["kind"] = c.kindRaw
        self["minutes"] = c.minutes
        self["effort"] = c.effort
        self["meters"] = c.meters
        self["kcal"] = c.kcal
        self["title"] = c.title
        self["note"] = c.note
        self["hasPhoto"] = c.hasPhoto ? 1 : 0
    }
}
