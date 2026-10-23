package com.alonsoalmeida.gymbros.ui.friends

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
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
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Chat
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.NotificationsOff
import androidx.compose.material.icons.filled.PersonRemove
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.alonsoalmeida.gymbros.data.RemoteFriend
import com.alonsoalmeida.gymbros.data.social.SocialCopy
import com.alonsoalmeida.gymbros.domain.Game
import com.alonsoalmeida.gymbros.domain.home.HomeData
import com.alonsoalmeida.gymbros.domain.social.DirectKind
import com.alonsoalmeida.gymbros.domain.social.FeedPost
import com.alonsoalmeida.gymbros.domain.social.Moderation
import com.alonsoalmeida.gymbros.domain.social.ReportedKind
import com.alonsoalmeida.gymbros.ui.AppEnv
import com.alonsoalmeida.gymbros.ui.components.GMAction
import com.alonsoalmeida.gymbros.ui.components.GMActions
import com.alonsoalmeida.gymbros.ui.components.GMButton
import com.alonsoalmeida.gymbros.ui.components.GMButtonKind
import com.alonsoalmeida.gymbros.ui.components.GMCard
import com.alonsoalmeida.gymbros.ui.components.GMDivider
import com.alonsoalmeida.gymbros.ui.components.GMEmptyState
import com.alonsoalmeida.gymbros.ui.components.GMIconButton
import com.alonsoalmeida.gymbros.ui.components.GMSection
import com.alonsoalmeida.gymbros.ui.components.PersonAvatar
import com.alonsoalmeida.gymbros.ui.copy
import com.alonsoalmeida.gymbros.ui.inbox.ConversationModal
import com.alonsoalmeida.gymbros.ui.moderation.ModerationRequest
import com.alonsoalmeida.gymbros.ui.moderation.ModerationSheets
import com.alonsoalmeida.gymbros.ui.moderation.ModerationTarget
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMType

/**
 * Perfil do amigo (PublicProfile.swift `FriendProfileView`): cabeçalho, mensagem e força (só entre amigos), X1, bro,
 * números e conquistas, ligas em comum e os posts em calendário. Menu: esconder meus treinos, silenciar, desfazer
 * amizade, denunciar perfil e bloquear.
 */
@Composable
fun FriendProfileScreen(friend: RemoteFriend, home: HomeData, vm: FriendsViewModel, onDismiss: () -> Unit, onSoon: (String) -> Unit,
                        env: AppEnv? = null) {
    val profiles by vm.profiles.collectAsStateValue()
    val state by vm.state.collectAsStateValue()
    val photos by vm.photos.collectAsStateValue()
    var menu by remember { mutableStateOf(false) }
    var confirmRemove by remember { mutableStateOf(false) }
    var moderation by remember { mutableStateOf<ModerationRequest?>(null) }
    var chatting by remember { mutableStateOf(false) }
    var dueling by remember { mutableStateOf(false) }
    var cheered by remember { mutableStateOf(false) }
    var opened by remember { mutableStateOf<FeedPost?>(null) }
    LaunchedEffect(friend.id) { vm.loadProfile(friend.id) }
    val p = profiles[friend.id]
    val isFriend = state.friends.any { it.id == friend.id }
    val name = friend.name.ifEmpty { p?.name.orEmpty() }

    val social = env?.let { SocialViewModel.of(it) }
    val data = env?.let { SocialCopy.read(it.copy()) }
    val extras = social?.profile?.collectAsStateValue()?.value?.get(friend.id)
    LaunchedEffect(friend.id, data?.leagues?.size) { if (social != null && data != null) social.loadProfile(friend.id, data) }
    val mod = data?.moderation ?: Moderation()
    val prefs = data?.prefs(friend.id)

    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Column(Modifier.fillMaxSize().background(GMColors.bg).safeDrawingPadding()) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp)) {
                GMIconButton(Icons.AutoMirrored.Filled.ArrowBack, "Voltar", onDismiss)
                Spacer(Modifier.weight(1f))
                GMIconButton(Icons.Filled.MoreHoriz, "Mais opções", { menu = true })
            }
            Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 40.dp),
                   verticalArrangement = Arrangement.spacedBy(18.dp)) {
                Column(Modifier.fillMaxWidth().padding(top = 8.dp), horizontalAlignment = Alignment.CenterHorizontally,
                       verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    PersonAvatar(name, size = 110.dp, photo = photos[friend.id])
                    Text(name, color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Black)
                    if (!p?.username.isNullOrEmpty()) Text("@${p!!.username}", color = GMColors.dim, style = GMType.subheadline)
                    if (!p?.bio.isNullOrEmpty()) Text(p!!.bio, color = Color.White, style = GMType.subheadline, textAlign = TextAlign.Center)
                }
                // Conversa e força direto do perfil (só entre amigos)
                if (isFriend && social != null && data != null) {
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        GMButton("Mensagem", { chatting = true }, Modifier.weight(1f), icon = Icons.AutoMirrored.Filled.Chat, kind = GMButtonKind.SECONDARY)
                        GMButton(if (cheered) "Força enviada" else "Mandar força", {
                            social.send(DirectKind.CHEER, friend.id, data, state.friends) { cheered = true }
                        }, Modifier.weight(1f), icon = if (cheered) Icons.Filled.Check else Icons.Filled.Bolt, enabled = !cheered)
                    }
                }
                if (prefs != null && (prefs.hideMine || prefs.muted)) {
                    Text(listOfNotNull(
                        if (prefs.hideMine) "Seus treinos estão escondidos de $name (nas ligas em comum continuam aparecendo)." else null,
                        if (prefs.muted) "Notificações de $name silenciadas." else null,
                    ).joinToString(" "), color = GMColors.dim, style = GMType.caption, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
                }
                GMButton("Desafiar para um X1", { if (env != null) dueling = true else onSoon("X1") }, icon = Icons.Filled.Shield, kind = GMButtonKind.SECONDARY)
                if (mod.isHidden(ReportedKind.PROFILE, friend.id)) {
                    GMEmptyState(Icons.Filled.Flag, "Perfil denunciado", "Você não vê mais o conteúdo deste perfil. ${Moderation.REVIEW_NOTE}")
                } else if (p == null) {
                    Box(Modifier.fillMaxWidth().padding(top = 40.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = GMColors.accent) }
                } else {
                    if (p.extra.bro != null || p.extra.stats != null || !p.extra.achievements.isNullOrEmpty()) GMCard { PublicProfileCard(p) }
                    if (data != null) {
                        val common = data.leagues.filter { !it.isPastSeason && it.code in extras?.commonLeagues.orEmpty() }
                        if (common.isNotEmpty()) {
                            GMSection("Ligas em comum") {
                                common.forEachIndexed { i, l ->
                                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                        Box(Modifier.size(38.dp).background(GMColors.raised, CircleShape), contentAlignment = Alignment.Center) {
                                            Text(l.emoji, style = GMType.title3)
                                        }
                                        Text(l.name, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
                                    }
                                    if (i < common.lastIndex) GMDivider()
                                }
                            }
                        }
                        val avatar = p.extra.bro?.form ?: friend.form
                        val posts = mod.visiblePosts(extras?.posts.orEmpty().map { r ->
                            FeedPost(r.id, friend.id, name, avatar, false, r.date, r.title, r.note, r.kind, r.minutes, Game.xp(r.kind, r.minutes, r.effort),
                                     r.hasPhoto, r.effort, r.place)
                        })
                        if (extras == null) {
                            Box(Modifier.fillMaxWidth().padding(top = 20.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = GMColors.accent) }
                        } else {
                            GMSection("Posts · ${posts.size}", footer = if (posts.isEmpty()) "$name ainda não postou nada no perfil." else null) {
                                PostsCalendar(posts) { opened = it }
                            }
                        }
                    }
                }
            }
        }

        // Menu: o que você controla por amigo, depois denunciar e bloquear
        val actions = mutableListOf<GMAction>()
        if (isFriend && social != null && prefs != null) {
            actions += if (prefs.hideMine) GMAction("Mostrar meus treinos para $name", Icons.Filled.Visibility) { social.setHideMine(friend.id, false) }
                       else GMAction("Esconder meus treinos de $name", Icons.Filled.VisibilityOff) { social.setHideMine(friend.id, true) }
            actions += if (prefs.muted) GMAction("Reativar notificações de $name", Icons.Filled.Notifications) { social.setMuted(friend.id, false) }
                       else GMAction("Silenciar $name", Icons.Filled.NotificationsOff) { social.setMuted(friend.id, true) }
        }
        if (isFriend) actions += GMAction("Desfazer amizade", Icons.Filled.PersonRemove, destructive = true) { confirmRemove = true }
        val target = ModerationTarget(friend.id, name, if (mod.isHidden(ReportedKind.PROFILE, friend.id)) null else ReportedKind.PROFILE, friend.id)
        if (social != null) actions += target.actions { moderation = it }
        else actions += GMAction("Bloquear $name", Icons.Filled.Shield, destructive = true) { vm.block(friend.id, name, home); onDismiss() }
        GMActions(menu, { menu = false }, title = name, actions = actions)
        GMActions(confirmRemove, { confirmRemove = false }, title = "Desfazer amizade com $name?", message = "Vocês continuam nas mesmas ligas.",
                  actions = listOf(GMAction("Desfazer amizade", Icons.Filled.PersonRemove, destructive = true) { vm.remove(friend.id, home); onDismiss() }))
        if (social != null && env != null) {
            ModerationSheets(moderation, { moderation = it }, social, onBlocked = { vm.refresh(home); onDismiss() })
            ConversationModal(chatting, friend.id, env, home, onDismiss = { chatting = false })
            CheckInDetailModal(opened, env, home, onDismiss = { opened = null })
            com.alonsoalmeida.gymbros.ui.duels.DuelsModal(dueling, env, home, { dueling = false }, opponentID = friend.id)
        }
    }
}
