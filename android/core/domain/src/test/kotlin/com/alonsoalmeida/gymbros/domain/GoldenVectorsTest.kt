package com.alonsoalmeida.gymbros.domain

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/** Paridade provada pelos vetores gerados no iPhone (GymBrosTests/Fixtures/gymbros-golden-*.json) */
class GoldenVectorsTest {
    private fun load(group: String): JsonObject {
        val text = javaClass.getResource("/gymbros-golden-$group.json")!!.readText()
        return Json.parseToJsonElement(text).jsonObject
    }

    private fun bits(s: String): Double = Double.fromBits(s.toULong().toLong())
    private fun Any.s(key: String) = (this as JsonObject)[key]!!.jsonPrimitive.content
    private fun Any.i(key: String) = (this as JsonObject)[key]!!.jsonPrimitive.int

    @Test
    fun groupA() {
        val a = load("A")
        val xp = a["xp"]!!.jsonArray
        for (c in xp) assertEquals(c.i("xp"), Game.xp(ActivityKind.of(c.s("kind")), c.i("minutes"), c.i("effort")), c.toString())
        for (c in a["random"]!!.jsonArray) {
            val r = SeededRandom(c.s("seed"))
            for (n in c.jsonObject["next"]!!.jsonArray) assertEquals(n.jsonPrimitive.content.toULong(), r.next().toRawBits().toULong(), c.s("seed"))
        }
        for (c in a["pair"]!!.jsonArray) {
            val o = c.jsonObject
            val met = o["met"]!!.jsonObject.mapValues { (_, v) -> v.jsonObject.mapValues { it.value.jsonPrimitive.int } }
            val byes = o["byes"]!!.jsonObject.mapValues { it.value.jsonPrimitive.int }
            val out = Swiss.pair(o["ranked"]!!.jsonArray.map { it.jsonPrimitive.content }, met, byes)
            assertEquals(o["pairs"]!!.jsonArray.map { p -> p.jsonArray.let { it[0].jsonPrimitive.content to it[1].jsonPrimitive.content } }, out.pairs, o.toString())
            assertEquals(o["bye"].let { if (it == null || it is JsonNull) null else it.jsonPrimitive.content }, out.bye, o.toString())
        }
        for (c in a["photo"]!!.jsonArray) {
            val o = c.jsonObject
            val rule = PhotoRule.entries.first { it.raw == o.s("rule") }
            assertEquals(o.i("out"), rule.apply(o.i("score"), o["hasPhoto"]!!.jsonPrimitive.content.toBoolean()))
        }
    }

    @Test
    fun groupBSnapshot() {
        val b = load("B")
        val zone = ZoneId.of(b.s("timeZone"))
        for (c in b["snapshot"]!!.jsonArray) {
            val o = c.jsonObject
            val records = o["records"]!!.jsonArray.map { r ->
                val ro = r.jsonObject
                ActivityRecord(
                    id = ro.s("id"), kind = ActivityKind.of(ro.s("kind")), date = Instant.parse(ro.s("date")),
                    minutes = ro.i("minutes"), effort = ro.i("effort"), share = bits(ro.s("share")),
                    weights = (ro["weights"] as? JsonObject)?.entries?.associate { Attribute.of(it.key)!! to bits(it.value.jsonPrimitive.content) },
                )
            }
            val s = SnapshotRules.snapshot(records, RuleClock(zone, Instant.parse(o.s("now"))))
            assertEquals(o.i("totalXP"), s.totalXP)
            assertEquals(o.i("todayXP"), s.todayXP)
            assertEquals(o.i("streak"), s.streak)
            assertEquals(o.i("bestStreak"), s.bestStreak)
            assertEquals(o.s("form"), s.form.key)
            assertEquals(o["evolutions"]!!.jsonArray.map { it.jsonPrimitive.content }, s.evolutions.map { it.form.key })
            assertEquals(o["xpByActivity"]!!.jsonArray.map { it.jsonPrimitive.int }, records.map { s.xpByActivity[it.id] ?: 0 })
            val lifetime = o["lifetimeAttributes"]!!.jsonObject.mapValues { it.value.jsonPrimitive.content.toULong() }
            assertEquals(lifetime, s.lifetimeAttributes.entries.associate { it.key.raw to it.value.toRawBits().toULong() })
        }
    }

    @Test
    fun groupBSwissTable() {
        val b = load("B")
        val zone = ZoneId.of(b.s("timeZone"))
        for (c in b["swissTable"]!!.jsonArray) {
            val o = c.jsonObject
            val tallies = o["tallies"]!!.jsonObject.entries.associate { (stamp, v) ->
                val (y, m, d) = stamp.split("-").map { it.toInt() }
                LocalDate.of(y, m, d) to v.jsonObject.mapValues { val t = it.value.jsonArray; SwissTally(t[0].jsonPrimitive.int, t[1].jsonPrimitive.int) }
            }
            val rounds = SwissTable.table(
                members = o["members"]!!.jsonArray.map { it.jsonPrimitive.content }, tallies = tallies,
                start = Instant.parse(o.s("start")), end = null, clock = RuleClock(zone, Instant.parse(o.s("now"))),
                seed = o.s("seed"), criterion = SwissCriterion.entries.first { it.raw == o.s("criterion") },
                joined = o["joined"]!!.jsonObject.mapValues { Instant.parse(it.value.jsonPrimitive.content) },
            )
            val expected = o["rounds"]!!.jsonArray
            assertEquals(expected.size, rounds.size, o.s("seed"))
            for ((r, e) in rounds.zip(expected)) {
                val eo = e.jsonObject
                assertEquals(eo.s("day"), Swiss.dayStamp(r.day.year, r.day.monthValue, r.day.dayOfMonth))
                assertEquals(eo["finished"]!!.jsonPrimitive.content.toBoolean(), r.finished)
                val em = eo["matches"]!!.jsonArray.map { m -> m.jsonArray.let { listOf(it[0].jsonPrimitive.content, (it[1] as? JsonNull)?.let { "-" } ?: it[1].jsonPrimitive.content, it[2].jsonPrimitive.content, it[3].jsonPrimitive.content) } }
                assertEquals(em, r.matches.map { listOf(it.a, it.b ?: "-", it.pointsA.toRawBits().toULong().toString(), it.pointsB.toRawBits().toULong().toString()) }, o.s("seed"))
            }
            val points = o["points"]!!.jsonObject.mapValues { it.value.jsonPrimitive.content.toULong() }
            assertEquals(points, SwissTable.points(rounds).mapValues { it.value.toRawBits().toULong() })
        }
    }
}
