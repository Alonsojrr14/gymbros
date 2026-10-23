package com.alonsoalmeida.gymbros.ui.friends

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.alonsoalmeida.gymbros.domain.ActivityText
import com.alonsoalmeida.gymbros.domain.social.FeedPost
import com.alonsoalmeida.gymbros.domain.social.SocialText
import com.alonsoalmeida.gymbros.domain.social.label
import com.alonsoalmeida.gymbros.domain.social.symbol
import com.alonsoalmeida.gymbros.ui.components.GMCard
import com.alonsoalmeida.gymbros.ui.components.GMDateText
import com.alonsoalmeida.gymbros.ui.components.GMIconButton
import com.alonsoalmeida.gymbros.ui.components.GMSheet
import com.alonsoalmeida.gymbros.ui.components.Symbols
import com.alonsoalmeida.gymbros.ui.components.gmPress
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMRadius
import com.alonsoalmeida.gymbros.ui.theme.GMType
import java.time.LocalDate
import java.time.ZoneId

private val WEEKDAYS = listOf("Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb")

/**
 * Posts em calendário do mês (Profile/ProfileCalendar.swift `PostsCalendar` + `ActivityCalendar`): o tipo de cada dia
 * (fotos dos outros não vêm do servidor); tocar num dia mostra os posts dele, e cada um abre o check-in.
 */
@Composable
fun PostsCalendar(posts: List<FeedPost>, onOpen: (FeedPost) -> Unit) {
    val zone = ZoneId.systemDefault()
    val today = LocalDate.now(zone)
    var month by remember { mutableStateOf(today.withDayOfMonth(1)) }
    var day by remember { mutableStateOf<LocalDate?>(null) }
    val byDay = remember(posts) { posts.groupBy { it.date.atZone(zone).toLocalDate() } }
    val isCurrent = month == today.withDayOfMonth(1)
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            GMIconButton(Icons.AutoMirrored.Filled.KeyboardArrowLeft, "Mês anterior", { month = month.minusMonths(1) }, size = 34.dp)
            Text(SocialText.monthTitle(month), color = Color.White, style = GMType.title3.copy(fontWeight = FontWeight.Black),
                 textAlign = TextAlign.Center, modifier = Modifier.weight(1f))
            GMIconButton(Icons.AutoMirrored.Filled.KeyboardArrowRight, "Próximo mês", { if (!isCurrent) month = month.plusMonths(1) }, size = 34.dp)
        }
        Row(Modifier.fillMaxWidth()) {
            for (w in WEEKDAYS) Text(w, color = GMColors.dim, style = GMType.caption.copy(fontWeight = FontWeight.Bold), textAlign = TextAlign.Center,
                                     modifier = Modifier.weight(1f))
        }
        // Domingo primeiro, como o calendário do iOS em pt-BR
        val lead = month.dayOfWeek.value % 7
        val cells = List(lead) { null } + (1..month.lengthOfMonth()).map { month.withDayOfMonth(it) }
        GMCard(padding = 10.dp) {
            for (week in cells.chunked(7)) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    for (i in 0 until 7) {
                        val d = week.getOrNull(i)
                        Box(Modifier.weight(1f).height(48.dp), contentAlignment = Alignment.Center) {
                            if (d != null) DayCell(d, byDay[d].orEmpty(), d == today) { if (byDay[d] != null) day = d }
                        }
                    }
                }
            }
        }
    }
    day?.let { d ->
        GMSheet(onDismiss = { day = null }) {
            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(GMDateText.day(d.atStartOfDay(zone).toInstant()), color = Color.White, style = GMType.headline)
                for (p in byDay[d].orEmpty().sortedBy { it.date }) {
                    Row(Modifier.fillMaxWidth().gmPress { day = null; onOpen(p) }, verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Box(Modifier.size(58.dp).background(if (p.hasPhoto) GMColors.accent.copy(alpha = 0.3f) else GMColors.raised, GMRadius.m),
                            contentAlignment = Alignment.Center) { Icon(Symbols.of(p.kind.symbol), null, tint = Color.White, modifier = Modifier.size(26.dp)) }
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            Text(p.title, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold), maxLines = 2)
                            Text("${p.kind.label} · ${ActivityText.duration(p.minutes)} · ${SocialText.time(p.date)}", color = GMColors.dim, style = GMType.caption)
                        }
                        Icon(Icons.Filled.ChevronRight, null, tint = GMColors.dim, modifier = Modifier.size(16.dp))
                    }
                }
            }
        }
    }
}

@Composable
private fun DayCell(d: LocalDate, items: List<FeedPost>, today: Boolean, onClick: () -> Unit) {
    Box(Modifier.gmPress(onClick = onClick), contentAlignment = Alignment.Center) {
        val first = items.firstOrNull()
        if (first != null) {
            Box(Modifier.size(42.dp).background(GMColors.accent.copy(alpha = 0.9f), CircleShape), contentAlignment = Alignment.Center) {
                Icon(Symbols.of(first.kind.symbol), "${d.dayOfMonth}: ${items.size} post${if (items.size == 1) "" else "s"}", tint = Color.Black,
                     modifier = Modifier.size(18.dp))
            }
            if (items.size > 1) {
                Text("${items.size}", color = Color.Black, fontSize = 10.sp, fontWeight = FontWeight.Black, textAlign = TextAlign.Center,
                     modifier = Modifier.offset(15.dp, (-15).dp).size(18.dp).background(Color.White, CircleShape))
            }
        } else {
            Text("${d.dayOfMonth}", color = if (today) GMColors.accent else Color.White,
                 style = GMType.body.copy(fontWeight = if (today) FontWeight.Black else FontWeight.Normal, fontFeatureSettings = "tnum"))
        }
    }
}
