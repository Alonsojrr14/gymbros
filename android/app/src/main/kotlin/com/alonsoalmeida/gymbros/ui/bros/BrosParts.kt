package com.alonsoalmeida.gymbros.ui.bros

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.painter.BitmapPainter
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.imageResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.alonsoalmeida.gymbros.domain.MonsterForm
import com.alonsoalmeida.gymbros.ui.components.MonsterSprite
import com.alonsoalmeida.gymbros.ui.components.Sprites
import com.alonsoalmeida.gymbros.ui.components.gmPress
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMType
import java.text.NumberFormat
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

internal val ptBR: Locale = Locale.forLanguageTag("pt-BR")

/** `Int.formatted()` do iOS em português: 1.500 */
internal fun Int.br(): String = NumberFormat.getIntegerInstance(ptBR).format(this)

/** `.dateTime.day().month(.abbreviated)`: "16 de jan." */
internal fun Instant.dayMonth(): String = DateTimeFormatter.ofPattern("d 'de' MMM", ptBR).withZone(ZoneId.systemDefault()).format(this)

/** "16 de jan., 08:00" */
internal fun Instant.dayMonthTime(): String = DateTimeFormatter.ofPattern("d 'de' MMM, HH:mm", ptBR).withZone(ZoneId.systemDefault()).format(this)

/** MonsterSprite com `hidden`: a silhueta preta das formas ainda não descobertas */
@Composable
internal fun BroSprite(form: MonsterForm, modifier: Modifier = Modifier, hidden: Boolean = false) {
    if (!hidden) return MonsterSprite(form, modifier)
    val res = Sprites.id(form.spriteWithFallback)
    if (res == 0) return MonsterSprite(form, modifier)
    Image(BitmapPainter(ImageBitmap.imageResource(res), filterQuality = FilterQuality.None), contentDescription = null,
          modifier = modifier.aspectRatio(1f), contentScale = ContentScale.Fit,
          colorFilter = ColorFilter.tint(Color.Black.copy(alpha = 0.85f)))
}

/** GMSegmented (GMChips.swift): trilho `raised` em cápsula, a opção escolhida em verde */
@Composable
internal fun BroSegmented(options: List<Pair<Int, String>>, selection: Int, onSelect: (Int) -> Unit) {
    Row(Modifier.fillMaxWidth().background(GMColors.raised, CircleShape).padding(4.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        for ((tag, title) in options) {
            val on = tag == selection
            Box(
                Modifier.weight(1f).heightIn(min = 40.dp).background(if (on) GMColors.accent else Color.Transparent, CircleShape)
                    .gmPress(role = Role.Tab) { onSelect(tag) }.semantics { selected = on; role = Role.Tab },
                contentAlignment = Alignment.Center,
            ) {
                Text(title, color = if (on) Color.Black else Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold),
                     maxLines = 1)
            }
        }
    }
}

/** GMBadge: texto curto em cápsula na cor dada */
@Composable
internal fun BroBadge(text: String, tint: Color = GMColors.accent) {
    Text(text, color = tint, fontSize = 11.sp, fontWeight = FontWeight.Bold, maxLines = 1,
         modifier = Modifier.background(tint.copy(alpha = 0.15f), CircleShape).padding(horizontal = 8.dp, vertical = 3.dp))
}

@Composable
internal fun BroDivider() = Box(Modifier.fillMaxWidth().height(1.dp).background(GMColors.stroke))
