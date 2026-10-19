import HealthKit
import SwiftData
import SwiftUI

/// Um tipo de treino do Apple Saúde, com nome e ícone em português.
/// A categoria do app (`ActivityKind`) continua existindo para espécie, ligas e XP; o tipo é o que a pessoa escolheu.
struct WorkoutType: Identifiable, Hashable {
    let type: HKWorkoutActivityType
    let name: String
    let symbol: String
    let section: Section
    /// Outros nomes para a busca
    var aliases: [String] = []

    var id: UInt { type.rawValue }
    var kind: ActivityKind { HealthSync.kind(for: type) }

    enum Section: String, CaseIterable {
        case academia = "Academia e funcional"
        case corrida = "Corrida e caminhada"
        case bike = "Ciclismo"
        case agua = "Na água"
        case bola = "Esportes com bola"
        case raquete = "Raquete"
        case lutas = "Lutas"
        case corpo = "Dança, corpo e mente"
        case neve = "Neve e gelo"
        case livre = "Ao ar livre e outros"
    }

    static func byID(_ raw: UInt?) -> WorkoutType? { raw.flatMap { index[$0] } }
    static func byID(_ raw: Int?) -> WorkoutType? { byID(raw.map(UInt.init)) }
    private static let index = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    /// O tipo equivalente às categorias antigas do app
    static func of(_ kind: ActivityKind) -> WorkoutType { byID(HealthSync.activityType(kind).rawValue) ?? other }
    static let other = WorkoutType(type: .other, name: "Outro", symbol: "figure.mixed.cardio", section: .livre)

    static let all: [WorkoutType] = [
        // Academia e funcional
        .init(type: .traditionalStrengthTraining, name: "Musculação", symbol: "figure.strengthtraining.traditional", section: .academia, aliases: ["academia", "peso", "força"]),
        .init(type: .functionalStrengthTraining, name: "Treino funcional", symbol: "figure.strengthtraining.functional", section: .academia, aliases: ["funcional"]),
        .init(type: .crossTraining, name: "Crossfit", symbol: "figure.cross.training", section: .academia, aliases: ["cross training", "wod"]),
        .init(type: .highIntensityIntervalTraining, name: "HIIT", symbol: "figure.highintensity.intervaltraining", section: .academia, aliases: ["intervalado", "tabata"]),
        .init(type: .coreTraining, name: "Core", symbol: "figure.core.training", section: .academia, aliases: ["abdômen", "abdominal"]),
        .init(type: .mixedCardio, name: "Cardio misto", symbol: "figure.mixed.cardio", section: .academia, aliases: ["aeróbico"]),
        .init(type: .elliptical, name: "Elíptico", symbol: "figure.elliptical", section: .academia, aliases: ["transport"]),
        .init(type: .stairClimbing, name: "Escada (aparelho)", symbol: "figure.stair.stepper", section: .academia, aliases: ["stair", "simulador de escada"]),
        .init(type: .stepTraining, name: "Step", symbol: "figure.step.training", section: .academia),
        .init(type: .jumpRope, name: "Pular corda", symbol: "figure.jumprope", section: .academia, aliases: ["corda"]),
        .init(type: .gymnastics, name: "Ginástica", symbol: "figure.gymnastics", section: .academia, aliases: ["calistenia"]),
        .init(type: .fitnessGaming, name: "Jogos fitness", symbol: "gamecontroller.fill", section: .academia, aliases: ["videogame"]),
        .init(type: .cooldown, name: "Desaquecimento", symbol: "figure.cooldown", section: .academia, aliases: ["cooldown"]),
        .init(type: .preparationAndRecovery, name: "Preparação e recuperação", symbol: "figure.flexibility", section: .academia, aliases: ["mobilidade", "recovery"]),
        // Corrida e caminhada
        .init(type: .running, name: "Corrida", symbol: "figure.run", section: .corrida, aliases: ["correr", "running"]),
        .init(type: .walking, name: "Caminhada", symbol: "figure.walk", section: .corrida, aliases: ["andar"]),
        .init(type: .hiking, name: "Trilha", symbol: "figure.hiking", section: .corrida, aliases: ["hiking", "montanha"]),
        .init(type: .trackAndField, name: "Atletismo", symbol: "figure.track.and.field", section: .corrida, aliases: ["pista"]),
        .init(type: .stairs, name: "Escadas", symbol: "figure.stairs", section: .corrida, aliases: ["subir escada"]),
        .init(type: .wheelchairWalkPace, name: "Cadeira de rodas (caminhada)", symbol: "figure.roll", section: .corrida),
        .init(type: .wheelchairRunPace, name: "Cadeira de rodas (corrida)", symbol: "figure.roll.runningpace", section: .corrida),
        // Ciclismo
        .init(type: .cycling, name: "Bike", symbol: "figure.outdoor.cycle", section: .bike, aliases: ["ciclismo", "bicicleta", "pedal", "spinning"]),
        .init(type: .handCycling, name: "Handbike", symbol: "figure.hand.cycling", section: .bike),
        .init(type: .swimBikeRun, name: "Triatlo", symbol: "figure.open.water.swim", section: .bike, aliases: ["triathlon"]),
        // Na água
        .init(type: .swimming, name: "Natação", symbol: "figure.pool.swim", section: .agua, aliases: ["nadar", "piscina"]),
        .init(type: .waterFitness, name: "Hidroginástica", symbol: "figure.water.fitness", section: .agua),
        .init(type: .waterPolo, name: "Polo aquático", symbol: "figure.waterpolo", section: .agua),
        .init(type: .surfingSports, name: "Surfe", symbol: "figure.surfing", section: .agua, aliases: ["surf", "bodyboard", "kitesurf"]),
        .init(type: .paddleSports, name: "Remo e caiaque", symbol: "oar.2.crossed", section: .agua, aliases: ["stand up paddle", "sup", "canoa"]),
        .init(type: .rowing, name: "Remo", symbol: "figure.rower", section: .agua, aliases: ["remo ergômetro"]),
        .init(type: .sailing, name: "Vela", symbol: "figure.sailing", section: .agua, aliases: ["velejar"]),
        .init(type: .waterSports, name: "Esportes aquáticos", symbol: "water.waves", section: .agua, aliases: ["jet ski", "wakeboard"]),
        .init(type: .underwaterDiving, name: "Mergulho", symbol: "water.waves.and.arrow.down", section: .agua),
        // Esportes com bola
        .init(type: .soccer, name: "Futebol", symbol: "figure.soccer", section: .bola, aliases: ["futsal", "society", "pelada"]),
        .init(type: .volleyball, name: "Vôlei", symbol: "figure.volleyball", section: .bola, aliases: ["volei de praia", "futevôlei"]),
        .init(type: .basketball, name: "Basquete", symbol: "figure.basketball", section: .bola),
        .init(type: .handball, name: "Handebol", symbol: "figure.handball", section: .bola),
        .init(type: .americanFootball, name: "Futebol americano", symbol: "figure.american.football", section: .bola),
        .init(type: .australianFootball, name: "Futebol australiano", symbol: "figure.australian.football", section: .bola),
        .init(type: .rugby, name: "Rugby", symbol: "figure.rugby", section: .bola),
        .init(type: .baseball, name: "Beisebol", symbol: "figure.baseball", section: .bola),
        .init(type: .softball, name: "Softbol", symbol: "figure.softball", section: .bola),
        .init(type: .cricket, name: "Críquete", symbol: "figure.cricket", section: .bola),
        .init(type: .hockey, name: "Hóquei", symbol: "figure.hockey", section: .bola),
        .init(type: .lacrosse, name: "Lacrosse", symbol: "figure.lacrosse", section: .bola),
        .init(type: .discSports, name: "Frisbee", symbol: "figure.disc.sports", section: .bola, aliases: ["ultimate"]),
        .init(type: .golf, name: "Golfe", symbol: "figure.golf", section: .bola),
        .init(type: .bowling, name: "Boliche", symbol: "figure.bowling", section: .bola),
        // Raquete
        .init(type: .tennis, name: "Tênis", symbol: "figure.tennis", section: .raquete, aliases: ["beach tennis"]),
        .init(type: .pickleball, name: "Pickleball", symbol: "figure.pickleball", section: .raquete, aliases: ["padel"]),
        .init(type: .squash, name: "Squash", symbol: "figure.squash", section: .raquete),
        .init(type: .racquetball, name: "Raquetebol", symbol: "figure.racquetball", section: .raquete),
        .init(type: .badminton, name: "Badminton", symbol: "figure.badminton", section: .raquete),
        .init(type: .tableTennis, name: "Tênis de mesa", symbol: "figure.table.tennis", section: .raquete, aliases: ["pingue-pongue", "ping pong"]),
        // Lutas
        .init(type: .martialArts, name: "Artes marciais", symbol: "figure.martial.arts", section: .lutas, aliases: ["jiu-jitsu", "judô", "karatê", "taekwondo", "muay thai", "lutas"]),
        .init(type: .boxing, name: "Boxe", symbol: "figure.boxing", section: .lutas),
        .init(type: .kickboxing, name: "Kickboxing", symbol: "figure.kickboxing", section: .lutas, aliases: ["muay thai"]),
        .init(type: .wrestling, name: "Luta livre", symbol: "figure.wrestling", section: .lutas, aliases: ["wrestling", "mma"]),
        .init(type: .fencing, name: "Esgrima", symbol: "figure.fencing", section: .lutas),
        // Dança, corpo e mente
        .init(type: .cardioDance, name: "Dança", symbol: "figure.dance", section: .corpo, aliases: ["zumba", "fit dance"]),
        .init(type: .socialDance, name: "Dança de salão", symbol: "figure.socialdance", section: .corpo, aliases: ["forró", "samba", "salsa"]),
        .init(type: .barre, name: "Barre", symbol: "figure.barre", section: .corpo, aliases: ["balé"]),
        .init(type: .yoga, name: "Yoga", symbol: "figure.yoga", section: .corpo),
        .init(type: .pilates, name: "Pilates", symbol: "figure.pilates", section: .corpo),
        .init(type: .flexibility, name: "Alongamento", symbol: "figure.flexibility", section: .corpo, aliases: ["flexibilidade"]),
        .init(type: .mindAndBody, name: "Corpo e mente", symbol: "figure.mind.and.body", section: .corpo, aliases: ["meditação"]),
        .init(type: .taiChi, name: "Tai chi", symbol: "figure.taichi", section: .corpo),
        // Neve e gelo
        .init(type: .snowSports, name: "Esportes na neve", symbol: "snowflake", section: .neve),
        .init(type: .downhillSkiing, name: "Esqui", symbol: "figure.skiing.downhill", section: .neve),
        .init(type: .crossCountrySkiing, name: "Esqui cross-country", symbol: "figure.skiing.crosscountry", section: .neve),
        .init(type: .snowboarding, name: "Snowboard", symbol: "figure.snowboarding", section: .neve),
        .init(type: .skatingSports, name: "Patinação e skate", symbol: "figure.skating", section: .neve, aliases: ["skate", "patins"]),
        .init(type: .curling, name: "Curling", symbol: "figure.curling", section: .neve),
        // Ao ar livre e outros
        .init(type: .climbing, name: "Escalada", symbol: "figure.climbing", section: .livre, aliases: ["boulder"]),
        .init(type: .equestrianSports, name: "Hipismo", symbol: "figure.equestrian.sports", section: .livre, aliases: ["cavalo"]),
        .init(type: .archery, name: "Arco e flecha", symbol: "figure.archery", section: .livre),
        .init(type: .fishing, name: "Pesca", symbol: "figure.fishing", section: .livre),
        .init(type: .hunting, name: "Caça", symbol: "figure.hunting", section: .livre),
        .init(type: .play, name: "Brincadeiras", symbol: "figure.play", section: .livre, aliases: ["parquinho"]),
        other,
    ]

    /// Os 12 de sempre, na ordem da grade antiga (atalhos de quem ainda não tem histórico)
    static let classics: [WorkoutType] = ActivityKind.allCases.map(of)

    static func search(_ text: String) -> [WorkoutType] {
        let q = fold(text)
        guard !q.isEmpty else { return all }
        return all.filter { t in ([t.name] + t.aliases).contains { fold($0).contains(q) } }
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR")).trimmingCharacters(in: .whitespaces)
    }
}

extension Activity {
    /// Tipo escolhido (ou importado do Saúde); sem ele, o equivalente da categoria
    var workoutType: WorkoutType { WorkoutType.byID(healthType) ?? .of(kind) }
    var typeName: String { workoutType.name }
    var typeSymbol: String { workoutType.symbol }
}

// MARK: - Seletor

/// Atalhos com o que você mais faz e "Todas" para os ~80 tipos do Apple Saúde, com busca
struct ActivityTypePicker: View {
    @Binding var type: UInt
    @Query(sort: \Activity.date, order: .reverse) private var history: [Activity]
    /// Tipos escolhidos por último (ids, mais recente primeiro): entram nos atalhos mesmo antes de salvar
    @AppStorage("recentWorkoutTypes") private var recentRaw = ""
    @State private var browsing = false
    /// Atalhos fixados ao abrir a tela: escolher não reordena nada
    @State private var slots: [UInt] = []

    private var recent: [UInt] { recentRaw.split(separator: ",").compactMap { UInt($0) } }

    /// Os 7 mais frequentes: treinos salvos recentemente + escolhas recentes; os clássicos completam
    private func ranked() -> [UInt] {
        var score: [UInt: Double] = [:]
        for a in history.prefix(60) { score[a.workoutType.id, default: 0] += 1 }
        for (i, id) in recent.prefix(10).enumerated() { score[id, default: 0] += 2 - Double(i) * 0.15 }
        let classics = WorkoutType.classics.map(\.id)
        let used = score.keys.sorted { a, b in
            score[a]! != score[b]! ? score[a]! > score[b]! : (classics.firstIndex(of: a) ?? 99, a) < (classics.firstIndex(of: b) ?? 99, b)
        }
        var out: [UInt] = []
        for id in used + classics where WorkoutType.byID(id) != nil && !out.contains(id) && out.count < 7 { out.append(id) }
        return out
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(slots.compactMap { WorkoutType.byID($0) }) { t in
                tile(t.name, t.symbol, on: t.id == type) { type = t.id }
            }
            tile("Todas", "magnifyingglass", on: false) { browsing = true }
                .accessibilityHint("Abre a lista com todos os tipos de treino")
        }
        .onAppear {
            guard slots.isEmpty else { return }
            slots = ranked()
            place(type)
        }
        .onChange(of: type) { _, t in
            place(t)
            remember(t)
        }
        .sheet(isPresented: $browsing) {
            WorkoutTypeList(selection: $type)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(Theme.radiusXL)
                .presentationBackground(Theme.bg)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }

    /// Escolhido fora dos atalhos: fica no último lugar (e continua lá se você trocar de novo)
    private func place(_ t: UInt) {
        guard !slots.contains(t), !slots.isEmpty else { return }
        slots[slots.count - 1] = t
    }

    private func remember(_ t: UInt) {
        recentRaw = ([t] + recent.filter { $0 != t }).prefix(10).map(String.init).joined(separator: ",")
    }

    private func tile(_ name: String, _ symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.title2).frame(height: 30)
                Text(name).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 66)
            .background(on ? Theme.accent.opacity(0.2) : Theme.raised, in: .rect(cornerRadius: Theme.radiusM))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusM).stroke(on ? Theme.accent : .clear, lineWidth: 1.5))
            .foregroundStyle(on ? Theme.accent : .white)
        }
        .buttonStyle(GMPress())
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Todos os tipos, por seção, com busca
struct WorkoutTypeList: View {
    @Binding var selection: UInt
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            let found = WorkoutType.search(query)
            List {
                ForEach(WorkoutType.Section.allCases, id: \.self) { section in
                    let items = found.filter { $0.section == section }
                    if !items.isEmpty {
                        SwiftUI.Section(section.rawValue) {
                            ForEach(items) { t in row(t) }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .overlay {
                if found.isEmpty { ContentUnavailableView.search(text: query) }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Buscar treino")
            .navigationTitle("Tipo de treino")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } }
            }
        }
    }

    private func row(_ t: WorkoutType) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            selection = t.id
            dismiss()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: t.symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(t.id == selection ? .black : Theme.accent)
                    .frame(width: 36, height: 36)
                    .background(t.id == selection ? Theme.accent : Theme.accent.opacity(0.15), in: .rect(cornerRadius: Theme.radiusS))
                Text(t.name).foregroundStyle(.white)
                Spacer()
                if t.id == selection { Image(systemName: "checkmark").font(.body.bold()).foregroundStyle(Theme.accent) }
            }
        }
        .listRowBackground(Theme.card)
        .accessibilityAddTraits(t.id == selection ? .isSelected : [])
    }
}
