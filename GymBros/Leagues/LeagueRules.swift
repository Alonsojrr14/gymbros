import Foundation

// Regras extras de uma liga: verificação do check-in, revisão do dono, pose do dia, pontos por atividade,
// limites de pontuação, metas no lugar do ranking e início da semana. Ficam em `League.settingsRaw` (JSON):
// campo novo entra aqui sem mudar o banco, e o que faltar no JSON fica no padrão.

struct LeagueSettings: Codable, Hashable, Sendable {
    var verification = CheckInVerification.off
    /// O dono aprova cada check-in antes de pontuar
    var reviewRequired = false
    /// Desde quando a revisão está ligada: check-in de antes disso já valia
    var reviewSince: Date?
    /// Toda foto do dia precisa ter a pose sorteada
    var posesEnabled = false
    var limits = ScoringLimits()
    /// Tabela do modo "Pontos por atividade"
    var pointRules: [ActivityPointRule] = []
    /// Sem ranking: só a barra de progresso da meta
    var rankingsDisabled = false
    /// Meta de cada pessoa, na unidade da pontuação (0 = sem meta)
    var individualGoal = 0
    /// Meta de cada time, na unidade da pontuação (0 = sem meta)
    var teamGoal = 0
    /// Primeiro dia da semana do ranking semanal (1 = domingo … 7 = sábado); nil = o do aparelho
    var weekStart: Int?
    /// Quem quer entrar espera o dono aprovar
    var requiresApproval = false
    /// Ids (servidor) de quem modera junto com o dono
    var mods: [String] = []
    /// Ids (servidor) de quem foi banido: não volta nem pelo código
    var banned: [String] = []
    /// Ids de quem o dono tirou da liga (pode voltar pelo código)
    var removed: [String] = []
    /// Pedidos de entrada aceitos e ignorados
    var approved: [String] = []
    var ignored: [String] = []
    /// Desafio criado dentro de um clube (série do clube): quem é do clube participa sem convite
    var parentClub: UUID?
    /// Treino do dia postado pelo dono
    var dailyWorkout: DailyWorkout?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LeagueSettings()
        verification = try c.decodeIfPresent(CheckInVerification.self, forKey: .verification) ?? d.verification
        reviewRequired = try c.decodeIfPresent(Bool.self, forKey: .reviewRequired) ?? d.reviewRequired
        reviewSince = try c.decodeIfPresent(Date.self, forKey: .reviewSince)
        posesEnabled = try c.decodeIfPresent(Bool.self, forKey: .posesEnabled) ?? d.posesEnabled
        limits = try c.decodeIfPresent(ScoringLimits.self, forKey: .limits) ?? d.limits
        pointRules = try c.decodeIfPresent([ActivityPointRule].self, forKey: .pointRules) ?? d.pointRules
        rankingsDisabled = try c.decodeIfPresent(Bool.self, forKey: .rankingsDisabled) ?? d.rankingsDisabled
        individualGoal = try c.decodeIfPresent(Int.self, forKey: .individualGoal) ?? d.individualGoal
        teamGoal = try c.decodeIfPresent(Int.self, forKey: .teamGoal) ?? d.teamGoal
        weekStart = try c.decodeIfPresent(Int.self, forKey: .weekStart)
        requiresApproval = try c.decodeIfPresent(Bool.self, forKey: .requiresApproval) ?? d.requiresApproval
        mods = try c.decodeIfPresent([String].self, forKey: .mods) ?? d.mods
        banned = try c.decodeIfPresent([String].self, forKey: .banned) ?? d.banned
        removed = try c.decodeIfPresent([String].self, forKey: .removed) ?? d.removed
        approved = try c.decodeIfPresent([String].self, forKey: .approved) ?? d.approved
        ignored = try c.decodeIfPresent([String].self, forKey: .ignored) ?? d.ignored
        parentClub = try c.decodeIfPresent(UUID.self, forKey: .parentClub)
        dailyWorkout = try c.decodeIfPresent(DailyWorkout.self, forKey: .dailyWorkout)
    }

    /// Liga criada agora: verificação padrão ligada (ligas antigas, sem o campo, continuam sem verificação)
    static var newLeague: LeagueSettings {
        var s = LeagueSettings()
        s.verification = .padrao
        return s
    }

    init(rawValue: String) {
        self = rawValue.isEmpty ? LeagueSettings() : ((try? JSONDecoder().decode(LeagueSettings.self, from: Data(rawValue.utf8))) ?? LeagueSettings())
    }

    var rawValue: String {
        guard self != LeagueSettings() else { return "" }
        let e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        e.dateEncodingStrategy = .deferredToDate
        return (try? e.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    /// Calendário do ranking semanal, com o início da semana da liga
    func calendar(_ base: Calendar = .current) -> Calendar {
        var cal = base
        if let weekStart, (1...7).contains(weekStart) { cal.firstWeekday = weekStart }
        return cal
    }
}

// MARK: - Verificação

/// Conjunto pronto de regras de verificação
enum VerificationPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case off, padrao, verificado, personalizado

    var id: String { rawValue }

    var name: String {
        switch self {
        case .off: "Desligada"
        case .padrao: "Padrão"
        case .verificado: "Bro-verificação"
        case .personalizado: "Personalizar"
        }
    }

    var detail: String {
        switch self {
        case .off: "Nenhuma regra: qualquer check-in vale, com ou sem prova."
        case .padrao: "A experiência clássica: foto da câmera ou da galeria, e dá para postar treino de qualquer dia."
        case .verificado: "Equilíbrio recomendado entre justiça e facilidade: check-in só no mesmo dia e foto da galeria só com hora verificada."
        case .personalizado: "Monte suas próprias regras."
        }
    }
}

/// Quando a foto (ou o vídeo) é obrigatória
enum MediaPolicy: String, Codable, CaseIterable, Identifiable, Sendable {
    case always = "always_required", deviceOptional = "device_optional", never = "never_required"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .always: "Sempre"
        case .deviceOptional: "Dispensa com aparelho"
        case .never: "Opcional"
        }
    }

    var detail: String {
        switch self {
        case .always: "Foto é obrigatória em todo check-in."
        case .deviceOptional: "Foto não é obrigatória quando o treino foi gravado por um aparelho (Apple Watch, Apple Saúde ou GPS do app) ou numa visita verificada na academia."
        case .never: "Foto é opcional."
        }
    }
}

/// Quando uma foto da galeria pode ir no check-in
enum LibraryMediaPolicy: String, Codable, CaseIterable, Identifiable, Sendable {
    case allowAll = "allow_all", verifiedOnly = "verified_only", disabled

    var id: String { rawValue }

    var name: String {
        switch self {
        case .allowAll: "Liberada"
        case .verifiedOnly: "Só verificada"
        case .disabled: "Proibida"
        }
    }

    var detail: String {
        switch self {
        case .allowAll: "Qualquer foto da galeria pode ir no check-in."
        case .verifiedOnly: "Foto da galeria só se a hora dela for válida: tirada no mesmo dia do treino, e não depois de agora."
        case .disabled: "Nunca da galeria: a foto tem que ser tirada na câmera do app."
        }
    }
}

/// Quanto a hora do check-in pode se afastar da hora verificada (da foto ou do aparelho)
enum CheckInTimePolicy: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, sameDay = "same_day", strict

    var id: String { rawValue }

    var name: String {
        switch self {
        case .none: "Livre"
        case .sameDay: "Mesmo dia"
        case .strict: "Exata"
        }
    }

    var detail: String {
        switch self {
        case .none: "Sem restrição de horário."
        case .sameDay: "O treino tem que ser do mesmo dia da foto ou do aparelho; a hora pode mudar."
        case .strict: "O horário do treino tem que bater com o da foto ou do aparelho."
        }
    }
}

struct CheckInVerification: Codable, Hashable, Sendable {
    var preset: VerificationPreset
    var media: MediaPolicy
    var library: LibraryMediaPolicy
    var time: CheckInTimePolicy
    /// Quantos dias para trás dá para postar: -1 = qualquer data, 0 = só hoje
    var backlogDays: Int
    var locationRequired: Bool
    var deviceRequired: Bool

    static let off = CheckInVerification(preset: .off, media: .never, library: .allowAll, time: .none, backlogDays: -1,
                                         locationRequired: false, deviceRequired: false)
    static let padrao = CheckInVerification(preset: .padrao, media: .deviceOptional, library: .allowAll, time: .none, backlogDays: -1,
                                            locationRequired: false, deviceRequired: false)
    static let verificado = CheckInVerification(preset: .verificado, media: .deviceOptional, library: .verifiedOnly, time: .none,
                                                backlogDays: 0, locationRequired: false, deviceRequired: false)

    static func preset(_ p: VerificationPreset) -> CheckInVerification {
        switch p {
        case .off: .off
        case .padrao: .padrao
        case .verificado: .verificado
        // Personalizar começa do padrão
        case .personalizado: { var v = padrao; v.preset = .personalizado; return v }()
        }
    }

    static let backlogOptions = [0, 1, 7, 30, -1]

    static func backlogName(_ days: Int) -> String {
        switch days {
        case 0: "Só hoje"
        case 1: "1 dia"
        case -1: "Qualquer"
        default: "\(days) dias"
        }
    }

    /// Resumo das regras em tópicos, como na tela de cada preset
    var bullets: [String] {
        guard preset != .off else { return ["Qualquer check-in vale, com ou sem prova"] }
        var out: [String] = []
        switch media {
        case .always: out.append("Foto sempre obrigatória")
        case .deviceOptional: out.append("Foto dispensada quando o treino foi gravado por um aparelho")
        case .never: out.append("Foto opcional")
        }
        switch library {
        case .allowAll: out.append("Câmera do app e galeria liberadas")
        case .verifiedOnly: out.append("Câmera do app liberada; galeria só com hora verificada")
        case .disabled: out.append("Só a câmera do app: galeria proibida")
        }
        switch time {
        case .none: break
        case .sameDay: out.append("O treino tem que ser do mesmo dia da foto ou do aparelho")
        case .strict: out.append("O horário do treino tem que bater com o da foto ou do aparelho")
        }
        switch backlogDays {
        case -1: out.append("Pode postar treino de qualquer data")
        case 0: out.append("Só no mesmo dia: nada retroativo")
        case 1: out.append("Pode postar treino de até o dia anterior")
        default: out.append("Pode postar treino de até \(backlogDays) dias atrás")
        }
        if deviceRequired { out.append("Treino gravado por aparelho é obrigatório") }
        if locationRequired { out.append("O check-in precisa ter local") }
        return out
    }

    /// Margem do horário "exato": a foto ou o aparelho podem ser até meia hora antes do início ou uma hora depois do fim
    static let strictBefore: TimeInterval = 30 * 60
    static let strictAfter: TimeInterval = 60 * 60

    /// O que impede o check-in nesta liga, na ordem em que a pessoa resolve (vazio = pode postar)
    func problems(_ s: PostSubject, now: Date = .now, calendar cal: Calendar = .current) -> [VerificationProblem] {
        guard preset != .off else { return [] }
        var out: [VerificationProblem] = []
        let photo = s.photo
        // Prova
        switch media {
        case .always where photo == nil:
            out.append(.init(kind: .media, message: "Foto obrigatória.", fix: "adicione uma foto"))
        case .deviceOptional where photo == nil && !s.deviceRecorded && s.gymVisit == nil:
            out.append(.init(kind: .media, message: "Precisa de foto, de treino gravado por aparelho ou de visita verificada na academia.", fix: "adicione uma foto"))
        default: break
        }
        // Galeria
        if let photo, photo.source == .library {
            switch library {
            case .allowAll: break
            case .disabled:
                out.append(.init(kind: .library, message: "Foto da galeria não vale aqui.", fix: "tire a foto na câmera do app"))
            case .verifiedOnly:
                if !photo.timeIsValid(for: s.date, now: now, calendar: cal) {
                    out.append(.init(kind: .library, message: photo.takenAt == nil ? "Foto da galeria sem hora verificada."
                                                                                   : "A foto da galeria não é do dia do treino.",
                                     fix: "tire a foto na câmera do app"))
                }
            }
        }
        // Horário
        if time != .none {
            let verified = s.verifiedTimes(now: now)
            if verified.isEmpty {
                out.append(.init(kind: .time, message: "Sem hora verificada: precisa de foto ou de treino gravado por aparelho.",
                                 fix: "adicione uma foto"))
            } else if time == .sameDay, !verified.contains(where: { cal.isDate($0, inSameDayAs: s.date) }) {
                out.append(.init(kind: .time, message: "O treino não é do mesmo dia da foto ou do aparelho.", fix: "corrija a data do treino"))
            } else if time == .strict, !verified.contains(where: { s.fits($0) }) {
                out.append(.init(kind: .time, message: "O horário do treino não bate com o da foto ou do aparelho.", fix: "corrija o horário do treino"))
            }
        }
        // Retroativo
        if backlogDays >= 0 {
            let limit = cal.date(byAdding: .day, value: -backlogDays, to: cal.startOfDay(for: now))!
            if s.date < limit {
                out.append(.init(kind: .backlog, message: backlogDays == 0 ? "Só vale treino de hoje." : "Só vale treino de até \(Self.backlogName(backlogDays)) atrás.",
                                 fix: "escolha um treino mais recente"))
            }
        }
        if deviceRequired && !s.deviceRecorded {
            out.append(.init(kind: .device, message: "Precisa ser um treino gravado por aparelho.", fix: "importe o treino do Apple Saúde ou do Apple Watch"))
        }
        if locationRequired && !s.hasLocation {
            out.append(.init(kind: .location, message: "O check-in precisa ter local.", fix: "poste da academia ou use uma foto com local"))
        }
        return out
    }
}

struct VerificationProblem: Hashable, Sendable {
    enum Kind: String, Sendable { case media, library, time, backlog, device, location }
    let kind: Kind
    let message: String
    /// Como resolver, para a frase "Para resolver, X ou desmarque esta liga."
    let fix: String
}

/// O treino que vai ser postado, com o que serve de prova
struct PostSubject: Sendable {
    var workoutTypeID: UInt?
    /// Início do treino
    var date: Date
    var minutes: Int
    /// Gravado por aparelho: importado do Apple Saúde, do Apple Watch ou com GPS do app
    var deviceRecorded = false
    var place: String?
    var photo: PhotoProof?
    /// Academia em que a localização do iPhone registrou uma visita durante o treino (visita verificada)
    var gymVisit: String?

    var hasLocation: Bool { place != nil || gymVisit != nil || photo?.hasLocation == true }

    /// Horas que valem como verificadas: a do aparelho (o próprio treino), a da foto da galeria, ou a do post para a câmera do app
    func verifiedTimes(now: Date) -> [Date] {
        var out: [Date] = []
        // Gravado por aparelho ou dentro de uma visita verificada na academia: a hora do treino vale
        if deviceRecorded || gymVisit != nil { out.append(date) }
        if let photo {
            switch photo.source {
            case .camera: out.append(photo.takenAt ?? now)
            case .library: if let t = photo.takenAt { out.append(t) }
            }
        }
        return out
    }

    /// A hora verificada cai dentro do treino (com a margem do "exato")
    func fits(_ t: Date) -> Bool {
        t >= date.addingTimeInterval(-CheckInVerification.strictBefore)
            && t <= date.addingTimeInterval(TimeInterval(minutes * 60) + CheckInVerification.strictAfter)
    }
}

// MARK: - Pose do dia

/// Uma pose sorteada por dia, igual em todos os aparelhos
struct DailyPose: Hashable, Sendable {
    let id: String
    let name: String
    let emoji: String

    static let all: [DailyPose] = [
        DailyPose(id: "biceps", name: "Duplo bíceps", emoji: "💪"),
        DailyPose(id: "joinha", name: "Joinha com as duas mãos", emoji: "👍"),
        DailyPose(id: "paz", name: "Sinal de paz", emoji: "✌️"),
        DailyPose(id: "rock", name: "Mãozinha do rock", emoji: "🤘"),
        DailyPose(id: "coracao", name: "Coração com as mãos", emoji: "🫶"),
        DailyPose(id: "pensador", name: "Pose do pensador", emoji: "🤔"),
        DailyPose(id: "flexao", name: "Uma mão no chão", emoji: "🖐️"),
        DailyPose(id: "lingua", name: "Língua para fora", emoji: "😛"),
        DailyPose(id: "aceno", name: "Tchauzinho", emoji: "👋"),
        DailyPose(id: "olhos", name: "Mão na testa, olhando longe", emoji: "🫡"),
        DailyPose(id: "tres", name: "Três dedos para cima", emoji: "🤟"),
        DailyPose(id: "punho", name: "Punho cerrado no alto", emoji: "✊"),
        DailyPose(id: "careta", name: "Careta de esforço", emoji: "😤"),
        DailyPose(id: "sentado", name: "Sentado no chão", emoji: "🧘"),
    ]

    static func byID(_ id: String?) -> DailyPose? { all.first { $0.id == id } }

    static func of(_ day: Date, calendar: Calendar = .current) -> DailyPose {
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        var rng = SeededRandom(seed: "pose-\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)")
        return all[Int(rng.next() * Double(all.count)) % all.count]
    }

    static var today: DailyPose { of(.now) }
}

// MARK: - Pontos por atividade

/// Linha da tabela do modo "Pontos por atividade": vale para tipos de treino ou para seções inteiras do catálogo
struct ActivityPointRule: Codable, Hashable, Identifiable, Sendable {
    enum Method: String, Codable, CaseIterable, Identifiable, Sendable {
        /// N pontos toda vez que registra
        case perCheckIn
        /// 1 ponto (ou N) a cada X minutos, km ou kcal
        case perAmount

        var id: String { rawValue }
        var name: String { self == .perCheckIn ? "Por vez" : "Por quantidade" }
    }

    enum Metric: String, Codable, CaseIterable, Identifiable, Sendable {
        case minutes, km, kcal

        var id: String { rawValue }
        var name: String {
            switch self {
            case .minutes: "min"
            case .km: "km"
            case .kcal: "kcal"
            }
        }
    }

    var id = UUID().uuidString
    /// Tipos do catálogo (`WorkoutType.id`)
    var workoutTypeIDs: [UInt] = []
    /// Seções do catálogo (`WorkoutType.Section.rawValue`)
    var sections: [String] = []
    var method: Method = .perCheckIn
    /// Pontos ganhos (negativo = perde pontos)
    var points = 1
    /// No "por quantidade": a cada quanto
    var every = 30
    var metric: Metric = .minutes

    func matches(_ typeID: UInt?) -> Bool {
        guard let typeID else { return false }
        if workoutTypeIDs.contains(typeID) { return true }
        guard let section = WorkoutType.byID(typeID)?.section.rawValue else { return false }
        return sections.contains(section)
    }

    /// Mais específico primeiro: tipo antes de seção
    var specificity: Int { workoutTypeIDs.isEmpty ? 0 : 1 }

    func score(_ i: ScoreInput) -> Int {
        switch method {
        case .perCheckIn: return points
        case .perAmount:
            let amount: Double = switch metric {
            case .minutes: Double(min(i.minutes, Game.maxMinutes))
            case .km: (i.meters ?? 0) / 1000
            case .kcal: i.kcal ?? HealthSync.activeKcal(kind: i.kind, minutes: i.minutes, effort: i.effort, weight: LeagueScoring.referenceWeight)
            }
            guard every > 0 else { return 0 }
            return Int((amount / Double(every)).rounded(.down)) * points
        }
    }

    /// "10 pts por vez", "1 pt a cada 30 min", "−5 pts por vez"
    var summary: String {
        let pts = "\(points) pt\(abs(points) == 1 ? "" : "s")".replacingOccurrences(of: "-", with: "−")
        return method == .perCheckIn ? "\(pts) por vez" : "\(pts) a cada \(every) \(metric.name)"
    }

    var targetName: String {
        let names = workoutTypeIDs.compactMap { WorkoutType.byID($0)?.name } + sections
        return names.isEmpty ? "Nenhum treino" : names.joined(separator: ", ")
    }
}

extension Array where Element == ActivityPointRule {
    /// Pontos de um check-in pela tabela; treino fora da tabela vale 0
    func score(_ i: ScoreInput) -> Int {
        filter { $0.matches(i.workoutTypeID) }.max { $0.specificity < $1.specificity }?.score(i) ?? 0
    }
}

// MARK: - Limites de pontuação

enum LimitPeriod: String, Codable, CaseIterable, Identifiable, Sendable {
    case day, week, month, total

    var id: String { rawValue }

    var name: String {
        switch self {
        case .day: "Por dia"
        case .week: "Por semana"
        case .month: "Por mês"
        case .total: "Total"
        }
    }

    func key(_ d: Date, calendar: Calendar) -> Date {
        switch self {
        case .day: calendar.startOfDay(for: d)
        case .week: calendar.dateInterval(of: .weekOfYear, for: d)?.start ?? d
        case .month: calendar.dateInterval(of: .month, for: d)?.start ?? d
        case .total: .distantPast
        }
    }
}

/// Teto de pontos por período, para cada pessoa e para cada time (0 = sem teto)
struct ScoringLimits: Codable, Hashable, Sendable {
    var individual: [LimitPeriod: Int] = [:]
    var team: [LimitPeriod: Int] = [:]

    var isEnabled: Bool { individual.values.contains { $0 > 0 } || team.values.contains { $0 > 0 } }

    /// Corta os pontos que passam do teto, do check-in mais antigo para o mais novo. `group` diz de quem é o placar.
    static func apply(_ caps: [LimitPeriod: Int], to items: [FeedItem], group: (FeedItem) -> String?, calendar: Calendar) -> [String: Int] {
        let caps = caps.filter { $0.value > 0 }
        guard !caps.isEmpty else { return [:] }
        var used: [String: Int] = [:]
        var cut: [String: Int] = [:]
        for item in items.sorted(by: { $0.date < $1.date }) where item.score > 0 {
            guard let g = group(item) else { continue }
            var allowed = item.score
            for (period, cap) in caps {
                let k = "\(g)|\(period.rawValue)|\(period.key(item.date, calendar: calendar).timeIntervalSince1970)"
                allowed = min(allowed, max(cap - used[k, default: 0], 0))
            }
            for period in caps.keys {
                let k = "\(g)|\(period.rawValue)|\(period.key(item.date, calendar: calendar).timeIntervalSince1970)"
                used[k, default: 0] += allowed
            }
            if allowed < item.score { cut[item.id] = item.score - allowed }
        }
        return cut
    }

    var summary: [String] {
        let ind = LimitPeriod.allCases.compactMap { p in individual[p].flatMap { $0 > 0 ? "\(p.name.lowercased()) \($0)" : nil } }
        let tm = LimitPeriod.allCases.compactMap { p in team[p].flatMap { $0 > 0 ? "\(p.name.lowercased()) \($0)" : nil } }
        return (ind.isEmpty ? [] : ["Teto por pessoa: " + ind.joined(separator: ", ")]) + (tm.isEmpty ? [] : ["Teto por time: " + tm.joined(separator: ", ")])
    }
}

/// Estado de revisão gravado no seu check-in (`LeagueCheckIn.reviewRaw`)
enum ReviewState {
    static let pending = "pending"
    static let denied = "denied"
}

/// Treino do dia da liga: o dono escolhe os exercícios (ou cola o WOD) e todo mundo começa com um toque
struct DailyWorkout: Codable, Hashable, Sendable {
    struct Item: Codable, Hashable, Sendable {
        var exerciseID: String
        var sets: Int
        var reps: Int
    }

    var day: Date
    var title: String
    var items: [Item] = []
    /// Texto livre (WOD do coach, observações)
    var note = ""

    var isToday: Bool { Calendar.current.isDateInToday(day) }
}
