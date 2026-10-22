import Foundation
import SwiftData

@Model
final class League {
    var uuid: UUID = UUID()
    var name: String = ""
    var emoji: String = "🏆"
    var scoringRaw: String = LeagueScoring.pontos.rawValue
    var start: Date = Date.now
    var code: String = ""
    /// Liga de exemplo, com participantes simulados
    var isMock: Bool = false
    var joinedAt: Date = Date.now
    /// Monstro que representa o jogador nesta liga (recebe parte do XP dos check-ins dela; o principal recebe tudo)
    var monsterUUID: UUID?
    /// Último dia da liga (fim do dia); nil = sem fim
    var end: Date?
    /// Capa da liga
    @Attribute(.externalStorage) var cover: Data?
    /// Renovação automática: ao acabar, começa outra temporada igual
    var autoRenew: Bool = false
    var season: Int = 1
    /// Liga da 1ª temporada (todas as temporadas apontam para ela); nil = esta é a primeira
    var seriesID: UUID?
    /// Temporada seguinte, quando esta já foi renovada
    var nextUUID: UUID?
    /// Multiplicador de cada atributo no modo pontos ("forca:2,tecnica:0"); vazio = 1× em tudo
    var weightsRaw: String = ""
    var tieBreakRaw: String = LeagueTieBreak.primeiro.rawValue
    var photoRuleRaw: String = PhotoRule.livre.rawValue
    /// Tipos de treino aceitos pela liga; vazio = qualquer um.
    var activityRuleRaw: String = ""
    /// Verificação, revisão, pose, limites, metas e moderação (`LeagueSettings` em JSON; vazio = nada ligado) (SchemaV4)
    var settingsRaw: String = ""
    /// Critério da rodada suíça diária (SchemaV2)
    var swissRaw: String = SwissCriterion.pontos.rawValue
    /// Times, um por linha: "id\tnome" (formato antigo: só o nome, id = posição); vazio = liga sem times
    var teamsRaw: String = ""
    /// Quando o servidor recebeu a liga (regras) e o seu lugar nela (nome, bro, time); nil = pendente
    var syncedAt: Date?
    /// Entrou por código numa liga de outra pessoa (não é você quem cria no servidor)
    var joined: Bool = false
    /// Seu time (`LeagueTeam.id`)
    var myTeamID: String?

    init(name: String, emoji: String, scoring: LeagueScoring, start: Date = .now, isMock: Bool = false) {
        self.name = name
        self.emoji = emoji
        self.scoringRaw = scoring.rawValue
        self.start = League.ruleDay(start)
        self.isMock = isMock
        self.code = League.newCode()
    }

    var scoring: LeagueScoring { LeagueScoring(rawValue: scoringRaw) ?? .pontos }

    var tieBreak: LeagueTieBreak {
        get { LeagueTieBreak(rawValue: tieBreakRaw) ?? .primeiro }
        set { tieBreakRaw = newValue.rawValue }
    }

    var photoRule: PhotoRule {
        get { PhotoRule(rawValue: photoRuleRaw) ?? .livre }
        set { photoRuleRaw = newValue.rawValue }
    }

    var swiss: SwissCriterion {
        get { SwissCriterion(rawValue: swissRaw) ?? .pontos }
        set { swissRaw = newValue.rawValue }
    }

    /// Times com id estável: renomear, reordenar ou tirar um time não troca ninguém de time
    var teams: [LeagueTeam] {
        get { LeagueTeams.parse(teamsRaw) }
        set {
            teamsRaw = LeagueTeams.encode(newValue)
            if let t = myTeamID, !teams.contains(where: { $0.id == t }) { myTeamID = nil }
        }
    }

    var teamNames: [String] { teams.map(\.name) }

    var hasTeams: Bool { !teams.isEmpty }

    var activityRule: LeagueActivityRule {
        get { LeagueActivityRule(rawValue: activityRuleRaw) }
        set { activityRuleRaw = newValue.rawValue }
    }

    func accepts(_ workoutType: WorkoutType) -> Bool { activityRule.accepts(workoutType.id) }

    var settings: LeagueSettings {
        get { LeagueSettings(rawValue: settingsRaw) }
        set { settingsRaw = newValue.rawValue }
    }

    /// O que impede postar este treino aqui (tipo que não vale e regras de verificação); vazio = pode
    func problems(_ s: PostSubject, now: Date = .now) -> [VerificationProblem] {
        guard activityRule.accepts(s.workoutTypeID) else {
            let name = s.workoutTypeID.flatMap { WorkoutType.byID($0)?.name } ?? "Este treino"
            return [VerificationProblem(kind: .media, message: "\(name) não vale nesta liga.", fix: "escolha outro treino")]
        }
        return settings.verification.problems(s, now: now)
    }

    /// Clubes não têm fim; desafios sempre têm período definido.
    var format: LeagueFormat { end == nil ? .club : .challenge }

    /// Só os atributos fora de 1×
    var attributeWeights: [Attribute: Double] {
        get {
            weightsRaw.split(separator: ",").reduce(into: [:]) { acc, pair in
                let p = pair.split(separator: ":")
                if p.count == 2, let a = Attribute(rawValue: String(p[0])), let v = Double(p[1]) { acc[a] = v }
            }
        }
        set {
            weightsRaw = Attribute.allCases.compactMap { a in
                newValue[a].flatMap { $0 == 1 ? nil : "\(a.rawValue):\($0.formatted(.number.locale(Locale(identifier: "en_US_POSIX")).grouping(.never)))" }
            }.joined(separator: ",")
        }
    }

    /// Pontos de um check-in nesta liga (antes de limites e de "dias ativos", que dependem dos outros check-ins)
    func score(_ i: ScoreInput, hasPhoto: Bool = true) -> Int {
        guard activityRule.accepts(i.workoutTypeID) else { return 0 }
        let raw = scoring == .atividades ? settings.pointRules.score(i) : scoring.score(i, weights: scoring == .pontos ? attributeWeights : [:])
        // Pontos negativos da tabela não passam pela regra da foto (metade de uma perda continuaria sendo perda)
        return raw < 0 ? raw : photoRule.apply(raw, hasPhoto: hasPhoto)
    }

    var isOver: Bool { end.map { $0 < .now } ?? false }

    /// Dias que faltam, contando hoje (nil = sem fim)
    var daysLeft: Int? {
        guard let end else { return nil }
        let cal = League.rulesCalendar
        return max(0, (cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: end)).day ?? 0) + 1)
    }

    var hasStarted: Bool { start <= .now }

    /// Identifica a série de temporadas
    var seriesKey: UUID { seriesID ?? uuid }

    /// Já virou temporada passada (existe uma seguinte)
    var isPastSeason: Bool { nextUUID != nil }

    /// Dias até começar (0 se já começou)
    var daysToStart: Int {
        let cal = League.rulesCalendar
        return max(0, cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: start)).day ?? 0)
    }

    /// "começa hoje", "começa amanhã", "começa em 3 dias" (minúsculo, para ir no meio da frase)
    static func startsText(_ start: Date) -> String {
        let cal = League.rulesCalendar
        let n = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: start)).day ?? 0
        switch n {
        case ..<0: return "já começou"
        case 0: return "começa hoje"
        case 1: return "começa amanhã"
        default: return "começa em \(n) dias"
        }
    }

    /// O dia que a pessoa escolheu no calendário do aparelho, no calendário das regras (Brasília): mesmo ano, mês e dia.
    /// Converter o instante mudaria o dia para quem está a leste de Brasília (meia-noite local = dia anterior lá).
    static func ruleDay(_ date: Date, from device: Calendar = .current) -> Date {
        let c = device.dateComponents([.year, .month, .day], from: date)
        return rulesCalendar.date(from: DateComponents(year: c.year, month: c.month, day: c.day)) ?? rulesCalendar.startOfDay(for: date)
    }

    /// Período escolhido no calendário: do começo do dia de início ao fim do dia final (nil = sem fim)
    func setPeriod(start s: Date, end e: Date?) {
        let cal = League.rulesCalendar
        start = League.ruleDay(s)
        end = e.map { cal.date(byAdding: .second, value: -1, to: cal.date(byAdding: .day, value: 1, to: League.ruleDay(max($0, s)))!)! }
    }

    /// Define a duração em dias a partir do início (0 = sem fim)
    func setDuration(days: Int) {
        let cal = League.rulesCalendar
        end = days > 0 ? cal.date(byAdding: .second, value: -1, to: cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: start))!) : nil
    }

    var durationDays: Int {
        guard let end else { return 0 }
        let cal = League.rulesCalendar
        return (cal.dateComponents([.day], from: cal.startOfDay(for: start), to: cal.startOfDay(for: end)).day ?? 0) + 1
    }

    static func newCode() -> String {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).map { _ in chars.randomElement()! })
    }
}

@Model
final class LeagueCheckIn {
    var uuid: UUID = UUID()
    var leagueUUID: UUID = UUID()
    var activityUUID: UUID = UUID()
    var title: String = ""
    var note: String = ""
    var date: Date = Date.now
    @Attribute(.externalStorage) var photo: Data?
    /// Onde foi (ex.: nome da academia), quando postado de lá
    var place: String?
    /// Foi postado com foto, mesmo que a imagem não esteja mais aqui (backup restaurado não traz as fotos)
    var hadPhoto: Bool = false
    /// Quando o servidor recebeu esta versão; nil = na caixa de saída (novo ou editado)
    var syncedAt: Date?

    /// Prova do check-in (`CheckInProof` em JSON) (SchemaV4)
    var proofRaw: String = ""
    /// Revisão do dono: "" = não precisa (ou já aprovado), "pending", "denied" (SchemaV4)
    var reviewRaw: String = ""
    /// Fotos além da primeira (até 4), em property list de `[Data]` (SchemaV5)
    @Attribute(.externalStorage) var extraPhotosData: Data?

    /// Todas as fotos do post: a principal e as extras
    var photos: [Data] {
        get { (photo.map { [$0] } ?? []) + (extraPhotosData.flatMap { try? PropertyListDecoder().decode([Data].self, from: $0) } ?? []) }
        set {
            setPhoto(newValue.first)
            let rest = Array(newValue.dropFirst().prefix(4))
            extraPhotosData = rest.isEmpty ? nil : try? PropertyListEncoder().encode(rest)
        }
    }

    /// Vale como check-in com foto na regra da liga
    var hasPhoto: Bool { photo != nil || hadPhoto }

    var proof: CheckInProof {
        get { CheckInProof(rawValue: proofRaw) }
        set { proofRaw = newValue.rawValue }
    }

    init(leagueUUID: UUID, activityUUID: UUID, title: String, note: String, date: Date, photo: Data?) {
        self.leagueUUID = leagueUUID
        self.activityUUID = activityUUID
        self.title = title
        self.note = note
        self.date = date
        self.photo = photo
        self.hadPhoto = photo != nil
    }

    /// Troca a foto do post. Sem imagem guardada (backup restaurado), tirar a foto da edição não apaga o "tinha foto".
    func setPhoto(_ data: Data?) {
        if data == nil && photo == nil { return }
        photo = data
        hadPhoto = data != nil
    }
}

/// Seu recado no mural de uma liga
@Model
final class LeagueMessage {
    var uuid: UUID = UUID()
    var leagueUUID: UUID = UUID()
    var text: String = ""
    var date: Date = Date.now
    /// Quando o servidor aceitou; nil = na caixa de saída
    var syncedAt: Date?
    /// Foto do recado (SchemaV5)
    @Attribute(.externalStorage) var photo: Data?

    init(leagueUUID: UUID, text: String) {
        self.leagueUUID = leagueUUID
        self.text = text
    }
}

/// Comentário (ou reação) num check-in de liga. Por enquanto não chega a outras pessoas (vai só na cópia da conta).
@Model
final class CheckInComment {
    var uuid: UUID = UUID()
    /// `FeedItem.id` do check-in (o seu ou o de um participante simulado)
    var itemID: String = ""
    var text: String = ""
    var date: Date = Date.now
    /// Quem escreveu: "me" (você) ou o `memberID` de outra pessoa. Comentários antigos não tinham autor: são seus.
    var authorID: String = "me"
    /// Nome de quem escreveu quando não é você (o seu vem sempre do nome atual)
    var authorName: String = ""

    init(itemID: String, text: String, authorID: String = "me", authorName: String = "") {
        self.itemID = itemID
        self.text = text
        self.authorID = authorID
        self.authorName = authorName
    }

    var isMine: Bool { authorID == "me" }

    /// Comentário só com emoji é uma reação (👍, 💪…)
    var isReaction: Bool { Self.isReaction(text) }

    static func isReaction(_ s: String) -> Bool {
        s.count <= 3 && s.unicodeScalars.allSatisfy { $0.properties.isEmojiPresentation || $0.properties.isEmoji && $0.value > 0x238C || $0.value == 0x200D || $0.value == 0xFE0F }
    }
}

/// Decisão do dono sobre um check-in de outra pessoa numa liga com revisão (o seu fica no próprio LeagueCheckIn)
@Model
final class CheckInReview {
    var uuid: UUID = UUID()
    var leagueUUID: UUID = UUID()
    /// `FeedItem.id` do check-in
    var itemID: String = ""
    var approved: Bool = true
    var date: Date = Date.now

    init(leagueUUID: UUID, itemID: String, approved: Bool) {
        self.leagueUUID = leagueUUID
        self.itemID = itemID
        self.approved = approved
    }
}
