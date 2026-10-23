package com.alonsoalmeida.gymbros.ui.train

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.alonsoalmeida.gymbros.data.train.PersonalRecord
import com.alonsoalmeida.gymbros.data.train.TrainData
import com.alonsoalmeida.gymbros.data.train.TrainEdits
import com.alonsoalmeida.gymbros.data.train.TrainScope
import com.alonsoalmeida.gymbros.data.train.WgerLibrary
import com.alonsoalmeida.gymbros.domain.roundHalfAwayFromZero
import com.alonsoalmeida.gymbros.domain.train.CustomExercise
import com.alonsoalmeida.gymbros.domain.train.Exercise
import com.alonsoalmeida.gymbros.domain.train.ExerciseType
import com.alonsoalmeida.gymbros.domain.train.Exercises
import com.alonsoalmeida.gymbros.domain.train.Muscle
import com.alonsoalmeida.gymbros.domain.train.MuscleGroup
import com.alonsoalmeida.gymbros.domain.train.PRBook
import com.alonsoalmeida.gymbros.domain.train.Progression
import com.alonsoalmeida.gymbros.domain.train.SetLog
import com.alonsoalmeida.gymbros.domain.train.TrainingGoal
import com.alonsoalmeida.gymbros.domain.train.Weeks
import com.alonsoalmeida.gymbros.domain.train.clock
import com.alonsoalmeida.gymbros.domain.train.meters
import com.alonsoalmeida.gymbros.domain.train.muscleLoad
import com.alonsoalmeida.gymbros.domain.train.normalized
import com.alonsoalmeida.gymbros.ui.AppEnv
import com.alonsoalmeida.gymbros.ui.auth.GMTextField
import com.alonsoalmeida.gymbros.ui.components.ExerciseImages
import com.alonsoalmeida.gymbros.ui.components.GMAction
import com.alonsoalmeida.gymbros.ui.components.GMActions
import com.alonsoalmeida.gymbros.ui.components.GMBadge
import com.alonsoalmeida.gymbros.ui.components.GMButton
import com.alonsoalmeida.gymbros.ui.components.GMButtonKind
import com.alonsoalmeida.gymbros.ui.components.GMCard
import com.alonsoalmeida.gymbros.ui.components.GMChoiceChips
import com.alonsoalmeida.gymbros.ui.components.GMDateTimePicker
import com.alonsoalmeida.gymbros.ui.components.GMDecimalField
import com.alonsoalmeida.gymbros.ui.components.GMDivider
import com.alonsoalmeida.gymbros.ui.components.GMEmptyState
import com.alonsoalmeida.gymbros.ui.components.GMFullScreen
import com.alonsoalmeida.gymbros.ui.components.GMIconButton
import com.alonsoalmeida.gymbros.ui.components.GMIconLabel
import com.alonsoalmeida.gymbros.ui.components.GMModal
import com.alonsoalmeida.gymbros.ui.components.GMRow
import com.alonsoalmeida.gymbros.ui.components.GMScreen
import com.alonsoalmeida.gymbros.ui.components.GMSearchField
import com.alonsoalmeida.gymbros.ui.components.GMSection
import com.alonsoalmeida.gymbros.ui.components.GMSegmented
import com.alonsoalmeida.gymbros.ui.components.GMTextArea
import com.alonsoalmeida.gymbros.ui.components.GMTintIconButton
import com.alonsoalmeida.gymbros.ui.components.GMValueRow
import com.alonsoalmeida.gymbros.ui.components.TrainIcons
import com.alonsoalmeida.gymbros.ui.components.gmPress
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMRadius
import com.alonsoalmeida.gymbros.ui.theme.GMType
import kotlinx.coroutines.delay
import java.time.Instant
import java.time.ZoneId

// Exercícios (ios/GymBros/Exercises e Train/ExerciseStatsView.swift, WeeklyVolume.swift, PR.swift). O mapa do corpo do
// iOS (pacote MuscleMap) não tem equivalente no Android: os músculos aparecem em barras com a mesma escala de calor.

/** Cabeçalho do GMModal (X à esquerda, título no meio), para as listas longas que precisam ser preguiçosas */
@Composable
private fun ModalHeader(title: String, onDismiss: () -> Unit) {
    Box(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), contentAlignment = Alignment.Center) {
        Text(title, color = Color.White, style = GMType.headline)
        Row(Modifier.fillMaxWidth()) { GMIconButton(Icons.Filled.Close, "Fechar", onDismiss, size = 36.dp) }
    }
}

private sealed interface PickerRow {
    data class Header(val title: String) : PickerRow
    data class Item(val e: Exercise, val section: String, val last: Boolean) : PickerRow
}

/**
 * Biblioteca e seletor de exercícios (RoutineEditView.swift `ExercisePicker`): busca, criar, "Meus exercícios", filtro
 * Todos/Academia/CrossFit e um card por grupo. Sem `onPick`, tocar abre os detalhes.
 */
@Composable
internal fun ExercisePickerModal(visible: Boolean, env: AppEnv, data: TrainData, onPick: ((Exercise) -> Unit)?, onDismiss: () -> Unit) {
    if (!visible) return
    var search by remember { mutableStateOf("") }
    var filter by remember { mutableIntStateOf(0) }
    var info by remember { mutableStateOf<Exercise?>(null) }
    var creating by remember { mutableStateOf(false) }
    var credits by remember { mutableStateOf(false) }
    val rows = remember(search, filter, data.customs) {
        val out = mutableListOf<PickerRow>()
        fun section(title: String, list: List<Exercise>) {
            if (list.isEmpty()) return
            out += PickerRow.Header(title)
            list.forEachIndexed { i, e -> out += PickerRow.Item(e, title, i == list.size - 1) }
        }
        section("Meus exercícios", data.customs.map { it.exercise }.filter { Exercises.matches(it, search) }.sortedBy { it.name })
        val cross = Exercises.builtIn.filter { it.isCrossfit && Exercises.matches(it, search) }
        if (filter != 1 && cross.isNotEmpty()) section("CrossFit · ${cross.size}", cross)
        if (filter != 2) for (g in MuscleGroup.entries) {
            val items = Exercises.builtIn.filter { it.group == g && !it.crossfit && Exercises.matches(it, search) }
            if (items.isNotEmpty()) section("${g.label} · ${items.size}", items)
        }
        out
    }
    GMFullScreen(true, onDismiss) {
        ModalHeader("Exercícios", onDismiss)
        LazyColumn(Modifier.fillMaxSize(), contentPadding = androidx.compose.foundation.layout.PaddingValues(start = 16.dp, end = 16.dp, bottom = 40.dp)) {
            item(key = "top") {
                Column(Modifier.padding(top = 16.dp, bottom = 8.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
                    GMSearchField(search, { search = it }, "Buscar exercício")
                    GMButton("Criar exercício", { creating = true }, icon = TrainIcons.of("plus"), kind = GMButtonKind.SECONDARY)
                }
            }
            var segmentShown = false
            for (r in rows) {
                when (r) {
                    is PickerRow.Header -> {
                        if (r.title != "Meus exercícios" && !segmentShown) {
                            segmentShown = true
                            item(key = "seg") { Box(Modifier.padding(vertical = 10.dp)) { GMSegmented(listOf(0 to "Todos", 1 to "Academia", 2 to "CrossFit"), filter, { filter = it }) } }
                        }
                        item(key = "h-${r.title}", contentType = "h") {
                            Text(r.title.uppercase(), color = GMColors.dim, style = GMType.caption.copy(fontWeight = FontWeight.Bold, letterSpacing = 0.6.sp),
                                 modifier = Modifier.padding(start = 4.dp, top = 18.dp, bottom = 8.dp))
                        }
                    }
                    is PickerRow.Item -> item(key = "${r.section}-${r.e.id}", contentType = "e") {
                        Column(Modifier.background(GMColors.card).padding(horizontal = 16.dp)) {
                            Row(Modifier.fillMaxWidth().heightIn(min = 56.dp).gmPress {
                                if (onPick != null) { onPick(r.e); onDismiss() } else info = r.e
                            }.padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                Thumb(r.e.id)
                                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                    Text(r.e.name, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
                                    Text(r.e.equipment, color = GMColors.dim, style = GMType.caption)
                                }
                                if (onPick != null) GMIconButton(TrainIcons.of("info"), "Como fazer", { info = r.e }, size = 30.dp) else Chevron()
                            }
                            if (!r.last) GMDivider()
                        }
                    }
                }
            }
            if (!segmentShown) item(key = "seg") { Box(Modifier.padding(vertical = 10.dp)) { GMSegmented(listOf(0 to "Todos", 1 to "Academia", 2 to "CrossFit"), filter, { filter = it }) } }
            item(key = "credits") {
                Box(Modifier.fillMaxWidth().padding(top = 18.dp)) {
                    GMButton("Imagens: wger, Everkinetic e Commons · créditos", { credits = true }, kind = GMButtonKind.GHOST, small = true)
                }
            }
        }
    }
    info?.let { ExerciseInfoModal(env, data, it) { info = null } }
    CreditsModal(credits) { credits = false }
    CustomExerciseForm(creating, env, null, onCreate = { e -> if (onPick != null) { onPick(e); onDismiss() } }) { creating = false }
}

/** Detalhe do exercício: fotos, vídeo, ficha, como fazer, nota, músculos (MuscleViews.swift `ExerciseInfoView`) */
@Composable
internal fun ExerciseInfoModal(env: AppEnv, data: TrainData, exercise: Exercise, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val wger = remember(exercise.id) { WgerLibrary.entry(context, exercise.id) }
    var editing by remember { mutableStateOf(false) }
    var credits by remember { mutableStateOf(false) }
    fun open(url: String) = runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
    GMModal(true, exercise.name, onDismiss) {
        val assets = wger?.images?.mapNotNull { it.asset }.orEmpty()
        if (assets.isNotEmpty()) ExercisePhotos(assets, wger!!.images)
        wger?.videos?.firstOrNull()?.let { v ->
            v.url?.let { url ->
                GMButton("Ver vídeo de demonstração", { open(url) }, icon = TrainIcons.of("play.fill"))
                CreditLine("Vídeo", v.credit.author, v.credit.license, wger.url)
            }
        }
        Row(Modifier.fillMaxWidth().heightIn(min = 50.dp).gmPress { open("https://www.youtube.com/results?search_query=" + Uri.encode(exercise.videoQuery)) }
                .background(GMColors.video, GMRadius.l).padding(vertical = 14.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
            verticalAlignment = Alignment.CenterVertically) {
            Icon(TrainIcons.of("play.fill"), null, tint = Color.White)
            Text("Buscar vídeos no YouTube", color = Color.White, style = GMType.headline)
        }
        GMCard {
            GMValueRow("Grupo", exercise.group.label)
            GMValueRow("Equipamento", exercise.equipment)
            GMValueRow("Registro", exercise.type.label)
        }
        val steps = exercise.instructions.ifEmpty { wger?.steps.orEmpty() }
        if (steps.isNotEmpty()) {
            GMSection("Como fazer", footer = if (exercise.instructions.isEmpty()) wger?.let {
                "Texto: ${it.text.author} · ${it.text.license} · ${WgerLibrary.sourceName(it.url)}" + if (it.language == "en") " (em inglês: a tradução no aparelho é só do iPhone)" else ""
            } else null) {
                steps.forEachIndexed { i, step ->
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text("${i + 1}", color = GMColors.accent, style = GMType.subheadline.copy(fontWeight = FontWeight.Bold))
                        Text(step, color = Color.White, style = GMType.subheadline)
                    }
                }
            }
        }
        data.notes[exercise.id]?.takeIf { it.isNotEmpty() }?.let { GMSection("Sua nota") { Text(it, color = Color.White, style = GMType.subheadline) } }
        Exercises.customNotes[exercise.id]?.takeIf { it.isNotEmpty() }?.let { GMSection("Descrição") { Text(it, color = Color.White, style = GMType.subheadline) } }
        val m = exercise.muscles
        GMSection("Músculos") {
            MuscleBars(m.primary.associateWith { 1.0 } + m.secondary.filter { it !in m.primary }.associateWith { 0.45 }, raw = true)
            Text("Principal: " + m.primary.joinToString(", ") { it.label }, color = Color.White, style = GMType.caption)
            if (m.secondary.isNotEmpty()) Text("Auxiliar: " + m.secondary.joinToString(", ") { it.label }, color = GMColors.dim, style = GMType.caption)
        }
        if (exercise.isCustom) GMButton("Editar exercício", { editing = true }, icon = TrainIcons.of("pencil"), kind = GMButtonKind.SECONDARY)
        if (wger != null) GMButton("Créditos e licenças", { credits = true }, icon = TrainIcons.of("c.circle"), kind = GMButtonKind.GHOST, small = true)
    }
    CreditsModal(credits) { credits = false }
    CustomExerciseForm(editing, env, data.customs.firstOrNull { it.exerciseID == exercise.id }, onCreate = null) { editing = false }
}

/** Imagens do exercício alternando como animação, com o crédito embaixo (Wger.swift `ExercisePhotos`) */
@Composable
private fun ExercisePhotos(assets: List<String>, media: List<com.alonsoalmeida.gymbros.data.train.WgerMedia>) {
    val context = LocalContext.current
    var frame by remember { mutableIntStateOf(0) }
    LaunchedEffect(assets.size) { if (assets.size > 1) while (true) { delay(1200); frame = (frame + 1) % assets.size } }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Box(Modifier.fillMaxWidth().height(240.dp).background(Color.White, GMRadius.m), contentAlignment = Alignment.Center) {
            val img = remember(assets[frame]) { ExerciseImages.load(context, assets[frame]) }
            if (img != null) Image(img, null, contentScale = ContentScale.Fit, modifier = Modifier.fillMaxSize().padding(10.dp))
        }
        media.getOrNull(frame)?.let { CreditLine("Imagem", it.credit.author, it.credit.license, it.source) }
    }
}

@Composable
private fun CreditLine(prefix: String, author: String, license: String, source: String?) {
    Text("$prefix: $author · $license" + (source?.let { " · ${WgerLibrary.sourceName(it)}" } ?: ""), color = GMColors.dim, style = GMType.caption2, maxLines = 1,
         overflow = TextOverflow.Ellipsis)
}

/** Créditos e licenças (Wger.swift `CreditsView`) */
@Composable
internal fun CreditsModal(visible: Boolean, onDismiss: () -> Unit) {
    if (!visible) return
    val context = LocalContext.current
    fun open(url: String) = runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
    GMModal(true, "Créditos e licenças", onDismiss) {
        GMSection("Exercícios: wger, Everkinetic e Commons", footer = "Imagens, vídeos e instruções de exercícios do projeto wger (wger.de), ilustrações do Everkinetic (github.com/everkinetic/data, de Greg Priday) e fotos do Wikimedia Commons (domínio público, CC0, CC BY e CC BY-SA), sob Creative Commons. Cada imagem mostra o autor e a licença. Instruções em inglês aparecem como vieram; as adaptações seguem a mesma licença (CC BY-SA).") {
            GMRow("wger.de", TrainIcons.of("link"), GMColors.accent, onClick = { open("https://wger.de") })
            GMRow("Everkinetic", TrainIcons.of("link"), GMColors.accent, onClick = { open("https://github.com/everkinetic/data") })
            GMRow("Wikimedia Commons", TrainIcons.of("link"), GMColors.accent, onClick = { open("https://commons.wikimedia.org") })
            GMDivider()
            for ((c, n) in remember { WgerLibrary.allCredits(context) }) {
                Row(Modifier.fillMaxWidth().gmPress { open(c.licenseURL) }, verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(c.author, color = Color.White, style = GMType.subheadline)
                        Text(c.license, color = GMColors.dim, style = GMType.caption)
                    }
                    Text("$n ite${if (n == 1) "m" else "ns"}", color = GMColors.dim, style = GMType.caption)
                }
            }
        }
        GMSection("Vídeos do YouTube", footer = "O botão de vídeo abre uma busca no YouTube; os vídeos são de seus autores.") {}
        GMSection("Bros", footer = "Artes dos bros, telas e textos do GymBros são próprios.") {}
    }
}

/** Criar ou editar exercício personalizado (CustomExerciseForm.swift) */
@Composable
internal fun CustomExerciseForm(visible: Boolean, env: AppEnv, editing: CustomExercise?, onCreate: ((Exercise) -> Unit)?, onDismiss: () -> Unit) {
    if (!visible) return
    var name by remember { mutableStateOf(editing?.name.orEmpty()) }
    var group by remember { mutableStateOf(editing?.let { MuscleGroup.of(it.group) } ?: if (editing == null) MuscleGroup.PEITO else MuscleGroup.CORPO) }
    var equipment by remember { mutableStateOf(editing?.equipment ?: "Máquina") }
    var type by remember { mutableStateOf(editing?.let { ExerciseType.of(it.type) } ?: ExerciseType.WEIGHTED) }
    var notes by remember { mutableStateOf(editing?.notes.orEmpty()) }
    var confirmDelete by remember { mutableStateOf(false) }
    GMModal(true, if (editing == null) "Novo exercício" else "Editar exercício", onDismiss, confirm = "Salvar", confirmEnabled = name.isNotBlank(), onConfirm = {
        val c = CustomExercise(editing?.uuid ?: TrainEdits.newID(), name.trim(), group.raw, equipment, type.raw, notes)
        TrainScope.edit(env) { TrainEdits.saveCustom(it, c) }
        if (editing == null) {
            // Registra já, para a tela que chamou usar o exercício na hora
            Exercises.add(c)
            onCreate?.invoke(c.exercise)
        }
        onDismiss()
    }) {
        GMSection("Nome") { GMTextField(name, { name = it }, "Nome do exercício") }
        GMSection(footer = "Peso do corpo progride em reps (dá para somar carga extra). Por tempo registra segundos.") {
            GMChoiceChips(MuscleGroup.entries.map { it to it.label }, group, { group = it }, title = "Grupo muscular")
            GMDivider()
            GMChoiceChips(Exercises.equipments.map { it to it }, equipment, { equipment = it }, title = "Equipamento")
            GMDivider()
            GMChoiceChips(ExerciseType.entries.map { it to it.label }, type, { type = it }, title = "Registro")
        }
        GMSection("Descrição (opcional)") { GMTextArea(notes, { notes = it }, "Como fazer, ajustes da máquina…") }
        if (editing != null) {
            GMSection(footer = "O histórico de treinos com ele continua salvo.") {
                GMRow("Apagar exercício", TrainIcons.of("trash"), GMColors.danger, onClick = { confirmDelete = true })
            }
        }
    }
    GMActions(confirmDelete, { confirmDelete = false }, title = "Apagar $name?", actions = listOf(GMAction("Apagar", TrainIcons.of("trash"), true) {
        editing?.let { e -> TrainScope.edit(env) { TrainEdits.deleteCustom(it, e.uuid) } }
        onDismiss()
    }))
}

/** Escala de calor do mapa muscular do iOS: cinza, amarelo, laranja e vermelho */
private fun heat(v: Double): Color {
    val stops = listOf(Color(0xFF4D4D4D), Color(0xFFFFD60A), Color(0xFFFF9F0A), Color(0xFFFF453A))
    val x = v.coerceIn(0.0, 1.0) * (stops.size - 1)
    val i = x.toInt().coerceAtMost(stops.size - 2)
    val t = (x - i).toFloat()
    val a = stops[i]; val b = stops[i + 1]
    return Color(a.red + (b.red - a.red) * t, a.green + (b.green - a.green) * t, a.blue + (b.blue - a.blue) * t)
}

/** Músculos em barras com a escala de calor (no lugar do desenho do corpo do iOS). `raw`: já são intensidades */
@Composable
internal fun MuscleBars(load: Map<Muscle, Double>, raw: Boolean = false) {
    val values = if (raw) load else normalized(load)
    if (values.isEmpty()) { Text("Nenhum músculo trabalhado.", color = GMColors.dim, style = GMType.subheadline); return }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        for ((m, v) in values.entries.sortedByDescending { it.value }) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
                modifier = Modifier.semantics(mergeDescendants = true) {}) {
                Text(m.label, color = Color.White, style = GMType.caption, modifier = Modifier.width(110.dp))
                Box(Modifier.weight(1f).height(10.dp).background(GMColors.raised, CircleShape)) {
                    Box(Modifier.fillMaxWidth(v.toFloat().coerceIn(0.05f, 1f)).height(10.dp).background(heat(v), CircleShape))
                }
            }
        }
    }
}

/** Exercícios e recordes (ExerciseStatsView.swift `ExerciseStatsList`) */
@Composable
internal fun ExerciseStatsScreen(data: TrainData, nav: TrainNav) {
    val rows = remember(data.sessions) {
        val count = HashMap<String, Int>()
        val sets = HashMap<String, MutableList<SetLog>>()
        for (s in data.finished) {
            val log = s.log
            for (id in log.sets.map { it.exerciseID }.toSet()) count[id] = (count[id] ?: 0) + 1
            for (set in log.sets) if (set.done) sets.getOrPut(set.exerciseID) { mutableListOf() } += set
        }
        count.keys.sortedByDescending { count[it] }.map { id ->
            val done = sets[id].orEmpty()
            val type = Exercises.byID(id)?.type
            val best = when {
                type == ExerciseType.DISTANCE -> "máx. " + meters(done.maxOfOrNull { it.weight } ?: 0.0)
                Progression.bestOneRM(done) != null -> "1RM ~${Progression.fmt(roundHalfAwayFromZero(Progression.bestOneRM(done)!!))} kg"
                (done.maxOfOrNull { it.weight } ?: 0.0) > 0 -> "máx. ${Progression.fmt(done.maxOf { it.weight })} kg"
                else -> "máx. ${done.maxOfOrNull { it.reps } ?: 0}${if (type == ExerciseType.TIME) " s" else " reps"}"
            }
            Triple(id, count[id]!!, best)
        }
    }
    GMScreen("Exercícios e recordes", bottomInset = 120.dp, leading = { BackButton(nav) }) {
        if (rows.isEmpty()) {
            GMEmptyState(TrainIcons.of("chart.line.uptrend.xyaxis"), "Sem recordes ainda", "Conclua um treino guiado para ver seus recordes aqui.")
        } else GMCard {
            rows.forEachIndexed { i, (id, n, best) ->
                GMRow(Exercises.name(id), subtitle = "$n treino${if (n == 1) "" else "s"}", chevron = true, onClick = { nav.push("exercise/$id") }) {
                    Text(best, color = GMColors.accent, style = GMType.subheadline.copy(fontWeight = FontWeight.Bold, fontFeatureSettings = "tnum"))
                }
                if (i < rows.size - 1) GMDivider()
            }
        }
    }
}

/** Evolução de um exercício: objetivo, gráfico, 1RM, calculadora, PRs e histórico (ExerciseStatsView.swift `ExerciseDetailView`) */
@Composable
internal fun ExerciseDetailScreen(env: AppEnv, data: TrainData, id: String, nav: TrainNav) {
    val ex = Exercises.byID(id)
    val prs = data.prs.filter { it.exerciseID == id }.sortedBy { it.date }
    val sessions = data.finished
    val weighted = ex?.type?.let { it == ExerciseType.WEIGHTED } ?: (prs.isNotEmpty() || sessions.any { s -> s.sets.any { it.exerciseID == id && it.weight > 0 } })
    val sessionSets = sessions.sortedBy { it.start }.mapNotNull { s ->
        val sets = s.log.sets.filter { it.exerciseID == id && it.done && (!weighted || it.weight > 0) }
        if (sets.isEmpty()) null else s.start to sets
    }
    val usesOneRM = sessionSets.all { Progression.bestOneRM(it.second) != null } && prs.all { Progression.oneRM(it.weight, it.reps) != null }
    val points = sessionSets.map { (d, sets) ->
        val v = when {
            ex?.type == ExerciseType.DISTANCE -> sets.maxOf { it.weight }
            weighted -> if (usesOneRM) Progression.bestOneRM(sets) ?: 0.0 else sets.maxOf { it.weight }
            else -> sets.maxOf { it.reps }.toDouble()
        }
        Triple(d, v, sets)
    }
    val bestOneRM = (sessionSets.mapNotNull { Progression.bestOneRM(it.second) } + prs.mapNotNull { Progression.oneRM(it.weight, it.reps) }).maxOrNull()
    var goal by remember(id) { mutableStateOf(TrainingGoal.of(id)) }

    GMScreen(Exercises.name(id), bottomInset = 120.dp, leading = { BackButton(nav) }) {
        if (ex?.type == ExerciseType.WEIGHTED) {
            GMSection("Objetivo", footer = goal?.let { "Faixa de ${it.range.first}–${it.range.last} reps: +1 rep por treino até o topo, depois sobe a carga e volta ao início. Descanso sugerido de ${clock(it.rest)}." }
                ?: "Sem objetivo: reps fixas da rotina, carga sobe quando completa todas.") {
                GMChoiceChips(listOf<Pair<TrainingGoal?, String>>(null to "Nenhum") + TrainingGoal.entries.map { it to it.label }, goal, { g ->
                    goal = g
                    val m = data.goals.toMutableMap().apply { if (g == null) remove(id) else put(id, g.raw) }
                    TrainScope.edit(env) { TrainEdits.text(it, TrainingGoal.KEY, TrainingGoal.encode(m)) }
                })
            }
        }
        val title = if (weighted) (if (usesOneRM) "1RM estimado (kg)" else "Maior carga (kg)")
            else when (ex?.type) { ExerciseType.TIME -> "Melhor tempo (s)"; ExerciseType.DISTANCE -> "Maior distância (m)"; else -> "Mais reps" }
        GMSection(title) {
            val manual = if (weighted) prs else emptyList()
            if (points.size + manual.size >= 2) {
                LineChart(points.map { it.first to it.second }, manual.map { it.date to (if (usesOneRM) Progression.oneRM(it.weight, it.reps) ?: it.weight else it.weight) })
                if (manual.isNotEmpty()) GMIconLabel("PR registrado na sessão de PR", TrainIcons.of("trophy.fill"), GMColors.trophy, GMType.caption)
            } else Text("O gráfico aparece a partir do segundo treino.", color = GMColors.dim, style = GMType.body)
            if (weighted && bestOneRM != null) {
                GMDivider()
                GMValueRow("Melhor 1RM estimado", "${Progression.fmt(roundHalfAwayFromZero(bestOneRM * 10) / 10)} kg")
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text("Calculadora (reps × carga)", color = GMColors.dim, style = GMType.subheadline)
                    Text(Progression.repTable(bestOneRM, ex?.increment ?: 2.5).joinToString("   ") { "${it.first}×${Progression.fmt(it.second)}" },
                         color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold, fontFeatureSettings = "tnum"))
                }
            }
        }
        if (prs.isNotEmpty()) GMSection("PRs registrados") {
            for (p in prs.reversed()) Row(Modifier.fillMaxWidth()) {
                Text(dayMonthYear(p.date), color = GMColors.dim, style = GMType.caption, modifier = Modifier.weight(1f))
                Text("🏆 ${Progression.fmt(p.weight)} kg × ${p.reps}", color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
            }
        }
        GMSection("Histórico") {
            for ((d, _, sets) in points.reversed()) Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(dayMonthYear(d), color = GMColors.dim, style = GMType.caption)
                Text(sets.joinToString(", ") { if (it.weight > 0) "${Progression.fmt(it.weight)}×${it.reps}" else "${it.reps}" }, color = Color.White,
                     style = GMType.subheadline.copy(fontFeatureSettings = "tnum"))
            }
        }
    }
}

/** Gráfico de linha com pontos (Charts do iOS); os PRs à mão são losangos dourados */
@Composable
private fun LineChart(points: List<Pair<Instant, Double>>, manual: List<Pair<Instant, Double>>) {
    val all = points + manual
    val minX = all.minOf { it.first.epochSecond }.toFloat()
    val maxX = all.maxOf { it.first.epochSecond }.toFloat().let { if (it == minX) minX + 1 else it }
    val minY = all.minOf { it.second }.toFloat()
    val maxY = all.maxOf { it.second }.toFloat().let { if (it == minY) minY + 1 else it }
    val accent = GMColors.accent
    val trophy = GMColors.trophy
    val grid = GMColors.stroke
    Column {
        Row(Modifier.fillMaxWidth()) {
            Text(Progression.fmt(roundHalfAwayFromZero(maxY.toDouble())), color = GMColors.dim, style = GMType.caption2)
        }
        Canvas(Modifier.fillMaxWidth().height(180.dp).semantics { contentDescription = "Gráfico com ${all.size} pontos" }) {
            fun pos(p: Pair<Instant, Double>) = Offset((p.first.epochSecond - minX) / (maxX - minX) * (size.width - 16f) + 8f,
                                                     size.height - 8f - ((p.second.toFloat() - minY) / (maxY - minY)) * (size.height - 16f))
            for (k in 0..3) drawLine(grid, Offset(0f, size.height * k / 3), Offset(size.width, size.height * k / 3), 1f)
            val sorted = points.sortedBy { it.first }
            if (sorted.size > 1) {
                val path = Path()
                sorted.forEachIndexed { i, p -> val o = pos(p); if (i == 0) path.moveTo(o.x, o.y) else path.lineTo(o.x, o.y) }
                drawPath(path, accent, style = Stroke(width = 4f))
            }
            for (p in sorted) drawCircle(accent, 7f, pos(p))
            for (p in manual) {
                val o = pos(p)
                val d = Path().apply { moveTo(o.x, o.y - 12f); lineTo(o.x + 12f, o.y); lineTo(o.x, o.y + 12f); lineTo(o.x - 12f, o.y); close() }
                drawPath(d, trophy)
            }
        }
        Text(Progression.fmt(roundHalfAwayFromZero(minY.toDouble())), color = GMColors.dim, style = GMType.caption2)
    }
}

/** Séries por grupo na semana vs. faixa de 10–20 (WeeklyVolume.swift) */
@Composable
internal fun WeeklyVolumeScreen(data: TrainData, nav: TrainNav) {
    val low = 10; val high = 20
    var offset by remember { mutableIntStateOf(0) }
    val zone = ZoneId.systemDefault()
    val week = Weeks.start(Instant.now(), zone).plusWeeks(offset.toLong())
    val counts = HashMap<MuscleGroup, Int>()
    for (s in data.finished) if (Weeks.start(s.start, zone) == week) for (set in s.sets) if (set.done && !set.warmup) {
        val g = Exercises.byID(set.exerciseID)?.group
        if (g != null && g != MuscleGroup.CORPO) counts[g] = (counts[g] ?: 0) + 1
    }
    val groups = MuscleGroup.entries.filter { it != MuscleGroup.CORPO }
    val inRange = groups.count { (counts[it] ?: 0) in low..high }
    val f = java.time.format.DateTimeFormatter.ofPattern("d 'de' MMM", ptBR)
    GMScreen("Volume semanal", bottomInset = 120.dp, leading = { BackButton(nav) }) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            GMIconButton(TrainIcons.of("chevron.left"), "Semana anterior", { offset -= 1 }, size = 34.dp)
            Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(when (offset) { 0 -> "Esta semana"; -1 -> "Semana passada"; else -> "${week.format(f)} – ${week.plusDays(6).format(f)}" },
                     color = Color.White, style = GMType.headline)
                Text("${counts.values.sum()} séries · $inRange de ${groups.size} grupos na faixa", color = GMColors.dim, style = GMType.caption)
            }
            GMTintIconButton(TrainIcons.of("chevron.right"), "Próxima semana", if (offset == 0) GMColors.dim else Color.White, { if (offset < 0) offset += 1 }, size = 34.dp)
        }
        GMSection(footer = "Conta as séries feitas de cada exercício no músculo principal dele (aquecimento fica de fora). Entre $low e $high séries por semana é a faixa que a maioria dos estudos associa a ganho de massa; abaixo disso o músculo cresce menos, acima a recuperação pesa.") {
            for (g in groups.sortedByDescending { counts[it] ?: 0 }) {
                val n = counts[g] ?: 0
                val color = if (n < low) GMColors.warning else if (n <= high) GMColors.accent else GMColors.info
                Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(g.label, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold), modifier = Modifier.weight(1f))
                        Text("$n", color = color, style = GMType.subheadline.copy(fontWeight = FontWeight.Bold))
                        Text(if (n < low) "faltam ${low - n}" else if (n <= high) "na faixa" else "acima", color = GMColors.dim, style = GMType.caption,
                             modifier = Modifier.width(64.dp), textAlign = androidx.compose.ui.text.style.TextAlign.End)
                    }
                    Canvas(Modifier.fillMaxWidth().height(10.dp)) {
                        val maxN = 26f
                        val w = size.width
                        drawRoundRect(GMColors.raised, cornerRadius = androidx.compose.ui.geometry.CornerRadius(size.height / 2))
                        drawRect(GMColors.accent.copy(alpha = 0.15f), Offset(w * low / maxN, 0f), androidx.compose.ui.geometry.Size(w * (high - low) / maxN, size.height))
                        val fill = if (n > 0) maxOf(w * minOf(n.toFloat(), maxN) / maxN, 6.dp.toPx()) else 0f
                        drawRoundRect(color, size = androidx.compose.ui.geometry.Size(fill, size.height), cornerRadius = androidx.compose.ui.geometry.CornerRadius(size.height / 2))
                    }
                }
            }
        }
    }
}

/** Mapa muscular do período (MuscleViews.swift `MuscleMapView`), com as barras no lugar do desenho do corpo */
@Composable
internal fun MuscleMapScreen(data: TrainData, nav: TrainNav) {
    var days by remember { mutableIntStateOf(7) }
    val since = Instant.now().minusSeconds(days * 86_400L)
    val sets = data.finished.filter { days == 0 || it.start >= since }.flatMap { it.log.sets }
    val load = muscleLoad(sets)
    val missing = Muscle.tracked.filter { (load[it] ?: 0.0) == 0.0 }
    GMScreen("Mapa muscular", bottomInset = 120.dp, leading = { BackButton(nav) }) {
        GMSegmented(listOf(7 to "7 dias", 30 to "30 dias", 0 to "Tudo"), days, { days = it })
        GMCard { MuscleBars(load) }
        if (load.isNotEmpty()) GMSection("Séries por músculo") {
            for ((m, v) in load.entries.sortedByDescending { it.value }) GMValueRow(m.label, Progression.fmt(roundHalfAwayFromZero(v * 2) / 2))
        }
        GMSection("Sem treino no período", footer = "Série principal conta 1, músculo auxiliar conta meia.") {
            Text(if (missing.isEmpty()) "Você treinou todos os grupos no período. 💪" else missing.joinToString(", ") { it.label }, color = Color.White, style = GMType.subheadline)
        }
    }
}

/** Melhores marcas e a sessão de PR (PR.swift `PRBookView`) */
@Composable
internal fun PRBookScreen(env: AppEnv, data: TrainData, nav: TrainNav) {
    var session by remember { mutableStateOf(false) }
    var single by remember { mutableStateOf<String?>(null) }
    var menu by remember { mutableStateOf<String?>(null) }
    data class Row(val id: String, val best: SetLog, val date: Instant, val manual: Boolean)
    val rows = remember(data) {
        val cands = LinkedHashMap<String, MutableList<Triple<SetLog, Instant, Boolean>>>()
        for (r in data.prs) cands.getOrPut(r.exerciseID) { mutableListOf() } += Triple(r.log, r.date, true)
        for (s in data.finished) for (set in s.log.sets) if (set.done && set.weight > 0) cands.getOrPut(set.exerciseID) { mutableListOf() } += Triple(set, s.start, false)
        cands.mapNotNull { (id, list) ->
            val b = PRBook.best(list.map { it.first }) ?: return@mapNotNull null
            val hit = list.firstOrNull { it.first.weight == b.weight && it.first.reps == b.reps } ?: return@mapNotNull null
            Row(id, b, hit.second, hit.third)
        }.sortedWith { a, b -> Exercises.byName.compare(Exercises.name(a.id), Exercises.name(b.id)) }
    }
    GMScreen("Meus PRs", bottomInset = 120.dp, leading = { BackButton(nav) }) {
        GMCard {
            androidx.compose.foundation.layout.Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("🏆", fontSize = 36.sp)
                Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text("Sessão de PR", color = Color.White, style = GMType.headline)
                    Text("Registre carga e reps máximas de vários exercícios de uma vez. No primeiro treino de cada um, a carga sugerida já vem calculada daqui.",
                         color = GMColors.dim, style = GMType.caption)
                }
            }
            GMButton("Começar sessão de PR", { session = true }, icon = TrainIcons.of("plus"))
        }
        if (rows.isEmpty()) GMEmptyState(TrainIcons.of("trophy"), "Nenhum PR ainda", "Registre seus PRs ou conclua um treino.")
        else GMSection("Melhores marcas", footer = "Considera os treinos do app e o que você registrou à mão. 1RM estimado pela fórmula de Epley (até 12 reps).") {
            rows.forEachIndexed { i, r ->
                androidx.compose.foundation.layout.Row(Modifier.fillMaxWidth().gmPress { menu = r.id }, verticalAlignment = Alignment.CenterVertically,
                                                        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    if (Exercises.byID(r.id) != null) Thumb(r.id)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(Exercises.name(r.id), color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold), maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text((Progression.oneRM(r.best.weight, r.best.reps)?.let { "1RM ~${Progression.fmt(roundHalfAwayFromZero(it))} kg · " } ?: "") +
                             fmt(r.date, "d 'de' MMM 'de' yy") + if (r.manual) " · registrado" else " · no treino", color = GMColors.dim, style = GMType.caption)
                    }
                    Text("${Progression.fmt(r.best.weight)} kg × ${r.best.reps}", color = GMColors.accent, style = GMType.subheadline.copy(fontWeight = FontWeight.Bold))
                }
                if (i < rows.size - 1) GMDivider()
            }
        }
    }
    val m = menu
    val mine = data.prs.filter { it.exerciseID == m }
    GMActions(m != null, { menu = null }, title = m?.let(Exercises::name), actions = if (m == null) emptyList() else buildList {
        add(GMAction("Registrar novo PR", TrainIcons.of("plus")) { single = m })
        if (mine.isNotEmpty()) add(GMAction("Apagar PRs registrados à mão (${mine.size})", TrainIcons.of("trash"), true) {
            TrainScope.edit(env) { TrainEdits.deletePRs(it, mine.map { p -> p.uuid }.toSet()) }
        })
    })
    if (session) PRSessionModal(env, data, null) { session = false }
    single?.let { PRSessionModal(env, data, it) { single = null } }
}

/** Vários exercícios de uma vez: carga e reps de cada um (PR.swift `PRSessionView`) */
@Composable
internal fun PRSessionModal(env: AppEnv, data: TrainData, only: String?, onDismiss: () -> Unit) {
    var ids by remember {
        mutableStateOf(only?.let { listOf(it) } ?: data.routines.flatMap { it.sortedItems }.map { it.exerciseID }
            .filter { Exercises.byID(it)?.type == ExerciseType.WEIGHTED }.distinct())
    }
    val weights = remember { androidx.compose.runtime.mutableStateMapOf<String, Double?>() }
    val reps = remember { androidx.compose.runtime.mutableStateMapOf<String, Double?>() }
    var date by remember { mutableStateOf(Instant.now()) }
    var picking by remember { mutableStateOf(false) }
    val filled = ids.filter { (weights[it] ?: 0.0) > 0 && (reps[it] ?: 0.0) >= 1 }
    GMModal(true, if (only == null) "Sessão de PR" else "Novo PR", onDismiss, confirm = "Salvar", confirmEnabled = filled.isNotEmpty(), onConfirm = {
        val list = filled.map { PersonalRecord(TrainEdits.newID(), it, weights[it]!!, reps[it]!!.toInt(), date) }
        TrainScope.edit(env) { TrainEdits.addPRs(it, list) }
        onDismiss()
    }) {
        if (only == null) Text("Preencha só o que você testou hoje (ou lembra). Exercícios em branco são ignorados.", color = GMColors.dim, style = GMType.subheadline)
        for (id in ids) {
            val best = PRBook.best(data.prs.filter { it.exerciseID == id }.map { it.log } +
                                   data.finished.flatMap { s -> s.log.sets.filter { it.exerciseID == id && it.done && it.weight > 0 } })
            val w = weights[id] ?: 0.0
            val r = (reps[id] ?: 0.0).toInt()
            GMCard {
                androidx.compose.foundation.layout.Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(Exercises.name(id), color = Color.White, style = GMType.headline)
                        Text(best?.let { "Atual: ${Progression.fmt(it.weight)} kg × ${it.reps}" } ?: "Sem PR ainda", color = GMColors.dim, style = GMType.caption)
                    }
                    if (w > 0 && r > 0 && PRBook.beats(SetLog(id, w, r, r, true), best)) GMBadge("🏆 Novo PR")
                    if (only == null) GMIconButton(TrainIcons.of("xmark"), "Tirar ${Exercises.name(id)}", { ids = ids - id }, size = 30.dp)
                }
                GMDecimalField("Carga", weights[id], { weights[id] = it }, Exercises.byID(id)?.increment ?: 2.5, "kg", best?.weight ?: 20.0)
                GMDivider()
                GMDecimalField("Reps", reps[id], { reps[id] = it?.let { v -> maxOf(1.0, roundHalfAwayFromZero(v)) } }, 1.0, "reps", 1.0)
                if (w > 0 && r > 0) Progression.oneRM(w, r)?.let {
                    Text("1RM estimado ~${Progression.fmt(roundHalfAwayFromZero(it))} kg", color = GMColors.accent, style = GMType.caption)
                }
            }
        }
        if (only == null) GMButton("Adicionar exercício", { picking = true }, icon = TrainIcons.of("plus"), kind = GMButtonKind.SECONDARY)
        GMSection("Quando") { GMDateTimePicker(date) { date = it } }
    }
    ExercisePickerModal(picking, env, data, onPick = { if (it.id !in ids) ids = ids + it.id }) { picking = false }
}
