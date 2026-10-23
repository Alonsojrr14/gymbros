package com.alonsoalmeida.gymbros.ui.map

import androidx.compose.foundation.Canvas
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.DirectionsBike
import androidx.compose.material.icons.filled.DirectionsRun
import androidx.compose.material.icons.filled.DirectionsWalk
import androidx.compose.material.icons.filled.FitnessCenter
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.alonsoalmeida.gymbros.data.FriendsRepository
import com.alonsoalmeida.gymbros.data.LiveFriend
import com.alonsoalmeida.gymbros.data.LiveFriendsRepository
import com.alonsoalmeida.gymbros.domain.ActivityKind
import com.alonsoalmeida.gymbros.domain.Attribute
import com.alonsoalmeida.gymbros.domain.home.HomeData
import com.alonsoalmeida.gymbros.domain.map.Coordinate
import com.alonsoalmeida.gymbros.domain.map.GymRow
import com.alonsoalmeida.gymbros.domain.map.MapData
import com.alonsoalmeida.gymbros.domain.map.RouteRow
import com.alonsoalmeida.gymbros.domain.map.clock
import com.alonsoalmeida.gymbros.domain.map.kindName
import com.alonsoalmeida.gymbros.domain.map.kmText
import com.alonsoalmeida.gymbros.ui.AppEnv
import com.alonsoalmeida.gymbros.ui.components.GMScreen
import com.alonsoalmeida.gymbros.ui.components.GMSection
import com.alonsoalmeida.gymbros.ui.components.GMSheet
import com.alonsoalmeida.gymbros.ui.components.MonsterSprite
import com.alonsoalmeida.gymbros.ui.components.PersonAvatar
import com.alonsoalmeida.gymbros.ui.components.gmPress
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMRadius
import com.alonsoalmeida.gymbros.ui.theme.GMType
import com.alonsoalmeida.gymbros.ui.theme.color
import kotlinx.coroutines.delay
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.cos

// Aba Mapa (ios/GymBros/Friends/MapScreen.swift) em lista, como decidido no ADR-010: amigos ao vivo, números do mês,
// lugares de treino e percursos. Mapa visual, gravação por GPS, cerca da academia e editar lugares ficam para a v1.1.

private val locale = Locale.forLanguageTag("pt-BR")
private val dayMonth = DateTimeFormatter.ofPattern("d 'de' MMM", locale)
private val dayMonthTime = DateTimeFormatter.ofPattern("d 'de' MMM, HH:mm", locale)

/** Cor de cada atividade no mapa (MapScreen `color`) */
private fun routeColor(k: ActivityKind): Color = when (k) {
    ActivityKind.BIKE -> GMColors.streak // .orange do sistema (mesmo tom)
    ActivityKind.CAMINHADA -> GMColors.info // .cyan do sistema (mesmo tom)
    else -> GMColors.accent
}

/** Cor de quem está ao vivo (LiveFriend.color) */
private fun liveColor(k: ActivityKind): Color = when (k) {
    ActivityKind.MUSCULACAO, ActivityKind.CROSSFIT -> Attribute.FORCA.color()
    ActivityKind.CORRIDA, ActivityKind.CAMINHADA, ActivityKind.BIKE -> Attribute.RESISTENCIA.color()
    ActivityKind.FUTEBOL, ActivityKind.VOLEI, ActivityKind.LUTAS -> Attribute.AGILIDADE.color()
    else -> Attribute.TECNICA.color()
}

@Composable
fun MapTab(env: AppEnv, home: HomeData) {
    val vm: MapViewModel = viewModel(key = "map-${env.uid}", factory = viewModelFactory {
        initializer { MapViewModel(env.copies, FriendsRepository(), LiveFriendsRepository()) }
    })
    LaunchedEffect(home) { vm.update(home) }
    // Amigos ao vivo só com a aba visível e o app na frente (ADR-013)
    LifecycleResumeEffect(vm) {
        vm.start()
        onPauseOrDispose { vm.stop() }
    }
    val s by vm.state.collectAsStateWithLifecycle()
    var now by remember { mutableStateOf(Instant.now()) }
    LaunchedEffect(Unit) {
        while (true) { delay(30_000); now = Instant.now(); vm.rebuild() }
    }
    var route by rememberSaveable { mutableStateOf<String?>(null) }
    var friend by rememberSaveable { mutableStateOf<String?>(null) }

    GMScreen("Mapa", bottomInset = 120.dp, leading = { PersonAvatar(home.trainerName, photo = home.profilePhoto) }) {
        if (s.social == true) FriendsSection(s.live, s.hasFriends, now) { friend = it.id }
        MonthStats(s.data)
        OutdoorSection(s.data)
        GymSection(s.data.gyms)
        if (s.data.routes.isNotEmpty()) RoutesSection(s.data.routes.take(20)) { route = it.id }
    }

    s.data.routes.firstOrNull { it.id == route }?.let { r -> GMSheet({ route = null }) { RouteDetail(r) } }
    s.live.firstOrNull { it.id == friend }?.let { f -> GMSheet({ friend = null }) { LiveDetail(f, now) } }
}

@Composable
private fun FriendsSection(list: List<LiveFriend>, hasFriends: Boolean, now: Instant, onOpen: (LiveFriend) -> Unit) {
    GMSection("Amigos agora", footer = "Só aparecem amigos que ligaram \"Compartilhar treino ao vivo\" no iPhone, durante o treino.") {
        if (list.isEmpty()) {
            Text(if (hasFriends) "Nenhum amigo treinando agora." else "Adicione amigos (aba Feed) para ver quem está treinando.",
                 color = GMColors.dim, style = GMType.subheadline)
        }
        list.forEach { f -> LiveRow(f, now, Modifier.gmPress { onOpen(f) }) }
    }
}

@Composable
private fun LiveRow(f: LiveFriend, now: Instant, modifier: Modifier = Modifier) {
    val tint = liveColor(f.kind)
    Row(modifier.fillMaxWidth().heightIn(min = 48.dp).semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.size(42.dp).background(GMColors.raised, CircleShape).border(2.dp, if (f.isLive) tint else Color.Transparent, CircleShape),
            contentAlignment = Alignment.Center) { MonsterSprite(f.form, Modifier.size(34.dp), saturation = if (f.isLive) 1f else 0.2f) }
        Column(Modifier.weight(1f)) {
            Text(f.name, color = if (f.isLive) Color.White else GMColors.dim, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
            Text(if (f.isLive) "${kindName(f.kind)} · ${f.place}" else lastSeen(f, now), color = GMColors.dim, style = GMType.caption,
                 maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        f.start?.let { start ->
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                Box(Modifier.size(6.dp).background(GMColors.online, CircleShape))
                Text(clock(maxOf(0, (now.epochSecond - start.epochSecond).toInt())), color = tint, style = GMType.caption.copy(fontWeight = FontWeight.Bold))
            }
        }
        Icon(Icons.Filled.ChevronRight, null, tint = GMColors.dim, modifier = Modifier.size(16.dp))
    }
}

/** "Corrida há 2 h" (o `.relative(presentation: .named)` do iOS, simplificado) */
private fun lastSeen(f: LiveFriend, now: Instant): String {
    val ended = f.endedAt ?: return ""
    val m = (now.epochSecond - ended.epochSecond) / 60
    val ago = when {
        m < 1 -> "agora"
        m < 60 -> "há $m min"
        else -> "há ${m / 60} h"
    }
    return "${kindName(f.kind)} $ago"
}

@Composable
private fun LiveDetail(f: LiveFriend, now: Instant) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        MonsterSprite(f.form, Modifier.size(56.dp))
        Column(Modifier.weight(1f)) {
            Text(f.name, color = Color.White, style = GMType.headline)
            Text(if (f.isLive) "${kindName(f.kind)} · ${f.place}" else lastSeen(f, now), color = GMColors.dim, style = GMType.caption)
        }
    }
    if (f.isLive && f.now.isNotEmpty()) {
        Text(f.now, color = Color.White, style = GMType.subheadline, modifier = Modifier.fillMaxWidth())
    }
    f.start?.let { Stat(clock(maxOf(0, (now.epochSecond - it.epochSecond).toInt())), "tempo") }
}

@Composable
private fun MonthStats(d: MapData) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Chip("${d.month.visits}", "idas à academia", Modifier.weight(1f))
        Chip(d.month.averageText, "tempo médio", Modifier.weight(1f))
        Chip(d.month.outdoorText, "ao ar livre", Modifier.weight(1f))
    }
}

@Composable
private fun Chip(value: String, label: String, modifier: Modifier) {
    Column(modifier.background(GMColors.card, GMRadius.l).padding(vertical = 12.dp, horizontal = 4.dp).semantics(mergeDescendants = true) {},
           horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(value, color = Color.White, style = GMType.headline, maxLines = 1)
        Text(label, color = GMColors.dim, style = GMType.caption2, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** Total do mês por atividade ao ar livre (gravar o percurso pelo GPS fica para a v1.1) */
@Composable
private fun OutdoorSection(d: MapData) {
    GMSection("Ao ar livre", footer = "Total do mês. Para gravar o percurso pelo GPS, use o iPhone por enquanto.") {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            MapData.OUTDOOR.forEach { k ->
                Column(Modifier.weight(1f).heightIn(min = 88.dp).background(GMColors.raised, GMRadius.m).padding(8.dp).semantics(mergeDescendants = true) {},
                       horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterVertically)) {
                    Icon(outdoorIcon(k), null, tint = Color.White, modifier = Modifier.size(26.dp))
                    Text(kindName(k), color = Color.White, style = GMType.caption.copy(fontWeight = FontWeight.SemiBold))
                    Text(kmText(d.outdoorByKind[k] ?: 0.0), color = GMColors.dim, style = GMType.caption2)
                }
            }
        }
    }
}

private fun outdoorIcon(k: ActivityKind) = when (k) {
    ActivityKind.BIKE -> Icons.Filled.DirectionsBike
    ActivityKind.CAMINHADA -> Icons.Filled.DirectionsWalk
    else -> Icons.Filled.DirectionsRun
}

@Composable
private fun GymSection(gyms: List<GymRow>) {
    GMSection("Lugares de treino", footer = "Mais usados primeiro. Lugares novos são salvos ao começar um treino no iPhone.") {
        if (gyms.isEmpty()) Text("Nenhum lugar ainda. Comece um treino na academia pelo iPhone.", color = GMColors.dim, style = GMType.subheadline)
        val zone = ZoneId.systemDefault()
        gyms.forEach { g ->
            Row(Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Box(Modifier.size(40.dp).background(GMColors.raised, CircleShape), contentAlignment = Alignment.Center) {
                    Icon(Icons.Filled.FitnessCenter, null, tint = Color.White, modifier = Modifier.size(18.dp))
                }
                Column(Modifier.weight(1f)) {
                    Text(g.name, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text("${g.count} treino${if (g.count == 1) "" else "s"}" + (g.last?.let { " · último ${dayMonth.format(it.atZone(zone))}" } ?: ""),
                         color = GMColors.dim, style = GMType.caption)
                }
            }
        }
    }
}

@Composable
private fun RoutesSection(routes: List<RouteRow>, onOpen: (RouteRow) -> Unit) {
    val zone = ZoneId.systemDefault()
    GMSection("Percursos") {
        routes.forEach { r ->
            Row(Modifier.fillMaxWidth().gmPress { onOpen(r) }.semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                RouteShape(r, Modifier.size(64.dp))
                Column(Modifier.weight(1f)) {
                    Text(r.title, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
                    Text("${dayMonthTime.format(r.start.atZone(zone))} · ${clock(r.seconds)} · ${r.pace}", color = GMColors.dim, style = GMType.caption)
                }
                Icon(Icons.Filled.ChevronRight, null, tint = GMColors.dim, modifier = Modifier.size(16.dp))
            }
        }
    }
}

@Composable
private fun RouteDetail(r: RouteRow) {
    Text(r.title, color = Color.White, style = GMType.headline, modifier = Modifier.fillMaxWidth())
    RouteShape(r, Modifier.fillMaxWidth().height(260.dp))
    Row {
        Stat(clock(r.seconds), "tempo", Modifier.weight(1f))
        Stat(kmText(r.meters), "distância", Modifier.weight(1f))
        Stat(r.pace, if (r.kind == ActivityKind.BIKE) "velocidade" else "ritmo", Modifier.weight(1f))
    }
}

@Composable
private fun Stat(value: String, label: String, modifier: Modifier = Modifier) {
    Column(modifier.semantics(mergeDescendants = true) {}, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(value, color = Color.White, style = GMType.headline, maxLines = 1)
        Text(label, color = GMColors.dim, style = GMType.caption)
    }
}

/** Desenho do percurso (sem mapa por baixo): os pontos do GPS projetados no quadro, com a mesma escala nos dois eixos */
@Composable
private fun RouteShape(r: RouteRow, modifier: Modifier) {
    val color = routeColor(r.kind)
    Canvas(modifier.clip(GMRadius.m).background(GMColors.raised)) {
        val pts = r.coordinates
        if (pts.size < 2) return@Canvas
        val lat0 = pts.map { it.latitude }.average()
        val k = cos(Math.toRadians(lat0))
        fun xy(c: Coordinate) = Offset((c.longitude * k).toFloat(), (-c.latitude).toFloat())
        val raw = pts.map(::xy)
        val minX = raw.minOf { it.x }; val maxX = raw.maxOf { it.x }
        val minY = raw.minOf { it.y }; val maxY = raw.maxOf { it.y }
        val pad = size.minDimension * 0.12f
        val span = maxOf(maxX - minX, maxY - minY, 1e-9f)
        val scale = minOf(size.width - 2 * pad, size.height - 2 * pad) / span
        val ox = (size.width - (maxX - minX) * scale) / 2
        val oy = (size.height - (maxY - minY) * scale) / 2
        val path = Path()
        raw.forEachIndexed { i, p ->
            val x = ox + (p.x - minX) * scale
            val y = oy + (p.y - minY) * scale
            if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
        }
        drawPath(path, color, style = Stroke(width = 3.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
    }
}
