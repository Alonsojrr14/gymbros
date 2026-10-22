package com.alonsoalmeida.gymbros.domain.backup

import com.dd.plist.BinaryPropertyListWriter
import com.dd.plist.NSArray
import com.dd.plist.NSData
import com.dd.plist.NSDate
import com.dd.plist.NSDictionary
import com.dd.plist.NSNumber
import com.dd.plist.NSObject
import com.dd.plist.NSString
import com.dd.plist.PropertyListParser
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.math.BigDecimal
import java.time.Instant
import java.util.Base64

/**
 * Mesclagem da cópia da conta entre aparelhos (IOS-08), igual a ios/GymBros/Services/BackupMerge.swift e provada pelo
 * vetor M. Três vias: a cópia deste aparelho, a da nuvem e a base (a última que este aparelho enviou ou recebeu).
 * Trabalha sobre o JSON inteiro: campo que o Android ainda não conhece passa pela mesclagem sem se perder.
 */
object BackupMerge {
    /** Campos de foto: a cópia da nuvem vai sem eles, então não contam como mudança e a foto local fica */
    val photoKeys = setOf("photo", "photoFront", "photoSide", "extraPhotos")
    /** Listas que se mesclam por outra chave que não o `uuid` */
    val listKeys = mapOf("notes" to "exerciseID")
    /** Ajustes que são registros (só crescem): une os dois lados em vez de escolher um */
    val registryKeys = setOf("retiredActivities", "duelScoreRecords", "tradeBases", "tradeGone", "tradeApplied")

    data class Result(val backup: JsonObject, val conflicts: List<String>)

    fun merge(local: JsonObject, remote: JsonObject, base: JsonObject?): Result {
        val newerIsLocal = seconds(local) >= seconds(remote)
        val out = LinkedHashMap<String, JsonElement>(local)
        val conflicts = mutableListOf<String>()
        for (key in (local.keys + remote.keys)) {
            val lv = local[key]
            val rv = remote[key]
            val bv = base?.get(key)
            when {
                key == "accountSettings" -> put(out, key, mergeSettingsPlist(lv.string(), rv.string(), bv.string(), newerIsLocal)?.let(::JsonPrimitive))
                key == "settings" || key == "typedSettings" ->
                    put(out, key, mergeDict(lv as? JsonObject, rv as? JsonObject, bv as? JsonObject, newerIsLocal, ::canonical, ::unionJson)?.let(::JsonObject))
                lv is JsonArray || rv is JsonArray -> {
                    // Listas de itens (atividades, rotinas, sessões, ligas, bros, medidas, check-ins…): por item
                    val id = listKeys[key] ?: "uuid"
                    val (items, c) = mergeItems(objects(lv), objects(rv), (bv as? JsonArray)?.let { objects(it) }, id, newerIsLocal)
                    out[key] = JsonArray(items)
                    conflicts += c.map { "$key:$it" }
                }
                key == "exportedAt" -> put(out, key, if (newerIsLocal) lv else rv)
                lv == null || lv is JsonNull -> put(out, key, rv)
                // Outros campos (versão, foto do perfil, estado de sincronização): ficam os deste aparelho
            }
        }
        return Result(JsonObject(out), conflicts.sorted())
    }

    private fun put(out: MutableMap<String, JsonElement>, key: String, v: JsonElement?) {
        if (v == null || v is JsonNull) out.remove(key) else out[key] = v
    }

    private fun JsonElement?.string(): String? = (this as? JsonPrimitive)?.takeIf { it.isString }?.content

    private fun objects(e: JsonElement?): List<JsonObject> = (e as? JsonArray)?.filterIsInstance<JsonObject>() ?: emptyList()

    /** Segundos inteiros do `exportedAt` (o arquivo guarda sem fração) */
    private fun seconds(b: JsonObject): Long = b["exportedAt"].string()?.let { runCatching { Instant.parse(it).epochSecond }.getOrNull() } ?: 0

    // Itens

    /** Três vias por item. Ordem: a deste aparelho, depois os novos da nuvem na ordem dela. */
    fun mergeItems(local: List<JsonObject>, remote: List<JsonObject>, base: List<JsonObject>?, id: String,
                   newerIsLocal: Boolean): Pair<List<JsonObject>, List<String>> {
        fun index(list: List<JsonObject>): Map<String, JsonObject> {
            val m = LinkedHashMap<String, JsonObject>()
            for (i in list) i[id].string()?.let { if (it !in m) m[it] = i }
            return m
        }
        val li = index(local)
        val ri = index(remote)
        val bi = base?.let(::index) ?: emptyMap()
        val hasBase = base != null
        val out = mutableListOf<JsonObject>()
        val conflicts = mutableListOf<String>()
        val order = local.mapNotNull { it[id].string() } + remote.mapNotNull { it[id].string() }.filter { it !in li }
        for (key in order) {
            val l = li[key]
            val r = ri[key]
            val b = bi[key]
            when {
                l != null && r != null -> when {
                    same(l, r) || (b != null && same(r, b)) -> out += l
                    b != null && same(l, b) -> out += withPhotos(r, l)
                    else -> {
                        // Mudou dos dois lados (ou sem base): fica o do aparelho com a cópia mais nova
                        out += if (newerIsLocal) l else withPhotos(r, l)
                        conflicts += key
                    }
                }
                // Só aqui: novo deste aparelho, ou apagado no outro (some, a menos que tenha mudado aqui depois)
                l != null -> if (!hasBase || b == null || !same(l, b)) out += l
                // Só na nuvem: novo do outro aparelho, ou apagado aqui (não volta, a menos que tenha mudado lá)
                r != null -> if (!hasBase || b == null || !same(r, b)) out += r
            }
        }
        return out to conflicts
    }

    /** Iguais fora as fotos (a cópia da nuvem não tem) */
    fun same(a: JsonObject, b: JsonObject): Boolean =
        canonical(JsonObject(a.filterKeys { it !in photoKeys })) == canonical(JsonObject(b.filterKeys { it !in photoKeys }))

    private fun withPhotos(item: JsonObject, local: JsonObject): JsonObject {
        val out = LinkedHashMap<String, JsonElement>(item)
        for (k in photoKeys) {
            if (out[k] == null || out[k] is JsonNull) local[k]?.takeIf { it !is JsonNull }?.let { out[k] = it }
        }
        return JsonObject(out)
    }

    // Ajustes

    fun <T> mergeDict(l: Map<String, T>?, r: Map<String, T>?, b: Map<String, T>?, newerIsLocal: Boolean,
                      canon: (T) -> String, union: (T?, T?) -> T?): Map<String, T>? {
        if (l == null && r == null) return null
        val lm = l ?: emptyMap()
        val rm = r ?: emptyMap()
        val out = LinkedHashMap<String, T>()
        for (key in (lm.keys + rm.keys)) {
            val lv = lm[key]
            val rv = rm[key]
            val bv = b?.get(key)
            if (key in registryKeys) {
                union(lv, rv)?.let { out[key] = it }
                continue
            }
            when {
                lv != null && rv != null -> out[key] = when {
                    canon(lv) == canon(rv) || (bv != null && canon(bv) == canon(rv)) -> lv
                    bv != null && canon(bv) == canon(lv) -> rv
                    else -> if (newerIsLocal) lv else rv
                }
                // Só aqui: novo, ou apagado no outro aparelho sem mudança aqui
                lv != null -> if (bv == null || canon(bv) != canon(lv)) out[key] = lv
                rv != null -> if (bv == null || canon(bv) != canon(rv)) out[key] = rv
            }
        }
        return out
    }

    /** `accountSettings`: plist binário em base64 no JSON */
    private fun mergeSettingsPlist(l: String?, r: String?, b: String?, newerIsLocal: Boolean): String? {
        fun dict(s: String?): Map<String, NSObject>? {
            val bytes = s?.let { runCatching { Base64.getDecoder().decode(it) }.getOrNull() } ?: return null
            return (PropertyListParser.parse(bytes) as? NSDictionary)?.hashMap
        }
        val merged = mergeDict(dict(l), dict(r), dict(b), newerIsLocal, ::canonical, ::unionPlist) ?: return null
        val out = NSDictionary()
        for ((k, v) in merged) out[k] = v
        return Base64.getEncoder().encodeToString(BinaryPropertyListWriter.writeToArray(out))
    }

    /** União de registros: listas sem repetir, dicionários chave a chave (o deste aparelho primeiro) */
    private fun unionJson(a: JsonElement?, b: JsonElement?): JsonElement? = when {
        a is JsonArray && b is JsonArray -> {
            val seen = a.map(::canonical).toMutableSet()
            JsonArray(a + b.filter { seen.add(canonical(it)) })
        }
        a is JsonObject && b is JsonObject -> JsonObject(LinkedHashMap<String, JsonElement>(b).apply { putAll(a) })
        else -> a ?: b
    }

    private fun unionPlist(a: NSObject?, b: NSObject?): NSObject? = when {
        a is NSArray && b is NSArray -> {
            val seen = a.array.map(::canonical).toMutableSet()
            NSArray(*(a.array.toList() + b.array.filter { seen.add(canonical(it)) }).toTypedArray())
        }
        a is NSDictionary && b is NSDictionary -> NSDictionary().also { d ->
            for ((k, v) in b.hashMap) d[k] = v
            for ((k, v) in a.hashMap) d[k] = v
        }
        else -> a ?: b
    }

    // Texto estável para comparar valores (chaves ordenadas)

    fun canonical(v: JsonElement): String = when (v) {
        is JsonNull -> "null"
        is JsonObject -> "{" + v.keys.sorted().joinToString(",") { "$it:${canonical(v[it]!!)}" } + "}"
        is JsonArray -> "[" + v.joinToString(",") { canonical(it) } + "]"
        is JsonPrimitive -> when {
            v.isString -> v.content
            v.content == "true" || v.content == "false" -> v.content
            // 80 e 80.0 são o mesmo número (o NSNumber do iOS escreve os dois como "80")
            else -> runCatching { BigDecimal(v.content).stripTrailingZeros().toPlainString() }.getOrDefault(v.content)
        }
    }

    fun canonical(v: NSObject): String = when (v) {
        is NSDate -> "date:${v.date.time / 1000.0}"
        is NSData -> "data:" + Base64.getEncoder().encodeToString(v.bytes())
        is NSDictionary -> "{" + v.hashMap.keys.sorted().joinToString(",") { "$it:${canonical(v.hashMap[it]!!)}" } + "}"
        is NSArray -> "[" + v.array.joinToString(",") { canonical(it) } + "]"
        is NSNumber -> when (v.type()) {
            NSNumber.BOOLEAN -> if (v.boolValue()) "true" else "false"
            NSNumber.INTEGER -> v.longValue().toString()
            else -> BigDecimal(v.doubleValue()).stripTrailingZeros().toPlainString()
        }
        is NSString -> v.content
        else -> v.toString()
    }
}
