package com.alonsoalmeida.gymbros.domain

import com.alonsoalmeida.gymbros.domain.backup.BackupMerge
import com.dd.plist.NSDictionary
import com.dd.plist.PropertyListParser
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import java.util.Base64

/** Grupo M: a mesclagem da cópia da conta dá o mesmo resultado que a do iPhone, caso a caso */
class GroupMTest {
    private val m = Json.parseToJsonElement(javaClass.getResource("/gymbros-golden-M.json")!!.readText()).jsonObject

    private fun parse(e: JsonElement): JsonObject = Json.parseToJsonElement(e.jsonPrimitive.content).jsonObject

    /** O iOS passa o resultado pelo Backup (some o que é nulo); a cópia de ajustes compara pelo conteúdo do plist */
    private fun normal(e: JsonElement): JsonElement = when (e) {
        is JsonObject -> JsonObject(e.filterValues { it !is JsonNull }.mapValues { (k, v) ->
            if (k == "accountSettings" && v is JsonPrimitive) {
                val d = PropertyListParser.parse(Base64.getDecoder().decode(v.content)) as NSDictionary
                JsonPrimitive(BackupMerge.canonical(d))
            } else normal(v)
        })
        is JsonArray -> JsonArray(e.map(::normal))
        else -> e
    }

    @Test
    fun cases() {
        for ((k, c) in m["cases"]!!.jsonArray.map { it.jsonObject }.withIndex()) {
            val base = c["base"]!!.takeIf { it !is JsonNull }?.let(::parse)
            val out = BackupMerge.merge(parse(c["local"]!!), parse(c["remote"]!!), base)
            assertEquals(c["conflicts"]!!.jsonArray.map { it.jsonPrimitive.content }, out.conflicts, "caso $k")
            assertEquals(BackupMerge.canonical(normal(parse(c["merged"]!!))), BackupMerge.canonical(normal(out.backup)), "caso $k")
        }
    }
}
