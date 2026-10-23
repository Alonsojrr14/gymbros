package com.alonsoalmeida.gymbros.ui.leagues

import android.content.Intent
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.EmojiEmotions
import androidx.compose.material.icons.filled.Forum
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.alonsoalmeida.gymbros.data.FriendsRepository
import com.alonsoalmeida.gymbros.data.RemoteFriend
import com.alonsoalmeida.gymbros.domain.ActivityText
import com.alonsoalmeida.gymbros.domain.MonsterForm
import com.alonsoalmeida.gymbros.domain.backup.AccountCopy
import com.alonsoalmeida.gymbros.domain.home.HomeData
import com.alonsoalmeida.gymbros.domain.leagues.DailyPose
import com.alonsoalmeida.gymbros.domain.leagues.DailyWorkout
import com.alonsoalmeida.gymbros.domain.leagues.FeedItem
import com.alonsoalmeida.gymbros.domain.leagues.League
import com.alonsoalmeida.gymbros.domain.leagues.LeagueText
import com.alonsoalmeida.gymbros.domain.leagues.RankRow
import com.alonsoalmeida.gymbros.data.leagues.LeagueStore
import com.alonsoalmeida.gymbros.ui.AppEnv
import com.alonsoalmeida.gymbros.ui.auth.GMSegmented
import com.alonsoalmeida.gymbros.ui.auth.GMTextField
import com.alonsoalmeida.gymbros.ui.components.GMAction
import com.alonsoalmeida.gymbros.ui.components.GMActions
import com.alonsoalmeida.gymbros.ui.components.GMButton
import com.alonsoalmeida.gymbros.ui.components.GMButtonKind
import com.alonsoalmeida.gymbros.ui.components.GMCard
import com.alonsoalmeida.gymbros.ui.components.GMDivider
import com.alonsoalmeida.gymbros.ui.components.GMEmptyState
import com.alonsoalmeida.gymbros.ui.components.GMFlow
import com.alonsoalmeida.gymbros.ui.components.GMIconButton
import com.alonsoalmeida.gymbros.ui.components.GMModal
import com.alonsoalmeida.gymbros.ui.components.GMRow
import com.alonsoalmeida.gymbros.ui.components.GMSection
import com.alonsoalmeida.gymbros.ui.components.GMSheet
import com.alonsoalmeida.gymbros.ui.components.MonsterSprite
import com.alonsoalmeida.gymbros.ui.components.PersonAvatar
import com.alonsoalmeida.gymbros.ui.components.PhotoFill
import com.alonsoalmeida.gymbros.ui.components.Photos
import com.alonsoalmeida.gymbros.ui.components.gmPress
import com.alonsoalmeida.gymbros.ui.friends.FriendProfileScreen
import com.alonsoalmeida.gymbros.ui.friends.FriendsViewModel
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMRadius
import com.alonsoalmeida.gymbros.ui.theme.GMType
import kotlinx.coroutines.launch
import java.text.BreakIterator
import java.time.Instant
import java.time.ZoneId

/** Comentário só com emoji é uma reação (CheckInComment.isReaction) */
fun isReaction(s: String): Boolean {
    val it = BreakIterator.getCharacterInstance().apply { setText(s) }
    var n = 0
    while (it.next() != BreakIterator.DONE) n++
    return n in 1..3 && s.none { c -> c.isLetterOrDigit() || c.isWhitespace() || c in ".,!?;:-_'\"" }
}

// MARK: Mural (LeagueMural.swift)

private data class Line(val id: String, val memberID: String, val name: String, val form: MonsterForm, val isMe: Boolean, val date: Instant,
                        val text: String, val pending: Boolean = false, val photo: ByteArray? = null)

@Composable
fun LeagueMural(league: League, env: AppEnv, home: HomeData, vm: LeaguesViewModel, avatar: MonsterForm, now: Instant) {
    val ui by vm.ui.collectAsStateWithLifecycle()
    val cache by vm.cache.collectAsStateWithLifecycle()
    var text by remember { mutableStateOf("") }
    var photo by remember { mutableStateOf<ByteArray?>(null) }
    var mode by remember { mutableStateOf(0) }
    var menu by remember { mutableStateOf<String?>(null) }
    var viewing by remember { mutableStateOf<ByteArray?>(null) }
    val pickers = rememberPhotoPickers(onPicked = { photo = it.bytes })
    val remote = vm.remote(cache, league)
    val lines = remember(ui, remote) {
        val others = remote.messages.mapNotNull { m -> remote.member(m.memberID)?.let { Line(m.id, it.id, it.name, it.form, false, m.date, m.text) } }
        val mine = ui.copy.messages.orEmpty().filter { it.leagueUUID.equals(league.uuid, true) }.map {
            Line(it.uuid, "me", home.trainerName.ifEmpty { "Você" }, avatar, true, it.date, it.text, it.syncedAt == null, Photos.base64(it.photo))
        }
        others + mine
    }
    val canSend = text.isNotBlank() || photo != null

    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        GMSegmented(listOf(0 to "Conversa", 1 to "Mídia"), mode) { mode = it }
        if (mode == 1) {
            val fromCheckIns = ui.copy.checkIns.orEmpty().filter { it.leagueUUID.equals(league.uuid, true) }.sortedByDescending { it.date }
                .flatMap { listOfNotNull(Photos.base64(it.photo)) + LeagueStore.extraPhotos(it.extraPhotos) }
            val all = (lines.mapNotNull { it.photo } + fromCheckIns).take(120)
            if (all.isEmpty()) GMEmptyState(Icons.Filled.PhotoLibrary, "Nenhuma foto ainda", "Fotos do mural e dos check-ins aparecem aqui.")
            else all.chunked(3).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    for (d in row) Box(Modifier.weight(1f).aspectRatio(1f).clip(GMRadius.s).gmPress { viewing = d }) { PhotoFill(d, Modifier.fillMaxSize(), 400) }
                    repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        } else {
            if (!league.isOver(now)) {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    photo?.let { p ->
                        Box(Modifier.size(90.dp).clip(GMRadius.m)) {
                            PhotoFill(p, Modifier.fillMaxSize(), 300)
                            Box(Modifier.align(Alignment.TopEnd).padding(3.dp).size(22.dp).background(Color.Black.copy(alpha = 0.6f), CircleShape).gmPress { photo = null },
                                contentAlignment = Alignment.Center) { Icon(Icons.Filled.Close, null, tint = Color.White, modifier = Modifier.size(11.dp)) }
                        }
                    }
                    Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        GMIconButton(Icons.Filled.Image, "Mandar foto", pickers.gallery)
                        Box(Modifier.weight(1f)) { GMTextField(text, { text = it }, "Escrever no mural…") }
                        Box(Modifier.size(40.dp).background(if (canSend) GMColors.accent else GMColors.raised, CircleShape)
                                .gmPress(enabled = canSend) {
                                    val t = text.trim()
                                    val p = photo
                                    text = ""; photo = null
                                    vm.launch { addMessage(league.uuid, t, p) }
                                }.semantics { contentDescription = "Enviar" }, contentAlignment = Alignment.Center) {
                            Icon(Icons.Filled.ArrowUpward, null, tint = if (canSend) Color.Black else GMColors.dim, modifier = Modifier.size(18.dp))
                        }
                    }
                }
            }
            if (lines.isEmpty()) GMEmptyState(Icons.Filled.Forum, "Mural vazio", "Mande o primeiro recado pra galera da liga.")
            val zone = ZoneId.systemDefault()
            val days = lines.sortedByDescending { it.date }.take(150).groupBy { it.date.atZone(zone).toLocalDate() }
            for (day in days.keys.sortedDescending()) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(LeagueFormats.dayTitle(day), color = Color.White, style = GMType.headline)
                    for (l in days[day].orEmpty().sortedByDescending { it.date }) Bubble(l, { viewing = it }) { if (l.isMe) menu = l.id }
                }
            }
        }
    }
    GMActions(menu != null, { menu = null }, "Recado", actions = listOf(GMAction("Apagar recado", Icons.Filled.Delete, destructive = true) {
        menu?.let { id -> vm.launch { deleteMessage(id) } }
    }))
    viewing?.let { PhotoViewer(it) { viewing = null } }
}

@Composable
private fun Bubble(l: Line, onPhoto: (ByteArray) -> Unit, onLongPress: () -> Unit) {
    Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        if (l.isMe) Spacer(Modifier.weight(1f).widthIn(min = 40.dp)) else MonsterSprite(l.form, Modifier.size(32.dp))
        Column(Modifier.weight(4f, fill = false).pointerInput(l.id) { detectTapGestures(onLongPress = { onLongPress() }) },
               horizontalAlignment = if (l.isMe) Alignment.End else Alignment.Start, verticalArrangement = Arrangement.spacedBy(3.dp)) {
            if (!l.isMe) Text(l.name, color = GMColors.dim, style = GMType.caption.copy(fontWeight = FontWeight.Bold))
            l.photo?.let { p -> Box(Modifier.size(180.dp).clip(GMRadius.l).gmPress { onPhoto(p) }) { PhotoFill(p, Modifier.fillMaxSize(), 500) } }
            if (l.text.isNotEmpty()) {
                Text(l.text, color = if (l.isMe) Color.Black else Color.White, style = GMType.subheadline,
                     modifier = Modifier.background(if (l.isMe) GMColors.accent else GMColors.card, GMRadius.l).padding(horizontal = 12.dp, vertical = 8.dp))
            }
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                if (l.pending) Icon(Icons.Filled.Schedule, null, tint = GMColors.dim, modifier = Modifier.size(11.dp))
                Text(LeagueFormats.time(l.date), color = GMColors.dim, style = GMType.caption2.copy(fontFeatureSettings = "tnum"))
            }
        }
        if (l.isMe) MonsterSprite(l.form, Modifier.size(32.dp)) else Spacer(Modifier.weight(1f).widthIn(min = 40.dp))
    }
}

@Composable
private fun PhotoViewer(data: ByteArray, onDismiss: () -> Unit) {
    Dialog(onDismiss, DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Box(Modifier.fillMaxSize().background(Color.Black).safeDrawingPadding()) {
            val img = remember(data) { Photos.decode(data, 2000) }
            if (img != null) androidx.compose.foundation.Image(img, null, Modifier.fillMaxSize(), contentScale = androidx.compose.ui.layout.ContentScale.Fit)
            Box(Modifier.padding(16.dp)) { GMIconButton(Icons.Filled.Close, "Fechar", onDismiss) }
        }
    }
}

// MARK: Detalhe do check-in (CheckInDetail.swift)

@Composable
fun CheckInDetailScreen(item: FeedItem, env: AppEnv, home: HomeData, vm: LeaguesViewModel, onDismiss: () -> Unit) {
    val ui by vm.ui.collectAsStateWithLifecycle()
    val others by vm.comments.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var text by remember { mutableStateOf("") }
    var menu by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }
    var removing by remember { mutableStateOf(false) }
    var reacting by remember { mutableStateOf(false) }
    var commentMenu by remember { mutableStateOf<CommentLine?>(null) }
    var whoReacted by remember { mutableStateOf(false) }
    var person by remember { mutableStateOf<RankRow?>(null) }

    val mine = if (item.isMe) ui.checkIn(item.id) else null
    val title = mine?.title ?: item.title
    val note = mine?.note ?: item.note
    val photos = remember(mine) { if (mine == null) emptyList() else listOfNotNull(Photos.base64(mine.photo)) + LeagueStore.extraPhotos(mine.extraPhotos) }
    val myName = home.trainerName.ifEmpty { "Você" }
    fun lines(itemID: String): List<CommentLine> =
        (ui.comments(itemID).map { CommentLine(it.uuid, it.text, it.date, true, "me", myName) } +
            others[itemID].orEmpty().map { CommentLine(it.id, it.text, it.date, false, it.user, it.userName) }).sortedBy { it.date }
    val comments = lines(item.id)
    val reactions = comments.filter { isReaction(it.text) }
    val league = ui.league(item.leagueID)
    val moderated = league?.takeIf { it.canModerate(env.uid) }

    LaunchedEffect(item.id, comments.size) {
        vm.store.pullComments(listOf(item.id) + comments.filter { !isReaction(it.text) }.map { "c:${it.id}" })
    }

    fun send(raw: String) {
        val t = raw.trim()
        if (t.isEmpty()) return
        scope.launch { vm.store.addComment(t, item.id, item.memberID, home.trainerName) }
        if (raw == text) text = ""
    }

    Dialog(onDismiss, DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        BackHandler(onBack = onDismiss)
        Column(Modifier.fillMaxSize().background(GMColors.bg).safeDrawingPadding().imePadding()) {
            Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                // Foto em destaque
                Box(Modifier.fillMaxWidth().height(if (photos.isEmpty()) 300.dp else 460.dp)) {
                    if (photos.isNotEmpty()) {
                        val pager = androidx.compose.foundation.pager.rememberPagerState { photos.size }
                        androidx.compose.foundation.pager.HorizontalPager(pager, Modifier.fillMaxSize()) { i ->
                            val img = remember(photos[i]) { Photos.decode(photos[i], 2000) }
                            Box(Modifier.fillMaxSize().background(GMColors.card)) {
                                if (img != null) androidx.compose.foundation.Image(img, null, Modifier.fillMaxSize(), contentScale = androidx.compose.ui.layout.ContentScale.Fit)
                            }
                        }
                    } else {
                        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf((if (item.isMe) GMColors.accent else Color.White).copy(alpha = 0.25f), GMColors.card))),
                            contentAlignment = Alignment.Center) {
                            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                MonsterSprite(item.avatar, Modifier.size(150.dp))
                                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                    Icon(LeagueFormats.kindIcon(item.kind), null, tint = Color.White.copy(alpha = 0.8f), modifier = Modifier.size(18.dp))
                                    Text(LeagueFormats.kindName(item.kind), color = Color.White.copy(alpha = 0.8f), style = GMType.headline)
                                }
                            }
                        }
                    }
                    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
                        GMIconButton(Icons.AutoMirrored.Filled.ArrowBack, "Voltar", onDismiss)
                        Spacer(Modifier.weight(1f))
                        GMIconButton(Icons.Filled.MoreHoriz, "Opções", { menu = true })
                    }
                    DailyPose.byID(item.proof.pose)?.let { pose ->
                        Text("${pose.emoji} ${pose.name}", color = Color.White, style = GMType.caption.copy(fontWeight = FontWeight.Bold),
                             modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 14.dp).background(Color.Black.copy(alpha = 0.65f), CircleShape)
                                 .padding(horizontal = 12.dp, vertical = 7.dp))
                    }
                }
                Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        if (item.isMe) PersonAvatar(home.trainerName, size = 46.dp, photo = home.profilePhoto)
                        else Box(Modifier.size(46.dp).background(GMColors.raised, CircleShape), contentAlignment = Alignment.Center) { MonsterSprite(item.avatar, Modifier.size(37.dp)) }
                        Column(Modifier.weight(1f)) {
                            Text(if (item.isMe) myName else item.name, color = Color.White, style = GMType.headline)
                            Text(LeagueFormats.whenText(item.date) + (item.place?.let { " · $it" } ?: ""), color = GMColors.dim, style = GMType.subheadline, maxLines = 2)
                        }
                        Icon(if (photos.isEmpty()) LeagueFormats.kindIcon(item.kind) else Icons.Filled.Image, null, tint = Color.White, modifier = Modifier.size(22.dp))
                    }
                    Text(title, color = Color.White, fontSize = 26.sp, fontWeight = FontWeight.ExtraBold)
                    if (note.isNotEmpty()) Text(note, color = Color.White.copy(alpha = 0.85f), style = GMType.body)
                    GMFlow {
                        Chip(Icons.Filled.Timer, ActivityText.duration(item.minutes))
                        Chip(LeagueFormats.kindIcon(item.kind), LeagueFormats.kindName(item.kind))
                        if (item.pending) Chip(Icons.Filled.Schedule, "Em revisão", GMColors.dim)
                        else Chip(Icons.Filled.Bolt, "+" + (item.scoring?.let { LeagueText.format(it, item.score) } ?: "${item.score} XP"), GMColors.accent)
                        item.place?.let { Chip(Icons.Filled.Place, it) }
                    }
                    if (item.pending) Text("Esperando o dono da liga aprovar: até lá, não pontua.", color = GMColors.dim, style = GMType.caption)
                    if (item.capped > 0 && item.scoring != null) Text("O teto da liga cortou ${LeagueText.format(item.scoring!!, item.capped)} deste check-in.",
                                                                      color = GMColors.dim, style = GMType.caption)
                    for (line in item.proof.lines) Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.Verified, null, tint = GMColors.dim, modifier = Modifier.size(13.dp))
                        Text(line, color = GMColors.dim, style = GMType.caption)
                    }
                    if (comments.isNotEmpty()) {
                        GMDivider()
                        if (reactions.isNotEmpty()) Row(Modifier.gmPress { whoReacted = true }, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            Text(summary(reactions), color = Color.White, style = GMType.subheadline)
                            Text("· quem reagiu", color = GMColors.accent, style = GMType.caption.copy(fontWeight = FontWeight.SemiBold))
                        }
                        for (c in comments) {
                            val r = lines("c:${c.id}")
                            Row(Modifier.fillMaxWidth().pointerInput(c.id) { detectTapGestures(onLongPress = { commentMenu = c }) },
                                horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                if (c.isMine) PersonAvatar(home.trainerName, size = 32.dp, photo = home.profilePhoto)
                                else PersonAvatar(c.authorName, size = 32.dp, modifier = Modifier.gmPress { person = RankRow(c.authorID, c.authorName, MonsterForm.EGG, false) })
                                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                        Text(c.authorName.ifEmpty { "Treinador" }, color = Color.White, style = GMType.caption.copy(fontWeight = FontWeight.Bold))
                                        Text(LeagueFormats.ago(c.date), color = GMColors.dim, style = GMType.caption2)
                                    }
                                    Text(c.text, color = Color.White, style = if (isReaction(c.text)) GMType.title3.copy(fontSize = 28.sp) else GMType.subheadline)
                                    if (r.isNotEmpty()) Text(summary(r), color = Color.White, style = GMType.caption,
                                                             modifier = Modifier.background(GMColors.raised, CircleShape).padding(horizontal = 8.dp, vertical = 3.dp))
                                }
                            }
                        }
                    }
                }
            }
            // Comentar e reagir
            Column(Modifier.background(GMColors.bg).padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                if (reacting) {
                    Row(Modifier.fillMaxWidth().background(GMColors.card, CircleShape).padding(vertical = 6.dp)) {
                        for (e in listOf("💪", "🔥", "👏", "😮‍💨", "🏆", "❤️")) {
                            Box(Modifier.weight(1f).gmPress { send(e); reacting = false }, contentAlignment = Alignment.Center) { Text(e, fontSize = 30.sp) }
                        }
                    }
                }
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(Modifier.weight(1f).background(GMColors.card, CircleShape).padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.weight(1f)) {
                            if (text.isEmpty()) Text("Comentar…", color = GMColors.dim, style = GMType.body)
                            BasicTextField(text, { text = it }, textStyle = GMType.body.copy(color = Color.White), cursorBrush = SolidColor(GMColors.accent), maxLines = 4,
                                           modifier = Modifier.fillMaxWidth())
                        }
                        if (text.isNotBlank()) Box(Modifier.size(28.dp).background(GMColors.accent, CircleShape).gmPress { send(text) }.semantics { contentDescription = "Enviar" },
                                                   contentAlignment = Alignment.Center) { Icon(Icons.Filled.ArrowUpward, null, tint = Color.Black, modifier = Modifier.size(16.dp)) }
                    }
                    Box(Modifier.size(50.dp).background(GMColors.card, CircleShape).gmPress { reacting = !reacting }.semantics { contentDescription = "Reagir" },
                        contentAlignment = Alignment.Center) { Icon(if (reacting) Icons.Filled.Close else Icons.Filled.EmojiEmotions, null, tint = Color.White) }
                }
            }
        }
    }

    GMActions(menu, { menu = false }, title, actions = buildList {
        add(GMAction("Compartilhar", Icons.Filled.Share) {
            val send = Intent(Intent.ACTION_SEND).setType("text/plain")
                .putExtra(Intent.EXTRA_TEXT, "$title · ${LeagueFormats.kindName(item.kind)}, ${ActivityText.duration(item.minutes)} no GymBros 💪")
            context.startActivity(Intent.createChooser(send, null))
        })
        if (mine != null) add(GMAction("Apagar check-in", Icons.Filled.Delete, destructive = true) { confirmDelete = true })
        else if (!item.isMe && moderated != null) add(GMAction("Remover check-in da liga", Icons.Filled.Cancel, destructive = true) { removing = true })
    })
    GMActions(confirmDelete, { confirmDelete = false }, "Apagar check-in?", "Sai desta liga. A atividade continua no seu histórico.",
              listOf(GMAction("Apagar check-in", Icons.Filled.Delete, destructive = true) {
                  scope.launch { comments.filter { it.isMine }.forEach { vm.store.removeComment(it.id) }; vm.store.deleteCheckIn(item.id) }
                  onDismiss()
              }))
    GMActions(removing, { removing = false }, "Remover este check-in?", "Ele sai da liga e não pontua. ${item.name} fica sabendo que o check-in foi removido.",
              listOf(GMAction("Remover check-in", Icons.Filled.Cancel, destructive = true) {
                  moderated?.let { l -> scope.launch { vm.store.review(l.uuid, item.id, false) } }
                  onDismiss()
              }))
    commentMenu?.let { c ->
        GMActions(true, { commentMenu = null }, "Comentário", actions = listOf("👍", "❤️‍🔥", "💪", "😂").map { e ->
            GMAction("Reagir $e", Icons.Filled.EmojiEmotions) { scope.launch { vm.store.addComment(e, "c:${c.id}", c.authorID, home.trainerName) } }
        } + if (c.isMine) listOf(GMAction("Apagar comentário", Icons.Filled.Delete, destructive = true) {
            scope.launch { lines("c:${c.id}").filter { it.isMine }.forEach { vm.store.removeComment(it.id) }; vm.store.removeComment(c.id) }
        }) else emptyList())
    }
    if (whoReacted) GMSheet({ whoReacted = false }) {
        Text("Quem reagiu", color = Color.White, style = GMType.headline)
        for ((emoji, list) in reactions.groupBy { it.text }.entries.sortedByDescending { it.value.size }) {
            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("$emoji ${list.size}", color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.Bold))
                Text(list.joinToString(", ") { if (it.isMine) "Você" else it.authorName }, color = GMColors.dim, style = GMType.subheadline)
            }
        }
    }
    person?.let { MemberProfile(env, home, it) { person = null } }
}

private data class CommentLine(val id: String, val text: String, val date: Instant, val isMine: Boolean, val authorID: String, val authorName: String)

private fun summary(list: List<CommentLine>): String =
    list.groupingBy { it.text }.eachCount().entries.sortedByDescending { it.value }.joinToString(" · ") { if (it.value > 1) "${it.key} ${it.value}" else it.key }

@Composable
private fun Chip(icon: androidx.compose.ui.graphics.vector.ImageVector, text: String, tint: Color = Color.White) {
    Row(Modifier.background(GMColors.raised, CircleShape).padding(horizontal = 14.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Icon(icon, null, tint = tint, modifier = Modifier.size(16.dp))
        Text(text, color = tint, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
    }
}

/** Perfil público de alguém da liga (FriendProfileView), com o mesmo ViewModel de amigos do app */
@Composable
fun MemberProfile(env: AppEnv, home: HomeData, r: RankRow, onDismiss: () -> Unit) {
    val friends: FriendsViewModel = viewModel(key = "friends-${env.uid}", factory = viewModelFactory {
        initializer { FriendsViewModel(FriendsRepository(), env.copies, com.alonsoalmeida.gymbros.data.ProfilePhotosRepository(env.context)) }
    })
    FriendProfileScreen(RemoteFriend(r.id, r.name, r.avatar.id, ""), home, friends, onDismiss) {}
}

// MARK: Revisão (LeagueReviewViews.swift `LeagueReviewQueue`)

@Composable
fun LeagueReviewQueue(league: League, items: List<FeedItem>, env: AppEnv, home: HomeData, vm: LeaguesViewModel, onDismiss: () -> Unit) {
    var decided by remember { mutableStateOf(setOf<String>()) }
    var denying by remember { mutableStateOf<FeedItem?>(null) }
    var opened by remember { mutableStateOf<FeedItem?>(null) }
    val pending = items.filter { it.id !in decided }.sortedBy { it.date }
    fun decide(i: FeedItem, ok: Boolean) { decided = decided + i.id; vm.launch { review(league.uuid, i.id, ok) } }
    GMModal(true, if (pending.size == 1) "1 check-in para revisar" else "${pending.size} check-ins para revisar", onDismiss) {
        if (pending.isEmpty()) GMEmptyState(Icons.Filled.Verified, "Tudo revisado", "Nenhum check-in esperando.")
        for (item in pending) GMCard {
            Row(Modifier.fillMaxWidth().gmPress { opened = item }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                MonsterSprite(item.avatar, Modifier.size(40.dp))
                Column(Modifier.weight(1f)) {
                    Text(item.title, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold), maxLines = 2)
                    Text("${item.name} · ${ActivityText.duration(item.minutes)} · ${LeagueFormats.weekdayDayTime(item.date)}", color = GMColors.dim, style = GMType.caption)
                }
            }
            for (line in item.proof.lines + if (item.hasPhoto) emptyList() else listOf("Sem foto")) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.Verified, null, tint = GMColors.dim, modifier = Modifier.size(13.dp))
                    Text(line, color = GMColors.dim, style = GMType.caption)
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                GMButton("Negar", { denying = item }, Modifier.weight(1f), icon = Icons.Filled.Close, kind = GMButtonKind.SECONDARY, small = true)
                GMButton("Aprovar", { decide(item, true) }, Modifier.weight(1f), icon = Icons.Filled.Check, small = true)
            }
        }
        if (pending.isNotEmpty()) Text("Aprovado, o check-in pontua. Negado, ele sai da liga e quem postou fica sabendo." +
                                       if (league.settings.posesEnabled) " Sem a pose do dia na foto, negue." else "", color = GMColors.dim, style = GMType.footnote)
    }
    denying?.let { d ->
        GMActions(true, { denying = null }, "Negar este check-in?", "Ele sai da liga e não pontua.",
                  listOf(GMAction("Negar check-in", Icons.Filled.Cancel, destructive = true) { decide(d, false) }))
    }
    opened?.let { CheckInDetailScreen(it, env, home, vm) { opened = null } }
}

// MARK: Treino do dia (LeagueModerationViews.swift `DailyWorkoutEditor`)

@Composable
fun DailyWorkoutEditor(league: League, env: AppEnv, vm: LeaguesViewModel, now: Instant, onDismiss: () -> Unit) {
    val copyState by env.copies.state.collectAsStateWithLifecycle()
    val routines = remember(copyState) {
        ((copyState as? com.alonsoalmeida.gymbros.data.CopyState.Ready)?.copy?.let { runCatching { AccountCopy.decode(it).routines }.getOrNull() }).orEmpty().sortedBy { it.order }
    }
    val today = league.settings.dailyWorkout?.takeIf { it.isToday(now) }
    var title by remember { mutableStateOf(today?.title.orEmpty()) }
    var note by remember { mutableStateOf(today?.note.orEmpty()) }
    var from by remember { mutableStateOf<String?>(null) }
    GMModal(true, "Treino do dia", onDismiss, confirm = "Postar", confirmEnabled = title.isNotBlank(), onConfirm = {
        val items = routines.firstOrNull { it.uuid == from }?.items?.sortedBy { it.order }?.map { DailyWorkout.Item(it.exerciseID, it.sets, it.reps) }
            ?: today?.items.orEmpty()
        vm.launch { moderate(league) { it.copy(dailyWorkout = DailyWorkout(Instant.now(), title.trim(), items, note)) } }
        onDismiss()
    }) {
        GMSection("Título") { GMTextField(title, { title = it }, "Ex.: Perna pesada") }
        GMSection("Exercícios", footer = "Copia os exercícios de uma rotina sua; quem abrir a liga hoje começa o treino com um toque.") {
            GMRow("Sem exercícios (só o texto)", onClick = { from = null }) { SelectDot(from == null) }
            for (r in routines) {
                GMDivider()
                GMRow(r.name, subtitle = "${r.items.size} exercícios", onClick = { from = r.uuid; if (title.isEmpty()) title = r.name }) { SelectDot(from == r.uuid) }
            }
        }
        GMSection("Texto", footer = "WOD do coach, aquecimento, observações.") { GMTextField(note, { note = it }, "Opcional") }
        if (today != null) GMButton("Tirar o treino de hoje", {
            vm.launch { moderate(league) { it.copy(dailyWorkout = null) } }
            onDismiss()
        }, icon = Icons.Filled.Delete, kind = GMButtonKind.DANGER)
    }
}
