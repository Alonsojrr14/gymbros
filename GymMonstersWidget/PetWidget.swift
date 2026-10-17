import AppIntents
import SwiftUI
import WidgetKit

// Widget "bichinho": o monstro em destaque, mudando de pose a cada minuto (com transição
// animada) e reagindo a carinho com um toque. Widgets não rodam animação contínua; cada
// pose é uma entrada da timeline e o iOS anima a troca entre elas.

enum Pose: Int {
    case idle, hop, lookBack, stretch, sleep, pet, wobbleLeft, wobbleRight, celebrate
}

struct PetEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
    let pose: Pose
    let pets: Int

    var mood: Mood { Mood.of(isEgg: data.isEgg, lastActivity: data.lastActivity, todayXP: data.todayXP, streak: data.streak, now: date) }
}

enum PetStore {
    static let petAtKey = "petAt"
    static let petsKey = "pets"

    static var lastPet: Date? { WidgetData.defaults?.object(forKey: petAtKey) as? Date }
    static var pets: Int { WidgetData.defaults?.integer(forKey: petsKey) ?? 0 }

    static func pet() {
        WidgetData.defaults?.set(Date.now, forKey: petAtKey)
        WidgetData.defaults?.set(pets + 1, forKey: petsKey)
    }
}

struct PetIntent: AppIntent {
    static var title: LocalizedStringResource = "Fazer carinho"
    static var description = IntentDescription("Faz carinho no seu bro.")

    func perform() async throws -> some IntentResult {
        PetStore.pet()
        return .result()
    }
}

struct PetProvider: TimelineProvider {
    func placeholder(in context: Context) -> PetEntry { PetEntry(date: .now, data: .placeholder, pose: .idle, pets: 0) }

    func getSnapshot(in context: Context, completion: @escaping (PetEntry) -> Void) {
        completion(PetEntry(date: .now, data: WidgetData.load() ?? .placeholder, pose: .idle, pets: PetStore.pets))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PetEntry>) -> Void) {
        let data = WidgetData.load() ?? .placeholder
        let pets = PetStore.pets
        let now = Date.now
        var entries: [PetEntry] = []
        var start = now

        // Acabou de receber carinho: reage e volta ao normal em seguida
        if let last = PetStore.lastPet, now.timeIntervalSince(last) < 5 {
            entries.append(PetEntry(date: now, data: data, pose: .pet, pets: pets))
            start = now.addingTimeInterval(4)
        }

        let mood = Mood.of(isEgg: data.isEgg, lastActivity: data.lastActivity, todayXP: data.todayXP, streak: data.streak, now: now)
        var cycle: [Pose]
        switch mood {
        case .ovo: cycle = [.idle, .wobbleLeft, .idle, .wobbleRight, .idle, .wobbleLeft]
        case .triste, .entediado, .exausto: cycle = [.idle, .sleep, .sleep, .idle, .stretch, .sleep]
        default: cycle = [.idle, .hop, .idle, .lookBack, .idle, .stretch, .hop, .idle]
        }
        // Nas 24 h depois de evoluir, comemora pulando
        if data.celebrating(at: now) { cycle = [.hop, .celebrate, .hop, .idle, .celebrate, .lookBack] }
        // Uma pose por minuto pela próxima hora
        for i in 0..<60 {
            let date = start.addingTimeInterval(Double(i) * 60)
            entries.append(PetEntry(date: date, data: data, pose: cycle[i % cycle.count], pets: pets))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct PetView: View {
    let entry: PetEntry
    @Environment(\.widgetFamily) private var family

    private var d: WidgetData { entry.data }
    private var spriteSize: CGFloat { family == .systemSmall ? 92 : family == .systemLarge ? 230 : 120 }

    var body: some View {
        switch family {
        case .accessoryCircular: lockCircular
        case .accessoryRectangular: lockRectangular
        default: home
        }
    }

    // Tela de bloqueio: o iOS desenha em tons translúcidos, sem cor

    private var lockCircular: some View {
        Button(intent: PetIntent()) {
            ZStack {
                AccessoryWidgetBackground()
                lockSprite.padding(7)
                if entry.pose == .pet {
                    Text("❤️").font(.system(size: 13)).offset(x: 14, y: -15)
                }
            }
        }
        .buttonStyle(.plain)
        .containerBackground(.clear, for: .widget)
    }

    private var lockRectangular: some View {
        Button(intent: PetIntent()) {
            HStack(spacing: 8) {
                lockSprite.frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 1) {
                    Text(d.monsterName).font(.headline).lineLimit(1).widgetAccentable()
                    Text(entry.pose == .pet ? "❤️ carinho!" : entry.pose == .sleep ? "Zzz…" : "\(entry.mood.emoji) \(entry.mood.name)")
                        .font(.caption)
                    Text(d.isEgg ? "\(d.xpToNext ?? 0) XP p/ chocar" : "Nível \(d.level)\(Mood.liveStreak(d.streak, lastActivity: d.lastActivity, now: entry.date) > 0 ? " · 🔥\(Mood.liveStreak(d.streak, lastActivity: d.lastActivity, now: entry.date))" : "")")
                        .font(.caption2)
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .containerBackground(.clear, for: .widget)
    }

    private var lockSprite: some View {
        let p = entry.pose
        return Image(d.sprite)
            .resizable()
            .interpolation(.none)
            .scaledToFit()
            .scaleEffect(x: p == .lookBack ? -1 : 1, y: p == .stretch ? 1.08 : p == .sleep ? 0.94 : 1, anchor: .bottom)
            .rotationEffect(.degrees(p == .wobbleLeft ? -9 : p == .wobbleRight ? 9 : p == .sleep ? 4 : 0), anchor: .bottom)
            .offset(y: p == .hop ? -4 : p == .pet ? -6 : 0)
            .animation(.spring(duration: 0.8, bounce: 0.45), value: p)
    }

    private var home: some View {
        Button(intent: PetIntent()) {
            ZStack {
                VStack(spacing: family == .systemSmall ? 4 : 8) {
                    HStack {
                        Text(d.monsterName).font(family == .systemSmall ? .caption.bold() : .headline)
                        Spacer()
                        Text(entry.mood.emoji)
                    }
                    Spacer(minLength: 0)
                    monster
                    Spacer(minLength: 0)
                    if family != .systemSmall {
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .contentTransition(.opacity)
                    }
                }
            }
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color(red: 0.12, green: 0.16, blue: 0.10), Theme.bg],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    private var caption: String {
        if entry.pose != .pet, let e = d.event(at: entry.date) { return e }
        switch entry.pose {
        case .pet: return "❤️ Obrigado pelo carinho!"
        case .sleep: return "Zzz… (toque para acordar)"
        default: return entry.pets > 0 ? "\(entry.pets) carinho\(entry.pets == 1 ? "" : "s") · toque para mais" : "Toque para fazer carinho"
        }
    }

    private var monster: some View {
        let p = entry.pose
        return ZStack(alignment: .top) {
            // Sombra no chão: encolhe quando ele pula
            Ellipse()
                .fill(.black.opacity(0.35))
                .frame(width: spriteSize * (p == .hop || p == .pet ? 0.45 : 0.6), height: spriteSize * 0.08)
                .offset(y: spriteSize * 0.95)

            Image(d.sprite)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .hueRotation(.degrees(d.hue))
                .saturation(entry.mood == .triste ? 0.35 : entry.mood == .entediado ? 0.7 : 1)
                .frame(width: spriteSize, height: spriteSize)
                .scaleEffect(x: p == .lookBack ? -1 : 1, y: p == .stretch ? 1.08 : p == .sleep ? 0.94 : 1, anchor: .bottom)
                .rotationEffect(.degrees(p == .wobbleLeft ? -9 : p == .wobbleRight ? 9 : p == .sleep ? 4 : 0), anchor: .bottom)
                .offset(y: p == .hop ? -spriteSize * 0.14 : (p == .pet || p == .celebrate) ? -spriteSize * 0.2 : 0)

            if p == .pet {
                Text("❤️").font(.system(size: spriteSize * 0.2)).offset(x: -spriteSize * 0.35, y: -spriteSize * 0.05)
                Text("❤️").font(.system(size: spriteSize * 0.14)).offset(x: spriteSize * 0.38, y: spriteSize * 0.05)
                    .transition(.scale.combined(with: .opacity))
            }
            if p == .celebrate {
                Text("✨").font(.system(size: spriteSize * 0.18)).offset(x: -spriteSize * 0.4, y: -spriteSize * 0.1)
                Text("✨").font(.system(size: spriteSize * 0.14)).offset(x: spriteSize * 0.42, y: spriteSize * 0.12)
                Text("🎉").font(.system(size: spriteSize * 0.16)).offset(x: spriteSize * 0.3, y: -spriteSize * 0.18)
            }
            if p == .sleep {
                Text("z z").font(.system(size: spriteSize * 0.16, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .offset(x: spriteSize * 0.4, y: -spriteSize * 0.05)
            }
        }
        .frame(height: spriteSize)
        .animation(.spring(duration: 0.8, bounce: 0.45), value: p)
    }
}

struct PetWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GymMonstersPet", provider: PetProvider()) { PetView(entry: $0) }
            .configurationDisplayName("Meu bro")
            .description("Seu bro se mexendo na tela de início. Toque para fazer carinho.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular])
    }
}
