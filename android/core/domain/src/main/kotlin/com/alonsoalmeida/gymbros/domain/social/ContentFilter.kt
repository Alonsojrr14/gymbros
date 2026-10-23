package com.alonsoalmeida.gymbros.domain.social

import java.text.Normalizer

/**
 * Termos bloqueados (Moderation/BlockedTerms.swift). Um termo por linha, em minúsculas; acento, maiúsculas e trocas
 * como @→a, 0→o e 1→i não importam (o filtro normaliza). Vale só a palavra inteira; `*` no fim pega também o que
 * começa com ele. Termos com espaço casam a frase.
 */
object BlockedTerms {
    val portuguese = listOf(
        "porra", "caralho*", "merda", "merdas", "cu", "cuzao", "cuzinho", "puta", "putas", "putinha", "putaria",
        "fdp", "vsf", "vtnc", "tnc", "pqp", "foder", "fodase", "foda-se", "fodido", "fodida",
        "buceta*", "boceta*", "xoxota*", "piroca*", "punheta*", "vagabunda", "vagabundas",
        "viado", "viados", "viadinho", "sapatao", "traveco", "crioulo", "crioula",
        "retardado", "retardada", "otario", "otaria", "babaca", "imbecil", "corno",
        "vai se matar", "se mata logo",
    )

    val english = listOf(
        "fuck*", "motherfuck*", "shit", "shits", "shitty", "bullshit", "bitch*", "cunt*", "whore*", "slut*",
        "asshole*", "dickhead*", "nigger*", "nigga*", "faggot*", "fag", "fags", "retard", "retarded",
        "kys", "kill yourself", "kill urself",
    )

    val all = portuguese + english
}

/**
 * Confere o que vai ser publicado (comentários, mensagens, recados, nome, bio…) contra [BlockedTerms]
 * (Moderation/ContentFilter.swift). Compara palavras inteiras depois de normalizar: minúsculas, sem acento, trocas
 * comuns (@→a, 0→o, 1→i…), letras repetidas ("merdaaa") e letras separadas ("p u t a").
 *
 * Função pública para todas as frentes: `ContentFilter.allows(texto)` antes de publicar qualquer texto de usuário.
 */
object ContentFilter {
    const val MESSAGE = "Esse texto tem palavras que não são permitidas no GymBros. Ajuste e tente de novo."

    fun allows(vararg texts: String): Boolean = texts.all { match(it) == null }

    /** O texto, ou vazio se tiver termo bloqueado (para o que sobe sem passar por uma tela, como o nome) */
    fun publishable(text: String): String = if (allows(text)) text else ""

    /** O primeiro termo bloqueado encontrado no texto */
    fun match(text: String, terms: List<String>? = null): String? {
        val variants = listOf(tokens(text), tokens(text, leet = false)).filter { it.isNotEmpty() }
        if (variants.isEmpty()) return null
        val candidates = variants + variants.flatMap(::spelledOut).map { listOf(it) }
        val list = terms?.mapNotNull(Term::of) ?: defaultTerms
        return list.firstOrNull { term -> candidates.any { term.matches(it) } }?.raw
    }

    private val defaultTerms by lazy { BlockedTerms.all.mapNotNull(Term::of) }

    private val leetMap = mapOf('@' to 'a', '4' to 'a', '0' to 'o', '1' to 'i', '!' to 'i', '3' to 'e', '5' to 's', '$' to 's', '7' to 't')

    /** Sem acento, minúsculas e sem largura (o `folding` do iOS), um caractere por posição */
    private fun fold(text: String): List<String> {
        val decomposed = Normalizer.normalize(text, Normalizer.Form.NFKD).replace(Regex("\\p{Mn}+"), "")
        val lower = decomposed.lowercase(java.util.Locale.forLanguageTag("pt-BR"))
        val out = ArrayList<String>()
        var i = 0
        while (i < lower.length) {
            val cp = lower.codePointAt(i)
            out.add(String(Character.toChars(cp)))
            i += Character.charCount(cp)
        }
        return out
    }

    private fun isLetter(s: String) = s.isNotEmpty() && Character.isLetter(s.codePointAt(0))

    /**
     * Palavras normalizadas. Troca de número ou símbolo só vale grudada numa letra ("p0rra"); o "!" só entre letras,
     * para "merda!" continuar sendo "merda". Sem `leet`, número e símbolo só separam ("putaria123").
     */
    fun tokens(text: String, leet: Boolean = true): List<String> {
        val folded = fold(text)
        val out = StringBuilder()
        for ((i, c) in folded.withIndex()) {
            if (isLetter(c)) { out.append(c); continue }
            val before = i > 0 && isLetter(folded[i - 1])
            val after = i + 1 < folded.size && isLetter(folded[i + 1])
            val m = if (c.length == 1) leetMap[c[0]] else null
            if (leet && m != null && (if (c == "!") before && after else before || after)) out.append(m) else out.append(' ')
        }
        return out.split(' ').filter { it.isNotEmpty() }
    }

    private fun length(s: String) = s.codePointCount(0, s.length)

    /** Letras soltas em sequência viram uma palavra ("p u t a" → "puta"); só com 3 ou mais */
    private fun spelledOut(words: List<String>): List<String> {
        val runs = mutableListOf<String>()
        var current = ""
        for (w in words + "") {
            if (length(w) == 1) current += w
            else {
                if (length(current) >= 3) runs.add(current)
                current = ""
            }
        }
        return runs
    }

    private data class Run(val letter: Int, val count: Int)

    private class Term(val raw: String, val words: List<List<Run>>, val prefix: Boolean) {
        fun matches(text: List<String>): Boolean {
            if (text.size < words.size) return false
            val runs = text.map(::runs)
            return (0..(runs.size - words.size)).any { start ->
                words.indices.all { j -> same(runs[start + j], words[j], prefix && j == words.lastIndex) }
            }
        }

        companion object {
            fun of(raw: String): Term? {
                val prefix = raw.endsWith("*")
                val words = tokens(if (prefix) raw.dropLast(1) else raw).map(::runs)
                return if (words.isEmpty()) null else Term(raw, words, prefix)
            }

            /** "porrraaa" → p1 o1 r3 a3 */
            fun runs(s: String): List<Run> {
                val out = ArrayList<Run>()
                var i = 0
                while (i < s.length) {
                    val cp = s.codePointAt(i)
                    if (out.isNotEmpty() && out.last().letter == cp) out[out.lastIndex] = out.last().copy(count = out.last().count + 1)
                    else out.add(Run(cp, 1))
                    i += Character.charCount(cp)
                }
                return out
            }

            /** Letra repetida a mais ainda casa ("porrraaa" = "porra"); a menos, não ("as" ≠ "ass") */
            fun same(word: List<Run>, term: List<Run>, prefix: Boolean): Boolean {
                if (if (prefix) word.size < term.size else word.size != term.size) return false
                return word.zip(term).all { (w, t) -> w.letter == t.letter && w.count >= t.count }
            }
        }
    }
}
