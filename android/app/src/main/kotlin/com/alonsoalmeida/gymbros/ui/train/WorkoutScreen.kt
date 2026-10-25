@file:OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)

package com.alonsoalmeida.gymbros.ui.train

import android.content.Context
import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.isImeVisible
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.alonsoalmeida.gymbros.data.train.RestAlarm
import com.alonsoalmeida.gymbros.data.train.TrainCopy
import com.alonsoalmeida.gymbros.data.train.TrainData
import com.alonsoalmeida.gymbros.data.train.TrainEdits
import com.alonsoalmeida.gymbros.data.map.GymLocation
import com.alonsoalmeida.gymbros.data.train.TrainHooks
import com.alonsoalmeida.gymbros.data.train.TrainScope
import com.alonsoalmeida.gymbros.domain.ActivityKind
import com.alonsoalmeida.gymbros.domain.ActivityText
import com.alonsoalmeida.gymbros.domain.Attribute
import com.alonsoalmeida.gymbros.domain.AttributeSplit
import com.alonsoalmeida.gymbros.domain.RuleClock
import com.alonsoalmeida.gymbros.domain.home.HomeData
import com.alonsoalmeida.gymbros.domain.home.LogPreview
import com.alonsoalmeida.gymbros.domain.roundHalfAwayFromZero
import com.alonsoalmeida.gymbros.domain.train.Deload
import com.alonsoalmeida.gymbros.domain.train.Exercise
import com.alonsoalmeida.gymbros.domain.train.ExerciseType
import com.alonsoalmeida.gymbros.domain.train.Exercises
import com.alonsoalmeida.gymbros.domain.train.LoggedSet
import com.alonsoalmeida.gymbros.domain.train.Progression
import com.alonsoalmeida.gymbros.domain.train.Session
import com.alonsoalmeida.gymbros.domain.train.SessionLog
import com.alonsoalmeida.gymbros.domain.train.Swap
import com.alonsoalmeida.gymbros.domain.train.TrainSplit
import com.alonsoalmeida.gymbros.domain.train.TrainingGoal
import com.alonsoalmeida.gymbros.domain.train.WorkoutStart
import com.alonsoalmeida.gymbros.domain.train.clock
import com.alonsoalmeida.gymbros.domain.train.meters
import com.alonsoalmeida.gymbros.domain.train.muscleLoad
import com.alonsoalmeida.gymbros.ui.AppEnv
import com.alonsoalmeida.gymbros.ui.components.GMAction
import com.alonsoalmeida.gymbros.ui.components.GMActions
import com.alonsoalmeida.gymbros.ui.components.GMButton
import com.alonsoalmeida.gymbros.ui.components.GMButtonKind
import com.alonsoalmeida.gymbros.ui.components.GMCard
import com.alonsoalmeida.gymbros.ui.components.GMCompactStepper
import com.alonsoalmeida.gymbros.ui.components.GMDivider
import com.alonsoalmeida.gymbros.ui.components.GMDurationWheel
import com.alonsoalmeida.gymbros.ui.components.GMEffortPicker
import com.alonsoalmeida.gymbros.ui.components.GMEmptyState
import com.alonsoalmeida.gymbros.ui.components.GMFullScreen
import com.alonsoalmeida.gymbros.ui.components.GMIconButton
import com.alonsoalmeida.gymbros.ui.components.GMIconLabel
import com.alonsoalmeida.gymbros.ui.components.GMModal
import com.alonsoalmeida.gymbros.ui.components.GMOutlinedCard
import com.alonsoalmeida.gymbros.ui.components.GMPrompt
import com.alonsoalmeida.gymbros.ui.components.GMSection
import com.alonsoalmeida.gymbros.ui.components.GMSegmented
import com.alonsoalmeida.gymbros.ui.components.GMSheet
import com.alonsoalmeida.gymbros.ui.components.GMTintIconButton
import com.alonsoalmeida.gymbros.ui.components.GMToggle
import com.alonsoalmeida.gymbros.ui.components.MonsterSprite
import com.alonsoalmeida.gymbros.ui.components.Symbols
import com.alonsoalmeida.gymbros.ui.components.TrainIcons
import com.alonsoalmeida.gymbros.ui.components.gmPress
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMRadius
import com.alonsoalmeida.gymbros.ui.theme.GMType
import com.alonsoalmeida.gymbros.ui.theme.color
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId

/**
 * Treino em andamento (Train/WorkoutView.swift): lista ou guiado, séries com carga e reps, descanso com cronômetro,
 * superset, aquecimento, troca de exercício, objetivo, notas e conclusão. O treino aberto fica na cópia da conta sem
 * `end` (como no iOS): fechar o app ou minimizar não perde nada, e o iPhone vê o mesmo treino.
 * Ficam de fora no Android: Live Activity, relógio, modo fone (aviso falado) e "ao vivo para os amigos".
 */
@Composable
internal fun WorkoutScreen(env: AppEnv, home: HomeData, data: TrainData, id: String, onDismiss: () -> Unit) {
    var session by remember(id) { mutableStateOf<Session?>(null) }
    LaunchedEffect(data, id) {
        if (session == null) data.sessions.firstOrNull { it.uuid == id }?.let { session = it }
    }
    val s = session
    GMFullScreen(true, onDismiss) {
        if (s == null) {
            GMEmptyState(TrainIcons.of("dumbbell"), "Abrindo o treino…", "")
            return@GMFullScreen
        }
        WorkoutContent(env, home, data, s, { session = it }, onDismiss)
    }
}

private fun prefs(c: Context) = c.getSharedPreferences("gymbros-train", Context.MODE_PRIVATE)

@Composable
private fun WorkoutContent(env: AppEnv, home: HomeData, data: TrainData, session: Session, update: (Session) -> Unit, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val haptic = LocalHapticFeedback.current
    val view = LocalView.current
    val scope = rememberCoroutineScope()
    val history: List<SessionLog> = remember(data.sessions) { data.finished.filter { it.uuid != session.uuid }.sortedBy { it.start }.map { it.log } }

    // Tela acesa durante o treino (isIdleTimerDisabled do iOS)
    DisposableEffect(Unit) { view.keepScreenOn = true; onDispose { view.keepScreenOn = false } }

    // Grava na cópia da conta pouco depois de cada mudança e ao minimizar
    val latest by rememberUpdatedState(session)
    var saved by remember { mutableStateOf(session) }
    // Concluído ou descartado: nada mais deste treino é gravado por aqui
    var closed by remember { mutableStateOf(false) }
    val isClosed by rememberUpdatedState(closed)
    LaunchedEffect(session) { if (session != saved && !closed) { delay(700); if (!isClosed) { saved = session; persistOpen(env, session) } } }
    DisposableEffect(session.uuid) { onDispose { if (!isClosed && latest != saved && latest.end == null) persistOpen(env, latest) } }
    // Encerrado fora desta tela (saída da academia ou no iPhone) ou descartado: fecha sem gravar por cima
    LaunchedEffect(data.sessions) {
        if (!closed && data.sessions.none { it.uuid == session.uuid && it.end == null }) { closed = true; RestAlarm.cancel(context); onDismiss() }
    }

    // Relógio da tela (cronômetro e descanso), lido só nos pedaços que mudam
    var nowMs by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) { while (true) { nowMs = System.currentTimeMillis(); delay(250) } }

    var guided by remember { mutableStateOf(prefs(context).getBoolean("guidedWorkout", false)) }
    var collapsed by remember { mutableStateOf(setOf<String>()) }
    var picking by remember { mutableStateOf(false) }
    var finishing by remember { mutableStateOf(false) }
    var confirmDiscard by remember { mutableStateOf(false) }
    var info by remember { mutableStateOf<Exercise?>(null) }
    var exerciseMenu by remember { mutableStateOf<String?>(null) }
    var setMenu by remember { mutableStateOf<String?>(null) }
    var confirmRemove by remember { mutableStateOf<String?>(null) }
    var goalFor by remember { mutableStateOf<String?>(null) }
    var swapping by remember { mutableStateOf<String?>(null) }
    var historyFor by remember { mutableStateOf<String?>(null) }
    var platesFor by remember { mutableStateOf<Double?>(null) }
    var noteFor by remember { mutableStateOf<String?>(null) }
    var noteText by remember { mutableStateOf("") }
    var restPicker by remember { mutableStateOf<String?>(null) } // "" = descanso agora; id = padrão do exercício
    var restDraft by remember { mutableIntStateOf(90) }
    var choosingPlace by remember { mutableStateOf(false) }
    var guidedFocus by remember { mutableStateOf<String?>(null) }
    var guidedLast by remember { mutableStateOf<String?>(null) }
    val listState = rememberLazyListState()

    BackHandler { onDismiss() }

    fun startRest(seconds: Int, keepTotal: Boolean = false, base: Session = latest): Session {
        if (seconds <= 0) return base
        val end = Instant.now().plusSeconds(seconds.toLong())
        RestAlarm.schedule(context, end, data.restNotification)
        return base.copy(restEnd = end, restTotal = if (keepTotal) maxOf(base.restTotal, seconds) else seconds)
    }
    fun cancelRest(base: Session = latest): Session { RestAlarm.cancel(context); return base.copy(restEnd = null) }

    // Vibra e fecha o descanso quando ele acaba
    LaunchedEffect(session.restEnd) {
        val end = session.restEnd ?: return@LaunchedEffect
        val left = end.toEpochMilli() - System.currentTimeMillis()
        if (left <= 0) return@LaunchedEffect
        delay(left)
        if (latest.restEnd == end) { haptic.performHapticFeedback(HapticFeedbackType.LongPress); update(latest.copy(restEnd = null)) }
    }

    /** Terminou todas as séries de um exercício: recolhe e rola até o próximo que falta */
    fun setToggled(s: Session, id: String): Session {
        val sets = s.setsOf(id)
        val cur = s.currentExerciseID
        if (cur != null && cur != id && cur in s.group(id) && !sets.all { it.done }) {
            collapsed = collapsed - cur
            scope.launch { delay(350); listState.animateScrollToItem(s.exerciseIDs.indexOf(cur).coerceAtLeast(0)) }
            return s
        }
        if (sets.isEmpty() || !sets.all { it.done }) return s
        collapsed = collapsed + id
        val ids = s.exerciseIDs
        val i = ids.indexOf(id)
        if (i < 0) return s
        val next = (ids.drop(i + 1) + ids.take(i)).firstOrNull { e -> !s.setsOf(e).all { it.done } } ?: return s
        collapsed = collapsed - next
        scope.launch { delay(350); listState.animateScrollToItem(ids.indexOf(next)) }
        return s.copy(currentExerciseID = next)
    }

    /** Marcou ou desmarcou uma série */
    fun toggled(key: String, done: Boolean) {
        var s = latest.updating(key) { it.copy(done = done) }
        val set = s.sets.first { it.key == key }
        if (done) {
            // Superset: vai para o próximo do bloco sem descanso
            val (adv, rest) = s.advance(set.exerciseID)
            s = if (rest) startRest(set.rest, base = adv) else cancelRest(adv)
            s = setToggled(s, set.exerciseID)
            guidedLast = key
            guidedFocus = null
        } else s = cancelRest(s)
        update(s)
    }

    fun swap(old: String, new: Exercise) {
        val work = latest.orderedSets.filter { it.exerciseID == old && !it.done && !it.warmup }
        var sug = Progression.suggest(new.id, work.size, work.firstOrNull()?.targetReps ?: 10, history)
        if (latest.isDeload) sug = Deload.apply(sug, work.size, new.id).first
        update(latest.swapPending(old, new.id, sug))
        collapsed = collapsed - new.id
    }

    fun setGoal(g: TrainingGoal?, id: String) {
        val m = data.goals.toMutableMap().apply { if (g == null) remove(id) else put(id, g.raw) }
        TrainingGoal.goals = m
        TrainScope.edit(env) { TrainEdits.text(it, TrainingGoal.KEY, TrainingGoal.encode(m)) }
        val pending = latest.orderedSets.filter { it.exerciseID == id && !it.warmup && !it.done }
        val sug = Progression.suggest(id, pending.size, pending.firstOrNull()?.targetReps ?: 10, history)
        val keys = pending.map { it.key }.toSet()
        update(latest.copy(sets = latest.sets.map {
            if (it.key !in keys) it else it.copy(reps = sug.reps, targetReps = sug.reps, rest = g?.rest ?: it.rest, weight = if (sug.weight > 0 && it.weight == 0.0) sug.weight else it.weight)
        }))
    }

    val resting = session.restEnd?.let { it.toEpochMilli() > nowMs } ?: false

    Box(Modifier.fillMaxSize().imePadding()) {
        Column(Modifier.fillMaxSize()) {
            // Cabeçalho: minimizar, título e cronômetro, concluir
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                GMIconButton(TrainIcons.of("chevron.down"), "Minimizar treino", onDismiss)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                    Text(session.title, color = Color.White, style = GMType.headline, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(clock(maxOf(((nowMs - session.start.toEpochMilli()) / 1000).toInt(), 0)), color = GMColors.accent,
                         style = GMType.subheadline.copy(fontFeatureSettings = "tnum"))
                }
                GMButton("Concluir", { finishing = true }, icon = TrainIcons.of("checkmark"), full = false, small = true)
            }
            // Onde está treinando e o bro que treina com você
            Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                val gym = data.gyms.firstOrNull { it.first == session.gymUUID }
                GMIconLabel(gym?.second ?: if (session.placeAsked) "Sem local" else "Onde você está?", TrainIcons.of("mappin.and.ellipse"),
                            if (gym != null) GMColors.accent else Color.White,
                            modifier = Modifier.heightIn(min = 32.dp).gmPress { choosingPlace = true }
                                .background(if (gym != null) GMColors.accent.copy(alpha = 0.18f) else GMColors.raised, CircleShape).padding(horizontal = 12.dp, vertical = 6.dp))
                Spacer(Modifier.weight(1f))
                Row(Modifier.background(GMColors.accent.copy(alpha = 0.12f), CircleShape).border(1.dp, GMColors.accent.copy(alpha = 0.4f), CircleShape)
                        .padding(start = 6.dp, end = 10.dp, top = 3.dp, bottom = 3.dp).clearAndSetSemantics { contentDescription = "Treinando com ${home.monsterName}" },
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    MonsterSprite(home.snapshot.form, Modifier.size(22.dp))
                    Text(home.monsterName, color = Color.White, style = GMType.caption.copy(fontWeight = FontWeight.Bold), maxLines = 1)
                }
            }
            if (session.exerciseIDs.isNotEmpty()) {
                GMSegmented(listOf(false to "Lista", true to "Guiado"), guided, { guided = it; prefs(context).edit().putBoolean("guidedWorkout", it).apply() },
                            Modifier.padding(start = 16.dp, end = 16.dp, bottom = 6.dp))
            }
            val bottom = if (resting) 180.dp else 90.dp
            if (guided && session.exerciseIDs.isNotEmpty()) {
                Column(Modifier.verticalScroll(rememberScrollState()).padding(16.dp).padding(bottom = bottom)) {
                    GuidedContent(session, history, guidedFocus, guidedLast, onFocus = { k, ex -> guidedFocus = k; update(latest.copy(currentExerciseID = ex)) },
                                  onToggle = ::toggled, onUpdate = update, onUndo = { k ->
                                      val set = latest.sets.firstOrNull { it.key == k } ?: return@GuidedContent
                                      update(cancelRest(latest.updating(k) { it.copy(done = false) }).copy(currentExerciseID = set.exerciseID))
                                      guidedFocus = k; guidedLast = null
                                  }, onMenu = { setMenu = it }, onRemove = { update(WorkoutStart.removeSet(latest, it)) }, onInfo = { info = it })
                }
            } else {
                LazyColumn(Modifier.fillMaxSize(), state = listState, contentPadding = androidx.compose.foundation.layout.PaddingValues(start = 16.dp, end = 16.dp, top = 16.dp, bottom = bottom),
                           verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    if (session.exerciseIDs.isEmpty()) item(key = "empty") {
                        GMEmptyState(TrainIcons.of("dumbbell"), "Treino vazio", "Toque em + Exercício, aqui embaixo, para começar.")
                    }
                    val ids = session.exerciseIDs
                    ids.forEachIndexed { i, exID ->
                        item(key = exID) {
                            Column {
                                ExerciseCard(session, exID, history, data.notes[exID], exID in collapsed,
                                             onCollapse = { collapsed = if (exID in collapsed) collapsed - exID else collapsed + exID },
                                             onCurrent = { haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove); update(latest.copy(currentExerciseID = exID)); collapsed = collapsed - exID },
                                             onMenu = { exerciseMenu = exID }, onInfo = { info = it },
                                             onNote = { noteText = data.notes[exID].orEmpty(); noteFor = exID },
                                             onUpdate = update, onToggle = ::toggled, onSetMenu = { setMenu = it },
                                             onRemoveSet = { update(WorkoutStart.removeSet(latest, it)); haptic.performHapticFeedback(HapticFeedbackType.LongPress) })
                                if (session.linkedNext(exID) && i < ids.size - 1) {
                                    // Elo do superset
                                    Box(Modifier.fillMaxWidth().offset(y = 2.dp), contentAlignment = Alignment.Center) {
                                        Box(Modifier.size(28.dp).background(GMColors.info.copy(alpha = 0.2f), CircleShape), contentAlignment = Alignment.Center) {
                                            Icon(TrainIcons.of("link"), "Superset", tint = GMColors.info, modifier = Modifier.size(14.dp))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Descanso e ações sempre à mão, sem rolar até o fim; com o teclado aberto saem da frente (no iOS ficam atrás dele)
        if (!androidx.compose.foundation.layout.WindowInsets.isImeVisible) Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            val end = session.restEnd
            if (resting && end != null) {
                val left = ((end.toEpochMilli() - nowMs + 999) / 1000).toInt().coerceAtLeast(0)
                RestBar(left, session.restTotal, onPick = { restDraft = maxOf(left / 5 * 5, 5); restPicker = "" },
                        onMinus = { val l = left - 15; update(if (l <= 0) cancelRest() else startRest(l, keepTotal = true)) },
                        onPlus = { update(startRest(left + 15, keepTotal = true)) }, onSkip = { update(cancelRest()) })
            }
            val all = session.exerciseIDs
            val allCollapsed = all.isNotEmpty() && all.all { it in collapsed }
            Row(Modifier.fillMaxWidth().background(Brush.verticalGradient(listOf(GMColors.bg.copy(alpha = 0f), GMColors.bg, GMColors.bg)))
                    .padding(start = 16.dp, end = 16.dp, top = 10.dp, bottom = 6.dp), horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically) {
                GMButton("Exercício", { picking = true }, Modifier.weight(1f), icon = TrainIcons.of("plus"), kind = GMButtonKind.SECONDARY)
                GMIconButton(TrainIcons.of(if (allCollapsed) "arrow.up.left.and.arrow.down.right" else "arrow.down.right.and.arrow.up.left"),
                             if (allCollapsed) "Expandir exercícios" else "Recolher exercícios", { collapsed = if (allCollapsed) emptySet() else all.toSet() }, size = 48.dp)
                GMTintIconButton(TrainIcons.of("trash"), "Descartar treino", GMColors.danger, { confirmDiscard = true }, size = 48.dp)
            }
        }
    }

    // Folhas, menus e modais
    ExercisePickerModal(picking, env, data, onPick = { ex ->
        update(WorkoutStart.add(latest, ex, history)); collapsed = collapsed - ex.id
        scope.launch { delay(400); listState.animateScrollToItem(latest.exerciseIDs.indexOf(ex.id).coerceAtLeast(0)) }
    }) { picking = false }
    swapping?.let { old -> SwapModal(old, session.exerciseIDs.toSet(), history, { info = it }, { swap(old, it) }) { swapping = null } }
    info?.let { ExerciseInfoModal(env, data, it) { info = null } }
    historyFor?.let { id ->
        val local = remember(id) { TrainNav().apply { stack = listOf("exercise/$id") } }
        if (local.stack.isEmpty()) historyFor = null
        GMFullScreen(true, { historyFor = null }) { ExerciseDetailScreen(env, data, id, local) }
    }
    if (finishing) FinishWorkoutModal(env, home, data, session, history, { finishing = false }) { done ->
        RestAlarm.cancel(context)
        closed = true
        finishing = false
        onDismiss()
    }
    GMActions(confirmDiscard, { confirmDiscard = false }, title = "Descartar este treino?", message = "Nada dele será salvo.", actions = listOf(
        GMAction("Descartar", TrainIcons.of("trash"), true) {
            RestAlarm.cancel(context)
            closed = true
            TrainScope.edit(env) { TrainEdits.deleteSession(it, session.uuid) }
            onDismiss()
        }))
    val em = exerciseMenu
    GMActions(em != null, { exerciseMenu = null }, title = em?.let(Exercises::name), actions = em?.let { id -> exerciseActions(id, session, data,
        onInfo = { info = it }, onPlates = { platesFor = it }, onRest = { r -> restDraft = r; restPicker = id },
        onSuperset = { on -> update(latest.setLinkedNext(id, on)) }, onWarmup = { ex -> update(WorkoutStart.addWarmup(latest, ex)); collapsed = collapsed - id },
        onRemoveWarmup = { update(WorkoutStart.removeWarmup(latest, id)) }, onGoal = { goalFor = id }, onSwap = { swapping = id },
        onHistory = { historyFor = id }, onNote = { noteText = data.notes[id].orEmpty(); noteFor = id }, onRemove = { confirmRemove = id }) }.orEmpty())
    val sm = session.sets.firstOrNull { it.key == setMenu }
    GMActions(sm != null, { setMenu = null }, title = sm?.let { "${Exercises.name(it.exerciseID)} · ${if (it.warmup) "aquecimento" else "série"}" },
              actions = sm?.let { set ->
                  val last = session.sets.none { it.exerciseID == set.exerciseID && it.key != set.key }
                  listOf(GMAction("Duplicar série", TrainIcons.of("square.stack")) { update(WorkoutStart.duplicateSet(latest, set.key)) },
                         GMAction(if (last) "Remover série (o exercício sai do treino)" else "Remover série", TrainIcons.of("trash"), true) {
                             update(WorkoutStart.removeSet(latest, set.key))
                         })
              }.orEmpty())
    val cr = confirmRemove
    GMActions(cr != null, { confirmRemove = null }, title = cr?.let { "Remover ${Exercises.name(it)}?" }, message = "As séries dele neste treino, feitas ou não, saem do treino.",
              actions = cr?.let { listOf(GMAction("Remover", TrainIcons.of("trash"), true) { update(WorkoutStart.removeExercise(latest, it)) }) }.orEmpty())
    val gf = goalFor
    GMActions(gf != null, { goalFor = null }, title = "Objetivo",
              message = "Define a faixa de reps e como a carga sobe: +1 rep por treino até o topo da faixa, depois +carga e volta ao início.",
              actions = gf?.let { id -> TrainingGoal.entries.map { g -> GMAction(g.fullLabel, TrainIcons.of("target")) { setGoal(g, id) } } +
                  GMAction("Sem objetivo (reps fixas)", TrainIcons.of("xmark")) { setGoal(null, id) } }.orEmpty())
    platesFor?.let { total -> GMSheet({ platesFor = null }) { PlateCalculator(env, data, total) } }
    GMPrompt(noteFor != null, "Nota do exercício", noteText, { noteText = it }, "Ex.: banco na posição 4", { noteFor = null }, {
        val id = noteFor ?: return@GMPrompt
        TrainScope.edit(env) { TrainEdits.saveNote(it, id, noteText, Instant.now()) }
    }, message = "Ajuste da máquina, pegada, o que lembrar da próxima vez.")
    val rp = restPicker
    if (rp != null) GMSheet({ restPicker = null }) {
        Text(if (rp.isEmpty()) "Descanso agora" else "Descanso · ${Exercises.name(rp)}", color = Color.White, style = GMType.headline)
        GMDurationWheel(restDraft, { restDraft = it })
        if (rp.isNotEmpty()) Text("Vale para as próximas séries deste exercício neste treino.", color = GMColors.dim, style = GMType.caption)
        GMButton("Confirmar", {
            if (rp.isNotEmpty()) update(latest.copy(sets = latest.sets.map { if (it.exerciseID == rp && !it.done) it.copy(rest = restDraft) else it }))
            else update(if (restDraft > 0) startRest(restDraft) else cancelRest())
            restPicker = null
        })
    }
    if (choosingPlace) GMSheet({ choosingPlace = false }) {
        Text("Onde você está?", color = Color.White, style = GMType.headline)
        for ((gid, name) in data.gyms) GMButton(name, { update(latest.copy(gymUUID = gid, placeAsked = true)); choosingPlace = false },
                                                icon = TrainIcons.of("dumbbell"), kind = GMButtonKind.SECONDARY)
        GMButton("Sem local", { update(latest.copy(gymUUID = null, placeAsked = true)); choosingPlace = false }, icon = TrainIcons.of("xmark"), kind = GMButtonKind.SECONDARY)
    }
}

/** Ações do menu do exercício (WorkoutView.swift `exerciseActions`) */
private fun exerciseActions(id: String, session: Session, data: TrainData, onInfo: (Exercise) -> Unit, onPlates: (Double) -> Unit, onRest: (Int) -> Unit,
                            onSuperset: (Boolean) -> Unit, onWarmup: (Exercise) -> Unit, onRemoveWarmup: () -> Unit, onGoal: () -> Unit, onSwap: () -> Unit,
                            onHistory: () -> Unit, onNote: () -> Unit, onRemove: () -> Unit): List<GMAction> = buildList {
    val ex = Exercises.byID(id)
    if (ex != null) {
        add(GMAction("Ver como fazer", TrainIcons.of("info.circle")) { onInfo(ex) })
        if (ex.type == ExerciseType.WEIGHTED) {
            val w = session.orderedSets.lastOrNull { it.exerciseID == id }?.weight ?: 60.0
            add(GMAction("Calcular anilhas", TrainIcons.of("circle.grid.2x1")) { onPlates(if (ex.weightIncludesBar(session.isCrossfit)) w else w + data.barWeight) })
        }
    }
    val rest = session.orderedSets.firstOrNull { it.exerciseID == id && !it.done }?.rest ?: session.orderedSets.lastOrNull { it.exerciseID == id }?.rest ?: 90
    add(GMAction("Tempo de descanso (${clock(rest)})", TrainIcons.of("timer")) { onRest(rest) })
    val ids = session.exerciseIDs
    val i = ids.indexOf(id)
    if (i >= 0 && i < ids.size - 1) {
        val on = session.linkedNext(id)
        add(GMAction(if (on) "Separar de ${Exercises.name(ids[i + 1])}" else "Superset com ${Exercises.name(ids[i + 1])}", TrainIcons.of("link")) { onSuperset(!on) })
    }
    val sets = session.setsOf(id)
    if (sets.any { it.warmup }) add(GMAction("Tirar aquecimento", TrainIcons.of("flame")) { onRemoveWarmup() })
    else if (ex != null && ex.type == ExerciseType.WEIGHTED && (sets.firstOrNull()?.weight ?: 0.0) > 0) add(GMAction("Adicionar aquecimento", TrainIcons.of("flame")) { onWarmup(ex) })
    if (ex?.type == ExerciseType.WEIGHTED) add(GMAction("Objetivo: ${TrainingGoal.of(id)?.fullLabel ?: "nenhum"}", TrainIcons.of("target")) { onGoal() })
    if (session.pending(id)) add(GMAction("Trocar exercício (aparelho ocupado)", TrainIcons.of("arrow.triangle.swap")) { onSwap() })
    add(GMAction("Histórico de cargas", TrainIcons.of("chart.line.uptrend.xyaxis")) { onHistory() })
    add(GMAction(if (data.notes[id].isNullOrEmpty()) "Adicionar nota" else "Editar nota", TrainIcons.of("note.text")) { onNote() })
    add(GMAction("Remover exercício", TrainIcons.of("trash"), true) { onRemove() })
}

/** Card de um exercício no modo lista (WorkoutView.swift `exerciseCard`) */
@Composable
private fun ExerciseCard(session: Session, id: String, history: List<SessionLog>, note: String?, isCollapsed: Boolean, onCollapse: () -> Unit, onCurrent: () -> Unit,
                         onMenu: () -> Unit, onInfo: (Exercise) -> Unit, onNote: () -> Unit, onUpdate: (Session) -> Unit, onToggle: (String, Boolean) -> Unit,
                         onSetMenu: (String) -> Unit, onRemoveSet: (String) -> Unit) {
    val ex = Exercises.byID(id)
    val sets = session.setsOf(id)
    val work = sets.filter { !it.warmup }
    val warmups = sets.size - work.size
    val suggestion = remember(history, id, work.size) { Progression.suggest(id, work.size, work.firstOrNull()?.targetReps ?: 10, history) }
    val group = session.group(id)
    val last = history.lastOrNull { l -> l.sets.any { it.exerciseID == id } }
    val done = sets.count { it.done }
    val complete = sets.isNotEmpty() && done == sets.size
    val current = session.currentExercise == id
    GMOutlinedCard(if (current) GMColors.accent else if (complete) GMColors.accent.copy(alpha = 0.35f) else Color.Transparent, if (current) 2.dp else 1.dp,
                   padding = if (isCollapsed) 12.dp else 16.dp) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            if (ex != null) Box(Modifier.gmPress { onInfo(ex) }) { Thumb(id, if (isCollapsed) 40.dp else 52.dp) }
            // Tocar no nome recolhe ou expande o card
            Row(Modifier.weight(1f).gmPress(onClick = onCollapse), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(ex?.name ?: id, color = Color.White, style = GMType.headline, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        if (complete) Icon(TrainIcons.of("checkmark.circle.fill"), null, tint = GMColors.accent, modifier = Modifier.size(14.dp))
                        Text("$done/${sets.size} séries" + if (isCollapsed) "" else " · " + listOfNotNull(ex?.group?.label, ex?.equipment).joinToString(" · "),
                             color = if (complete) GMColors.accent else GMColors.dim, style = GMType.caption, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
                Icon(TrainIcons.of(if (isCollapsed) "chevron.down" else "chevron.up"), null, tint = GMColors.dim, modifier = Modifier.size(18.dp))
            }
            // Marca o exercício que está fazendo agora
            CircleIcon("play.fill", current, onCurrent, if (current) "Fazendo agora" else "Marcar como fazendo agora")
            GMIconButton(TrainIcons.of("ellipsis"), "Opções de ${ex?.name ?: id}", onMenu, size = 34.dp)
        }
        if (current && !isCollapsed) GMIconLabel("Fazendo agora", TrainIcons.of("dot.radiowaves.left.and.right"), GMColors.accent)
        if (isCollapsed) return@GMOutlinedCard
        if (group.size > 1) GMIconLabel("Superset ${group.indexOf(id) + 1}/${group.size} · descanso depois de ${Exercises.name(group.last())}", TrainIcons.of("link"), GMColors.info)
        if (!note.isNullOrEmpty()) GMIconLabel(note, TrainIcons.of("note.text"), GMColors.note.copy(alpha = 0.9f), GMType.caption, Modifier.gmPress(onClick = onNote))
        val pending = work.filter { !it.done }
        if (suggestion.weight > 0 && pending.isNotEmpty() && pending.all { it.weight == 0.0 }) {
            // Treino aberto antes de registrar o PR (ou carga em branco): preenche com um toque
            val keys = pending.map { it.key }.toSet()
            GMIconLabel("Usar ${Progression.fmt(suggestion.weight)} kg nas séries", TrainIcons.of("wand.and.stars"), Color.Black,
                        GMType.subheadline.copy(fontWeight = FontWeight.Bold),
                        Modifier.gmPress { onUpdate(session.copy(sets = session.sets.map { if (it.key in keys) it.copy(weight = suggestion.weight) else it })) }
                            .background(GMColors.accent, CircleShape).padding(horizontal = 12.dp, vertical = 7.dp))
        }
        val lastMax = last?.sets?.filter { it.exerciseID == id && it.done }?.maxOfOrNull { it.weight }
        if (lastMax != null && suggestion.weight > lastMax) {
            GMIconLabel("Subir para ${Progression.fmt(suggestion.weight)} kg (+${Progression.fmt(suggestion.weight - lastMax)} kg)", TrainIcons.of("arrow.up.circle.fill"),
                        GMColors.accent, GMType.subheadline.copy(fontWeight = FontWeight.Bold),
                        Modifier.background(GMColors.accent.copy(alpha = 0.18f), CircleShape).padding(horizontal = 12.dp, vertical = 7.dp))
        }
        GMIconLabel(suggestion.reason, TrainIcons.of("arrow.up.right"), GMColors.accent.copy(alpha = 0.9f), GMType.caption)
        last?.sets?.filter { it.exerciseID == id && it.done }?.takeIf { it.isNotEmpty() }?.let { prev ->
            Text("Última vez: " + prev.joinToString(", ") { s ->
                if (ex?.type == ExerciseType.DISTANCE) "${meters(s.weight)} em ${clock(s.reps)}"
                else (if (ex?.type == ExerciseType.WEIGHTED || s.weight > 0) "${Progression.fmt(s.weight)}×${s.reps}" else "${s.reps}") + if (s.reps < s.target) "/${s.target}" else ""
            }, color = GMColors.dim, style = GMType.caption2)
        }
        for (s in sets) {
            SetRow(s, if (s.warmup) "A" else "${s.index - warmups + 1}", ex?.type ?: ExerciseType.WEIGHTED, ex?.increment ?: 2.5, ex?.weightUnit(session.isCrossfit) ?: "kg",
                   onChange = { n -> onUpdate(session.updating(s.key) { n }) }, onMenu = { onSetMenu(s.key) }, onRemove = { onRemoveSet(s.key) },
                   onToggle = { onToggle(s.key, it) })
        }
        GMButton("Série", { onUpdate(WorkoutStart.addSet(session, id)) }, icon = TrainIcons.of("plus"), kind = GMButtonKind.SECONDARY, full = false, small = true)
    }
}

/** Uma série: número (menu), carga e reps editáveis, feita; arrastar para a esquerda remove (WorkoutView.swift `SetRow`) */
@Composable
private fun SetRow(set: LoggedSet, label: String, type: ExerciseType, increment: Double, unit: String, onChange: (LoggedSet) -> Unit, onMenu: () -> Unit,
                   onRemove: () -> Unit, onToggle: (Boolean) -> Unit) {
    val haptic = LocalHapticFeedback.current
    var offset by remember(set.key) { mutableStateOf(0f) }
    val reveal = 76f * androidx.compose.ui.platform.LocalDensity.current.density
    val shown by animateFloatAsState(offset, label = "swipe")
    // Fez menos que o planejado (na distância, menos tempo é melhor: nunca "faltou")
    val missed = type != ExerciseType.DISTANCE && !set.warmup && set.reps < set.targetReps
    Box(Modifier.fillMaxWidth().semantics { customActions = listOf(CustomAccessibilityAction("Remover série") { onRemove(); true }) }) {
        if (shown < 0) {
            Box(Modifier.align(Alignment.CenterEnd).width(with(androidx.compose.ui.platform.LocalDensity.current) { maxOf(-shown - 8f, 0f).toDp() }).height(44.dp)
                    .background(GMColors.danger, GMRadius.m).gmPress(onClick = onRemove), contentAlignment = Alignment.Center) {
                Icon(TrainIcons.of("trash.fill"), "Remover série", tint = Color.White)
            }
        }
        Row(Modifier.fillMaxWidth().offset { IntOffset(shown.toInt(), 0) }.background(GMColors.card).alpha(if (set.done) 0.75f else 1f)
                .pointerInput(set.key) {
                    detectHorizontalDragGestures(onDragEnd = {
                        if (offset < -220 * density) { offset = 0f; onRemove() } else offset = if (offset < -reveal / 2) -reveal else 0f
                    }) { _, drag -> offset = minOf(0f, offset + drag) }
                }.padding(vertical = 2.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(Modifier.size(44.dp).gmPress(onClick = onMenu).semantics { contentDescription = "Opções da série $label" }, contentAlignment = Alignment.Center) {
                Box(Modifier.size(26.dp).background(GMColors.raised, CircleShape), contentAlignment = Alignment.Center) {
                    Text(label, color = if (set.warmup) GMColors.streak else GMColors.dim, style = GMType.subheadline.copy(fontWeight = FontWeight.Bold))
                }
            }
            if (type == ExerciseType.DISTANCE) {
                GMCompactStepper(set.weight, { onChange(set.copy(weight = maxOf(it, 0.0))) }, 100.0, "m", editable = true)
                GMCompactStepper(set.reps.toDouble(), { onChange(set.copy(reps = maxOf(it.toInt(), 0))) }, 15.0, "s", editable = true)
            } else {
                // Peso do corpo e isometria aceitam carga extra (cinto, colete, halteres)
                GMCompactStepper(set.weight, { onChange(set.copy(weight = maxOf(it, 0.0))) }, if (type == ExerciseType.WEIGHTED) increment else 2.5,
                                 if (type == ExerciseType.WEIGHTED) unit else "+kg", decimals = true, editable = true)
                // Planejado × feito: a etiqueta mostra a meta
                val unitLabel = if (type == ExerciseType.TIME) "s" else "reps"
                val showTarget = set.targetReps > 0 && set.reps != set.targetReps
                GMCompactStepper(set.reps.toDouble(), { onChange(set.copy(reps = maxOf(it.toInt(), 0))) }, if (type == ExerciseType.TIME) 5.0 else 1.0,
                                 if (showTarget) "de ${set.targetReps}" else unitLabel,
                                 Modifier.border(1.5.dp, if (missed) GMColors.warning.copy(alpha = 0.7f) else Color.Transparent, GMRadius.m), editable = true,
                                 labelColor = if (showTarget) (if (missed) GMColors.warning else GMColors.accent) else GMColors.dim, labelBold = showTarget)
            }
            Spacer(Modifier.weight(1f))
            Box(Modifier.size(44.dp).gmPress {
                haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                onToggle(!set.done)
            }.semantics { contentDescription = if (set.done) "Série feita" else "Marcar série como feita" }, contentAlignment = Alignment.Center) {
                Icon(TrainIcons.of(if (set.done) (if (missed) "checkmark.circle" else "checkmark.circle.fill") else "circle"), null,
                     tint = if (set.done) (if (missed) GMColors.warning else GMColors.accent) else GMColors.dim, modifier = Modifier.size(30.dp))
            }
        }
    }
}

/** Uma série por vez: da última vez, alvo, registrar, anterior/desfazer/próxima (WorkoutView.swift `guidedContent`) */
@Composable
private fun GuidedContent(session: Session, history: List<SessionLog>, focus: String?, lastKey: String?, onFocus: (String, String) -> Unit,
                          onToggle: (String, Boolean) -> Unit, onUpdate: (Session) -> Unit, onUndo: (String) -> Unit, onMenu: (String) -> Unit,
                          onRemove: (String) -> Unit, onInfo: (Exercise) -> Unit) {
    val all = session.orderedSets
    val pending = all.filter { !it.done }
    val cur = session.currentExercise
    val s = all.firstOrNull { it.key == focus } ?: pending.firstOrNull { it.exerciseID == cur } ?: pending.firstOrNull()
    if (s == null) { GMEmptyState(TrainIcons.of("checkmark.seal"), "Todas as séries feitas", "Toque em Concluir para salvar o treino."); return }
    val id = s.exerciseID
    val ex = Exercises.byID(id)
    val mine = all.filter { it.exerciseID == id }
    val pos = mine.indexOfFirst { it.key == s.key } + 1
    val last = history.lastOrNull { l -> l.sets.any { it.exerciseID == id } }?.sets?.filter { it.exerciseID == id && it.done }
    val lastSame = last?.let { it.getOrNull(pos - 1) ?: it.lastOrNull() }
    fun text(w: Double, r: Int) = when (ex?.type ?: ExerciseType.WEIGHTED) {
        ExerciseType.DISTANCE -> "${meters(w)} em ${clock(r)}"
        ExerciseType.TIME -> "$r s" + if (w > 0) " · ${Progression.fmt(w)} kg" else ""
        ExerciseType.BODYWEIGHT -> if (w == 0.0) "$r reps" else "${Progression.fmt(w)} kg × $r"
        else -> "${Progression.fmt(w)} kg × $r"
    }
    Column(Modifier.fillMaxWidth().background(GMColors.card, GMRadius.card).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            if (ex != null) Thumb(id, 56.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(ex?.name ?: id, color = Color.White, style = GMType.title3.copy(fontWeight = FontWeight.Bold), maxLines = 2)
                Text((if (s.warmup) "Aquecimento · " else "") + "Série $pos de ${mine.size}", color = GMColors.dim, style = GMType.subheadline)
            }
            GMIconButton(TrainIcons.of("info.circle"), "Como fazer", { ex?.let(onInfo) }, size = 36.dp)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            GuidedChip("Da última vez", lastSame?.let { text(it.weight, it.reps) } ?: "primeira vez", false, Modifier.weight(1f))
            GuidedChip("Alvo", text(s.weight, s.targetReps), true, Modifier.weight(1f))
        }
        SetRow(s, if (s.warmup) "A" else "$pos", ex?.type ?: ExerciseType.WEIGHTED, ex?.increment ?: 2.5, ex?.weightUnit(session.isCrossfit) ?: "kg",
               onChange = { n -> onUpdate(session.updating(s.key) { n }) }, onMenu = { onMenu(s.key) }, onRemove = { onRemove(s.key) }, onToggle = { onToggle(s.key, it) })
        if (s.done) GMIconLabel("Série registrada", TrainIcons.of("checkmark.circle.fill"), GMColors.accent, GMType.subheadline.copy(fontWeight = FontWeight.Bold))
        else GMButton("Registrar série", { onToggle(s.key, true) }, icon = TrainIcons.of("checkmark"))
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            val i = all.indexOfFirst { it.key == s.key }
            GMButton("Anterior", { all.getOrNull(i - 1)?.let { onFocus(it.key, it.exerciseID) } }, Modifier.weight(1f), icon = TrainIcons.of("chevron.left"),
                     kind = GMButtonKind.SECONDARY, small = true, enabled = i > 0)
            val undo = all.firstOrNull { it.key == lastKey }
            if (undo != null && undo.done) GMButton("Desfazer", { onUndo(undo.key) }, Modifier.weight(1f), icon = TrainIcons.of("arrow.uturn.backward"),
                                                    kind = GMButtonKind.SECONDARY, small = true)
            GMButton("Próxima", { all.getOrNull(i + 1)?.let { onFocus(it.key, it.exerciseID) } }, Modifier.weight(1f), icon = TrainIcons.of("chevron.right"),
                     kind = GMButtonKind.SECONDARY, small = true, enabled = i < all.size - 1)
        }
        val i = all.indexOfFirst { it.key == s.key }
        (all.drop(i + 1) + all.take(i)).firstOrNull { !it.done && it.key != s.key }?.let { next ->
            Text("A seguir: ${Exercises.name(next.exerciseID)} · série ${all.filter { it.exerciseID == next.exerciseID }.indexOfFirst { it.key == next.key } + 1}",
                 color = GMColors.dim, style = GMType.caption)
        }
    }
    Text("${all.count { it.done }} de ${all.size} séries feitas", color = GMColors.dim, style = GMType.caption.copy(fontFeatureSettings = "tnum"),
         modifier = Modifier.fillMaxWidth().padding(top = 8.dp), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
}

@Composable
private fun GuidedChip(title: String, value: String, accent: Boolean, modifier: Modifier) {
    Column(modifier.background(GMColors.raised, GMRadius.m).padding(10.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(title, color = GMColors.dim, style = GMType.caption)
        Text(value, color = if (accent) GMColors.accent else Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.Bold, fontFeatureSettings = "tnum"), maxLines = 1)
    }
}

/** Barra do descanso: anel, tempo (toque abre a roleta), −15, +15 e Pular */
@Composable
private fun RestBar(left: Int, total: Int, onPick: () -> Unit, onMinus: () -> Unit, onPlus: () -> Unit, onSkip: () -> Unit) {
    Row(Modifier.padding(horizontal = 12.dp).fillMaxWidth().background(GMColors.card, GMRadius.card).border(1.dp, GMColors.stroke, GMRadius.card).padding(14.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        val track = Color.White.copy(alpha = 0.12f)
        val accent = GMColors.accent
        Canvas(Modifier.size(36.dp)) {
            drawCircle(track, style = Stroke(4.dp.toPx()))
            drawArc(accent, -90f, 360f * left / maxOf(total, 1), false, style = Stroke(4.dp.toPx(), cap = StrokeCap.Round))
        }
        Column(Modifier.gmPress(onClick = onPick).semantics { contentDescription = "Descanso, faltam ${left / 60} minutos e ${left % 60} segundos. Toque para escolher" }) {
            Text("Descanso", color = GMColors.dim, style = GMType.caption)
            Text(String.format(java.util.Locale.ROOT, "%d:%02d", left / 60, left % 60), color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Bold,
                 style = GMType.title3.copy(fontFeatureSettings = "tnum", textDecoration = TextDecoration.Underline))
        }
        Spacer(Modifier.weight(1f))
        GMIconButton(TrainIcons.of("minus"), "Menos 15 segundos", onMinus, size = 38.dp)
        GMIconButton(TrainIcons.of("plus"), "Mais 15 segundos", onPlus, size = 38.dp)
        GMButton("Pular", onSkip, full = false, small = true)
    }
}

/** Alternativas do mesmo músculo (SwapExercise.swift) */
@Composable
private fun SwapModal(current: String, exclude: Set<String>, history: List<SessionLog>, onInfo: (Exercise) -> Unit, onPick: (Exercise) -> Unit, onDismiss: () -> Unit) {
    val base = Exercises.byID(current)
    val list = remember(current) { base?.let { Swap.ranked(it, Exercises.all, exclude, history) }.orEmpty() }
    val count = remember(history) { Swap.counts(history) }
    GMModal(true, "Trocar ${base?.name.orEmpty()}", onDismiss) {
        Text("Aparelho ocupado? Escolha outro de ${base?.group?.label?.lowercase() ?: "mesmo músculo"}. As séries que faltam passam para ele, com a carga sugerida pelo seu histórico.",
             color = GMColors.dim, style = GMType.subheadline)
        if (list.isEmpty()) GMEmptyState(TrainIcons.of("dumbbell"), "Nenhuma alternativa", "")
        GMSection {
            list.forEachIndexed { i, ex ->
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Box(Modifier.gmPress { onInfo(ex) }) { Thumb(ex.id) }
                    Row(Modifier.weight(1f).gmPress { onPick(ex); onDismiss() }, verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(ex.name, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold), maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(ex.equipment + ((count[ex.id] ?: 0).takeIf { it > 0 }?.let { " · já fez $it×" } ?: ""), color = GMColors.dim, style = GMType.caption)
                        }
                        Icon(TrainIcons.of("arrow.triangle.swap"), null, tint = GMColors.accent)
                    }
                }
                if (i < list.size - 1) GMDivider()
            }
        }
    }
}

/** Grava o treino aberto, salvo se ele já foi encerrado ou apagado (nunca reabre um treino salvo) */
private fun persistOpen(env: AppEnv, s: Session) = TrainScope.edit(env) { c ->
    if (TrainCopy.read(c).sessions.none { it.uuid == s.uuid && it.end == null }) c else TrainEdits.saveSession(c, s)
}

/** Concluir treino (WorkoutView.swift `FinishWorkoutView`) */
@Composable
private fun FinishWorkoutModal(env: AppEnv, home: HomeData, data: TrainData, session: Session, history: List<SessionLog>, onDismiss: () -> Unit,
                               onDone: (Session) -> Unit) {
    var effort by remember { mutableIntStateOf(7) }
    var updateRoutine by remember { mutableStateOf(false) }
    // Com esta tela aberta, sair da academia não encerra o treino (LiveWorkout.concluding)
    DisposableEffect(session.uuid) {
        GymLocation.concluding = session.uuid
        onDispose { if (GymLocation.concluding == session.uuid) GymLocation.concluding = null }
    }
    var saved by remember { mutableStateOf(false) }
    val minutes = maxOf(((Instant.now().epochSecond - session.start.epochSecond) / 60).toInt(), 1)
    val done = session.doneWorkSets
    val volume = session.volume
    val log = session.log
    val records = remember(session) { Progression.records(log, history) }
    val routine = data.routines.firstOrNull { it.uuid == session.routineUUID }
    val changes = routine?.let { session.routineChanges(it) }.orEmpty()
    val signals = done.map { TrainSplit.SetSignal(it.exerciseID, it.reps, it.rest) }
    val split = TrainSplit.split(ActivityKind.MUSCULACAO, minutes, effort, sets = signals)
    val preview = LogPreview.compute(home.roster, ActivityKind.MUSCULACAO, minutes, effort, session.start, split, RuleClock(ZoneId.systemDefault(), Instant.now()))
    val post = com.alonsoalmeida.gymbros.ui.leagues.rememberTrainingPost(home)
    val typeID = com.alonsoalmeida.gymbros.domain.BroCatalog.classicType[ActivityKind.MUSCULACAO.raw]

    GMModal(true, "Concluir treino", onDismiss, confirm = "Salvar", confirmEnabled = done.isNotEmpty() && post.canSave && !saved, onConfirm = save@{
        // Um toque só: o mesmo treino nunca vira duas atividades (salvo antes, aqui ou em outro aparelho)
        if (saved) return@save
        saved = true
        if (data.sessions.any { it.uuid == session.uuid && it.end != null }) { onDone(session); return@save }
        val activityID = TrainEdits.newID()
        val finished = session.copy(end = Instant.now(), effort = effort, activityUUID = activityID, restEnd = null)
        val summary = if (records.isEmpty()) "" else "🏆 " + records.joinToString(" · ")
        TrainScope.edit(env) { c ->
            if (TrainCopy.read(c).sessions.any { it.uuid == session.uuid && it.end != null }) return@edit c
            var out = TrainEdits.addActivity(c, activityID, ActivityKind.MUSCULACAO.raw, session.start, minutes, effort, session.title,
                                             AttributeSplit.encode(split), session.gymUUID)
            if (updateRoutine && routine != null && changes.isNotEmpty()) out = TrainEdits.saveRoutine(out, finished.applyTo(routine))
            TrainEdits.saveSession(out, finished)
        }
        // Depois de salvar: o check-in em cada destino escolhido (postCheckIns)
        post.post(com.alonsoalmeida.gymbros.domain.leagues.LeagueActivityJson(activityID, ActivityKind.MUSCULACAO.raw, session.start, minutes, effort,
                                                                              session.title, gymUUID = session.gymUUID, healthType = typeID), session.title, summary)
        onDone(finished)
    }) {
        GMCard {
            Row(Modifier.fillMaxWidth()) {
                Stat(ActivityText.duration(minutes), "duração", Modifier.weight(1f))
                Stat("${done.size}/${session.workSets.size}", "séries", Modifier.weight(1f))
                Stat(if (volume > 0) "${Progression.fmt(roundHalfAwayFromZero(volume))} kg" else "–", "volume", Modifier.weight(1f))
            }
        }
        if (done.isNotEmpty()) GMSection("Músculos trabalhados") { MuscleBars(muscleLoad(log.sets)) }
        val ups = session.exerciseIDs.mapNotNull { id ->
            val sets = log.sets.filter { it.exerciseID == id }
            val w = sets.filter { it.done }.maxOfOrNull { it.weight } ?: return@mapNotNull null
            val reps = sets.firstOrNull()?.target ?: return@mapNotNull null
            val s = Progression.suggest(id, sets.size, reps, history + log)
            val type = Exercises.byID(id)?.type
            when {
                s.weight > w -> Exercises.name(id) to "${Progression.fmt(s.weight)} kg (+${Progression.fmt(s.weight - w)})"
                s.reps > reps && s.weight == w -> Exercises.name(id) to when (type) { ExerciseType.TIME -> "${s.reps} s"; ExerciseType.DISTANCE -> "${meters(s.weight)} em ${clock(s.reps)}"; else -> "${s.reps} reps" }
                else -> null
            }
        }
        if (ups.isNotEmpty()) GMSection("No próximo treino, suba a carga", footer = "Você completou todas as séries desses exercícios. A sugestão já vem preenchida no próximo treino.") {
            for ((name, text) in ups) Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(name, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold), modifier = Modifier.weight(1f))
                GMIconLabel(text, TrainIcons.of("arrow.up.circle.fill"), GMColors.accent, GMType.subheadline.copy(fontWeight = FontWeight.Bold))
            }
        }
        val misses = session.exerciseIDs.mapNotNull { id ->
            if (Exercises.byID(id)?.type == ExerciseType.DISTANCE) return@mapNotNull null
            val sets = session.orderedSets.filter { it.exerciseID == id && it.done && !it.warmup }
            val target = sets.maxOfOrNull { it.targetReps } ?: return@mapNotNull null
            if (sets.none { it.reps < it.targetReps }) null else Triple(Exercises.name(id), sets.joinToString(" · ") { "${it.reps}" }, target)
        }
        if (misses.isNotEmpty()) GMSection("Onde melhorar", footer = "Séries em que você fez menos que o planejado. A carga se mantém no próximo treino até você completar todas.") {
            for ((name, reps, target) in misses) Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(name, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold), modifier = Modifier.weight(1f))
                Text(reps, color = Color.White, style = GMType.subheadline.copy(fontFeatureSettings = "tnum"))
                Text("de $target", color = GMColors.warning, style = GMType.caption.copy(fontWeight = FontWeight.Bold))
            }
        }
        if (records.isNotEmpty()) GMSection("Recordes 🏆") { for (r in records) Text(r, color = Color.White, style = GMType.subheadline) }
        if (routine != null && changes.isNotEmpty()) {
            GMSection("Rotina ${routine.name}", footer = "Liga para a próxima vez já começar assim. Cargas não entram: elas vêm do histórico.") {
                for (c in changes) Text("• $c", color = Color.White, style = GMType.subheadline)
                GMDivider()
                GMToggle("Salvar essas mudanças na rotina", updateRoutine, { updateRoutine = it })
            }
        }
        GMSection { GMEffortPicker(effort) { effort = it } }
        com.alonsoalmeida.gymbros.ui.leagues.TrainingPostSection(home, post,
            com.alonsoalmeida.gymbros.domain.leagues.PostSubject(typeID, session.start, minutes))
        GMSection(footer = if (done.isEmpty()) "Marque ao menos uma série feita para salvar." else null) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text("+${preview.xp} XP", color = GMColors.accent, fontSize = 22.sp, fontWeight = FontWeight.Black, modifier = Modifier.weight(1f))
                GMIconLabel("Força", Symbols.of(Attribute.FORCA), Attribute.FORCA.color(), GMType.subheadline)
            }
            preview.message?.takeIf { preview.grows.isNotEmpty() }?.let { Text(it, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.Bold)) }
        }
    }
}
