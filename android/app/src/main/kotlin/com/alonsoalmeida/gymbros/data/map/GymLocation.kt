package com.alonsoalmeida.gymbros.data.map

import android.Manifest
import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.alonsoalmeida.gymbros.GymBrosApp
import com.alonsoalmeida.gymbros.MainActivity
import com.alonsoalmeida.gymbros.R
import com.alonsoalmeida.gymbros.data.AccountCopyRepository
import com.alonsoalmeida.gymbros.data.CopyState
import com.alonsoalmeida.gymbros.data.leagues.LeagueStore
import com.alonsoalmeida.gymbros.data.leagues.PROFILE_FEED
import com.alonsoalmeida.gymbros.data.train.TrainCopy
import com.alonsoalmeida.gymbros.data.train.TrainEdits
import com.alonsoalmeida.gymbros.domain.ActivityKind
import com.alonsoalmeida.gymbros.domain.AttributeSplit
import com.alonsoalmeida.gymbros.domain.BroCatalog
import com.alonsoalmeida.gymbros.domain.backup.AccountEdits
import com.alonsoalmeida.gymbros.domain.Game
import com.alonsoalmeida.gymbros.domain.duel.durationText
import com.alonsoalmeida.gymbros.domain.leagues.League
import com.alonsoalmeida.gymbros.domain.leagues.LeagueActivityJson
import com.alonsoalmeida.gymbros.domain.leagues.LeagueEdits
import com.alonsoalmeida.gymbros.domain.map.Coordinate
import com.alonsoalmeida.gymbros.domain.map.Gym
import com.alonsoalmeida.gymbros.domain.map.GymPlaces
import com.alonsoalmeida.gymbros.domain.profile.ProfileEdits
import com.alonsoalmeida.gymbros.domain.train.Progression
import com.alonsoalmeida.gymbros.domain.train.TrainSplit
import com.alonsoalmeida.gymbros.domain.train.WodPlan
import com.alonsoalmeida.gymbros.domain.train.iosWeekday
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import com.google.firebase.auth.FirebaseAuth
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.intOrNull
import java.time.Instant
import java.time.ZoneId

/**
 * Lugares de treino (Services/Location.swift `GymLocation`): posição atual, cerca de cada lugar salvo (Geofencing API, até
 * 20, os visitados mais recentemente), ida aberta ao chegar e fechada ao sair, aviso "Chegou na X 💪" e o treino em
 * andamento encerrado ao sair (`LiveWorkout.autoFinish`).
 *
 * A posição fica no aparelho: nada daqui vai para o servidor. As idas e os lugares vão só na cópia da conta, como no iOS.
 * O lugar em que está agora (`insideID`) é do aparelho: cada aparelho vê a própria cerca.
 */
object GymLocation {
    private const val CHANNEL = "gym"
    private const val ARRIVAL_ID = 4301
    private const val FINISHED_ID = 4302
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val lock = Mutex()
    /** Lugares já registrados neste processo (evita registrar de novo a cada mudança da cópia) */
    private var registered: String? = null

    /** Treino com a tela "Concluir treino" aberta: nunca é encerrado pela saída (`LiveWorkout.concluding`) */
    @Volatile var concluding: String? = null

    private fun prefs(c: Context) = c.getSharedPreferences("gymbros-gym", Context.MODE_PRIVATE)

    /** Lugar em que está agora (último evento de entrada), deste aparelho e desta conta */
    fun insideID(c: Context, uid: String): String? = prefs(c).getString("inside-$uid", null)
    private fun setInside(c: Context, uid: String, id: String?) = prefs(c).edit().apply { if (id == null) remove("inside-$uid") else putString("inside-$uid", id) }.apply()

    /** Lugar apagado: deixa de contar como "você está aqui" */
    fun forget(c: Context, uid: String, id: String) { if (insideID(c, uid) == id) setInside(c, uid, null) }

    fun hasFine(c: Context) = ContextCompat.checkSelfPermission(c, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
        ContextCompat.checkSelfPermission(c, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED

    /** "O tempo todo": sem isso a cerca não funciona com o app fechado (Android 10+) */
    fun hasBackground(c: Context) = Build.VERSION.SDK_INT < 29 ||
        ContextCompat.checkSelfPermission(c, Manifest.permission.ACCESS_BACKGROUND_LOCATION) == PackageManager.PERMISSION_GRANTED

    private fun canNotify(c: Context) = Build.VERSION.SDK_INT < 33 ||
        ContextCompat.checkSelfPermission(c, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    // MARK: Localização atual

    /** Uma leitura do GPS (null sem permissão, sem sinal ou passado o tempo) */
    @SuppressLint("MissingPermission")
    suspend fun currentLocation(c: Context, timeoutMs: Long = 15_000): Location? {
        if (!hasFine(c)) return null
        val client = LocationServices.getFusedLocationProviderClient(c)
        val cancel = CancellationTokenSource()
        val fresh = withTimeoutOrNull(timeoutMs) {
            runCatching { client.getCurrentLocation(Priority.PRIORITY_HIGH_ACCURACY, cancel.token).await() }.getOrNull()
        }
        if (fresh == null) cancel.cancel()
        return fresh ?: runCatching { client.lastLocation.await() }.getOrNull()?.takeIf { System.currentTimeMillis() - it.time < 120_000 }
    }

    fun Location.coordinate() = Coordinate(latitude, longitude)

    // MARK: Cerca

    private fun fenceIntent(c: Context): PendingIntent =
        PendingIntent.getBroadcast(c, 0, Intent(c, GeofenceReceiver::class.java),
                                   PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0))

    /** Registra a cerca dos lugares salvos (precisa rodar ao abrir o app e depois de reiniciar o aparelho) */
    @SuppressLint("MissingPermission")
    fun startMonitoring(c: Context, copy: JsonObject?, force: Boolean = false) {
        val ctx = c.applicationContext
        val list = GymPlaces.recent(copy)
        val key = list.joinToString { "${it.uuid}:${it.coordinate.latitude}:${it.coordinate.longitude}:${it.radius}" }
        val allowed = hasFine(ctx) && hasBackground(ctx)
        if (!force && registered == (if (allowed) key else "")) return
        val client = LocationServices.getGeofencingClient(ctx)
        runCatching { client.removeGeofences(fenceIntent(ctx)) }
        registered = if (allowed) key else ""
        if (!allowed || list.isEmpty()) return
        val fences = list.map { g ->
            Geofence.Builder().setRequestId(g.uuid)
                .setCircularRegion(g.coordinate.latitude, g.coordinate.longitude, g.radius.toFloat())
                .setExpirationDuration(Geofence.NEVER_EXPIRE)
                .setTransitionTypes(Geofence.GEOFENCE_TRANSITION_ENTER or Geofence.GEOFENCE_TRANSITION_EXIT)
                .build()
        }
        val request = GeofencingRequest.Builder().setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER).addGeofences(fences).build()
        runCatching { client.addGeofences(request, fenceIntent(ctx)).addOnFailureListener { registered = null } }.onFailure { registered = null }
    }

    /** A conta que está aberta, com a cópia pronta (o processo pode ter sido acordado só pela cerca) */
    private suspend fun account(c: Context): Pair<String, AccountCopyRepository>? {
        val uid = FirebaseAuth.getInstance().currentUser?.uid ?: return null
        val copies = (c.applicationContext as GymBrosApp).container.copies
        copies.start(uid)
        withTimeoutOrNull(10_000) { copies.state.first { it is CopyState.Ready } } ?: return null
        return uid to copies
    }

    private fun copyOf(copies: AccountCopyRepository) = (copies.state.value as? CopyState.Ready)?.copy

    /** Evento da cerca: entrada abre a ida; saída fecha e pode encerrar o treino */
    internal suspend fun handle(c: Context, ids: List<String>, entered: Boolean) = lock.withLock {
        val (uid, copies) = account(c) ?: return@withLock
        for (id in ids) {
            val g = GymPlaces.gym(copyOf(copies), id) ?: continue
            if (entered) arrived(c, uid, copies, g) else left(c, uid, copies, g)
        }
        copies.flush()
    }

    private suspend fun arrived(c: Context, uid: String, copies: AccountCopyRepository, g: Gym) {
        if (insideID(c, uid) == g.uuid) return
        setInside(c, uid, g.uuid)
        copies.edit { x -> GymPlaces.openVisit(x ?: AccountEdits.empty("", Instant.now()), g, Instant.now()) }
        val copy = copyOf(copies)
        val st = TrainCopy.settings(copy)
        if (!ProfileEdits.bool(st, "gymNotifyArrival", true) || ProfileEdits.bool(st, "notify.paused", false)) return
        if (TrainCopy.read(copy).inProgress != null) return
        val routine = todayTrainingName(copy)
        notify(c, ARRIVAL_ID, "Chegou na ${g.name} 💪", routine?.let { "Começar $it? Toque para abrir o treino." } ?: "Bora treinar? Toque para começar.")
    }

    private suspend fun left(c: Context, uid: String, copies: AccountCopyRepository, g: Gym) {
        copies.edit { x -> x?.let { GymPlaces.closeVisit(it, g.uuid, Instant.now()) } ?: AccountEdits.empty("", Instant.now()) }
        // Já tinha entrado em outro lugar: só fecha a ida deste
        if (insideID(c, uid) != g.uuid) return
        setInside(c, uid, null)
        val copy = copyOf(copies)
        if (!ProfileEdits.bool(TrainCopy.settings(copy), "gymAutoFinish", true)) return
        val s = TrainCopy.read(copy).inProgress ?: return
        if (concluding == s.uuid || (s.gymUUID != null && s.gymUUID != g.uuid)) return
        if (Instant.now().epochSecond - s.start.epochSecond < GymPlaces.MIN_WORKOUT_MINUTES * 60) return
        val here = currentLocation(c) ?: return
        if (!GymPlaces.leftForReal(g, here.coordinate(), here.accuracy.toDouble())) return
        if (concluding == s.uuid) return
        val summary = autoFinish(c, uid, copies, s.uuid, g.name) ?: return
        notify(c, FINISHED_ID, "Treino encerrado ao sair da ${g.name}", summary)
    }

    /**
     * Salva o treino em andamento como a conclusão faria (LiveWorkout.swift `autoFinish`): só séries de trabalho contam,
     * esforço estimado pelos últimos treinos, atividade com o lugar na nota, check-in no perfil e nas ligas em andamento e
     * a oferta de atualizar a rotina guardada para a aba Treino. Treino já salvo (aqui ou no iPhone) não vira outra atividade.
     */
    private suspend fun autoFinish(c: Context, uid: String, copies: AccountCopyRepository, sessionID: String, place: String): String? {
        var summary: String? = null
        var posted: LeagueActivityJson? = null
        var title = ""
        var records = emptyList<String>()
        copies.edit { x ->
            val copy = x ?: return@edit AccountEdits.empty("", Instant.now())
            val data = TrainCopy.read(copy)
            val s = data.sessions.firstOrNull { it.uuid == sessionID } ?: return@edit copy
            if (s.end != null) return@edit copy
            val done = s.doneWorkSets
            if (done.isEmpty()) {
                summary = "Nenhuma série marcada, então o treino foi descartado."
                return@edit TrainEdits.deleteSession(copy, s.uuid)
            }
            TrainCopy.install(data)
            val now = Instant.now()
            val efforts = (copy["activities"] as? JsonArray).orEmpty().mapNotNull { it as? JsonObject }
                .filter { (it["kind"] as? JsonPrimitive)?.content == ActivityKind.MUSCULACAO.raw }
                .sortedBy { (it["date"] as? JsonPrimitive)?.content.orEmpty() }
                .mapNotNull { (it["effort"] as? JsonPrimitive)?.intOrNull }
            val effort = Progression.estimatedEffort(efforts)
            val minutes = maxOf(((now.epochSecond - s.start.epochSecond) / 60).toInt(), 1)
            val split = TrainSplit.split(ActivityKind.MUSCULACAO, minutes, effort, sets = done.map { TrainSplit.SetSignal(it.exerciseID, it.reps, it.rest) })
            val activityID = TrainEdits.newID()
            val note = "${s.title} · 📍 $place"
            var out = TrainEdits.addActivity(copy, activityID, ActivityKind.MUSCULACAO.raw, s.start, minutes, effort, note, AttributeSplit.encode(split), s.gymUUID)
            out = TrainEdits.saveSession(out, s.copy(end = now, effort = effort, activityUUID = activityID, restEnd = null))
            records = Progression.records(s.log, data.finished.filter { it.uuid != s.uuid }.sortedBy { it.start }.map { it.log })
            var routineNote = ""
            val routine = data.routines.firstOrNull { it.uuid == s.routineUUID }
            if (routine != null && s.routineChanges(routine).isNotEmpty()) {
                out = TrainEdits.text(out, "pendingRoutineUpdate", s.uuid)
                routineNote = " A rotina ${routine.name} mudou: abra a aba Treino para atualizar."
            }
            title = s.title
            posted = LeagueActivityJson(activityID, ActivityKind.MUSCULACAO.raw, s.start, minutes, effort, note, gymUUID = s.gymUUID,
                                        healthType = BroCatalog.classicType[ActivityKind.MUSCULACAO.raw])
            summary = "${s.title}: ${durationText(minutes)}, ${done.size} séries. +${Game.xp(ActivityKind.MUSCULACAO, minutes, effort)} XP pro seu bro.$routineNote"
            out
        }
        posted?.let { a -> runCatching { post(c, uid, copies, a, title, records) } }
        return summary
    }

    /** Mesmo destino padrão da conclusão: perfil e ligas em andamento, com os recordes no texto (postCheckIns) */
    private suspend fun post(c: Context, uid: String, copies: AccountCopyRepository, a: LeagueActivityJson, title: String, records: List<String>) {
        val copy = copyOf(copies) ?: return
        val terms = (TrainCopy.settings(copy)["termsAcceptedVersion"] as? Number)?.toInt() ?: 0
        if (terms < 2) return
        val store = LeagueStore.of(c, uid, copies)
        val roles = runCatching { store.remote.roles() }.getOrNull() ?: return
        if (roles.isEmpty()) return
        val now = Instant.now()
        val leagues = LeagueEdits.read(copy).leagues.orEmpty().map(::League).filter { !it.isOver(now) && it.hasStarted(now) && !it.isPastSeason }
        val note = if (records.isEmpty()) "" else "🏆 " + records.joinToString(" · ")
        store.post(LeagueStore.NewPost(a, title, note, null, null, null), leagues.map { it.uuid }.toSet() + PROFILE_FEED, leagues)
        store.flush()
    }

    /** O WOD do coach agendado para hoje vem antes da rotina do dia */
    private fun todayTrainingName(copy: JsonObject?): String? {
        val data = TrainCopy.read(copy)
        val zone = ZoneId.systemDefault()
        val day = Instant.now().atZone(zone).toLocalDate()
        WodPlan.pending(data.plannedRaw, data.wods.map { it.wodID }.toSet(), day, zone)?.let { return "${it.name} (${it.format.name})" }
        return data.routines.firstOrNull { iosWeekday(day) in it.weekdays }?.name
    }

    private fun notify(c: Context, id: Int, title: String, body: String) {
        if (!canNotify(c)) return
        val nm = c.getSystemService(NotificationManager::class.java) ?: return
        if (Build.VERSION.SDK_INT >= 26) nm.createNotificationChannel(NotificationChannel(CHANNEL, "Lugares de treino", NotificationManager.IMPORTANCE_HIGH))
        val open = PendingIntent.getActivity(c, id, Intent(c, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_IMMUTABLE)
        val n = NotificationCompat.Builder(c, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_train)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(open)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()
        runCatching { NotificationManagerCompat.from(c).notify(id, n) }
    }

    internal fun launch(block: suspend () -> Unit, done: () -> Unit) {
        scope.launch { try { block() } finally { done() } }
    }
}

/** Entrada e saída da cerca de um lugar (só o Google Play Services dispara, pelo PendingIntent do app) */
class GeofenceReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val event = GeofencingEvent.fromIntent(intent) ?: return
        if (event.hasError()) return
        val entered = when (event.geofenceTransition) {
            Geofence.GEOFENCE_TRANSITION_ENTER -> true
            Geofence.GEOFENCE_TRANSITION_EXIT -> false
            else -> return
        }
        val ids = event.triggeringGeofences.orEmpty().map { it.requestId }
        val pending = goAsync()
        GymLocation.launch({ GymLocation.handle(context.applicationContext, ids, entered) }) { pending.finish() }
    }
}

/** Depois de reiniciar o aparelho (ou atualizar o app) a cerca some: registra de novo */
class GymBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED && intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        val pending = goAsync()
        GymLocation.launch({
            val uid = FirebaseAuth.getInstance().currentUser?.uid ?: return@launch
            val copies = (context.applicationContext as GymBrosApp).container.copies
            copies.start(uid)
            withTimeoutOrNull(10_000) { copies.state.first { it is CopyState.Ready } }
            GymLocation.startMonitoring(context, (copies.state.value as? CopyState.Ready)?.copy, force = true)
        }) { pending.finish() }
    }
}
