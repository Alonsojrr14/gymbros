package com.alonsoalmeida.gymbros.domain

import com.alonsoalmeida.gymbros.domain.map.MapData
import com.alonsoalmeida.gymbros.domain.map.clock
import com.alonsoalmeida.gymbros.domain.map.distanceText
import com.alonsoalmeida.gymbros.domain.map.kmText
import com.alonsoalmeida.gymbros.domain.map.paceText
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.time.Instant
import java.time.ZoneId
import java.util.Base64

/** Aba Mapa em lista: contagens e textos iguais aos do MapScreen.swift e do Route.swift */
class MapDataTest {
    private val zone = ZoneId.of("America/Sao_Paulo")
    private val now = Instant.parse("2026-10-20T15:00:00Z")

    private fun points(vararg v: Double): String {
        val b = ByteBuffer.allocate(v.size * 8).order(ByteOrder.LITTLE_ENDIAN)
        v.forEach { b.putDouble(it) }
        return Base64.getEncoder().encodeToString(b.array())
    }

    private val copy = Json.parseToJsonElement("""
        {"version":1,"exportedAt":"2026-10-20T00:00:00Z",
         "gyms":[{"uuid":"g1","name":"Smart Fit","latitude":-23.5,"longitude":-46.6,"radius":120,"createdAt":"2026-01-01T00:00:00Z"},
                 {"uuid":"G2","name":"Parque","latitude":-23.6,"longitude":-46.7,"radius":200,"createdAt":"2026-02-01T00:00:00Z"}],
         "visits":[{"uuid":"v1","gymName":"Smart Fit","start":"2026-10-02T10:00:00Z","end":"2026-10-02T11:10:00Z","gymUUID":"G1"},
                   {"uuid":"v2","gymName":"Smart Fit","start":"2026-10-05T10:00:00Z","end":"2026-10-05T10:03:00Z","gymUUID":"g1"},
                   {"uuid":"v3","gymName":"Parque","start":"2026-09-30T10:00:00Z","end":"2026-09-30T10:50:00Z","gymUUID":"g2"},
                   {"uuid":"v4","gymName":"Parque","start":"2026-10-06T10:00:00Z","gymUUID":"g2"}],
         "activities":[{"uuid":"a1","kind":"corrida","date":"2026-10-07T10:00:00Z","minutes":30,"effort":5,"gymUUID":"g2"},
                       {"uuid":"a2","kind":"corrida","date":"2026-10-08T10:00:00Z","minutes":30,"effort":5,"gymUUID":"g2"},
                       {"uuid":"a3","kind":"corrida","date":"2026-10-09T10:00:00Z","minutes":30,"effort":5,"gymUUID":"g2"}],
         "routes":[{"uuid":"r1","kind":"corrida","start":"2026-10-03T10:00:00Z","seconds":1800,"meters":5000,"points":"${points(-23.5, -46.6, -23.51, -46.61)}"},
                   {"uuid":"r2","kind":"bike","start":"2026-09-03T10:00:00Z","seconds":3600,"meters":20000,"points":""}]}
    """.trimIndent()).jsonObject

    @Test fun gymsCountVisitsOrActivitiesAndSortByMostUsed() {
        val d = MapData.build(copy, now, zone)
        assertEquals(listOf("Parque", "Smart Fit"), d.gyms.map { it.name })
        assertEquals(listOf(3, 2), d.gyms.map { it.count })
        assertEquals(Instant.parse("2026-10-09T10:00:00Z"), d.gyms[0].last)
    }

    @Test fun monthStatsOnlyThisMonth() {
        val d = MapData.build(copy, now, zone)
        assertEquals(3, d.month.visits) // v1, v2, v4 (v3 é de setembro)
        assertEquals(70, d.month.averageMinutes) // só visitas encerradas com 5 min ou mais
        assertEquals("5,00 km", d.month.outdoorText)
        assertEquals(5000.0, d.outdoorByKind[ActivityKind.CORRIDA])
        assertEquals(0.0, d.outdoorByKind[ActivityKind.BIKE])
    }

    @Test fun routesNewestFirstWithDecodedPoints() {
        val d = MapData.build(copy, now, zone)
        assertEquals(listOf("r1", "r2"), d.routes.map { it.id })
        assertEquals(2, d.routes[0].coordinates.size)
        assertEquals(-46.61, d.routes[0].coordinates[1].longitude)
        assertEquals("Corrida · 5,00 km", d.routes[0].title)
        assertEquals("6'00\" /km", d.routes[0].pace)
        assertEquals("20,0 km/h", d.routes[1].pace)
    }

    @Test fun emptyCopyHasNothing() {
        val d = MapData.build(null, now, zone)
        assertEquals(0, d.gyms.size)
        assertNull(d.month.averageMinutes)
        assertEquals("–", d.month.averageText)
        assertEquals("–", d.month.outdoorText)
    }

    @Test fun textsMatchIOS() {
        assertEquals("0,00 km", kmText(0.0))
        assertEquals("1,23 km", kmText(1234.0))
        assertEquals("–", paceText(ActivityKind.CORRIDA, 10.0, 60))
        assertEquals("5:09", clock(309))
        assertEquals("1:05:09", clock(3909))
        assertEquals("350 m", distanceText(350.7))
        assertEquals("1,20 km", distanceText(1200.0))
    }
}
