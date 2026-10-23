package com.alonsoalmeida.gymbros.domain.bros

import com.alonsoalmeida.gymbros.domain.MonsterForm
import com.alonsoalmeida.gymbros.domain.Roster
import com.alonsoalmeida.gymbros.domain.Stage
import com.alonsoalmeida.gymbros.domain.backup.AccountEdits
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** Um bro mudou de fase (o ovo chocou ou evoluiu). Fonte: App.swift (`EvolutionEvent`) */
data class EvolutionEvent(val monster: String, val from: MonsterForm, val to: MonsterForm) {
    val id: String get() = monster + from.id + to.id
    val hatching: Boolean get() = from.stage == Stage.EGG
}

/**
 * O `check` do App.swift: a cada mudança da Box, as formas novas entram no BroBook (`discovered`), cada bro que subiu
 * de fase vira uma cena, e a cópia guarda a forma de agora (`lastFormID`) e a espécie fixada na chocagem (`speciesID`).
 */
object BroEvents {
    data class Result(val events: List<EvolutionEvent>, val copy: JsonObject?)

    private fun str(o: JsonObject, k: String) = (o[k] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.content

    /** `copy` = null quando não há nada a gravar (evita gravar de novo a mesma coisa) */
    fun check(copy: JsonObject, roster: Roster): Result {
        val monsters = (copy["monsters"] as? JsonArray).orEmpty()
        if (monsters.isEmpty()) return Result(emptyList(), null)
        val settings = copy["settings"] as? JsonObject
        val stored = str(settings ?: JsonObject(emptyMap()), "discovered")
            ?: BroSettings.read(runCatching { com.alonsoalmeida.gymbros.domain.backup.AccountCopy.decode(copy) }.getOrNull()).discovered
        val seen = Dex.discovered(stored, roster)
        val discovered = seen.sorted().joinToString(",")

        val events = mutableListOf<EvolutionEvent>()
        var changed = discovered != stored
        val next = monsters.map { e ->
            val o = e as? JsonObject ?: return@map e
            val id = str(o, "uuid")?.uppercase() ?: return@map e
            if (roster.monster(id) == null) return@map e
            val form = roster.snapshot(id).form
            val oldID = str(o, "lastFormID")
            val old = oldID?.let(MonsterForm::byID) ?: MonsterForm.EGG
            if (old != form && form.stage > old.stage) events += EvolutionEvent(id, old, form)
            val out = LinkedHashMap<String, JsonElement>(o)
            out["lastFormID"] = JsonPrimitive(form.id)
            val species = str(o, "speciesID")
            // Fixa a espécie na chocagem; voltou a ser ovo (atividades apagadas): o próximo choco decide de novo
            if (species == null && form.stage > Stage.EGG) out["speciesID"] = JsonPrimitive(form.species)
            if (species != null && form.stage == Stage.EGG) out.remove("speciesID")
            val result = JsonObject(out)
            if (result != o) changed = true
            result
        }
        if (!changed) return Result(events, null)
        val withText = JsonObject(LinkedHashMap<String, JsonElement>(copy).apply {
            put("monsters", JsonArray(next))
            put("settings", JsonObject(LinkedHashMap<String, JsonElement>(settings ?: JsonObject(emptyMap())).apply { put("discovered", JsonPrimitive(discovered)) }))
        })
        return Result(events, AccountEdits.updateSettings(withText) { it["discovered"] = com.dd.plist.NSString(discovered) })
    }
}
