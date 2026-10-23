package com.alonsoalmeida.gymbros.domain

import com.alonsoalmeida.gymbros.domain.backup.ActivityDto
import com.alonsoalmeida.gymbros.domain.duel.DuelActivity
import com.alonsoalmeida.gymbros.domain.duel.DuelAnswer
import com.alonsoalmeida.gymbros.domain.duel.DuelMetric
import com.alonsoalmeida.gymbros.domain.duel.DuelPerson
import com.alonsoalmeida.gymbros.domain.duel.DuelPhase
import com.alonsoalmeida.gymbros.domain.duel.DuelRefusal
import com.alonsoalmeida.gymbros.domain.duel.DuelResult
import com.alonsoalmeida.gymbros.domain.duel.DuelScore
import com.alonsoalmeida.gymbros.domain.duel.Duels
import com.alonsoalmeida.gymbros.domain.duel.RemoteDuel
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.time.Instant

/** Porte de ios/GymBrosTests/DuelTests.swift (parte das regras; o servidor simulado não existe no Android) */
class DuelTest {
    private val t0 = Instant.ofEpochSecond(1_800_000_000)
    private val hour = 3600L
    private fun at(seconds: Long) = t0.plusSeconds(seconds)

    private fun person(id: String) = DuelPerson(id, id.replaceFirstChar { it.uppercase() }, MonsterForm.EGG.id)
    private fun act(date: Instant, minutes: Int = 30, meters: Double? = null) = DuelActivity(date, ActivityKind.CORRIDA, minutes, 5, meters)

    private fun duel(id: String = "d1", from: String = "me", to: String = "bruno", metric: DuelMetric = DuelMetric.TREINOS,
                     created: Instant = t0, answer: DuelAnswer? = null, answered: Instant? = null, theirs: Int? = null): RemoteDuel {
        val d = RemoteDuel(id, person(from), person(to), metric, created, answer, answered)
        return if (theirs != null) d.copy(reported = mapOf((if (from == "me") to else from) to theirs)) else d
    }

    private fun refusal(opponent: String = "bruno", duels: List<RemoteDuel> = emptyList(), blocked: Set<String> = emptySet(),
                        blockedBy: Set<String> = emptySet(), now: Instant = t0) =
        Duels.refusal("me", opponent, duels, blocked, blockedBy, now)

    @Test fun acceptedDuelLasts24HoursFromAcceptance() {
        val d = duel(answer = DuelAnswer.ACCEPTED, answered = at(2 * hour))
        assertEquals(DuelPhase.Active(at(26 * hour)), d.phase(at(3 * hour)))
        assertEquals(DuelPhase.Active(at(26 * hour)), d.phase(at(26 * hour - 1)))
        assertEquals(DuelPhase.Finished(at(26 * hour)), d.phase(at(26 * hour)))
    }

    @Test fun myValueCountsAnyActivityOnlyInTheWindow() {
        val d = duel(answer = DuelAnswer.ACCEPTED, answered = at(hour), theirs = 1)
        val acts = listOf(act(t0), act(at(2 * hour)), act(at(10 * hour)), act(at(24 * hour)), act(at(25 * hour)))
        assertEquals(DuelScore(3, 1), Duels.score(d, activities = acts, now = at(30 * hour)))
        assertEquals(1, Duels.score(d, activities = acts, now = at(3 * hour)).mine, "ao vivo só até agora")
        assertEquals(0, Duels.myValue(duel(), acts, at(30 * hour)), "sem aceite não há placar")
    }

    @Test fun metricsMeasureDifferentThings() {
        val a = act(at(2 * hour), minutes = 45, meters = 7_500.0)
        fun value(m: DuelMetric) = Duels.myValue(duel(metric = m, answer = DuelAnswer.ACCEPTED, answered = t0), listOf(a), at(30 * hour))
        assertEquals(1, value(DuelMetric.TREINOS))
        assertEquals(45, value(DuelMetric.MINUTOS))
        assertEquals(7_500, value(DuelMetric.DISTANCIA))
        assertEquals(Game.xp(ActivityKind.CORRIDA, 45, 5), value(DuelMetric.XP))
        // Sem kcal do Saúde, estimada: Int(45 × 9,5 × 1,2) = Int(513,0)
        assertEquals(513, value(DuelMetric.CALORIAS))
    }

    @Test fun caloriesAndDistanceTruncateLikeSwiftInt() {
        assertEquals(36, DuelMetric.CALORIAS.value(ActivityKind.YOGA, 10, 5, null, null)) // 10 × 3 × 1,2 = 36,0
        assertEquals(399, DuelMetric.CALORIAS.value(ActivityKind.CORRIDA, 30, 5, null, 399.99))
        assertEquals(1234, DuelMetric.DISTANCIA.value(ActivityKind.BIKE, 30, 5, 1234.9, null))
    }

    @Test fun winnerDrawAndLoss() {
        assertEquals(DuelResult.VITORIA, DuelScore(3, 1).result)
        assertEquals(DuelResult.DERROTA, DuelScore(1, 3).result)
        assertEquals(DuelResult.EMPATE, DuelScore(2, 2).result)
        assertEquals("Você venceu Bruno no X1 · 3 a 1 treinos", Duels.summary(DuelScore(3, 1), "Bruno", DuelMetric.TREINOS))
        assertEquals("Você empatou com Ana no X1 · 1 a 1 treino", Duels.summary(DuelScore(1, 1), "Ana", DuelMetric.TREINOS))
        assertEquals("Você perdeu para Ana no X1 · 30 min a 1 h 30 min", Duels.summary(DuelScore(30, 90), "Ana", DuelMetric.MINUTOS))
    }

    @Test fun kilometersFormatLikeCPrintf() {
        assertEquals("7,5 km", DuelMetric.DISTANCIA.short(7_500))
        assertEquals("0,2 km", DuelMetric.DISTANCIA.short(250)) // empate exato: para o par, como o printf
        assertEquals("0,8 km", DuelMetric.DISTANCIA.short(750))
        assertEquals("0,1 km", DuelMetric.DISTANCIA.short(150)) // 0,15 em binário é 0,1499…
        assertEquals("12 km", DuelMetric.DISTANCIA.short(12_400))
        assertEquals("12 km", DuelMetric.DISTANCIA.short(12_500))
        assertEquals("14 km", DuelMetric.DISTANCIA.short(13_500))
    }

    @Test fun recordsAndTally() {
        val won = duel("a", answer = DuelAnswer.ACCEPTED, answered = t0, theirs = 0)
        val lost = duel("b", to = "ana", answer = DuelAnswer.ACCEPTED, answered = t0, theirs = 5)
        val active = duel("c", to = "carla", answer = DuelAnswer.ACCEPTED, answered = at(20 * hour))
        val declined = duel("d", to = "diego", answer = DuelAnswer.DECLINED, answered = t0)
        val records = Duels.records(listOf(won, lost, active, declined), activities = listOf(act(at(hour))), now = at(25 * hour))
        assertEquals(setOf("a", "b"), records.map { it.id }.toSet())
        val t = Duels.tally(records)
        assertEquals(listOf(1, 0, 1), listOf(t.v, t.e, t.d))
    }

    @Test fun fastRefreshOnlyRightAfterYouChallenge() {
        assertEquals(3, Duels.refreshInterval(listOf(duel()), now = at(10)))
        assertEquals(30, Duels.refreshInterval(listOf(duel()), now = at(Duels.FAST_WINDOW.seconds + 1)))
        assertEquals(30, Duels.refreshInterval(listOf(duel(from = "bruno", to = "me")), now = at(10)))
        assertEquals(30, Duels.refreshInterval(emptyList(), now = t0))
    }

    @Test fun pendingChallengeExpiresAfter24Hours() {
        val d = duel()
        assertEquals(DuelPhase.Pending(at(24 * hour)), d.phase(at(23 * hour)))
        assertEquals(DuelPhase.Expired, d.phase(at(24 * hour)))
        assertEquals(DuelRefusal.NOT_PENDING, Duels.acceptRefusal(duel(from = "bruno", to = "me"), "me", emptyList(), emptySet(), at(25 * hour)))
        assertNull(Duels.acceptRefusal(duel(from = "bruno", to = "me"), "me", emptyList(), emptySet(), at(hour)))
    }

    @Test fun onlyOneOpenDuelPerPair() {
        assertNull(refusal())
        assertEquals(DuelRefusal.ALREADY_OPEN, refusal(duels = listOf(duel())))
        assertEquals(DuelRefusal.ALREADY_OPEN, refusal(duels = listOf(duel(from = "bruno", to = "me"))), "vale nos dois sentidos")
        assertNull(refusal("ana", duels = listOf(duel())))
        assertNull(refusal(duels = listOf(duel(answer = DuelAnswer.ACCEPTED, answered = t0)), now = at(25 * hour)), "encerrado libera")
        assertNull(refusal(duels = listOf(duel()), now = at(24 * hour)), "expirado libera")
        val active = duel("a", answer = DuelAnswer.ACCEPTED, answered = t0)
        val incoming = duel("b", from = "bruno", to = "me", created = at(hour))
        assertEquals(DuelRefusal.ALREADY_OPEN, Duels.acceptRefusal(incoming, "me", listOf(active, incoming), emptySet(), at(2 * hour)))
        // Desafios cruzados quase juntos: só o mais antigo pode ser aceito
        val mine = duel("c", created = t0)
        val theirs = duel("d", from = "bruno", to = "me", created = at(60))
        assertEquals(DuelRefusal.ALREADY_OPEN, Duels.acceptRefusal(theirs, "me", listOf(mine, theirs), emptySet(), at(hour)))
        val older = duel("e", from = "bruno", to = "me", created = t0)
        val newer = duel("f", created = at(60))
        assertNull(Duels.acceptRefusal(older, "me", listOf(older, newer), emptySet(), at(hour)))
    }

    @Test fun healthActivityCountsWithoutHealthData() {
        val a = ActivityDto("A", "corrida", t0, 30, 9, healthUUID = "hk-1", meters = 5_000.0, kcal = 400.0)
        val d = DuelActivity.of(a)
        assertEquals(5, d.effort)
        assertNull(d.meters)
        assertNull(d.kcal)
        val watch = DuelActivity.of(ActivityDto("B", "corrida", t0, 30, 9, source = "Apple Watch", meters = 5_000.0, kcal = 400.0))
        assertEquals(9, watch.effort)
        assertNull(watch.meters)
        assertNull(watch.kcal)
        val written = DuelActivity.of(ActivityDto("C", "corrida", t0, 30, 9, healthWritten = "hw", meters = 5_000.0, kcal = 400.0))
        assertEquals(5_000.0, written.meters)
        assertNull(written.kcal)
        val app = DuelActivity.of(ActivityDto("D", "corrida", t0, 30, 9, meters = 5_000.0))
        assertEquals(5_000.0, app.meters)
    }

    @Test fun anyoneCanBeChallengedButYourselfAndBlocked() {
        assertNull(refusal("alguem-de-fora-das-ligas"), "não precisa estar numa liga")
        assertEquals(DuelRefusal.YOURSELF, refusal("me"))
        assertEquals(DuelRefusal.BLOCKED, refusal(blocked = setOf("bruno")))
        assertEquals(DuelRefusal.BLOCKED, refusal(blockedBy = setOf("bruno")))
        assertEquals(DuelRefusal.BLOCKED, Duels.acceptRefusal(duel(from = "bruno", to = "me"), "me", emptyList(), setOf("bruno"), t0))
    }

    @Test fun eachBroFightsOneDuelAtATime() {
        var sent = duel("a", from = "me", to = "bruno", created = t0)
        val active = duel("b", from = "carla", to = "me", created = t0, answer = DuelAnswer.ACCEPTED, answered = at(60))
        val waiting = duel("c", from = "diego", to = "me", created = t0)
        val reps = mapOf("a" to "bro-1", "b" to "bro-2")
        assertEquals(setOf("bro-1", "bro-2"), Duels.busyFighters(listOf(sent, active, waiting), reps, now = at(3600)))
        // Acabou ou foi recusado: o bro fica livre de novo
        sent = sent.copy(answer = DuelAnswer.DECLINED, answeredAt = at(60))
        assertEquals(emptySet<String>(), Duels.busyFighters(listOf(sent, active), reps, now = at(Duels.WINDOW.seconds + 3600)))
    }

    @Test fun serverIdBecomesMeAndStrangersChallengesAreHidden() {
        val raw = RemoteDuel("x", DuelPerson("uid-1", "Eu", "f"), DuelPerson("bruno", "Bruno", "g"), DuelMetric.XP, t0,
                             reported = mapOf("uid-1" to 10, "bruno" to 4))
        val local = Duels.local(raw, "uid-1")
        assertEquals("me", local.challenger.id)
        assertEquals(mapOf("me" to 10, "bruno" to 4), local.reported)
        val fromStranger = duel("s", from = "zeca", to = "me")
        val mineToStranger = duel("t", from = "me", to = "zeca")
        val fromBlocked = duel("u", from = "bruno", to = "me")
        val shown = Duels.visible(listOf(fromStranger, mineToStranger, fromBlocked), blocked = setOf("bruno"), friends = setOf("ana"))
        assertEquals(listOf("t"), shown.map { it.id })
    }

    @Test fun remainingRoundsMinutesUp() {
        assertEquals("1 min", Duels.remaining(at(10), t0))
        assertEquals("1 min", Duels.remaining(t0.minusSeconds(5), t0))
        assertEquals("2 min", Duels.remaining(at(61), t0))
        assertEquals("5 h 20 min", Duels.remaining(at(5 * hour + 20 * 60), t0))
        assertTrue(Duels.nextFighterFree(emptyList(), emptyMap(), t0) == null)
    }
}
