package com.alonsoalmeida.gymbros.domain

import java.time.Instant
import java.time.LocalDate

/** Estágios e limiares de XP. Fonte: Game.swift (`enum Stage`) */
enum class Stage(val raw: String, val threshold: Int) {
    EGG("egg", 0), BABY("baby", 60), ROOKIE("rookie", 300), CHAMPION("champion", 1200), ULTIMATE("ultimate", 3600);

    val next: Stage? get() = entries.getOrNull(ordinal + 1)
    /** Estágios em que o atributo dominante escolhe o galho */
    val branches: Boolean get() = this == CHAMPION || this == ULTIMATE
}

/**
 * Forma do bro (sem espécie). Dupla sempre na ordem F, R, A, T; a Lenda guarda o galho do Atleta de origem só quando
 * é de virada. Fonte: Game.swift (`struct MonsterForm`).
 */
class MonsterForm(val stage: Stage, attribute: Attribute?, attribute2: Attribute? = null, origin: Attribute? = null, origin2: Attribute? = null) {
    val attribute: Attribute?
    val attribute2: Attribute?
    val origin: Attribute?
    val origin2: Attribute?

    init {
        val (a, b) = ordered(attribute, attribute2)
        this.attribute = a
        this.attribute2 = b
        val (o1, o2) = ordered(origin, origin2)
        val virada = stage == Stage.ULTIMATE && o1 != null && (o1 != a || o2 != b)
        this.origin = if (virada) o1 else null
        this.origin2 = if (virada) o2 else null
    }

    /** "champion_forca", "champion_forca_resistencia", "ultimate_forca_to_resistencia" */
    val key: String
        get() {
            val a = attribute ?: return stage.raw
            val branch = listOfNotNull(a, attribute2).joinToString("_") { it.raw }
            val o = origin ?: return "${stage.raw}_$branch"
            val from = listOfNotNull(o, origin2).joinToString("_") { it.raw }
            return "${stage.raw}_${from}_to_$branch"
        }

    companion object {
        val EGG = MonsterForm(Stage.EGG, null)

        private fun ordered(a: Attribute?, b: Attribute?): Pair<Attribute?, Attribute?> {
            if (a == null || b == null || a == b) return a to null
            return if (a.ordinal > b.ordinal) b to a else a to b
        }
    }
}

/** Uma atividade como o jogo a vê. `share`: 1 no principal, 0,8 no representante de liga (RF-JOG-43) */
data class ActivityRecord(
    val id: String,
    val kind: ActivityKind,
    val date: Instant,
    val minutes: Int,
    val effort: Int,
    val weights: Map<Attribute, Double>? = null,
    val share: Double = 1.0,
) {
    val split: Map<Attribute, Double> get() = weights ?: kind.weights
}

class Snapshot {
    var totalXP = 0
    var form = MonsterForm.EGG
    val stageAttributes = LinkedHashMap<Attribute, Double>()
    val lifetimeAttributes = LinkedHashMap<Attribute, Double>()
    var hatchAttributes: Map<Attribute, Double> = emptyMap()
    val evolutions = mutableListOf<MonsterForm>()
    val xpByActivity = HashMap<String, Int>()
    var streak = 0
    var bestStreak = 0
    var todayXP = 0
}

/** O bro é função do histórico. Fonte: Game.swift (`Game.snapshot`, `streak`, `bestStreak`) */
object SnapshotRules {
    fun snapshot(records: List<ActivityRecord>, clock: RuleClock): Snapshot {
        val s = Snapshot()
        val dayTotals = HashMap<LocalDate, Int>()
        val dayGained = HashMap<LocalDate, Int>()
        for (r in records.sortedBy { it.date }) {
            val raw = roundToIntSwift(Game.xp(r.kind, r.minutes, r.effort).toDouble() * r.share)
            val day = clock.day(r.date)
            val before = dayTotals[day] ?: 0
            val full = maxOf(minOf(raw, Game.DAILY_SOFT_CAP - before), 0)
            val gainedBefore = dayGained[day] ?: 0
            val gained = minOf(full + (raw - full) / 3, maxOf(Game.DAILY_HARD_CAP - gainedBefore, 0))
            dayTotals[day] = before + raw
            dayGained[day] = gainedBefore + gained
            s.xpByActivity[r.id] = gained
            s.totalXP += gained
            for ((attr, w) in r.split) {
                s.stageAttributes[attr] = (s.stageAttributes[attr] ?: 0.0) + gained.toDouble() * w
                s.lifetimeAttributes[attr] = (s.lifetimeAttributes[attr] ?: 0.0) + gained.toDouble() * w
            }
            // Vários estágios numa atividade só: a fase nova ainda está vazia, então o galho usa a anterior
            var carried: Map<Attribute, Double> = emptyMap()
            while (true) {
                val next = s.form.stage.next ?: break
                if (s.totalXP < next.threshold) break
                val attrs: Map<Attribute, Double> = if (s.stageAttributes.isEmpty()) carried else HashMap(s.stageAttributes)
                if (s.form.stage == Stage.EGG) s.hatchAttributes = attrs
                s.form = if (next.branches) {
                    val (a, b) = Game.branch(attrs)
                    MonsterForm(next, a, b, origin = s.form.attribute, origin2 = s.form.attribute2)
                } else {
                    MonsterForm(next, null)
                }
                s.evolutions += s.form
                carried = attrs
                s.stageAttributes.clear()
            }
        }
        s.streak = streak(dayTotals.keys, clock.today)
        s.bestStreak = bestStreak(dayTotals.keys)
        s.todayXP = dayGained[clock.today] ?: 0
        return s
    }

    /** Dias seguidos com atividade, terminando hoje ou ontem */
    fun streak(days: Set<LocalDate>, today: LocalDate): Int {
        var day = if (days.contains(today)) today else today.minusDays(1)
        var count = 0
        while (days.contains(day)) {
            count++
            day = day.minusDays(1)
        }
        return count
    }

    /** Maior sequência de dias seguidos já feita */
    fun bestStreak(days: Set<LocalDate>): Int {
        var best = 0
        for (d in days) {
            if (days.contains(d.minusDays(1))) continue
            var n = 1
            var cur = d
            while (days.contains(cur.plusDays(1))) {
                n++
                cur = cur.plusDays(1)
            }
            best = maxOf(best, n)
        }
        return best
    }
}
