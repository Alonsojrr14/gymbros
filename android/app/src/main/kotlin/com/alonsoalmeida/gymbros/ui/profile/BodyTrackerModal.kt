package com.alonsoalmeida.gymbros.ui.profile

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.health.connect.client.PermissionController
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.alonsoalmeida.gymbros.data.health.HealthConnectSync
import com.alonsoalmeida.gymbros.domain.profile.BodyEdits
import com.alonsoalmeida.gymbros.domain.profile.BodyEntryData
import com.alonsoalmeida.gymbros.domain.profile.Measure
import com.alonsoalmeida.gymbros.ui.AppEnv
import com.alonsoalmeida.gymbros.ui.components.GMButton
import com.alonsoalmeida.gymbros.ui.components.GMButtonKind
import com.alonsoalmeida.gymbros.ui.components.GMDateTimePicker
import com.alonsoalmeida.gymbros.ui.components.GMIconButton
import com.alonsoalmeida.gymbros.ui.components.GMModal
import com.alonsoalmeida.gymbros.ui.components.GMSection
import com.alonsoalmeida.gymbros.ui.components.GMSheet
import com.alonsoalmeida.gymbros.ui.components.gmPress
import com.alonsoalmeida.gymbros.ui.settings.settingsViewModel
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMType
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

private val shortDate = DateTimeFormatter.ofPattern("d 'de' MMM 'de' yyyy", ptBR)
private val longDate = DateTimeFormatter.ofPattern("d 'de' MMMM 'de' yyyy", ptBR)
private fun BodyEntryData.day(f: DateTimeFormatter) = date.atZone(ZoneId.systemDefault()).format(f)

/**
 * Peso e medidas (Profile/BodyTrackerView.swift): peso atual e a variação no período, gráfico, medidas, registros e
 * importar o peso do Health Connect. Fotos de progresso ainda não chegaram ao Android (as do iPhone ficam só nele).
 */
@Composable
fun BodyTrackerModal(visible: Boolean, env: AppEnv, onDismiss: () -> Unit) {
    if (!visible) return
    val vm = profileViewModel(env)
    val settings = settingsViewModel(env)
    val health by settings.healthState.collectAsStateWithLifecycle()
    val ui by vm.state.collectAsStateWithLifecycle()
    val entries = ui?.data?.body.orEmpty()
    val scope = rememberCoroutineScope()
    var adding by rememberSaveable { mutableStateOf(false) }
    var editing by rememberSaveable { mutableStateOf<String?>(null) }
    var menu by rememberSaveable { mutableStateOf<String?>(null) }
    var confirmDelete by rememberSaveable { mutableStateOf<String?>(null) }
    var measure by rememberSaveable { mutableStateOf<Measure?>(null) }
    var message by rememberSaveable { mutableStateOf<String?>(null) }
    val importWeights = { scope.launch { message = settings.importWeights() } }
    val ask = rememberLauncherForActivityResult(PermissionController.createRequestPermissionResultContract()) { granted ->
        if (HealthConnectSync.WEIGHT in granted) importWeights() else message = "Sem acesso ao peso do Health Connect."
    }

    GMModal(true, "Peso e medidas", onDismiss) {
        Row(Modifier.fillMaxWidth()) {
            Spacer(Modifier.weight(1f))
            GMIconButton(Icons.Filled.Add, "Novo registro", { adding = true })
        }
        val weights = entries.filter { it.weight != null }.reversed()
        GMSection("Peso (kg)") {
            weights.lastOrNull()?.weight?.let { last ->
                Row(verticalAlignment = Alignment.Bottom) {
                    Text(BodyEdits.fmt(last), color = Color.White, fontSize = 40.sp, fontWeight = FontWeight.ExtraBold, maxLines = 1)
                    Text(" kg", color = GMColors.dim, style = GMType.body)
                    Spacer(Modifier.weight(1f))
                    val first = weights.first().weight
                    if (first != null && weights.size > 1) {
                        val diff = Math.round((last - first) * 10) / 10.0
                        Text((if (diff >= 0) "+" else "") + BodyEdits.fmt(diff) + " kg no período", color = GMColors.dim,
                             style = GMType.caption.copy(fontWeight = FontWeight.SemiBold))
                    }
                }
            }
            if (weights.size >= 2) LineChart(weights.map { it.weight!! }, label = "Gráfico do peso, ${weights.size} registros")
            else Text(if (weights.isEmpty()) "Registre seu peso para acompanhar a evolução." else "O gráfico aparece a partir do segundo registro.",
                      color = GMColors.dim, style = GMType.subheadline)
            if (health.available) {
                GMButton("Importar peso do Health Connect", {
                    scope.launch {
                        if (HealthConnectSync.WEIGHT in settings.health.granted()) message = settings.importWeights()
                        else ask.launch(HealthConnectSync.PERMISSIONS)
                    }
                }, icon = Icons.Filled.FavoriteBorder, kind = GMButtonKind.SECONDARY, small = true)
            }
            message?.let { Text(it, color = GMColors.dim, style = GMType.caption) }
        }

        val withMeasures = entries.filter { it.hasMeasures }
        if (withMeasures.isNotEmpty()) {
            GMSection("Medidas (cm)") {
                for (m in Measure.entries) {
                    val series = withMeasures.mapNotNull { e -> m.value(e)?.let { e.date to it } }
                    val latest = series.firstOrNull() ?: continue
                    val more = series.size > 1
                    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).gmPress(enabled = more) { measure = m }.semantics(mergeDescendants = true) {},
                        verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(m.label, color = Color.White, style = GMType.body)
                            if (more) {
                                val d = Math.round((latest.second - series.last().second) * 10) / 10.0
                                Text((if (d >= 0) "+" else "") + BodyEdits.fmt(d) + " cm desde o primeiro registro", color = GMColors.dim, style = GMType.caption)
                            }
                        }
                        Text("${BodyEdits.fmt(latest.second)} cm", color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.Bold, fontFeatureSettings = "tnum"))
                        if (more) Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = GMColors.dim, modifier = Modifier.size(20.dp))
                    }
                }
            }
        }

        GMSection("Fotos de progresso", footer = "As fotos de progresso ainda estão chegando no Android. As tiradas no iPhone ficam só nele.") {
            Text("Peso e medidas sincronizam entre os aparelhos; as fotos não.", color = GMColors.dim, style = GMType.subheadline)
        }

        if (entries.isNotEmpty()) {
            GMSection("Registros") {
                entries.forEachIndexed { i, e ->
                    if (i > 0) Hairline()
                    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).gmPress { menu = e.id }.semantics(mergeDescendants = true) {},
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Column(Modifier.weight(1f)) {
                            Text(e.day(shortDate), color = Color.White, style = GMType.body)
                            Text(summary(e), color = GMColors.dim, style = GMType.caption)
                        }
                        if (e.healthUUID != null) Icon(Icons.Filled.Favorite, null, tint = GMColors.health,
                                                       modifier = Modifier.size(11.dp).semantics { contentDescription = "Do app de saúde" })
                    }
                }
            }
        }
    }

    if (adding) BodyEntryForm(null, entries, onDismiss = { adding = false }) { vm.saveBody(null, it); adding = false }
    entries.firstOrNull { it.id == editing }?.let { e ->
        BodyEntryForm(e, entries, onDismiss = { editing = null }) { vm.saveBody(e.id, it); editing = null }
    }
    entries.firstOrNull { it.id == menu }?.let { e ->
        GMSheet(onDismiss = { menu = null }) {
            Text(e.day(longDate), color = Color.White, style = GMType.headline)
            GMButton("Editar", { menu = null; editing = e.id }, icon = Icons.Filled.Edit, kind = GMButtonKind.SECONDARY)
            GMButton("Apagar", { menu = null; confirmDelete = e.id }, icon = Icons.Filled.Delete, kind = GMButtonKind.DANGER)
        }
    }
    entries.firstOrNull { it.id == confirmDelete }?.let { e ->
        ConfirmDialog("Apagar o registro de ${e.day(longDate)}?", "Peso, medidas e fotos desse dia saem do app.", "Apagar",
                      onConfirm = { vm.deleteBody(e.id) }, onDismiss = { confirmDelete = null })
    }
    measure?.let { m ->
        GMSheet(onDismiss = { measure = null }) {
            Text(m.label, color = Color.White, style = GMType.headline, modifier = Modifier.fillMaxWidth())
            LineChart(entries.mapNotNull { m.value(it) }.reversed(), label = "Gráfico de ${m.label.lowercase()}")
        }
    }
}

private fun summary(e: BodyEntryData): String {
    val parts = mutableListOf<String>()
    e.weight?.let { parts += "${BodyEdits.fmt(it)} kg" }
    for (m in Measure.entries) m.value(e)?.let { parts += "${m.label.lowercase()} ${BodyEdits.fmt(it)}" }
    return parts.joinToString(" · ")
}

/** Novo registro ou edição (BodyEntryForm): dia, peso e medidas; precisa de pelo menos um valor */
@Composable
private fun BodyEntryForm(entry: BodyEntryData?, entries: List<BodyEntryData>, onDismiss: () -> Unit, onSave: (BodyEdits.Values) -> Unit) {
    var date by remember { mutableStateOf(entry?.date ?: Instant.now()) }
    var weight by remember { mutableStateOf(entry?.weight) }
    val values = remember { mutableStateMapOf<Measure, Double?>().apply { if (entry != null) for (m in Measure.entries) put(m, m.value(entry)) } }
    val lastWeight = entries.firstNotNullOfOrNull { it.weight } ?: 70.0
    val ok = weight != null || values.values.any { it != null }
    GMModal(true, if (entry == null) "Novo registro" else "Editar registro", onDismiss, confirm = "Salvar", confirmEnabled = ok,
            onConfirm = { onSave(BodyEdits.Values(date, weight, Measure.entries.associateWith { values[it] })) }) {
        GMSection { GMDateTimePicker(date) { date = it } }
        GMSection("Peso") { DecimalField("Peso", weight, { weight = it }, step = 0.1, start = lastWeight) }
        GMSection("Medidas (opcional)", footer = "Meça sempre no mesmo horário e do mesmo jeito, para comparar.") {
            Measure.entries.forEachIndexed { i, m ->
                if (i > 0) Hairline()
                DecimalField(m.label, values[m], { values[m] = it }, step = 0.5, start = entries.firstNotNullOfOrNull { m.value(it) } ?: 80.0, unit = "cm")
            }
        }
    }
}
