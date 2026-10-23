package com.alonsoalmeida.gymbros.ui.friends

import android.content.Intent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ArrowCircleUp
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.PanTool
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.SentimentSatisfied
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.alonsoalmeida.gymbros.data.RemoteFriend
import com.alonsoalmeida.gymbros.data.social.SocialCopy
import com.alonsoalmeida.gymbros.domain.ActivityText
import com.alonsoalmeida.gymbros.domain.home.HomeData
import com.alonsoalmeida.gymbros.domain.social.FeedPost
import com.alonsoalmeida.gymbros.domain.social.Moderation
import com.alonsoalmeida.gymbros.domain.social.Reactions
import com.alonsoalmeida.gymbros.domain.social.ReportedKind
import com.alonsoalmeida.gymbros.domain.social.SocialComment
import com.alonsoalmeida.gymbros.domain.social.SocialText
import com.alonsoalmeida.gymbros.domain.social.label
import com.alonsoalmeida.gymbros.domain.social.symbol
import com.alonsoalmeida.gymbros.ui.AppEnv
import com.alonsoalmeida.gymbros.ui.components.ComposerField
import com.alonsoalmeida.gymbros.ui.components.ContentBlockedNote
import com.alonsoalmeida.gymbros.ui.components.GMAction
import com.alonsoalmeida.gymbros.ui.components.GMActions
import com.alonsoalmeida.gymbros.ui.components.GMDivider
import com.alonsoalmeida.gymbros.ui.components.GMEmptyState
import com.alonsoalmeida.gymbros.ui.components.GMIconButton
import com.alonsoalmeida.gymbros.ui.components.GMSheet
import com.alonsoalmeida.gymbros.ui.components.MonsterSprite
import com.alonsoalmeida.gymbros.ui.components.PersonAvatar
import com.alonsoalmeida.gymbros.ui.components.Symbols
import com.alonsoalmeida.gymbros.ui.components.gmPress
import com.alonsoalmeida.gymbros.ui.copy
import com.alonsoalmeida.gymbros.ui.moderation.ModerationRequest
import com.alonsoalmeida.gymbros.ui.moderation.ModerationSheets
import com.alonsoalmeida.gymbros.ui.moderation.ModerationStep
import com.alonsoalmeida.gymbros.ui.moderation.ModerationTarget
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMType

/**
 * Tela cheia de um check-in (Leagues/CheckInDetail.swift `CheckInDetailView`): foto ou bro em destaque, autor, título,
 * detalhes e comentários ao vivo (só com a tela aberta). Segurar um comentário: reagir, apagar o seu ou denunciar.
 */
@OptIn(ExperimentalFoundationApi::class, ExperimentalLayoutApi::class)
@Composable
fun CheckInDetailModal(item: FeedPost?, env: AppEnv, home: HomeData, onDismiss: () -> Unit) {
    if (item == null) return
    val social = SocialViewModel.of(env)
    val friendsVm = SocialViewModel.friends(env)
    val copy = env.copy()
    val data = remember(copy) { SocialCopy.read(copy) }
    val mod = data.moderation
    val mine = if (item.isMe) data.checkIns.firstOrNull { it.uuid.equals(item.id, true) } else null
    val title = mine?.title ?: item.title
    val note = mine?.note ?: item.note
    val photo = if (item.isMe) remember(copy, item.id) { SocialCopy.photo(copy, item.id) } else null
    val all = data.comments
    val comments = all.filter { it.itemID == item.id }
    val visible = mod.visibleComments(comments)
    val reactionComments = visible.filter { it.isReaction }
    fun reactionsTo(c: SocialComment) = mod.visibleComments(all.filter { it.itemID == "c:${c.id}" })
    val gone = !item.isMe && (mod.isHidden(ReportedKind.CHECK_IN, item.id) || mod.isBlocked(item.memberID))
    val target = ModerationTarget(item.memberID, item.name, ReportedKind.CHECK_IN, item.id)
    val name = data.trainerName.ifEmpty { home.trainerName }

    var menu by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }
    var whoReacted by remember { mutableStateOf(false) }
    var commentMenu by remember { mutableStateOf<SocialComment?>(null) }
    var moderation by remember { mutableStateOf<ModerationRequest?>(null) }
    var person by remember { mutableStateOf<RemoteFriend?>(null) }
    var text by remember { mutableStateOf("") }
    var reacting by remember { mutableStateOf(false) }
    var blocked by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val haptic = LocalHapticFeedback.current

    // Comentários de todo mundo neste check-in, e as reações a eles, ao vivo enquanto está aberto
    val watchIDs = listOf(item.id) + visible.filter { !it.isReaction }.map { "c:${it.id}" }
    DisposableEffect(watchIDs.joinToString()) {
        social.watchComments(watchIDs)
        onDispose { social.stopWatchingComments() }
    }

    fun send(raw: String) {
        val t = raw.trim()
        if (t.isEmpty()) return
        if (!social.comment(t, item.id, item.memberID)) { blocked = true; return }
        if (raw == text) text = ""
        haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
    }

    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Column(Modifier.fillMaxSize().background(GMColors.bg).safeDrawingPadding().imePadding()) {
            if (gone) {
                Row(Modifier.padding(16.dp)) { GMIconButton(Icons.AutoMirrored.Filled.ArrowBack, "Voltar", onDismiss) }
                if (mod.isBlocked(item.memberID)) {
                    GMEmptyState(Icons.Filled.PanTool, "Check-in oculto",
                                 "Você bloqueou ${item.name.ifEmpty { "esta pessoa" }}. Para ver de novo, desbloqueie em Ajustes > Privacidade.")
                } else {
                    GMEmptyState(Icons.Filled.Flag, "Check-in denunciado", "Você não vê mais este check-in. ${Moderation.REVIEW_NOTE}")
                }
                return@Column
            }
            Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Hero(item, photo, onBack = onDismiss, onMenu = { menu = true })
                Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    // Autor
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        if (item.isMe) PersonAvatar(home.trainerName, size = 46.dp, photo = home.profilePhoto)
                        else Box(Modifier.size(46.dp).background(GMColors.raised, CircleShape), contentAlignment = Alignment.Center) {
                            MonsterSprite(item.avatar, Modifier.size(37.dp))
                        }
                        Column(Modifier.weight(1f)) {
                            Text(if (item.isMe) name.ifEmpty { "Você" } else item.name, color = Color.White, style = GMType.headline)
                            Text(SocialText.whenText(item.date) + (item.place?.let { " · $it" } ?: ""), color = GMColors.dim, style = GMType.subheadline, maxLines = 2)
                        }
                        Icon(if (photo == null) Symbols.of(item.kind.symbol) else Icons.Filled.Image, null, tint = Color.White, modifier = Modifier.size(22.dp))
                    }
                    Text(title, color = Color.White, fontSize = 26.sp, fontWeight = FontWeight.Black)
                    if (note.isNotEmpty()) Text(note, color = Color.White.copy(alpha = 0.85f), style = GMType.body)
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Chip(Icons.Filled.Timer, ActivityText.duration(item.minutes))
                        Chip(Symbols.of(item.kind.symbol), item.kind.label)
                        // Pontos de liga dependem das regras da liga (frente das ligas); no perfil vale XP
                        if (item.leagueID == null) Chip(Icons.Filled.Bolt, "+${item.score} XP", GMColors.accent)
                        item.place?.let { Chip(Icons.Filled.LocationOn, it) }
                    }
                    if (visible.isNotEmpty()) {
                        GMDivider()
                        if (reactionComments.isNotEmpty()) {
                            Row(Modifier.gmPress { whoReacted = true }, horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                                Text(Reactions.summary(reactionComments.map { it.text }), color = Color.White, style = GMType.subheadline)
                                Text("· quem reagiu", color = GMColors.accent, style = GMType.caption.copy(fontWeight = FontWeight.SemiBold))
                            }
                        }
                        for (c in visible) androidx.compose.runtime.key(c.id) {
                            Row(Modifier.fillMaxWidth().combinedClickable(remember { MutableInteractionSource() }, null, onClick = {},
                                                                          onLongClick = { commentMenu = c }),
                                horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                val open = { if (!c.isMine) person = RemoteFriend(c.authorID, c.authorName, "", "") }
                                if (c.isMine) PersonAvatar(home.trainerName, size = 32.dp, photo = home.profilePhoto)
                                else PersonAvatar(c.authorName, size = 32.dp, modifier = Modifier.gmPress(onClick = open))
                                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                                        Text(if (c.isMine) name.ifEmpty { "Você" } else c.authorName, color = Color.White,
                                             style = GMType.caption.copy(fontWeight = FontWeight.Bold), modifier = Modifier.gmPress(onClick = open))
                                        Text(SocialText.shortAgo(c.date), color = GMColors.dim, style = GMType.caption2)
                                    }
                                    Text(mention(c.text), color = Color.White, style = if (c.isReaction) GMType.largeTitle.copy(fontWeight = FontWeight.Normal) else GMType.subheadline)
                                    val r = reactionsTo(c)
                                    if (r.isNotEmpty()) Text(Reactions.summary(r.map { it.text }), color = Color.White, style = GMType.caption,
                                                             modifier = Modifier.background(GMColors.raised, CircleShape).padding(horizontal = 8.dp, vertical = 3.dp))
                                }
                            }
                        }
                    }
                }
            }
            // Escrever
            Column(Modifier.fillMaxWidth().background(GMColors.bg).padding(horizontal = 16.dp).padding(top = 10.dp, bottom = 8.dp),
                   verticalArrangement = Arrangement.spacedBy(10.dp)) {
                if (blocked) ContentBlockedNote()
                AnimatedVisibility(reacting) {
                    Row(Modifier.fillMaxWidth().background(GMColors.card, CircleShape).padding(vertical = 6.dp)) {
                        for (e in Reactions.detail) Box(Modifier.weight(1f).gmPress { send(e); reacting = false }, contentAlignment = Alignment.Center) {
                            Text(e, fontSize = 30.sp)
                        }
                    }
                }
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    ComposerField(text, { text = it; blocked = false }, "Comentar…", Modifier.weight(1f), maxLines = 4) {
                        if (text.isNotBlank()) Icon(Icons.Filled.ArrowCircleUp, "Enviar", tint = GMColors.accent,
                                                     modifier = Modifier.size(28.dp).gmPress { send(text) })
                    }
                    Box(Modifier.size(50.dp).gmPress { reacting = !reacting }.background(GMColors.card, CircleShape), contentAlignment = Alignment.Center) {
                        Icon(if (reacting) Icons.Filled.Close else Icons.Filled.SentimentSatisfied, if (reacting) "Fechar reações" else "Reagir",
                             tint = Color.White, modifier = Modifier.size(26.dp))
                    }
                }
            }
        }

        // Menu do post
        val actions = mutableListOf(GMAction("Compartilhar", Icons.Filled.Share) {
            val send = Intent(Intent.ACTION_SEND).setType("text/plain")
                .putExtra(Intent.EXTRA_TEXT, "$title · ${item.kind.label}, ${ActivityText.duration(item.minutes)} no GymBros 💪")
            context.startActivity(Intent.createChooser(send, null))
        })
        if (mine != null) actions += GMAction("Apagar check-in", Icons.Filled.Delete, destructive = true) { confirmDelete = true }
        else if (!item.isMe) {
            val list = target.actions { moderation = it }.toMutableList()
            if (item.hasPhoto && !mod.isHidden(ReportedKind.PHOTO, item.id)) {
                val p = ModerationTarget(item.memberID, item.name, ReportedKind.PHOTO, item.id)
                list.add(1, GMAction("Denunciar foto", Icons.Filled.Image) { moderation = ModerationRequest(p, ModerationStep.REPORT) })
            }
            actions += list
        }
        GMActions(menu, { menu = false }, title = title, actions = actions)
        GMActions(confirmDelete, { confirmDelete = false }, title = "Apagar check-in?", message = "Sai desta liga. A atividade continua no seu histórico.",
                  actions = listOf(GMAction("Apagar check-in", Icons.Filled.Delete, destructive = true) {
                      social.deleteCheckIn(item.id, comments + comments.flatMap { reactionsTo(it) })
                      onDismiss()
                  }))
        commentMenu?.let { c ->
            val list = Reactions.quick.map { e -> GMAction("Reagir $e", Icons.Filled.SentimentSatisfied) { social.comment(e, "c:${c.id}", c.authorID) } }.toMutableList()
            if (c.isMine) list += GMAction("Apagar comentário", Icons.Filled.Delete, destructive = true) { social.removeComment(c, reactionsTo(c)) }
            else list += GMAction("Denunciar comentário", Icons.Filled.Flag, destructive = true) {
                moderation = ModerationRequest(ModerationTarget(c.authorID, c.authorName, ReportedKind.COMMENT, c.id), ModerationStep.REPORT)
            }
            GMActions(true, { commentMenu = null }, title = "Comentário", actions = list)
        }
        if (whoReacted) {
            GMSheet(onDismiss = { whoReacted = false }) {
                Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    Text("Quem reagiu", color = Color.White, style = GMType.headline)
                    for ((emoji, list) in reactionComments.groupBy { it.text }.entries.sortedByDescending { it.value.size }) {
                        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Text("$emoji ${list.size}", color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.Bold))
                            Text(list.joinToString(", ") { if (it.isMine) "Você" else it.authorName }, color = GMColors.dim, style = GMType.subheadline)
                        }
                    }
                }
            }
        }
        ModerationSheets(moderation, { moderation = it }, social, onBlocked = onDismiss)
        person?.let { p -> FriendProfileScreen(p, home, friendsVm, onDismiss = { person = null }, onSoon = {}, env = env) }
    }
}

/** Foto em destaque (com o fundo borrado dela mesma) ou o bro sobre um degradê */
@Composable
private fun Hero(item: FeedPost, photo: ByteArray?, onBack: () -> Unit, onMenu: () -> Unit) {
    val image = remember(photo) { photo?.let { runCatching { android.graphics.BitmapFactory.decodeByteArray(it, 0, it.size)?.asImageBitmap() }.getOrNull() } }
    Box(Modifier.fillMaxWidth().height(if (image == null) 300.dp else 460.dp)
            .clip(RoundedCornerShape(bottomStart = 20.dp, bottomEnd = 20.dp))) {
        if (image != null) {
            Image(image, null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize().blur(40.dp), alpha = 0.7f)
            Image(image, null, contentScale = ContentScale.Fit, modifier = Modifier.fillMaxSize())
        } else {
            Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf((if (item.isMe) GMColors.accent else Color.White).copy(alpha = 0.25f), GMColors.card))))
            Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                MonsterSprite(item.avatar, Modifier.size(150.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Symbols.of(item.kind.symbol), null, tint = Color.White.copy(alpha = 0.8f), modifier = Modifier.size(18.dp))
                    Text(item.kind.label, color = Color.White.copy(alpha = 0.8f), style = GMType.headline)
                }
            }
        }
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
            GMIconButton(Icons.AutoMirrored.Filled.ArrowBack, "Voltar", onBack)
            Spacer(Modifier.weight(1f))
            GMIconButton(Icons.Filled.MoreHoriz, "Mais opções", onMenu)
        }
    }
}

@Composable
private fun Chip(icon: ImageVector, text: String, tint: Color = Color.White) {
    Row(Modifier.background(GMColors.raised, CircleShape).padding(horizontal = 14.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = tint, modifier = Modifier.size(16.dp))
        Text(text, color = tint, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
    }
}

/** "@fulano" em verde e negrito (LeagueNotifications.swift `mentionText`) */
private fun mention(text: String) = buildAnnotatedString {
    text.split(" ").forEachIndexed { i, w ->
        if (i > 0) append(" ")
        if (w.startsWith("@") && w.length > 1) withStyle(SpanStyle(color = GMColors.accent, fontWeight = FontWeight.Bold)) { append(w) } else append(w)
    }
}
