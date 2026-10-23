package com.alonsoalmeida.gymbros.ui.leagues

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Block
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.foundation.lazy.items
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.alonsoalmeida.gymbros.data.leagues.LeagueStore
import com.alonsoalmeida.gymbros.data.leagues.PROFILE_FEED
import com.alonsoalmeida.gymbros.domain.ActivityKind
import com.alonsoalmeida.gymbros.domain.ActivityText
import com.alonsoalmeida.gymbros.domain.AttributeSplit
import com.alonsoalmeida.gymbros.domain.BroCatalog
import com.alonsoalmeida.gymbros.domain.Game
import com.alonsoalmeida.gymbros.domain.PhotoRule
import com.alonsoalmeida.gymbros.domain.WorkoutType
import com.alonsoalmeida.gymbros.domain.backup.AccountEdits
import com.alonsoalmeida.gymbros.domain.home.HomeData
import com.alonsoalmeida.gymbros.domain.leagues.CheckInProof
import com.alonsoalmeida.gymbros.domain.leagues.DailyPose
import com.alonsoalmeida.gymbros.domain.leagues.League
import com.alonsoalmeida.gymbros.domain.leagues.LeagueActivityJson
import com.alonsoalmeida.gymbros.domain.leagues.PostSubject
import com.alonsoalmeida.gymbros.domain.leagues.VerificationProblem
import com.alonsoalmeida.gymbros.ui.AppEnv
import com.alonsoalmeida.gymbros.ui.auth.GMSegmented
import com.alonsoalmeida.gymbros.ui.auth.GMTextField
import com.alonsoalmeida.gymbros.ui.auth.LegalModal
import com.alonsoalmeida.gymbros.ui.components.GMButton
import com.alonsoalmeida.gymbros.ui.components.GMButtonKind
import com.alonsoalmeida.gymbros.ui.components.GMDateTimePicker
import com.alonsoalmeida.gymbros.ui.components.GMDivider
import com.alonsoalmeida.gymbros.ui.components.GMEffortPicker
import com.alonsoalmeida.gymbros.ui.components.GMModal
import com.alonsoalmeida.gymbros.ui.components.GMRow
import com.alonsoalmeida.gymbros.ui.components.GMSection
import com.alonsoalmeida.gymbros.ui.components.GMSheet
import com.alonsoalmeida.gymbros.ui.components.GMStepper
import com.alonsoalmeida.gymbros.ui.components.PersonAvatar
import com.alonsoalmeida.gymbros.ui.components.PhotoFill
import com.alonsoalmeida.gymbros.ui.components.Symbols
import com.alonsoalmeida.gymbros.ui.components.gmPress
import com.alonsoalmeida.gymbros.ui.legal.Legal
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMRadius
import com.alonsoalmeida.gymbros.ui.theme.GMType
import kotlinx.coroutines.launch
import java.time.Instant

/** Postar exige termos aceitos e uma conta com permissão (Terms.canPublish + AccessStore) */
fun canPublish(home: HomeData, roles: Set<String>?): Boolean = home.termsVersion >= 2 && roles != null && roles.isNotEmpty()

/** Toda atividade vai para pelo menos um lugar quando a conta pode postar (LeaguesView.swift `hasPostDestination`) */
fun hasPostDestination(canPublish: Boolean, selected: Set<String>) = !canPublish || selected.isNotEmpty()

/** Ligas em que dá para postar agora, mais as já marcadas (para poder tirar) */
fun postLeagues(all: List<League>, selected: Set<String>, now: Instant) = all.filter { (it.hasStarted(now) && !it.isOver(now)) || it.uuid in selected }

/**
 * "Postar em" e a foto (LeaguesView.swift `LeaguePostSection`): perfil e ligas, liga bloqueada com o motivo quando o
 * treino ou a foto não cumprem as regras dela, aviso de foto e a pose do dia.
 */
@Composable
fun LeaguePostSection(
    home: HomeData,
    leagues: List<League>,
    roles: Set<String>?,
    selected: Set<String>,
    onSelected: (Set<String>) -> Unit,
    photo: PickedPhoto?,
    onPhoto: (PickedPhoto?) -> Unit,
    extras: List<ByteArray>? = null,
    onExtras: (List<ByteArray>) -> Unit = {},
    selectAllByDefault: Boolean = true,
    fromHealth: Boolean = false,
    subject: PostSubject? = null,
    onAcceptTerms: () -> Unit,
) {
    val haptic = LocalHapticFeedback.current
    val now = Instant.now()
    val signedIn = canPublish(home, roles)
    val shown = if (signedIn) postLeagues(leagues, selected, now) else emptyList()
    val current = subject?.copy(photo = photo?.proof)
    fun problems(l: League): List<VerificationProblem> = current?.let { l.problems(it, now) } ?: emptyList()
    fun accepts(l: League) = problems(l).isEmpty()
    val everything = if (signedIn) shown.filter { !it.isOver(now) && it.hasStarted(now) && accepts(it) }.map { it.uuid }.toSet() + PROFILE_FEED else emptySet()
    val pose = if (shown.any { it.uuid in selected && it.settings.posesEnabled }) DailyPose.of(now) else null
    var reading by remember { mutableStateOf(false) }

    LaunchedEffect(signedIn) { if (signedIn && selectAllByDefault && selected.isEmpty()) onSelected(everything) }
    // Mudou o treino ou a foto: sai das ligas em que ele não vale mais
    val blocked = shown.filter { !accepts(it) }.map { it.uuid }.toSet()
    LaunchedEffect(blocked) { if (selected.any { it in blocked }) onSelected(selected - blocked) }

    Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
        when {
            signedIn -> {
                val health = if (fromHealth) "Do Apple Saúde, o post leva só tipo, data e duração." else null
                val warning = if (photo != null) null else shown.filter { it.uuid in selected && it.photoRule != PhotoRule.LIVRE }.takeIf { it.isNotEmpty() }?.let { strict ->
                    val zero = strict.filter { it.photoRule == PhotoRule.OBRIGATORIA }.map { it.name }
                    val half = strict.filter { it.photoRule == PhotoRule.METADE }.map { it.name }
                    "📷 Sem foto, o check-in " + (listOfNotNull(zero.takeIf { it.isNotEmpty() }?.let { "não pontua em ${it.joinToString(", ")}" },
                                                                 half.takeIf { it.isNotEmpty() }?.let { "vale metade em ${it.joinToString(", ")}" })).joinToString(" e ") + "."
                }
                val footer = if (selected.isEmpty()) "Escolha pelo menos um lugar para salvar." else listOfNotNull(health, warning).joinToString(" ").ifEmpty { null }
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(Modifier.padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text("POSTAR EM", color = GMColors.dim, style = GMType.caption.copy(fontWeight = FontWeight.Bold, letterSpacing = 0.6.sp), modifier = Modifier.weight(1f))
                        val all = selected.containsAll(everything)
                        Text(if (all) "Desmarcar" else "Marcar todos", color = GMColors.accent, style = GMType.caption.copy(fontWeight = FontWeight.Bold),
                             modifier = Modifier.gmPress {
                                 onSelected(if (all) emptySet() else selected + everything)
                                 haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                             })
                    }
                    com.alonsoalmeida.gymbros.ui.components.GMCard {
                        Destination(PROFILE_FEED in selected, true, "Meu perfil", "Aparece no seu perfil público", {
                            PersonAvatar(home.trainerName, size = 38.dp, photo = home.profilePhoto)
                        }) { onSelected(toggle(selected, PROFILE_FEED)); haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove) }
                        for (l in shown) {
                            GMDivider()
                            val p = problems(l).firstOrNull()
                            val sub = when {
                                p != null -> if (p.fix == "escolha outro treino") p.message else "${p.message} Para postar aqui: ${p.fix}."
                                l.isOver(now) -> "Encerrada"
                                !l.hasStarted(now) -> "Liga · ${League.startsText(l.start, now)}"
                                else -> "Liga · " + (l.daysLeft(now)?.let { if (it == 1) "último dia" else "faltam $it dias" } ?: "sem fim")
                            }
                            Destination(l.uuid in selected, p == null, l.name, sub, {
                                Box(Modifier.size(38.dp).background(GMColors.raised, CircleShape), contentAlignment = Alignment.Center) { Text(l.emoji, fontSize = 20.sp) }
                            }) { onSelected(toggle(selected, l.uuid)); haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove) }
                        }
                    }
                    footer?.let { Text(it, color = GMColors.dim, style = GMType.caption, modifier = Modifier.padding(horizontal = 4.dp)) }
                }
            }
            home.termsVersion >= 2 -> GMSection("Postar em") {
                Text(if (roles == null) "Conferindo sua conta…" else "Sua conta não pode postar agora. A atividade fica só no seu histórico.",
                     color = GMColors.dim, style = GMType.footnote)
            }
            else -> GMSection("Postar em") {
                Text("Para postar no perfil e nas ligas, aceite os termos de uso. Sem isso, a atividade fica só no seu histórico.",
                     color = GMColors.dim, style = GMType.footnote)
                GMButton("Ler e aceitar os termos", { reading = true }, icon = Icons.Filled.Description, kind = GMButtonKind.SECONDARY, small = true)
            }
        }
        PhotoSection(photo, onPhoto, extras, onExtras, pose)
    }
    LegalModal(reading, "Termos de uso", Legal.terms, "Atualizados", onDismiss = { reading = false }, confirm = "Aceitar",
               onConfirm = { onAcceptTerms(); reading = false })
}

private fun toggle(s: Set<String>, id: String) = if (id in s) s - id else s + id

@Composable
private fun Destination(on: Boolean, enabled: Boolean, title: String, subtitle: String, icon: @Composable () -> Unit, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().gmPress(enabled = enabled, onClick = onClick).then(if (enabled) Modifier else Modifier.padding(0.dp)),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.then(if (enabled) Modifier else Modifier)) { icon() }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(title, color = Color.White.copy(alpha = if (enabled) 1f else 0.5f), style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold), maxLines = 1)
            Text(subtitle, color = GMColors.dim.copy(alpha = if (enabled) 0.55f else 0.3f), style = GMType.caption)
        }
        Icon(if (!enabled) Icons.Filled.Block else if (on && enabled) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked, null,
             tint = if (on && enabled) GMColors.accent else GMColors.dim, modifier = Modifier.size(24.dp))
    }
}

/** Foto do post: a principal (trocar ou tirar), até 4 a mais e a pose do dia */
@Composable
private fun PhotoSection(photo: PickedPhoto?, onPhoto: (PickedPhoto?) -> Unit, extras: List<ByteArray>?, onExtras: (List<ByteArray>) -> Unit, pose: DailyPose?) {
    val pickers = rememberPhotoPickers(pose?.id, onPicked = { onPhoto(it) })
    val extraPickers = rememberPhotoPickers(pose?.id, onPicked = { p -> extras?.let { if (it.size < 4) onExtras(it + p.bytes) } },
                                            onMany = { list -> extras?.let { onExtras((it + list).take(4)) } })
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("FOTO", color = GMColors.dim, style = GMType.caption.copy(fontWeight = FontWeight.Bold, letterSpacing = 0.6.sp), modifier = Modifier.padding(horizontal = 4.dp))
        if (pose != null) {
            Row(Modifier.fillMaxWidth().background(GMColors.card, GMRadius.card).padding(12.dp), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(pose.emoji, fontSize = 22.sp)
                Column {
                    Text("Pose do dia: ${pose.name}", color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
                    Text("Sem a pose do dia na foto, o check-in não pontua.", color = GMColors.dim, style = GMType.caption)
                }
            }
        }
        if (photo != null) {
            Box(Modifier.fillMaxWidth().height(200.dp).clip(GMRadius.card).gmPress(onClick = pickers.gallery)) {
                PhotoFill(photo.bytes, Modifier.fillMaxSize(), 1200)
                Row(Modifier.align(Alignment.BottomStart).padding(10.dp).background(Color.Black.copy(alpha = 0.6f), CircleShape).padding(horizontal = 10.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Icon(Icons.Filled.Sync, null, tint = Color.White, modifier = Modifier.size(12.dp))
                    Text("Trocar", color = Color.White, style = GMType.caption.copy(fontWeight = FontWeight.Bold))
                }
                Text(CheckInProof.photoLabel(photo.proof), color = Color.White, style = GMType.caption2.copy(fontWeight = FontWeight.SemiBold),
                     modifier = Modifier.align(Alignment.BottomEnd).padding(10.dp).background(Color.Black.copy(alpha = 0.6f), CircleShape).padding(horizontal = 8.dp, vertical = 5.dp))
                Box(Modifier.align(Alignment.TopEnd).padding(10.dp).size(30.dp).background(Color.Black.copy(alpha = 0.6f), CircleShape)
                        .gmPress {
                            // Tirou a principal: a próxima extra sobe
                            if (!extras.isNullOrEmpty()) { onPhoto(PickedPhoto(extras.first(), com.alonsoalmeida.gymbros.domain.leagues.PhotoProof("library"))); onExtras(extras.drop(1)) }
                            else onPhoto(null)
                        }.semantics { contentDescription = "Tirar foto" }, contentAlignment = Alignment.Center) {
                    Icon(Icons.Filled.Close, null, tint = Color.White, modifier = Modifier.size(14.dp))
                }
            }
            if (extras != null) {
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    extras.forEachIndexed { i, data ->
                        Box(Modifier.size(72.dp).clip(GMRadius.m)) {
                            PhotoFill(data, Modifier.fillMaxSize(), 300)
                            Box(Modifier.align(Alignment.TopEnd).padding(3.dp).size(22.dp).background(Color.Black.copy(alpha = 0.6f), CircleShape)
                                    .gmPress { onExtras(extras.filterIndexed { j, _ -> j != i }) }.semantics { contentDescription = "Tirar foto ${i + 2}" },
                                contentAlignment = Alignment.Center) { Icon(Icons.Filled.Close, null, tint = Color.White, modifier = Modifier.size(11.dp)) }
                        }
                    }
                    if (extras.size < 4) {
                        MiniTile(Icons.Filled.CameraAlt, "Tirar mais uma foto", extraPickers.camera)
                        MiniTile(Icons.Filled.Add, "Mais fotos da galeria", extraPickers.galleryMany)
                    }
                }
            }
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                PhotoTile(Modifier.weight(1f), Icons.Filled.CameraAlt, "Tirar foto", pickers.camera)
                PhotoTile(Modifier.weight(1f), Icons.Filled.PhotoLibrary, "Da galeria", pickers.gallery)
            }
        }
    }
}

private fun Modifier.dashed(radius: androidx.compose.ui.unit.Dp) = this.then(Modifier.drawBehindDashed(radius))

private fun Modifier.drawBehindDashed(radius: androidx.compose.ui.unit.Dp): Modifier = Modifier.drawBehind {
    drawRoundRect(GMColors.dim.copy(alpha = 0.4f), cornerRadius = androidx.compose.ui.geometry.CornerRadius(radius.toPx()),
                  style = Stroke(width = 1.5.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(6.dp.toPx(), 5.dp.toPx()))))
}

@Composable
private fun PhotoTile(modifier: Modifier, icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, onClick: () -> Unit) {
    Column(modifier.heightIn(min = 110.dp).gmPress(onClick = onClick).background(GMColors.card, GMRadius.card).dashed(20.dp),
           horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterVertically)) {
        Icon(icon, null, tint = GMColors.dim, modifier = Modifier.size(26.dp))
        Text(title, color = GMColors.dim, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
    }
}

@Composable
private fun MiniTile(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, onClick: () -> Unit) {
    Box(Modifier.size(72.dp).gmPress(onClick = onClick).background(GMColors.card, GMRadius.m).dashed(12.dp).semantics { contentDescription = label },
        contentAlignment = Alignment.Center) { Icon(icon, null, tint = GMColors.dim, modifier = Modifier.size(22.dp)) }
}

/** Aceitar os termos pelo "Postar em" (TermsGate) */
suspend fun acceptTerms(env: AppEnv, home: HomeData) {
    env.copies.edit { c ->
        AccountEdits.updateSettings(c ?: AccountEdits.empty(home.trainerName, Instant.now())) {
            it["termsAcceptedVersion"] = com.dd.plist.NSNumber(2); it["termsAcceptedAt"] = com.dd.plist.NSDate(java.util.Date())
        }
    }
}

/** Check-in pela liga (LeaguesView.swift `CheckInForm`): nova atividade ou uma já registrada, com o post */
@Composable
fun CheckInFormScreen(env: AppEnv, home: HomeData, vm: LeaguesViewModel, preselected: Set<String>, onDismiss: () -> Unit) {
    val ui by vm.ui.collectAsStateWithLifecycle()
    val roles by vm.roles.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    val haptic = LocalHapticFeedback.current
    var useExisting by remember { mutableStateOf(false) }
    var existing by remember { mutableStateOf<String?>(null) }
    var extras by remember { mutableStateOf(setOf<String>()) }
    var type by remember { mutableStateOf(BroCatalog.classicType["musculacao"]!!) }
    var minutes by remember { mutableIntStateOf(60) }
    var effort by remember { mutableIntStateOf(6) }
    var date by remember { mutableStateOf(Instant.now()) }
    var title by remember { mutableStateOf("") }
    var note by remember { mutableStateOf("") }
    var leagues by remember { mutableStateOf(preselected) }
    var photo by remember { mutableStateOf<PickedPhoto?>(null) }
    var extraPhotos by remember { mutableStateOf(listOf<ByteArray>()) }
    var choosingType by remember { mutableStateOf(false) }

    val since = Instant.now().minusSeconds(7 * 86400)
    val recent = ui.copy.activities.filter { it.date >= since }.sortedByDescending { it.date }
    val chosen = existing?.let { id -> ui.activities[id.uppercase()] }
    val subject = if (useExisting) chosen?.let { PostSubject(it.workoutTypeID, it.date, it.minutes, it.isDeviceRecorded) }
                  else PostSubject(type, date, minutes)

    GMModal(true, "Check-in", onDismiss, confirm = "Postar", confirmEnabled = leagues.isNotEmpty() && !(useExisting && existing == null), onConfirm = {
        scope.launch {
            val now = Instant.now()
            val activity: LeagueActivityJson = if (useExisting && chosen != null) chosen else {
                val kind = WorkoutType.byID(type)?.kind ?: ActivityKind.OUTRO
                val id = com.alonsoalmeida.gymbros.domain.leagues.LeagueEdits.newID()
                val split = AttributeSplit.split(kind, minutes, effort, healthType = type)
                env.copies.edit { c -> AccountEdits.addActivity(c ?: AccountEdits.empty(home.trainerName, now),
                    AccountEdits.NewActivity(kind.raw, date, minutes, effort, title, type, AttributeSplit.encode(split), id = id)) }
                LeagueActivityJson(id, kind.raw, date, minutes, effort, title, healthType = type)
            }
            // Não posta duas vezes a mesma atividade na mesma liga
            val already = ui.copy.checkIns.orEmpty().filter { it.activityUUID.equals(activity.uuid, true) }.map { it.leagueUUID.uppercase() }.toSet()
            val grouped = if (useExisting) extras.mapNotNull { ui.activities[it.uppercase()] } else emptyList()
            vm.store.post(LeagueStore.NewPost(activity, title, note, photo?.bytes, photo?.proof, photo?.pose, extraPhotos, grouped), leagues, ui.leagues, already)
            haptic.performHapticFeedback(HapticFeedbackType.LongPress)
            onDismiss()
        }
    }) {
        GMSegmented(listOf(false to "Nova atividade", true to "Já registrada"), useExisting) { useExisting = it }
        if (useExisting) {
            GMSection("Atividades recentes", footer = "Treinos guiados e os importados do Apple Saúde aparecem aqui. Atividades do mesmo dia podem ir juntas num check-in só: toque em mais de uma.") {
                if (recent.isEmpty()) Text("Nada registrado nos últimos 7 dias.", color = GMColors.dim, style = GMType.body)
                recent.forEachIndexed { i, a ->
                    val id = a.uuid.uppercase()
                    val posted = ui.copy.checkIns.orEmpty().any { it.activityUUID.equals(id, true) && it.leagueUUID.uppercase() in leagues }
                    val on = existing == id || id in extras
                    GMRow(a.typeName, icon = LeagueFormats.typeIcon(a.workoutTypeID), subtitle = "${ActivityText.duration(a.minutes)} · ${LeagueFormats.weekdayDayTime(a.date)}",
                          onClick = {
                              haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                              // Primeira escolhida é a principal; outras do mesmo dia entram juntas; de outro dia, recomeça
                              val first = existing?.let { ui.activities[it] }
                              if (first == null) { existing = id; extras = emptySet() }
                              else if (id == existing) { existing = extras.firstOrNull(); existing?.let { extras = extras - it } }
                              else if (a.date.atZone(java.time.ZoneId.systemDefault()).toLocalDate() == first.date.atZone(java.time.ZoneId.systemDefault()).toLocalDate()) {
                                  extras = if (id in extras) extras - id else extras + id
                              } else { existing = id; extras = emptySet() }
                          }) {
                        if (posted) Text("já postada", color = GMColors.dim, style = GMType.caption2)
                        SelectDot(on)
                    }
                    if (i < recent.lastIndex) GMDivider()
                }
            }
        } else {
            GMSection("Atividade") {
                GMRow(WorkoutType.byID(type)?.name ?: "Outro", icon = Symbols.of(BroCatalog.workoutSymbols[type] ?: ""), iconTint = GMColors.accent,
                      chevron = true, onClick = { choosingType = true })
            }
            GMSection {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Duração", color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold), modifier = Modifier.weight(1f))
                    GMStepper(minutes, { minutes = it }, 5..Game.MAX_MINUTES, step = 5, format = ActivityText::duration)
                }
                GMDivider()
                GMEffortPicker(effort) { effort = it }
            }
            GMSection("Quando") { GMDateTimePicker(date) { date = it } }
        }
        GMSection("Post") {
            GMTextField(title, { title = it }, "Título (ex.: Dia de perna 🦵)")
            GMTextField(note, { note = it }, "Descrição (opcional)")
        }
        LeaguePostSection(home, ui.leagues, roles, leagues, { leagues = it }, photo, { photo = it }, extraPhotos, { extraPhotos = it },
                          selectAllByDefault = false, subject = subject, onAcceptTerms = { scope.launch { acceptTerms(env, home) } })
    }
    if (choosingType) WorkoutTypeSheet(setOf(type), single = true, onDismiss = { choosingType = false }) { type = it.first(); choosingType = false }
}

/** Escolha de tipos de treino (LeaguesView.swift `LeagueWorkoutTypePicker`), por seção e com busca */
@Composable
fun WorkoutTypeSheet(selection: Set<Long>, single: Boolean = false, except: Boolean = false, title: String? = null, onDismiss: () -> Unit,
                     onDone: (Set<Long>) -> Unit) {
    var query by remember { mutableStateOf("") }
    var chosen by remember { mutableStateOf(selection) }
    val tint = if (except) GMColors.danger else GMColors.accent
    fun fold(s: String) = java.text.Normalizer.normalize(s, java.text.Normalizer.Form.NFD).replace(Regex("\\p{M}"), "").lowercase()
    GMSheet(onDismiss = { if (single) onDismiss() else onDone(chosen) }) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(title ?: if (single) "Tipo de treino" else if (except) "Não valem pontos" else "Valem pontos", color = Color.White,
                     style = GMType.title3.copy(fontWeight = FontWeight.Bold))
                if (!single) Text(when (chosen.size) { 0 -> "Nenhum escolhido"; 1 -> "1 escolhido"; else -> "${chosen.size} escolhidos" },
                                  color = GMColors.dim, style = GMType.subheadline)
            }
            if (!single) GMButton("Pronto", { onDone(chosen) }, full = false, small = true)
        }
        GMTextField(query, { query = it }, "Buscar treino")
        val q = fold(query.trim())
        val found = WorkoutType.all.filter { t -> q.isEmpty() || fold(t.name).contains(q) || BroCatalog.workoutAliases[t.id].orEmpty().any { fold(it).contains(q) } }
        if (found.isEmpty()) Text("Nenhum resultado para \"$query\"", color = GMColors.dim, style = GMType.subheadline)
        androidx.compose.foundation.lazy.LazyColumn(Modifier.fillMaxWidth().heightIn(max = 520.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            for (section in found.map { it.section }.distinct()) {
                val items = found.filter { it.section == section }
                item(key = "s-$section") {
                    val on = items.count { it.id in chosen }
                    Row(Modifier.fillMaxWidth().padding(top = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(section, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
                        if (on > 0) Text("  $on", color = tint, style = GMType.caption.copy(fontWeight = FontWeight.Bold))
                        androidx.compose.foundation.layout.Spacer(Modifier.weight(1f))
                        if (!single) {
                            val all = on == items.size
                            Text(if (all) "Tirar todos" else "Marcar todos", color = GMColors.dim, style = GMType.caption.copy(fontWeight = FontWeight.SemiBold),
                                 modifier = Modifier.gmPress { chosen = if (all) chosen - items.map { it.id }.toSet() else chosen + items.map { it.id } })
                        }
                    }
                }
                items(items.chunked(3), key = { row -> "r-" + row.joinToString { "${it.id}" } }) { row ->
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        for (t in row) {
                            val on = t.id in chosen
                            Column(Modifier.weight(1f).heightIn(min = 78.dp).gmPress {
                                if (single) onDone(setOf(t.id)) else chosen = if (on) chosen - t.id else chosen + t.id
                            }.background(if (on) tint.copy(alpha = 0.18f) else GMColors.raised, GMRadius.m)
                                .border(1.5.dp, if (on) tint else Color.Transparent, GMRadius.m).padding(6.dp),
                                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterVertically)) {
                                Icon(Symbols.of(BroCatalog.workoutSymbols[t.id] ?: ""), null, tint = if (on) tint else Color.White, modifier = Modifier.size(22.dp))
                                Text(t.name, color = if (on) tint else Color.White, style = GMType.caption.copy(fontWeight = FontWeight.SemiBold),
                                     maxLines = 2, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                            }
                        }
                        repeat(3 - row.size) { androidx.compose.foundation.layout.Spacer(Modifier.weight(1f)) }
                    }
                }
            }
        }
    }
}
