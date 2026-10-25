package com.alonsoalmeida.gymbros.ui.settings

import android.Manifest
import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Alarm
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.DarkMode
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.NotificationsActive
import androidx.compose.material.icons.filled.NotificationsOff
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.app.NotificationManagerCompat
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.alonsoalmeida.gymbros.data.leagues.LeagueStore
import com.alonsoalmeida.gymbros.data.reminders.LocalReminders
import com.alonsoalmeida.gymbros.domain.Attribute
import com.alonsoalmeida.gymbros.domain.profile.ProfileEdits
import com.alonsoalmeida.gymbros.domain.reminders.ReminderSettings
import com.alonsoalmeida.gymbros.ui.AppEnv
import com.alonsoalmeida.gymbros.ui.components.GMButton
import com.alonsoalmeida.gymbros.ui.components.GMButtonKind
import com.alonsoalmeida.gymbros.ui.components.GMCard
import com.alonsoalmeida.gymbros.ui.components.GMModal
import com.alonsoalmeida.gymbros.ui.components.GMSection
import com.alonsoalmeida.gymbros.ui.components.GMTimeField
import com.alonsoalmeida.gymbros.ui.copy
import com.alonsoalmeida.gymbros.ui.profile.Hairline
import com.alonsoalmeida.gymbros.ui.profile.Tile
import com.alonsoalmeida.gymbros.ui.profile.ToggleRow
import com.alonsoalmeida.gymbros.ui.profile.profileViewModel
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMType
import com.alonsoalmeida.gymbros.ui.theme.color
import kotlinx.coroutines.delay

/** Permissão de notificações do Android (NotificationPermission.swift): `denied` depois de um pedido recusado */
private class NotifyPermission(val allowed: Boolean, val denied: Boolean)

@Composable
private fun rememberNotifyPermission(): Pair<NotifyPermission, () -> Unit> {
    val context = LocalContext.current
    var allowed by remember { mutableStateOf(NotificationManagerCompat.from(context).areNotificationsEnabled()) }
    var refused by rememberSaveable { mutableStateOf(false) }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok ->
        allowed = ok && NotificationManagerCompat.from(context).areNotificationsEnabled()
        if (!ok) refused = true
    }
    LifecycleResumeEffect(Unit) {
        allowed = NotificationManagerCompat.from(context).areNotificationsEnabled()
        onPauseOrDispose {}
    }
    // Android 13+ pede na hora; antes disso (ou já recusado) só dá para ligar nos ajustes do sistema
    val ask: () -> Unit = {
        if (!allowed) {
            if (Build.VERSION.SDK_INT >= 33 && !refused) launcher.launch(Manifest.permission.POST_NOTIFICATIONS)
            else openSystemSettings(context)
        }
    }
    val denied = !allowed && (refused || Build.VERSION.SDK_INT < 33)
    return NotifyPermission(allowed, denied) to ask
}

private fun openSystemSettings(context: android.content.Context) {
    val i = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    runCatching { context.startActivity(i) }
}

/** Valor da linha "Notificações" no índice dos Ajustes (SettingsView.swift `notificationsValue`) */
@Composable
internal fun notificationsValue(settings: Map<String, Any?>): Pair<String?, Boolean> {
    val context = LocalContext.current
    var allowed by remember { mutableStateOf(true) }
    LifecycleResumeEffect(Unit) {
        allowed = NotificationManagerCompat.from(context).areNotificationsEnabled()
        onPauseOrDispose {}
    }
    val s = ReminderSettings.of(settings)
    return when {
        !allowed -> "Desligadas no Android" to true
        s.paused -> "Pausadas" to false
        s.remindersOn -> "Lembrete às ${ReminderSettings.timeText(s.reminderMinute)}" to false
        else -> null to false
    }
}

/**
 * Notificações (SettingsPages.swift `NotificationSettingsPage`): pausar tudo, lembrete para treinar, resumo da semana,
 * fim do descanso e chegada no lugar de treino. Tudo vai para a cópia da conta (mesmas chaves do iPhone), então vale
 * nos dois aparelhos. A seção "Amigos" do iOS fica de fora: o Android ainda não avisa de força, convites e mensagens.
 */
@Composable
internal fun NotificationSettingsPage(env: AppEnv, onBack: () -> Unit) {
    val vm = profileViewModel(env)
    val ui by vm.state.collectAsStateWithLifecycle()
    val settings = ui?.data?.settings.orEmpty()
    val s = ReminderSettings.of(settings)
    val rest = ProfileEdits.bool(settings, "restNotification", false)
    val arrival = ProfileEdits.bool(settings, "gymNotifyArrival", true)
    val (permission, ask) = rememberNotifyPermission()
    // Liga e, se ainda não pode, pede a permissão (só ao ligar, como o iOS)
    fun turnOn(key: String, on: Boolean) {
        vm.setSetting(key, on)
        if (on) ask()
    }

    GMModal(true, "Notificações", onBack) {
        if (!permission.allowed) PermissionCard(permission.denied, ask)

        GMSection(footer = if (s.paused) "Nada toca até você religar. Mensagens e convites continuam chegando na caixa de entrada." else null) {
            ToggleRow("Pausar todas", s.paused, { vm.setSetting(ReminderSettings.PAUSED, it) },
                      icon = if (s.paused) Icons.Filled.DarkMode else Icons.Filled.Notifications,
                      tint = if (s.paused) Attribute.TECNICA.color() else GMColors.badge, subtitle = "Silencia lembretes e avisos sociais")
        }

        val on = !s.paused
        Box(Modifier.alpha(if (on) 1f else 0.45f)) {
            GMSection("Treino", footer = "O lembrete só chega nos dias em que você ainda não treinou. Com o treino aberto, o celular já vibra no fim do descanso; o alerta é para quem quer o aviso também.") {
                ToggleRow("Lembrete para treinar", s.remindersOn, { turnOn(ReminderSettings.REMINDERS_ON, it) }, icon = Icons.Filled.Alarm,
                          tint = GMColors.streak, subtitle = if (s.remindersOn) "Seu bro te chama no horário escolhido" else null, enabled = on)
                if (s.remindersOn) {
                    GMTimeField(s.reminderMinute, { vm.setSetting(ReminderSettings.REMINDER_MINUTE, it) }, enabled = on)
                    ToggleRow("Só em dias de rotina", s.routineOnly, { vm.setSetting(ReminderSettings.ROUTINE_ONLY, it) }, enabled = on)
                }
                Hairline()
                ToggleRow("Resumo da semana", s.weeklySummary, { turnOn(ReminderSettings.WEEKLY_SUMMARY, it) }, icon = Icons.Filled.CalendarMonth,
                          tint = GMColors.info, subtitle = "Domingo às 19h: treinos, tempo, PRs e ligas", enabled = on)
                Hairline()
                ToggleRow("Fim do descanso", rest, { turnOn("restNotification", it) }, icon = Icons.Filled.Timer, tint = GMColors.accent, enabled = on)
                Hairline()
                ToggleRow("Chegada no lugar de treino", arrival, { vm.setSetting("gymNotifyArrival", it) }, icon = Icons.Filled.LocationOn,
                          tint = GMColors.health, subtitle = "Oferece começar o treino do dia", enabled = on)
            }
        }
    }
}

/** NotificationPrefs.swift `NotificationPermissionCard` */
@Composable
private fun PermissionCard(denied: Boolean, ask: () -> Unit) {
    GMCard {
        Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Tile(if (denied) Icons.Filled.NotificationsOff else Icons.Filled.NotificationsActive, if (denied) GMColors.warning else GMColors.badge)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(if (denied) "Notificações desligadas no Android" else "Saiba na hora quando for a hora de treinar",
                     color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
                Text(if (denied) "Nada do GymBros toca no celular. Lembretes e o resumo da semana não chegam."
                     else "Seus lembretes, o resumo da semana, o fim do descanso e a chegada no lugar de treino.",
                     color = GMColors.dim, style = GMType.caption)
            }
        }
        GMButton(if (denied) "Abrir ajustes do Android" else "Ativar notificações", ask, icon = Icons.Filled.Notifications,
                 kind = GMButtonKind.SECONDARY, small = true)
    }
}

/**
 * Mantém os lembretes e o resumo agendados (App.swift `publish` → `Reminders.schedule` e `WeeklySummary.schedule`):
 * refaz ao abrir o app, a cada mudança na conta (treino salvo, ajuste mudado, algo vindo do iPhone) e quando o placar
 * das ligas chega do servidor.
 */
@Composable
fun ReminderScheduler(env: AppEnv) {
    val context = LocalContext.current
    val copy = env.copy()
    val store = remember(env.uid) { LeagueStore.of(context, env.uid, env.copies) }
    val cache by store.cache.collectAsStateWithLifecycle()
    var resumed by remember { mutableIntStateOf(0) }
    LifecycleResumeEffect(Unit) {
        resumed++
        onPauseOrDispose {}
    }
    LaunchedEffect(copy, cache, resumed) {
        // Várias mudanças seguidas viram uma só
        delay(400)
        LocalReminders.reschedule(context, env.uid, copy, cache)
    }
}
