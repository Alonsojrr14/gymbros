package com.alonsoalmeida.gymbros.domain

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/**
 * Relógio das regras: nenhuma regra lê o fuso do aparelho sozinha (ADR-006). O fuso das ligas é o de Brasília,
 * igual ao `League.rulesCalendar` do iOS; o XP do próprio bro usa o fuso do aparelho, como no iOS.
 * Calendário gregoriano (o `LocalDate` do java.time).
 */
data class RuleClock(val zone: ZoneId, val now: Instant) {
    fun day(instant: Instant): LocalDate = instant.atZone(zone).toLocalDate()
    val today: LocalDate get() = day(now)

    companion object {
        val LEAGUE_ZONE: ZoneId = ZoneId.of("America/Sao_Paulo")
    }
}
