package com.alonsoalmeida.gymbros.domain

import com.alonsoalmeida.gymbros.domain.backup.AccountCopy
import com.alonsoalmeida.gymbros.domain.backup.AppleReferenceDate
import com.alonsoalmeida.gymbros.domain.backup.ChunkCodec
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.time.Instant
import java.util.Base64

/** Grupo C: a cópia da conta que o iPhone gravou (vetor gerado no aparelho) abre igual no Android */
class AccountCopyTest {
    private val c = Json.parseToJsonElement(javaClass.getResource("/gymbros-golden-C.json")!!.readText()).jsonObject
    private fun s(k: String) = c[k]!!.jsonPrimitive.content

    @Test
    fun inflatesTheIPhoneCopy() {
        val packed = Base64.getDecoder().decode(s("backupDeflateBase64"))
        assertTrue(packed[0] != 0x78.toByte(), "DEFLATE cru, sem cabeçalho zlib")
        val raw = ChunkCodec.inflate(packed)
        assertEquals(c["backupBytes"]!!.jsonPrimitive.int, raw.size)
        assertEquals(s("backupJSON"), raw.decodeToString())
    }

    @Test
    fun decodesTheCopy() {
        val b = AccountCopy.decode(s("backupJSON").encodeToByteArray())
        assertEquals(1, b.version)
        // A data com fração (…000.75) foi gravada em segundos
        assertEquals(Instant.ofEpochSecond(1_800_000_000), b.exportedAt)
        val a = b.activities.single()
        assertEquals("corrida", a.kind)
        assertEquals(42, a.minutes)
        assertEquals(7, a.effort)
        assertEquals(8_400.0, a.meters)
        assertEquals(Instant.ofEpochSecond(1_800_000_000), a.date)
        assertEquals("Treino A", b.routines.single().name)
        assertEquals(true, b.monsters!!.single().isStarter)
        assertEquals("pontos", b.leagues!!.single().scoring)
    }

    @Test
    fun chunksRoundTrip() {
        val big = ByteArray(2_100_000) { (it * 31 % 251).toByte() }
        val parts = ChunkCodec.split(big)
        assertEquals(listOf(900_000, 900_000, 300_000), parts.map { it.size })
        assertArrayEquals(big, ChunkCodec.join(parts))
        val raw = s("backupJSON").encodeToByteArray()
        assertArrayEquals(raw, ChunkCodec.inflate(ChunkCodec.deflate(raw)))
        assertEquals(AccountCopy.decode(raw), AccountCopy.fromChunks(ChunkCodec.split(ChunkCodec.deflate(raw))))
    }

    @Test
    fun leagueSettingsDatesCountFrom2001() {
        val settings = Json.parseToJsonElement(s("leagueSettingsRaw")).jsonObject
        val reviewSince = AppleReferenceDate.toInstant(settings["reviewSince"]!!.jsonPrimitive.double)
        val expected = java.lang.Double.longBitsToDouble(s("reviewSinceUnix").toULong().toLong())
        assertEquals(1_800_000_000L, reviewSince.epochSecond)
        assertEquals(750_000_000, reviewSince.nano)
        assertEquals(expected, AppleReferenceDate.fromInstant(reviewSince) + AppleReferenceDate.OFFSET, 1e-6)
        assertEquals(2, settings["weekStart"]!!.jsonPrimitive.int)
    }

    @Test
    fun readsBinaryPlists() {
        val sample = AccountCopy.settings(Base64.getDecoder().decode(s("plistSampleBase64")))
        assertEquals("olá", sample["texto"])
        assertEquals(42L, sample["inteiro"])
        assertEquals(2.5, sample["real"])
        assertEquals(true, sample["sim"])
        assertEquals(false, sample["nao"])
        assertEquals(Instant.ofEpochSecond(1_800_000_000), sample["data"])
        assertArrayEquals(byteArrayOf(1, 2, 3), sample["bytes"] as ByteArray)
        assertEquals(listOf(1L, "x", 2.5), sample["lista"])
        assertEquals(mapOf("k" to 1L), sample["dicionario"])
        val account = AccountCopy.settings(Base64.getDecoder().decode(s("accountSettingsBase64")))
        assertEquals("ABC234", account["friendCode"])
        assertEquals("Treinadora", account["trainerName"])
    }
}
