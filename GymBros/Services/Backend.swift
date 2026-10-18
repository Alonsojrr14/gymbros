import AuthenticationServices
import CloudKit
import Foundation
import UIKit

// Onde moram os dados compartilhados (ligas, amigos, perfil público, login).
//
// Hoje: `.mock`. O app é assinado com o Personal Team, que não tem iCloud; tudo de outras pessoas é simulado.
// Com a conta paga do Apple Developer:
//   1. Em Signing & Capabilities, adicione iCloud → CloudKit com o container `Backend.containerID`
//      e **Sign in with Apple** (sem ela, a folha da Apple do modo `.cloudKit` falha com erro 1000).
//   2. Troque `mode` para `.cloudKit`.
//   3. Crie o esquema no CloudKit Dashboard (docs/cloudkit.md: tipos de registro, índices e permissões).
// Nada mais muda: as telas falam só com os contratos (AuthBackend, LeagueBackend, FriendsBackend, ModerationBackend,
// AccountDataBackend).
//
// O que o modo `.cloudKit` ainda não cobre:
//   - Excluir conta apaga só os registros que você criou: vínculos de amizade de outras pessoas para você e ligas
//     criadas por você ficam (sem dono). O usuário do iCloud não pode ser apagado pelo app.
//   - Revogar o token do Sign in with Apple ao excluir a conta exige servidor próprio (REST da Apple com chave .p8).
//   - Moderação: as denúncias (Report) chegam ao banco público, mas analisar em até 24 h e tirar o conteúdo do ar
//     para todos é trabalho de uma pessoa no CloudKit Dashboard (ou de um servidor com chave de servidor); o app
//     não apaga registros de outras pessoas. Bloquear só esconde no seu aparelho (Block guarda a lista).
//   - Dados da conta (AccountDataBackend): a cópia tem dados do Apple Saúde (treinos importados, kcal, peso), que não
//     podem ir para o iCloud (guideline 5.1.3(ii)). Por isso `ServerAccountDataBackend` só lança erro: o caminho é um
//     servidor próprio (HTTPS, token da sessão do AuthBackend, dados cifrados em repouso) ou, se for CloudKit, o banco
//     privado sem nenhum campo vindo do Saúde. Enquanto isso, no `.cloudKit` o login para na tela "Não deu para abrir sua conta".
//   - Termos de uso e filtro de palavras ficam só no aparelho: o aceite (versão e data) não sobe e o servidor não
//     repete o ContentFilter. Expulsar quem viola os termos é ação administrativa (docs/cloudkit.md).

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
            ModerationStore.shared.backend = MockModerationBackend()
            AccountSync.shared.backend = MockAccountDataBackend()
            InboxStore.shared.backend = MockInboxBackend()
            #if DEBUG
            AccessStore.shared.backend = MockRoleBackend(assignments: DevAccount.assignments)
            #else
            AccessStore.shared.backend = MockRoleBackend()
            #endif
        case .cloudKit:
            AuthStore.shared.backend = CloudKitAuthBackend()
            LeagueRemoteStore.shared.backend = CloudKitLeagueBackend()
            FriendsStore.shared.backend = CloudKitFriendsBackend()
            ModerationStore.shared.backend = CloudKitModerationBackend()
            AccessStore.shared.backend = CloudKitRoleBackend()
            AccountSync.shared.backend = ServerAccountDataBackend()
            InboxStore.shared.backend = ServerInboxBackend()
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
               message = "Message", friendLink = "FriendLink", report = "Report", block = "Block"
    /// Liga reservada aos posts do perfil
    static let profileFeed = "profile"
}

// MARK: - Login

/// Com CloudKit, "Continuar com a Apple" abre a folha da Apple e os dados ficam no id do iCloud do aparelho.
/// E-mail e senha não existem nesse modo (não há servidor próprio para guardar senhas).
struct CloudKitAuthBackend: AuthBackend {
    func signInWithApple() async throws -> AuthUser {
        let credential = try await AppleIDAuthorization.request()
        let id = try await Cloud.me()
        let given = [credential.fullName?.givenName, credential.fullName?.familyName].compactMap { $0 }.joined(separator: " ")
        let name = given.isEmpty ? UserDefaults.standard.string(forKey: "trainerName") ?? "" : given
        let token = credential.identityToken.flatMap { String(data: $0, encoding: .utf8) } ?? credential.user
        return AuthUser(id: id, name: name, email: credential.email ?? "", provider: .apple, token: token)
    }

    func signIn(email: String, password: String) async throws -> AuthUser { throw AuthError.appleOnly }
    func signUp(name: String, email: String, password: String) async throws -> AuthUser { throw AuthError.appleOnly }
    func signOut(_ user: AuthUser) async { Cloud.forgetMe() }

    /// Apaga o que você criou no banco público: perfil, lugar nas ligas, check-ins (e posts do perfil), recados,
    /// os seus vínculos de amizade, denúncias e bloqueios
    func deleteAccount(_ user: AuthUser) async throws {
        let me = try await Cloud.me()
        let byUser = NSPredicate(format: "user == %@", me)
        async let members = Cloud.query(CloudType.member, byUser)
        async let checkIns = Cloud.query(CloudType.checkIn, byUser)
        async let messages = Cloud.query(CloudType.message, byUser)
        async let links = Cloud.query(CloudType.friendLink, NSPredicate(format: "from == %@", me))
        async let reports = Cloud.query(CloudType.report, byUser)
        async let blocks = Cloud.query(CloudType.block, byUser)
        let records = try await members + checkIns + messages + links + reports + blocks
        let names = records.map(\.recordID.recordName) + [me]
        for start in stride(from: 0, to: names.count, by: 300) {
            try await Cloud.delete(Array(names[start..<min(start + 300, names.count)]))
        }
        Cloud.forgetMe()
    }
}

/// Folha "Continuar com a Apple" de verdade (precisa da capability Sign in with Apple)
@MainActor
final class AppleIDAuthorization: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?
    private static var current: AppleIDAuthorization?

    static func request() async throws -> ASAuthorizationAppleIDCredential {
        let flow = AppleIDAuthorization()
        current = flow
        defer { current = nil }
        return try await withCheckedThrowingContinuation { c in
            flow.continuation = c
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = flow
            controller.presentationContextProvider = flow
            controller.performRequests()
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        MainActor.assumeIsolated {
            if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                continuation?.resume(returning: credential)
            } else {
                continuation?.resume(throwing: AuthError.cancelled)
            }
            continuation = nil
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        MainActor.assumeIsolated {
            let cancelled = (error as? ASAuthorizationError)?.code == .canceled
            continuation?.resume(throwing: cancelled ? AuthError.cancelled : error)
            continuation = nil
        }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        }
    }
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

// MARK: - Moderação

/// Denúncia e bloqueio são registros seus (campo `user`); a denúncia tem nome fixo por conteúdo, então denunciar de novo
/// só troca o motivo. Report não é legível pelo público (permissões em docs/cloudkit.md).
struct CloudKitModerationBackend: ModerationBackend {
    private func blockName(_ me: String, _ id: String) -> String { "block-\(me)->\(id)" }

    func report(content c: ReportedContent, reason: ReportReason) async throws {
        let me = try await Cloud.me()
        let r = CKRecord(recordType: CloudType.report, recordID: CKRecord.ID(recordName: "report-\(me)-\(c.key)"))
        r["user"] = me
        r["kind"] = c.kind.rawValue
        r["contentID"] = c.id
        r["author"] = c.authorID
        r["authorName"] = c.authorName
        r["reason"] = reason.rawValue
        r["date"] = Date.now
        _ = try await Cloud.save([r])
    }

    func block(userID: String, name: String) async throws {
        let me = try await Cloud.me()
        let r = CKRecord(recordType: CloudType.block, recordID: CKRecord.ID(recordName: blockName(me, userID)))
        r["user"] = me
        r["blocked"] = userID
        r["name"] = name
        r["date"] = Date.now
        _ = try await Cloud.save([r])
    }

    func unblock(userID: String) async throws {
        let me = try await Cloud.me()
        try await Cloud.delete([blockName(me, userID)])
    }

    func blockedUsers() async throws -> [BlockedUser] {
        let me = try await Cloud.me()
        return try await Cloud.query(CloudType.block, NSPredicate(format: "user == %@", me)).compactMap { r in
            guard let id = r["blocked"] as? String else { return nil }
            return BlockedUser(id: id, name: r["name"] as? String ?? "", date: r["date"] as? Date ?? .now)
        }
    }
}

// MARK: - Roles

/// Atribuição oficial em `RoleAssignment` (`role-<id do iCloud>`, campo `roles`, lista de String). Só o CloudKit Dashboard
/// ou um servidor com chave guardada num cofre/gerenciador de segredos cria e altera esses registros; o app só lê.
struct CloudKitRoleBackend: RoleBackend {
    func assignment(for userID: String) async throws -> [String]? {
        let me = try await Cloud.me()
        guard me == userID else { throw CloudError.noAccount }
        do {
            let r = try await Cloud.db.record(for: CKRecord.ID(recordName: "role-\(me)"))
            return r["roles"] as? [String] ?? []
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
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
