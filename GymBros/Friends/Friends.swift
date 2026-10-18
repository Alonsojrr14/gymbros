import CryptoKit
import Foundation
import Observation
import SwiftData
import SwiftUI

// Amigos: mesmo esquema das ligas (LeagueRemote.swift). FriendsBackend é o contrato com o servidor,
// os tipos Remote* têm o formato da API, e por enquanto quem responde é o MockFriendsBackend:
// um "servidor de mentira" que guarda o estado no aparelho, com pessoas simuladas.

struct RemoteFriend: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    /// `MonsterForm.id` do bro principal da pessoa
    let formID: String
    /// Código de amigo, para adicionar
    let code: String

    var form: MonsterForm { MonsterForm.byID(formID) ?? .egg }
}

struct FriendsState: Codable, Sendable {
    var friends: [RemoteFriend] = []
    /// Pedidos que outras pessoas te mandaram
    var incoming: [RemoteFriend] = []
}

enum FriendError: LocalizedError {
    case notFound, yourself, already

    var errorDescription: String? {
        switch self {
        case .notFound: "Ninguém com esse código."
        case .yourself: "Esse é o seu código 🙂"
        case .already: "Vocês já são amigos."
        }
    }
}

protocol FriendsBackend: Sendable {
    func fetch() async throws -> FriendsState
    /// Adiciona pelo código; devolve quem foi adicionado
    func add(code: String) async throws -> RemoteFriend
    /// Adiciona alguém que você conhece de uma liga (pelo id de participante)
    func add(id: String) async throws -> RemoteFriend
    func accept(_ id: String) async throws
    func decline(_ id: String) async throws
    func remove(_ id: String) async throws
    /// Perfil público da pessoa (só o que ela deixou aparecer)
    func profile(_ id: String) async throws -> PublicProfile
    /// Publica o seu perfil público (o que você deixou aparecer) com o seu código de amigo
    func publish(_ profile: PublicProfile, friendCode: String) async throws
}

// MARK: - Cache

@MainActor @Observable
final class FriendsStore {
    static let shared = FriendsStore()

    /// Trocar o backend descarta o que veio do anterior (o servidor de verdade não começa com as pessoas simuladas)
    var backend: any FriendsBackend = MockFriendsBackend() {
        didSet {
            state = Self.initialState(backend)
            profiles = [:]
        }
    }
    var access: AccessStore = .shared
    private(set) var state = FriendsStore.initialState(MockFriendsBackend())
    private(set) var profiles: [String: PublicProfile] = [:]

    /// Seu código de amigo, gerado uma vez
    var myCode: String {
        if let c = UserDefaults.standard.string(forKey: "friendCode") { return c }
        let c = League.newCode()
        UserDefaults.standard.set(c, forKey: "friendCode")
        return c
    }

    /// Sem quem você bloqueou
    var friends: [RemoteFriend] { ModerationStore.shared.visible(state.friends) }
    var incoming: [RemoteFriend] { ModerationStore.shared.visible(state.incoming) }
    var friendIDs: Set<String> { Set(friends.map(\.id)) }

    /// Publica o seu perfil se mudou desde o último envio
    func publish(_ profile: PublicProfile) async {
        // Hash estável entre aberturas do app (o hashValue do Swift muda a cada execução)
        let fingerprint = (try? JSONEncoder().encode(profile)).map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() } ?? ""
        // Por backend: trocar de mock para CloudKit publica de novo
        let key = "publishedProfile-\(Backend.mode)"
        guard access.can(.profileUpdate), UserDefaults.standard.string(forKey: key) != fingerprint else { return }
        do {
            try await backend.publish(profile, friendCode: myCode)
            UserDefaults.standard.set(fingerprint, forKey: key)
        } catch {}
    }

    /// Antes da primeira resposta: o mock responde do aparelho; outro backend começa vazio até o `refresh`
    private static func initialState(_ backend: any FriendsBackend) -> FriendsState {
        backend is MockFriendsBackend ? MockFriendsBackend.load() : FriendsState()
    }

    func refresh() async {
        if let s = try? await backend.fetch() { state = s }
    }

    /// Esquece o que veio do servidor (conta excluída)
    func reset() {
        state = Self.initialState(backend)
        profiles = [:]
    }

    func add(code: String) async throws -> RemoteFriend {
        try access.authorize(.friendsManage)
        let c = code.trimmingCharacters(in: .whitespaces).uppercased()
        if c == myCode { throw FriendError.yourself }
        if state.friends.contains(where: { $0.code == c }) { throw FriendError.already }
        let f = try await backend.add(code: c)
        await refresh()
        return f
    }

    func add(id: String) async throws -> RemoteFriend {
        try access.authorize(.friendsManage)
        let f = try await backend.add(id: id)
        await refresh()
        return f
    }

    /// Talvez você conheça: quem está nas suas ligas em andamento e ainda não é amigo nem te mandou pedido.
    /// Quem divide mais ligas com você vem primeiro.
    func suggestions(from leagues: [League]) -> [(member: RemoteMember, leagues: [League])] {
        let known = Set(state.friends.map(\.id)).union(state.incoming.map(\.id))
        var found: [String: (member: RemoteMember, leagues: [League])] = [:]
        for l in leagues where !l.isPastSeason && !l.isOver {
            for m in LeagueRemoteStore.shared.remote(l).members where !known.contains(m.id) && !ModerationStore.shared.isBlocked(m.id) {
                found[m.id, default: (m, [])].leagues.append(l)
            }
        }
        return found.values.sorted { ($0.leagues.count, $1.member.name) > ($1.leagues.count, $0.member.name) }
    }

    func loadProfile(_ id: String) async {
        if let p = try? await backend.profile(id) { profiles[id] = p }
    }

    func accept(_ id: String) async {
        guard access.can(.friendsManage) else { return }
        try? await backend.accept(id)
        await refresh()
    }
    func decline(_ id: String) async { try? await backend.decline(id); await refresh() }
    func remove(_ id: String) async { try? await backend.remove(id); await refresh() }

    /// Bloqueio: desfaz a amizade e recusa o pedido pendente
    func unfriend(_ id: String) async {
        if state.friends.contains(where: { $0.id == id }) { try? await backend.remove(id) }
        if state.incoming.contains(where: { $0.id == id }) { try? await backend.decline(id) }
        await refresh()
    }
}

// MARK: - Servidor simulado

struct MockFriendsBackend: FriendsBackend {
    private static let key = "mockFriends"

    /// Todo mundo que existe no "servidor": os amigos do mapa, os participantes da liga de exemplo e a Mari (pedido)
    static let directory: [RemoteFriend] = {
        var all = FriendsLive.simulated.map { RemoteFriend(id: $0.id, name: $0.name, formID: $0.form.id, code: code($0.id)) }
        for m in FakeMember.all where !all.contains(where: { $0.id == m.id }) {
            all.append(RemoteFriend(id: m.id, name: m.name, formID: m.form.id, code: code(m.id)))
        }
        all.append(RemoteFriend(id: "mari", name: "Mari", formID: MonsterForm(stage: .champion, attribute: .agilidade, species: "lobo").id, code: "MARI42"))
        return all
    }()

    private static func code(_ id: String) -> String { (id.uppercased() + "2026").prefix(6).description }

    /// Começo: os 5 amigos do mapa e um pedido da Mari
    private static var initial: FriendsState {
        let friends = Set(FriendsLive.simulated.map(\.id))
        return FriendsState(friends: directory.filter { friends.contains($0.id) }, incoming: directory.filter { $0.id == "mari" })
    }

    static func load() -> FriendsState {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(FriendsState.self, from: $0) } ?? initial
    }

    /// Volta ao começo (amigos e pedido de exemplo)
    static func reset() { UserDefaults.standard.removeObject(forKey: key) }

    private static func save(_ s: FriendsState) {
        UserDefaults.standard.set(try? JSONEncoder().encode(s), forKey: key)
    }

    func fetch() async throws -> FriendsState { Self.load() }

    /// Sem servidor, o pedido é aceito na hora
    func add(code: String) async throws -> RemoteFriend {
        guard let f = Self.directory.first(where: { $0.code == code }) else { throw FriendError.notFound }
        return try await add(id: f.id)
    }

    func add(id: String) async throws -> RemoteFriend {
        guard let f = Self.directory.first(where: { $0.id == id }) else { throw FriendError.notFound }
        var s = Self.load()
        s.incoming.removeAll { $0.id == f.id }
        if !s.friends.contains(where: { $0.id == f.id }) { s.friends.append(f) }
        Self.save(s)
        return f
    }

    func accept(_ id: String) async throws { _ = try await add(id: id) }

    func decline(_ id: String) async throws {
        var s = Self.load()
        s.incoming.removeAll { $0.id == id }
        Self.save(s)
    }

    /// Como cada pessoa simulada se apresenta; algumas escondem partes do perfil, como qualquer um pode fazer
    private static let bios: [String: (username: String, bio: String, hideStats: Bool, hideAchievements: Bool)] = [
        "ana": ("ana.corre", "Correndo atrás do sub-50 nos 10 km 🏃‍♀️", false, false),
        "bruno": ("brunao", "Supino é terapia", false, false),
        "carla": ("carla.zen", "Yoga, dança e café ☕️", false, true),
        "diego": ("diegol", "Pelada toda quinta ⚽", false, false),
        "fe": ("fe.nada", "Água é meu lugar 🏊‍♀️", true, false),
        "gui": ("gui.monstro", "Começando agora, sem pressa", false, false),
        "lia": ("lia.fit", "", false, false),
        "rafa": ("rafa.pedal", "Serra todo domingo 🚴", false, false),
        "mari": ("mari.move", "Crossfit e vôlei de praia", false, false),
    ]

    private static let badges: [PublicProfile.Badge] = [
        .init(title: "Primeiro passo", symbol: "figure.walk"), .init(title: "Chocou!", symbol: "sparkles"),
        .init(title: "Pegando o ritmo", symbol: "10.circle"), .init(title: "Embalado", symbol: "flame"),
        .init(title: "Semana cheia", symbol: "flame.fill"), .init(title: "Madrugador", symbol: "sunrise"),
        .init(title: "Eclético", symbol: "square.grid.2x2"), .init(title: "Recordista", symbol: "medal"),
        .init(title: "Maratonista", symbol: "timer"), .init(title: "Campeão", symbol: "trophy"),
    ]

    /// Sempre o mesmo perfil para a mesma pessoa; os posts acompanham o calendário
    func profile(_ id: String) async throws -> PublicProfile {
        guard let f = Self.directory.first(where: { $0.id == id }) else { throw FriendError.notFound }
        let info = Self.bios[id] ?? (id, "", false, false)
        var rng = SeededRandom(seed: "perfil-\(id)")
        let form = f.form
        let level = Game.level(for: form.stage.threshold + Int(rng.next() * 400))
        let checkIns = 20 + Int(rng.next() * 160)
        var p = PublicProfile(id: id, name: f.name, username: info.username, bio: info.bio)
        p.bro = .init(name: form.name, formID: form.id, level: level, progress: rng.next())
        if !info.hideStats {
            p.stats = .init(checkIns: checkIns, activeDays: Int(Double(checkIns) * (0.7 + rng.next() * 0.25)), leagues: 1 + Int(rng.next() * 4))
        }
        if !info.hideAchievements {
            p.achievements = Self.badges.filter { _ in rng.next() < 0.55 }
        }
        p.posts = Self.posts(id)
        return p
    }

    /// Posts dos últimos 90 dias, no estilo de treino de cada um
    private static func posts(_ id: String, now: Date = .now) -> [RemoteCheckIn] {
        let member = FakeMember.all.first { $0.id == id }
        let kinds = member?.kinds ?? [.crossfit, .volei]
        let cal = Calendar.current
        var out: [RemoteCheckIn] = []
        for back in 0..<90 {
            guard let day = cal.date(byAdding: .day, value: -back, to: cal.startOfDay(for: now)) else { continue }
            var rng = SeededRandom(seed: "post-\(id)-\(Int(day.timeIntervalSince1970))")
            guard rng.next() < 0.3 else { continue }
            guard let date = cal.date(byAdding: .minute, value: 6 * 60 + Int(rng.next() * 15 * 60), to: day), date <= now else { continue }
            let kind = kinds[Int(rng.next() * Double(kinds.count)) % kinds.count]
            let titles = member?.titles[kind] ?? [kind.name]
            let minutes = (member?.minutes ?? 40...70).lowerBound + Int(rng.next() * 40)
            out.append(RemoteCheckIn(id: "perfil-\(id)-\(back)", memberID: id, date: date, kindRaw: kind.rawValue, minutes: minutes / 5 * 5,
                                     effort: 5 + Int(rng.next() * 4), title: titles[Int(rng.next() * Double(titles.count)) % titles.count],
                                     hasPhoto: rng.next() < 0.8))
        }
        return out
    }

    func publish(_ profile: PublicProfile, friendCode: String) async throws {}

    func remove(_ id: String) async throws {
        var s = Self.load()
        s.friends.removeAll { $0.id == id }
        Self.save(s)
    }
}

// MARK: - Tela

struct FriendsView: View {
    @State private var store = FriendsStore.shared
    @State private var code = ""
    @State private var message: String?
    @State private var opened: RemoteFriend?
    @Query(sort: \League.joinedAt) private var leagues: [League]

    var body: some View {
        GMModal("Amigos") {
            SocialGate(requires: .friendsRead) {
                myCode
                GMSection("Adicionar amigo", footer: message ?? "Peça o código para a pessoa (fica na tela de amigos dela).") {
                    HStack(spacing: 8) {
                        GMTextField(placeholder: "Código do amigo", text: $code, capitalization: .characters)
                            .font(.title3.monospaced())
                            .autocorrectionDisabled()
                        GMButton("Adicionar", full: false, small: true, enabled: code.trimmingCharacters(in: .whitespaces).count >= 6) { add(code) }
                    }
                }
                if !store.incoming.isEmpty {
                    GMSection("Pedidos de amizade") {
                        ForEach(store.incoming) { f in
                            HStack(spacing: 10) {
                                person(f, subtitle: "Quer ser seu amigo")
                                GMIconButton(icon: "xmark", size: 36, label: "Recusar") { Task { await store.decline(f.id) } }
                                GMIconButton(icon: "checkmark", size: 36, label: "Aceitar") { Task { await store.accept(f.id) } }
                            }
                            if f.id != store.incoming.last?.id { GMDivider() }
                        }
                    }
                }
                GMSection("Seus amigos · \(store.friends.count)") {
                    if store.friends.isEmpty {
                        Text("Nenhum amigo ainda. Mande seu código pra galera.").font(.subheadline).foregroundStyle(Theme.dim)
                    }
                    ForEach(store.friends) { f in
                        Button { opened = f } label: {
                            HStack {
                                person(f, subtitle: status(f), online: isLive(f))
                                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.dim)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(GMPress())
                        if f.id != store.friends.last?.id { GMDivider() }
                    }
                }
                suggestionsSection
            }
        }
        .task(id: AuthStore.shared.isSignedIn) { if AuthStore.shared.isSignedIn { await store.refresh() } }
        .gmModal(item: $opened) { FriendProfileView(friend: $0) }
    }

    @ViewBuilder
    private var suggestionsSection: some View {
        let list = store.suggestions(from: leagues)
        GMSection("Talvez você conheça", footer: list.isEmpty ? nil : "Pessoas das suas ligas que ainda não são suas amigas.") {
            if list.isEmpty {
                Text(leagues.isEmpty ? "Entre numa liga para ver aqui quem treina com você." : "Você já é amigo de todo mundo das suas ligas 🙌")
                    .font(.subheadline).foregroundStyle(Theme.dim)
            }
            ForEach(list, id: \.member.id) { s in
                HStack {
                    person(s.member.name, form: s.member.form,
                           subtitle: s.leagues.count == 1 ? "\(s.leagues[0].emoji) \(s.leagues[0].name)" : "\(s.leagues.count) ligas em comum")
                    GMButton("Adicionar", kind: .secondary, full: false, small: true) { add(id: s.member.id) }
                }
                if s.member.id != list.last?.member.id { GMDivider() }
            }
        }
    }

    private var myCode: some View {
        GMCard {
            HStack(spacing: 14) {
                Avatar(size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Seu código").font(.caption).foregroundStyle(Theme.dim)
                    Text(store.myCode).gmFont(26, weight: .heavy, design: .monospaced, relativeTo: .title).lineLimit(1).minimumScaleFactor(0.5)
                }
                Spacer()
                ShareLink(item: "Me adiciona no GymBros! Meu código de amigo: \(store.myCode)") {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .accessibilityLabel("Compartilhar código")
                        .background(Theme.raised, in: .circle)
                        .foregroundStyle(.white)
                }
                .buttonStyle(GMPress())
            }
        }
    }

    private func person(_ f: RemoteFriend, subtitle: String, online: Bool = false) -> some View {
        person(f.name, form: f.form, subtitle: subtitle, online: online)
    }

    private func person(_ name: String, form: MonsterForm, subtitle: String, online: Bool = false) -> some View {
        HStack(spacing: 12) {
            MonsterSprite(form: form).frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(name).font(.subheadline.weight(.semibold))
                    if online { GMOnlineDot() }
                }
                Text(subtitle).font(.caption).foregroundStyle(Theme.dim).lineLimit(1)
            }
            Spacer()
        }
        .foregroundStyle(.white)
    }

    private func isLive(_ f: RemoteFriend) -> Bool { FriendsLive.simulated.first { $0.id == f.id }?.isLive ?? false }

    /// Treinando agora (do mapa) ou a forma do bro
    private func status(_ f: RemoteFriend) -> String {
        if let live = FriendsLive.simulated.first(where: { $0.id == f.id }) {
            if live.isLive { return "\(live.kind.name) agora · \(live.place)" }
            if !live.lastSeen.isEmpty { return live.lastSeen }
        }
        return f.form.name
    }

    private func add(_ c: String) { add { try await store.add(code: c) } }

    private func add(id: String) { add { try await store.add(id: id) } }

    private func add(_ request: @escaping () async throws -> RemoteFriend) {
        Task {
            do {
                let f = try await request()
                message = "\(f.name) agora é seu amigo 🎉"
                code = ""
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
