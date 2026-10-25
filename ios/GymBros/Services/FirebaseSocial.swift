import CoreLocation
import FirebaseAuth
import FirebaseFirestore
import Foundation
import Observation

// Modo `.firebase`, parte em tempo real: mensagens diretas e treino ao vivo no mapa.
// Os dois usam ouvintes do Firestore enquanto o app está aberto (cada mudança custa só a leitura do que mudou).
// Push com o app fechado precisa de Cloud Functions (plano Blaze) e da conta paga da Apple: até lá, o que chegou
// toca como notificação local quando o app abre ou volta para a frente.

/// Liga e desliga os ouvintes conforme a conta do Firebase Auth
@MainActor
enum FireSync {
    private static var handle: AuthStateDidChangeListenerHandle?

    static func start() {
        guard handle == nil else { return }
        handle = Auth.auth().addStateDidChangeListener { _, user in
            MainActor.assumeIsolated {
                DirectMessageFeed.shared.listen(uid: user?.uid)
                if user == nil { LiveFriendsStore.shared.follow([]) }
            }
        }
    }
}

// MARK: - Mensagens diretas

/// Uma mensagem por documento em `directMessages`, com as duas pontas em `participants`: só elas leem (firestore.rules)
struct FirebaseInboxBackend: InboxBackend {
    /// O servidor guarda 90 dias (igual ao contrato)
    static let window: TimeInterval = 90 * 86_400

    func fetch() async throws -> InboxState {
        let me = try Fire.me()
        let messages = await DirectMessageFeed.shared.current(me: me)
        let peers = try await peers(Set(messages.map(\.peerID)))
        let events = await LiveFriendsStore.shared.events
        return InboxState(messages: messages, events: events, peers: peers)
    }

    func send(_ message: DirectMessage) async throws -> DirectMessage {
        let me = try Fire.me()
        var data = Fire.fields([
            "from": me, "to": message.peerID, "participants": [me, message.peerID], "date": message.date,
            "kind": message.kind.rawValue, "text": message.text, "replyTo": message.replyTo, "accepted": message.accepted,
        ])
        if let i = message.invite {
            data["invite"] = Fire.fields(["kind": i.kindRaw, "place": i.place, "when": i.when, "latitude": i.latitude, "longitude": i.longitude])
        }
        try await Fire.db.collection(FireCollection.directMessages).document(message.id).setData(data)
        return message
    }

    /// Nome e bro de quem não é amigo (amigos já vêm do FriendsStore); guardados para não ler de novo
    private func peers(_ ids: Set<String>) async throws -> [InboxPeer] {
        let known = await DirectMessageFeed.shared.peers
        let friends = await MainActor.run { Set(FriendsStore.shared.friendIDs) }
        let missing = ids.subtracting(friends).subtracting(known.keys)
        if !missing.isEmpty {
            let found = try await Fire.documents(FireCollection.profiles, ids: Array(missing)).map { d in
                InboxPeer(id: d.documentID, name: d.data()["name"] as? String ?? "", formID: d.data()["broFormID"] as? String ?? MonsterForm.egg.id)
            }
            await DirectMessageFeed.shared.remember(found)
        }
        return Array(await DirectMessageFeed.shared.peers.values)
    }
}

/// As mensagens dos últimos 90 dias, mantidas por um ouvinte do Firestore. Cada mudança atualiza a caixa de entrada.
@MainActor
final class DirectMessageFeed {
    static let shared = DirectMessageFeed()

    private var listener: ListenerRegistration?
    private var uid: String?
    private var docs: [QueryDocumentSnapshot] = []
    private var loaded = false
    private(set) var peers: [String: InboxPeer] = [:]

    func listen(uid: String?) {
        guard uid != self.uid else { return }
        listener?.remove()
        listener = nil
        self.uid = uid
        docs = []
        loaded = false
        peers = [:]
        guard let uid else { return }
        let since = Date.now.addingTimeInterval(-FirebaseInboxBackend.window)
        listener = Fire.db.collection(FireCollection.directMessages)
            .whereField("participants", arrayContains: uid)
            .whereField("date", isGreaterThan: since)
            .addSnapshotListener { [weak self] snap, _ in
                MainActor.assumeIsolated {
                    guard let self, let snap else { return }
                    self.docs = snap.documents
                    let first = !self.loaded
                    self.loaded = true
                    // A primeira resposta é a da própria busca; as seguintes são mensagens chegando
                    if !first { Task { await InboxStore.shared.refresh() } }
                }
            }
    }

    /// Espera a primeira resposta do ouvinte (no máximo alguns segundos, sem rede vale o que veio do cache)
    func current(me: String) async -> [DirectMessage] {
        if uid != me { listen(uid: me) }
        for _ in 0..<60 where !loaded { try? await Task.sleep(for: .milliseconds(100)) }
        return docs.compactMap { DirectMessage(fire: $0, me: me) }
    }

    func remember(_ list: [InboxPeer]) {
        for p in list { peers[p.id] = p }
    }
}

extension DirectMessage {
    init?(fire doc: QueryDocumentSnapshot, me: String) {
        let d = doc.data()
        guard let from = d["from"] as? String, let to = d["to"] as? String, let date = (d["date"] as? Timestamp)?.dateValue() else { return nil }
        let invite = (d["invite"] as? [String: Any]).map { i in
            TrainInvite(kindRaw: i["kind"] as? String ?? ActivityKind.outro.rawValue, place: i["place"] as? String ?? "",
                        when: (i["when"] as? Timestamp)?.dateValue(), latitude: i["latitude"] as? Double, longitude: i["longitude"] as? Double)
        }
        self.init(id: doc.documentID, peerID: from == me ? to : from, outgoing: from == me, date: date,
                  kind: (d["kind"] as? String).flatMap(DirectKind.init(rawValue:)) ?? .text, text: d["text"] as? String ?? "",
                  invite: invite, replyTo: d["replyTo"] as? String, accepted: d["accepted"] as? Bool)
    }
}

// MARK: - Treino ao vivo: o seu

/// Publica o seu treino em `live/{uid}` enquanto ele roda (se "Ao vivo" estiver ligado para ele).
/// No máximo uma gravação a cada 30 s, além do começo e do fim: uma hora de treino gasta umas 120 gravações.
@MainActor
final class LivePresence {
    static let shared = LivePresence()

    struct Status: Equatable {
        var kind: ActivityKind
        var start: Date
        var place: String
        var now: String
        var done: [String] = []
        var sets: Int?
        var meters: Double?
        var coordinate: CLLocationCoordinate2D?
        var route: [CLLocationCoordinate2D] = []

        static func == (a: Status, b: Status) -> Bool {
            a.kind == b.kind && a.start == b.start && a.place == b.place && a.now == b.now && a.done == b.done && a.sets == b.sets
        }
    }

    private static let interval: TimeInterval = 30
    private var workoutID: String?
    private var last: Status?
    private var lastWrite = Date.distantPast
    private var pending: Task<Void, Never>?

    private var enabled: Bool { Backend.mode == .firebase && FirebaseSession.uid != nil }

    /// Estado novo do treino `id`. Mudança de exercício ou de série sobe na hora (respeitando o intervalo mínimo)
    func update(_ id: String, _ status: Status) {
        guard enabled else { return }
        guard LiveShare.isSharing(id) else { return end(id) }
        let changed = workoutID != id || last != status
        workoutID = id
        last = status
        let wait = Self.interval - Date.now.timeIntervalSince(lastWrite)
        guard changed || wait <= 0 else { return }
        pending?.cancel()
        pending = Task {
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled, let s = self.last, self.workoutID == id else { return }
            self.lastWrite = .now
            await Self.write(s)
        }
    }

    /// Treino encerrado (ou "Ao vivo" desligado nele): fica só o "visto há…"
    func end(_ id: String) {
        // Só encerra o que estava publicando (um treino não compartilhado não deixa rastro). Com o app reaberto no meio do
        // treino, a memória está vazia: encerra se o treino compartilhava, senão ele ficaria "ao vivo" para os amigos
        guard enabled, workoutID == id || (workoutID == nil && LiveShare.isSharing(id)) else { return }
        pending?.cancel()
        let kind = last?.kind
        workoutID = nil
        last = nil
        guard let me = FirebaseSession.uid else { return }
        Task {
            try? await Fire.db.collection(FireCollection.live).document(me).setData(Fire.fields([
                "user": me, "start": nil, "now": "", "done": [String](), "route": [Double](), "endedAt": Date.now,
                "kind": kind?.rawValue, "updatedAt": Date.now,
                // A última posição e a música não ficam no servidor depois do treino
                "latitude": nil, "longitude": nil, "music": nil,
            ]), merge: true)
        }
    }

    private static func write(_ s: Status) async {
        guard let me = FirebaseSession.uid else { return }
        let profile = await MainActor.run { () -> (String, String) in
            let name = UserDefaults.standard.string(forKey: "trainerName") ?? AuthStore.shared.user?.name ?? ""
            return (name, UserDefaults.standard.string(forKey: FriendsStore.broFormKey) ?? MonsterForm.egg.id)
        }
        let music = MusicShareStore.shared.sharing ? MusicShareStore.shared.current : nil
        // Percurso: os últimos ~100 pontos, achatados em [lat, lon, lat, lon…] (o Firestore não guarda lista de listas)
        let route = s.route.suffix(100).flatMap { [$0.latitude, $0.longitude] }
        try? await Fire.db.collection(FireCollection.live).document(me).setData(Fire.fields([
            "user": me, "name": profile.0, "formID": profile.1, "kind": s.kind.rawValue, "start": s.start, "place": s.place,
            "now": s.now, "done": s.done, "sets": s.sets, "meters": s.meters,
            "latitude": s.coordinate?.latitude, "longitude": s.coordinate?.longitude, "route": route,
            "music": music.map { ["title": $0.title, "artist": $0.artist, "source": $0.source.rawValue] },
            "endedAt": nil, "updatedAt": Date.now,
        ]), merge: true)
    }

    // MARK: Fontes

    /// Musculação: exercício e série atuais, e o que já terminou
    func workout(_ s: WorkoutSession, state st: WorkoutAttributes.ContentState) {
        let gym = GymLocation.shared.gym(s.gymUUID)
        let done = s.exerciseIDs.compactMap { id -> String? in
            let sets = s.orderedSets.filter { $0.exerciseID == id && !$0.warmup }
            guard !sets.isEmpty, sets.allSatisfy(\.done) else { return nil }
            return "\(Exercise.name(id)) · \(sets.count) séries"
        }
        let now = st.setText.isEmpty ? st.exercise : "\(st.exercise) · série \(st.setNumber) de \(st.setCount) · \(st.setText)"
        place(gym) { coordinate in
            self.update(s.uuid.uuidString, Status(kind: .musculacao, start: s.start, place: gym?.name ?? "", now: now, done: done,
                                                  sets: st.doneSets, coordinate: coordinate))
        }
    }

    /// CrossFit: a parte ou o WOD em andamento
    func wod(label: String) {
        guard let s = WodRun.shared.state else { return }
        let gym = GymLocation.shared.gym(s.gymID)
        place(gym) { coordinate in
            self.update(s.liveID, Status(kind: .crossfit, start: s.sessionStart ?? s.openedAt, place: gym?.name ?? "",
                                         now: "\(s.wod.name) · \(label)", coordinate: coordinate))
        }
    }

    /// Corrida, caminhada e bike: posição e percurso do GPS
    func route(_ id: String, tracker t: RouteTracker) {
        guard let start = t.start, let here = t.current?.coordinate ?? t.coords.last else { return }
        update(id, Status(kind: t.kind, start: start, place: t.kind.name, now: kmText(t.meters), meters: t.meters,
                          coordinate: here, route: t.coords))
    }

    /// Na academia: o lugar salvo; fora dela, a posição atual (lida uma vez por treino)
    private var located: (id: String, coordinate: CLLocationCoordinate2D)?

    private func place(_ gym: Gym?, _ then: @escaping (CLLocationCoordinate2D?) -> Void) {
        guard enabled else { return }
        if let gym { return then(gym.coordinate) }
        let key = workoutID ?? ""
        if let located, located.id == key { return then(located.coordinate) }
        Task {
            let c = await GymLocation.shared.currentLocation()?.coordinate
            if let c { self.located = (key, c) }
            then(c)
        }
    }
}

// MARK: - Treino ao vivo: os amigos

/// Um ouvinte por amigo em `live/{uid}`: cada um só deixa os amigos lerem (firestore.rules)
@MainActor @Observable
final class LiveFriendsStore {
    static let shared = LiveFriendsStore()

    private(set) var friends: [LiveFriend] = []
    @ObservationIgnored private var listeners: [String: ListenerRegistration] = [:]
    @ObservationIgnored private var docs: [String: [String: Any]] = [:]

    /// Quem terminou há mais que isso some do mapa
    private static let recent: TimeInterval = 12 * 3600

    func follow(_ ids: [String]) {
        let want = Set(Backend.mode == .firebase ? ids : [])
        for (id, l) in listeners where !want.contains(id) {
            l.remove()
            listeners[id] = nil
            docs[id] = nil
        }
        for id in want where listeners[id] == nil {
            listeners[id] = Fire.db.collection(FireCollection.live).document(id).addSnapshotListener { [weak self] snap, _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.docs[id] = snap?.data()
                    self.rebuild()
                }
            }
        }
        rebuild()
    }

    private func rebuild() {
        friends = docs.compactMap { id, d in LiveFriend(fire: d, id: id) }
            .filter { $0.isLive || ($0.endedAt.map { Date.now.timeIntervalSince($0) < Self.recent } ?? false) }
            .sorted { $0.name < $1.name }
    }

    /// "Fulano começou a treinar" na aba Notificações (as últimas 6 h)
    var events: [InboxEvent] {
        friends.compactMap { f in
            guard let start = f.start, Date.now.timeIntervalSince(start) < 6 * 3600 else { return nil }
            return InboxEvent(id: "live-\(f.id)-\(Int(start.timeIntervalSince1970))", kind: .liveStart, actorID: f.id, actorName: f.name,
                              actorFormID: f.form.id, date: start, text: f.kind.name, detail: f.place)
        }
    }
}

extension LiveFriend {
    init?(fire d: [String: Any], id: String) {
        guard let kind = (d["kind"] as? String).flatMap(ActivityKind.init(rawValue:)) else { return nil }
        let reportedAt = (d["updatedAt"] as? Timestamp)?.dateValue() ?? .now
        // Sem notícia há 15 min (app fechado no meio do treino, sem rede): conta como encerrado
        let stale = Date.now.timeIntervalSince(reportedAt) > 15 * 60
        let start = stale ? nil : (d["start"] as? Timestamp)?.dateValue()
        let ended = (d["endedAt"] as? Timestamp)?.dateValue() ?? (stale ? reportedAt : nil)
        let flat = d["route"] as? [Double] ?? []
        let route = stride(from: 0, to: flat.count - 1, by: 2).map { CLLocationCoordinate2D(latitude: flat[$0], longitude: flat[$0 + 1]) }
        let location = (d["latitude"] as? Double).flatMap { lat in (d["longitude"] as? Double).map { CLLocationCoordinate2D(latitude: lat, longitude: $0) } }
        let meters = d["meters"] as? Double
        let music = (d["music"] as? [String: Any]).flatMap { m in
            (m["source"] as? String).flatMap(MusicSource.init(rawValue:)).map {
                NowPlayingTrack(title: m["title"] as? String ?? "", artist: m["artist"] as? String ?? "", source: $0)
            }
        }
        self.init(id: id, name: d["name"] as? String ?? "", form: MonsterForm.byID(d["formID"] as? String ?? "") ?? .egg, kind: kind,
                  start: start, place: d["place"] as? String ?? "", offset: (0, 0), now: d["now"] as? String ?? "",
                  done: d["done"] as? [String] ?? [],
                  lastSeen: ended.map { "\(kind.name) \($0.formatted(.relative(presentation: .named)))" } ?? "", music: music)
        self.location = location
        self.route = route
        self.sets = d["sets"] as? Int
        self.endedAt = ended
        self.real = true
        // Velocidade média até a última posição: o pino segue andando entre uma atualização e outra
        if let meters, let start { speed = meters / max(reportedAt.timeIntervalSince(start), 1) }
    }
}
