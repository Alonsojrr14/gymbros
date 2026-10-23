package com.alonsoalmeida.gymbros.ui.inbox

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.Archive
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.HourglassEmpty
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.PanTool
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.SentimentSatisfied
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.outlined.Cancel
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TimePicker
import androidx.compose.material3.TimePickerDefaults
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.alonsoalmeida.gymbros.data.RemoteFriend
import com.alonsoalmeida.gymbros.data.social.SocialCopy
import com.alonsoalmeida.gymbros.domain.ActivityKind
import com.alonsoalmeida.gymbros.domain.Attribute
import com.alonsoalmeida.gymbros.domain.home.HomeData
import com.alonsoalmeida.gymbros.domain.social.ContentFilter
import com.alonsoalmeida.gymbros.domain.social.DirectKind
import com.alonsoalmeida.gymbros.domain.social.DirectMessage
import com.alonsoalmeida.gymbros.domain.social.InboxPeer
import com.alonsoalmeida.gymbros.domain.social.InboxRules
import com.alonsoalmeida.gymbros.domain.social.Reactions
import com.alonsoalmeida.gymbros.domain.social.ReportedKind
import com.alonsoalmeida.gymbros.domain.social.SocialText
import com.alonsoalmeida.gymbros.domain.social.TrainInvite
import com.alonsoalmeida.gymbros.domain.social.label
import com.alonsoalmeida.gymbros.domain.social.symbol
import com.alonsoalmeida.gymbros.ui.AppEnv
import com.alonsoalmeida.gymbros.ui.auth.GMTextField
import com.alonsoalmeida.gymbros.ui.components.ComposerField
import com.alonsoalmeida.gymbros.ui.components.ContentBlockedNote
import com.alonsoalmeida.gymbros.ui.components.GMAction
import com.alonsoalmeida.gymbros.ui.components.GMActions
import com.alonsoalmeida.gymbros.ui.components.GMButton
import com.alonsoalmeida.gymbros.ui.components.GMButtonKind
import com.alonsoalmeida.gymbros.ui.components.GMChip
import com.alonsoalmeida.gymbros.ui.components.GMDivider
import com.alonsoalmeida.gymbros.ui.components.GMIconButton
import com.alonsoalmeida.gymbros.ui.components.GMSheet
import com.alonsoalmeida.gymbros.ui.components.InboxAvatar
import com.alonsoalmeida.gymbros.ui.components.Symbols
import com.alonsoalmeida.gymbros.ui.components.gmPress
import com.alonsoalmeida.gymbros.ui.copy
import com.alonsoalmeida.gymbros.ui.friends.FriendProfileScreen
import com.alonsoalmeida.gymbros.ui.friends.SocialViewModel
import com.alonsoalmeida.gymbros.ui.moderation.ModerationRequest
import com.alonsoalmeida.gymbros.ui.moderation.ModerationSheets
import com.alonsoalmeida.gymbros.ui.moderation.ModerationStep
import com.alonsoalmeida.gymbros.ui.moderation.ModerationTarget
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMRadius
import com.alonsoalmeida.gymbros.ui.theme.GMType
import com.alonsoalmeida.gymbros.ui.theme.color
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId

/** Cor de cada atividade no convite e no mapa (FriendsLive.swift `LiveFriend.color`) */
private fun kindColor(k: ActivityKind): Color = when (k) {
    ActivityKind.MUSCULACAO, ActivityKind.CROSSFIT -> Attribute.FORCA.color()
    ActivityKind.CORRIDA, ActivityKind.CAMINHADA, ActivityKind.BIKE -> Attribute.RESISTENCIA.color()
    ActivityKind.FUTEBOL, ActivityKind.VOLEI, ActivityKind.LUTAS -> Attribute.AGILIDADE.color()
    else -> Attribute.TECNICA.color()
}

/**
 * Conversa com alguém (Inbox/ConversationView.swift): mensagens, força e convites para treinar junto, reações (segurar a
 * mensagem) e o menu com perfil, arquivar, limpar, denunciar e bloquear. Ao vivo enquanto está aberta.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun ConversationModal(visible: Boolean, peerID: String, env: AppEnv, home: HomeData, onDismiss: () -> Unit) {
    if (!visible || peerID.isEmpty()) return
    val social = SocialViewModel.of(env)
    val friendsVm = SocialViewModel.friends(env)
    val friends = friendsVm.state.collectAsStateWithLifecycle().value.friends
    val data = SocialCopy.read(env.copy())
    val remote by social.inbox.collectAsStateWithLifecycle()
    val error by social.error.collectAsStateWithLifecycle()
    ListenInbox(social) { friends }
    DisposableEffect(peerID) {
        social.openPeer = peerID
        social.clearError()
        social.markRead(peerID)
        onDispose { if (social.openPeer == peerID) social.openPeer = null }
    }
    val peer = social.peer(peerID, friends)
    val all = InboxRules.messages(InboxRules.visible(remote.messages, data.moderation), peerID, data.marks)
    val messages = all.filter { it.kind != DirectKind.REACTION }
    val reactions = all.filter { it.kind == DirectKind.REACTION && it.replyTo != null }.groupBy { it.replyTo!! }
    LaunchedEffect(messages.size) { social.markRead(peerID) }

    var text by remember { mutableStateOf("") }
    var blockedWord by remember { mutableStateOf(false) }
    var inviting by remember { mutableStateOf(false) }
    var dueling by remember { mutableStateOf(false) }
    var menu by remember { mutableStateOf(false) }
    var confirmClear by remember { mutableStateOf(false) }
    var reactingTo by remember { mutableStateOf<DirectMessage?>(null) }
    var profile by remember { mutableStateOf<RemoteFriend?>(null) }
    var moderation by remember { mutableStateOf<ModerationRequest?>(null) }
    val list = rememberLazyListState()
    LaunchedEffect(messages.size) { if (messages.isNotEmpty()) list.scrollToItem(messages.size) }

    fun openProfile() { profile = friends.firstOrNull { it.id == peerID } ?: RemoteFriend(peerID, peer.name, peer.formID, "") }
    fun sendText() {
        val t = text.trim()
        if (t.isEmpty()) return
        if (!ContentFilter.allows(t)) { blockedWord = true; return }
        social.send(DirectKind.TEXT, peerID, data, friends, t) { text = "" }
    }

    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Column(Modifier.fillMaxSize().background(GMColors.bg).safeDrawingPadding().imePadding()) {
            // Cabeçalho
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                GMIconButton(Icons.AutoMirrored.Filled.ArrowBack, "Voltar", onDismiss)
                Row(Modifier.weight(1f).gmPress { openProfile() }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    InboxAvatar(peer.form, 40.dp)
                    Column {
                        Text(peer.name, color = Color.White, style = GMType.headline)
                        Text(peer.form.name, color = GMColors.dim, style = GMType.caption2)
                    }
                }
                GMIconButton(Icons.Filled.MoreHoriz, "Mais opções", { menu = true })
            }
            GMDivider()
            LazyColumn(Modifier.weight(1f).fillMaxWidth(), state = list, contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
                       verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (messages.isEmpty()) item("intro") {
                    Column(Modifier.fillMaxWidth().padding(vertical = 40.dp), horizontalAlignment = Alignment.CenterHorizontally,
                           verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        InboxAvatar(peer.form, 90.dp)
                        Text(peer.name, color = Color.White, style = GMType.title3.copy(fontWeight = FontWeight.Bold))
                        Text("Mande força, chame pra treinar junto ou só diga oi.", color = GMColors.dim, style = GMType.subheadline, textAlign = TextAlign.Center)
                    }
                }
                items(messages.size, key = { messages[it].id }, contentType = { messages[it].kind }) { i ->
                    val m = messages[i]
                    val zone = ZoneId.systemDefault()
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        if (i == 0 || messages[i - 1].date.atZone(zone).toLocalDate() != m.date.atZone(zone).toLocalDate()) {
                            Text(SocialText.dayText(m.date), color = GMColors.dim, style = GMType.caption2.copy(fontWeight = FontWeight.Bold),
                                 textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp))
                        }
                        // Segurar: reagir (e, na dos outros, denunciar)
                        Box(Modifier.fillMaxWidth().combinedClickable(remember { MutableInteractionSource() }, null, onClick = {}, onLongClick = { reactingTo = m })) {
                            MessageView(m, peer, if (m.kind == DirectKind.INVITE) InboxRules.answer(remote.messages, m) else null) { yes ->
                                social.send(DirectKind.INVITE_REPLY, peerID, data, friends, replyTo = m.id, accepted = yes)
                            }
                        }
                        reactions[m.id]?.takeIf { it.isNotEmpty() }?.let { r ->
                            Row(Modifier.fillMaxWidth(), horizontalArrangement = if (m.outgoing) Arrangement.End else Arrangement.Start) {
                                Text(Reactions.summary(r.map { it.text }), color = Color.White, style = GMType.caption,
                                     modifier = Modifier.background(GMColors.raised, CircleShape).padding(horizontal = 8.dp, vertical = 4.dp))
                            }
                        }
                    }
                }
            }
            // Escrever
            Column(Modifier.fillMaxWidth().background(GMColors.bg)) {
                GMDivider()
                Column(Modifier.padding(horizontal = 16.dp).padding(top = 10.dp, bottom = 8.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    if (blockedWord) ContentBlockedNote()
                    error?.let { Text(it, color = GMColors.danger, style = GMType.caption) }
                    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Quick("Mandar força", Icons.Filled.Bolt, GMColors.accent) { social.send(DirectKind.CHEER, peerID, data, friends) }
                        Quick("Treinar junto", Icons.Filled.Group, Attribute.AGILIDADE.color()) { inviting = true }
                        Quick("X1", Icons.Filled.Shield, GMColors.trophy) { dueling = true }
                    }
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        ComposerField(text, { text = it; blockedWord = false }, "Mensagem…", Modifier.weight(1f))
                        val empty = text.isBlank()
                        Box(Modifier.size(46.dp).gmPress(enabled = !empty) { sendText() }.background(if (empty) GMColors.raised else GMColors.accent, CircleShape)
                                .semantics { contentDescription = "Enviar" }, contentAlignment = Alignment.Center) {
                            Icon(Icons.Filled.ArrowUpward, null, tint = if (empty) GMColors.dim else Color.Black, modifier = Modifier.size(22.dp))
                        }
                    }
                }
            }
        }

        GMActions(menu, { menu = false }, title = peer.name, actions = listOf(
            GMAction("Ver perfil", Icons.Filled.AccountCircle) { openProfile() },
            GMAction("Arquivar conversa", Icons.Filled.Archive) { social.archive(peerID); onDismiss() },
            GMAction("Limpar conversa", Icons.Filled.Delete) { confirmClear = true },
        ) + ModerationTarget(peerID, peer.name, kind = null).actions { moderation = it })
        GMActions(confirmClear, { confirmClear = false }, title = "Limpar a conversa?",
                  message = "As mensagens somem só do seu lado. ${peer.name} continua com todas.",
                  actions = listOf(GMAction("Limpar conversa", Icons.Filled.Delete, destructive = true) { social.clear(peerID) }))
        reactingTo?.let { m ->
            val actions = Reactions.quick.map { e -> GMAction("Reagir $e", Icons.Filled.SentimentSatisfied) {
                social.send(DirectKind.REACTION, peerID, data, friends, e, replyTo = m.id)
            } }.toMutableList()
            if (!m.outgoing) actions += GMAction("Denunciar mensagem", Icons.Filled.Flag, destructive = true) {
                moderation = ModerationRequest(ModerationTarget(peerID, peer.name, ReportedKind.DIRECT_MESSAGE, m.id), ModerationStep.REPORT)
            }
            GMActions(true, { reactingTo = null }, title = "Reagir", actions = actions)
        }
        if (inviting) InviteComposer(peer.name, home, onDismiss = { inviting = false }) { invite, note ->
            inviting = false
            social.send(DirectKind.INVITE, peerID, data, friends, note, invite = invite)
        }
        ModerationSheets(moderation, { moderation = it }, social, onBlocked = onDismiss)
        profile?.let { FriendProfileScreen(it, home, friendsVm, onDismiss = { profile = null }, onSoon = {}, env = env) }
        com.alonsoalmeida.gymbros.ui.duels.DuelsModal(dueling, env, home, { dueling = false }, opponentID = peerID)
    }
}

@Composable
private fun Quick(title: String, icon: ImageVector, tint: Color, onClick: () -> Unit) {
    Row(Modifier.gmPress(onClick = onClick).background(tint.copy(alpha = 0.15f), CircleShape).border(1.dp, tint.copy(alpha = 0.5f), CircleShape)
            .padding(horizontal = 12.dp, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = tint, modifier = Modifier.size(14.dp))
        Text(title, color = tint, style = GMType.caption.copy(fontWeight = FontWeight.Bold))
    }
}

/** Uma mensagem (ConversationView.swift `MessageView`): balão, força, convite ou resposta ao convite */
@Composable
private fun MessageView(m: DirectMessage, peer: InboxPeer, answer: Boolean?, reply: (Boolean) -> Unit) {
    val time = @Composable { Text(SocialText.time(m.date), color = GMColors.dim, style = GMType.caption2) }
    val align = if (m.outgoing) Arrangement.End else Arrangement.Start
    when (m.kind) {
        DirectKind.TEXT -> Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp, if (m.outgoing) Alignment.End else Alignment.Start),
                               verticalAlignment = Alignment.Bottom) {
            if (m.outgoing) time()
            SelectionContainer {
                Text(m.text, color = if (m.outgoing) Color.Black else Color.White, style = GMType.subheadline,
                     modifier = Modifier.widthIn(max = 280.dp).background(if (m.outgoing) GMColors.accent else GMColors.card,
                         RoundedCornerShape(topStart = 18.dp, topEnd = 18.dp, bottomStart = if (m.outgoing) 18.dp else 6.dp, bottomEnd = if (m.outgoing) 6.dp else 18.dp))
                         .padding(horizontal = 14.dp, vertical = 10.dp))
            }
            if (!m.outgoing) time()
        }
        DirectKind.CHEER -> Row(Modifier.fillMaxWidth(), horizontalArrangement = align) {
            Column(Modifier.widthIn(max = 300.dp).background(Brush.linearGradient(listOf(GMColors.accent.copy(alpha = 0.28f), GMColors.accent.copy(alpha = 0.08f))), GMRadius.xl)
                       .border(1.dp, GMColors.accent.copy(alpha = 0.5f), GMRadius.xl).padding(14.dp),
                   horizontalAlignment = if (m.outgoing) Alignment.End else Alignment.Start, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text("💪", fontSize = 34.sp)
                    Column {
                        Text(if (m.outgoing) "Você mandou força" else "${peer.name} mandou força", color = Color.White,
                             style = GMType.subheadline.copy(fontWeight = FontWeight.Bold))
                        if (m.text.isNotEmpty()) Text(m.text, color = Color.White.copy(alpha = 0.85f), style = GMType.caption)
                    }
                }
                time()
            }
        }
        DirectKind.INVITE -> {
            val inv = m.invite ?: TrainInvite(ActivityKind.OUTRO.raw, "")
            val color = kindColor(inv.kind)
            val context = LocalContext.current
            Row(Modifier.fillMaxWidth(), horizontalArrangement = align) {
                Column(Modifier.widthIn(max = 290.dp).background(color.copy(alpha = 0.1f), GMRadius.xl).border(1.5.dp, color.copy(alpha = 0.5f), GMRadius.xl)
                           .padding(14.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(46.dp).background(color, CircleShape), contentAlignment = Alignment.Center) {
                            Icon(Symbols.of(inv.kind.symbol), null, tint = Color.Black, modifier = Modifier.size(22.dp))
                        }
                        Column {
                            Text(if (m.outgoing) "Você chamou pra treinar junto" else "Bora treinar junto?", color = Color.White,
                                 style = GMType.subheadline.copy(fontWeight = FontWeight.Bold))
                            Text(inv.kind.label, color = color, style = GMType.caption.copy(fontWeight = FontWeight.Bold))
                        }
                    }
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        if (inv.place.isNotEmpty()) {
                            val maps = if (inv.latitude != null && inv.longitude != null) "geo:${inv.latitude},${inv.longitude}?q=${inv.latitude},${inv.longitude}(${Uri.encode(inv.place)})" else null
                            Row(Modifier.then(if (maps != null) Modifier.gmPress { runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(maps))) } } else Modifier),
                                horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                                Icon(Icons.Filled.LocationOn, null, tint = Color.White, modifier = Modifier.size(14.dp))
                                Text(inv.place, color = Color.White, style = GMType.caption.copy(fontWeight = FontWeight.SemiBold,
                                     textDecoration = if (maps != null) TextDecoration.Underline else null))
                                if (maps != null) Text("Ver no mapa", color = color, style = GMType.caption.copy(fontWeight = FontWeight.SemiBold))
                            }
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Filled.Schedule, null, tint = Color.White, modifier = Modifier.size(14.dp))
                            Text(inv.whenText(), color = Color.White, style = GMType.caption.copy(fontWeight = FontWeight.SemiBold))
                        }
                    }
                    if (m.text.isNotEmpty()) Text(m.text, color = Color.White.copy(alpha = 0.85f), style = GMType.caption)
                    when {
                        answer != null -> Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                            val tint = if (answer) GMColors.accent else GMColors.dim
                            Icon(if (answer) Icons.Filled.CheckCircle else Icons.Outlined.Cancel, null, tint = tint, modifier = Modifier.size(14.dp))
                            Text(if (answer) (if (m.outgoing) "${peer.name} topou" else "Você topou") else (if (m.outgoing) "${peer.name} não vai" else "Você recusou"),
                                 color = tint, style = GMType.caption.copy(fontWeight = FontWeight.Bold))
                        }
                        m.outgoing -> Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Filled.HourglassEmpty, null, tint = GMColors.dim, modifier = Modifier.size(14.dp))
                            Text("Esperando resposta", color = GMColors.dim, style = GMType.caption.copy(fontWeight = FontWeight.Bold))
                        }
                        else -> Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            GMButton("Bora! 🤝", { reply(true) }, Modifier.weight(1f), small = true)
                            GMButton("Hoje não", { reply(false) }, Modifier.weight(1f), kind = GMButtonKind.SECONDARY, small = true)
                        }
                    }
                }
            }
        }
        DirectKind.INVITE_REPLY -> Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            val who = if (m.outgoing) "Você" else peer.name
            val yes = m.accepted == true
            Row(Modifier.background(GMColors.raised, CircleShape).padding(horizontal = 12.dp, vertical = 6.dp),
                horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(if (yes) Icons.Filled.ThumbUp else Icons.Filled.PanTool, null, tint = if (yes) GMColors.accent else GMColors.dim, modifier = Modifier.size(14.dp))
                Text(if (yes) "$who topou o convite" else "$who recusou o convite", color = if (yes) GMColors.accent else GMColors.dim,
                     style = GMType.caption.copy(fontWeight = FontWeight.Bold))
            }
        }
        DirectKind.REACTION -> {}
    }
}

private enum class InviteWhen(val title: String) { NOW("Agora"), TODAY("Hoje"), TOMORROW("Amanhã"), OTHER("Outro dia") }

/**
 * Convite para treinar junto (ConversationView.swift `InviteComposer`): atividade, academia salva ou lugar, quando e um
 * recado. "Outro dia" escolhe entre os próximos dias; o horário abre o relógio.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun InviteComposer(peerName: String, home: HomeData, onDismiss: () -> Unit, send: (TrainInvite, String) -> Unit) {
    val zone = ZoneId.systemDefault()
    var kind by remember { mutableStateOf(ActivityKind.MUSCULACAO) }
    var place by remember { mutableStateOf("") }
    var whenOpt by remember { mutableStateOf(InviteWhen.NOW) }
    var day by remember { mutableStateOf(LocalDate.now(zone).plusDays(2)) }
    var time by remember { mutableStateOf(LocalTime.of(19, 0)) }
    var note by remember { mutableStateOf("") }
    var clock by remember { mutableStateOf(false) }
    val date: Instant? = when (whenOpt) {
        InviteWhen.NOW -> null
        InviteWhen.TODAY -> LocalDate.now(zone).atTime(time).atZone(zone).toInstant()
        InviteWhen.TOMORROW -> LocalDate.now(zone).plusDays(1).atTime(time).atZone(zone).toInstant()
        InviteWhen.OTHER -> day.atTime(time).atZone(zone).toInstant()
    }
    val isPast = date?.let { it < Instant.now() } ?: false
    val allowed = ContentFilter.allows(place, note)
    GMSheet(onDismiss = onDismiss) {
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text("Treinar junto com $peerName", color = Color.White, style = GMType.headline, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (k in ActivityKind.entries.filter { it != ActivityKind.OUTRO }) GMChip(k.label, kind == k) { kind = k }
            }
            if (home.gyms.isNotEmpty()) {
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    for ((_, g) in home.gyms) GMChip(g, place == g) { place = g }
                }
            }
            GMTextField(place, { place = it }, "Onde? (academia, parque…)")
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { for (w in InviteWhen.entries) GMChip(w.title, whenOpt == w) { whenOpt = w } }
            if (whenOpt == InviteWhen.OTHER) {
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    for (n in 2..8) {
                        val d = LocalDate.now(zone).plusDays(n.toLong())
                        GMChip(SocialText.whenText(d.atTime(12, 0).atZone(zone).toInstant()).substringBeforeLast(","), day == d) { day = d }
                    }
                }
            }
            if (whenOpt != InviteWhen.NOW) {
                Row(Modifier.fillMaxWidth().gmPress { clock = true }, verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.Schedule, null, tint = Color.White, modifier = Modifier.size(18.dp))
                    Text("Horário", color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold), modifier = Modifier.padding(start = 10.dp).weight(1f))
                    Text("%02d:%02d".format(time.hour, time.minute), color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold),
                         modifier = Modifier.background(GMColors.raised, CircleShape).padding(horizontal = 12.dp, vertical = 7.dp))
                }
            }
            if (isPast) Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Warning, null, tint = GMColors.warning, modifier = Modifier.size(14.dp))
                Text("Esse horário já passou", color = GMColors.warning, style = GMType.caption.copy(fontWeight = FontWeight.Bold))
            }
            GMTextField(note, { note = it }, "Recado (opcional)")
            if (!allowed) ContentBlockedNote()
            GMButton("Enviar convite", { send(TrainInvite(kind.raw, place.trim(), date), note) }, icon = Icons.AutoMirrored.Filled.Send,
                     enabled = allowed && !isPast)
        }
    }
    if (clock) {
        val state = rememberTimePickerState(time.hour, time.minute, is24Hour = true)
        GMSheet(onDismiss = { clock = false }) {
            Text("Horário", color = Color.White, style = GMType.headline)
            TimePicker(state, colors = TimePickerDefaults.colors(clockDialColor = GMColors.raised, selectorColor = GMColors.accent,
                                                               timeSelectorSelectedContainerColor = GMColors.accent.copy(alpha = 0.25f),
                                                               timeSelectorSelectedContentColor = GMColors.accent))
            GMButton("Confirmar", { time = LocalTime.of(state.hour, state.minute); clock = false })
        }
    }
}
