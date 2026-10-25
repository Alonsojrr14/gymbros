package com.alonsoalmeida.gymbros.data.route

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.location.Location
import android.os.Build
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.alonsoalmeida.gymbros.MainActivity
import com.alonsoalmeida.gymbros.R
import com.alonsoalmeida.gymbros.data.live.LivePresence
import com.alonsoalmeida.gymbros.data.live.LiveShareStore
import com.alonsoalmeida.gymbros.data.map.GymLocation
import com.alonsoalmeida.gymbros.domain.ActivityKind
import com.alonsoalmeida.gymbros.domain.map.Coordinate
import com.alonsoalmeida.gymbros.domain.map.Fix
import com.alonsoalmeida.gymbros.domain.map.RouteTrack
import com.alonsoalmeida.gymbros.domain.map.clock
import com.alonsoalmeida.gymbros.domain.map.kindName
import com.alonsoalmeida.gymbros.domain.map.kmText
import com.alonsoalmeida.gymbros.domain.map.paceText
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.Instant
import java.util.UUID

/**
 * Corrida, caminhada e bike com GPS (Route.swift `RouteTracker`): o percurso, a distância, o tempo e o ritmo, e o treino
 * ao vivo para os amigos a cada ponto novo. Um percurso por vez, guardado no processo enquanto a tela de gravação, a
 * conclusão ou a notificação estão abertas (como no iOS, não sobrevive ao app ser encerrado à força).
 *
 * O GPS é lido pelo Fused Location (alta precisão, a cada 5 m). Depois de "Começar", um serviço em primeiro plano do tipo
 * `location` ([RouteService]) mantém a leitura com a tela bloqueada ou o app em segundo plano, com a notificação contínua
 * (tempo, distância e ritmo; Pausar/Continuar e Encerrar): não precisa da localização "o tempo todo". Não mexe na cerca
 * das academias: sair de um lugar salvo só encerra o treino guiado em andamento, nunca o percurso (igual ao iOS).
 */
object RouteRecorder {
    data class Run(
        /** Id do percurso: o da escolha do ao vivo e o `uuid` do RouteRecord salvo */
        val id: String,
        val track: RouteTrack,
        /** "Terminar": GPS parado e a tela de conclusão aberta */
        val finishing: Boolean = false,
    ) {
        val kind: ActivityKind get() = track.kind
    }

    /** Fonte gravada nas atividades do percurso (o "GPS do iPhone" do iOS); vale como treino gravado por aparelho */
    const val SOURCE = "GPS do Android"

    private const val EXTRA_FINISH = "gymbros.route.finish"
    internal const val TOGGLE = "com.alonsoalmeida.gymbros.route.TOGGLE"

    private val _run = MutableStateFlow<Run?>(null)
    val run: StateFlow<Run?> = _run.asStateFlow()

    private var app: Context? = null
    private var client: FusedLocationProviderClient? = null
    private val callback = object : LocationCallback() {
        override fun onLocationResult(result: LocationResult) { result.locations.forEach(::add) }
    }

    /** Abre a tela de gravação (`prepare`): já mostra onde você está, sem gravar */
    fun open(c: Context, kind: ActivityKind) {
        if (_run.value != null) return
        app = c.applicationContext
        _run.value = Run(UUID.randomUUID().toString().uppercase(), RouteTrack(kind))
        startUpdates()
    }

    /** A permissão de localização chegou com a tela já aberta: passa a ler o GPS */
    fun prepare() { if (_run.value?.finishing == false) startUpdates() }

    /** "Começar": grava daqui em diante, também com a tela bloqueada */
    fun begin() {
        val c = app ?: return
        edit { it.copy(track = it.track.begin(Instant.now())) }
        startUpdates()
        RouteService.start(c)
    }

    fun togglePause() = edit { r -> if (r.finishing || !r.track.started) r else r.copy(track = r.track.togglePause(Instant.now())) }

    /** "Terminar" (ou Encerrar na notificação): para o GPS e o tempo, e abre a conclusão */
    fun finish() {
        val r = _run.value ?: return
        if (r.finishing) return
        if (!r.track.started) return discard()
        stopUpdates()
        _run.value = r.copy(track = r.track.stop(Instant.now()), finishing = true)
    }

    /** Fechou a conclusão sem salvar: volta para a gravação, pausada; "Continuar" segue gravando */
    fun cancelFinish() {
        val r = _run.value ?: return
        if (!r.finishing) return
        _run.value = r.copy(finishing = false)
        startUpdates()
        app?.let(RouteService::start)
    }

    /** Sair sem salvar, salvo, ou a conta saiu: tudo para e o ao vivo sai do ar */
    fun discard() {
        val r = _run.value ?: return
        stopUpdates()
        _run.value = null
        app?.let { c ->
            LiveShareStore.end(c, r.id)
            RouteService.stop(c)
        }
    }

    private fun edit(change: (Run) -> Run) {
        val r = _run.value ?: return
        _run.value = change(r)
    }

    @SuppressLint("MissingPermission")
    private fun startUpdates() {
        val c = app ?: return
        if (!GymLocation.hasFine(c)) return
        val cl = client ?: LocationServices.getFusedLocationProviderClient(c).also { client = it }
        val req = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 1_000L)
            .setMinUpdateDistanceMeters(RouteTrack.DISTANCE_FILTER)
            .setWaitForAccurateLocation(false)
            .build()
        runCatching { cl.requestLocationUpdates(req, callback, Looper.getMainLooper()) }
    }

    private fun stopUpdates() { runCatching { client?.removeLocationUpdates(callback) } }

    /** Precisão sem informação conta como inválida, como a negativa do CoreLocation */
    private fun add(loc: Location) {
        val r = _run.value ?: return
        if (r.finishing) return
        val fix = Fix(Coordinate(loc.latitude, loc.longitude), if (loc.hasAccuracy()) loc.accuracy.toDouble() else -1.0, Instant.ofEpochMilli(loc.time))
        val t = r.track.add(fix)
        _run.value = r.copy(track = t)
        // Ao vivo: posição e percurso para os amigos (o LivePresence limita a uma gravação a cada 30 s)
        val start = t.start
        val here = t.here
        val c = app
        if (t.coords.size != r.track.coords.size && start != null && here != null && c != null) {
            LivePresence.route(c, r.id, t.kind, start, t.meters, here, t.coords)
        }
    }

    // MARK: Notificação

    /** Pedido vindo da notificação ("Encerrar"): abre o app já na conclusão */
    fun take(intent: Intent?) {
        if (intent?.getBooleanExtra(EXTRA_FINISH, false) != true) return
        intent.removeExtra(EXTRA_FINISH)
        finish()
    }

    internal const val CHANNEL = "route"
    internal const val NOTIFICATION_ID = 4401

    internal fun channel(c: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val nm = c.getSystemService(NotificationManager::class.java) ?: return
        if (nm.getNotificationChannel(CHANNEL) != null) return
        nm.createNotificationChannel(NotificationChannel(CHANNEL, "Percurso ao ar livre", NotificationManager.IMPORTANCE_LOW).apply {
            description = "Tempo, distância e ritmo enquanto o GPS grava a corrida, a caminhada ou a bike"
            setShowBadge(false)
        })
    }

    /** O que a notificação mostra, para só redesenhar quando muda */
    internal fun key(r: Run?): String {
        val t = r?.track ?: return ""
        return listOf(t.kind, kmText(t.meters), pace(t), t.paused, t.pausedTotalMillis, t.start?.toEpochMilli()).joinToString("|")
    }

    private fun pace(t: RouteTrack): String = paceText(t.kind, t.meters, t.elapsed(Instant.now()))

    internal fun notification(c: Context, r: Run?): Notification {
        val open = PendingIntent.getActivity(c, NOTIFICATION_ID, Intent(c, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                                             PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val b = NotificationCompat.Builder(c, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_train)
            .setColor(0xFFA3E636.toInt())
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_WORKOUT)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setContentIntent(open)
        val t = r?.track ?: return b.setContentTitle("Percurso").build()
        val now = Instant.now()
        val paceLabel = if (t.kind == ActivityKind.BIKE) "Velocidade" else "Ritmo"
        b.setContentTitle("${kindName(t.kind)} · ${kmText(t.meters)}")
        val start = t.start
        if (t.paused || start == null) {
            b.setContentText(if (start == null) "Pronto para começar" else "Pausado · ${clock(t.elapsed(now))} · $paceLabel ${pace(t)}").setShowWhen(false)
        } else {
            // Cronômetro desenhado pelo sistema: começa no início, empurrado pelo tempo pausado
            b.setContentText("$paceLabel ${pace(t)}").setUsesChronometer(true).setShowWhen(true)
                .setWhen(start.toEpochMilli() + t.pausedTotalMillis)
        }
        if (start != null) {
            val toggle = PendingIntent.getBroadcast(c, NOTIFICATION_ID + 1, Intent(c, RouteReceiver::class.java).setAction(TOGGLE),
                                                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            val finish = PendingIntent.getActivity(c, NOTIFICATION_ID + 2,
                                                   Intent(c, MainActivity::class.java).putExtra(EXTRA_FINISH, true).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                                                   PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            b.addAction(0, if (t.paused) "Continuar" else "Pausar", toggle)
            b.addAction(0, "Encerrar", finish)
        }
        return b.build()
    }
}

/**
 * Serviço em primeiro plano do percurso (tipo `location`): mantém o GPS com a tela bloqueada e mostra a notificação
 * contínua. Só existe entre "Começar" e "Terminar"/sair; começa sempre por um toque na tela (o Android só deixa iniciar
 * um serviço de localização com o app na frente).
 */
class RouteService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var watching: Job? = null
    private var shown = ""

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val r = RouteRecorder.run.value
        RouteRecorder.channel(this)
        // Primeiro em primeiro plano (o sistema exige logo depois do start), depois confere se ainda há o que gravar
        val ok = runCatching {
            ServiceCompat.startForeground(this, RouteRecorder.NOTIFICATION_ID, RouteRecorder.notification(this, r),
                                          if (Build.VERSION.SDK_INT >= 29) ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION else 0)
        }.isSuccess
        if (!ok || r == null || r.finishing || !r.track.started) { finish(); return START_NOT_STICKY }
        shown = RouteRecorder.key(r)
        if (watching == null) watching = scope.launch {
            RouteRecorder.run.collect { x ->
                if (x == null || x.finishing) { finish(); return@collect }
                val k = RouteRecorder.key(x)
                if (k == shown) return@collect
                shown = k
                runCatching { NotificationManagerCompat.from(this@RouteService).notify(RouteRecorder.NOTIFICATION_ID, RouteRecorder.notification(this@RouteService, x)) }
            }
        }
        return START_NOT_STICKY
    }

    private fun finish() {
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    companion object {
        fun start(c: Context) {
            runCatching { ContextCompat.startForegroundService(c, Intent(c, RouteService::class.java)) }
        }

        fun stop(c: Context) {
            runCatching { c.stopService(Intent(c, RouteService::class.java)) }
            NotificationManagerCompat.from(c).cancel(RouteRecorder.NOTIFICATION_ID)
        }
    }
}

/** Pausar/Continuar da notificação do percurso (só o próprio app dispara, pelo PendingIntent) */
class RouteReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == RouteRecorder.TOGGLE) RouteRecorder.togglePause()
    }
}
