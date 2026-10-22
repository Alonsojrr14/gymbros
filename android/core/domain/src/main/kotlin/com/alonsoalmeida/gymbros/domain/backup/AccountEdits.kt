package com.alonsoalmeida.gymbros.domain.backup

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.UUID

/**
 * Mudanças que o Android faz na cópia da conta, direto no JSON do `Backup` (o resto do JSON fica intacto).
 * Os campos seguem os DTOs de ios/GymBros/Services/Backup.swift: o iPhone lê o que o Android grava.
 */
object AccountEdits {
    fun iso(i: Instant): String = DateTimeFormatter.ISO_INSTANT.format(i.truncatedTo(ChronoUnit.SECONDS))

    /** Cópia nova (conta sem dados): o mínimo que o `Backup` do iOS exige, com o bro inicial (`Roster.ensureStarter`) */
    fun empty(trainerName: String, now: Instant): JsonObject = buildJsonObject {
        put("version", 1)
        put("exportedAt", iso(now))
        put("settings", buildJsonObject { if (trainerName.isNotEmpty()) put("trainerName", trainerName) })
        put("activities", JsonArray(emptyList()))
        put("routines", JsonArray(emptyList()))
        put("sessions", JsonArray(emptyList()))
        put("customExercises", JsonArray(emptyList()))
        put("monsters", JsonArray(listOf(starter())))
    }

    /** O bro do começo: ovo, criado "no início dos tempos" como no iOS (`Date.distantPast`) */
    fun starter(): JsonObject = buildJsonObject {
        put("uuid", UUID.randomUUID().toString().uppercase())
        put("name", "")
        put("createdAt", "0001-01-01T00:00:00Z")
        put("isStarter", true)
        put("lastFormID", "egg")
    }

    data class NewActivity(
        val kind: String,
        val date: Instant,
        val minutes: Int,
        val effort: Int,
        val note: String,
        /** Tipo exato (`HKWorkoutActivityType.rawValue`), como o iOS grava em `healthType` */
        val type: Long,
        /** Divisão do XP calculada ao salvar (`AttributeSplit.encode`) */
        val attributes: String,
        val gymUUID: String? = null,
        val id: String = UUID.randomUUID().toString().uppercase(),
    )

    /** Atividade nova (LogActivityView.save): o XP vai para o bro principal gravado (`MainMonster.id`) */
    fun addActivity(copy: JsonObject, a: NewActivity): JsonObject {
        val main = ((copy["settings"] as? JsonObject)?.get("mainMonster") as? JsonPrimitive)?.content
        val item = buildJsonObject {
            put("uuid", a.id)
            put("kind", a.kind)
            put("date", iso(a.date))
            put("minutes", a.minutes)
            put("effort", a.effort)
            put("note", a.note)
            put("healthType", a.type)
            put("attributes", a.attributes)
            if (main != null) put("monsterUUID", main)
            if (a.gymUUID != null) put("gymUUID", a.gymUUID)
        }
        val list = (copy["activities"] as? JsonArray).orEmpty()
        val out = LinkedHashMap<String, JsonElement>(copy)
        out["activities"] = JsonArray(list + item)
        if ((copy["monsters"] as? JsonArray).isNullOrEmpty()) out["monsters"] = JsonArray(listOf(starter()))
        return JsonObject(out)
    }
}
