package com.alonsoalmeida.gymbros.ui.profile

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.automirrored.filled.DirectionsRun
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.MilitaryTech
import androidx.compose.material.icons.filled.MonitorWeight
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.alonsoalmeida.gymbros.data.Badge
import com.alonsoalmeida.gymbros.data.PublicBro
import com.alonsoalmeida.gymbros.data.PublicExtra
import com.alonsoalmeida.gymbros.data.PublicProfile
import com.alonsoalmeida.gymbros.data.PublicStats
import com.alonsoalmeida.gymbros.domain.Attribute
import com.alonsoalmeida.gymbros.domain.activities.ActivityEdits
import com.alonsoalmeida.gymbros.domain.home.HomeData
import com.alonsoalmeida.gymbros.domain.profile.ContentFilter
import com.alonsoalmeida.gymbros.domain.profile.ProfileData
import com.alonsoalmeida.gymbros.ui.AppEnv
import com.alonsoalmeida.gymbros.ui.activities.ActivityDetailModal
import com.alonsoalmeida.gymbros.ui.activities.HistoryModal
import com.alonsoalmeida.gymbros.ui.auth.GMTextField
import com.alonsoalmeida.gymbros.ui.auth.LegalModal
import com.alonsoalmeida.gymbros.ui.components.GMButton
import com.alonsoalmeida.gymbros.ui.components.GMButtonKind
import com.alonsoalmeida.gymbros.ui.components.GMCard
import com.alonsoalmeida.gymbros.ui.components.GMIconButton
import com.alonsoalmeida.gymbros.ui.components.GMModal
import com.alonsoalmeida.gymbros.ui.components.GMProgressBar
import com.alonsoalmeida.gymbros.ui.components.GMSection
import com.alonsoalmeida.gymbros.ui.components.GMDateText
import com.alonsoalmeida.gymbros.ui.components.GMSheet
import com.alonsoalmeida.gymbros.ui.components.PersonAvatar
import com.alonsoalmeida.gymbros.ui.components.Symbols
import com.alonsoalmeida.gymbros.ui.components.gmPress
import com.alonsoalmeida.gymbros.ui.friends.PublicProfileCard
import com.alonsoalmeida.gymbros.ui.legal.Legal
import com.alonsoalmeida.gymbros.ui.log.LogActivityScreen
import com.alonsoalmeida.gymbros.ui.settings.SettingsModal
import com.alonsoalmeida.gymbros.ui.train.TrainPageModal
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMRadius
import com.alonsoalmeida.gymbros.ui.theme.GMType
import com.alonsoalmeida.gymbros.ui.theme.color
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.time.temporal.TemporalAdjusters

/**
 * Perfil (a bolinha no topo das abas: Profile/ProfileView.swift): parte pública (o que amigos veem) e privada
 * (números, recordes, estatísticas, calendário, todas as atividades, peso). Metas, sequências, retrospectiva, histórico
 * de X1 e títulos nos clubes ainda não chegaram ao Android e ficam de fora.
 */
@Composable
fun ProfileModal(visible: Boolean, env: AppEnv, home: HomeData, onDismiss: () -> Unit) {
    if (!visible) return
    val vm = profileViewModel(env)
    val ui by vm.state.collectAsStateWithLifecycle()
    val message by vm.message.collectAsStateWithLifecycle()
    val context = LocalContext.current
    var tab by rememberSaveable { mutableStateOf(1) }
    var settings by rememberSaveable { mutableStateOf(false) }
    var editing by rememberSaveable { mutableStateOf(false) }
    var stats by rememberSaveable { mutableStateOf(false) }
    var records by rememberSaveable { mutableStateOf(false) }
    var all by rememberSaveable { mutableStateOf(false) }
    var body by rememberSaveable { mutableStateOf(false) }
    var logging by rememberSaveable { mutableStateOf(false) }
    var day by rememberSaveable { mutableStateOf<String?>(null) }
    var detail by rememberSaveable { mutableStateOf<String?>(null) }
    val pick = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) vm.setPhotoFrom { context.contentResolver.openInputStream(uri)?.use { it.readBytes() } }
    }

    GMModal(true, "Perfil", onDismiss) {
        val state = ui ?: return@GMModal
        val data = state.data
        Row(Modifier.fillMaxWidth()) {
            Spacer(Modifier.weight(1f))
            GMIconButton(Icons.Outlined.Settings, "Ajustes", { settings = true })
        }
        Header(data, home) { pick.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }
        GMButton("Editar perfil", { editing = true }, icon = Icons.Filled.Edit, kind = GMButtonKind.SECONDARY, full = false, small = true,
                 modifier = Modifier.align(Alignment.CenterHorizontally))
        message?.let { Text(it, color = GMColors.warning, style = GMType.footnote, modifier = Modifier.align(Alignment.CenterHorizontally)) }
        Segmented(listOf(0 to "Público", 1 to "Privado"), tab) { tab = it }
        if (tab == 0) PublicPart(data, home, state.mainNick) { detail = it }
        else PrivatePart(data, onRecords = { records = true }, onStats = { stats = true }, onAll = { all = true }, onBody = { body = true }, onDay = { day = it.toString() })
        GMButton("Registrar atividade", { logging = true }, icon = Icons.Filled.AddCircle)
    }

    SettingsModal(settings, env, home) { settings = false }
    EditProfileModal(editing, vm, home, ui?.data) { editing = false }
    TrainPageModal(if (records) "stats" else null, env, home) { records = false }
    StatsModal(stats, ui?.data) { stats = false }
    HistoryModal(all, env, home) { all = false }
    BodyTrackerModal(body, env) { body = false }
    LogActivityScreen(logging, home, onDismiss = { logging = false }, onSave = { vm.addActivity(it); logging = false })
    day?.let { d ->
        val date = LocalDate.parse(d)
        val items = ui?.data?.activities.orEmpty().filter { it.date.atZone(ZoneId.systemDefault()).toLocalDate() == date }
        GMSheet(onDismiss = { day = null }) {
            Text(GMDateText.day(date.atStartOfDay(ZoneId.systemDefault()).toInstant()), color = Color.White, style = GMType.headline,
                 modifier = Modifier.fillMaxWidth())
            for (a in items) ProfileActivityRow(a) { day = null; detail = a.id }
        }
    }
    ActivityDetailModal(detail, env, home) { detail = null }
}

@Composable
private fun Header(data: ProfileData, home: HomeData, onPhoto: () -> Unit) {
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(Modifier.gmPress(onClick = onPhoto).semantics(mergeDescendants = true) { contentDescription = "Trocar foto do perfil" }) {
            PersonAvatar(data.name, size = 110.dp, photo = home.profilePhoto)
            Box(Modifier.align(Alignment.BottomEnd).size(32.dp).background(GMColors.accent, CircleShape), contentAlignment = Alignment.Center) {
                Icon(Icons.Filled.CameraAlt, null, tint = Color.Black, modifier = Modifier.size(16.dp))
            }
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(data.name.ifEmpty { "Treinador" }, color = Color.White, style = GMType.title3.copy(fontWeight = FontWeight.ExtraBold))
            if (data.username.isNotEmpty()) Text("@${data.username}", color = GMColors.dim, style = GMType.subheadline)
            if (data.bio.isNotEmpty()) Text(data.bio, color = Color.White, style = GMType.subheadline, textAlign = TextAlign.Center,
                                            modifier = Modifier.padding(top = 4.dp))
        }
    }
}

@Composable
private fun Stat(value: String, label: String, modifier: Modifier) {
    Column(modifier.semantics(mergeDescendants = true) {}, horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, color = Color.White, style = GMType.headline.copy(fontFeatureSettings = "tnum"))
        Text(label, color = GMColors.dim, style = GMType.caption)
    }
}

@Composable
private fun PrivatePart(data: ProfileData, onRecords: () -> Unit, onStats: () -> Unit, onAll: () -> Unit, onBody: () -> Unit, onDay: (LocalDate) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
        Row(Modifier.fillMaxWidth()) {
            Stat("${data.activities.size}", "Atividades", Modifier.weight(1f))
            Stat("${data.activeDays(ZoneId.systemDefault())}", "Dias ativos", Modifier.weight(1f))
            Stat(hoursText(data.totalMinutes), "Duração", Modifier.weight(1f))
        }
        Row(Modifier.fillMaxWidth().background(GMColors.card, CircleShape).padding(6.dp)) {
            Pill(Icons.Filled.MilitaryTech, "Recordes", Modifier.weight(1f), onRecords)
            Pill(Icons.Filled.Bolt, "Estatísticas", Modifier.weight(1f), onStats)
            Pill(Icons.Filled.MonitorWeight, "Peso", Modifier.weight(1f), onBody)
        }
        ActivityCalendar(data.activities.map { CalendarMark(it.id, it.date, it.typeSymbol) }, onDay)
        GMButton("Ver todas as atividades", onAll, icon = Icons.AutoMirrored.Filled.DirectionsRun, kind = GMButtonKind.SECONDARY)
    }
}

@Composable
private fun Pill(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, modifier: Modifier, onClick: () -> Unit) {
    Row(modifier.gmPress(onClick = onClick).padding(vertical = 12.dp), horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = Color.White, modifier = Modifier.size(18.dp))
        Text(title, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
    }
}

/** Como os amigos te veem: a mesma montagem do perfil público publicado */
@Composable
private fun PublicPart(data: ProfileData, home: HomeData, nick: String, onOpen: (String) -> Unit) {
    val s = home.snapshot
    val unlocked = data.achievements.filter { it.unlocked }
    val profile = PublicProfile("me", data.name, data.username, data.bio, PublicExtra(
        bro = if (data.showMonster) PublicBro(if (s.form.stage == com.alonsoalmeida.gymbros.domain.Stage.EGG || nick.isEmpty()) s.form.name else nick,
                                              s.form.id, s.level, s.progress) else null,
        stats = if (data.showStats) PublicStats(data.publicNumbers.checkIns, data.publicNumbers.activeDays, data.publicNumbers.leagues) else null,
        achievements = if (data.showAchievements) unlocked.map { Badge(it.title, it.symbol) } else null,
        bros = if (data.showBros) data.publicBros else null,
    ))
    val posts = data.activities.filter { ActivityEdits.PROFILE_FEED in it.postedIn }
    Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
        Text("É assim que seus amigos te veem", color = GMColors.dim, style = GMType.caption, modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center)
        GMCard { PublicProfileCard(profile) }
        GMSection("Posts · ${posts.size}", footer = if (posts.isEmpty()) "Ao registrar uma atividade, marque \"Meu perfil\" em \"Postar em\"." else null) {
            if (posts.isEmpty()) Text("Nenhum post ainda.", color = GMColors.dim, style = GMType.subheadline)
            posts.forEachIndexed { i, a ->
                if (i > 0) Hairline()
                ProfileActivityRow(a) { onOpen(a.id) }
            }
        }
    }
}

/**
 * Editar perfil (EditProfileView): nome, @usuário e bio só valem ao salvar, passam pelo filtro de palavras e pelo aceite
 * dos termos; os interruptores valem na hora.
 */
@Composable
private fun EditProfileModal(visible: Boolean, vm: ProfileViewModel, home: HomeData, data: ProfileData?, onDismiss: () -> Unit) {
    if (!visible || data == null) return
    var name by rememberSaveable { mutableStateOf(data.name) }
    var username by rememberSaveable { mutableStateOf(data.username) }
    var bio by rememberSaveable { mutableStateOf(data.bio) }
    var blocked by remember { mutableStateOf(false) }
    var terms by remember { mutableStateOf(false) }
    LaunchedEffect(name, username, bio) { blocked = false }
    val save = {
        if (!ContentFilter.allows(name, username, bio)) blocked = true
        else if (home.termsVersion < ProfileViewModel.TERMS_VERSION) terms = true
        else if (vm.saveProfile(name, username, bio)) onDismiss()
    }
    GMModal(true, "Editar perfil", onDismiss, confirm = "Salvar", onConfirm = save) {
        GMSection("Perfil público", footer = "A foto você troca tocando nela, no topo do perfil.") {
            GMTextField(name, { name = it }, "Seu nome")
            GMTextField(username, { t -> username = t.lowercase().filter { it.isLetterOrDigit() || it == '_' || it == '.' } }, "@usuário")
            GMTextField(bio, { bio = it }, "Bio (ex.: Rato de academia desde 2019)")
            if (blocked) Text(ContentFilter.MESSAGE, color = GMColors.danger, style = GMType.footnote)
        }
        GMSection("O que aparece para os outros",
                  footer = "Nome, @usuário, bio e os posts do perfil sempre aparecem. Em \"Bros e atributos\", os atributos somam todos os seus treinos, mas só aparece o percentual de cada um. Peso, medidas, recordes, metas, notas e as atividades que você não postou ficam sempre privados.") {
            ToggleRow("Foto do perfil", data.showPhoto, { vm.setVisibility("publicPhoto", it) })
            Hairline()
            ToggleRow("Bro principal", data.showMonster, { vm.setVisibility("publicMonster", it) })
            Hairline()
            ToggleRow("Números (check-ins, dias, ligas)", data.showStats, { vm.setVisibility("publicStats", it) })
            Hairline()
            ToggleRow("Conquistas", data.showAchievements, { vm.setVisibility("publicAchievements", it) })
            Hairline()
            ToggleRow("Bros e atributos", data.showBros, { vm.setVisibility("publicBros", it) })
        }
    }
    LegalModal(terms, "Termos de uso", Legal.terms, "Atualizados", onDismiss = { terms = false }, confirm = "Aceitar", onConfirm = {
        terms = false
        vm.acceptTerms()
        if (vm.saveProfile(name, username, bio)) onDismiss()
    })
}

/** Estatísticas (ProfileStatsView) */
@Composable
private fun StatsModal(visible: Boolean, data: ProfileData?, onDismiss: () -> Unit) {
    if (!visible || data == null) return
    val zone = ZoneId.systemDefault()
    val acts = data.activities
    val s = data.player
    GMModal(true, "Estatísticas", onDismiss) {
        val first = acts.minOfOrNull { it.date }
        val weeks = maxOf((first?.let { ChronoUnit.DAYS.between(it.atZone(zone).toLocalDate(), LocalDate.now(zone)) } ?: 0L) / 7.0, 1.0)
        GMCard {
            Row(Modifier.fillMaxWidth()) {
                Big("${s.bestStreak}", "melhor sequência", Modifier.weight(1f))
                Big(String.format(ptBR, "%.1f", acts.size / weeks), "treinos/semana", Modifier.weight(1f))
                Big(hoursText(acts.maxOfOrNull { it.minutes } ?: 0), "maior treino", Modifier.weight(1f))
            }
        }
        GMSection("Últimas 16 semanas") { Heatmap(data) }
        val byType = acts.groupBy { it.typeName }
        if (byType.isNotEmpty()) {
            val maxMinutes = byType.values.maxOf { l -> l.sumOf { it.minutes } }.coerceAtLeast(1)
            GMSection("Por atividade") {
                for ((name, items) in byType.entries.sortedByDescending { it.value.size }) {
                    val minutes = items.sumOf { it.minutes }
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            Icon(Symbols.of(items.first().typeSymbol), null, tint = Color.White, modifier = Modifier.size(16.dp))
                            Text(name, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold), modifier = Modifier.weight(1f))
                            Text("${items.size}× · ${hoursText(minutes)}", color = GMColors.dim, style = GMType.caption.copy(fontFeatureSettings = "tnum"))
                        }
                        GMProgressBar(minutes.toDouble() / maxMinutes, height = 6.dp)
                    }
                }
            }
        }
        val sum = s.lifetimeAttributes.values.sum().coerceAtLeast(1.0)
        GMSection("Atributos treinados") {
            for (a in Attribute.entries) {
                val v = s.lifetimeAttributes[a] ?: 0.0
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(Modifier.width(130.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Icon(Symbols.of(a), null, tint = a.color(), modifier = Modifier.size(16.dp))
                        Text(a.label, color = a.color(), style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
                    }
                    GMProgressBar(v / sum, Modifier.weight(1f), tint = a.color(), height = 6.dp)
                    Text("${Math.round(v / sum * 100)}%", color = Color.White, style = GMType.caption.copy(fontFeatureSettings = "tnum"),
                         modifier = Modifier.width(40.dp), textAlign = TextAlign.End)
                }
            }
        }
    }
}

@Composable
private fun Big(value: String, label: String, modifier: Modifier) {
    Column(modifier.semantics(mergeDescendants = true) {}, horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, color = Color.White, style = GMType.title3.copy(fontWeight = FontWeight.ExtraBold, fontFeatureSettings = "tnum"))
        Text(label, color = GMColors.dim, style = GMType.caption2, textAlign = TextAlign.Center)
    }
}

/** Grade de semanas × dias, cor pela quantidade de minutos (semana começando no domingo, como no iPhone em pt-BR) */
@Composable
private fun Heatmap(data: ProfileData) {
    val zone = ZoneId.systemDefault()
    val today = LocalDate.now(zone)
    val minutes = data.activities.groupBy { it.date.atZone(zone).toLocalDate() }.mapValues { (_, l) -> l.sumOf { it.minutes } }
    val thisWeek = today.with(TemporalAdjusters.previousOrSame(DayOfWeek.SUNDAY))
    Row(Modifier.fillMaxWidth().semantics { contentDescription = "Treinos das últimas 16 semanas" }, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
        for (w in 0 until 16) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                for (d in 0 until 7) {
                    val day = thisWeek.plusDays((d - (15 - w) * 7).toLong())
                    val m = minutes[day] ?: 0
                    val color = when {
                        day.isAfter(today) -> Color.Transparent
                        m == 0 -> GMColors.raised
                        else -> GMColors.accent.copy(alpha = minOf(0.3f + m / 120f, 1f))
                    }
                    Box(Modifier.fillMaxWidth().aspectRatio(1f).background(color, GMRadius.xs))
                }
            }
        }
    }
}
