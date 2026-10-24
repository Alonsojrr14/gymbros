package com.alonsoalmeida.gymbros.data.social

import com.alonsoalmeida.gymbros.domain.ActivityKind
import com.alonsoalmeida.gymbros.domain.MonsterForm
import com.alonsoalmeida.gymbros.domain.social.BlockedUser
import com.alonsoalmeida.gymbros.domain.social.DirectKind
import com.alonsoalmeida.gymbros.domain.social.DirectMessage
import com.alonsoalmeida.gymbros.domain.social.InboxPeer
import com.alonsoalmeida.gymbros.domain.social.InboxRules
import com.alonsoalmeida.gymbros.domain.social.ReportReason
import com.alonsoalmeida.gymbros.domain.social.ReportedContent
import com.alonsoalmeida.gymbros.domain.social.SocialComment
import com.alonsoalmeida.gymbros.domain.social.TrainInvite
import com.google.firebase.Timestamp
import com.alonsoalmeida.gymbros.domain.social.CommentScope
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.DocumentSnapshot
import com.google.firebase.firestore.FieldPath
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.SetOptions
import kotlinx.coroutines.tasks.await
import java.time.Instant
import java.util.Date
import java.util.UUID

/** Check-in de outra pessoa como está em `checkIns` (FirebaseBackend.swift `RemoteCheckIn(fire:)`) */
data class RemoteCheckIn(
    val id: String, val memberID: String, val date: Instant, val kind: ActivityKind, val minutes: Int, val effort: Int,
    val title: String, val note: String, val hasPhoto: Boolean, val place: String?, val league: String?, val postedIn: String? = null,
    /** Postado numa liga pública (vai para o Feed dos amigos) */
    val feed: Boolean = false,
)

/**
 * Parte social no Firestore, igual ao iOS (FirebaseBackend.swift, FirebaseSocial.swift, FirebaseGame.swift e
 * CommentSync.swift). As regras (firebase/firestore.rules) são a autoridade: cada um só grava o que é seu (`user`/`from`
 * = uid); mensagens diretas só as duas pontas leem; denúncias só admin lê. Fotos de check-in não sobem (ficam no aparelho).
 *
 * Plano grátis: toda consulta tem janela de datas ou limite, e as escutas ao vivo só ficam ligadas com a tela aberta.
 */
class SocialRepository(private val db: FirebaseFirestore = FirebaseFirestore.getInstance()) {
    fun me(): String = FirebaseAuth.getInstance().currentUser?.uid ?: throw IllegalStateException("sem sessão")

    private fun Any?.instant(): Instant? = (this as? Timestamp)?.toDate()?.toInstant() ?: (this as? Date)?.toInstant()

    private fun checkIn(d: DocumentSnapshot, postedIn: String? = null): RemoteCheckIn? {
        val user = d.getString("user") ?: return null
        val date = d.get("date").instant() ?: return null
        return RemoteCheckIn(d.id, user, date, ActivityKind.of(d.getString("kind") ?: "outro"), (d.getLong("minutes") ?: 0).toInt(),
                             (d.getLong("effort") ?: 5).toInt(), d.getString("title") ?: "", d.getString("note") ?: "",
                             d.getBoolean("hasPhoto") ?: false, d.getString("place"), d.getString("league"), postedIn,
                             d.getBoolean("feed") ?: false)
    }

    // MARK: Posts

    /** Posts do perfil da pessoa, do mais novo para o mais antigo; nulo se ela escondeu os treinos de você */
    suspend fun profilePosts(id: String, hiddenFrom: List<String>): List<RemoteCheckIn>? {
        if (me() in hiddenFrom) return null
        // Os últimos 200 (o calendário do perfil mostra meses; o iOS traz todos)
        val docs = db.collection("checkIns").whereEqualTo("league", PROFILE_CODE).whereEqualTo("user", id).limit(200).get().await().documents
        return docs.mapNotNull { checkIn(it) }.sortedByDescending { it.date }
    }

    /**
     * Check-ins da pessoa em ligas públicas dos últimos 7 dias, com o nome da liga ("🔥 Liga"). Confere a liga agora: se
     * virou privada depois, sai. A janela vai na consulta (índice `user` + `feed` + `date`); sem o índice publicado, cai
     * no jeito do iOS (traz os com `feed` e filtra aqui), com limite.
     */
    suspend fun leaguePosts(id: String, now: Instant = Instant.now()): List<RemoteCheckIn> {
        val since = now.minusSeconds(7 * 86_400)
        val base = db.collection("checkIns").whereEqualTo("user", id).whereEqualTo("feed", true)
        val docs = try {
            base.whereGreaterThanOrEqualTo("date", Timestamp(Date.from(since))).limit(100).get().await().documents
        } catch (e: FirebaseFirestoreException) {
            if (e.code != FirebaseFirestoreException.Code.FAILED_PRECONDITION) throw e
            base.limit(300).get().await().documents
        }.filter { (it.get("date").instant() ?: Instant.MIN) >= since }
        val codes = docs.mapNotNull { it.getString("league") }.distinct()
        val open = HashMap<String, String>()
        for (chunk in codes.chunked(30)) {
            for (l in db.collection("leagues").whereIn(FieldPath.documentId(), chunk).get().await().documents) {
                val private = l.getString("settings")?.contains("\"isPrivate\":true") == true
                if (!private) open[l.id] = "${l.getString("emoji") ?: "🏆"} ${l.getString("name") ?: ""}"
            }
        }
        return docs.mapNotNull { d -> d.getString("league")?.let(open::get)?.let { checkIn(d, it) } }.sortedByDescending { it.date }
    }

    /** Check-ins dos outros numa liga sua, da temporada atual (índice `league` + `date`, já publicado), com limite */
    suspend fun leagueCheckIns(code: String, start: Instant): List<RemoteCheckIn> {
        val me = me()
        return db.collection("checkIns").whereEqualTo("league", code).whereGreaterThanOrEqualTo("date", Timestamp(Date.from(start)))
            .limit(300).get().await().documents.mapNotNull { checkIn(it) }.filter { it.memberID != me }
    }

    /** Tira do servidor um check-in seu (as regras só deixam apagar o que é seu) */
    suspend fun retractCheckIn(id: String) {
        db.collection("checkIns").document(id.uppercase()).delete().await()
    }

    // MARK: Comentários (CommentSync.swift)

    private fun comment(d: DocumentSnapshot, me: String): SocialComment? {
        val user = d.getString("user") ?: return null
        if (user == me) return null
        runCatching { UUID.fromString(d.id) }.getOrNull() ?: return null
        val item = d.getString("item") ?: return null
        val text = d.getString("text") ?: return null
        return SocialComment(d.id.uppercase(), item, text, d.get("date").instant() ?: Instant.now(), user, d.getString("userName") ?: "")
    }

    /** Comentários dos outros nesses posts (os seus vêm da cópia da conta) */
    /** Uma consulta por liga (e, fora das suas ligas, por dono e `feed`): é o que a regra do servidor consegue conferir */
    private fun query(scope: CommentScope, me: String): com.google.firebase.firestore.Query {
        var q: com.google.firebase.firestore.Query = db.collection(COMMENTS).whereEqualTo("league", scope.league)
        if (!scope.member && scope.league != CommentScope.PROFILE_CODE) {
            q = q.whereEqualTo("poster", if (scope.owner == "me") me else scope.owner).whereEqualTo("feed", true)
        }
        return q
    }

    /** Comentários e reações desses posts (CommentSync.pull), agrupados pela liga de cada um */
    suspend fun comments(items: List<Pair<String, CommentScope>>): List<SocialComment> {
        val me = me()
        val out = ArrayList<SocialComment>()
        for ((scope, group) in items.groupBy({ it.second }, { it.first })) {
            for (chunk in group.distinct().chunked(30)) {
                // Erro em qualquer grupo cancela tudo: quem chama não apaga os comentários guardados por engano
                query(scope, me).whereIn("item", chunk).get().await().documents.mapNotNullTo(out) { comment(it, me) }
            }
        }
        return out
    }

    /** Ao vivo, com o post aberto: comentário novo de outra pessoa aparece na hora. Devolve como parar */
    fun watchComments(items: List<Pair<String, CommentScope>>, onChange: (List<SocialComment>) -> Unit): () -> Unit {
        val me = runCatching { me() }.getOrNull() ?: return {}
        val groups = items.groupBy({ it.second }, { it.first }).mapValues { it.value.distinct().take(30) }.filterValues { it.isNotEmpty() }
        val latest = java.util.concurrent.ConcurrentHashMap<CommentScope, List<SocialComment>>()
        val regs = groups.map { (scope, ids) ->
            query(scope, me).whereIn("item", ids).addSnapshotListener { snap, _ ->
                if (snap == null || snap.metadata.hasPendingWrites()) return@addSnapshotListener
                latest[scope] = snap.documents.mapNotNull { comment(it, me) }
                onChange(latest.values.flatten())
            }
        }
        return { regs.forEach { it.remove() } }
    }

    /** Sobe o seu comentário ou reação. `owner`: dono do post ("me" = você) */
    suspend fun publishComment(c: SocialComment, owner: String, myName: String, scope: CommentScope) {
        val me = me()
        db.collection(COMMENTS).document(c.id.uppercase()).set(mapOf(
            "user" to me, "userName" to myName, "item" to c.itemID, "owner" to (if (owner == "me") me else owner),
            "text" to c.text, "date" to Timestamp(Date.from(c.date)),
            // Liga do post e se é pública: o servidor só deixa ler quem pode ver o post
            "league" to scope.league, "feed" to scope.isPublic, "poster" to (if (scope.owner == "me") me else scope.owner),
        )).await()
    }

    suspend fun retractComment(id: String) {
        db.collection(COMMENTS).document(id.uppercase()).delete().await()
    }

    // MARK: Mensagens diretas (FirebaseSocial.swift)

    private fun message(d: DocumentSnapshot, me: String): DirectMessage? {
        val from = d.getString("from") ?: return null
        val to = d.getString("to") ?: return null
        val date = d.get("date").instant() ?: return null
        @Suppress("UNCHECKED_CAST")
        val invite = (d.get("invite") as? Map<String, Any?>)?.let { i ->
            TrainInvite(i["kind"] as? String ?: "outro", i["place"] as? String ?: "", i["when"].instant(),
                        i["latitude"] as? Double, i["longitude"] as? Double)
        }
        return DirectMessage(d.id, if (from == me) to else from, from == me, date, DirectKind.of(d.getString("kind")), d.getString("text") ?: "",
                             invite, d.getString("replyTo"), d.getBoolean("accepted"))
    }

    /**
     * As mensagens dos últimos 90 dias, ao vivo (índice `participants` + `date`, já publicado). Liga só com a caixa de
     * entrada aberta; cada mudança custa só a leitura do que mudou. Devolve como parar.
     */
    fun watchMessages(onChange: (List<DirectMessage>) -> Unit, onError: (String) -> Unit): () -> Unit {
        val me = runCatching { me() }.getOrNull() ?: return {}
        val since = Timestamp(Date.from(Instant.now().minusSeconds(InboxRules.WINDOW_SECONDS)))
        val reg = db.collection(DMS).whereArrayContains("participants", me).whereGreaterThan("date", since)
            .addSnapshotListener { snap, error ->
                if (error != null) onError("Confira a internet e tente de novo.")
                if (snap != null) onChange(snap.documents.mapNotNull { message(it, me) })
            }
        return { reg.remove() }
    }

    /** Entrega a mensagem (as regras conferem: você manda, para quem te adicionou e não te bloqueou) */
    suspend fun send(m: DirectMessage) {
        val me = me()
        val data = hashMapOf<String, Any?>(
            "from" to me, "to" to m.peerID, "participants" to listOf(me, m.peerID), "date" to Timestamp(Date.from(m.date)),
            "kind" to m.kind.raw, "text" to m.text, "replyTo" to m.replyTo, "accepted" to m.accepted,
        )
        m.invite?.let { i ->
            data["invite"] = mapOf("kind" to i.kindRaw, "place" to i.place, "when" to i.whenAt?.let { Timestamp(Date.from(it)) },
                                   "latitude" to i.latitude, "longitude" to i.longitude)
        }
        db.collection(DMS).document(m.id).set(data).await()
    }

    /** Nome e bro de quem não é amigo (os amigos já vêm da tela de amigos) */
    suspend fun peers(ids: Collection<String>): List<InboxPeer> {
        val out = ArrayList<InboxPeer>()
        for (chunk in ids.distinct().chunked(30)) {
            db.collection("profiles").whereIn(FieldPath.documentId(), chunk).get().await().documents.mapTo(out) {
                InboxPeer(it.id, it.getString("name") ?: "", it.getString("broFormID") ?: MonsterForm.EGG.id)
            }
        }
        return out
    }

    // MARK: Moderação (FirebaseGame.swift `FirebaseModerationBackend`)

    /** Denúncia em `reports/{você}-{tipo}:{id}`: só admins leem; a data é a do servidor */
    suspend fun report(c: ReportedContent, reason: ReportReason) {
        val me = me()
        db.collection("reports").document("$me-${c.key}").set(mapOf(
            "user" to me, "kind" to c.kind.raw, "contentID" to c.id, "author" to c.authorID, "authorName" to c.authorName,
            "reason" to reason.raw, "date" to FieldValue.serverTimestamp(),
        )).await()
    }

    /** Bloqueio em `blocks/{você}->{pessoa}`: as regras usam para impedir mensagens, X1 e trocas; desfaz a amizade */
    suspend fun block(id: String, name: String) {
        val me = me()
        db.collection("blocks").document("$me->$id").set(mapOf("user" to me, "blocked" to id, "name" to name, "date" to Timestamp.now())).await()
        runCatching { db.collection("friendLinks").document("$me->$id").delete().await() }
    }

    suspend fun unblock(id: String) {
        db.collection("blocks").document("${me()}->$id").delete().await()
    }

    suspend fun blockedUsers(): List<BlockedUser> =
        db.collection("blocks").whereEqualTo("user", me()).get().await().documents.mapNotNull { d ->
            val id = d.getString("blocked") ?: return@mapNotNull null
            BlockedUser(id, d.getString("name") ?: "", d.get("date").instant() ?: Instant.now())
        }

    /** Quem não vê seus treinos (`profiles/{você}.hiddenFrom`; o app de quem foi escondido respeita, não é sigilo) */
    suspend fun setHidden(ids: List<String>) {
        db.collection("profiles").document(me()).set(mapOf("hiddenFrom" to ids), SetOptions.merge()).await()
    }

    /** Em quais dessas ligas (códigos) a pessoa também está: uma consulta só (`members` por `user` e `league`) */
    suspend fun leaguesWith(id: String, codes: List<String>): Set<String> {
        val out = HashSet<String>()
        for (chunk in codes.distinct().chunked(30)) {
            db.collection("members").whereEqualTo("user", id).whereIn("league", chunk).get().await().documents.mapNotNullTo(out) { it.getString("league") }
        }
        return out
    }

    /** Perfis de várias pessoas de uma vez: quem elas esconderam e a forma do bro público (avatar dos posts) */
    suspend fun profileCards(ids: Collection<String>): Map<String, ProfileCard> {
        val out = HashMap<String, ProfileCard>()
        for (chunk in ids.distinct().chunked(30)) {
            for (d in db.collection("profiles").whereIn(FieldPath.documentId(), chunk).get().await().documents) {
                @Suppress("UNCHECKED_CAST")
                val hidden = (d.get("hiddenFrom") as? List<String>).orEmpty()
                val bro = d.getString("public")?.let { Regex("\"formID\"\\s*:\\s*\"([^\"]+)\"").find(it)?.groupValues?.get(1) }
                out[d.id] = ProfileCard(hidden, bro ?: d.getString("broFormID"))
            }
        }
        return out
    }

    data class ProfileCard(val hiddenFrom: List<String>, val formID: String?)

    companion object {
        /** `CloudType.profileFeed`: a "liga" dos posts do perfil */
        const val PROFILE_CODE = "profile"
        const val COMMENTS = "comments"
        const val DMS = "directMessages"
    }
}
