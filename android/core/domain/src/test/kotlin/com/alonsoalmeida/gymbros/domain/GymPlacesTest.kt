package com.alonsoalmeida.gymbros.domain

import com.alonsoalmeida.gymbros.domain.map.Coordinate
import com.alonsoalmeida.gymbros.domain.map.GymPlaces
import com.alonsoalmeida.gymbros.domain.map.MapData
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.time.Instant

/** Lugares e idas gravados no formato do Backup.swift, e a regra de saída de verdade (Location.swift `left`) */
class GymPlacesTest {
    private val now = Instant.parse("2026-10-24T12:00:00Z")
    private val paulista = Coordinate(-23.5614, -46.6559)
    private val base = Json.parseToJsonElement("""{"trainerName":"Zé","futuro":{"x":1},"gyms":[],"visits":[]}""") as JsonObject

    @Test
    fun savesEditsAndDeletesInTheIPhoneFormat() {
        var c = GymPlaces.save(base, null, "  ", paulista, 100.0, now)
        val g = c["gyms"]!!.jsonArray.single().jsonObject
        assertEquals("Academia", g["name"]!!.jsonPrimitive.content)
        assertEquals("100", g["radius"]!!.jsonPrimitive.content)
        assertEquals("2026-10-24T12:00:00Z", g["createdAt"]!!.jsonPrimitive.content)
        val id = g["uuid"]!!.jsonPrimitive.content
        assertEquals(id.uppercase(), id)
        assertTrue(c.containsKey("futuro"))

        c = GymPlaces.save(c, id.lowercase(), "Smart Fit", paulista, 150.0, now.plusSeconds(60))
        val e = GymPlaces.gyms(c).single()
        assertEquals("Smart Fit", e.name)
        assertEquals(150.0, e.radius)
        assertEquals(now, e.createdAt)
        assertEquals(1, MapData.build(c, now).gyms.size)

        assertTrue(GymPlaces.gyms(GymPlaces.delete(c, id)).isEmpty())
    }

    @Test
    fun opensAndClosesTheVisitOfThatPlace() {
        var c = GymPlaces.save(base, null, "A", paulista, 100.0, now)
        val g = GymPlaces.gyms(c).single()
        c = GymPlaces.openVisit(c, g, now)
        c = GymPlaces.closeVisit(c, "outro", now.plusSeconds(600))
        assertNull(c["visits"]!!.jsonArray.single().jsonObject["end"])
        c = GymPlaces.closeVisit(c, g.uuid, now.plusSeconds(3600))
        val v = c["visits"]!!.jsonArray.single().jsonObject
        assertEquals("2026-10-24T13:00:00Z", v["end"]!!.jsonPrimitive.content)
        assertEquals(g.uuid, v["gymUUID"]!!.jsonPrimitive.content)
        assertEquals(60, MapData.build(c, now).month.averageMinutes)
    }

    @Test
    fun onlyLeavesForRealOutsideRadiusPlusAccuracy() {
        val g = GymPlaces.gyms(GymPlaces.save(base, null, "A", paulista, 100.0, now)).single()
        val north = { m: Double -> Coordinate(paulista.latitude + m / 111_195.0, paulista.longitude) }
        assertEquals(120.0, GymPlaces.distance(paulista, north(120.0)), 1.0)
        assertFalse(GymPlaces.leftForReal(g, north(140.0), 10.0))   // 100 + 50 mínimo
        assertTrue(GymPlaces.leftForReal(g, north(160.0), 10.0))
        assertFalse(GymPlaces.leftForReal(g, north(160.0), 80.0))   // precisão ruim: 100 + 80
        assertEquals(g, GymPlaces.containing(listOf(g), north(90.0), 5.0))
        assertNull(GymPlaces.containing(listOf(g), north(130.0), 5.0))
    }
}
