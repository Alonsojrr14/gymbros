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

    var isLive: Bool { start != nil }

    func elapsed(at date: Date) -> Int { start.map { max(0, Int(date.timeIntervalSince($0))) } ?? 0 }

    var moves: Bool { !path.isEmpty }

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
        let p = moves ? point(meters(at: date)) : (0, 0)
        return base.moved(east: offset.east + p.0, north: offset.north + p.1)
    }

    /// Rastro dos últimos ~800 m, como o traço que fica atrás de quem corre
    func trail(base: CLLocationCoordinate2D, at date: Date) -> [CLLocationCoordinate2D] {
        guard moves else { return [] }
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
            return [(clock(s), "tempo"), ("\(8 + s / 300)", "séries"), ("\(kcal)", "kcal")]
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

    static let all: [LiveFriend] = [
        LiveFriend(id: "bruno", name: "Bruno", form: MonsterForm(stage: .champion, attribute: .forca, species: "urso"),
                   kind: .musculacao, start: opened.addingTimeInterval(-38 * 60), place: "Smart Fit", offset: (520, 380),
                   now: "Supino reto · série 3 de 4 · 80 kg",
                   done: ["Supino inclinado · 4×10 · 26 kg", "Crucifixo · 3×12 · 14 kg", "Tríceps corda · 3×15"]),
        LiveFriend(id: "ana", name: "Ana", form: MonsterForm(stage: .champion, attribute: .resistencia, species: "lobo"),
                   kind: .corrida, start: opened.addingTimeInterval(-24 * 60), place: "Parque", offset: (-420, -160),
                   path: [(0, 0), (140, 60), (260, 40), (380, 130), (420, 260), (360, 400), (210, 450), (90, 520),
                          (-60, 470), (-150, 340), (-120, 200), (-170, 90), (-90, -20)],
                   speed: 3.1, now: "Longão leve · 5:20/km"),
        LiveFriend(id: "diego", name: "Diego", form: MonsterForm(stage: .ultimate, attribute: .forca, attribute2: .agilidade, species: "gato"),
                   kind: .futebol, start: opened.addingTimeInterval(-51 * 60), place: "Quadra do bairro", offset: (180, -650),
                   now: "Pelada · 2º tempo, 3 a 2 pro time dele"),
        LiveFriend(id: "fe", name: "Fê", form: MonsterForm(stage: .rookie, attribute: nil, species: "coruja"),
                   kind: .natacao, start: opened.addingTimeInterval(-17 * 60), place: "Clube", offset: (-650, 520),
                   now: "Crawl · tiros de 100 m"),
        LiveFriend(id: "carla", name: "Carla", form: MonsterForm(stage: .champion, attribute: .tecnica, species: "esquilo"),
                   kind: .yoga, start: nil, place: "Studio", offset: (300, 90), lastSeen: "Yoga há 3 h"),
    ]

    static var liveCount: Int { all.filter(\.isLive).count }
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
                MonsterSprite(form: friend.form).frame(width: 34, height: 34)
                    .saturation(friend.isLive ? 1 : 0.2)
                Image(systemName: friend.kind.symbol)
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 18, height: 18)
                    .background(friend.isLive ? friend.color : Theme.raised, in: .circle)
                    .foregroundStyle(.black)
                    .offset(x: 17, y: 16)
            }
            Text(friend.isLive ? "\(friend.name) · \(friend.elapsed(at: date) / 60) min" : friend.name)
                .font(.system(size: 10, weight: .bold))
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Theme.bg.opacity(0.85), in: .capsule)
                .foregroundStyle(.white)
        }
        .onAppear {
            guard friend.isLive else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

// MARK: - Card do amigo

struct LiveFriendCard: View {
    let friend: LiveFriend
    @Binding var cheered: Set<String>
    var onShow: () -> Void = {}
    @State private var together = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    MonsterSprite(form: friend.form)
                        .frame(width: 56, height: 56)
                        .padding(6)
                        .background(Theme.raised, in: .circle)
                        .overlay(Circle().stroke(friend.isLive ? friend.color : Theme.stroke, lineWidth: 3))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(friend.name).font(.title3.bold())
                        Text(friend.form.name).font(.caption).foregroundStyle(Theme.dim)
                        if friend.isLive {
                            HStack(spacing: 5) {
                                Circle().fill(.red).frame(width: 7, height: 7)
                                Text("AO VIVO · \(friend.kind.name) · \(friend.place)").font(.caption.bold()).foregroundStyle(friend.color)
                            }
                        } else {
                            Text(friend.lastSeen).font(.caption).foregroundStyle(Theme.dim)
                        }
                    }
                    Spacer(minLength: 0)
                }
                if friend.isLive {
                    HStack(spacing: 8) {
                        ForEach(Array(friend.stats(at: ctx.date).enumerated()), id: \.offset) { _, s in
                            VStack(spacing: 2) {
                                Text(s.0).font(.headline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
                                Text(s.1).font(.caption2).foregroundStyle(Theme.dim)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Theme.raised, in: .rect(cornerRadius: 12))
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("AGORA").font(.caption2.bold()).foregroundStyle(Theme.dim)
                        Label(friend.now, systemImage: friend.kind.symbol).font(.subheadline.weight(.semibold))
                        ForEach(friend.done, id: \.self) { d in
                            Label(d, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(Theme.dim)
                        }
                    }
                }
                HStack(spacing: 10) {
                    let on = cheered.contains(friend.id)
                    GMButton(on ? "Força enviada" : "Mandar força 💪", icon: on ? "checkmark" : nil, kind: on ? .secondary : .primary) {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation(.snappy) {
                            if on { cheered.remove(friend.id) } else { cheered.insert(friend.id) }
                        }
                    }
                    GMIconButton(icon: "location.fill", size: 48) { onShow() }
                }
                if friend.isLive { togetherButton }
                Text("Prévia com amigos simulados.").font(.caption2).foregroundStyle(Theme.dim)
            }
        }
    }

    /// Convite para treinar junto: cartão com o bro dos dois e a cor da atividade do amigo
    private var togetherButton: some View {
        Button {
            guard !together else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.spring(duration: 0.35, bounce: 0.4)) { together = true }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(friend.color.opacity(together ? 1 : 0.18))
                    Image(systemName: together ? "checkmark" : "figure.2")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(together ? .black : friend.color)
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(together ? "Convite enviado" : "Treinar junto com \(friend.name)")
                        .font(.subheadline.bold())
                    Text(together ? "\(friend.name) vai ver no app e pode te chamar no \(friend.place)"
                                  : "Chama pra somar XP em dupla no \(friend.place)")
                        .font(.caption).foregroundStyle(Theme.dim).lineLimit(2)
                }
                Spacer(minLength: 0)
                if !together {
                    Image(systemName: "paperplane.fill").font(.subheadline.bold()).foregroundStyle(friend.color)
                }
            }
            .padding(12)
            .background(friend.color.opacity(together ? 0.16 : 0.08), in: .rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(friend.color.opacity(together ? 0.9 : 0.45), lineWidth: 1.5))
            .foregroundStyle(.white)
        }
        .buttonStyle(GMPress())
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
                    Circle().fill(.red).frame(width: 6, height: 6)
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
