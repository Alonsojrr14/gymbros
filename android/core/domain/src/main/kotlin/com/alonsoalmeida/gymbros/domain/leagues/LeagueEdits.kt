package com.alonsoalmeida.gymbros.domain.leagues

import com.alonsoalmeida.gymbros.domain.backup.AccountCopy
import com.alonsoalmeida.gymbros.domain.backup.AccountEdits
import com.dd.plist.NSArray
import com.dd.plist.NSData
import com.dd.plist.NSDictionary
import com.dd.plist.NSString
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.time.Instant
import java.util.UUID

/**
 * Mudanças das ligas na cópia da conta, direto no JSON do `Backup` (o resto fica intacto). Os campos seguem os DTOs de
 * Backup.swift: o iPhone lê o que o Android grava. Ids em UUID maiúsculo; datas ISO 8601 sem fração.
 */
object LeagueEdits {
    fun newID(): String = UUID.randomUUID().toString().uppercase()

    /** Lê as partes das ligas da cópia */
    fun read(copy: JsonObject?): LeaguesCopy =
        copy?.let { runCatching { AccountCopy.json.decodeFromJsonElement(LeaguesCopy.serializer(), it) }.getOrNull() } ?: LeaguesCopy()

    private fun list(copy: JsonObject, key: String): List<JsonElement> = (copy[key] as? JsonArray).orEmpty()

    private fun with(copy: JsonObject, key: String, items: List<JsonElement>): JsonObject =
        JsonObject(LinkedHashMap<String, JsonElement>(copy).apply { put(key, JsonArray(items)) })

    private fun uuidOf(e: JsonElement) = ((e as? JsonObject)?.get("uuid") as? JsonPrimitive)?.content?.uppercase()

    /** Valores: String, Boolean, Number, Instant (vira ISO), JsonElement; null tira o campo */
    private fun put(m: MutableMap<String, JsonElement>, k: String, v: Any?) {
        when (v) {
            null -> m.remove(k)
            is JsonElement -> if (v is JsonNull) m.remove(k) else m[k] = v
            is String -> m[k] = JsonPrimitive(v)
            is Boolean -> m[k] = JsonPrimitive(v)
            is Number -> m[k] = JsonPrimitive(v)
            is Instant -> m[k] = JsonPrimitive(AccountEdits.iso(v))
            else -> error("tipo não suportado: $k")
        }
    }

    /** Acrescenta um item novo (array criado se faltar) */
    fun add(copy: JsonObject, key: String, fields: Map<String, Any?>): JsonObject {
        val m = LinkedHashMap<String, JsonElement>()
        for ((k, v) in fields) put(m, k, v)
        return with(copy, key, list(copy, key) + JsonObject(m))
    }

    /** Muda campos de um item pelo uuid, preservando os outros */
    fun update(copy: JsonObject, key: String, uuid: String, fields: Map<String, Any?>): JsonObject =
        with(copy, key, list(copy, key).map { e ->
            if (uuidOf(e) != uuid.uppercase()) e
            else JsonObject(LinkedHashMap((e as JsonObject)).apply { for ((k, v) in fields) put(this, k, v) })
        })

    fun updateMany(copy: JsonObject, key: String, ids: Set<String>, fields: Map<String, Any?>): JsonObject {
        val up = ids.map { it.uppercase() }.toSet()
        return with(copy, key, list(copy, key).map { e ->
            if (uuidOf(e) !in up) e else JsonObject(LinkedHashMap((e as JsonObject)).apply { for ((k, v) in fields) put(this, k, v) })
        })
    }

    fun remove(copy: JsonObject, key: String, ids: Set<String>): JsonObject {
        val up = ids.map { it.uppercase() }.toSet()
        return with(copy, key, list(copy, key).filter { uuidOf(it) !in up })
    }

    /** Remove itens que casam com o filtro */
    fun removeWhere(copy: JsonObject, key: String, match: (JsonObject) -> Boolean): JsonObject =
        with(copy, key, list(copy, key).filterNot { (it as? JsonObject)?.let(match) == true })

    /** Ovo novo para representar você numa liga (ModelContext.representative) */
    fun addEgg(copy: JsonObject, now: Instant): Pair<JsonObject, String> {
        val id = newID()
        return add(copy, "monsters", mapOf("uuid" to id, "name" to "", "createdAt" to now, "isStarter" to false, "lastFormID" to "egg")) to id
    }

    // MARK: Ajustes da conta (plist)

    /** Check-ins publicados que precisam sair do servidor (`pendingRetractions`, liga → ids), como no iPhone */
    fun retractions(settings: Map<String, Any?>): Map<String, List<String>> =
        (settings["pendingRetractions"] as? Map<*, *>)?.mapNotNull { (k, v) ->
            (k as? String)?.let { it to (v as? List<*>)?.mapNotNull { x -> x as? String }.orEmpty() }
        }?.toMap().orEmpty()

    fun setRetractions(copy: JsonObject, value: Map<String, List<String>>): JsonObject = AccountEdits.updateSettings(copy) { m ->
        val d = NSDictionary()
        for ((k, v) in value) if (v.isNotEmpty()) d[k] = NSArray(*v.map { NSString(it) }.toTypedArray())
        if (d.count() == 0) m.remove("pendingRetractions") else m["pendingRetractions"] = d
    }

    data class PendingJoin(val code: String, val name: String, val emoji: String, val date: Instant, val monsterUUID: String?)

    /** Pedidos de entrada esperando o dono (`league.pendingJoins`: JSON de `[PendingJoin]` em Data, datas do iOS) */
    fun pendingJoins(settings: Map<String, Any?>): List<PendingJoin> {
        val raw = (settings["league.pendingJoins"] as? ByteArray)?.decodeToString() ?: return emptyList()
        val arr = runCatching { J.json.parseToJsonElement(raw) as JsonArray }.getOrNull() ?: return emptyList()
        return arr.mapNotNull { e ->
            val o = e as? JsonObject ?: return@mapNotNull null
            PendingJoin(J.str(o, "code") ?: return@mapNotNull null, J.str(o, "name") ?: "", J.str(o, "emoji") ?: "🏆",
                        J.date(o, "date") ?: Instant.now(), J.str(o, "monsterUUID"))
        }
    }

    fun setPendingJoins(copy: JsonObject, list: List<PendingJoin>): JsonObject = AccountEdits.updateSettings(copy) { m ->
        val arr = JsonArray(list.map { p ->
            J.sorted(buildMap {
                put("code", JsonPrimitive(p.code)); put("name", JsonPrimitive(p.name)); put("emoji", JsonPrimitive(p.emoji))
                put("date", J.date(p.date)); p.monsterUUID?.let { put("monsterUUID", JsonPrimitive(it)) }
            })
        })
        m["league.pendingJoins"] = NSData(arr.toString().encodeToByteArray())
    }
}
