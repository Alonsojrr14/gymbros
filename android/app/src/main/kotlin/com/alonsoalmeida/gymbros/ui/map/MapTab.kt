package com.alonsoalmeida.gymbros.ui.map

import androidx.compose.runtime.DisposableEffect
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
import androidx.compose.material.icons.filled.Bedtime
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.DirectionsBike
import androidx.compose.material.icons.filled.DirectionsRun
import androidx.compose.material.icons.filled.DirectionsWalk
import androidx.compose.material.icons.filled.FitnessCenter
import androidx.compose.material.icons.filled.PersonAdd
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
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.MyLocation
import androidx.compose.material.icons.filled.NearMe
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import com.alonsoalmeida.gymbros.data.map.GymLocation
import com.alonsoalmeida.gymbros.data.route.RouteRecorder
import com.alonsoalmeida.gymbros.domain.social.LiveShare
import com.alonsoalmeida.gymbros.data.train.TrainCopy
import com.alonsoalmeida.gymbros.data.train.TrainEdits
import com.alonsoalmeida.gymbros.data.train.TrainScope
import com.alonsoalmeida.gymbros.domain.map.Gym
import com.alonsoalmeida.gymbros.domain.map.GymPlaces
import com.alonsoalmeida.gymbros.domain.map.distanceText
import com.alonsoalmeida.gymbros.domain.profile.ProfileEdits
import com.alonsoalmeida.gymbros.ui.components.GMDivider
import com.alonsoalmeida.gymbros.ui.components.GMIconButton
import com.alonsoalmeida.gymbros.ui.components.GMTextButton
import com.alonsoalmeida.gymbros.ui.components.GMToggle
import com.alonsoalmeida.gymbros.ui.copy
import kotlinx.coroutines.launch
import kotlin.math.cos

// Aba Mapa (ios/GymBros/Friends/MapScreen.swift): o mapa com você, os lugares de treino (raio e nome), os percursos e os
// amigos ao vivo com rastro; onde você está, amigos agora, números do mês, começar corrida/caminhada/bike pelo GPS
// (RouteRun.kt), lugares (adicionar e editar) e percursos.

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
    val context = LocalContext.current
    // Volta dos ajustes do sistema: confere as permissões de novo
    var resumed by remember { mutableIntStateOf(0) }
    // Amigos ao vivo só com a aba visível e o app na frente (ADR-013)
    LifecycleResumeEffect(vm) {
        vm.start()
        resumed++
        onPauseOrDispose { vm.stop() }
    }
    val s by vm.state.collectAsStateWithLifecycle()
    var now by remember { mutableStateOf(Instant.now()) }
    LaunchedEffect(Unit) {
        while (true) { delay(30_000); now = Instant.now(); vm.rebuild() }
    }
    var route by rememberSaveable { mutableStateOf<String?>(null) }
    var friend by rememberSaveable { mutableStateOf<String?>(null) }
    var editing by rememberSaveable { mutableStateOf<String?>(null) }
    var settings by remember { mutableStateOf(false) }
    var askAlways by remember { mutableStateOf(false) }
    var showFriends by rememberSaveable { mutableStateOf(true) }
    var here by remember { mutableStateOf<Coordinate?>(null) }
    var locating by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val camera = remember { MapController() }

    val copy = env.copy()
    val gyms = remember(copy) { GymPlaces.gyms(copy) }
    val st = remember(copy) { TrainCopy.settings(copy) }
    val arrival = ProfileEdits.bool(st, "gymNotifyArrival", true)
    val autoFinish = ProfileEdits.bool(st, "gymAutoFinish", true)
    val shareLive = LiveShare.isOn(st)
    val running = remember(copy) { TrainCopy.read(copy).inProgress != null }
    val insideID = remember(copy, resumed) { GymLocation.insideID(context, env.uid) }
    val inside = gyms.firstOrNull { it.uuid == insideID }
    val allowed = remember(resumed, askAlways) { GymLocation.hasFine(context) && GymLocation.hasBackground(context) }
    LaunchedEffect(copy, allowed) { GymLocation.startMonitoring(context, copy) }

    // Os amigos sem posição ficam em volta de onde você treina (ou de onde você está)
    val base = here?.let { h -> GymPlaces.nearest(gyms, h)?.first?.coordinate } ?: gyms.firstOrNull()?.coordinate ?: here

    fun focusPlaces() {
        val g = here?.let { GymPlaces.nearest(gyms, it)?.first } ?: gyms.firstOrNull() ?: return
        camera.focus(g.coordinate, 1500.0)
    }
    suspend fun locate(): Coordinate? = GymLocation.currentLocation(context)?.let { Coordinate(it.latitude, it.longitude) }?.also { here = it }
    suspend fun focusMe() { locate(); here?.let { camera.focus(it, 1500.0) } }
    suspend fun goNearest() {
        locating = true
        locate()
        locating = false
        val h = here
        val g = h?.let { GymPlaces.nearest(gyms, it)?.first }
        when {
            g != null -> camera.focus(g.coordinate, 800.0)
            gyms.isNotEmpty() -> focusPlaces()
            else -> focusMe()
        }
    }
    val askFine = rememberLocationRequest { ok -> if (ok) scope.launch { locate(); focusPlaces() } }
    // Começar ao ar livre: a tela de gravação pede a localização se ainda faltar
    fun startOutdoor(k: ActivityKind) = RouteRecorder.open(context, k)
    LaunchedEffect(Unit) {
        if (GymLocation.hasFine(context)) { locate(); if (gyms.isNotEmpty()) focusPlaces() else here?.let { camera.focus(it, 1500.0, animate = false) } }
        else { focusPlaces(); askFine() }
    }
    fun setFlag(key: String, on: Boolean) {
        TrainScope.edit(env) { TrainEdits.flag(it, key, on) }
        if (on && gyms.isNotEmpty() && !allowed) askAlways = true
    }

    GMScreen("Mapa", bottomInset = 120.dp, leading = { PersonAvatar(home.trainerName, photo = home.profilePhoto) },
             trailing = { GMIconButton(Icons.Filled.Settings, "Ajustes de localização", { settings = true }) }) {
        BigMap(camera, s, gyms, here, base, showFriends && s.social == true, now, inside, running, locating,
               onFriend = { f -> base?.let { camera.focus(f.coordinate(it), 700.0) }; showFriends = true; friend = f.id },
               onToggleFriends = { showFriends = !showFriends },
               onMe = { scope.launch { if (GymLocation.hasFine(context)) focusMe() else askFine() } },
               onStatus = { scope.launch { if (GymLocation.hasFine(context)) goNearest() else askFine() } })
        if (gyms.isNotEmpty() && (arrival || autoFinish) && !allowed) PermissionBanner { askAlways = true }
        if (s.social == true) FriendsSection(s.live, s.hasFriends, now) { f ->
            base?.let { camera.focus(f.coordinate(it), 700.0) }
            showFriends = true
            friend = f.id
        }
        MonthStats(s.data)
        OutdoorSection(s.data, ::startOutdoor)
        GymSection(s.data.gyms, here, insideID, onFocus = { camera.focus(it.coordinate, 800.0) }, onEdit = { editing = it }) { editing = NEW_GYM }
        if (s.data.routes.isNotEmpty()) RoutesSection(s.data.routes.take(20)) { route = it.id }
    }

    s.data.routes.firstOrNull { it.id == route }?.let { r -> GMSheet({ route = null }) { RouteDetail(r) } }
    s.live.firstOrNull { it.id == friend }?.let { f -> GMSheet({ friend = null }) { LiveDetail(f, now) } }
    if (settings) GMSheet({ settings = false }) {
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text("Localização", color = Color.White, style = GMType.headline)
            GMToggle("Avisar ao chegar", arrival, { setFlag("gymNotifyArrival", it) },
                     subtitle = "Sugere começar o treino do dia quando você chega num lugar salvo")
            GMDivider()
            GMToggle("Encerrar treino ao sair", autoFinish, { setFlag("gymAutoFinish", it) },
                     subtitle = "Salva o treino em andamento (mais de 10 min) quando você sai do lugar")
            GMDivider()
            GMToggle("Compartilhar treino ao vivo", shareLive, { on -> TrainScope.edit(env) { TrainEdits.flag(it, LiveShare.KEY, on) } },
                     subtitle = "Padrão dos próximos treinos: amigos veem onde você treina e o exercício atual, só durante o treino. Cada treino pode mudar no chip \"Ao vivo\".")
            GMDivider()
            Text("Ao começar musculação ou CrossFit, o app reconhece o lugar ou pergunta onde você está. Fora de um treino ao vivo, a localização fica só neste aparelho. Os lugares salvos e as idas vão com a sua conta, para o iPhone também.",
                 color = GMColors.dim, style = GMType.caption)
        }
    }
    editing?.let { id ->
        val g = gyms.firstOrNull { it.uuid == id }
        if (id != NEW_GYM && g == null) { editing = null; return@let }
        GymEditor(env, g, { editing = null }) { isNew -> if (isNew && (arrival || autoFinish) && !allowed) askAlways = true }
    }
    AlwaysLocationSheet(askAlways, { askAlways = false }) {
        resumed++
        GymLocation.startMonitoring(context, copy, force = true)
    }
}

private const val NEW_GYM = "novo"

/** Registra a cerca dos lugares salvos sempre que eles mudam (aqui ou no iPhone) */
@Composable
fun GymMonitor(env: AppEnv) {
    val copy = env.copy()
    val context = LocalContext.current
    LaunchedEffect(copy) { GymLocation.startMonitoring(context, copy) }
}

/** Distância curta (MapScreen `distance`) */
private fun distance(m: Double) = distanceText(m)

@Composable
private fun BigMap(camera: MapController, s: MapUiState, gyms: List<Gym>, here: Coordinate?, base: Coordinate?, friends: Boolean, now: Instant,
                   inside: Gym?, running: Boolean, locating: Boolean, onFriend: (LiveFriend) -> Unit, onToggleFriends: () -> Unit,
                   onMe: () -> Unit, onStatus: () -> Unit) {
    val circles = remember(gyms) { gyms.map { MapCircle(it.coordinate, it.radius, GMColors.accent) } }
    val photos = rememberFriendPhotos(if (friends) s.live.map { it.id } else emptyList())
    val lines = s.data.routes.take(10).map { MapLine(it.coordinates, routeColor(it.kind), 4f, 0.85f) } +
        if (friends) s.live.filter { it.isLive && it.moves }.map { MapLine(it.route, liveColor(it.kind), 5f) } else emptyList()
    GymMapView(camera, circles, lines, Modifier.fillMaxWidth().height(340.dp).clip(GMRadius.card).background(GMColors.card)) {
        gyms.forEach { g -> MapPin(camera, g.coordinate, 16.dp) { GymPin(g.name) } }
        here?.let { MapPin(camera, it, 10.dp) { MePin() } }
        if (friends && base != null) s.live.forEach { f -> MapPin(camera, f.coordinate(base), 23.dp) { FriendPin(f, now, photos[f.id]) { onFriend(f) } } }
        Box(Modifier.align(Alignment.TopEnd).padding(10.dp)) { GMIconButton(Icons.Filled.MyLocation, "Minha localização", onMe, size = 36.dp) }
        if (s.social == true) FriendsToggle(friends, s.live.count { it.isLive }, onToggleFriends, Modifier.align(Alignment.TopStart).padding(10.dp))
        StatusPill(gyms, here, inside, running, locating, onStatus, Modifier.align(Alignment.BottomCenter).padding(10.dp))
    }
}

@Composable
private fun FriendsToggle(on: Boolean, live: Int, onClick: () -> Unit, modifier: Modifier) {
    Row(modifier.gmPress(onClick = onClick).background(if (on) GMColors.accent else GMColors.bg.copy(alpha = 0.85f), CircleShape)
            .padding(horizontal = 12.dp, vertical = 9.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Icon(Icons.Filled.People, null, tint = if (on) Color.Black else Color.White, modifier = Modifier.size(14.dp))
        Text(if (on) "$live ao vivo" else "Amigos", color = if (on) Color.Black else Color.White, style = GMType.caption.copy(fontWeight = FontWeight.Bold))
    }
}

/** Onde você está agora, por cima do mapa. Tocar atualiza a posição e leva o mapa ao lugar mais próximo */
@Composable
private fun StatusPill(gyms: List<Gym>, here: Coordinate?, inside: Gym?, running: Boolean, locating: Boolean, onClick: () -> Unit, modifier: Modifier) {
    val nearest = here?.let { GymPlaces.nearest(gyms, it) }
    Row(modifier.fillMaxWidth().gmPress(!locating, onClick = onClick).background(GMColors.bg.copy(alpha = 0.92f), GMRadius.l).padding(10.dp)
            .semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(Modifier.size(34.dp).background(if (inside != null) GMColors.accent else GMColors.raised, CircleShape), contentAlignment = Alignment.Center) {
            if (locating) CircularProgressIndicator(Modifier.size(18.dp), color = Color.White, strokeWidth = 2.dp)
            else Icon(if (inside != null) Icons.Filled.FitnessCenter else Icons.Filled.NearMe, null,
                      tint = if (inside != null) Color.Black else Color.White, modifier = Modifier.size(16.dp))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            val (title, sub, subColor) = when {
                inside != null -> Triple("Você está na ${inside.name}", if (running) "Treino em andamento" else "Bora treinar 💪", GMColors.accent)
                nearest != null -> Triple(nearest.first.name, "Lugar mais próximo · ${distance(nearest.second)}", GMColors.dim)
                gyms.isEmpty() -> Triple("Nenhum lugar salvo", "Toque em Adicionar, em Lugares de treino", GMColors.dim)
                else -> Triple("Procurando você…", "Permita a localização para ver a distância", GMColors.dim)
            }
            Text(title, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.Bold), maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(sub, color = subColor, style = GMType.caption, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (gyms.isNotEmpty() || here == null) Icon(Icons.Filled.Refresh, null, tint = GMColors.dim, modifier = Modifier.size(16.dp))
    }
}

@Composable
private fun PermissionBanner(onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().gmPress(onClick = onClick).background(GMColors.warning.copy(alpha = 0.1f), GMRadius.m).padding(12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Icon(Icons.Filled.Warning, null, tint = GMColors.warning, modifier = Modifier.size(18.dp))
        Text("Permita a localização \"o tempo todo\" para avisar ao chegar e encerrar o treino ao sair com o app fechado.",
             color = Color.White, style = GMType.caption, modifier = Modifier.weight(1f))
        Icon(Icons.Filled.ChevronRight, null, tint = GMColors.dim, modifier = Modifier.size(16.dp))
    }
}

/** Pino do amigo no mapa (FriendsLive.swift `FriendPin`): o bro na bolinha com a cor da atividade e o nome com o tempo */
@Composable
private fun FriendPin(f: LiveFriend, now: Instant, photo: ByteArray?, onClick: () -> Unit) {
    val tint = liveColor(f.kind)
    Column(Modifier.gmPress(onClick = onClick).semantics(mergeDescendants = true) {}, horizontalAlignment = Alignment.CenterHorizontally,
           verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Box(Modifier.size(46.dp).background(GMColors.bg, CircleShape).border(3.dp, if (f.isLive) tint else GMColors.dim, CircleShape),
            contentAlignment = Alignment.Center) {
            // Foto pública do amigo; sem ela (escondeu ou não tem), o bro principal
            if (photo != null) PersonAvatar(f.name, 40.dp, photo = photo)
            else MonsterSprite(f.form, Modifier.size(34.dp), saturation = if (f.isLive) 1f else 0.2f)
        }
        Row(Modifier.background(GMColors.bg.copy(alpha = 0.85f), CircleShape).padding(horizontal = 7.dp, vertical = 3.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            if (f.isLive) Box(Modifier.size(6.dp).background(GMColors.online, CircleShape))
            val min = f.start?.let { (now.epochSecond - it.epochSecond) / 60 }
            Text(if (f.isLive && min != null) "${f.name} · $min min" else f.name, color = Color.White,
                 style = GMType.caption2.copy(fontWeight = FontWeight.Bold), maxLines = 1)
        }
    }
}

@Composable
private fun FriendsSection(list: List<LiveFriend>, hasFriends: Boolean, now: Instant, onOpen: (LiveFriend) -> Unit) {
    GMSection("Amigos agora", footer = "Só aparecem amigos que ligaram \"Compartilhar treino ao vivo\", durante o treino.") {
        if (list.isEmpty()) FriendsEmpty(hasFriends)
        list.forEach { f -> LiveRow(f, now, Modifier.gmPress { onOpen(f) }) }
    }
}

@Composable
private fun FriendsEmpty(hasFriends: Boolean) {
    Row(Modifier.fillMaxWidth().semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.size(42.dp).background(GMColors.raised, CircleShape), contentAlignment = Alignment.Center) {
            Icon(if (hasFriends) Icons.Filled.Bedtime else Icons.Filled.PersonAdd, null, tint = GMColors.dim, modifier = Modifier.size(20.dp))
        }
        Column(Modifier.weight(1f)) {
            Text(if (hasFriends) "Ninguém treinando agora" else "Sem amigos ainda",
                 color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
            Text(if (hasFriends) "Quando um amigo começar um treino ao vivo, ele aparece aqui e no mapa."
                 else "Adicione amigos na aba Feed para ver quem está treinando.",
                 color = GMColors.dim, style = GMType.caption)
        }
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

/** Começar corrida, caminhada ou bike pelo GPS, com o total do mês embaixo de cada uma */
@Composable
private fun OutdoorSection(d: MapData, onStart: (ActivityKind) -> Unit) {
    GMSection("Começar ao ar livre", footer = "Grava o percurso pelo GPS. Embaixo de cada um, o total do mês.") {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            MapData.OUTDOOR.forEach { k ->
                Column(Modifier.weight(1f).heightIn(min = 88.dp).gmPress { onStart(k) }.background(GMColors.raised, GMRadius.m).padding(8.dp)
                           .semantics(mergeDescendants = true) {},
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
private fun GymSection(gyms: List<GymRow>, here: Coordinate?, insideID: String?, onFocus: (GymRow) -> Unit, onEdit: (String) -> Unit, onAdd: () -> Unit) {
    GMSection("Lugares de treino", trailing = { GMTextButton("Adicionar", Icons.Filled.Add, onAdd) }) {
        if (gyms.isEmpty()) Text("Nenhum lugar ainda. Toque em Adicionar para salvar onde você treina.", color = GMColors.dim, style = GMType.subheadline)
        val zone = ZoneId.systemDefault()
        gyms.forEachIndexed { i, g ->
            val inside = insideID != null && g.id.equals(insideID, true)
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                // Tocar no ícone centraliza no mapa
                Box(Modifier.size(40.dp).gmPress { onFocus(g) }.background(if (inside) GMColors.accent else GMColors.raised, CircleShape)
                        .semantics { contentDescription = "Mostrar ${g.name} no mapa" }, contentAlignment = Alignment.Center) {
                    Icon(Icons.Filled.FitnessCenter, null, tint = if (inside) Color.Black else Color.White, modifier = Modifier.size(18.dp))
                }
                Row(Modifier.weight(1f).gmPress { onEdit(g.id.uppercase()) }.semantics(mergeDescendants = true) {},
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Column(Modifier.weight(1f)) {
                        Text(g.name, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold), maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text("${g.count} treino${if (g.count == 1) "" else "s"}" + (g.last?.let { " · último ${dayMonth.format(it.atZone(zone))}" } ?: ""),
                             color = GMColors.dim, style = GMType.caption)
                    }
                    here?.let { Text(distance(GymPlaces.distance(g.coordinate, it)), color = GMColors.dim, style = GMType.caption.copy(fontFeatureSettings = "tnum")) }
                    Icon(Icons.Filled.ChevronRight, null, tint = GMColors.dim, modifier = Modifier.size(16.dp))
                }
            }
            if (i < gyms.size - 1) GMDivider()
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

/** Fotos dos amigos no mapa (ProfilePhotos): escuta só a versão, com a aba aberta, e baixa a foto quando ela muda */
@Composable
private fun rememberFriendPhotos(ids: List<String>): Map<String, ByteArray> {
    val context = LocalContext.current
    val repo = remember { com.alonsoalmeida.gymbros.data.ProfilePhotosRepository(context.applicationContext) }
    var photos by remember { mutableStateOf(mapOf<String, ByteArray>()) }
    val scope = rememberCoroutineScope()
    val key = ids.distinct().sorted()
    DisposableEffect(key) {
        val versions = mutableMapOf<String, String>()
        val stop = repo.watch(key) { id, version ->
            if (versions[id] == version) return@watch
            versions[id] = version
            scope.launch {
                val data = repo.photo(id, version)
                photos = if (data != null) photos + (id to data) else photos - id
            }
        }
        onDispose { stop() }
    }
    return photos
}
