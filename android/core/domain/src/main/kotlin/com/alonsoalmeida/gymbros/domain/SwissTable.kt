package com.alonsoalmeida.gymbros.domain

import java.time.Instant
import java.time.LocalDate

data class SwissMatch(val a: String, val b: String?, val tallyA: SwissTally, val tallyB: SwissTally, val pointsA: Double, val pointsB: Double)

data class SwissRound(val day: LocalDate, val matches: List<SwissMatch>, val finished: Boolean)

/** Rodadas suíças diárias. Fonte: Swiss.swift (`Swiss.table`). O dia é sempre o do fuso de Brasília (`RuleClock.LEAGUE_ZONE`). */
object SwissTable {
    fun table(
        members: List<String>,
        tallies: Map<LocalDate, Map<String, SwissTally>>,
        start: Instant,
        end: Instant?,
        clock: RuleClock,
        seed: String,
        criterion: SwissCriterion,
        identity: Map<String, String> = emptyMap(),
        joined: Map<String, Instant> = emptyMap(),
    ): List<SwissRound> {
        val players = members.distinct()
        if (players.size < 2) return emptyList()
        val key = { id: String -> identity[id] ?: id }
        val today = clock.today
        val last = end?.let { minOf(today, clock.day(it)) } ?: today
        var day = clock.day(start)
        val points = HashMap<String, Double>()
        val met = HashMap<String, HashMap<String, Int>>()
        val byes = HashMap<String, Int>()
        val rounds = mutableListOf<SwissRound>()
        val firstDay = joined.mapValues { clock.day(it.value) }
        while (!day.isAfter(last)) {
            val active = players.filter { !(firstDay[it] ?: day).isAfter(day) }
            if (active.size < 2) {
                day = day.plusDays(1)
                continue
            }
            val ranked = if (rounds.isEmpty()) {
                val stamp = Swiss.dayStamp(day.year, day.monthValue, day.dayOfMonth)
                val hash = active.associateWith { SeededRandom("${key(it)}-$seed-$stamp").next() }
                active.sortedWith { x, y ->
                    val hx = hash.getValue(x)
                    val hy = hash.getValue(y)
                    if (hx != hy) hx.compareTo(hy) else key(x).compareTo(key(y))
                }
            } else {
                active.sortedWith { x, y ->
                    val px = points[x] ?: 0.0
                    val py = points[y] ?: 0.0
                    if (px != py) py.compareTo(px) else key(x).compareTo(key(y))
                }
            }
            val pairing = Swiss.pair(ranked, met, byes)
            val finished = day.isBefore(today)
            val dayTallies = tallies[day] ?: emptyMap()
            val matches = pairing.pairs.map { (a, b) ->
                val ta = dayTallies[a] ?: SwissTally()
                val tb = dayTallies[b] ?: SwissTally()
                val (pa, pb) = criterion.result(ta, tb)
                SwissMatch(a, b, ta, tb, pa, pb)
            }.toMutableList()
            pairing.bye?.let { matches += SwissMatch(it, null, dayTallies[it] ?: SwissTally(), SwissTally(), 1.0, 0.0) }
            rounds += SwissRound(day, matches, finished)
            if (finished) {
                for (m in matches) {
                    points[m.a] = (points[m.a] ?: 0.0) + m.pointsA
                    if (m.b != null) {
                        points[m.b] = (points[m.b] ?: 0.0) + m.pointsB
                        met.getOrPut(m.a) { HashMap() }.merge(m.b, 1, Int::plus)
                        met.getOrPut(m.b) { HashMap() }.merge(m.a, 1, Int::plus)
                    } else {
                        byes.merge(m.a, 1, Int::plus)
                    }
                }
            }
            day = day.plusDays(1)
        }
        return rounds
    }

    /** Pontos suíços acumulados nas rodadas encerradas (folga vale 1) */
    fun points(rounds: List<SwissRound>): Map<String, Double> {
        val out = HashMap<String, Double>()
        for (r in rounds.filter { it.finished }) for (m in r.matches) {
            out[m.a] = (out[m.a] ?: 0.0) + (if (m.b == null) 1.0 else m.pointsA)
            if (m.b != null) out[m.b] = (out[m.b] ?: 0.0) + m.pointsB
        }
        return out
    }
}
