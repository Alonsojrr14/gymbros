package com.alonsoalmeida.gymbros.data.leagues

import com.alonsoalmeida.gymbros.domain.leagues.CheckInProof
import com.alonsoalmeida.gymbros.domain.leagues.LeagueSettings
import com.alonsoalmeida.gymbros.domain.leagues.LeagueTeams
import com.alonsoalmeida.gymbros.domain.leagues.RemoteCheckIn
import com.alonsoalmeida.gymbros.domain.leagues.RemoteLeague
import com.alonsoalmeida.gymbros.domain.leagues.RemoteMember
import com.alonsoalmeida.gymbros.domain.leagues.RemoteMessage
import com.alonsoalmeida.gymbros.domain.leagues.RemoteTeam
import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.DocumentSnapshot
import com.google.firebase.firestore.FirebaseFirestore
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.tasks.await
import java.time.Instant
import java.util.Date

/** O que o servidor precisa saber de uma liga para responder (LeagueRemote.swift `LeagueKey`) */
data class LeagueKey(val code: String, val start: Instant, val end: Instant?, val teams: String, val isPrivate: Boolean = false) {
    companion object {
        /** Destino dos posts do perfil (funciona como uma liga só sua) */
        val PROFILE = LeagueKey("profile", Instant.EPOCH, null, "")
    }
}

/** Liga como o servidor guarda: regras e times (LeagueRemote.swift `LeagueDraft`) */
data class LeagueDraft(
    val code: String, val name: String, val emoji: String, val scoring: String, val weights: String, val tieBreak: String,
    val photoRule: String, val activityRule: String?, val settings: String?, val teams: String, val start: Instant, val end: Instant?,
    val autoRenew: Boolean, val swiss: String?,
)

/** Como você aparece numa liga */
data class Membership(val name: String, val formID: String, val teamID: String?, val joinedAt: Instant?)

/** Seu check-in a publicar (LeagueRemote.swift `OutgoingCheckIn`). A foto nunca sobe: fica no aparelho. */
data class OutgoingCheckIn(
    val id: String, val date: Instant, val kindRaw: String, val minutes: Int, val effort: Int, val meters: Double?, val kcal: Double?,
    val title: String, val note: String, val hasPhoto: Boolean, val workoutTypeID: Long?, val place: String?, val proof: CheckInProof,
)

data class RemoteComment(val id: String, val user: String, val userName: String, val item: String, val text: String, val date: Instant)

/**
 * Ligas no Firestore, igual ao iOS (FirebaseBackend.swift `FirebaseLeagueBackend`, CommentSync.swift). As regras do
 * Firestore são a autoridade: cada um só grava o que tem o próprio `user`; só o dono (`owner`) muda as regras da liga.
 * Fotos dos check-ins não sobem (no iPhone vão para o CloudKit; o Android deixa no aparelho).
 */
class LeagueRemote(private val db: FirebaseFirestore = FirebaseFirestore.getInstance()) {
    fun me(): String = FirebaseAuth.getInstance().currentUser?.uid ?: throw IllegalStateException("Entre na sua conta para usar ligas e amigos.")

    private fun DocumentSnapshot.date(k: String): Instant? = getTimestamp(k)?.toDate()?.toInstant()
    private fun ts(i: Instant) = Timestamp(Date.from(i))

    /** Estado da liga: outros participantes, check-ins da temporada, mural e pedidos. Os seus vêm da cópia da conta. */
    suspend fun fetch(key: LeagueKey): RemoteLeague = coroutineScope {
        val me = me()
        val code = key.code
        val members = async { db.collection("members").whereEqualTo("league", code).get().await() }
        // Só a temporada atual: índice league + date
        val checkIns = async { db.collection("checkIns").whereEqualTo("league", code).whereGreaterThanOrEqualTo("date", ts(key.start)).get().await() }
        val messages = async { db.collection("messages").whereEqualTo("league", code).get().await() }
        val requests = async { runCatching { db.collection("joinRequests").whereEqualTo("league", code).get().await() }.getOrNull() }

        val others = members.await().documents.filter { it.getString("user") != me }.mapNotNull { d ->
            val user = d.getString("user") ?: return@mapNotNull null
            RemoteMember(user, d.getString("name") ?: "", d.getString("formID") ?: "egg", d.getString("teamID"), d.date("joinedAt"))
        }
        val teams = LeagueTeams.parse(key.teams).map { t -> RemoteTeam(t.id, t.name, others.filter { it.teamID == t.id }.map { it.id }) }
        val end = key.end ?: Instant.MAX
        val theirs = checkIns.await().documents.filter { it.getString("user") != me }.mapNotNull(::checkIn).filter { it.date <= end }
        val msgs = messages.await().documents.mapNotNull { d ->
            val user = d.getString("user") ?: return@mapNotNull null
            val date = d.date("date") ?: return@mapNotNull null
            if (user == me) null else RemoteMessage(d.id, user, date, d.getString("text") ?: "")
        }.sortedBy { it.date }
        val ids = others.map { it.id }.toSet()
        val reqs = requests.await()?.documents.orEmpty().mapNotNull { d ->
            val user = d.getString("user") ?: return@mapNotNull null
            if (user == me || user in ids) null else RemoteMember(user, d.getString("name") ?: "", d.getString("formID") ?: "egg", joinedAt = d.date("date"))
        }
        RemoteLeague(others, theirs, teams, msgs, reqs)
    }

    private fun checkIn(d: DocumentSnapshot): RemoteCheckIn? {
        val user = d.getString("user") ?: return null
        val date = d.date("date") ?: return null
        return RemoteCheckIn(
            id = d.id, memberID = user, date = date, kindRaw = d.getString("kind") ?: "outro",
            minutes = (d.get("minutes") as? Number)?.toInt() ?: 0, effort = (d.get("effort") as? Number)?.toInt() ?: 5,
            meters = (d.get("meters") as? Number)?.toDouble(), kcal = (d.get("kcal") as? Number)?.toDouble(),
            title = d.getString("title") ?: "", note = d.getString("note") ?: "", hasPhoto = d.getBoolean("hasPhoto") ?: false,
            workoutTypeID = (d.get("workoutType") as? Number)?.toLong(), place = d.getString("place"),
            proof = d.getString("proof")?.let { CheckInProof.parse(it) },
        )
    }

    suspend fun send(messages: List<Triple<String, Instant, String>>, key: LeagueKey) {
        if (messages.isEmpty()) return
        val me = me()
        val batch = db.batch()
        for ((id, date, text) in messages) {
            batch.set(db.collection("messages").document(id), mapOf("league" to key.code, "user" to me, "date" to ts(date), "text" to text))
        }
        batch.commit().await()
    }

    /** Cria (ou atualiza) a liga: você é o dono */
    suspend fun create(d: LeagueDraft) {
        val me = me()
        db.collection("leagues").document(d.code).set(hashMapOf<String, Any?>(
            "code" to d.code, "owner" to me, "name" to d.name, "emoji" to d.emoji, "scoring" to d.scoring, "weights" to d.weights,
            "tieBreak" to d.tieBreak, "photoRule" to d.photoRule, "activityRule" to d.activityRule, "settings" to d.settings,
            "swiss" to d.swiss, "teams" to d.teams, "start" to ts(d.start), "end" to d.end?.let(::ts), "autoRenew" to d.autoRenew,
        ), com.google.firebase.firestore.SetOptions.merge()).await()
    }

    /** Acha a liga pelo código; null = não existe */
    suspend fun join(code: String): LeagueDraft? {
        val d = db.collection("leagues").document(code).get().await()
        if (!d.exists()) return null
        val start = d.date("start") ?: return null
        return LeagueDraft(code, d.getString("name") ?: code, d.getString("emoji") ?: "🏆", d.getString("scoring") ?: "pontos",
                           d.getString("weights") ?: "", d.getString("tieBreak") ?: "primeiro", d.getString("photoRule") ?: "livre",
                           d.getString("activityRule"), d.getString("settings"), d.getString("teams") ?: "", start, d.date("end"),
                           d.getBoolean("autoRenew") ?: false, d.getString("swiss"))
    }

    suspend fun setMembership(m: Membership, key: LeagueKey) {
        val me = me()
        db.collection("members").document("${key.code}-$me").set(hashMapOf<String, Any?>(
            "league" to key.code, "user" to me, "name" to m.name, "formID" to m.formID, "teamID" to m.teamID, "joinedAt" to m.joinedAt?.let(::ts),
        ), com.google.firebase.firestore.SetOptions.merge()).await()
    }

    suspend fun publish(list: List<OutgoingCheckIn>, key: LeagueKey) {
        if (list.isEmpty()) return
        val me = me()
        val batch = db.batch()
        for (c in list) {
            batch.set(db.collection("checkIns").document(c.id), hashMapOf<String, Any?>(
                "league" to key.code, "user" to me, "date" to ts(c.date), "kind" to c.kindRaw, "minutes" to c.minutes, "effort" to c.effort,
                "meters" to c.meters, "kcal" to c.kcal, "title" to c.title, "note" to c.note, "hasPhoto" to c.hasPhoto, "photo" to null,
                "workoutType" to c.workoutTypeID, "place" to c.place, "proof" to c.proof.rawValue.ifEmpty { null },
                // Liga pública: entra no Feed dos amigos (o perfil tem a busca própria)
                "feed" to (key.code != LeagueKey.PROFILE.code && !key.isPrivate),
            ))
        }
        batch.commit().await()
    }

    suspend fun retract(ids: List<String>) {
        for (chunk in ids.chunked(450)) {
            val batch = db.batch()
            chunk.forEach { batch.delete(db.collection("checkIns").document(it)) }
            batch.commit().await()
        }
    }

    /** Sai da liga: seus check-ins dela e o seu lugar saem do servidor */
    suspend fun leave(code: String) {
        val me = me()
        val mine = db.collection("checkIns").whereEqualTo("league", code).whereEqualTo("user", me).get().await().documents.map { it.reference }
        val refs = mine + db.collection("members").document("$code-$me")
        for (chunk in refs.chunked(450)) {
            val batch = db.batch()
            chunk.forEach { batch.delete(it) }
            batch.commit().await()
        }
    }

    suspend fun requestJoin(code: String, m: Membership) {
        val me = me()
        db.collection("joinRequests").document("$code-pedido-$me").set(mapOf(
            "league" to code, "user" to me, "name" to m.name, "formID" to m.formID, "date" to ts(Instant.now()),
        )).await()
    }

    /** Aceito = o dono pôs você em `approved` nas regras da liga */
    suspend fun isApproved(code: String): LeagueDraft? {
        val d = join(code) ?: return null
        return d.takeIf { me() in LeagueSettings.parse(it.settings).approved }
    }

    /** Só o dono atual grava na liga: passar o `owner` entrega a edição */
    suspend fun transfer(code: String, to: String) {
        db.collection("leagues").document(code).update("owner", to).await()
    }

    // MARK: Comentários (CommentSync.swift)

    suspend fun comments(items: List<String>): List<RemoteComment> {
        val out = mutableListOf<RemoteComment>()
        for (chunk in items.distinct().chunked(30)) {
            if (chunk.isEmpty()) continue
            db.collection("comments").whereIn("item", chunk).get().await().documents.forEach { d ->
                val user = d.getString("user") ?: return@forEach
                out += RemoteComment(d.id, user, d.getString("userName") ?: "", d.getString("item") ?: return@forEach,
                                     d.getString("text") ?: return@forEach, d.date("date") ?: Instant.now())
            }
        }
        return out
    }

    suspend fun addComment(id: String, item: String, owner: String, text: String, name: String, date: Instant) {
        val me = me()
        db.collection("comments").document(id).set(mapOf(
            "user" to me, "userName" to name, "item" to item, "owner" to if (owner == "me") me else owner, "text" to text, "date" to ts(date),
        )).await()
    }

    suspend fun removeComment(id: String) { db.collection("comments").document(id).delete().await() }

    /** Papéis da conta (só leitura): sem atribuição, USER */
    suspend fun roles(): Set<String> {
        val doc = db.collection("roles").document(me()).get().await()
        if (!doc.exists()) return setOf("USER")
        @Suppress("UNCHECKED_CAST")
        return ((doc.get("roles") as? List<String>) ?: emptyList()).toSet()
    }

}
