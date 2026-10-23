package com.alonsoalmeida.gymbros.ui.leagues

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddCircleOutline
import androidx.compose.material.icons.filled.Autorenew
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.ConfirmationNumber
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.alonsoalmeida.gymbros.data.leagues.LeagueStore
import com.alonsoalmeida.gymbros.domain.backup.AccountEdits
import com.alonsoalmeida.gymbros.domain.home.HomeData
import com.alonsoalmeida.gymbros.domain.leagues.League
import com.alonsoalmeida.gymbros.ui.AppEnv
import com.alonsoalmeida.gymbros.ui.components.GMBadge
import com.alonsoalmeida.gymbros.ui.components.GMButton
import com.alonsoalmeida.gymbros.ui.components.GMButtonKind
import com.alonsoalmeida.gymbros.ui.components.GMCard
import com.alonsoalmeida.gymbros.ui.components.GMDivider
import com.alonsoalmeida.gymbros.ui.components.GMEmptyState
import com.alonsoalmeida.gymbros.ui.components.GMRow
import com.alonsoalmeida.gymbros.ui.components.GMScreen
import com.alonsoalmeida.gymbros.ui.components.GMSection
import com.alonsoalmeida.gymbros.ui.components.MonsterSprite
import com.alonsoalmeida.gymbros.ui.components.PersonAvatar
import com.alonsoalmeida.gymbros.ui.components.gmPress
import com.alonsoalmeida.gymbros.ui.friends.TermsPrompt
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMType
import com.dd.plist.NSDate
import com.dd.plist.NSNumber
import kotlinx.coroutines.launch
import java.time.Instant
import java.util.Date

/** `Terms.version` do iOS */
private const val TERMS_VERSION = 2

@Composable
fun leaguesViewModel(env: AppEnv): LeaguesViewModel = viewModel(key = "leagues-${env.uid}", factory = viewModelFactory {
    initializer { LeaguesViewModel(LeagueStore.of(env.context, env.uid, env.copies)) }
})

/** Aba Ligas (Leagues/LeaguesView.swift `LeaguesView`) */
@Composable
fun LeaguesTab(env: AppEnv, home: HomeData) {
    val vm = leaguesViewModel(env)
    val ui by vm.ui.collectAsStateWithLifecycle()
    val cache by vm.cache.collectAsStateWithLifecycle()
    val roles by vm.roles.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    var opened by rememberSaveable { mutableStateOf<String?>(null) }
    var creating by rememberSaveable { mutableStateOf(false) }
    var joining by rememberSaveable { mutableStateOf(false) }
    // Ao voltar para o app: renova, confere pedidos, relê e manda o que falta (o .task do iOS)
    LifecycleResumeEffect(Unit) {
        vm.onOpen()
        onPauseOrDispose { }
    }

    GMScreen("Ligas", leading = { PersonAvatar(home.trainerName, size = 40.dp, photo = home.profilePhoto) }, bottomInset = 120.dp) {
        when {
            home.termsVersion < TERMS_VERSION -> TermsPrompt {
                scope.launch {
                    env.copies.edit { c ->
                        AccountEdits.updateSettings(c ?: AccountEdits.empty(home.trainerName, Instant.now())) {
                            it["termsAcceptedVersion"] = NSNumber(TERMS_VERSION); it["termsAcceptedAt"] = NSDate(Date())
                        }
                    }
                }
            }
            roles == null -> Box(Modifier.fillMaxWidth().padding(vertical = 40.dp), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = GMColors.accent)
            }
            roles!!.isEmpty() -> GMCard { GMEmptyState(Icons.Filled.Lock, "Sem acesso", "Sua conta não tem permissão para ver isto.") }
            else -> {
                val now = Instant.now()
                val list = ui.current
                if (list.isEmpty()) GMEmptyState(Icons.Filled.EmojiEvents, "Nenhuma liga", "Crie uma liga e chame os amigos, ou entre com um código.")
                for (l in list) {
                    GMCard(Modifier.gmPress { opened = l.uuid }) { LeagueRow(l, ui, home, vm, cache, env.uid, now) }
                }
                PendingJoinsSection(ui) { code -> vm.launch { cancelJoin(code) } }
                GMSection(footer = "Cada liga é um ranking de check-ins, de qualquer atividade. Ao entrar, você escolhe quem te representa: um bro seu ou um ovo novo. Os check-ins da liga dão XP para ele (um pouco menos que para o seu principal, que sempre recebe tudo).") {
                    GMRow("Criar liga", icon = Icons.Filled.AddCircleOutline, iconTint = GMColors.accent, chevron = true, onClick = { creating = true })
                    GMDivider()
                    GMRow("Entrar com código", icon = Icons.Filled.ConfirmationNumber, iconTint = GMColors.accent, chevron = true, onClick = { joining = true })
                }
            }
        }
    }

    opened?.let { id ->
        val l = ui.league(id)
        if (l == null) LaunchedEffect(id) { opened = null }
        else LeagueDetailScreen(l, env, home, vm, onOpen = { opened = it }, onDismiss = { opened = null })
    }
    if (creating) CreateLeagueScreen(env, home, vm, null, null) { creating = false }
    if (joining) JoinLeagueScreen(env, home, vm, "") { joining = false }
}

/** Uma liga na lista (LeaguesView.swift `LeagueRow`) */
@Composable
private fun LeagueRow(l: League, ui: LeaguesUi, home: HomeData, vm: LeaguesViewModel, cache: Map<String, com.alonsoalmeida.gymbros.domain.leagues.RemoteLeague>,
                      uid: String, now: Instant) {
    val remote = vm.remote(cache, l)
    val board = remember(l, ui, remote, home.roster) { LeaguesViewModel.board(l, ui, home, remote, uid, now) }
    val pos = board.total.indexOfFirst { it.isMe }.let { if (it < 0) 0 else it } + 1
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(l.emoji, fontSize = 34.sp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(l.name, color = Color.White, style = GMType.headline, maxLines = 1, modifier = Modifier.weight(1f, fill = false))
                if (l.isMock) GMBadge("Exemplo", Color.White)
                if (l.autoRenew) Icon(Icons.Filled.Autorenew, null, tint = GMColors.dim, modifier = Modifier.size(13.dp))
            }
            val status = if (l.isOver(now)) "encerrado" else l.daysLeft(now)?.let { if (it == 1) "último dia" else "faltam $it dias" } ?: "clube"
            Text((if (l.season > 1) "T${l.season} · " else "") + "${pos}º de ${board.total.size} · " + status, color = GMColors.dim, style = GMType.caption)
        }
        MonsterSprite(board.avatar, Modifier.size(44.dp))
        Icon(Icons.Filled.ChevronRight, null, tint = GMColors.dim, modifier = Modifier.size(16.dp))
    }
}

/** Pedidos esperando aprovação (LeagueModerationViews.swift `PendingJoinsSection`) */
@Composable
private fun PendingJoinsSection(ui: LeaguesUi, onCancel: (String) -> Unit) {
    val list = ui.pendingJoins
    if (list.isEmpty()) return
    GMSection("Esperando aprovação", footer = "O dono da liga aprova cada pedido. Quando aceitar, a liga aparece aqui.") {
        list.forEachIndexed { i, p ->
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(p.emoji, fontSize = 22.sp)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(p.name, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
                    Text("Pedido enviado ${LeagueFormats.ago(p.date)}", color = GMColors.dim, style = GMType.caption)
                }
                GMButton("Cancelar", { onCancel(p.code) }, kind = GMButtonKind.SECONDARY, full = false, small = true,
                         modifier = Modifier.semantics { contentDescription = "Cancelar pedido para ${p.name}" })
            }
            if (i < list.lastIndex) GMDivider()
        }
    }
}
