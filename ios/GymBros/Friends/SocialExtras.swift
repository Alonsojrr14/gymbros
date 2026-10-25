import AVFoundation
import CoreImage.CIFilterBuiltins
import SwiftData
import SwiftUI

// Social: o que você controla por amigo (esconder seus treinos, silenciar), o Deck dos Bros (check-ins que você
// recentes, um por vez, aberto pelos stories) e o QR do seu código de amigo.

// MARK: - Por amigo

struct FriendPrefs: Codable, Hashable {
    /// Seus treinos ficam escondidos dessa pessoa (o que você posta numa liga em comum continua aparecendo lá)
    var hideMine = false
    /// Notificações dessa pessoa não tocam (as mensagens e eventos chegam do mesmo jeito)
    var muted = false

    static let key = "friends.prefs"

    static func all(_ defaults: UserDefaults = .standard) -> [String: FriendPrefs] {
        defaults.string(forKey: key).flatMap { try? JSONDecoder().decode([String: FriendPrefs].self, from: Data($0.utf8)) } ?? [:]
    }

    static func of(_ id: String, _ defaults: UserDefaults = .standard) -> FriendPrefs { all(defaults)[id] ?? FriendPrefs() }

    static func set(_ id: String, _ change: (inout FriendPrefs) -> Void, defaults: UserDefaults = .standard) {
        var all = all(defaults)
        var p = all[id] ?? FriendPrefs()
        change(&p)
        all[id] = p == FriendPrefs() ? nil : p
        defaults.set((try? JSONEncoder().encode(all)).flatMap { String(data: $0, encoding: .utf8) }, forKey: key)
    }

    /// Quem não vê seus treinos
    static func hiddenFrom(_ defaults: UserDefaults = .standard) -> [String] { all(defaults).filter(\.value.hideMine).map(\.key).sorted() }
}

extension FriendsStore {
    /// Esconde (ou mostra) seus treinos para um amigo e avisa o servidor
    func setHideMine(_ id: String, _ hide: Bool) async {
        FriendPrefs.set(id) { $0.hideMine = hide }
        try? await backend.setHidden(from: FriendPrefs.hiddenFrom())
    }
}

extension FriendsBackend {
    /// Servidor sem o "esconder meus treinos" (os de teste)
    func setHidden(from ids: [String]) async throws {}
}

// MARK: - Deck dos Bros

/// Um card do deck: check-in de outra pessoa, de uma liga ou do perfil de um amigo
struct DeckCard: Identifiable {
    let item: FeedItem
    /// Onde foi postado ("🔥 Liga dos Bros" ou "Perfil")
    let place: String
    let leagueID: UUID?
    var id: String { item.id }
}

@MainActor
enum BroDeck {
    static let seenKey = "deck.seen"

    static func seen(_ defaults: UserDefaults = .standard) -> Set<String> { Set(defaults.stringArray(forKey: seenKey) ?? []) }

    /// Marca como visto (guarda os 600 mais recentes)
    static func markSeen(_ ids: [String], _ defaults: UserDefaults = .standard) {
        var list = defaults.stringArray(forKey: seenKey) ?? []
        for id in ids where !list.contains(id) { list.append(id) }
        defaults.set(Array(list.suffix(600)), forKey: seenKey)
    }

    /// Check-ins dos outros dos últimos 3 dias (ligas e perfis dos amigos) que você ainda não viu, do mais antigo para o mais novo
    static func cards(leagues: [League], checkIns: [LeagueCheckIn], activities: [Activity], me: String, friends: [FeedItem] = [],
                      includeSeen: Bool = false, now: Date = .now) -> [DeckCard] {
        let byID = Dictionary(activities.map { ($0.uuid, $0) }, uniquingKeysWith: { a, _ in a })
        let since = now.addingTimeInterval(-3 * 86400)
        let seen = includeSeen ? [] : seen()
        var out: [DeckCard] = []
        var ids = Set<String>()
        for l in leagues where !l.isPastSeason && !l.settings.isPrivate {
            let feed = LeagueBoard.feed(league: l, mine: checkIns.filter { $0.leagueUUID == l.uuid }, activities: byID, me: me, myAvatar: .egg)
            for f in ModerationStore.shared.visible(feed) where !f.isMe && f.date >= since && !seen.contains(f.id) && ids.insert(f.id).inserted {
                out.append(DeckCard(item: f, place: "\(l.emoji) \(l.name)", leagueID: l.uuid))
            }
        }
        for f in ModerationStore.shared.visible(friends) where f.date >= since && !seen.contains(f.id) && ids.insert(f.id).inserted {
            out.append(DeckCard(item: f, place: f.postedIn ?? "Perfil", leagueID: nil))
        }
        return out.sorted { $0.item.date < $1.item.date }
    }
}

/// Os check-ins recentes de uma pessoa, para a bolinha dos stories
struct DeckPerson: Identifiable {
    let id: String
    let cards: [DeckCard]
    let unseen: Int
    var latest: FeedItem { cards.last!.item }
    /// Onde o deck começa: no primeiro que você não viu, ou do começo se já viu tudo
    var start: Int { unseen > 0 ? cards.count - unseen : 0 }
}

extension BroDeck {
    /// Pessoas com check-in nos últimos 3 dias: quem tem novidade primeiro, depois quem você já viu (mais recentes antes)
    static func people(leagues: [League], checkIns: [LeagueCheckIn], activities: [Activity], me: String, friends: [FeedItem] = []) -> [DeckPerson] {
        let all = cards(leagues: leagues, checkIns: checkIns, activities: activities, me: me, friends: friends, includeSeen: true)
        let seen = seen()
        let people = Dictionary(grouping: all, by: \.item.memberID).map { id, cards in
            // Os vistos vêm antes dos novos, para o deck abrir direto no primeiro novo
            let ordered = cards.filter { seen.contains($0.id) } + cards.filter { !seen.contains($0.id) }
            return DeckPerson(id: id, cards: ordered, unseen: cards.count { !seen.contains($0.id) })
        }
        return people.sorted { a, b in
            if (a.unseen > 0) != (b.unseen > 0) { return a.unseen > 0 }
            return a.cards.map(\.item.date).max()! > b.cards.map(\.item.date).max()!
        }
    }
}

/// Fileira de stories: uma bolinha por amigo que postou nos últimos 3 dias. Com novidade, anel verde;
/// já vista, fica apagada mas continua abrindo.
struct BroStories: View {
    @Query(sort: \League.joinedAt) private var leagues: [League]
    @Query private var checkIns: [LeagueCheckIn]
    @Query private var activities: [Activity]
    @AppStorage("trainerName") private var me = ""
    @State private var store = FriendsStore.shared
    @State private var opened: (cards: [DeckCard], start: Int)?
    /// Muda quando o deck fecha, para as bolinhas recalcularem o que já foi visto
    @State private var version = 0

    var body: some View {
        // Como o feed: só os amigos (o resto do pessoal das ligas fica dentro de cada liga)
        let people = version >= 0 ? BroDeck.people(leagues: leagues, checkIns: checkIns, activities: activities, me: me, friends: friendPosts(store, leagues: true))
            .filter { store.friendIDs.contains($0.id) } : []
        if !people.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(people) { p in
                        Button { opened = (p.cards, p.start) } label: { bubble(p) }
                            .buttonStyle(GMPress())
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
            .gmModal(isPresented: Binding(get: { opened != nil }, set: { if !$0 { opened = nil; version += 1 } })) {
                BroDeckView(cards: opened?.cards ?? [], start: opened?.start ?? 0)
            }
        }
    }

    private func bubble(_ p: DeckPerson) -> some View {
        let fresh = p.unseen > 0
        return VStack(spacing: 6) {
            ZStack {
                Circle()
                    .strokeBorder(fresh ? AnyShapeStyle(AngularGradient(colors: [Theme.accent, Theme.accent.opacity(0.45), Theme.accent],
                                                                         center: .center))
                                        : AnyShapeStyle(Theme.track), lineWidth: fresh ? 3 : 1.5)
                Circle().fill(Theme.raised).padding(5)
                MonsterSprite(form: p.latest.avatar).padding(12)
                    .saturation(fresh ? 1 : 0.2)
                    .opacity(fresh ? 1 : 0.55)
            }
            .frame(width: 66, height: 66)
            .overlay(alignment: .bottomTrailing) {
                if p.unseen > 1 {
                    Text("\(p.unseen)").font(.caption2.bold()).monospacedDigit()
                        .padding(.horizontal, 5).frame(minWidth: 20, minHeight: 20)
                        .background(Theme.accent, in: .capsule).foregroundStyle(.black)
                        .overlay(Capsule().stroke(Theme.bg, lineWidth: 2))
                }
            }
            Text(p.latest.name).font(.caption2.weight(fresh ? .semibold : .regular)).lineLimit(1)
                .foregroundStyle(fresh ? .white : Theme.dim)
                .frame(width: 70)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(fresh ? "\(p.latest.name), \(p.unseen) novo\(p.unseen == 1 ? "" : "s")" : "\(p.latest.name), já visto")
    }
}

/// O deck: um check-in por vez. Arrasta para o lado para passar, toque duplo manda força, e dá para reagir ou responder.
struct BroDeckView: View {
    let cards: [DeckCard]
    var start = 0
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("trainerName") private var trainerName = ""
    @State private var index = 0
    @State private var drag: CGSize = .zero
    @State private var burst: String?
    @State private var replying = false
    @State private var replyTo: DeckCard?
    @State private var replyText = ""
    @State private var replyAsDM = false
    @State private var sentNote: String?

    private let emojis = ["👍", "❤️‍🔥", "💪", "🥚"]

    init(cards: [DeckCard], start: Int = 0) {
        self.cards = cards
        _index = State(initialValue: min(start, cards.count))
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                GMIconButton(icon: "xmark", label: "Fechar") { dismiss() }
                Spacer()
                Text(index < cards.count ? "\(index + 1) de \(cards.count)" : "Fim").font(.subheadline.monospacedDigit()).foregroundStyle(Theme.dim)
                Spacer()
                Color.clear.frame(width: 40, height: 40)
            }
            if index < cards.count {
                card(cards[index])
                    .offset(x: drag.width, y: drag.height * 0.2)
                    .rotationEffect(.degrees(Double(drag.width) / 22))
                    .gesture(DragGesture().onChanged { drag = $0.translation }.onEnded { v in
                        if abs(v.translation.width) > 110 { next() } else { withAnimation(.snappy) { drag = .zero } }
                    })
                    .onTapGesture(count: 2) { react("💪") }
                    .overlay {
                        if let burst {
                            Text(burst).font(.system(size: 110)).transition(.scale.combined(with: .opacity))
                        }
                    }
                HStack(spacing: 12) {
                    ForEach(emojis, id: \.self) { e in
                        Button { react(e) } label: {
                            Text(e).font(.system(size: 30)).frame(width: 56, height: 56).background(Theme.raised, in: .circle)
                        }
                        .buttonStyle(GMPress())
                        .accessibilityLabel("Reagir com \(e)")
                    }
                }
                HStack(spacing: 10) {
                    GMButton("Responder", icon: "arrowshape.turn.up.left", kind: .secondary) {
                        replyTo = cards[index]
                        replyText = ""
                        replyAsDM = false
                        replying = true
                    }
                    GMButton("Passar", icon: "arrow.right") { next() }
                }
                if let sentNote { Text(sentNote).font(.caption).foregroundStyle(Theme.dim) }
            } else {
                Spacer()
                GMEmptyState(icon: "checkmark.seal", title: "Você viu tudo", message: "Quando os bros postarem de novo, aparece aqui.")
                GMButton("Ver de novo", icon: "arrow.counterclockwise", kind: .secondary, full: false) { withAnimation { index = 0 } }
                Spacer()
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Theme.bg.ignoresSafeArea())
        .screenTip(.deck, blocked: replying || cards.isEmpty)
        .gmSheet(isPresented: $replying) { close in replySheet(close) }
    }

    private func card(_ c: DeckCard) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                if let data = c.item.photo, let img = UIImage(data: data) {
                    Color.clear.overlay { Image(uiImage: img).resizable().scaledToFill() }
                } else {
                    LinearGradient(colors: [Theme.accent.opacity(0.35), Theme.card], startPoint: .top, endPoint: .bottom)
                    MonsterSprite(form: c.item.avatar).frame(width: 160, height: 160)
                }
            }
            .frame(height: 340)
            .frame(maxWidth: .infinity)
            .clipped()
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    MonsterSprite(form: c.item.avatar).frame(width: 28, height: 28)
                    Text(c.item.name).font(.subheadline.bold())
                    Text("· \(shortAgo(c.item.date))").font(.caption).foregroundStyle(Theme.dim)
                    Spacer()
                    Text(c.place).font(.caption.weight(.semibold)).foregroundStyle(Theme.dim).lineLimit(1)
                }
                Text(c.item.title).font(.title3.bold()).lineLimit(2)
                Text("\(c.item.kind.name) · \(durationText(c.item.minutes))" + (c.item.scoring.map { " · +\($0.short(c.item.score))" } ?? ""))
                    .font(.caption).foregroundStyle(Theme.dim)
            }
            .padding(16)
        }
        .background(Theme.card, in: .rect(cornerRadius: Theme.radiusL))
        .clipShape(.rect(cornerRadius: Theme.radiusL))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Toque duas vezes para mandar força. Arraste para o lado para passar.")
        .accessibilityAction(named: "Passar") { next() }
    }

    /// Reação vira um comentário com o emoji no check-in (como no detalhe)
    private func react(_ e: String) {
        guard index < cards.count else { return }
        CommentSync.add(e, to: cards[index].id, owner: cards[index].item.memberID, scope: cards[index].item.comments, context: context)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(duration: 0.3)) { burst = e }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation { burst = nil }
            next()
        }
    }

    private func next() {
        guard index < cards.count else { return }
        BroDeck.markSeen([cards[index].id])
        sentNote = nil
        withAnimation(.snappy) {
            drag = .zero
            index += 1
        }
    }

    /// Responder: no check-in (todo mundo da liga vê) ou por mensagem direta (só vocês dois)
    private func replySheet(_ close: @escaping () -> Void) -> some View {
        let c = replyTo
        let isFriend = c.map { card in FriendsStore.shared.friendIDs.contains(card.item.memberID) } ?? false
        return VStack(alignment: .leading, spacing: 14) {
            Text("Responder \(c?.item.name ?? "")").font(.headline)
            GMSegmented(options: [(false, "No check-in"), (true, "Mensagem direta")], selection: $replyAsDM)
            Text(replyAsDM ? (isFriend ? "Só vocês dois veem." : "Mensagem direta é só entre amigos.") : "Todo mundo da liga vê.")
                .font(.caption).foregroundStyle(Theme.dim)
            GMTextField(placeholder: "Escreva…", text: $replyText, axis: .vertical)
            GMButton("Enviar", icon: "paperplane.fill",
                     enabled: !replyText.trimmingCharacters(in: .whitespaces).isEmpty && (!replyAsDM || isFriend)) {
                guard let c, ContentFilter.allows(replyText) else { return }
                let text = replyText.trimmingCharacters(in: .whitespaces)
                if replyAsDM {
                    Task { _ = try? await InboxStore.shared.send(.text, to: c.item.memberID, text: "Sobre \"\(c.item.title)\": \(text)") }
                    sentNote = "Mensagem enviada para \(c.item.name)."
                } else {
                    CommentSync.add(text, to: c.id, owner: c.item.memberID, scope: c.item.comments, context: context)
                    sentNote = "Comentário no check-in de \(c.item.name)."
                }
                close()
            }
        }
    }
}

// MARK: - QR do código de amigo

/// "gymbros://amigo/ABC123"
enum FriendQR {
    static func link(_ code: String) -> String { "gymbros://amigo/\(code)" }

    /// Lê o código de um QR do GymBros (ou o próprio código, se alguém mostrou só ele)
    static func code(in text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = t.range(of: "gymbros://amigo/") { return String(t[r.upperBound...]).uppercased() }
        let plain = t.uppercased()
        return plain.count == 6 && plain.allSatisfy { $0.isLetter || $0.isNumber } ? plain : nil
    }

    static func image(_ text: String) -> UIImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// Mostrar o QR (para quem está do lado) e ler o QR de outra pessoa
struct FriendQRView: View {
    let myCode: String
    let add: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var scanning = false

    var body: some View {
        GMModal("QR do amigo") {
            GMSegmented(options: [(false, "Mostrar meu QR"), (true, "Ler um QR")], selection: $scanning)
            if scanning {
                QRScanner { text in
                    guard let code = FriendQR.code(in: text), code != myCode else { return }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    dismiss()
                    add(code)
                }
                .frame(height: 360)
                .clipShape(.rect(cornerRadius: Theme.radius))
                Text("Aponte para o QR na tela do seu amigo.").font(.footnote).foregroundStyle(Theme.dim)
            } else {
                VStack(spacing: 12) {
                    if let img = FriendQR.image(FriendQR.link(myCode)) {
                        Image(uiImage: img).interpolation(.none).resizable().scaledToFit()
                            .padding(18).background(.white, in: .rect(cornerRadius: Theme.radius))
                            .frame(maxWidth: 280)
                            .accessibilityLabel("QR do seu código de amigo")
                    }
                    Text(myCode).font(.title2.monospaced().bold())
                    Text("Para quem está do seu lado: a pessoa lê este QR no app e vocês viram amigos.").font(.footnote).foregroundStyle(Theme.dim)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// Câmera lendo QR (AVFoundation), com o pedido de permissão
private struct QRScanner: UIViewControllerRepresentable {
    let found: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        let c = ScannerController()
        c.found = found
        return c
    }

    func updateUIViewController(_ c: ScannerController, context: Context) {}

    final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var found: ((String) -> Void)?
        private let session = AVCaptureSession()
        private var done = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            AVCaptureDevice.requestAccess(for: .video) { ok in
                DispatchQueue.main.async { ok ? self.setup() : self.denied() }
            }
        }

        private func denied() {
            let l = UILabel()
            l.text = "Libere a câmera nos Ajustes do iPhone para ler o QR."
            l.textColor = .lightGray
            l.numberOfLines = 0
            l.textAlignment = .center
            l.frame = view.bounds.insetBy(dx: 24, dy: 24)
            l.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(l)
        }

        private func setup() {
            guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return denied() }
            session.addInput(input)
            let out = AVCaptureMetadataOutput()
            guard session.canAddOutput(out) else { return }
            session.addOutput(out)
            out.setMetadataObjectsDelegate(self, queue: .main)
            out.metadataObjectTypes = [.qr]
            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            preview.frame = view.bounds
            view.layer.addSublayer(preview)
            let s = session
            DispatchQueue.global(qos: .userInitiated).async { s.startRunning() }
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            view.layer.sublayers?.compactMap { $0 as? AVCaptureVideoPreviewLayer }.forEach { $0.frame = view.bounds }
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            let s = session
            DispatchQueue.global(qos: .userInitiated).async { s.stopRunning() }
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !done, let text = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
            if FriendQR.code(in: text) != nil { done = true }
            found?(text)
        }
    }
}
