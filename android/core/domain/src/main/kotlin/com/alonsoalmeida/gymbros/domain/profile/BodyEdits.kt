package com.alonsoalmeida.gymbros.domain.profile

import com.alonsoalmeida.gymbros.domain.backup.AccountEdits
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.util.Locale
import java.util.UUID

/**
 * Peso e medidas na cópia da conta (`body`, Backup.swift `BodyDTO`). As fotos de progresso nunca entram aqui: ficam só no
 * aparelho (no iOS, saem da cópia antes de subir, `stripPhotos`), e o Android preserva as que vieram de lá.
 */
object BodyEdits {
    data class Values(val date: java.time.Instant, val weight: Double?, val measures: Map<Measure, Double?>)

    /** Novo (id nulo) ou editado; devolve a cópia e o id */
    fun save(copy: JsonObject, id: String?, v: Values): Pair<JsonObject, String> {
        val uuid = id?.uppercase() ?: UUID.randomUUID().toString().uppercase()
        val list = (copy["body"] as? JsonArray).orEmpty()
        val old = list.firstOrNull { ((it as? JsonObject)?.get("uuid") as? JsonPrimitive)?.content?.equals(uuid, true) == true } as? JsonObject
        val item = LinkedHashMap<String, JsonElement>(old ?: JsonObject(emptyMap()))
        item["uuid"] = JsonPrimitive(uuid)
        item["date"] = JsonPrimitive(AccountEdits.iso(v.date))
        fun put(k: String, x: Double?) { if (x == null) item.remove(k) else item[k] = JsonPrimitive(x) }
        put("weight", v.weight)
        for (m in Measure.entries) put(m.raw, v.measures[m])
        val next = if (old == null) list + JsonObject(item) else list.map { if (it === old) JsonObject(item) else it }
        var out = JsonObject(LinkedHashMap<String, JsonElement>(copy).apply { put("body", JsonArray(next)) })
        // BodyProfile.remember(weight:): último peso para estimativas fora das telas
        latestWeight(out)?.takeIf { it > 0 }?.let { out = ProfileEdits.set(out, "profileLastWeight", it) }
        return out to uuid
    }

    data class WeightSample(val id: String, val date: java.time.Instant, val kg: Double)

    /**
     * Pesos do Health Connect (BodyTools.swift `importBodyMass`): um por dia, só nos dias sem peso registrado e sem
     * repetir amostra já importada; peso com uma casa. Devolve a cópia e quantos entraram.
     */
    fun importWeights(copy: JsonObject, samples: List<WeightSample>, zone: java.time.ZoneId): Pair<JsonObject, Int> {
        val existing = (copy["body"] as? JsonArray).orEmpty().mapNotNull { it as? JsonObject }
        val known = existing.mapNotNull { (it["healthUUID"] as? JsonPrimitive)?.takeIf { p -> p !is JsonNull }?.content }.toSet()
        val days = existing.filter { (it["weight"] as? JsonPrimitive)?.takeIf { p -> p !is JsonNull } != null }
            .mapNotNull { runCatching { java.time.Instant.parse((it["date"] as JsonPrimitive).content).atZone(zone).toLocalDate() }.getOrNull() }
            .toMutableSet()
        val added = mutableListOf<JsonObject>()
        for (s in samples.sortedBy { it.date }) {
            val day = s.date.atZone(zone).toLocalDate()
            if (s.id in known || day in days) continue
            added += JsonObject(mapOf(
                "uuid" to JsonPrimitive(UUID.randomUUID().toString().uppercase()), "date" to JsonPrimitive(AccountEdits.iso(s.date)),
                "weight" to JsonPrimitive(com.alonsoalmeida.gymbros.domain.roundHalfAwayFromZero(s.kg * 10) / 10), "healthUUID" to JsonPrimitive(s.id),
            ))
            days += day
        }
        if (added.isEmpty()) return copy to 0
        return JsonObject(LinkedHashMap<String, JsonElement>(copy).apply { put("body", JsonArray(existing + added)) }) to added.size
    }

    fun delete(copy: JsonObject, id: String): JsonObject {
        val list = (copy["body"] as? JsonArray) ?: return copy
        return JsonObject(LinkedHashMap<String, JsonElement>(copy).apply {
            put("body", JsonArray(list.filter { ((it as? JsonObject)?.get("uuid") as? JsonPrimitive)?.content?.equals(id, true) != true }))
        })
    }

    fun latestWeight(copy: JsonObject): Double? = (copy["body"] as? JsonArray).orEmpty().mapNotNull { it as? JsonObject }
        .filter { (it["weight"] as? JsonPrimitive)?.takeIf { p -> p !is JsonNull } != null }
        .maxByOrNull { (it["date"] as? JsonPrimitive)?.content ?: "" }?.let { (it["weight"] as JsonPrimitive).content.toDoubleOrNull() }

    /** Progression.fmt: inteiro sem casas; senão uma (ou duas, se exatas), com vírgula */
    fun fmt(w: Double): String {
        if (w % 1.0 == 0.0) return w.toLong().toString()
        val cents = Math.round(w * 100).toDouble()
        val exact = kotlin.math.abs(w * 100 - cents) < 1e-6 && cents.toLong() % 10 != 0L
        val text = if (exact) String.format(Locale.ROOT, "%.2f", w) else String.format(Locale.ROOT, "%.1f", w)
        return text.replace(".", ",")
    }
}
