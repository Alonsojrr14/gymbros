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
    /// Monstro que representa o jogador nesta liga (recebe o XP dos check-ins dela)
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
        self.start = Calendar.current.startOfDay(for: start)
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

    /// Pontos de um check-in nesta liga
    func score(_ i: ScoreInput, hasPhoto: Bool = true) -> Int {
        photoRule.apply(scoring.score(i, weights: scoring == .pontos ? attributeWeights : [:]), hasPhoto: hasPhoto)
    }

    var isOver: Bool { end.map { $0 < .now } ?? false }

    /// Dias que faltam, contando hoje (nil = sem fim)
    var daysLeft: Int? {
        guard let end else { return nil }
        let cal = Calendar.current
        return max(0, (cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: end)).day ?? 0) + 1)
    }

    var hasStarted: Bool { start <= .now }

    /// Identifica a série de temporadas
    var seriesKey: UUID { seriesID ?? uuid }

    /// Já virou temporada passada (existe uma seguinte)
    var isPastSeason: Bool { nextUUID != nil }

    /// Dias até começar (0 se já começou)
    var daysToStart: Int {
        let cal = Calendar.current
        return max(0, cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: start)).day ?? 0)
    }

    /// "começa hoje", "começa amanhã", "começa em 3 dias" (minúsculo, para ir no meio da frase)
    static func startsText(_ start: Date) -> String {
        let cal = Calendar.current
        let n = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: start)).day ?? 0
        switch n {
        case ..<0: return "já começou"
        case 0: return "começa hoje"
        case 1: return "começa amanhã"
        default: return "começa em \(n) dias"
        }
    }

    /// Período escolhido no calendário: do começo do dia de início ao fim do dia final (nil = sem fim)
    func setPeriod(start s: Date, end e: Date?) {
        let cal = Calendar.current
        start = cal.startOfDay(for: s)
        end = e.map { cal.date(byAdding: .second, value: -1, to: cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: max($0, s)))!)! }
    }

    /// Define a duração em dias a partir do início (0 = sem fim)
    func setDuration(days: Int) {
        let cal = Calendar.current
        end = days > 0 ? cal.date(byAdding: .second, value: -1, to: cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: start))!) : nil
    }

    var durationDays: Int {
        guard let end else { return 0 }
        let cal = Calendar.current
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

    /// Vale como check-in com foto na regra da liga
    var hasPhoto: Bool { photo != nil || hadPhoto }

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
}
