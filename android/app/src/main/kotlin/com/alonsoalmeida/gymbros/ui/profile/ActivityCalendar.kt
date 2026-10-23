package com.alonsoalmeida.gymbros.ui.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.alonsoalmeida.gymbros.ui.components.GMCard
import com.alonsoalmeida.gymbros.ui.components.Symbols
import com.alonsoalmeida.gymbros.ui.components.gmPress
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMType
import java.time.Instant
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/** Um dia marcado no calendário (CalendarMark): o ícone do tipo do que foi feito */
data class CalendarMark(val id: String, val date: Instant, val symbol: String)

private val weekdays = listOf("Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb")
private val monthTitle = DateTimeFormatter.ofPattern("MMMM 'de' yyyy", ptBR)

/**
 * Calendário do mês (Profile/ProfileCalendar.swift `ActivityCalendar`): semana começando no domingo, dia com atividade
 * vira um círculo verde com o ícone do tipo e a contagem quando há mais de uma. Fotos de check-in ficam só no iPhone.
 */
@Composable
fun ActivityCalendar(marks: List<CalendarMark>, onDay: (LocalDate) -> Unit) {
    val zone = ZoneId.systemDefault()
    val now = YearMonth.now(zone)
    var month by rememberSaveable { mutableStateOf(now.toString()) }
    val ym = YearMonth.parse(month)
    val byDay = marks.groupBy { it.date.atZone(zone).toLocalDate() }
    val isCurrent = ym >= now
    val lead = ym.atDay(1).dayOfWeek.value % 7
    val cells: List<LocalDate?> = List(lead) { null } + (1..ym.lengthOfMonth()).map { ym.atDay(it) }
    val today = LocalDate.now(zone)

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Arrow(Icons.AutoMirrored.Filled.KeyboardArrowLeft, "Mês anterior", true) { month = ym.minusMonths(1).toString() }
            Spacer(Modifier.weight(1f))
            Text(ym.atDay(1).format(monthTitle).replaceFirstChar { it.uppercase() }, color = Color.White, style = GMType.title3.copy(fontWeight = FontWeight.ExtraBold))
            Spacer(Modifier.weight(1f))
            Arrow(Icons.AutoMirrored.Filled.KeyboardArrowRight, "Próximo mês", !isCurrent) { if (!isCurrent) month = ym.plusMonths(1).toString() }
        }
        Row(Modifier.fillMaxWidth()) {
            for (w in weekdays) Text(w, color = GMColors.dim, style = GMType.caption.copy(fontWeight = FontWeight.SemiBold),
                                     modifier = Modifier.weight(1f), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        }
        GMCard(padding = 10.dp) {
            for (week in cells.chunked(7)) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    for (i in 0 until 7) {
                        val d = week.getOrNull(i)
                        Box(Modifier.weight(1f).height(48.dp), contentAlignment = Alignment.Center) {
                            if (d != null) DayCell(d, byDay[d].orEmpty(), d == today) { onDay(d) }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun Arrow(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, enabled: Boolean, onClick: () -> Unit) {
    Box(Modifier.size(48.dp).gmPress(onClick = onClick).semantics { contentDescription = label }, contentAlignment = Alignment.Center) {
        Box(Modifier.size(34.dp).background(GMColors.raised, CircleShape), contentAlignment = Alignment.Center) {
            Icon(icon, null, tint = if (enabled) Color.White else GMColors.dim, modifier = Modifier.size(18.dp))
        }
    }
}

@Composable
private fun DayCell(d: LocalDate, items: List<CalendarMark>, today: Boolean, onClick: () -> Unit) {
    val label = if (items.isEmpty()) "${d.dayOfMonth}" else "${d.dayOfMonth}, ${items.size} atividade${if (items.size == 1) "" else "s"}"
    Box(
        Modifier.fillMaxWidth().height(48.dp).gmPress(enabled = items.isNotEmpty(), onClick = onClick).clearAndSetSemantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        val first = items.firstOrNull()
        if (first == null) {
            Text("${d.dayOfMonth}", color = if (today) GMColors.accent else Color.White,
                 style = GMType.body.copy(fontWeight = if (today) FontWeight.ExtraBold else FontWeight.Normal, fontFeatureSettings = "tnum"))
        } else {
            Box(Modifier.size(42.dp).background(GMColors.accent.copy(alpha = 0.9f), CircleShape), contentAlignment = Alignment.Center) {
                Icon(Symbols.of(first.symbol), null, tint = Color.Black, modifier = Modifier.size(20.dp))
            }
            if (items.size > 1) {
                Box(Modifier.offset(15.dp, (-15).dp).size(18.dp).background(Color.White, CircleShape), contentAlignment = Alignment.Center) {
                    Text("${items.size}", color = Color.Black, fontSize = 10.sp, fontWeight = FontWeight.ExtraBold)
                }
            }
        }
    }
}
