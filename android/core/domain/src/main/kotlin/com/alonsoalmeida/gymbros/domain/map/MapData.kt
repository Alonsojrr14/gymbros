package com.alonsoalmeida.gymbros.domain.map

import com.alonsoalmeida.gymbros.domain.ActivityKind
import com.alonsoalmeida.gymbros.domain.backup.Iso8601Seconds
import com.alonsoalmeida.gymbros.domain.duel.durationText
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import java.math.BigDecimal
import java.math.RoundingMode
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import java.util.Base64

// Números e listas da aba Mapa. Fonte: ios/GymBros/Friends/MapScreen.swift, Models/Gym.swift, Models/RouteRecord.swift,
// Services/Route.swift. Lê o que está na cópia da conta (`gyms`, `visits`, `routes`, `activities.gymUUID`); quem grava
// lugares e idas é o GymPlaces.

/** Nome de cada categoria (Game.swift `ActivityKind.name`) */
fun kindName(k: ActivityKind): String = when (k) {
    ActivityKind.MUSCULACAO -> "Musculação"
    ActivityKind.CROSSFIT -> "Crossfit"
    ActivityKind.CORRIDA -> "Corrida"
    ActivityKind.CAMINHADA -> "Caminhada"
    ActivityKind.BIKE -> "Bike"
    ActivityKind.NATACAO -> "Natação"
    ActivityKind.VOLEI -> "Vôlei"
    ActivityKind.FUTEBOL -> "Futebol"
    ActivityKind.LUTAS -> "Lutas"
    ActivityKind.DANCA -> "Dança"
    ActivityKind.YOGA -> "Yoga"
    ActivityKind.OUTRO -> "Outro"
}

/** `String(format:)` do C: arredonda o valor binário exato, empate para o par */
private fun fixed(x: Double, digits: Int): String = BigDecimal(x).setScale(digits, RoundingMode.HALF_EVEN).toPlainString()

/** "5,23 km" (Route.swift `kmText`) */
fun kmText(meters: Double): String = "${fixed(meters / 1000, 2)} km".replace('.', ',')

/** Ritmo (min/km) para corrida e caminhada; velocidade (km/h) para bike (Route.swift `paceText`) */
fun paceText(kind: ActivityKind, meters: Double, seconds: Int): String {
    if (meters <= 20 || seconds <= 0) return "–"
    if (kind == ActivityKind.BIKE) return "${fixed(meters / 1000 / (seconds.toDouble() / 3600), 1)} km/h".replace('.', ',')
    val perKm = seconds.toDouble() / (meters / 1000)
    val whole = perKm.toInt()
    return "%d'%02d\" /km".format(whole / 60, whole % 60)
}

/** "1:05:09" ou "5:09" (Wod.swift `clock`) */
fun clock(s: Int): String = if (s >= 3600) "%d:%02d:%02d".format(s / 3600, s / 60 % 60, s % 60) else "%d:%02d".format(s / 60, s % 60)

/** "350 m" ou "1,20 km" (MapScreen `distance`) */
fun distanceText(m: Double): String = if (m < 1000) "${m.toInt()} m" else kmText(m)

@Serializable
private data class GymJson(val uuid: String, val name: String, val latitude: Double = 0.0, val longitude: Double = 0.0, val radius: Double = 0.0,
                           @Serializable(Iso8601Seconds::class) val createdAt: Instant)

@Serializable
private data class VisitJson(val uuid: String, val gymName: String = "", @Serializable(Iso8601Seconds::class) val start: Instant,
                             @Serializable(Iso8601Seconds::class) val end: Instant? = null, val gymUUID: String? = null)

@Serializable
private data class RouteJson(val uuid: String, val activityUUID: String? = null, val kind: String,
                             @Serializable(Iso8601Seconds::class) val start: Instant, val seconds: Int = 0, val meters: Double = 0.0,
                             val points: String = "")

@Serializable
private data class ActivityJson(val uuid: String, @Serializable(Iso8601Seconds::class) val date: Instant, val gymUUID: String? = null)

@Serializable
private data class MapCopy(val gyms: List<GymJson>? = null, val visits: List<VisitJson>? = null, val routes: List<RouteJson>? = null,
                           val activities: List<ActivityJson> = emptyList())

data class Coordinate(val latitude: Double, val longitude: Double)

/** Um lugar de treino, com a contagem que a lista mostra */
data class GymRow(val id: String, val name: String, val coordinate: Coordinate, val radius: Double, val count: Int, val last: Instant?)

data class RouteRow(val id: String, val kind: ActivityKind, val start: Instant, val seconds: Int, val meters: Double, val coordinates: List<Coordinate>) {
    val title: String get() = "${kindName(kind)} · ${kmText(meters)}"
    val pace: String get() = paceText(kind, meters, seconds)
}

data class MonthStats(val visits: Int, val averageMinutes: Int?, val outdoorMeters: Double) {
    val averageText: String get() = averageMinutes?.let { durationText(it) } ?: "–"
    val outdoorText: String get() = if (outdoorMeters > 0) kmText(outdoorMeters) else "–"
}

data class MapData(
    val gyms: List<GymRow>,
    /** Mais recentes primeiro (o iOS lista os 20 primeiros) */
    val routes: List<RouteRow>,
    val month: MonthStats,
    /** Total do mês de cada categoria ao ar livre (corrida, caminhada, bike) */
    val outdoorByKind: Map<ActivityKind, Double>,
) {
    companion object {
        private val json = Json { ignoreUnknownKeys = true; explicitNulls = false }
        val OUTDOOR = listOf(ActivityKind.CORRIDA, ActivityKind.CAMINHADA, ActivityKind.BIKE)

        fun build(copy: JsonObject?, now: Instant, zone: ZoneId = ZoneId.systemDefault()): MapData {
            val c = copy?.let { runCatching { json.decodeFromJsonElement(MapCopy.serializer(), it) }.getOrNull() } ?: MapCopy()
            val month = YearMonth.from(now.atZone(zone))
            fun inMonth(i: Instant) = YearMonth.from(i.atZone(zone)) == month

            val visits = c.visits.orEmpty()
            val acts = c.activities
            fun key(s: String?) = s?.uppercase()
            // Mais visitados primeiro; conta visitas detectadas e treinos registrados no lugar (o maior dos dois)
            val gyms = c.gyms.orEmpty().sortedBy { it.createdAt }.map { g ->
                val id = key(g.uuid)
                val v = visits.filter { key(it.gymUUID) == id }
                val a = acts.filter { key(it.gymUUID) == id }
                GymRow(g.uuid, g.name, Coordinate(g.latitude, g.longitude), g.radius, maxOf(v.size, a.size),
                       (v.map { it.start } + a.map { it.date }).maxOrNull())
            }.sortedByDescending { it.count } // estável, como o `sorted` do Swift com a ordem de criação no empate

            val routes = c.routes.orEmpty().sortedByDescending { it.start }.map { r ->
                RouteRow(r.uuid, ActivityKind.of(r.kind), r.start, r.seconds, r.meters, decodePoints(r.points))
            }
            val monthVisits = visits.filter { inMonth(it.start) }
            val durations = monthVisits.mapNotNull { v -> v.end?.let { maxOf(((it.epochSecond - v.start.epochSecond) / 60).toInt(), 0) } }.filter { it >= 5 }
            val monthRoutes = routes.filter { inMonth(it.start) }
            return MapData(
                gyms = gyms,
                routes = routes,
                month = MonthStats(monthVisits.size, if (durations.isEmpty()) null else durations.sum() / durations.size,
                                   monthRoutes.sumOf { it.meters }),
                outdoorByKind = OUTDOOR.associateWith { k -> monthRoutes.filter { it.kind == k }.sumOf { it.meters } },
            )
        }

        /** `RouteRecord.points`: Double nativos (little-endian) intercalados, latitude e longitude, em base64 no JSON */
        fun decodePoints(base64: String): List<Coordinate> {
            if (base64.isEmpty()) return emptyList()
            val bytes = runCatching { Base64.getDecoder().decode(base64) }.getOrNull() ?: return emptyList()
            val buf = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
            val values = DoubleArray(bytes.size / 8) { buf.getDouble(it * 8) }
            return (0 until values.size - 1 step 2).map { Coordinate(values[it], values[it + 1]) }
        }
    }
}
