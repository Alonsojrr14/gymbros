package com.alonsoalmeida.gymbros.domain

import com.alonsoalmeida.gymbros.domain.backup.AccountCopy
import com.alonsoalmeida.gymbros.domain.home.HomeBuilder
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.time.Instant
import java.time.ZoneId

/** Tela inicial montada a partir da cópia da conta que o iPhone exportou (vetor C) */
class HomeBuilderTest {
    private val c = Json.parseToJsonElement(javaClass.getResource("/gymbros-golden-C.json")!!.readText()).jsonObject

    @Test
    fun fromTheIPhoneCopy() {
        val copy = AccountCopy.decode(c["backupJSON"]!!.jsonPrimitive.content.encodeToByteArray())
        val clock = RuleClock(ZoneId.of("America/Sao_Paulo"), Instant.parse("2027-01-16T12:00:00Z"))
        val home = HomeBuilder.build(copy, clock)
        assertEquals("Treinadora", home.trainerName)
        assertEquals(1, home.recent.size)
        val row = home.recent.first()
        assertEquals("Corrida", row.typeName)
        assertEquals("figure.run", row.typeSymbol)
        assertTrue(row.xp > 0)
        assertEquals(row.xp, home.snapshot.totalXP)
        assertEquals(Stage.EGG, home.snapshot.stage)
        assertEquals(Mood.OVO, home.mood)
        assertEquals("Ovo", home.monsterName)
        assertTrue(home.line.isNotEmpty())
    }

    @Test
    fun withoutCopyIsAnEgg() {
        val home = HomeBuilder.build(null, RuleClock(ZoneId.of("UTC"), Instant.EPOCH))
        assertEquals(Stage.EGG, home.snapshot.stage)
        assertEquals("Toc toc… tem alguém aqui dentro.", Companion.candidates(Companion.Context("", Mood.OVO, home.snapshot, false, null, emptyList(), 0))[0])
    }
}
