package com.alonsoalmeida.gymbros.domain.bros

import com.alonsoalmeida.gymbros.domain.MonsterForm
import com.alonsoalmeida.gymbros.domain.OwnerXP
import com.alonsoalmeida.gymbros.domain.Roster
import com.alonsoalmeida.gymbros.domain.Stage
import com.alonsoalmeida.gymbros.domain.backup.AccountEdits
import com.alonsoalmeida.gymbros.domain.backup.AppleReferenceDate
import com.alonsoalmeida.gymbros.domain.backup.LeagueDto
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.time.Duration
import java.time.Instant
import java.util.UUID

// Troca de bros entre amigos, 1 por 1: você oferece um bro seu e pede um da pessoa; ela aceita ou recusa em até 48 h.
// Ovos não entram. O bro chega com a forma e o XP que tinha (`SnapshotBase`) e evolui dali com os treinos do novo dono.
// Fonte: ios/GymBros/Trades/Trade.swift. O formato JSON de `TradeBro` é o do `JSONEncoder` do iOS (campos `give`/`get`
// em `trades/{id}` e a lista em `tradeBros/{uid}`).

/** Dono anterior e quanto XP deu, no formato do `OwnerXP` do iOS */
@Serializable
data class TradeOwner(val name: String, val xp: Int) {
    fun toOwnerXP() = OwnerXP(name, xp)
}

/** Um bro como aparece na troca (o seu ou o do amigo). `id` = `Monster.uuid` no aparelho do dono */
@Serializable
data class TradeBro(
    val id: String,
    val name: String,
    val formID: String,
    val xp: Int,
    /** Atributos de tudo o que ele treinou (rawValue → valor) */
    val attributes: Map<String, Double> = emptyMap(),
    /** De quem é o XP: cada dono que o treinou e quanto, do primeiro ao atual (soma = `xp`) */
    val history: List<TradeOwner> = emptyList(),
) {
    val form: MonsterForm get() = MonsterForm.byID(formID) ?: MonsterForm.EGG
    val isEgg: Boolean get() = form.stage == Stage.EGG
}

data class TradePerson(val id: String, val name: String, val formID: String) {
    val form: MonsterForm get() = MonsterForm.byID(formID) ?: MonsterForm.EGG
}

enum class TradeAnswer(val raw: String) {
    ACCEPTED("accepted"), DECLINED("declined"), CANCELED("canceled");

    companion object {
        fun of(raw: String?): TradeAnswer? = entries.firstOrNull { it.raw == raw }
    }
}

/** Proposta: `from` dá `give` e recebe `get` de `to`. Você é sempre o id "me" */
data class TradeProposal(
    val id: String,
    val from: TradePerson,
    val to: TradePerson,
    val give: TradeBro,
    val get: TradeBro,
    val createdAt: Instant,
    val answer: TradeAnswer? = null,
    val answeredAt: Instant? = null,
) {
    val expiresAt: Instant get() = createdAt.plus(WINDOW)
    fun isPending(now: Instant): Boolean = answer == null && now < expiresAt
    val isDone: Boolean get() = answer == TradeAnswer.ACCEPTED

    /** Do ponto de vista de "me": o que eu dou, o que recebo e com quem */
    val mine: TradeBro get() = if (from.id == ME) give else get
    val theirs: TradeBro get() = if (from.id == ME) get else give
    val friend: TradePerson get() = if (from.id == ME) to else from

    companion object {
        const val ME = "me"
        val WINDOW: Duration = Duration.ofHours(48)
    }
}

/** Por que um bro seu não pode entrar numa troca agora (TradeRefusal do iOS) */
sealed class TradeRefusal(val message: String, val tag: String) {
    data object Egg : TradeRefusal("Ovos não entram em troca.", "Ovo")
    data object Main : TradeRefusal("É o seu principal. Escolha outro principal na Box antes de trocar.", "Principal")
    data class League(val name: String) : TradeRefusal("Representa você na liga $name.", "Em liga")
    data object InDuel : TradeRefusal("Está num X1 agora.", "Em X1")
    data object Busy : TradeRefusal("Já está numa troca em andamento.", "Em troca")
    data object NotPending : TradeRefusal("Essa troca não está mais aberta.", "Indisponível")
    data object Gone : TradeRefusal("Esse bro não está mais com você.", "Indisponível")
}

class TradeException(val refusal: TradeRefusal) : Exception(refusal.message)

/** Um bro seu como entra na troca, com o que precisa para as regras */
data class MyTradeBro(val uuid: String, val isStarter: Boolean, val lastFormID: String?, val bro: TradeBro)

/** Regras das trocas sobre a lista do servidor. Fonte: Trade.swift (`TradeStore`) */
object TradeRules {
    private fun same(a: String, b: String) = a.equals(b, ignoreCase = true)

    fun incoming(all: List<TradeProposal>, now: Instant): List<TradeProposal> =
        all.filter { it.to.id == TradeProposal.ME && it.isPending(now) }.sortedBy { it.createdAt }

    fun sent(all: List<TradeProposal>, now: Instant): List<TradeProposal> =
        all.filter { it.from.id == TradeProposal.ME && it.isPending(now) }.sortedByDescending { it.createdAt }

    /** Trocas que você propôs, o amigo aceitou e falta receber: o bro só chega quando você toca em Receber */
    fun ready(all: List<TradeProposal>, applied: Set<String>): List<TradeProposal> =
        all.filter { it.isDone && it.from.id == TradeProposal.ME && it.id !in applied }.sortedBy { it.answeredAt ?: it.createdAt }

    fun done(all: List<TradeProposal>, applied: Set<String>): List<TradeProposal> {
        val waiting = ready(all, applied).map { it.id }.toSet()
        return all.filter { it.isDone && it.id !in waiting }.sortedByDescending { it.answeredAt ?: it.createdAt }
    }

    /** Trocas que você aceitou e ainda não mudaram a sua Box (as que você propôs esperam o Receber) */
    fun toApply(all: List<TradeProposal>, applied: Set<String>): List<TradeProposal> =
        all.filter { it.isDone && it.to.id == TradeProposal.ME && it.id !in applied }

    /** Seus bros como entram na troca (forma e XP de agora), na ordem da Box */
    fun myBros(roster: Roster, lastForms: Map<String, String?>, trainerName: String): List<MyTradeBro> {
        val myName = trainerName.ifEmpty { "Você" }
        return roster.monsters.map { m ->
            val s = roster.snapshot(m.uuid)
            // O XP vai separado por dono: os de antes (se ele veio de troca) e o seu
            val history = s.inherited.map { TradeOwner(it.name, it.xp) } + if (s.myXP > 0) listOf(TradeOwner(myName, s.myXP)) else emptyList()
            MyTradeBro(m.uuid, m.isStarter, lastForms[m.uuid],
                       TradeBro(m.uuid, m.displayName(s.form), s.form.id, s.totalXP,
                                s.lifetimeAttributes.entries.associate { it.key.raw to it.value }, history))
        }
    }

    /** Por que este bro seu não pode entrar numa troca agora; null = pode */
    fun refusal(m: MyTradeBro, mainID: String?, leagues: List<LeagueDto>, busyFighters: Set<String>, all: List<TradeProposal>,
                applied: Set<String>, now: Instant): TradeRefusal? {
        if ((m.lastFormID?.let(MonsterForm::byID) ?: MonsterForm.EGG).stage == Stage.EGG) return TradeRefusal.Egg
        if ((mainID != null && same(m.uuid, mainID)) || (mainID == null && m.isStarter)) return TradeRefusal.Main
        leagues.firstOrNull { l -> l.monsterUUID?.let { same(it, m.uuid) } == true && !l.isPastSeason }?.let { return TradeRefusal.League(it.name) }
        if (busyFighters.any { same(it, m.uuid) }) return TradeRefusal.InDuel
        if (sent(all, now).any { same(it.give.id, m.uuid) }) return TradeRefusal.Busy
        // Aceita e ainda não recebida: ele já é do amigo
        if (ready(all, applied).any { same(it.give.id, m.uuid) }) return TradeRefusal.Busy
        return null
    }

    /** Lista publicada em `tradeBros/{uid}` (ordenada pelo id, como o iOS) */
    fun publishedJson(mine: List<TradeBro>): String = json.encodeToString(kotlinx.serialization.builtins.ListSerializer(TradeBro.serializer()), mine.sortedBy { it.id })

    val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    fun encode(b: TradeBro): String = json.encodeToString(TradeBro.serializer(), b)
    fun decode(raw: String?): TradeBro? = raw?.let { runCatching { json.decodeFromString(TradeBro.serializer(), it) }.getOrNull() }
    fun decodeList(raw: String?): List<TradeBro> =
        raw?.let { runCatching { json.decodeFromString(kotlinx.serialization.builtins.ListSerializer(TradeBro.serializer()), it) }.getOrNull() }.orEmpty()
}

/**
 * O que as trocas mudam na cópia da conta (TradeLedger do iOS): de onde parte quem chegou (`tradeBases`, JSON em Data),
 * quem saiu (`tradeGone`) e as trocas já aplicadas (`tradeApplied`), nos ajustes da conta. O bro que sai some de
 * `monsters`; o que chega entra com a forma e a espécie dele.
 */
object TradeLedger {
    const val BASES_KEY = "tradeBases"
    const val GONE_KEY = "tradeGone"
    const val APPLIED_KEY = "tradeApplied"

    /** Troca aceita aplicada na cópia, uma vez só por troca. null = nada a fazer (não aceita ou já aplicada) */
    data class Applied(val copy: JsonObject, val broUUID: String)

    fun apply(copy: JsonObject, p: TradeProposal, applied: Set<String>, now: Instant, newUUID: String = UUID.randomUUID().toString().uppercase()): Applied? {
        if (!p.isDone || p.id in applied) return null
        val leavingID = p.mine.id.uppercase()
        val monsters = (copy["monsters"] as? JsonArray).orEmpty()
        val leaving = monsters.any { (((it as? JsonObject)?.get("uuid") as? JsonPrimitive)?.content)?.uppercase() == leavingID }
        val got = p.theirs
        val createdAt = p.answeredAt ?: now
        val bro = buildJsonObject {
            put("uuid", newUUID)
            put("name", "")
            put("createdAt", AccountEdits.iso(createdAt))
            put("isStarter", false)
            put("lastFormID", got.formID)
            put("speciesID", got.form.species)
        }
        val kept = monsters.filterNot { (((it as? JsonObject)?.get("uuid") as? JsonPrimitive)?.content)?.uppercase() == leavingID }
        val withBro = JsonObject(LinkedHashMap<String, JsonElement>(copy).apply { put("monsters", JsonArray(kept + bro)) })
        val owners = got.history.ifEmpty { listOf(TradeOwner(p.friend.name, got.xp)) }
        val base = buildJsonObject {
            put("formID", got.formID)
            put("xp", got.xp)
            put("attributes", buildJsonObject { for ((k, v) in got.attributes) put(k, v) })
            put("date", AppleReferenceDate.fromInstant(createdAt))
            put("history", buildJsonArray { for (o in owners) add(buildJsonObject { put("name", o.name); put("xp", o.xp) }) })
        }
        val out = AccountEdits.updateSettings(withBro) { s ->
            if (leaving) s[GONE_KEY] = AccountEdits.nsList((AccountEdits.stringList(s[GONE_KEY]) + leavingID).distinct())
            val old = when (val v = s[BASES_KEY]) {
                is com.dd.plist.NSData -> v.bytes().decodeToString()
                is com.dd.plist.NSString -> v.content
                else -> null
            }
            val bases = old?.let { runCatching { Json.parseToJsonElement(it) as JsonObject }.getOrNull() } ?: JsonObject(emptyMap())
            val next = JsonObject(LinkedHashMap<String, JsonElement>(bases).apply { put(newUUID, base) })
            s[BASES_KEY] = com.dd.plist.NSData(Json.encodeToString(JsonElement.serializer(), next).encodeToByteArray())
            s[APPLIED_KEY] = AccountEdits.nsList((AccountEdits.stringList(s[APPLIED_KEY]) + p.id).distinct())
        }
        return Applied(out, newUUID)
    }
}
