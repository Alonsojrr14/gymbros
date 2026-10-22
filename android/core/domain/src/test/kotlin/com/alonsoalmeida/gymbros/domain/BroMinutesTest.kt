package com.alonsoalmeida.gymbros.domain

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import java.time.Instant
import java.time.ZoneId

/** Treinos no mesmo horário não somam duas vezes; cada treino conta no máximo 2 h 30 (iguais aos BroMinutesTests do iOS) */
class BroMinutesTest {
    private val t0 = Instant.ofEpochSecond(1_800_000_000)
    private val clock = RuleClock(ZoneId.of("America/Sao_Paulo"), t0)
    private var n = 0
    private fun rec(from: Long, minutes: Int, kind: ActivityKind = ActivityKind.MUSCULACAO) =
        ActivityRecord("a${n++}", kind, t0.plusSeconds(from * 60), minutes, 5)

    @Test fun overlapCountsOnlyTheFreePart() {
        val a = rec(0, 60); val b = rec(30, 60)
        val s = SnapshotRules.snapshot(listOf(a, b), clock)
        assertEquals(Game.xp(ActivityKind.MUSCULACAO, 30, 5), s.xpByActivity[b.id])
    }

    @Test fun sameTimeTwiceGivesNothing() {
        val s = SnapshotRules.snapshot(listOf(rec(0, 60), rec(0, 60)), clock)
        assertEquals(Game.xp(ActivityKind.MUSCULACAO, 60, 5), s.totalXP)
    }

    @Test fun longWorkoutCountsTwoAndAHalfHours() {
        val s = SnapshotRules.snapshot(listOf(rec(0, 240, ActivityKind.CAMINHADA)), clock)
        assertEquals(Game.xp(ActivityKind.CAMINHADA, 150, 5), s.totalXP)
    }

    @Test fun backToBackIsFine() {
        val b = rec(60, 60)
        val s = SnapshotRules.snapshot(listOf(rec(0, 60), b), clock)
        assertEquals(Game.xp(ActivityKind.MUSCULACAO, 60, 5), s.xpByActivity[b.id])
    }
}
