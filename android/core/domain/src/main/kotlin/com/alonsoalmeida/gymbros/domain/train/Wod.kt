package com.alonsoalmeida.gymbros.domain.train

import com.alonsoalmeida.gymbros.domain.backup.AppleReferenceDate
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID

// Porte de Train/Wod.swift (formatos, benchmarks, resultado), WodRun.swift (estado do cronômetro), WodImport.swift
// (`PlannedWod`, `WodPlan`) e WodTimeline.swift. O JSON de `WodFormat` e de `PlannedWod` é o do `JSONEncoder` do iOS
// (enum com valores associados: `{"amrap":{"minutes":12}}`; datas em segundos desde 2001).

sealed interface WodFormat {
    data class ForTime(val capMinutes: Int?) : WodFormat
    data class Amrap(val minutes: Int) : WodFormat
    data class Emom(val minutes: Int) : WodFormat
    data class Tabata(val rounds: Int) : WodFormat
    /** Blocos com descanso entre eles: minutos de cada bloco e segundos de descanso */
    data class Intervals(val blocks: List<Int>, val rest: Int, val emom: Boolean) : WodFormat
    /** E2MOM, "a cada 2' durante 10'": minutos 0 = sem fim */
    data class Every(val seconds: Int, val minutes: Int) : WodFormat

    val name: String
        get() = when (this) {
            is ForTime -> "For Time"
            is Amrap -> "AMRAP $minutes min"
            is Emom -> "EMOM $minutes min"
            is Every -> "A cada ${restText(seconds)}" + if (minutes > 0) " · $minutes min" else ""
            is Tabata -> "Tabata $rounds×(20s/10s)"
            is Intervals -> (if (blocks.toSet().size == 1) "${blocks.size}× ${if (emom) "EMOM" else "AMRAP"} ${blocks[0]}'"
                             else "${if (emom) "EMOM" else "AMRAP"} " + blocks.joinToString("+") { "$it'" }) +
                (if (rest > 0) " · descanso ${restText(rest)}" else "")
        }

    val detail: String
        get() = when (this) {
            is ForTime -> "Complete tudo o mais rápido possível" + (capMinutes?.let { " (limite de $it min)" } ?: "")
            is Amrap -> "O máximo de rodadas e repetições no tempo"
            is Emom -> "No começo de cada minuto, faça o trabalho; descanse o que sobrar"
            is Every -> "No começo de cada intervalo de ${restText(seconds)}, faça o trabalho; descanse o que sobrar"
            is Tabata -> "20 segundos de esforço máximo, 10 de descanso"
            is Intervals -> if (emom) "${blocks.size} blocos de EMOM com descanso entre eles" else "${blocks.size} blocos: o máximo de rodadas em cada um, com descanso entre eles"
        }

    val lowerIsBetter: Boolean get() = this is ForTime

    val totalSeconds: Int?
        get() = when (this) {
            is ForTime -> capMinutes?.let { it * 60 }
            is Amrap -> minutes * 60
            is Emom -> minutes * 60
            is Tabata -> rounds * 30
            is Intervals -> blocks.sum() * 60 + rest * maxOf(blocks.size - 1, 0)
            is Every -> if (minutes > 0) minutes * 60 else null
        }

    val segments: List<WodSegment>
        get() {
            if (this !is Intervals) return emptyList()
            return blocks.flatMapIndexed { i, m ->
                listOf(WodSegment(i, false, m * 60)) + if (i < blocks.size - 1 && rest > 0) listOf(WodSegment(i, true, rest)) else emptyList()
            }
        }

    /** Trecho em que está aos `elapsed` segundos e quanto falta nele */
    fun segment(elapsed: Int): Pair<WodSegment, Int>? {
        var t = elapsed
        for (seg in segments) {
            if (t < seg.seconds) return seg to (seg.seconds - t)
            t -= seg.seconds
        }
        return segments.lastOrNull()?.let { it to 0 }
    }

    fun toJson(): JsonObject = when (this) {
        is ForTime -> buildJsonObject { put("forTime", buildJsonObject { capMinutes?.let { put("capMinutes", it) } }) }
        is Amrap -> buildJsonObject { put("amrap", buildJsonObject { put("minutes", minutes) }) }
        is Emom -> buildJsonObject { put("emom", buildJsonObject { put("minutes", minutes) }) }
        is Tabata -> buildJsonObject { put("tabata", buildJsonObject { put("rounds", rounds) }) }
        is Intervals -> buildJsonObject {
            put("intervals", buildJsonObject {
                put("blocks", JsonArray(blocks.map { JsonPrimitive(it) })); put("rest", rest); put("emom", emom)
            })
        }
        is Every -> buildJsonObject { put("every", buildJsonObject { put("seconds", seconds); put("minutes", minutes) }) }
    }

    companion object {
        fun restText(s: Int): String = if (s % 60 == 0) "${s / 60}'" else "${s}s"

        fun fromJson(e: JsonElement?): WodFormat? {
            val o = e as? JsonObject ?: return null
            val (k, v) = o.entries.firstOrNull() ?: return null
            val b = v as? JsonObject ?: JsonObject(emptyMap())
            fun int(n: String) = (b[n] as? JsonPrimitive)?.intOrNull
            return when (k) {
                "forTime" -> ForTime(int("capMinutes"))
                "amrap" -> Amrap(int("minutes") ?: return null)
                "emom" -> Emom(int("minutes") ?: return null)
                "tabata" -> Tabata(int("rounds") ?: return null)
                "intervals" -> Intervals((b["blocks"] as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.intOrNull } ?: return null,
                                         int("rest") ?: 0, (b["emom"] as? JsonPrimitive)?.booleanOrNull ?: false)
                "every" -> Every(int("seconds") ?: return null, int("minutes") ?: 0)
                else -> null
            }
        }
    }
}

data class WodSegment(val block: Int, val rest: Boolean, val seconds: Int)

/** Parte do treino que não é cronometrada (aquecimento, força, skill…) */
data class WodPart(val title: String, val lines: List<String>)

/** Um nível do WOD (Scale, Amador, RX…) com o seu formato e as suas linhas */
data class WodLevelOption(val title: String, val format: WodFormat, val lines: List<String>) {
    companion object {
        fun parsing(title: String, lines: List<String>): WodLevelOption {
            val d = WodParser.fill(WodDraft(), lines.filter { !WodParser.isNoise(it) })
            return WodLevelOption(title, d.format, d.lines)
        }
    }
}

data class Wod(
    val id: String,
    val name: String,
    val category: String,
    val format: WodFormat,
    val lines: List<String>,
    val exercises: List<String> = emptyList(),
    val parts: List<WodPart> = emptyList(),
    val levels: List<WodLevelOption>? = null,
    val level: String? = null,
) {
    fun withLevel(title: String): Wod {
        val o = levels?.firstOrNull { it.title == title } ?: return this
        return Wod(id, name, category, o.format, o.lines, WodMovements.ids(o.lines), parts, levels, title)
    }

    companion object {
        val benchmarks = listOf(
            Wod("fran", "Fran", "Girls", WodFormat.ForTime(10), listOf("21-15-9 repetições de:", "Thruster (43/30 kg)", "Pull-up"), listOf("thruster", "cf-kipping-pull-up")),
            Wod("grace", "Grace", "Girls", WodFormat.ForTime(10), listOf("30 clean and jerks (61/43 kg)"), listOf("cf-clean-jerk")),
            Wod("isabel", "Isabel", "Girls", WodFormat.ForTime(10), listOf("30 snatches (61/43 kg)"), listOf("cf-snatch")),
            Wod("diane", "Diane", "Girls", WodFormat.ForTime(15), listOf("21-15-9 repetições de:", "Levantamento terra (102/70 kg)", "Handstand push-up"),
                listOf("levantamento-terra", "cf-hspu")),
            Wod("elizabeth", "Elizabeth", "Girls", WodFormat.ForTime(15), listOf("21-15-9 repetições de:", "Squat clean (61/43 kg)", "Ring dip"),
                listOf("cf-squat-clean", "cf-ring-dip")),
            Wod("helen", "Helen", "Girls", WodFormat.ForTime(20), listOf("3 rodadas de:", "400 m de corrida", "21 kettlebell swings (24/16 kg)", "12 pull-ups"),
                listOf("esteira", "kettlebell-swing", "cf-kipping-pull-up")),
            Wod("cindy", "Cindy", "Girls", WodFormat.Amrap(20), listOf("5 pull-ups", "10 flexões", "15 agachamentos"),
                listOf("cf-kipping-pull-up", "flexao", "agachamento-livre-corpo")),
            Wod("annie", "Annie", "Girls", WodFormat.ForTime(15), listOf("50-40-30-20-10 repetições de:", "Double unders", "Abdominal (sit-up)"),
                listOf("cf-double-under", "abdominal-completo")),
            Wod("karen", "Karen", "Girls", WodFormat.ForTime(15), listOf("150 wall balls (9/6 kg)"), listOf("cf-wall-ball")),
            Wod("jackie", "Jackie", "Girls", WodFormat.ForTime(15), listOf("1000 m de remo", "50 thrusters (20/15 kg)", "30 pull-ups"),
                listOf("cf-row-cal", "thruster", "cf-kipping-pull-up")),
            Wod("nancy", "Nancy", "Girls", WodFormat.ForTime(20), listOf("5 rodadas de:", "400 m de corrida", "15 overhead squats (43/30 kg)"),
                listOf("esteira", "cf-overhead-squat")),
            Wod("kelly", "Kelly", "Girls", WodFormat.ForTime(35), listOf("5 rodadas de:", "400 m de corrida", "30 box jumps (60/50 cm)", "30 wall balls (9/6 kg)"),
                listOf("esteira", "cf-box-jump", "cf-wall-ball")),
            Wod("chelsea", "Chelsea", "Girls", WodFormat.Emom(30), listOf("A cada minuto:", "5 pull-ups", "10 flexões", "15 agachamentos"),
                listOf("cf-kipping-pull-up", "flexao", "agachamento-livre-corpo")),
            Wod("murph", "Murph", "Heróis", WodFormat.ForTime(60), listOf("1 milha (1,6 km) de corrida", "100 pull-ups", "200 flexões", "300 agachamentos",
                                                                              "1 milha (1,6 km) de corrida", "Com colete de 9/6 kg; dá para dividir as repetições"),
                listOf("esteira", "cf-kipping-pull-up", "flexao", "agachamento-livre-corpo")),
            Wod("dt", "DT", "Heróis", WodFormat.ForTime(20), listOf("5 rodadas de:", "12 levantamentos terra (70/47 kg)", "9 hang power cleans", "6 push jerks"),
                listOf("levantamento-terra", "cf-hang-power-clean", "cf-push-jerk")),
        )

        fun byID(id: String): Wod? = benchmarks.firstOrNull { it.id == id }
    }
}

/** Resultado de WOD (Models/WodResult.swift); campos da cópia da conta (`wods`) */
data class WodResult(
    val uuid: String,
    val wodID: String,
    val wodName: String,
    val formatName: String,
    val date: Instant,
    val seconds: Int? = null,
    val rounds: Int? = null,
    val reps: Int? = null,
    val rx: Boolean = true,
    val note: String = "",
    val activityUUID: String? = null,
    val capped: Boolean = false,
) {
    val text: String
        get() {
            if (capped) return "CAP" + if ((reps ?: 0) > 0) " · $reps reps" else ""
            seconds?.let { return clock(it) }
            rounds?.let { return "$it rodadas" + if ((reps ?: 0) > 0) " + $reps" else "" }
            return "Concluído"
        }

    /** Para comparar resultados (maior = melhor) */
    val score: Double
        get() {
            if (capped) return -10_000_000.0 + (reps ?: 0)
            seconds?.let { return -it.toDouble() }
            return (rounds ?: 0) * 1000.0 + (reps ?: 0)
        }
}

/** WOD do coach importado (WodImport.swift `PlannedWod`) */
data class PlannedWod(
    val id: String = UUID.randomUUID().toString().uppercase(),
    val day: Instant,
    val name: String,
    val format: WodFormat,
    val lines: List<String>,
    val parts: List<WodPart> = emptyList(),
    val levels: List<WodLevelOption>? = null,
    val level: String? = null,
) {
    val wodID: String get() = "coach-$id"

    fun wod(preferredLevel: String? = null): Wod {
        var parts = this.parts
        var levels = this.levels
        // Importados antes da troca de nível no treino: os outros níveis estavam nas partes
        val others = parts.filter { it.title.startsWith(OTHER_LEVEL) }
        if (levels == null && others.isNotEmpty()) {
            parts = parts.filter { !it.title.startsWith(OTHER_LEVEL) }
            val otherTitles = others.map { it.title.removePrefix(OTHER_LEVEL) }
            val mine = level ?: preferredLevel?.takeIf { it !in otherTitles } ?: "Escolhido"
            levels = listOf(WodLevelOption(mine, blocksFormat, lines)) + otherTitles.zip(others).map { (t, p) -> WodLevelOption.parsing(t, p.lines) }
        }
        val chosen = level ?: levels?.firstOrNull()?.title
        return Wod(wodID, name, "Coach", blocksFormat, WodParser.expandComplexes(lines), WodMovements.ids(lines),
                   parts.map { WodPart(it.title, WodParser.expandComplexes(it.lines)) },
                   levels?.map { WodLevelOption(it.title, it.format, WodParser.expandComplexes(it.lines)) }, chosen)
    }

    /** Importados antes dos blocos viraram um AMRAP/EMOM só com o tempo somado: os blocos voltam a partir das linhas */
    private val blocksFormat: WodFormat
        get() = when (format) { is WodFormat.Amrap, is WodFormat.Emom -> WodParser.intervals(lines) ?: format; else -> format }

    fun toJson(): JsonObject = buildJsonObject {
        put("id", id)
        put("day", AppleReferenceDate.fromInstant(day))
        put("name", name)
        put("format", format.toJson())
        put("lines", JsonArray(lines.map { JsonPrimitive(it) }))
        put("parts", JsonArray(parts.map { partJson(it) }))
        levels?.let { l -> put("levels", JsonArray(l.map { buildJsonObject { put("title", it.title); put("format", it.format.toJson()); put("lines", strings(it.lines)) } })) }
        level?.let { put("level", it) }
    }

    companion object {
        const val OTHER_LEVEL = "Outro nível: "
        private fun strings(l: List<String>) = JsonArray(l.map { JsonPrimitive(it) })
        private fun partJson(p: WodPart) = buildJsonObject { put("title", p.title); put("lines", strings(p.lines)) }
        private fun lines(e: JsonElement?) = (e as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.content }.orEmpty()

        fun fromJson(e: JsonElement): PlannedWod? = runCatching {
            val o = e.jsonObject
            PlannedWod(
                id = o["id"]!!.jsonPrimitive.content,
                day = AppleReferenceDate.toInstant(o["day"]!!.jsonPrimitive.doubleOrNull!!),
                name = o["name"]!!.jsonPrimitive.content,
                format = WodFormat.fromJson(o["format"])!!,
                lines = lines(o["lines"]),
                parts = (o["parts"] as? JsonArray)?.map { p -> WodPart(p.jsonObject["title"]!!.jsonPrimitive.content, lines(p.jsonObject["lines"])) }.orEmpty(),
                levels = (o["levels"] as? JsonArray)?.mapNotNull { l ->
                    val x = l.jsonObject
                    WodLevelOption(x["title"]!!.jsonPrimitive.content, WodFormat.fromJson(x["format"]) ?: return@mapNotNull null, lines(x["lines"]))
                },
                level = (o["level"] as? JsonPrimitive)?.content,
            )
        }.getOrNull()
    }
}

/** WODs do coach importados (`plannedWods`, texto JSON nos ajustes da conta) */
object WodPlan {
    const val KEY = "plannedWods"

    fun all(raw: String?): List<PlannedWod> {
        if (raw.isNullOrEmpty()) return emptyList()
        return runCatching { kotlinx.serialization.json.Json.parseToJsonElement(raw).jsonArray.mapNotNull(PlannedWod::fromJson) }
            .getOrDefault(emptyList()).sortedBy { it.day }
    }

    fun encode(list: List<PlannedWod>): String = JsonArray(list.map { it.toJson() }).toString()

    fun save(raw: String?, p: PlannedWod): String = encode(all(raw).filter { it.id != p.id } + p)
    fun delete(raw: String?, p: PlannedWod): String = encode(all(raw).filter { it.id != p.id })

    /** WOD de um dia que ainda não tem resultado salvo */
    fun pending(raw: String?, done: Set<String>, day: LocalDate, zone: ZoneId): PlannedWod? =
        all(raw).firstOrNull { it.day.atZone(zone).toLocalDate() == day && it.wodID !in done }
}

/** WOD em andamento (WodRun.swift `WodRunState`): relógio de parede, sobrevive a fechar o app */
data class WodRunState(
    val wod: Wod,
    val openedAt: Instant,
    val startedAt: Instant? = null,
    val pausedAt: Instant? = null,
    /** Segundos pausados */
    val pausedTotal: Double = 0.0,
    val countdownEnd: Instant? = null,
    val rounds: Int = 0,
    val gymID: String? = null,
    val placeAsked: Boolean = false,
    val sessionStart: Instant? = null,
    /** Parte na tela; igual a `wod.parts.size` é o WOD */
    val phase: Int = 0,
    val phaseStart: Instant? = null,
    val workingPhase: Int? = null,
    val partSeconds: Map<Int, Double> = emptyMap(),
    val blockRounds: List<Int> = emptyList(),
    val loads: List<WodLoad> = emptyList(),
    val partTimers: Map<Int, Instant> = emptyMap(),
    /** Linhas riscadas no chipper */
    val checked: List<Int> = emptyList(),
) {
    val onWod: Boolean get() = phase >= wod.parts.size
    val working: Int get() = workingPhase ?: phase

    private fun secs(a: Instant, b: Instant): Double = (b.toEpochMilli() - a.toEpochMilli()) / 1000.0

    fun partElapsed(i: Int, now: Instant): Double =
        (partSeconds[i] ?: 0.0) + if (i == working) maxOf(secs(phaseStart ?: now, now), 0.0) else 0.0

    fun view(i: Int) = copy(phase = i)

    fun work(i: Int, now: Instant): WodRunState {
        var s = copy(sessionStart = sessionStart ?: now)
        if (phaseStart != null && i != working) s = s.copy(partSeconds = partSeconds + (working to partElapsed(working, now)))
        if (phaseStart == null || i != working) s = s.copy(workingPhase = i, phaseStart = now)
        return s.copy(phase = i)
    }

    fun resetPart(i: Int, now: Instant): WodRunState {
        var s = copy(partSeconds = partSeconds - i)
        if (i == working) s = s.copy(phaseStart = now)
        return s
    }

    fun elapsed(now: Instant): Double {
        val st = startedAt ?: return 0.0
        return secs(st, pausedAt ?: now) - pausedTotal
    }

    fun workBlock(now: Instant): Int? {
        val seg = wod.format.segment(elapsed(now).toInt())?.first ?: return null
        return if (seg.rest) null else seg.block
    }

    fun addRound(now: Instant): WodRunState {
        val f = wod.format as? WodFormat.Intervals ?: return copy(rounds = rounds + 1)
        val i = workBlock(now) ?: return this
        val b = blockRounds + List(maxOf(f.blocks.size - blockRounds.size, 0)) { 0 }
        return copy(blockRounds = b.mapIndexed { k, v -> if (k == i) v + 1 else v })
    }

    fun removeRound(now: Instant): WodRunState {
        if (wod.format !is WodFormat.Intervals) return copy(rounds = maxOf(rounds - 1, 0))
        val i = workBlock(now) ?: return this
        if (i !in blockRounds.indices) return this
        return copy(blockRounds = blockRounds.mapIndexed { k, v -> if (k == i) maxOf(v - 1, 0) else v })
    }

    fun roundsShown(now: Instant): Int {
        if (wod.format !is WodFormat.Intervals) return rounds
        return workBlock(now)?.let { blockRounds.getOrNull(it) ?: 0 } ?: 0
    }
}

/** Linha do tempo dos WODs (WodTimeline.swift) */
data class WodTimelineEntry(val id: String, val day: Instant, val name: String, val format: String, val lines: List<String>,
                            val plan: PlannedWod?, val results: List<WodResult>) {
    enum class Status { DONE, TODAY, SCHEDULED, MISSED }

    fun status(now: Instant, zone: ZoneId): Status {
        if (results.isNotEmpty()) return Status.DONE
        if (day.atZone(zone).toLocalDate() == now.atZone(zone).toLocalDate()) return Status.TODAY
        return if (day > now) Status.SCHEDULED else Status.MISSED
    }

    companion object {
        fun build(plans: List<PlannedWod>, results: List<WodResult>): List<WodTimelineEntry> {
            val byWod = results.groupBy { it.wodID }
            val planIDs = plans.map { it.wodID }.toSet()
            val imported = plans.map { p ->
                WodTimelineEntry(p.wodID, p.day, p.name, p.format.name, p.lines, p, byWod[p.wodID].orEmpty().sortedByDescending { it.score })
            }
            val others = results.filter { it.wodID !in planIDs }.map { r ->
                WodTimelineEntry(r.uuid, r.date, r.wodName, r.formatName, Wod.byID(r.wodID)?.lines.orEmpty(), null, listOf(r))
            }
            return (imported + others).sortedByDescending { it.day }
        }
    }
}
