package com.alonsoalmeida.gymbros.domain

import com.alonsoalmeida.gymbros.domain.profile.PublicBros
import com.alonsoalmeida.gymbros.domain.profile.PublicBrosRules
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

/** "Bros e atributos" do perfil público contra o vetor compartilhado com o iPhone (gymbros-public-bros.json) */
class PublicBrosTest {
    private val vector = Json.parseToJsonElement(javaClass.getResource("/gymbros-public-bros.json")!!.readText()).jsonObject

    @Test
    fun attributes() {
        for (c in vector["attributes"]!!.jsonArray.map { it.jsonObject }) {
            val values = c["values"]!!.jsonObject.entries.associate { (k, v) -> Attribute.of(k)!! to v.jsonPrimitive.double }
            val percent = PublicBrosRules.percentages(values)
            val expected = (c["percent"] as? JsonObject)?.mapValues { it.value.jsonPrimitive.int }
            assertEquals(expected, percent, c.toString())
            assertEquals(c["dominant"]!!.takeIf { it !is JsonNull }?.jsonPrimitive?.content, PublicBrosRules.dominant(percent)?.raw, c.toString())
            percent?.let { assertEquals(100, it.values.sum()) }
        }
    }

    @Test
    fun favorite() {
        for (c in vector["favorite"]!!.jsonArray.map { it.jsonObject }) {
            val got = PublicBrosRules.favorite(c["kinds"]!!.jsonArray.map { ActivityKind.of(it.jsonPrimitive.content) })
            val expected = (c["favorite"] as? JsonObject)?.let { PublicBros.Favorite(it["kind"]!!.jsonPrimitive.content, it["count"]!!.jsonPrimitive.int) }
            assertEquals(expected, got, c.toString())
        }
    }

    @Test
    fun top() {
        for (c in vector["top"]!!.jsonArray.map { it.jsonObject }) {
            val expected = c["index"]!!.takeIf { it !is JsonNull }?.jsonPrimitive?.int
            assertEquals(expected, PublicBrosRules.topIndex(c["xp"]!!.jsonArray.map { it.jsonPrimitive.int }), c.toString())
        }
    }

    /** O JSON que o iPhone grava em `public.bros` abre aqui, e o daqui volta igual; perfil antigo fica sem `bros` */
    @Test
    fun format() {
        val json = Json { ignoreUnknownKeys = true }
        val ios = """{"top":{"name":"Rex","formID":"egg","level":3},"dexFound":4,"dexTotal":80,"favorite":{"kind":"corrida","count":7},""" +
            """"attributes":{"forca":10,"resistencia":70,"agilidade":20,"tecnica":0}}"""
        val b = json.decodeFromString(PublicBros.serializer(), ios)
        assertEquals("Rex", b.top?.name)
        assertEquals(ActivityKind.CORRIDA, b.favorite?.activity)
        assertEquals(Attribute.RESISTENCIA, b.dominant)
        assertEquals(b, json.decodeFromString(PublicBros.serializer(), json.encodeToString(PublicBros.serializer(), b)))
        val bare = json.decodeFromString(PublicBros.serializer(), """{"dexFound":1,"dexTotal":80}""")
        assertNull(bare.top)
        assertNull(bare.attributes)
    }
}
