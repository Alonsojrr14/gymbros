package com.alonsoalmeida.gymbros.ui.map

import android.Manifest
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.MyLocation
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.alonsoalmeida.gymbros.data.map.GymLocation
import com.alonsoalmeida.gymbros.data.route.RouteRecorder
import com.alonsoalmeida.gymbros.data.train.TrainEdits
import com.alonsoalmeida.gymbros.data.train.TrainScope
import com.alonsoalmeida.gymbros.domain.ActivityKind
import com.alonsoalmeida.gymbros.domain.BroCatalog
import com.alonsoalmeida.gymbros.domain.home.HomeData
import com.alonsoalmeida.gymbros.domain.leagues.LeagueActivityJson
import com.alonsoalmeida.gymbros.domain.leagues.PostSubject
import com.alonsoalmeida.gymbros.domain.map.Coordinate
import com.alonsoalmeida.gymbros.domain.map.GymPlaces
import com.alonsoalmeida.gymbros.domain.map.RouteEdits
import com.alonsoalmeida.gymbros.domain.map.clock
import com.alonsoalmeida.gymbros.domain.map.kindName
import com.alonsoalmeida.gymbros.domain.map.kmText
import com.alonsoalmeida.gymbros.domain.map.paceText
import com.alonsoalmeida.gymbros.ui.AppEnv
import com.alonsoalmeida.gymbros.ui.components.GMAction
import com.alonsoalmeida.gymbros.ui.components.GMActions
import com.alonsoalmeida.gymbros.ui.components.GMButton
import com.alonsoalmeida.gymbros.ui.components.GMButtonKind
import com.alonsoalmeida.gymbros.ui.components.GMCard
import com.alonsoalmeida.gymbros.ui.components.GMEffortPicker
import com.alonsoalmeida.gymbros.ui.components.GMIconButton
import com.alonsoalmeida.gymbros.ui.components.GMModal
import com.alonsoalmeida.gymbros.ui.components.GMSection
import com.alonsoalmeida.gymbros.ui.components.LiveShareChip
import com.alonsoalmeida.gymbros.ui.components.TrainIcons
import com.alonsoalmeida.gymbros.ui.copy
import com.alonsoalmeida.gymbros.ui.leagues.TrainingPostSection
import com.alonsoalmeida.gymbros.ui.leagues.rememberTrainingPost
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMRadius
import com.alonsoalmeida.gymbros.ui.theme.GMType
import kotlinx.coroutines.delay
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.time.Instant

// Corrida, caminhada e bike com GPS (ios/GymBros/Services/Route.swift `RouteRunView`, `RouteFinishView`, `RouteMap`):
// o mapa com o percurso, tempo, distância e ritmo, Pausar/Terminar e a conclusão com esforço e "Postar em".

/**
 * Percurso em andamento por cima de tudo, como o `gmModal` do iOS. Fica na raiz do app (não na aba Mapa) para voltar
 * aberto ao trocar de aba, sair e voltar pelo ícone ou tocar na notificação.
 */
@Composable
fun RouteHost(env: AppEnv, home: HomeData) {
    val run by RouteRecorder.run.collectAsStateWithLifecycle()
    val r = run ?: return
    RouteRunScreen(env, r)
    if (r.finishing) RouteFinishModal(env, home, r)
}

@Composable
private fun RouteRunScreen(env: AppEnv, r: RouteRecorder.Run) {
    val context = LocalContext.current
    val t = r.track
    var confirmQuit by remember { mutableStateOf(false) }
    var now by remember { mutableStateOf(Instant.now()) }
    LaunchedEffect(Unit) { while (true) { delay(1_000); now = Instant.now() } }
    // Tela acesa enquanto grava (o `isIdleTimerDisabled` do iOS)
    val view = LocalView.current
    DisposableEffect(view) {
        view.keepScreenOn = true
        onDispose { view.keepScreenOn = false }
    }
    var granted by remember { mutableStateOf(GymLocation.hasFine(context)) }
    val askLocation = rememberLocationRequest { ok -> granted = ok || GymLocation.hasFine(context); if (granted) RouteRecorder.prepare() }
    LaunchedEffect(Unit) { if (!granted) askLocation() }
    // O aviso contínuo precisa da permissão de notificações (Android 13+); sem ela, o percurso grava do mesmo jeito
    val askNotify = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { RouteRecorder.begin() }
    fun begin() {
        if (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
            android.content.pm.PackageManager.PERMISSION_GRANTED) askNotify.launch(Manifest.permission.POST_NOTIFICATIONS)
        else RouteRecorder.begin()
    }
    fun close() { if (!t.started) RouteRecorder.discard() else confirmQuit = true }

    Dialog(::close, DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false, dismissOnClickOutside = false)) {
        val camera = remember { MapController() }
        // Segue você no mapa, como o `.userLocation` do iOS, até você arrastar; o botão volta a seguir
        var follow by remember { mutableStateOf(true) }
        var seen by remember { mutableIntStateOf(camera.moved) }
        LaunchedEffect(camera.moved) { if (camera.moved != seen) { seen = camera.moved; follow = false } }
        val here = t.here
        var framed by remember { mutableStateOf(false) }
        LaunchedEffect(here, follow) {
            if (follow && here != null) { camera.focus(here, 800.0, animate = framed); framed = true }
        }
        val secs = t.elapsed(now)
        Box(Modifier.fillMaxSize().background(GMColors.bg)) {
            GymMapView(camera, emptyList(), listOf(MapLine(t.coords, GMColors.accent, 6f)), Modifier.fillMaxSize()) {
                here?.let { MapPin(camera, it, 10.dp) { MePin() } }
            }
            Column(Modifier.fillMaxSize().safeDrawingPadding()) {
                Row(Modifier.fillMaxWidth().padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                    GMIconButton(Icons.Filled.Close, if (t.started) "Sair sem salvar" else "Fechar", ::close)
                    Box(Modifier.weight(1f))
                    if (!follow && here != null) GMIconButton(Icons.Filled.MyLocation, "Seguir minha posição", { follow = true })
                }
                Box(Modifier.weight(1f))
                GMCard(Modifier.padding(12.dp), padding = 18.dp) {
                    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { LiveShareChip(env, r.id) }
                    Row(Modifier.fillMaxWidth()) {
                        RunStat(clock(secs), "tempo", Modifier.weight(1f))
                        RunStat(kmText(t.meters), "distância", Modifier.weight(1f))
                        RunStat(paceText(t.kind, t.meters, secs), if (t.kind == ActivityKind.BIKE) "velocidade" else "ritmo", Modifier.weight(1f))
                    }
                    when {
                        !granted -> {
                            Text("Permita a localização para gravar o percurso pelo GPS.", color = GMColors.dim, style = GMType.caption,
                                 textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
                            GMButton("Permitir localização", { askLocation() }, icon = Icons.Filled.MyLocation)
                        }
                        !t.started -> GMButton("Começar ${kindName(t.kind).lowercase()}", ::begin, icon = TrainIcons.of("play.fill"))
                        else -> Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            GMButton(if (t.paused) "Continuar" else "Pausar", RouteRecorder::togglePause, Modifier.weight(1f),
                                     icon = TrainIcons.of(if (t.paused) "play.fill" else "pause.fill"), kind = GMButtonKind.SECONDARY)
                            GMButton("Terminar", RouteRecorder::finish, Modifier.weight(1f), icon = TrainIcons.of("flag.checkered"))
                        }
                    }
                }
            }
        }
        GMActions(confirmQuit, { confirmQuit = false }, title = "Sair sem salvar?", message = "O percurso será descartado.",
                  actions = listOf(GMAction("Sair sem salvar", TrainIcons.of("xmark"), true) { RouteRecorder.discard() }))
    }
}

@Composable
private fun RunStat(value: String, label: String, modifier: Modifier = Modifier) {
    Column(modifier.semantics(mergeDescendants = true) {}, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        com.alonsoalmeida.gymbros.ui.components.AutoShrinkText(value, 20f, 14f)
        Text(label, color = GMColors.dim, style = GMType.caption)
    }
}

/** Conclusão (RouteFinishView): o percurso no mapa, os números, o esforço e "Postar em" */
@Composable
private fun RouteFinishModal(env: AppEnv, home: HomeData, r: RouteRecorder.Run) {
    val context = LocalContext.current
    val haptic = LocalHapticFeedback.current
    val t = r.track
    val kind = t.kind
    val secs = t.elapsed(Instant.now())
    val start = t.start ?: Instant.now()
    val minutes = RouteEdits.minutes(secs)
    var effort by remember { mutableIntStateOf(RouteEdits.DEFAULT_EFFORT) }
    var saved by remember { mutableStateOf(false) }
    val post = rememberTrainingPost(home)
    val copy = env.copy()
    // Onde está agora, se for um lugar salvo (GymLocation.placeNow)
    val place = remember(copy) { GymPlaces.gym(copy, GymLocation.insideID(context, env.uid))?.name }
    val typeID = BroCatalog.classicType[kind.raw]

    GMModal(true, "${kindName(kind)} concluída", RouteRecorder::cancelFinish, confirm = "Salvar", confirmEnabled = post.canSave && !saved, onConfirm = save@{
        // Um toque só: o mesmo percurso nunca vira duas atividades
        if (saved) return@save
        saved = true
        val activityID = TrainEdits.newID()
        val meters = t.meters
        val note = RouteEdits.note(kind, meters, secs)
        val attributes = RouteEdits.attributes(kind, secs, effort, meters)
        val e = effort
        TrainScope.edit(env) { c ->
            if (hasRoute(c, r.id)) return@edit c
            var out = TrainEdits.addActivity(c, activityID, kind.raw, start, minutes, e, note, attributes, null)
            // Gravada pelo GPS do app: vale como treino gravado por aparelho nas regras das ligas
            out = RouteEdits.stampActivity(out, activityID, meters, RouteRecorder.SOURCE)
            RouteEdits.addRoute(out, RouteEdits.routeJson(r.id, activityID, kind, start, secs, meters, t.coords))
        }
        // Depois de salvar: o check-in em cada destino escolhido (postCheckIns), num escopo que sobrevive à tela
        post.post(LeagueActivityJson(activityID, kind.raw, start, minutes, e, note, source = RouteRecorder.SOURCE, meters = meters),
                  RouteEdits.title(kind, meters), "", TrainScope.scope)
        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
        RouteRecorder.discard()
    }) {
        if (t.coords.size > 1) RouteMapView(t.coords, Modifier.fillMaxWidth().height(220.dp).clip(GMRadius.l))
        GMCard {
            Row(Modifier.fillMaxWidth()) {
                FinishStat(clock(secs), "tempo", Modifier.weight(1f))
                FinishStat(kmText(t.meters), "distância", Modifier.weight(1f))
                FinishStat(paceText(kind, t.meters, secs), if (kind == ActivityKind.BIKE) "velocidade" else "ritmo", Modifier.weight(1f))
            }
        }
        GMSection { GMEffortPicker(effort) { effort = it } }
        TrainingPostSection(home, post, PostSubject(typeID, start, minutes, deviceRecorded = true, place = place))
    }
}

private fun hasRoute(copy: JsonObject, id: String): Boolean =
    (copy["routes"] as? JsonArray).orEmpty().any { ((it as? JsonObject)?.get("uuid") as? JsonPrimitive)?.content.equals(id, true) }

@Composable
private fun FinishStat(value: String, label: String, modifier: Modifier = Modifier) {
    Column(modifier.semantics(mergeDescendants = true) {}, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(value, color = Color.White, style = GMType.headline.copy(fontFeatureSettings = "tnum"), maxLines = 1)
        Text(label, color = GMColors.dim, style = GMType.caption)
    }
}

/** Mapa parado de um percurso, enquadrado nele (RouteMap): início em branco, fim na cor do app */
@Composable
internal fun RouteMapView(coords: List<Coordinate>, modifier: Modifier) {
    val camera = remember { MapController() }
    LaunchedEffect(coords) { camera.fit(coords) }
    Box(modifier) {
        GymMapView(camera, emptyList(), listOf(MapLine(coords, GMColors.accent, 5f)), Modifier.fillMaxSize()) {
            coords.firstOrNull()?.let { MapPin(camera, it, 6.dp) { Box(Modifier.size(12.dp).background(Color.White, CircleShape)) } }
            coords.lastOrNull()?.let { MapPin(camera, it, 7.dp) { Box(Modifier.size(14.dp).background(GMColors.accent, CircleShape)) } }
        }
        // Só de ver: os toques não mexem no mapa
        Box(Modifier.matchParentSize().pointerInput(Unit) {
            awaitPointerEventScope { while (true) awaitPointerEvent().changes.forEach { it.consume() } }
        })
    }
}
