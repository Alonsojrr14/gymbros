package com.alonsoalmeida.gymbros.domain

import kotlin.math.sqrt

/** Atributos do bro, na ordem do iOS (`Attribute.allCases`): decide o desempate do galho. Fonte: GymBros/Bros/Game.swift */
enum class Attribute(val raw: String) {
    FORCA("forca"), RESISTENCIA("resistencia"), AGILIDADE("agilidade"), TECNICA("tecnica");

    companion object {
        fun of(raw: String): Attribute? = entries.firstOrNull { it.raw == raw }
    }
}

/** Categoria do jogo, com o MET e a divisão de atributos da tabela do iOS (Game.swift `met` e `weights`) */
enum class ActivityKind(val raw: String, val met: Double, val weights: Map<Attribute, Double>) {
    MUSCULACAO("musculacao", 5.0, mapOf(Attribute.FORCA to 0.8, Attribute.TECNICA to 0.2)),
    CROSSFIT("crossfit", 8.0, mapOf(Attribute.FORCA to 0.4, Attribute.RESISTENCIA to 0.4, Attribute.AGILIDADE to 0.2)),
    CORRIDA("corrida", 9.5, mapOf(Attribute.RESISTENCIA to 0.8, Attribute.AGILIDADE to 0.2)),
    CAMINHADA("caminhada", 3.5, mapOf(Attribute.RESISTENCIA to 1.0)),
    BIKE("bike", 7.0, mapOf(Attribute.RESISTENCIA to 0.8, Attribute.FORCA to 0.2)),
    NATACAO("natacao", 8.0, mapOf(Attribute.RESISTENCIA to 0.6, Attribute.TECNICA to 0.4)),
    VOLEI("volei", 5.0, mapOf(Attribute.AGILIDADE to 0.6, Attribute.TECNICA to 0.4)),
    FUTEBOL("futebol", 7.0, mapOf(Attribute.AGILIDADE to 0.5, Attribute.RESISTENCIA to 0.5)),
    LUTAS("lutas", 9.0, mapOf(Attribute.AGILIDADE to 0.4, Attribute.TECNICA to 0.3, Attribute.FORCA to 0.3)),
    DANCA("danca", 5.0, mapOf(Attribute.AGILIDADE to 0.5, Attribute.TECNICA to 0.5)),
    YOGA("yoga", 3.0, mapOf(Attribute.TECNICA to 1.0)),
    OUTRO("outro", 5.0, mapOf(Attribute.FORCA to 0.25, Attribute.RESISTENCIA to 0.25, Attribute.AGILIDADE to 0.25, Attribute.TECNICA to 0.25));

    companion object {
        fun of(raw: String): ActivityKind = entries.firstOrNull { it.raw == raw } ?: OUTRO
    }
}

/** Regras do bro. Fonte: GymBros/Bros/Game.swift (`enum Game`) */
object Game {
    const val MAX_MINUTES = 240
    /** Acima disso no mesmo dia o XP conta 1/3, até o teto diário */
    const val DAILY_SOFT_CAP = 150
    const val DAILY_HARD_CAP = 300
    /** O 2º atributo precisa ter pelo menos 90% do 1º para virar híbrido */
    const val HYBRID_RATIO = 0.9

    fun xp(kind: ActivityKind, minutes: Int, effort: Int): Int {
        val m = minutes.coerceIn(0, MAX_MINUTES).toDouble()
        val intensity = 0.6 + 0.08 * effort.coerceIn(1, 10).toDouble() // esforço 5 = 1,0
        return maxOf(roundToIntSwift(m * kind.met * intensity / 10), if (minutes > 0) 1 else 0)
    }

    fun level(xp: Int): Int = sqrt(xp.toDouble() / 5).toInt() + 1

    /** Dominante: o maior, e no empate o primeiro na ordem F, R, A, T (`max(by:)` do Swift fica com o primeiro) */
    fun dominant(attrs: Map<Attribute, Double>): Attribute {
        var best = Attribute.FORCA
        for (a in Attribute.entries) if ((attrs[a] ?: 0.0) > (attrs[best] ?: 0.0)) best = a
        return best
    }

    /** Galho da evolução: o dominante e, se o segundo estiver quase empatado, ele também */
    fun branch(attrs: Map<Attribute, Double>): Pair<Attribute, Attribute?> {
        val a = dominant(attrs)
        val top = attrs[a] ?: 0.0
        val rest = Attribute.entries.filter { it != a }
        var b = rest.first()
        for (x in rest) if ((attrs[x] ?: 0.0) > (attrs[b] ?: 0.0)) b = x
        return if (top > 0 && (attrs[b] ?: 0.0) >= top * HYBRID_RATIO) a to b else a to null
    }
}
