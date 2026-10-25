package com.alonsoalmeida.gymbros.ui.friends

import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.PersonRemove
import androidx.compose.material.icons.filled.Block
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.QrCode
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.VerifiedUser
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.alonsoalmeida.gymbros.data.PublicProfile
import com.alonsoalmeida.gymbros.domain.Attribute
import com.alonsoalmeida.gymbros.data.RemoteFriend
import com.alonsoalmeida.gymbros.domain.MonsterForm
import com.alonsoalmeida.gymbros.domain.Stage
import com.alonsoalmeida.gymbros.domain.home.HomeData
import com.alonsoalmeida.gymbros.domain.profile.PublicBros
import com.alonsoalmeida.gymbros.domain.social.label
import com.alonsoalmeida.gymbros.domain.social.symbol
import com.alonsoalmeida.gymbros.ui.auth.GMTextField
import com.alonsoalmeida.gymbros.ui.auth.LegalModal
import com.alonsoalmeida.gymbros.ui.components.GMButton
import com.alonsoalmeida.gymbros.ui.components.GMButtonKind
import com.alonsoalmeida.gymbros.ui.components.GMCard
import com.alonsoalmeida.gymbros.ui.components.GMEmptyState
import com.alonsoalmeida.gymbros.ui.components.GMIconButton
import com.alonsoalmeida.gymbros.ui.components.GMModal
import com.alonsoalmeida.gymbros.ui.components.GMProgressBar
import com.alonsoalmeida.gymbros.ui.components.GMRow
import com.alonsoalmeida.gymbros.ui.components.GMSection
import com.alonsoalmeida.gymbros.ui.components.GMSheet
import com.alonsoalmeida.gymbros.ui.components.LivingMonster
import com.alonsoalmeida.gymbros.ui.components.MonsterSprite
import com.alonsoalmeida.gymbros.ui.components.PersonAvatar
import com.alonsoalmeida.gymbros.ui.components.Symbols
import com.alonsoalmeida.gymbros.ui.components.gmPress
import com.alonsoalmeida.gymbros.ui.legal.Legal
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMRadius
import com.alonsoalmeida.gymbros.ui.theme.GMType
import com.alonsoalmeida.gymbros.ui.theme.color

/** Link do QR e do convite (FriendQR.link do iOS) */
fun friendLink(code: String) = "gymbros://amigo/$code"

/** Ligas, amigos e perfil público pedem termos aceitos e permissão (App/SocialGate.swift) */
@Composable
fun SocialGate(home: HomeData, vm: FriendsViewModel, roles: Set<String>?, content: @Composable () -> Unit) {
    when {
        home.termsVersion < FriendsViewModel.TERMS_VERSION -> TermsPrompt { vm.acceptTerms(home) }
        roles == null -> Box(Modifier.fillMaxWidth().padding(vertical = 40.dp), contentAlignment = Alignment.Center) {
            CircularProgressIndicator(color = GMColors.accent)
        }
        roles.isEmpty() -> GMCard { GMEmptyState(Icons.Filled.Lock, "Sem acesso", "Sua conta não tem permissão para ver isto.") }
        else -> content()
    }
}

/** TermsView.swift `TermsPrompt` */
@Composable
fun TermsPrompt(onAccept: () -> Unit) {
    var reading by remember { mutableStateOf(false) }
    GMCard {
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Icon(Icons.Filled.VerifiedUser, null, tint = GMColors.accent, modifier = Modifier.size(40.dp))
            Text("Aceite os termos para continuar", color = Color.White, style = GMType.headline)
            Text("Ligas, amigos e o perfil público seguem regras de convivência, com tolerância zero para conteúdo ofensivo e abuso.",
                 color = GMColors.dim, style = GMType.subheadline, textAlign = TextAlign.Center)
            GMButton("Ler e aceitar os termos", { reading = true })
        }
    }
    LegalModal(reading, "Termos de uso", Legal.terms, "Atualizados", onDismiss = { reading = false }, confirm = "Aceitar",
               onConfirm = { onAccept(); reading = false })
}

/** Pessoa numa lista: bro, nome e uma linha (Friends.swift `person`) */
@Composable
fun PersonRow(name: String, form: MonsterForm, subtitle: String, modifier: Modifier = Modifier, photo: ByteArray? = null) {
    Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        // Foto da pessoa (ou a inicial) com o bro dela no cantinho
        Box {
            PersonAvatar(name, size = 42.dp, photo = photo)
            com.alonsoalmeida.gymbros.ui.components.BroAvatars(listOf(form), Modifier.align(Alignment.BottomEnd).offset(6.dp, 6.dp), size = 20.dp)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(name, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
            Text(subtitle, color = GMColors.dim, style = GMType.caption, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

@Composable
private fun Divider() = Box(Modifier.fillMaxWidth().height(1.dp).background(GMColors.stroke))

/** Amigos (Friends.swift `FriendsView`) */
@Composable
fun FriendsScreen(visible: Boolean, home: HomeData, vm: FriendsViewModel, onDismiss: () -> Unit, onSoon: (String) -> Unit,
                  env: com.alonsoalmeida.gymbros.ui.AppEnv? = null) {
    var qr by remember { mutableStateOf(false) }
    var duels by remember { mutableStateOf(false) }
    val state by vm.state.collectAsStateValue()
    val roles by vm.roles.collectAsStateValue()
    val suggestions by vm.suggestions.collectAsStateValue()
    val message by vm.message.collectAsStateValue()
    val photos by vm.photos.collectAsStateValue()
    var code by remember { mutableStateOf("") }
    var opened by remember { mutableStateOf<RemoteFriend?>(null) }
    val context = LocalContext.current
    LaunchedEffect(visible) { if (visible) { vm.clearMessage(); vm.refresh(home) } }
    // Fotos: escuta só com a tela aberta e o app na frente
    if (visible) {
        val owner = androidx.lifecycle.compose.LocalLifecycleOwner.current
        androidx.compose.runtime.DisposableEffect(owner) {
            val obs = androidx.lifecycle.LifecycleEventObserver { _, e ->
                if (e == androidx.lifecycle.Lifecycle.Event.ON_START) vm.startWatching()
                if (e == androidx.lifecycle.Lifecycle.Event.ON_STOP) vm.stopWatching()
            }
            owner.lifecycle.addObserver(obs)
            onDispose { owner.lifecycle.removeObserver(obs); vm.stopWatching() }
        }
    }
    // Deu certo (amizade ou pedido enviado): limpa o campo, como no iOS
    LaunchedEffect(message) { if (message?.endsWith("🎉") == true || message?.startsWith("Pedido de amizade enviado") == true) code = "" }

    GMModal(visible, "Amigos", onDismiss) {
        SocialGate(home, vm, roles) {
            Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
                // Seu código
                GMCard {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                        PersonAvatar(home.trainerName, size = 48.dp, photo = home.profilePhoto)
                        Column(Modifier.weight(1f)) {
                            Text("Seu código", color = GMColors.dim, style = GMType.caption)
                            Text(home.friendCode ?: "······", color = Color.White, fontSize = 26.sp, fontWeight = FontWeight.Black,
                                 fontFamily = FontFamily.Monospace, maxLines = 1)
                        }
                        val c = home.friendCode
                        if (c != null) {
                            GMIconButton(Icons.Filled.QrCode, "QR do código", { qr = true })
                            GMIconButton(Icons.Filled.Share, "Compartilhar código", {
                                val send = Intent(Intent.ACTION_SEND).setType("text/plain")
                                    .putExtra(Intent.EXTRA_TEXT, "Me adiciona no GymBros! Meu código de amigo: $c (${friendLink(c)})")
                                context.startActivity(Intent.createChooser(send, null))
                            })
                        }
                    }
                }
                GMSection {
                    Row(Modifier.fillMaxWidth().gmPress { if (env != null) duels = true else onSoon("X1") }, verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Box(Modifier.size(32.dp).background(GMColors.trophy.copy(alpha = 0.18f), GMRadius.s), contentAlignment = Alignment.Center) {
                            Icon(Icons.Filled.Shield, null, tint = GMColors.trophy, modifier = Modifier.size(18.dp))
                        }
                        Text("X1", color = Color.White, style = GMType.body, modifier = Modifier.weight(1f))
                        Text("Desafie um amigo", color = GMColors.dim, style = GMType.subheadline)
                        Icon(Icons.Filled.ChevronRight, null, tint = GMColors.dim, modifier = Modifier.size(18.dp))
                    }
                }
                GMSection("Adicionar amigo", footer = message ?: "Peça o código para a pessoa (fica na tela de amigos dela).") {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Box(Modifier.weight(1f)) {
                            GMTextField(code, { code = it.uppercase().take(12) }, "Código do amigo",
                                        keyboard = KeyboardOptions(capitalization = KeyboardCapitalization.Characters, autoCorrectEnabled = false))
                        }
                        GMButton("Adicionar", { vm.addByCode(code, home) }, enabled = code.trim().length >= 6, full = false, small = true)
                    }
                }
                if (state.incoming.isNotEmpty()) {
                    GMSection("Pedidos de amizade") {
                        state.incoming.forEachIndexed { i, f ->
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                PersonRow(f.name, f.form, "Quer ser seu amigo", Modifier.weight(1f), photos[f.id])
                                GMIconButton(Icons.Filled.Close, "Recusar", { vm.decline(f.id, home) }, size = 36.dp)
                                GMIconButton(Icons.Filled.Check, "Aceitar", { vm.accept(f.id, home) }, size = 36.dp)
                            }
                            if (i < state.incoming.lastIndex) Divider()
                        }
                    }
                }
                GMSection("Seus amigos · ${state.friends.size}") {
                    if (state.friends.isEmpty()) Text("Nenhum amigo ainda. Mande seu código pra galera.", color = GMColors.dim, style = GMType.subheadline)
                    state.friends.forEachIndexed { i, f ->
                        Row(Modifier.fillMaxWidth().gmPress { opened = f }, verticalAlignment = Alignment.CenterVertically) {
                            PersonRow(f.name, f.form, f.form.name, Modifier.weight(1f), photos[f.id])
                            Icon(Icons.Filled.ChevronRight, null, tint = GMColors.dim, modifier = Modifier.size(18.dp))
                        }
                        if (i < state.friends.lastIndex) Divider()
                    }
                }
                GMSection("Talvez você conheça", footer = if (suggestions.isEmpty()) null else "Pessoas das suas ligas que ainda não são suas amigas.") {
                    if (suggestions.isEmpty()) {
                        Text(if (home.leagues.isEmpty()) "Entre numa liga para ver aqui quem treina com você." else "Você já é amigo de todo mundo das suas ligas 🙌",
                             color = GMColors.dim, style = GMType.subheadline)
                    }
                    suggestions.forEachIndexed { i, s ->
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            val sub = if (s.leagues.size == 1) "${s.leagues[0].first} ${s.leagues[0].second}" else "${s.leagues.size} ligas em comum"
                            PersonRow(s.member.name, s.member.form, sub, Modifier.weight(1f), photos[s.member.id])
                            GMButton("Adicionar", { vm.addById(s.member.id, home) }, kind = GMButtonKind.SECONDARY, full = false, small = true)
                        }
                        if (i < suggestions.lastIndex) Divider()
                    }
                }
            }
        }
    }
    opened?.let { f -> FriendProfileScreen(f, home, vm, onDismiss = { opened = null }, onSoon = onSoon, env = env) }
    home.friendCode?.let { c -> FriendQRModal(qr, c, onDismiss = { qr = false }) { vm.addByCode(it, home) } }
    if (env != null) com.alonsoalmeida.gymbros.ui.duels.DuelsModal(duels, env, home, { duels = false })
}

/** Bro, números, bros e atributos e conquistas (PublicProfile.swift `PublicProfileCard`, sem o cabeçalho) */
@Composable
fun PublicProfileCard(p: PublicProfile) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        p.extra.bro?.let { b ->
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                LivingMonster(b.form, Modifier.size(60.dp), progress = b.progress)
                Column {
                    Text(b.name, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.Bold))
                    Text(if (b.form.stage == Stage.EGG) "Ovo" else "${b.form.speciesInfo.name} · ${b.form.stage.label} · Nível ${b.level}",
                         color = GMColors.dim, style = GMType.caption)
                }
            }
        }
        p.extra.stats?.let { s ->
            if (p.extra.bro != null) Divider()
            Row(Modifier.fillMaxWidth()) {
                for ((v, l) in listOf(s.checkIns to "Check-ins", s.activeDays to "Dias ativos", s.leagues to "Ligas")) {
                    Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("$v", color = Color.White, style = GMType.headline.copy(fontFeatureSettings = "tnum"))
                        Text(l, color = GMColors.dim, style = GMType.caption)
                    }
                }
            }
        }
        p.extra.bros?.let { b ->
            if (p.extra.bro != null || p.extra.stats != null) Divider()
            PublicBrosSection(b)
        }
        val a = p.extra.achievements.orEmpty()
        if (a.isNotEmpty()) {
            if (p.extra.bro != null || p.extra.stats != null || p.extra.bros != null) Divider()
            Text("Conquistas · ${a.size}", color = GMColors.dim, style = GMType.caption.copy(fontWeight = FontWeight.Bold))
            for (row in a.take(6).chunked(2)) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    for (b in row) {
                        Row(Modifier.background(GMColors.trophy.copy(alpha = 0.15f), CircleShape).padding(horizontal = 10.dp, vertical = 6.dp),
                            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                            Icon(Icons.Filled.EmojiEvents, null, tint = GMColors.trophy, modifier = Modifier.size(13.dp))
                            Text(b.title, color = GMColors.trophy, style = GMType.caption.copy(fontWeight = FontWeight.SemiBold))
                        }
                    }
                }
            }
        }
    }
}

/**
 * Bros e atributos no perfil público (PublicProfile.swift `PublicBrosSection`): o bro de maior nível, a atividade
 * favorita, o BroBook e os atributos gerais, com o de mais afinidade em destaque
 */
@Composable
fun PublicBrosSection(b: PublicBros) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Bros e atributos", color = GMColors.dim, style = GMType.caption.copy(fontWeight = FontWeight.Bold))
        b.top?.let { t ->
            GMRow(t.name, subtitle = "Bro de maior nível", modifier = Modifier.semantics(mergeDescendants = true) {}, leading = {
                Box(Modifier.size(34.dp).background(GMColors.raised, GMRadius.s), contentAlignment = Alignment.Center) {
                    MonsterSprite(t.form, Modifier.size(30.dp))
                }
            }) {
                Text(if (t.form.stage == Stage.EGG) "Ovo" else "Nível ${t.level}", color = GMColors.dim,
                     style = GMType.caption.copy(fontWeight = FontWeight.SemiBold, fontFeatureSettings = "tnum"))
            }
        }
        b.favorite?.let { f ->
            GMRow(f.activity.label, Symbols.of(f.activity.symbol), GMColors.accent, "Atividade favorita",
                  modifier = Modifier.semantics(mergeDescendants = true) {}) {
                Text("${f.count}×", color = GMColors.dim, style = GMType.caption.copy(fontWeight = FontWeight.SemiBold, fontFeatureSettings = "tnum"))
            }
        }
        val dex = b.dexFound.toDouble() / maxOf(b.dexTotal, 1)
        Column(Modifier.semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            GMRow("BroBook", Icons.AutoMirrored.Filled.MenuBook, GMColors.accent, "${b.dexFound} de ${b.dexTotal} formas") {
                Text("${Math.round(dex * 100)}%", color = GMColors.dim, style = GMType.caption.copy(fontWeight = FontWeight.SemiBold, fontFeatureSettings = "tnum"))
            }
            GMProgressBar(dex, height = 6.dp)
        }
        b.dominant?.let { dominant ->
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text("Mais afinidade com", color = GMColors.dim, style = GMType.caption.copy(fontWeight = FontWeight.SemiBold))
                    Icon(Symbols.of(dominant), null, tint = dominant.color(), modifier = Modifier.size(13.dp))
                    Text(dominant.label, color = dominant.color(), style = GMType.caption.copy(fontWeight = FontWeight.SemiBold))
                }
                for (a in Attribute.entries) BroAttributeRow(a, b.percent(a), a == dominant)
            }
        }
    }
}

@Composable
private fun BroAttributeRow(a: Attribute, percent: Int, highlighted: Boolean) {
    Row(Modifier.semantics(mergeDescendants = true) { contentDescription = "${a.label}, $percent%" },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(Modifier.width(130.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Icon(Symbols.of(a), null, tint = if (highlighted) a.color() else Color.White, modifier = Modifier.size(16.dp))
            Text(a.label, color = if (highlighted) a.color() else Color.White,
                 style = GMType.subheadline.copy(fontWeight = if (highlighted) FontWeight.Bold else FontWeight.SemiBold))
        }
        GMProgressBar(percent / 100.0, Modifier.weight(1f), tint = if (highlighted) a.color() else a.color().copy(alpha = 0.5f), height = 6.dp)
        Text("$percent%", color = if (highlighted) Color.White else GMColors.dim, style = GMType.caption.copy(fontFeatureSettings = "tnum"),
             modifier = Modifier.width(40.dp), textAlign = TextAlign.End)
    }
}

@Composable
internal fun <T> kotlinx.coroutines.flow.StateFlow<T>.collectAsStateValue() = collectAsStateWithLifecycle()
