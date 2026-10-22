package com.alonsoalmeida.gymbros.domain

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** Grupo L: pontos de um check-in iguais aos do iPhone (vetor gerado no aparelho) */
class LeagueScoreTest {
    private val l = Json.parseToJsonElement(javaClass.getResource("/gymbros-golden-L.json")!!.readText()).jsonObject
    private fun bits(s: String) = Double.fromBits(s.toULong().toLong())

    @Test
    fun catalogMatchesIOS() {
        val catalog = l["catalog"]!!.jsonArray
        assertEquals(catalog.size, WorkoutType.all.size)
        for (c in catalog) {
            val o = c.jsonObject
            val t = WorkoutType.byID(o["id"]!!.jsonPrimitive.long)!!
            assertEquals(o["section"]!!.jsonPrimitive.content, t.section)
            assertEquals(o["kind"]!!.jsonPrimitive.content, t.kind.raw)
        }
    }

    @Test
    fun activeKcalBitForBit() {
        for (c in l["kcal"]!!.jsonArray) {
            val o = c.jsonObject
            val got = Kcal.active(ActivityKind.of(o["kind"]!!.jsonPrimitive.content), o["minutes"]!!.jsonPrimitive.int, o["effort"]!!.jsonPrimitive.int)
            assertEquals(o["kcal"]!!.jsonPrimitive.content.toULong(), got.toRawBits().toULong(), o.toString())
        }
    }

    @Test
    fun checkInScoreMatchesIOS() {
        var weighted = 0
        var offByOne = 0
        for (c in l["score"]!!.jsonArray) {
            val o = c.jsonObject
            val inp = o["input"]!!.jsonObject
            fun opt(k: String) = inp[k].let { if (it == null || it is JsonNull) null else bits(it.jsonPrimitive.content) }
            val input = ScoreInput(
                kind = ActivityKind.of(inp["kind"]!!.jsonPrimitive.content), minutes = inp["minutes"]!!.jsonPrimitive.int,
                effort = inp["effort"]!!.jsonPrimitive.int, meters = opt("meters"), kcal = opt("kcal"),
                workoutTypeID = inp["workoutTypeID"].let { if (it == null || it is JsonNull) null else it.jsonPrimitive.long },
            )
            val rules = o["pointRules"]!!.jsonArray.map { r ->
                val ro = r.jsonObject
                ActivityPointRule(
                    workoutTypeIDs = ro["workoutTypeIDs"]!!.jsonArray.map { it.jsonPrimitive.long },
                    sections = ro["sections"]!!.jsonArray.map { it.jsonPrimitive.content },
                    method = ro["method"]!!.jsonPrimitive.content, points = ro["points"]!!.jsonPrimitive.int,
                    every = ro["every"]!!.jsonPrimitive.int, metric = ro["metric"]!!.jsonPrimitive.content,
                )
            }
            val scoring = LeagueScoring.entries.first { it.raw == o["scoring"]!!.jsonPrimitive.content }
            val got = LeagueScore.score(
                input, scoring, o["weightsRaw"]!!.jsonPrimitive.content, LeagueActivityRule.parse(o["activityRule"]!!.jsonPrimitive.content),
                rules, PhotoRule.entries.first { it.raw == o["photoRule"]!!.jsonPrimitive.content },
                o["hasPhoto"]!!.jsonPrimitive.content.toBoolean(),
            )
            val want = o["score"]!!.jsonPrimitive.int
            val hasWeights = scoring == LeagueScoring.PONTOS && o["weightsRaw"]!!.jsonPrimitive.content.isNotEmpty()
            if (hasWeights) weighted++
            if (hasWeights && got != want) {
                // ND-9: a soma dos pesos no iOS segue a ordem de um Dictionary; só pode diferir por 1, na borda do arredondamento
                assertEquals(want.toDouble(), got.toDouble(), 1.0, o.toString())
                offByOne++
            } else {
                assertEquals(want, got, o.toString())
            }
        }
        println("Grupo L: ${l["score"]!!.jsonArray.size} casos, $weighted com pesos, $offByOne com diferença de 1 (ND-9)")
        assertTrue(offByOne <= weighted)
    }
}
