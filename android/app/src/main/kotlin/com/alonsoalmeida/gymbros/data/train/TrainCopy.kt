package com.alonsoalmeida.gymbros.data.train

import com.alonsoalmeida.gymbros.domain.backup.AccountCopy
import com.alonsoalmeida.gymbros.domain.backup.AccountEdits
import com.alonsoalmeida.gymbros.domain.train.CustomExercise
import com.alonsoalmeida.gymbros.domain.train.Deload
import com.alonsoalmeida.gymbros.domain.train.Exercises
import com.alonsoalmeida.gymbros.domain.train.LoggedSet
import com.alonsoalmeida.gymbros.domain.train.PRBook
import com.alonsoalmeida.gymbros.domain.train.Routine
import com.alonsoalmeida.gymbros.domain.train.RoutineItem
import com.alonsoalmeida.gymbros.domain.train.Session
import com.alonsoalmeida.gymbros.domain.train.SessionLog
import com.alonsoalmeida.gymbros.domain.train.SetLog
import com.alonsoalmeida.gymbros.domain.train.TrainingGoal
import com.alonsoalmeida.gymbros.domain.train.WodPlan
import com.alonsoalmeida.gymbros.domain.train.WodResult
import com.alonsoalmeida.gymbros.ui.AppEnv
import com.dd.plist.NSArray
import com.dd.plist.NSNumber
import com.dd.plist.NSObject
import com.dd.plist.NSString
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import java.time.Instant
import java.util.Base64
import java.util.UUID

/** PR registrado à mão (Models/PersonalRecord.swift; `prs` na cópia da conta) */
data class PersonalRecord(val uuid: String, val exerciseID: String, val weight: Double, val reps: Int, val date: Instant) {
    val log: SetLog get() = SetLog(exerciseID, weight, reps, reps, true)
}

/**
 * O que o treino usa da cópia da conta (JSON do `Backup` do iOS): rotinas, treinos com séries, exercícios personalizados,
 * notas, PRs, resultados de WOD e os ajustes do treino (`accountSettings`). Só leitura; mudanças passam por `TrainEdits`.
 */
data class TrainData(
    val routines: List<Routine>,
    /** Todos os treinos, do mais novo ao mais antigo (como o @Query do iOS) */
    val sessions: List<Session>,
    val customs: List<CustomExercise>,
    val notes: Map<String, String>,
    val prs: List<PersonalRecord>,
    val wods: List<WodResult>,
    val goals: Map<String, String>,
    /** Aquecimento automático (padrão: ligado) */
    val autoWarmup: Boolean,
    val restNotification: Boolean,
    val barWeight: Double,
    val plannedRaw: String?,
    val deloadUntil: Instant?,
    val deloadSnooze: Instant?,
    val liked: Set<String>,
    val pendingRoutineUpdate: String?,
    val trainerName: String,
    val lastFormID: String?,
    /** Atividades ligadas a treinos/WODs: id → (data, minutos, esforço, nota) */
    val activityDates: Map<String, Instant>,
    val gyms: List<Pair<String, String>>,
) {
    val finished: List<Session> get() = sessions.filter { it.end != null }
    val inProgress: Session? get() = sessions.firstOrNull { it.end == null }
    /** Treinos concluídos, do mais antigo ao mais novo */
    val history: List<SessionLog> get() = finished.sortedBy { it.start }.map { it.log }
    fun deloadActive(now: Instant): Boolean = deloadUntil?.let { it > now } ?: false
    fun snoozed(now: Instant): Boolean = deloadSnooze?.let { it > now } ?: false

    companion object {
        val EMPTY = TrainData(emptyList(), emptyList(), emptyList(), emptyMap(), emptyList(), emptyList(), emptyMap(), true, false, 20.0,
                              null, null, null, emptySet(), null, "", null, emptyMap(), emptyList())
    }
}

object TrainCopy {
    private fun s(o: JsonObject, k: String): String? = (o[k] as? JsonPrimitive)?.takeIf { it.isString }?.content
    private fun i(o: JsonObject, k: String): Int? = (o[k] as? JsonPrimitive)?.intOrNull ?: (o[k] as? JsonPrimitive)?.doubleOrNull?.toInt()
    private fun d(o: JsonObject, k: String): Double? = (o[k] as? JsonPrimitive)?.doubleOrNull
    private fun b(o: JsonObject, k: String): Boolean? = (o[k] as? JsonPrimitive)?.booleanOrNull
    private fun date(o: JsonObject, k: String): Instant? = s(o, k)?.let { runCatching { Instant.parse(it) }.getOrNull() }
    private fun list(copy: JsonObject?, k: String): List<JsonObject> = (copy?.get(k) as? JsonArray)?.mapNotNull { it as? JsonObject }.orEmpty()

    fun settings(copy: JsonObject?): Map<String, Any?> {
        val raw = (copy?.get("accountSettings") as? JsonPrimitive)?.content ?: return emptyMap()
        return runCatching { AccountCopy.settings(Base64.getDecoder().decode(raw)) }.getOrDefault(emptyMap())
    }

    private fun epoch(v: Any?): Instant? = when (v) {
        is Number -> v.toDouble().takeIf { it > 0 }?.let { Instant.ofEpochMilli((it * 1000).toLong()) }
        is String -> v.toDoubleOrNull()?.takeIf { it > 0 }?.let { Instant.ofEpochMilli((it * 1000).toLong()) }
        else -> null
    }

    private fun bool(v: Any?): Boolean? = when (v) {
        is Boolean -> v
        is Number -> v.toInt() != 0
        is String -> v == "1" || v.equals("true", true)
        else -> null
    }

    fun read(copy: JsonObject?): TrainData {
        if (copy == null) return TrainData.EMPTY
        val st = settings(copy)
        val text = (copy["settings"] as? JsonObject).orEmpty()
        fun str(k: String): String? = st[k] as? String ?: (text[k] as? JsonPrimitive)?.content
        val routines = list(copy, "routines").mapNotNull { r ->
            Routine(s(r, "uuid")?.uppercase() ?: return@mapNotNull null, s(r, "name").orEmpty(), s(r, "weekdays").orEmpty(), i(r, "order") ?: 0,
                    (r["items"] as? JsonArray)?.mapNotNull { it as? JsonObject }?.map { x ->
                        RoutineItem(s(x, "exerciseID").orEmpty(), i(x, "sets") ?: 3, i(x, "reps") ?: 10, i(x, "rest") ?: 90, i(x, "order") ?: 0,
                                    b(x, "supersetNext") ?: false)
                    }.orEmpty())
        }.sortedBy { it.order }
        val sessions = list(copy, "sessions").mapNotNull(::session).sortedByDescending { it.start }
        val customs = list(copy, "customExercises").mapNotNull { c ->
            CustomExercise(s(c, "uuid")?.uppercase() ?: return@mapNotNull null, s(c, "name").orEmpty(), s(c, "group") ?: "corpo",
                           s(c, "equipment") ?: "Outro", s(c, "type") ?: "weighted", s(c, "notes").orEmpty())
        }
        val notes = list(copy, "notes").mapNotNull { n -> (s(n, "exerciseID") ?: return@mapNotNull null) to s(n, "text").orEmpty() }.toMap()
        val prs = list(copy, "prs").mapNotNull { p ->
            PersonalRecord(s(p, "uuid")?.uppercase() ?: return@mapNotNull null, s(p, "exerciseID").orEmpty(), d(p, "weight") ?: 0.0, i(p, "reps") ?: 1,
                           date(p, "date") ?: return@mapNotNull null)
        }.sortedByDescending { it.date }
        val wods = list(copy, "wods").mapNotNull { w ->
            WodResult(s(w, "uuid")?.uppercase() ?: return@mapNotNull null, s(w, "wodID").orEmpty(), s(w, "wodName").orEmpty(), s(w, "formatName").orEmpty(),
                      date(w, "date") ?: return@mapNotNull null, i(w, "seconds"), i(w, "rounds"), i(w, "reps"), b(w, "rx") ?: true, s(w, "note").orEmpty(),
                      s(w, "activityUUID")?.uppercase(), b(w, "capped") ?: false)
        }.sortedByDescending { it.date }
        @Suppress("UNCHECKED_CAST")
        val liked = ((st["routines.liked"] as? List<Any?>).orEmpty()).mapNotNull { it as? String }.toSet()
        val bar = when (val v = st["barWeight"]) { is Number -> v.toDouble(); is String -> v.toDoubleOrNull(); else -> null } ?: 20.0
        return TrainData(
            routines, sessions, customs, notes, prs, wods,
            goals = TrainingGoal.decode(str(TrainingGoal.KEY)),
            autoWarmup = bool(st["autoWarmup"]) ?: true,
            // "Pausar todas" (`notify.paused`) também cala o fim do descanso, como o LiveWorkout.swift
            restNotification = (bool(st["restNotification"]) ?: false) && bool(st["notify.paused"]) != true,
            barWeight = bar,
            plannedRaw = str(WodPlan.KEY),
            deloadUntil = epoch(st[Deload.UNTIL_KEY]),
            deloadSnooze = epoch(st[Deload.SNOOZE_KEY]),
            liked = liked,
            pendingRoutineUpdate = (st["pendingRoutineUpdate"] as? String)?.uppercase()?.ifEmpty { null },
            trainerName = str("trainerName").orEmpty(),
            lastFormID = str("lastFormID"),
            activityDates = list(copy, "activities").mapNotNull { a -> (s(a, "uuid")?.uppercase() ?: return@mapNotNull null) to (date(a, "date") ?: return@mapNotNull null) }.toMap(),
            gyms = list(copy, "gyms").mapNotNull { g -> (s(g, "uuid")?.uppercase() ?: return@mapNotNull null) to s(g, "name").orEmpty() },
        )
    }

    private fun session(o: JsonObject): Session? {
        val id = s(o, "uuid")?.uppercase() ?: return null
        val sets = (o["sets"] as? JsonArray)?.mapNotNull { it as? JsonObject }?.map { x ->
            val reps = i(x, "reps") ?: 0
            LoggedSet(s(x, "exerciseID").orEmpty(), i(x, "exerciseOrder") ?: 0, i(x, "index") ?: 0, d(x, "weight") ?: 0.0, reps,
                      i(x, "targetReps") ?: reps, i(x, "rest") ?: 90, b(x, "done") ?: false, b(x, "warmup") ?: false)
        }.orEmpty()
        return Session(id, s(o, "title").orEmpty(), s(o, "routineUUID")?.uppercase(), date(o, "start") ?: return null, date(o, "end"),
                       i(o, "effort") ?: 6, s(o, "activityUUID")?.uppercase(), s(o, "currentExerciseID"), date(o, "restEnd"), i(o, "restTotal") ?: 90,
                       s(o, "gymUUID")?.uppercase(), b(o, "placeAsked") ?: false, s(o, "superset").orEmpty(), b(o, "deload") ?: false, sets)
    }

    /** Preenche o que as regras puras consultam (como o `UserDefaults` e o `PRBook.reload()` do iOS) */
    fun install(t: TrainData) {
        Exercises.register(t.customs)
        TrainingGoal.goals = t.goals
        PRBook.manual = t.prs.map { it.log }.groupBy { it.exerciseID }
    }
}

/** Mudanças do treino na cópia da conta: o resto do JSON fica intacto; ids em UUID maiúsculo; datas ISO 8601 sem fração */
object TrainEdits {
    fun newID(): String = UUID.randomUUID().toString().uppercase()
    private fun iso(i: Instant) = AccountEdits.iso(i)

    private fun replaceList(copy: JsonObject, key: String, list: List<JsonElement>): JsonObject =
        JsonObject(LinkedHashMap<String, JsonElement>(copy).apply { put(key, JsonArray(list)) })

    private fun items(copy: JsonObject, key: String): List<JsonObject> = (copy[key] as? JsonArray)?.mapNotNull { it as? JsonObject }.orEmpty()
    private fun idOf(o: JsonObject, k: String = "uuid") = (o[k] as? JsonPrimitive)?.content?.uppercase()

    /** Troca (ou acrescenta) o item `id`, mantendo os campos que o Android não conhece */
    private fun upsert(copy: JsonObject, key: String, id: String, fields: Map<String, JsonElement?>, idKey: String = "uuid"): JsonObject {
        val list = items(copy, key)
        val old = list.firstOrNull { idOf(it, idKey) == id.uppercase() }
        val merged = LinkedHashMap<String, JsonElement>(old ?: emptyMap())
        for ((k, v) in fields) if (v == null || v is JsonNull) merged.remove(k) else merged[k] = v
        val obj = JsonObject(merged)
        return replaceList(copy, key, if (old == null) list + obj else list.map { if (it === old) obj else it })
    }

    private fun remove(copy: JsonObject, key: String, ids: Set<String>, idKey: String = "uuid"): JsonObject =
        replaceList(copy, key, items(copy, key).filter { idOf(it, idKey) !in ids.map { s -> s.uppercase() } })

    private fun p(v: String?) = v?.let { JsonPrimitive(it) }
    private fun p(v: Int) = JsonPrimitive(v)
    private fun p(v: Boolean) = JsonPrimitive(v)
    /** Número como o iOS grava (60 e não 60.0 quando inteiro) */
    private fun num(v: Double): JsonPrimitive = if (v % 1.0 == 0.0 && kotlin.math.abs(v) < 1e15) JsonPrimitive(v.toLong()) else JsonPrimitive(v)

    // Rotinas

    fun saveRoutine(copy: JsonObject, r: Routine): JsonObject = upsert(copy, "routines", r.uuid, mapOf(
        "uuid" to p(r.uuid), "name" to p(r.name), "weekdays" to p(r.weekdaysRaw), "order" to p(r.order),
        "items" to JsonArray(r.sortedItems.map { x ->
            JsonObject(mapOf("exerciseID" to JsonPrimitive(x.exerciseID), "sets" to p(x.sets), "reps" to p(x.reps), "rest" to p(x.rest),
                             "order" to p(x.order), "supersetNext" to p(x.supersetNext)))
        }),
    ))

    fun deleteRoutine(copy: JsonObject, id: String): JsonObject = remove(copy, "routines", setOf(id))

    // Treinos

    fun saveSession(copy: JsonObject, s: Session): JsonObject = upsert(copy, "sessions", s.uuid, mapOf(
        "uuid" to p(s.uuid), "title" to p(s.title), "routineUUID" to p(s.routineUUID), "start" to p(iso(s.start)), "end" to p(s.end?.let(::iso)),
        "effort" to p(s.effort), "activityUUID" to p(s.activityUUID),
        "sets" to JsonArray(s.orderedSets.map { x ->
            JsonObject(mapOf("exerciseID" to JsonPrimitive(x.exerciseID), "exerciseOrder" to p(x.exerciseOrder), "index" to p(x.index),
                             "weight" to num(x.weight), "reps" to p(x.reps), "targetReps" to p(x.targetReps), "rest" to p(x.rest),
                             "done" to p(x.done), "warmup" to p(x.warmup)))
        }),
        "superset" to p(s.supersetRaw), "deload" to p(s.isDeload), "gymUUID" to p(s.gymUUID), "currentExerciseID" to p(s.currentExerciseID),
        "restEnd" to p(s.restEnd?.let(::iso)), "restTotal" to p(s.restTotal), "placeAsked" to p(s.placeAsked),
    ))

    fun deleteSession(copy: JsonObject, id: String): JsonObject = remove(copy, "sessions", setOf(id))

    // Exercícios personalizados, notas e PRs

    fun saveCustom(copy: JsonObject, c: CustomExercise): JsonObject = upsert(copy, "customExercises", c.uuid, mapOf(
        "uuid" to p(c.uuid), "name" to p(c.name), "group" to p(c.group), "equipment" to p(c.equipment), "type" to p(c.type), "notes" to p(c.notes)))

    fun deleteCustom(copy: JsonObject, id: String): JsonObject = remove(copy, "customExercises", setOf(id))

    /** Nota do exercício (vazia apaga); a chave das notas é o `exerciseID` */
    fun saveNote(copy: JsonObject, exerciseID: String, text: String, now: Instant): JsonObject {
        val clean = text.trim()
        if (clean.isEmpty()) return replaceList(copy, "notes", items(copy, "notes").filter { (it["exerciseID"] as? JsonPrimitive)?.content != exerciseID })
        val list = items(copy, "notes")
        val old = list.firstOrNull { (it["exerciseID"] as? JsonPrimitive)?.content == exerciseID }
        val obj = JsonObject(LinkedHashMap<String, JsonElement>(old ?: emptyMap()).apply {
            put("exerciseID", JsonPrimitive(exerciseID)); put("text", JsonPrimitive(clean)); put("updated", JsonPrimitive(iso(now)))
        })
        return replaceList(copy, "notes", if (old == null) list + obj else list.map { if (it === old) obj else it })
    }

    fun addPRs(copy: JsonObject, prs: List<PersonalRecord>): JsonObject =
        replaceList(copy, "prs", items(copy, "prs") + prs.map {
            JsonObject(mapOf("uuid" to JsonPrimitive(it.uuid), "exerciseID" to JsonPrimitive(it.exerciseID), "weight" to num(it.weight),
                             "reps" to p(it.reps), "date" to JsonPrimitive(iso(it.date))))
        })

    fun deletePRs(copy: JsonObject, ids: Set<String>): JsonObject = remove(copy, "prs", ids)

    fun addWod(copy: JsonObject, r: WodResult): JsonObject = upsert(copy, "wods", r.uuid, mapOf(
        "uuid" to p(r.uuid), "wodID" to p(r.wodID), "wodName" to p(r.wodName), "formatName" to p(r.formatName), "date" to p(iso(r.date)),
        "seconds" to r.seconds?.let(::p), "rounds" to r.rounds?.let(::p), "reps" to r.reps?.let(::p), "rx" to p(r.rx), "note" to p(r.note),
        "activityUUID" to p(r.activityUUID), "capped" to p(r.capped)))

    /**
     * Atividade de treino guiado/WOD, como o iOS cria na conclusão (Activity sem tipo do Saúde, XP para o bro principal,
     * com a divisão de atributos calculada ao salvar).
     */
    fun addActivity(copy: JsonObject, id: String, kind: String, date: Instant, minutes: Int, effort: Int, note: String, attributes: String,
                    gymUUID: String?): JsonObject {
        val st = TrainCopy.settings(copy)
        val main = (st["mainMonster"] as? String) ?: ((copy["settings"] as? JsonObject)?.get("mainMonster") as? JsonPrimitive)?.content
        var out = upsert(copy, "activities", id, mapOf(
            "uuid" to p(id), "kind" to p(kind), "date" to p(iso(date)), "minutes" to p(minutes), "effort" to p(effort), "note" to p(note),
            "monsterUUID" to p(main?.uppercase()), "gymUUID" to p(gymUUID), "attributes" to p(attributes)))
        if ((out["monsters"] as? JsonArray).isNullOrEmpty()) out = JsonObject(LinkedHashMap<String, JsonElement>(out).apply { put("monsters", JsonArray(listOf(AccountEdits.starter()))) })
        return out
    }

    // Ajustes da conta (plist)

    fun setting(copy: JsonObject, key: String, value: NSObject?): JsonObject {
        var out = AccountEdits.updateSettings(copy) { if (value == null) it.remove(key) else it[key] = value }
        // Chave que também está nos ajustes em texto (`settings`): os dois iguais
        val text = out["settings"] as? JsonObject
        if (text != null && text.containsKey(key) && value is NSString) {
            out = JsonObject(LinkedHashMap<String, JsonElement>(out).apply { put("settings", JsonObject(text + (key to JsonPrimitive(value.content)))) })
        }
        return out
    }

    fun text(copy: JsonObject, key: String, value: String?): JsonObject = setting(copy, key, value?.let { NSString(it) })
    fun flag(copy: JsonObject, key: String, value: Boolean): JsonObject = setting(copy, key, NSNumber(value))
    fun number(copy: JsonObject, key: String, value: Double): JsonObject = setting(copy, key, NSNumber(value))
    fun strings(copy: JsonObject, key: String, value: List<String>): JsonObject = setting(copy, key, NSArray(*value.map { NSString(it) }.toTypedArray()))
}

/**
 * Pontos de encaixe com as outras frentes, ligados pelo orquestrador:
 *  · `onPost`: depois de salvar um treino guiado ou WOD, o "Postar em" (perfil e ligas). Recebe o id da atividade criada,
 *    o título do post e o texto (recordes ou o resumo do treino do coach). Sem ligação, a atividade fica só no histórico.
 *  · `deleteActivity`: apagar a atividade ligada a um treino (o XP fica com os bros: `RetiredActivities` do iOS).
 *    Sem ligação, apagar um treino com atividade abre o detalhe da atividade, que é de outra frente.
 *  · `postDestinations`: o seletor "Postar em" (LeaguePostSection do iOS); sem ligação, mostra que posta depois.
 */
object TrainHooks {
    @Volatile var onPost: ((activityID: String, title: String, note: String) -> Unit)? = null
    @Volatile var deleteActivity: ((env: AppEnv, activityID: String) -> Unit)? = null
}

/** Gravações que não podem morrer junto com a tela que fechou (concluir, apagar): escopo do processo */
object TrainScope {
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    fun edit(env: AppEnv, change: (JsonObject) -> JsonObject) {
        scope.launch { env.copies.edit { c -> change(c ?: AccountEdits.empty(env.name, Instant.now())) } }
    }
}
