package com.alonsoalmeida.gymbros.ui.inbox

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.filled.Archive
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.CloudOff
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Forum
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.alonsoalmeida.gymbros.data.RemoteFriend
import com.alonsoalmeida.gymbros.data.social.SocialCopy
import com.alonsoalmeida.gymbros.domain.home.HomeData
import com.alonsoalmeida.gymbros.domain.social.Conversation
import com.alonsoalmeida.gymbros.domain.social.DirectKind
import com.alonsoalmeida.gymbros.domain.social.InboxEvent
import com.alonsoalmeida.gymbros.domain.social.InboxPeer
import com.alonsoalmeida.gymbros.domain.social.InboxRules
import com.alonsoalmeida.gymbros.domain.social.SocialText
import com.alonsoalmeida.gymbros.ui.AppEnv
import com.alonsoalmeida.gymbros.ui.components.GMButton
import com.alonsoalmeida.gymbros.ui.components.GMButtonKind
import com.alonsoalmeida.gymbros.ui.components.GMCard
import com.alonsoalmeida.gymbros.ui.components.GMCountBadge
import com.alonsoalmeida.gymbros.ui.components.GMDivider
import com.alonsoalmeida.gymbros.ui.components.GMEmptyState
import com.alonsoalmeida.gymbros.ui.components.GMIconButton
import com.alonsoalmeida.gymbros.ui.components.GMSection
import com.alonsoalmeida.gymbros.ui.components.GMSegmented
import com.alonsoalmeida.gymbros.ui.components.GMSheet
import com.alonsoalmeida.gymbros.ui.components.InboxAvatar
import com.alonsoalmeida.gymbros.ui.components.SocialSymbols
import com.alonsoalmeida.gymbros.ui.components.gmPress
import com.alonsoalmeida.gymbros.ui.copy
import com.alonsoalmeida.gymbros.ui.friends.SocialViewModel
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMType

/** Tela cheia com X à esquerda, título no meio e um botão opcional à direita (o cabeçalho do GMScreen com `close`) */
@Composable
internal fun FullScreen(title: String, onDismiss: () -> Unit, trailing: @Composable () -> Unit = {}, content: @Composable ColumnScope.() -> Unit) {
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        val shown = remember { MutableTransitionState(false).apply { targetState = true } }
        AnimatedVisibility(shown, enter = slideInVertically { it }) {
            Column(Modifier.fillMaxSize().background(GMColors.bg).safeDrawingPadding()) {
                Box(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), contentAlignment = Alignment.Center) {
                    Text(title, color = Color.White, style = GMType.headline)
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        GMIconButton(Icons.Filled.Close, "Fechar", onDismiss, size = 36.dp)
                        Spacer(Modifier.weight(1f))
                        trailing()
                    }
                }
                Column(Modifier.verticalScroll(rememberScrollState()).padding(16.dp).padding(bottom = 40.dp),
                       verticalArrangement = Arrangement.spacedBy(18.dp), content = content)
            }
        }
    }
}

/** Escuta as mensagens enquanto a tela está aberta e o app na frente (economiza o limite do plano grátis) */
@Composable
internal fun ListenInbox(social: SocialViewModel, friends: () -> List<RemoteFriend>) {
    val owner = LocalLifecycleOwner.current
    DisposableEffect(owner) {
        var on = false
        fun start() { if (!on) { on = true; social.startInbox(friends) } }
        fun stop() { if (on) { on = false; social.stopInbox() } }
        val obs = LifecycleEventObserver { _, e ->
            if (e == Lifecycle.Event.ON_START) start()
            if (e == Lifecycle.Event.ON_STOP) stop()
        }
        owner.lifecycle.addObserver(obs)
        if (owner.lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)) start()
        onDispose { owner.lifecycle.removeObserver(obs); stop() }
    }
}

private enum class InboxTab { ACTIVITY, MESSAGES }

/**
 * Caixa de entrada (Inbox/InboxView.swift): aba Notificações (força, convites e pedidos de amizade) e aba Mensagens
 * (conversas com amigos, arquivadas à parte). O lido, o arquivado e o limpo vão com a conta para o iPhone.
 */
@Composable
fun InboxModal(visible: Boolean, env: AppEnv, home: HomeData, onDismiss: () -> Unit) {
    if (!visible) return
    val social = SocialViewModel.of(env)
    val friendsVm = SocialViewModel.friends(env)
    val friendsState by friendsVm.state.collectAsStateWithLifecycle()
    val friends = friendsState.friends
    val data = SocialCopy.read(env.copy())
    val remote by social.inbox.collectAsStateWithLifecycle()
    val error by social.error.collectAsStateWithLifecycle()
    ListenInbox(social) { friends }
    LaunchedEffect(Unit) { friendsVm.refresh(home); social.clearError() }

    val mod = data.moderation
    val messages = InboxRules.visible(remote.messages, mod)
    val peer = { id: String -> social.peer(id, friends) }
    val requests = friendsState.incoming.filter { !mod.isBlocked(it.id) }.map { InboxPeer(it.id, it.name, it.formID) }
    LaunchedEffect(requests.map { it.id }.toSet()) { social.rememberRequests(requests.map { it.id }.toSet()) }
    val activity = InboxRules.activity(messages, requests, data.marks, peer)
    val unreadActivity = InboxRules.unreadActivity(activity, data.marks)
    val conversations = InboxRules.conversations(messages, data.marks, peer, archived = false)
    val archived = InboxRules.conversations(messages, data.marks, peer, archived = true)
    val unreadMessages = conversations.sumOf { it.unread }

    var tab by remember { mutableStateOf(if (unreadActivity == 0 && unreadMessages > 0) InboxTab.MESSAGES else InboxTab.ACTIVITY) }
    var showArchived by remember { mutableStateOf(false) }
    var composing by remember { mutableStateOf(false) }
    var conversation by remember { mutableStateOf<String?>(null) }
    var done by remember { mutableStateOf(setOf<String>()) }
    // Sair da aba Notificações (ou fechar) marca como vista; a bolinha de "Nova" fica até lá
    val seenAtOpen = remember { data.marks }
    val close = { if (tab == InboxTab.ACTIVITY) social.markActivitySeen(); onDismiss() }

    fun label(t: String, n: Int) = if (n > 0) "$t · $n" else t

    FullScreen("Caixa de entrada", close, trailing = {
        if (tab == InboxTab.MESSAGES) GMIconButton(Icons.Filled.Edit, "Nova mensagem", { composing = true })
    }) {
        GMSegmented(listOf(InboxTab.ACTIVITY to label("Notificações", unreadActivity), InboxTab.MESSAGES to label("Mensagens", unreadMessages)), tab, {
            if (tab == InboxTab.ACTIVITY && it != tab) social.markActivitySeen()
            tab = it
        })
        when {
            remote.error != null -> GMEmptyState(Icons.Filled.CloudOff, "Caixa de entrada indisponível", remote.error!!)
            !remote.loaded -> Box(Modifier.fillMaxWidth().padding(top = 40.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = GMColors.accent) }
            tab == InboxTab.ACTIVITY -> {
                if (activity.isEmpty()) {
                    GMEmptyState(Icons.Filled.Notifications, "Nada por aqui ainda",
                                 "Quando alguém reagir aos seus check-ins, mandar força ou te chamar pra treinar, aparece aqui.")
                } else {
                    val new = activity.filter { InboxRules.isNew(it, seenAtOpen) }
                    val old = activity.filter { !InboxRules.isNew(it, seenAtOpen) }
                    @Composable
                    fun rows(list: List<InboxEvent>) = list.forEachIndexed { i, e ->
                        InboxEventRow(e, InboxRules.isNew(e, seenAtOpen), e.id in done,
                                      if (e.kind == InboxEvent.Kind.INVITE) e.targetID?.let { id -> messages.firstOrNull { it.id == id } }?.let { InboxRules.answer(messages, it) } else null,
                                      onOpen = {
                                          if (e.kind in setOf(InboxEvent.Kind.CHEER, InboxEvent.Kind.INVITE, InboxEvent.Kind.INVITE_REPLY, InboxEvent.Kind.LIVE_START))
                                              conversation = e.actorID
                                      }) { action ->
                            when (action) {
                                EventAction.CHEER -> social.send(DirectKind.CHEER, e.actorID, data, friends) { done = done + e.id }
                                EventAction.ACCEPT, EventAction.DECLINE -> {
                                    val yes = action == EventAction.ACCEPT
                                    if (e.kind == InboxEvent.Kind.FRIEND_REQUEST) {
                                        if (yes) friendsVm.accept(e.actorID, home) else friendsVm.decline(e.actorID, home)
                                        done = done + e.id
                                    } else {
                                        val m = e.targetID?.let { id -> messages.firstOrNull { it.id == id } }
                                        if (m != null) social.send(DirectKind.INVITE_REPLY, m.peerID, data, friends, replyTo = m.id, accepted = yes) { done = done + e.id }
                                    }
                                }
                            }
                        }
                        if (i < list.lastIndex) GMDivider()
                    }
                    if (new.isNotEmpty()) GMSection("Novas") { rows(new) }
                    if (old.isNotEmpty()) GMSection(if (new.isEmpty()) null else "Anteriores") { rows(old) }
                }
            }
            else -> {
                val list = if (showArchived) archived else conversations
                if (archived.isNotEmpty() || showArchived) {
                    Row(Modifier.gmPress { showArchived = !showArchived }, verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Icon(if (showArchived) Icons.AutoMirrored.Filled.KeyboardArrowLeft else Icons.Filled.Archive, null, tint = GMColors.accent,
                             modifier = Modifier.size(18.dp))
                        Text(if (showArchived) "Voltar para as conversas" else "Arquivadas · ${archived.size}", color = GMColors.accent,
                             style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
                    }
                }
                if (showArchived) {
                    if (list.isEmpty()) GMEmptyState(Icons.Filled.Archive, "Nada arquivado", "Conversa arquivada volta quando chega mensagem nova.")
                    else GMCard {
                        list.forEachIndexed { i, c ->
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Box(Modifier.weight(1f).gmPress { conversation = c.peer.id }) { ConversationRow(c) }
                                GMButton("Desarquivar", { social.unarchive(c.peer.id) }, kind = GMButtonKind.SECONDARY, full = false, small = true)
                            }
                            if (i < list.lastIndex) GMDivider()
                        }
                    }
                } else if (list.isEmpty()) {
                    GMEmptyState(Icons.Filled.Forum, "Nenhuma conversa", "Mande força, chame um amigo pra treinar junto ou só diga oi.")
                    GMButton("Nova mensagem", { composing = true }, icon = Icons.Filled.Edit)
                } else {
                    GMCard {
                        list.forEachIndexed { i, c ->
                            Box(Modifier.fillMaxWidth().gmPress { conversation = c.peer.id }) { ConversationRow(c) }
                            if (i < list.lastIndex) GMDivider()
                        }
                    }
                }
            }
        }
        error?.let { Text(it, color = GMColors.danger, style = GMType.caption) }
    }

    if (composing) {
        GMSheet(onDismiss = { composing = false }) {
            Text("Nova mensagem", color = Color.White, style = GMType.headline)
            if (friends.isEmpty()) {
                GMEmptyState(Icons.Filled.Group, "Sem amigos ainda", "Mensagens são só entre amigos. Adicione alguém em Amigos.")
            } else {
                Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    for (f in friends.filter { !mod.isBlocked(it.id) }) {
                        Row(Modifier.fillMaxWidth().gmPress { composing = false; conversation = f.id }, verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            InboxAvatar(f.form, 42.dp)
                            Text(f.name, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold), modifier = Modifier.weight(1f))
                            Icon(Icons.Filled.ChevronRight, null, tint = GMColors.dim, modifier = Modifier.size(16.dp))
                        }
                    }
                }
            }
        }
    }
    ConversationModal(conversation != null, conversation.orEmpty(), env, home, onDismiss = { conversation = null })
}

internal enum class EventAction { CHEER, ACCEPT, DECLINE }

private fun icon(e: InboxEvent): Pair<ImageVector, Color> = when (e.kind) {
    InboxEvent.Kind.REACTION, InboxEvent.Kind.COMMENT -> SocialSymbols.reactions to SocialSymbols.reactionsTint
    InboxEvent.Kind.LIVE_START -> SocialSymbols.friendsTraining to SocialSymbols.trainingTint
    InboxEvent.Kind.FRIEND_REQUEST -> SocialSymbols.friendRequests to SocialSymbols.requestsTint
    InboxEvent.Kind.CHEER -> SocialSymbols.cheers to SocialSymbols.cheersTint
    InboxEvent.Kind.INVITE, InboxEvent.Kind.INVITE_REPLY -> SocialSymbols.invites to SocialSymbols.invitesTint
}

/** Linha de notificação (InboxView.swift `InboxEventRow`): bro com o ícone do tipo, frase, citação, tempo e ações */
@Composable
private fun InboxEventRow(e: InboxEvent, isNew: Boolean, done: Boolean, answer: Boolean?, onOpen: () -> Unit, act: (EventAction) -> Unit) {
    val (badge, tint) = icon(e)
    Row(Modifier.fillMaxWidth().gmPress(onClick = onOpen), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        InboxAvatar(e.actorForm, badge = badge, tint = tint, live = e.kind == InboxEvent.Kind.LIVE_START)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(buildAnnotatedString {
                withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append(e.actorName) }
                append(" " + e.phrase)
            }, color = Color.White, style = GMType.subheadline)
            if (e.quote.isNotEmpty()) {
                Text(e.quote, color = Color.White.copy(alpha = 0.85f), style = GMType.caption, maxLines = 2, overflow = TextOverflow.Ellipsis,
                     modifier = Modifier.background(GMColors.raised, com.alonsoalmeida.gymbros.ui.theme.GMRadius.s).padding(horizontal = 10.dp, vertical = 6.dp))
            }
            Text(SocialText.shortAgo(e.date), color = GMColors.dim, style = GMType.caption2)
            when (e.kind) {
                InboxEvent.Kind.CHEER, InboxEvent.Kind.LIVE_START ->
                    if (done) DoneLabel("Força enviada")
                    else GMButton(if (e.kind == InboxEvent.Kind.CHEER) "Devolver força 💪" else "Mandar força 💪", { act(EventAction.CHEER) },
                                  kind = GMButtonKind.SECONDARY, full = false, small = true)
                InboxEvent.Kind.INVITE ->
                    if (answer != null) DoneLabel(if (answer) "Você topou" else "Você recusou")
                    else if (done) DoneLabel("Respondido")
                    else Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        GMButton("Bora! 🤝", { act(EventAction.ACCEPT) }, full = false, small = true)
                        GMButton("Hoje não", { act(EventAction.DECLINE) }, kind = GMButtonKind.SECONDARY, full = false, small = true)
                    }
                InboxEvent.Kind.FRIEND_REQUEST ->
                    if (done) DoneLabel("Respondido")
                    else Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        GMButton("Aceitar", { act(EventAction.ACCEPT) }, full = false, small = true)
                        GMButton("Recusar", { act(EventAction.DECLINE) }, kind = GMButtonKind.SECONDARY, full = false, small = true)
                    }
                else -> {}
            }
        }
        if (isNew) Box(Modifier.padding(top = 6.dp).size(8.dp).background(GMColors.accent, CircleShape).semantics { contentDescription = "Nova" })
    }
}

@Composable
private fun DoneLabel(text: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Filled.Check, null, tint = GMColors.accent, modifier = Modifier.size(14.dp))
        Text(text, color = GMColors.accent, style = GMType.caption.copy(fontWeight = FontWeight.Bold))
    }
}

/** Linha de conversa (InboxView.swift `ConversationRow`) */
@Composable
private fun ConversationRow(c: Conversation) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        InboxAvatar(c.peer.form, 50.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(c.peer.name, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold), modifier = Modifier.weight(1f), maxLines = 1)
                Text(SocialText.shortAgo(c.last.date), color = if (c.unread > 0) GMColors.accent else GMColors.dim, style = GMType.caption2)
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(c.last.preview(), color = if (c.unread > 0) Color.White else GMColors.dim, maxLines = 1, overflow = TextOverflow.Ellipsis,
                     style = GMType.caption.copy(fontWeight = if (c.unread > 0) FontWeight.SemiBold else FontWeight.Normal), modifier = Modifier.weight(1f))
                if (c.unread > 0) GMCountBadge(c.unread, GMColors.accent)
            }
        }
    }
}
