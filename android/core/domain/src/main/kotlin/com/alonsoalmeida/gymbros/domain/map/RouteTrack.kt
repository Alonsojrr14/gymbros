package com.alonsoalmeida.gymbros.domain.map

import com.alonsoalmeida.gymbros.domain.ActivityKind
import com.alonsoalmeida.gymbros.domain.AttributeSplit
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Base64

// Corrida, caminhada e bike com GPS (ios/GymBros/Services/Route.swift `RouteTracker`, `RouteFinishView.save`;
// Models/RouteRecord.swift). Regras sem plataforma: o que entra no percurso, distância, tempo com pausas e o que vai
// para a cópia da conta (`routes` e a atividade).

/** Uma leitura do GPS: posição, precisão horizontal em metros (negativa = inválida) e a hora dela */
data class Fix(val coordinate: Coordinate, val accuracy: Double, val time: Instant)

/**
 * Gravação de um percurso (`RouteTracker`). Imutável: cada mudança devolve outra. Só grava com boa precisão (< 30 m), com
 * a gravação rodando e não pausada; saltos impossíveis do GPS (mais de 15 m/s) ficam de fora. Continuar depois de uma
 * pausa não liga o ponto de antes ao de agora (o trecho andado pausado não conta).
 */
data class RouteTrack(
    val kind: ActivityKind,
    val coords: List<Coordinate> = emptyList(),
    val meters: Double = 0.0,
    /** Começou (null: ainda na tela antes de "Começar") */
    val start: Instant? = null,
    val pausedAt: Instant? = null,
    val pausedTotalMillis: Long = 0,
    /** Último ponto que entrou no percurso */
    val last: Fix? = null,
    /** Última leitura, mesmo que não tenha entrado (posição no mapa e no ao vivo) */
    val current: Fix? = null,
) {
    val started: Boolean get() = start != null
    val paused: Boolean get() = pausedAt != null

    /** Segundos gravados, sem as pausas (`elapsed`) */
    fun elapsed(now: Instant): Int {
        val s = start ?: return 0
        val end = pausedAt ?: now
        return maxOf(((end.toEpochMilli() - s.toEpochMilli() - pausedTotalMillis) / 1000).toInt(), 0)
    }

    fun begin(now: Instant): RouteTrack = copy(start = now)

    fun togglePause(now: Instant): RouteTrack {
        val p = pausedAt ?: return copy(pausedAt = now)
        return copy(pausedTotalMillis = pausedTotalMillis + (now.toEpochMilli() - p.toEpochMilli()), pausedAt = null, last = null)
    }

    /** Terminar: o tempo para aqui */
    fun stop(now: Instant): RouteTrack = if (pausedAt == null) copy(pausedAt = now) else this

    fun add(fix: Fix): RouteTrack {
        val withCurrent = copy(current = fix)
        if (start == null || pausedAt != null || fix.accuracy < 0 || fix.accuracy >= MAX_ACCURACY) return withCurrent
        var meters = meters
        last?.let { prev ->
            val d = GymPlaces.distance(prev.coordinate, fix.coordinate)
            val dt = maxOf((fix.time.toEpochMilli() - prev.time.toEpochMilli()) / 1000.0, 1.0)
            if (d / dt > MAX_SPEED) return withCurrent
            meters += d
        }
        return withCurrent.copy(meters = meters, last = fix, coords = coords + fix.coordinate)
    }

    /** Onde você está agora para o mapa e para os amigos: a última leitura ou o fim do percurso */
    val here: Coordinate? get() = current?.coordinate ?: coords.lastOrNull()

    companion object {
        /** Precisão mínima para gravar (m) */
        const val MAX_ACCURACY = 30.0
        /** Acima disso (m/s) é salto do GPS */
        const val MAX_SPEED = 15.0
        /** O GPS só avisa depois de andar isso (m), como o `distanceFilter` do iOS */
        const val DISTANCE_FILTER = 5f
    }
}

/** Percurso salvo e a atividade dele, na cópia da conta (Backup.swift `RouteDTO` e `ActivityDTO`) */
object RouteEdits {
    /** Esforço padrão da conclusão (RouteFinishView) */
    const val DEFAULT_EFFORT = 6

    /** `RouteRecord.encode`: Double nativos little-endian intercalados (latitude, longitude…), em base64 no JSON */
    fun encodePoints(coords: List<Coordinate>): String {
        val buf = ByteBuffer.allocate(coords.size * 16).order(ByteOrder.LITTLE_ENDIAN)
        for (c in coords) { buf.putDouble(c.latitude); buf.putDouble(c.longitude) }
        return Base64.getEncoder().encodeToString(buf.array())
    }

    /** Minutos da atividade: pelo menos 1 */
    fun minutes(seconds: Int): Int = maxOf(seconds / 60, 1)

    /** Nota da atividade: "5,23 km · 5'40\" /km" */
    fun note(kind: ActivityKind, meters: Double, seconds: Int): String = kmText(meters) + " · " + paceText(kind, meters, seconds)

    /** Título do post: "Corrida · 5,23 km" */
    fun title(kind: ActivityKind, meters: Double): String = "${kindName(kind)} · ${kmText(meters)}"

    /** Divisão de atributos da atividade (ActivitySplits.stamp: sem tipo do Saúde, com a distância) */
    fun attributes(kind: ActivityKind, seconds: Int, effort: Int, meters: Double): String =
        AttributeSplit.encode(com.alonsoalmeida.gymbros.domain.train.TrainSplit.split(kind, minutes(seconds), effort, meters = meters))

    private fun iso(i: Instant) = DateTimeFormatter.ISO_INSTANT.format(i.truncatedTo(ChronoUnit.SECONDS))

    /** Item de `routes` (RouteDTO): uuid, activityUUID, kind, start, seconds, meters, points */
    fun routeJson(id: String, activityID: String?, kind: ActivityKind, start: Instant, seconds: Int, meters: Double, coords: List<Coordinate>): JsonObject =
        buildJsonObject {
            put("uuid", id)
            if (activityID != null) put("activityUUID", activityID)
            put("kind", kind.raw)
            put("start", iso(start))
            put("seconds", seconds)
            put("meters", meters)
            put("points", encodePoints(coords))
        }

    /** Junta o percurso em `routes` (o resto da cópia fica intacto); id repetido não entra de novo */
    fun addRoute(copy: JsonObject, route: JsonObject): JsonObject {
        val id = (route["uuid"] as? JsonPrimitive)?.content?.uppercase()
        val list = (copy["routes"] as? JsonArray).orEmpty()
        if (list.any { ((it as? JsonObject)?.get("uuid") as? JsonPrimitive)?.content?.uppercase() == id }) return copy
        return JsonObject(LinkedHashMap<String, JsonElement>(copy).apply { put("routes", JsonArray(list + route)) })
    }

    /**
     * Marca a atividade como gravada pelo GPS do app: distância (`meters`) e origem (`source`). Com `source`, ela vale
     * como treino gravado por aparelho nas regras das ligas, como no iOS.
     */
    fun stampActivity(copy: JsonObject, activityID: String, meters: Double, source: String): JsonObject {
        val list = (copy["activities"] as? JsonArray) ?: return copy
        val out = list.map { e ->
            val o = e as? JsonObject ?: return@map e
            if ((o["uuid"] as? JsonPrimitive)?.content?.uppercase() != activityID.uppercase()) return@map e
            JsonObject(LinkedHashMap<String, JsonElement>(o).apply { put("meters", JsonPrimitive(meters)); put("source", JsonPrimitive(source)) })
        }
        return JsonObject(LinkedHashMap<String, JsonElement>(copy).apply { put("activities", JsonArray(out)) })
    }
}
