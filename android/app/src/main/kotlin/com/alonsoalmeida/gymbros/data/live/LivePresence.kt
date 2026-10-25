package com.alonsoalmeida.gymbros.data.live

import android.content.Context
import com.alonsoalmeida.gymbros.GymBrosApp
import com.alonsoalmeida.gymbros.data.CopyState
import com.alonsoalmeida.gymbros.data.map.GymLocation
import com.alonsoalmeida.gymbros.data.train.TrainCopy
import com.alonsoalmeida.gymbros.data.train.TrainEdits
import com.alonsoalmeida.gymbros.domain.ActivityKind
import com.alonsoalmeida.gymbros.domain.MonsterForm
import com.alonsoalmeida.gymbros.domain.RuleClock
import com.alonsoalmeida.gymbros.domain.backup.AccountCopy
import com.alonsoalmeida.gymbros.domain.home.HomeBuilder
import com.alonsoalmeida.gymbros.domain.map.Coordinate
import com.alonsoalmeida.gymbros.domain.map.GymPlaces
import com.alonsoalmeida.gymbros.domain.social.LivePresenceRules
import com.alonsoalmeida.gymbros.domain.social.LiveShare
import com.alonsoalmeida.gymbros.domain.social.LiveStatus
import com.alonsoalmeida.gymbros.domain.train.Session
import com.alonsoalmeida.gymbros.domain.train.WodRunState
import com.dd.plist.NSDictionary
import com.dd.plist.NSNumber
import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.SetOptions
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.JsonObject
import java.time.Instant
import java.time.ZoneId
import java.util.Date

/**
 * Treino ao vivo: o seu (FirebaseSocial.swift `LivePresence`). Publica o treino em `live/{uid}` enquanto ele roda, se
 * "Ao vivo" estiver ligado para ele: no máximo uma gravação a cada 30 s, além do começo e do fim. Mudança de exercício ou
 * de série sobe na hora (respeitando o intervalo); posição e distância sozinhas esperam a janela. As regras
 * (firestore.rules) só deixam você gravar o seu documento e só amigos mútuos sem bloqueio lerem.
 *
 * Fontes: treino guiado e WOD pela notificação do treino (`LiveWorkout.render`, que vê toda mudança da sessão, aqui ou no
 * iPhone) e o percurso pelo GPS (`RouteRecorder`, a cada ponto novo). Fora de um treino ao vivo nada é enviado.
 */
object LivePresence {
    /** De onde veio o treino publicado: o fim de cada fonte só encerra o que ela publicou */
    enum class Source { WORKOUT, WOD, ROUTE }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val db get() = FirebaseFirestore.getInstance()

    private var workoutID: String? = null
    private var source: Source? = null
    private var last: LiveStatus? = null
    private var lastWrite = 0L
    private var pending: Job? = null
    /** Fora da academia: a posição lida uma vez por treino (treino → posição) */
    private var located: Pair<String, Coordinate>? = null
    private var locating: String? = null

    private fun uid(): String? = FirebaseAuth.getInstance().currentUser?.uid

    private fun copy(c: Context): JsonObject? = ((c.applicationContext as GymBrosApp).container.copies.state.value as? CopyState.Ready)?.copy

    /** Estado novo do treino `id` (`update`) */
    fun update(c: Context, id: String, from: Source, status: LiveStatus) {
        val me = uid() ?: return
        val app = c.applicationContext
        if (!LiveShare.isSharing(id, TrainCopy.settings(copy(app)))) return end(id)
        val changed = workoutID != id || !status.sameAs(last)
        workoutID = id
        source = from
        last = status
        val wait = LivePresenceRules.waitMillis(lastWrite, System.currentTimeMillis())
        if (!LivePresenceRules.shouldSchedule(changed, wait)) return
        pending?.cancel()
        pending = scope.launch {
            if (wait > 0) delay(wait)
            val s = last
            if (s == null || workoutID != id || uid() != me) return@launch
            lastWrite = System.currentTimeMillis()
            write(app, me, s)
        }
    }

    /** Treino encerrado (ou "Ao vivo" desligado nele): fica só o "visto há…". Só encerra o que estava publicando */
    fun end(id: String) {
        if (workoutID != id) return
        val kind = last?.kind
        clear()
        val me = uid() ?: return
        set(me, LivePresenceRules.endedFields(me, kind, Instant.now()))
    }

    /** A fonte acabou (treino salvo ou descartado aqui ou no iPhone, WOD fechado, percurso encerrado) */
    fun endSource(from: Source) { if (source == from) workoutID?.let(::end) }

    /** Sair da conta: encerra o que estiver no ar antes de a sessão acabar (as regras pedem o dono) */
    suspend fun signOut() {
        if (workoutID == null) return clear()
        val kind = last?.kind
        clear()
        val me = uid() ?: return
        withTimeoutOrNull(5_000) { runCatching { ref(me).set(stamped(LivePresenceRules.endedFields(me, kind, Instant.now())), SetOptions.merge()).await() } }
    }

    /** Excluir a conta: o documento é apagado junto; nada pendente pode recriá-lo */
    fun reset() = clear()

    private fun clear() {
        pending?.cancel()
        pending = null
        workoutID = null
        source = null
        last = null
        located = null
    }

    private fun ref(me: String) = db.collection("live").document(me)

    /** Instant → Timestamp; o resto vai como está (null grava null, como o `Fire.fields` do iOS) */
    private fun stamped(fields: Map<String, Any?>): Map<String, Any?> =
        fields.mapValues { (_, v) -> if (v is Instant) Timestamp(Date.from(v)) else v }

    /** Sem esperar a confirmação: sem rede, o Firestore guarda e manda depois (como o `setData` do iOS) */
    private fun set(me: String, fields: Map<String, Any?>) {
        runCatching { ref(me).set(stamped(fields), SetOptions.merge()) }
    }

    private fun write(c: Context, me: String, s: LiveStatus) {
        // Nome do treinador e o bro principal, como aparecem para os amigos (o perfil público mostra o mesmo bro)
        val home = runCatching { copy(c)?.let { HomeBuilder.build(AccountCopy.decode(it), RuleClock(ZoneId.systemDefault(), Instant.now())) } }.getOrNull()
        val name = home?.trainerName?.takeIf { it.isNotEmpty() } ?: FirebaseAuth.getInstance().currentUser?.displayName.orEmpty()
        val formID = home?.takeIf { it.showBro }?.snapshot?.form?.id ?: MonsterForm.EGG.id
        set(me, LivePresenceRules.fields(me, name, formID, s, Instant.now()))
    }

    // MARK: Fontes

    /** Musculação: exercício e série atuais e o que já terminou */
    fun workout(c: Context, s: Session, copy: JsonObject?) {
        if (uid() == null) return
        val gym = GymPlaces.gym(copy, s.gymUUID)
        place(c, s.uuid, gym?.coordinate) { here ->
            update(c, s.uuid, Source.WORKOUT, LivePresenceRules.workout(s, gym?.name.orEmpty(), here))
        }
    }

    /** CrossFit: a parte ou o WOD em andamento (só depois de começar o treino ou o cronômetro) */
    fun wod(c: Context, w: WodRunState, label: String, copy: JsonObject?) {
        if (uid() == null) return
        val start = w.sessionStart ?: w.openedAt
        val gym = GymPlaces.gym(copy, w.gymID)
        val id = liveID(w)
        place(c, id, gym?.coordinate) { here ->
            update(c, id, Source.WOD, LivePresenceRules.wod(w.wod.name, label, start, gym?.name.orEmpty(), here))
        }
    }

    /** Corrida, caminhada e bike: posição e percurso do GPS */
    fun route(c: Context, id: String, kind: ActivityKind, start: Instant, meters: Double, here: Coordinate, route: List<Coordinate>) {
        update(c, id, Source.ROUTE, LivePresenceRules.route(kind, start, meters, here, route))
    }

    /** Id do WOD aberto para a escolha do ao vivo (o `liveID` do WodRun no iOS): fixo enquanto ele está aberto */
    fun liveID(w: WodRunState): String = "WOD-" + w.openedAt.toEpochMilli()

    /** Na academia: o lugar salvo; fora dela, a posição atual (lida uma vez por treino) */
    private fun place(c: Context, id: String, gym: Coordinate?, then: (Coordinate?) -> Unit) {
        if (gym != null) return then(gym)
        located?.takeIf { it.first == id }?.let { return then(it.second) }
        // Só pergunta se este treino compartilha (um treino só seu não lê a posição)
        if (!LiveShare.isSharing(id, TrainCopy.settings(copy(c)))) return then(null)
        if (locating == id) return
        locating = id
        scope.launch {
            val here = GymLocation.currentLocation(c.applicationContext)?.let { Coordinate(it.latitude, it.longitude) }
            locating = null
            if (here != null) located = id to here
            then(here)
        }
    }
}

/**
 * Escolha do ao vivo (LiveShare.swift): o padrão (`shareLive`) e a de cada treino (`shareLiveWorkouts`), nos ajustes
 * da conta, as mesmas chaves do iPhone.
 */
object LiveShareStore {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    fun isSharing(copy: JsonObject?, id: String): Boolean = LiveShare.isSharing(id, TrainCopy.settings(copy))

    /** Liga ou desliga só este treino (o chip "Ao vivo"); desligar tira do ar na hora */
    fun set(c: Context, id: String, on: Boolean) {
        if (!on) LivePresence.end(id)
        val copies = (c.applicationContext as GymBrosApp).container.copies
        scope.launch {
            copies.edit { x ->
                val copy = x ?: return@edit com.alonsoalmeida.gymbros.domain.backup.AccountEdits.empty("", Instant.now())
                val o = LiveShare.overrides(TrainCopy.settings(copy)) + (id to on)
                TrainEdits.setting(copy, LiveShare.OVERRIDES_KEY, dict(o))
            }
        }
    }

    /** Treino encerrado ou descartado: sai do ar e a escolha dele não vale mais */
    fun end(c: Context, id: String) {
        LivePresence.end(id)
        val copies = (c.applicationContext as GymBrosApp).container.copies
        val current = (copies.state.value as? CopyState.Ready)?.copy
        if (id !in LiveShare.overrides(TrainCopy.settings(current))) return
        scope.launch {
            copies.edit { x ->
                val copy = x ?: return@edit com.alonsoalmeida.gymbros.domain.backup.AccountEdits.empty("", Instant.now())
                val o = LiveShare.overrides(TrainCopy.settings(copy))
                if (id !in o) copy else TrainEdits.setting(copy, LiveShare.OVERRIDES_KEY, dict(o - id))
            }
        }
    }

    private fun dict(o: Map<String, Boolean>): NSDictionary = NSDictionary().apply { for ((k, v) in o) put(k, NSNumber(v)) }
}
