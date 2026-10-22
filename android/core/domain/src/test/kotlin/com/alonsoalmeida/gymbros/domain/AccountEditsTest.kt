package com.alonsoalmeida.gymbros.domain

import com.alonsoalmeida.gymbros.domain.backup.AccountCopy
import com.alonsoalmeida.gymbros.domain.backup.AccountEdits
import com.alonsoalmeida.gymbros.domain.backup.BackupMerge
import com.alonsoalmeida.gymbros.domain.home.HomeBuilder
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.time.Instant
import java.time.ZoneId

class AccountEditsTest {
    private val c = Json.parseToJsonElement(javaClass.getResource("/gymbros-golden-C.json")!!.readText()).jsonObject
    private val iphone = Json.parseToJsonElement(c["backupJSON"]!!.jsonPrimitive.content) as JsonObject
    private val clock = RuleClock(ZoneId.of("America/Sao_Paulo"), Instant.parse("2027-01-16T12:00:00Z"))

    private fun run(id: String) = AccountEdits.NewActivity("corrida", Instant.parse("2027-01-16T10:00:00Z"), 30, 5, "", 37,
        AttributeSplit.encode(AttributeSplit.split(ActivityKind.CORRIDA, 30, 5, healthType = 37)), id = id)

    @Test
    fun newActivityKeepsEverythingElseAndCountsForTheBro() {
        val out = AccountEdits.addActivity(iphone, run("A1"))
        // Nada do que o iPhone gravou se perde
        for ((k, v) in iphone) if (k != "activities") assertEquals(v, out[k], k)
        assertEquals((iphone["activities"] as JsonArray).size + 1, (out["activities"] as JsonArray).size)
        val before = HomeBuilder.build(AccountCopy.decode(iphone), clock)
        val after = HomeBuilder.build(AccountCopy.decode(out), clock)
        assertTrue(after.snapshot.totalXP > before.snapshot.totalXP)
        assertEquals("Corrida", after.recent.first().typeName)
    }

    @Test
    fun activityFromEachDeviceSurvivesTheMerge() {
        val base = iphone
        val android = AccountEdits.addActivity(base, run("A1"))
        val other = AccountEdits.addActivity(base, run("B1"))
        val merged = BackupMerge.merge(android, other, base)
        val ids = (merged.backup["activities"] as JsonArray).map { it.jsonObject["uuid"]!!.jsonPrimitive.content }
        assertTrue("A1" in ids && "B1" in ids)
        assertTrue(merged.conflicts.isEmpty())
    }

    @Test
    fun brandNewAccountGetsAStarterEgg() {
        val out = AccountEdits.addActivity(AccountEdits.empty("Ana", clock.now), run("A1"))
        val home = HomeBuilder.build(AccountCopy.decode(out), clock)
        assertEquals("Ana", home.trainerName)
        assertTrue(home.snapshot.totalXP > 0)
    }
}
