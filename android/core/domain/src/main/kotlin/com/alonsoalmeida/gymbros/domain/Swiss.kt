package com.alonsoalmeida.gymbros.domain

/** O que uma pessoa fez num dia da liga. Fonte: GymBros/Leagues/Swiss.swift */
data class SwissTally(val score: Int = 0, val checkIns: Int = 0) {
    val trained: Boolean get() = checkIns > 0
}

enum class SwissCriterion(val raw: String) {
    PONTOS("pontos"), CHECKINS("checkins"), PRESENCA("presenca");

    fun value(t: SwissTally): Int = when (this) {
        PONTOS -> t.score
        CHECKINS -> t.checkIns
        PRESENCA -> if (t.trained) 1 else 0
    }

    /** Pontos suíços de cada lado: ninguém treinou = 0 para os dois; empate = ½ para cada */
    fun result(a: SwissTally, b: SwissTally): Pair<Double, Double> {
        if (!a.trained && !b.trained) return 0.0 to 0.0
        val va = value(a)
        val vb = value(b)
        if (va == vb) return 0.5 to 0.5
        return if (va > vb) 1.0 to 0.0 else 0.0 to 1.0
    }
}

enum class SwissResult { VITORIA, EMPATE, DERROTA, FOLGA }

/** Modos de pontuação da liga (Leagues.swift `LeagueScoring`) */
enum class LeagueScoring(val raw: String) {
    PONTOS("pontos"), TREINOS("treinos"), DIAS("dias"), MINUTOS("minutos"), DISTANCIA("distancia"), CALORIAS("calorias"), ATIVIDADES("atividades")
}

/** Bônus no placar da liga, em unidades da métrica. Folga vale como vitória. */
object SwissBonus {
    private val table = mapOf(
        LeagueScoring.PONTOS to (10 to 5),
        LeagueScoring.MINUTOS to (5 to 2),
        LeagueScoring.DISTANCIA to (500 to 250),
        LeagueScoring.CALORIAS to (50 to 25),
        LeagueScoring.TREINOS to (1 to 0),
        LeagueScoring.DIAS to (1 to 0),
        LeagueScoring.ATIVIDADES to (10 to 5),
    )

    fun value(result: SwissResult, scoring: LeagueScoring): Int {
        val (win, draw) = table[scoring] ?: (0 to 0)
        return when (result) {
            SwissResult.VITORIA, SwissResult.FOLGA -> win
            SwissResult.EMPATE -> draw
            SwissResult.DERROTA -> 0
        }
    }
}

object Swiss {
    data class Pairing(val pairs: List<Pair<String, String>>, val bye: String?)

    /**
     * Pareia na ordem do ranking (melhor primeiro). Com número ímpar, folga quem folgou menos, do fim da lista.
     * Procura um pareamento sem revanche (no máximo 5 000 tentativas); se não houver, aceita a revanche com quem enfrentou menos vezes.
     */
    fun pair(ranked: List<String>, met: Map<String, Map<String, Int>>, byes: Map<String, Int>): Pairing {
        val list = ranked.toMutableList()
        var bye: String? = null
        if (list.size % 2 == 1) {
            val fewest = list.minOfOrNull { byes[it] ?: 0 } ?: 0
            val i = list.indexOfLast { (byes[it] ?: 0) == fewest }
            if (i >= 0) bye = list.removeAt(i)
        }
        val budget = intArrayOf(5_000)
        withoutRematch(list, met, budget)?.let { return Pairing(it, bye) }
        return Pairing(fewestRematches(list, met), bye)
    }

    private fun withoutRematch(list: List<String>, met: Map<String, Map<String, Int>>, budget: IntArray): List<Pair<String, String>>? {
        val first = list.firstOrNull() ?: return emptyList()
        for (j in 1 until list.size) {
            if ((met[first]?.get(list[j]) ?: 0) != 0) continue
            budget[0] -= 1
            if (budget[0] < 0) return null
            val rest = list.toMutableList()
            rest.removeAt(j)
            rest.removeAt(0)
            withoutRematch(rest, met, budget)?.let { return listOf(first to list[j]) + it }
        }
        return null
    }

    private fun fewestRematches(list: List<String>, met: Map<String, Map<String, Int>>): List<Pair<String, String>> {
        val left = list.toMutableList()
        val out = mutableListOf<Pair<String, String>>()
        while (left.size >= 2) {
            val first = left.removeAt(0)
            // Menor (vezes que se enfrentaram, posição): a tupla do Swift
            var j = 0
            for (k in left.indices) {
                val a = met[first]?.get(left[k]) ?: 0
                val b = met[first]?.get(left[j]) ?: 0
                if (a < b) j = k
            }
            out += first to left.removeAt(j)
        }
        return out
    }

    /** "2026-10-18" no calendário da rodada, sem zeros à esquerda ("2026-1-5"), como o `dayStamp` do iOS */
    fun dayStamp(year: Int, month: Int, day: Int): String = "$year-$month-$day"
}

/** Regra da foto. Fonte: Leagues.swift (`PhotoRule.apply`) */
enum class PhotoRule(val raw: String) {
    LIVRE("livre"), METADE("metade"), OBRIGATORIA("obrigatoria");

    fun apply(score: Int, hasPhoto: Boolean): Int {
        if (hasPhoto) return score
        return when (this) {
            LIVRE -> score
            // Arredonda para cima: metade de algo que vale nunca vira zero
            METADE -> (score + 1) / 2
            OBRIGATORIA -> 0
        }
    }
}
