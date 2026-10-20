import Foundation

/// Liga as linhas do WOD do coach aos exercícios da biblioteca ("7 KETTLEBELL SWING (1KB)" → kettlebell-swing),
/// tolerando inglês/português, plural, abreviações (KB, DB, T2B) e erros de digitação ou de leitura do print.
enum WodMovements {
    /// Apelido → exercício. Ganha o apelido com mais palavras que aparece na linha, na ordem.
    private static let aliases: [(String, String)] = [
        ("wall ball", "cf-wall-ball"), ("wallball", "cf-wall-ball"),
        ("kettlebell swing", "kettlebell-swing"), ("american swing", "kettlebell-swing"), ("russian swing", "kettlebell-swing"),
        ("swing", "kettlebell-swing"),
        ("kettlebell snatch", "cf-kb-snatch"),
        ("push up", "flexao"), ("flexao", "flexao"), ("flexao braco", "flexao"), ("hand release push up", "flexao"),
        ("release push up", "flexao"),
        ("handstand push up", "cf-hspu"), ("hspu", "cf-hspu"), ("handstand walk", "cf-handstand-walk"), ("hsw", "cf-handstand-walk"),
        ("air squat", "agachamento-livre-corpo"), ("squat", "agachamento-livre-corpo"), ("agachamento livre corpo", "agachamento-livre-corpo"),
        ("agachamento sem carga", "agachamento-livre-corpo"),
        ("agachamento", "agachamento"), ("back squat", "agachamento"), ("agachamento barra", "agachamento"),
        ("front squat", "agachamento-frontal"), ("agachamento frontal", "agachamento-frontal"),
        ("overhead squat", "cf-overhead-squat"), ("ohs", "cf-overhead-squat"),
        ("goblet squat", "agachamento-goblet"), ("agachamento goblet", "agachamento-goblet"),
        ("jump squat", "agachamento-salto"), ("agachamento salto", "agachamento-salto"),
        ("pistol", "cf-pistol"), ("box squat", "agachamento-box"),
        ("devil press", "cf-devil-press"),
        ("avanco", "afundo"), ("afundo", "afundo"), ("lunge", "afundo"), ("walking lunge", "afundo"),
        ("avanco barra", "afundo-barra"), ("afundo barra", "afundo-barra"), ("front rack lunge", "afundo-barra"),
        ("jumping lunge", "cf-jumping-lunge"), ("afundo salto", "cf-jumping-lunge"), ("avanco salto", "cf-jumping-lunge"),
        ("burpee", "burpee"), ("burpee box jump over", "cf-burpee-box"), ("bbjo", "cf-burpee-box"),
        ("bicep", "rosca-direta"), ("rosca", "rosca-direta"), ("rosca direta", "rosca-direta"), ("bicep curl", "rosca-direta"), ("curl", "rosca-direta"),
        ("bicep halter", "rosca-alternada"), ("rosca halter", "rosca-alternada"), ("rosca alternada", "rosca-alternada"), ("curl halter", "rosca-alternada"),
        ("rosca martelo", "rosca-martelo"), ("hammer curl", "rosca-martelo"),
        ("tricep", "triceps-pulley"), ("tricep halter", "triceps-deitado-halter"),
        ("remada", "remada-curvada"), ("bent over row", "remada-curvada"), ("remada curvada", "remada-curvada"),
        ("remada halter", "remada-curvada-halter"), ("halter row", "remada-curvada-halter"), ("renegade row", "remada-curvada-halter"),
        ("remada alta", "remada-alta"), ("upright row", "remada-alta"), ("ring row", "remada-invertida"), ("remada invertida", "remada-invertida"),
        ("run", "esteira"), ("running", "esteira"), ("corrida", "esteira"), ("correr", "esteira"),
        ("row", "cf-row-cal"), ("remo", "cf-row-cal"), ("rowing", "cf-row-cal"),
        ("bike", "cf-bike-cal"), ("assault bike", "cf-bike-cal"), ("air bike", "cf-bike-cal"), ("echo bike", "cf-bike-cal"),
        ("ski", "cf-ski-cal"), ("ski erg", "cf-ski-cal"),
        ("double under", "cf-double-under"), ("du", "cf-double-under"), ("dub", "cf-double-under"),
        ("single under", "pular-corda"), ("pular corda", "pular-corda"), ("su", "pular-corda"),
        ("rope climb", "cf-rope-climb"), ("subida corda", "cf-rope-climb"), ("corda naval", "corda-naval"), ("battle rope", "corda-naval"),
        ("pull up", "cf-kipping-pull-up"), ("barra fixa", "cf-kipping-pull-up"),
        ("strict pull up", "barra-fixa"), ("pull up strict", "barra-fixa"),
        ("chest bar", "cf-chest-to-bar"), ("c2b", "cf-chest-to-bar"), ("ctb", "cf-chest-to-bar"),
        ("toe bar", "cf-toes-to-bar"), ("t2b", "cf-toes-to-bar"), ("ttb", "cf-toes-to-bar"),
        ("knee elbow", "cf-knees-to-elbows"), ("k2e", "cf-knees-to-elbows"),
        ("muscle up", "cf-bar-muscle-up"), ("bar muscle up", "cf-bar-muscle-up"), ("bmu", "cf-bar-muscle-up"),
        ("ring muscle up", "cf-ring-muscle-up"), ("rmu", "cf-ring-muscle-up"), ("ring dip", "cf-ring-dip"),
        ("sit up", "abdominal-completo"), ("abdominal", "abdominal-completo"), ("ghd", "cf-ghd-situp"),
        ("v up", "canivete"), ("canivete", "canivete"), ("prancha", "prancha"), ("plank", "prancha"),
        ("l sit", "cf-l-sit"), ("mountain climber", "cf-mountain-climber"), ("escalador", "cf-mountain-climber"),
        ("tuck jump", "cf-tuck-jump"), ("turkish get up", "cf-turkish"), ("tgu", "cf-turkish"),
        ("thruster", "thruster"),
        ("deadlift", "levantamento-terra"), ("dl", "levantamento-terra"), ("levantamento terra", "levantamento-terra"), ("terra", "levantamento-terra"),
        ("sumo deadlift high pull", "cf-sdhp"), ("sdhp", "cf-sdhp"),
        ("romanian deadlift", "terra-romeno"), ("rdl", "terra-romeno"), ("terra romeno", "terra-romeno"), ("stiff", "terra-romeno"),
        ("snatch", "cf-snatch"), ("arranco", "cf-snatch"), ("power snatch", "cf-power-snatch"), ("hang snatch", "cf-hang-snatch"),
        ("halter snatch", "cf-dumbbell-snatch"), ("halter power snatch", "cf-dumbbell-snatch"),
        ("clean", "clean"), ("power clean", "clean"), ("squat clean", "cf-squat-clean"), ("hang squat clean", "cf-squat-clean"),
        ("hang power clean", "cf-hang-power-clean"), ("hpc", "cf-hang-power-clean"),
        ("clean jerk", "cf-clean-jerk"), ("arremesso", "cf-clean-jerk"),
        ("push press", "cf-push-press"), ("push jerk", "cf-push-jerk"), ("split jerk", "cf-split-jerk"),
        ("shoulder press", "desenvolvimento"), ("strict press", "desenvolvimento"), ("desenvolvimento", "desenvolvimento"),
        ("desenvolvimento halter", "desenvolvimento-halter"), ("shoulder press halter", "desenvolvimento-halter"),
        ("bench press", "supino-reto"), ("supino", "supino-reto"),
        ("box jump", "cf-box-jump"), ("box jump over", "cf-box-jump-over"), ("bjo", "cf-box-jump-over"),
        ("step up", "subida-banco"), ("subida banco", "subida-banco"), ("subida caixa", "subida-banco"),
        ("farmer walk", "farmer-walk"), ("farmer carry", "farmer-walk"), ("sandbag", "cf-sandbag"), ("sled push", "cf-sled-push"),
    ]

    private static let parsed: [(tokens: [String], id: String)] = aliases.map { (baseTokens($0.0), $0.1) }
    private static let vocabulary: Set<String> = Set(parsed.flatMap(\.tokens))

    private static let synonyms: [String: [String]] = [
        "db": ["halter"], "dumbbell": ["halter"], "dumbell": ["halter"], "dumbel": ["halter"], "dumbbel": ["halter"], "haltere": ["halter"],
        "halteres": ["halter"], "kb": ["kettlebell"], "kettlebel": ["kettlebell"], "kettle": ["kettlebell"], "kbs": ["kettlebell"], "dbs": ["halter"], "bb": ["barra"], "barbell": ["barra"],
        "pushup": ["push", "up"], "pullup": ["pull", "up"], "situp": ["sit", "up"], "stepup": ["step", "up"], "muscleup": ["muscle", "up"],
        "burpe": ["burpee"], "abdominai": ["abdominal"],
    ]

    private static let stopwords: Set<String> = ["com", "de", "do", "da", "dos", "das", "no", "na", "nos", "em", "and", "the", "with",
                                                 "e", "a", "o", "to", "of", "on"]

    /// Exercícios das linhas, na ordem, sem repetir
    static func ids(_ lines: [String]) -> [String] {
        var seen = Set<String>()
        return lines.flatMap(identify).filter { seen.insert($0).inserted }
    }

    /// Exercícios de uma linha ("10 thrusters + 10 pull-ups" e "30 DU / 60 SU" dão dois). Entre parênteses vem a opção
    /// mais fácil ("8 HSPU (RELEASE PUSH UP)") ou o equipamento ("(2DB)"): só o equipamento entra na conta.
    static func identify(_ line: String) -> [String] {
        line.replacingOccurrences(of: "\\s+/\\s+", with: ";", options: .regularExpression)
            .split(whereSeparator: { "+,;".contains($0) }).compactMap { piece in
                let text = String(piece)
                let outside = text.replacingOccurrences(of: "\\([^)]*\\)?", with: " ", options: .regularExpression)
                let inside = text.matches(of: /\(([^)]*)\)/).flatMap { tokens(String($0.output.1)) }
                return best(tokens(outside) + inside.filter(equipment.contains))
            }
    }

    private static let equipment: Set<String> = ["halter", "kettlebell", "barra"]

    private static func best(_ words: [String]) -> String? {
        var found: (tokens: [String], id: String)?
        for alias in parsed where alias.tokens.count > (found?.tokens.count ?? 0) && isSubsequence(alias.tokens, of: words) {
            found = alias
        }
        return found?.id
    }

    private static func isSubsequence(_ needle: [String], of hay: [String]) -> Bool {
        var i = 0
        for w in hay where i < needle.count && w == needle[i] { i += 1 }
        return i == needle.count
    }

    /// Minúsculas, sem acento, sem números e cargas, no singular, com sinônimos e erros de digitação corrigidos
    static func tokens(_ text: String) -> [String] { baseTokens(text).map(corrected) }

    private static func baseTokens(_ text: String) -> [String] {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR")).lowercased()
            .replacingOccurrences(of: "(\\d)([a-z])", with: "$1 $2", options: .regularExpression)
        return folded.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.contains(where: \.isLetter) }
            .map(singular)
            .flatMap { synonyms[$0] ?? [$0] }
            .filter { !stopwords.contains($0) }
    }

    private static func singular(_ w: String) -> String {
        if w.count > 4, w.hasSuffix("oes") { return String(w.dropLast(3)) + "ao" }
        return w.count > 2 && w.hasSuffix("s") && !w.hasSuffix("ss") ? String(w.dropLast()) : w
    }

    /// "burpeer" → "burpee": palavra parecida do vocabulário (1 letra de diferença; 2 em palavras longas)
    private static func corrected(_ w: String) -> String {
        guard w.count >= 5, !vocabulary.contains(w), !w.contains(where: \.isNumber) else { return w }
        let limit = w.count >= 8 ? 2 : 1
        let close = vocabulary.compactMap { v -> (String, Int)? in
            guard abs(v.count - w.count) <= limit else { return nil }
            let d = distance(w, v)
            return d <= limit ? (v, d) : nil
        }
        guard let min = close.map(\.1).min() else { return w }
        let best = close.filter { $0.1 == min }
        return best.count == 1 ? best[0].0 : w
    }

    private static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var row = Array(0...b.count)
        for i in 1...a.count {
            var prev = row[0]
            row[0] = i
            for j in 1...b.count {
                let cur = row[j]
                row[j] = a[i - 1] == b[j - 1] ? prev : 1 + min(prev, row[j], row[j - 1])
                prev = cur
            }
        }
        return row[b.count]
    }

    #if DEBUG
    static var allIDs: Set<String> { Set(aliases.map(\.1)) }
    #endif
}
