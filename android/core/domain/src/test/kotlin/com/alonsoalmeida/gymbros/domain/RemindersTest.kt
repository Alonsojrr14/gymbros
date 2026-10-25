package com.alonsoalmeida.gymbros.domain

import com.alonsoalmeida.gymbros.domain.reminders.ReminderSettings
import com.alonsoalmeida.gymbros.domain.reminders.Reminders
import com.alonsoalmeida.gymbros.domain.reminders.WeeklySummary
import com.alonsoalmeida.gymbros.domain.train.SessionLog
import com.alonsoalmeida.gymbros.domain.train.SetLog
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime

/** Lembrete diário e resumo da semana (Companion.swift `Reminders` e `WeeklySummary`) */
class RemindersTest {
    private val zone = ZoneId.of("America/Sao_Paulo")
    // Sábado, 24/10/2026, 12h em São Paulo
    private val now = ZonedDateTime.of(2026, 10, 24, 12, 0, 0, 0, zone).toInstant()

    private fun plan(enabled: Boolean = true, minute: Int = 18 * 60, routineOnly: Boolean = false, routines: Map<Int, String> = emptyMap(),
                     streak: Int = 0, trainedToday: Boolean = false, isEgg: Boolean = false, at: Instant = now) =
        Reminders.plan(enabled, minute, routineOnly, routines, "Brutus", streak, trainedToday, isEgg, at, zone)

    @Test
    fun settingsDefaultsAndKeysMatchTheIPhone() {
        val d = ReminderSettings.of(emptyMap())
        assertFalse(d.remindersOn)
        assertEquals(18 * 60, d.reminderMinute)
        assertFalse(d.routineOnly)
        assertTrue(d.weeklySummary)
        assertFalse(d.paused)
        val s = ReminderSettings.of(mapOf("remindersOn" to true, "reminderMinute" to 7 * 60 + 30, "reminderRoutineOnly" to true,
                                          "weeklySummary" to false, "notify.paused" to true))
        assertTrue(s.remindersOn)
        assertEquals(450, s.reminderMinute)
        assertTrue(s.routineOnly)
        assertFalse(s.summaryActive)
        // Pausar silencia tudo
        assertFalse(s.remindersActive)
        assertEquals("07:30", ReminderSettings.timeText(450))
        assertEquals("18:00", ReminderSettings.timeText(ReminderSettings.DEFAULT_MINUTE))
    }

    @Test
    fun offPlansNothing() = assertTrue(plan(enabled = false).isEmpty())

    @Test
    fun sevenDaysFromTodayAtTheChosenTime() {
        val p = plan()
        assertEquals(7, p.size)
        assertEquals((0 until 7).map { "reminder-$it" }, p.map { it.id })
        assertEquals(ZonedDateTime.of(2026, 10, 24, 18, 0, 0, 0, zone).toInstant(), p.first().at)
        assertEquals(ZonedDateTime.of(2026, 10, 30, 18, 0, 0, 0, zone).toInstant(), p.last().at)
        assertEquals("Brutus está te chamando", p.first().title)
        assertEquals("Que tal um treino hoje? Qualquer atividade conta.", p.first().body)
    }

    @Test
    fun todayIsSkippedWhenTrainedOrAlreadyPast() {
        assertEquals("reminder-1", plan(trainedToday = true).first().id)
        val late = ZonedDateTime.of(2026, 10, 24, 18, 0, 0, 0, zone).toInstant()
        val p = plan(at = late)
        assertEquals(6, p.size)
        assertEquals("reminder-1", p.first().id)
    }

    @Test
    fun streakOnlyTodayAndRoutineWins() {
        val p = plan(streak = 1, routines = mapOf(2 to "Peito"))
        assertEquals("Não deixa a sequência de 1 dia acabar 🔥", p[0].body)
        // Domingo (offset 1) sem rotina: a sequência só aparece hoje
        assertEquals("Que tal um treino hoje? Qualquer atividade conta.", p[1].body)
        // Segunda = 2 no calendário do iOS
        assertEquals("Hoje é dia de Peito. Bora?", p[2].body)
        assertEquals("Não deixa a sequência de 5 dias acabar 🔥", plan(streak = 5)[0].body)
        assertEquals("Seu ovo está esfriando 🥚", plan(isEgg = true)[0].title)
    }

    @Test
    fun onlyRoutineDays() {
        val p = plan(routineOnly = true, routines = mapOf(2 to "Peito", 7 to "Perna"))
        // Sábado (hoje, 7) e segunda (2)
        assertEquals(listOf("reminder-0", "reminder-2"), p.map { it.id })
        assertEquals("Hoje é dia de Perna. Bora?", p[0].body)
        assertTrue(plan(routineOnly = true).isEmpty())
    }

    @Test
    fun routinesByWeekdayFirstInOrderWins() {
        val m = Reminders.routinesByWeekday(listOf("A" to "2,4", "B" to "4, 6", "C" to ""))
        assertEquals(mapOf(2 to "A", 4 to "A", 6 to "B"), m)
        assertEquals(1, Reminders.weekday(LocalDate.of(2026, 10, 25)))
        assertEquals(7, Reminders.weekday(LocalDate.of(2026, 10, 24)))
    }

    @Test
    fun stillDueAtFireTime() {
        val on = ReminderSettings(remindersOn = true)
        assertTrue(Reminders.stillDue(on, trainedToday = false))
        assertFalse(Reminders.stillDue(on, trainedToday = true))
        assertFalse(Reminders.stillDue(on.copy(paused = true), trainedToday = false))
        assertFalse(Reminders.stillDue(ReminderSettings(), trainedToday = false))
    }

    @Test
    fun summaryFiresNextSundayAt19() {
        assertEquals(ZonedDateTime.of(2026, 10, 25, 19, 0, 0, 0, zone), WeeklySummary.fireAt(now, zone))
        val sunday = ZonedDateTime.of(2026, 10, 25, 18, 59, 0, 0, zone).toInstant()
        assertEquals(ZonedDateTime.of(2026, 10, 25, 19, 0, 0, 0, zone), WeeklySummary.fireAt(sunday, zone))
        val after = ZonedDateTime.of(2026, 10, 25, 19, 0, 2, 0, zone).toInstant()
        assertEquals(ZonedDateTime.of(2026, 11, 1, 19, 0, 0, 0, zone), WeeklySummary.fireAt(after, zone))
        assertEquals(ZonedDateTime.of(2026, 10, 19, 0, 0, 0, 0, zone).toInstant(), WeeklySummary.weekStart(WeeklySummary.fireAt(now, zone)))
    }

    @Test
    fun summaryBody() {
        val fire = WeeklySummary.fireAt(now, zone)
        val old = ZonedDateTime.of(2026, 10, 18, 10, 0, 0, 0, zone).toInstant()
        val mon = ZonedDateTime.of(2026, 10, 19, 7, 0, 0, 0, zone).toInstant()
        assertEquals("Nenhum treino nesta semana. Segunda é um ótimo dia para voltar 💪", WeeklySummary.body(listOf(old to 60), 0, emptyList(), fire))
        assertEquals("1 treino · 45 min", WeeklySummary.body(listOf(old to 60, mon to 45), 0, emptyList(), fire))
        assertEquals("2 treinos · 1 h 30 min · 1 PR 🏆", WeeklySummary.body(listOf(mon to 45, now to 45), 1, emptyList(), fire))
        assertEquals("1 treino · 2 h · 3 PRs 🏆", WeeklySummary.body(listOf(mon to 120), 3, emptyList(), fire))

        val leagues = listOf(
            WeeklySummary.LeagueLine("🔥", "Firma", 2, 8, ZonedDateTime.of(2026, 10, 31, 23, 0, 0, 0, zone).toInstant()),
            WeeklySummary.LeagueLine("🏆", "Amigos", 1, 3, ZonedDateTime.of(2026, 10, 25, 23, 59, 0, 0, zone).toInstant()),
            WeeklySummary.LeagueLine("💪", "Terceira", 1, 1, null),
        )
        assertEquals("1 treino · 45 min\n🔥 2º de 8 na Firma · faltam 7 dias\n🏆 1º de 3 na Amigos · último dia!",
                     WeeklySummary.body(listOf(mon to 45), 0, leagues, fire))
        assertEquals("1 treino · 45 min\n💪 1º de 1 na Terceira", WeeklySummary.body(listOf(mon to 45), 0, leagues.drop(2), fire))

        val p = WeeklySummary.plan(true, emptyList(), 0, emptyList(), fire)!!
        assertEquals("weekly-summary", p.id)
        assertEquals("Sua semana no GymBros", p.title)
        assertEquals(fire.toInstant(), p.at)
        assertNull(WeeklySummary.plan(false, emptyList(), 0, emptyList(), fire))
    }

    @Test
    fun weeklyPrsCountSessionsOfTheWeekAndManualOnes() {
        val ws = ZonedDateTime.of(2026, 10, 19, 0, 0, 0, 0, zone).toInstant()
        fun s(day: Int, kg: Double) = SessionLog(ZonedDateTime.of(2026, 10, day, 8, 0, 0, 0, zone).toInstant(),
                                                 listOf(SetLog("supino", kg, 8, 8, true)))
        val sessions = listOf(s(12, 60.0), s(20, 70.0), s(22, 65.0))
        assertEquals(1, WeeklySummary.prs(sessions, emptyList(), ws))
        assertEquals(2, WeeklySummary.prs(sessions, listOf(ws.minusSeconds(60), ws.plusSeconds(60)), ws))
    }
}
