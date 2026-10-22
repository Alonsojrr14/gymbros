package com.alonsoalmeida.gymbros.ui.components

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.alonsoalmeida.gymbros.ui.theme.GMColors

/**
 * Tela padrão (ios/GymBros/DesignSystem/GMScreen.swift): cabeçalho próprio com botões nas pontas e o título grande
 * (32, heavy) embaixo; conteúdo rolável com espaçamento 18 e margem 16.
 */
@Composable
fun GMScreen(
    title: String,
    leading: @Composable RowScope.() -> Unit = {},
    trailing: @Composable RowScope.() -> Unit = {},
    bottomInset: Dp = 40.dp,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(Modifier.fillMaxSize().background(GMColors.bg).safeDrawingPadding()) {
        Column(Modifier.padding(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(Modifier.fillMaxWidth().heightIn(min = 40.dp), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                leading()
                Spacer(Modifier.weight(1f))
                trailing()
            }
            // iOS: lineLimit(1) com minimumScaleFactor(0.5)
            AutoShrinkText(title, maxSize = 32f, minSize = 16f)
        }
        Column(
            Modifier.verticalScroll(rememberScrollState()).padding(start = 16.dp, end = 16.dp, top = 4.dp, bottom = bottomInset),
            verticalArrangement = Arrangement.spacedBy(18.dp),
            content = content,
        )
    }
}

/** Texto de uma linha que diminui até `minSize` para caber (o `minimumScaleFactor` do iOS) */
@Composable
fun AutoShrinkText(text: String, maxSize: Float, minSize: Float, modifier: Modifier = Modifier, weight: FontWeight = FontWeight.ExtraBold,
                   color: Color = Color.White) {
    var size by remember(text) { mutableFloatStateOf(maxSize) }
    var ready by remember(text) { mutableStateOf(false) }
    Text(
        text, color = color, fontSize = size.sp, fontWeight = weight, maxLines = 1, softWrap = false, overflow = TextOverflow.Clip,
        modifier = modifier.drawWithContent { if (ready) drawContent() },
        onTextLayout = { r ->
            if (r.didOverflowWidth && size > minSize) size = maxOf(size * 0.92f, minSize) else ready = true
        },
    )
}

/** GMProgressBar (GMIndicators.swift): trilho em cápsula, 8 de altura; o preenchimento anima com mola */
@Composable
fun GMProgressBar(value: Double, modifier: Modifier = Modifier, tint: Color = GMColors.accent, height: Dp = 8.dp) {
    val v by animateFloatAsState(value.coerceIn(0.0, 1.0).toFloat(), spring(), label = "progress")
    BoxWithConstraints(modifier.fillMaxWidth().height(height).clip(CircleShape).background(GMColors.track)) {
        val w = if (value > 0) maxOf(maxWidth * v, height) else 0.dp
        Box(Modifier.width(w).fillMaxHeight().clip(CircleShape).background(tint))
    }
}

/** PersonAvatar (PublicProfile.swift): inicial do nome em preto sobre o verde, círculo com borda fina */
@Composable
fun PersonAvatar(name: String, size: Dp = 40.dp, modifier: Modifier = Modifier) {
    val initial = name.take(1).uppercase().ifEmpty { "?" }
    Box(
        modifier.size(size).clip(CircleShape).background(GMColors.accent).border(1.dp, GMColors.stroke, CircleShape),
        contentAlignment = Alignment.Center,
    ) { Text(initial, color = Color.Black, fontSize = (size.value * 0.42f).sp, fontWeight = FontWeight.Black) }
}
