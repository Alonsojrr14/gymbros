package com.alonsoalmeida.gymbros.domain

import com.alonsoalmeida.gymbros.domain.map.Coordinate
import com.alonsoalmeida.gymbros.domain.map.Fix
import com.alonsoalmeida.gymbros.domain.map.GymPlaces
import com.alonsoalmeida.gymbros.domain.map.MapData
import com.alonsoalmeida.gymbros.domain.map.RouteEdits
import com.alonsoalmeida.gymbros.domain.map.RouteTrack
import com.alonsoalmeida.gymbros.domain.social.LivePresenceRules
import com.alonsoalmeida.gymbros.domain.social.LiveShare
import com.alonsoalmeida.gymbros.domain.social.LiveStatus
import com.alonsoalmeida.gymbros.domain.train.LoggedSet
import com.alonsoalmeida.gymbros.domain.train.Session
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.time.Instant

/** Percurso pelo GPS (Route.swift `RouteTracker`, `RouteFinishView.save`) e treino ao vivo (LiveShare.swift, `LivePresence`) */
class RouteLiveTest {
    private val t0 = Instant.parse("2026-10-24T10:00:00Z")
    private fun at(s: Long) = t0.plusSeconds(s)
    /** ~11,1 m de latitude por 0,0001° */
    private fun fix(lat: Double, s: Long, acc: Double = 5.0) = Fix(Coordinate(lat, -46.6), acc, at(s))

    @Test fun recordsOnlyWhileRunningWithGoodAccuracy() {
        var r = RouteTrack(ActivityKind.CORRIDA)
        r = r.add(fix(-23.5, 0))
        assertTrue(r.coords.isEmpty(), "antes de começar só mostra a posição")
        assertEquals(Coordinate(-23.5, -46.6), r.here)
        r = r.begin(t0).add(fix(-23.5, 0)).add(fix(-23.5001, 4)).add(fix(-23.5002, 8, acc = 30.0)).add(fix(-23.5002, 9, acc = -1.0))
        assertEquals(2, r.coords.size, "precisão de 30 m ou inválida fica de fora")
        assertEquals(GymPlaces.distance(Coordinate(-23.5, -46.6), Coordinate(-23.5001, -46.6)), r.meters, 1e-9)
    }

    @Test fun ignoresGpsJumps() {
        var r = RouteTrack(ActivityKind.CORRIDA).begin(t0).add(fix(-23.5, 0))
        // ~111 m em 2 s = 55 m/s: salto
        r = r.add(fix(-23.501, 2))
        assertEquals(1, r.coords.size)
        assertEquals(Coordinate(-23.501, -46.6), r.here, "a leitura vira a posição atual mesmo fora do percurso")
        // Medido do último ponto bom: ~111 m em 20 s = 5,5 m/s
        r = r.add(fix(-23.501, 20))
        assertEquals(2, r.coords.size)
        assertEquals(111.2, r.meters, 0.5)
    }

    @Test fun jumpUsesAtLeastOneSecond() {
        // Duas leituras na mesma hora: divide por 1 s (10 m/s passa, 22 m/s não)
        val r = RouteTrack(ActivityKind.BIKE).begin(t0).add(fix(-23.5, 0)).add(fix(-23.50009, 0))
        assertEquals(2, r.coords.size)
        assertEquals(2, r.add(fix(-23.5003, 0)).coords.size)
    }

    @Test fun pausesStopTimeAndDistance() {
        var r = RouteTrack(ActivityKind.CAMINHADA).begin(t0).add(fix(-23.5, 0)).add(fix(-23.5001, 10))
        r = r.togglePause(at(60))
        assertEquals(60, r.elapsed(at(500)), "pausado, o tempo não anda")
        r = r.add(fix(-23.6, 100))
        assertEquals(2, r.coords.size, "pausado não grava")
        r = r.togglePause(at(160))
        assertNull(r.last, "continuar não liga o ponto de antes ao de agora")
        r = r.add(fix(-23.6, 170)).add(fix(-23.6001, 180))
        assertEquals(4, r.coords.size)
        assertEquals(2 * 11.12, r.meters, 0.05)
        assertEquals(100, r.elapsed(at(200)))
        r = r.stop(at(260))
        assertEquals(160, r.elapsed(at(9_999)))
        assertEquals(0, RouteTrack(ActivityKind.CORRIDA).elapsed(at(100)))
    }

    @Test fun pointsRoundTripWithTheIPhoneFormat() {
        val coords = listOf(Coordinate(-23.561, -46.656), Coordinate(-23.562, -46.657))
        assertEquals(coords, MapData.decodePoints(RouteEdits.encodePoints(coords)))
        assertEquals("", RouteEdits.encodePoints(emptyList()))
    }

    @Test fun savedRouteShowsOnTheMapAndHasTheActivity() {
        val copy = Json.parseToJsonElement("""{"version":1,"exportedAt":"2026-10-24T00:00:00Z",
            "activities":[{"uuid":"A1","kind":"corrida","date":"2026-10-24T10:00:00Z","minutes":25,"effort":6,"note":"x"}]}""").jsonObject
        val coords = listOf(Coordinate(-23.5, -46.6), Coordinate(-23.51, -46.6))
        val route = RouteEdits.routeJson("R1", "A1", ActivityKind.CORRIDA, Instant.parse("2026-10-24T10:00:00.700Z"), 1530, 5230.4, coords)
        assertEquals(setOf("uuid", "activityUUID", "kind", "start", "seconds", "meters", "points"), route.keys)
        assertEquals("2026-10-24T10:00:00Z", (route["start"] as JsonPrimitive).content, "datas sem fração, como o .iso8601 do iOS")
        var out = RouteEdits.addRoute(copy, route)
        assertEquals(out, RouteEdits.addRoute(out, route), "o mesmo percurso não entra duas vezes")
        out = RouteEdits.stampActivity(out, "a1", 5230.4, "GPS do Android")
        val act = (out["activities"] as JsonArray)[0] as JsonObject
        assertEquals(5230.4, (act["meters"] as JsonPrimitive).content.toDouble())
        assertEquals("GPS do Android", (act["source"] as JsonPrimitive).content)
        val map = MapData.build(out, Instant.parse("2026-10-25T10:00:00Z"))
        assertEquals(1, map.routes.size)
        assertEquals(coords, map.routes[0].coordinates)
        assertEquals("Corrida · 5,23 km", map.routes[0].title)
        assertEquals(5230.4, map.outdoorByKind[ActivityKind.CORRIDA]!!, 1e-9)
    }

    @Test fun activityTextsMatchTheIPhone() {
        assertEquals(1, RouteEdits.minutes(30))
        assertEquals(25, RouteEdits.minutes(1530))
        assertEquals("5,00 km · 5'06\" /km", RouteEdits.note(ActivityKind.CORRIDA, 5000.0, 1530))
        assertEquals("20,00 km · 24,0 km/h", RouteEdits.note(ActivityKind.BIKE, 20000.0, 3000))
        assertEquals("Caminhada · 0,01 km", RouteEdits.title(ActivityKind.CAMINHADA, 10.0))
    }

    // MARK: Ao vivo

    @Test fun shareChoiceFollowsDefaultAndPerWorkoutOverrides() {
        assertTrue(LiveShare.isSharing("treino", emptyMap()), "ligado por padrão")
        assertFalse(LiveShare.isSharing("treino", mapOf("shareLive" to false)))
        val s = mapOf("shareLive" to false, "shareLiveWorkouts" to mapOf("a" to true, "b" to false))
        assertTrue(LiveShare.isSharing("a", s), "pode ligar num treino mesmo com o padrão desligado")
        assertFalse(LiveShare.isSharing("c", s))
        assertFalse(LiveShare.isSharing("b", mapOf("shareLiveWorkouts" to mapOf("b" to false))), "só o treino escolhido muda")
    }

    @Test fun throttleWritesAtMostEvery30Seconds() {
        assertEquals(0L, LivePresenceRules.waitMillis(Long.MIN_VALUE / 2, 1_000))
        assertEquals(20_000L, LivePresenceRules.waitMillis(0, 10_000))
        assertTrue(LivePresenceRules.shouldSchedule(changed = true, wait = 20_000))
        assertFalse(LivePresenceRules.shouldSchedule(changed = false, wait = 20_000))
        assertTrue(LivePresenceRules.shouldSchedule(changed = false, wait = 0))
    }

    @Test fun positionAloneIsNotAChange() {
        val a = LiveStatus(ActivityKind.CORRIDA, t0, "Corrida", "1,00 km", meters = 1000.0, coordinate = Coordinate(1.0, 1.0))
        assertTrue(a.sameAs(a.copy(meters = 1004.0, coordinate = Coordinate(2.0, 2.0), route = listOf(Coordinate(2.0, 2.0)))))
        assertFalse(a.sameAs(a.copy(now = "1,01 km")))
        assertFalse(a.sameAs(null))
    }

    @Test fun documentHasTheSameFieldsAsTheIPhone() {
        val route = (0 until 150).map { Coordinate(it.toDouble(), -it.toDouble()) }
        val s = LivePresenceRules.route(ActivityKind.BIKE, t0, 12_345.0, Coordinate(9.0, 9.0), route)
        val f = LivePresenceRules.fields("me", "Ana", "egg", s, at(60))
        assertEquals(listOf("user", "name", "formID", "kind", "start", "place", "now", "done", "sets", "meters", "latitude", "longitude",
                            "route", "music", "endedAt", "updatedAt"), f.keys.toList())
        assertEquals("bike", f["kind"])
        assertEquals("Bike", f["place"])
        assertEquals("12,35 km", f["now"])
        assertEquals(9.0, f["latitude"])
        @Suppress("UNCHECKED_CAST") val flat = f["route"] as List<Double>
        assertEquals(200, flat.size, "os últimos 100 pontos")
        assertEquals(listOf(50.0, -50.0), flat.take(2))
        assertNull(f["music"])
        assertNull(f["endedAt"])
        assertNull(f["sets"])
        val end = LivePresenceRules.endedFields("me", ActivityKind.BIKE, at(90))
        assertEquals(setOf("user", "start", "now", "done", "route", "endedAt", "kind", "updatedAt"), end.keys)
        assertNull(end["start"])
        assertEquals("", end["now"])
        assertEquals(at(90), end["endedAt"])
    }

    @Test fun workoutStatusShowsCurrentSetAndFinishedExercises() {
        val sets = listOf(
            LoggedSet("supino-reto", 0, 0, 20.0, 10, done = true, warmup = true),
            LoggedSet("supino-reto", 0, 1, 60.0, 10, done = true),
            LoggedSet("supino-reto", 0, 2, 60.0, 10, done = true),
            LoggedSet("remada-baixa", 1, 0, 50.0, 12, done = true),
            LoggedSet("remada-baixa", 1, 1, 50.0, 12),
        )
        val s = Session("S1", "Peito", start = t0, sets = sets, currentExerciseID = "remada-baixa")
        val st = LivePresenceRules.workout(s, "Smart Fit", null)
        assertEquals(ActivityKind.MUSCULACAO, st.kind)
        assertEquals(listOf("Supino reto · 2 séries"), st.done)
        assertEquals(3, st.sets)
        assertEquals("Remada baixa · série 2 de 2 · 50 kg × 12", st.now)
        val all = LivePresenceRules.workout(s.copy(sets = sets.map { it.copy(done = true) }), "", null)
        assertEquals("Remada baixa", all.now, "sem série a fazer, só o exercício")
        assertEquals("Treino livre", LivePresenceRules.workout(s.copy(sets = emptyList(), currentExerciseID = null), "", null).now)
        assertEquals("Fran · For Time", LivePresenceRules.wod("Fran", "For Time", t0, "", null).now)
    }
}
