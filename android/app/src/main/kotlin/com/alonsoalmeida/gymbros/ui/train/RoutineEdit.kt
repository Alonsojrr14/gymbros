package com.alonsoalmeida.gymbros.ui.train

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.alonsoalmeida.gymbros.data.train.TrainData
import com.alonsoalmeida.gymbros.data.train.TrainEdits
import com.alonsoalmeida.gymbros.data.train.TrainScope
import com.alonsoalmeida.gymbros.domain.ActivityText
import com.alonsoalmeida.gymbros.domain.train.ExerciseType
import com.alonsoalmeida.gymbros.domain.train.Exercises
import com.alonsoalmeida.gymbros.domain.train.Routine
import com.alonsoalmeida.gymbros.domain.train.RoutineItem
import com.alonsoalmeida.gymbros.domain.train.SetLog
import com.alonsoalmeida.gymbros.domain.train.Weeks
import com.alonsoalmeida.gymbros.domain.train.clock
import com.alonsoalmeida.gymbros.domain.train.muscleLoad
import com.alonsoalmeida.gymbros.domain.train.weekdaySymbols
import com.alonsoalmeida.gymbros.ui.AppEnv
import com.alonsoalmeida.gymbros.ui.auth.GMTextField
import com.alonsoalmeida.gymbros.ui.components.GMAction
import com.alonsoalmeida.gymbros.ui.components.GMActions
import com.alonsoalmeida.gymbros.ui.components.GMButton
import com.alonsoalmeida.gymbros.ui.components.GMCompactStepper
import com.alonsoalmeida.gymbros.ui.components.GMDivider
import com.alonsoalmeida.gymbros.ui.components.GMDurationWheel
import com.alonsoalmeida.gymbros.ui.components.GMIconButton
import com.alonsoalmeida.gymbros.ui.components.GMIconLabel
import com.alonsoalmeida.gymbros.ui.components.GMRow
import com.alonsoalmeida.gymbros.ui.components.GMScreen
import com.alonsoalmeida.gymbros.ui.components.GMSection
import com.alonsoalmeida.gymbros.ui.components.GMSheet
import com.alonsoalmeida.gymbros.ui.components.TrainIcons
import com.alonsoalmeida.gymbros.ui.components.gmPress
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMRadius
import com.alonsoalmeida.gymbros.ui.theme.GMType
import kotlinx.coroutines.delay
import java.time.Instant
import java.time.ZoneId

/**
 * Editar rotina (Train/RoutineEditView.swift): nome, números da rotina, dias, músculos e exercícios com séries, reps,
 * descanso, ordem e superset. As mudanças ficam na tela e vão para a cópia da conta logo depois (e ao sair).
 */
@Composable
internal fun RoutineEditScreen(env: AppEnv, data: TrainData, id: String, nav: TrainNav) {
    val original = data.routines.firstOrNull { it.uuid == id }
    if (original == null) { LaunchedEffect(Unit) { nav.pop() }; return }
    var routine by remember(id) { mutableStateOf(original) }
    var picking by remember { mutableStateOf(false) }
    var itemMenu by remember { mutableStateOf<Int?>(null) }
    val haptic = LocalHapticFeedback.current

    // Grava pouco depois de cada mudança e ao sair (o iOS salva ao sair da tela)
    val latest by rememberUpdatedState(routine)
    LaunchedEffect(routine) { if (routine != original) { delay(600); TrainScope.edit(env) { TrainEdits.saveRoutine(it, routine) } } }
    DisposableEffect(id) { onDispose { if (latest != original) TrainScope.edit(env) { TrainEdits.saveRoutine(it, latest) } } }

    fun renumber(items: List<RoutineItem>) = items.mapIndexed { i, it -> it.copy(order = i) }

    GMScreen(routine.name.ifEmpty { "Rotina" }, bottomInset = 120.dp, leading = { BackButton(nav) }) {
        GMSection("Nome") {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Thumb(routine.sortedItems.firstOrNull()?.exerciseID ?: "", 48.dp)
                Box(Modifier.weight(1f)) { GMTextField(routine.name, { routine = routine.copy(name = it) }, "Nome da rotina") }
            }
        }
        RoutineStatsSection(data, routine)
        GMSection("Dias") {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                for ((day, label) in weekdaySymbols) {
                    val on = day in routine.weekdays
                    Box(Modifier.weight(1f).heightIn(min = 44.dp).gmPress {
                        haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                        routine = routine.withWeekdays(if (on) routine.weekdays - day else routine.weekdays + day)
                    }.background(if (on) GMColors.accent else GMColors.raised, GMRadius.s).semantics { selected = on }, contentAlignment = Alignment.Center) {
                        Text(label, color = if (on) Color.Black else Color.White, style = GMType.caption.copy(fontWeight = FontWeight.Bold))
                    }
                }
            }
        }
        if (routine.items.isNotEmpty()) {
            GMSection("O que essa rotina treina") {
                val sets = routine.items.flatMap { item -> List(item.sets) { SetLog(item.exerciseID, 0.0, 0, 0, true) } }
                MuscleBars(muscleLoad(sets))
            }
        }
        GMSection("Exercícios", footer = "A carga não fica na rotina: o app sugere a cada treino a partir do seu histórico.") {
            val items = routine.sortedItems
            items.forEachIndexed { i, item ->
                ItemEditor(item, onChange = { new -> routine = routine.copy(items = items.map { if (it === item) new else it }) }) { itemMenu = i }
                if (item.supersetNext && i < items.size - 1) GMIconLabel("Superset: sem descanso até o próximo", TrainIcons.of("link"), GMColors.info)
                else GMDivider()
            }
            GMRow("Adicionar exercício", TrainIcons.of("plus"), GMColors.accent, onClick = { picking = true })
        }
    }

    ExercisePickerModal(picking, env, data, onPick = { ex ->
        routine = routine.copy(items = routine.sortedItems + RoutineItem(ex.id, 3, if (ex.type == ExerciseType.TIME) 30 else 10, 90, routine.items.size))
    }) { picking = false }

    val items = routine.sortedItems
    val i = itemMenu
    val item = i?.let { items.getOrNull(it) }
    GMActions(item != null, { itemMenu = null }, title = item?.let { Exercises.name(it.exerciseID) }, actions = if (item == null || i == null) emptyList() else buildList {
        if (i > 0) add(GMAction("Mover para cima", TrainIcons.of("chevron.up")) {
            routine = routine.copy(items = renumber(items.toMutableList().also { java.util.Collections.swap(it, i, i - 1) }))
        })
        if (i < items.size - 1) {
            add(GMAction("Mover para baixo", TrainIcons.of("chevron.down")) {
                routine = routine.copy(items = renumber(items.toMutableList().also { java.util.Collections.swap(it, i, i + 1) }))
            })
            val next = Exercises.name(items[i + 1].exerciseID)
            add(GMAction(if (item.supersetNext) "Separar de $next" else "Superset com $next", TrainIcons.of("link")) {
                routine = routine.copy(items = items.map { if (it === item) it.copy(supersetNext = !it.supersetNext) else it })
            })
        }
        add(GMAction("Remover da rotina", TrainIcons.of("trash"), destructive = true) { routine = routine.copy(items = renumber(items.filter { it !== item })) })
    })
}

@Composable
private fun ItemEditor(item: RoutineItem, onChange: (RoutineItem) -> Unit, onMenu: () -> Unit) {
    val ex = Exercises.byID(item.exerciseID)
    var pickingRest by remember { mutableStateOf(false) }
    var draft by remember { mutableIntStateOf(90) }
    val timed = ex?.type == ExerciseType.TIME || ex?.type == ExerciseType.DISTANCE
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            if (ex != null) Thumb(item.exerciseID, 36.dp)
            Text(ex?.name ?: item.exerciseID, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold), modifier = Modifier.weight(1f))
            GMIconButton(TrainIcons.of("ellipsis"), "Opções de ${ex?.name ?: item.exerciseID}", onMenu, size = 30.dp)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            GMCompactStepper(item.sets.toDouble(), { onChange(item.copy(sets = it.toInt())) }, 1.0, "séries", Modifier.weight(1f), 1.0..10.0)
            GMCompactStepper(item.reps.toDouble(), { onChange(item.copy(reps = it.toInt())) }, if (timed) 5.0 else 1.0, if (timed) "seg" else "reps", Modifier.weight(1f), 1.0..300.0)
            // Descanso: toque para escolher o tempo exato na roleta
            Column(Modifier.weight(1f).heightIn(min = 44.dp).gmPress { draft = item.rest; pickingRest = true }.background(GMColors.raised, GMRadius.m).padding(vertical = 4.dp),
                   horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                Text(clock(item.rest), color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.Bold, fontFeatureSettings = "tnum"))
                Text("descanso", color = GMColors.dim, style = GMType.caption2)
            }
        }
    }
    if (pickingRest) GMSheet({ pickingRest = false }) {
        Text("Descanso · ${Exercises.name(item.exerciseID)}", color = Color.White, style = GMType.headline)
        GMDurationWheel(draft, { draft = it })
        GMButton("Confirmar", { onChange(item.copy(rest = draft)); pickingRest = false })
    }
}

/** Números da rotina: última vez, quantas vezes, tempo médio e as últimas 8 semanas (PublicRoutines.swift `RoutineStatsSection`) */
@Composable
private fun RoutineStatsSection(data: TrainData, routine: Routine) {
    val done = data.finished.filter { it.routineUUID == routine.uuid }.sortedBy { it.start }
    if (done.isEmpty()) return
    val minutes = done.mapNotNull { s -> s.end?.let { ((it.epochSecond - s.start.epochSecond) / 60).toInt() } }
    val avg = if (minutes.isEmpty()) 0 else minutes.sum() / minutes.size
    val zone = ZoneId.systemDefault()
    val thisWeek = Weeks.start(Instant.now(), zone)
    val weeks = (7 downTo 0).map { back -> val w = thisWeek.minusWeeks(back.toLong()); done.count { Weeks.start(it.start, zone) == w } }
    GMSection("Seus números com esta rotina") {
        Row(Modifier.fillMaxWidth()) {
            Stat(shortAgo(done.last().start), "última vez", Modifier.weight(1f))
            Stat("${done.size}×", "feita", Modifier.weight(1f))
            Stat(ActivityText.duration(avg), "tempo médio", Modifier.weight(1f))
        }
        GMDivider()
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text("Últimas 8 semanas", color = GMColors.dim, style = GMType.caption)
            Row(Modifier.fillMaxWidth().height(50.dp), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                for (n in weeks) Box(Modifier.weight(1f).height((8 + minOf(n, 4) * 10).dp).background(if (n > 0) GMColors.accent else GMColors.raised, androidx.compose.foundation.shape.RoundedCornerShape(3.dp)))
            }
        }
    }
}

/** "agora", "12 min", "3 h", "ontem", "22 de out." (Inbox/InboxView.swift `shortAgo`) */
internal fun shortAgo(i: Instant, now: Instant = Instant.now()): String {
    val zone = ZoneId.systemDefault()
    val s = now.epochSecond - i.epochSecond
    if (s < 60) return "agora"
    if (s < 3600) return "${s / 60} min"
    val day = i.atZone(zone).toLocalDate()
    val today = now.atZone(zone).toLocalDate()
    if (day == today) return "${s / 3600} h"
    if (day == today.minusDays(1)) return "ontem"
    return dayMonth(i)
}

@Composable
internal fun Stat(value: String, label: String, modifier: Modifier = Modifier) {
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(value, color = Color.White, style = GMType.headline.copy(fontFeatureSettings = "tnum"), maxLines = 1, textAlign = TextAlign.Center)
        Text(label, color = GMColors.dim, style = GMType.caption)
    }
}
