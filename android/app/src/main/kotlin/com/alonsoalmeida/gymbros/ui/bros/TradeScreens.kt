package com.alonsoalmeida.gymbros.ui.bros

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.CardGiftcard
import androidx.compose.material.icons.filled.CloudOff
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.HourglassEmpty
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.QuestionMark
import androidx.compose.material.icons.automirrored.filled.Redo
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.alonsoalmeida.gymbros.data.RemoteFriend
import com.alonsoalmeida.gymbros.domain.ActivityText
import com.alonsoalmeida.gymbros.domain.MonsterForm
import com.alonsoalmeida.gymbros.domain.Stage
import com.alonsoalmeida.gymbros.domain.bros.MyTradeBro
import com.alonsoalmeida.gymbros.domain.bros.TradeBro
import com.alonsoalmeida.gymbros.domain.bros.TradeOwner
import com.alonsoalmeida.gymbros.domain.bros.TradeProposal
import com.alonsoalmeida.gymbros.domain.bros.TradeRules
import com.alonsoalmeida.gymbros.domain.home.HomeData
import com.alonsoalmeida.gymbros.ui.auth.GMTextField
import com.alonsoalmeida.gymbros.ui.components.GMButton
import com.alonsoalmeida.gymbros.ui.components.GMButtonKind
import com.alonsoalmeida.gymbros.ui.components.GMCard
import com.alonsoalmeida.gymbros.ui.components.GMEmptyState
import com.alonsoalmeida.gymbros.ui.components.GMModal
import com.alonsoalmeida.gymbros.ui.components.GMProgressBar
import com.alonsoalmeida.gymbros.ui.components.GMSection
import com.alonsoalmeida.gymbros.ui.components.GMSheet
import com.alonsoalmeida.gymbros.ui.components.LivingMonster
import com.alonsoalmeida.gymbros.ui.components.MonsterSprite
import com.alonsoalmeida.gymbros.ui.components.gmPress
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMRadius
import com.alonsoalmeida.gymbros.ui.theme.GMType
import com.alonsoalmeida.gymbros.ui.theme.color
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.Duration
import java.time.Instant

/** Tempo que falta (DuelsView.remaining): pelo menos 1 min, arredondado para cima */
private fun remaining(end: Instant, now: Instant): String =
    ActivityText.duration(maxOf(1, ((Duration.between(now, end).seconds + 59) / 60).toInt()))

/** Trocas de bros com amigos (TradeViews.swift `TradeHubView`): as que chegaram, as que você mandou e as que já aconteceram */
@Composable
internal fun TradeHub(visible: Boolean, home: HomeData, vm: BrosViewModel, applied: Set<String>, onDismiss: () -> Unit) {
    if (!visible) return
    val st by vm.state.collectAsStateWithLifecycle()
    var composing by rememberSaveable { mutableStateOf(false) }
    var confirming by remember { mutableStateOf<TradeProposal?>(null) }
    var problem by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val haptic = LocalHapticFeedback.current
    // Atualiza com a tela aberta e o app na frente
    LifecycleResumeEffect(Unit) {
        vm.startPolling()
        onPauseOrDispose { vm.stopPolling() }
    }
    // O relógio da tela (prazos), a cada 30 s
    val now by produceState(Instant.now()) { while (true) { delay(30_000); value = Instant.now() } }

    fun answer(p: TradeProposal, accept: Boolean) {
        busy = true
        scope.launch {
            val err = vm.respond(p, accept)
            busy = false
            if (err == null) haptic.performHapticFeedback(HapticFeedbackType.LongPress) else problem = err
        }
    }

    GMModal(true, "Trocas", onDismiss, confirm = "Nova troca", onConfirm = { composing = true }) {
        Text("Troque bros com amigos, 1 por 1. Ovos não entram.", color = GMColors.dim, style = GMType.subheadline)
        val incoming = TradeRules.incoming(st.all, now)
        val sent = TradeRules.sent(st.all, now)
        val ready = TradeRules.ready(st.all, applied)
        val done = TradeRules.done(st.all, applied)
        st.lastError?.let { GMEmptyState(Icons.Filled.CloudOff, "Trocas indisponíveis", it) }
        if (ready.isNotEmpty()) {
            Label("Chegou para você", ready.size, GMColors.accent)
            for (p in ready) ReadyCard(p) { vm.receive(p) }
        }
        if (incoming.isNotEmpty()) {
            Label("Te ofereceram", incoming.size, GMColors.trophy)
            for (p in incoming) OfferCard(p, now, busy) { accept -> if (accept) confirming = p else answer(p, false) }
        }
        if (sent.isNotEmpty()) {
            GMSection("Esperando resposta") {
                sent.forEachIndexed { i, p ->
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                        TradePair(p.mine, p.theirs, 34)
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text("Aguardando ${p.friend.name}", color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold), maxLines = 1)
                            Text("${p.mine.name} por ${p.theirs.name} · ${remaining(p.expiresAt, now)}", color = GMColors.dim, style = GMType.caption,
                                 maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                        Text("Cancelar", color = GMColors.danger, style = GMType.caption.copy(fontWeight = FontWeight.Bold),
                             modifier = Modifier.heightIn(min = 48.dp).gmPress { vm.cancel(p) }.padding(horizontal = 4.dp, vertical = 15.dp))
                    }
                    if (i < sent.size - 1) BroDivider()
                }
            }
        }
        if (incoming.isEmpty() && sent.isEmpty() && ready.isEmpty() && st.loaded) IdleCard(home) { composing = true }
        if (!st.loaded && st.lastError == null) {
            Box(Modifier.fillMaxWidth().padding(30.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = GMColors.accent) }
        }
        if (done.isNotEmpty()) {
            // Truncamento do iOS: as 20 mais recentes
            val shown = done.take(20)
            GMSection("Trocas feitas") {
                shown.forEachIndexed { i, p ->
                    Row(Modifier.semantics(mergeDescendants = true) {}, horizontalArrangement = Arrangement.spacedBy(10.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        TradePair(p.mine, p.theirs, 30)
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text("${p.mine.name} por ${p.theirs.name}", color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold),
                                 maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text("com ${p.friend.name} · ${(p.answeredAt ?: p.createdAt).dayMonth()}", color = GMColors.dim, style = GMType.caption, maxLines = 1)
                        }
                    }
                    if (i < shown.size - 1) BroDivider()
                }
            }
        }
    }

    if (composing) TradeComposer(home, vm) { composing = false }
    confirming?.let { p ->
        AlertDialog(
            onDismissRequest = { confirming = null }, containerColor = GMColors.card,
            title = { Text("Trocar ${p.mine.name} por ${p.theirs.name}?", color = Color.White, style = GMType.headline) },
            text = {
                Text("${p.mine.name} vai para ${p.friend.name} com o XP dele, e ${p.theirs.name} chega com ${p.theirs.xp.br()} XP. Não dá para desfazer.",
                     color = GMColors.dim, style = GMType.subheadline)
            },
            confirmButton = { TextButton({ confirming = null; answer(p, true) }) { Text("Trocar", color = GMColors.accent) } },
            dismissButton = { TextButton({ confirming = null }) { Text("Cancelar", color = Color.White) } },
        )
    }
    problem?.let { msg ->
        AlertDialog(
            onDismissRequest = { problem = null }, containerColor = GMColors.card,
            title = { Text("Troca", color = Color.White, style = GMType.headline) },
            text = { Text(msg, color = GMColors.dim, style = GMType.subheadline) },
            confirmButton = { TextButton({ problem = null }) { Text("OK", color = GMColors.accent) } },
        )
    }
}

@Composable
private fun Label(text: String, count: Int, tint: Color) {
    Row(Modifier.padding(horizontal = 4.dp), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(7.dp).background(tint, CircleShape))
        Text(text.uppercase(), color = GMColors.dim, style = GMType.caption.copy(fontWeight = FontWeight.Bold, letterSpacing = 0.6.sp))
        if (count > 1) BroBadge("$count", tint)
    }
}

/** O seu bro e o do amigo, com as setas da troca no meio (miniatura das listas) */
@Composable
private fun TradePair(give: TradeBro, get: TradeBro, size: Int) {
    Row(horizontalArrangement = Arrangement.spacedBy(2.dp), verticalAlignment = Alignment.CenterVertically) {
        MonsterSprite(give.form, Modifier.size(size.dp))
        Icon(Icons.Filled.SwapHoriz, null, tint = GMColors.trophy, modifier = Modifier.size((size * 0.4f).dp))
        MonsterSprite(get.form, Modifier.size(size.dp))
    }
}

/** Você dá × você recebe, lado a lado com as setas no meio */
@Composable
private fun Versus(give: TradeBro, get: TradeBro, friend: String, getOwners: List<TradeOwner>) {
    Row(
        Modifier.fillMaxWidth().background(GMColors.raised, GMRadius.l).padding(vertical = 12.dp)
            .semantics(mergeDescendants = true) { contentDescription = "Você dá ${give.name} e recebe ${get.name} de $friend" },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Side("Você dá", give, GMColors.danger, null)
        Box(Modifier.width(56.dp), contentAlignment = Alignment.Center) {
            Box(Modifier.size(42.dp).background(Brush.linearGradient(listOf(GMColors.trophy, GMColors.streak)), CircleShape), contentAlignment = Alignment.Center) {
                Icon(Icons.Filled.SwapHoriz, null, tint = Color.Black, modifier = Modifier.size(20.dp))
            }
        }
        Side("Você recebe", get, GMColors.accent, getOwners.ifEmpty { null })
    }
}

@Composable
private fun RowScope.Side(title: String, b: TradeBro, tint: Color, owners: List<TradeOwner>?) {
    Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(title.uppercase(), color = tint, fontSize = 9.sp, fontWeight = FontWeight.Black, letterSpacing = 0.5.sp)
        LivingMonster(b.form, Modifier.size(64.dp))
        Text(b.name, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.Bold), maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text("${b.form.stage.label} · ${b.xp.br()} XP", color = GMColors.dim, style = GMType.caption2, maxLines = 1)
        if (owners != null) {
            val names = owners.map { it.name }
            Text("XP de " + if (names.size <= 2) names.joinToString(" e ") else "${names.last()} e mais ${names.size - 1}",
                 color = GMColors.trophy, fontSize = 9.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

/** Troca sua que o amigo aceitou: o bro dele só chega quando você toca em Receber */
@Composable
private fun ReadyCard(p: TradeProposal, receive: () -> Unit) {
    GMCard(Modifier.border(1.5.dp, GMColors.accent.copy(alpha = 0.5f), GMRadius.card)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.Verified, null, tint = GMColors.accent, modifier = Modifier.size(18.dp))
            Text("${p.friend.name} aceitou a troca", color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.Bold))
        }
        Versus(p.mine, p.theirs, p.friend.name, p.theirs.history)
        GMButton("Receber ${p.theirs.name}", receive, icon = Icons.Filled.CardGiftcard)
    }
}

/** Proposta que chegou: o que você recebe, o que dá, o prazo e os botões */
@Composable
private fun OfferCard(p: TradeProposal, now: Instant, busy: Boolean, answer: (Boolean) -> Unit) {
    val left = Duration.between(now, p.expiresAt).seconds.toDouble() / TradeProposal.WINDOW.seconds
    Column(
        Modifier.fillMaxWidth().background(GMColors.card, GMRadius.card)
            .background(Brush.verticalGradient(listOf(GMColors.trophy.copy(alpha = 0.14f), Color.Transparent)), GMRadius.card)
            .border(1.5.dp, GMColors.trophy.copy(alpha = 0.45f), GMRadius.card).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            MonsterSprite(p.friend.form, Modifier.size(28.dp))
            Text("${p.friend.name} quer trocar", color = Color.White, style = GMType.headline, maxLines = 1, overflow = TextOverflow.Ellipsis,
                 modifier = Modifier.weight(1f))
            Text(android.text.format.DateUtils.getRelativeTimeSpanString(p.createdAt.toEpochMilli(), now.toEpochMilli(),
                                                                          android.text.format.DateUtils.MINUTE_IN_MILLIS).toString(),
                 color = GMColors.dim, style = GMType.caption2)
        }
        Versus(p.mine, p.theirs, p.friend.name, p.theirs.history)
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            GMProgressBar(left, tint = if (left < 0.25) GMColors.danger else GMColors.trophy, height = 6.dp)
            Text("Você tem ${remaining(p.expiresAt, now)} para responder.", color = GMColors.dim, style = GMType.caption)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            GMButton("Recusar", { answer(false) }, Modifier.weight(1f), kind = GMButtonKind.SECONDARY, enabled = !busy)
            GMButton("Trocar", { answer(true) }, Modifier.weight(1f), icon = Icons.Filled.SwapHoriz, enabled = !busy)
        }
    }
}

/** Sem troca rolando: o seu bro e um "?", como funciona e o botão */
@Composable
private fun IdleCard(home: HomeData, start: () -> Unit) {
    Column(
        Modifier.fillMaxWidth().background(GMColors.card, GMRadius.card)
            .background(Brush.radialGradient(listOf(GMColors.trophy.copy(alpha = 0.12f), Color.Transparent)), GMRadius.card).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                LivingMonster(home.snapshot.form, Modifier.size(68.dp))
                Text("Seu bro", color = Color.White, style = GMType.caption.copy(fontWeight = FontWeight.Bold))
            }
            Icon(Icons.Filled.SwapHoriz, null, tint = GMColors.trophy, modifier = Modifier.size(24.dp))
            Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Box(Modifier.size(68.dp).border(2.dp, GMColors.dim.copy(alpha = 0.4f), CircleShape), contentAlignment = Alignment.Center) {
                    Icon(Icons.Filled.QuestionMark, null, tint = GMColors.dim, modifier = Modifier.size(28.dp))
                }
                Text("Do amigo", color = GMColors.dim, style = GMType.caption.copy(fontWeight = FontWeight.Bold))
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("Nenhuma troca rolando", color = Color.White, style = GMType.title3.copy(fontWeight = FontWeight.Bold))
            Text("Escolha um bro de um amigo, ofereça um seu e espere ele aceitar.", color = GMColors.dim, style = GMType.subheadline)
        }
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Rule(Icons.Filled.People, "Só entre amigos, 1 bro por 1 bro. Ovos não entram.")
            Rule(Icons.Filled.AutoAwesome, "O bro chega com a forma e o XP que tinha. Esse XP fica marcado como de quem o treinou, separado do que ele ganhar com você.")
            Rule(Icons.Filled.HourglassEmpty, "O amigo tem 48 h para responder. O principal e quem está em liga ou X1 não entram.")
        }
        GMButton("Propor troca", start, icon = Icons.Filled.SwapHoriz)
    }
}

@Composable
private fun Rule(icon: ImageVector, text: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.Top) {
        Box(Modifier.size(28.dp).background(GMColors.trophy.copy(alpha = 0.14f), CircleShape), contentAlignment = Alignment.Center) {
            Icon(icon, null, tint = GMColors.trophy, modifier = Modifier.size(14.dp))
        }
        Text(text, color = Color.White.copy(alpha = 0.85f), style = GMType.subheadline)
    }
}

// MARK: Propor troca

/** Numa folha só: amigo → bro dele → seu bro → conferir e mandar */
@Composable
private fun TradeComposer(home: HomeData, vm: BrosViewModel, done: () -> Unit) {
    val st by vm.state.collectAsStateWithLifecycle()
    var friend by remember { mutableStateOf<RemoteFriend?>(null) }
    var theirs by remember { mutableStateOf<TradeBro?>(null) }
    var mine by remember { mutableStateOf<MyTradeBro?>(null) }
    var friendBros by remember { mutableStateOf<List<TradeBro>?>(null) }
    var query by rememberSaveable { mutableStateOf("") }
    var problem by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val haptic = LocalHapticFeedback.current
    LaunchedEffect(Unit) { vm.loadFriends() }
    LaunchedEffect(friend?.id) { friendBros = null; friend?.let { friendBros = vm.bros(it.id) } }
    val step = if (mine != null) 4 else if (theirs != null) 3 else if (friend != null) 2 else 1
    fun pick(f: () -> Unit) { haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove); f() }
    fun back() { if (mine != null) mine = null else if (theirs != null) theirs = null else friend = null; problem = null }

    GMSheet(done) {
        androidx.activity.compose.BackHandler(step > 1) { back() }
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(48.dp), contentAlignment = Alignment.Center) {
                if (step > 1) Icon(Icons.AutoMirrored.Filled.ArrowBack, "Voltar", tint = GMColors.accent,
                                   modifier = Modifier.size(48.dp).gmPress { pick { back() } }.padding(12.dp))
            }
            Text(listOf("Trocar com quem?", "O que você quer?", "O que você dá?", "Conferir troca")[step - 1], color = Color.White,
                 style = GMType.headline, textAlign = TextAlign.Center, modifier = Modifier.weight(1f))
            Text("$step/4", color = GMColors.dim, style = GMType.caption.copy(fontWeight = FontWeight.Bold), modifier = Modifier.width(48.dp),
                 textAlign = TextAlign.End)
        }
        val f = friend
        val t = theirs
        val m = mine
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            when {
                f != null && t != null && m != null -> {
                    Versus(m.bro, t, f.name, t.history)
                    Note(Icons.Filled.AutoAwesome, "${t.name} chega com ${t.xp.br()} XP de quem o treinou antes. Na ficha dele, esse XP fica separado do que ele ganhar com você.")
                    Note(Icons.AutoMirrored.Filled.Redo, "${m.bro.name} vai para ${f.name} com o XP dele.")
                    Note(Icons.Filled.HourglassEmpty, "${f.name} tem 48 h para aceitar. Até lá, dá para cancelar.")
                    problem?.let { WarningLine(it, GMColors.danger) }
                    GMButton(if (busy) "Enviando…" else "Propor troca a ${f.name}", {
                        busy = true
                        scope.launch {
                            val err = vm.propose(f, m, t)
                            busy = false
                            if (err == null) { haptic.performHapticFeedback(HapticFeedbackType.LongPress); done() } else problem = err
                        }
                    }, icon = Icons.AutoMirrored.Filled.Send, enabled = !busy)
                }
                f != null && t != null -> {
                    Text("Da sua Box", color = GMColors.dim, style = GMType.subheadline)
                    val list = vm.myBros(home)
                    val refusals = list.associate { it.uuid to vm.refusal(home, it) }
                    if (refusals.values.all { it != null }) {
                        WarningLine("Nenhum bro seu pode entrar agora. Ovos, o principal e quem está em liga, X1 ou outra troca ficam de fora.", GMColors.trophy)
                    }
                    BroGrid(list.map { b -> Triple(b.bro, refusals[b.uuid]?.tag) { pick { mine = b } } })
                }
                f != null -> {
                    Text("Bros de ${f.name}", color = GMColors.dim, style = GMType.subheadline)
                    val bros = friendBros
                    if (bros == null) Box(Modifier.fillMaxWidth().padding(30.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = GMColors.accent) }
                    else if (bros.isEmpty()) GMEmptyState(Icons.Filled.GridView, "Nenhum bro para trocar", "${f.name} ainda não tem bros disponíveis para troca.")
                    else BroGrid(bros.map { b -> Triple(b, if (b.isEgg) "Ovo não troca" else null) { pick { theirs = b } } })
                }
                else -> FriendStep(st.friends, st.friendsLoaded, query, { query = it }) { pick { friend = it } }
            }
        }
    }
}

@Composable
private fun FriendStep(all: List<RemoteFriend>, loaded: Boolean, query: String, onQuery: (String) -> Unit, onPick: (RemoteFriend) -> Unit) {
    if (!loaded) return Box(Modifier.fillMaxWidth().padding(30.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = GMColors.accent) }
    if (all.isEmpty()) return GMEmptyState(Icons.Filled.People, "Sem amigos ainda", "Troca é só entre amigos. Adicione alguém pelo código de amigo.")
    fun fold(s: String) = java.text.Normalizer.normalize(s, java.text.Normalizer.Form.NFD).replace(Regex("\\p{M}"), "").lowercase()
    val shown = all.filter { query.isEmpty() || fold(it.name).contains(fold(query)) }
    if (all.size > 6) GMTextField(query, onQuery, "Buscar amigo")
    Column(Modifier.fillMaxWidth().heightIn(max = 420.dp).verticalScroll(rememberScrollState()).background(GMColors.raised, GMRadius.m)
               .padding(horizontal = 12.dp)) {
        shown.forEachIndexed { i, f ->
            Row(Modifier.fillMaxWidth().heightIn(min = 52.dp).gmPress { onPick(f) }.padding(vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.width(42.dp), contentAlignment = Alignment.Center) { MonsterSprite(f.form, Modifier.size(36.dp)) }
                Text(f.name, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold), modifier = Modifier.weight(1f))
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = GMColors.dim, modifier = Modifier.size(16.dp))
            }
            if (i < shown.size - 1) Box(Modifier.padding(start = 54.dp)) { BroDivider() }
        }
    }
}

/** Grade de 3 colunas com rolagem: funciona igual com 2 ou 40 bros. `tag` explica por que não dá para escolher */
@Composable
private fun BroGrid(items: List<Triple<TradeBro, String?, () -> Unit>>) {
    Column(Modifier.fillMaxWidth().heightIn(max = 420.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        for (row in items.chunked(3)) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                for ((b, tag, pick) in row) BroCard(b, tag, Modifier.weight(1f), pick)
                repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}

@Composable
private fun BroCard(b: TradeBro, tag: String?, modifier: Modifier, onClick: () -> Unit) {
    Column(
        modifier.graphicsLayer { alpha = if (tag == null) 1f else 0.45f }.background(GMColors.raised, GMRadius.m)
            .gmPress(enabled = tag == null, role = Role.Button, onClick = onClick).padding(horizontal = 4.dp).padding(bottom = 8.dp)
            .semantics(mergeDescendants = true) { contentDescription = listOfNotNull(b.name, tag).joinToString(", ") },
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        MonsterSprite(b.form, Modifier.padding(top = 8.dp).size(52.dp))
        Text(b.name, color = Color.White, style = GMType.caption.copy(fontWeight = FontWeight.Bold), maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(if (b.form.stage == Stage.EGG) " " else "${b.form.stage.label} · ${b.xp.br()} XP", color = GMColors.dim, fontSize = 9.sp,
             fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
        // A etiqueta ocupa o mesmo espaço com ou sem texto: os cards ficam da mesma altura
        Text(tag ?: " ", color = GMColors.trophy, fontSize = 9.sp, fontWeight = FontWeight.Black, maxLines = 1,
             modifier = Modifier.background(if (tag == null) Color.Transparent else GMColors.trophy.copy(alpha = 0.15f), CircleShape)
                 .padding(horizontal = 6.dp, vertical = 2.dp))
    }
}

@Composable
private fun Note(icon: ImageVector, text: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Top) {
        Icon(icon, null, tint = GMColors.trophy, modifier = Modifier.size(14.dp))
        Text(text, color = Color.White.copy(alpha = 0.85f), style = GMType.caption)
    }
}

@Composable
private fun WarningLine(text: String, tint: Color) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.Top) {
        Icon(Icons.Filled.Warning, null, tint = tint, modifier = Modifier.size(14.dp))
        Text(text, color = tint, style = GMType.caption.copy(fontWeight = FontWeight.Bold))
    }
}

// MARK: Chegada

/**
 * Bro que chegou por troca (TradeSwapScene.swift `TradeArrivedView`): a comemoração em tela cheia. A cena animada de
 * troca de DNA do iPhone ainda não foi portada; aqui o bro aparece direto, como no iPhone com "reduzir movimento".
 */
@Composable
internal fun TradeArrived(home: HomeData, a: Arrival, onDismiss: () -> Unit) {
    val haptic = LocalHapticFeedback.current
    LaunchedEffect(a) { haptic.performHapticFeedback(HapticFeedbackType.LongPress) }
    val arriving = home.roster.snapshot(a.broUUID).form.takeIf { home.roster.monster(a.broUUID) != null } ?: a.proposal.theirs.form
    val name = home.roster.monster(a.broUUID)?.displayName(arriving) ?: arriving.name
    val tint = arriving.attribute?.color() ?: GMColors.trophy
    val p = a.proposal
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Column(Modifier.fillMaxSize().background(Color.Black).background(Brush.radialGradient(listOf(tint.copy(alpha = 0.32f), Color.Transparent)))
                   .safeDrawingPadding().padding(horizontal = 20.dp),
               horizontalAlignment = Alignment.CenterHorizontally) {
            Spacer(Modifier.weight(1f))
            LivingMonster(arriving, Modifier.size(180.dp).semantics { contentDescription = name })
            Spacer(Modifier.weight(1f))
            Column(Modifier.padding(horizontal = 8.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("TROCA FEITA", color = GMColors.trophy, style = GMType.caption.copy(fontWeight = FontWeight.Black, letterSpacing = 1.2.sp))
                Text("$name agora é seu GymBro!", color = Color.White, fontSize = 28.sp, fontWeight = FontWeight.ExtraBold, textAlign = TextAlign.Center)
                Text("Continue treinando e evoluindo juntos.", color = Color.White.copy(alpha = 0.85f), style = GMType.headline)
                Text("Veio de ${p.friend.name} com ${p.theirs.xp.br()} XP, que ficam marcados como de quem o treinou. ${p.mine.name} foi para ${p.friend.name}.",
                     color = GMColors.dim, style = GMType.caption, textAlign = TextAlign.Center)
            }
            GMButton("Ver na Box", onDismiss, Modifier.padding(top = 22.dp, bottom = 24.dp), icon = Icons.Filled.GridView)
        }
    }
}
