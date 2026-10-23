package com.alonsoalmeida.gymbros.data.train

import android.content.Context
import com.alonsoalmeida.gymbros.domain.train.Wod
import com.alonsoalmeida.gymbros.domain.train.WodFormat
import com.alonsoalmeida.gymbros.domain.train.WodLevelOption
import com.alonsoalmeida.gymbros.domain.train.WodLoad
import com.alonsoalmeida.gymbros.domain.train.WodPart
import com.alonsoalmeida.gymbros.domain.train.WodRunState
import com.alonsoalmeida.gymbros.domain.train.WodSet
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put
import java.time.Instant

/**
 * WOD em andamento fora da tela do cronômetro (WodRun.swift): dá para minimizar e continuar, mesmo se o app fechar.
 * No iOS fica no aparelho (`activeWod` não vai na cópia da conta); aqui também, nas preferências do app.
 * Também guarda o nível de WOD preferido (`wodLevel`) e a barra do box (`wodBarWeight`), locais como no iPhone.
 */
object WodRunStore {
    private const val PREFS = "gymbros-train"
    private val _state = MutableStateFlow<WodRunState?>(null)
    val state: StateFlow<WodRunState?> = _state.asStateFlow()
    private var loaded = false

    private fun prefs(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun load(c: Context) {
        if (loaded) return
        loaded = true
        _state.value = prefs(c).getString("activeWod", null)?.let { runCatching { decode(Json.parseToJsonElement(it) as JsonObject) }.getOrNull() }
    }

    fun set(c: Context, s: WodRunState?) {
        _state.value = s
        prefs(c).edit().apply { if (s == null) remove("activeWod") else putString("activeWod", encode(s).toString()) }.apply()
    }

    /** Abre este WOD; se já tem um em andamento, é ele que continua (um treino por vez) */
    fun open(c: Context, wod: Wod) { load(c); if (_state.value == null) set(c, WodRunState(wod, Instant.now())) }

    fun preferredLevel(c: Context): String? = prefs(c).getString("wodLevel", null)
    fun setPreferredLevel(c: Context, v: String) = prefs(c).edit().putString("wodLevel", v).apply()
    fun bar(c: Context): Double = prefs(c).getFloat("wodBarWeight", 20f).toDouble()
    fun setBar(c: Context, v: Double) = prefs(c).edit().putFloat("wodBarWeight", v.toFloat()).apply()

    /** Sair da conta: o WOD aberto é da conta que saiu */
    fun clear(c: Context) { set(c, null) }

    private fun strings(l: List<String>) = JsonArray(l.map { JsonPrimitive(it) })
    private fun lines(e: JsonElement?) = (e as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.content }.orEmpty()
    private fun ms(i: Instant?) = i?.toEpochMilli()?.let { JsonPrimitive(it) }
    private fun time(o: JsonObject, k: String) = (o[k] as? JsonPrimitive)?.longOrNull?.let { Instant.ofEpochMilli(it) }

    private fun wodJson(w: Wod): JsonObject = buildJsonObject {
        put("id", w.id); put("name", w.name); put("category", w.category); put("format", w.format.toJson()); put("lines", strings(w.lines))
        put("exercises", strings(w.exercises))
        put("parts", JsonArray(w.parts.map { buildJsonObject { put("title", it.title); put("lines", strings(it.lines)) } }))
        w.levels?.let { l -> put("levels", JsonArray(l.map { buildJsonObject { put("title", it.title); put("format", it.format.toJson()); put("lines", strings(it.lines)) } })) }
        w.level?.let { put("level", it) }
    }

    private fun wod(o: JsonObject): Wod = Wod(
        (o["id"] as JsonPrimitive).content, (o["name"] as JsonPrimitive).content, (o["category"] as JsonPrimitive).content,
        WodFormat.fromJson(o["format"])!!, lines(o["lines"]), lines(o["exercises"]),
        (o["parts"] as? JsonArray)?.map { p -> WodPart(((p as JsonObject)["title"] as JsonPrimitive).content, lines(p["lines"])) }.orEmpty(),
        (o["levels"] as? JsonArray)?.mapNotNull { l -> val x = l as JsonObject; WodLevelOption((x["title"] as JsonPrimitive).content, WodFormat.fromJson(x["format"]) ?: return@mapNotNull null, lines(x["lines"])) },
        (o["level"] as? JsonPrimitive)?.content,
    )

    private fun encode(s: WodRunState): JsonObject = buildJsonObject {
        put("wod", wodJson(s.wod))
        put("openedAt", ms(s.openedAt)!!)
        ms(s.startedAt)?.let { put("startedAt", it) }
        ms(s.pausedAt)?.let { put("pausedAt", it) }
        put("pausedTotal", s.pausedTotal)
        ms(s.countdownEnd)?.let { put("countdownEnd", it) }
        put("rounds", s.rounds)
        s.gymID?.let { put("gymID", it) }
        put("placeAsked", s.placeAsked)
        ms(s.sessionStart)?.let { put("sessionStart", it) }
        put("phase", s.phase)
        ms(s.phaseStart)?.let { put("phaseStart", it) }
        s.workingPhase?.let { put("workingPhase", it) }
        put("partSeconds", JsonObject(s.partSeconds.entries.associate { it.key.toString() to JsonPrimitive(it.value) }))
        put("blockRounds", JsonArray(s.blockRounds.map { JsonPrimitive(it) }))
        put("loads", JsonArray(s.loads.map { l ->
            buildJsonObject {
                put("exerciseID", l.exerciseID); put("part", l.part); l.removed?.let { put("removed", it) }
                put("sets", JsonArray(l.sets.map { x -> buildJsonObject { put("weight", x.weight); put("reps", x.reps); x.bar?.let { put("bar", it) } } }))
            }
        }))
        put("partTimers", JsonObject(s.partTimers.entries.associate { it.key.toString() to JsonPrimitive(it.value.toEpochMilli()) }))
        put("checked", JsonArray(s.checked.map { JsonPrimitive(it) }))
    }

    private fun decode(o: JsonObject): WodRunState = WodRunState(
        wod = wod(o["wod"] as JsonObject), openedAt = time(o, "openedAt") ?: Instant.now(), startedAt = time(o, "startedAt"), pausedAt = time(o, "pausedAt"),
        pausedTotal = (o["pausedTotal"] as? JsonPrimitive)?.doubleOrNull ?: 0.0, countdownEnd = time(o, "countdownEnd"),
        rounds = (o["rounds"] as? JsonPrimitive)?.intOrNull ?: 0, gymID = (o["gymID"] as? JsonPrimitive)?.content,
        placeAsked = (o["placeAsked"] as? JsonPrimitive)?.booleanOrNull ?: false, sessionStart = time(o, "sessionStart"),
        phase = (o["phase"] as? JsonPrimitive)?.intOrNull ?: 0, phaseStart = time(o, "phaseStart"),
        workingPhase = (o["workingPhase"] as? JsonPrimitive)?.intOrNull,
        partSeconds = (o["partSeconds"] as? JsonObject)?.entries?.associate { it.key.toInt() to ((it.value as JsonPrimitive).doubleOrNull ?: 0.0) }.orEmpty(),
        blockRounds = (o["blockRounds"] as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.intOrNull }.orEmpty(),
        loads = (o["loads"] as? JsonArray)?.map { e ->
            val l = e as JsonObject
            WodLoad((l["exerciseID"] as JsonPrimitive).content, (l["part"] as JsonPrimitive).intOrNull ?: 0,
                    (l["sets"] as? JsonArray)?.map { x -> val s = x as JsonObject; WodSet((s["weight"] as JsonPrimitive).doubleOrNull ?: 0.0, (s["reps"] as JsonPrimitive).intOrNull ?: 0, (s["bar"] as? JsonPrimitive)?.doubleOrNull) }.orEmpty(),
                    (l["removed"] as? JsonPrimitive)?.booleanOrNull)
        }.orEmpty(),
        partTimers = (o["partTimers"] as? JsonObject)?.entries?.associate { it.key.toInt() to Instant.ofEpochMilli((it.value as JsonPrimitive).longOrNull ?: 0) }.orEmpty(),
        checked = (o["checked"] as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.intOrNull }.orEmpty(),
    )
}
