package com.alonsoalmeida.gymbros.domain.train

import com.alonsoalmeida.gymbros.domain.ActivityKind
import com.alonsoalmeida.gymbros.domain.Attribute
import com.alonsoalmeida.gymbros.domain.AttributeSplit

/**
 * Divisão do XP com o detalhe do treino (Bros/AttributeSplit.swift: séries da musculação e movimentos/formato do WOD).
 * Estende o `AttributeSplit` do domínio (tipo exato, duração, esforço e ritmo, provado pelo vetor S) sem mudá-lo:
 * sem séries nem WOD, o resultado é o mesmo do `AttributeSplit.split`.
 */
object TrainSplit {
    private val F = Attribute.FORCA
    private val R = Attribute.RESISTENCIA
    private val A = Attribute.AGILIDADE
    private val T = Attribute.TECNICA

    data class SetSignal(val exerciseID: String, val reps: Int, val rest: Int)
    data class WodSignal(val format: WodFormat, val exercises: List<String>)

    fun split(kind: ActivityKind, minutes: Int, effort: Int, meters: Double? = null, healthType: Long? = null,
              sets: List<SetSignal> = emptyList(), wod: WodSignal? = null): Map<Attribute, Double> {
        if (sets.isEmpty() && wod == null) return AttributeSplit.split(kind, minutes, effort, meters, healthType)
        var w = healthType?.let(AttributeSplit::health) ?: kind.weights
        detail(sets, wod)?.let { w = mix(w, 0.25, it, 0.75) }
        w = intensity(w, kind, minutes, effort, meters)
        return AttributeSplit.tidy(w)
    }

    private fun detail(sets: List<SetSignal>, wod: WodSignal?): Map<Attribute, Double>? {
        if (sets.isNotEmpty()) {
            return average(sets.map { s ->
                var w = movement(s.exerciseID, s.reps)
                // Descanso curto vira condicionamento
                if (s.rest in 1..45) w = AttributeSplit.shift(w, R, 0.25)
                w
            })
        }
        if (wod != null) {
            val moves = wod.exercises.map { movement(it, null) }
            val format = wodFormat(wod.format)
            return if (moves.isEmpty()) format else mix(average(moves), 0.6, format, 0.4)
        }
        return null
    }

    enum class Pattern { SKILL, PLYO, CARDIO, CARRY, ISOMETRIC, BODYWEIGHT, MACHINE, FREE }

    private val skillWords = listOf("snatch", "clean", "jerk", "overhead-squat", "pistol", "hspu", "handstand", "muscle-up",
                                    "turkish", "l-sit", "rope-climb", "toes-to-bar", "knees-to-elbows", "kipping", "ring-dip")
    private val plyoWords = listOf("salto", "jump", "pliometrica", "burpee", "tuck", "double-under", "mountain-climber")
    private val cardioWords = listOf("esteira", "remo", "row-cal", "bike", "ski", "corda-naval", "pular-corda", "eliptico", "escada")
    private val carryWords = listOf("farmer", "sandbag", "sled", "carry")

    fun pattern(id: String): Pattern {
        val e = Exercises.byID(id)
        if (skillWords.any { id.contains(it) }) return Pattern.SKILL
        if (plyoWords.any { id.contains(it) }) return Pattern.PLYO
        if (cardioWords.any { id.contains(it) }) return Pattern.CARDIO
        if (carryWords.any { id.contains(it) }) return Pattern.CARRY
        when (e?.type) {
            ExerciseType.DISTANCE -> return Pattern.CARDIO
            ExerciseType.TIME -> return Pattern.ISOMETRIC
            ExerciseType.BODYWEIGHT -> return Pattern.BODYWEIGHT
            else -> {}
        }
        if (e != null && listOf("Máquina", "Polia", "Smith").any { e.equipment.contains(it) }) return Pattern.MACHINE
        return Pattern.FREE
    }

    /** Divisão de um movimento; `reps` null = sem a série (WOD), usa a faixa do meio */
    fun movement(id: String, reps: Int?): Map<Attribute, Double> = when (val p = pattern(id)) {
        Pattern.SKILL -> mapOf(T to 0.6, F to 0.25, A to 0.15)
        Pattern.PLYO -> mapOf(A to 0.6, R to 0.25, F to 0.15)
        Pattern.CARDIO -> mapOf(R to 0.8, A to 0.2)
        Pattern.CARRY -> mapOf(F to 0.55, R to 0.45)
        Pattern.ISOMETRIC -> mapOf(T to 0.5, R to 0.3, F to 0.2)
        Pattern.BODYWEIGHT -> when {
            reps == null -> mapOf(F to 0.4, R to 0.3, T to 0.3)
            reps <= 10 -> mapOf(F to 0.55, T to 0.3, R to 0.15)
            else -> mapOf(R to 0.5, F to 0.3, T to 0.2)
        }
        Pattern.MACHINE, Pattern.FREE -> {
            val tech = if (p == Pattern.FREE) 0.15 else 0.05
            when (val r = reps ?: 10) {
                in Int.MIN_VALUE..5 -> mapOf(F to 1 - tech, T to tech)
                in 6..12 -> mapOf(F to 0.8 - tech, R to 0.2, T to tech)
                in 13..20 -> mapOf(F to 0.45, R to 0.55 - tech, T to tech)
                else -> { check(r > 20); mapOf(R to 0.7, F to 0.3 - tech, T to tech) }
            }
        }
    }

    private fun wodFormat(f: WodFormat): Map<Attribute, Double> = when (f) {
        is WodFormat.Emom, is WodFormat.Every -> mapOf(F to 0.4, T to 0.3, R to 0.3)
        is WodFormat.Tabata -> mapOf(A to 0.5, R to 0.5)
        is WodFormat.Amrap -> timed(f.minutes)
        is WodFormat.ForTime -> f.capMinutes?.let(::timed) ?: mapOf(R to 0.4, F to 0.3, A to 0.3)
        is WodFormat.Intervals -> if (f.emom) wodFormat(WodFormat.Emom(0)) else wodFormat(WodFormat.Amrap(f.blocks.sum()))
    }

    private fun timed(m: Int): Map<Attribute, Double> = when {
        m >= 15 -> mapOf(R to 0.6, F to 0.2, A to 0.2)
        m <= 8 -> mapOf(A to 0.4, F to 0.3, R to 0.3)
        else -> mapOf(R to 0.4, F to 0.3, A to 0.3)
    }

    /** Duração, esforço e ritmo; com séries ou WOD, o "curto e no talo" não vale (o detalhe já disse como foi) */
    private fun intensity(base: Map<Attribute, Double>, kind: ActivityKind, minutes: Int, effort: Int, meters: Double?): Map<Attribute, Double> {
        var w = base
        if (minutes >= 75) w = AttributeSplit.shift(w, R, minOf(0.25, (minutes - 60).toDouble() / 240))
        if (effort <= 3 && kind != ActivityKind.CAMINHADA) w = AttributeSplit.shift(w, T, 0.1)
        val m = meters ?: return w
        if (m < 300 || minutes <= 0) return w
        val km = m / 1000
        val hours = minutes.toDouble() / 60
        when (kind) {
            ActivityKind.CORRIDA -> {
                val pace = (minutes * 60).toDouble() / km
                if (pace < 270) w = AttributeSplit.shift(w, A, 0.25) else if (pace < 330) w = AttributeSplit.shift(w, A, 0.1)
                if (km >= 15) w = AttributeSplit.shift(w, R, 0.15)
            }
            ActivityKind.CAMINHADA -> {
                if (km / hours >= 6.5) w = AttributeSplit.shift(w, A, 0.1)
                if (km >= 12) w = AttributeSplit.shift(w, F, 0.1)
            }
            ActivityKind.BIKE -> {
                if (km / hours >= 30) w = AttributeSplit.shift(w, A, 0.15)
                if (km >= 60) w = AttributeSplit.shift(w, R, 0.1)
            }
            ActivityKind.NATACAO -> {
                val per100 = (minutes * 60).toDouble() / (m / 100)
                if (per100 < 120) { w = AttributeSplit.shift(w, T, 0.1); w = AttributeSplit.shift(w, A, 0.1) }
                if (m >= 2000) w = AttributeSplit.shift(w, R, 0.15)
            }
            else -> {}
        }
        return w
    }

    private fun mix(a: Map<Attribute, Double>, wa: Double, b: Map<Attribute, Double>, wb: Double): Map<Attribute, Double> {
        val out = LinkedHashMap<Attribute, Double>()
        for ((k, v) in a) out[k] = v * wa
        for ((k, v) in b) out[k] = (out[k] ?: 0.0) + v * wb
        return out
    }

    private fun average(list: List<Map<Attribute, Double>>): Map<Attribute, Double> {
        if (list.isEmpty()) return emptyMap()
        val out = LinkedHashMap<Attribute, Double>()
        for (w in list) for ((k, v) in w) out[k] = (out[k] ?: 0.0) + v / list.size
        return out
    }
}
