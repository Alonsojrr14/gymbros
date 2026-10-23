package com.alonsoalmeida.gymbros.domain.train

import com.alonsoalmeida.gymbros.domain.roundHalfAwayFromZero
import java.text.Normalizer
import java.time.LocalDate
import java.util.regex.Pattern

// Porte de Train/WodMovements.swift, WodImport.swift (`WodParser`, `WodDraft`), WodLoads.swift (`WodLoads`, `WodScheme`).
// As expressões regulares do iOS (NSRegularExpression, ICU) rodam aqui com Unicode ligado, para \b e \w tratarem
// "ç" e "ã" como letra, como no iPhone.

internal object Rx {
    private val cache = java.util.concurrent.ConcurrentHashMap<Pair<String, Boolean>, Pattern>()
    fun p(pattern: String, ci: Boolean = false): Pattern = cache.getOrPut(pattern to ci) {
        Pattern.compile(pattern, Pattern.UNICODE_CHARACTER_CLASS or (if (ci) Pattern.CASE_INSENSITIVE or Pattern.UNICODE_CASE else 0))
    }
    fun replace(s: String, pattern: String, with: String, ci: Boolean = false): String = p(pattern, ci).matcher(s).replaceAll(with)
    fun has(s: String, pattern: String, ci: Boolean = false): Boolean = p(pattern, ci).matcher(s).find()
    /** Primeiro trecho que casa */
    fun find(s: String, pattern: String, ci: Boolean = false): String? = p(pattern, ci).matcher(s).let { if (it.find()) it.group() else null }
}

/** `capitalizedFirst` do iOS: só a primeira letra em maiúscula */
internal fun String.capitalizedFirst(): String = if (isEmpty()) this else substring(0, 1).uppercase() + substring(1)

object WodMovements {
    private val aliases: List<Pair<String, String>> = listOf(
        "wall ball" to "cf-wall-ball", "wallball" to "cf-wall-ball",
        "kettlebell swing" to "kettlebell-swing", "american swing" to "kettlebell-swing", "russian swing" to "kettlebell-swing",
        "swing" to "kettlebell-swing",
        "kettlebell snatch" to "cf-kb-snatch",
        "push up" to "flexao", "flexao" to "flexao", "flexao braco" to "flexao", "hand release push up" to "flexao",
        "release push up" to "flexao",
        "handstand push up" to "cf-hspu", "hspu" to "cf-hspu", "handstand walk" to "cf-handstand-walk", "hsw" to "cf-handstand-walk",
        "air squat" to "agachamento-livre-corpo", "squat" to "agachamento-livre-corpo", "agachamento livre corpo" to "agachamento-livre-corpo",
        "agachamento sem carga" to "agachamento-livre-corpo",
        "agachamento" to "agachamento", "back squat" to "agachamento", "agachamento barra" to "agachamento",
        "front squat" to "agachamento-frontal", "agachamento frontal" to "agachamento-frontal",
        "overhead squat" to "cf-overhead-squat", "ohs" to "cf-overhead-squat",
        "goblet squat" to "agachamento-goblet", "agachamento goblet" to "agachamento-goblet",
        "jump squat" to "agachamento-salto", "agachamento salto" to "agachamento-salto",
        "pistol" to "cf-pistol", "box squat" to "agachamento-box",
        "devil press" to "cf-devil-press",
        "avanco" to "afundo", "afundo" to "afundo", "lunge" to "afundo", "walking lunge" to "afundo",
        "avanco barra" to "afundo-barra", "afundo barra" to "afundo-barra", "front rack lunge" to "afundo-barra",
        "jumping lunge" to "cf-jumping-lunge", "afundo salto" to "cf-jumping-lunge", "avanco salto" to "cf-jumping-lunge",
        "burpee" to "burpee", "burpee box jump over" to "cf-burpee-box", "bbjo" to "cf-burpee-box",
        "bicep" to "rosca-direta", "rosca" to "rosca-direta", "rosca direta" to "rosca-direta", "bicep curl" to "rosca-direta", "curl" to "rosca-direta",
        "bicep halter" to "rosca-alternada", "rosca halter" to "rosca-alternada", "rosca alternada" to "rosca-alternada", "curl halter" to "rosca-alternada",
        "rosca martelo" to "rosca-martelo", "hammer curl" to "rosca-martelo",
        "tricep" to "triceps-pulley", "tricep halter" to "triceps-deitado-halter",
        "remada" to "remada-curvada", "bent over row" to "remada-curvada", "remada curvada" to "remada-curvada",
        "remada halter" to "remada-curvada-halter", "halter row" to "remada-curvada-halter", "renegade row" to "remada-curvada-halter",
        "remada alta" to "remada-alta", "upright row" to "remada-alta", "ring row" to "remada-invertida", "remada invertida" to "remada-invertida",
        "run" to "esteira", "running" to "esteira", "corrida" to "esteira", "correr" to "esteira",
        "row" to "cf-row-cal", "remo" to "cf-row-cal", "rowing" to "cf-row-cal",
        "bike" to "cf-bike-cal", "assault bike" to "cf-bike-cal", "air bike" to "cf-bike-cal", "echo bike" to "cf-bike-cal",
        "ski" to "cf-ski-cal", "ski erg" to "cf-ski-cal",
        "double under" to "cf-double-under", "du" to "cf-double-under", "dub" to "cf-double-under",
        "single under" to "pular-corda", "pular corda" to "pular-corda", "su" to "pular-corda",
        "rope climb" to "cf-rope-climb", "subida corda" to "cf-rope-climb", "corda naval" to "corda-naval", "battle rope" to "corda-naval",
        "pull up" to "cf-kipping-pull-up", "barra fixa" to "cf-kipping-pull-up",
        "strict pull up" to "barra-fixa", "pull up strict" to "barra-fixa",
        "chest bar" to "cf-chest-to-bar", "c2b" to "cf-chest-to-bar", "ctb" to "cf-chest-to-bar",
        "toe bar" to "cf-toes-to-bar", "t2b" to "cf-toes-to-bar", "ttb" to "cf-toes-to-bar",
        "knee elbow" to "cf-knees-to-elbows", "k2e" to "cf-knees-to-elbows",
        "muscle up" to "cf-bar-muscle-up", "bar muscle up" to "cf-bar-muscle-up", "bmu" to "cf-bar-muscle-up",
        "ring muscle up" to "cf-ring-muscle-up", "rmu" to "cf-ring-muscle-up", "ring dip" to "cf-ring-dip",
        "sit up" to "abdominal-completo", "abdominal" to "abdominal-completo", "ghd" to "cf-ghd-situp",
        "v up" to "canivete", "canivete" to "canivete", "prancha" to "prancha", "plank" to "prancha",
        "l sit" to "cf-l-sit", "mountain climber" to "cf-mountain-climber", "escalador" to "cf-mountain-climber",
        "tuck jump" to "cf-tuck-jump", "turkish get up" to "cf-turkish", "tgu" to "cf-turkish",
        "thruster" to "thruster",
        "deadlift" to "levantamento-terra", "dl" to "levantamento-terra", "levantamento terra" to "levantamento-terra", "terra" to "levantamento-terra",
        "sumo deadlift high pull" to "cf-sdhp", "sdhp" to "cf-sdhp",
        "romanian deadlift" to "terra-romeno", "rdl" to "terra-romeno", "terra romeno" to "terra-romeno", "stiff" to "terra-romeno",
        "snatch" to "cf-snatch", "arranco" to "cf-snatch", "power snatch" to "cf-power-snatch", "hang snatch" to "cf-hang-snatch",
        "halter snatch" to "cf-dumbbell-snatch", "halter power snatch" to "cf-dumbbell-snatch",
        "clean" to "clean", "power clean" to "clean", "squat clean" to "cf-squat-clean", "hang squat clean" to "cf-squat-clean",
        "hang power clean" to "cf-hang-power-clean", "hpc" to "cf-hang-power-clean",
        "clean jerk" to "cf-clean-jerk", "arremesso" to "cf-clean-jerk",
        "push press" to "cf-push-press", "push jerk" to "cf-push-jerk", "split jerk" to "cf-split-jerk",
        "shoulder press" to "desenvolvimento", "strict press" to "desenvolvimento", "desenvolvimento" to "desenvolvimento",
        "desenvolvimento halter" to "desenvolvimento-halter", "shoulder press halter" to "desenvolvimento-halter",
        "bench press" to "supino-reto", "supino" to "supino-reto",
        "box jump" to "cf-box-jump", "box jump over" to "cf-box-jump-over", "bjo" to "cf-box-jump-over",
        "step up" to "subida-banco", "subida banco" to "subida-banco", "subida caixa" to "subida-banco",
        "farmer walk" to "farmer-walk", "farmer carry" to "farmer-walk", "sandbag" to "cf-sandbag", "sled push" to "cf-sled-push",
    )

    private val synonyms: Map<String, List<String>> = mapOf(
        "db" to listOf("halter"), "dumbbell" to listOf("halter"), "dumbell" to listOf("halter"), "dumbel" to listOf("halter"),
        "dumbbel" to listOf("halter"), "haltere" to listOf("halter"), "halteres" to listOf("halter"), "kb" to listOf("kettlebell"),
        "kettlebel" to listOf("kettlebell"), "kettle" to listOf("kettlebell"), "kbs" to listOf("kettlebell"), "dbs" to listOf("halter"),
        "bb" to listOf("barra"), "barbell" to listOf("barra"),
        "pushup" to listOf("push", "up"), "pullup" to listOf("pull", "up"), "situp" to listOf("sit", "up"), "stepup" to listOf("step", "up"),
        "muscleup" to listOf("muscle", "up"), "burpe" to listOf("burpee"), "abdominai" to listOf("abdominal"),
    )

    private val stopwords = setOf("com", "de", "do", "da", "dos", "das", "no", "na", "nos", "em", "and", "the", "with", "e", "a", "o", "to", "of", "on")
    private val equipment = setOf("halter", "kettlebell", "barra")

    private val parsed: List<Pair<List<String>, String>> by lazy { aliases.map { baseTokens(it.first) to it.second } }
    private val vocabulary: Set<String> by lazy { parsed.flatMap { it.first }.toSet() }

    /** Exercícios das linhas, na ordem, sem repetir */
    fun ids(lines: List<String>): List<String> = lines.flatMap(::identify).distinct()

    /** Exercícios de uma linha ("10 thrusters + 10 pull-ups" dá dois); entre parênteses só o equipamento conta */
    fun identify(line: String): List<String> =
        Rx.replace(line, "\\s+/\\s+", ";").split('+', ',', ';').filter { it.isNotEmpty() }.mapNotNull { text ->
            val outside = Rx.replace(text, "\\([^)]*\\)?", " ")
            val m = Rx.p("\\(([^)]*)\\)").matcher(text)
            val inside = mutableListOf<String>()
            while (m.find()) inside += tokens(m.group(1))
            best(tokens(outside) + inside.filter { it in equipment })
        }

    private fun best(words: List<String>): String? {
        var found: Pair<List<String>, String>? = null
        for (alias in parsed) if (alias.first.size > (found?.first?.size ?: 0) && isSubsequence(alias.first, words)) found = alias
        return found?.second
    }

    private fun isSubsequence(needle: List<String>, hay: List<String>): Boolean {
        var i = 0
        for (w in hay) if (i < needle.size && w == needle[i]) i++
        return i == needle.size
    }

    fun tokens(text: String): List<String> = baseTokens(text).map(::corrected)

    private fun baseTokens(text: String): List<String> {
        val folded = Rx.replace(Normalizer.normalize(text, Normalizer.Form.NFD).replace(Regex("\\p{M}"), "").lowercase(), "(\\d)([a-z])", "$1 $2")
        return folded.split(Regex("[^\\p{L}\\p{N}]+"))
            .filter { w -> w.any { it.isLetter() } }
            .map(::singular)
            .flatMap { synonyms[it] ?: listOf(it) }
            .filter { it !in stopwords }
    }

    private fun singular(w: String): String {
        if (w.length > 4 && w.endsWith("oes")) return w.dropLast(3) + "ao"
        return if (w.length > 2 && w.endsWith("s") && !w.endsWith("ss")) w.dropLast(1) else w
    }

    /** "burpeer" → "burpee": palavra parecida do vocabulário (1 letra; 2 em palavras longas) */
    private fun corrected(w: String): String {
        if (w.length < 5 || w in vocabulary || w.any { it.isDigit() }) return w
        val limit = if (w.length >= 8) 2 else 1
        val close = vocabulary.mapNotNull { v ->
            if (kotlin.math.abs(v.length - w.length) > limit) return@mapNotNull null
            val d = distance(w, v)
            if (d <= limit) v to d else null
        }
        val min = close.minOfOrNull { it.second } ?: return w
        val best = close.filter { it.second == min }
        return if (best.size == 1) best[0].first else w
    }

    private fun distance(a: String, b: String): Int {
        val row = IntArray(b.length + 1) { it }
        for (i in 1..a.length) {
            var prev = row[0]
            row[0] = i
            for (j in 1..b.length) {
                val cur = row[j]
                row[j] = if (a[i - 1] == b[j - 1]) prev else 1 + minOf(prev, row[j], row[j - 1])
                prev = cur
            }
        }
        return row[b.length]
    }
}

data class WodDraft(
    val name: String = "WOD do coach",
    val format: WodFormat = WodFormat.ForTime(null),
    val lines: List<String> = emptyList(),
    val parts: List<WodPart> = emptyList(),
    /** Nenhum formato apareceu no texto: For Time sem limite é só um palpite */
    val guessed: Boolean = true,
    val day: LocalDate? = null,
    val variants: List<WodPart> = emptyList(),
    val level: String? = null,
    val baseParts: List<WodPart> = emptyList(),
) {
    fun picking(name: String): WodDraft {
        val chosen = variants.firstOrNull { it.title == name } ?: return this
        return WodParser.fill(copy(level = name), chosen.lines).copy(parts = baseParts)
    }
}

object WodParser {
    private enum class Kind { WARMUP, SKILL, STRENGTH, WOD, EXTRA }

    private val headers: List<Triple<Kind, String, List<String>>> = listOf(
        Triple(Kind.WARMUP, "Aquecimento", listOf("aquecimento", "warm up", "warm-up", "warmup", "mobilidade", "mobility", "ativação", "ativacao")),
        Triple(Kind.SKILL, "Skill", listOf("skill", "técnica", "tecnica", "habilidade", "gymnastics", "ginástica", "ginastica")),
        Triple(Kind.STRENGTH, "Força", listOf("força", "forca", "strength", "lpo", "weightlifting", "levantamento olímpico", "levantamento olimpico")),
        Triple(Kind.WOD, "WOD", listOf("wod", "metcon", "conditioning", "condicionamento")),
        Triple(Kind.EXTRA, "Extra", listOf("acessório", "acessórios", "acessorio", "acessorios", "accessory", "core", "cooldown", "cool down",
                                           "alongamento", "finisher", "volta à calma", "volta a calma")),
    )

    private data class Section(val kind: Kind?, val title: String, val lines: MutableList<String>)

    /** `today`: para datas sem ano ("17/10") */
    fun parse(text: String, preferredLevel: String? = null, today: LocalDate = LocalDate.now()): WodDraft {
        val lines = text.split(Regex("\\r\\n|\\r|\\n|\\u2028|\\u2029")).map(::clean).filter { it.isNotEmpty() && !isNoise(it) }
        val sections = mutableListOf(Section(null, "", mutableListOf()))
        var day: LocalDate? = null
        for (line in lines) {
            val h = header(line)
            if (h != null) {
                day = day ?: date(line, today)
                sections += Section(h.first, h.second, if (h.third.isEmpty()) mutableListOf() else mutableListOf(tidy(h.third)))
            } else {
                sections.last().lines += tidy(line)
            }
        }
        val hasHeaders = sections.any { it.kind != null }
        if (hasHeaders) day = day ?: sections[0].lines.firstNotNullOfOrNull { date(it, today) }
        sections.removeAll { it.kind == null && it.lines.isEmpty() }

        val wodIndex = sections.indexOfLast { it.kind == Kind.WOD }.takeIf { it >= 0 }
            ?: sections.indexOfLast { s -> s.lines.any { format(it) != null } }.takeIf { it >= 0 }
            ?: (if (hasHeaders) sections.indexOfLast { it.kind != null }.takeIf { it >= 0 } else sections.indices.lastOrNull())

        var draft = WodDraft(day = day)
        if (wodIndex == null) return draft
        val base = sections.mapIndexedNotNull { i, s -> if (i == wodIndex || s.kind == null || s.lines.isEmpty()) null else WodPart(s.title, s.lines.toList()) }
        draft = draft.copy(baseParts = base, parts = base)
        val wodLines = sections[wodIndex].lines.toList()
        val (common, levels) = splitLevels(wodLines)
        if (levels.size > 1) {
            val variants = levels.map { WodPart(it.first, common + it.second) }
            val names = variants.map { it.title }
            return draft.copy(variants = variants).picking(preferredLevel?.takeIf { it in names } ?: names.last())
        }
        return fill(draft, wodLines)
    }

    /** Formato e linhas do WOD a partir das linhas dele */
    fun fill(d: WodDraft, wodLines: List<String>): WodDraft {
        val blocks = intervals(wodLines)
        if (blocks != null) {
            return d.copy(format = blocks, guessed = false, lines = wodLines.filter { !isOnlyFormat(it) || blockMinutes(it) != null })
        }
        val found = wodLines.firstNotNullOfOrNull { format(it) }
        if (found != null) {
            var f: WodFormat = found
            if (f is WodFormat.ForTime && f.capMinutes == null) wodLines.firstNotNullOfOrNull { cap(it) }?.let { f = WodFormat.ForTime(it) }
            return d.copy(format = f, guessed = false, lines = wodLines.filter { !isOnlyFormat(it) })
        }
        return d.copy(format = WodFormat.ForTime(null), guessed = true, lines = wodLines.filter { !isOnlyFormat(it) })
    }

    private const val LEVEL_PATTERN = "^(scaled?|rx'?d?|rx\\+|amador|iniciantes?|intermedi[aá]rios?|avan[cç]ados?|elite|masters?|teens?|adaptados?|beginners?|intermediate|advanced|foundations?|(?:n[ií]vel|level)\\s*\\w{1,12})\\s*:?$"

    fun splitLevels(lines: List<String>): Pair<List<String>, List<Pair<String, List<String>>>> {
        val common = mutableListOf<String>()
        val levels = mutableListOf<Pair<String, MutableList<String>>>()
        for (line in lines) {
            if (match(LEVEL_PATTERN, line) != null) {
                val lower = line.lowercase().trim(' ', ':')
                levels += (if (lower.startsWith("rx")) lower.uppercase() else lower.capitalizedFirst()) to mutableListOf()
            } else if (levels.isEmpty()) common += line else levels.last().second += line
        }
        return common to levels.filter { it.second.isNotEmpty() }
    }

    const val COMPLEX_MARK = "↳ "

    fun expandComplexes(lines: List<String>): List<String> {
        val out = mutableListOf<String>()
        var i = 0
        while (i < lines.size) {
            val line = lines[i]
            val m = match("^(\\d{1,2}\\s*(?:x|×)?)?\\s*complex(?:o|es)?\\b\\s*[:\\-–]?\\s*(.*)$", line)
            if (m == null) { out += line; i++; continue }
            val pieces = if (m[2].isEmpty()) mutableListOf() else mutableListOf(m[2])
            var j = i + 1
            if (pieces.isEmpty()) {
                while (j < lines.size && lines[j].contains("+") && !lines[j].startsWith(COMPLEX_MARK)) { pieces += lines[j]; j++ }
            }
            val movements = pieces.flatMap { it.split("+") }.map { it.trim() }.filter { it.isNotEmpty() }
            if (movements.size < 2) { out += line; i++; continue }
            val count = m[1].trim()
            out += "${if (count.isEmpty()) "" else "$count "}Complex: ${movements.size} movimentos seguidos, sem soltar a barra"
            out += movements.map { t ->
                val k = t.indexOfFirst { it.isLetter() }
                COMPLEX_MARK + if (k < 0) t else t.substring(0, k) + t.substring(k, k + 1).uppercase() + t.substring(k + 1)
            }
            i = j
        }
        return out
    }

    /** Emojis (aproximação dos `isEmoji` do iOS: blocos de emoji e símbolos pictográficos) */
    private fun isEmoji(cp: Int): Boolean = cp == 0xFE0F || cp == 0x200D || cp == 0x20E3 ||
        cp in 0x1F000..0x1FAFF || cp in 0x2600..0x27BF || cp in 0x2300..0x23FF || cp in 0x2B00..0x2BFF || cp in 0x1F1E6..0x1F1FF ||
        cp in 0x2194..0x2199 || cp in 0x21A9..0x21AA || cp == 0x203C || cp == 0x2049 || cp == 0x2122 || cp == 0x2139 ||
        cp in 0x25AA..0x25AB || cp == 0x25B6 || cp == 0x25C0 || cp in 0x25FB..0x25FE || cp in 0x2934..0x2935 || cp in 0x3030..0x3030 ||
        cp == 0x303D || cp == 0x3297 || cp == 0x3299 || cp in 0xE0020..0xE007F

    /** Tira negrito/itálico de mensagem, emojis, marcadores e espaços repetidos */
    fun clean(line: String): String {
        val sb = StringBuilder()
        line.codePoints().forEach { if (!isEmoji(it)) sb.appendCodePoint(it) }
        var s = sb.toString()
        s = Rx.replace(s, "[*_~`]", "")
        s = Rx.replace(s, "^\\s*[-•▪◦>·]+\\s*", "")
        s = Rx.replace(s, "\\s+", " ")
        return s.trim()
    }

    private val typos = listOf("burpeers" to "burpees", "burpeer" to "burpee", "burpes" to "burpees", "dumbels" to "dumbbells",
                               "dumbells" to "dumbbells", "dumbel" to "dumbbell", "dumbell" to "dumbbell", "dumbbel" to "dumbbell",
                               "kettlebel" to "kettlebell", "wallball" to "wall ball",
                               "shoud" to "shoulder", "shouder" to "shoulder", "sholder" to "shoulder")

    private const val ACRONYMS = "kb|db|bb|amrap|emom|e\\dmom|wod|hspu|t2b|ttb|c2b|ctb|ghd|rm|pr|bjo|bbjo|ohs|du|sdhp|tgu|hpc|rx|tc|ft|rdl|dl|bmu|rmu|k2e|hsw|lpo|mmss|mmii|ii|su|rft"

    /** Linha do jeito que o atleta lê: "03 DEVIL PRESS (2DB)" → "3 Devil press (2 DB)", "REST 2'" → "Descanso 2'" */
    fun tidy(line: String): String {
        var s = Rx.replace(line, "^0+(\\d)", "$1")
        s = Rx.replace(s, "(\\d)\\s*(kb|db|bb)\\b", "$1 $2", ci = true)
        s = Rx.replace(s, "\\bMMSS\\s*/\\s*II\\b", "MMSS/MMII", ci = true)
        s = Rx.replace(s, "\\bMMII\\s*/\\s*SS\\b", "MMII/MMSS", ci = true)
        s = Rx.replace(s, "\\(\\s+", "(")
        s = Rx.replace(s, "\\s+\\)", ")")
        s = Rx.replace(s, "\\s*\\(\\s*\\)", "")
        val shouting = s.none { it.isLowerCase() } && s.count { it.isLetter() } >= 4
        for ((typo, fix) in typos) s = Rx.replace(s, "\\b$typo\\b", if (shouting) fix.uppercase() else fix, ci = true)
        if (shouting) s = sentenceCase(s)
        return Rx.replace(s, "^(?:rest|desc\\.?|pausa)(?=[\\s:\\d]|$)\\s*:?\\s*", "Descanso ", ci = true).trim()
    }

    private fun sentenceCase(line: String): String {
        val sb = StringBuilder(line.lowercase())
        val m = Rx.p("\\b(?:$ACRONYMS)\\b").matcher(sb.toString())
        val ranges = mutableListOf<IntRange>()
        while (m.find()) ranges += m.start() until m.end()
        for (r in ranges.reversed()) sb.replace(r.first, r.last + 1, sb.substring(r.first, r.last + 1).uppercase())
        var s = sb.toString()
        val first = s.split(Regex("[^\\p{L}]+")).firstOrNull { it.isNotEmpty() }.orEmpty()
        val keepLower = s.startsWith("(") ||
            (s.firstOrNull()?.isDigit() == true && first in setOf("a", "e", "x", "ou", "rounds", "round", "reps", "rep", "rodadas", "rodada"))
        if (!keepLower) {
            val i = s.indexOfFirst { it.isLetter() }
            if (i >= 0) s = s.substring(0, i) + s.substring(i, i + 1).uppercase() + s.substring(i + 1)
        }
        return s
    }

    /** Marca d'água do app do box e botões da tela dele */
    fun isNoise(line: String): Boolean {
        if (Rx.has(line, "^[\\d<>‹›]{1,2}$")) return true
        val key = line.lowercase().filter { it.isLetter() || it == ' ' || it == '-' }.trim()
        if (key in setOf("tecnofit", "nextfit", "next fit", "wodify", "sugarwod", "btwb", "pushpress", "push press app", "zen planner",
                         "check-in", "checkin", "ações", "acoes", "cross")) return true
        val words = key.replace("check-in", " checkin ").split(" ").filter { it.isNotEmpty() }
        val buttons = setOf("ver", "fazer", "ranking", "banking", "rankinq", "rankingcheckin", "checkin", "dicas", "nenhuma", "ações", "acoes", "curtir", "comentar")
        return words.isNotEmpty() && words.size <= 4 && words.all { it in buttons }
    }

    /** "19/10/2026", "17/10" (sem ano: este ano); cargas como "9/6kg" não contam */
    fun date(line: String, today: LocalDate = LocalDate.now()): LocalDate? {
        val m = match("(?<![\\d/])(\\d{1,2})/(\\d{1,2})(?:/(\\d{2,4}))?(?![\\d/])(?!\\s*(?:kg|lb))", line) ?: return null
        val d = m[1].toIntOrNull() ?: return null
        val mo = m[2].toIntOrNull() ?: return null
        if (d !in 1..31 || mo !in 1..12) return null
        var y = m[3].toIntOrNull() ?: today.year
        if (y < 100) y += 2000
        // O Calendar do iOS leva 31/04 para 01/05; aqui também
        return runCatching { LocalDate.of(y, mo, 1).plusDays((d - 1).toLong()) }.getOrNull()
    }

    fun intervals(lines: List<String>): WodFormat? {
        val rest = lines.firstNotNullOfOrNull(::restSeconds) ?: lines.firstNotNullOfOrNull(::inlineRest) ?: 0
        for (line in lines) {
            val m = match("^(\\d{1,2})\\s*(?:x|×|rounds?|rodadas?|blocos?)\\s*(?:de\\s*)?(?:amrap|e\\d?mom)", line) ?: continue
            val n = m[1].toIntOrNull() ?: continue
            if (n !in 2..12) continue
            when (val f = format(line)) {
                is WodFormat.Amrap -> return WodFormat.Intervals(List(n) { f.minutes }, rest, false)
                is WodFormat.Emom -> return WodFormat.Intervals(List(n) { f.minutes }, rest, true)
                else -> continue
            }
        }
        val blocks = lines.filter(::isOnlyFormat).mapNotNull(::format)
        val amraps = blocks.mapNotNull { (it as? WodFormat.Amrap)?.minutes }
        val emoms = blocks.mapNotNull { (it as? WodFormat.Emom)?.minutes }
        if (amraps.size > 1 && emoms.isEmpty()) return WodFormat.Intervals(amraps, rest, false)
        if (emoms.size > 1 && amraps.isEmpty()) return WodFormat.Intervals(emoms, rest, true)
        return null
    }

    private fun inlineRest(line: String): Int? {
        val m = match("(?:descanso|rest|pausa)\\s*:?\\s*(\\d{1,3})\\s*('|’|min|s\\b|seg|\")?", line) ?: return null
        val n = m[1].toIntOrNull() ?: return null
        return if (m[2].lowercase() in setOf("s", "seg", "\"")) n else n * 60
    }

    private fun blockMinutes(line: String): Int? = when (val f = format(line)) {
        is WodFormat.Amrap -> f.minutes
        is WodFormat.Emom -> f.minutes
        else -> null
    }

    private fun restSeconds(line: String): Int? {
        val m = match("^descanso\\s*(\\d{1,3})\\s*('|’|min|s\\b|seg|\")?", line) ?: return null
        val n = m[1].toIntOrNull() ?: return null
        return if (m[2].lowercase() in setOf("s", "seg", "\"")) n else n * 60
    }

    private fun header(line: String): Triple<Kind, String, String>? {
        val stripped = Rx.replace(line, "^([a-zA-Z0-9][).]|parte \\d+)\\s*", "", ci = true)
        val lower = stripped.lowercase()
        for ((kind, title0, words) in headers) {
            for (w in words) {
                if (!lower.startsWith(w)) continue
                val rest = stripped.drop(w.length)
                if (rest.isNotEmpty() && rest.first().isLetter()) continue
                var tail = rest.trim(' ', ':', '-', '–', '—', '|')
                tail = Rx.replace(tail, "^\\(\\s*\\)$", "")
                val title = if (w == "condicionamento" || w == "conditioning") "Condicionamento" else title0
                if (Rx.has(tail, "^\\d{1,2}/\\d{1,2}(/\\d{2,4})?$")) return Triple(kind, title, "")
                match("^\\(([^()]{2,30})\\)$", tail)?.get(1)?.let { inner ->
                    val name = if (w == "lpo") "LPO" else title
                    return Triple(kind, "$name (${inner.lowercase().capitalizedFirst()})", "")
                }
                if (Rx.has(tail, "^(\\d{1,2}|[a-z])$", ci = true)) return Triple(kind, "$title ${tail.uppercase()}", "")
                val sep = rest.trim(' ').firstOrNull()?.let { it in ":-–—|" } == true
                if (tail.isEmpty() || sep || format(tail) != null) return Triple(kind, title, tail)
            }
        }
        return null
    }

    /** Grupos do primeiro trecho que casa (sem distinção de caixa); grupo ausente vira "" */
    fun match(pattern: String, text: String): List<String>? {
        val m = Rx.p(pattern, ci = true).matcher(text)
        if (!m.find()) return null
        return (0..m.groupCount()).map { m.group(it) ?: "" }
    }

    private const val MINUTES = "(\\d{1,3})\\s*(?:'|’|min\\b|minutos|minutes)?"

    fun format(line: String): WodFormat? {
        (match("\\bamrap\\s*(?:de|in|em|:|-)?\\s*$MINUTES", line) ?: match("\\b$MINUTES\\s*(?:de\\s*)?amrap\\b", line))?.let { m ->
            val n = m[1].toIntOrNull()
            if (n != null && n in 1..90) return WodFormat.Amrap(n)
        }
        everyFormat(line)?.let { return it }
        (match("\\be1?mom\\s*(?:de|x|:|-)?\\s*$MINUTES", line) ?: match("\\b$MINUTES\\s*(?:de\\s*)?e1?mom\\b", line))?.let { m ->
            val n = m[1].toIntOrNull()
            if (n != null && n in 1..90) return WodFormat.Emom(n)
        }
        if (match("^(\\d{1,2})(?:\\s*(?:a|-|–|ou)\\s*\\d{1,2})?\\s*(?:rounds?|rodadas?|rfts?)\\b", line) != null &&
            match("amrap|e\\d?mom|tabata", line) == null) return WodFormat.ForTime(cap(line))
        if (match("\\btabata\\b", line) != null) {
            val rounds = match("(\\d{1,2})\\s*(?:x|rounds?|rodadas?)", line)?.get(1)?.toIntOrNull()?.takeIf { it in 1..20 }
            return WodFormat.Tabata(rounds ?: 8)
        }
        if (match("\\bfor\\s*time\\b|\\bft\\b|\\bpor\\s*tempo\\b", line) != null || cap(line) != null) return WodFormat.ForTime(cap(line))
        return null
    }

    private fun everyFormat(line: String): WodFormat? {
        var seconds: Int? = null
        match("\\be(\\d)mom\\b", line)?.get(1)?.toIntOrNull()?.let { if (it >= 2) seconds = it * 60 }
        val ms = match("\\b(?:a\\s*cada|every)\\s*(\\d{1,2})\\s*(?:'|’|min)\\s*(\\d{2})\\s*(?:\"|”|s\\b|seg)?", line)
        if (ms != null && ms[1].toIntOrNull() != null && ms[2].toIntOrNull() != null) {
            seconds = ms[1].toInt() * 60 + ms[2].toInt()
        } else {
            val m = match("\\b(?:a\\s*cada|every)\\s*(\\d{1,2})(?:[:,.](\\d{2}))?\\s*('|’|min|minutos|s\\b|seg|\")?", line)
            val n = m?.get(1)?.toIntOrNull()
            if (m != null && n != null) {
                val isSeconds = m[3].lowercase() in setOf("s", "seg", "\"")
                seconds = if (isSeconds) n else n * 60 + (m[2].toIntOrNull() ?: 0)
            }
        }
        val sec = seconds ?: return null
        val l = line.lowercase()
        if (sec < 15 || (sec == 60 && !l.contains("cada") && !l.contains("every"))) return null
        val total = match("\\b(?:durante|por|for|x)\\s*(\\d{1,3})\\s*(?:'|’|min)", line)?.get(1)?.toIntOrNull()
            ?: match("\\be\\dmom\\s*(?:de|x|:|-)?\\s*(\\d{1,3})", line)?.get(1)?.toIntOrNull()
        val m = minOf(total ?: 0, 90)
        return if (sec == 60 && m > 0) WodFormat.Emom(m) else WodFormat.Every(sec, m)
    }

    fun cap(line: String): Int? =
        match("\\b(?:tc|time\\s*cap|cap)\\s*(?:de|:|=|-)?\\s*$MINUTES", line)?.get(1)?.toIntOrNull()?.takeIf { it in 1..90 }

    private fun isOnlyFormat(line: String): Boolean {
        if (format(line) == null) return false
        val rest = Rx.replace(line.lowercase(),
            "amrap|e\\d?mom|a\\s*cada|every|durante|tabata|for\\s*time|\\bft\\b|por\\s*tempo|time\\s*cap|\\btc\\b|\\bcap\\b|min(?:utos|utes)?\\b|\\bde\\b|\\bem\\b|\\bin\\b|[0-9'’():=\\-–—.,\\s]", "")
        return rest.isEmpty()
    }
}

/** Esquema do WOD lido das linhas: rodadas-alvo, escada de reps e chipper (WodLoads.swift `WodScheme`) */
object WodScheme {
    fun rounds(lines: List<String>): Int? {
        for (line in lines) {
            val l = line.lowercase()
            Rx.find(l, "^(\\d{1,2})\\s*(?:rounds?|rodadas?|rft|x)\\b")?.let { r ->
                val n = r.takeWhile { it.isDigit() }.toIntOrNull()
                if (n != null && n in 2..30 && !l.contains("amrap") && !l.contains("mom")) return n
            }
            Rx.find(l, "\\brft\\s*(\\d{1,2})")?.let { r ->
                val n = r.filter { it.isDigit() }.toIntOrNull()
                if (n != null && n in 2..30) return n
            }
        }
        return null
    }

    fun ladder(lines: List<String>): List<Int>? {
        for (line in lines) {
            val r = Rx.find(line, "^\\d{1,3}(?:\\s*-\\s*\\d{1,3}){2,}") ?: continue
            val reps = r.split("-").mapNotNull { it.trim().toIntOrNull() }
            if (reps.size >= 3) return reps
        }
        return null
    }

    fun blocks(lines: List<String>): List<List<String>> {
        val groups = mutableListOf<MutableList<String>>()
        for (line in lines) {
            val l = line.lowercase()
            if (l.startsWith("descanso") || l.startsWith("rest")) continue
            if (WodParser.format(line) != null && WodMovements.identify(line).isEmpty() && line.codePointCount(0, line.length) <= 20) groups += mutableListOf<String>()
            else if (groups.isEmpty()) groups += mutableListOf(line)
            else groups.last() += line
        }
        return groups
    }

    fun isChipper(wod: Wod): Boolean {
        if (wod.format !is WodFormat.ForTime) return false
        return rounds(wod.lines) == null && ladder(wod.lines) == null && wod.lines.count { WodMovements.identify(it).isNotEmpty() } >= 3
    }
}

/** Série de carga do treino do coach: total com a barra */
data class WodSet(val weight: Double, val reps: Int, val bar: Double? = null) {
    val perSide: Double get() = maxOf((weight - (bar ?: 0.0)) / 2, 0.0)
}

data class WodLoad(val exerciseID: String, val part: Int, val sets: List<WodSet> = emptyList(), val removed: Boolean? = null)

object WodLoads {
    val barOptions = listOf(20.0, 15.0, 10.0)

    fun isWeighted(id: String): Boolean = Exercises.byID(id)?.type == ExerciseType.WEIGHTED
    fun weighted(lines: List<String>): List<String> = WodMovements.ids(lines).filter(::isWeighted)
    fun tracked(lines: List<String>, bodyweight: Boolean): List<String> = if (bodyweight) WodMovements.ids(lines) else weighted(lines)

    /** Reps escritas junto do movimento ("30 DU / 60 SU" → 30 para double under) */
    fun repsOf(id: String, lines: List<String>): Int? {
        for (line in lines) for (piece in line.split('/', ',', '+', ';')) {
            if (id !in WodMovements.ids(listOf(piece))) continue
            val n = piece.trim().takeWhile { it.isDigit() }.toIntOrNull()
            if (n != null && n > 0) return n
        }
        return null
    }

    /** Percentuais do PR na prescrição: "75% do PR", "70-75-80% 1RM" → [0.75…] */
    fun percents(lines: List<String>): List<Double> {
        val out = mutableListOf<Double>()
        val p = Rx.p("(\\d{2,3}(?:\\s*%?\\s*[-/–,e]\\s*\\d{2,3})*)\\s*%")
        for (line in lines) {
            val m = p.matcher(line)
            while (m.find()) out += m.group(1).split(Regex("[^0-9]+")).mapNotNull { it.toDoubleOrNull() }.filter { it in 30.0..110.0 }.map { it / 100 }
        }
        return out
    }

    /** 1RM estimado (PRs à mão e séries dos treinos), como total com a barra */
    fun oneRM(id: String, history: List<SessionLog>, manual: List<SetLog>, bar: Double): Double? {
        val ex = Exercises.byID(id)
        val platesOnly = ex?.usesBar == true && !(ex.weightIncludesBar())
        val sets = history.flatMap { it.sets }.filter { it.exerciseID == id && it.done } + manual.filter { it.exerciseID == id }
        return sets.mapNotNull { Progression.oneRM(if (platesOnly) it.weight + bar else it.weight, it.reps) }.maxOrNull()
    }

    fun weight(pct: Double, oneRM: Double, exerciseID: String, bar: Double): Double {
        val ex = Exercises.byID(exerciseID)
        val inc = ex?.increment ?: 2.5
        val w = roundHalfAwayFromZero(pct * oneRM / inc) * inc
        return if (ex?.usesBar == true) maxOf(w, bar) else w
    }

    /** Reps da prescrição ("5 REPS", "3x5", "5-4-3-2-1" → 5); sem número, 5 */
    fun reps(lines: List<String>): Int {
        for (line in lines) {
            Rx.find(line, "\\d+\\s*x\\s*(\\d+)", ci = true)?.let { r -> r.split(Regex("[^0-9]+")).lastOrNull { it.isNotEmpty() }?.toIntOrNull()?.let { return it } }
            Rx.find(line, "(\\d+)\\s*(?:reps?|repetições|repeticoes)", ci = true)?.let { r -> r.takeWhile { it.isDigit() }.toIntOrNull()?.let { return it } }
            Rx.find(line, "^(\\d+)(?:\\s*-\\s*\\d+)+")?.let { r -> r.takeWhile { it.isDigit() }.toIntOrNull()?.let { return it } }
        }
        return 5
    }

    fun next(after: List<WodSet>, exerciseID: String, reps: Int, history: List<SessionLog>, bar: Double,
             percents: List<Double> = emptyList(), oneRM: Double? = null): WodSet {
        val ex = Exercises.byID(exerciseID)
        if (!isWeighted(exerciseID)) return WodSet(0.0, after.lastOrNull()?.reps ?: reps)
        if (oneRM != null && percents.isNotEmpty()) {
            val pct = percents[minOf(after.size, percents.size - 1)]
            return WodSet(weight(pct, oneRM, exerciseID, bar), after.lastOrNull()?.reps ?: reps, if (ex?.usesBar == true) after.lastOrNull()?.bar ?: bar else null)
        }
        after.lastOrNull()?.let { return it }
        val s = Progression.suggest(exerciseID, 1, reps, history)
        if (ex?.usesBar != true) return WodSet(s.weight, reps)
        val total = if (s.weight > 0 && !ex.weightIncludesBar()) s.weight + bar else s.weight
        return WodSet(maxOf(total, bar), reps, bar)
    }

    fun text(loads: List<WodLoad>): String = loads.filter { it.sets.isNotEmpty() }.joinToString("; ") { l ->
        "${Exercises.name(l.exerciseID)} " + l.sets.joinToString(", ") { setText(it, l.exerciseID) }
    }

    fun setText(s: WodSet, id: String, spaced: Boolean = false): String {
        if (!isWeighted(id)) return "${s.reps} reps"
        return if (spaced) "${Progression.fmt(s.weight)} kg × ${s.reps}" else "${Progression.fmt(s.weight)}×${s.reps}"
    }

    /** Vira um treino com séries feitas, ligado à atividade (WodLoads.save) */
    fun session(loads: List<WodLoad>, title: String, activityUUID: String, date: java.time.Instant, minutes: Int, effort: Int,
                gymUUID: String?, defaultBar: Double): Session? {
        val filled = loads.filter { it.sets.isNotEmpty() }
        if (filled.isEmpty()) return null
        val totals = filled.any { Exercises.byID(it.exerciseID)?.crossfit == true }
        val sets = filled.flatMapIndexed { i, l ->
            l.sets.mapIndexed { k, set ->
                val w = if (totals || Exercises.byID(l.exerciseID)?.usesBar != true) set.weight else maxOf(set.weight - (set.bar ?: defaultBar), 0.0)
                LoggedSet(l.exerciseID, i, k, w, set.reps, rest = 120, done = true)
            }
        }
        return Session(Session.newID(), title, null, date, date.plusSeconds(maxOf(minutes, 1) * 60L), effort, activityUUID,
                       gymUUID = gymUUID, placeAsked = true, sets = sets)
    }
}
