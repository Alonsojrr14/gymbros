package com.alonsoalmeida.gymbros.domain.activities

import com.alonsoalmeida.gymbros.domain.ActivityKind
import com.alonsoalmeida.gymbros.domain.AttributeSplit
import com.alonsoalmeida.gymbros.domain.BroLedger
import com.alonsoalmeida.gymbros.domain.Roster
import com.alonsoalmeida.gymbros.domain.backup.AccountEdits
import com.alonsoalmeida.gymbros.domain.backup.AppleReferenceDate
import com.alonsoalmeida.gymbros.domain.profile.ProfileEdits
import com.dd.plist.NSArray
import com.dd.plist.NSData
import com.dd.plist.NSDictionary
import com.dd.plist.NSString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put
import java.time.Instant

/**
 * Apagar e editar atividades direto na cópia da conta, como o iPhone faz. Fontes: Activities/ActivityDetail.swift
 * (`deleteActivity`), Bros/RetiredActivities.swift (`retire`) e Activities/LogActivityView.swift (`save` editando).
 */
object ActivityEdits {
    /** Liga especial dos posts no perfil (`ProfileFeed.id`) */
    const val PROFILE_FEED = "00000000-0000-0000-0000-0000000000AA"
    const val IGNORED_KEY = "healthIgnored"
    const val RETRACTIONS_KEY = "pendingRetractions"
    const val SPLITS_KEY = "activitySplits"

    private fun JsonObject.str(k: String): String? = (this[k] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.content
    private fun list(copy: JsonObject, key: String): List<JsonObject> = (copy[key] as? JsonArray)?.mapNotNull { it as? JsonObject }.orEmpty()
    private fun same(a: String?, b: String) = a != null && a.equals(b, ignoreCase = true)

    fun activity(copy: JsonObject, id: String): JsonObject? = list(copy, "activities").firstOrNull { same(it.str("uuid"), id) }

    /** Check-ins (perfil e ligas) da atividade */
    fun posts(copy: JsonObject, id: String): List<JsonObject> = list(copy, "checkIns").filter { same(it.str("activityUUID"), id) }

    /** Treino guiado ou WOD ligado: a divisão de atributos usa as séries, que o Android ainda não tem */
    fun hasWorkout(copy: JsonObject, id: String): Boolean =
        list(copy, "sessions").any { same(it.str("activityUUID"), id) } || list(copy, "wods").any { same(it.str("activityUUID"), id) }

    /**
     * RetiredActivities.retire: guarda o XP da atividade antes de apagá-la, para os mesmos bros que o receberam (apagar
     * não faz o bro voltar de forma). `roster` dá a regra das partes (`Roster.shares`). Devolve a cópia com o registro
     * novo em `retiredActivities` (JSON do `JSONEncoder` do iOS, guardado como Data no plist).
     */
    fun retire(copy: JsonObject, id: String, roster: Roster): JsonObject {
        val a = activity(copy, id) ?: return copy
        val leagues = posts(copy, id).mapNotNull { it.str("leagueUUID")?.uppercase() }.toSet()
        val shares = roster.shares(leagues, a.str("monsterUUID")?.uppercase())
        if (shares.isEmpty()) return copy
        val settings = ProfileEdits.settings(copy)
        val old = when (val v = settings[BroLedger.RETIRED_KEY]) {
            is ByteArray -> v.decodeToString()
            is String -> v
            else -> null
        }
        val uuid = id.uppercase()
        val kept = old?.let { runCatching { Json.parseToJsonElement(it) as JsonArray }.getOrNull() }.orEmpty()
            .filter { ((it as? JsonObject)?.get("id") as? JsonPrimitive)?.content?.uppercase() != uuid }
        @Suppress("UNCHECKED_CAST")
        val weights = a.str("attributes") ?: (settings[SPLITS_KEY] as? Map<String, Any?>)?.get(uuid) as? String
        val entry = buildJsonObject {
            put("id", uuid)
            put("kind", a.str("kind") ?: ActivityKind.OUTRO.raw)
            put("date", AppleReferenceDate.fromInstant(Instant.parse(a.str("date"))))
            put("minutes", (a["minutes"] as? JsonPrimitive)?.intOrNull ?: 0)
            put("effort", (a["effort"] as? JsonPrimitive)?.intOrNull ?: 5)
            (a["healthType"] as? JsonPrimitive)?.longOrNull?.let { put("healthType", it) }
            weights?.let { put("weights", it) }
            put("owners", buildJsonArray { shares.keys.sorted().forEach { add(JsonPrimitive(it)) } })
            put("shares", buildJsonObject { for ((k, v) in shares) put(k, v) })
        }
        val text = Json.encodeToString(JsonElement.serializer(), JsonArray(kept + entry))
        return ProfileEdits.set(copy, BroLedger.RETIRED_KEY, NSData(text.encodeToByteArray()))
    }

    /**
     * deleteActivity: retira o XP, apaga a atividade e tudo ligado a ela (treino guiado, check-ins e os comentários deles,
     * WOD, percurso). Treino do Saúde/Health Connect fica ignorado (não volta na próxima importação). Check-ins que já
     * estavam no servidor e não saíram de lá agora (`retracted`) vão para a fila `pendingRetractions` (o iPhone apaga).
     */
    fun delete(copy: JsonObject, id: String, roster: Roster, retracted: Set<String> = emptySet()): JsonObject {
        val a = activity(copy, id) ?: return copy
        var out = retire(copy, id, roster)
        val posts = posts(out, id)
        val postIDs = posts.mapNotNull { it.str("uuid")?.uppercase() }.toSet()
        val m = LinkedHashMap<String, JsonElement>(out)
        fun drop(key: String, test: (JsonObject) -> Boolean) {
            val arr = out[key] as? JsonArray ?: return
            m[key] = JsonArray(arr.filter { e -> !(e is JsonObject && test(e)) })
        }
        drop("activities") { same(it.str("uuid"), id) }
        drop("sessions") { same(it.str("activityUUID"), id) }
        drop("checkIns") { same(it.str("activityUUID"), id) }
        drop("comments") { c -> c.str("itemID")?.uppercase() in postIDs }
        drop("wods") { same(it.str("activityUUID"), id) }
        drop("routes") { same(it.str("activityUUID"), id) }
        out = JsonObject(m)

        val settings = ProfileEdits.settings(out)
        val changes = LinkedHashMap<String, Any?>()
        a.str("healthUUID")?.let { h ->
            val ignored = ProfileEdits.strings(settings, IGNORED_KEY)
            if (h !in ignored) changes[IGNORED_KEY] = NSArray(*(ignored + h).map { NSString(it) }.toTypedArray())
        }
        // Só os já publicados (`syncedAt`) e que não foram tirados do servidor aqui
        val queue = posts.filter { it.str("syncedAt") != null && it.str("uuid")?.uppercase() !in retracted }
        if (queue.isNotEmpty()) {
            @Suppress("UNCHECKED_CAST")
            val old = (settings[RETRACTIONS_KEY] as? Map<String, Any?>).orEmpty()
                .mapValues { (_, v) -> (v as? List<*>)?.mapNotNull { it as? String }.orEmpty() }.toMutableMap()
            for (p in queue) {
                val league = p.str("leagueUUID")!!.uppercase()
                old[league] = old[league].orEmpty() + p.str("uuid")!!.uppercase()
            }
            val dict = NSDictionary()
            for ((k, v) in old) dict[k] = NSArray(*v.map { NSString(it) }.toTypedArray())
            changes[RETRACTIONS_KEY] = dict
        }
        @Suppress("UNCHECKED_CAST")
        val splits = settings[SPLITS_KEY] as? Map<String, Any?>
        if (splits != null && splits.keys.any { it.equals(id, true) }) {
            val dict = NSDictionary()
            for ((k, v) in splits) if (!k.equals(id, true) && v is String) dict[k] = NSString(v)
            changes[SPLITS_KEY] = dict
        }
        return if (changes.isEmpty()) out else ProfileEdits.setAll(out, changes)
    }

    data class Change(
        val type: Long,
        val kind: ActivityKind,
        val date: Instant,
        val minutes: Int,
        val effort: Int,
        val note: String,
        val gymUUID: String?,
    )

    /**
     * Editar (LogActivityView.save com `editing`): tipo, dia, duração, esforço, observação e local. A divisão de atributos
     * é refeita (`ActivitySplits.stamp`), a não ser que tipo, duração e esforço continuem iguais.
     */
    fun edit(copy: JsonObject, id: String, c: Change): JsonObject {
        val list = (copy["activities"] as? JsonArray) ?: return copy
        val items = list.map { e ->
            val a = e as? JsonObject
            if (a == null || !same(a.str("uuid"), id)) return@map e
            val unchanged = (a["healthType"] as? JsonPrimitive)?.longOrNull == c.type &&
                (a["minutes"] as? JsonPrimitive)?.intOrNull == c.minutes && (a["effort"] as? JsonPrimitive)?.intOrNull == c.effort
            val meters = (a["meters"] as? JsonPrimitive)?.doubleOrNull
            val split = if (unchanged && a.str("attributes") != null) a.str("attributes")!!
                        else AttributeSplit.encode(AttributeSplit.split(c.kind, c.minutes, c.effort, meters, c.type))
            JsonObject(LinkedHashMap<String, JsonElement>(a).apply {
                put("kind", JsonPrimitive(c.kind.raw))
                put("healthType", JsonPrimitive(c.type))
                put("date", JsonPrimitive(AccountEdits.iso(c.date)))
                put("minutes", JsonPrimitive(c.minutes))
                put("effort", JsonPrimitive(c.effort))
                put("note", JsonPrimitive(c.note))
                put("attributes", JsonPrimitive(split))
                // `healthWritten` fica: tirar daqui faria o iPhone gravar de novo no Saúde sem apagar o antigo (duplicaria)
                if (c.gymUUID != null) put("gymUUID", JsonPrimitive(c.gymUUID)) else remove("gymUUID")
            })
        }
        return JsonObject(LinkedHashMap<String, JsonElement>(copy).apply { put("activities", JsonArray(items)) })
    }
}
