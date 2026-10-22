package com.alonsoalmeida.gymbros.domain

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.BeforeAll
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestInstance
import java.io.File
import java.time.Instant
import java.time.ZoneId

/** Grupo R: formas, espécies, humor e o plantel de bros, contra o que o iPhone calculou */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class GroupRTest {
    private val r: JsonObject = Json.parseToJsonElement(javaClass.getResource("/gymbros-golden-R.json")!!.readText()).jsonObject
    private val zone: ZoneId = ZoneId.of(r["timeZone"]!!.jsonPrimitive.content)

    private fun bits(s: String): Double = Double.fromBits(s.toULong().toLong())
    private fun JsonObject.s(key: String) = this[key]!!.jsonPrimitive.content
    private fun JsonObject.os(key: String) = this[key]?.takeIf { it !is JsonNull }?.jsonPrimitive?.content

    @BeforeAll
    fun sprites() {
        // As mesmas artes que o app Android leva (geradas dos imagesets do iOS)
        val dir = File("../../app/src/main/res/drawable-nodpi")
        val names = dir.list()!!.map { it.substringBeforeLast('.') }.toSet()
        SpriteArt.exists = { it in names }
    }

    @Test
    fun forms() {
        val forms = r["forms"]!!.jsonArray.map { it.jsonObject }
        assertEquals(904, forms.size)
        for (f in forms) {
            val form = MonsterForm.byID(f.s("id")) ?: if (f.s("id") == "egg") MonsterForm.EGG else error(f.s("id"))
            assertEquals(f.s("id"), form.id)
            assertEquals(f.s("key"), form.key)
            assertEquals(f.s("name"), form.name, f.s("id"))
            assertEquals(f.s("sprite"), form.sprite)
            assertEquals(f["hasArt"]!!.jsonPrimitive.boolean, form.hasArt, f.s("id"))
            assertEquals(f.s("resolved"), form.resolved.id)
            assertEquals(f.s("spriteWithFallback"), form.spriteWithFallback)
        }
        for (s in r["species"]!!.jsonArray.map { it.jsonObject }) {
            assertEquals(s["isReady"]!!.jsonPrimitive.boolean, Species.byID(s.s("id"))!!.isReady)
        }
    }

    @Test
    fun eraDayAndMood() {
        for (e in r["eraDays"]!!.jsonArray.map { it.jsonObject }) {
            val at = Instant.parse(e.s("date"))
            // Antes de 2002 o fuso histórico do iOS difere do tzdata do Java; a frase só usa datas de agora
            if (at.isBefore(Instant.parse("2010-01-01T00:00:00Z"))) continue
            assertEquals(e["ordinality"]!!.jsonPrimitive.long, Companion.eraDay(RuleClock(zone, at)), e.s("date"))
        }
        for (m in r["moods"]!!.jsonArray.map { it.jsonObject }) {
            val mood = Mood.of(m["isEgg"]!!.jsonPrimitive.boolean, m.os("last")?.let(Instant::parse), m["todayXP"]!!.jsonPrimitive.int,
                               m["streak"]!!.jsonPrimitive.int, RuleClock(zone, Instant.parse(m.s("now"))))
            assertEquals(m.s("mood"), mood.raw, m.toString())
        }
    }

    @Test
    fun rosters() {
        for ((k, c) in r["rosters"]!!.jsonArray.map { it.jsonObject }.withIndex()) {
            val monsters = c["monsters"]!!.jsonArray.map { it.jsonObject }.map {
                Bro(it.s("uuid"), it.s("name"), Instant.parse(it.s("createdAt")), it["isStarter"]!!.jsonPrimitive.boolean, it.os("speciesID"))
            }
            val activities = c["activities"]!!.jsonArray.map { it.jsonObject }.map {
                OwnedActivity(ActivityRecord(it.s("uuid"), ActivityKind.of(it.s("kind")), Instant.parse(it.s("date")), it["minutes"]!!.jsonPrimitive.int,
                                             it["effort"]!!.jsonPrimitive.int, healthType = it.os("healthType")?.toLong()), it.os("monsterUUID"))
            }
            val checkIns = c["checkIns"]!!.jsonArray.map { it.jsonObject }.map { it.s("leagueUUID") to it.s("activityUUID") }
            val leagues = c["leagues"]!!.jsonArray.map { it.jsonObject }.associate { it.s("uuid") to it.os("monsterUUID") }
            val roster = Roster(monsters, activities, checkIns, leagues, c.os("mainMonster"), BroLedger.retired(c.s("retiredActivities")),
                                BroLedger.bases(c.s("tradeBases")), c["tradeGone"]!!.jsonArray.map { it.jsonPrimitive.content }.toSet(),
                                RuleClock(zone, Instant.parse("2026-10-20T15:00:00Z")))
            val tag = "roster-$k"
            assertEquals(c.os("mainID"), roster.mainID, tag)
            assertEquals(c.os("main"), roster.main?.uuid, tag)
            assertEquals(c["xpByActivity"]!!.jsonObject.mapValues { it.value.jsonPrimitive.int }, roster.xpByActivity, tag)
            for (e in c["snapshots"]!!.jsonArray.map { it.jsonObject }) {
                val s = roster.snapshot(e.s("uuid"))
                val t = "$tag ${e.s("uuid")}"
                assertEquals(e.s("form"), s.form.id, t)
                assertEquals(e["totalXP"]!!.jsonPrimitive.int, s.totalXP, t)
                assertEquals(e["level"]!!.jsonPrimitive.int, s.level, t)
                assertEquals(bits(e.s("progress")).toRawBits(), s.progress.toRawBits(), t)
                assertEquals(e.os("xpToNext")?.toInt(), s.xpToNext, t)
                assertEquals(e.os("nextForm"), s.nextForm?.id, t)
                assertEquals(e.s("displayName"), roster.monster(e.s("uuid"))!!.displayName(s.form), t)
                assertEquals(e["evolutions"]!!.jsonArray.map { it.jsonPrimitive.content }, s.evolutions.map { it.form.id }, t)
                assertEquals(e["inheritedXP"]!!.jsonPrimitive.int, s.inheritedXP, t)
                fun attrs(key: String) = e[key]!!.jsonObject.entries.associate { Attribute.of(it.key)!! to bits(it.value.jsonPrimitive.content).toRawBits() }
                assertEquals(attrs("stageAttributes"), s.stageAttributes.mapValues { it.value.toRawBits() }, t)
                assertEquals(attrs("lifetimeAttributes"), s.lifetimeAttributes.mapValues { it.value.toRawBits() }, t)
            }
        }
    }
}
