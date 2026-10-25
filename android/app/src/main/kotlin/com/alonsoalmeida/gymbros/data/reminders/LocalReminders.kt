package com.alonsoalmeida.gymbros.data.reminders

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.alonsoalmeida.gymbros.GymBrosApp
import com.alonsoalmeida.gymbros.MainActivity
import com.alonsoalmeida.gymbros.R
import com.alonsoalmeida.gymbros.data.CopyState
import com.alonsoalmeida.gymbros.data.train.TrainCopy
import com.alonsoalmeida.gymbros.domain.RuleClock
import com.alonsoalmeida.gymbros.domain.Stage
import com.alonsoalmeida.gymbros.domain.backup.AccountCopy
import com.alonsoalmeida.gymbros.domain.home.HomeBuilder
import com.alonsoalmeida.gymbros.domain.leagues.League
import com.alonsoalmeida.gymbros.domain.leagues.LeagueBoard
import com.alonsoalmeida.gymbros.domain.leagues.LeagueEdits
import com.alonsoalmeida.gymbros.domain.leagues.MyCheckIn
import com.alonsoalmeida.gymbros.domain.leagues.RemoteLeague
import com.alonsoalmeida.gymbros.domain.profile.ProfileEdits
import com.alonsoalmeida.gymbros.domain.reminders.PlannedNotification
import com.alonsoalmeida.gymbros.domain.reminders.ReminderSettings
import com.alonsoalmeida.gymbros.domain.reminders.Reminders
import com.alonsoalmeida.gymbros.domain.reminders.WeeklySummary
import com.google.firebase.auth.FirebaseAuth
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put
import java.time.Instant
import java.time.ZoneId

/**
 * Lembrete diário para treinar e resumo de domingo (Companion.swift `Reminders` e `WeeklySummary`), só no aparelho:
 * nada passa pelo servidor. Como no iOS, o texto é montado ao agendar e tudo é reagendado quando os dados ou os
 * ajustes mudam (ao abrir o app, ao salvar um treino, ao mexer nos Ajustes ou ao chegar algo do iPhone).
 *
 * O que muda em relação ao iOS, por ser Android: os alarmes somem ao reiniciar (o [ReminderReceiver] os refaz) e, na
 * hora de tocar, o lembrete confere a cópia da conta neste aparelho: se o iPhone já registrou o treino do dia ou
 * desligou o lembrete, não toca. Depois de tocar, os próximos 7 dias são refeitos a partir da cópia.
 */
object LocalReminders {
    private const val CHANNEL = "lembretes"
    private const val PREFS = "lembretes"
    private const val PLAN = "plano"
    private const val LEAGUES = "ligas"
    private const val ACTION = "com.alonsoalmeida.gymbros.LEMBRETE"
    private const val EXTRA_ID = "id"
    private const val REMINDER_NOTIFICATION = 4300
    private const val SUMMARY_NOTIFICATION = 4310

    private val lock = Mutex()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    fun canNotify(context: Context): Boolean =
        Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    // MARK: Plano

    /** Posição conhecida numa liga (o placar dos outros só vem do servidor com a aba das ligas aberta) */
    private data class Known(val position: Int, val count: Int)

    /**
     * Tudo o que deve estar agendado agora, a partir da cópia da conta. `cache` é o que o app já leu das ligas no servidor;
     * sem ele, vale a última posição conhecida de cada liga.
     */
    private fun plan(context: Context, uid: String, copy: JsonObject?, cache: Map<String, RemoteLeague>, now: Instant, zone: ZoneId): List<PlannedNotification> {
        if (copy == null) return emptyList()
        val settings = ReminderSettings.of(ProfileEdits.settings(copy))
        if (!settings.remindersActive && !settings.summaryActive) return emptyList()
        val clock = RuleClock(zone, now)
        val home = HomeBuilder.build(AccountCopy.decode(copy), clock)
        val train = TrainCopy.read(copy)
        TrainCopy.install(train)
        val trainedToday = home.busy.any { clock.day(it.start) == clock.today }
        val routines = Reminders.routinesByWeekday(train.routines.sortedBy { it.order }.map { it.name to it.weekdaysRaw })
        val out = Reminders.plan(settings.remindersActive, settings.reminderMinute, settings.routineOnly, routines, home.monsterName,
                                 home.snapshot.streak, trainedToday, home.snapshot.stage == Stage.EGG, now, zone).toMutableList()
        if (settings.summaryActive) {
            val fire = WeeklySummary.fireAt(now, zone)
            val prs = WeeklySummary.prs(train.history, train.prs.map { it.date }, WeeklySummary.weekStart(fire))
            val lines = leagueLines(context, uid, copy, cache, home, now)
            WeeklySummary.plan(true, home.busy.map { it.start to it.minutes }, prs, lines, fire)?.let { out += it }
        }
        return out
    }

    /** Posição em cada liga ativa (as duas primeiras), como o resumo do iOS */
    private fun leagueLines(context: Context, uid: String, copy: JsonObject, cache: Map<String, RemoteLeague>,
                            home: com.alonsoalmeida.gymbros.domain.home.HomeData, now: Instant): List<WeeklySummary.LeagueLine> {
        val data = LeagueEdits.read(copy)
        val leagues = data.leagues.orEmpty().map(::League).filter { !it.isOver(now) }.sortedBy { it.j.joinedAt }.take(2)
        if (leagues.isEmpty()) return emptyList()
        val activities = data.activities.associateBy { it.uuid.uppercase() }
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val key = "$LEAGUES-$uid"
        val known = readKnown(prefs.getString(key, null)).toMutableMap()
        val out = mutableListOf<WeeklySummary.LeagueLine>()
        for (l in leagues) {
            val remote = cache[l.code]
            val k = if (remote != null || l.isMock || l.code.isEmpty()) {
                val r = (remote ?: RemoteLeague.EMPTY).applying(l)
                val mine = data.checkIns.orEmpty().filter { it.leagueUUID.equals(l.uuid, true) }.map(::MyCheckIn)
                val reviews = data.reviews.orEmpty().filter { it.leagueUUID.equals(l.uuid, true) }.associate { it.itemID to it.approved }
                val avatar = home.roster.snapshot(l.monsterUUID).form
                val feed = LeagueBoard.feed(l, mine, activities, home.trainerName, avatar, r, reviews)
                val swiss = LeagueBoard.swiss(l, feed, r, uid, now)
                val rank = LeagueBoard.ranking(feed, l, home.trainerName, avatar, null, null, r, swiss, uid)
                Known((rank.indexOfFirst { it.isMe }.takeIf { it >= 0 } ?: 0) + 1, rank.size).also { known[l.uuid] = it }
            } else known[l.uuid]
            k?.let { out += WeeklySummary.LeagueLine(l.emoji, l.name, it.position, it.count, l.end) }
        }
        prefs.edit().putString(key, writeKnown(known.filterKeys { id -> data.leagues.orEmpty().any { it.uuid.equals(id, true) } })).apply()
        return out
    }

    private fun readKnown(raw: String?): Map<String, Known> = runCatching {
        (Json.parseToJsonElement(raw ?: return emptyMap()) as JsonObject).mapValues { (_, v) ->
            val o = v.jsonObject
            Known(o["p"]!!.jsonPrimitive.intOrNull!!, o["n"]!!.jsonPrimitive.intOrNull!!)
        }
    }.getOrDefault(emptyMap())

    private fun writeKnown(m: Map<String, Known>): String =
        JsonObject(m.mapValues { (_, k) -> buildJsonObject { put("p", k.position); put("n", k.count) } }).toString()

    // MARK: Agendar

    /** Refaz a agenda com o que a conta tem agora (chamado pelo app a cada mudança) */
    fun reschedule(context: Context, uid: String, copy: JsonObject?, cache: Map<String, RemoteLeague> = emptyMap()) {
        val ctx = context.applicationContext
        scope.launch {
            lock.withLock {
                val list = runCatching { plan(ctx, uid, copy, cache, Instant.now(), ZoneId.systemDefault()) }.getOrNull() ?: return@withLock
                apply(ctx, list)
            }
        }
    }

    /** Saiu da conta: nada fica agendado */
    fun cancelAll(context: Context) {
        val ctx = context.applicationContext
        scope.launch {
            lock.withLock {
                apply(ctx, emptyList())
                // As posições conhecidas nas ligas também saem do aparelho com a conta
                ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
            }
        }
    }

    private fun apply(context: Context, list: List<PlannedNotification>) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val old = readPlan(prefs.getString(PLAN, null))
        // Sempre regrava: o alarme com o mesmo PendingIntent é substituído (e "Forçar parada" apaga os alarmes do app)
        for (p in old) if (list.none { it.id == p.id }) cancel(context, p.id)
        for (p in list) set(context, p)
        prefs.edit().putString(PLAN, writePlan(list)).apply()
    }

    private fun requestCode(id: String): Int =
        if (id == WeeklySummary.ID) SUMMARY_NOTIFICATION else REMINDER_NOTIFICATION + (id.removePrefix(Reminders.PREFIX).toIntOrNull() ?: 0)

    private fun intent(context: Context, id: String): PendingIntent =
        PendingIntent.getBroadcast(context, requestCode(id),
                                   Intent(context, ReminderReceiver::class.java).setAction(ACTION).putExtra(EXTRA_ID, id),
                                   PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)

    private fun set(context: Context, p: PlannedNotification) {
        val am = context.getSystemService(AlarmManager::class.java) ?: return
        val at = p.at.toEpochMilli()
        // Exato só se o sistema já permitir (o app não pede a permissão especial); senão o Android pode atrasar um pouco
        if (Build.VERSION.SDK_INT < 31 || am.canScheduleExactAlarms()) am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, intent(context, p.id))
        else am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, intent(context, p.id))
    }

    private fun cancel(context: Context, id: String) {
        context.getSystemService(AlarmManager::class.java)?.cancel(intent(context, id))
    }

    private fun readPlan(raw: String?): List<PlannedNotification> = runCatching {
        (Json.parseToJsonElement(raw ?: return emptyList()) as JsonArray).map { e ->
            val o = e.jsonObject
            PlannedNotification(o["id"]!!.jsonPrimitive.content, Instant.ofEpochMilli(o["at"]!!.jsonPrimitive.longOrNull!!),
                                o["title"]!!.jsonPrimitive.content, o["body"]!!.jsonPrimitive.content)
        }
    }.getOrDefault(emptyList())

    private fun writePlan(list: List<PlannedNotification>): String = buildJsonArray {
        for (p in list) add(buildJsonObject { put("id", p.id); put("at", p.at.toEpochMilli()); put("title", p.title); put("body", p.body) })
    }.toString()

    // MARK: Receptor

    /** A cópia da conta aberta neste aparelho (o processo pode ter sido acordado só pelo alarme) */
    private suspend fun account(context: Context): Pair<String, JsonObject?>? {
        val uid = FirebaseAuth.getInstance().currentUser?.uid ?: return null
        val copies = (context.applicationContext as GymBrosApp).container.copies
        copies.start(uid)
        withTimeoutOrNull(6_000) { copies.state.first { it is CopyState.Ready } } ?: return null
        return uid to (copies.state.value as? CopyState.Ready)?.copy
    }

    /** Hora de um lembrete ou do resumo: confere se ainda vale, mostra e refaz a agenda */
    internal suspend fun fire(context: Context, id: String) = lock.withLock {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val planned = readPlan(prefs.getString(PLAN, null)).firstOrNull { it.id == id } ?: return@withLock
        if (FirebaseAuth.getInstance().currentUser == null) { apply(context, emptyList()); return@withLock }
        val account = account(context)
        val now = Instant.now()
        val zone = ZoneId.systemDefault()
        var show = true
        if (account != null) {
            val (uid, copy) = account
            val settings = ReminderSettings.of(ProfileEdits.settings(copy))
            show = if (id == WeeklySummary.ID) settings.summaryActive else {
                val clock = RuleClock(zone, now)
                val trained = copy?.let { HomeBuilder.build(AccountCopy.decode(it), clock).busy.any { b -> clock.day(b.start) == clock.today } } ?: false
                Reminders.stillDue(settings, trained)
            }
            // Os próximos 7 dias e o domingo seguinte, sem o que acabou de passar
            runCatching { plan(context, uid, copy, emptyMap(), now.plusSeconds(1), zone) }.getOrNull()?.let { apply(context, it) }
        }
        if (show) show(context, planned)
    }

    /** Reiniciou, atualizou ou mudou o fuso: refaz pela cópia; sem ela, reaproveita o que estava agendado */
    internal suspend fun restore(context: Context) = lock.withLock {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (FirebaseAuth.getInstance().currentUser == null) { apply(context, emptyList()); return@withLock }
        val account = account(context)
        val fresh = account?.let { (uid, copy) -> runCatching { plan(context, uid, copy, emptyMap(), Instant.now(), ZoneId.systemDefault()) }.getOrNull() }
        if (fresh != null) apply(context, fresh)
        else {
            val keep = readPlan(prefs.getString(PLAN, null)).filter { it.at > Instant.now() }
            keep.forEach { set(context, it) }
            prefs.edit().putString(PLAN, writePlan(keep)).apply()
        }
    }

    private fun show(context: Context, p: PlannedNotification) {
        if (!canNotify(context)) return
        val nm = context.getSystemService(NotificationManager::class.java) ?: return
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(NotificationChannel(CHANNEL, "Lembretes e resumo da semana", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Lembrete para treinar e resumo de domingo"
            })
        }
        val code = requestCode(p.id)
        val open = PendingIntent.getActivity(context, code, Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                                             PendingIntent.FLAG_IMMUTABLE)
        val n = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_train)
            .setContentTitle(p.title)
            .setContentText(p.body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(p.body))
            .setAutoCancel(true)
            .setContentIntent(open)
            .build()
        val nid = if (p.id == WeeklySummary.ID) SUMMARY_NOTIFICATION else REMINDER_NOTIFICATION
        runCatching { NotificationManagerCompat.from(context).notify(nid, n) }
    }

    internal fun idOf(intent: Intent): String? = intent.takeIf { it.action == ACTION }?.getStringExtra(EXTRA_ID)
}

/**
 * Hora do lembrete ou do resumo (só o próprio app dispara, pelo PendingIntent) e o reagendamento depois de reiniciar,
 * atualizar o app ou mudar a hora/fuso do aparelho (o sistema entrega a receptor não exportado).
 */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = LocalReminders.idOf(intent)
        val restore = intent.action in setOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED,
                                             Intent.ACTION_TIMEZONE_CHANGED, Intent.ACTION_TIME_CHANGED)
        if (id == null && !restore) return
        val pending = goAsync()
        CoroutineScope(SupervisorJob() + Dispatchers.Default).launch {
            try {
                if (id != null) LocalReminders.fire(context.applicationContext, id) else LocalReminders.restore(context.applicationContext)
            } finally {
                pending.finish()
            }
        }
    }
}
