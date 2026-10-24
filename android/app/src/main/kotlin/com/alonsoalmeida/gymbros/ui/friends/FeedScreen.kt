package com.alonsoalmeida.gymbros.ui.friends

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Chat
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material.icons.outlined.ThumbUp
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.alonsoalmeida.gymbros.data.social.SocialCopy
import com.alonsoalmeida.gymbros.domain.home.HomeData
import com.alonsoalmeida.gymbros.domain.social.DeckCard
import com.alonsoalmeida.gymbros.domain.social.DeckPerson
import com.alonsoalmeida.gymbros.domain.social.FeedPost
import com.alonsoalmeida.gymbros.domain.social.FriendRank
import com.alonsoalmeida.gymbros.domain.social.FriendsMetric
import com.alonsoalmeida.gymbros.domain.social.FriendsRanking
import com.alonsoalmeida.gymbros.domain.social.Reactions
import com.alonsoalmeida.gymbros.domain.social.SocialComment
import com.alonsoalmeida.gymbros.domain.social.SocialText
import com.alonsoalmeida.gymbros.domain.social.UnifiedFeed
import com.alonsoalmeida.gymbros.domain.social.UnifiedPost
import com.alonsoalmeida.gymbros.domain.social.label
import com.alonsoalmeida.gymbros.domain.social.symbol
import com.alonsoalmeida.gymbros.ui.AppEnv
import com.alonsoalmeida.gymbros.ui.components.GMDivider
import com.alonsoalmeida.gymbros.ui.components.GMEmptyState
import com.alonsoalmeida.gymbros.ui.components.GMIconButton
import com.alonsoalmeida.gymbros.ui.components.GMScreen
import com.alonsoalmeida.gymbros.ui.components.MonsterSprite
import com.alonsoalmeida.gymbros.ui.components.PersonAvatar
import com.alonsoalmeida.gymbros.ui.components.Symbols
import com.alonsoalmeida.gymbros.ui.components.gmPress
import com.alonsoalmeida.gymbros.ui.copy
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMRadius
import com.alonsoalmeida.gymbros.ui.theme.GMType
import kotlinx.coroutines.delay

/**
 * Aba Feed (FriendsFeed.swift `UnifiedFeedView`): stories dos bros, ranking da semana e os posts seus e dos amigos (ligas
 * públicas e perfil), cada treino uma vez só, com os lugares. Toque duplo na mídia manda força 💪; toque abre o post.
 * `env` liga o feed de verdade (sem ele, só o botão de amigos e o aviso, como antes).
 */
@Composable
fun FeedScreen(home: HomeData, vm: FriendsViewModel, env: AppEnv? = null, onSoon: (String) -> Unit) {
    var friendsOpen by remember { mutableStateOf(false) }
    val state by vm.state.collectAsStateValue()
    LaunchedEffect(Unit) { vm.refresh(home) }
    GMScreen(
        "Feed",
        bottomInset = 120.dp,
        leading = { PersonAvatar(home.trainerName, photo = home.profilePhoto) },
        trailing = { GMIconButton(Icons.Filled.People, "Amigos", { friendsOpen = true }) },
    ) {
        if (env == null) {
            GMEmptyState(Icons.Filled.Group, if (state.friends.isEmpty()) "Sem amigos ainda" else "Nada por aqui",
                         if (state.friends.isEmpty()) "Adicione amigos no canto de cima para ver os treinos deles aqui."
                         else "Os treinos que você e os seus amigos postarem aparecem aqui.", Modifier.padding(top = 40.dp))
        } else {
            FeedContent(env, home, vm)
        }
    }
    FriendsScreen(friendsOpen, home, vm, onDismiss = { friendsOpen = false }, onSoon = onSoon, env = env)
}

@Composable
private fun FeedContent(env: AppEnv, home: HomeData, friendsVm: FriendsViewModel) {
    val social = SocialViewModel.of(env)
    val copy = env.copy()
    val data = remember(copy) { SocialCopy.read(copy) }
    val friends = friendsVm.state.collectAsStateValue().value.friends
    val remote by social.feed.collectAsStateValue()
    val myAvatar = home.snapshot.form
    val model = remember(data, remote, friends, myAvatar) { social.model(data, remote, friends, myAvatar) }
    var opened by remember { mutableStateOf<FeedPost?>(null) }
    var ranking by remember { mutableStateOf(false) }
    var deck by remember { mutableStateOf<Pair<List<DeckCard>, Int>?>(null) }
    val friendIDs = friends.map { it.id }
    LaunchedEffect(friendIDs, data.leagues.size) { social.refreshFeed(friends, data) }
    val shown = model.shown.take(150)
    // Reações e número de comentários dos posts na tela (os comentários em si só abrem no post)
    LaunchedEffect(shown.take(60).joinToString { it.id }) { social.pullComments(shown.map { it.item }) }
    val visibleComments = data.moderation.visibleComments(data.comments)
    val byItem = remember(visibleComments) { visibleComments.groupBy { it.itemID } }

    BroStories(model.stories) { p -> deck = p.cards to p.start }
    if (friends.isNotEmpty()) FriendsRankCard(model.ranking) { ranking = true }
    if (shown.isEmpty()) {
        GMEmptyState(Icons.Filled.Group, if (friendIDs.isEmpty()) "Sem amigos ainda" else "Nada por aqui",
                     if (friendIDs.isEmpty()) "Adicione amigos no canto de cima para ver os treinos deles aqui."
                     else "Os treinos que você e os seus amigos postarem aparecem aqui.")
    }
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        for (p in shown) androidx.compose.runtime.key(p.id) {
            PostCard(p, byItem[p.id].orEmpty(), if (p.item.isMe) SocialCopy.photo(copy, p.id) else null,
                     onOpen = { opened = p.item }, onStrength = { mine -> social.toggleStrength(p.item, mine) })
        }
    }

    CheckInDetailModal(opened, env, home, onDismiss = { opened = null })
    RankingModal(ranking, env, home, friendsVm, onDismiss = { ranking = false })
    deck?.let { (cards, start) -> BroDeckModal(cards, start, env, friends, onDismiss = { deck = null }) }
}

/** Um post: cabeçalho, mídia (foto sua ou faixa com o treino), título e as ações */
@Composable
private fun PostCard(p: UnifiedPost, comments: List<SocialComment>, photo: ByteArray?, onOpen: () -> Unit, onStrength: (SocialComment?) -> Unit) {
    val f = p.item
    val reactions = comments.filter { it.isReaction }
    val talk = comments.count { !it.isReaction }
    val mine = reactions.firstOrNull { it.isMine && it.text == "💪" }
    var burst by remember { mutableStateOf(false) }
    val haptic = LocalHapticFeedback.current
    LaunchedEffect(burst) { if (burst) { delay(600); burst = false } }
    Column(Modifier.fillMaxWidth().background(GMColors.card, GMRadius.card).padding(14.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        // Cabeçalho: bro, nome, há quanto tempo e onde
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(Modifier.size(40.dp).background(GMColors.raised, CircleShape).padding(5.dp)) { MonsterSprite(f.avatar, Modifier.fillMaxSize()) }
            Column(Modifier.weight(1f)) {
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(if (f.isMe) "Você" else f.name, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.Bold), maxLines = 1)
                    Text("· ${SocialText.shortAgo(f.date)}", color = GMColors.dim, style = GMType.caption)
                }
                Text(UnifiedFeed.placesText(p.places), color = GMColors.dim, style = GMType.caption, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        Box(Modifier.pointerInput(f.id, mine) {
            detectTapGestures(onDoubleTap = {
                if (mine == null) { onStrength(null); haptic.performHapticFeedback(HapticFeedbackType.LongPress) }
                burst = true
            }, onTap = { onOpen() })
        }, contentAlignment = Alignment.Center) {
            Media(f, photo)
            BurstEmoji(if (burst) "💪" else null, 90)
        }
        Column(Modifier.fillMaxWidth().gmPress(onClick = onOpen), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(f.title, color = Color.White, style = GMType.headline, maxLines = 2, overflow = TextOverflow.Ellipsis)
            if (f.note.isNotEmpty()) Text(f.note, color = Color.White.copy(alpha = 0.85f), style = GMType.subheadline, maxLines = 3, overflow = TextOverflow.Ellipsis)
        }
        // Ações: força, comentar (com o total) e o resumo das reações
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            Row(Modifier.gmPress { onStrength(mine); haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove) }
                    .semantics { contentDescription = if (mine == null) "Mandar força" else "Tirar força" },
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                val tint = if (mine == null) Color.White else GMColors.accent
                Icon(if (mine == null) Icons.Outlined.ThumbUp else Icons.Filled.ThumbUp, null, tint = tint, modifier = Modifier.size(18.dp))
                Text(if (mine == null) "Força" else "Força!", color = tint, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
            }
            Row(Modifier.gmPress(onClick = onOpen).semantics {
                    contentDescription = if (talk == 0) "Comentar" else "Comentar, $talk comentário${if (talk == 1) "" else "s"}"
                }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(Icons.AutoMirrored.Outlined.Chat, null, tint = Color.White, modifier = Modifier.size(18.dp))
                Text("Comentar", color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
                if (talk > 0) Text("$talk", color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold, fontFeatureSettings = "tnum"),
                                   modifier = Modifier.background(GMColors.raised, CircleShape).padding(horizontal = 7.dp, vertical = 2.dp))
            }
            Spacer(Modifier.weight(1f))
            if (reactions.isNotEmpty()) Text(Reactions.feedSummary(reactions), color = GMColors.dim, maxLines = 1,
                                             style = GMType.caption.copy(fontWeight = FontWeight.SemiBold))
        }
    }
}

/** Foto grande quando tem (só as suas: fotos de check-in não vão para o servidor); sem foto, a faixa com o treino */
@Composable
private fun Media(f: FeedPost, photo: ByteArray?) {
    val image = remember(photo) { photo?.let { runCatching { android.graphics.BitmapFactory.decodeByteArray(it, 0, it.size)?.asImageBitmap() }.getOrNull() } }
    if (image != null) {
        Box(Modifier.fillMaxWidth().aspectRatio(4f / 5f).clip(GMRadius.xl)) {
            Image(image, null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
            Row(Modifier.align(Alignment.BottomStart).padding(10.dp).background(Color.Black.copy(alpha = 0.55f), CircleShape)
                    .padding(horizontal = 10.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Symbols.of(f.kind.symbol), null, tint = Color.White, modifier = Modifier.size(14.dp))
                Text(UnifiedFeed.statsText(f), color = Color.White, style = GMType.caption.copy(fontWeight = FontWeight.SemiBold))
            }
        }
    } else {
        Row(Modifier.fillMaxWidth().background(GMColors.raised, GMRadius.xl).padding(12.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Box(Modifier.size(56.dp).background(GMColors.accent.copy(alpha = 0.15f), GMRadius.m), contentAlignment = Alignment.Center) {
                Icon(Symbols.of(f.kind.symbol), null, tint = GMColors.accent, modifier = Modifier.size(30.dp))
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(f.kind.label, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
                Text(UnifiedFeed.statsText(f), color = GMColors.dim, style = GMType.caption)
            }
            if (f.hasPhoto) Icon(Icons.Filled.CameraAlt, "Tem foto", tint = GMColors.dim, modifier = Modifier.size(14.dp))
        }
    }
}

/** Fileira de stories (SocialExtras.swift `BroStories`): anel verde com novidade; já vista fica apagada mas abre */
@Composable
private fun BroStories(people: List<DeckPerson>, onOpen: (DeckPerson) -> Unit) {
    if (people.isEmpty()) return
    Row(Modifier.horizontalScroll(rememberScrollState()).padding(vertical = 2.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        for (p in people) {
            val fresh = p.unseen > 0
            Column(Modifier.width(70.dp).gmPress { onOpen(p) }.semantics {
                    contentDescription = if (fresh) "${p.latest.name}, ${p.unseen} novo${if (p.unseen == 1) "" else "s"}" else "${p.latest.name}, já visto"
                }, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Box(Modifier.size(66.dp)) {
                    val ring = if (fresh) Modifier.border(3.dp, Brush.sweepGradient(listOf(GMColors.accent, GMColors.accent.copy(alpha = 0.45f), GMColors.accent)), CircleShape)
                               else Modifier.border(1.5.dp, GMColors.track, CircleShape)
                    Box(Modifier.size(66.dp).then(ring).padding(5.dp).background(GMColors.raised, CircleShape).padding(7.dp)) {
                        MonsterSprite(p.latest.avatar, Modifier.fillMaxSize().then(if (fresh) Modifier else Modifier.background(Color.Transparent)),
                                      saturation = if (fresh) 1f else 0.2f)
                    }
                    if (p.unseen > 1) {
                        Text("${p.unseen}", color = Color.Black, fontSize = 11.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center,
                             modifier = Modifier.align(Alignment.BottomEnd).border(2.dp, GMColors.bg, CircleShape).background(GMColors.accent, CircleShape)
                                 .padding(horizontal = 6.dp, vertical = 2.dp))
                    }
                }
                Text(p.latest.name, color = if (fresh) Color.White else GMColors.dim, maxLines = 1, overflow = TextOverflow.Ellipsis,
                     style = GMType.caption2.copy(fontWeight = if (fresh) FontWeight.SemiBold else FontWeight.Normal))
            }
        }
    }
}

/** Ranking dos bros da semana (FriendsFeed.swift `FriendsRankCard`): os 3 primeiros e a sua posição se ficou de fora */
@Composable
private fun FriendsRankCard(rows: List<FriendRank>, onOpen: () -> Unit) {
    val me = rows.indexOfFirst { it.isMe }
    Column(Modifier.fillMaxWidth().gmPress(onClick = onOpen).background(GMColors.card, GMRadius.card).padding(14.dp),
           verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Icon(Icons.Filled.EmojiEvents, null, tint = Color.White, modifier = Modifier.size(16.dp))
            Text("Ranking dos bros · semana", color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.Bold), modifier = Modifier.weight(1f))
            Text("Ver tudo", color = GMColors.accent, style = GMType.caption.copy(fontWeight = FontWeight.SemiBold))
            Icon(Icons.Filled.ChevronRight, null, tint = GMColors.dim, modifier = Modifier.size(14.dp))
        }
        rows.take(3).forEachIndexed { i, r -> RankLine(i, r) }
        if (me >= 3) { GMDivider(); RankLine(me, rows[me]) }
    }
}

@Composable
private fun RankLine(i: Int, r: FriendRank) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(FriendsRanking.medal(i), color = Color.White, textAlign = TextAlign.Center, modifier = Modifier.width(28.dp),
             style = if (i < 3) GMType.body else GMType.subheadline.copy(fontWeight = FontWeight.Bold))
        MonsterSprite(r.avatar, Modifier.size(28.dp))
        Text(if (r.isMe) "Você" else r.name, color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
             style = GMType.subheadline.copy(fontWeight = if (r.isMe) FontWeight.Bold else FontWeight.SemiBold))
        Text(FriendsMetric.CHECK_INS.format(r.value), color = if (r.isMe) GMColors.accent else GMColors.dim,
             style = GMType.subheadline.copy(fontFeatureSettings = "tnum"))
    }
}
