package com.alonsoalmeida.gymbros.ui.bros

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.alonsoalmeida.gymbros.domain.ActivityRecord
import com.alonsoalmeida.gymbros.domain.ActivityText
import com.alonsoalmeida.gymbros.domain.Attribute
import com.alonsoalmeida.gymbros.domain.Bro
import com.alonsoalmeida.gymbros.domain.MonsterForm
import com.alonsoalmeida.gymbros.domain.OwnerXP
import com.alonsoalmeida.gymbros.domain.Snapshot
import com.alonsoalmeida.gymbros.domain.Stage
import com.alonsoalmeida.gymbros.domain.bros.Dex
import com.alonsoalmeida.gymbros.domain.home.HomeData
import com.alonsoalmeida.gymbros.ui.auth.GMTextField
import com.alonsoalmeida.gymbros.ui.components.GMButton
import com.alonsoalmeida.gymbros.ui.components.GMButtonKind
import com.alonsoalmeida.gymbros.ui.components.GMIconButton
import com.alonsoalmeida.gymbros.ui.components.GMProgressBar
import com.alonsoalmeida.gymbros.ui.components.GMSection
import com.alonsoalmeida.gymbros.ui.components.GMSheet
import com.alonsoalmeida.gymbros.ui.components.LivingMonster
import com.alonsoalmeida.gymbros.ui.components.MonsterSprite
import com.alonsoalmeida.gymbros.ui.components.Symbols
import com.alonsoalmeida.gymbros.ui.components.gmPress
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMRadius
import com.alonsoalmeida.gymbros.ui.theme.GMType
import com.alonsoalmeida.gymbros.ui.theme.color

/**
 * Ficha do bro (Monsters.swift `broSheet` + BroHistory.swift): resumo, atributos, ligas, principal, apelido e BroBook,
 * com o que ele viveu. Arrastar para os lados passa pelos outros bros da Box.
 */
@Composable
internal fun BroSheet(home: HomeData, id: String, vm: BrosViewModel, liveIDs: Set<String>, isKnown: (MonsterForm) -> Boolean,
                      onSelect: (String) -> Unit, onDismiss: () -> Unit) {
    val monsters = home.roster.monsters
    val start = monsters.indexOfFirst { it.uuid == id }.coerceAtLeast(0)
    val pager = rememberPagerState(initialPage = start) { monsters.size }
    var renaming by remember { mutableStateOf<Bro?>(null) }
    var dexEntry by rememberSaveable { mutableStateOf<String?>(null) }
    LaunchedEffect(pager) { snapshotFlow { pager.currentPage }.collect { monsters.getOrNull(it)?.let { m -> onSelect(m.uuid) } } }
    if (monsters.isEmpty()) return onDismiss()

    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Column(Modifier.fillMaxSize().background(GMColors.bg).safeDrawingPadding()) {
            Box(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), contentAlignment = Alignment.Center) {
                if (monsters.size > 1) Pager(monsters.size, pager.currentPage)
                Row(Modifier.fillMaxWidth()) { GMIconButton(Icons.Filled.Close, "Fechar", onDismiss, size = 36.dp) }
            }
            HorizontalPager(pager, key = { monsters[it].uuid }) { page ->
                val m = monsters[page]
                val s = home.roster.snapshot(m.uuid)
                Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp).padding(top = 8.dp, bottom = 32.dp),
                       verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    Summary(home, m, s, m.uuid == home.roster.mainID, onMain = { vm.setMain(m.uuid) }, onRename = { renaming = m },
                            onDex = { dexEntry = s.form.id })
                    History(s, home.roster.records[m.uuid].orEmpty(), liveIDs)
                }
            }
        }
        renaming?.let { m ->
            var text by rememberSaveable(m.uuid) { mutableStateOf(m.name) }
            AlertDialog(
                onDismissRequest = { renaming = null }, containerColor = GMColors.card,
                title = { Text("Apelido", color = Color.White, style = GMType.headline) },
                text = {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text("Vazio usa o nome da forma atual.", color = GMColors.dim, style = GMType.subheadline)
                        GMTextField(text, { text = it }, "Apelido", onDone = { vm.rename(m.uuid, text); renaming = null })
                    }
                },
                confirmButton = { TextButton({ vm.rename(m.uuid, text); renaming = null }) { Text("Salvar", color = GMColors.accent) } },
                dismissButton = { TextButton({ renaming = null }) { Text("Cancelar", color = Color.White) } },
            )
        }
        dexEntry?.let { f ->
            val m = monsters.getOrNull(pager.currentPage)
            MonsterForm.byID(f)?.let { DexEntry(it, home.roster.snapshot(m?.uuid), isKnown) { dexEntry = null } }
        }
    }
}

/** Até 7 bros: um ponto para cada. Com mais, uma janela de 7 pontos que anda junto e o "3 de 24" ao lado */
@Composable
private fun Pager(n: Int, i: Int) {
    val window = 7
    val start = if (n <= window) 0 else (i - window / 2).coerceIn(0, n - window)
    val range = start until minOf(start + window, n)
    Row(Modifier.height(36.dp).semantics(mergeDescendants = true) { contentDescription = "Bro ${i + 1} de $n. Arraste para os lados para trocar" },
        horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
            for (k in range) {
                val edge = n > window && ((k == range.first && k > 0) || (k == range.last && k < n - 1))
                Box(Modifier.width(if (k == i) 16.dp else if (edge) 4.dp else 6.dp).height(if (edge) 4.dp else 6.dp)
                        .background(if (k == i) GMColors.accent else GMColors.track, CircleShape))
            }
        }
        if (n > window) Text("${i + 1} de $n", color = GMColors.dim, fontSize = 11.sp, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun Summary(home: HomeData, m: Bro, s: Snapshot, isMain: Boolean, onMain: () -> Unit, onRename: () -> Unit, onDex: () -> Unit) {
    val color = s.form.attribute?.color() ?: GMColors.accent
    val reps = home.leagues.filter { it.monsterUUID?.equals(m.uuid, ignoreCase = true) == true }
    Column(Modifier.fillMaxWidth().background(GMColors.card, GMRadius.card).border(1.dp, color.copy(alpha = 0.35f), GMRadius.card).padding(16.dp),
           verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(84.dp).background(color.copy(alpha = 0.15f), CircleShape), contentAlignment = Alignment.Center) {
                LivingMonster(s.form, Modifier.size(84.dp), progress = s.progress)
            }
            Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(m.displayName(s.form), color = Color.White, style = GMType.title3.copy(fontWeight = FontWeight.Bold), maxLines = 1,
                         overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                    if (isMain) BroBadge("Principal")
                }
                if (m.name.isNotEmpty() && s.stage != Stage.EGG) {
                    Text(s.form.name, color = GMColors.dim, style = GMType.caption.copy(fontWeight = FontWeight.SemiBold))
                }
                Text(if (s.stage == Stage.EGG) "Ovo · ${s.xpToNext ?: 0} XP para chocar" else "${s.stage.label} · Nível ${s.level} · ${s.totalXP.br()} XP",
                     color = GMColors.dim, style = GMType.caption)
                val from = s.inherited.lastOrNull()
                val at = s.arrivedAt
                if (from != null && at != null) {
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.SwapHoriz, null, tint = GMColors.trophy, modifier = Modifier.size(14.dp))
                        Text("Veio de ${from.name} em ${at.dayMonth()}", color = GMColors.trophy, style = GMType.caption.copy(fontWeight = FontWeight.SemiBold))
                    }
                }
                GMProgressBar(s.progress, tint = color, height = 5.dp)
            }
        }
        Attributes(s)
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.Flag, null, tint = GMColors.dim, modifier = Modifier.size(14.dp))
            Text(if (reps.isEmpty()) "Não representa nenhuma liga" else reps.joinToString(", ") { "${it.emoji} ${it.name}" },
                 color = GMColors.dim, style = GMType.caption)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (!isMain) GMButton("Principal", onMain, icon = Icons.Filled.Star, full = false, small = true)
            GMButton("Apelido", onRename, icon = Icons.Filled.Edit, kind = GMButtonKind.SECONDARY, full = false, small = true)
            GMButton("BroBook", onDex, icon = Icons.AutoMirrored.Filled.MenuBook, kind = GMButtonKind.SECONDARY, full = false, small = true)
        }
    }
}

/** Atributos de tudo que ele já treinou (barras relativas ao maior) */
@Composable
private fun Attributes(s: Snapshot) {
    if (s.lifetimeAttributes.values.none { it > 0 }) return
    val top = maxOf(s.lifetimeAttributes.values.maxOrNull() ?: 0.0, 1.0)
    Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
        for (a in Attribute.entries) {
            Row(Modifier.semantics(mergeDescendants = true) {}, horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Symbols.of(a), null, tint = a.color(), modifier = Modifier.size(14.dp))
                Text(a.label, color = Color.White, style = GMType.caption.copy(fontWeight = FontWeight.SemiBold), modifier = Modifier.width(84.dp))
                GMProgressBar((s.lifetimeAttributes[a] ?: 0.0) / top, Modifier.weight(1f), tint = a.color(), height = 6.dp)
            }
        }
    }
}

/** O que ele já viveu com você: números, de onde vem o XP, evoluções e os treinos que deram XP (inclusive os apagados) */
@Composable
private fun History(s: Snapshot, records: List<ActivityRecord>, liveIDs: Set<String>) {
    val workouts = remember(records) { records.sortedByDescending { it.date } }
    var showAll by rememberSaveable { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            if (s.inherited.isEmpty()) StatBox(s.totalXP.br(), "XP total", GMColors.accent)
            else {
                StatBox(s.myXP.br(), "seu XP", GMColors.accent)
                StatBox(s.inheritedXP.br(), "XP herdado", GMColors.dim)
            }
            StatBox("${workouts.size}", if (workouts.size == 1) "treino" else "treinos", Attribute.RESISTENCIA.color())
        }
        if (s.inherited.isNotEmpty()) XpOrigin(s)
        if (s.evolutions.isNotEmpty()) {
            GMSection("Evoluções") {
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(4.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    s.evolutions.forEachIndexed { i, e ->
                        if (i > 0) Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = GMColors.dim, modifier = Modifier.size(12.dp))
                        val arrived = e.date == s.arrivedAt
                        Column(Modifier.width(74.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            MonsterSprite(e.form, Modifier.size(40.dp))
                            Text(e.form.name, color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(if (arrived) "chegou ${e.date.dayMonth()}" else e.date.dayMonth(), color = if (arrived) GMColors.trophy else GMColors.dim,
                                 fontSize = 9.sp, fontFamily = FontFamily.Monospace, maxLines = 1)
                        }
                    }
                }
            }
        }
        if (workouts.isNotEmpty()) {
            val anyRetired = workouts.any { it.id !in liveIDs }
            GMSection("Treinos com ele", footer = if (anyRetired) "Treinos apagados saem da sua lista, mas o XP continua com o bro." else null) {
                val shown = if (showAll) workouts else workouts.take(5)
                shown.forEachIndexed { i, r ->
                    WorkoutRow(r, s.xpByActivity[r.id] ?: 0, r.id !in liveIDs)
                    if (i < shown.size - 1) BroDivider()
                }
                if (workouts.size > 5) {
                    Text(if (showAll) "Mostrar menos" else "Ver todos (${workouts.size})", color = GMColors.accent,
                         style = GMType.caption.copy(fontWeight = FontWeight.Bold), textAlign = TextAlign.Center,
                         modifier = Modifier.fillMaxWidth().gmPress { showAll = !showAll }.padding(vertical = 12.dp))
                }
            }
        } else {
            Text("Ainda sem treinos com este bro. Registre um treino com ele como principal ou numa liga que ele representa.",
                 color = GMColors.dim, style = GMType.caption)
        }
    }
}

@Composable
private fun androidx.compose.foundation.layout.RowScope.StatBox(value: String, label: String, tint: Color) {
    Column(Modifier.weight(1f).background(GMColors.card, GMRadius.l).padding(vertical = 10.dp).semantics(mergeDescendants = true) {},
           horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(value, color = tint, fontSize = 20.sp, fontWeight = FontWeight.ExtraBold, maxLines = 1)
        Text(label, color = GMColors.dim, style = GMType.caption2)
    }
}

/** De quem é o XP: barra dividida por dono (os anteriores em cinza, você em verde); com muitos donos, os 3 últimos e o resto somado */
@Composable
private fun XpOrigin(s: Snapshot) {
    val total = maxOf(s.totalXP, 1)
    var owners: List<OwnerXP> = s.inherited
    if (owners.size > 3) {
        val older = owners.dropLast(3)
        owners = listOf(OwnerXP("${older.size} donos antes", older.sumOf { it.xp })) + owners.takeLast(3)
    }
    val rows = owners.map { Triple("Com ${it.name}", it.xp, false) } + Triple("Com você", s.myXP, true)
    fun tint(i: Int, mine: Boolean) = if (mine) GMColors.accent else Color.White.copy(alpha = 0.18f + 0.12f * (i % 3))
    GMSection("De onde vem o XP", footer = "O XP de antes da troca é de quem treinou o ${s.form.name}. Os seus números contam só o que ele ganhou com você.") {
        BoxWithConstraints(Modifier.fillMaxWidth().height(8.dp)) {
            val usable = maxWidth - 2.dp * (rows.size - 1)
            Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                rows.forEachIndexed { i, r ->
                    val w = maxOf(if (r.second > 0) 4.dp else 0.dp, usable * (r.second.toFloat() / total))
                    Box(Modifier.width(w).height(8.dp).background(tint(i, r.third), CircleShape))
                }
            }
        }
        rows.forEachIndexed { i, r ->
            Row(Modifier.semantics(mergeDescendants = true) {}, horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(8.dp).background(tint(i, r.third), CircleShape))
                Text(r.first, color = Color.White, style = GMType.subheadline.copy(fontWeight = if (r.third) FontWeight.Bold else FontWeight.Normal),
                     maxLines = 1, modifier = Modifier.weight(1f))
                Text("${r.second.br()} XP", color = if (r.third) GMColors.accent else GMColors.dim, style = GMType.subheadline)
            }
        }
    }
}

@Composable
private fun WorkoutRow(r: ActivityRecord, xp: Int, retired: Boolean) {
    Row(Modifier.semantics(mergeDescendants = true) {}, horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(34.dp).background(GMColors.raised, GMRadius.s), contentAlignment = Alignment.Center) {
            Icon(Symbols.of(kindSymbol(r.kind.raw)), null, tint = if (retired) GMColors.dim else GMColors.accent, modifier = Modifier.size(18.dp))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(kindName(r.kind.raw), color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
                if (retired) BroBadge("apagado", GMColors.dim)
            }
            Text("${r.date.dayMonthTime()} · ${ActivityText.duration(r.minutes)}", color = GMColors.dim, style = GMType.caption)
        }
        Text("+$xp XP", color = if (xp > 0) GMColors.accent else GMColors.dim, style = GMType.subheadline.copy(fontWeight = FontWeight.Bold))
    }
}

// MARK: BroBook

/** Ficha de uma forma no BroBook (DexEntryView.swift): arte, tipos, números e onde o seu bro está */
@Composable
internal fun DexEntry(form: MonsterForm, snapshot: Snapshot, isKnown: (MonsterForm) -> Boolean, onDismiss: () -> Unit) {
    val known = isKnown(form)
    val tint = if (known) form.attribute?.color() ?: GMColors.accent else GMColors.dim
    val tint2 = if (known) form.attribute2?.color() ?: tint else GMColors.dim
    val number = remember(form) { "Nº %03d".format(maxOf(Dex.allForms().indexOf(form), 0)) }
    GMSheet(onDismiss) {
        Box(Modifier.fillMaxWidth().height(240.dp).background(Brush.verticalGradient(listOf(tint.copy(alpha = 0.45f), tint2.copy(alpha = 0.18f), GMColors.bg)), GMRadius.card),
            contentAlignment = Alignment.Center) {
            if (known) LivingMonster(form, Modifier.size(150.dp)) else BroSprite(form, Modifier.size(150.dp), hidden = true)
            Text(number, color = Color.White.copy(alpha = 0.8f), fontSize = 15.sp, fontWeight = FontWeight.ExtraBold, fontFamily = FontFamily.Monospace,
                 modifier = Modifier.align(Alignment.TopStart).padding(16.dp).background(Color.Black.copy(alpha = 0.25f), CircleShape)
                     .padding(horizontal = 12.dp, vertical = 6.dp))
        }
        Text(if (known) form.name else "???", color = Color.White, fontSize = 34.sp, fontWeight = FontWeight.ExtraBold, textAlign = TextAlign.Center)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            val types = listOfNotNull(form.attribute, form.attribute2)
            if (types.isEmpty() || !known) {
                Pill(if (form.stage == Stage.EGG) "Ovo" else if (known) "Sem galho" else "???", GMColors.raised, Color.White)
            } else for (a in types) Pill(a.label, a.color(), Color.Black, Symbols.of(a))
        }
        if (!known) {
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.VisibilityOff, null, tint = GMColors.dim, modifier = Modifier.size(14.dp))
                Text("Ainda não descoberta", color = GMColors.dim, style = GMType.caption.copy(fontWeight = FontWeight.Bold))
            }
        }
        Row(Modifier.fillMaxWidth().background(GMColors.card, GMRadius.card).padding(vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
            EntryStat(if (form.stage == Stage.EGG) "—" else if (known) form.speciesInfo.name else "???", "Espécie")
            EntryStat(form.stage.label, "Fase")
            EntryStat(form.stage.threshold.br(), "XP para chegar")
        }
        mineText(form, snapshot)?.let { text ->
            Row(Modifier.fillMaxWidth().background(GMColors.card, GMRadius.card).padding(14.dp), horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically) {
                LivingMonster(snapshot.form, Modifier.size(40.dp), progress = snapshot.progress)
                Text(text, color = Color.White, style = GMType.subheadline)
            }
        }
        Spacer(Modifier.height(8.dp))
    }
}

private fun mineText(form: MonsterForm, s: Snapshot): String? {
    if (s.form == form) {
        val next = s.xpToNext ?: return "Seu bro está nesta forma · nível ${s.level} · forma final"
        return "Seu bro está nesta forma · nível ${s.level} · faltam ${next.br()} XP para ${if (form.stage == Stage.EGG) "chocar" else "evoluir"}"
    }
    val e = s.evolutions.firstOrNull { it.form == form } ?: return null
    return "Seu bro passou por aqui em ${java.time.format.DateTimeFormatter.ofPattern("d 'de' MMM 'de' yyyy", ptBR).withZone(java.time.ZoneId.systemDefault()).format(e.date)}"
}

@Composable
private fun Pill(text: String, bg: Color, fg: Color, icon: androidx.compose.ui.graphics.vector.ImageVector? = null) {
    Row(Modifier.background(bg, CircleShape).padding(horizontal = 14.dp, vertical = 7.dp), horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically) {
        if (icon != null) Icon(icon, null, tint = fg, modifier = Modifier.size(14.dp))
        Text(text, color = fg, style = GMType.subheadline.copy(fontWeight = FontWeight.Bold))
    }
}

@Composable
private fun androidx.compose.foundation.layout.RowScope.EntryStat(value: String, label: String) {
    Column(Modifier.weight(1f).semantics(mergeDescendants = true) {}, horizontalAlignment = Alignment.CenterHorizontally,
           verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Text(value, color = Color.White, style = GMType.headline, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(label, color = GMColors.dim, style = GMType.caption)
    }
}
