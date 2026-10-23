package com.alonsoalmeida.gymbros.domain.leagues

import com.alonsoalmeida.gymbros.domain.ActivityKind
import com.alonsoalmeida.gymbros.domain.ActivityPointRule
import com.alonsoalmeida.gymbros.domain.BroCatalog
import com.alonsoalmeida.gymbros.domain.RuleClock
import com.alonsoalmeida.gymbros.domain.ScoreInput
import com.alonsoalmeida.gymbros.domain.SeededRandom
import com.alonsoalmeida.gymbros.domain.WorkoutType
import com.alonsoalmeida.gymbros.domain.backup.AppleReferenceDate
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.longOrNull
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

// Regras extras de uma liga (LeagueRules.swift e CheckInProof.swift): verificação do check-in, revisão do dono, pose do
// dia, tabela de pontos, limites, metas e moderação. Ficam em `League.settingsRaw` (JSON). O iPhone grava com o
// JSONEncoder padrão: datas em segundos desde 2001 (`.deferredToDate`) e chaves em ordem. O que o Android não conhece no
// JSON passa intacto (`extra`).

internal object J {
    val json = Json { ignoreUnknownKeys = true }
    fun obj(raw: String?): JsonObject? = raw?.takeIf { it.isNotBlank() }?.let { runCatching { json.parseToJsonElement(it) as? JsonObject }.getOrNull() }
    fun str(o: JsonObject, k: String): String? = (o[k] as? JsonPrimitive)?.takeIf { it.isString }?.content
    fun bool(o: JsonObject, k: String): Boolean? = (o[k] as? JsonPrimitive)?.booleanOrNull
    fun int(o: JsonObject, k: String): Int? = (o[k] as? JsonPrimitive)?.let { it.intOrNull ?: it.doubleOrNull?.toInt() }
    fun dbl(o: JsonObject, k: String): Double? = (o[k] as? JsonPrimitive)?.doubleOrNull
    fun date(o: JsonObject, k: String): Instant? = dbl(o, k)?.let(AppleReferenceDate::toInstant)
    fun strings(o: JsonObject, k: String): List<String> = (o[k] as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.takeIf { p -> p.isString }?.content }.orEmpty()
    fun date(i: Instant): JsonPrimitive = JsonPrimitive(AppleReferenceDate.fromInstant(i))
    fun list(l: List<String>) = JsonArray(l.map { JsonPrimitive(it) })
    /** Chaves em ordem, como o `.sortedKeys` do iOS */
    fun sorted(m: Map<String, JsonElement>): JsonObject = JsonObject(m.toSortedMap())
}

/** Calendário das regras (Swiss.calendar / League.rulesCalendar): fuso de Brasília, semana começando no domingo (1) */
data class RulesCalendar(val zone: ZoneId = RuleClock.LEAGUE_ZONE, val firstWeekday: Int = 1) {
    fun day(i: Instant): LocalDate = i.atZone(zone).toLocalDate()
    fun startOfDay(i: Instant): Instant = day(i).atStartOfDay(zone).toInstant()
    fun start(d: LocalDate): Instant = d.atStartOfDay(zone).toInstant()
    fun sameDay(a: Instant, b: Instant) = day(a) == day(b)

    /** Início da semana que contém o dia (o `dateInterval(of: .weekOfYear)` do iOS, com o `firstWeekday`) */
    fun weekStart(d: LocalDate): LocalDate {
        val dow = d.dayOfWeek.value % 7 + 1 // domingo = 1, como o Calendar do iOS
        return d.minusDays(((dow - firstWeekday + 7) % 7).toLong())
    }

    fun weekInterval(i: Instant): Pair<Instant, Instant> { val s = weekStart(day(i)); return start(s) to start(s.plusDays(7)) }
    fun monthInterval(i: Instant): Pair<Instant, Instant> { val s = day(i).withDayOfMonth(1); return start(s) to start(s.plusMonths(1)) }
    fun yearInterval(i: Instant): Pair<Instant, Instant> { val s = day(i).withDayOfYear(1); return start(s) to start(s.plusYears(1)) }

    companion object { val RULES = RulesCalendar() }
}

// MARK: - Verificação

enum class VerificationPreset(val raw: String, val label: String, val detail: String) {
    OFF("off", "Desligada", "Nenhuma regra: qualquer check-in vale, com ou sem prova."),
    PADRAO("padrao", "Padrão", "A experiência clássica: foto da câmera ou da galeria, e dá para postar treino de qualquer dia."),
    VERIFICADO("verificado", "Bro-verificação", "Equilíbrio recomendado entre justiça e facilidade: check-in só no mesmo dia e foto da galeria só com hora verificada."),
    PERSONALIZADO("personalizado", "Personalizar", "Monte suas próprias regras.");
    companion object { fun of(r: String?) = entries.firstOrNull { it.raw == r } }
}

enum class MediaPolicy(val raw: String, val label: String, val detail: String) {
    ALWAYS("always_required", "Sempre", "Foto é obrigatória em todo check-in."),
    DEVICE_OPTIONAL("device_optional", "Dispensa com aparelho", "Foto não é obrigatória quando o treino foi gravado por um aparelho (Apple Watch, Apple Saúde ou GPS do app) ou numa visita verificada na academia."),
    NEVER("never_required", "Opcional", "Foto é opcional.");
    companion object { fun of(r: String?) = entries.firstOrNull { it.raw == r } }
}

enum class LibraryMediaPolicy(val raw: String, val label: String, val detail: String) {
    ALLOW_ALL("allow_all", "Liberada", "Qualquer foto da galeria pode ir no check-in."),
    VERIFIED_ONLY("verified_only", "Só verificada", "Foto da galeria só se a hora dela for válida: tirada no mesmo dia do treino, e não depois de agora."),
    DISABLED("disabled", "Proibida", "Nunca da galeria: a foto tem que ser tirada na câmera do app.");
    companion object { fun of(r: String?) = entries.firstOrNull { it.raw == r } }
}

enum class CheckInTimePolicy(val raw: String, val label: String, val detail: String) {
    NONE("none", "Livre", "Sem restrição de horário."),
    SAME_DAY("same_day", "Mesmo dia", "O treino tem que ser do mesmo dia da foto ou do aparelho; a hora pode mudar."),
    STRICT("strict", "Exata", "O horário do treino tem que bater com o da foto ou do aparelho.");
    companion object { fun of(r: String?) = entries.firstOrNull { it.raw == r } }
}

data class VerificationProblem(val kind: String, val message: String, val fix: String)

/** De onde veio a foto do check-in (CheckInProof.swift `PhotoProof`) */
data class PhotoProof(val source: String, val takenAt: Instant? = null, val hasLocation: Boolean = false) {
    /** A hora da foto da galeria serve como verificada: existe, é do mesmo dia do treino e não é do futuro */
    fun timeIsValid(workout: Instant, now: Instant, cal: RulesCalendar): Boolean {
        if (source == CAMERA) return true
        val t = takenAt ?: return false
        return t <= now.plusSeconds(60) && cal.sameDay(t, workout)
    }

    fun json(): JsonObject = J.sorted(buildMap {
        put("source", JsonPrimitive(source))
        takenAt?.let { put("takenAt", J.date(it)) }
        put("hasLocation", JsonPrimitive(hasLocation))
    })

    companion object {
        const val CAMERA = "camera"
        const val LIBRARY = "library"
        fun parse(o: JsonObject): PhotoProof? = J.str(o, "source")?.let { PhotoProof(it, J.date(o, "takenAt"), J.bool(o, "hasLocation") ?: false) }
    }
}

/** Uma atividade agrupada num check-in (CheckInProof.swift `ScorePart`) */
data class ScorePart(val kindRaw: String, val minutes: Int, val effort: Int, val meters: Double? = null, val kcal: Double? = null,
                     val workoutTypeID: Long? = null) {
    val input: ScoreInput get() {
        val kind = ActivityKind.of(kindRaw)
        return ScoreInput(kind, minutes, effort, meters, kcal, workoutTypeID ?: BroCatalog.classicType[kind.raw])
    }

    fun json(): JsonObject = J.sorted(buildMap {
        put("kindRaw", JsonPrimitive(kindRaw)); put("minutes", JsonPrimitive(minutes)); put("effort", JsonPrimitive(effort))
        meters?.let { put("meters", JsonPrimitive(it)) }; kcal?.let { put("kcal", JsonPrimitive(it)) }
        workoutTypeID?.let { put("workoutTypeID", JsonPrimitive(it)) }
    })

    companion object {
        fun parse(o: JsonObject) = ScorePart(J.str(o, "kindRaw") ?: "outro", J.int(o, "minutes") ?: 0, J.int(o, "effort") ?: 5,
                                             J.dbl(o, "meters"), J.dbl(o, "kcal"), (o["workoutTypeID"] as? JsonPrimitive)?.longOrNull)
    }
}

/** A prova do check-in (CheckInProof.swift `CheckInProof`), guardada em `proofRaw` */
data class CheckInProof(
    val photo: PhotoProof? = null,
    val deviceRecorded: Boolean = false,
    val device: String? = null,
    val pose: String? = null,
    val gymVisit: String? = null,
    val grouped: List<String> = emptyList(),
    val groupedParts: List<ScorePart> = emptyList(),
) {
    val rawValue: String get() {
        if (this == CheckInProof()) return ""
        return J.sorted(buildMap {
            photo?.let { put("photo", it.json()) }
            put("deviceRecorded", JsonPrimitive(deviceRecorded))
            device?.let { put("device", JsonPrimitive(it)) }
            pose?.let { put("pose", JsonPrimitive(it)) }
            gymVisit?.let { put("gymVisit", JsonPrimitive(it)) }
            put("grouped", J.list(grouped))
            put("groupedParts", JsonArray(groupedParts.map { it.json() }))
        }).toString()
    }

    /** Linhas para o detalhe do check-in */
    val lines: List<String> get() = buildList {
        photo?.let { add(photoLabel(it)) }
        if (deviceRecorded) add(device?.let { "Gravado no $it" } ?: "Gravado por aparelho")
        gymVisit?.let { add("📍 Visita verificada na $it") }
        DailyPose.byID(pose)?.let { add("${it.emoji} Pose do dia: ${it.name}") }
    }

    companion object {
        fun parse(raw: String?): CheckInProof {
            val o = J.obj(raw) ?: return CheckInProof()
            return CheckInProof(
                photo = (o["photo"] as? JsonObject)?.let(PhotoProof::parse),
                deviceRecorded = J.bool(o, "deviceRecorded") ?: false,
                device = J.str(o, "device"), pose = J.str(o, "pose"), gymVisit = J.str(o, "gymVisit"),
                grouped = J.strings(o, "grouped").map { it.uppercase() },
                groupedParts = (o["groupedParts"] as? JsonArray)?.mapNotNull { (it as? JsonObject)?.let(ScorePart::parse) }.orEmpty(),
            )
        }

        /** Só o modelo do aparelho que gravou: o nome no Saúde costuma levar o da pessoa ("iPhone de Ana") */
        fun publicDevice(name: String?): String? = name?.let { n -> listOf("Apple Watch", "iPhone", "iPad").firstOrNull { n.contains(it, ignoreCase = true) } }

        /** "Tirada na câmera do app", "Da galeria · tirada 21/10 07:42", "Da galeria, sem hora gravada" */
        fun photoLabel(p: PhotoProof, zone: ZoneId = ZoneId.systemDefault()): String {
            if (p.source == PhotoProof.CAMERA) return "Tirada na câmera do app"
            val t = p.takenAt ?: return "Da galeria, sem hora gravada"
            val z = t.atZone(zone)
            return "Da galeria · tirada %02d/%02d %02d:%02d".format(z.dayOfMonth, z.monthValue, z.hour, z.minute)
        }
    }
}

/** O treino que vai ser postado, com o que serve de prova (LeagueRules.swift `PostSubject`) */
data class PostSubject(
    val workoutTypeID: Long?,
    val date: Instant,
    val minutes: Int,
    val deviceRecorded: Boolean = false,
    val place: String? = null,
    val photo: PhotoProof? = null,
    val gymVisit: String? = null,
) {
    val hasLocation: Boolean get() = place != null || gymVisit != null || photo?.hasLocation == true

    fun verifiedTimes(now: Instant): List<Instant> = buildList {
        if (deviceRecorded || gymVisit != null) add(date)
        photo?.let { p -> if (p.source == PhotoProof.CAMERA) add(p.takenAt ?: now) else p.takenAt?.let { add(it) } }
    }

    fun fits(t: Instant): Boolean =
        t >= date.minusSeconds(CheckInVerification.STRICT_BEFORE) && t <= date.plusSeconds(minutes * 60L + CheckInVerification.STRICT_AFTER)
}

data class CheckInVerification(
    val preset: VerificationPreset,
    val media: MediaPolicy,
    val library: LibraryMediaPolicy,
    val time: CheckInTimePolicy,
    /** Quantos dias para trás dá para postar: -1 = qualquer data, 0 = só hoje */
    val backlogDays: Int,
    val locationRequired: Boolean,
    val deviceRequired: Boolean,
) {
    val bullets: List<String> get() {
        if (preset == VerificationPreset.OFF) return listOf("Qualquer check-in vale, com ou sem prova")
        val out = mutableListOf<String>()
        out += when (media) {
            MediaPolicy.ALWAYS -> "Foto sempre obrigatória"
            MediaPolicy.DEVICE_OPTIONAL -> "Foto dispensada quando o treino foi gravado por um aparelho"
            MediaPolicy.NEVER -> "Foto opcional"
        }
        out += when (library) {
            LibraryMediaPolicy.ALLOW_ALL -> "Câmera do app e galeria liberadas"
            LibraryMediaPolicy.VERIFIED_ONLY -> "Câmera do app liberada; galeria só com hora verificada"
            LibraryMediaPolicy.DISABLED -> "Só a câmera do app: galeria proibida"
        }
        when (time) {
            CheckInTimePolicy.NONE -> {}
            CheckInTimePolicy.SAME_DAY -> out += "O treino tem que ser do mesmo dia da foto ou do aparelho"
            CheckInTimePolicy.STRICT -> out += "O horário do treino tem que bater com o da foto ou do aparelho"
        }
        out += when (backlogDays) {
            -1 -> "Pode postar treino de qualquer data"
            0 -> "Só no mesmo dia: nada retroativo"
            1 -> "Pode postar treino de até o dia anterior"
            else -> "Pode postar treino de até $backlogDays dias atrás"
        }
        if (deviceRequired) out += "Treino gravado por aparelho é obrigatório"
        if (locationRequired) out += "O check-in precisa ter local"
        return out
    }

    /** O que impede o check-in nesta liga, na ordem em que a pessoa resolve (vazio = pode postar) */
    fun problems(s: PostSubject, now: Instant, cal: RulesCalendar = RulesCalendar.RULES): List<VerificationProblem> {
        if (preset == VerificationPreset.OFF) return emptyList()
        val out = mutableListOf<VerificationProblem>()
        val photo = s.photo
        if (media == MediaPolicy.ALWAYS && photo == null) out += VerificationProblem("media", "Foto obrigatória.", "adicione uma foto")
        if (media == MediaPolicy.DEVICE_OPTIONAL && photo == null && !s.deviceRecorded && s.gymVisit == null)
            out += VerificationProblem("media", "Precisa de foto, de treino gravado por aparelho ou de visita verificada na academia.", "adicione uma foto")
        if (photo != null && photo.source == PhotoProof.LIBRARY) {
            when (library) {
                LibraryMediaPolicy.ALLOW_ALL -> {}
                LibraryMediaPolicy.DISABLED -> out += VerificationProblem("library", "Foto da galeria não vale aqui.", "tire a foto na câmera do app")
                LibraryMediaPolicy.VERIFIED_ONLY -> if (!photo.timeIsValid(s.date, now, cal)) {
                    out += VerificationProblem("library", if (photo.takenAt == null) "Foto da galeria sem hora verificada." else "A foto da galeria não é do dia do treino.",
                                               "tire a foto na câmera do app")
                }
            }
        }
        if (time != CheckInTimePolicy.NONE) {
            val verified = s.verifiedTimes(now)
            if (verified.isEmpty()) {
                out += VerificationProblem("time", "Sem hora verificada: precisa de foto ou de treino gravado por aparelho.", "adicione uma foto")
            } else if (time == CheckInTimePolicy.SAME_DAY && verified.none { cal.sameDay(it, s.date) }) {
                out += VerificationProblem("time", "O treino não é do mesmo dia da foto ou do aparelho.", "corrija a data do treino")
            } else if (time == CheckInTimePolicy.STRICT && verified.none { s.fits(it) }) {
                out += VerificationProblem("time", "O horário do treino não bate com o da foto ou do aparelho.", "corrija o horário do treino")
            }
        }
        if (backlogDays >= 0) {
            val limit = cal.start(cal.day(now).minusDays(backlogDays.toLong()))
            if (s.date < limit) {
                out += VerificationProblem("backlog", if (backlogDays == 0) "Só vale treino de hoje." else "Só vale treino de até ${backlogName(backlogDays)} atrás.",
                                           "escolha um treino mais recente")
            }
        }
        if (deviceRequired && !s.deviceRecorded)
            out += VerificationProblem("device", "Precisa ser um treino gravado por aparelho.", "importe o treino do Apple Saúde ou do Apple Watch")
        if (locationRequired && !s.hasLocation)
            out += VerificationProblem("location", "O check-in precisa ter local.", "poste da academia ou use uma foto com local")
        return out
    }

    fun json(): JsonObject = J.sorted(mapOf(
        "preset" to JsonPrimitive(preset.raw), "media" to JsonPrimitive(media.raw), "library" to JsonPrimitive(library.raw),
        "time" to JsonPrimitive(time.raw), "backlogDays" to JsonPrimitive(backlogDays),
        "locationRequired" to JsonPrimitive(locationRequired), "deviceRequired" to JsonPrimitive(deviceRequired),
    ))

    companion object {
        const val STRICT_BEFORE = 30L * 60
        const val STRICT_AFTER = 60L * 60
        val OFF = CheckInVerification(VerificationPreset.OFF, MediaPolicy.NEVER, LibraryMediaPolicy.ALLOW_ALL, CheckInTimePolicy.NONE, -1, false, false)
        val PADRAO = CheckInVerification(VerificationPreset.PADRAO, MediaPolicy.DEVICE_OPTIONAL, LibraryMediaPolicy.ALLOW_ALL, CheckInTimePolicy.NONE, -1, false, false)
        val VERIFICADO = CheckInVerification(VerificationPreset.VERIFICADO, MediaPolicy.DEVICE_OPTIONAL, LibraryMediaPolicy.VERIFIED_ONLY, CheckInTimePolicy.NONE, 0, false, false)

        fun preset(p: VerificationPreset): CheckInVerification = when (p) {
            VerificationPreset.OFF -> OFF
            VerificationPreset.PADRAO -> PADRAO
            VerificationPreset.VERIFICADO -> VERIFICADO
            // Personalizar começa do padrão
            VerificationPreset.PERSONALIZADO -> PADRAO.copy(preset = VerificationPreset.PERSONALIZADO)
        }

        val backlogOptions = listOf(0, 1, 7, 30, -1)

        fun backlogName(days: Int): String = when (days) {
            0 -> "Só hoje"
            1 -> "1 dia"
            -1 -> "Qualquer"
            else -> "$days dias"
        }

        fun parse(o: JsonObject): CheckInVerification? {
            val preset = VerificationPreset.of(J.str(o, "preset")) ?: return null
            return CheckInVerification(preset, MediaPolicy.of(J.str(o, "media")) ?: return null, LibraryMediaPolicy.of(J.str(o, "library")) ?: return null,
                                       CheckInTimePolicy.of(J.str(o, "time")) ?: return null, J.int(o, "backlogDays") ?: return null,
                                       J.bool(o, "locationRequired") ?: false, J.bool(o, "deviceRequired") ?: false)
        }
    }
}

// MARK: - Pose do dia

data class DailyPose(val id: String, val name: String, val emoji: String) {
    companion object {
        val all = listOf(
            DailyPose("biceps", "Duplo bíceps", "💪"), DailyPose("joinha", "Joinha com as duas mãos", "👍"),
            DailyPose("paz", "Sinal de paz", "✌️"), DailyPose("rock", "Mãozinha do rock", "🤘"),
            DailyPose("coracao", "Coração com as mãos", "🫶"), DailyPose("pensador", "Pose do pensador", "🤔"),
            DailyPose("flexao", "Uma mão no chão", "🖐️"), DailyPose("lingua", "Língua para fora", "😛"),
            DailyPose("aceno", "Tchauzinho", "👋"), DailyPose("olhos", "Mão na testa, olhando longe", "🫡"),
            DailyPose("tres", "Três dedos para cima", "🤟"), DailyPose("punho", "Punho cerrado no alto", "✊"),
            DailyPose("careta", "Careta de esforço", "😤"), DailyPose("sentado", "Sentado no chão", "🧘"),
        )

        fun byID(id: String?): DailyPose? = all.firstOrNull { it.id == id }

        /** Uma pose por dia (no calendário das regras), igual em todos os aparelhos */
        fun of(day: Instant, cal: RulesCalendar = RulesCalendar.RULES): DailyPose {
            val d = cal.day(day)
            val r = SeededRandom("pose-${d.year}-${d.monthValue}-${d.dayOfMonth}")
            return all[(r.next() * all.size).toInt() % all.size]
        }
    }
}

// MARK: - Tabela de pontos

/** Linha da tabela "Por atividade" com o id que o iPhone grava (a regra em si é `ActivityPointRule`) */
data class PointRuleRow(val id: String, val rule: ActivityPointRule) {
    val summary: String get() {
        val p = rule.points
        val pts = ("$p pt" + (if (kotlin.math.abs(p) == 1) "" else "s")).replace("-", "−")
        return if (rule.method == "perCheckIn") "$pts por vez" else "$pts a cada ${rule.every} ${metricName(rule.metric)}"
    }

    val targetName: String get() {
        val names = rule.workoutTypeIDs.mapNotNull { WorkoutType.byID(it)?.name } + rule.sections
        return if (names.isEmpty()) "Nenhum treino" else names.joinToString(", ")
    }

    fun json(): JsonObject = J.sorted(mapOf(
        "id" to JsonPrimitive(id), "workoutTypeIDs" to JsonArray(rule.workoutTypeIDs.map { JsonPrimitive(it) }),
        "sections" to J.list(rule.sections), "method" to JsonPrimitive(rule.method), "points" to JsonPrimitive(rule.points),
        "every" to JsonPrimitive(rule.every), "metric" to JsonPrimitive(rule.metric),
    ))

    companion object {
        fun metricName(m: String) = when (m) { "km" -> "km"; "kcal" -> "kcal"; else -> "min" }
        fun parse(o: JsonObject) = PointRuleRow(J.str(o, "id") ?: java.util.UUID.randomUUID().toString().uppercase(), ActivityPointRule(
            workoutTypeIDs = (o["workoutTypeIDs"] as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.longOrNull }.orEmpty(),
            sections = J.strings(o, "sections"), method = J.str(o, "method") ?: "perCheckIn", points = J.int(o, "points") ?: 1,
            every = J.int(o, "every") ?: 30, metric = J.str(o, "metric") ?: "minutes"))
    }
}

// MARK: - Limites

enum class LimitPeriod(val raw: String, val label: String) {
    DAY("day", "Por dia"), WEEK("week", "Por semana"), MONTH("month", "Por mês"), TOTAL("total", "Total");

    fun key(d: Instant, cal: RulesCalendar): Long = when (this) {
        DAY -> cal.startOfDay(d).epochSecond
        WEEK -> cal.weekInterval(d).first.epochSecond
        MONTH -> cal.monthInterval(d).first.epochSecond
        TOTAL -> Long.MIN_VALUE
    }
    companion object { fun of(r: String?) = entries.firstOrNull { it.raw == r } }
}

data class ScoringLimits(val individual: Map<LimitPeriod, Int> = emptyMap(), val team: Map<LimitPeriod, Int> = emptyMap()) {
    val isEnabled: Boolean get() = individual.values.any { it > 0 } || team.values.any { it > 0 }

    val summary: List<String> get() {
        fun line(m: Map<LimitPeriod, Int>) = LimitPeriod.entries.mapNotNull { p -> m[p]?.takeIf { it > 0 }?.let { "${p.label.lowercase()} $it" } }
        val ind = line(individual)
        val tm = line(team)
        return (if (ind.isEmpty()) emptyList() else listOf("Teto por pessoa: " + ind.joinToString(", "))) +
            (if (tm.isEmpty()) emptyList() else listOf("Teto por time: " + tm.joinToString(", ")))
    }

    /**
     * O `[LimitPeriod: Int]` do iOS: o JSONEncoder grava dicionário com chave de enum como lista alternada
     * ["day", 100, "week", 500]. Lê também o formato de objeto, por segurança.
     */
    fun json(): JsonObject = J.sorted(mapOf("individual" to encode(individual), "team" to encode(team)))

    companion object {
        private fun encode(m: Map<LimitPeriod, Int>) = JsonArray(LimitPeriod.entries.filter { m.containsKey(it) }.flatMap { listOf(JsonPrimitive(it.raw), JsonPrimitive(m[it]!!)) })

        private fun decode(e: JsonElement?): Map<LimitPeriod, Int> = when (e) {
            is JsonArray -> e.chunked(2).mapNotNull { pair ->
                val k = LimitPeriod.of((pair.getOrNull(0) as? JsonPrimitive)?.content)
                val v = (pair.getOrNull(1) as? JsonPrimitive)?.intOrNull
                if (k != null && v != null) k to v else null
            }.toMap()
            is JsonObject -> e.mapNotNull { (k, v) -> LimitPeriod.of(k)?.let { p -> (v as? JsonPrimitive)?.intOrNull?.let { p to it } } }.toMap()
            else -> emptyMap()
        }

        fun parse(o: JsonObject) = ScoringLimits(decode(o["individual"]), decode(o["team"]))

        /** Corta os pontos que passam do teto, do check-in mais antigo para o mais novo. `group` diz de quem é o placar. */
        fun <T> apply(caps: Map<LimitPeriod, Int>, items: List<T>, id: (T) -> String, date: (T) -> Instant, score: (T) -> Int,
                      group: (T) -> String?, cal: RulesCalendar): Map<String, Int> {
            val active = caps.filter { it.value > 0 }
            if (active.isEmpty()) return emptyMap()
            val used = HashMap<String, Int>()
            val cut = HashMap<String, Int>()
            for (item in items.sortedBy(date)) {
                val s = score(item)
                if (s <= 0) continue
                val g = group(item) ?: continue
                var allowed = s
                for ((p, cap) in active) {
                    val k = "$g|${p.raw}|${p.key(date(item), cal)}"
                    allowed = minOf(allowed, maxOf(cap - (used[k] ?: 0), 0))
                }
                for (p in active.keys) {
                    val k = "$g|${p.raw}|${p.key(date(item), cal)}"
                    used[k] = (used[k] ?: 0) + allowed
                }
                if (allowed < s) cut[id(item)] = s - allowed
            }
            return cut
        }
    }
}

/** Treino do dia da liga (LeagueRules.swift `DailyWorkout`) */
data class DailyWorkout(val day: Instant, val title: String, val items: List<Item> = emptyList(), val note: String = "") {
    data class Item(val exerciseID: String, val sets: Int, val reps: Int)

    fun isToday(now: Instant, zone: ZoneId = ZoneId.systemDefault()): Boolean = day.atZone(zone).toLocalDate() == now.atZone(zone).toLocalDate()

    fun json(): JsonObject = J.sorted(mapOf(
        "day" to J.date(day), "title" to JsonPrimitive(title), "note" to JsonPrimitive(note),
        "items" to JsonArray(items.map { J.sorted(mapOf("exerciseID" to JsonPrimitive(it.exerciseID), "sets" to JsonPrimitive(it.sets), "reps" to JsonPrimitive(it.reps))) }),
    ))

    companion object {
        fun parse(o: JsonObject): DailyWorkout? = J.date(o, "day")?.let { d ->
            DailyWorkout(d, J.str(o, "title") ?: "", (o["items"] as? JsonArray)?.mapNotNull { e ->
                (e as? JsonObject)?.let { Item(J.str(it, "exerciseID") ?: return@mapNotNull null, J.int(it, "sets") ?: 0, J.int(it, "reps") ?: 0) }
            }.orEmpty(), J.str(o, "note") ?: "")
        }
    }
}

/**
 * `LeagueSettings` (LeagueRules.swift), lido do JSON em texto. Campo ausente fica no padrão; chave desconhecida fica em
 * `extra` e volta igual ao gravar.
 */
data class LeagueSettings(
    val verification: CheckInVerification = CheckInVerification.OFF,
    val reviewRequired: Boolean = false,
    val reviewSince: Instant? = null,
    val posesEnabled: Boolean = false,
    val limits: ScoringLimits = ScoringLimits(),
    val pointRules: List<PointRuleRow> = emptyList(),
    val rankingsDisabled: Boolean = false,
    val individualGoal: Int = 0,
    val teamGoal: Int = 0,
    /** 1 = domingo … 7 = sábado; nil = domingo */
    val weekStart: Int? = null,
    val requiresApproval: Boolean = false,
    val mods: List<String> = emptyList(),
    val banned: List<String> = emptyList(),
    val removed: List<String> = emptyList(),
    val approved: List<String> = emptyList(),
    val ignored: List<String> = emptyList(),
    val parentClub: String? = null,
    val dailyWorkout: DailyWorkout? = null,
    val isPrivate: Boolean = false,
    val extra: Map<String, JsonElement> = emptyMap(),
) {
    /** Calendário do ranking semanal, com o início da semana da liga */
    fun calendar(): RulesCalendar = weekStart?.takeIf { it in 1..7 }?.let { RulesCalendar(firstWeekday = it) } ?: RulesCalendar.RULES

    val rawValue: String get() {
        if (this == LeagueSettings()) return ""
        val m = HashMap<String, JsonElement>(extra)
        m["verification"] = verification.json()
        m["reviewRequired"] = JsonPrimitive(reviewRequired)
        reviewSince?.let { m["reviewSince"] = J.date(it) } ?: m.remove("reviewSince")
        m["posesEnabled"] = JsonPrimitive(posesEnabled)
        m["limits"] = limits.json()
        m["pointRules"] = JsonArray(pointRules.map { it.json() })
        m["rankingsDisabled"] = JsonPrimitive(rankingsDisabled)
        m["individualGoal"] = JsonPrimitive(individualGoal)
        m["teamGoal"] = JsonPrimitive(teamGoal)
        weekStart?.let { m["weekStart"] = JsonPrimitive(it) } ?: m.remove("weekStart")
        m["requiresApproval"] = JsonPrimitive(requiresApproval)
        m["mods"] = J.list(mods); m["banned"] = J.list(banned); m["removed"] = J.list(removed)
        m["approved"] = J.list(approved); m["ignored"] = J.list(ignored)
        parentClub?.let { m["parentClub"] = JsonPrimitive(it) } ?: m.remove("parentClub")
        dailyWorkout?.let { m["dailyWorkout"] = it.json() } ?: m.remove("dailyWorkout")
        m["isPrivate"] = JsonPrimitive(isPrivate)
        return J.sorted(m).toString()
    }

    companion object {
        private val KNOWN = setOf("verification", "reviewRequired", "reviewSince", "posesEnabled", "limits", "pointRules", "rankingsDisabled",
                                  "individualGoal", "teamGoal", "weekStart", "requiresApproval", "mods", "banned", "removed", "approved",
                                  "ignored", "parentClub", "dailyWorkout", "isPrivate")

        /** Liga criada agora: verificação padrão ligada */
        val NEW_LEAGUE = LeagueSettings(verification = CheckInVerification.PADRAO)

        fun parse(raw: String?): LeagueSettings {
            val o = J.obj(raw) ?: return LeagueSettings()
            return LeagueSettings(
                verification = (o["verification"] as? JsonObject)?.let(CheckInVerification::parse) ?: CheckInVerification.OFF,
                reviewRequired = J.bool(o, "reviewRequired") ?: false,
                reviewSince = J.date(o, "reviewSince"),
                posesEnabled = J.bool(o, "posesEnabled") ?: false,
                limits = (o["limits"] as? JsonObject)?.let(ScoringLimits::parse) ?: ScoringLimits(),
                pointRules = (o["pointRules"] as? JsonArray)?.mapNotNull { (it as? JsonObject)?.let(PointRuleRow::parse) }.orEmpty(),
                rankingsDisabled = J.bool(o, "rankingsDisabled") ?: false,
                individualGoal = J.int(o, "individualGoal") ?: 0,
                teamGoal = J.int(o, "teamGoal") ?: 0,
                weekStart = J.int(o, "weekStart"),
                requiresApproval = J.bool(o, "requiresApproval") ?: false,
                mods = J.strings(o, "mods"), banned = J.strings(o, "banned"), removed = J.strings(o, "removed"),
                approved = J.strings(o, "approved"), ignored = J.strings(o, "ignored"),
                parentClub = J.str(o, "parentClub"),
                dailyWorkout = (o["dailyWorkout"] as? JsonObject)?.let(DailyWorkout::parse),
                isPrivate = J.bool(o, "isPrivate") ?: false,
                extra = o.filterKeys { it !in KNOWN && o[it] !is JsonNull },
            )
        }

        /** "Dom", "Seg"… (LeagueGoalsSection.weekday) */
        fun weekday(n: Int): String = listOf("Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb").getOrElse(n - 1) { "" }
    }
}
