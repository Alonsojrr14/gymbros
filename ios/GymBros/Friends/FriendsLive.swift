import CoreLocation
import MapKit
import SwiftUI

// MARK: - Amigos treinando agora (prévia)
//
// Prévia de como o Mapa fica quando as ligas tiverem servidor: amigos que compartilham o treino ao vivo
// aparecem no mapa com o bro deles. Por enquanto os amigos são simulados (os mesmos das ligas de teste),
// posicionados em volta de onde você treina.

struct LiveFriend: Identifiable {
    let id: String
    let name: String
    let form: MonsterForm
    let kind: ActivityKind
    /// Começou o treino (nil: não está treinando agora)
    let start: Date?
    let place: String
    /// Deslocamento em metros a partir do ponto base (leste, norte)
    let offset: (east: Double, north: Double)
    /// Corrida: percurso fechado (pontos em metros a partir do offset) que a pessoa repete, e velocidade (m/s)
    var path: [(Double, Double)] = []
    var speed: Double = 0
    /// O que está fazendo agora e o que já fez
    var now: String = ""
    var done: [String] = []
    var lastSeen: String = ""
    /// O que está ouvindo (só quem liga "Mostrar o que estou ouvindo")
    var music: NowPlayingTrack?
    /// Amigo de verdade (modo `.firebase`): posição e percurso reais, sem números inventados
    var real = false
    var location: CLLocationCoordinate2D?
    var route: [CLLocationCoordinate2D] = []
    var sets: Int?
    var endedAt: Date?

    var isLive: Bool { start != nil }

    func elapsed(at date: Date) -> Int { start.map { max(0, Int(date.timeIntervalSince($0))) } ?? 0 }

    var moves: Bool { real ? route.count > 1 : !path.isEmpty }

    /// Metros percorridos (corrida)
    func meters(at date: Date) -> Double { speed * Double(elapsed(at: date)) }

    /// Ponto do percurso a `d` metros do início (o percurso se repete)
    private func point(_ d: Double) -> (Double, Double) {
        let segs = zip(path, path.dropFirst() + [path[0]]).map { a, b in (a, b, hypot(b.0 - a.0, b.1 - a.1)) }
        var r = d.truncatingRemainder(dividingBy: segs.reduce(0) { $0 + $1.2 })
        for (a, b, len) in segs {
            if r <= len { let t = r / len; return (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t) }
            r -= len
        }
        return path[0]
    }

    func coordinate(base: CLLocationCoordinate2D, at date: Date) -> CLLocationCoordinate2D {
        if real { return location ?? route.last ?? base }
        let p = moves ? point(meters(at: date)) : (0, 0)
        return base.moved(east: offset.east + p.0, north: offset.north + p.1)
    }

    /// Rastro dos últimos ~800 m, como o traço que fica atrás de quem corre
    func trail(base: CLLocationCoordinate2D, at date: Date) -> [CLLocationCoordinate2D] {
        guard moves else { return [] }
        if real { return route }
        let total = meters(at: date)
        return stride(from: max(0, total - 800), through: total, by: 10).map { d in
            let p = point(d)
            return base.moved(east: offset.east + p.0, north: offset.north + p.1)
        }
    }

    /// Números do card, conforme a atividade
    func stats(at date: Date) -> [(String, String)] {
        let s = elapsed(at: date)
        let kcal = Int(Double(s) / 60 * kind.met * 1.2)
        switch kind {
        case .corrida, .caminhada, .bike:
            let m = meters(at: date)
            return [(clock(s), "tempo"), (kmText(m), "distância"), (paceText(kind: kind, meters: m, seconds: s), "ritmo")]
        case .musculacao:
            return [(clock(s), "tempo"), (real ? "\(sets ?? 0)" : "\(8 + s / 300)", "séries"), ("\(kcal)", "kcal")]
        case _ where real:
            return [(clock(s), "tempo"), ("\(kcal)", "kcal")]
        case .natacao:
            return [(clock(s), "tempo"), ("\(s / 60 * 50 / 2) m", "nadados"), ("\(kcal)", "kcal")]
        default:
            return [(clock(s), "tempo"), ("\(kcal)", "kcal"), ("\(120 + s % 37)", "bpm")]
        }
    }

    var color: Color { LiveFriend.color(kind) }

    static func color(_ k: ActivityKind) -> Color {
        switch k {
        case .musculacao, .crossfit: Attribute.forca.color
        case .corrida, .caminhada, .bike: Attribute.resistencia.color
        case .futebol, .volei, .lutas: Attribute.agilidade.color
        default: Attribute.tecnica.color
        }
    }
}

enum FriendsLive {
    /// Os treinos simulados começam um pouco antes de abrir o app, e o tempo corre de verdade a partir daí
    private static let opened = Date.now

    /// Mesmo bro que a pessoa tem nas ligas (FakeMember)
    private static func form(_ id: String) -> MonsterForm { FakeMember.byID(id)?.form ?? .egg }

    /// Todos os simulados; `all` são só os que ainda são seus amigos (FriendsStore)
    static let simulated: [LiveFriend] = [
        LiveFriend(id: "bruno", name: "Bruno", form: form("bruno"),
                   kind: .musculacao, start: opened.addingTimeInterval(-38 * 60), place: "Smart Fit", offset: (520, 380),
                   now: "Supino reto · série 3 de 4 · 80 kg",
                   done: ["Supino inclinado · 4×10 · 26 kg", "Crucifixo · 3×12 · 14 kg", "Tríceps corda · 3×15"],
                   music: NowPlayingTrack(title: "Till I Collapse", artist: "Eminem", source: .appleMusic)),
        LiveFriend(id: "ana", name: "Ana", form: form("ana"),
                   kind: .corrida, start: opened.addingTimeInterval(-24 * 60), place: "Parque", offset: (-420, -160),
                   path: [(0, 0), (140, 60), (260, 40), (380, 130), (420, 260), (360, 400), (210, 450), (90, 520),
                          (-60, 470), (-150, 340), (-120, 200), (-170, 90), (-90, -20)],
                   speed: 3.1, now: "Longão leve · 5:20/km",
                   music: NowPlayingTrack(title: "Run Boy Run", artist: "Woodkid", source: .spotify)),
        LiveFriend(id: "diego", name: "Diego", form: form("diego"),
                   kind: .futebol, start: opened.addingTimeInterval(-51 * 60), place: "Quadra do bairro", offset: (180, -650),
                   now: "Pelada · 2º tempo, 3 a 2 pro time dele"),
        LiveFriend(id: "fe", name: "Fê", form: form("fe"),
                   kind: .natacao, start: opened.addingTimeInterval(-17 * 60), place: "Clube", offset: (-650, 520),
                   now: "Crawl · tiros de 100 m"),
        LiveFriend(id: "carla", name: "Carla", form: form("carla"),
                   kind: .yoga, start: nil, place: "Studio", offset: (300, 90), lastSeen: "Yoga há 3 h"),
    ]

    @MainActor static var all: [LiveFriend] {
        Backend.mode == .firebase ? LiveFriendsStore.shared.friends : simulated.filter { FriendsStore.shared.friendIDs.contains($0.id) }
    }

    /// O amigo, se estiver no mapa (de verdade ou simulado)
    @MainActor static func find(_ id: String) -> LiveFriend? {
        Backend.mode == .firebase ? LiveFriendsStore.shared.friends.first { $0.id == id } : simulated.first { $0.id == id }
    }

    @MainActor static var liveCount: Int { all.filter(\.isLive).count }
}

extension CLLocationCoordinate2D {
    func moved(east: Double, north: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude + north / 111_111,
                               longitude: longitude + east / (111_111 * cos(latitude * .pi / 180)))
    }
}

// MARK: - Pino do amigo no mapa

struct FriendPin: View {
    let friend: LiveFriend
    let date: Date
    /// Foto pública do amigo; sem ela (escondeu ou não tem), aparece o bro principal
    var photo: Data?
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                if friend.isLive {
                    Circle().stroke(friend.color, lineWidth: 2)
                        .frame(width: 48, height: 48)
                        .scaleEffect(pulse ? 1.7 : 1)
                        .opacity(pulse ? 0 : 0.8)
                }
                Circle().fill(Theme.bg).frame(width: 46, height: 46)
                    .overlay(Circle().stroke(friend.isLive ? friend.color : Theme.dim, lineWidth: 3))
                if let photo, let img = UIImage(data: photo) {
                    Image(uiImage: img).resizable().scaledToFill()
                        .frame(width: 40, height: 40).clipShape(.circle)
                        .saturation(friend.isLive ? 1 : 0.2)
                } else {
                    MonsterSprite(form: friend.form).frame(width: 34, height: 34)
                        .saturation(friend.isLive ? 1 : 0.2)
                }
                Image(systemName: friend.kind.symbol)
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 18, height: 18)
                    .background(friend.isLive ? friend.color : Theme.raised, in: .circle)
                    .foregroundStyle(.black)
                    .offset(x: 17, y: 16)
            }
            // Por cima da bolinha, sem mudar o tamanho do pino (o ponto no mapa continua o mesmo)
            .overlay(alignment: .top) {
                if friend.isLive, let music = friend.music {
                    Label(music.title, systemImage: "music.note")
                        .labelStyle(MusicTagStyle())
                        // Largura máxima da etiqueta; títulos longos terminam em "…"
                        .frame(width: 120)
                        .offset(y: -20)
                        .accessibilityLabel("Ouvindo \(music.title)")
                }
            }
            HStack(spacing: 3) {
                if friend.isLive { GMOnlineDot(size: 6) }
                Text(friend.isLive ? "\(friend.name) · \(friend.elapsed(at: date) / 60) min" : friend.name)
            }
                .gmFont(10, weight: .bold, relativeTo: .caption2)
                .lineLimit(1)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Theme.bg.opacity(0.85), in: .capsule)
                .foregroundStyle(.white)
        }
        // Pino no mapa: o texto cresce só até um limite
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .onAppear {
            guard friend.isLive else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

/// Etiqueta mínima da música em cima do pino: nota + título curto
private struct MusicTagStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.health)
            configuration.title.lineLimit(1)
        }
        .gmFont(9, weight: .semibold, relativeTo: .caption2)
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Theme.bg.opacity(0.8), in: .capsule)
    }
}

// MARK: - Card do amigo

struct LiveFriendCard: View {
    let friend: LiveFriend
    @Binding var cheered: Set<String>
    var onMessage: () -> Void = {}
    @State private var together = false
    @State private var error: String?
    @State private var terms = TermsGate()
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            VStack(alignment: .leading, spacing: 16) {
                header(at: ctx.date)
                if friend.isLive {
                    statsStrip(at: ctx.date)
                    nowCard
                    if let music = friend.music { musicRow(music) }
                }
                actions
                if friend.isLive { togetherButton }
                feedback
            }
        }
        .termsGate($terms)
        .onAppear {
            guard friend.isLive, !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
        }
    }

    private func header(at date: Date) -> some View {
        HStack(spacing: 14) {
            ZStack {
                if friend.isLive {
                    Circle().stroke(friend.color.opacity(0.5), lineWidth: 2)
                        .scaleEffect(pulse ? 1.25 : 1)
                        .opacity(pulse ? 0 : 1)
                }
                Circle().fill(friend.color.opacity(friend.isLive ? 0.14 : 0)).background(Theme.raised, in: .circle)
                MonsterSprite(form: friend.form).padding(8)
                    .saturation(friend.isLive ? 1 : 0.3)
                Circle().stroke(friend.isLive ? friend.color : Theme.stroke, lineWidth: 3)
            }
            .frame(width: 76, height: 76)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(friend.name).gmFont(24, weight: .heavy, design: .rounded, relativeTo: .title2).lineLimit(1)
                Text(friend.form.name).font(.caption).foregroundStyle(Theme.dim)
                if friend.isLive {
                    HStack(spacing: 6) {
                        GMOnlineDot(size: 6)
                        Text("AO VIVO").font(.caption2.weight(.heavy))
                        Text(clock(friend.elapsed(at: date))).font(.caption2.weight(.heavy).monospacedDigit())
                    }
                    .foregroundStyle(friend.color)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(friend.color.opacity(0.14), in: .capsule)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(liveLabel(minutes: friend.elapsed(at: date) / 60))
                    Label("\(friend.kind.name) · \(friend.place)", systemImage: "mappin.and.ellipse")
                        .font(.caption).foregroundStyle(Theme.dim).lineLimit(1)
                } else {
                    Text(friend.lastSeen).font(.caption).foregroundStyle(Theme.dim)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// Números do treino numa faixa só, com ícone por medida
    private func statsStrip(at date: Date) -> some View {
        let stats = friend.stats(at: date)
        return HStack(spacing: 0) {
            ForEach(Array(stats.enumerated()), id: \.offset) { i, s in
                if i > 0 { Rectangle().fill(Theme.stroke).frame(width: 1, height: 34) }
                VStack(spacing: 4) {
                    Image(systemName: Self.icon(s.1)).font(.caption.bold()).foregroundStyle(friend.color)
                    Text(s.0).font(.headline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
                    Text(s.1).font(.caption2).foregroundStyle(Theme.dim)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, 12)
        .background(Theme.raised, in: .rect(cornerRadius: Theme.radiusL))
    }

    private static func icon(_ label: String) -> String {
        switch label {
        case "tempo": "timer"
        case "kcal": "flame.fill"
        case "bpm": "heart.fill"
        case "distância": "point.topleft.down.to.point.bottomright.curvepath"
        case "ritmo", "velocidade": "speedometer"
        default: "chart.bar.fill"
        }
    }

    private var nowCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: friend.kind.symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(friend.color)
                .frame(width: 36, height: 36)
                .background(friend.color.opacity(0.16), in: .circle)
            VStack(alignment: .leading, spacing: 4) {
                Text("AGORA").font(.caption2.bold()).foregroundStyle(Theme.dim)
                Text(friend.now).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                ForEach(friend.done, id: \.self) { d in
                    Label(d, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(Theme.dim)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.raised, in: .rect(cornerRadius: Theme.radiusL))
        .accessibilityElement(children: .combine)
    }

    private func musicRow(_ music: NowPlayingTrack) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "headphones")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.health)
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
            VStack(alignment: .leading, spacing: 1) {
                Text(music.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(music.artist.isEmpty ? music.source.name : "\(music.artist) · \(music.source.name)")
                    .font(.caption).foregroundStyle(Theme.dim).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.health.opacity(0.10), in: .rect(cornerRadius: Theme.radiusL))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ouvindo \(music.title)\(music.artist.isEmpty ? "" : ", de \(music.artist)"), no \(music.source.name)")
    }

    /// Força e mensagem: ações com ícone e nome, para nenhuma ficar misteriosa.
    /// Não há "ver no mapa": o card já abre com o mapa centrado no amigo
    private var actions: some View {
        let on = cheered.contains(friend.id)
        return HStack(spacing: 10) {
            ActionTile(icon: on ? "checkmark" : "hands.clap.fill", title: on ? "Força enviada" : "Mandar força",
                       tint: on ? Theme.dim : .black, fill: on ? Theme.raised : Theme.accent, enabled: !on) {
                send { try await InboxStore.shared.cheer(friend.id) } done: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.snappy) { _ = cheered.insert(friend.id) }
                }
            }
            ActionTile(icon: "envelope.fill", title: "Mensagem", tint: .white, fill: Theme.raised, action: onMessage)
        }
    }

    @ViewBuilder
    private var feedback: some View {
        if let error {
            Text(error).font(.caption2).foregroundStyle(Theme.danger)
        } else if cheered.contains(friend.id) || together {
            Label("Chegou para \(friend.name). A resposta aparece no sino da tela inicial.", systemImage: "bell.fill")
                .font(.caption2).foregroundStyle(Theme.dim)
        }
    }

    /// Envia pela caixa de entrada (depois do aceite dos termos) e mostra o erro no card
    private func send(_ action: @escaping () async throws -> Void, done: @escaping () -> Void) {
        terms.run {
            Task {
                do {
                    try await action()
                    error = nil
                    done()
                } catch {
                    self.error = error.localizedDescription
                }
            }
        }
    }

    /// Convite para treinar junto, na cor da atividade do amigo
    private var togetherButton: some View {
        Button {
            guard !together else { return }
            send { try await InboxStore.shared.invite(friend.id, TrainInvite(kindRaw: friend.kind.rawValue, place: friend.place, when: nil)) } done: {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(.spring(duration: 0.35, bounce: 0.4)) { together = true }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: together ? "checkmark" : "figure.2")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(together ? .black : friend.color)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
                    .background(friend.color.opacity(together ? 1 : 0.18), in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(together ? "Convite enviado" : "Treinar junto")
                        .font(.subheadline.bold())
                    Text(together ? "\(friend.name) responde pela conversa de vocês."
                                  : "Chama \(friend.name) pra treinar junto em \(friend.place)")
                        .font(.caption).foregroundStyle(Theme.dim).lineLimit(2)
                }
                Spacer(minLength: 0)
                if !together {
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(friend.color)
                }
            }
            .padding(12)
            .background(
                LinearGradient(colors: [friend.color.opacity(together ? 0.22 : 0.14), friend.color.opacity(0.04)],
                               startPoint: .leading, endPoint: .trailing),
                in: .rect(cornerRadius: Theme.radiusL)
            )
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusL).stroke(friend.color.opacity(together ? 0.9 : 0.4), lineWidth: 1.5))
            .foregroundStyle(.white)
        }
        .buttonStyle(GMPress())
        .disabled(together)
    }
}

/// Botão quadrado com ícone e nome embaixo (ações do card do amigo)
private struct ActionTile: View {
    let icon: String
    let title: String
    let tint: Color
    let fill: Color
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 18, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
                Text(title).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.75)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(fill, in: .rect(cornerRadius: Theme.radiusL))
        }
        .buttonStyle(GMPress())
        .disabled(!enabled)
        .accessibilityLabel(title)
    }
}

// MARK: - Linha da lista "Amigos agora"

struct LiveFriendRow: View {
    let friend: LiveFriend
    let date: Date

    var body: some View {
        HStack(spacing: 12) {
            MonsterSprite(form: friend.form)
                .frame(width: 34, height: 34)
                .padding(4)
                .background(Theme.raised, in: .circle)
                .overlay(Circle().stroke(friend.isLive ? friend.color : .clear, lineWidth: 2))
                .saturation(friend.isLive ? 1 : 0.2)
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.name).font(.subheadline.weight(.semibold))
                Text(friend.isLive ? "\(friend.kind.name) · \(friend.place)" : friend.lastSeen)
                    .font(.caption).foregroundStyle(Theme.dim).lineLimit(1)
            }
            Spacer()
            if friend.isLive {
                HStack(spacing: 5) {
                    GMOnlineDot(size: 6)
                    Text(clock(friend.elapsed(at: date))).font(.caption.monospacedDigit().bold())
                }
                .foregroundStyle(friend.color)
            }
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.dim)
        }
        .contentShape(Rectangle())
        .opacity(friend.isLive ? 1 : 0.6)
    }
}

/// Rótulo do VoiceOver para o tempo ao vivo, com singular e menos de um minuto
func liveLabel(minutes: Int) -> String {
    switch minutes {
    case ..<1: "Ao vivo há menos de 1 minuto"
    case 1: "Ao vivo há 1 minuto"
    default: "Ao vivo há \(minutes) minutos"
    }
}
