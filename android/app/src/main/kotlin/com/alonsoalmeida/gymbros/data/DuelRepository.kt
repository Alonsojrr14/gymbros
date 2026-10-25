package com.alonsoalmeida.gymbros.data

import com.alonsoalmeida.gymbros.domain.MonsterForm
import com.alonsoalmeida.gymbros.domain.duel.DuelAnswer
import com.alonsoalmeida.gymbros.domain.duel.DuelMetric
import com.alonsoalmeida.gymbros.domain.duel.DuelPerson
import com.alonsoalmeida.gymbros.domain.duel.DuelRefusal
import com.alonsoalmeida.gymbros.domain.duel.DuelRefusalException
import com.alonsoalmeida.gymbros.domain.duel.RemoteDuel
import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import kotlinx.coroutines.tasks.await
import java.time.Instant
import java.util.Date
import java.util.UUID

/**
 * X1 no Firestore, igual ao iOS (Services/FirebaseGame.swift `FirebaseDuelBackend`): um documento por X1 em `duels`.
 * Quem desafia cria; só o desafiado responde (uma vez, em até 24 h) e cada lado só escreve o próprio valor
 * (`score_<uid>`). As datas são do servidor; as regras do Firestore são a autoridade. Uma consulta por atualização,
 * só dos últimos 30 dias (ADR-013).
 */
class DuelRepository(private val db: FirebaseFirestore = FirebaseFirestore.getInstance()) {
    private val col get() = db.collection("duels")

    fun me(): String = FirebaseAuth.getInstance().currentUser?.uid ?: throw IllegalStateException("sem sessão")

    private fun denied(e: Throwable) = (e as? FirebaseFirestoreException)?.code == FirebaseFirestoreException.Code.PERMISSION_DENIED

    private fun date(v: Any?): Instant? = (v as? Timestamp)?.toDate()?.toInstant()

    /** X1 em que você está (desafiou ou foi desafiado), dos últimos 30 dias, com os ids do servidor */
    suspend fun duels(now: Instant): List<RemoteDuel> {
        val me = me()
        val since = Date.from(now.minusSeconds(30L * 86_400))
        val docs = col.whereArrayContains("participants", me).whereGreaterThanOrEqualTo("createdAt", since).get().await().documents
        return docs.mapNotNull { doc ->
            val d = doc.data ?: return@mapNotNull null
            val from = d["challenger"] as? String ?: return@mapNotNull null
            val to = d["challenged"] as? String ?: return@mapNotNull null
            val metric = DuelMetric.of(d["metric"] as? String) ?: return@mapNotNull null
            val reported = buildMap {
                for (u in listOf(from, to)) (d["score_$u"] as? Number)?.let { put(u, it.toInt()) }
            }
            RemoteDuel(
                id = doc.id,
                challenger = DuelPerson(from, d["challengerName"] as? String ?: "", d["challengerFormID"] as? String ?: MonsterForm.EGG.id),
                challenged = DuelPerson(to, d["challengedName"] as? String ?: "", d["challengedFormID"] as? String ?: MonsterForm.EGG.id),
                metric = metric,
                // Criado agora e ainda sem a hora do servidor (cache local): vale o relógio do aparelho, como no iOS
                createdAt = date(d["createdAt"]) ?: now,
                answer = DuelAnswer.of(d["answer"] as? String),
                answeredAt = date(d["answeredAt"]),
                reported = reported,
            )
        }
    }

    /** Desafia alguém; devolve o desafio criado (com o seu id do servidor) */
    suspend fun challenge(opponent: DuelPerson, from: DuelPerson, metric: DuelMetric, now: Instant): RemoteDuel {
        val my = me()
        if (opponent.id == my) throw DuelRefusalException(DuelRefusal.YOURSELF)
        val ref = col.document("duel-${UUID.randomUUID().toString().uppercase()}")
        try {
            ref.set(mapOf(
                "challenger" to my, "challengerName" to from.name, "challengerFormID" to from.formID,
                "challenged" to opponent.id, "challengedName" to opponent.name, "challengedFormID" to opponent.formID,
                "participants" to listOf(my, opponent.id), "metric" to metric.raw, "createdAt" to FieldValue.serverTimestamp(),
            )).await()
        } catch (e: Exception) {
            // A regra só recusa quem não é seu amigo ou te bloqueou
            if (denied(e)) throw DuelRefusalException(DuelRefusal.BLOCKED)
            throw e
        }
        return RemoteDuel(ref.id, DuelPerson(my, from.name, from.formID), opponent, metric, now)
    }

    /** Aceita ou recusa; ao aceitar, leva o bro que vai lutar (quem desafiou só sabia o seu principal) */
    suspend fun respond(duelID: String, accept: Boolean, person: DuelPerson) {
        val data = mutableMapOf<String, Any>(
            "answer" to (if (accept) DuelAnswer.ACCEPTED else DuelAnswer.DECLINED).raw,
            "answeredAt" to FieldValue.serverTimestamp(),
        )
        if (accept) data["challengedFormID"] = person.formID
        try {
            col.document(duelID).update(data).await()
        } catch (e: Exception) {
            if (denied(e)) throw DuelRefusalException(DuelRefusal.NOT_PENDING)
            throw e
        }
    }

    /** Informa o seu valor no X1 (calculado das suas atividades) */
    suspend fun report(value: Int, duelID: String) {
        col.document(duelID).update(mapOf("score_${me()}" to value.toLong())).await()
    }
}

/** Amigo treinando agora (ou que terminou há pouco), lido de `live/{uid}` (FirebaseSocial.swift `LiveFriend(fire:)`) */
data class LiveFriend(
    val id: String,
    val name: String,
    val formID: String,
    val kind: com.alonsoalmeida.gymbros.domain.ActivityKind,
    /** Começou o treino (null: não está treinando agora) */
    val start: Instant?,
    val place: String,
    val now: String,
    val endedAt: Instant?,
    /** Última posição enviada e o percurso (corrida, caminhada, bike), para o mapa */
    val location: com.alonsoalmeida.gymbros.domain.map.Coordinate? = null,
    val route: List<com.alonsoalmeida.gymbros.domain.map.Coordinate> = emptyList(),
) {
    val form: MonsterForm get() = MonsterForm.byID(formID) ?: MonsterForm.EGG
    val isLive: Boolean get() = start != null
    /** Anda no mapa (deixa rastro) */
    val moves: Boolean get() = route.size > 1
    /** Onde aparece: a posição, o fim do percurso ou, sem nada, o lugar base (FriendsLive.swift `coordinate`) */
    fun coordinate(base: com.alonsoalmeida.gymbros.domain.map.Coordinate): com.alonsoalmeida.gymbros.domain.map.Coordinate = location ?: route.lastOrNull() ?: base

    companion object {
        /** Quem terminou há mais que isso some da lista */
        const val RECENT_SECONDS = 12L * 3600
        /** Sem notícia há 15 min (app fechado no meio do treino, sem rede): conta como encerrado */
        const val STALE_SECONDS = 15L * 60

        fun of(id: String, d: Map<String, Any?>, now: Instant): LiveFriend? {
            val raw = d["kind"] as? String ?: return null
            val kind = com.alonsoalmeida.gymbros.domain.ActivityKind.entries.firstOrNull { it.raw == raw } ?: return null
            val reportedAt = (d["updatedAt"] as? Timestamp)?.toDate()?.toInstant() ?: now
            val stale = now.epochSecond - reportedAt.epochSecond > STALE_SECONDS
            val start = if (stale) null else (d["start"] as? Timestamp)?.toDate()?.toInstant()
            val ended = (d["endedAt"] as? Timestamp)?.toDate()?.toInstant() ?: if (stale) reportedAt else null
            val flat = (d["route"] as? List<*>).orEmpty().mapNotNull { (it as? Number)?.toDouble() }
            val route = (0 until flat.size - 1 step 2).map { com.alonsoalmeida.gymbros.domain.map.Coordinate(flat[it], flat[it + 1]) }
            val lat = (d["latitude"] as? Number)?.toDouble()
            val lon = (d["longitude"] as? Number)?.toDouble()
            return LiveFriend(id, d["name"] as? String ?: "", d["formID"] as? String ?: MonsterForm.EGG.id, kind, start,
                              d["place"] as? String ?: "", d["now"] as? String ?: "", ended,
                              if (lat != null && lon != null) com.alonsoalmeida.gymbros.domain.map.Coordinate(lat, lon) else null, route)
        }
    }
}

/**
 * Treino ao vivo dos amigos (FirebaseSocial.swift `LiveFriendsStore`): um ouvinte por amigo em `live/{uid}` (as regras
 * só deixam ler amigos mútuos). Quem chama liga só com a aba Mapa visível e desliga ao sair (ADR-013). Só leitura: o
 * seu treino ao vivo é publicado pelo `LivePresence` (data/live).
 */
class LiveFriendsRepository(private val db: FirebaseFirestore = FirebaseFirestore.getInstance()) {
    /** Escuta os amigos `ids`; `onChange` recebe os documentos por id (null: sem documento). Devolve como parar */
    fun watch(ids: List<String>, onChange: (String, Map<String, Any?>?) -> Unit): () -> Unit {
        val regs = ids.distinct().filter { it.isNotEmpty() }.map { id ->
            db.collection("live").document(id).addSnapshotListener { snap, _ -> onChange(id, snap?.data) }
        }
        return { regs.forEach { it.remove() } }
    }
}
