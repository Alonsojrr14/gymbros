package com.alonsoalmeida.gymbros.domain

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

/** Casos copiados dos testes Swift (GymBrosTests): o mesmo resultado nos dois apps */
class GroupATest {
    @Test
    fun roundingMatchesSwift() {
        assertEquals(3.0, roundHalfAwayFromZero(2.5))
        assertEquals(-3.0, roundHalfAwayFromZero(-2.5))
        assertEquals(2.0, roundHalfAwayFromZero(2.4999999999999996))
        assertEquals(1.0, roundHalfAwayFromZero(0.5))
        assertEquals(0.0, roundHalfAwayFromZero(0.49999999999999994))
    }

    /** GameTests.testXPFormula */
    @Test
    fun xpFormula() {
        assertEquals(30, Game.xp(ActivityKind.MUSCULACAO, 60, 5))
        assert(Game.xp(ActivityKind.MUSCULACAO, 60, 9) > 30)
        assertEquals(0, Game.xp(ActivityKind.MUSCULACAO, 0, 5))
        assertEquals(Game.xp(ActivityKind.CORRIDA, Game.MAX_MINUTES, 5), Game.xp(ActivityKind.CORRIDA, 600, 5))
        assertEquals(1, Game.xp(ActivityKind.YOGA, 1, 1))
    }

    @Test
    fun branchTieGoesToFirstAttribute() {
        val tie = mapOf(Attribute.TECNICA to 10.0, Attribute.FORCA to 10.0)
        assertEquals(Attribute.FORCA to Attribute.TECNICA, Game.branch(tie))
    }

    /** SwissTests.testPairsNeighboursInRankOrder */
    @Test
    fun pairsNeighboursInRankOrder() {
        val p = Swiss.pair(listOf("a", "b", "c", "d"), emptyMap(), emptyMap())
        assertEquals(listOf("a" to "b", "c" to "d"), p.pairs)
        assertNull(p.bye)
    }

    /** SwissTests.testAvoidsRematchWhenPossible */
    @Test
    fun avoidsRematchWhenPossible() {
        val met = mapOf("a" to mapOf("b" to 1), "b" to mapOf("a" to 1), "c" to mapOf("d" to 1), "d" to mapOf("c" to 1))
        assertEquals(listOf("a" to "c", "b" to "d"), Swiss.pair(listOf("a", "b", "c", "d"), met, emptyMap()).pairs)
    }

    /** SwissTests.testRematchWhenUnavoidable */
    @Test
    fun rematchWhenUnavoidable() {
        val met = mapOf("a" to mapOf("b" to 3), "b" to mapOf("a" to 3))
        assertEquals(listOf("a" to "b"), Swiss.pair(listOf("a", "b"), met, emptyMap()).pairs)
    }

    /** SwissTests.testOddPlayerByeGoesToLowestWithFewestByes */
    @Test
    fun oddPlayerByeGoesToLowestWithFewestByes() {
        assertEquals("b", Swiss.pair(listOf("a", "b", "c"), emptyMap(), mapOf("c" to 1)).bye)
    }

    /** SwissTests.testResultByCriterion */
    @Test
    fun resultByCriterion() {
        val none = SwissTally()
        val one = SwissTally(score = 30, checkIns = 1)
        val two = SwissTally(score = 20, checkIns = 2)
        assertEquals(1.0, SwissCriterion.PONTOS.result(one, two).first)
        assertEquals(1.0, SwissCriterion.CHECKINS.result(one, two).second)
        assertEquals(0.5, SwissCriterion.PRESENCA.result(one, two).first)
        assertEquals(1.0, SwissCriterion.PRESENCA.result(one, none).first)
        for (c in SwissCriterion.entries) assertEquals(0.0 to 0.0, c.result(none, none))
    }

    /** SwissTests.testBonusTable e Swiss.swift `SwissBonus.table` */
    @Test
    fun bonusTable() {
        assertEquals(10, SwissBonus.value(SwissResult.VITORIA, LeagueScoring.PONTOS))
        assertEquals(500, SwissBonus.value(SwissResult.FOLGA, LeagueScoring.DISTANCIA))
        assertEquals(2, SwissBonus.value(SwissResult.EMPATE, LeagueScoring.MINUTOS))
        assertEquals(0, SwissBonus.value(SwissResult.EMPATE, LeagueScoring.DIAS))
        assertEquals(5, SwissBonus.value(SwissResult.EMPATE, LeagueScoring.ATIVIDADES))
        assertEquals(0, SwissBonus.value(SwissResult.DERROTA, LeagueScoring.PONTOS))
    }

    /** LeagueTests.testPhotoRule / testHalfPhotoNeverZeroesAScore */
    @Test
    fun photoRule() {
        assertEquals(15, PhotoRule.METADE.apply(30, hasPhoto = false))
        assertEquals(1, PhotoRule.METADE.apply(1, hasPhoto = false))
        assertEquals(0, PhotoRule.OBRIGATORIA.apply(30, hasPhoto = false))
        assertEquals(30, PhotoRule.OBRIGATORIA.apply(30, hasPhoto = true))
    }

    @Test
    fun dayStampHasNoLeadingZeros() {
        assertEquals("2026-1-5", Swiss.dayStamp(2026, 1, 5))
    }
}
