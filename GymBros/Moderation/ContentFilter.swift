import SwiftUI

/// Confere o que vai ser publicado (recados, comentários, check-ins, nome, @usuário e bio) contra BlockedTerms.
/// Compara palavras inteiras depois de normalizar: minúsculas, sem acento, trocas comuns (@→a, 0→o, 1→i…),
/// letras repetidas ("merdaaa") e letras separadas ("p u t a").
enum ContentFilter {
    static let message = "Esse texto tem palavras que não são permitidas no GymBros. Ajuste e tente de novo."

    static func allows(_ texts: String...) -> Bool { texts.allSatisfy { match(in: $0) == nil } }

    /// O texto, ou vazio se tiver termo bloqueado (para o que sobe sem passar por uma tela, como o nome)
    static func publishable(_ text: String) -> String { allows(text) ? text : "" }

    /// O primeiro termo bloqueado encontrado no texto
    static func match(in text: String, terms: [String]? = nil) -> String? {
        let variants = [tokens(text), tokens(text, leet: false)].filter { !$0.isEmpty }
        guard !variants.isEmpty else { return nil }
        let candidates = variants + variants.flatMap(spelledOut).map { [$0] }
        let list = terms.map { $0.compactMap(Term.init) } ?? defaultTerms
        return list.first { term in candidates.contains { term.matches($0) } }?.raw
    }

    private static let defaultTerms = BlockedTerms.all.compactMap(Term.init)

    private static let leet: [Character: Character] = ["@": "a", "4": "a", "0": "o", "1": "i", "!": "i", "3": "e", "5": "s", "$": "s", "7": "t"]

    /// Palavras normalizadas. Troca de número ou símbolo só vale grudada numa letra ("p0rra"); o "!" só entre
    /// letras, para "merda!" continuar sendo "merda". Sem `leet`, número e símbolo só separam ("putaria123").
    static func tokens(_ text: String, leet useLeet: Bool = true) -> [String] {
        let folded = Array(text.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "pt_BR"))
            .lowercased())
        var out = ""
        for (i, c) in folded.enumerated() {
            if c.isLetter {
                out.append(c)
                continue
            }
            let before = i > 0 && folded[i - 1].isLetter
            let after = i + 1 < folded.count && folded[i + 1].isLetter
            if useLeet, let m = leet[c], c == "!" ? before && after : before || after {
                out.append(m)
            } else {
                out.append(" ")
            }
        }
        return out.split(separator: " ").map(String.init)
    }

    /// Letras soltas em sequência viram uma palavra ("p u t a" → "puta"); só com 3 ou mais, para "e o" não virar nada
    private static func spelledOut(_ words: [String]) -> [String] {
        var runs: [String] = [], current = ""
        for w in words + [""] {
            if w.count == 1 {
                current += w
            } else {
                if current.count >= 3 { runs.append(current) }
                current = ""
            }
        }
        return runs
    }

    private struct Term {
        let raw: String
        let words: [[Run]]
        let prefix: Bool

        init?(_ raw: String) {
            self.raw = raw
            prefix = raw.hasSuffix("*")
            words = ContentFilter.tokens(prefix ? String(raw.dropLast()) : raw).map(Self.runs)
            if words.isEmpty { return nil }
        }

        func matches(_ text: [String]) -> Bool {
            guard text.count >= words.count else { return false }
            let text = text.map(Self.runs)
            return (0...(text.count - words.count)).contains { start in
                words.indices.allSatisfy { j in
                    Self.same(text[start + j], words[j], prefix: prefix && j == words.count - 1)
                }
            }
        }

        struct Run {
            let letter: Character
            var count: Int
        }

        /// "porrraaa" → p1 o1 r3 a3
        static func runs(_ s: String) -> [Run] {
            var out: [Run] = []
            for c in s {
                if out.last?.letter == c { out[out.count - 1].count += 1 } else { out.append(Run(letter: c, count: 1)) }
            }
            return out
        }

        /// Letra repetida a mais ainda casa ("porrraaa" = "porra"); a menos, não ("as" ≠ "ass")
        static func same(_ word: [Run], _ term: [Run], prefix: Bool) -> Bool {
            guard prefix ? word.count >= term.count : word.count == term.count else { return false }
            return zip(word, term).allSatisfy { $0.letter == $1.letter && $0.count >= $1.count }
        }
    }
}

/// Aviso de texto barrado, perto do campo
struct ContentBlockedNote: View {
    var body: some View {
        Label(ContentFilter.message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.danger)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
