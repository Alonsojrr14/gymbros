package com.alonsoalmeida.gymbros.ui.train

import com.alonsoalmeida.gymbros.domain.onboarding.ScreenTip
import com.alonsoalmeida.gymbros.ui.onboarding.ScreenTipHost
import android.content.ClipboardManager
import android.media.AudioManager
import android.media.ToneGenerator
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.alonsoalmeida.gymbros.data.train.TrainData
import com.alonsoalmeida.gymbros.data.train.TrainEdits
import com.alonsoalmeida.gymbros.data.train.TrainHooks
import com.alonsoalmeida.gymbros.data.train.TrainScope
import com.alonsoalmeida.gymbros.data.train.WodRunStore
import com.alonsoalmeida.gymbros.domain.ActivityKind
import com.alonsoalmeida.gymbros.domain.ActivityText
import com.alonsoalmeida.gymbros.domain.AttributeSplit
import com.alonsoalmeida.gymbros.domain.Game
import com.alonsoalmeida.gymbros.domain.RuleClock
import com.alonsoalmeida.gymbros.domain.home.HomeData
import com.alonsoalmeida.gymbros.domain.home.LogPreview
import com.alonsoalmeida.gymbros.domain.train.Exercises
import com.alonsoalmeida.gymbros.domain.train.PRBook
import com.alonsoalmeida.gymbros.domain.train.PlannedWod
import com.alonsoalmeida.gymbros.domain.train.Progression
import com.alonsoalmeida.gymbros.domain.train.TrainSplit
import com.alonsoalmeida.gymbros.domain.train.Wod
import com.alonsoalmeida.gymbros.domain.train.WodDraft
import com.alonsoalmeida.gymbros.domain.train.WodFormat
import com.alonsoalmeida.gymbros.domain.train.WodLevelOption
import com.alonsoalmeida.gymbros.domain.train.WodLoad
import com.alonsoalmeida.gymbros.domain.train.WodLoads
import com.alonsoalmeida.gymbros.domain.train.WodMovements
import com.alonsoalmeida.gymbros.domain.train.WodParser
import com.alonsoalmeida.gymbros.domain.train.WodPart
import com.alonsoalmeida.gymbros.domain.train.WodPlan
import com.alonsoalmeida.gymbros.domain.train.WodResult
import com.alonsoalmeida.gymbros.domain.train.WodRunState
import com.alonsoalmeida.gymbros.domain.train.WodScheme
import com.alonsoalmeida.gymbros.domain.train.WodSet
import com.alonsoalmeida.gymbros.domain.train.WodTimelineEntry
import com.alonsoalmeida.gymbros.domain.train.clock
import com.alonsoalmeida.gymbros.ui.AppEnv
import com.alonsoalmeida.gymbros.ui.components.GMAction
import com.alonsoalmeida.gymbros.ui.components.GMActions
import com.alonsoalmeida.gymbros.ui.components.GMButton
import com.alonsoalmeida.gymbros.ui.components.GMButtonKind
import com.alonsoalmeida.gymbros.ui.components.GMCard
import com.alonsoalmeida.gymbros.ui.components.GMChip
import com.alonsoalmeida.gymbros.ui.components.GMChoiceChips
import com.alonsoalmeida.gymbros.ui.components.GMDecimalField
import com.alonsoalmeida.gymbros.ui.components.GMDivider
import com.alonsoalmeida.gymbros.ui.components.GMEffortPicker
import com.alonsoalmeida.gymbros.ui.components.GMEmptyState
import com.alonsoalmeida.gymbros.ui.components.GMFullScreen
import com.alonsoalmeida.gymbros.ui.components.GMIconButton
import com.alonsoalmeida.gymbros.ui.components.GMIconLabel
import com.alonsoalmeida.gymbros.ui.components.GMModal
import com.alonsoalmeida.gymbros.ui.components.GMRow
import com.alonsoalmeida.gymbros.ui.components.GMScreen
import com.alonsoalmeida.gymbros.ui.components.GMSection
import com.alonsoalmeida.gymbros.ui.components.GMSegmented
import com.alonsoalmeida.gymbros.ui.components.GMSheet
import com.alonsoalmeida.gymbros.ui.components.GMStepper
import com.alonsoalmeida.gymbros.ui.components.GMTextArea
import com.alonsoalmeida.gymbros.ui.components.GMTextButton
import com.alonsoalmeida.gymbros.ui.components.GMTintIconButton
import com.alonsoalmeida.gymbros.ui.components.GMTitledStepper
import com.alonsoalmeida.gymbros.ui.components.GMToggle
import com.alonsoalmeida.gymbros.ui.components.GMValueRow
import com.alonsoalmeida.gymbros.ui.components.MonsterSprite
import com.alonsoalmeida.gymbros.ui.components.TrainIcons
import com.alonsoalmeida.gymbros.ui.components.gmPress
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMRadius
import com.alonsoalmeida.gymbros.ui.theme.GMType
import kotlinx.coroutines.delay
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset

// Modo WOD (Train/Wod.swift, WodImport.swift, WodLoads.swift, WodTimeline.swift): benchmarks, WOD livre, treino do coach
// importado do texto, cronômetro For Time / AMRAP / EMOM / Tabata / blocos, cargas e resultado. O print (OCR do iPhone)
// e o modelo do aparelho (Apple Intelligence) não existem no Android: aqui o treino entra colando ou digitando o texto.

private fun resultText(r: WodResult) = r.text + if (r.rx) " RX" else ""

/** WODs: benchmarks, WOD livre, importar e últimos resultados (Wod.swift `WodListView`) */
@Composable
internal fun WodListScreen(env: AppEnv, data: TrainData, nav: TrainNav) {
    var custom by remember { mutableStateOf(false) }
    GMScreen("WODs", bottomInset = 120.dp, leading = { BackButton(nav) }) {
        Text("CrossFit: benchmarks e cronômetro", color = GMColors.dim, style = GMType.subheadline)
        ScreenTipHost(env, ScreenTip.WOD, blocked = custom || nav.importing || nav.wod != null)
        GMButton("WOD livre (monte o seu)", { custom = true }, icon = TrainIcons.of("timer"), kind = GMButtonKind.SECONDARY)
        GMButton("Importar treino do coach", { nav.importing = true }, icon = TrainIcons.of("doc.on.clipboard"), kind = GMButtonKind.SECONDARY)
        Column(Modifier.background(GMColors.card, GMRadius.card).padding(12.dp)) {
            GMRow("Meus WODs", TrainIcons.of("clock.arrow.circlepath"), GMColors.accent, "Linha do tempo", chevron = true, onClick = { nav.push("timeline") })
        }
        for (cat in listOf("Girls", "Heróis")) {
            GMSection(cat) {
                val list = Wod.benchmarks.filter { it.category == cat }
                list.forEachIndexed { i, w ->
                    GMRow(w.name, TrainIcons.of("flame.fill"), GMColors.streak, w.format.name, chevron = true, onClick = { nav.push("wod/${w.id}") }) {
                        data.wods.filter { it.wodID == w.id }.maxByOrNull { it.score }?.let {
                            Text(it.text, color = GMColors.accent, style = GMType.subheadline.copy(fontWeight = FontWeight.Bold, fontFeatureSettings = "tnum"))
                        }
                    }
                    if (i < list.size - 1) GMDivider()
                }
            }
        }
        if (data.wods.isNotEmpty()) GMSection("Últimos resultados") {
            for (r in data.wods.take(10)) GMValueRow("${r.wodName} · ${dayMonth(r.date)}", resultText(r))
        }
    }
    CustomWodModal(custom, { nav.wod = it; custom = false }) { custom = false }
}

/** Um benchmark: formato, linhas, movimentos, começar, recorde e histórico (Wod.swift `WodDetailView`) */
@Composable
internal fun WodDetailScreen(env: AppEnv, data: TrainData, id: String, nav: TrainNav) {
    val wod = Wod.byID(id) ?: run { LaunchedEffect(Unit) { nav.pop() }; return }
    var info by remember { mutableStateOf<com.alonsoalmeida.gymbros.domain.train.Exercise?>(null) }
    val results = data.wods.filter { it.wodID == wod.id }
    val best = results.maxByOrNull { it.score }
    GMScreen(wod.name, bottomInset = 120.dp, leading = { BackButton(nav) }) {
        Text(wod.format.name, color = GMColors.dim, style = GMType.subheadline)
        GMCard {
            Text(wod.format.detail, color = GMColors.dim, style = GMType.caption)
            for (l in wod.lines) Text(l, color = Color.White, style = GMType.headline)
        }
        if (wod.exercises.isNotEmpty()) GMSection("Movimentos") {
            for (e in wod.exercises.mapNotNull(Exercises::byID)) GMRow(e.name, chevron = true, onClick = { info = e }, leading = { Thumb(e.id, 36.dp) })
        }
        GMButton("Começar", { nav.wod = wod }, icon = TrainIcons.of("play.fill"))
        if (best != null) GMSection("Seu recorde") { GMValueRow(dayMonthYear(best.date), resultText(best)) }
        if (results.isNotEmpty()) GMSection("Histórico") { for (r in results) GMValueRow(dayMonthYear(r.date), resultText(r)) }
    }
    info?.let { ExerciseInfoModal(env, data, it) { info = null } }
}

/** WOD montado na hora: formato e tempo (Wod.swift `CustomWodView`) */
@Composable
private fun CustomWodModal(visible: Boolean, onStart: (Wod) -> Unit, onDismiss: () -> Unit) {
    if (!visible) return
    var kind by remember { mutableIntStateOf(1) }
    var minutes by remember { mutableIntStateOf(12) }
    var rounds by remember { mutableIntStateOf(8) }
    var lines by remember { mutableStateOf("") }
    GMModal(true, "WOD livre", onDismiss, confirm = "Montar", onConfirm = {
        val f = when (kind) { 0 -> WodFormat.ForTime(minutes); 1 -> WodFormat.Amrap(minutes); 2 -> WodFormat.Emom(minutes); else -> WodFormat.Tabata(rounds) }
        onStart(Wod("livre", "WOD livre", "Livre", f, lines.split("\n").filter { it.isNotEmpty() }))
    }) {
        GMSection("Formato") {
            GMChoiceChips(listOf(0 to "For Time", 1 to "AMRAP", 2 to "EMOM", 3 to "Tabata"), kind, { kind = it })
            if (kind == 3) GMTitledStepper("Rodadas", rounds, { rounds = it }, 1..20)
            else GMTitledStepper(if (kind == 0) "Limite" else "Duração", minutes, { minutes = it }, 1..90, format = { "$it min" })
        }
        GMSection("Movimentos (opcional)", footer = "Um por linha, ex.: 10 burpees") { GMTextArea(lines, { lines = it }, "10 burpees\n15 kettlebell swings", 80.dp) }
    }
}

/** Linha do treino; movimento de um complex aparece recuado, com a etiqueta "complex" */
@Composable
private fun WodLine(line: String, style: androidx.compose.ui.text.TextStyle = GMType.subheadline) {
    if (line.startsWith(WodParser.COMPLEX_MARK)) {
        Row(Modifier.padding(start = 12.dp).height(IntrinsicSize.Min), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(Modifier.width(2.dp).fillMaxHeight().background(GMColors.accent.copy(alpha = 0.6f)))
            Text(line.removePrefix(WodParser.COMPLEX_MARK), color = Color.White, style = style)
            Text("complex", color = GMColors.accent, style = GMType.caption2.copy(fontWeight = FontWeight.Bold),
                 modifier = Modifier.background(GMColors.accent.copy(alpha = 0.15f), CircleShape).padding(horizontal = 6.dp, vertical = 2.dp))
        }
    } else Text(line, color = Color.White, style = style)
}

/** Bipes das viradas (os sons 1005/1057 do iOS): um tom longo e um curto, sem permissão especial */
private object Beeper {
    private var tone: ToneGenerator? = null
    fun beep(long: Boolean) {
        val t = tone ?: runCatching { ToneGenerator(AudioManager.STREAM_NOTIFICATION, 90) }.getOrNull()?.also { tone = it } ?: return
        t.startTone(if (long) ToneGenerator.TONE_PROP_BEEP2 else ToneGenerator.TONE_PROP_BEEP, if (long) 400 else 120)
    }
}

private data class FinishedWod(val seconds: Int, val capped: Boolean, val startedAt: Instant?)

/** Cronômetro do WOD e do treino do coach com partes (Wod.swift `WodTimerView`) */
@Composable
internal fun WodTimerScreen(env: AppEnv, home: HomeData, data: TrainData, wod: Wod, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val haptic = LocalHapticFeedback.current
    val view = LocalView.current
    LaunchedEffect(Unit) { WodRunStore.open(context, wod) }
    DisposableEffect(Unit) { view.keepScreenOn = true; onDispose { view.keepScreenOn = false } }
    val run by WodRunStore.state.collectAsState()
    val s = run ?: WodRunState(wod, Instant.now())
    fun update(change: (WodRunState) -> WodRunState) = WodRunStore.set(context, change(WodRunStore.state.value ?: s))
    var nowMs by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) { while (true) { nowMs = System.currentTimeMillis(); delay(100) } }
    val now = Instant.ofEpochMilli(nowMs)
    var finished by remember { mutableStateOf<FinishedWod?>(null) }
    var lastTick by remember { mutableIntStateOf(-1) }
    var confirmQuit by remember { mutableStateOf(false) }
    var choosingPlace by remember { mutableStateOf(false) }
    val current = s.wod
    val parts = current.parts
    val overview = parts.isNotEmpty() && s.sessionStart == null
    val chipper = WodScheme.isChipper(current)
    val e = s.elapsed(now)

    fun beep(long: Boolean) { Beeper.beep(long); haptic.performHapticFeedback(if (long) HapticFeedbackType.LongPress else HapticFeedbackType.TextHandleMove) }

    fun finish(el: Double) {
        if (finished != null) return
        val total = current.format.totalSeconds?.let { minOf(el, it.toDouble()) } ?: el
        update { st -> if (st.pausedAt == null) st.copy(pausedAt = st.startedAt?.plusMillis(((total + st.pausedTotal) * 1000).toLong()) ?: Instant.now()) else st }
        beep(true)
        // For Time que chegou no limite: é CAP, não "terminou no tempo-limite"
        val f = current.format
        val capped = f is WodFormat.ForTime && f.capMinutes != null && total.toInt() >= f.capMinutes!! * 60
        finished = FinishedWod(maxOf(total.toInt(), 1), capped, s.startedAt)
    }

    // Contagem que acabou (mesmo com a tela fechada): o WOD começou no fim dela
    LaunchedEffect(s.countdownEnd?.let { it <= now } ?: false) {
        val c = s.countdownEnd
        if (c != null && c <= Instant.now() && s.startedAt == null) { update { it.copy(startedAt = minOf(c, Instant.now())) }; beep(true) }
    }
    // Avisos nas viradas (minuto do EMOM, troca do Tabata e dos blocos, fim do tempo)
    LaunchedEffect(e.toInt()) {
        val sec = e.toInt()
        if (s.startedAt == null || s.pausedAt != null || sec == lastTick) return@LaunchedEffect
        lastTick = sec
        val total = current.format.totalSeconds
        if (total != null && sec >= total) { finish(total.toDouble()); return@LaunchedEffect }
        when (val f = current.format) {
            is WodFormat.Emom -> if (sec > 0 && sec % 60 == 0) beep(true) else if (sec % 60 >= 57) beep(false)
            is WodFormat.Every -> if (sec > 0 && sec % f.seconds == 0) beep(true) else if (sec % f.seconds >= f.seconds - 3) beep(false)
            is WodFormat.Tabata -> if (sec % 30 == 0 || sec % 30 == 20) beep(true)
            is WodFormat.Amrap -> if (f.minutes * 60 - sec <= 3) beep(false)
            is WodFormat.Intervals -> f.segment(sec)?.let { (seg, remaining) ->
                val into = seg.seconds - remaining
                if (sec > 0 && into == 0) beep(true)
                else if (remaining <= 3 || (f.emom && !seg.rest && into % 60 >= 57)) beep(false)
                else if (f.emom && !seg.rest && into > 0 && into % 60 == 0) beep(true)
            }
            is WodFormat.ForTime -> {}
        }
    }

    GMFullScreen(true, onDismiss) {
        BackHandler { onDismiss() }
        Column(Modifier.fillMaxSize().padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                GMIconButton(TrainIcons.of("chevron.down"), "Minimizar treino", onDismiss)
                Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(current.name, color = Color.White, style = GMType.headline)
                    val ss = s.sessionStart
                    if (ss != null) GMIconLabel("Treino ${clock(((nowMs - ss.toEpochMilli()) / 1000).toInt())}", TrainIcons.of("stopwatch"), GMColors.accent)
                    else Text(current.format.name, color = GMColors.dim, style = GMType.caption)
                }
                GMIconButton(TrainIcons.of("xmark"), "Sair do treino", { confirmQuit = true })
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                val gym = data.gyms.firstOrNull { it.first == s.gymID }
                GMIconLabel(gym?.second ?: if (s.placeAsked) "Sem local" else "Onde você está?", TrainIcons.of("mappin.and.ellipse"), if (gym != null) GMColors.accent else Color.White,
                            modifier = Modifier.heightIn(min = 32.dp).gmPress { choosingPlace = true }
                                .background(if (gym != null) GMColors.accent.copy(alpha = 0.18f) else GMColors.raised, CircleShape).padding(horizontal = 12.dp, vertical = 6.dp))
                com.alonsoalmeida.gymbros.ui.components.LiveShareChip(env, com.alonsoalmeida.gymbros.data.live.LivePresence.liveID(s))
            }
            if (parts.isNotEmpty() && !overview) Progress(s, parts) { i -> if (s.startedAt == null && i != s.phase) update { it.view(i) } }
            when {
                overview -> {
                    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        for (p in parts) GMCard {
                            Text(p.title.uppercase(), color = GMColors.dim, style = GMType.caption.copy(fontWeight = FontWeight.Bold))
                            for (l in p.lines) WodLine(l)
                        }
                        LevelPicker(s, ::update)
                        WodCard(s, chipper, ::update)
                    }
                    GMButton("Começar treino", { update { it.work(0, Instant.now()) } }, icon = TrainIcons.of("play.fill"))
                }
                !s.onWod -> PartView(env, data, s, now, ::update)
                else -> {
                    if (s.startedAt == null && s.countdownEnd == null) WorkingLink(s, now, ::update)
                    LevelPicker(s, ::update)
                    val f = current.format
                    val groups = (f as? WodFormat.Intervals)?.let { WodScheme.blocks(current.lines).takeIf { g -> g.size == f.blocks.size } }
                    if (groups != null) BlockList(s, groups, e)
                    else if (current.lines.isNotEmpty()) Column(Modifier.heightIn(max = if (s.startedAt == null) 260.dp else 180.dp).verticalScroll(rememberScrollState())) {
                        WodCard(s, chipper, ::update)
                    }
                    Spacer(Modifier.weight(1f))
                    val cd = s.countdownEnd
                    if (cd != null && cd > now) {
                        Text("${((cd.toEpochMilli() - nowMs + 999) / 1000)}", color = GMColors.accent, fontSize = 120.sp, fontWeight = FontWeight.ExtraBold, maxLines = 1)
                        Text("Prepare-se", color = Color.White, style = GMType.title3.copy(fontWeight = FontWeight.Bold))
                    } else Display(s, e, now, chipper, ::update)
                    Spacer(Modifier.weight(1f))
                    if (s.startedAt == null) {
                        GMButton(if (s.countdownEnd == null) (if (parts.isEmpty()) "Começar (10 s)" else "Começar WOD (10 s)") else "Começando…", {
                            update { st -> var x = st.copy(countdownEnd = Instant.now().plusSeconds(10)); if (x.wod.parts.isNotEmpty()) x = x.work(x.wod.parts.size, Instant.now()); x }
                        }, icon = TrainIcons.of("play.fill"), enabled = s.countdownEnd == null)
                    } else Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        GMButton(if (s.pausedAt == null) "Pausar" else "Continuar", {
                            update { st ->
                                val p = st.pausedAt
                                if (p != null) st.copy(pausedTotal = st.pausedTotal + (System.currentTimeMillis() - p.toEpochMilli()) / 1000.0, pausedAt = null)
                                else st.copy(pausedAt = Instant.now())
                            }
                        }, Modifier.weight(1f), icon = TrainIcons.of(if (s.pausedAt == null) "pause.fill" else "play.fill"), kind = GMButtonKind.SECONDARY)
                        GMButton("Terminar", { finish(e) }, Modifier.weight(1f), icon = TrainIcons.of("flag.checkered"))
                    }
                }
            }
        }
    }
    GMActions(confirmQuit, { confirmQuit = false }, title = "Sair do treino?", message = if (s.sessionStart == null && s.startedAt == null) null else "O tempo não será salvo.",
              actions = listOf(GMAction("Sair sem salvar", TrainIcons.of("xmark"), true) { WodRunStore.set(context, null); onDismiss() }))
    if (choosingPlace) GMSheet({ choosingPlace = false }) {
        Text("Onde você está?", color = Color.White, style = GMType.headline)
        for ((gid, name) in data.gyms) GMButton(name, { update { it.copy(gymID = gid, placeAsked = true) }; choosingPlace = false }, icon = TrainIcons.of("dumbbell"), kind = GMButtonKind.SECONDARY)
        GMButton("Sem local", { update { it.copy(gymID = null, placeAsked = true) }; choosingPlace = false }, icon = TrainIcons.of("xmark"), kind = GMButtonKind.SECONDARY)
    }
    finished?.let { f ->
        WodResultModal(env, home, data, current, f, s, { finished = null; update { it.copy(pausedAt = null) } }) {
            WodRunStore.set(context, null)
            finished = null
            onDismiss()
        }
    }
}

/** Etapas do treino (partes e o WOD); toque numa etapa para ir até ela */
@Composable
private fun Progress(s: WodRunState, parts: List<WodPart>, onGo: (Int) -> Unit) {
    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        for (i in 0..parts.size) {
            val title = if (i < parts.size) parts[i].title else "WOD"
            val done = i < s.working && i != s.phase
            val here = i == s.phase
            Box(Modifier.heightIn(min = 36.dp).gmPress(enabled = s.startedAt == null) { onGo(i) }
                    .background(if (here) GMColors.accent else if (done) GMColors.accent.copy(alpha = 0.15f) else GMColors.raised, CircleShape)
                    .border(if (i == s.working && !here) 1.5.dp else 0.dp, GMColors.accent, CircleShape)
                    .padding(horizontal = if (done) 9.dp else 12.dp, vertical = 7.dp)
                    .semantics { contentDescription = if (done) "$title, feito" else title }, contentAlignment = Alignment.Center) {
                val tint = if (here) Color.Black else if (done || i == s.working) GMColors.accent else GMColors.dim
                if (done) Icon(TrainIcons.of("checkmark"), null, tint = tint, modifier = Modifier.size(14.dp))
                else Text(title, color = tint, style = GMType.caption.copy(fontWeight = FontWeight.Bold), maxLines = 1)
            }
        }
    }
}

/** Níveis do WOD do coach: dá para trocar até o cronômetro começar (o app lembra o seu nível) */
@Composable
private fun LevelPicker(s: WodRunState, update: ((WodRunState) -> WodRunState) -> Unit) {
    val context = LocalContext.current
    val levels = s.wod.levels ?: return
    if (levels.size <= 1 || s.startedAt != null || s.countdownEnd != null) return
    GMChoiceChips(levels.map { it.title to it.title }, s.wod.level ?: "", { t ->
        WodRunStore.setPreferredLevel(context, t)
        update { it.copy(wod = it.wod.withLevel(t), checked = emptyList()) }
    })
}

@Composable
private fun WodCard(s: WodRunState, chipper: Boolean, update: ((WodRunState) -> WodRunState) -> Unit) {
    val current = s.wod
    if (current.lines.isEmpty()) return
    GMCard {
        if (current.parts.isNotEmpty() || current.level != null) {
            Text((listOf("WOD", current.format.name) + listOfNotNull(current.level)).joinToString(" · "), color = GMColors.accent, style = GMType.caption.copy(fontWeight = FontWeight.Bold))
        }
        if (chipper && s.startedAt != null) {
            // Chipper: risca cada movimento ao terminar
            current.lines.forEachIndexed { i, line ->
                val done = i in s.checked
                Row(Modifier.fillMaxWidth().heightIn(min = 40.dp).gmPress { update { st -> st.copy(checked = if (i in st.checked) st.checked - i else st.checked + i) } },
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Icon(TrainIcons.of(if (done) "checkmark.circle.fill" else "circle"), null, tint = if (done) GMColors.accent else GMColors.dim)
                    Text(line, color = if (done) GMColors.dim else Color.White,
                         style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold, textDecoration = if (done) TextDecoration.LineThrough else null))
                }
            }
        } else for (l in current.lines) WodLine(l, GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
    }
}

/** Blocos lado a lado: o atual em destaque (no descanso, o próximo), os feitos apagados */
@Composable
private fun BlockList(s: WodRunState, groups: List<List<String>>, e: Double) {
    val f = s.wod.format as WodFormat.Intervals
    val seg = if (s.startedAt == null) null else f.segment(e.toInt())?.first
    val active = seg?.let { if (it.rest) it.block + 1 else it.block } ?: 0
    val scroll = rememberScrollState()
    Row(Modifier.fillMaxWidth().horizontalScroll(scroll).height(IntrinsicSize.Max), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        groups.forEachIndexed { i, lines ->
            val here = i == active
            Column(Modifier.width(230.dp).fillMaxHeight().alpha(if (i < active) 0.45f else 1f).background(GMColors.card, GMRadius.card)
                       .border(2.dp, if (here) GMColors.accent else Color.Transparent, GMRadius.card).padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row {
                    Text("BLOCO ${i + 1}", color = if (here) GMColors.accent else GMColors.dim, style = GMType.caption.copy(fontWeight = FontWeight.ExtraBold), modifier = Modifier.weight(1f))
                    Text("${if (f.emom) "EMOM" else "AMRAP"} ${f.blocks[i]}'", color = GMColors.dim, style = GMType.caption.copy(fontWeight = FontWeight.Bold))
                }
                for (l in lines) WodLine(l, GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
                if (i < groups.size - 1 && f.rest > 0) {
                    Spacer(Modifier.weight(1f))
                    GMIconLabel("Descanso ${WodFormat.restText(f.rest)}", TrainIcons.of("pause.fill"),
                                GMColors.warning.copy(alpha = if (seg?.rest == true && seg.block == i) 1f else 0.6f), GMType.caption.copy(fontWeight = FontWeight.SemiBold))
                }
            }
        }
    }
}

@Composable
private fun Big(text: String, color: Color = Color.White) =
    Text(text, color = color, fontSize = 92.sp, fontWeight = FontWeight.ExtraBold, maxLines = 1, style = GMType.largeTitle.copy(fontFeatureSettings = "tnum"))

/** O relógio grande de cada formato (Wod.swift `display`) */
@Composable
private fun ColumnScope.Display(s: WodRunState, e: Double, now: Instant, chipper: Boolean, update: ((WodRunState) -> WodRunState) -> Unit) {
    val sec = e.toInt()
    when (val f = s.wod.format) {
        is WodFormat.ForTime -> {
            Big(clock(sec))
            Text(f.capMinutes?.let { "limite $it:00" } ?: "cronômetro", color = GMColors.dim)
            if (chipper) Text("${s.checked.size} de ${s.wod.lines.size} feitos", color = Color.White, style = GMType.title3.copy(fontWeight = FontWeight.Bold))
            else RoundCounter(s, now, update)
        }
        is WodFormat.Amrap -> { Big(clock(maxOf(f.minutes * 60 - sec, 0))); Text("restantes de ${f.minutes}:00", color = GMColors.dim); RoundCounter(s, now, update) }
        is WodFormat.Emom -> { Big(clock(60 - sec % 60)); Text("Minuto ${minOf(sec / 60 + 1, f.minutes)} de ${f.minutes}", color = Color.White, style = GMType.title3.copy(fontWeight = FontWeight.Bold)) }
        is WodFormat.Every -> {
            Big(clock(f.seconds - sec % f.seconds))
            Text("Intervalo ${sec / f.seconds + 1}" + if (f.minutes > 0) " de ${maxOf(f.minutes * 60 / f.seconds, 1)}" else "", color = Color.White, style = GMType.title3.copy(fontWeight = FontWeight.Bold))
            Text("a cada ${clock(f.seconds)}", color = GMColors.dim)
        }
        is WodFormat.Tabata -> {
            val work = sec % 30 < 20
            Big(clock(if (work) 20 - sec % 30 else 30 - sec % 30), if (work) GMColors.accent else GMColors.warning)
            Text(if (work) "ESFORÇO" else "DESCANSO", color = if (work) GMColors.accent else GMColors.warning, fontSize = 22.sp, fontWeight = FontWeight.ExtraBold)
            Text("Rodada ${minOf(sec / 30 + 1, f.rounds)} de ${f.rounds}", color = GMColors.dim)
        }
        is WodFormat.Intervals -> {
            SegmentBar(f, sec)
            f.segment(sec)?.let { (seg, remaining) ->
                Big(clock(remaining), if (seg.rest) GMColors.warning else Color.White)
                if (seg.rest) {
                    Text("DESCANSO", color = GMColors.warning, fontSize = 22.sp, fontWeight = FontWeight.ExtraBold)
                    Text("Próximo: bloco ${seg.block + 2} de ${f.blocks.size}", color = GMColors.dim)
                } else {
                    Text("Bloco ${seg.block + 1} de ${f.blocks.size}", color = Color.White, style = GMType.title3.copy(fontWeight = FontWeight.Bold))
                    if (f.emom) Text("Minuto ${minOf((seg.seconds - remaining) / 60 + 1, f.blocks[seg.block])} de ${f.blocks[seg.block]}", color = GMColors.dim)
                    else RoundCounter(s, now, update)
                }
            }
        }
    }
}

/** Linha do tempo dos blocos: trabalho em verde, descanso em amarelo, preenchendo com o tempo */
@Composable
private fun SegmentBar(f: WodFormat.Intervals, sec: Int) {
    val segs = f.segments
    val total = maxOf(segs.sumOf { it.seconds }, 1)
    val accent = GMColors.accent
    val warning = GMColors.warning
    Canvas(Modifier.fillMaxWidth().padding(horizontal = 8.dp).height(8.dp)) {
        val gap = 4.dp.toPx()
        val width = size.width - gap * maxOf(segs.size - 1, 0)
        var x = 0f
        var startAt = 0
        for (seg in segs) {
            val w = width * seg.seconds / total
            val tint = if (seg.rest) warning else accent
            val fill = ((sec - startAt).toFloat() / seg.seconds).coerceIn(0f, 1f)
            drawRoundRect(tint.copy(alpha = 0.2f), Offset(x, 0f), Size(w, size.height), CornerRadius(size.height / 2))
            drawRoundRect(tint, Offset(x, 0f), Size(w * fill, size.height), CornerRadius(size.height / 2))
            x += w + gap
            startAt += seg.seconds
        }
    }
}

@Composable
private fun RoundCounter(s: WodRunState, now: Instant, update: ((WodRunState) -> WodRunState) -> Unit) {
    val haptic = LocalHapticFeedback.current
    if (s.startedAt == null) {
        s.wod.format.totalSeconds?.let { Text("${ActivityText.duration(maxOf(it / 60, 1))} no total", color = GMColors.dim, style = GMType.subheadline, modifier = Modifier.padding(top = 8.dp)) }
        return
    }
    val done = s.roundsShown(now)
    val caption = if (s.wod.format !is WodFormat.ForTime) "rodadas" else WodScheme.ladder(s.wod.lines)?.let { l ->
        if (done < l.size) "rodadas de ${l.size}\nagora: ${l[done]} reps" else "rodadas de ${l.size}\nterminou!"
    } ?: WodScheme.rounds(s.wod.lines)?.let { n -> if (done < n) "rodadas de $n" else "rodadas de $n\nterminou!" } ?: "rodadas"
    Row(Modifier.padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        GMIconButton(TrainIcons.of("minus"), "Tirar rodada", { update { it.removeRound(Instant.now()) } }, size = 44.dp)
        Column(Modifier.width(100.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text("$done", color = Color.White, style = GMType.largeTitle.copy(fontFeatureSettings = "tnum"))
            Text(caption, color = GMColors.dim, style = GMType.caption, textAlign = TextAlign.Center)
        }
        Box(Modifier.size(64.dp).gmPress { haptic.performHapticFeedback(HapticFeedbackType.LongPress); update { it.addRound(Instant.now()) } }
                .background(GMColors.accent, CircleShape).semantics { contentDescription = "Mais uma rodada" }, contentAlignment = Alignment.Center) {
            Icon(TrainIcons.of("plus"), null, tint = Color.Black, modifier = Modifier.size(28.dp))
        }
    }
}

/** Olhando outra parte: atalho de volta para a que está em andamento */
@Composable
private fun WorkingLink(s: WodRunState, now: Instant, update: ((WodRunState) -> WodRunState) -> Unit) {
    if (s.sessionStart == null || s.phase == s.working) return
    val title = if (s.working < s.wod.parts.size) s.wod.parts[s.working].title else "WOD"
    GMIconLabel("Em andamento: $title · ${clock(s.partElapsed(s.working, now).toInt())}", TrainIcons.of("arrow.uturn.forward"), GMColors.accent,
                modifier = Modifier.heightIn(min = 32.dp).gmPress { update { it.view(it.working) } })
}

/** Uma parte do treino (aquecimento, força…): relógio da parte, linhas, cronômetro interno e séries */
@Composable
private fun ColumnScope.PartView(env: AppEnv, data: TrainData, s: WodRunState, now: Instant, update: ((WodRunState) -> WodRunState) -> Unit) {
    val p = s.wod.parts[s.phase]
    val running = s.phase == s.working
    val spent = s.partElapsed(s.phase, now).toInt()
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(p.title, color = Color.White, style = GMType.title3.copy(fontWeight = FontWeight.Bold))
        Big(clock(spent), if (running) Color.White else GMColors.dim)
        val reset = @Composable { GMIconLabel("Zerar", TrainIcons.of("arrow.counterclockwise"), GMColors.dim, modifier = Modifier.heightIn(min = 32.dp)
            .gmPress { update { it.resetPart(it.phase, Instant.now()) } }.background(GMColors.raised, CircleShape).padding(horizontal = 10.dp, vertical = 5.dp)) }
        if (running) Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("nesta parte", color = GMColors.dim, style = GMType.caption)
            if (spent > 0) reset()
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                GMButton(if (spent > 0) "Continuar aqui" else "Começar aqui", { update { it.work(it.phase, Instant.now()) } }, icon = TrainIcons.of("play.fill"), full = false, small = true)
                if (spent > 0) reset()
            }
            WorkingLink(s, now, update)
        }
    }
    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Column(Modifier.fillMaxWidth().background(GMColors.card, GMRadius.card).padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            for (l in p.lines) WodLine(l, GMType.headline)
        }
        PartTimerCard(p.lines, s.partTimers[s.phase], now) { v -> update { st -> st.copy(partTimers = if (v == null) st.partTimers - st.phase else st.partTimers + (st.phase to v)) } }
        WodLoadsEditor(env, data, s.loads, { l -> update { it.copy(loads = l) } }, s.phase, p.lines, "Séries", bodyweight = true)
    }
    val next = if (s.phase + 1 < s.wod.parts.size) s.wod.parts[s.phase + 1].title else null
    GMButton(next?.let { "Próxima: $it" } ?: "Ir para o WOD", { update { it.work(it.phase + 1, Instant.now()) } }, icon = TrainIcons.of(if (next == null) "flame.fill" else "forward.fill"))
}

/** Cronômetro dentro de uma parte (força "a cada 2'", skill em EMOM); só aparece se a parte tiver tempo */
@Composable
private fun PartTimerCard(lines: List<String>, start: Instant?, now: Instant, onStart: (Instant?) -> Unit) {
    val f = lines.firstNotNullOfOrNull { WodParser.format(it) } ?: return
    GMCard {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(f.name, color = GMColors.accent, style = GMType.caption.copy(fontWeight = FontWeight.Bold))
                if (start == null) Text("Cronômetro desta parte", color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
                else {
                    val sec = ((now.toEpochMilli() - start.toEpochMilli()) / 1000).toInt()
                    val style = GMType.title3.copy(fontWeight = FontWeight.Bold, fontFeatureSettings = "tnum")
                    when {
                        f is WodFormat.Every && (f.minutes == 0 || sec < f.minutes * 60) ->
                            Text("Série ${sec / f.seconds + 1}${if (f.minutes > 0) " de ${maxOf(f.minutes * 60 / f.seconds, 1)}" else ""} · ${clock(f.seconds - sec % f.seconds)}", color = Color.White, style = style)
                        f is WodFormat.Emom && sec < f.minutes * 60 -> Text("Minuto ${sec / 60 + 1} de ${f.minutes} · ${clock(60 - sec % 60)}", color = Color.White, style = style)
                        f is WodFormat.Amrap && sec < f.minutes * 60 -> Text("Faltam ${clock(f.minutes * 60 - sec)}", color = Color.White, style = style)
                        f is WodFormat.ForTime && f.capMinutes != null && sec < f.capMinutes!! * 60 -> Text("${clock(sec)} de ${f.capMinutes}:00", color = Color.White, style = style)
                        f is WodFormat.ForTime && f.capMinutes == null -> Text(clock(sec), color = Color.White, style = style)
                        else -> Text("Tempo esgotado", color = GMColors.warning, style = GMType.title3.copy(fontWeight = FontWeight.Bold))
                    }
                }
            }
            GMButton(if (start == null) "Iniciar" else "Zerar", { onStart(if (start == null) Instant.now() else null) },
                     icon = TrainIcons.of(if (start == null) "play.fill" else "arrow.counterclockwise"),
                     kind = if (start == null) GMButtonKind.PRIMARY else GMButtonKind.SECONDARY, full = false, small = true)
        }
    }
}

/** Séries de uma parte do treino (WodLoads.swift `WodLoadsEditor`): com peso, carga × reps; sem peso, só reps */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun WodLoadsEditor(env: AppEnv, data: TrainData, loads: List<WodLoad>, onLoads: (List<WodLoad>) -> Unit, part: Int, lines: List<String>, title: String,
                           bodyweight: Boolean = false) {
    val context = LocalContext.current
    var picking by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf<Pair<String, Int>?>(null) }
    var confirmRemove by remember { mutableStateOf<String?>(null) }
    var registeringPR by remember { mutableStateOf<String?>(null) }
    val mine = loads.filter { it.part == part }
    val removed = mine.filter { it.removed == true }.map { it.exerciseID }.toSet()
    val exercises = WodLoads.tracked(lines, bodyweight).filter { it !in removed }.toMutableList().apply {
        for (l in mine) if (l.removed != true && l.exerciseID !in this) add(l.exerciseID)
    }
    val percents = WodLoads.percents(lines)
    val bar = WodRunStore.bar(context)
    fun oneRM(id: String) = WodLoads.oneRM(id, data.history, PRBook.manual[id].orEmpty(), bar)
    fun sets(id: String) = loads.firstOrNull { it.exerciseID == id && it.part == part }?.sets.orEmpty()
    fun setSets(id: String, list: List<WodSet>) {
        val i = loads.indexOfFirst { it.exerciseID == id && it.part == part }
        onLoads(if (i >= 0) loads.mapIndexed { k, l -> if (k == i) l.copy(sets = list) else l } else loads + WodLoad(id, part, list))
    }
    fun remove(id: String) {
        var out = loads.filter { !(it.exerciseID == id && it.part == part) }
        if (id in WodLoads.tracked(lines, bodyweight)) out = out + WodLoad(id, part, removed = true)
        onLoads(out)
    }
    GMSection(title, footer = if (exercises.isEmpty()) "Nenhum movimento reconhecido. Adicione o que você fez."
              else "O + repete a série anterior${if (percents.isEmpty()) "" else " (ou usa o próximo % do PR)"}. Toque numa série para corrigir.") {
        exercises.forEachIndexed { i, id ->
            if (i > 0) GMDivider()
            val list = sets(id)
            val bars = list.mapNotNull { it.bar }.toSet()
            val weighted = WodLoads.isWeighted(id)
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                        Text(Exercises.name(id), color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
                        when {
                            !weighted -> Text("Sem peso · conta as repetições", color = GMColors.dim, style = GMType.caption)
                            bars.size == 1 -> Text("Total com a barra de ${Progression.fmt(bars.first())} kg", color = GMColors.dim, style = GMType.caption)
                            Exercises.byID(id)?.usesBar == true && list.isEmpty() -> Text("Barra + anilhas", color = GMColors.dim, style = GMType.caption)
                        }
                        if (weighted && percents.isNotEmpty()) {
                            val pcts = percents.map { "${com.alonsoalmeida.gymbros.domain.roundToIntSwift(it * 100)}%" }
                            val pctText = if (pcts.size == 1) pcts[0] else "${pcts.first()}–${pcts.last()}"
                            val orm = oneRM(id)
                            if (orm != null) {
                                val kgs = percents.map { WodLoads.weight(it, orm, id, bar) }
                                val kgText = if (kgs.toSet().size == 1) "${Progression.fmt(kgs[0])} kg" else "${Progression.fmt(kgs.first())}–${Progression.fmt(kgs.last())} kg"
                                GMIconLabel("$pctText do PR (${Progression.fmt(com.alonsoalmeida.gymbros.domain.roundHalfAwayFromZero(orm))} kg) = $kgText", TrainIcons.of("trophy.fill"), GMColors.trophy,
                                            GMType.caption.copy(fontWeight = FontWeight.SemiBold))
                            } else GMIconLabel("$pctText do PR · registre seu PR", TrainIcons.of("trophy"), GMColors.trophy, GMType.caption.copy(fontWeight = FontWeight.SemiBold),
                                               Modifier.gmPress { registeringPR = id })
                        }
                    }
                    GMTintIconButton(TrainIcons.of("trash"), "Tirar ${Exercises.name(id)}", GMColors.dim, { if (list.isEmpty()) remove(id) else confirmRemove = id }, size = 30.dp)
                    Text(if (list.isEmpty()) "Série" else "+ série", color = Color.Black, style = GMType.caption.copy(fontWeight = FontWeight.Bold),
                         modifier = Modifier.heightIn(min = 32.dp).gmPress {
                             val reps = WodLoads.repsOf(id, lines) ?: WodLoads.reps(lines)
                             setSets(id, list + WodLoads.next(list, id, reps, data.history, bar, percents, oneRM(id)))
                         }.background(GMColors.accent, CircleShape).padding(horizontal = 12.dp, vertical = 6.dp))
                }
                if (list.isNotEmpty()) FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    list.forEachIndexed { k, set ->
                        Text("${k + 1}  ${WodLoads.setText(set, id, spaced = true)}", color = Color.White, style = GMType.caption.copy(fontWeight = FontWeight.SemiBold, fontFeatureSettings = "tnum"),
                             modifier = Modifier.heightIn(min = 32.dp).gmPress { editing = id to k }.background(GMColors.raised, CircleShape).padding(horizontal = 10.dp, vertical = 6.dp))
                    }
                }
            }
        }
        if (exercises.isNotEmpty()) GMDivider()
        GMRow("Outro exercício", TrainIcons.of("plus"), GMColors.accent, chevron = true, onClick = { picking = true })
    }
    ExercisePickerModal(picking, env, data, onPick = { e ->
        if (e.id !in exercises) onLoads(loads.filter { !(it.exerciseID == e.id && it.part == part) } + WodLoad(e.id, part))
    }) { picking = false }
    val cr = confirmRemove
    GMActions(cr != null, { confirmRemove = null }, title = "Tirar ${cr?.let(Exercises::name) ?: "exercício"}?", message = "As séries registradas dele saem junto.",
              actions = cr?.let { listOf(GMAction("Tirar exercício", TrainIcons.of("trash"), true) { remove(it) }) }.orEmpty())
    registeringPR?.let { PRSessionModal(env, data, it) { registeringPR = null } }
    editing?.let { (id, k) ->
        val set = sets(id).getOrNull(k) ?: run { editing = null; return@let }
        val ex = Exercises.byID(id)
        val weighted = WodLoads.isWeighted(id)
        val usesBar = weighted && ex?.usesBar == true
        var weight by remember(editing) { mutableStateOf<Double?>(set.weight) }
        var reps by remember(editing) { mutableStateOf<Double?>(set.reps.toDouble()) }
        var b by remember(editing) { mutableStateOf(set.bar ?: bar) }
        GMSheet({ editing = null }) {
            Text("${Exercises.name(id)} · série ${k + 1}", color = Color.White, style = GMType.headline)
            if (weighted) {
                if (usesBar) {
                    val side = maxOf(((weight ?: b) - b) / 2, 0.0)
                    GMChoiceChips(WodLoads.barOptions.map { it to "${Progression.fmt(it)} kg" }, b, { nb -> weight = nb + 2 * side; b = nb }, title = "Barra")
                    GMDecimalField("Anilhas de cada lado", side, { weight = b + 2 * maxOf(it ?: 0.0, 0.0) }, 1.25, "kg", 10.0, clearable = false)
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text("Total", color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold), modifier = Modifier.weight(1f))
                        Text("${Progression.fmt(b)} + 2 × ${Progression.fmt(side)} =", color = GMColors.dim, style = GMType.caption)
                        Text("${Progression.fmt(weight ?: b)} kg", color = GMColors.accent, style = GMType.title3.copy(fontWeight = FontWeight.ExtraBold))
                    }
                    GMDecimalField("Ou digite o total", weight, { weight = it }, 2.5, "kg", b, clearable = false)
                } else GMDecimalField("Carga", weight, { weight = it }, ex?.increment ?: 2.5, "kg", 20.0, clearable = false)
                GMDivider()
            }
            GMDecimalField("Reps", reps, { reps = it?.let { v -> maxOf(0.0, com.alonsoalmeida.gymbros.domain.roundHalfAwayFromZero(v)) } }, 1.0, "reps", 5.0, clearable = false)
            GMButton("Salvar", {
                if (usesBar) WodRunStore.setBar(context, b)
                setSets(id, sets(id).mapIndexed { i, x -> if (i == k) WodSet(if (weighted) maxOf(weight ?: 0.0, if (usesBar) b else 0.0) else 0.0, (reps ?: 0.0).toInt(), if (usesBar) b else null) else x })
                editing = null
            })
            GMButton("Apagar série", { setSets(id, sets(id).filterIndexed { i, _ -> i != k }); editing = null }, icon = TrainIcons.of("trash"), kind = GMButtonKind.DANGER)
        }
    }
}

/** Resultado do WOD (Wod.swift `WodResultForm`): placar, partes, cargas, duração, RX, esforço, observação e o XP */
@Composable
private fun WodResultModal(env: AppEnv, home: HomeData, data: TrainData, wod: Wod, f: FinishedWod, st: WodRunState, onDismiss: () -> Unit, onDone: () -> Unit) {
    val seconds = f.seconds
    val wodStart = f.startedAt ?: Instant.now().minusSeconds(seconds.toLong())
    val start = minOf(st.sessionStart ?: st.openedAt, wodStart)
    val wodMinutes = maxOf(seconds / 60, 1)
    var roundsDone by remember { mutableIntStateOf(st.rounds) }
    var extraReps by remember { mutableIntStateOf(0) }
    var rx by remember { mutableStateOf(true) }
    var effort by remember { mutableIntStateOf(8) }
    var note by remember { mutableStateOf("") }
    var minutes by remember { mutableIntStateOf(minOf(maxOf(((Instant.now().epochSecond - start.epochSecond) / 60).toInt(), wodMinutes), Game.MAX_MINUTES)) }
    var loadsDone by remember { mutableStateOf(st.loads) }
    val partResults = remember { mutableStateListOf<String>().apply { repeat(wod.parts.size) { add("") } } }
    val intervals = wod.format as? WodFormat.Intervals
    val blocksDone = remember { mutableStateListOf<Int>().apply { intervals?.blocks?.indices?.forEach { add(st.blockRounds.getOrNull(it) ?: 0) } } }
    val blockReps = remember { mutableStateListOf<Int>().apply { intervals?.blocks?.forEach { _ -> add(0) } } }

    fun postText(): String {
        val parts = wod.parts.mapIndexedNotNull { i, p ->
            val done = listOf(WodLoads.text(loadsDone.filter { it.part == i }), partResults.getOrElse(i) { "" }.trim()).filter { it.isNotEmpty() }.joinToString(" · ")
            if (done.isEmpty()) null else "${p.title}: $done"
        }
        val wodLoads = WodLoads.text(loadsDone.filter { it.part == wod.parts.size })
        val blocks = if (intervals != null && !intervals.emom) blocksDone.indices.map { i -> "Bloco ${i + 1}: ${blocksDone[i]} rodadas" + (blockReps.getOrElse(i) { 0 }.takeIf { it > 0 }?.let { " + $it" } ?: "") } else emptyList()
        return (parts + blocks + (if (wodLoads.isEmpty()) emptyList() else listOf("Cargas do WOD: $wodLoads")) + note.trim()).filter { it.isNotEmpty() }.joinToString("\n")
    }

    val total = maxOf(minutes, wodMinutes)
    val split = TrainSplit.split(ActivityKind.CROSSFIT, total, effort, wod = TrainSplit.WodSignal(wod.format, wod.exercises.ifEmpty { WodMovements.ids(wod.lines) }))
    val preview = LogPreview.compute(home.roster, ActivityKind.CROSSFIT, total, effort, start, split, RuleClock(ZoneId.systemDefault(), Instant.now()))

    val post = com.alonsoalmeida.gymbros.ui.leagues.rememberTrainingPost(home)
    val typeID = com.alonsoalmeida.gymbros.domain.BroCatalog.classicType[ActivityKind.CROSSFIT.raw]
    GMModal(true, "Resultado", onDismiss, confirm = "Salvar", confirmEnabled = post.canSave, onConfirm = {
        val r = WodResult(TrainEdits.newID(), wod.id, wod.name, wod.format.name, Instant.now(),
            seconds = if (wod.format is WodFormat.ForTime) seconds else null,
            rounds = when { wod.format is WodFormat.Amrap -> roundsDone; intervals != null && !intervals.emom -> blocksDone.sum(); else -> null },
            reps = when { wod.format is WodFormat.ForTime && f.capped -> extraReps; wod.format is WodFormat.Amrap -> extraReps; intervals != null && !intervals.emom -> blockReps.sum(); else -> null },
            rx = rx, note = note, capped = wod.format is WodFormat.ForTime && f.capped)
        val level = wod.level?.let { " · $it" } ?: ""
        val activityID = TrainEdits.newID()
        val loadsSession = WodLoads.session(loadsDone, if (wod.parts.isEmpty()) wod.name else "${wod.name} · cargas", activityID, start, total, effort, st.gymID, WodRunStore.bar(env.context))
        // A divisão olha as séries registradas primeiro (como o `ActivitySplits.stamp` do iOS), senão o WOD
        val finalSplit = TrainSplit.split(ActivityKind.CROSSFIT, total, effort,
            sets = loadsSession?.doneWorkSets?.map { TrainSplit.SetSignal(it.exerciseID, it.reps, it.rest) }.orEmpty(),
            wod = TrainSplit.WodSignal(wod.format, wod.exercises.ifEmpty { WodMovements.ids(wod.lines) }))
        TrainScope.edit(env) { c ->
            var out = TrainEdits.addActivity(c, activityID, ActivityKind.CROSSFIT.raw, start, total, effort, "${wod.name}$level · ${r.text}",
                                             AttributeSplit.encode(finalSplit), st.gymID)
            out = TrainEdits.addWod(out, r.copy(activityUUID = activityID))
            if (loadsSession != null) out = TrainEdits.saveSession(out, loadsSession)
            out
        }
        // Depois de salvar: o check-in em cada destino escolhido (postCheckIns)
        post.post(com.alonsoalmeida.gymbros.domain.leagues.LeagueActivityJson(activityID, ActivityKind.CROSSFIT.raw, start, total, effort,
                                                                              "${wod.name}$level · ${r.text}", gymUUID = st.gymID, healthType = typeID),
                  "${wod.name}$level · ${r.text}${if (rx) " RX" else ""}", postText())
        onDone()
    }) {
        GMCard {
            Text(wod.name, color = Color.White, style = GMType.title3.copy(fontWeight = FontWeight.ExtraBold))
            when {
                wod.format is WodFormat.ForTime && f.capped -> {
                    Text("CAP", color = GMColors.warning, fontSize = 48.sp, fontWeight = FontWeight.ExtraBold)
                    Text("Tempo esgotado no limite de ${clock(seconds)}: não conta como terminado.", color = GMColors.dim, style = GMType.caption)
                    GMTitledStepper("Repetições feitas", extraReps, { extraReps = it }, 0..2000)
                }
                wod.format is WodFormat.ForTime -> Text(clock(seconds), color = GMColors.accent, fontSize = 48.sp, fontWeight = FontWeight.ExtraBold)
                wod.format is WodFormat.Amrap -> {
                    GMTitledStepper("Rodadas", roundsDone, { roundsDone = it }, 0..200)
                    GMTitledStepper("Repetições extras", extraReps, { extraReps = it }, 0..500)
                }
                intervals != null && !intervals.emom -> intervals.blocks.forEachIndexed { i, b ->
                    if (i > 0) GMDivider()
                    Text("Bloco ${i + 1} · AMRAP $b'", color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.Bold))
                    GMTitledStepper("Rodadas", blocksDone.getOrElse(i) { 0 }, { blocksDone[i] = it }, 0..200)
                    GMTitledStepper("Repetições extras", blockReps.getOrElse(i) { 0 }, { blockReps[i] = it }, 0..500)
                }
                else -> Text("Concluído em ${clock(seconds)}", color = GMColors.accent, style = GMType.headline)
            }
        }
        if (wod.parts.isNotEmpty()) GMSection("Treino completo", footer = "As cargas registradas e as observações vão para o post junto com o WOD.") {
            wod.parts.forEachIndexed { i, part ->
                if (i > 0) GMDivider()
                Text(part.title, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.Bold))
                Text(part.lines.joinToString("\n"), color = GMColors.dim, style = GMType.caption)
                GMTextArea(partResults.getOrElse(i) { "" }, { partResults[i] = it }, "Observação da parte (opcional)")
            }
        }
        wod.parts.forEachIndexed { i, part ->
            if (WodLoads.tracked(part.lines, true).isNotEmpty() || loadsDone.any { it.part == i }) {
                WodLoadsEditor(env, data, loadsDone, { loadsDone = it }, i, part.lines, "Séries · ${part.title}", bodyweight = true)
            }
        }
        WodLoadsEditor(env, data, loadsDone, { loadsDone = it }, wod.parts.size, wod.lines, if (wod.parts.isEmpty()) "Cargas" else "Cargas · WOD")
        GMSection("Duração do treino", footer = "Do começo do treino até agora. O WOD em si levou ${ActivityText.duration(wodMinutes)}.") {
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { GMStepper(minutes, { minutes = it }, 1..Game.MAX_MINUTES, 5, ActivityText::duration) }
        }
        GMSection(footer = "RX: com as cargas e movimentos prescritos, sem adaptação.") { GMToggle("RX", rx, { rx = it }) }
        GMSection { GMEffortPicker(effort) { effort = it } }
        GMSection("Observação") { GMTextArea(note, { note = it }, "Carga usada, adaptações…") }
        GMSection("Bro do treino", footer = "O principal recebe o XP inteiro; quem te representa nas ligas marcadas, um pouco menos.") {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                MonsterSprite(home.snapshot.form, Modifier.size(36.dp))
                Text(home.monsterName, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold), modifier = Modifier.weight(1f))
                Text("+${preview.xp} XP", color = GMColors.accent, style = GMType.headline)
            }
            preview.message?.takeIf { preview.grows.isNotEmpty() }?.let { Text(it, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.Bold)) }
        }
        com.alonsoalmeida.gymbros.ui.leagues.TrainingPostSection(home, post, com.alonsoalmeida.gymbros.domain.leagues.PostSubject(typeID, start, total))
    }
}

/** Treino do coach completo: partes, WOD e ações (WodImport.swift `PlannedWodView`) */
@Composable
internal fun PlannedWodModal(env: AppEnv, data: TrainData, id: String, nav: TrainNav, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val plan = WodPlan.all(data.plannedRaw).firstOrNull { it.id == id } ?: run { LaunchedEffect(Unit) { onDismiss() }; return }
    var editing by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }
    var info by remember { mutableStateOf<com.alonsoalmeida.gymbros.domain.train.Exercise?>(null) }
    GMModal(true, plan.name, onDismiss) {
        Text(plannedDayText(plan.day) + " · " + plan.format.name, color = GMColors.dim, style = GMType.subheadline)
        for (p in plan.parts) GMSection(p.title) { for (l in p.lines) Text(l, color = Color.White, style = GMType.subheadline) }
        GMSection("WOD · ${plan.format.name}") {
            Text(plan.format.detail, color = GMColors.dim, style = GMType.caption)
            for (l in plan.lines) Text(l, color = Color.White, style = GMType.headline)
        }
        val done = data.wods.filter { it.wodID == plan.wodID }
        if (done.isNotEmpty()) GMSection("Seu resultado") { for (r in done) GMValueRow(dayMonthYear(r.date), resultText(r)) }
        val movements = WodMovements.ids(plan.parts.flatMap { it.lines } + plan.lines).mapNotNull(Exercises::byID)
        if (movements.isNotEmpty()) GMSection("Movimentos") { for (e in movements) GMRow(e.name, chevron = true, onClick = { info = e }, leading = { Thumb(e.id, 36.dp) }) }
        GMButton(if (plan.parts.isEmpty()) "Começar WOD" else "Começar treino", { nav.wod = plan.wod(WodRunStore.preferredLevel(context)); onDismiss() }, icon = TrainIcons.of("play.fill"))
        GMButton("Editar", { editing = true }, icon = TrainIcons.of("pencil"), kind = GMButtonKind.SECONDARY)
        GMButton("Apagar treino", { confirmDelete = true }, icon = TrainIcons.of("trash"), kind = GMButtonKind.DANGER)
    }
    ImportWodModal(editing, env, data, nav, plan) { editing = false }
    info?.let { ExerciseInfoModal(env, data, it) { info = null } }
    GMActions(confirmDelete, { confirmDelete = false }, title = "Apagar ${plan.name}?", message = "Resultados já salvos continuam no histórico.", actions = listOf(
        GMAction("Apagar", TrainIcons.of("trash"), true) { TrainScope.edit(env) { TrainEdits.text(it, WodPlan.KEY, WodPlan.delete(data.plannedRaw, plan)) }; onDismiss() }))
}

/** Colar ou digitar o treino do coach, conferir e agendar (WodImport.swift `ImportWodView`) */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ImportWodModal(visible: Boolean, env: AppEnv, data: TrainData, nav: TrainNav, editing: PlannedWod?, onDismiss: () -> Unit) {
    if (!visible) return
    val context = LocalContext.current
    val zone = ZoneId.systemDefault()
    val today = LocalDate.now(zone)
    var raw by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var reviewing by remember { mutableStateOf(false) }
    var name by remember { mutableStateOf("WOD do coach") }
    var day by remember { mutableStateOf(today) }
    var kind by remember { mutableIntStateOf(0) }
    var minutes by remember { mutableIntStateOf(12) }
    var rounds by remember { mutableIntStateOf(8) }
    var blocks by remember { mutableStateOf(listOf(3, 3, 3)) }
    var blockRest by remember { mutableIntStateOf(120) }
    var every by remember { mutableIntStateOf(60) }
    var blocksEmom by remember { mutableStateOf(false) }
    var linesText by remember { mutableStateOf("") }
    var parts by remember { mutableStateOf(listOf<WodPart>()) }
    var guessed by remember { mutableStateOf(false) }
    var draft by remember { mutableStateOf<WodDraft?>(null) }
    var dayChoice by remember { mutableIntStateOf(0) }
    var pickingDay by remember { mutableStateOf(false) }

    fun apply(f: WodFormat) = when (f) {
        is WodFormat.ForTime -> { kind = 0; minutes = f.capMinutes ?: 0 }
        is WodFormat.Amrap -> { kind = 1; minutes = f.minutes }
        is WodFormat.Emom -> { kind = 2; minutes = f.minutes; every = 60 }
        is WodFormat.Every -> { kind = 2; minutes = f.minutes; every = f.seconds }
        is WodFormat.Tabata -> { kind = 3; rounds = f.rounds }
        is WodFormat.Intervals -> { kind = 4; blocks = f.blocks; blockRest = f.rest; blocksEmom = f.emom }
    }
    fun setDay(d: LocalDate) { val off = java.time.temporal.ChronoUnit.DAYS.between(today, d).toInt(); dayChoice = if (off in 0..1) off else 2; day = d }
    LaunchedEffect(editing) {
        val p = editing ?: return@LaunchedEffect
        name = p.name; setDay(p.day.atZone(zone).toLocalDate()); apply(p.format); linesText = p.lines.joinToString("\n"); parts = p.parts; reviewing = true
    }
    val lines = linesText.split("\n").map(WodParser::clean).filter { it.isNotEmpty() }
    val format: WodFormat = when (kind) {
        0 -> WodFormat.ForTime(minutes.takeIf { it > 0 })
        1 -> WodFormat.Amrap(minutes)
        2 -> if (every == 60 && minutes > 0) WodFormat.Emom(minutes) else WodFormat.Every(every, minutes)
        4 -> WodFormat.Intervals(blocks, blockRest, blocksEmom)
        else -> WodFormat.Tabata(rounds)
    }
    fun interpret() {
        error = null
        val d = WodParser.parse(raw, WodRunStore.preferredLevel(context), today)
        if (d.lines.isEmpty()) { error = "Não achei os movimentos do WOD. Confira o texto."; return }
        draft = d; apply(d.format); d.day?.let(::setDay); linesText = d.lines.joinToString("\n"); parts = d.parts; guessed = d.guessed; reviewing = true
    }
    fun save(): PlannedWod {
        var p = editing ?: PlannedWod(day = day.atStartOfDay(zone).toInstant(), name = name, format = format, lines = lines)
        val chosen = draft?.takeIf { it.variants.size > 1 }?.level
        p = p.copy(day = day.atStartOfDay(zone).toInstant(), name = name.trim().ifEmpty { "WOD do coach" }, format = format, lines = lines,
                   parts = parts.filter { !it.title.startsWith(PlannedWod.OTHER_LEVEL) })
        if (chosen != null) p = p.copy(levels = draft!!.variants.map { if (it.title == chosen) WodLevelOption(chosen, format, lines) else WodLevelOption.parsing(it.title, it.lines) }, level = chosen)
        else p.level?.let { c -> p.levels?.indexOfFirst { it.title == c }?.takeIf { it >= 0 }?.let { i -> p = p.copy(levels = p.levels!!.mapIndexed { k, l -> if (k == i) WodLevelOption(c, format, lines) else l }) } }
        val saved = p
        TrainScope.edit(env) { TrainEdits.text(it, WodPlan.KEY, WodPlan.save(TrainCopyRaw.planned(it), saved)) }
        return saved
    }

    GMModal(true, if (editing == null) "Treino do coach" else "Editar treino", onDismiss, confirm = if (reviewing) "Salvar" else null, confirmEnabled = lines.isNotEmpty(),
            onConfirm = { save(); onDismiss() }) {
        if (!reviewing) {
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Box(Modifier.size(68.dp).background(GMColors.streak.copy(alpha = 0.15f), CircleShape), contentAlignment = Alignment.Center) {
                    Icon(TrainIcons.of("flame.fill"), null, tint = GMColors.streak, modifier = Modifier.size(30.dp))
                }
                Text("Traga o treino do coach", color = Color.White, fontSize = 24.sp, fontWeight = FontWeight.Bold)
                Text("O app separa aquecimento, força e WOD e deixa o cronômetro pronto para quando você chegar no box.", color = GMColors.dim,
                     style = GMType.subheadline, textAlign = TextAlign.Center)
            }
            GMCard {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Icon(TrainIcons.of("doc.on.clipboard"), null, tint = GMColors.accent, modifier = Modifier.width(28.dp))
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text("Texto copiado", color = Color.White, style = GMType.headline)
                        Text("Copie a mensagem do coach e cole aqui", color = GMColors.dim, style = GMType.caption)
                    }
                    GMButton("Colar", {
                        val clip = context.getSystemService(ClipboardManager::class.java)?.primaryClip
                        val text = clip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.coerceToText(context)?.toString()
                        if (!text.isNullOrBlank()) { raw = text; interpret() } else error = "Nada copiado para colar."
                    }, full = false, small = true)
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Box(Modifier.weight(1f).height(1.dp).background(GMColors.stroke))
                Text("ou digite", color = GMColors.dim, style = GMType.caption)
                Box(Modifier.weight(1f).height(1.dp).background(GMColors.stroke))
            }
            GMTextArea(raw, { raw = it }, "AQUECIMENTO\n3 rounds: 10 air squats\n\nWOD\nAMRAP 15'\n10 wall balls\n10 burpees", 170.dp)
            GMIconLabel("Títulos como AQUECIMENTO, FORÇA e WOD separam as partes.", TrainIcons.of("lightbulb"), GMColors.dim, GMType.caption)
            error?.let { Notice(it, "exclamationmark.circle.fill", GMColors.danger) }
            GMButton("Ler treino", ::interpret, icon = TrainIcons.of("wand.and.stars"), enabled = raw.isNotBlank())
        } else {
            GMCard {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                    Box(Modifier.size(52.dp).background(GMColors.streak.copy(alpha = 0.15f), GMRadius.l), contentAlignment = Alignment.Center) {
                        Icon(TrainIcons.of("flame.fill"), null, tint = GMColors.streak)
                    }
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        androidx.compose.foundation.text.BasicTextField(name, { name = it }, singleLine = true,
                            textStyle = GMType.title3.copy(color = Color.White, fontWeight = FontWeight.Bold), cursorBrush = androidx.compose.ui.graphics.SolidColor(GMColors.accent))
                        Text("${format.name} · ${lines.size} ${if (lines.size == 1) "movimento" else "movimentos"}", color = GMColors.accent, style = GMType.caption.copy(fontWeight = FontWeight.SemiBold))
                    }
                    Icon(TrainIcons.of("pencil"), null, tint = GMColors.dim, modifier = Modifier.size(14.dp))
                }
            }
            if (guessed) Notice("Não achei o formato no texto: confira abaixo.", "exclamationmark.triangle.fill", GMColors.warning)
            GMSection("Quando") {
                GMChoiceChips(listOf(0 to "Hoje", 1 to "Amanhã", 2 to "Outro dia"), dayChoice, { c -> dayChoice = c; if (c < 2) day = today.plusDays(c.toLong()) else pickingDay = true })
                if (dayChoice == 2) { GMDivider(); GMRow("Dia", TrainIcons.of("calendar"), onClick = { pickingDay = true }) { Text(plannedDayText(day.atStartOfDay(zone).toInstant()), color = Color.White, style = GMType.subheadline) } }
            }
            GMSection("Formato") {
                GMChoiceChips(listOf(0 to "For Time", 1 to "AMRAP", 2 to "EMOM", 3 to "Tabata", 4 to "Blocos"), kind, { kind = it })
                GMDivider()
                when (kind) {
                    4 -> {
                        GMChoiceChips(listOf(false to "AMRAP", true to "EMOM"), blocksEmom, { blocksEmom = it })
                        GMTitledStepper("Blocos", blocks.size, { n -> blocks = if (n > blocks.size) blocks + List(n - blocks.size) { blocks.lastOrNull() ?: 3 } else blocks.take(n) }, 2..12)
                        GMTitledStepper("Cada bloco", blocks.firstOrNull() ?: 3, { m -> blocks = blocks.map { m } }, 1..30, format = { "$it min" })
                        GMTitledStepper("Descanso entre eles", blockRest, { blockRest = it }, 0..600, 30, { if (it == 0) "Sem descanso" else WodFormat.restText(it) })
                    }
                    3 -> GMTitledStepper("Rodadas", rounds, { rounds = it }, 1..20)
                    2 -> {
                        GMTitledStepper("A cada", every, { every = it }, 30..300, 30, ::clock)
                        GMTitledStepper("Duração", minutes, { minutes = it }, 0..90, format = { if (it == 0) "Sem fim" else "$it min" })
                    }
                    else -> GMTitledStepper(if (kind == 0) "Time cap" else "Duração", minutes, { minutes = it }, if (kind == 0) 0..90 else 1..90,
                                            format = { if (kind == 0 && it == 0) "Sem limite" else "$it min" })
                }
            }
            val d = draft
            if (d != null && d.variants.size > 1) {
                GMSection("Nível", footer = "O coach mandou o WOD em ${d.variants.size} níveis. O escolhido vai para o cronômetro e os outros ficam salvos no treino. O app lembra o seu nível na próxima vez.") {
                    GMChoiceChips(d.variants.map { it.title to it.title }, d.level ?: "", { lv ->
                        val nd = d.picking(lv); WodRunStore.setPreferredLevel(context, lv); draft = nd; apply(nd.format)
                        linesText = nd.lines.joinToString("\n"); parts = nd.parts; guessed = nd.guessed
                    })
                }
            }
            val names = WodMovements.ids(lines).mapNotNull(Exercises::byID).map { it.name }
            GMSection("WOD", footer = "Um movimento por linha; é o que aparece no cronômetro." + if (names.isEmpty()) "" else "\nReconhecidos: ${names.joinToString(", ")}.") {
                GMTextArea(linesText, { linesText = it }, "10 wall balls\n10 burpees", 120.dp)
            }
            parts.forEachIndexed { i, part ->
                GMCard {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(part.title.uppercase(), color = GMColors.dim, style = GMType.caption.copy(fontWeight = FontWeight.Bold), modifier = Modifier.weight(1f))
                        GMIconButton(TrainIcons.of("trash"), "Tirar ${part.title}", { parts = parts.filterIndexed { k, _ -> k != i } }, size = 28.dp)
                    }
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        for (l in WodParser.expandComplexes(part.lines)) Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            if (!l.startsWith(WodParser.COMPLEX_MARK)) Box(Modifier.size(5.dp).background(GMColors.accent, CircleShape))
                            WodLine(l)
                        }
                    }
                }
            }
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                if (day == today) GMButton("Salvar e começar agora", { val p = save(); nav.wod = p.wod(WodRunStore.preferredLevel(context)); onDismiss() },
                                           icon = TrainIcons.of("play.fill"), enabled = lines.isNotEmpty())
                else {
                    val t = plannedDayText(day.atStartOfDay(zone).toInstant())
                    GMButton("Agendar para ${t.take(1).lowercase() + t.drop(1)}", { save(); onDismiss() }, icon = TrainIcons.of("calendar.badge.plus"), enabled = lines.isNotEmpty())
                }
                if (editing == null) Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { GMTextButton("Usar outro texto", TrainIcons.of("arrow.uturn.backward")) { reviewing = false } }
            }
        }
    }
    if (pickingDay) {
        val state = rememberDatePickerState(initialSelectedDateMillis = day.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli())
        GMSheet({ pickingDay = false }) {
            DatePicker(state, title = null, headline = null, showModeToggle = false, colors = DatePickerDefaults.colors(containerColor = GMColors.bg,
                selectedDayContainerColor = GMColors.accent, selectedDayContentColor = Color.Black, todayDateBorderColor = GMColors.accent, todayContentColor = GMColors.accent))
            GMButton("Confirmar", { state.selectedDateMillis?.let { setDay(Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate()) }; pickingDay = false })
        }
    }
}

/** Plano de WODs atual dentro da cópia (lido na hora de gravar, para não perder o que mudou no meio) */
private object TrainCopyRaw {
    fun planned(copy: kotlinx.serialization.json.JsonObject): String? {
        val st = com.alonsoalmeida.gymbros.data.train.TrainCopy.settings(copy)
        return st[WodPlan.KEY] as? String ?: ((copy["settings"] as? kotlinx.serialization.json.JsonObject)?.get(WodPlan.KEY) as? kotlinx.serialization.json.JsonPrimitive)?.content
    }
}

@Composable
private fun Notice(text: String, icon: String, tint: Color) {
    GMIconLabel(text, TrainIcons.of(icon), tint, GMType.subheadline.copy(fontWeight = FontWeight.SemiBold),
                Modifier.fillMaxWidth().background(tint.copy(alpha = 0.12f), GMRadius.m).padding(12.dp))
}

/** Todos os WODs importados e feitos, por mês (WodTimeline.swift) */
@Composable
internal fun WodTimelineScreen(env: AppEnv, data: TrainData, nav: TrainNav) {
    var filter by remember { mutableIntStateOf(0) }
    val now = Instant.now()
    val zone = ZoneId.systemDefault()
    val all = WodTimelineEntry.build(WodPlan.all(data.plannedRaw), data.wods)
    val shown = all.filter { e -> when (filter) { 1 -> e.status(now, zone) == WodTimelineEntry.Status.DONE; 2 -> e.status(now, zone) != WodTimelineEntry.Status.DONE; else -> true } }
    GMScreen("Meus WODs", bottomInset = 120.dp, leading = { BackButton(nav) }, trailing = { GMIconButton(TrainIcons.of("plus"), "Importar WOD do coach", { nav.importing = true }) }) {
        Text("Tudo que você importou do coach e o que já treinou", color = GMColors.dim, style = GMType.subheadline)
        val done = all.filter { it.status(now, zone) == WodTimelineEntry.Status.DONE }
        Row(Modifier.fillMaxWidth().background(GMColors.card, GMRadius.card).padding(vertical = 14.dp)) {
            for ((v, l, c) in listOf(Triple("${done.size}", "feitos", GMColors.accent),
                                     Triple("${done.count { it.day.atZone(zone).let { d -> d.year == now.atZone(zone).year && d.month == now.atZone(zone).month } }}", "este mês", GMColors.streak),
                                     Triple("${all.count { it.plan != null }}", "importados", GMColors.info))) {
                Column(Modifier.weight(1f).semantics(mergeDescendants = true) {}, horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(v, color = c, fontSize = 24.sp, fontWeight = FontWeight.ExtraBold)
                    Text(l, color = GMColors.dim, style = GMType.caption)
                }
            }
        }
        GMSegmented(listOf(0 to "Todos", 1 to "Feitos", 2 to "Não feitos"), filter, { filter = it })
        if (shown.isEmpty()) GMEmptyState(TrainIcons.of("flame"), if (all.isEmpty()) "Nenhum WOD ainda" else "Nada por aqui",
                                         if (all.isEmpty()) "Importe o WOD do coach (texto) e ele aparece aqui, no dia dele." else "Mude o filtro para ver os outros.")
        val months = LinkedHashMap<String, MutableList<WodTimelineEntry>>()
        for (e in shown) months.getOrPut(fmt(e.day, "MMMM 'de' yyyy").replaceFirstChar { it.uppercase() }) { mutableListOf() } += e
        for ((month, list) in months) Column {
            Text(month.uppercase(), color = GMColors.dim, style = GMType.caption.copy(fontWeight = FontWeight.Bold, letterSpacing = 0.6.sp), modifier = Modifier.padding(start = 4.dp, bottom = 10.dp))
            list.forEachIndexed { i, e -> TimelineRow(e, i == list.size - 1, now, zone, nav) }
        }
    }
}

@Composable
private fun TimelineRow(e: WodTimelineEntry, last: Boolean, now: Instant, zone: ZoneId, nav: TrainNav) {
    val status = e.status(now, zone)
    val tint = when (status) { WodTimelineEntry.Status.DONE -> GMColors.accent; WodTimelineEntry.Status.TODAY -> GMColors.streak
                               WodTimelineEntry.Status.SCHEDULED -> GMColors.info; WodTimelineEntry.Status.MISSED -> GMColors.dim }
    Row(Modifier.height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Column(Modifier.width(40.dp).padding(top = 10.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(fmt(e.day, "d"), color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.ExtraBold)
            Text(fmt(e.day, "EEE").replace(".", "").uppercase(), color = GMColors.dim, fontSize = 10.sp, fontWeight = FontWeight.Bold)
        }
        Column(Modifier.width(12.dp).fillMaxHeight(), horizontalAlignment = Alignment.CenterHorizontally) {
            Box(Modifier.padding(top = 16.dp).size(12.dp).background(tint, CircleShape).border(3.dp, GMColors.bg, CircleShape))
            Box(Modifier.width(2.dp).weight(1f).background(if (last) Color.Transparent else GMColors.track))
        }
        val click: (() -> Unit)? = e.plan?.let { p -> { nav.plan = p.id } } ?: e.results.firstOrNull()?.let { r -> Wod.byID(r.wodID)?.let { { nav.push("wod/${it.id}") } } }
        Column(Modifier.weight(1f).padding(bottom = 12.dp).then(if (click != null) Modifier.gmPress(onClick = click) else Modifier)
                   .background(GMColors.card, GMRadius.l).border(1.5.dp, if (status == WodTimelineEntry.Status.TODAY) tint.copy(alpha = 0.6f) else Color.Transparent, GMRadius.l)
                   .padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(e.name, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.Bold), maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                Text(e.format, color = GMColors.streak, style = GMType.caption2.copy(fontWeight = FontWeight.Bold),
                     modifier = Modifier.background(GMColors.streak.copy(alpha = 0.15f), CircleShape).padding(horizontal = 7.dp, vertical = 3.dp))
            }
            if (e.lines.isNotEmpty()) Text(e.lines.take(3).joinToString(" · "), color = GMColors.dim, style = GMType.caption, maxLines = 2, overflow = TextOverflow.Ellipsis)
            val label = when (status) {
                WodTimelineEntry.Status.DONE -> { val r = e.results[0]; "Feito · " + resultText(r) + if (e.results.size > 1) " · ${e.results.size}×" else "" }
                WodTimelineEntry.Status.TODAY -> "Hoje"
                WodTimelineEntry.Status.SCHEDULED -> "Agendado"
                WodTimelineEntry.Status.MISSED -> "Não registrado"
            }
            GMIconLabel(label, TrainIcons.of(when (status) { WodTimelineEntry.Status.DONE -> "checkmark.circle.fill"; WodTimelineEntry.Status.TODAY -> "flame.fill"
                                                           WodTimelineEntry.Status.SCHEDULED -> "calendar"; WodTimelineEntry.Status.MISSED -> "minus.circle" }), tint)
        }
    }
}
