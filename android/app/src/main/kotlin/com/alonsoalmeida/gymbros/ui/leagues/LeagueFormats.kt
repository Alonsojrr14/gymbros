package com.alonsoalmeida.gymbros.ui.leagues

import androidx.compose.ui.graphics.vector.ImageVector
import com.alonsoalmeida.gymbros.domain.ActivityKind
import com.alonsoalmeida.gymbros.domain.BroCatalog
import com.alonsoalmeida.gymbros.domain.WorkoutType
import com.alonsoalmeida.gymbros.ui.components.Symbols
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** Datas e nomes como o iOS mostra nas ligas (formatos `.dateTime` em pt-BR) */
object LeagueFormats {
    private val pt = Locale.forLanguageTag("pt-BR")
    private val zone get() = ZoneId.systemDefault()

    private fun cap(s: String) = s.replaceFirstChar { it.uppercase() }

    /** "6 de out." (day().month(.abbreviated)) */
    fun dayMonth(i: Instant, z: ZoneId = zone): String = i.atZone(z).format(DateTimeFormatter.ofPattern("d 'de' MMM", pt))

    fun time(i: Instant): String = i.atZone(zone).format(DateTimeFormatter.ofPattern("HH:mm", pt))

    /** "Hoje", "Ontem", "Quarta-feira, 22 de outubro" */
    fun dayTitle(d: LocalDate): String {
        val today = LocalDate.now(zone)
        if (d == today) return "Hoje"
        if (d == today.minusDays(1)) return "Ontem"
        return cap(d.format(DateTimeFormatter.ofPattern("EEEE, d 'de' MMMM", pt)))
    }

    /** "Hoje, 07:42", "Ontem, 07:42", "qua., 22 de out., 07:42" */
    fun whenText(i: Instant): String {
        val d = i.atZone(zone).toLocalDate()
        val today = LocalDate.now(zone)
        val t = time(i)
        if (d == today) return "Hoje, $t"
        if (d == today.minusDays(1)) return "Ontem, $t"
        return "${d.format(DateTimeFormatter.ofPattern("EEE, d 'de' MMM", pt))}, $t"
    }

    /** "qua. 22 07:42" (weekday().day().hour().minute()) */
    fun weekdayDayTime(i: Instant): String = i.atZone(zone).format(DateTimeFormatter.ofPattern("EEE d HH:mm", pt))

    /** "22/10" */
    fun dayNumMonth(d: LocalDate): String = "${d.dayOfMonth}/${d.monthValue}"

    /** "22 de out., 07:42" (day().month(.abbreviated).hour().minute()) */
    fun dayMonthTime(i: Instant): String = "${dayMonth(i)}, ${time(i)}"

    /** "há 5 min", "há 2 h", "há 3 dias" (shortAgo) */
    fun ago(i: Instant): String {
        val s = Duration.between(i, Instant.now()).seconds
        return when {
            s < 60 -> "agora"
            s < 3600 -> "há ${s / 60} min"
            s < 86400 -> "há ${s / 3600} h"
            else -> "há ${s / 86400} dia" + if (s / 86400 == 1L) "" else "s"
        }
    }

    /** "Semana de 6 de out.", "Outubro de 2026", "2026" */
    fun winTitle(p: com.alonsoalmeida.gymbros.domain.leagues.WinPeriod, start: Instant): String {
        val z = com.alonsoalmeida.gymbros.domain.RuleClock.LEAGUE_ZONE
        return when (p) {
            com.alonsoalmeida.gymbros.domain.leagues.WinPeriod.WEEK -> "Semana de ${dayMonth(start, z)}"
            com.alonsoalmeida.gymbros.domain.leagues.WinPeriod.MONTH -> cap(start.atZone(z).format(DateTimeFormatter.ofPattern("MMMM 'de' yyyy", pt)))
            com.alonsoalmeida.gymbros.domain.leagues.WinPeriod.YEAR -> "${start.atZone(z).year}"
        }
    }

    fun kindType(k: ActivityKind): WorkoutType? = WorkoutType.byID(BroCatalog.classicType[k.raw])
    fun kindName(k: ActivityKind): String = kindType(k)?.name ?: k.raw
    fun kindIcon(k: ActivityKind): ImageVector = Symbols.of(BroCatalog.workoutSymbols[BroCatalog.classicType[k.raw]] ?: "")
    fun typeIcon(id: Long?): ImageVector = Symbols.of(id?.let { BroCatalog.workoutSymbols[it] } ?: "")
}
