package com.alonsoalmeida.gymbros.ui.map

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.FitnessCenter
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.MyLocation
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.alonsoalmeida.gymbros.data.map.GymLocation
import com.alonsoalmeida.gymbros.data.map.GymLocation.coordinate
import com.alonsoalmeida.gymbros.data.train.TrainScope
import com.alonsoalmeida.gymbros.domain.map.Coordinate
import com.alonsoalmeida.gymbros.domain.map.Gym
import com.alonsoalmeida.gymbros.domain.map.GymPlaces
import com.alonsoalmeida.gymbros.ui.AppEnv
import com.alonsoalmeida.gymbros.ui.auth.GMTextField
import com.alonsoalmeida.gymbros.ui.components.GMActions
import com.alonsoalmeida.gymbros.ui.components.GMAction
import com.alonsoalmeida.gymbros.ui.components.GMButton
import com.alonsoalmeida.gymbros.ui.components.GMButtonKind
import com.alonsoalmeida.gymbros.ui.components.GMModal
import com.alonsoalmeida.gymbros.ui.components.GMSection
import com.alonsoalmeida.gymbros.ui.components.GMSheet
import com.alonsoalmeida.gymbros.ui.components.gmPress
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMRadius
import com.alonsoalmeida.gymbros.ui.theme.GMType
import kotlinx.coroutines.launch
import java.time.Instant

/** Pino de lugar de treino (o Annotation do MapScreen): halteres no círculo verde e o nome embaixo */
@Composable
internal fun GymPin(name: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Box(Modifier.size(32.dp).background(GMColors.accent, CircleShape), contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.FitnessCenter, null, tint = Color.Black, modifier = Modifier.size(16.dp))
        }
        if (name.isNotEmpty()) Text(name, color = Color.White, style = GMType.caption2.copy(fontWeight = FontWeight.Bold), maxLines = 1,
                                    overflow = TextOverflow.Ellipsis, modifier = Modifier.background(GMColors.bg.copy(alpha = 0.85f), CircleShape)
                                        .padding(horizontal = 7.dp, vertical = 2.dp))
    }
}

/** Ponto azul de "você está aqui" (UserAnnotation) */
@Composable
internal fun MePin() {
    Box(Modifier.size(20.dp).background(Color.White, CircleShape).padding(3.dp).background(Color(0xFF0A84FF), CircleShape))
}

/** Pedir a localização precisa (ao abrir o mapa ou cadastrar um lugar) */
@Composable
internal fun rememberLocationRequest(onResult: (Boolean) -> Unit): () -> Unit {
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { r -> onResult(r.values.any { it }) }
    return { launcher.launch(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)) }
}

/**
 * Localização "o tempo todo" para chegada e saída (o `requestAlways` do iOS): primeiro a explicação, depois o pedido do
 * sistema (no Android 11+ ele leva aos ajustes do app). Negado de vez, abre os ajustes do app. Depois, as notificações.
 */
@Composable
internal fun AlwaysLocationSheet(visible: Boolean, onDismiss: () -> Unit, onDone: () -> Unit) {
    val context = LocalContext.current
    val notifications = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { onDone() }
    fun afterBackground() {
        if (Build.VERSION.SDK_INT >= 33 && androidx.core.content.ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS)
            != android.content.pm.PackageManager.PERMISSION_GRANTED) notifications.launch(Manifest.permission.POST_NOTIFICATIONS)
        else onDone()
    }
    val background = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok ->
        if (ok) afterBackground()
        else runCatching {
            context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))
                                      .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }
    val fine = rememberLocationRequest { ok -> if (ok) { if (Build.VERSION.SDK_INT >= 29) background.launch(Manifest.permission.ACCESS_BACKGROUND_LOCATION) else afterBackground() } }
    if (!visible) return
    GMSheet(onDismiss) {
        Box(Modifier.size(56.dp).background(GMColors.accent, CircleShape), contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.LocationOn, null, tint = Color.Black, modifier = Modifier.size(28.dp))
        }
        Text("Chegada e saída da academia", color = Color.White, style = GMType.headline, textAlign = TextAlign.Center)
        Text("Para avisar quando você chega num lugar salvo e encerrar o treino quando você sai, mesmo com o app fechado, o GymBros " +
             "precisa da localização \"Permitir o tempo todo\". Ela é usada só neste aparelho, para conferir se você está dentro do raio " +
             "dos seus lugares, e nunca vai para o servidor.", color = GMColors.dim, style = GMType.subheadline, textAlign = TextAlign.Center)
        if (Build.VERSION.SDK_INT >= 30) Text("Na próxima tela, escolha \"Permitir o tempo todo\".", color = Color.White,
                                               style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold), textAlign = TextAlign.Center)
        GMButton("Continuar", {
            onDismiss()
            if (GymLocation.hasFine(context)) { if (Build.VERSION.SDK_INT >= 29) background.launch(Manifest.permission.ACCESS_BACKGROUND_LOCATION) else afterBackground() }
            else fine()
        })
        GMButton("Agora não", onDismiss, kind = GMButtonKind.GHOST)
    }
}

/** Raio do lugar (o GMSegmented do iOS) */
@Composable
private fun RadiusPicker(value: Double, onChange: (Double) -> Unit) {
    Row(Modifier.fillMaxWidth().background(GMColors.card, GMRadius.m).padding(4.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        for (r in GymPlaces.RADII) {
            val on = r == value
            Box(Modifier.weight(1f).heightIn(min = 36.dp).clip(GMRadius.s).background(if (on) GMColors.accent else Color.Transparent)
                    .gmPress(role = Role.Tab) { onChange(r) }.semantics { selected = on }, contentAlignment = Alignment.Center) {
                Text("${r.toInt()} m", color = if (on) Color.Black else Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
            }
        }
    }
}

/**
 * Novo lugar ou editar (Route.swift `GymEditorView`): tocar no mapa marca o lugar, "Estou aqui" usa a posição atual; raio e
 * nome; apagar mantém o histórico. `onSaved(novo)` deixa o Mapa pedir a localização "o tempo todo" depois do primeiro lugar.
 */
@Composable
internal fun GymEditor(env: AppEnv, gym: Gym?, onDismiss: () -> Unit, onSaved: (Boolean) -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val camera = remember { MapController() }
    var name by remember { mutableStateOf(gym?.name.orEmpty()) }
    var center by remember { mutableStateOf(gym?.coordinate) }
    var radius by remember { mutableDoubleStateOf(gym?.radius ?: 100.0) }
    var here by remember { mutableStateOf<Coordinate?>(null) }
    var locating by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }

    suspend fun locate(useAsCenter: Boolean) {
        locating = true
        GymLocation.currentLocation(context)?.coordinate()?.let { c ->
            here = c
            if (useAsCenter) center = c
            camera.focus(c, 600.0)
        }
        locating = false
    }
    var wantCenter by remember { mutableStateOf(false) }
    val ask = rememberLocationRequest { ok -> if (ok) scope.launch { locate(wantCenter) } }

    LaunchedEffect(Unit) {
        val g = gym
        if (g != null) camera.focus(g.coordinate, 600.0, animate = false)
        else if (GymLocation.hasFine(context)) locate(false) else { wantCenter = false; ask() }
    }

    GMModal(true, if (gym == null) "Novo lugar" else "Editar lugar", onDismiss, confirm = "Salvar", confirmEnabled = center != null, onConfirm = save@{
        val c = center ?: return@save
        TrainScope.edit(env) { copy -> GymPlaces.save(copy, gym?.uuid, name, c, radius, Instant.now()) }
        onDismiss()
        onSaved(gym == null)
    }) {
        GymMapView(camera, listOfNotNull(center?.let { MapCircle(it, radius, GMColors.accent) }), emptyList(),
                   Modifier.fillMaxWidth().height(320.dp).clip(GMRadius.card), onTap = { center = it }) {
            here?.let { MapPin(camera, it, 10.dp) { MePin() } }
            center?.let { MapPin(camera, it, 16.dp) { GymPin(name) } }
            Text(if (center == null) "Toque no mapa para marcar o lugar" else "Toque em outro ponto para mover",
                 color = Color.White, style = GMType.caption.copy(fontWeight = FontWeight.Bold),
                 modifier = Modifier.align(Alignment.TopCenter).padding(10.dp).background(GMColors.bg.copy(alpha = 0.9f), CircleShape)
                     .padding(horizontal = 12.dp, vertical = 6.dp))
            Row(Modifier.align(Alignment.BottomEnd).padding(10.dp).gmPress(!locating) {
                    if (GymLocation.hasFine(context)) scope.launch { locate(true) } else { wantCenter = true; ask() }
                }.background(GMColors.accent, CircleShape).padding(horizontal = 12.dp, vertical = 9.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(Icons.Filled.MyLocation, null, tint = Color.Black, modifier = Modifier.size(14.dp))
                Text(if (locating) "Buscando…" else "Estou aqui", color = Color.Black, style = GMType.caption.copy(fontWeight = FontWeight.Bold))
            }
        }

        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("RAIO", color = GMColors.dim, style = GMType.caption.copy(fontWeight = FontWeight.Bold), modifier = Modifier.padding(horizontal = 4.dp))
            RadiusPicker(radius) { radius = it }
            Text("100 m cobre uma academia comum. Aumente se o GPS da região for impreciso.", color = GMColors.dim, style = GMType.caption,
                 modifier = Modifier.padding(horizontal = 4.dp))
        }

        GMSection("Nome") { GMTextField(name, { name = it }, "Ex.: Smart Fit Paulista") }

        if (gym != null) {
            GMButton("Apagar ${gym.name}", { confirmDelete = true }, icon = Icons.Filled.Delete, kind = GMButtonKind.SECONDARY)
            Text("O histórico de treinos continua; só o lugar some.", color = GMColors.dim, style = GMType.caption, textAlign = TextAlign.Center,
                 modifier = Modifier.fillMaxWidth())
        }
    }
    GMActions(confirmDelete, { confirmDelete = false }, title = "Apagar ${gym?.name.orEmpty()}?", actions = listOf(
        GMAction("Apagar lugar", Icons.Filled.Delete, destructive = true) {
            gym?.let { g ->
                GymLocation.forget(context, env.uid, g.uuid)
                TrainScope.edit(env) { GymPlaces.delete(it, g.uuid) }
            }
            onDismiss()
        }))
}
