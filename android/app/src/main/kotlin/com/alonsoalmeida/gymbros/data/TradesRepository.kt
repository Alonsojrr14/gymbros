package com.alonsoalmeida.gymbros.data

import com.alonsoalmeida.gymbros.domain.MonsterForm
import com.alonsoalmeida.gymbros.domain.bros.TradeAnswer
import com.alonsoalmeida.gymbros.domain.bros.TradeBro
import com.alonsoalmeida.gymbros.domain.bros.TradeException
import com.alonsoalmeida.gymbros.domain.bros.TradePerson
import com.alonsoalmeida.gymbros.domain.bros.TradeProposal
import com.alonsoalmeida.gymbros.domain.bros.TradeRefusal
import com.alonsoalmeida.gymbros.domain.bros.TradeRules
import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.DocumentSnapshot
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import kotlinx.coroutines.tasks.await
import java.time.Duration
import java.time.Instant
import java.util.Date
import java.util.UUID

/**
 * Trocas no Firestore, iguais ao iPhone (FirebaseGame.swift `FirebaseTradeBackend`): uma proposta por documento em
 * `trades` (datas do servidor, conferidas pelas regras) e os bros que você pode trocar em `tradeBros/{uid}` para os
 * amigos escolherem. Cada aparelho aplica a sua parte da troca aceita na cópia da conta (TradeLedger).
 */
class TradesRepository(private val db: FirebaseFirestore = FirebaseFirestore.getInstance()) {
    private val col get() = db.collection("trades")
    /** Lista já publicada nesta sessão (o iPhone guarda no aparelho): só grava quando muda */
    private var published: String? = null

    private fun me(): String = FirebaseAuth.getInstance().currentUser?.uid ?: throw IllegalStateException("sem sessão")

    private fun date(v: Any?): Instant? = (v as? Timestamp)?.toDate()?.toInstant()

    /** Bros de um amigo (para escolher o que pedir) */
    suspend fun bros(friendID: String): List<TradeBro> =
        TradeRules.decodeList(db.collection("tradeBros").document(friendID).get().await().getString("bros"))

    /** Publica os seus bros que podem entrar e devolve as trocas dos últimos 30 dias em que você está */
    suspend fun proposals(now: Instant, mine: List<TradeBro>): List<TradeProposal> {
        val my = me()
        publish(mine, my)
        val since = Date.from(now.minus(Duration.ofDays(30)))
        val docs = col.whereArrayContains("participants", my).whereGreaterThanOrEqualTo("createdAt", since).get().await().documents
        return docs.mapNotNull { parse(it, my, now) }.filter { it.answer != TradeAnswer.CANCELED }
    }

    private fun parse(doc: DocumentSnapshot, my: String, now: Instant): TradeProposal? {
        // Horário do servidor estimado enquanto a gravação ainda não voltou
        val d = doc.getData(DocumentSnapshot.ServerTimestampBehavior.ESTIMATE) ?: return null
        val from = d["from"] as? String ?: return null
        val to = d["to"] as? String ?: return null
        val give = TradeRules.decode(d["give"] as? String) ?: return null
        val get = TradeRules.decode(d["get"] as? String) ?: return null
        // O app chama você de "me"
        fun person(id: String, prefix: String) = TradePerson(if (id == my) TradeProposal.ME else id, d["${prefix}Name"] as? String ?: "",
                                                             d["${prefix}FormID"] as? String ?: MonsterForm.EGG.id)
        return TradeProposal(doc.id, person(from, "from"), person(to, "to"), give, get, date(d["createdAt"]) ?: now,
                             TradeAnswer.of(d["answer"] as? String), date(d["answeredAt"]))
    }

    private suspend fun publish(mine: List<TradeBro>, my: String) {
        val raw = TradeRules.publishedJson(mine)
        if (published == "$my:$raw") return
        db.collection("tradeBros").document(my).set(mapOf("user" to my, "bros" to raw, "updatedAt" to Date())).await()
        published = "$my:$raw"
    }

    suspend fun propose(friend: TradePerson, me: TradePerson, give: TradeBro, get: TradeBro, now: Instant): TradeProposal {
        val my = me()
        val ref = col.document(UUID.randomUUID().toString().uppercase())
        ref.set(mapOf(
            "from" to my, "fromName" to me.name, "fromFormID" to me.formID, "to" to friend.id, "toName" to friend.name,
            "toFormID" to friend.formID, "participants" to listOf(my, friend.id), "give" to TradeRules.encode(give),
            "get" to TradeRules.encode(get), "createdAt" to FieldValue.serverTimestamp(),
        )).await()
        return TradeProposal(ref.id, me, friend, give, get, now)
    }

    suspend fun respond(id: String, accept: Boolean) = answer(id, if (accept) TradeAnswer.ACCEPTED else TradeAnswer.DECLINED)

    suspend fun cancel(id: String) = answer(id, TradeAnswer.CANCELED)

    private suspend fun answer(id: String, a: TradeAnswer) {
        try {
            col.document(id).update(mapOf("answer" to a.raw, "answeredAt" to FieldValue.serverTimestamp())).await()
        } catch (e: FirebaseFirestoreException) {
            if (e.code == FirebaseFirestoreException.Code.PERMISSION_DENIED) throw TradeException(TradeRefusal.NotPending)
            throw e
        }
    }

    /**
     * Bros seus num X1 aberto (pendente que você mandou, ou aceito e em andamento), pelo representante de cada X1
     * guardado na conta (`duelMonsters`). Fonte: Duel.swift (`busyFighters`, `phase`).
     */
    suspend fun busyFighters(representatives: Map<String, String>, now: Instant): Set<String> {
        if (representatives.isEmpty()) return emptySet()
        val my = me()
        val since = Date.from(now.minus(Duration.ofDays(30)))
        val window = Duration.ofHours(24)
        return db.collection("duels").whereArrayContains("participants", my).whereGreaterThanOrEqualTo("createdAt", since).get().await()
            .documents.mapNotNull { doc ->
                val d = doc.getData(DocumentSnapshot.ServerTimestampBehavior.ESTIMATE) ?: return@mapNotNull null
                val rep = representatives[doc.id] ?: return@mapNotNull null
                val created = date(d["createdAt"]) ?: now
                val accepted = if (d["answer"] == "accepted") date(d["answeredAt"]) else null
                val open = when (d["answer"] as? String) {
                    "accepted" -> accepted != null && now < accepted.plus(window)
                    null -> now < created.plus(window)
                    else -> false
                }
                rep.takeIf { open && (accepted != null || d["challenger"] == my) }
            }.toSet()
    }
}
