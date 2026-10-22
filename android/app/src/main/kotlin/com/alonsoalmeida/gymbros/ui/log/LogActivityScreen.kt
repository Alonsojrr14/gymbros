package com.alonsoalmeida.gymbros.ui.log

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.FitnessCenter
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Warning
import com.alonsoalmeida.gymbros.ui.components.GMDateText
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.alonsoalmeida.gymbros.domain.ActivityText
import com.alonsoalmeida.gymbros.domain.Attribute
import com.alonsoalmeida.gymbros.domain.AttributeSplit
import com.alonsoalmeida.gymbros.domain.BroCatalog
import com.alonsoalmeida.gymbros.domain.Game
import com.alonsoalmeida.gymbros.domain.RuleClock
import com.alonsoalmeida.gymbros.domain.WorkoutType
import com.alonsoalmeida.gymbros.domain.backup.AccountEdits
import com.alonsoalmeida.gymbros.domain.home.HomeData
import com.alonsoalmeida.gymbros.domain.home.LogPreview
import com.alonsoalmeida.gymbros.ui.auth.GMTextField
import com.alonsoalmeida.gymbros.ui.components.GMChip
import com.alonsoalmeida.gymbros.ui.components.GMDateTimePicker
import com.alonsoalmeida.gymbros.ui.components.GMEffortPicker
import com.alonsoalmeida.gymbros.ui.components.GMModal
import com.alonsoalmeida.gymbros.ui.components.GMSection
import com.alonsoalmeida.gymbros.ui.components.GMSheet
import com.alonsoalmeida.gymbros.ui.components.GMStepper
import com.alonsoalmeida.gymbros.ui.components.GMCard
import com.alonsoalmeida.gymbros.ui.components.Symbols
import com.alonsoalmeida.gymbros.ui.components.gmPress
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMRadius
import com.alonsoalmeida.gymbros.ui.theme.GMType
import com.alonsoalmeida.gymbros.ui.theme.color
import java.text.Normalizer
import java.time.Instant
import java.time.ZoneId

/**
 * Nova atividade (Activities/LogActivityView.swift). No Android ainda não há treino feito (rotina/WOD) nem post no
 * perfil e nas ligas: a atividade vai para o histórico e dá XP aos bros, e o iPhone recebe na hora.
 */
@Composable
fun LogActivityScreen(visible: Boolean, home: HomeData, onDismiss: () -> Unit, onSave: (AccountEdits.NewActivity) -> Unit) {
    val context = LocalContext.current
    val haptic = LocalHapticFeedback.current
    val prefs = remember { context.getSharedPreferences("gymbros", Context.MODE_PRIVATE) }
    var type by remember(visible) { mutableStateOf(WorkoutType.byID(BroCatalog.classicType["musculacao"])!!.id) }
    var date by remember(visible) { mutableStateOf(Instant.now()) }
    var minutes by remember(visible) { mutableIntStateOf(60) }
    var effort by remember(visible) { mutableIntStateOf(6) }
    var note by remember(visible) { mutableStateOf("") }
    var place by remember(visible) { mutableStateOf<Pair<String, String>?>(null) }
    var choosingPlace by remember { mutableStateOf(false) }

    val kind = WorkoutType.byID(type)?.kind ?: com.alonsoalmeida.gymbros.domain.ActivityKind.OUTRO
    val split = AttributeSplit.split(kind, minutes, effort, healthType = type)
    val preview = LogPreview.compute(home.roster, kind, minutes, effort, date, split, RuleClock(ZoneId.systemDefault(), Instant.now()))

    // Treino que já ocupa esse horário: não salva (LogActivityView.swift `clash`)
    val clash = home.busy.firstOrNull { it.overlaps(date, minutes) }

    GMModal(visible, "Nova atividade", onDismiss, confirm = "Salvar", confirmEnabled = clash == null, onConfirm = {
        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
        onSave(AccountEdits.NewActivity(kind.raw, date, minutes, effort, note.trim(), type, AttributeSplit.encode(split), place?.first))
    }) {
        GMSection("Atividade") {
            ActivityTypePicker(type, home.typeHistory, prefs) { type = it }
        }

        GMSection("Duração") {
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                GMStepper(minutes, { minutes = it }, 5..Game.MAX_MINUTES, step = 5, format = ActivityText::duration)
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally)) {
                for (m in listOf(30, 45, 60, 90)) GMChip("$m min", minutes == m) { minutes = m }
            }
        }

        GMSection(footer = "Quão puxado foi, de 1 (bem leve) a 10 (no limite).") {
            GMEffortPicker(effort) { effort = it }
        }

        GMSection("Quando") {
            GMDateTimePicker(date) { date = it }
            GMTextField(note, { note = it }, "Observação (opcional)")
            // Onde foi (opcional): vai para a atividade
            if (home.gyms.isNotEmpty()) {
                Box(Modifier.fillMaxWidth().height(1.dp).background(GMColors.stroke))
                Row(Modifier.fillMaxWidth().gmPress { choosingPlace = true }, verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Icon(Icons.Filled.Place, null, tint = if (place == null) GMColors.dim else GMColors.accent, modifier = Modifier.size(22.dp))
                    Column(Modifier.weight(1f)) {
                        Text(place?.second ?: "Sem local", color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
                        Text("Onde foi", color = GMColors.dim, style = GMType.caption)
                    }
                    Text("›", color = GMColors.dim, fontSize = 20.sp)
                }
            }
        }

        if (clash != null) {
            GMCard {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(Icons.Filled.Warning, null, tint = GMColors.warning, modifier = Modifier.size(20.dp))
                    Text("Já tem um treino nesse horário: ${clash.typeName}, ${GMDateText.time(clash.start)}–${GMDateText.time(clash.end)}. Mude o horário ou a duração.",
                         color = GMColors.warning, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
                }
            }
        }
        GMCard { PreviewView(preview) }

        GMSection("Postar em", footer = "Postar no perfil e nas ligas ainda está chegando no Android. A atividade fica no seu histórico, dá XP aos bros e aparece no iPhone.") {
            Text("Só no histórico, por enquanto.", color = GMColors.dim, style = GMType.footnote)
        }
    }

    if (choosingPlace) {
        GMSheet(onDismiss = { choosingPlace = false }) {
            Text("Onde foi?", color = Color.White, style = GMType.headline)
            for (g in home.gyms) {
                SheetAction(g.second, Icons.Filled.FitnessCenter) { place = g; choosingPlace = false }
            }
            SheetAction("Sem local", Icons.Filled.Close) { place = null; choosingPlace = false }
        }
    }
}

@Composable
private fun SheetAction(title: String, icon: androidx.compose.ui.graphics.vector.ImageVector, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().gmPress(onClick = onClick).background(GMColors.raised, GMRadius.m).padding(14.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(icon, null, tint = GMColors.accent, modifier = Modifier.size(20.dp))
        Text(title, color = Color.White, style = GMType.body)
    }
}

@Composable
private fun PreviewView(p: LogPreview) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("+${p.xp} XP", color = GMColors.accent, fontSize = 22.sp, fontWeight = FontWeight.Black,
                 style = GMType.body.copy(fontFeatureSettings = "tnum"))
            Spacer(Modifier.weight(1f))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (a in Attribute.entries) {
                    val v = p.attributeXP(a) ?: continue
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                        Icon(Symbols.of(a), null, tint = a.color(), modifier = Modifier.size(13.dp))
                        Text("+$v", color = a.color(), style = GMType.caption.copy(fontWeight = FontWeight.SemiBold, fontFeatureSettings = "tnum"))
                    }
                }
            }
        }
        p.message?.let {
            if (p.grows.isNotEmpty()) Text(it, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.Bold))
            else Text(it, color = GMColors.dim, style = GMType.caption)
        }
    }
}

/**
 * Atalhos com o que você mais faz e "Todas" para os ~80 tipos, com busca (WorkoutTypes.swift `ActivityTypePicker`).
 * Os 7 atalhos: treinos salvos recentemente + escolhas recentes; os clássicos completam. Fixados ao abrir.
 */
@Composable
private fun ActivityTypePicker(type: Long, history: List<Long>, prefs: android.content.SharedPreferences, onPick: (Long) -> Unit) {
    var browsing by remember { mutableStateOf(false) }
    val slots = remember { mutableStateOf(ranked(history, recent(prefs))) }
    LaunchedEffect(type) {
        // Escolhido fora dos atalhos: fica no último lugar
        if (type !in slots.value && slots.value.isNotEmpty()) slots.value = slots.value.dropLast(1) + type
        prefs.edit().putString("recentWorkoutTypes", (listOf(type) + recent(prefs).filter { it != type }).take(10).joinToString(",")).apply()
    }
    val tiles = slots.value.mapNotNull { WorkoutType.byID(it) }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        for (row in (tiles.map { it as WorkoutType? } + listOf(null)).chunked(4)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (t in row) {
                    Box(Modifier.weight(1f)) {
                        if (t != null) Tile(t.name, Symbols.of(BroCatalog.workoutSymbols[t.id] ?: ""), t.id == type) { onPick(t.id) }
                        else Tile("Todas", Icons.Filled.Search, false) { browsing = true }
                    }
                }
                repeat(4 - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
    if (browsing) WorkoutTypeList(type, { onPick(it); browsing = false }) { browsing = false }
}

private fun recent(prefs: android.content.SharedPreferences): List<Long> =
    prefs.getString("recentWorkoutTypes", "").orEmpty().split(",").mapNotNull { it.toLongOrNull() }

private fun ranked(history: List<Long>, recent: List<Long>): List<Long> {
    val score = LinkedHashMap<Long, Double>()
    for (id in history.take(60)) score[id] = (score[id] ?: 0.0) + 1
    for ((i, id) in recent.take(10).withIndex()) score[id] = (score[id] ?: 0.0) + 2 - i * 0.15
    val classics = com.alonsoalmeida.gymbros.domain.ActivityKind.entries.mapNotNull { BroCatalog.classicType[it.raw] }
    fun pos(id: Long) = classics.indexOf(id).let { if (it < 0) 99 else it }
    val used = score.keys.sortedWith(compareByDescending<Long> { score[it] }.thenBy { pos(it) }.thenBy { it })
    val out = mutableListOf<Long>()
    for (id in used + classics) if (WorkoutType.byID(id) != null && id !in out && out.size < 7) out += id
    return out
}

@Composable
private fun Tile(name: String, icon: androidx.compose.ui.graphics.vector.ImageVector, on: Boolean, onClick: () -> Unit) {
    val haptic = LocalHapticFeedback.current
    Column(
        Modifier.fillMaxWidth().heightIn(min = 66.dp)
            .gmPress { haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove); onClick() }
            .background(if (on) GMColors.accent.copy(alpha = 0.2f) else GMColors.raised, GMRadius.m)
            .border(1.5.dp, if (on) GMColors.accent else Color.Transparent, GMRadius.m)
            .padding(horizontal = 4.dp, vertical = 8.dp)
            .semantics { selected = on },
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterVertically),
    ) {
        val tint = if (on) GMColors.accent else Color.White
        Icon(icon, null, tint = tint, modifier = Modifier.size(26.dp))
        Text(name, color = tint, style = GMType.caption2.copy(fontWeight = FontWeight.SemiBold), maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

private fun fold(s: String) = Normalizer.normalize(s, Normalizer.Form.NFD).replace(Regex("\\p{M}"), "").lowercase()

/** Todos os tipos, por seção, com busca (WorkoutTypes.swift `WorkoutTypeList`) */
@Composable
private fun WorkoutTypeList(selection: Long, onPick: (Long) -> Unit, onDismiss: () -> Unit) {
    var query by remember { mutableStateOf("") }
    GMSheet(onDismiss) {
        Text("Tipo de treino", color = Color.White, style = GMType.headline)
        GMTextField(query, { query = it }, "Buscar treino")
        val q = fold(query.trim())
        val found = WorkoutType.all.filter { t -> q.isEmpty() || fold(t.name).contains(q) || BroCatalog.workoutAliases[t.id].orEmpty().any { fold(it).contains(q) } }
        if (found.isEmpty()) Text("Nenhum resultado para \"$query\"", color = GMColors.dim, style = GMType.subheadline)
        LazyColumn(Modifier.fillMaxWidth().heightIn(max = 560.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            for (section in found.map { it.section }.distinct()) {
                item(key = "s-$section") {
                    Text(section.uppercase(), color = GMColors.dim, style = GMType.caption.copy(fontWeight = FontWeight.Bold),
                         modifier = Modifier.padding(start = 4.dp, top = 14.dp, bottom = 6.dp))
                }
                items(found.filter { it.section == section }, key = { it.id }) { t ->
                    val on = t.id == selection
                    Row(Modifier.fillMaxWidth().gmPress { onPick(t.id) }.background(GMColors.card).padding(horizontal = 14.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                        Box(Modifier.size(36.dp).background(if (on) GMColors.accent else GMColors.accent.copy(alpha = 0.15f), GMRadius.s),
                            contentAlignment = Alignment.Center) {
                            Icon(Symbols.of(BroCatalog.workoutSymbols[t.id] ?: ""), null, tint = if (on) Color.Black else GMColors.accent,
                                 modifier = Modifier.size(20.dp))
                        }
                        Text(t.name, color = Color.White, style = GMType.body, modifier = Modifier.weight(1f))
                        if (on) Icon(Icons.Filled.Check, null, tint = GMColors.accent, modifier = Modifier.size(20.dp))
                    }
                }
            }
        }
    }
}

