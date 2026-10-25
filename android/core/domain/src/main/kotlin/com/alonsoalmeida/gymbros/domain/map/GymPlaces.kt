package com.alonsoalmeida.gymbros.domain.map

import com.alonsoalmeida.gymbros.domain.backup.AccountEdits
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull
import java.time.Instant
import java.util.UUID
import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

// Lugares de treino e idas a eles (Models/Gym.swift, Services/Location.swift `GymLocation`), gravados na cópia da conta
// como o Backup.swift do iOS: `gyms` {uuid, name, latitude, longitude, radius, createdAt} e `visits` {uuid, gymName, start,
// end?, gymUUID?}. Ids em UUID maiúsculo, datas ISO 8601 sem fração; campos que o Android não conhece ficam intactos.

data class Gym(val uuid: String, val name: String, val coordinate: Coordinate, val radius: Double, val createdAt: Instant)

object GymPlaces {
    /** Treinos com menos tempo que isso não são encerrados ao sair (evita falso alarme do GPS) */
    const val MIN_WORKOUT_MINUTES = 10L
    /** Lugares vigiados de uma vez (o iOS monitora até 20) */
    const val MONITOR_LIMIT = 20
    val RADII = listOf(50.0, 100.0, 150.0, 250.0)

    private fun s(o: JsonObject, k: String): String? = (o[k] as? JsonPrimitive)?.takeIf { it.isString }?.content
    private fun d(o: JsonObject, k: String): Double? = (o[k] as? JsonPrimitive)?.doubleOrNull
    private fun date(o: JsonObject, k: String): Instant? = s(o, k)?.let { runCatching { Instant.parse(it) }.getOrNull() }
    private fun items(copy: JsonObject?, k: String): List<JsonObject> = (copy?.get(k) as? JsonArray)?.mapNotNull { it as? JsonObject }.orEmpty()
    private fun replace(copy: JsonObject, k: String, list: List<JsonElement>) =
        JsonObject(LinkedHashMap<String, JsonElement>(copy).apply { put(k, JsonArray(list)) })
    private fun num(v: Double): JsonPrimitive = if (v % 1.0 == 0.0 && kotlin.math.abs(v) < 1e15) JsonPrimitive(v.toLong()) else JsonPrimitive(v)

    fun newID(): String = UUID.randomUUID().toString().uppercase()

    /** Do mais antigo ao mais novo (o @Query do iOS) */
    fun gyms(copy: JsonObject?): List<Gym> = items(copy, "gyms").mapNotNull { g ->
        Gym(s(g, "uuid")?.uppercase() ?: return@mapNotNull null, s(g, "name").orEmpty(), Coordinate(d(g, "latitude") ?: 0.0, d(g, "longitude") ?: 0.0),
            d(g, "radius") ?: 100.0, date(g, "createdAt") ?: Instant.EPOCH)
    }.sortedBy { it.createdAt }

    fun gym(copy: JsonObject?, id: String?): Gym? = id?.let { gyms(copy).firstOrNull { g -> g.uuid.equals(it, true) } }

    /** Distância em metros (esfera de raio médio; difere do CLLocation em centímetros nessas distâncias) */
    fun distance(a: Coordinate, b: Coordinate): Double {
        val r = 6_371_008.8
        val p1 = Math.toRadians(a.latitude); val p2 = Math.toRadians(b.latitude)
        val dp = p2 - p1; val dl = Math.toRadians(b.longitude - a.longitude)
        val h = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * r * asin(minOf(1.0, sqrt(h)))
    }

    /** Lugar salvo que contém a posição (o mais próximo, se houver mais de um) */
    fun containing(gyms: List<Gym>, here: Coordinate, accuracy: Double): Gym? =
        gyms.map { it to distance(it.coordinate, here) }.filter { it.second <= maxOf(it.first.radius, accuracy) }.minByOrNull { it.second }?.first

    fun nearest(gyms: List<Gym>, here: Coordinate): Pair<Gym, Double>? = gyms.map { it to distance(it.coordinate, here) }.minByOrNull { it.second }

    /** O GPS dentro do prédio oscila e o sistema avisa saídas que não aconteceram: só conta longe do lugar de verdade */
    fun leftForReal(g: Gym, here: Coordinate, accuracy: Double): Boolean = distance(g.coordinate, here) > g.radius + maxOf(accuracy, 50.0)

    /** Os lugares vigiados: os visitados mais recentemente (ou criados), até `limit` */
    fun recent(copy: JsonObject?, limit: Int = MONITOR_LIMIT): List<Gym> {
        val last = HashMap<String, Instant>()
        for (v in items(copy, "visits")) {
            val id = s(v, "gymUUID")?.uppercase() ?: continue
            val start = date(v, "start") ?: continue
            if ((last[id] ?: Instant.MIN) < start) last[id] = start
        }
        return gyms(copy).sortedByDescending { last[it.uuid] ?: it.createdAt }.take(limit)
    }

    /** Pontos de um círculo de `radius` metros, para desenhar o raio no mapa */
    fun circle(center: Coordinate, radius: Double, steps: Int = 64): List<Coordinate> {
        val k = cos(Math.toRadians(center.latitude))
        return (0..steps).map { i ->
            val a = 2 * Math.PI * i / steps
            Coordinate(center.latitude + radius * sin(a) / 111_111, center.longitude + radius * cos(a) / (111_111 * k))
        }
    }

    /** Novo ou editado; nome vazio vira "Academia" no novo e mantém o antigo na edição (GymEditorView.save) */
    fun save(copy: JsonObject, id: String?, name: String, at: Coordinate, radius: Double, now: Instant): JsonObject {
        val list = items(copy, "gyms")
        val old = id?.let { list.firstOrNull { o -> s(o, "uuid").equals(it, true) } }
        val clean = name.trim()
        val obj = JsonObject(LinkedHashMap<String, JsonElement>(old ?: emptyMap()).apply {
            put("uuid", JsonPrimitive(old?.let { s(it, "uuid") } ?: newID()))
            put("name", JsonPrimitive(clean.ifEmpty { old?.let { s(it, "name") } ?: "Academia" }))
            put("latitude", JsonPrimitive(at.latitude)); put("longitude", JsonPrimitive(at.longitude)); put("radius", num(radius))
            if (old == null) put("createdAt", JsonPrimitive(AccountEdits.iso(now)))
        })
        return replace(copy, "gyms", if (old == null) list + obj else list.map { if (it === old) obj else it })
    }

    /** Apaga só o lugar: o histórico de treinos e as idas continuam */
    fun delete(copy: JsonObject, id: String): JsonObject = replace(copy, "gyms", items(copy, "gyms").filter { !s(it, "uuid").equals(id, true) })

    /** Chegou: abre uma ida ao lugar */
    fun openVisit(copy: JsonObject, g: Gym, now: Instant): JsonObject = replace(copy, "visits", items(copy, "visits") + JsonObject(mapOf(
        "uuid" to JsonPrimitive(newID()), "gymName" to JsonPrimitive(g.name), "start" to JsonPrimitive(AccountEdits.iso(now)),
        "gymUUID" to JsonPrimitive(g.uuid))))

    /** Saiu: fecha a ida aberta deste lugar (com mais de um lugar, a última aberta pode ser de outro) */
    fun closeVisit(copy: JsonObject, gymID: String, now: Instant): JsonObject {
        val list = items(copy, "visits")
        val open = list.filter { it["end"].let { e -> e == null || e !is JsonPrimitive || !e.isString } && s(it, "gymUUID").equals(gymID, true) }
            .maxByOrNull { date(it, "start") ?: Instant.MIN } ?: return copy
        val closed = JsonObject(LinkedHashMap<String, JsonElement>(open).apply { put("end", JsonPrimitive(AccountEdits.iso(now))) })
        return replace(copy, "visits", list.map { if (it === open) closed else it })
    }
}
