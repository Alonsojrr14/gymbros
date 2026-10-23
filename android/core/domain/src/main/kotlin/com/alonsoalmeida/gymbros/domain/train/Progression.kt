package com.alonsoalmeida.gymbros.domain.train

import com.alonsoalmeida.gymbros.domain.roundHalfAwayFromZero
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.TemporalAdjusters
import kotlin.math.abs
import kotlin.math.floor

// Porte de Train/Progression.swift e Train/PR.swift (funções puras do histórico). Os ajustes que no iOS ficam no
// UserDefaults (objetivos por exercício, PRs à mão) chegam aqui pela cópia da conta: quem lê a conta preenche
// `TrainingGoal.goals` e `PRBook.manual`, como o iOS faz com o `UserDefaults` e o `PRBook.reload()`.

data class SetLog(val exerciseID: String, val weight: Double, val reps: Int, val target: Int, val done: Boolean) {
    val hit: Boolean get() = done && reps >= target
}

data class SessionLog(val date: Instant, val sets: List<SetLog>, val deload: Boolean = false)

/** Objetivo do exercício: faixa de reps da dupla progressão e o descanso */
enum class TrainingGoal(val raw: String, val label: String, val range: IntRange, val rest: Int) {
    FORCA("forca", "Força", 3..6, 180),
    HIPERTROFIA("hipertrofia", "Hipertrofia", 8..12, 90),
    RESISTENCIA("resistencia", "Resistência", 15..20, 60);

    val fullLabel: String get() = "$label · ${range.first}–${range.last} reps"

    companion object {
        const val KEY = "exerciseGoals"

        /** Objetivos por exercício (`exerciseGoals`: JSON `{"supino-reto":"forca"}` guardado como texto nos ajustes) */
        @Volatile var goals: Map<String, String> = emptyMap()

        fun of(exerciseID: String): TrainingGoal? = goals[exerciseID]?.let { g -> entries.firstOrNull { it.raw == g } }

        fun decode(json: String?): Map<String, String> {
            if (json.isNullOrEmpty()) return emptyMap()
            return runCatching {
                (kotlinx.serialization.json.Json.parseToJsonElement(json) as kotlinx.serialization.json.JsonObject)
                    .mapValues { (it.value as kotlinx.serialization.json.JsonPrimitive).content }
            }.getOrDefault(emptyMap())
        }

        /** Como o `JSONEncoder` do iOS: chaves em qualquer ordem, sem espaços */
        fun encode(m: Map<String, String>): String =
            kotlinx.serialization.json.JsonObject(m.mapValues { kotlinx.serialization.json.JsonPrimitive(it.value) }).toString()
    }
}

data class Suggestion(
    val weight: Double,
    val reps: Int,
    val reason: String,
    /** Quantas séries de trabalho prescrever (null = as da rotina) */
    val sets: Int? = null,
    /** Rampa feita à mão da última vez, para repetir como aquecimento */
    val ramp: List<Pair<Double, Int>> = emptyList(),
)

/** Semana do calendário (domingo a sábado, o `weekOfYear` do iPhone em pt-BR) */
object Weeks {
    fun start(d: LocalDate, first: DayOfWeek = DayOfWeek.SUNDAY): LocalDate = d.with(TemporalAdjusters.previousOrSame(first))
    fun start(i: Instant, zone: ZoneId, first: DayOfWeek = DayOfWeek.SUNDAY): LocalDate = start(i.atZone(zone).toLocalDate(), first)
    /** Fim da semana (começo da seguinte), como `dateInterval(of: .weekOfYear).end` */
    fun end(i: Instant, zone: ZoneId, first: DayOfWeek = DayOfWeek.SUNDAY): Instant = start(i, zone, first).plusDays(7).atStartOfDay(zone).toInstant()
}

/** Semana de deload: depois de várias semanas seguidas, cargas a 70 % e menos séries */
object Deload {
    const val AFTER = 5
    const val LOAD = 0.7
    const val UNTIL_KEY = "deloadUntil"
    const val SNOOZE_KEY = "deloadSnooze"

    /** Semanas seguidas (até esta ou a passada) com treino, parando numa semana sem treino ou de deload */
    fun streak(sessions: List<Pair<Instant, Boolean>>, now: Instant, zone: ZoneId): Int {
        val byWeek = sessions.groupBy { Weeks.start(it.first, zone) }
        var w = Weeks.start(now, zone)
        if (byWeek[w] == null) w = w.minusWeeks(1)
        var n = 0
        while (true) {
            val list = byWeek[w] ?: break
            if (list.any { it.second }) break
            n++
            w = w.minusWeeks(1)
        }
        return n
    }

    /** Aplica o deload: 70 % da carga (arredondada ao incremento) e um terço a menos de séries */
    fun apply(s: Suggestion, sets: Int, exerciseID: String): Pair<Suggestion, Int> {
        val inc = Exercises.byID(exerciseID)?.increment ?: 2.5
        return Suggestion(roundHalfAwayFromZero(s.weight * LOAD / inc) * inc, s.reps, "Semana de deload") to
            maxOf(1, roundHalfAwayFromZero(sets.toDouble() * 2 / 3).toInt())
    }
}

object PRBook {
    /** PRs registrados à mão, por exercício (a cópia da conta: `prs`) */
    @Volatile var manual: Map<String, List<SetLog>> = emptyMap()

    private fun key(s: SetLog) = Triple(Progression.strength(s.weight, s.reps), s.weight, s.reps)

    /** Melhor série: maior força na escala de 1RM, depois maior carga e mais reps (o primeiro entre iguais, como `max(by:)`) */
    fun best(sets: List<SetLog>): SetLog? {
        var out: SetLog? = null
        for (s in sets.filter { it.done }) {
            val o = out
            if (o == null || compare(key(o), key(s)) < 0) out = s
        }
        return out
    }

    private fun compare(a: Triple<Double, Double, Int>, b: Triple<Double, Double, Int>): Int =
        compareValuesBy(a, b, { it.first }, { it.second }, { it.third })

    /** `new` supera `old`? Mesma régua de `best` */
    fun beats(new: SetLog, old: SetLog?): Boolean {
        if (old == null) return true
        val a = Progression.strength(new.weight, new.reps)
        val b = Progression.strength(old.weight, old.reps)
        if (abs(a - b) > 0.01) return a > b
        return new.weight > old.weight || (new.weight == old.weight && new.reps > old.reps)
    }

    /** Carga de trabalho para `reps` a partir do melhor PR à mão (com 1–2 reps de sobra) */
    fun workingWeight(exerciseID: String, reps: Int, increment: Double): Pair<Double, SetLog>? {
        val pr = best(manual[exerciseID].orEmpty()) ?: return null
        if (pr.weight <= 0) return null
        val w = Progression.oneRM(pr.weight, pr.reps)?.let { it / (1 + reps.toDouble() / 30) * 0.92 }
            ?: if (pr.reps >= reps) pr.weight else return null
        val rounded = floor(w / increment) * increment
        return if (rounded > 0) rounded to pr else null
    }
}

object Progression {
    const val DELOAD_AFTER = 3
    const val RAMP_SHARE = 0.8

    /** Séries de trabalho de um exercício num treino: tira a rampa (séries bem mais leves que a maior carga) */
    fun workSets(sets: List<SetLog>): List<SetLog> {
        val top = sets.maxOfOrNull { it.weight } ?: 0.0
        if (top <= 0) return sets
        return sets.filter { it.weight >= top * RAMP_SHARE }
    }

    /** Próxima prescrição de um exercício. `history`: treinos concluídos, do mais antigo ao mais novo */
    fun suggest(exerciseID: String, sets: Int, reps: Int, history: List<SessionLog>): Suggestion {
        val mine = history.filter { !it.deload }.mapNotNull { s -> s.sets.filter { it.exerciseID == exerciseID }.ifEmpty { null } }
        val lastAll = mine.lastOrNull() ?: return core(exerciseID, sets, reps, emptyList())
        val past = mine.map(::workSets)
        val work = past.lastOrNull().orEmpty()
        val top = lastAll.maxOfOrNull { it.weight } ?: 0.0
        val ramp = lastAll.filter { it.weight < top * RAMP_SHARE }
        val wanted = maxOf(sets - ramp.size, 1)
        var s = core(exerciseID, work.size, reps, past)
        val lastWeight = work.maxOfOrNull { it.weight } ?: 0.0
        val raised = s.weight > lastWeight
        var reason = s.reason
        if (ramp.isNotEmpty()) reason += " As séries leves (${ramp.joinToString(", ") { fmt(it.weight) }} kg) contam como aquecimento."
        s = s.copy(sets = if (raised) minOf(wanted, work.size) else minOf(wanted, work.size + 1), ramp = ramp.map { it.weight to it.reps },
                   reason = reason)
        return s
    }

    private fun core(exerciseID: String, sets: Int, repsIn: Int, past: List<List<SetLog>>): Suggestion {
        val ex = Exercises.byID(exerciseID)
        val type = ex?.type ?: ExerciseType.WEIGHTED
        val goal = if (type == ExerciseType.WEIGHTED) TrainingGoal.of(exerciseID) else null
        val reps = goal?.range?.first ?: repsIn
        val last = past.lastOrNull()
        if (last == null) {
            if (type == ExerciseType.WEIGHTED) {
                PRBook.workingWeight(exerciseID, reps, ex?.increment ?: 2.5)?.let { (w, pr) ->
                    return Suggestion(w, reps, "Pelo seu PR de ${fmt(pr.weight)} kg × ${pr.reps}: ${fmt(w)} kg para $reps reps, com 1–2 de sobra.")
                }
            }
            return Suggestion(0.0, reps, if (ex?.type == ExerciseType.WEIGHTED) "Primeira vez: escolha uma carga em que as $reps reps saiam com boa técnica."
                                         else "Primeira vez: faça o que conseguir com boa técnica.")
        }

        val lastWeight = last.filter { it.done }.maxOfOrNull { it.weight } ?: last.maxOfOrNull { it.weight } ?: 0.0
        val lastTarget = last.maxOfOrNull { it.target } ?: reps

        if (goal != null) {
            val r = goal.range
            val target = minOf(maxOf(lastTarget, r.first), r.last)
            val work = last.take(maxOf(sets, 1))
            val allDone = last.size >= sets && work.all { it.done }
            val minReps = work.minOfOrNull { it.reps } ?: 0
            val inc = ex?.increment ?: 2.5
            if (allDone && minReps >= r.last) {
                return Suggestion(lastWeight + inc, r.first, "${goal.label}: bateu ${r.last} reps em todas. +${fmt(inc)} kg e volta para ${r.first}.")
            }
            if (allDone && minReps >= target) {
                val next = minOf(target + 1, r.last)
                return Suggestion(lastWeight, next, "${goal.label}: mesma carga, $next reps (faixa ${r.first}–${r.last}).")
            }
            return Suggestion(lastWeight, target, "${goal.label}: mesma carga até completar $target reps em todas as séries.")
        }

        val target = maxOf(reps, 1)
        if (lastTarget < target) return Suggestion(lastWeight, target, "Nova meta de $target reps: mantenha a carga até completar.")
        val success = last.size >= sets && last.take(sets).all { it.hit } && lastTarget >= target

        when {
            type == ExerciseType.DISTANCE -> {
                val best = last.filter { it.done }.map { it.reps }.filter { it > 0 }.minOrNull() ?: lastTarget
                return Suggestion(lastWeight, best, "Mesma distância: tente baixar de ${clock(best)}.")
            }
            type == ExerciseType.TIME -> return if (success) Suggestion(lastWeight, lastTarget + 5, "+5 s: você segurou todas as séries.")
                else Suggestion(lastWeight, lastTarget, "Mesmo tempo: tente segurar todas as séries.")
            type == ExerciseType.BODYWEIGHT && lastWeight == 0.0 -> return if (success) Suggestion(0.0, lastTarget + 1, "+1 rep: você completou todas as séries.")
                else Suggestion(0.0, lastTarget, "Mesmas reps: faltou completar da última vez.")
        }
        val inc = ex?.increment ?: 2.5
        if (success) return Suggestion(lastWeight + inc, target, "+${fmt(inc)} kg: você completou todas as séries da última vez.")
        var misses = 0
        for (s in past.reversed()) {
            val w = s.filter { it.done }.maxOfOrNull { it.weight } ?: s.maxOfOrNull { it.weight } ?: 0.0
            val ok = s.isNotEmpty() && s.all { it.hit }
            if (w != lastWeight || ok) break
            misses++
        }
        if (misses >= DELOAD_AFTER && lastWeight > 0) {
            val reduced = floor((lastWeight * 0.9) / inc) * inc
            return Suggestion(reduced, target, "Deload de 10 %: $misses treinos sem completar ${fmt(lastWeight)} kg. Reconstrua a partir daqui.")
        }
        return Suggestion(lastWeight, target, "Mesma carga: faltou completar da última vez ($misses/$DELOAD_AFTER antes do deload).")
    }

    /** Aquecimento: 40 % × 10, 60 % × 6, 80 % × 3 (arredondado ao incremento) */
    fun warmup(work: Double, increment: Double, minimum: Double = 0.0): List<Pair<Double, Int>> {
        if (work <= 0) return emptyList()
        return listOf(0.4 to 10, 0.6 to 6, 0.8 to 3).mapNotNull { (pct, reps) ->
            val w = maxOf(roundHalfAwayFromZero(work * pct / increment) * increment, minimum)
            if (w < work) w to reps else null
        }
    }

    /** 1RM estimado (Epley). Não estima acima de 12 reps */
    fun oneRM(weight: Double, reps: Int): Double? {
        if (weight <= 0 || reps !in 1..12) return null
        return if (reps == 1) weight else weight * (1 + reps.toDouble() / 30)
    }

    fun bestOneRM(sets: List<SetLog>): Double? = sets.filter { it.done }.mapNotNull { oneRM(it.weight, it.reps) }.maxOrNull()

    /** Força na escala de 1RM: acima de 12 reps conta como 12; sem carga, 0 */
    fun strength(weight: Double, reps: Int): Double = oneRM(weight, minOf(reps, 12)) ?: 0.0

    /** Calculadora reps × carga a partir do 1RM */
    fun repTable(oneRM: Double, increment: Double, reps: List<Int> = listOf(12, 10, 8, 5, 3)): List<Pair<Int, Double>> {
        val inc = if (increment > 0) increment else 2.5
        return reps.map { r -> r to roundHalfAwayFromZero((oneRM / (1 + r.toDouble() / 30)) / inc) * inc }
    }

    /** Esforço de um treino salvo sem a tela de conclusão: média dos últimos (até 10), ou 7 */
    fun estimatedEffort(recent: List<Int>): Int {
        val valid = recent.takeLast(10).filter { it in 1..10 }
        if (valid.isEmpty()) return 7
        return roundHalfAwayFromZero(valid.sum().toDouble() / valid.size).toInt()
    }

    /** Recordes batidos na sessão em relação ao histórico anterior */
    fun records(session: SessionLog, history: List<SessionLog>): List<String> {
        val out = mutableListOf<String>()
        val ids = session.sets.map { it.exerciseID }.distinct()
        for (id in ids) {
            val now = session.sets.filter { it.exerciseID == id && it.done }
            val before = history.flatMap { it.sets }.filter { it.exerciseID == id && it.done } + PRBook.manual[id].orEmpty()
            if (now.isEmpty() || before.isEmpty()) continue
            val name = Exercises.name(id)
            val maxNow = now.maxOf { it.weight }
            val maxBefore = before.maxOf { it.weight }
            if (Exercises.byID(id)?.type == ExerciseType.DISTANCE) {
                if (maxNow > maxBefore) out += "$name: maior distância, ${meters(maxNow)}"
                continue
            }
            val a = bestOneRM(now)
            val b = bestOneRM(before)
            if (maxNow > maxBefore && maxNow > 0) {
                out += "$name: maior carga, ${fmt(maxNow)} kg"
            } else if (a != null && b != null && a > b + 0.01) {
                out += "$name: 1RM estimado ${fmt(a)} kg"
            } else if (maxNow == 0.0 && maxBefore == 0.0) {
                val r = now.maxOf { it.reps }
                if (r > (before.maxOfOrNull { it.reps } ?: 0)) out += "$name: $r reps"
            }
        }
        return out
    }

    /** Número em pt-BR: inteiro sem casas; 2 casas só quando exato nelas (1,25); senão 1 casa */
    fun fmt(w: Double): String {
        if (w % 1.0 == 0.0) return w.toLong().toString()
        val cents = roundHalfAwayFromZero(w * 100)
        val exact = abs(w * 100 - cents) < 1e-6 && cents.toLong() % 10 != 0L
        val text = if (exact) String.format(java.util.Locale.ROOT, "%.2f", w) else String.format(java.util.Locale.ROOT, "%.1f", w)
        return text.replace(".", ",")
    }
}

/** "1:30", "1:02:03" (Wod.swift `clock`) */
fun clock(s: Int): String = if (s >= 3600) String.format(java.util.Locale.ROOT, "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
    else String.format(java.util.Locale.ROOT, "%d:%02d", s / 60, s % 60)

/** Distância de uma série: "800 m", "1.500 m", "10 km" */
fun meters(m: Double): String =
    if (m >= 10_000 && m % 1000 == 0.0) "${(m / 1000).toInt()} km"
    else "${java.text.NumberFormat.getIntegerInstance(java.util.Locale.forLanguageTag("pt-BR")).format(roundHalfAwayFromZero(m).toLong())} m"

/** Dias da semana do Calendar do iOS (1 = domingo) na ordem de segunda a domingo */
val weekdaySymbols: List<Pair<Int, String>> = listOf(2 to "Seg", 3 to "Ter", 4 to "Qua", 5 to "Qui", 6 to "Sex", 7 to "Sáb", 1 to "Dom")

fun weekdaysText(days: Set<Int>): String =
    if (days.isEmpty()) "Sem dia fixo" else weekdaySymbols.filter { it.first in days }.joinToString(", ") { it.second }

/** Dia da semana do iOS (domingo = 1) */
fun iosWeekday(d: LocalDate): Int = d.dayOfWeek.value % 7 + 1

/** Modelos prontos (Progression.swift `RoutineTemplate`) */
data class RoutineTemplate(val name: String, val detail: String, val routines: List<TemplateRoutine>) {
    data class TemplateRoutine(val name: String, val weekdays: Set<Int>, val items: List<Triple<String, Int, Int>>)

    companion object {
        private fun r(name: String, days: Set<Int>, vararg items: Triple<String, Int, Int>) = TemplateRoutine(name, days, items.toList())
        private fun i(id: String, sets: Int, reps: Int) = Triple(id, sets, reps)

        val all = listOf(
            RoutineTemplate("ABC", "3 treinos, 6 dias: empurrar, puxar, pernas", listOf(
                r("A · Peito, ombro e tríceps", setOf(2, 5), i("supino-reto", 4, 8), i("supino-inclinado-halter", 3, 10), i("crucifixo", 3, 12),
                  i("desenvolvimento-halter", 3, 10), i("elevacao-lateral", 3, 15), i("triceps-corda", 3, 12)),
                r("B · Costas e bíceps", setOf(3, 6), i("puxada-frente", 4, 10), i("remada-curvada", 4, 8), i("remada-baixa", 3, 12),
                  i("face-pull", 3, 15), i("rosca-direta", 3, 10), i("rosca-martelo", 3, 12)),
                r("C · Pernas e abdômen", setOf(4, 7), i("agachamento", 4, 8), i("leg-press", 3, 12), i("stiff", 3, 10),
                  i("cadeira-extensora", 3, 12), i("panturrilha-pe", 4, 15), i("prancha", 3, 45)),
            )),
            RoutineTemplate("Full body", "Corpo todo, 3× por semana", listOf(
                r("Full body", setOf(2, 4, 6), i("agachamento", 3, 8), i("supino-reto", 3, 8), i("remada-curvada", 3, 8),
                  i("desenvolvimento", 3, 10), i("stiff", 3, 10), i("prancha", 3, 45)),
            )),
            RoutineTemplate("Superior / Inferior", "4 dias alternando", listOf(
                r("Superior", setOf(2, 5), i("supino-reto", 4, 8), i("remada-curvada", 4, 8), i("desenvolvimento-halter", 3, 10),
                  i("puxada-frente", 3, 10), i("rosca-alternada", 3, 12), i("triceps-pulley", 3, 12)),
                r("Inferior", setOf(3, 6), i("agachamento", 4, 8), i("terra-romeno", 3, 10), i("leg-press", 3, 12),
                  i("mesa-flexora", 3, 12), i("panturrilha-sentado", 4, 15), i("abdominal", 3, 15)),
            )),
            RoutineTemplate("CrossFit", "3 dias: olímpicos, ginástica e força + metcon", listOf(
                r("CF A · Olímpicos", setOf(2), i("cf-power-snatch", 5, 3), i("cf-hang-power-clean", 5, 3), i("cf-push-jerk", 4, 3),
                  i("cf-overhead-squat", 3, 5), i("cf-box-jump", 3, 10), i("cf-double-under", 3, 50)),
                r("CF B · Ginástica", setOf(4), i("cf-kipping-pull-up", 5, 10), i("cf-toes-to-bar", 4, 10), i("cf-hspu", 4, 6),
                  i("cf-ring-dip", 3, 10), i("cf-pistol", 3, 8), i("cf-l-sit", 3, 20)),
                r("CF C · Força e metcon", setOf(6), i("agachamento-frontal", 5, 5), i("levantamento-terra", 4, 5), i("cf-push-press", 4, 6),
                  i("thruster", 3, 12), i("kettlebell-swing", 3, 20), i("cf-wall-ball", 3, 20)),
            )),
            RoutineTemplate("Kettlebell e metcon", "Corpo todo com kettlebell, 2× por semana", listOf(
                r("Kettlebell", setOf(3, 6), i("kettlebell-swing", 5, 20), i("agachamento-goblet", 4, 12), i("cf-kb-snatch", 4, 8),
                  i("cf-turkish", 3, 3), i("cf-sdhp", 3, 12), i("cf-mountain-climber", 3, 30)),
            )),
            RoutineTemplate("Em casa", "Só peso do corpo, 3× por semana", listOf(
                r("Peso do corpo", setOf(2, 4, 6), i("flexao", 4, 12), i("agachamento-livre-corpo", 4, 20), i("barra-fixa", 3, 6),
                  i("afundo", 3, 12), i("mergulho-banco", 3, 12), i("prancha", 3, 45), i("burpee", 3, 10)),
            )),
        )

        /** Descanso do item ao instalar: 120 s em grupo pesado com 4+ séries, senão 90 */
        fun rest(exerciseID: String, sets: Int): Int = if ((Exercises.byID(exerciseID)?.group?.heavy ?: false) && sets >= 4) 120 else 90
    }
}
