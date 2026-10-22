package com.alonsoalmeida.gymbros.domain

import kotlin.math.floor

/** O que conta de um check-in. Fonte: Leagues.swift (`ScoreInput`). Atividade do Saúde chega com esforço 5, sem metros nem kcal. */
data class ScoreInput(
    val kind: ActivityKind,
    val minutes: Int,
    val effort: Int,
    val meters: Double? = null,
    val kcal: Double? = null,
    val workoutTypeID: Long? = null,
)

object Kcal {
    const val REFERENCE_WEIGHT = 70.0

    /** Calorias ativas estimadas (HealthSync.activeKcal): o esforço aqui não é limitado a 1…10, como no iOS */
    fun active(kind: ActivityKind, minutes: Int, effort: Int, weight: Double = REFERENCE_WEIGHT): Double {
        val met = kind.met * (0.6 + 0.08 * effort.toDouble())
        return maxOf(met - 1, 0.0) * 3.5 * weight / 200 * minutes.toDouble()
    }
}

/** Quais tipos valem pontos na liga ("only:1,2", "except:…", "" = todos). Fonte: Leagues.swift (`LeagueActivityRule`) */
data class LeagueActivityRule(val mode: String = "all", val workoutTypeIDs: Set<Long> = emptySet()) {
    fun accepts(id: Long?): Boolean {
        if (id == null) return true
        return when (mode) {
            "only" -> id in workoutTypeIDs
            "except" -> id !in workoutTypeIDs
            else -> true
        }
    }

    companion object {
        fun parse(raw: String): LeagueActivityRule {
            val parts = raw.split(":", limit = 2)
            if (parts.size != 2 || parts[0] !in setOf("all", "only", "except")) return LeagueActivityRule()
            return LeagueActivityRule(parts[0], parts[1].split(",").mapNotNull { it.toLongOrNull()?.takeIf { v -> v >= 0 } }.toSet())
        }
    }
}

/** Uma linha da tabela "por atividade". Fonte: LeagueRules.swift (`ActivityPointRule`) */
data class ActivityPointRule(
    val workoutTypeIDs: List<Long> = emptyList(),
    val sections: List<String> = emptyList(),
    val method: String = "perCheckIn",
    val points: Int = 1,
    val every: Int = 30,
    val metric: String = "minutes",
) {
    fun matches(typeID: Long?): Boolean {
        if (typeID == null) return false
        if (typeID in workoutTypeIDs) return true
        val section = WorkoutType.byID(typeID)?.section ?: return false
        return section in sections
    }

    /** Mais específico primeiro: tipo antes de seção */
    val specificity: Int get() = if (workoutTypeIDs.isEmpty()) 0 else 1

    fun score(i: ScoreInput): Int {
        if (method == "perCheckIn") return points
        val amount = when (metric) {
            "km" -> (i.meters ?: 0.0) / 1000
            "kcal" -> i.kcal ?: Kcal.active(i.kind, i.minutes, i.effort)
            else -> minOf(i.minutes, Game.MAX_MINUTES).toDouble()
        }
        if (every <= 0) return 0
        return floor(amount / every.toDouble()).toInt() * points
    }
}

object LeagueScore {
    /** Pesos guardados como "forca:1.5,tecnica:0.5" (só os diferentes de 1). Fonte: League.swift (`attributeWeights`) */
    fun parseWeights(raw: String): Map<Attribute, Double> =
        raw.split(",").mapNotNull { pair ->
            val p = pair.split(":")
            val a = if (p.size == 2) Attribute.of(p[0]) else null
            val v = if (p.size == 2) p[1].toDoubleOrNull() else null
            if (a != null && v != null) a to v else null
        }.toMap()

    /**
     * Pontos pelo modo da liga (Leagues.swift `LeagueScoring.score`). No modo pontos com pesos, o fator soma as partes da
     * tabela da categoria (não a divisão gravada). ND-9: o iOS soma na ordem de um Dictionary, que muda a cada execução;
     * aqui a ordem é a dos atributos (F, R, A, T). Em raros casos na borda do arredondamento, pode dar 1 de diferença.
     */
    fun byScoring(scoring: LeagueScoring, i: ScoreInput, weights: Map<Attribute, Double> = emptyMap()): Int = when (scoring) {
        LeagueScoring.PONTOS -> {
            val xp = Game.xp(i.kind, i.minutes, i.effort)
            if (weights.isEmpty()) xp
            else {
                var factor = 0.0
                for (a in Attribute.entries) i.kind.weights[a]?.let { factor += it * (weights[a] ?: 1.0) }
                roundToIntSwift(xp.toDouble() * factor)
            }
        }
        LeagueScoring.TREINOS, LeagueScoring.DIAS -> 1
        LeagueScoring.ATIVIDADES -> 0
        LeagueScoring.MINUTOS -> minOf(i.minutes, Game.MAX_MINUTES)
        LeagueScoring.DISTANCIA -> (i.meters ?: 0.0).toInt()
        LeagueScoring.CALORIAS -> roundToIntSwift(i.kcal ?: Kcal.active(i.kind, i.minutes, i.effort))
    }

    /** Tabela "por atividade": a linha mais específica que casa; empate fica com a primeira; fora da tabela vale 0 */
    fun byRules(rules: List<ActivityPointRule>, i: ScoreInput): Int {
        var best: ActivityPointRule? = null
        for (r in rules) if (r.matches(i.workoutTypeID) && (best == null || r.specificity > best.specificity)) best = r
        return best?.score(i) ?: 0
    }

    /** Pontos de um check-in nesta liga (League.swift `score`): tipo aceito → modo → foto (negativo não passa pela foto) */
    fun score(
        i: ScoreInput,
        scoring: LeagueScoring,
        weightsRaw: String,
        activityRule: LeagueActivityRule,
        pointRules: List<ActivityPointRule>,
        photoRule: PhotoRule,
        hasPhoto: Boolean = true,
    ): Int {
        if (!activityRule.accepts(i.workoutTypeID)) return 0
        val raw = if (scoring == LeagueScoring.ATIVIDADES) byRules(pointRules, i)
                  else byScoring(scoring, i, if (scoring == LeagueScoring.PONTOS) parseWeights(weightsRaw) else emptyMap())
        return if (raw < 0) raw else photoRule.apply(raw, hasPhoto)
    }
}
