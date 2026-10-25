package com.alonsoalmeida.gymbros.data.train

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
import com.alonsoalmeida.gymbros.MainActivity
import com.alonsoalmeida.gymbros.R
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.time.Instant

/**
 * Fim do descanso com o app em segundo plano (LiveWorkout.startRest): notificação local "Descanso acabou", só com o
 * ajuste "restNotification" ligado e a permissão de notificações dada. Alarme exato só se o sistema já permitir
 * (o app não pede a permissão especial); senão o Android pode atrasar um pouco. Com a tela aberta, o app vibra na hora.
 * O alarme também acorda o app para a notificação do treino em andamento (LiveWorkout) mostrar que o descanso acabou,
 * mesmo com o aviso desligado; o aviso "Descanso acabou" só sai com o ajuste ligado.
 */
object RestAlarm {
    private const val CHANNEL = "rest"
    private const val ID = 4201
    private const val EXTRA_NOTIFY = "notify"

    fun canNotify(context: Context): Boolean =
        Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    private fun intent(context: Context, notify: Boolean = false): PendingIntent =
        PendingIntent.getBroadcast(context, ID, Intent(context, RestReceiver::class.java).putExtra(EXTRA_NOTIFY, notify),
                                   PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)

    fun schedule(context: Context, end: Instant, enabled: Boolean) {
        cancel(context)
        if (!canNotify(context)) return
        val am = context.getSystemService(AlarmManager::class.java) ?: return
        val at = end.toEpochMilli()
        val pi = intent(context, enabled)
        if (Build.VERSION.SDK_INT < 31 || am.canScheduleExactAlarms()) am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
        else am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
    }

    internal fun notifies(intent: Intent): Boolean = intent.getBooleanExtra(EXTRA_NOTIFY, false)

    fun cancel(context: Context) {
        context.getSystemService(AlarmManager::class.java)?.cancel(intent(context))
        NotificationManagerCompat.from(context).cancel(ID)
    }

    internal fun show(context: Context) {
        if (!canNotify(context)) return
        val nm = context.getSystemService(NotificationManager::class.java) ?: return
        if (Build.VERSION.SDK_INT >= 26) nm.createNotificationChannel(NotificationChannel(CHANNEL, "Descanso do treino", NotificationManager.IMPORTANCE_HIGH))
        val open = PendingIntent.getActivity(context, ID, Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                                             PendingIntent.FLAG_IMMUTABLE)
        val n = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_train)
            .setContentTitle("Descanso acabou")
            .setContentText("Bora para a próxima série 💪")
            .setAutoCancel(true)
            .setContentIntent(open)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()
        runCatching { NotificationManagerCompat.from(context).notify(ID, n) }
    }
}

class RestReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (RestAlarm.notifies(intent)) RestAlarm.show(context)
        // Notificação do treino em andamento: "Descanso acabou" mesmo com o app fechado
        val pending = goAsync()
        CoroutineScope(Dispatchers.Main.immediate).launch { try { LiveWorkout.wake(context) } finally { pending.finish() } }
    }
}
