package com.alonsoalmeida.gymbros.domain.profile

import com.alonsoalmeida.gymbros.domain.backup.AccountCopy
import com.alonsoalmeida.gymbros.domain.backup.AccountEdits
import com.dd.plist.NSArray
import com.dd.plist.NSData
import com.dd.plist.NSDictionary
import com.dd.plist.NSNumber
import com.dd.plist.NSObject
import com.dd.plist.NSString
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import java.util.Base64

/**
 * Ajustes da conta mudados pelo Android, gravados como o iPhone grava. Fontes: Services/Backup.swift (`settings`,
 * `typedSettings`, `settingKeys`) e Services/Auth.swift (`AccountData.userKeys`, plist `accountSettings`).
 * Com `accountSettings` presente, o iPhone aplica o plist (que inclui as `settingKeys`); `settings` e `typedSettings`
 * acompanham para backups antigos e para quem lê a cópia sem o plist.
 */
object ProfileEdits {
    /** `Backup.settingKeys` (sem as do BodyProfile, que o Android ainda não edita) */
    val SETTING_KEYS = setOf(
        "trainerName", "monsterNick", "lastFormID", "discovered", "bodyGender", "mainMonster", "profileUsername", "profileBio",
        "exerciseGoals", "autoWarmup", "restNotification", "barWeight", "wodPlan", "personalGoals",
        "profileHeight", "profileBirthYear", "profileGoal", "profileExperience", "profileLastWeight", "goalWeight", "goalWeekly", "goalMinutes",
    )

    /** Valores aceitos: String, Boolean, Int/Long, Double; null tira a chave */
    fun set(copy: JsonObject, key: String, value: Any?): JsonObject = setAll(copy, mapOf(key to value))

    fun setAll(copy: JsonObject, values: Map<String, Any?>): JsonObject {
        var out = AccountEdits.updateSettings(copy) { map ->
            for ((k, v) in values) if (v == null) map.remove(k) else map[k] = ns(v)
        }
        val typed = values.filterKeys { it in SETTING_KEYS }
        if (typed.isEmpty()) return out
        val m = LinkedHashMap<String, JsonElement>(out)
        // `settings`: só textos (`d.string(forKey:)`)
        val settings = LinkedHashMap<String, JsonElement>((out["settings"] as? JsonObject) ?: JsonObject(emptyMap()))
        val typedSettings = LinkedHashMap<String, JsonElement>((out["typedSettings"] as? JsonObject) ?: JsonObject(emptyMap()))
        for ((k, v) in typed) {
            when (v) {
                null -> { settings.remove(k); typedSettings.remove(k) }
                is String -> { settings[k] = JsonPrimitive(v); typedSettings[k] = typedValue("text", JsonPrimitive(v)) }
                is Boolean -> typedSettings[k] = typedValue("bool", JsonPrimitive(v))
                is Number -> typedSettings[k] = typedValue("number", JsonPrimitive(v.toDouble()))
            }
        }
        m["settings"] = JsonObject(settings)
        if (out["typedSettings"] != null || typedSettings.isNotEmpty()) m["typedSettings"] = JsonObject(typedSettings)
        out = JsonObject(m)
        return out
    }

    /** `Backup.Setting` do Swift: `{"text":{"_0":"Zé"}}` */
    private fun typedValue(case: String, v: JsonElement) = buildJsonObject { put(case, buildJsonObject { put("_0", v) }) }

    private fun ns(v: Any): NSObject = when (v) {
        is NSObject -> v
        is String -> NSString(v)
        is Boolean -> NSNumber(v)
        is Int -> NSNumber(v)
        is Long -> NSNumber(v)
        is Double -> NSNumber(v)
        is Float -> NSNumber(v.toDouble())
        is ByteArray -> NSData(v)
        is List<*> -> NSArray(*v.map { ns(it ?: "") }.toTypedArray())
        else -> NSString(v.toString())
    }

    /** Foto do perfil (`profilePhoto`, JPEG em base64 no nível de cima da cópia); null tira */
    fun setPhoto(copy: JsonObject, jpeg: ByteArray?): JsonObject = JsonObject(LinkedHashMap<String, JsonElement>(copy).apply {
        if (jpeg == null) remove("profilePhoto") else put("profilePhoto", JsonPrimitive(Base64.getEncoder().encodeToString(jpeg)))
    })

    /** Ajustes da conta lidos do plist, com o tipo preservado */
    fun settings(copy: JsonObject?): Map<String, Any?> {
        val raw = (copy?.get("accountSettings") as? JsonPrimitive)?.takeIf { it !is JsonNull }?.content ?: return emptyMap()
        return runCatching { AccountCopy.settings(Base64.getDecoder().decode(raw)) }.getOrDefault(emptyMap())
    }

    /** Texto da conta: `settings` (o que o iOS exporta) e, sem ele, o plist */
    fun text(copy: JsonObject?, key: String): String? =
        ((copy?.get("settings") as? JsonObject)?.get(key) as? JsonPrimitive)?.content ?: settings(copy)[key] as? String

    /** Interruptor com padrão (`@AppStorage(..) = padrão`): ausente vale o padrão */
    fun bool(settings: Map<String, Any?>, key: String, default: Boolean): Boolean = when (val v = settings[key]) {
        is Boolean -> v
        is Number -> v.toInt() != 0
        else -> default
    }

    fun int(settings: Map<String, Any?>, key: String, default: Int): Int = (settings[key] as? Number)?.toInt() ?: default

    /** Lista de textos guardada no plist */
    fun strings(settings: Map<String, Any?>, key: String): List<String> = (settings[key] as? List<*>)?.mapNotNull { it as? String }.orEmpty()

    /** Para quem quer o NSDictionary cru (listas de listas, como `pendingRetractions`) */
    fun dict(o: NSObject?): Map<String, List<String>> =
        (o as? NSDictionary)?.hashMap?.mapValues { (_, v) -> AccountEdits.stringList(v) }.orEmpty()
}
