import PhotosUI
import SwiftData
import SwiftUI
import Vision
#if canImport(FoundationModels)
import FoundationModels
#endif

// Treino do coach: o texto (colado de uma mensagem ou lido de um print) vira um WOD agendado para o dia,
// que aparece em Treino → Hoje e no aviso de chegada ao box. Tudo no aparelho.

/// Parte do treino que não é cronometrada (aquecimento, força, skill…)
struct WodPart: Codable, Hashable {
    var title: String
    var lines: [String]
}

struct PlannedWod: Codable, Identifiable, Hashable {
    var id = UUID()
    var day: Date
    var name: String
    var format: WodFormat
    var lines: [String]
    var parts: [WodPart] = []

    var wodID: String { "coach-" + id.uuidString }
    var wod: Wod { Wod(id: wodID, name: name, category: "Coach", format: blocksFormat, lines: lines, exercises: WodMovements.ids(lines), parts: parts) }

    /// Importados antes dos blocos viraram um AMRAP/EMOM só com o tempo somado: os blocos voltam a partir das linhas
    private var blocksFormat: WodFormat {
        switch format {
        case .amrap, .emom: WodParser.intervals(lines) ?? format
        default: format
        }
    }
}

/// WODs do coach importados, em `UserDefaults`. Ficam todos: são a linha do tempo dos seus WODs (WodTimelineView)
enum WodPlan {
    static let key = "plannedWods"

    static func all(_ raw: String? = UserDefaults.standard.string(forKey: key)) -> [PlannedWod] {
        guard let data = raw?.data(using: .utf8) else { return [] }
        return ((try? JSONDecoder().decode([PlannedWod].self, from: data)) ?? []).sorted { $0.day < $1.day }
    }

    static func save(_ p: PlannedWod) {
        var list = all().filter { $0.id != p.id }
        list.append(p)
        store(list)
    }

    static func delete(_ p: PlannedWod) { store(all().filter { $0.id != p.id }) }

    private static func store(_ list: [PlannedWod]) {
        UserDefaults.standard.set(String(data: (try? JSONEncoder().encode(list)) ?? Data(), encoding: .utf8), forKey: key)
    }

    /// WOD de um dia que ainda não tem resultado salvo
    static func pending(on day: Date = .now, raw: String? = UserDefaults.standard.string(forKey: key), done: Set<String>) -> PlannedWod? {
        all(raw).first { Calendar.current.isDate($0.day, inSameDayAs: day) && !done.contains($0.wodID) }
    }

    @MainActor
    static func pendingToday() -> PlannedWod? {
        let ids = ((try? AppData.container.mainContext.fetch(FetchDescriptor<WodResult>())) ?? []).map(\.wodID)
        return pending(done: Set(ids))
    }
}

// MARK: - Leitura do texto

struct WodDraft: Equatable {
    var name = "WOD do coach"
    var format: WodFormat = .forTime(capMinutes: nil)
    var lines: [String] = []
    var parts: [WodPart] = []
    /// Nenhum formato apareceu no texto: For Time sem limite é só um palpite
    var guessed = true
    /// Dia que veio no título ("WOD 19/10/2026", "Treino sexta 17/10")
    var day: Date?
    /// Níveis do WOD ("SCALE", "AMADOR", "RX"…), cada um com as suas linhas; vazio quando o WOD é um só
    var variants: [WodPart] = []
    /// Nível escolhido entre `variants`
    var level: String?
    /// Partes do treino sem os outros níveis (que entram em `parts` como "Outro nível: …")
    var baseParts: [WodPart] = []

    /// O mesmo treino com outro nível no cronômetro; os demais ficam nas partes, para consulta
    func picking(_ name: String) -> WodDraft {
        guard let chosen = variants.first(where: { $0.title == name }) else { return self }
        var d = self
        d.level = name
        WodParser.fill(&d, with: chosen.lines)
        d.parts = baseParts + variants.filter { $0.title != name }.map { WodPart(title: "Outro nível: \($0.title)", lines: $0.lines) }
        return d
    }
}

/// Nível do WOD que você costuma fazer (Scale, Amador, RX…): já vem escolhido no próximo treino com níveis
enum WodLevel {
    static let key = "wodLevel"
    static var preferred: String? {
        get { UserDefaults.standard.string(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

enum WodParser {
    private enum Kind { case warmup, skill, strength, wod, extra }

    private static let headers: [(Kind, String, [String])] = [
        (.warmup, "Aquecimento", ["aquecimento", "warm up", "warm-up", "warmup", "mobilidade", "mobility", "ativação", "ativacao"]),
        (.skill, "Skill", ["skill", "técnica", "tecnica", "habilidade", "gymnastics", "ginástica", "ginastica"]),
        (.strength, "Força", ["força", "forca", "strength", "lpo", "weightlifting", "levantamento olímpico", "levantamento olimpico"]),
        (.wod, "WOD", ["wod", "metcon", "conditioning", "condicionamento"]),
        (.extra, "Extra", ["acessório", "acessórios", "acessorio", "acessorios", "accessory", "core", "cooldown", "cool down",
                           "alongamento", "finisher", "volta à calma", "volta a calma"]),
    ]

    static func parse(_ text: String) -> WodDraft {
        let lines = text.components(separatedBy: .newlines).map(clean).filter { !$0.isEmpty && !isNoise($0) }
        var sections: [(kind: Kind?, title: String, lines: [String])] = [(nil, "", [])]
        var day: Date?
        for line in lines {
            if let (kind, title, rest) = header(line) {
                day = day ?? date(in: line)
                sections.append((kind, title, rest.isEmpty ? [] : [tidy(rest)]))
            } else {
                sections[sections.count - 1].lines.append(tidy(line))
            }
        }
        let hasHeaders = sections.contains { $0.kind != nil }
        if hasHeaders { day = day ?? sections[0].lines.lazy.compactMap { date(in: $0) }.first }
        sections.removeAll { $0.kind == nil && $0.lines.isEmpty }

        let wodIndex = sections.lastIndex { $0.kind == .wod }
            ?? sections.lastIndex { $0.lines.contains { format(in: $0) != nil } }
            ?? (hasHeaders ? sections.lastIndex { $0.kind != nil } : sections.indices.last)

        var draft = WodDraft()
        draft.day = day
        guard let wodIndex else { return draft }
        // Antes do primeiro título costuma vir "Treino de sexta 17/10" ou o nome do box: não é parte do treino
        draft.baseParts = sections.enumerated().compactMap { i, s in
            i == wodIndex || s.kind == nil || s.lines.isEmpty ? nil : WodPart(title: s.title, lines: s.lines)
        }
        draft.parts = draft.baseParts
        let wodLines = sections[wodIndex].lines
        let (common, levels) = split(levels: wodLines)
        if levels.count > 1 {
            // O que vem antes do primeiro nível ("AMRAP 12'") vale para todos
            draft.variants = levels.map { WodPart(title: $0.title, lines: common + $0.lines) }
            let names = draft.variants.map(\.title)
            return draft.picking(WodLevel.preferred.flatMap { names.contains($0) ? $0 : nil } ?? names[names.count - 1])
        }
        fill(&draft, with: wodLines)
        return draft
    }

    /// Formato e linhas do WOD a partir das linhas dele
    static func fill(_ draft: inout WodDraft, with wodLines: [String]) {
        draft.guessed = true
        draft.format = .forTime(capMinutes: nil)
        if let blocks = intervals(wodLines) {
            draft.format = blocks
            draft.guessed = false
            draft.lines = wodLines.filter { !isOnlyFormat($0) || blockMinutes($0) != nil }
        } else if let found = wodLines.lazy.compactMap(format(in:)).first {
            draft.format = found
            draft.guessed = false
            // "For time" numa linha e "Cap: 15'" na outra
            if case .forTime(nil) = found, let c = wodLines.lazy.compactMap(cap(in:)).first { draft.format = .forTime(capMinutes: c) }
            draft.lines = wodLines.filter { !isOnlyFormat($0) }
        } else {
            draft.lines = wodLines.filter { !isOnlyFormat($0) }
        }
    }

    /// Nomes de nível que o coach escreve sozinhos numa linha, dentro do WOD
    private static let levelPattern = "^(scaled?|rx'?d?|rx\\+|amador|iniciantes?|intermedi[aá]rios?|avan[cç]ados?|elite|masters?|teens?|adaptados?|beginners?|intermediate|advanced|foundations?|(?:n[ií]vel|level)\\s*\\w{1,12})\\s*:?$"

    /// "SCALE / 5 rounds… / AMADOR / 5 a 10 rounds…" → linhas comuns e cada nível com as suas
    static func split(levels lines: [String]) -> (common: [String], levels: [(title: String, lines: [String])]) {
        var common: [String] = [], levels: [(title: String, lines: [String])] = []
        for line in lines {
            if match(levelPattern, line) != nil {
                let lower = line.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " :"))
                levels.append((lower.hasPrefix("rx") ? lower.uppercased() : lower.capitalizedFirst, []))
            } else if levels.isEmpty {
                common.append(line)
            } else {
                levels[levels.count - 1].lines.append(line)
            }
        }
        return (common, levels.filter { !$0.lines.isEmpty })
    }

    /// Tira negrito/itálico de mensagem (*, _, ~), emojis, marcadores de lista e espaços repetidos
    static func clean(_ line: String) -> String {
        let scalars = line.unicodeScalars.filter { s in
            !(s.properties.isEmojiPresentation || (s.properties.isEmoji && s.value > 0x2000 && !(0x2018...0x201F).contains(s.value)))
                && s.value != 0xFE0F && s.value != 0x200D
        }
        var s = String(String.UnicodeScalarView(scalars))
        s = s.replacingOccurrences(of: "[*_~`]", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "^\\s*[-•▪◦>·]+\\s*", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// Linha do jeito que o atleta lê: "03 DEVIL PRESS (2DB)" → "3 Devil press (2 DB)", "REST 2'" → "Descanso 2'",
    /// "AQUECIMENTO MMSS/II" → "Aquecimento MMSS/MMII", "(OU ISOMETRIA )" → "(ou isometria)"
    static func tidy(_ line: String) -> String {
        var s = line.replacingOccurrences(of: "^0+(\\d)", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "(\\d)\\s*(kb|db|bb)\\b", with: "$1 $2", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "\\bMMSS\\s*/\\s*II\\b", with: "MMSS/MMII", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "\\bMMII\\s*/\\s*SS\\b", with: "MMII/MMSS", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "\\(\\s+", with: "(", options: .regularExpression)
            .replacingOccurrences(of: "\\s+\\)", with: ")", options: .regularExpression)
            .replacingOccurrences(of: "\\s*\\(\\s*\\)", with: "", options: .regularExpression)
        let shouting = !s.contains(where: \.isLowercase) && s.filter(\.isLetter).count >= 4
        for (typo, fix) in typos {
            s = s.replacingOccurrences(of: "\\b\(typo)\\b", with: shouting ? fix.uppercased() : fix, options: [.regularExpression, .caseInsensitive])
        }
        if shouting { s = sentenceCase(s) }
        return s.replacingOccurrences(of: "^(?:rest|desc\\.?|pausa)(?=[\\s:\\d]|$)\\s*:?\\s*", with: "Descanso ",
                                      options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces)
    }

    private static let typos = [("burpeers", "burpees"), ("burpeer", "burpee"), ("burpes", "burpees"), ("dumbels", "dumbbells"),
                                ("dumbells", "dumbbells"), ("dumbel", "dumbbell"), ("dumbell", "dumbbell"), ("dumbbel", "dumbbell"),
                                ("kettlebel", "kettlebell"), ("wallball", "wall ball"),
                                ("shoud", "shoulder"), ("shouder", "shoulder"), ("sholder", "shoulder")]

    private static let acronyms = "kb|db|bb|amrap|emom|e\\dmom|wod|hspu|t2b|ttb|c2b|ctb|ghd|rm|pr|bjo|bbjo|ohs|du|sdhp|tgu|hpc|rx|tc|ft|rdl|dl|bmu|rmu|k2e|hsw|lpo|mmss|mmii|ii|su|rft"

    /// "5 WALL BALL" → "5 Wall ball", mantendo siglas (KB, DB, AMRAP…) em maiúsculas. Não sobe a primeira letra de
    /// "(ou isometria)", "2 a 4 reps" e "5 rounds": parêntese, conectivo e unidade ficam minúsculos
    private static func sentenceCase(_ line: String) -> String {
        var s = line.lowercased()
        if let re = try? NSRegularExpression(pattern: "\\b(?:\(acronyms))\\b") {
            for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)).reversed() {
                if let r = Range(m.range, in: s) { s.replaceSubrange(r, with: s[r].uppercased()) }
            }
        }
        let first = s.split(whereSeparator: { !$0.isLetter }).first.map(String.init) ?? ""
        let keepLower = s.hasPrefix("(")
            || (s.first?.isNumber == true && ["a", "e", "x", "ou", "rounds", "round", "reps", "rep", "rodadas", "rodada"].contains(first))
        if !keepLower, let i = s.firstIndex(where: \.isLetter) { s.replaceSubrange(i...i, with: s[i].uppercased()) }
        return s
    }

    /// Marca d'água do app do box ("TECNOFIT" no rodapé do print) e os botões da tela dele (Check-in, Ranking, Dicas…)
    static func isNoise(_ line: String) -> Bool {
        // Contador solto de curtidas/comentários ("0") e setas de navegação
        if line.range(of: "^[\\d<>‹›]{1,2}$", options: .regularExpression) != nil { return true }
        let key = line.lowercased().filter { $0.isLetter || $0 == " " || $0 == "-" }.trimmingCharacters(in: .whitespaces)
        if ["tecnofit", "nextfit", "next fit", "wodify", "sugarwod", "btwb", "pushpress", "push press app", "zen planner",
            "check-in", "checkin", "ações", "acoes", "cross"].contains(key) { return true }
        // Só palavras de botão, juntas ou não ("Ver Ranking", "Fazer check-in", "Ver RankingCheck-In")
        let words = key.replacingOccurrences(of: "check-in", with: " checkin ").split(separator: " ")
        let buttons: Set<String> = ["ver", "fazer", "ranking", "rankingcheckin", "checkin", "dicas", "nenhuma", "ações", "acoes", "curtir", "comentar"]
        return !words.isEmpty && words.count <= 4 && words.allSatisfy { buttons.contains(String($0)) }
    }

    /// "19/10/2026", "17/10" (sem ano: este ano); cargas como "9/6kg" não contam
    static func date(in line: String) -> Date? {
        guard let m = match("(?<![\\d/])(\\d{1,2})/(\\d{1,2})(?:/(\\d{2,4}))?(?![\\d/])(?!\\s*(?:kg|lb))", line),
              let d = Int(m[1]), let mo = Int(m[2]), (1...31).contains(d), (1...12).contains(mo) else { return nil }
        let cal = Calendar.current
        var y = Int(m[3]) ?? cal.component(.year, from: .now)
        if y < 100 { y += 2000 }
        return cal.date(from: DateComponents(year: y, month: mo, day: d))
    }

    /// Blocos com descanso ("AMRAP 3' / Descanso 2' / AMRAP 3'…" ou "3x AMRAP 3' descanso 1'"): cada bloco com o seu cronômetro
    static func intervals(_ lines: [String]) -> WodFormat? {
        let rest = lines.lazy.compactMap(restSeconds).first ?? lines.lazy.compactMap(inlineRest).first ?? 0
        for line in lines {
            guard let m = match("^(\\d{1,2})\\s*(?:x|×|rounds?|rodadas?|blocos?)\\s*(?:de\\s*)?(?:amrap|e\\d?mom)", line),
                  let n = Int(m[1]), (2...12).contains(n) else { continue }
            switch format(in: line) {
            case .amrap(let mins): return .intervals(blocks: Array(repeating: mins, count: n), rest: rest, emom: false)
            case .emom(let mins): return .intervals(blocks: Array(repeating: mins, count: n), rest: rest, emom: true)
            default: continue
            }
        }
        let blocks = lines.filter(isOnlyFormat).compactMap(format(in:))
        let amraps = blocks.compactMap { if case .amrap(let m) = $0 { m } else { nil } }
        let emoms = blocks.compactMap { if case .emom(let m) = $0 { m } else { nil } }
        if amraps.count > 1, emoms.isEmpty { return .intervals(blocks: amraps, rest: rest, emom: false) }
        if emoms.count > 1, amraps.isEmpty { return .intervals(blocks: emoms, rest: rest, emom: true) }
        return nil
    }

    /// "3x AMRAP 3' descanso 1'" (descanso na mesma linha)
    private static func inlineRest(_ line: String) -> Int? {
        guard let m = match("(?:descanso|rest|pausa)\\s*:?\\s*(\\d{1,3})\\s*('|’|min|s\\b|seg|\")?", line), let n = Int(m[1]) else { return nil }
        return ["s", "seg", "\""].contains(m[2].lowercased()) ? n : n * 60
    }

    private static func blockMinutes(_ line: String) -> Int? {
        switch format(in: line) {
        case .amrap(let m), .emom(let m): m
        default: nil
        }
    }

    private static func restSeconds(_ line: String) -> Int? {
        guard let m = match("^descanso\\s*(\\d{1,3})\\s*('|’|min|s\\b|seg|\")?", line), let n = Int(m[1]) else { return nil }
        return ["s", "seg", "\""].contains(m[2].lowercased()) ? n : n * 60
    }

    /// "AQUECIMENTO", "B) Força:", "WOD: AMRAP 15'", "WOD 1", "WOD 19/10/2026" (o que vem depois dos dois-pontos fica como linha)
    private static func header(_ line: String) -> (Kind, String, String)? {
        let stripped = line.replacingOccurrences(of: "^([a-zA-Z0-9][).]|parte \\d+)\\s*", with: "", options: [.regularExpression, .caseInsensitive])
        let lower = stripped.lowercased()
        for (kind, title, words) in headers {
            for w in words where lower.hasPrefix(w) {
                let rest = stripped.dropFirst(w.count)
                guard rest.isEmpty || !(rest.first!.isLetter) else { continue }
                // "FORÇA ()": parênteses vazios contam como título sem nada depois
                let tail = rest.trimmingCharacters(in: CharacterSet(charactersIn: " :-–—|"))
                    .replacingOccurrences(of: "^\\(\\s*\\)$", with: "", options: .regularExpression)
                // Condicionamento dentro do treino é uma parte com nome próprio; o WOD principal é o último bloco desse tipo
                let title = ["condicionamento", "conditioning"].contains(w) ? "Condicionamento" : title
                if tail.range(of: "^\\d{1,2}/\\d{1,2}(/\\d{2,4})?$", options: .regularExpression) != nil { return (kind, title, "") }
                if let inner = match("^\\(([^()]{2,30})\\)$", tail)?[1] {
                    let name = w == "lpo" ? "LPO" : title
                    return (kind, "\(name) (\(inner.lowercased().capitalizedFirst))", "")
                }
                if tail.range(of: "^(\\d{1,2}|[a-z])$", options: [.regularExpression, .caseInsensitive]) != nil {
                    return (kind, "\(title) \(tail.uppercased())", "")
                }
                // "Core: 3x20 abdominais" é título com conteúdo; "Força total no agachamento" não é título
                if tail.isEmpty || rest.trimmingCharacters(in: .whitespaces).first.map({ ":-–—|".contains($0) }) == true || format(in: tail) != nil {
                    return (kind, title, tail)
                }
            }
        }
        return nil
    }

    private static func match(_ pattern: String, _ text: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<m.numberOfRanges).map { Range(m.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
    }

    private static let minutes = "(\\d{1,3})\\s*(?:'|’|min\\b|minutos|minutes)?"

    static func format(in line: String) -> WodFormat? {
        if let m = match("\\bamrap\\s*(?:de|in|em|:|-)?\\s*" + minutes, line) ?? match("\\b" + minutes + "\\s*(?:de\\s*)?amrap\\b", line),
           let n = Int(m[1]), (1...90).contains(n) {
            return .amrap(minutes: n)
        }
        if let every = everyFormat(line) { return every }
        if let m = match("\\be1?mom\\s*(?:de|x|:|-)?\\s*" + minutes, line) ?? match("\\b" + minutes + "\\s*(?:de\\s*)?e1?mom\\b", line),
           let n = Int(m[1]), (1...90).contains(n) {
            return .emom(minutes: n)
        }
        // "5 ROUNDS", "5 A 10 ROUNDS" sem cronômetro: rounds para fazer, como For Time
        if match("^(\\d{1,2})(?:\\s*(?:a|-|–|ou)\\s*\\d{1,2})?\\s*(?:rounds?|rodadas?|rfts?)\\b", line) != nil,
           match("amrap|e\\d?mom|tabata", line) == nil {
            return .forTime(capMinutes: cap(in: line))
        }
        if match("\\btabata\\b", line) != nil {
            let rounds = match("(\\d{1,2})\\s*(?:x|rounds?|rodadas?)", line).flatMap { Int($0[1]) }.flatMap { (1...20).contains($0) ? $0 : nil }
            return .tabata(rounds: rounds ?? 8)
        }
        if match("\\bfor\\s*time\\b|\\bft\\b|\\bpor\\s*tempo\\b", line) != nil || cap(in: line) != nil {
            return .forTime(capMinutes: cap(in: line))
        }
        return nil
    }

    /// "E2MOM 10'", "A CADA 2' DURANTE 10'", "Durante 10' a cada 2'", "every 3 min x 15", "A CADA 2,00" (sem fim)
    private static func everyFormat(_ line: String) -> WodFormat? {
        var seconds: Int?
        if let m = match("\\be(\\d)mom\\b", line), let n = Int(m[1]), n >= 2 { seconds = n * 60 }
        // "A CADA 1'30"", "a cada 1min30": minutos e segundos
        if let m = match("\\b(?:a\\s*cada|every)\\s*(\\d{1,2})\\s*(?:'|’|min)\\s*(\\d{2})\\s*(?:\"|”|s\\b|seg)?", line),
           let n = Int(m[1]), let sec = Int(m[2]) {
            seconds = n * 60 + sec
        } else if let m = match("\\b(?:a\\s*cada|every)\\s*(\\d{1,2})(?:[:,.](\\d{2}))?\\s*('|’|min|minutos|s\\b|seg|\")?", line), let n = Int(m[1]) {
            let isSeconds = ["s", "seg", "\""].contains(m[3].lowercased())
            seconds = isSeconds ? n : n * 60 + (Int(m[2]) ?? 0)
        }
        guard let seconds, seconds >= 15, seconds != 60 || line.lowercased().contains("cada") || line.lowercased().contains("every") else { return nil }
        let total = match("\\b(?:durante|por|for|x)\\s*(\\d{1,3})\\s*(?:'|’|min)", line).flatMap { Int($0[1]) }
            ?? match("\\be\\dmom\\s*(?:de|x|:|-)?\\s*(\\d{1,3})", line).flatMap { Int($0[1]) }
        let m = min(total ?? 0, 90)
        return seconds == 60 && m > 0 ? .emom(minutes: m) : .every(seconds: seconds, minutes: m)
    }

    private static func cap(in line: String) -> Int? {
        match("\\b(?:tc|time\\s*cap|cap)\\s*(?:de|:|=|-)?\\s*" + minutes, line).flatMap { Int($0[1]) }.flatMap { (1...90).contains($0) ? $0 : nil }
    }

    /// "AMRAP 20'", "For Time (TC 12 min)": só o formato, sem movimento
    private static func isOnlyFormat(_ line: String) -> Bool {
        guard format(in: line) != nil else { return false }
        let rest = line.lowercased().replacingOccurrences(
            of: "amrap|e\\d?mom|a\\s*cada|every|durante|tabata|for\\s*time|\\bft\\b|por\\s*tempo|time\\s*cap|\\btc\\b|\\bcap\\b|min(?:utos|utes)?\\b|\\bde\\b|\\bem\\b|\\bin\\b|[0-9'’():=\\-–—.,\\s]",
            with: "", options: .regularExpression)
        return rest.isEmpty
    }
}

// MARK: - Print (Vision) e modelo do aparelho

enum WodOCR {
    /// Texto de um print ou foto, de cima para baixo; horários soltos de mensagens ("10:32") saem
    static func text(from image: UIImage) async throws -> String {
        try await lines(from: image).joined(separator: "\n")
    }

    static func lines(from image: UIImage) async throws -> [String] {
        guard let cg = image.cgImage else { return [] }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["pt-BR", "en-US"]
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(cgImage: cg, orientation: orientation).perform([request])
            // De cima para baixo (no Vision, y cresce para cima); na mesma altura, da esquerda para a direita
            return (request.results ?? [])
                .sorted { abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.008 ? $0.boundingBox.midY > $1.boundingBox.midY
                                                                              : $0.boundingBox.minX < $1.boundingBox.minX }
                .compactMap { $0.topCandidates(1).first?.string }
                .filter { $0.range(of: "^\\d{1,2}:\\d{2}$", options: .regularExpression) == nil }
        }.value
    }

    /// Treino que não coube num print só: junta as partes pela sobreposição (o fim de um print repete o começo do outro),
    /// em qualquer ordem de escolha. O título que se repete no topo de cada print fica uma vez só.
    static func merge(_ pages: [[String]]) -> [String] {
        let pages = pages.map { $0.filter { !key($0).isEmpty && !WodParser.isNoise(WodParser.clean($0)) } }.filter { !$0.isEmpty }
        guard pages.count > 1 else { return pages.first ?? [] }
        let repeated = pages.dropFirst().reduce(Set(pages[0].prefix(3).map(key))) { $0.intersection($1.prefix(3).map(key)) }
        let title = pages[0].prefix(3).filter { repeated.contains(key($0)) }
        var rest = pages.map { $0.filter { !repeated.contains(key($0)) } }
        var chain = rest.removeFirst()
        while !rest.isEmpty {
            var best = (index: 0, lines: chain + rest[0], size: 0)
            for (i, p) in rest.enumerated() {
                for joined in [join(chain, p), join(p, chain)] where joined.size > best.size {
                    best = (i, joined.lines, joined.size)
                }
            }
            // Sem sobreposição: vale a ordem em que os prints foram escolhidos
            if best.size == 0 { best.lines = chain + rest[best.index] }
            rest.remove(at: best.index)
            chain = best.lines
        }
        return title + chain
    }

    /// `a` em cima de `b`: o maior trecho repetido perto da emenda (fim de `a`, começo de `b`). O que sobra depois do
    /// trecho em `a` (botão flutuante, linha cortada) e antes dele em `b` (título, linha cortada) sai.
    private static func join(_ a: [String], _ b: [String]) -> (lines: [String], size: Int) {
        let ka = a.map(key), kb = b.map(key)
        var best = (i: 0, j: 0, k: 0)
        for i in ka.indices {
            for j in kb.indices.prefix(4) {
                var k = 0
                while i + k < ka.count, j + k < kb.count, ka[i + k] == kb[j + k] { k += 1 }
                if k > best.k, ka.count - (i + k) <= 3 { best = (i, j, k) }
            }
        }
        guard best.k >= min(2, a.count, b.count) else { return (a + b, 0) }
        return (Array(a[..<(best.i + best.k)]) + b[(best.j + best.k)...], best.k)
    }

    private static func key(_ line: String) -> String { line.lowercased().filter { $0.isLetter || $0.isNumber } }
}

private extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct AIWod {
    @Guide(description: "Formato do WOD principal: amrap, emom, tabata ou fortime")
    var formato: String
    @Guide(description: "Minutos do AMRAP ou do EMOM, ou o time cap do For Time; 0 se não houver")
    var minutos: Int
    @Guide(description: "Rodadas do Tabata; 0 se não for Tabata")
    var rodadas: Int
    @Guide(description: "Movimentos do WOD principal, um por item, como estão no texto (repetições e cargas incluídas)")
    var movimentos: [String]
    @Guide(description: "Outras partes do treino (aquecimento, força, skill, acessórios), na ordem do texto")
    var partes: [AIPart]
}

@available(iOS 26.0, *)
@Generable
struct AIPart {
    @Guide(description: "Título curto: Aquecimento, Força, Skill ou Extra")
    var titulo: String
    var linhas: [String]
}
#endif

enum WodAI {
    static var available: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) { return SystemLanguageModel.default.isAvailable }
        #endif
        return false
    }

    /// Lê textos bagunçados com o modelo do próprio aparelho (Apple Intelligence); nil se não der
    static func parse(_ text: String) async -> WodDraft? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable {
            let session = LanguageModelSession(instructions: """
                Você recebe o treino de CrossFit que o coach mandou e separa o WOD principal \
                (a parte cronometrada) das outras partes. Não invente movimentos: copie do texto.
                """)
            guard let ai = try? await session.respond(to: text, generating: AIWod.self).content, !ai.movimentos.isEmpty else { return nil }
            var d = WodDraft()
            let n = ai.minutos > 0 ? min(ai.minutos, 90) : nil
            switch ai.formato.lowercased().filter(\.isLetter) {
            case "amrap": d.format = .amrap(minutes: n ?? 12)
            case "emom": d.format = .emom(minutes: n ?? 10)
            case "tabata": d.format = .tabata(rounds: ai.rodadas > 0 ? min(ai.rodadas, 20) : 8)
            default: d.format = .forTime(capMinutes: n)
            }
            d.guessed = false
            d.lines = ai.movimentos.map { WodParser.tidy(WodParser.clean($0)) }.filter { !$0.isEmpty }
            d.parts = ai.partes.map { WodPart(title: $0.titulo, lines: $0.linhas.map(WodParser.clean).filter { !$0.isEmpty }) }.filter { !$0.lines.isEmpty }
            return d
        }
        #endif
        return nil
    }
}

// MARK: - Telas

/// Colar o texto ou escolher o print, conferir e agendar
struct ImportWodView: View {
    var editing: PlannedWod?
    /// Usado no registro de atividade: o dia do treino e o que fazer com o WOD salvo (em vez de agendar ou começar)
    var initialDay: Date?
    var onPick: ((PlannedWod) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var raw = ""
    @State private var photos: [PhotosPickerItem] = []
    @State private var reading = false
    @State private var error: String?
    @State private var reviewing = false
    @State private var name = "WOD do coach"
    @State private var day = Date.now
    @State private var kind = 0
    @State private var minutes = 12
    @State private var rounds = 8
    /// Blocos com descanso: minutos de cada um, descanso em segundos e se é EMOM
    @State private var blocks: [Int] = [3, 3, 3]
    @State private var blockRest = 120
    /// EMOM: tamanho do intervalo (1 = a cada minuto; 2 = E2MOM…), em segundos
    @State private var every = 60
    @State private var blocksEmom = false
    @State private var linesText = ""
    @State private var parts: [WodPart] = []
    @State private var guessed = false
    /// Leitura do texto, para trocar de nível sem ler de novo
    @State private var draft: WodDraft?
    @State private var start: Wod?
    /// 0 hoje, 1 amanhã, 2 outro dia (calendário)
    @State private var dayChoice = 0

    var body: some View {
        GMModal(editing == nil ? "Treino do coach" : "Editar treino", confirm: reviewing ? "Salvar" : nil, confirmEnabled: !lines.isEmpty,
                onConfirm: { let p = save(); onPick?(p); dismiss() }) {
            if reviewing { review } else { input }
        }
        .overlay { if reading { readingOverlay } }
        .animation(.snappy, value: reviewing)
        .onChange(of: photos) { _, items in if !items.isEmpty { Task { await read(items) } } }
        .onChange(of: dayChoice) { _, c in
            if c < 2 { day = Calendar.current.date(byAdding: .day, value: c, to: Calendar.current.startOfDay(for: .now))! }
        }
        .onAppear {
            if let editing { load(editing) } else if let d = initialDay { setDay(d) }
        }
        .gmModal(item: $start) { WodTimerView(wod: $0) }
    }

    // MARK: Entrada

    @ViewBuilder
    private var input: some View {
        VStack(spacing: 10) {
            Image(systemName: "flame.fill")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Theme.streak)
                .frame(width: 68, height: 68)
                .background(Theme.streak.opacity(0.15), in: .circle)
            Text("Traga o treino do coach").gmFont(24, weight: .bold, design: .rounded, relativeTo: .title2)
            Text("O app separa aquecimento, força e WOD e deixa o cronômetro pronto para quando você chegar no box.")
                .font(.subheadline).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)

        HStack(spacing: 12) {
            PhotosPicker(selection: $photos, maxSelectionCount: 6, selectionBehavior: .ordered, matching: .screenshots) {
                sourceTile(icon: "text.viewfinder", title: "Prints", subtitle: "Um ou mais, se não coube")
            }
            PhotosPicker(selection: $photos, maxSelectionCount: 6, selectionBehavior: .ordered, matching: .images) {
                sourceTile(icon: "photo.on.rectangle", title: "Foto", subtitle: "Ex.: quadro do box")
            }
        }
        .buttonStyle(GMPress())

        GMCard {
            HStack(spacing: 12) {
                Image(systemName: "doc.on.clipboard").font(.title3).foregroundStyle(Theme.accent).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Texto copiado").font(.headline)
                    Text("Copie a mensagem do coach e cole aqui").font(.caption).foregroundStyle(Theme.dim)
                }
                Spacer()
                PasteButton(payloadType: String.self) { strings in
                    guard let text = strings.first else { return }
                    Task { @MainActor in
                        raw = text
                        await interpret()
                    }
                }
                .labelStyle(.titleOnly)
                .buttonBorderShape(.capsule)
                .tint(Theme.accent)
            }
        }

        HStack {
            Rectangle().fill(Theme.stroke).frame(height: 1)
            Text("ou digite").font(.caption).foregroundStyle(Theme.dim)
            Rectangle().fill(Theme.stroke).frame(height: 1)
        }

        WodTextEditor(text: $raw, placeholder: "AQUECIMENTO\n3 rounds: 10 air squats\n\nWOD\nAMRAP 15'\n10 wall balls\n10 burpees", minHeight: 170)
        Label("Títulos como AQUECIMENTO, FORÇA e WOD separam as partes.", systemImage: "lightbulb")
            .font(.caption).foregroundStyle(Theme.dim)

        if let error { notice(error, icon: "exclamationmark.circle.fill", tint: Theme.danger) }

        GMButton("Ler treino", icon: "wand.and.stars", enabled: !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !reading) {
            Task { await interpret() }
        }
    }

    private func sourceTile(icon: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).font(.title2).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(.white)
                Text(subtitle).font(.caption).foregroundStyle(Theme.dim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.card, in: .rect(cornerRadius: Theme.radius))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Escolher uma imagem do treino")
    }

    private var readingOverlay: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().controlSize(.large).tint(Theme.accent)
                Text("Lendo o treino…").font(.subheadline.weight(.semibold))
            }
            .padding(24)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: Theme.radius))
        }
        .transition(.opacity)
    }

    private func notice(_ text: String, icon: String, tint: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(tint.opacity(0.12), in: .rect(cornerRadius: Theme.radiusM))
    }

    // MARK: Conferência

    @ViewBuilder
    private var review: some View {
        GMCard {
            HStack(spacing: 14) {
                Image(systemName: "flame.fill")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.streak)
                    .frame(width: 52, height: 52)
                    .background(Theme.streak.opacity(0.15), in: .rect(cornerRadius: Theme.radiusL))
                VStack(alignment: .leading, spacing: 4) {
                    TextField("", text: $name, prompt: Text("Nome do treino").foregroundStyle(Theme.dim))
                        .font(.title3.bold())
                        .textInputAutocapitalization(.words)
                    Text("\(format.name) · \(lines.count) \(lines.count == 1 ? "movimento" : "movimentos")")
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                }
                Image(systemName: "pencil").font(.caption).foregroundStyle(Theme.dim)
            }
        }

        if guessed { notice("Não achei o formato no texto: confira abaixo.", icon: "exclamationmark.triangle.fill", tint: Theme.warning) }

        GMSection("Quando") {
            GMChoiceChips(options: [(0, "Hoje"), (1, "Amanhã"), (2, "Outro dia")], selection: $dayChoice)
            if dayChoice == 2 {
                GMDivider()
                GMDateField(date: $day, limitToNow: false, title: "Dia")
            }
        }

        GMSection("Formato") {
            GMChoiceChips(options: [(0, "For Time"), (1, "AMRAP"), (2, "EMOM"), (3, "Tabata"), (4, "Blocos")], selection: $kind)
            GMDivider()
            if kind == 4 {
                GMChoiceChips(options: [(false, "AMRAP"), (true, "EMOM")], selection: $blocksEmom)
                GMStepper(title: "Blocos", value: Binding(get: { blocks.count }, set: { n in
                    blocks = n > blocks.count ? blocks + Array(repeating: blocks.last ?? 3, count: n - blocks.count) : Array(blocks.prefix(n))
                }), range: 2...12)
                GMStepper(title: "Cada bloco", value: Binding(get: { blocks.first ?? 3 }, set: { m in blocks = blocks.map { _ in m } }),
                          range: 1...30, format: { "\($0) min" })
                GMStepper(title: "Descanso entre eles", value: $blockRest, range: 0...600, step: 30, format: { $0 == 0 ? "Sem descanso" : WodFormat.restText($0) })
            } else if kind == 3 {
                GMStepper(title: "Rodadas", value: $rounds, range: 1...20)
            } else if kind == 2 {
                GMStepper(title: "A cada", value: $every, range: 30...300, step: 30, format: { clock($0) })
                GMStepper(title: "Duração", value: $minutes, range: 0...90, format: { $0 == 0 ? "Sem fim" : "\($0) min" })
            } else {
                GMStepper(title: kind == 0 ? "Time cap" : "Duração", value: $minutes, range: kind == 0 ? 0...90 : 1...90,
                          format: { kind == 0 && $0 == 0 ? "Sem limite" : "\($0) min" })
            }
        }

        if let d = draft, d.variants.count > 1 {
            GMSection("Nível", footer: "O coach mandou o WOD em \(d.variants.count) níveis. O escolhido vai para o cronômetro e os outros ficam salvos no treino. O app lembra o seu nível na próxima vez.") {
                GMChoiceChips(options: d.variants.map { ($0.title, $0.title) },
                              selection: Binding(get: { d.level ?? "" }, set: { pick(level: $0) }))
            }
        }

        GMSection("WOD", footer: recognizedFooter) {
            WodTextEditor(text: $linesText, placeholder: "10 wall balls\n10 burpees", minHeight: 120)
        }

        ForEach(Array(parts.enumerated()), id: \.offset) { i, part in
            GMCard {
                HStack {
                    Text(part.title.uppercased()).font(.caption.bold()).foregroundStyle(Theme.dim)
                    Spacer()
                    GMIconButton(icon: "trash", size: 28, label: "Tirar \(part.title)") {
                        withAnimation(.snappy) { _ = parts.remove(at: i) }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(part.lines.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(Theme.accent).frame(width: 5, height: 5)
                            Text(line).font(.subheadline)
                        }
                    }
                }
            }
        }

        VStack(spacing: 6) {
            if let onPick {
                GMButton("Usar este WOD", icon: "checkmark", enabled: !lines.isEmpty) {
                    onPick(save())
                    dismiss()
                }
            } else if Calendar.current.isDateInToday(day) {
                GMButton("Salvar e começar agora", icon: "play.fill", enabled: !lines.isEmpty) { start = save().wod }
            } else {
                GMButton("Agendar para \(PlannedWodView.dayText(day).prefix(1).lowercased() + PlannedWodView.dayText(day).dropFirst())", icon: "calendar.badge.plus", enabled: !lines.isEmpty) {
                    save()
                    dismiss()
                }
            }
            if editing == nil {
                GMTextButton(title: "Usar outro texto", icon: "arrow.uturn.backward") { reviewing = false }
            }
        }
        .padding(.top, 4)
    }

    private var recognizedFooter: String {
        let names = WodMovements.ids(lines).compactMap(Exercise.byID).map(\.name)
        return "Um movimento por linha; é o que aparece no cronômetro."
            + (names.isEmpty ? "" : "\nReconhecidos: " + names.joined(separator: ", ") + ".")
    }

    private var lines: [String] {
        linesText.components(separatedBy: .newlines).map(WodParser.clean).filter { !$0.isEmpty }
    }

    private var format: WodFormat {
        switch kind {
        case 0: .forTime(capMinutes: minutes > 0 ? minutes : nil)
        case 1: .amrap(minutes: minutes)
        case 2: every == 60 && minutes > 0 ? .emom(minutes: minutes) : .every(seconds: every, minutes: minutes)
        case 4: .intervals(blocks: blocks, rest: blockRest, emom: blocksEmom)
        default: .tabata(rounds: rounds)
        }
    }

    @discardableResult
    private func save() -> PlannedWod {
        var p = editing ?? PlannedWod(day: day, name: name, format: format, lines: lines)
        p.day = Calendar.current.startOfDay(for: day)
        p.name = name.trimmingCharacters(in: .whitespaces).isEmpty ? "WOD do coach" : name.trimmingCharacters(in: .whitespaces)
        p.format = format
        p.lines = lines
        p.parts = parts
        WodPlan.save(p)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        return p
    }

    private func load(_ p: PlannedWod) {
        name = p.name
        let offset = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: p.day).day ?? 2
        dayChoice = (0...1).contains(offset) ? offset : 2
        day = p.day
        apply(p.format)
        linesText = p.lines.joined(separator: "\n")
        parts = p.parts
        reviewing = true
    }

    private func setDay(_ d: Date) {
        let offset = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: d)).day ?? 2
        dayChoice = (0...1).contains(offset) ? offset : 2
        day = d
    }

    private func apply(_ f: WodFormat) {
        switch f {
        case .forTime(let cap): kind = 0; minutes = cap ?? 0
        case .amrap(let m): kind = 1; minutes = m
        case .emom(let m): kind = 2; minutes = m; every = 60
        case .every(let sec, let m): kind = 2; minutes = m; every = sec
        case .tabata(let r): kind = 3; rounds = r
        case .intervals(let b, let rest, let emom): kind = 4; blocks = b; blockRest = rest; blocksEmom = emom
        }
    }

    private func read(_ items: [PhotosPickerItem]) async {
        error = nil
        reading = true
        defer { reading = false; photos = [] }
        var pages: [[String]] = []
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                error = items.count == 1 ? "Não deu para abrir a imagem." : "Não deu para abrir uma das imagens."
                return
            }
            pages.append((try? await WodOCR.lines(from: image)) ?? [])
        }
        let text = WodOCR.merge(pages).joined(separator: "\n")
        guard !text.isEmpty else {
            error = "Não achei texto nessa imagem. Tente um print mais de perto."
            return
        }
        raw = text
        await interpret()
    }

    private func pick(level: String) {
        guard let d = draft?.picking(level) else { return }
        WodLevel.preferred = level
        draft = d
        apply(d.format)
        linesText = d.lines.joined(separator: "\n")
        parts = d.parts
        guessed = d.guessed
    }

    private func interpret() async {
        error = nil
        reading = true
        defer { reading = false }
        let heuristic = WodParser.parse(raw)
        let draft = heuristic.guessed || heuristic.lines.isEmpty ? (await WodAI.parse(raw) ?? heuristic) : heuristic
        guard !draft.lines.isEmpty else {
            error = "Não achei os movimentos do WOD. Confira o texto."
            return
        }
        self.draft = draft
        apply(draft.format)
        if let d = draft.day { setDay(d) }
        linesText = draft.lines.joined(separator: "\n")
        parts = draft.parts
        guessed = draft.guessed
        reviewing = true
    }
}

/// Campo de texto grande com dica por cima enquanto vazio
private struct WodTextEditor: View {
    @Binding var text: String
    let placeholder: String
    var minHeight: CGFloat = 120

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder).foregroundStyle(Theme.dim.opacity(0.7)).padding(.horizontal, 5).padding(.vertical, 8)
                    .accessibilityHidden(true)
            }
            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .autocorrectionDisabled()
        }
        .font(.callout)
        .frame(minHeight: minHeight)
        .padding(10)
        .background(Theme.raised, in: .rect(cornerRadius: Theme.radiusM))
    }
}

/// Treino do coach completo: partes, WOD e ações
struct PlannedWodView: View {
    let initial: PlannedWod
    @AppStorage(WodPlan.key) private var raw = ""
    @Environment(\.dismiss) private var dismiss
    @State private var start: Wod?
    @State private var editing = false
    @State private var confirmDelete = false
    @State private var info: Exercise?
    @Query(sort: \WodResult.date, order: .reverse) private var allResults: [WodResult]

    /// Volta da edição com o que foi salvo
    private var plan: PlannedWod { WodPlan.all(raw).first { $0.id == initial.id } ?? initial }

    var body: some View {
        GMModal(plan.name) {
            Text(PlannedWodView.dayText(plan.day) + " · " + plan.format.name).font(.subheadline).foregroundStyle(Theme.dim)
            ForEach(Array(plan.parts.enumerated()), id: \.offset) { _, part in
                GMSection(part.title) {
                    ForEach(Array(part.lines.enumerated()), id: \.offset) { Text($0.element).font(.subheadline) }
                }
            }
            GMSection("WOD · \(plan.format.name)") {
                Text(plan.format.detail).font(.caption).foregroundStyle(Theme.dim)
                ForEach(Array(plan.lines.enumerated()), id: \.offset) { Text($0.element).font(.headline) }
            }
            let done = allResults.filter { $0.wodID == plan.wodID }
            if !done.isEmpty {
                GMSection("Seu resultado") {
                    ForEach(done) { r in
                        GMValueRow(label: r.date.formatted(date: .abbreviated, time: .omitted), value: r.text + (r.rx ? " RX" : ""))
                    }
                }
            }
            let movements = WodMovements.ids(plan.parts.flatMap(\.lines) + plan.lines).compactMap(Exercise.byID)
            if !movements.isEmpty {
                GMSection("Movimentos") {
                    ForEach(movements) { e in
                        GMRow(title: e.name, chevron: true, action: { info = e }) { ExerciseThumb(exercise: e, size: 36) }
                    }
                }
            }
            GMButton(plan.parts.isEmpty ? "Começar WOD" : "Começar treino", icon: "play.fill") { start = plan.wod }
            GMButton("Editar", icon: "pencil", kind: .secondary) { editing = true }
            GMButton("Apagar treino", icon: "trash", kind: .danger) { confirmDelete = true }
        }
        .gmModal(item: $start) { WodTimerView(wod: $0) }
        .gmModal(isPresented: $editing) { ImportWodView(editing: plan) }
        .gmModal(item: $info) { ExerciseInfoView(exercise: $0) }
        .gmActions(isPresented: $confirmDelete, title: "Apagar \(plan.name)?", message: "Resultados já salvos continuam no histórico.",
                   actions: [GMAction("Apagar", icon: "trash", destructive: true) { WodPlan.delete(plan); dismiss() }])
    }

    static func dayText(_ d: Date) -> String {
        Calendar.current.isDateInTomorrow(d) ? "Amanhã" : GMDateText.day(d)
    }
}
