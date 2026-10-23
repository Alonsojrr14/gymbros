package com.alonsoalmeida.gymbros.ui.duels

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.CloudOff
import androidx.compose.material.icons.filled.DirectionsRun
import androidx.compose.material.icons.filled.HourglassTop
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.alonsoalmeida.gymbros.data.DuelRepository
import com.alonsoalmeida.gymbros.data.FriendsRepository
import com.alonsoalmeida.gymbros.domain.Attribute
import com.alonsoalmeida.gymbros.domain.MonsterForm
import com.alonsoalmeida.gymbros.domain.duel.DuelMetric
import com.alonsoalmeida.gymbros.domain.duel.DuelPerson
import com.alonsoalmeida.gymbros.domain.duel.DuelRecord
import com.alonsoalmeida.gymbros.domain.duel.DuelRefusal
import com.alonsoalmeida.gymbros.domain.duel.DuelResult
import com.alonsoalmeida.gymbros.domain.duel.DuelTally
import com.alonsoalmeida.gymbros.domain.duel.Duels
import com.alonsoalmeida.gymbros.domain.duel.RemoteDuel
import com.alonsoalmeida.gymbros.domain.home.HomeData
import com.alonsoalmeida.gymbros.ui.AppEnv
import com.alonsoalmeida.gymbros.ui.components.GMButton
import com.alonsoalmeida.gymbros.ui.components.GMButtonKind
import com.alonsoalmeida.gymbros.ui.components.GMCard
import com.alonsoalmeida.gymbros.ui.components.GMEmptyState
import com.alonsoalmeida.gymbros.ui.components.GMIconButton
import com.alonsoalmeida.gymbros.ui.components.GMModal
import com.alonsoalmeida.gymbros.ui.components.GMProgressBar
import com.alonsoalmeida.gymbros.ui.components.GMSection
import com.alonsoalmeida.gymbros.ui.components.GMSheet
import com.alonsoalmeida.gymbros.ui.friends.TermsPrompt
import com.alonsoalmeida.gymbros.ui.components.MonsterSprite
import com.alonsoalmeida.gymbros.ui.components.gmPress
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMRadius
import com.alonsoalmeida.gymbros.ui.theme.GMType
import com.alonsoalmeida.gymbros.ui.theme.color
import kotlinx.coroutines.delay
import java.time.Instant

// X1 (ios/GymBros/Duels/DuelViews.swift): card na tela inicial, tela com recebidos, valendo, enviados e encerrados,
// e a folha de desafio (pessoa, bro que luta e métrica).

/** Até 20 encerrados na lista, como no iOS */
private const val MAX_RECORDS = 20

/** O mesmo `DuelsViewModel` para o card e a tela (escopo da conta aberta) */
@Composable
private fun duelsViewModel(env: AppEnv): DuelsViewModel = viewModel(key = "duels-${env.uid}", factory = viewModelFactory {
    initializer { DuelsViewModel(DuelRepository(), FriendsRepository(), env.copies) }
})

/** "Agora" que avança sozinho (o `TimelineView(.periodic)` do iOS) */
@Composable
private fun rememberNow(periodMillis: Long): Instant {
    var now by remember { mutableStateOf(Instant.now()) }
    LaunchedEffect(periodMillis) {
        while (true) { delay(periodMillis); now = Instant.now() }
    }
    return now
}

private fun DuelMetric.icon(): ImageVector = when (this) {
    DuelMetric.XP -> Icons.Filled.AutoAwesome
    DuelMetric.TREINOS -> Icons.Filled.CheckCircle
    DuelMetric.MINUTOS -> Icons.Filled.Timer
    DuelMetric.DISTANCIA -> Icons.Filled.DirectionsRun
    DuelMetric.CALORIAS -> Icons.Filled.LocalFireDepartment
}

/** `DuelMetric.tint` do iOS */
private fun DuelMetric.tint(): Color = when (this) {
    DuelMetric.XP -> GMColors.accent
    DuelMetric.TREINOS -> Attribute.TECNICA.color()
    DuelMetric.MINUTOS -> Attribute.RESISTENCIA.color()
    DuelMetric.DISTANCIA -> GMColors.online
    DuelMetric.CALORIAS -> GMColors.streak
}

// MARK: Card da tela inicial

/** Card do X1 na tela inicial (DuelHomeCard): retrospecto, desafios esperando você e X1 valendo */
@Composable
fun DuelHomeCard(env: AppEnv, home: HomeData) {
    val vm = duelsViewModel(env)
    LaunchedEffect(home) { vm.update(home) }
    LifecycleResumeEffect(vm) {
        vm.refresh()
        onPauseOrDispose { }
    }
    val s by vm.state.collectAsStateWithLifecycle()
    val now = rememberNow(60_000)
    var open by rememberSaveable { mutableStateOf(false) }
    var openPicking by rememberSaveable { mutableStateOf(false) }
    var target by remember { mutableStateOf<DuelPerson?>(null) }
    val maxRows = 3
    val incoming = s.incoming(now)
    val active = s.active(now)
    val rows = incoming.map { it to true } + active.map { it to false }
    val t = Duels.tally(s.records(now))

    GMCard {
        Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).gmPress { open = true }.semantics { contentDescription = "Abrir X1" },
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(Icons.Filled.Bolt, null, tint = GMColors.trophy, modifier = Modifier.size(20.dp))
            Text("X1", color = GMColors.trophy, style = GMType.headline)
            Spacer(Modifier.weight(1f))
            if (t.total > 0) Text("${t.v}V · ${t.e}E · ${t.d}D", color = GMColors.dim, style = GMType.caption.copy(fontWeight = FontWeight.Bold))
            Icon(Icons.Filled.ChevronRight, null, tint = GMColors.dim, modifier = Modifier.size(16.dp))
        }
        if (rows.isEmpty()) {
            Text("Ninguém no X1 com você agora. Desafie alguém: vence quem treinar mais nas 24 h depois do aceite.",
                 color = Color.White.copy(alpha = 0.85f), style = GMType.subheadline)
            val quick = s.friends.filter { s.refusal(it.id, now) == null }.take(4)
            if (quick.isNotEmpty()) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    quick.forEach { f ->
                        Column(Modifier.weight(1f).gmPress { target = DuelPerson(f.id, f.name, f.formID) }.semantics(mergeDescendants = true) {
                            contentDescription = "Desafiar ${f.name}"
                        }, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            Box(Modifier.size(48.dp).background(GMColors.raised, CircleShape).border(1.5.dp, GMColors.trophy.copy(alpha = 0.6f), CircleShape),
                                contentAlignment = Alignment.Center) { MonsterSprite(f.form, Modifier.size(34.dp)) }
                            Text(f.name, color = Color.White, style = GMType.caption2.copy(fontWeight = FontWeight.Bold), maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                }
            }
            GMButton("Desafiar alguém", { openPicking = true }, icon = Icons.Filled.Bolt, kind = GMButtonKind.SECONDARY, small = true)
        } else {
            rows.take(maxRows).forEach { (d, pending) ->
                Box(Modifier.gmPress { open = true }) { if (pending) IncomingRow(d, now) else ActiveRow(d, s, now) }
            }
            if (rows.size > maxRows) {
                Text("Ver mais ${rows.size - maxRows}", color = GMColors.accent, style = GMType.caption.copy(fontWeight = FontWeight.Bold),
                     modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).gmPress { open = true }.padding(top = 14.dp))
            }
        }
    }

    DuelsModal(open || openPicking, env, home, onDismiss = { open = false; openPicking = false }, startPicking = openPicking)
    target?.let { p -> ComposerSheet(vm, s, p, now, onDismiss = { target = null }) }
}

@Composable
private fun IncomingRow(d: RemoteDuel, now: Instant) {
    Row(Modifier.fillMaxWidth().background(GMColors.trophy.copy(alpha = 0.1f), GMRadius.m).padding(10.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        MonsterSprite(d.challenger.form, Modifier.size(36.dp))
        Column(Modifier.weight(1f)) {
            Text("${d.challenger.name} te desafiou", color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
            Text("${d.metric.title} · expira em ${Duels.remaining(d.expiresAt, now)}", color = GMColors.dim, style = GMType.caption)
        }
        Text("Responder", color = Color.Black, style = GMType.caption.copy(fontWeight = FontWeight.Bold),
             modifier = Modifier.background(GMColors.trophy, CircleShape).padding(horizontal = 10.dp, vertical = 6.dp))
    }
}

@Composable
private fun ActiveRow(d: RemoteDuel, s: DuelsUiState, now: Instant) {
    val score = s.score(d, now)
    val other = d.opponent(Duels.ME)
    val tint = if (score.mine > score.theirs) GMColors.accent else if (score.mine < score.theirs) GMColors.danger else Color.White
    Row(Modifier.fillMaxWidth().background(GMColors.raised, GMRadius.m).padding(10.dp).semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        MonsterSprite(s.myForm(d), Modifier.size(32.dp))
        Text(d.metric.short(score.mine), color = tint, style = GMType.headline, maxLines = 1)
        Text("×", color = GMColors.dim, style = GMType.subheadline.copy(fontWeight = FontWeight.Bold))
        Text(d.metric.short(score.theirs), color = Color.White, style = GMType.headline, maxLines = 1)
        MonsterSprite(other.form, Modifier.size(32.dp))
        Column(Modifier.weight(1f)) {
            Text(other.name, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold), maxLines = 1, overflow = TextOverflow.Ellipsis)
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(d.metric.icon(), null, tint = GMColors.dim, modifier = Modifier.size(11.dp))
                Text(d.endsAt?.let { Duels.remaining(it, now) } ?: "", color = GMColors.dim, style = GMType.caption2)
            }
        }
    }
}

// MARK: Tela do X1

/** X1 (DuelsView). `opponentID`: abre já desafiando essa pessoa; `startPicking`: abre já na escolha de quem desafiar */
@Composable
fun DuelsModal(visible: Boolean, env: AppEnv, home: HomeData, onDismiss: () -> Unit, opponentID: String? = null, startPicking: Boolean = false) {
    if (!visible) return
    val vm = duelsViewModel(env)
    LaunchedEffect(home) { vm.update(home) }
    LifecycleResumeEffect(vm) {
        vm.startPolling()
        onPauseOrDispose { vm.stopPolling() }
    }
    val s by vm.state.collectAsStateWithLifecycle()
    val now = rememberNow(30_000)
    var picking by rememberSaveable { mutableStateOf(startPicking) }
    var target by remember { mutableStateOf<DuelPerson?>(null) }
    var answering by remember { mutableStateOf<RemoteDuel?>(null) }

    // Aberto pelo perfil de alguém: vai direto para o desafio, quando os amigos chegarem
    var asked by rememberSaveable(opponentID) { mutableStateOf(false) }
    LaunchedEffect(opponentID, s.loaded, s.friends) {
        if (opponentID == null || asked || !s.loaded) return@LaunchedEffect
        asked = true
        val f = s.friends.firstOrNull { it.id == opponentID }
        if (f != null) target = DuelPerson(f.id, f.name, f.formID)
        else vm.showMessage((s.personRefusal(opponentID, Instant.now()) ?: DuelRefusal.NOT_FRIEND).message)
    }

    // Sem os termos aceitos, o X1 pede o aceite antes (termsGate do iOS)
    if (!s.termsOK) {
        GMModal(true, "X1", onDismiss) { TermsPrompt { vm.acceptTerms() } }
        return
    }

    GMModal(true, "X1", onDismiss) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Desafie um amigo: vence quem fizer mais nas 24 h depois do aceite", color = GMColors.dim, style = GMType.subheadline,
                 modifier = Modifier.weight(1f))
            GMIconButton(Icons.Filled.Add, "Novo X1", { picking = true })
        }
        val records = s.records(now)
        RecordCard(Duels.tally(records), s.me.form)

        val incoming = s.incoming(now)
        val active = s.active(now)
        val sent = s.sent(now)
        if (s.lastError != null && s.all.isEmpty()) {
            GMEmptyState(Icons.Filled.CloudOff, "X1 indisponível", s.lastError!!)
        } else {
            if (incoming.isNotEmpty()) {
                GroupLabel("Te desafiaram", incoming.size, GMColors.trophy)
                incoming.forEach { d -> InviteCard(d, now, s.busy, onAccept = { answering = d }, onDecline = { vm.respond(d, false, null) }) }
            }
            if (active.isNotEmpty()) {
                GroupLabel("Valendo agora", active.size, GMColors.accent)
                active.forEach { d -> Scoreboard(d, s, now) }
            }
            if (sent.isNotEmpty()) {
                GMSection("Esperando resposta") {
                    sent.forEach { d ->
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            MonsterSprite(d.challenged.form, Modifier.size(40.dp))
                            Column(Modifier.weight(1f)) {
                                Text("Aguardando ${d.challenged.name}", color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
                                Text(d.metric.title, color = d.metric.tint(), style = GMType.caption.copy(fontWeight = FontWeight.Bold))
                                Text("Expira em ${Duels.remaining(d.expiresAt, now)}", color = GMColors.dim, style = GMType.caption)
                            }
                            Icon(Icons.Filled.HourglassTop, null, tint = GMColors.dim, modifier = Modifier.size(18.dp))
                        }
                    }
                }
            }
            if (incoming.isEmpty() && active.isEmpty() && sent.isEmpty() && s.loaded) {
                GMCard {
                    Text("Desafie um amigo. Vence quem treinar mais nas 24 h depois do aceite.", color = Color.White, style = GMType.subheadline)
                    GMButton("Escolher quem desafiar", { picking = true }, icon = Icons.Filled.Bolt)
                }
            }
        }
        if (records.isNotEmpty()) {
            GMSection("Encerrados") { records.take(MAX_RECORDS).forEach { RecordRow(it) } }
        }
    }

    if (picking) PeopleSheet(s, now, onPick = { picking = false; target = it }, onDismiss = { picking = false })
    target?.let { p -> ComposerSheet(vm, s, p, now, onDismiss = { target = null }) }
    answering?.let { d ->
        FighterSheet(s, now, title = "Quem vai lutar contra ${d.challenger.name}?", action = "Aceitar o X1", onDismiss = { answering = null }) { m ->
            answering = null
            vm.respond(d, true, m)
        }
    }
    MessageSheet(s.message) { vm.clearMessage() }
}

@Composable
private fun GroupLabel(text: String, count: Int, tint: Color) {
    Row(Modifier.padding(horizontal = 4.dp, vertical = 2.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Box(Modifier.size(7.dp).background(tint, CircleShape))
        Text(text.uppercase(), color = GMColors.dim, style = GMType.caption.copy(fontWeight = FontWeight.Bold, letterSpacing = 0.6.sp))
        if (count > 1) Text("$count", color = Color.Black, style = GMType.caption2.copy(fontWeight = FontWeight.Bold),
                            modifier = Modifier.background(tint, CircleShape).padding(horizontal = 6.dp, vertical = 1.dp))
    }
}

/** Seu bro e o retrospecto V/E/D, com a barra de aproveitamento (DuelRecordCard) */
@Composable
private fun RecordCard(t: DuelTally, form: MonsterForm) {
    GMCard {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            MonsterSprite(form, Modifier.size(56.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(18.dp)) {
                    Number(t.v, "vitórias", GMColors.accent)
                    Number(t.e, "empates", Color.White)
                    Number(t.d, "derrotas", GMColors.danger)
                }
                if (t.total > 0) {
                    GMProgressBar(t.v.toDouble() / t.total)
                    // `(v / total × 100).rounded()` do Swift: metade para longe do zero
                    val pct = com.alonsoalmeida.gymbros.domain.roundToIntSwift(t.v.toDouble() / t.total * 100)
                    Text("$pct% de vitórias em ${t.total} X1", color = GMColors.dim, style = GMType.caption)
                } else {
                    Text("Nenhum X1 encerrado ainda", color = GMColors.dim, style = GMType.caption)
                }
            }
        }
    }
}

@Composable
private fun Number(value: Int, label: String, tint: Color) {
    Column(Modifier.semantics(mergeDescendants = true) {}) {
        Text("$value", color = tint, fontSize = 26.sp, fontWeight = FontWeight.ExtraBold)
        Text(label, color = GMColors.dim, style = GMType.caption2)
    }
}

@Composable
private fun InviteCard(d: RemoteDuel, now: Instant, busy: Boolean, onAccept: () -> Unit, onDecline: () -> Unit) {
    GMCard {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            MonsterSprite(d.challenger.form, Modifier.size(48.dp))
            Column(Modifier.weight(1f)) {
                Text("${d.challenger.name} te chamou pro X1", color = Color.White, style = GMType.headline, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Icon(d.metric.icon(), null, tint = d.metric.tint(), modifier = Modifier.size(14.dp))
                    Text("Vale ${d.metric.title.lowercase()}", color = d.metric.tint(), style = GMType.subheadline.copy(fontWeight = FontWeight.Bold))
                }
            }
        }
        Text("Você tem ${Duels.remaining(d.expiresAt, now)} para responder. Aceitou, valem as próximas 24 h.", color = GMColors.dim, style = GMType.caption)
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            GMButton("Recusar", onDecline, Modifier.weight(1f), kind = GMButtonKind.SECONDARY, enabled = !busy, small = true)
            GMButton("Aceitar", onAccept, Modifier.weight(1f), enabled = !busy, small = true)
        }
    }
}

/** X1 valendo: você × a pessoa, com o tempo que falta (DuelScoreboard) */
@Composable
private fun Scoreboard(d: RemoteDuel, s: DuelsUiState, now: Instant) {
    val score = s.score(d, now)
    val other = d.opponent(Duels.ME)
    GMCard {
        Row(Modifier.semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.CenterVertically) {
            Side(s.myForm(d), "Você", d.metric.short(score.mine), score.mine > score.theirs, Modifier.weight(1f))
            Text("×", color = GMColors.dim, style = GMType.title3.copy(fontWeight = FontWeight.Bold))
            Side(other.form, other.name, d.metric.short(score.theirs), score.theirs > score.mine, Modifier.weight(1f))
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Icon(d.metric.icon(), null, tint = d.metric.tint(), modifier = Modifier.size(14.dp))
            Text(d.metric.title, color = d.metric.tint(), style = GMType.caption.copy(fontWeight = FontWeight.Bold))
            Spacer(Modifier.weight(1f))
            Text("Acaba em ${d.endsAt?.let { Duels.remaining(it, now) } ?: ""}", color = GMColors.dim, style = GMType.caption)
        }
    }
}

@Composable
private fun Side(form: MonsterForm, name: String, value: String, ahead: Boolean, modifier: Modifier) {
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        MonsterSprite(form, Modifier.size(52.dp))
        Text(name, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold), maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(value, color = if (ahead) GMColors.accent else Color.White, fontSize = 22.sp, fontWeight = FontWeight.ExtraBold, maxLines = 1)
    }
}

/** X1 encerrado (DuelRecordRow): letra do resultado e o resumo */
@Composable
private fun RecordRow(r: DuelRecord) {
    val tint = when (r.score.result) {
        DuelResult.VITORIA -> GMColors.accent
        DuelResult.DERROTA -> GMColors.danger
        DuelResult.EMPATE -> GMColors.dim
    }
    Row(Modifier.semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.size(32.dp).background(tint.copy(alpha = 0.18f), CircleShape), contentAlignment = Alignment.Center) {
            Text(r.score.result.letter, color = tint, style = GMType.subheadline.copy(fontWeight = FontWeight.Black))
        }
        MonsterSprite(r.opponent.form, Modifier.size(32.dp))
        Text(r.text, color = Color.White, style = GMType.footnote, modifier = Modifier.weight(1f))
    }
}

// MARK: Desafiar

/** Desafiar quem? Só amigos; quem não pode agora aparece apagado com o motivo (DuelPeoplePicker) */
@Composable
private fun PeopleSheet(s: DuelsUiState, now: Instant, onPick: (DuelPerson) -> Unit, onDismiss: () -> Unit) {
    GMSheet(onDismiss) {
        Text("Desafiar quem?", color = Color.White, style = GMType.headline)
        val block = s.fighterRefusal(null, now)
        if (block != null) {
            val free = s.nextFighterFree(now)
            Text(block.message + (if (block == DuelRefusal.ALL_FIGHTERS_BUSY && free != null) " Um bro fica livre em ${Duels.remaining(free, now)}." else ""),
                 color = GMColors.warning, style = GMType.footnote,
                 modifier = Modifier.fillMaxWidth().background(GMColors.warning.copy(alpha = 0.1f), GMRadius.m).padding(12.dp))
        }
        if (s.friends.isEmpty()) {
            Text("X1 é só entre amigos. Adicione amigos (aba Feed) para desafiar.", color = GMColors.dim, style = GMType.subheadline)
        }
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            s.friends.sortedBy { it.name }.forEach { f ->
                val r = s.personRefusal(f.id, now)
                val enabled = r == null && block == null
                Row(Modifier.fillMaxWidth().heightIn(min = 56.dp).gmPress(enabled) { onPick(DuelPerson(f.id, f.name, f.formID)) }
                        .padding(vertical = 6.dp).semantics(mergeDescendants = true) {},
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    MonsterSprite(f.form, Modifier.size(40.dp), saturation = if (enabled) 1f else 0.2f)
                    Text(f.name, color = if (enabled) Color.White else GMColors.dim, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold),
                         modifier = Modifier.weight(1f))
                    if (r != null) Text(tag(r), color = GMColors.dim, style = GMType.caption)
                    else Icon(Icons.Filled.ChevronRight, null, tint = GMColors.dim, modifier = Modifier.size(16.dp))
                }
            }
        }
    }
}

private fun tag(r: DuelRefusal): String = when (r) {
    DuelRefusal.ALREADY_OPEN -> "X1 aberto"
    DuelRefusal.BLOCKED -> "Indisponível"
    else -> ""
}

/** Desafio para uma pessoa: quem luta, o que vale e as regras (DuelComposer) */
@Composable
private fun ComposerSheet(vm: DuelsViewModel, s: DuelsUiState, opponent: DuelPerson, now: Instant, onDismiss: () -> Unit) {
    var metric by rememberSaveable { mutableStateOf(DuelMetric.XP) }
    var fighter by rememberSaveable { mutableStateOf(s.defaultFighter(now)?.uuid) }
    GMSheet(onDismiss) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            val mine = s.fighters.firstOrNull { it.uuid == fighter }
            FighterBadge(mine?.form ?: s.me.form, mine?.name ?: "Você")
            Text("VS", color = GMColors.trophy, fontSize = 18.sp, fontWeight = FontWeight.Black)
            FighterBadge(opponent.form, opponent.name)
        }
        if (s.fighters.size > 1) {
            Label("Quem vai lutar?")
            FighterRow(s, now, fighter) { fighter = it }
        }
        Label("Vale o quê?")
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            DuelMetric.entries.forEach { m ->
                val on = m == metric
                Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).gmPress(role = Role.RadioButton) { metric = m }
                        .semantics(mergeDescendants = true) { selected = on }
                        .background(if (on) m.tint().copy(alpha = 0.15f) else GMColors.raised, GMRadius.m)
                        .border(1.5.dp, if (on) m.tint() else Color.Transparent, GMRadius.m).padding(12.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Icon(m.icon(), null, tint = m.tint(), modifier = Modifier.size(20.dp))
                    Column(Modifier.weight(1f)) {
                        Text(m.title, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.Bold))
                        Text(if (on) m.detail else m.hint, color = GMColors.dim, style = GMType.caption)
                    }
                }
            }
        }
        Text("${opponent.name} tem 24 h para aceitar. Aceitou, vale tudo o que cada um registrar nas 24 h seguintes.",
             color = GMColors.dim, style = GMType.caption)
        GMButton("Desafiar ${opponent.name}", { vm.challenge(opponent, metric, fighter, onDismiss) }, icon = Icons.Filled.Bolt, enabled = !s.busy)
    }
}

@Composable
private fun FighterBadge(form: MonsterForm, name: String) {
    Column(Modifier.width(96.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        MonsterSprite(form, Modifier.size(64.dp))
        Text(name, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.Bold), maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun Label(text: String) {
    Text(text.uppercase(), color = GMColors.dim, style = GMType.caption.copy(fontWeight = FontWeight.Bold, letterSpacing = 0.6.sp),
         modifier = Modifier.fillMaxWidth())
}

/** Bros chocados lado a lado; ocupados aparecem apagados (cada bro luta um X1 por vez) */
@Composable
private fun FighterRow(s: DuelsUiState, now: Instant, selected: String?, onPick: (String) -> Unit) {
    val busy = s.busyFighters(now)
    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        s.fighters.forEach { f ->
            val free = f.uuid !in busy
            val on = f.uuid == selected
            Column(Modifier.width(72.dp).gmPress(free, role = Role.RadioButton) { onPick(f.uuid) }
                    .semantics(mergeDescendants = true) { this.selected = on; contentDescription = f.name + if (free) "" else ", em X1" }
                    .background(if (on) GMColors.accent.copy(alpha = 0.15f) else GMColors.raised, GMRadius.m)
                    .border(1.5.dp, if (on) GMColors.accent else Color.Transparent, GMRadius.m).padding(6.dp),
                horizontalAlignment = Alignment.CenterHorizontally) {
                MonsterSprite(f.form, Modifier.size(44.dp), saturation = if (free) 1f else 0.2f)
                Text(f.name, color = if (free) Color.White else GMColors.dim, style = GMType.caption2, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

/** Ao aceitar: escolher o bro (só com mais de um livre; senão aceita direto com o sugerido) */
@Composable
private fun FighterSheet(s: DuelsUiState, now: Instant, title: String, action: String, onDismiss: () -> Unit, onConfirm: (String?) -> Unit) {
    if (s.fighters.size <= 1) { LaunchedEffect(Unit) { onConfirm(null) }; return }
    var fighter by rememberSaveable { mutableStateOf(s.defaultFighter(now)?.uuid) }
    GMSheet(onDismiss) {
        Text(title, color = Color.White, style = GMType.headline)
        Text("Cada bro luta um X1 por vez", color = GMColors.dim, style = GMType.caption)
        FighterRow(s, now, fighter) { fighter = it }
        GMButton(action, { onConfirm(fighter) }, enabled = !s.busy)
    }
}

@Composable
private fun MessageSheet(message: String?, onDismiss: () -> Unit) {
    if (message == null) return
    GMSheet(onDismiss) {
        Text("X1", color = Color.White, style = GMType.headline)
        Text(message, color = Color.White, style = GMType.subheadline)
        GMButton("OK", onDismiss)
    }
}
