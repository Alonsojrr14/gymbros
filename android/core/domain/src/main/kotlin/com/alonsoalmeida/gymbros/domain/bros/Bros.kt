package com.alonsoalmeida.gymbros.domain.bros

import com.alonsoalmeida.gymbros.domain.MonsterForm
import com.alonsoalmeida.gymbros.domain.Roster
import com.alonsoalmeida.gymbros.domain.Species
import com.alonsoalmeida.gymbros.domain.Stage
import com.alonsoalmeida.gymbros.domain.backup.AccountCopy
import com.alonsoalmeida.gymbros.domain.backup.AccountEdits
import com.alonsoalmeida.gymbros.domain.backup.BackupDto
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.util.Base64

/** BroBook: todas as formas de todas as espécies com arte. Fonte: DexView.swift (`allForms`, `forms`) */
object Dex {
    /** Formas de uma espécie (sem o ovo): normais, híbridas com arte e as Lendas de virada */
    fun forms(species: Species): List<MonsterForm> =
        MonsterForm.all(species.id).filter { it.stage != Stage.EGG } + MonsterForm.hybrids(species.id).filter { it.hasArt } +
            MonsterForm.viradas(species.id)

    /** O ovo conta uma vez */
    fun allForms(): List<MonsterForm> = listOf(MonsterForm.EGG) + Species.catalog.flatMap { forms(it) }

    /**
     * Formas descobertas: as gravadas (`discovered`, ids separados por vírgula) mais o ovo e as evoluções de todos os bros
     * da Box, como o `check` do App.swift faz ao abrir.
     */
    fun discovered(stored: String?, roster: Roster): Set<String> {
        val seen = stored.orEmpty().split(",").filter { it.isNotEmpty() }.toMutableSet()
        seen += MonsterForm.EGG.id
        for (s in roster.snapshots.values) seen += s.evolutions.map { it.form.id }
        return seen
    }
}

/** O que a Box e as trocas leem dos ajustes da conta (`settings` em texto e `accountSettings` em plist) */
data class BroSettings(
    val discovered: String?,
    val revealAll: Boolean,
    val tradeApplied: Set<String>,
    /** X1 → bro que luta nele (`duelMonsters` do DuelStore) */
    val duelMonsters: Map<String, String>,
) {
    companion object {
        fun read(copy: BackupDto?): BroSettings {
            val s = copy?.accountSettings?.let { runCatching { AccountCopy.settings(Base64.getDecoder().decode(it)) }.getOrNull() } ?: emptyMap()
            fun strings(v: Any?) = (v as? List<*>)?.mapNotNull { it as? String }.orEmpty()
            @Suppress("UNCHECKED_CAST")
            val duels = (s["duelMonsters"] as? Map<String, Any?>).orEmpty().mapNotNull { (k, v) -> (v as? String)?.let { k to it.uppercase() } }.toMap()
            return BroSettings(
                discovered = copy?.settings?.get("discovered") ?: s["discovered"] as? String,
                revealAll = s["dexRevealAll"] as? Boolean ?: false,
                tradeApplied = strings(s[TradeLedger.APPLIED_KEY]).toSet(),
                duelMonsters = duels,
            )
        }
    }
}

/** Mudanças da Box na cópia da conta (Monsters.swift `MyBrosList`) */
object BroEdits {
    /** Principal novo: vai nos dois lugares que o iPhone lê (`settings` e os ajustes da conta) */
    fun setMain(copy: JsonObject, uuid: String): JsonObject {
        val id = uuid.uppercase()
        val settings = (copy["settings"] as? JsonObject) ?: JsonObject(emptyMap())
        val withText = JsonObject(LinkedHashMap<String, JsonElement>(copy).apply {
            put("settings", JsonObject(LinkedHashMap<String, JsonElement>(settings).apply { put("mainMonster", JsonPrimitive(id)) }))
        })
        return AccountEdits.updateSettings(withText) { it["mainMonster"] = com.dd.plist.NSString(id) }
    }

    /** Apelido (vazio usa o nome da forma). O iOS tira os espaços das pontas */
    fun rename(copy: JsonObject, uuid: String, name: String): JsonObject {
        val list = (copy["monsters"] as? JsonArray).orEmpty().map { m ->
            val o = m as? JsonObject ?: return@map m
            if ((o["uuid"] as? JsonPrimitive)?.content?.uppercase() != uuid.uppercase()) o
            else JsonObject(LinkedHashMap<String, JsonElement>(o).apply { put("name", JsonPrimitive(name.trim(' ', '\t'))) })
        }
        return JsonObject(LinkedHashMap<String, JsonElement>(copy).apply { put("monsters", JsonArray(list)) })
    }

    /** "Revelar todas" do BroBook (`dexRevealAll`, vai com a conta) */
    fun setRevealAll(copy: JsonObject, on: Boolean): JsonObject =
        AccountEdits.updateSettings(copy) { it["dexRevealAll"] = com.dd.plist.NSNumber(on) }
}
