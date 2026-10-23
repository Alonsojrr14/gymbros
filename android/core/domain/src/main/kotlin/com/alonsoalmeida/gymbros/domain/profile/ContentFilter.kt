package com.alonsoalmeida.gymbros.domain.profile

import java.text.Normalizer

/** Termos bloqueados. Fonte: Moderation/BlockedTerms.swift (mesma lista, mesma ordem) */
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
 * Confere o que vai ser publicado (nome, @usuário, bio…) contra [BlockedTerms]. Fonte: Moderation/ContentFilter.swift.
 * Palavras inteiras depois de normalizar: minúsculas, sem acento, trocas comuns (@→a, 0→o, 1→i…), letras repetidas
 * ("merdaaa") e letras separadas ("p u t a").
 */
object ContentFilter {
    const val MESSAGE = "Esse texto tem palavras que não são permitidas no GymBros. Ajuste e tente de novo."

    fun allows(vararg texts: String): Boolean = texts.all { match(it) == null }

    /** O texto, ou vazio se tiver termo bloqueado */
    fun publishable(text: String): String = if (allows(text)) text else ""

    fun match(text: String, terms: List<String>? = null): String? {
        val variants = listOf(tokens(text), tokens(text, leet = false)).filter { it.isNotEmpty() }
        if (variants.isEmpty()) return null
        val candidates = variants + variants.flatMap(::spelledOut).map { listOf(it) }
        val list = terms?.mapNotNull(Term::of) ?: defaultTerms
        return list.firstOrNull { term -> candidates.any { term.matches(it) } }?.raw
    }

    private val defaultTerms by lazy { BlockedTerms.all.mapNotNull(Term::of) }

    private val leetMap = mapOf('@' to 'a', '4' to 'a', '0' to 'o', '1' to 'i', '!' to 'i', '3' to 'e', '5' to 's', '$' to 's', '7' to 't')

    /** Sem acento, sem largura (`folding` do iOS) e em minúsculas */
    private fun fold(s: String): String =
        Normalizer.normalize(s, Normalizer.Form.NFKD).replace(Regex("\\p{M}+"), "").lowercase()

    /** Palavras normalizadas. Troca de número ou símbolo só vale grudada numa letra; o "!" só entre letras */
    fun tokens(text: String, leet: Boolean = true): List<String> {
        val folded = fold(text).toCharArray()
        val out = StringBuilder()
        for ((i, c) in folded.withIndex()) {
            if (c.isLetter()) { out.append(c); continue }
            val before = i > 0 && folded[i - 1].isLetter()
            val after = i + 1 < folded.size && folded[i + 1].isLetter()
            val m = leetMap[c]
            if (leet && m != null && (if (c == '!') before && after else before || after)) out.append(m) else out.append(' ')
        }
        return out.split(' ').filter { it.isNotEmpty() }
    }

    /** Letras soltas em sequência viram uma palavra ("p u t a" → "puta"); só com 3 ou mais */
    private fun spelledOut(words: List<String>): List<String> {
        val runs = mutableListOf<String>()
        var current = ""
        for (w in words + "") {
            if (w.length == 1) current += w
            else {
                if (current.length >= 3) runs += current
                current = ""
            }
        }
        return runs
    }

    private data class Run(val letter: Char, val count: Int)

    private class Term(val raw: String, val words: List<List<Run>>, val prefix: Boolean) {
        fun matches(text: List<String>): Boolean {
            if (text.size < words.size) return false
            val t = text.map(::runs)
            return (0..(t.size - words.size)).any { start ->
                words.indices.all { j -> same(t[start + j], words[j], prefix && j == words.size - 1) }
            }
        }

        companion object {
            fun of(raw: String): Term? {
                val prefix = raw.endsWith("*")
                val words = tokens(if (prefix) raw.dropLast(1) else raw).map(::runs)
                return if (words.isEmpty()) null else Term(raw, words, prefix)
            }
        }
    }

    /** "porrraaa" → p1 o1 r3 a3 */
    private fun runs(s: String): List<Run> {
        val out = mutableListOf<Run>()
        for (c in s) {
            if (out.lastOrNull()?.letter == c) out[out.size - 1] = out.last().copy(count = out.last().count + 1) else out += Run(c, 1)
        }
        return out
    }

    /** Letra repetida a mais ainda casa; a menos, não ("as" ≠ "ass") */
    private fun same(word: List<Run>, term: List<Run>, prefix: Boolean): Boolean {
        if (if (prefix) word.size < term.size else word.size != term.size) return false
        return word.zip(term).all { (a, b) -> a.letter == b.letter && a.count >= b.count }
    }
}
