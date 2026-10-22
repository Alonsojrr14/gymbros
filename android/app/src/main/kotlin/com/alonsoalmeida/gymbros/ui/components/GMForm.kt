package com.alonsoalmeida.gymbros.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SelectableDates
import androidx.compose.material3.Text
import androidx.compose.material3.TimePicker
import androidx.compose.material3.TimePickerDefaults
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.alonsoalmeida.gymbros.domain.ActivityText
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMRadius
import com.alonsoalmeida.gymbros.ui.theme.GMType
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Locale

/** − valor + (GMSteppers.swift `GMStepper`) */
@Composable
fun GMStepper(value: Int, onChange: (Int) -> Unit, range: IntRange, step: Int = 1, format: (Int) -> String = { "$it" }) {
    val haptic = LocalHapticFeedback.current
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        StepButton(Icons.Filled.Remove, "Diminuir") { haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove); onChange(maxOf(value - step, range.first)) }
        Text(format(value), color = Color.White, style = GMType.headline.copy(fontFeatureSettings = "tnum"),
             modifier = Modifier.widthIn(min = 64.dp), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        StepButton(Icons.Filled.Add, "Aumentar") { haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove); onChange(minOf(value + step, range.last)) }
    }
}

@Composable
private fun StepButton(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, onClick: () -> Unit) {
    Box(Modifier.size(36.dp).gmPress(onClick = onClick).background(GMColors.raised, CircleShape).semantics { contentDescription = label },
        contentAlignment = Alignment.Center) { Icon(icon, null, tint = Color.White, modifier = Modifier.size(16.dp)) }
}

/** Pílula selecionável (GMChips.swift `GMChip`) */
@Composable
fun GMChip(title: String, selected: Boolean, onClick: () -> Unit) {
    Text(
        title, color = if (selected) Color.Black else Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold),
        modifier = Modifier.gmPress(onClick = onClick).background(if (selected) GMColors.accent else GMColors.raised, CircleShape)
            .padding(horizontal = 14.dp, vertical = 9.dp),
    )
}

/** Esforço de 1 a 10: barras crescentes, toque ou arraste (GMSteppers.swift `GMEffortPicker`) */
@Composable
fun GMEffortPicker(value: Int, onChange: (Int) -> Unit) {
    val haptic = LocalHapticFeedback.current
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(Modifier.fillMaxWidth()) {
            Text("Esforço", color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
            Spacer(Modifier.weight(1f))
            Text("$value/10 · ${ActivityText.effortLabel(value)}", color = GMColors.dim, style = GMType.subheadline.copy(fontFeatureSettings = "tnum"))
        }
        BoxWithConstraints(Modifier.fillMaxWidth().height(40.dp)) {
            val width = constraints.maxWidth.toFloat()
            fun pick(x: Float) {
                val i = ((x / width * 10).toInt() + 1).coerceIn(1, 10)
                if (i != value) {
                    haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                    onChange(i)
                }
            }
            Row(
                Modifier.fillMaxWidth().height(40.dp)
                    .pointerInput(value) { detectTapGestures { pick(it.x) } }
                    .pointerInput(value) { detectDragGestures { change, _ -> pick(change.position.x) } }
                    .semantics { contentDescription = "Esforço $value de 10, ${ActivityText.effortLabel(value)}" },
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                verticalAlignment = Alignment.Bottom,
            ) {
                for (i in 1..10) {
                    Box(Modifier.weight(1f).height((12 + i * 2.6).dp).background(if (i <= value) effortColor(i) else GMColors.track, GMRadius.xs))
                }
            }
        }
    }
}

private fun effortColor(i: Int): Color = when {
    i <= 3 -> GMColors.accent
    i <= 6 -> Color(0xFFFFD60A) // .yellow do iOS no escuro
    i <= 8 -> Color(0xFFFF9F0A) // .orange
    else -> Color(0xFFFF453A) // .red
}

/** Textos de dia e hora (GMCalendar.swift `GMDateText`) */
object GMDateText {
    private val locale = Locale.forLanguageTag("pt-BR")

    fun day(i: Instant, zone: ZoneId = ZoneId.systemDefault()): String {
        val d = i.atZone(zone).toLocalDate()
        val today = LocalDate.now(zone)
        if (d == today) return "Hoje"
        if (d == today.minusDays(1)) return "Ontem"
        val f = DateTimeFormatter.ofPattern(if (d.year == today.year) "EEE, d 'de' MMMM" else "d 'de' MMM 'de' yyyy", locale)
        return d.format(f).replaceFirstChar { it.uppercase() }
    }

    fun time(i: Instant, zone: ZoneId = ZoneId.systemDefault()): String = i.atZone(zone).format(DateTimeFormatter.ofPattern("HH:mm", locale))
}

/** Dia e horário: duas linhas que abrem calendário e relógio em folhas de baixo (GMCalendar.swift `GMDateTimePicker`) */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GMDateTimePicker(date: Instant, onChange: (Instant) -> Unit) {
    val zone = ZoneId.systemDefault()
    var dayOpen by remember { mutableStateOf(false) }
    var timeOpen by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        FieldRow(Icons.Filled.CalendarMonth, "Dia", GMDateText.day(date)) { dayOpen = true }
        Box(Modifier.fillMaxWidth().height(1.dp).background(GMColors.stroke))
        FieldRow(Icons.Filled.Schedule, "Horário", GMDateText.time(date)) { timeOpen = true }
    }
    val now = Instant.now()
    if (dayOpen) {
        // O DatePicker do Material trabalha em UTC: o dia escolhido vira meia-noite UTC
        val today = LocalDate.now(zone)
        val state = rememberDatePickerState(
            initialSelectedDateMillis = date.atZone(zone).toLocalDate().atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli(),
            selectableDates = object : SelectableDates {
                override fun isSelectableDate(utcTimeMillis: Long) =
                    !Instant.ofEpochMilli(utcTimeMillis).atZone(ZoneOffset.UTC).toLocalDate().isAfter(today)
            },
        )
        GMSheet(onDismiss = { dayOpen = false }) {
            DatePicker(state, title = null, headline = null, showModeToggle = false, colors = DatePickerDefaults.colors(
                containerColor = GMColors.bg, selectedDayContainerColor = GMColors.accent, selectedDayContentColor = Color.Black,
                todayDateBorderColor = GMColors.accent, todayContentColor = GMColors.accent))
            GMButton("Confirmar", {
                state.selectedDateMillis?.let { ms ->
                    // Mantém o horário, troca só o dia; nunca no futuro
                    val day = Instant.ofEpochMilli(ms).atZone(ZoneOffset.UTC).toLocalDate()
                    val t = date.atZone(zone).toLocalTime()
                    onChange(minOf(LocalDateTime.of(day, t).atZone(zone).toInstant(), now))
                }
                dayOpen = false
            })
        }
    }
    if (timeOpen) {
        val local = date.atZone(zone)
        val state = rememberTimePickerState(local.hour, local.minute, is24Hour = true)
        GMSheet(onDismiss = { timeOpen = false }) {
            Text("Horário", color = Color.White, style = GMType.headline)
            TimePicker(state, colors = TimePickerDefaults.colors(clockDialColor = GMColors.raised, selectorColor = GMColors.accent,
                                                               timeSelectorSelectedContainerColor = GMColors.accent.copy(alpha = 0.25f),
                                                               timeSelectorSelectedContentColor = GMColors.accent))
            GMButton("Confirmar", {
                val d = LocalDateTime.of(local.toLocalDate(), LocalTime.of(state.hour, state.minute)).atZone(zone).toInstant()
                onChange(minOf(d, now))
                timeOpen = false
            })
        }
    }
}

/** Folha de baixo do app (gmSheet do iOS): fundo do app, conteúdo centralizado com espaçamento 16 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GMSheet(onDismiss: () -> Unit, content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
                     containerColor = GMColors.bg) {
        Column(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, bottom = 24.dp),
               horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp), content = content)
    }
}

@Composable
private fun FieldRow(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, value: String, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().gmPress(onClick = onClick), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.size(34.dp).background(GMColors.raised, GMRadius.s), contentAlignment = Alignment.Center) {
            Icon(icon, null, tint = Color.White, modifier = Modifier.size(18.dp))
        }
        Text(title, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
        Spacer(Modifier.weight(1f))
        Text(value, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold),
             modifier = Modifier.background(GMColors.raised, CircleShape).padding(horizontal = 12.dp, vertical = 7.dp))
    }
}
