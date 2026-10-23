package com.alonsoalmeida.gymbros.domain.duel

import com.alonsoalmeida.gymbros.domain.ActivityKind
import com.alonsoalmeida.gymbros.domain.Game
import com.alonsoalmeida.gymbros.domain.MonsterForm
import com.alonsoalmeida.gymbros.domain.backup.ActivityDto
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.Duration
import java.time.Instant

// X1: desafio direto entre dois amigos (só amigos). Fonte: ios/GymBros/Duels/Duel.swift.
// Não tem relação com ligas. Quem desafia escolhe a métrica; aceito, vale tudo o que cada um registrar nas 24 h
// seguintes ao aceite. Cada aparelho calcula o próprio valor e informa ao servidor; o do adversário vem do servidor.

enum class DuelAnswer(val raw: String) {
    ACCEPTED("accepted"), DECLINED("declined");

    companion object { fun of(raw: String?): DuelAnswer? = entries.firstOrNull { it.raw == raw } }
}

/** O que conta no X1 (`DuelMetric`) */
enum class DuelMetric(val raw: String, val title: String, val symbol: String, val hint: String, val detail: String) {
    XP("xp", "XP", "sparkles", "Justo entre modalidades",
       "XP de cada atividade (duração × tipo × esforço): justo entre corrida, musculação, yoga…"),
    TREINOS("treinos", "Treinos", "checkmark.circle.fill", "Cada atividade vale 1", "Cada atividade registrada vale 1."),
    MINUTOS("minutos", "Minutos", "timer", "Tempo de treino", "Soma do tempo de treino."),
    DISTANCIA("distancia", "Distância", "figure.run", "Corrida, bike, natação", "Soma dos quilômetros (corrida, caminhada, bike, natação)."),
    CALORIAS("calorias", "Calorias", "flame.fill", "Do Saúde ou estimadas", "Soma das calorias (do Saúde ou estimadas).");

    /** Valor de uma atividade nesta métrica (`Int(...)` do Swift trunca em direção ao zero, como `toInt()`) */
    fun value(kind: ActivityKind, minutes: Int, effort: Int, meters: Double?, kcal: Double?): Int = when (this) {
        XP -> Game.xp(kind, minutes, effort)
        TREINOS -> 1
        MINUTOS -> minutes
        DISTANCIA -> (meters ?: 0.0).toInt()
        CALORIAS -> (kcal ?: (minutes.toDouble() * kind.met * 1.2)).toInt()
    }

    fun format(v: Int, count: Int? = null): String = when (this) {
        XP -> "$v XP"
        TREINOS -> "$v treino${if ((count ?: v) == 1) "" else "s"}"
        MINUTOS -> durationText(v)
        DISTANCIA -> km(v)
        CALORIAS -> "$v kcal"
    }

    /** Só o número, para o placar */
    fun short(v: Int): String = when (this) {
        MINUTOS -> durationText(v)
        DISTANCIA -> km(v)
        else -> "$v"
    }

    companion object {
        fun of(raw: String?): DuelMetric? = entries.firstOrNull { it.raw == raw }

        /**
         * `String(format: "%.1f km" | "%.0f km")` com vírgula. O printf do C arredonda o valor binário exato, com
         * empate para o par; `BigDecimal(Double)` + HALF_EVEN dá o mesmo (ex.: 250 m → "0,2 km").
         */
        fun km(meters: Int): String {
            val v = BigDecimal(meters.toDouble() / 1000).setScale(if (meters < 10_000) 1 else 0, RoundingMode.HALF_EVEN)
            return "${v.toPlainString()} km".replace('.', ',')
        }
    }
}

/** `durationText` do iOS (Models/Activity.swift) */
fun durationText(minutes: Int): String = when {
    minutes < 60 -> "$minutes min"
    minutes % 60 == 0 -> "${minutes / 60} h"
    else -> "${minutes / 60} h ${minutes % 60} min"
}

/** Uma pessoa do X1 (nome e bro como estavam no servidor) */
data class DuelPerson(val id: String, val name: String, val formID: String) {
    val form: MonsterForm get() = MonsterForm.byID(formID) ?: MonsterForm.EGG
}

sealed interface DuelPhase {
    data class Pending(val expires: Instant) : DuelPhase
    data object Expired : DuelPhase
    data object Declined : DuelPhase
    data class Active(val ends: Instant) : DuelPhase
    data class Finished(val ended: Instant) : DuelPhase
}

/** Desafio como o servidor guarda (o seu id vira "me" no aparelho) */
data class RemoteDuel(
    val id: String,
    val challenger: DuelPerson,
    val challenged: DuelPerson,
    val metric: DuelMetric,
    val createdAt: Instant,
    val answer: DuelAnswer? = null,
    val answeredAt: Instant? = null,
    /** Valor que cada lado informou (id da pessoa → valor na métrica) */
    val reported: Map<String, Int> = emptyMap(),
) {
    fun involves(id: String) = challenger.id == id || challenged.id == id
    fun isPair(a: String, b: String) = involves(a) && involves(b) && a != b
    fun opponent(of: String): DuelPerson = if (challenger.id == of) challenged else challenger
    fun side(of: String): DuelPerson = if (challenger.id == of) challenger else challenged

    val acceptedAt: Instant? get() = if (answer == DuelAnswer.ACCEPTED) answeredAt else null
    val endsAt: Instant? get() = acceptedAt?.plus(Duels.WINDOW)
    val expiresAt: Instant get() = createdAt.plus(Duels.WINDOW)

    fun phase(now: Instant): DuelPhase = when (answer) {
        DuelAnswer.DECLINED -> DuelPhase.Declined
        DuelAnswer.ACCEPTED -> endsAt?.let { if (now < it) DuelPhase.Active(it) else DuelPhase.Finished(it) } ?: DuelPhase.Declined
        null -> if (now < expiresAt) DuelPhase.Pending(expiresAt) else DuelPhase.Expired
    }

    fun isPending(now: Instant) = answer == null && now < expiresAt

    /** Pendente dentro do prazo ou em andamento: bloqueia outro X1 entre o mesmo par */
    fun isOpen(now: Instant) = phase(now).let { it is DuelPhase.Pending || it is DuelPhase.Active }
}

/** Por que não dá para desafiar ou aceitar */
enum class DuelRefusal(val message: String) {
    YOURSELF("Não dá para desafiar você mesmo."),
    NOT_FOUND("Não achamos essa pessoa."),
    BLOCKED("Não dá para desafiar essa pessoa."),
    ALREADY_OPEN("Vocês já têm um X1 aberto."),
    NOT_PENDING("Esse desafio não está mais aberto."),
    NOT_YOURS("Esse desafio não é para você."),
    NO_HATCHED_BRO("Ovos não entram no X1. Choque um ovo (no principal ou numa liga) para lutar."),
    NOT_FRIEND("X1 é só entre amigos. Adicione a pessoa como amiga para desafiar."),
    FIGHTER_BUSY("Esse bro já está num X1. Cada bro luta um X1 por vez."),
    ALL_FIGHTERS_BUSY("Todos os seus bros já estão em X1. Cada bro luta um X1 por vez: choque mais ovos para lutar mais."),
}

class DuelRefusalException(val refusal: DuelRefusal) : Exception(refusal.message)

enum class DuelResult(val letter: String) { VITORIA("V"), EMPATE("E"), DERROTA("D") }

data class DuelScore(val mine: Int = 0, val theirs: Int = 0) {
    val result: DuelResult get() = if (mine == theirs) DuelResult.EMPATE else if (mine > theirs) DuelResult.VITORIA else DuelResult.DERROTA
}

/** Atividade como o X1 enxerga (só o que entra na conta) */
data class DuelActivity(val date: Instant, val kind: ActivityKind, val minutes: Int, val effort: Int, val meters: Double? = null,
                        val kcal: Double? = null) {
    companion object {
        /**
         * Só o que pode sair do aparelho, como nas ligas (Leagues.swift `publishable*`): atividade do Apple Saúde conta
         * com esforço neutro, sem distância e sem kcal; gravada no relógio, sem distância e sem kcal; treino gravado
         * também no relógio (`healthWritten`), sem kcal.
         */
        fun of(a: ActivityDto): DuelActivity {
            val fromHealth = a.healthUUID != null
            val watch = a.source == "Apple Watch"
            return DuelActivity(
                a.date, ActivityKind.of(a.kind), a.minutes,
                effort = if (fromHealth) 5 else a.effort,
                meters = if (fromHealth || watch) null else a.meters,
                kcal = if (fromHealth || watch || a.healthWritten != null) null else a.kcal,
            )
        }
    }
}

/** X1 encerrado */
data class DuelRecord(val id: String, val opponent: DuelPerson, val ended: Instant, val score: DuelScore, val metric: DuelMetric) {
    val text: String get() = Duels.summary(score, opponent.name, metric)
}

data class DuelTally(val v: Int, val e: Int, val d: Int) {
    val total: Int get() = v + e + d
}

object Duels {
    val WINDOW: Duration = Duration.ofHours(24)
    val FAST_WINDOW: Duration = Duration.ofMinutes(2)
    const val ME = "me"

    /** Motivo para não poder desafiar `opponent` agora; null = pode */
    fun refusal(me: String, opponent: String, duels: List<RemoteDuel>, blocked: Set<String>, blockedBy: Set<String>, now: Instant): DuelRefusal? {
        if (opponent == me) return DuelRefusal.YOURSELF
        if (opponent in blocked || opponent in blockedBy) return DuelRefusal.BLOCKED
        if (duels.any { it.isPair(me, opponent) && it.isOpen(now) }) return DuelRefusal.ALREADY_OPEN
        return null
    }

    /** Motivo para não poder aceitar; null = pode. Recusar sempre pode enquanto estiver pendente. */
    fun acceptRefusal(duel: RemoteDuel, me: String, duels: List<RemoteDuel>, blocked: Set<String>, now: Instant): DuelRefusal? {
        if (duel.challenged.id != me) return DuelRefusal.NOT_YOURS
        if (duel.phase(now) !is DuelPhase.Pending) return DuelRefusal.NOT_PENDING
        if (duel.challenger.id in blocked) return DuelRefusal.BLOCKED
        // Outro X1 aberto do par: um já aceito, ou um pendente mais antigo (desafios cruzados quase juntos: vale o primeiro)
        val other = duels.any {
            it.id != duel.id && it.isPair(me, duel.challenger.id) && it.isOpen(now) &&
                (it.acceptedAt != null || olderThan(it, duel))
        }
        return if (other) DuelRefusal.ALREADY_OPEN else null
    }

    /** `(a.createdAt, a.id) < (b.createdAt, b.id)` do Swift (o id comparado como texto, por unidade UTF-16 como o String do Swift em ASCII) */
    private fun olderThan(a: RemoteDuel, b: RemoteDuel): Boolean =
        a.createdAt < b.createdAt || (a.createdAt == b.createdAt && a.id < b.id)

    /** Bros ocupados: cada um luta um X1 por vez. Ocupa quem está num X1 valendo ou num desafio seu ainda sem resposta. */
    fun busyFighters(duels: List<RemoteDuel>, representatives: Map<String, String>, me: String = ME, now: Instant): Set<String> =
        duels.filter { it.isOpen(now) && (it.acceptedAt != null || it.challenger.id == me) }.mapNotNull { representatives[it.id] }.toSet()

    /** Seu valor na janela de 24 h depois do aceite (até agora), com as suas atividades */
    fun myValue(duel: RemoteDuel, activities: List<DuelActivity>, now: Instant): Int {
        val start = duel.acceptedAt ?: return 0
        val end = duel.endsAt ?: return 0
        val limit = minOf(end, now)
        return activities.filter { it.date >= start && it.date < end && it.date <= limit }
            .sumOf { duel.metric.value(it.kind, it.minutes, it.effort, it.meters, it.kcal) }
    }

    /** Placar: o seu calculado aqui, o do adversário como ele informou */
    fun score(duel: RemoteDuel, me: String = ME, activities: List<DuelActivity>, now: Instant): DuelScore =
        DuelScore(myValue(duel, activities, now), duel.reported[duel.opponent(me).id] ?: 0)

    /** Intervalo para buscar respostas (segundos): curto só logo depois de você desafiar */
    fun refreshInterval(duels: List<RemoteDuel>, me: String = ME, now: Instant): Long {
        val fresh = duels.any { it.challenger.id == me && it.isPending(now) && Duration.between(it.createdAt, now) < FAST_WINDOW }
        return if (fresh) 3 else 30
    }

    /** "Você venceu Bruno no X1 · 3 a 1 treinos" */
    fun summary(score: DuelScore, opponent: String, metric: DuelMetric): String {
        val verb = when (score.result) {
            DuelResult.VITORIA -> "Você venceu $opponent"
            DuelResult.DERROTA -> "Você perdeu para $opponent"
            DuelResult.EMPATE -> "Você empatou com $opponent"
        }
        return "$verb no X1 · ${metric.short(score.mine)} a ${metric.format(score.theirs, maxOf(score.mine, score.theirs))}"
    }

    /** X1 seus que já acabaram, do mais recente para o mais antigo */
    fun records(duels: List<RemoteDuel>, me: String = ME, activities: List<DuelActivity>, now: Instant): List<DuelRecord> =
        duels.mapNotNull { d ->
            val phase = d.phase(now)
            if (!d.involves(me) || phase !is DuelPhase.Finished) null
            else DuelRecord(d.id, d.opponent(me), phase.ended, score(d, me, activities, now), d.metric)
        }.sortedByDescending { it.ended }

    /** Vitórias, empates e derrotas */
    fun tally(records: List<DuelRecord>): DuelTally = DuelTally(
        records.count { it.score.result == DuelResult.VITORIA },
        records.count { it.score.result == DuelResult.EMPATE },
        records.count { it.score.result == DuelResult.DERROTA },
    )

    /** "5 h 20 min", "12 min" (`DuelsView.remaining`: minutos arredondados para cima, no mínimo 1) */
    fun remaining(end: Instant, now: Instant): String {
        val seconds = Duration.between(now, end).toMillis() / 1000.0
        return durationText(maxOf(1, kotlin.math.ceil(seconds / 60).toInt()))
    }

    /** Seu id no servidor vira "me", como no resto do app (`DuelStore.local`) */
    fun local(d: RemoteDuel, myID: String): RemoteDuel {
        fun swap(p: DuelPerson) = if (p.id == myID) p.copy(id = ME) else p
        val reported = LinkedHashMap<String, Int>()
        for ((k, v) in d.reported) { val key = if (k == myID) ME else k; if (key !in reported) reported[key] = v }
        return d.copy(challenger = swap(d.challenger), challenged = swap(d.challenged), reported = reported)
    }

    /**
     * O que aparece (`DuelStore.duels`): sem os de quem você bloqueou e sem desafio recebido, sem resposta, de quem não é
     * seu amigo (X1 só entre amigos)
     */
    fun visible(all: List<RemoteDuel>, blocked: Set<String>, friends: Set<String>): List<RemoteDuel> = all.filter { d ->
        val other = d.opponent(ME).id
        other !in blocked && (other in friends || !(d.challenged.id == ME && d.answer == null))
    }

    /** Quando o primeiro bro ocupado fica livre (fim do X1 valendo ou prazo do seu desafio sem resposta) */
    fun nextFighterFree(all: List<RemoteDuel>, representatives: Map<String, String>, now: Instant): Instant? =
        all.filter { representatives[it.id] != null && it.isOpen(now) && (it.acceptedAt != null || it.challenger.id == ME) }
            .map { it.endsAt ?: it.expiresAt }
            .minOrNull()
}
