package com.alonsoalmeida.gymbros.ui.friends

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.automirrored.filled.Reply
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.alonsoalmeida.gymbros.data.RemoteFriend
import com.alonsoalmeida.gymbros.data.social.SocialCopy
import com.alonsoalmeida.gymbros.domain.ActivityText
import com.alonsoalmeida.gymbros.domain.home.HomeData
import com.alonsoalmeida.gymbros.domain.social.DeckCard
import com.alonsoalmeida.gymbros.domain.social.DirectKind
import com.alonsoalmeida.gymbros.domain.social.FriendsMetric
import com.alonsoalmeida.gymbros.domain.social.FriendsRanking
import com.alonsoalmeida.gymbros.domain.social.Reactions
import com.alonsoalmeida.gymbros.domain.social.RankWindow
import com.alonsoalmeida.gymbros.domain.social.SocialText
import com.alonsoalmeida.gymbros.domain.social.label
import com.alonsoalmeida.gymbros.ui.AppEnv
import com.alonsoalmeida.gymbros.ui.auth.GMTextField
import com.alonsoalmeida.gymbros.ui.components.ContentBlockedNote
import com.alonsoalmeida.gymbros.ui.components.GMButton
import com.alonsoalmeida.gymbros.ui.components.GMButtonKind
import com.alonsoalmeida.gymbros.ui.components.GMChip
import com.alonsoalmeida.gymbros.ui.components.GMDivider
import com.alonsoalmeida.gymbros.ui.components.GMEmptyState
import com.alonsoalmeida.gymbros.ui.components.GMIconButton
import com.alonsoalmeida.gymbros.ui.components.GMModal
import com.alonsoalmeida.gymbros.ui.components.GMSection
import com.alonsoalmeida.gymbros.ui.components.GMSegmented
import com.alonsoalmeida.gymbros.ui.components.GMSheet
import com.alonsoalmeida.gymbros.ui.components.MonsterSprite
import com.alonsoalmeida.gymbros.ui.components.gmPress
import com.alonsoalmeida.gymbros.ui.copy
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMRadius
import com.alonsoalmeida.gymbros.ui.theme.GMType
import kotlinx.coroutines.delay
import java.time.Instant

/** Ranking dos bros completo (FriendsFeed.swift `FriendsRankingView`): métrica, janela e todo mundo */
@Composable
fun RankingModal(visible: Boolean, env: AppEnv, home: HomeData, friendsVm: FriendsViewModel, onDismiss: () -> Unit) {
    if (!visible) return
    val social = SocialViewModel.of(env)
    val data = SocialCopy.read(env.copy())
    val friends = friendsVm.state.collectAsStateValue().value.friends
    val remote by social.feed.collectAsStateValue()
    var metric by remember { mutableStateOf(FriendsMetric.CHECK_INS) }
    var window by remember { mutableStateOf(RankWindow.SEMANA) }
    val rows = social.ranking(data, remote, friends, home.snapshot.form, metric, window.since(Instant.now()))
    GMModal(true, "Ranking dos bros", onDismiss) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            for (m in FriendsMetric.entries) GMChip(m.title, metric == m) { metric = m }
        }
        GMSegmented(RankWindow.entries.map { it to if (it == RankWindow.LIGA) "Sempre" else it.title }, window, { window = it })
        if (friends.isEmpty()) {
            GMEmptyState(Icons.Filled.People, "Sem amigos ainda", "Adicione amigos para comparar os treinos postados no perfil.")
        } else {
            GMSection(footer = "Conta o que cada um postou no perfil (o que os amigos veem), sem precisar de liga.") {
                rows.forEachIndexed { i, r ->
                    if (i > 0) GMDivider()
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text(FriendsRanking.medal(i), color = Color.White, textAlign = TextAlign.Center, modifier = Modifier.width(32.dp),
                             style = if (i < 3) GMType.title3 else GMType.subheadline.copy(fontWeight = FontWeight.Bold))
                        MonsterSprite(r.avatar, Modifier.size(36.dp))
                        Text(if (r.isMe) "${r.name} (você)" else r.name, color = Color.White, modifier = Modifier.weight(1f), maxLines = 1,
                             overflow = TextOverflow.Ellipsis, style = GMType.subheadline.copy(fontWeight = if (r.isMe) FontWeight.Bold else FontWeight.SemiBold))
                        Text(metric.format(r.value), color = if (r.isMe) GMColors.accent else Color.White,
                             style = GMType.subheadline.copy(fontWeight = FontWeight.Bold, fontFeatureSettings = "tnum"))
                    }
                }
            }
        }
    }
}

/**
 * O deck (SocialExtras.swift `BroDeckView`): um check-in por vez. Arrasta para o lado para passar, toque duplo manda
 * força, dá para reagir ou responder (no check-in ou por mensagem direta).
 */
@Composable
fun BroDeckModal(cards: List<DeckCard>, start: Int, env: AppEnv, friends: List<RemoteFriend>, onDismiss: () -> Unit) {
    val social = SocialViewModel.of(env)
    val data = SocialCopy.read(env.copy())
    var index by remember { mutableIntStateOf(minOf(start, cards.size)) }
    var drag by remember { mutableFloatStateOf(0f) }
    var burst by remember { mutableStateOf<String?>(null) }
    var replying by remember { mutableStateOf<DeckCard?>(null) }
    var sentNote by remember { mutableStateOf<String?>(null) }
    val haptic = LocalHapticFeedback.current
    val offset by animateFloatAsState(drag, label = "drag")

    fun next() {
        if (index >= cards.size) return
        social.markDeckSeen(listOf(cards[index].id))
        sentNote = null
        drag = 0f
        index++
    }

    LaunchedEffect(burst) {
        if (burst != null) { delay(600); burst = null; next() }
    }

    fun react(e: String) {
        if (index >= cards.size) return
        val c = cards[index]
        social.comment(e, c.id, c.item.memberID)
        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
        burst = e
    }

    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Column(Modifier.fillMaxSize().background(GMColors.bg).safeDrawingPadding().padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp),
               horizontalAlignment = Alignment.CenterHorizontally) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                GMIconButton(Icons.Filled.Close, "Fechar", onDismiss)
                Spacer(Modifier.weight(1f))
                Text(if (index < cards.size) "${index + 1} de ${cards.size}" else "Fim", color = GMColors.dim,
                     style = GMType.subheadline.copy(fontFeatureSettings = "tnum"))
                Spacer(Modifier.weight(1f))
                Spacer(Modifier.size(40.dp))
            }
            if (index < cards.size) {
                val c = cards[index]
                Box(contentAlignment = Alignment.Center) {
                    DeckCardView(c, Modifier.graphicsLayer { translationX = offset; rotationZ = offset / 22f / density }
                        .pointerInput(c.id) {
                            detectDragGestures(onDragEnd = { if (kotlin.math.abs(drag) > 110 * density) next() else drag = 0f },
                                               onDragCancel = { drag = 0f }) { change, amount -> change.consume(); drag += amount.x }
                        }
                        .pointerInput(c.id) { detectTapGestures(onDoubleTap = { react("💪") }) }
                        .semantics { contentDescription = "${c.item.name}, ${c.item.title}. Toque duas vezes para mandar força. Arraste para o lado para passar." })
                    BurstEmoji(burst, 110)
                }
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    for (e in Reactions.deck) {
                        Box(Modifier.size(56.dp).gmPress { react(e) }.background(GMColors.raised, CircleShape).semantics { contentDescription = "Reagir com $e" },
                            contentAlignment = Alignment.Center) { Text(e, fontSize = 30.sp) }
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    GMButton("Responder", { replying = c }, Modifier.weight(1f), icon = Icons.AutoMirrored.Filled.Reply, kind = GMButtonKind.SECONDARY)
                    GMButton("Passar", { next() }, Modifier.weight(1f), icon = Icons.AutoMirrored.Filled.ArrowForward)
                }
                sentNote?.let { Text(it, color = GMColors.dim, style = GMType.caption) }
            } else {
                Spacer(Modifier.weight(1f))
                GMEmptyState(Icons.Filled.Verified, "Você viu tudo", "Quando os bros postarem de novo, aparece aqui.")
                GMButton("Ver de novo", { index = 0 }, icon = Icons.Filled.Replay, kind = GMButtonKind.SECONDARY, full = false)
                Spacer(Modifier.weight(1f))
            }
        }
        replying?.let { c ->
            ReplySheet(c, isFriend = friends.any { it.id == c.item.memberID }, onDismiss = { replying = null }) { text, asDM ->
                if (asDM) {
                    social.send(DirectKind.TEXT, c.item.memberID, data, friends, "Sobre \"${c.item.title}\": $text")
                    sentNote = "Mensagem enviada para ${c.item.name}."
                } else {
                    social.comment(text, c.id, c.item.memberID)
                    sentNote = "Comentário no check-in de ${c.item.name}."
                }
                replying = null
            }
        }
    }
}

@Composable
private fun DeckCardView(c: DeckCard, modifier: Modifier) {
    Column(modifier.fillMaxWidth().clip(GMRadius.xl).background(GMColors.card)) {
        Box(Modifier.fillMaxWidth().height(340.dp).background(Brush.verticalGradient(listOf(GMColors.accent.copy(alpha = 0.35f), GMColors.card))),
            contentAlignment = Alignment.Center) { MonsterSprite(c.item.avatar, Modifier.size(160.dp)) }
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                MonsterSprite(c.item.avatar, Modifier.size(28.dp))
                Text(c.item.name, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.Bold))
                Text("· ${SocialText.shortAgo(c.item.date)}", color = GMColors.dim, style = GMType.caption)
                Spacer(Modifier.weight(1f))
                Text(c.place, color = GMColors.dim, maxLines = 1, overflow = TextOverflow.Ellipsis, style = GMType.caption.copy(fontWeight = FontWeight.SemiBold))
            }
            Text(c.item.title, color = Color.White, maxLines = 2, style = GMType.title3.copy(fontWeight = FontWeight.Bold))
            Text("${c.item.kind.label} · ${ActivityText.duration(c.item.minutes)}", color = GMColors.dim, style = GMType.caption)
        }
    }
}

/** Responder: no check-in (todo mundo da liga vê) ou por mensagem direta (só vocês dois) */
@Composable
private fun ReplySheet(c: DeckCard, isFriend: Boolean, onDismiss: () -> Unit, onSend: (String, Boolean) -> Unit) {
    var text by remember { mutableStateOf("") }
    var asDM by remember { mutableStateOf(false) }
    var blocked by remember { mutableStateOf(false) }
    GMSheet(onDismiss = onDismiss) {
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text("Responder ${c.item.name}", color = Color.White, style = GMType.headline)
            GMSegmented(listOf(false to "No check-in", true to "Mensagem direta"), asDM, { asDM = it })
            Text(if (asDM) (if (isFriend) "Só vocês dois veem." else "Mensagem direta é só entre amigos.") else "Todo mundo da liga vê.",
                 color = GMColors.dim, style = GMType.caption)
            GMTextField(text, { text = it; blocked = false }, "Escreva…")
            if (blocked) ContentBlockedNote()
            GMButton("Enviar", {
                if (!com.alonsoalmeida.gymbros.domain.social.ContentFilter.allows(text)) blocked = true else onSend(text.trim(), asDM)
            }, icon = Icons.AutoMirrored.Filled.Send, enabled = text.isNotBlank() && (!asDM || isFriend))
        }
    }
}

/** O emoji que pula em cima do post (toque duplo ou reação): cresce com mola e some */
@Composable
internal fun BurstEmoji(emoji: String?, size: Int) {
    val scale by animateFloatAsState(if (emoji != null) 1f else 0.3f, androidx.compose.animation.core.spring(dampingRatio = 0.5f), label = "burst")
    if (emoji != null) Text(emoji, fontSize = size.sp, modifier = Modifier.graphicsLayer { scaleX = scale; scaleY = scale })
}
