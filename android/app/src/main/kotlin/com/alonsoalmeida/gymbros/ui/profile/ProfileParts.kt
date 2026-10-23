package com.alonsoalmeida.gymbros.ui.profile

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.toggleableState
import androidx.compose.ui.state.ToggleableState
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.alonsoalmeida.gymbros.domain.ActivityText
import com.alonsoalmeida.gymbros.domain.profile.BodyEdits
import com.alonsoalmeida.gymbros.domain.profile.ProfileActivity
import com.alonsoalmeida.gymbros.ui.AppEnv
import com.alonsoalmeida.gymbros.ui.auth.GMTextField
import com.alonsoalmeida.gymbros.ui.components.GMStepper
import com.alonsoalmeida.gymbros.ui.components.Symbols
import com.alonsoalmeida.gymbros.ui.components.gmPress
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMRadius
import com.alonsoalmeida.gymbros.ui.theme.GMType
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** Um ViewModel por conta para toda a frente de perfil (ajustes, perfil, histórico, peso) */
@Composable
fun profileViewModel(env: AppEnv): ProfileViewModel =
    viewModel(key = "profile-${env.uid}", factory = viewModelFactory { initializer { ProfileViewModel(env.copies) } })

internal val ptBR: Locale = Locale.forLanguageTag("pt-BR")

/** Linha fina entre itens de um card (GMDivider) */
@Composable
internal fun Hairline() = Box(Modifier.fillMaxWidth().height(1.dp).background(GMColors.stroke))

/** Ícone num quadrado colorido, como os ícones de Ajustes do iOS (GMNavRow/GMRow `tile`) */
@Composable
internal fun Tile(icon: ImageVector, tint: Color) {
    Box(Modifier.size(32.dp).background(tint.copy(alpha = 0.18f), GMRadius.s), contentAlignment = Alignment.Center) {
        Icon(icon, null, tint = tint, modifier = Modifier.size(18.dp))
    }
}

/** Linha que leva a outra tela (GMNavRow): ícone, título, valor e a setinha */
@Composable
internal fun NavRow(icon: ImageVector, tint: Color, title: String, value: String? = null, valueTint: Color = GMColors.dim,
                    subtitle: String? = null, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).gmPress(onClick = onClick), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Tile(icon, tint)
        Column(Modifier.weight(1f)) {
            Text(title, color = Color.White, style = GMType.body)
            subtitle?.let { Text(it, color = GMColors.dim, style = GMType.caption) }
        }
        value?.let { Text(it, color = valueTint, style = GMType.subheadline, maxLines = 1) }
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = GMColors.dim, modifier = Modifier.size(20.dp))
    }
}

/** Rótulo à esquerda e valor à direita (GMValueRow) */
@Composable
internal fun ValueRow(label: String, value: String) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(label, color = GMColors.dim, style = GMType.subheadline)
        Spacer(Modifier.weight(1f))
        Text(value, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold), maxLines = 2)
    }
}

/** Interruptor com ícone, título e subtítulo (GMIconToggle/GMToggle); a linha inteira liga e desliga */
@Composable
internal fun ToggleRow(title: String, on: Boolean, onChange: (Boolean) -> Unit, icon: ImageVector? = null, tint: Color = GMColors.accent,
                       subtitle: String? = null, enabled: Boolean = true) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 48.dp).gmPress(enabled, role = Role.Switch) { onChange(!on) }
            .semantics(mergeDescendants = true) { toggleableState = ToggleableState(on) },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (icon != null) Tile(icon, tint)
        Column(Modifier.weight(1f)) {
            Text(title, color = if (enabled) Color.White else GMColors.dim, style = GMType.body)
            subtitle?.let { Text(it, color = GMColors.dim, style = GMType.caption) }
        }
        Switch(on, null, enabled = enabled, colors = SwitchDefaults.colors(
            checkedTrackColor = GMColors.accent, checkedThumbColor = Color.White,
            uncheckedTrackColor = GMColors.track, uncheckedThumbColor = Color.White, uncheckedBorderColor = Color.Transparent))
    }
}

/** Duas ou mais opções lado a lado (GMSegmented) */
@Composable
internal fun <T> Segmented(options: List<Pair<T, String>>, selection: T, onSelect: (T) -> Unit) {
    Row(Modifier.fillMaxWidth().background(GMColors.card, CircleShape).padding(4.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        for ((value, title) in options) {
            val on = value == selection
            Box(
                Modifier.weight(1f).heightIn(min = 40.dp).gmPress(role = Role.Tab) { onSelect(value) }
                    .background(if (on) GMColors.accent else Color.Transparent, CircleShape)
                    .semantics { selected = on },
                contentAlignment = Alignment.Center,
            ) {
                Text(title, color = if (on) GMColors.onAccent else Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
            }
        }
    }
}

/** Confirmação antes de algo que não dá para desfazer (gmActions com ação destrutiva) */
@Composable
internal fun ConfirmDialog(title: String, message: String?, action: String, onConfirm: () -> Unit, onDismiss: () -> Unit, destructive: Boolean = true) {
    AlertDialog(
        onDismissRequest = onDismiss, containerColor = GMColors.card, titleContentColor = Color.White, textContentColor = GMColors.dim,
        title = { Text(title, style = GMType.headline) },
        text = message?.let { { Text(it, style = GMType.subheadline) } },
        confirmButton = {
            TextButton({ onDismiss(); onConfirm() }) {
                Text(action, color = if (destructive) GMColors.danger else GMColors.accent, style = GMType.headline)
            }
        },
        dismissButton = { TextButton(onDismiss) { Text("Cancelar", color = Color.White, style = GMType.body) } },
    )
}

/** Duração em horas e minutos (`hoursText` do iOS): 45m, 1h 30m */
internal fun hoursText(minutes: Int): String = if (minutes < 60) "${minutes}m" else "${minutes / 60}h ${minutes % 60}m"

private val dayMonth = DateTimeFormatter.ofPattern("d 'de' MMM", ptBR)

/** Linha de atividade do histórico e do perfil (HomeView.swift `ActivityRow`) */
@Composable
internal fun ProfileActivityRow(a: ProfileActivity, onClick: (() -> Unit)? = null) {
    Row(
        Modifier.fillMaxWidth().then(if (onClick != null) Modifier.gmPress(onClick = onClick) else Modifier)
            .semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(Modifier.size(40.dp).background(GMColors.raised, GMRadius.s), contentAlignment = Alignment.Center) {
            Icon(Symbols.of(a.typeSymbol), null, tint = Color.White, modifier = Modifier.size(22.dp))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(a.typeName, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
            val date = a.date.atZone(ZoneId.systemDefault()).format(dayMonth)
            Text("${ActivityText.duration(a.minutes)} · ${ActivityText.effortLabel(a.effort)} · $date", color = GMColors.dim, style = GMType.caption)
        }
        if (a.fromHealth) {
            Icon(Icons.Filled.Favorite, null, tint = GMColors.health, modifier = Modifier.size(11.dp).semantics { contentDescription = "Do Health Connect" })
        }
        Text("+${a.xp} XP", color = GMColors.accent, style = GMType.subheadline.copy(fontWeight = FontWeight.Bold, fontFeatureSettings = "tnum"))
    }
}

/**
 * Número com casas decimais (GMDecimalField): vazio até tocar em "Adicionar", que começa no último valor; − e +
 * andam pelo passo e o campo aceita digitar com vírgula.
 */
@Composable
internal fun DecimalField(title: String, value: Double?, onChange: (Double?) -> Unit, step: Double, start: Double, unit: String = "kg") {
    var text by remember { mutableStateOf(value?.let(BodyEdits::fmt).orEmpty()) }
    LaunchedEffect(value) {
        val parsed = text.replace(',', '.').toDoubleOrNull()
        if (parsed != value) text = value?.let(BodyEdits::fmt).orEmpty()
    }
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(title, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold), modifier = Modifier.weight(1f))
        if (value == null) {
            Text("Adicionar", color = GMColors.accent, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold),
                 modifier = Modifier.gmPress { onChange(start) }.background(GMColors.raised, CircleShape).padding(horizontal = 14.dp, vertical = 9.dp))
        } else {
            val tenths = Math.round(value * 100).toInt()
            val stepHundredths = Math.round(step * 100).toInt()
            GMStepper(tenths, { onChange(it / 100.0) }, 0..100_000, step = stepHundredths, format = { "${BodyEdits.fmt(it / 100.0)} $unit" })
            Text("Limpar", color = GMColors.dim, style = GMType.caption, modifier = Modifier.gmPress { onChange(null) }.padding(6.dp))
        }
    }
    if (value != null) {
        GMTextField(text, { t ->
            val clean = t.filter { it.isDigit() || it == ',' || it == '.' }.take(7)
            text = clean
            clean.replace(',', '.').toDoubleOrNull()?.takeIf { it in 0.0..1000.0 }?.let(onChange)
        }, "$title ($unit)", keyboard = KeyboardOptions(keyboardType = KeyboardType.Decimal))
    }
}

/** Linha com pontos, eixo Y sem zero (o Chart com `includesZero: false` do iOS) */
@Composable
internal fun LineChart(points: List<Double>, modifier: Modifier = Modifier, label: String) {
    if (points.size < 2) return
    val min = points.min()
    val max = points.max()
    val span = (max - min).takeIf { it > 0 } ?: 1.0
    Canvas(modifier.fillMaxWidth().height(200.dp).semantics { contentDescription = label }) {
        val pad = 8.dp.toPx()
        val w = size.width - pad * 2
        val h = size.height - pad * 2
        fun at(i: Int) = Offset(pad + w * i / (points.size - 1), pad + h * (1 - ((points[i] - min) / span).toFloat()))
        for (k in 0..3) {
            val y = pad + h * k / 3
            drawLine(GMColors.stroke, Offset(pad, y), Offset(pad + w, y), strokeWidth = 1.dp.toPx())
        }
        val path = Path().apply { moveTo(at(0).x, at(0).y); for (i in 1 until points.size) lineTo(at(i).x, at(i).y) }
        drawPath(path, GMColors.accent, style = Stroke(width = 2.5.dp.toPx()))
        for (i in points.indices) drawCircle(GMColors.accent, radius = 3.dp.toPx(), center = at(i))
    }
}
