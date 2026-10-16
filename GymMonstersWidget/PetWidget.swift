import AppIntents
import SwiftUI
import WidgetKit

// Widget "bichinho": o monstro em destaque, mudando de pose a cada minuto (com transição
// animada) e reagindo a carinho com um toque. Widgets não rodam animação contínua; cada
// pose é uma entrada da timeline e o iOS anima a troca entre elas.

enum Pose: Int {
    case idle, hop, lookBack, stretch, sleep, pet, wobbleLeft, wobbleRight
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
    static var description = IntentDescription("Faz carinho no seu GymMonster.")

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
        let cycle: [Pose]
        switch mood {
        case .ovo: cycle = [.idle, .wobbleLeft, .idle, .wobbleRight, .idle, .wobbleLeft]
        case .triste, .entediado, .exausto: cycle = [.idle, .sleep, .sleep, .idle, .stretch, .sleep]
        default: cycle = [.idle, .hop, .idle, .lookBack, .idle, .stretch, .hop, .idle]
        }
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
            LinearGradient(colors: [Color(red: 0.12, green: 0.16, blue: 0.10), Color(red: 0.05, green: 0.06, blue: 0.08)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    private var caption: String {
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
                .offset(y: p == .hop ? -spriteSize * 0.14 : p == .pet ? -spriteSize * 0.2 : 0)

            if p == .pet {
                Text("❤️").font(.system(size: spriteSize * 0.2)).offset(x: -spriteSize * 0.35, y: -spriteSize * 0.05)
                Text("❤️").font(.system(size: spriteSize * 0.14)).offset(x: spriteSize * 0.38, y: spriteSize * 0.05)
                    .transition(.scale.combined(with: .opacity))
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
            .configurationDisplayName("Meu monstro")
            .description("Seu GymMonster se mexendo na tela de início. Toque para fazer carinho.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
