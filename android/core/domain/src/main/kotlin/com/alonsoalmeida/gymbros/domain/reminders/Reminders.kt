package com.alonsoalmeida.gymbros.domain.reminders

import com.alonsoalmeida.gymbros.domain.duel.durationText
import com.alonsoalmeida.gymbros.domain.profile.ProfileEdits
import com.alonsoalmeida.gymbros.domain.train.Progression
import com.alonsoalmeida.gymbros.domain.train.SessionLog
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.temporal.ChronoUnit

/** Uma notificação local já montada: o texto sai pronto ao agendar, como o `UNNotificationRequest` do iOS */
data class PlannedNotification(val id: String, val at: Instant, val title: String, val body: String)

/**
 * Ajustes das notificações locais, nas mesmas chaves do iPhone (`AccountData.userKeys` → plist `accountSettings`),
 * para valerem nos dois aparelhos. Fonte: SettingsPages.swift `NotificationSettingsPage` e NotificationPrefs.swift.
 */
data class ReminderSettings(
    /** "Pausar todas" (`notify.paused`): silencia lembretes e resumo */
    val paused: Boolean = false,
    val remindersOn: Boolean = false,
    /** Minuto do dia do lembrete (padrão 18:00) */
    val reminderMinute: Int = DEFAULT_MINUTE,
    val routineOnly: Boolean = false,
    val weeklySummary: Boolean = true,
) {
    /** O que o App.swift passa como `enabled` */
    val remindersActive: Boolean get() = remindersOn && !paused
    val summaryActive: Boolean get() = weeklySummary && !paused

    companion object {
        const val PAUSED = "notify.paused"
        const val REMINDERS_ON = "remindersOn"
        const val REMINDER_MINUTE = "reminderMinute"
        const val ROUTINE_ONLY = "reminderRoutineOnly"
        const val WEEKLY_SUMMARY = "weeklySummary"
        const val DEFAULT_MINUTE = 18 * 60

        fun of(settings: Map<String, Any?>) = ReminderSettings(
            paused = ProfileEdits.bool(settings, PAUSED, false),
            remindersOn = ProfileEdits.bool(settings, REMINDERS_ON, false),
            reminderMinute = ProfileEdits.int(settings, REMINDER_MINUTE, DEFAULT_MINUTE).coerceIn(0, 24 * 60 - 1),
            routineOnly = ProfileEdits.bool(settings, ROUTINE_ONLY, false),
            weeklySummary = ProfileEdits.bool(settings, WEEKLY_SUMMARY, true),
        )

        /** "18:00" */
        fun timeText(minute: Int): String = "%02d:%02d".format(minute / 60, minute % 60)
    }
}

/** Lembrete diário para treinar (Companion.swift `Reminders`) */
object Reminders {
    const val PREFIX = "reminder-"

    /** Dia da semana como o `Calendar` do iOS: domingo = 1 … sábado = 7 */
    fun weekday(day: LocalDate): Int = day.dayOfWeek.value % 7 + 1

    /**
     * Nome da rotina de cada dia da semana (App.swift `routinesByWeekday`): rotinas na ordem (`order`), e a primeira que
     * cai no dia fica com ele. `weekdays` é o texto "2,4,6" do Backup.
     */
    fun routinesByWeekday(routines: List<Pair<String, String>>): Map<Int, String> {
        val out = HashMap<Int, String>()
        for ((name, weekdays) in routines) {
            for (d in weekdays.split(",").mapNotNull { it.trim().toIntOrNull() }) out.putIfAbsent(d, name)
        }
        return out
    }

    /**
     * Os próximos 7 dias de lembrete, a partir de hoje. Dias que já passaram do horário ficam de fora; hoje fica de fora
     * se já treinou; com "só em dias de rotina", dias sem rotina também. Reagendado a cada mudança.
     */
    fun plan(enabled: Boolean, minuteOfDay: Int, onlyRoutineDays: Boolean, routines: Map<Int, String>, name: String, streak: Int,
             trainedToday: Boolean, isEgg: Boolean, now: Instant, zone: ZoneId): List<PlannedNotification> {
        if (!enabled) return emptyList()
        val today = now.atZone(zone).toLocalDate()
        val out = mutableListOf<PlannedNotification>()
        for (offset in 0 until 7) {
            val day = today.plusDays(offset.toLong())
            val fire = day.atStartOfDay(zone).plusMinutes(minuteOfDay.toLong()).toInstant()
            if (fire <= now) continue
            if (offset == 0 && trainedToday) continue
            val routine = routines[weekday(day)]
            if (onlyRoutineDays && routine == null) continue
            out += PlannedNotification("$PREFIX$offset", fire, title(isEgg, name), body(routine, offset == 0, streak))
        }
        return out
    }

    fun title(isEgg: Boolean, name: String): String = if (isEgg) "Seu ovo está esfriando 🥚" else "$name está te chamando"

    fun body(routine: String?, today: Boolean, streak: Int): String = when {
        routine != null -> "Hoje é dia de $routine. Bora?"
        today && streak > 0 -> "Não deixa a sequência de $streak dia${if (streak == 1) "" else "s"} acabar 🔥"
        else -> "Que tal um treino hoje? Qualquer atividade conta."
    }

    /** Na hora de tocar: só se ainda vale (o outro aparelho pode ter registrado um treino ou mudado o ajuste) */
    fun stillDue(settings: ReminderSettings, trainedToday: Boolean): Boolean = settings.remindersActive && !trainedToday
}

/** Resumo de domingo à noite (Companion.swift `WeeklySummary`): treinos, tempo, PRs e posição nas ligas */
object WeeklySummary {
    const val ID = "weekly-summary"
    const val TITLE = "Sua semana no GymBros"

    /** Posição numa liga ativa, já calculada pelo placar da liga */
    data class LeagueLine(val emoji: String, val name: String, val position: Int, val count: Int, val end: Instant?)

    /** Próximo domingo às 19h (hoje, se ainda não passou) */
    fun fireAt(now: Instant, zone: ZoneId): ZonedDateTime {
        val local = now.atZone(zone)
        var day = local.toLocalDate()
        while (day.dayOfWeek != DayOfWeek.SUNDAY) day = day.plusDays(1)
        var fire = ZonedDateTime.of(day, LocalTime.of(19, 0), zone)
        // `nextDate(after: now - 1s)`: às 19:00:00 em ponto ainda é hoje
        if (fire.toInstant() < now.minusSeconds(1)) fire = ZonedDateTime.of(day.plusWeeks(1), LocalTime.of(19, 0), zone)
        return fire
    }

    /** Começo da semana do resumo: segunda-feira 0h (6 dias antes do domingo) */
    fun weekStart(fire: ZonedDateTime): Instant = fire.toLocalDate().minusDays(6).atStartOfDay(fire.zone).toInstant()

    /**
     * PRs da semana: recordes batidos em cada treino guiado concluído na semana (contra os anteriores) mais os PRs
     * registrados à mão. `sessions` são os treinos concluídos, do mais antigo ao mais novo.
     */
    fun prs(sessions: List<SessionLog>, manual: List<Instant>, weekStart: Instant): Int {
        var n = 0
        for ((i, s) in sessions.withIndex()) {
            if (s.date >= weekStart) n += Progression.records(s, sessions.subList(0, i)).size
        }
        return n + manual.count { it >= weekStart }
    }

    /** Corpo da notificação; `activities` são (data, minutos) de todas as atividades */
    fun body(activities: List<Pair<Instant, Int>>, prs: Int, leagues: List<LeagueLine>, fire: ZonedDateTime): String {
        val start = weekStart(fire)
        val week = activities.filter { it.first >= start }
        val lines = mutableListOf<String>()
        if (week.isEmpty()) {
            lines += "Nenhum treino nesta semana. Segunda é um ótimo dia para voltar 💪"
        } else {
            val minutes = week.sumOf { it.second }
            lines += "${week.size} treino${if (week.size == 1) "" else "s"} · ${durationText(minutes)}" +
                (if (prs > 0) " · $prs PR${if (prs == 1) "" else "s"} 🏆" else "")
        }
        val fireDay = fire.toLocalDate()
        for (l in leagues.take(2)) {
            val days = l.end?.let { ChronoUnit.DAYS.between(fireDay, it.atZone(fire.zone).toLocalDate()).toInt() }
            lines += "${l.emoji} ${l.position}º de ${l.count} na ${l.name}" +
                (days?.let { if (it > 0) " · faltam ${it + 1} dias" else " · último dia!" } ?: "")
        }
        return lines.joinToString("\n")
    }

    fun plan(enabled: Boolean, activities: List<Pair<Instant, Int>>, prs: Int, leagues: List<LeagueLine>, fire: ZonedDateTime): PlannedNotification? =
        if (!enabled) null else PlannedNotification(ID, fire.toInstant(), TITLE, body(activities, prs, leagues, fire))
}
