package com.alonsoalmeida.gymbros.domain.leagues

import com.alonsoalmeida.gymbros.domain.ActivityText
import com.alonsoalmeida.gymbros.domain.Attribute
import com.alonsoalmeida.gymbros.domain.LeagueActivityRule
import com.alonsoalmeida.gymbros.domain.LeagueScore
import com.alonsoalmeida.gymbros.domain.LeagueScoring
import com.alonsoalmeida.gymbros.domain.PhotoRule
import com.alonsoalmeida.gymbros.domain.ScoreInput
import com.alonsoalmeida.gymbros.domain.SwissCriterion
import com.alonsoalmeida.gymbros.domain.WorkoutType
import com.alonsoalmeida.gymbros.domain.backup.Iso8601Seconds
import kotlinx.serialization.Serializable
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.UUID

// O que é da conta nas ligas, como está na cópia da conta (Backup.swift `LeagueDTO`, `CheckInDTO`, `MessageDTO`,
// `ReviewDTO`, `CommentDTO`). Só leitura: quem grava mexe no JSON (LeagueEdits) para não perder campos desconhecidos.

@Serializable
data class LeagueJson(
    val uuid: String,
    val name: String = "",
    val emoji: String = "🏆",
    val scoring: String = "pontos",
    @Serializable(Iso8601Seconds::class) val start: Instant,
    val code: String = "",
    val isMock: Boolean = false,
    @Serializable(Iso8601Seconds::class) val joinedAt: Instant,
    val monsterUUID: String? = null,
    @Serializable(Iso8601Seconds::class) val end: Instant? = null,
    val autoRenew: Boolean? = null,
    val season: Int? = null,
    val seriesID: String? = null,
    val nextUUID: String? = null,
    val weights: String? = null,
    val tieBreak: String? = null,
    val photoRule: String? = null,
    val teams: String? = null,
    val myTeamID: String? = null,
    val activityRule: String? = null,
    val settings: String? = null,
    /** Capa (JPEG em base64) */
    val cover: String? = null,
    @Serializable(Iso8601Seconds::class) val syncedAt: Instant? = null,
    val joined: Boolean? = null,
    val swiss: String? = null,
)

@Serializable
data class CheckInJson(
    val uuid: String,
    val leagueUUID: String,
    val activityUUID: String,
    val title: String = "",
    val note: String = "",
    @Serializable(Iso8601Seconds::class) val date: Instant,
    val hadPhoto: Boolean? = null,
    val place: String? = null,
    @Serializable(Iso8601Seconds::class) val syncedAt: Instant? = null,
    val proof: String? = null,
    val review: String? = null,
    /** Fotos a mais: plist binário de `[Data]`, em base64 */
    val extraPhotos: String? = null,
    /** Foto principal (JPEG em base64): só na cópia da conta, nunca no servidor */
    val photo: String? = null,
) {
    val hasPhoto: Boolean get() = photo != null || hadPhoto == true
}

@Serializable
data class MessageJson(
    val uuid: String,
    val leagueUUID: String,
    val text: String = "",
    @Serializable(Iso8601Seconds::class) val date: Instant,
    @Serializable(Iso8601Seconds::class) val syncedAt: Instant? = null,
    val photo: String? = null,
)

@Serializable
data class ReviewJson(val uuid: String, val leagueUUID: String, val itemID: String, val approved: Boolean = true,
                      @Serializable(Iso8601Seconds::class) val date: Instant)

@Serializable
data class CommentJson(val uuid: String, val itemID: String, val text: String = "", @Serializable(Iso8601Seconds::class) val date: Instant,
                       val authorID: String? = null, val authorName: String? = null) {
    val isMine: Boolean get() = (authorID ?: "me") == "me"
}

/** Atividade como as ligas precisam (Backup.swift `ActivityDTO`) */
@Serializable
data class LeagueActivityJson(
    val uuid: String,
    val kind: String = "outro",
    @Serializable(Iso8601Seconds::class) val date: Instant,
    val minutes: Int = 0,
    val effort: Int = 5,
    val note: String = "",
    val healthUUID: String? = null,
    val source: String? = null,
    val monsterUUID: String? = null,
    val gymUUID: String? = null,
    val meters: Double? = null,
    val kcal: Double? = null,
    val healthType: Long? = null,
    val healthWritten: String? = null,
) {
    val kindEnum get() = com.alonsoalmeida.gymbros.domain.ActivityKind.of(kind)
    val isFromHealth: Boolean get() = healthUUID != null
    val isWatchMeasured: Boolean get() = source == "Apple Watch"
    /** Gravada por aparelho (Apple Saúde, Apple Watch ou GPS do app) */
    val isDeviceRecorded: Boolean get() = source != null
    val workoutTypeID: Long? get() = WorkoutType.byID(healthType)?.id ?: com.alonsoalmeida.gymbros.domain.BroCatalog.classicType[kindEnum.raw]
    val typeName: String get() = WorkoutType.byID(workoutTypeID)?.name ?: kind

    /** Mesmos dados que os outros participantes recebem (Leagues.swift `Activity.scoreInput`) */
    val scoreInput: ScoreInput get() = ScoreInput(
        kindEnum, minutes, if (isFromHealth) 5 else effort,
        if (isFromHealth || isWatchMeasured) null else meters,
        if (isFromHealth || isWatchMeasured || healthWritten != null) null else kcal,
        workoutTypeID,
    )

    val scorePart: ScorePart get() { val i = scoreInput; return ScorePart(kind, i.minutes, i.effort, i.meters, i.kcal, i.workoutTypeID) }
}

/** Partes da cópia da conta que as ligas usam */
@Serializable
data class LeaguesCopy(
    val leagues: List<LeagueJson>? = null,
    val checkIns: List<CheckInJson>? = null,
    val messages: List<MessageJson>? = null,
    val reviews: List<ReviewJson>? = null,
    val comments: List<CommentJson>? = null,
    val activities: List<LeagueActivityJson> = emptyList(),
)

data class LeagueTeam(val id: String, val name: String)

/** Formato de `League.teamsRaw`: "id\tnome" por linha (antigo: só o nome, id = "t0", "t1"…) */
object LeagueTeams {
    fun legacyID(i: Int) = "t$i"
    fun newID(): String = "x" + UUID.randomUUID().toString().take(8).lowercase()

    fun parse(raw: String): List<LeagueTeam> = raw.split("\n").filter { it.isNotEmpty() }.mapIndexedNotNull { i, line ->
        val parts = line.split("\t", limit = 2).map { it.trim() }
        val (id, name) = if (parts.size == 2) parts[0] to parts[1] else legacyID(i) to parts.first()
        if (name.isEmpty() || id.isEmpty()) null else LeagueTeam(id, name)
    }

    fun encode(teams: List<LeagueTeam>): String = teams.mapNotNull { t ->
        val name = t.name.replace("\t", " ").replace("\n", " ").trim()
        if (name.isEmpty()) null else "${t.id}\t$name"
    }.joinToString("\n")
}

/** Liga como o app usa (Models/League.swift `League`) */
data class League(val j: LeagueJson) {
    val uuid: String get() = j.uuid.uppercase()
    val name get() = j.name
    val emoji get() = j.emoji
    val code get() = j.code
    val start get() = j.start
    val end get() = j.end
    val isMock get() = j.isMock
    val season get() = j.season ?: 1
    val autoRenew get() = j.autoRenew ?: false
    val joined get() = j.joined ?: true
    /** Criada por você; liga achada pelo código é de outra pessoa (Access.swift `League.isMine`) */
    val isMine get() = !joined
    val scoring: LeagueScoring get() = LeagueScoring.entries.firstOrNull { it.raw == j.scoring } ?: LeagueScoring.PONTOS
    val tieBreak: LeagueTieBreak get() = LeagueTieBreak.entries.firstOrNull { it.raw == j.tieBreak } ?: LeagueTieBreak.PRIMEIRO
    val photoRule: PhotoRule get() = PhotoRule.entries.firstOrNull { it.raw == j.photoRule } ?: PhotoRule.LIVRE
    val swiss: SwissCriterion get() = SwissCriterion.entries.firstOrNull { it.raw == j.swiss } ?: SwissCriterion.PONTOS
    val activityRule: LeagueActivityRule get() = LeagueActivityRule.parse(j.activityRule ?: "")
    val settings: LeagueSettings by lazy { LeagueSettings.parse(j.settings) }
    val teams: List<LeagueTeam> get() = LeagueTeams.parse(j.teams ?: "")
    val myTeamID get() = j.myTeamID
    val monsterUUID get() = j.monsterUUID?.uppercase()
    val seriesKey: String get() = (j.seriesID ?: j.uuid).uppercase()
    val isPastSeason get() = j.nextUUID != null
    val format: LeagueFormat get() = if (end == null) LeagueFormat.CLUB else LeagueFormat.CHALLENGE
    val attributeWeights: Map<Attribute, Double> get() = LeagueScore.parseWeights(j.weights ?: "")

    fun isOver(now: Instant) = end?.let { it < now } ?: false
    fun hasStarted(now: Instant) = start <= now

    /** Dias que faltam, contando hoje (nil = sem fim) */
    fun daysLeft(now: Instant): Int? = end?.let { maxOf(0, daysBetween(now, it) + 1) }
    fun daysToStart(now: Instant): Int = maxOf(0, daysBetween(now, start))

    val durationDays: Int get() = end?.let { daysBetween(start, it) + 1 } ?: 0

    /** Quando você entra na rodada suíça: quem criou está desde o início */
    val swissJoinedAt: Instant get() = if (joined || isMock) j.joinedAt else minOf(j.joinedAt, start)

    /** Pontos de um check-in (antes de limites e de "dias ativos") */
    fun score(i: ScoreInput, hasPhoto: Boolean = true): Int =
        LeagueScore.score(i, scoring, j.weights ?: "", activityRule, settings.pointRules.map { it.rule }, photoRule, hasPhoto)

    fun score(parts: List<ScoreInput>, hasPhoto: Boolean): Int = parts.sumOf { score(it, hasPhoto) }

    /** O que impede postar este treino aqui (tipo que não vale e regras de verificação); vazio = pode */
    fun problems(s: PostSubject, now: Instant): List<VerificationProblem> {
        if (!activityRule.accepts(s.workoutTypeID)) {
            val name = s.workoutTypeID?.let { WorkoutType.byID(it)?.name } ?: "Este treino"
            return listOf(VerificationProblem("media", "$name não vale nesta liga.", "escolha outro treino"))
        }
        return settings.verification.problems(s, now)
    }

    /** O check-in espera o dono aprovar: liga com revisão, e o seu só se você não modera */
    fun needsReview(fromMe: Boolean, selfID: String) = settings.reviewRequired && !(fromMe && canModerate(selfID))

    /** Dono ou moderador */
    fun canModerate(selfID: String) = isMine || selfID in settings.mods

    companion object {
        val CAL = RulesCalendar.RULES
        fun daysBetween(a: Instant, b: Instant): Int = ChronoUnit.DAYS.between(CAL.day(a), CAL.day(b)).toInt()

        fun newCode(): String {
            val chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
            val r = java.security.SecureRandom()
            return (0 until 6).map { chars[r.nextInt(chars.length)] }.joinToString("")
        }

        /** "começa hoje", "começa amanhã", "começa em 3 dias" */
        fun startsText(start: Instant, now: Instant): String {
            val n = daysBetween(now, start)
            return when {
                n < 0 -> "já começou"
                n == 0 -> "começa hoje"
                n == 1 -> "começa amanhã"
                else -> "começa em $n dias"
            }
        }

        /**
         * O dia escolhido no calendário do aparelho, no calendário das regras (Brasília): mesmo ano, mês e dia
         * (League.ruleDay).
         */
        fun ruleDay(i: Instant, device: ZoneId = ZoneId.systemDefault()): Instant = CAL.start(i.atZone(device).toLocalDate())

        /** Período escolhido: do começo do dia de início ao fim do dia final (League.setPeriod) */
        fun period(start: Instant, end: Instant?, device: ZoneId = ZoneId.systemDefault()): Pair<Instant, Instant?> {
            val s = ruleDay(start, device)
            val e = end?.let { CAL.start(CAL.day(ruleDay(maxOf(it, start), device)).plusDays(1)).minusSeconds(1) }
            return s to e
        }
    }
}

enum class LeagueFormat(val label: String, val detail: String) {
    CLUB("Clube", "Grupo permanente, com rankings da semana e do mês."),
    CHALLENGE("Desafio", "Competição com data para começar, acabar e coroar um vencedor."),
}

enum class LeagueTieBreak(val raw: String, val label: String, val detail: String) {
    PRIMEIRO("primeiro", "Chegou antes", "No empate, fica na frente quem chegou primeiro àquela pontuação."),
    SEQUENCIA("sequencia", "Sequência", "No empate, fica na frente quem treinou mais dias seguidos no período."),
    CHECKINS("checkins", "Check-ins", "No empate, fica na frente quem fez mais check-ins."),
}

/** Textos dos modos, regras e critérios (Leagues.swift, Swiss.swift) */
object LeagueText {
    fun name(s: LeagueScoring) = when (s) {
        LeagueScoring.PONTOS -> "Pontos"; LeagueScoring.TREINOS -> "Treinos"; LeagueScoring.DIAS -> "Dias ativos"
        LeagueScoring.ATIVIDADES -> "Por atividade"; LeagueScoring.MINUTOS -> "Minutos"; LeagueScoring.DISTANCIA -> "Distância"
        LeagueScoring.CALORIAS -> "Calorias"
    }

    fun detail(s: LeagueScoring) = when (s) {
        LeagueScoring.PONTOS -> "Cada check-in vale o XP da atividade: duração × tipo × esforço. Justo entre corrida, musculação, yoga…"
        LeagueScoring.TREINOS -> "Cada check-in vale 1. Ganha quem treina mais vezes."
        LeagueScoring.DIAS -> "Cada dia com pelo menos um check-in vale 1: dois treinos no mesmo dia contam um dia só."
        LeagueScoring.ATIVIDADES -> "Você monta a tabela: cada tipo de treino vale pontos por vez ou por quantidade (minutos, km, kcal), e pode até tirar pontos. Treino fora da tabela vale 0."
        LeagueScoring.MINUTOS -> "Soma do tempo de todos os check-ins."
        LeagueScoring.DISTANCIA -> "Soma dos quilômetros (corrida, caminhada, bike, natação com GPS ou do Apple Saúde). Atividade sem distância não pontua."
        LeagueScoring.CALORIAS -> "Soma das calorias ativas: as do Apple Saúde quando houver, senão estimadas pela atividade, duração e esforço."
    }

    /** Ordem do iOS (`LeagueScoring.allCases`) */
    val scoringOrder = listOf(LeagueScoring.PONTOS, LeagueScoring.TREINOS, LeagueScoring.DIAS, LeagueScoring.MINUTOS,
                              LeagueScoring.DISTANCIA, LeagueScoring.CALORIAS, LeagueScoring.ATIVIDADES)

    /** "120 pts", "3 treinos", "1 h 20 min", "12,4 km", "830 kcal" */
    fun format(s: LeagueScoring, v: Int, count: Int? = null): String = when (s) {
        LeagueScoring.PONTOS, LeagueScoring.ATIVIDADES -> "$v pts"
        LeagueScoring.TREINOS -> "$v treino" + if ((count ?: v) == 1) "" else "s"
        LeagueScoring.DIAS -> "$v dia" + if ((count ?: v) == 1) "" else "s"
        LeagueScoring.MINUTOS -> ActivityText.duration(v)
        LeagueScoring.DISTANCIA -> km(v)
        LeagueScoring.CALORIAS -> "$v kcal"
    }

    fun short(s: LeagueScoring, v: Int): String = when (s) {
        LeagueScoring.MINUTOS -> ActivityText.duration(v)
        LeagueScoring.DISTANCIA -> km(v)
        else -> "$v"
    }

    /**
     * `String(format: "%.1f km")`: o printf arredonda o valor binário exato (empate exato vai para o par). O BigDecimal do
     * Double reproduz isso; o `String.format` do Java arredondaria a metade para cima.
     */
    fun km(meters: Int): String {
        val v = BigDecimal(meters.toDouble() / 1000).setScale(if (meters < 10_000) 1 else 0, RoundingMode.HALF_EVEN)
        return "${v.toPlainString().replace(".", ",")} km"
    }

    fun photoName(p: PhotoRule) = when (p) { PhotoRule.LIVRE -> "Opcional"; PhotoRule.METADE -> "Vale ½"; PhotoRule.OBRIGATORIA -> "Obrigatória" }
    fun photoDetail(p: PhotoRule) = when (p) {
        PhotoRule.LIVRE -> "Check-in sem foto vale o mesmo que com foto."
        PhotoRule.METADE -> "Check-in sem foto vale metade. A foto é a prova do treino."
        PhotoRule.OBRIGATORIA -> "Check-in sem foto não pontua. A foto é a prova do treino."
    }

    fun swissName(c: SwissCriterion) = when (c) { SwissCriterion.PONTOS -> "Mais pontos no dia"; SwissCriterion.CHECKINS -> "Mais check-ins no dia"; SwissCriterion.PRESENCA -> "Presença" }
    fun swissDetail(c: SwissCriterion) = when (c) {
        SwissCriterion.PONTOS -> "Vence quem somar mais na liga no dia."
        SwissCriterion.CHECKINS -> "Vence quem fizer mais check-ins válidos no dia."
        SwissCriterion.PRESENCA -> "Treinou e o outro não: vitória. Os dois treinaram: empate."
    }

    /** "4", "4,5" */
    fun swissPoints(p: Double): String = if (p == Math.rint(p)) "${p.toLong()}" else BigDecimal(p).setScale(1, RoundingMode.HALF_EVEN).toPlainString().replace(".", ",")

    /** "2×", "0,5×" */
    fun weight(v: Double): String = (if (v == Math.rint(v)) "${v.toLong()}" else BigDecimal(v).setScale(1, RoundingMode.HALF_EVEN).toPlainString().replace(".", ",")) + "×"

    /** Regra "Treinos que valem" (Leagues.swift `LeagueActivityRule`) */
    fun ruleModeName(mode: String) = when (mode) { "only" -> "Somente estes"; "except" -> "Todos, exceto:"; else -> "Todos" }
    fun ruleDetail(r: LeagueActivityRule) = when (r.mode) {
        "only" -> if (r.workoutTypeIDs.isEmpty()) "Escolha pelo menos um treino que vale pontos." else "Só os ${r.workoutTypeIDs.size} treino(s) selecionados valem pontos."
        "except" -> if (r.workoutTypeIDs.isEmpty()) "Nenhum treino foi excluído." else "Os ${r.workoutTypeIDs.size} treino(s) selecionados não valem pontos."
        else -> "Qualquer treino vale pontos."
    }
    fun ruleRaw(r: LeagueActivityRule): String = if (r.mode == "all") "" else r.mode + ":" + r.workoutTypeIDs.sorted().joinToString(",")

    /** Pesos guardados como "forca:1.5,tecnica:0.5" (só os diferentes de 1), na ordem dos atributos */
    fun weightsRaw(w: Map<Attribute, Double>): String = Attribute.entries.mapNotNull { a ->
        w[a]?.takeIf { it != 1.0 }?.let { v -> "${a.raw}:" + (if (v == Math.rint(v)) "${v.toLong()}" else BigDecimal(v).stripTrailingZeros().toPlainString()) }
    }.joinToString(",")
}

/** Renovação das temporadas (Leagues.swift `LeagueRenewal`, LeagueWinners.swift `restart`) */
object LeagueRenewal {
    data class Next(val start: Instant, val end: Instant, val season: Int)

    /** Próxima temporada de uma liga com renovação que acabou: pula as que passaram com o app fechado */
    fun next(old: League, now: Instant): Next {
        val cal = League.CAL
        val days = maxOf(old.durationDays, 1).toLong()
        var start = cal.day(old.end ?: now).plusDays(1)
        var seasons = 1
        while (start.plusDays(days - 1).isBefore(cal.day(now))) {
            start = start.plusDays(days)
            seasons += 1
        }
        return Next(cal.start(start), cal.start(start.plusDays(days)).minusSeconds(1), old.season + seasons)
    }

    /** Recomeça hoje um desafio encerrado, com a mesma duração */
    fun restart(old: League, now: Instant): Next {
        val cal = League.CAL
        val days = maxOf(old.durationDays, 1).toLong()
        val s = cal.day(now)
        return Next(cal.start(s), cal.start(s.plusDays(days)).minusSeconds(1), old.season + 1)
    }
}
