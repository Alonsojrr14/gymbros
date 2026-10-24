package com.alonsoalmeida.gymbros.data.leagues

import com.alonsoalmeida.gymbros.domain.social.CommentScope
import android.content.Context
import com.alonsoalmeida.gymbros.data.AccountCopyRepository
import com.alonsoalmeida.gymbros.data.CopyState
import com.alonsoalmeida.gymbros.domain.backup.AccountCopy
import com.alonsoalmeida.gymbros.domain.backup.AccountEdits
import com.alonsoalmeida.gymbros.domain.leagues.CheckInProof
import com.alonsoalmeida.gymbros.domain.leagues.League
import com.alonsoalmeida.gymbros.domain.leagues.LeagueActivityJson
import com.alonsoalmeida.gymbros.domain.leagues.LeagueEdits
import com.alonsoalmeida.gymbros.domain.leagues.LeagueJson
import com.alonsoalmeida.gymbros.domain.leagues.LeagueRenewal
import com.alonsoalmeida.gymbros.domain.leagues.LeagueSettings
import com.alonsoalmeida.gymbros.domain.leagues.PhotoProof
import com.alonsoalmeida.gymbros.domain.leagues.PostSubject
import com.alonsoalmeida.gymbros.domain.leagues.RemoteLeague
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.JsonObject
import java.time.Instant
import java.util.Base64

/** Para onde vai o post do perfil (Leagues.swift `ProfileFeed.id`) */
const val PROFILE_FEED = "00000000-0000-0000-0000-0000000000AA"

/**
 * Ligas da conta aberta (LeagueRemote.swift `LeagueRemoteStore` + a caixa de saída). Um por conta e por processo.
 *
 * O que é seu mora na cópia da conta (ligas, check-ins, recados, revisões e comentários): o iPhone recebe na hora pela
 * mesclagem. O que vem dos outros fica só na memória (cache do servidor), relido ao abrir a liga e no máximo a cada
 * minuto, para caber no plano grátis.
 *
 * Caixa de saída: o iPhone manda o que ele criou; o Android manda só o que nasceu ou mudou aqui (lista local de
 * pendentes). Assim um post do iPhone ainda não enviado nunca sai daqui sem a foto, que só ele guarda no CloudKit.
 */
class LeagueStore private constructor(context: Context, val uid: String, val copies: AccountCopyRepository) {
    val remote = LeagueRemote()
    private val prefs = context.getSharedPreferences("ligas-$uid", Context.MODE_PRIVATE)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val flushLock = Mutex()
    private var flushJob: Job? = null

    private val _cache = MutableStateFlow<Map<String, RemoteLeague>>(emptyMap())
    /** O que se sabe de cada liga no servidor, pelo código */
    val cache: StateFlow<Map<String, RemoteLeague>> = _cache.asStateFlow()
    private val fetchedAt = HashMap<String, Long>()

    private val _comments = MutableStateFlow<Map<String, List<RemoteComment>>>(emptyMap())
    /** Comentários dos outros por post (ficam só na memória) */
    val comments: StateFlow<Map<String, List<RemoteComment>>> = _comments.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val lastError: StateFlow<String?> = _error.asStateFlow()

    private val _roles = MutableStateFlow<Set<String>?>(null)
    val roles: StateFlow<Set<String>?> = _roles.asStateFlow()

    fun copy(): JsonObject? = (copies.state.value as? CopyState.Ready)?.copy

    fun settings(copy: JsonObject?): Map<String, Any?> =
        (copy?.get("accountSettings") as? kotlinx.serialization.json.JsonPrimitive)?.content?.let {
            runCatching { AccountCopy.settings(Base64.getDecoder().decode(it)) }.getOrNull()
        }.orEmpty()

    // MARK: Pendentes deste aparelho

    private fun pending(kind: String): Set<String> = prefs.getStringSet(kind, emptySet()).orEmpty()
    private fun markPending(kind: String, ids: Collection<String>) {
        if (ids.isEmpty()) return
        prefs.edit().putStringSet(kind, pending(kind) + ids.map { it.uppercase() }).apply()
    }
    private fun clearPending(kind: String, ids: Collection<String>) {
        prefs.edit().putStringSet(kind, pending(kind) - ids.map { it.uppercase() }.toSet()).apply()
    }

    // MARK: Leitura do servidor

    fun key(l: League) = LeagueKey(l.code, l.start, l.end, l.j.teams ?: "", l.settings.isPrivate)

    fun loadRoles() {
        if (_roles.value != null) return
        scope.launch { _roles.value = runCatching { remote.roles() }.getOrElse { setOf("USER") } }
    }

    /** Relê as ligas do servidor (ao abrir; `force` ao puxar para atualizar) */
    fun refresh(leagues: List<League>, force: Boolean = false) {
        val now = System.currentTimeMillis()
        for (l in leagues) {
            if (l.isMock || l.code.isEmpty()) continue
            val k = key(l)
            val last = fetchedAt[k.code] ?: 0
            if (!force && now - last < 60_000) continue
            fetchedAt[k.code] = now
            scope.launch {
                runCatching { remote.fetch(k) }
                    .onSuccess { r -> _cache.value = _cache.value + (k.code to r); _error.value = null }
                    .onFailure { fetchedAt.remove(k.code); _error.value = message(it) }
            }
        }
    }

    fun pullComments(league: String, items: List<String>) {
        if (items.isEmpty()) return
        scope.launch {
            runCatching { remote.comments(league, items) }.onSuccess { list ->
                val mine = uid
                val byItem = list.filter { it.user != mine }.groupBy { it.item }
                _comments.value = _comments.value + items.associateWith { byItem[it].orEmpty() }
            }
        }
    }

    private fun message(e: Throwable): String = when ((e as? com.google.firebase.firestore.FirebaseFirestoreException)?.code) {
        com.google.firebase.firestore.FirebaseFirestoreException.Code.PERMISSION_DENIED -> "Sua conta não tem permissão para isso."
        else -> "Confira a internet e tente de novo."
    }

    // MARK: Gravar na cópia da conta

    suspend fun edit(change: (JsonObject) -> JsonObject) {
        copies.edit { c -> change(c ?: AccountEdits.empty("", Instant.now())) }
    }

    /** Liga criada ou mudada aqui: sobe (regras e o seu lugar nela) */
    suspend fun saveLeague(uuid: String, fields: Map<String, Any?>, isNew: Boolean) {
        edit { c ->
            if (isNew) LeagueEdits.add(c, "leagues", fields + ("uuid" to uuid) + ("syncedAt" to null))
            else LeagueEdits.update(c, "leagues", uuid, fields + ("syncedAt" to null))
        }
        markPending(LEAGUES, listOf(uuid))
        scheduleFlush()
    }

    /** Decisão de moderação nas regras da liga (League.moderate) */
    suspend fun moderate(league: League, change: (LeagueSettings) -> LeagueSettings) {
        saveLeague(league.uuid, mapOf("settings" to change(league.settings).rawValue), false)
    }

    /** Representante: o bro escolhido ou um ovo novo (ModelContext.representative) */
    suspend fun representative(choice: String?): String {
        if (choice != null) return choice
        var id = ""
        edit { c -> val (out, egg) = LeagueEdits.addEgg(c, Instant.now()); id = egg; out }
        return id
    }

    data class NewPost(
        val activity: LeagueActivityJson,
        val title: String,
        val note: String,
        /** JPEG já reduzido */
        val photo: ByteArray?,
        val photoProof: PhotoProof?,
        val pose: String?,
        val extraPhotos: List<ByteArray> = emptyList(),
        val grouped: List<LeagueActivityJson> = emptyList(),
        val place: String? = null,
        val gymVisit: String? = null,
    )

    /**
     * Publica a atividade nos destinos (LeaguesView.swift `postCheckIns`): pula liga cujas regras barram e quem já tem post
     * desta atividade. O seu check-in em liga com revisão espera o dono, salvo se você modera.
     */
    suspend fun post(p: NewPost, destinations: Set<String>, leagues: List<League>, already: Set<String> = emptySet()) {
        val a = p.activity
        val subject = PostSubject(a.workoutTypeID, a.date, a.minutes, a.isDeviceRecorded, p.place, p.photoProof, p.gymVisit)
        val now = Instant.now()
        val ids = mutableListOf<String>()
        edit { c0 ->
            var c = c0
            for (dest in destinations - already) {
                val league = leagues.firstOrNull { it.uuid == dest }
                if (league != null && league.problems(subject, now).isNotEmpty()) continue
                val sameDay = p.grouped.filter { it.uuid.uppercase() != a.uuid.uppercase() && League.CAL.sameDay(it.date, a.date) }
                val proof = CheckInProof(p.photoProof, subject.deviceRecorded, if (subject.deviceRecorded) CheckInProof.publicDevice(a.source) else null,
                                         if (league?.settings?.posesEnabled == true) p.pose else null, p.gymVisit,
                                         sameDay.map { it.uuid.uppercase() }, sameDay.map { it.scorePart })
                val id = LeagueEdits.newID()
                ids += id
                c = LeagueEdits.add(c, "checkIns", mapOf(
                    "uuid" to id, "leagueUUID" to dest, "activityUUID" to a.uuid.uppercase(),
                    "title" to p.title.trim().ifEmpty { a.typeName }, "note" to p.note, "date" to a.date,
                    "hadPhoto" to (p.photo != null), "place" to p.place, "proof" to proof.rawValue,
                    "review" to if (league != null && league.needsReview(true, uid)) "pending" else "",
                    "photo" to p.photo?.let { Base64.getEncoder().encodeToString(it) },
                    "extraPhotos" to if (p.photo != null && p.extraPhotos.isNotEmpty()) extraPlist(p.extraPhotos) else null,
                ))
            }
            c
        }
        markPending(CHECKINS, ids)
        scheduleFlush()
    }

    /** Apaga um check-in seu: se já tinha subido, sai do servidor (LeagueOutbox.retract) */
    suspend fun deleteCheckIn(id: String) {
        edit { c ->
            val item = LeagueEdits.read(c).checkIns.orEmpty().firstOrNull { it.uuid.equals(id, true) }
            var out = LeagueEdits.remove(c, "checkIns", setOf(id))
            out = LeagueEdits.removeWhere(out, "comments") { (it["itemID"] as? kotlinx.serialization.json.JsonPrimitive)?.content.equals(id, true) }
            if (item?.syncedAt != null) {
                val r = LeagueEdits.retractions(settings(out)).toMutableMap()
                r[item.leagueUUID.uppercase()] = r[item.leagueUUID.uppercase()].orEmpty() + id.uppercase()
                out = LeagueEdits.setRetractions(out, r)
            }
            out
        }
        clearPending(CHECKINS, listOf(id))
        scheduleFlush()
    }

    suspend fun addMessage(leagueUUID: String, text: String, photo: ByteArray?) {
        val id = LeagueEdits.newID()
        edit { c -> LeagueEdits.add(c, "messages", mapOf("uuid" to id, "leagueUUID" to leagueUUID, "text" to text, "date" to Instant.now(),
                                                         "photo" to photo?.let { Base64.getEncoder().encodeToString(it) })) }
        markPending(MESSAGES, listOf(id))
        scheduleFlush(0)
    }

    /** Apagar um recado seu tira só daqui (como no iPhone) */
    suspend fun deleteMessage(id: String) = edit { c -> LeagueEdits.remove(c, "messages", setOf(id)) }

    suspend fun review(leagueUUID: String, itemID: String, approved: Boolean) = edit { c ->
        LeagueEdits.add(c, "reviews", mapOf("uuid" to LeagueEdits.newID(), "leagueUUID" to leagueUUID, "itemID" to itemID, "approved" to approved,
                                            "date" to Instant.now()))
    }

    suspend fun addComment(text: String, item: String, owner: String, name: String, where: CommentScope) {
        val id = LeagueEdits.newID()
        val now = Instant.now()
        edit { c -> LeagueEdits.add(c, "comments", mapOf("uuid" to id, "itemID" to item, "text" to text, "date" to now, "authorID" to "me", "authorName" to "")) }
        scope.launch { runCatching { remote.addComment(id, item, owner, text, name, now, where) } }
    }

    suspend fun removeComment(id: String) {
        edit { c -> LeagueEdits.remove(c, "comments", setOf(id)) }
        scope.launch { runCatching { remote.removeComment(id) } }
    }

    /** Sai da liga e de todas as temporadas dela: check-ins, recados e comentários somem daqui; no servidor, os seus */
    suspend fun leave(league: League, all: List<League>, successor: String? = null) {
        val series = all.filter { it.seriesKey == league.seriesKey }
        val ids = series.map { it.uuid }.toSet()
        edit { c ->
            val gone = LeagueEdits.read(c).checkIns.orEmpty().filter { it.leagueUUID.uppercase() in ids }.map { it.uuid.uppercase() }.toSet()
            var out = LeagueEdits.remove(c, "checkIns", gone)
            out = LeagueEdits.removeWhere(out, "comments") { (it["itemID"] as? kotlinx.serialization.json.JsonPrimitive)?.content?.uppercase() in gone }
            out = LeagueEdits.removeWhere(out, "messages") { (it["leagueUUID"] as? kotlinx.serialization.json.JsonPrimitive)?.content?.uppercase() in ids }
            val r = LeagueEdits.retractions(settings(out))
            if (r.keys.any { it.uppercase() in ids }) out = LeagueEdits.setRetractions(out, r.filterKeys { it.uppercase() !in ids })
            LeagueEdits.remove(out, "leagues", ids)
        }
        clearPending(LEAGUES, ids)
        if (!league.isMock && league.code.isNotEmpty()) scope.launch {
            runCatching {
                if (successor != null) remote.transfer(league.code, successor)
                remote.leave(league.code)
            }
        }
    }

    /** Nova temporada (renovação automática ou "Reiniciar desafio"): mesmas regras, check-ins zerados */
    suspend fun newSeason(old: League, next: LeagueRenewal.Next) {
        val id = LeagueEdits.newID()
        val j = old.j
        var created = false
        edit { c ->
            // Já renovada (pelo iPhone ou por um toque anterior): não cria outra temporada
            if (LeagueEdits.read(c).leagues.orEmpty().firstOrNull { it.uuid.equals(old.uuid, true) }?.nextUUID != null) return@edit c
            created = true
            val out = LeagueEdits.add(c, "leagues", mapOf(
                "uuid" to id, "name" to j.name, "emoji" to j.emoji, "scoring" to j.scoring, "start" to next.start, "end" to next.end,
                "code" to j.code, "isMock" to j.isMock, "joinedAt" to j.joinedAt, "monsterUUID" to j.monsterUUID, "autoRenew" to j.autoRenew,
                "season" to next.season, "seriesID" to old.seriesKey, "weights" to j.weights, "tieBreak" to j.tieBreak, "photoRule" to j.photoRule,
                "teams" to j.teams, "myTeamID" to j.myTeamID, "activityRule" to j.activityRule, "settings" to j.settings, "cover" to j.cover,
                "joined" to j.joined, "swiss" to j.swiss,
            ))
            LeagueEdits.update(out, "leagues", old.uuid, mapOf("nextUUID" to id))
        }
        if (!created) return
        markPending(LEAGUES, listOf(id))
        scheduleFlush()
    }

    /**
     * Renova as ligas com renovação automática que acabaram (LeagueRenewal.run). Espera 6 h depois do fim: o iPhone,
     * quando aberto, renova antes e a temporada nova chega pela cópia, sem criar duas.
     */
    suspend fun renewIfNeeded(leagues: List<League>) {
        val now = Instant.now()
        for (l in leagues) {
            if (!l.autoRenew || l.isPastSeason) continue
            val end = l.end ?: continue
            if (end.plusSeconds(6 * 3600) > now) continue
            newSeason(l, LeagueRenewal.next(l, now))
        }
    }

    // MARK: Pedidos de entrada

    suspend fun requestJoin(d: LeagueDraft, name: String, monster: String?) {
        remote.requestJoin(d.code, Membership(name, "egg", null, null))
        edit { c ->
            val list = LeagueEdits.pendingJoins(settings(c)).filter { it.code != d.code } + LeagueEdits.PendingJoin(d.code, d.name, d.emoji, Instant.now(), monster)
            LeagueEdits.setPendingJoins(c, list)
        }
    }

    suspend fun cancelJoin(code: String) = edit { c -> LeagueEdits.setPendingJoins(c, LeagueEdits.pendingJoins(settings(c)).filter { it.code != code }) }

    /** Entra nas ligas em que o pedido foi aceito (PendingJoins.check) */
    suspend fun checkPendingJoins() {
        val list = LeagueEdits.pendingJoins(settings(copy()))
        for (p in list) {
            val d = runCatching { remote.isApproved(p.code) }.getOrNull() ?: continue
            join(d, representative(p.monsterUUID))
            edit { c -> LeagueEdits.setPendingJoins(c, LeagueEdits.pendingJoins(settings(c)).filter { it.code != p.code }) }
        }
    }

    /** Liga de outra pessoa achada pelo código (League(draft:)) */
    suspend fun join(d: LeagueDraft, monster: String) {
        val now = Instant.now()
        saveLeague(LeagueEdits.newID(), mapOf(
            "name" to d.name, "emoji" to d.emoji, "scoring" to d.scoring, "start" to d.start, "end" to d.end, "code" to d.code,
            "isMock" to false, "joinedAt" to now, "monsterUUID" to monster, "autoRenew" to d.autoRenew, "season" to 1,
            "weights" to d.weights, "tieBreak" to d.tieBreak, "photoRule" to d.photoRule, "teams" to d.teams, "activityRule" to (d.activityRule ?: ""),
            "settings" to (d.settings ?: ""), "swiss" to (d.swiss ?: "pontos"), "joined" to true,
        ), isNew = true)
    }

    // MARK: Caixa de saída

    fun scheduleFlush(delayMs: Long = 2_000) {
        flushJob?.cancel()
        flushJob = scope.launch {
            delay(delayMs)
            flush()
        }
    }

    /** Manda o que nasceu aqui: ligas e o seu lugar nelas, check-ins, retiradas e recados (LeagueRemoteStore.send) */
    suspend fun flush() = flushLock.withLock {
        val c = copy() ?: return@withLock
        val data = LeagueEdits.read(c)
        val leagues = data.leagues.orEmpty().map(::League)
        val acts = data.activities.associateBy { it.uuid.uppercase() }
        val name = (c["settings"] as? JsonObject)?.get("trainerName")?.let { (it as? kotlinx.serialization.json.JsonPrimitive)?.content }.orEmpty()
        val now = Instant.now()
        // Forma do bro que representa você (`Monster.lastFormID`, como o iPhone manda)
        val forms = (c["monsters"] as? kotlinx.serialization.json.JsonArray).orEmpty().mapNotNull { e ->
            val o = e as? JsonObject ?: return@mapNotNull null
            val id = (o["uuid"] as? kotlinx.serialization.json.JsonPrimitive)?.content?.uppercase() ?: return@mapNotNull null
            id to (o["lastFormID"] as? kotlinx.serialization.json.JsonPrimitive)?.content.orEmpty()
        }.toMap()
        val formOf = { id: String? -> forms[id]?.ifEmpty { null } ?: "egg" }
        runCatching {
            // Ligas e o seu lugar
            val pl = pending(LEAGUES)
            val done = mutableListOf<String>()
            for (l in leagues.filter { it.uuid in pl && !it.isPastSeason && !it.isMock }) {
                val k = key(l)
                if (l.isMine) remote.create(draft(l.j))
                remote.setMembership(Membership(name, formOf(l.monsterUUID), l.myTeamID, l.swissJoinedAt), k)
                done += l.uuid
            }
            if (done.isNotEmpty()) { edit { x -> LeagueEdits.updateMany(x, "leagues", done.toSet(), mapOf("syncedAt" to now)) }; clearPending(LEAGUES, done) }
            clearPending(LEAGUES, pl.filter { id -> leagues.none { it.uuid == id } })

            // Check-ins
            val pc = pending(CHECKINS)
            val mine = data.checkIns.orEmpty().filter { it.uuid.uppercase() in pc }
            val sent = mutableListOf<String>()
            for ((leagueID, list) in mine.groupBy { it.leagueUUID.uppercase() }) {
                val k = if (leagueID == PROFILE_FEED) LeagueKey.PROFILE else leagues.firstOrNull { it.uuid == leagueID }?.takeIf { !it.isMock }?.let(::key) ?: continue
                val out = list.mapNotNull { ci ->
                    val a = acts[ci.activityUUID.uppercase()] ?: return@mapNotNull null
                    val i = a.scoreInput
                    OutgoingCheckIn(ci.uuid.uppercase(), ci.date, a.kind, i.minutes, i.effort, i.meters, i.kcal, ci.title, ci.note, ci.hasPhoto,
                                    i.workoutTypeID, ci.place, CheckInProof.parse(ci.proof))
                }
                remote.publish(out, k)
                sent += out.map { it.id }
            }
            if (sent.isNotEmpty()) { edit { x -> LeagueEdits.updateMany(x, "checkIns", sent.toSet(), mapOf("syncedAt" to now)) }; clearPending(CHECKINS, sent) }
            clearPending(CHECKINS, pc.filter { id -> data.checkIns.orEmpty().none { it.uuid.equals(id, true) } })

            // Retiradas (a fila é da conta: o iPhone também esvazia)
            val r = LeagueEdits.retractions(settings(c))
            val ids = r.values.flatten()
            if (ids.isNotEmpty()) {
                remote.retract(ids)
                edit { x ->
                    val left = LeagueEdits.retractions(settings(x)).mapValues { (_, v) -> v.filter { it !in ids } }.filterValues { it.isNotEmpty() }
                    LeagueEdits.setRetractions(x, left)
                }
            }

            // Recados
            val pm = pending(MESSAGES)
            val msgs = data.messages.orEmpty().filter { it.uuid.uppercase() in pm }
            val accepted = mutableListOf<String>()
            for ((leagueID, list) in msgs.groupBy { it.leagueUUID.uppercase() }) {
                val l = leagues.firstOrNull { it.uuid == leagueID }?.takeIf { !it.isMock } ?: continue
                remote.send(list.map { Triple(it.uuid.uppercase(), it.date, it.text) }, key(l))
                accepted += list.map { it.uuid.uppercase() }
            }
            if (accepted.isNotEmpty()) { edit { x -> LeagueEdits.updateMany(x, "messages", accepted.toSet(), mapOf("syncedAt" to now)) }; clearPending(MESSAGES, accepted) }
            clearPending(MESSAGES, pm.filter { id -> data.messages.orEmpty().none { it.uuid.equals(id, true) } })
            _error.value = null
        }.onFailure { _error.value = message(it) }
    }

    fun draft(j: LeagueJson) = LeagueDraft(j.code, j.name, j.emoji, j.scoring, j.weights ?: "", j.tieBreak ?: "primeiro", j.photoRule ?: "livre",
                                           j.activityRule ?: "", j.settings ?: "", j.teams ?: "", j.start, j.end, j.autoRenew ?: false, j.swiss ?: "pontos")

    private fun extraPlist(list: List<ByteArray>): String {
        val arr = com.dd.plist.NSArray(*list.take(4).map { com.dd.plist.NSData(it) }.toTypedArray())
        return Base64.getEncoder().encodeToString(com.dd.plist.BinaryPropertyListWriter.writeToArray(arr))
    }

    companion object {
        private const val LEAGUES = "leagues"
        private const val CHECKINS = "checkIns"
        private const val MESSAGES = "messages"
        private var current: LeagueStore? = null

        @Synchronized
        fun of(context: Context, uid: String, copies: AccountCopyRepository): LeagueStore {
            current?.takeIf { it.uid == uid }?.let { return it }
            return LeagueStore(context.applicationContext, uid, copies).also { current = it }
        }

        /** Fotos a mais do post (plist de `[Data]` em base64) */
        fun extraPhotos(raw: String?): List<ByteArray> = raw?.let {
            runCatching {
                (com.dd.plist.PropertyListParser.parse(Base64.getDecoder().decode(it)) as com.dd.plist.NSArray).array.mapNotNull { e -> (e as? com.dd.plist.NSData)?.bytes() }
            }.getOrNull()
        }.orEmpty()
    }
}
