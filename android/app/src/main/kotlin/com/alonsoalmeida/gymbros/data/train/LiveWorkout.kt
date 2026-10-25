package com.alonsoalmeida.gymbros.data.train

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.alonsoalmeida.gymbros.GymBrosApp
import com.alonsoalmeida.gymbros.MainActivity
import com.alonsoalmeida.gymbros.R
import com.alonsoalmeida.gymbros.data.AccountCopyRepository
import com.alonsoalmeida.gymbros.data.CopyState
import com.alonsoalmeida.gymbros.domain.train.Exercises
import com.alonsoalmeida.gymbros.domain.train.Session
import com.alonsoalmeida.gymbros.domain.train.WodFormat
import com.alonsoalmeida.gymbros.domain.train.WodRunState
import com.alonsoalmeida.gymbros.domain.train.clock
import com.alonsoalmeida.gymbros.domain.train.setText
import com.google.firebase.auth.FirebaseAuth
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.JsonObject
import java.time.Instant

/**
 * Treino e WOD em andamento fora do app: o Live Activity do iOS (LiveWorkout.swift, WorkoutLiveActivity.swift,
 * WodLiveActivity.swift) vira uma notificação contínua. Treino: exercício, série X de Y, séries feitas e, no descanso, a
 * contagem regressiva; botões "✓ Série feita" e "Pular descanso" (WorkoutIntents.swift). WOD: nome, formato, cronômetro
 * e "+1 rodada". Tocar abre a tela do treino.
 *
 * Notificação comum atualizada pelo app, sem serviço em primeiro plano: o estado mora na cópia da conta (treino) e nas
 * preferências (WOD) e só muda quando o app grava; o cronômetro e a contagem são desenhados pelo próprio sistema
 * (Chronometer da notificação). O único momento sem gravação é o fim do descanso: com o processo vivo, o app redesenha na
 * hora; com ele morto, o alarme do descanso (RestAlarm) acorda o app e redesenha. Um serviço exigiria tipo e permissão
 * especiais (`health`/`specialUse`) sem trabalho contínuo para fazer.
 *
 * Os botões editam a sessão pela mesma via que a tela: com a tela do treino aberta, é ela que aplica (ela é a dona da
 * sessão enquanto aberta) e grava na hora na cópia da conta; fechada, a mudança vai direto na cópia (`copies.edit`).
 * Assim tela, iPhone e notificação veem o mesmo treino.
 */
object LiveWorkout {
    private const val CHANNEL = "live"
    private const val WORKOUT_ID = 4202
    private const val WOD_ID = 4203
    private const val PREFIX = "com.alonsoalmeida.gymbros.live."
    internal const val SET_DONE = PREFIX + "SET_DONE"
    internal const val SKIP_REST = PREFIX + "SKIP_REST"
    internal const val ADD_ROUND = PREFIX + "ADD_ROUND"
    private const val EXTRA_OPEN = "gymbros.live.open"
    const val OPEN_WORKOUT = "workout"
    const val OPEN_WOD = "wod"

    enum class Action { SET_DONE, SKIP_REST }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    /**
     * Tela do treino aberta: os botões passam por ela. Só na thread principal; a tela registra ao abrir e tira ao fechar.
     */
    var screen: ((Action) -> Unit)? = null

    private val _open = MutableStateFlow<String?>(null)
    /** Toque na notificação: a aba Treino abre o treino (`OPEN_WORKOUT`) ou o WOD (`OPEN_WOD`) e chama `opened()` */
    val open: StateFlow<String?> = _open.asStateFlow()

    /** Intent que abriu (ou voltou para) o app: guarda o pedido de abrir o treino e o consome */
    fun take(intent: Intent?) {
        val what = intent?.getStringExtra(EXTRA_OPEN) ?: return
        intent.removeExtra(EXTRA_OPEN)
        _open.value = what
    }

    fun opened() { _open.value = null }

    // MARK: Regras dos botões

    /** Resultado do "✓ Série feita": a sessão, o exercício da série e o descanso (null = sem descanso, superset) */
    data class Completed(val session: Session, val exerciseID: String, val rest: Int?)

    /**
     * "✓ Série feita" (LiveWorkout.completeNextSet): marca a próxima série do exercício atual; superset passa direto para o
     * próximo do bloco, senão descansa o tempo da série. null quando não há série a marcar.
     */
    fun completeNext(s: Session): Completed? {
        val id = s.currentExercise ?: return null
        val set = s.setsOf(id).firstOrNull { !it.done } ?: return null
        val (adv, rest) = s.updating(set.key) { it.copy(done = true) }.advance(id)
        return Completed(adv, id, if (rest) set.rest else null)
    }

    // MARK: Observação

    private var watching: Job? = null

    /** Passa a manter a notificação em dia com a conta aberta (idempotente; vive enquanto o processo viver) */
    fun watch(context: Context) {
        if (watching?.isActive == true) return
        val c = context.applicationContext
        val container = (c as GymBrosApp).container
        WodRunStore.load(c)
        watching = scope.launch {
            combine(container.auth.user, container.copies.state, WodRunStore.state) { user, state, wod -> Triple(user != null, state, wod) }
                .collectLatest { (signedIn, state, wod) ->
                    if (!signedIn) { cancelAll(c); return@collectLatest }
                    // Abrindo a conta: deixa o que já está na tela
                    val ready = state as? CopyState.Ready ?: return@collectLatest
                    // Redesenha no fim do descanso e nas viradas do WOD (minuto do EMOM, fase do Tabata, fim do tempo)
                    while (true) {
                        val next = render(c, ready.copy, wod) ?: break
                        delay(maxOf(next.toEpochMilli() - System.currentTimeMillis(), 0L) + 250)
                    }
                }
        }
    }

    /** Acordado sem o app aberto (fim do descanso): abre a conta, redesenha agora e volta a observar */
    internal suspend fun wake(context: Context) {
        val c = context.applicationContext
        val copies = account(c) ?: return
        WodRunStore.load(c)
        render(c, (copies.state.value as? CopyState.Ready)?.copy, WodRunStore.state.value)
        watch(c)
    }

    /** Desenha as duas notificações; devolve quando precisa redesenhar sem mudança de dados */
    private fun render(c: Context, copy: JsonObject?, wod: WodRunState?): Instant? {
        val data = TrainCopy.read(copy).also(TrainCopy::install)
        val now = Instant.now()
        return listOfNotNull(renderWorkout(c, data.inProgress, now), renderWod(c, wod, now)).minOrNull()
    }

    /** A conta que está aberta, com a cópia pronta (o processo pode ter sido acordado só pela notificação) */
    private suspend fun account(c: Context): AccountCopyRepository? {
        val uid = FirebaseAuth.getInstance().currentUser?.uid ?: return null
        val copies = (c.applicationContext as GymBrosApp).container.copies
        copies.start(uid)
        withTimeoutOrNull(10_000) { copies.state.first { it is CopyState.Ready } } ?: return null
        return copies
    }

    // MARK: Botões

    internal suspend fun handle(context: Context, action: String?) {
        val c = context.applicationContext
        when (action) {
            ADD_ROUND -> {
                WodRunStore.load(c)
                val w = WodRunStore.state.value ?: return
                if (w.startedAt != null && w.pausedAt == null) WodRunStore.set(c, w.addRound(Instant.now()))
            }
            SET_DONE, SKIP_REST -> {
                val a = if (action == SET_DONE) Action.SET_DONE else Action.SKIP_REST
                screen?.let { it(a); return }
                val copies = account(c) ?: return
                val current = (copies.state.value as? CopyState.Ready)?.copy ?: return
                var restEnd: Instant? = null
                var keep = false
                var notify = false
                copies.edit { x ->
                    val copy = x ?: current
                    val d = TrainCopy.read(copy)
                    val s = d.inProgress ?: return@edit copy.also { keep = true }
                    notify = d.restNotification
                    val n = when (a) {
                        Action.SKIP_REST -> s.copy(restEnd = null)
                        Action.SET_DONE -> {
                            val done = completeNext(s) ?: return@edit copy.also { keep = true }
                            val rest = done.rest
                            when {
                                rest == null -> done.session.copy(restEnd = null)
                                rest > 0 -> Instant.now().plusSeconds(rest.toLong()).let { end ->
                                    restEnd = end
                                    done.session.copy(restEnd = end, restTotal = rest)
                                }
                                else -> { keep = true; done.session }
                            }
                        }
                    }
                    TrainEdits.saveSession(copy, n)
                }
                val end = restEnd
                if (end != null) RestAlarm.schedule(c, end, notify) else if (!keep) RestAlarm.cancel(c)
                watch(c)
                // O processo pode morrer logo depois: sobe já
                copies.flush()
            }
        }
    }

    // MARK: Notificações

    private val posted = mutableMapOf<Int, String>()

    private fun channel(c: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val nm = c.getSystemService(NotificationManager::class.java) ?: return
        if (nm.getNotificationChannel(CHANNEL) != null) return
        nm.createNotificationChannel(NotificationChannel(CHANNEL, "Treino em andamento", NotificationManager.IMPORTANCE_LOW).apply {
            description = "Série atual, descanso e cronômetro enquanto você treina"
            setShowBadge(false)
        })
    }

    private fun cancel(c: Context, id: Int) {
        if (posted.remove(id) != null) NotificationManagerCompat.from(c).cancel(id)
    }

    private fun cancelAll(c: Context) {
        posted.clear()
        NotificationManagerCompat.from(c).cancel(WORKOUT_ID)
        NotificationManagerCompat.from(c).cancel(WOD_ID)
    }

    private fun openIntent(c: Context, what: String, code: Int): PendingIntent =
        PendingIntent.getActivity(c, code, Intent(c, MainActivity::class.java).putExtra(EXTRA_OPEN, what).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                                  PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)

    private fun actionIntent(c: Context, action: String, code: Int): PendingIntent =
        PendingIntent.getBroadcast(c, code, Intent(c, LiveWorkoutReceiver::class.java).setAction(action),
                                   PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)

    private fun builder(c: Context): NotificationCompat.Builder = NotificationCompat.Builder(c, CHANNEL)
        .setSmallIcon(R.drawable.ic_stat_train)
        .setColor(0xFFA3E636.toInt())
        .setOngoing(true)
        .setOnlyAlertOnce(true)
        .setSilent(true)
        .setCategory(NotificationCompat.CATEGORY_WORKOUT)
        .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
        .setPriority(NotificationCompat.PRIORITY_LOW)

    /** Posta só se mudou (a notificação não pisca a cada gravação da cópia) */
    private fun post(c: Context, id: Int, key: String, build: () -> NotificationCompat.Builder) {
        if (!RestAlarm.canNotify(c)) { posted.remove(id); return }
        if (posted[id] == key) return
        channel(c)
        runCatching { NotificationManagerCompat.from(c).notify(id, build().build()) }.onSuccess { posted[id] = key }
    }

    /** Treino guiado (WorkoutLiveActivity + LiveWorkout.state): devolve o fim do descanso para redesenhar nele */
    private fun renderWorkout(c: Context, s: Session?, now: Instant): Instant? {
        if (s == null) { cancel(c, WORKOUT_ID); return null }
        val cur = s.currentExercise
        val sets = cur?.let(s::setsOf).orEmpty()
        val next = sets.indexOfFirst { !it.done }.takeIf { it >= 0 }
        val exercise = cur?.let(Exercises::name) ?: "Treino livre"
        val setLine = next?.let { i -> "Série ${i + 1} de ${sets.size} · " + (if (sets[i].warmup) "Aquecimento · " else "") + setText(sets[i]) }
        // Totais só com séries de trabalho, como na conclusão (aquecimento fica de fora)
        val done = s.doneWorkSets.size
        val total = s.workSets.size
        val restEnd = s.restEnd?.takeIf { it > now }
        val restOver = s.restEnd != null && restEnd == null
        val text = when {
            cur == null -> "Adicione exercícios no app"
            s.sets.isNotEmpty() && s.sets.all { it.done } -> "Todas as séries feitas · é só concluir no app"
            setLine == null -> "Exercício concluído"
            restEnd != null -> "Descanso · a seguir ${setLine.replaceFirstChar(Char::lowercase)}"
            restOver -> "Descanso acabou · $setLine"
            else -> setLine
        }
        val sub = s.title + if (total > 0) " · $done/$total séries" else ""
        val key = listOf(s.uuid, exercise, text, sub, restEnd?.toEpochMilli(), s.start.toEpochMilli()).joinToString("|")
        post(c, WORKOUT_ID, key) {
            builder(c).setContentTitle(exercise).setContentText(text).setSubText(sub)
                .setContentIntent(openIntent(c, OPEN_WORKOUT, WORKOUT_ID))
                .apply {
                    if (total > 0) setProgress(total, done, false)
                    // Descanso: contagem regressiva até o fim; fora dele, o tempo do treino
                    setUsesChronometer(true).setShowWhen(true)
                    if (restEnd != null) setWhen(restEnd.toEpochMilli()).setChronometerCountDown(true)
                    else setWhen(s.start.toEpochMilli()).setChronometerCountDown(false)
                    if (restEnd != null) addAction(0, "Pular descanso", actionIntent(c, SKIP_REST, WORKOUT_ID + 1))
                    else if (setLine != null) addAction(0, "✓ Série feita", actionIntent(c, SET_DONE, WORKOUT_ID + 2))
                }
        }
        return restEnd
    }

    /** WOD em andamento (Wod.swift `publishLive` + WodLiveActivity): devolve a próxima virada para redesenhar nela */
    private fun renderWod(c: Context, w: WodRunState?, now: Instant): Instant? {
        val sessionStart = w?.sessionStart
        if (w == null || (w.startedAt == null && sessionStart == null)) { cancel(c, WOD_ID); return null }
        val f = w.wod.format
        val parts = w.wod.parts
        var format = f.name
        var text: String
        var base: Instant? = null
        var end: Instant? = null
        var refresh: Instant? = null
        var round = false
        if (w.startedAt == null && sessionStart != null) {
            // Antes do cronômetro do WOD (aquecimento, força… ou esperando o WOD): relógio do treino todo, com a parte atual
            val i = w.working
            val here = if (i >= parts.size) "WOD · prepare-se" else parts[i].title
            text = if (parts.isEmpty()) here else "$here · ${minOf(i, parts.size) + 1} de ${parts.size + 1}"
            format = "Treino"
            base = sessionStart
        } else {
            val e = w.elapsed(now)
            val sec = e.toInt()
            val totalSec = f.totalSeconds
            val shows = when (f) { is WodFormat.ForTime, is WodFormat.Amrap -> true; is WodFormat.Intervals -> !f.emom; else -> false }
            val rounds = w.roundsShown(now).let { if (shows) " · $it rodada${if (it == 1) "" else "s"}" else "" }
            when {
                totalSec != null && sec >= totalSec -> text = "Tempo acabou · ${clock(totalSec)}$rounds"
                w.pausedAt != null -> text = "Pausado · ${clock(sec)}$rounds"
                else -> {
                    val start = now.minusMillis((e * 1000).toLong())
                    fun at(s: Int): Instant = start.plusSeconds(s.toLong())
                    // EMOM e Tabata: contagem até o fim do minuto/fase; blocos: até o fim do bloco ou descanso; AMRAP: até o fim do tempo
                    end = when (f) {
                        is WodFormat.ForTime -> null
                        is WodFormat.Emom -> at((sec / 60 + 1) * 60)
                        is WodFormat.Every -> at((sec / f.seconds + 1) * f.seconds)
                        is WodFormat.Tabata -> at(sec / 30 * 30 + if (sec % 30 < 20) 20 else 30)
                        is WodFormat.Intervals -> f.segment(sec)?.let { at(sec + it.second) }
                        is WodFormat.Amrap -> totalSec?.let(::at)
                    }
                    if (end == null) base = start
                    refresh = listOfNotNull(end, totalSec?.let(::at)).minOrNull()
                    text = label(f, sec) + rounds
                    round = shows
                }
            }
        }
        val key = listOf(w.wod.id, w.wod.name, format, text, base?.toEpochMilli(), end?.toEpochMilli(), round).joinToString("|")
        post(c, WOD_ID, key) {
            builder(c).setContentTitle(w.wod.name).setContentText(text).setSubText(format)
                .setContentIntent(openIntent(c, OPEN_WOD, WOD_ID))
                .apply {
                    val t = end ?: base
                    if (t != null) setUsesChronometer(true).setShowWhen(true).setWhen(t.toEpochMilli()).setChronometerCountDown(end != null)
                    else setShowWhen(false)
                    if (round) addAction(0, "+1 rodada", actionIntent(c, ADD_ROUND, WOD_ID + 1))
                }
        }
        return refresh
    }

    /** Parte do WOD na hora (Wod.swift `label`) */
    private fun label(f: WodFormat, sec: Int): String = when (f) {
        is WodFormat.ForTime -> f.capMinutes?.let { "Limite $it:00" } ?: "For Time"
        is WodFormat.Amrap -> "AMRAP ${f.minutes} min"
        is WodFormat.Emom -> "Minuto ${minOf(sec / 60 + 1, f.minutes)} de ${f.minutes}"
        is WodFormat.Every -> "Intervalo ${sec / f.seconds + 1}" + if (f.minutes > 0) " de ${maxOf(f.minutes * 60 / f.seconds, 1)}" else ""
        is WodFormat.Tabata -> "Rodada ${minOf(sec / 30 + 1, f.rounds)} de ${f.rounds} · " + if (sec % 30 < 20) "ESFORÇO" else "DESCANSO"
        is WodFormat.Intervals -> f.segment(sec)?.first?.let { seg ->
            if (seg.rest) "Descanso · próximo bloco ${seg.block + 2} de ${f.blocks.size}" else "Bloco ${seg.block + 1} de ${f.blocks.size}"
        } ?: f.name
    }
}

/** Botões da notificação do treino e do WOD (só o próprio app dispara, pelo PendingIntent) */
class LiveWorkoutReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        val action = intent.action
        CoroutineScope(Dispatchers.Main.immediate).launch {
            try { LiveWorkout.handle(context, action) } finally { pending.finish() }
        }
    }
}
