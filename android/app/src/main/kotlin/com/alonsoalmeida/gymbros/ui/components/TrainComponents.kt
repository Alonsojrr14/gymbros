package com.alonsoalmeida.gymbros.ui.components

import android.graphics.BitmapFactory
import android.util.LruCache
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.DirectionsRun
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.automirrored.filled.Note
import androidx.compose.material.icons.automirrored.filled.TrendingUp
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AccessibilityNew
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.BatteryChargingFull
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.FitnessCenter
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.LinkOff
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material.icons.filled.Scale
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.SelfImprovement
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material.icons.filled.TrackChanges
import androidx.compose.material.icons.filled.UnfoldLess
import androidx.compose.material.icons.filled.UnfoldMore
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material.icons.filled.Whatshot
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.Stairs
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.alonsoalmeida.gymbros.domain.train.Exercise
import com.alonsoalmeida.gymbros.domain.train.Progression
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMRadius
import com.alonsoalmeida.gymbros.ui.theme.GMType
import kotlinx.coroutines.flow.distinctUntilChanged

/** SF Symbols do treino → ícones Material (o mais próximo quando não há o mesmo desenho) */
object TrainIcons {
    fun of(symbol: String): ImageVector = when (symbol) {
        "plus" -> Icons.Filled.Add
        "minus" -> Icons.Filled.Remove
        "play.fill", "play" -> Icons.Filled.PlayArrow
        "pause.fill" -> Icons.Filled.Pause
        "checkmark" -> Icons.Filled.Check
        "checkmark.circle.fill", "checkmark.seal" -> Icons.Filled.CheckCircle
        "checkmark.circle" -> Icons.Outlined.CheckCircle
        "circle" -> Icons.Filled.RadioButtonUnchecked
        "xmark", "xmark.circle.fill" -> Icons.Filled.Close
        "xmark.circle", "minus.circle" -> Icons.Filled.Cancel
        "ellipsis" -> Icons.Filled.MoreHoriz
        "chevron.left" -> Icons.Filled.ChevronLeft
        "chevron.right" -> Icons.Filled.ChevronRight
        "chevron.down" -> Icons.Filled.ExpandMore
        "chevron.up" -> Icons.Filled.ExpandLess
        "pencil" -> Icons.Filled.Edit
        "trash", "trash.fill" -> Icons.Filled.Delete
        "list.bullet", "list.bullet.rectangle" -> Icons.AutoMirrored.Filled.List
        "square.stack" -> Icons.Filled.ContentCopy
        "person.2.fill", "person.2" -> Icons.Filled.Group
        "eye.slash" -> Icons.Filled.VisibilityOff
        "eye" -> Icons.Filled.Visibility
        "doc.on.clipboard" -> Icons.Filled.ContentPaste
        "calendar", "calendar.badge.plus" -> Icons.Filled.CalendarMonth
        "clock.arrow.circlepath" -> Icons.Filled.History
        "flame.fill", "flame" -> Icons.Filled.LocalFireDepartment
        "trophy.fill", "trophy" -> Icons.Filled.EmojiEvents
        "chart.line.uptrend.xyaxis", "arrow.up.right", "arrow.up.circle.fill" -> Icons.AutoMirrored.Filled.TrendingUp
        "chart.bar.fill" -> Icons.Filled.BarChart
        "figure.stand" -> Icons.Filled.AccessibilityNew
        "books.vertical" -> Icons.AutoMirrored.Filled.MenuBook
        "scalemass" -> Icons.Filled.Scale
        "circle.grid.2x1" -> Icons.Filled.FitnessCenter
        "battery.100.bolt" -> Icons.Filled.BatteryChargingFull
        "timer", "stopwatch" -> Icons.Filled.Timer
        "link", "link.badge.plus" -> Icons.Filled.Link
        "target" -> Icons.Filled.TrackChanges
        "arrow.triangle.swap" -> Icons.Filled.SwapHoriz
        "note.text" -> Icons.AutoMirrored.Filled.Note
        "info.circle", "info" -> Icons.Outlined.Info
        "arrow.uturn.backward", "arrow.counterclockwise" -> Icons.AutoMirrored.Filled.Undo
        "arrow.uturn.forward" -> Icons.Filled.Replay
        "forward.fill" -> Icons.Filled.SkipNext
        "flag.checkered" -> Icons.Filled.Flag
        "mappin.and.ellipse" -> Icons.Filled.Place
        "heart.fill" -> Icons.Filled.Favorite
        "heart" -> Icons.Filled.FavoriteBorder
        "square.and.arrow.down" -> Icons.Filled.Download
        "wand.and.stars" -> Icons.Filled.AutoAwesome
        "lightbulb" -> Icons.Filled.Lightbulb
        "exclamationmark.triangle.fill", "exclamationmark.circle.fill" -> Icons.Filled.Warning
        "magnifyingglass" -> Icons.Filled.Search
        "arrow.up.left.and.arrow.down.right" -> Icons.Filled.UnfoldMore
        "arrow.down.right.and.arrow.up.left" -> Icons.Filled.UnfoldLess
        "dot.radiowaves.left.and.right" -> Icons.Filled.Whatshot
        "figure.cross.training" -> Icons.Filled.Whatshot
        "figure.arms.open" -> Icons.Filled.AccessibilityNew
        "figure.rower" -> Icons.Filled.FitnessCenter
        "dumbbell.fill", "dumbbell" -> Icons.Filled.FitnessCenter
        "figure.step.training" -> Icons.Filled.Stairs
        "figure.core.training" -> Icons.Filled.SelfImprovement
        "figure.run" -> Icons.AutoMirrored.Filled.DirectionsRun
        "person" -> Icons.Filled.Person
        "c.circle" -> Icons.Filled.Info
        else -> Symbols.of(symbol)
    }

    val back: ImageVector get() = Icons.AutoMirrored.Filled.ArrowBack
}


/** Linha tocável: ícone, título, subtítulo e algo à direita (GMSurfaces.swift `GMRow`) */
@Composable
fun GMRow(title: String, icon: ImageVector? = null, iconTint: Color = Color.White, subtitle: String? = null, chevron: Boolean = false,
          onClick: (() -> Unit)? = null, leading: (@Composable () -> Unit)? = null, modifier: Modifier = Modifier, trailing: @Composable RowScope.() -> Unit = {}) {
    Row(
        modifier.fillMaxWidth().heightIn(min = 44.dp).then(if (onClick != null) Modifier.gmPress(onClick = onClick) else Modifier),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        leading?.invoke()
        if (icon != null) {
            Box(Modifier.size(34.dp).background(GMColors.raised, GMRadius.s), contentAlignment = Alignment.Center) {
                Icon(icon, null, tint = iconTint, modifier = Modifier.size(20.dp))
            }
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
            if (subtitle != null) Text(subtitle, color = GMColors.dim, style = GMType.caption)
        }
        trailing()
        if (chevron) Icon(Icons.Filled.ChevronRight, null, tint = GMColors.dim, modifier = Modifier.size(18.dp))
    }
}

/** Par rótulo/valor (GMValueRow) */
@Composable
fun GMValueRow(label: String, value: String) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(label, color = GMColors.dim, style = GMType.subheadline, modifier = Modifier.weight(1f))
        Text(value, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold, fontFeatureSettings = "tnum"))
    }
}

/** Etiqueta pequena colorida (GMIndicators.swift `GMBadge`) */
@Composable
fun GMBadge(text: String, tint: Color = GMColors.accent) {
    Text(text, color = tint, style = GMType.caption2.copy(fontWeight = FontWeight.Bold),
         modifier = Modifier.background(tint.copy(alpha = 0.2f), CircleShape).padding(horizontal = 7.dp, vertical = 3.dp))
}

/** Abas segmentadas (GMChips.swift `GMSegmented`) */
@Composable
fun <T> GMSegmented(options: List<Pair<T, String>>, selection: T, onSelect: (T) -> Unit, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth().background(GMColors.card, CircleShape).padding(4.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        for ((value, label) in options) {
            val on = value == selection
            Box(Modifier.weight(1f).heightIn(min = 40.dp).clip(CircleShape).background(if (on) GMColors.accent else Color.Transparent)
                    .gmPress(role = Role.Tab) { onSelect(value) }.semantics { stateDescription = if (on) "Selecionado" else "" },
                contentAlignment = Alignment.Center) {
                Text(label, color = if (on) Color.Black else Color.White.copy(alpha = 0.75f), style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold),
                     maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

/** Mesma escolha com a ação antes do título (ordem usada nas telas do treino) */
@Composable
fun <T> GMChoiceChips(options: List<Pair<T, String>>, selection: T, onSelect: (T) -> Unit, title: String? = null) =
    GMChoiceChips(options, selection, title, onSelect)

/** Escolha entre pílulas que quebram linha (GMChips.swift `GMChoiceChips`) */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun <T> GMChoiceChips(options: List<Pair<T, String>>, selection: T, title: String? = null, onSelect: (T) -> Unit) {
    val haptic = LocalHapticFeedback.current
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        if (title != null) Text(title, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            for ((v, label) in options) GMChip(label, v == selection) { haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove); onSelect(v) }
        }
    }
}

/** Interruptor (GMToggles.swift) */
@Composable
fun GMToggle(title: String, isOn: Boolean, onChange: (Boolean) -> Unit, subtitle: String? = null) {
    val haptic = LocalHapticFeedback.current
    Row(Modifier.fillMaxWidth().gmPress(role = Role.Switch) { haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove); onChange(!isOn) }
            .semantics { stateDescription = if (isOn) "Ativado" else "Desativado" },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
            if (subtitle != null) Text(subtitle, color = GMColors.dim, style = GMType.caption)
        }
        Box(Modifier.width(50.dp).height(30.dp).background(if (isOn) GMColors.accent else Color.White.copy(alpha = 0.15f), CircleShape).padding(4.dp),
            contentAlignment = if (isOn) Alignment.CenterEnd else Alignment.CenterStart) {
            Box(Modifier.size(22.dp).background(if (isOn) Color.Black else Color.White, CircleShape))
        }
    }
}

/** Número em texto pt-BR (vírgula) para os campos */
private fun numText(v: Double, decimals: Boolean): String = if (decimals) Progression.fmt(v) else v.toLong().toString()
private fun parseNum(s: String): Double? = s.replace(".", "").replace(",", ".").trim().toDoubleOrNull()
    ?: s.replace(",", ".").trim().toDoubleOrNull()

/** Campo de número que aceita digitação (vírgula ou ponto) e acompanha mudanças de fora */
@Composable
private fun NumberField(value: Double, onChange: (Double) -> Unit, decimals: Boolean, modifier: Modifier, style: androidx.compose.ui.text.TextStyle,
                        align: TextAlign = TextAlign.Center, placeholder: String = "0") {
    var text by remember { mutableStateOf(numText(value, decimals)) }
    var focused by remember { mutableStateOf(false) }
    // Vazio enquanto digita fica vazio (apagar não volta ao número anterior); vazio ao sair do campo vira 0
    LaunchedEffect(value) { if (parseNum(text) != value && !(focused && text.isEmpty())) text = numText(value, decimals) }
    BasicTextField(text, { t -> text = t; parseNum(t)?.let(onChange) },
        singleLine = true, textStyle = style.copy(color = Color.White, textAlign = align, fontFeatureSettings = "tnum"),
        cursorBrush = SolidColor(GMColors.accent),
        keyboardOptions = KeyboardOptions(keyboardType = if (decimals) KeyboardType.Decimal else KeyboardType.Number),
        modifier = modifier.gmRevealOnFocus().onFocusChanged {
            if (focused && !it.isFocused && parseNum(text) == null) { onChange(0.0); text = numText(0.0, decimals) }
            focused = it.isFocused
        }, decorationBox = { inner ->
            Box(contentAlignment = Alignment.Center) {
                if (text.isEmpty()) Text(placeholder, color = GMColors.dim, style = style, textAlign = align)
                inner()
            }
        })
}

/** Stepper compacto em bloco (− valor/rótulo +), editável nas séries (GMSteppers.swift `GMCompactStepper`) */
@Composable
fun GMCompactStepper(value: Double, onChange: (Double) -> Unit, step: Double, label: String, modifier: Modifier = Modifier,
                     range: ClosedFloatingPointRange<Double> = 0.0..Double.MAX_VALUE, decimals: Boolean = false, editable: Boolean = false,
                     labelColor: Color = GMColors.dim, labelBold: Boolean = false) {
    val haptic = LocalHapticFeedback.current
    Row(modifier.background(GMColors.raised, GMRadius.m).padding(horizontal = 4.dp, vertical = if (editable) 0.dp else 4.dp),
        verticalAlignment = Alignment.CenterVertically) {
        StepIcon(Icons.Filled.Remove, "Diminuir") { haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove); onChange(maxOf(value - step, range.start)) }
        Column(if (editable) Modifier.width(56.dp) else Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
            if (editable) NumberField(value, { onChange(it.coerceIn(range)) }, decimals, Modifier.fillMaxWidth(), GMType.body.copy(fontWeight = FontWeight.Bold))
            else Text(numText(value, decimals), color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.Bold, fontFeatureSettings = "tnum"))
            Text(label, color = labelColor, style = GMType.caption2.copy(fontWeight = if (labelBold) FontWeight.Bold else FontWeight.Normal), maxLines = 1)
        }
        StepIcon(Icons.Filled.Add, "Aumentar") { haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove); onChange(minOf(value + step, range.endInclusive)) }
    }
}

@Composable
private fun StepIcon(icon: ImageVector, label: String, onClick: () -> Unit) {
    Box(Modifier.size(width = 30.dp, height = 44.dp).gmPress(onClick = onClick).semantics { contentDescription = label }, contentAlignment = Alignment.Center) {
        Icon(icon, null, tint = Color.White, modifier = Modifier.size(14.dp))
    }
}

/** Número decimal opcional com − + e digitação (GMFields.swift `GMDecimalField`); vazio mostra "—" */
@Composable
fun GMDecimalField(title: String, value: Double?, onChange: (Double?) -> Unit, step: Double = 0.5, unit: String = "kg", start: Double = 70.0,
                   clearable: Boolean = true) {
    val haptic = LocalHapticFeedback.current
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(title, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold), modifier = Modifier.weight(1f))
        RoundStep(Icons.Filled.Remove, "Diminuir") { haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove); onChange(maxOf((value ?: start) - step, 0.0)) }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            if (value == null) Text("—", color = GMColors.dim, style = GMType.headline, modifier = Modifier.width(58.dp), textAlign = TextAlign.End)
            else NumberField(value, { onChange(it) }, true, Modifier.width(58.dp), GMType.headline, TextAlign.End)
            Text(unit, color = GMColors.dim, style = GMType.caption)
        }
        RoundStep(Icons.Filled.Add, "Aumentar") { haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove); onChange(value?.plus(step) ?: start) }
        if (clearable && value != null) {
            Box(Modifier.size(32.dp).gmPress { onChange(null) }.semantics { contentDescription = "Apagar" }, contentAlignment = Alignment.Center) {
                Icon(Icons.Filled.Cancel, null, tint = GMColors.dim, modifier = Modifier.size(20.dp))
            }
        }
    }
}

@Composable
private fun RoundStep(icon: ImageVector, label: String, onClick: () -> Unit) {
    Box(Modifier.size(32.dp).gmPress(onClick = onClick).background(GMColors.raised, CircleShape).semantics { contentDescription = label },
        contentAlignment = Alignment.Center) { Icon(icon, null, tint = Color.White, modifier = Modifier.size(14.dp)) }
}

/** − valor + com título à esquerda (GMStepper com `title`) */
@Composable
fun GMTitledStepper(title: String, value: Int, onChange: (Int) -> Unit, range: IntRange, step: Int = 1, format: (Int) -> String = { "$it" }) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(title, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold), modifier = Modifier.weight(1f))
        GMStepper(value, onChange, range, step, format)
    }
}

/** Campo de busca em cápsula (GMFields.swift `GMSearchField`) */
@Composable
fun GMSearchField(text: String, onChange: (String) -> Unit, placeholder: String) {
    Row(Modifier.fillMaxWidth().background(GMColors.card, CircleShape).padding(horizontal = 14.dp, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(Icons.Filled.Search, null, tint = GMColors.dim, modifier = Modifier.size(18.dp))
        BasicTextField(text, onChange, singleLine = true, textStyle = GMType.body.copy(color = Color.White), cursorBrush = SolidColor(GMColors.accent),
            modifier = Modifier.weight(1f).gmRevealOnFocus(), decorationBox = { inner ->
                Box { if (text.isEmpty()) Text(placeholder, color = GMColors.dim, style = GMType.body); inner() }
            })
        if (text.isNotEmpty()) Box(Modifier.size(24.dp).gmPress { onChange("") }.semantics { contentDescription = "Limpar busca" }, contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.Cancel, null, tint = GMColors.dim, modifier = Modifier.size(18.dp))
        }
    }
}

/** Texto de várias linhas com dica (GMTextField axis .vertical / WodTextEditor) */
@Composable
fun GMTextArea(text: String, onChange: (String) -> Unit, placeholder: String, minHeight: Dp = 56.dp, background: Color = GMColors.raised) {
    BasicTextField(text, onChange, textStyle = GMType.body.copy(color = Color.White), cursorBrush = SolidColor(GMColors.accent),
        modifier = Modifier.fillMaxWidth().heightIn(min = minHeight).gmRevealOnFocus().background(background, GMRadius.m).padding(horizontal = 14.dp, vertical = 12.dp),
        decorationBox = { inner -> Box { if (text.isEmpty()) Text(placeholder, color = GMColors.dim.copy(alpha = 0.7f), style = GMType.body); inner() } })
}

data class GMAction(val title: String, val icon: ImageVector? = null, val destructive: Boolean = false, val action: () -> Unit)

/** Folha de ações (GMSheets.swift `gmActions`): título, mensagem, ações e Cancelar; a ação roda depois de fechar */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GMActions(visible: Boolean, onDismiss: () -> Unit, title: String? = null, message: String? = null, actions: List<GMAction>) {
    if (!visible) return
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = GMColors.card,
                     shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp)) {
        Column(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, bottom = 24.dp).navigationBarsPadding(),
               horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (title != null) Text(title, color = Color.White, style = GMType.headline, textAlign = TextAlign.Center)
            if (message != null) Text(message, color = GMColors.dim, style = GMType.subheadline, textAlign = TextAlign.Center)
            if (title != null || message != null) Spacer(Modifier.height(4.dp))
            for (a in actions) GMButton(a.title, { onDismiss(); a.action() }, icon = a.icon, kind = if (a.destructive) GMButtonKind.DANGER else GMButtonKind.SECONDARY)
            GMButton("Cancelar", onDismiss, kind = GMButtonKind.GHOST)
        }
    }
}

/** Diálogo central com campo de texto (GMSheets.swift `gmPrompt`) */
@Composable
fun GMPrompt(visible: Boolean, title: String, text: String, onText: (String) -> Unit, placeholder: String, onDismiss: () -> Unit,
             onConfirm: () -> Unit, message: String? = null, confirm: String = "Salvar") {
    if (!visible) return
    Dialog(onDismissRequest = onDismiss) {
        Column(Modifier.fillMaxWidth().background(GMColors.card, GMRadius.xl).padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally,
               verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text(title, color = Color.White, style = GMType.headline)
            if (message != null) Text(message, color = GMColors.dim, style = GMType.subheadline, textAlign = TextAlign.Center)
            GMTextArea(text, onText, placeholder)
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                GMButton("Cancelar", onDismiss, Modifier.weight(1f), kind = GMButtonKind.SECONDARY)
                GMButton(confirm, { onDismiss(); onConfirm() }, Modifier.weight(1f))
            }
        }
    }
}

/** Roleta de valores (GMCalendar.swift `GMWheel`): rola e encaixa, a linha do meio é a escolhida */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun GMWheel(values: List<Int>, selection: Int, onSelect: (Int) -> Unit, modifier: Modifier = Modifier, format: (Int) -> String = { "$it" }) {
    val row = 40.dp
    val haptic = LocalHapticFeedback.current
    val state = rememberLazyListState(values.indexOf(selection).coerceAtLeast(0))
    // O efeito vive enquanto a roleta existe: lê sempre a seleção e o callback atuais
    val current by androidx.compose.runtime.rememberUpdatedState(selection)
    val select by androidx.compose.runtime.rememberUpdatedState(onSelect)
    LaunchedEffect(state) {
        snapshotFlow { state.firstVisibleItemIndex + if (state.firstVisibleItemScrollOffset > 20) 1 else 0 }.distinctUntilChanged().collect { i ->
            values.getOrNull(i)?.let { if (it != current) { haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove); select(it) } }
        }
    }
    LazyColumn(modifier.height(row * 5), state = state, flingBehavior = rememberSnapFlingBehavior(state),
               contentPadding = androidx.compose.foundation.layout.PaddingValues(vertical = row * 2), horizontalAlignment = Alignment.CenterHorizontally) {
        items(values.size) { i ->
            val on = values[i] == selection
            Box(Modifier.height(row).fillMaxWidth(), contentAlignment = Alignment.Center) {
                Text(format(values[i]), color = if (on) Color.White else GMColors.dim, style = GMType.title3.copy(fontWeight = if (on) FontWeight.Bold else FontWeight.Normal))
            }
        }
    }
}

/** Minutos e segundos (de 5 em 5) em duas roletas (GMCalendar.swift `GMDurationWheel`) */
@Composable
fun GMDurationWheel(seconds: Int, onChange: (Int) -> Unit, maxMinutes: Int = 10) {
    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        Box(Modifier.fillMaxWidth().height(40.dp).background(GMColors.raised, GMRadius.m))
        Row(Modifier.padding(horizontal = 24.dp), verticalAlignment = Alignment.CenterVertically) {
            GMWheel((0..maxMinutes).toList(), seconds / 60, { onChange(it * 60 + seconds % 60) }, Modifier.weight(1f))
            Text("min", color = GMColors.dim, style = GMType.headline)
            GMWheel((0..55 step 5).toList(), seconds % 60 / 5 * 5, { onChange(seconds / 60 * 60 + it) }, Modifier.weight(1f))
            Text("s", color = GMColors.dim, style = GMType.headline)
        }
    }
}

/** Tela cheia por cima de tudo, sem o cabeçalho do GMModal (treino em andamento e cronômetro do WOD) */
@Composable
fun GMFullScreen(visible: Boolean, onDismiss: () -> Unit, content: @Composable ColumnScope.() -> Unit) {
    if (!visible) return
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Column(Modifier.fillMaxSize().background(GMColors.bg).safeDrawingPadding(), content = content)
    }
}

/** Botão de texto pequeno com ícone (GMTextButton) */
@Composable
fun GMTextButton(title: String, icon: ImageVector? = null, onClick: () -> Unit) {
    Row(Modifier.heightIn(min = 44.dp).gmPress(onClick = onClick).padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        if (icon != null) Icon(icon, null, tint = GMColors.dim, modifier = Modifier.size(16.dp))
        Text(title, color = GMColors.dim, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
    }
}

/** Ícone redondo com cor própria (GMIconButton com `tint`) */
@Composable
fun GMTintIconButton(icon: ImageVector, label: String, tint: Color, onClick: () -> Unit, size: Dp = 40.dp, background: Color = GMColors.raised) {
    Box(Modifier.size(maxOf(size, 44.dp)).gmPress(onClick = onClick).semantics { contentDescription = label; role = Role.Button }, contentAlignment = Alignment.Center) {
        Box(Modifier.size(size).background(background, CircleShape), contentAlignment = Alignment.Center) {
            Icon(icon, null, tint = tint, modifier = Modifier.size(size * 0.42f))
        }
    }
}

/** Ilustrações do wger embutidas (assets/wger), decodificadas pequenas e guardadas em memória */
object ExerciseImages {
    private val cache = LruCache<String, ImageBitmap>(80)
    private var names: Map<String, String>? = null

    fun load(context: android.content.Context, asset: String): ImageBitmap? {
        cache.get(asset)?.let { return it }
        val files = names ?: runCatching { context.assets.list("wger").orEmpty().associateBy { it.substringBeforeLast('.') } }.getOrDefault(emptyMap()).also { names = it }
        val file = files[asset] ?: return null
        val bmp = runCatching {
            context.assets.open("wger/$file").use { s ->
                val opts = BitmapFactory.Options().apply { inSampleSize = 2 }
                BitmapFactory.decodeStream(s, null, opts)?.asImageBitmap()
            }
        }.getOrNull() ?: return null
        cache.put(asset, bmp)
        return bmp
    }
}

/** Miniatura do exercício: ilustração do wger (fundo branco) ou o ícone do grupo (RoutineEditView.swift `ExerciseThumb`) */
@Composable
fun ExerciseThumb(exercise: Exercise, asset: String?, size: Dp = 44.dp) {
    val context = LocalContext.current
    val img = remember(asset) { asset?.let { ExerciseImages.load(context, it) } }
    Box(Modifier.size(size).clip(GMRadius.s).background(if (img != null) Color.White else GMColors.raised), contentAlignment = Alignment.Center) {
        if (img != null) Image(img, null, contentScale = ContentScale.Fit, modifier = Modifier.fillMaxSize().padding(3.dp))
        else Icon(TrainIcons.of(if (exercise.isCrossfit) "figure.cross.training" else exercise.group.symbol), null, tint = GMColors.dim,
                  modifier = Modifier.size(size * 0.45f))
    }
}

/** Cartão com borda opcional (cards do treino com destaque do exercício atual) */
@Composable
fun GMOutlinedCard(border: Color, width: Dp, padding: Dp = 16.dp, modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(modifier.fillMaxWidth().background(GMColors.card, GMRadius.card).border(width, border, GMRadius.card).padding(padding),
           verticalArrangement = Arrangement.spacedBy(10.dp), content = content)
}

@Composable
fun GMIconLabel(text: String, icon: ImageVector, tint: Color, style: androidx.compose.ui.text.TextStyle = GMType.caption.copy(fontWeight = FontWeight.Bold),
                modifier: Modifier = Modifier) {
    Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Icon(icon, null, tint = tint, modifier = Modifier.size(14.dp))
        Text(text, color = tint, style = style)
    }
}

@Composable
fun GMMinWidth(content: @Composable () -> Unit) = Box(Modifier.widthIn(min = 48.dp)) { content() }
