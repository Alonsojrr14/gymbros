package com.alonsoalmeida.gymbros.ui.train

import android.Manifest
import android.os.Build
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.collectAsState
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.alonsoalmeida.gymbros.data.train.RestAlarm
import com.alonsoalmeida.gymbros.data.train.TrainCopy
import com.alonsoalmeida.gymbros.data.train.TrainData
import com.alonsoalmeida.gymbros.data.train.TrainEdits
import com.alonsoalmeida.gymbros.data.train.TrainHooks
import com.alonsoalmeida.gymbros.data.train.TrainScope
import com.alonsoalmeida.gymbros.data.train.WgerLibrary
import com.alonsoalmeida.gymbros.data.train.WodRunStore
import com.alonsoalmeida.gymbros.domain.ActivityText
import com.alonsoalmeida.gymbros.domain.home.HomeData
import com.alonsoalmeida.gymbros.domain.train.Deload
import com.alonsoalmeida.gymbros.domain.train.Exercises
import com.alonsoalmeida.gymbros.domain.train.Progression
import com.alonsoalmeida.gymbros.domain.train.Routine
import com.alonsoalmeida.gymbros.domain.train.RoutineItem
import com.alonsoalmeida.gymbros.domain.train.RoutineTemplate
import com.alonsoalmeida.gymbros.domain.train.Session
import com.alonsoalmeida.gymbros.domain.train.Wod
import com.alonsoalmeida.gymbros.domain.train.WodPlan
import com.alonsoalmeida.gymbros.domain.train.WorkoutStart
import com.alonsoalmeida.gymbros.domain.train.Weeks
import com.alonsoalmeida.gymbros.domain.train.iosWeekday
import com.alonsoalmeida.gymbros.domain.train.setText
import com.alonsoalmeida.gymbros.domain.train.weekdaysText
import com.alonsoalmeida.gymbros.ui.AppEnv
import com.alonsoalmeida.gymbros.ui.components.ExerciseThumb
import com.alonsoalmeida.gymbros.ui.components.GMAction
import com.alonsoalmeida.gymbros.ui.components.GMActions
import com.alonsoalmeida.gymbros.ui.components.GMButton
import com.alonsoalmeida.gymbros.ui.components.GMButtonKind
import com.alonsoalmeida.gymbros.ui.components.GMCard
import com.alonsoalmeida.gymbros.ui.components.GMDecimalField
import com.alonsoalmeida.gymbros.ui.components.GMDivider
import com.alonsoalmeida.gymbros.ui.components.GMIconButton
import com.alonsoalmeida.gymbros.ui.components.GMModal
import com.alonsoalmeida.gymbros.ui.components.GMRow
import com.alonsoalmeida.gymbros.ui.components.GMScreen
import com.alonsoalmeida.gymbros.ui.components.GMSection
import com.alonsoalmeida.gymbros.ui.components.GMSheet
import com.alonsoalmeida.gymbros.ui.components.GMToggle
import com.alonsoalmeida.gymbros.ui.components.PersonAvatar
import com.alonsoalmeida.gymbros.ui.components.TrainIcons
import com.alonsoalmeida.gymbros.ui.components.gmPress
import com.alonsoalmeida.gymbros.ui.copy
import com.alonsoalmeida.gymbros.ui.main.SoonModal
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMType
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

internal val ptBR: Locale = Locale.forLanguageTag("pt-BR")
internal fun fmt(i: Instant, pattern: String): String = i.atZone(ZoneId.systemDefault()).format(DateTimeFormatter.ofPattern(pattern, ptBR))
internal fun hhmm(i: Instant) = fmt(i, "HH:mm")
internal fun dayMonth(i: Instant) = fmt(i, "d 'de' MMM")
internal fun dayMonthYear(i: Instant) = fmt(i, "d 'de' MMM 'de' yyyy")
internal fun weekdayName(i: Instant) = fmt(i, "EEEE")

/** Estado de navegação da aba (NavigationStack + modais do TrainView.swift) */
@Stable
internal class TrainNav {
    var stack by mutableStateOf(listOf<String>())
    /** Treino em andamento aberto (id da sessão) */
    var workout by mutableStateOf<String?>(null)
    /** Cronômetro do WOD aberto */
    var wod by mutableStateOf<Wod?>(null)
    var plan by mutableStateOf<String?>(null)
    var importing by mutableStateOf(false)
    var library by mutableStateOf(false)
    var soon by mutableStateOf<String?>(null)
    fun push(route: String) { stack = stack + route }
    fun pop() { stack = stack.dropLast(1) }
}

/** Dados do treino lidos da cópia da conta, já com os personalizados, objetivos e PRs instalados para as regras */
@Composable
internal fun rememberTrainData(env: AppEnv): TrainData {
    val copy = env.copy()
    return remember(copy) { TrainCopy.read(copy).also(TrainCopy::install) }
}

/** Miniatura do exercício com a ilustração do wger, quando há */
@Composable
internal fun Thumb(id: String, size: androidx.compose.ui.unit.Dp = 44.dp) {
    val ex = Exercises.byID(id)
    val context = LocalContext.current
    if (ex != null) ExerciseThumb(ex, remember(id) { WgerLibrary.photoAssets(context, id).firstOrNull() }, size)
    else Box(Modifier.size(size).background(GMColors.raised, com.alonsoalmeida.gymbros.ui.theme.GMRadius.m), contentAlignment = Alignment.Center) {
        Icon(TrainIcons.of("list.bullet.rectangle"), null, tint = GMColors.accent)
    }
}

/** Aba Treino (Train/TrainView.swift) */
@Composable
fun TrainTab(env: AppEnv, home: HomeData) {
    val context = LocalContext.current
    val data = rememberTrainData(env)
    val nav = remember { TrainNav() }
    WodRunStore.load(context)
    val notifyPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {}

    BackHandler(nav.stack.isNotEmpty()) { nav.pop() }

    /** Começa um treino (LiveWorkout.startSession): cargas sugeridas, aquecimento automático e deload */
    fun start(routine: Routine?) {
        val now = Instant.now()
        val s = WorkoutStart.session(routine, data.history, data.deloadActive(now), data.autoWarmup, now)
        TrainScope.edit(env) { TrainEdits.saveSession(it, s) }
        nav.workout = s.uuid
        // O aviso de fim do descanso é opcional: só pede a permissão com o ajuste ligado (iOS pede ao começar)
        if (data.restNotification && Build.VERSION.SDK_INT >= 33 && !RestAlarm.canNotify(context)) notifyPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
    }

    when (val top = nav.stack.lastOrNull()) {
        null -> TrainHome(env, home, data, nav, ::start)
        else -> {
            val (route, arg) = top.substringBefore('/') to top.substringAfter('/', "")
            when (route) {
                "routine" -> RoutineEditScreen(env, data, arg, nav)
                "prs" -> PRBookScreen(env, data, nav)
                "stats" -> ExerciseStatsScreen(data, nav)
                "exercise" -> ExerciseDetailScreen(env, data, arg, nav)
                "volume" -> WeeklyVolumeScreen(data, nav)
                "muscles" -> MuscleMapScreen(data, nav)
                "public" -> PublicRoutinesScreen(env, data, nav)
                "wods" -> WodListScreen(env, data, nav)
                "wod" -> WodDetailScreen(env, data, arg, nav)
                "timeline" -> WodTimelineScreen(env, data, nav)
                "session" -> SessionDetailScreen(env, home, data, arg, nav)
                else -> nav.pop()
            }
        }
    }

    // Modais da aba (abrem por cima de qualquer tela empilhada)
    nav.workout?.let { id -> WorkoutScreen(env, home, data, id) { nav.workout = null } }
    nav.wod?.let { w -> WodTimerScreen(env, home, data, w) { nav.wod = null } }
    nav.plan?.let { id -> PlannedWodModal(env, data, id, nav) { nav.plan = null } }
    ImportWodModal(nav.importing, env, data, nav, editing = null) { nav.importing = false }
    ExercisePickerModal(nav.library, env, data, onPick = null) { nav.library = false }
    SoonModal(nav.soon) { nav.soon = null }
}

@Composable
private fun TrainHome(env: AppEnv, home: HomeData, data: TrainData, nav: TrainNav, start: (Routine?) -> Unit) {
    val context = LocalContext.current
    val now = Instant.now()
    val zone = ZoneId.systemDefault()
    val today = iosWeekday(now.atZone(zone).toLocalDate())
    val wodRun by WodRunStore.state.collectAsState()
    val doneWods = data.wods.map { it.wodID }.toSet()
    val plannedToday = WodPlan.pending(data.plannedRaw, doneWods, now.atZone(zone).toLocalDate(), zone)
    val plannedNext = WodPlan.all(data.plannedRaw).filter { it.day.atZone(zone).toLocalDate().isAfter(now.atZone(zone).toLocalDate()) }
    val inProgress = data.inProgress
    var routineMenu by remember { mutableStateOf<Routine?>(null) }
    var confirmDelete by remember { mutableStateOf<Routine?>(null) }
    var sessionMenu by remember { mutableStateOf<Session?>(null) }
    var templates by remember { mutableStateOf(false) }
    var plates by remember { mutableStateOf(false) }
    var profile by remember { mutableStateOf(false) }
    val published = rememberPublished(env)

    GMScreen("Treino", bottomInset = 120.dp,
             leading = { PersonAvatar(home.trainerName, photo = home.profilePhoto, modifier = Modifier.gmPress { profile = true }) }) {
        DeloadCard(env, data, now)
        PendingRoutineCard(env, data)
        wodRun?.let { w ->
            GMCard {
                StartCard(w.wod.name, when {
                    w.startedAt != null -> "WOD em andamento · ${w.wod.format.name}"
                    w.sessionStart != null -> "Em andamento · ${if (w.working >= w.wod.parts.size) "WOD" else w.wod.parts[w.working].title}"
                    else -> "Aberto desde ${hhmm(w.openedAt)}"
                }, "Continuar") { nav.wod = w.wod }
            }
        }
        if (inProgress != null) {
            GMCard { StartCard(inProgress.title, "Em andamento desde ${hhmm(inProgress.start)}", "Continuar") { nav.workout = inProgress.uuid } }
        } else {
            val todays = data.routines.filter { today in it.weekdays }
            GMSection(if (todays.isEmpty()) "Hoje" else "Hoje · ${weekdayName(now)}") {
                if (plannedToday != null && wodRun == null) {
                    StartCard(plannedToday.name, "Treino do coach · ${plannedToday.format.name}", "Começar") {
                        nav.wod = plannedToday.wod(WodRunStore.preferredLevel(context))
                    }
                    GMRow("Ver treino completo", TrainIcons.of("list.bullet"), subtitle = plannedToday.parts.takeIf { it.isNotEmpty() }?.joinToString(", ") { it.title },
                          chevron = true, onClick = { nav.plan = plannedToday.id })
                    GMDivider()
                }
                if (todays.isEmpty() && plannedToday == null) {
                    Text(if (data.routines.isEmpty()) "Crie uma rotina ou use um modelo pronto." else "Nenhuma rotina para hoje. Descanso também evolui o bro.",
                         color = GMColors.dim, style = GMType.subheadline)
                }
                for (r in todays) {
                    StartCard(r.name, "${r.items.size} exercícios · ${r.items.sumOf { it.sets }} séries", "Começar") { start(r) }
                    GMDivider()
                }
                GMRow("Treino livre", TrainIcons.of("plus"), GMColors.accent, "Monte na hora", chevron = true, onClick = { start(null) })
            }
        }

        GMSection("Minhas rotinas") {
            for (r in data.routines) {
                GMRow(r.name, subtitle = weekdaysText(r.weekdays) + " · ${r.items.size} exercícios" + if (r.uuid in published) " · pública" else "",
                      onClick = { nav.push("routine/${r.uuid}") }) {
                    GMIconButton(TrainIcons.of("ellipsis"), "Opções de ${r.name}", { routineMenu = r }, size = 32.dp)
                }
                GMDivider()
            }
            GMRow("Nova rotina", TrainIcons.of("plus"), GMColors.accent, onClick = {
                TrainScope.edit(env) { TrainEdits.saveRoutine(it, Routine(TrainEdits.newID(), "Nova rotina", order = data.routines.size)) }
            })
            GMDivider()
            GMRow("Usar modelo pronto", TrainIcons.of("square.stack"), GMColors.accent, chevron = true, onClick = { templates = true })
            GMDivider()
            GMRow("Rotinas públicas", TrainIcons.of("person.2.fill"), GMColors.accent, "Dos bros e dos amigos: curta e salve uma cópia", chevron = true,
                  onClick = { nav.push("public") })
        }

        GMSection("CrossFit") {
            GMRow("Importar treino do coach", TrainIcons.of("doc.on.clipboard"), GMColors.accent, "Cole o texto ou leia um print", chevron = true,
                  onClick = { nav.importing = true })
            GMDivider()
            for (p in plannedNext) {
                GMRow(p.name, TrainIcons.of("calendar"), subtitle = plannedDayText(p.day) + " · " + p.format.name, chevron = true, onClick = { nav.plan = p.id })
                GMDivider()
            }
            GMRow("Meus WODs", TrainIcons.of("clock.arrow.circlepath"), GMColors.accent, "Linha do tempo do que você importou e treinou", chevron = true,
                  onClick = { nav.push("timeline") })
            GMDivider()
            GMRow("WODs e cronômetro", TrainIcons.of("flame.fill"), GMColors.streak, "Fran, Cindy, Murph… · For Time, AMRAP, EMOM, Tabata", chevron = true,
                  onClick = { nav.push("wods") })
        }

        GMSection("Evolução") {
            GMRow("Meus PRs", TrainIcons.of("trophy.fill"), GMColors.trophy, "Sessão de PR: carga e reps de cada exercício", chevron = true, onClick = { nav.push("prs") })
            GMDivider()
            GMRow("Exercícios e recordes", TrainIcons.of("chart.line.uptrend.xyaxis"), chevron = true, onClick = { nav.push("stats") })
            GMDivider()
            GMRow("Volume semanal por músculo", TrainIcons.of("chart.bar.fill"), subtitle = "Séries por grupo vs. faixa de 10–20", chevron = true,
                  onClick = { nav.push("volume") })
            GMDivider()
            GMRow("Mapa muscular", TrainIcons.of("figure.stand"), chevron = true, onClick = { nav.push("muscles") })
            GMDivider()
            GMRow("Biblioteca de exercícios", TrainIcons.of("books.vertical"), chevron = true, onClick = { nav.library = true })
            GMDivider()
            // Peso e medidas é do Perfil (Profile/BodyTrackerView.swift), de outra frente
            GMRow("Peso e medidas", TrainIcons.of("scalemass"), chevron = true, onClick = { nav.soon = "Peso e medidas" })
            GMDivider()
            GMRow("Calculadora de anilhas", TrainIcons.of("circle.grid.2x1"), chevron = true, onClick = { plates = true })
        }

        val finished = data.finished
        if (finished.isNotEmpty()) {
            GMSection("Treinos recentes") {
                val shown = finished.take(10)
                for (s in shown) {
                    Row(Modifier.fillMaxWidth().gmPress { nav.push("session/${s.uuid}") }, verticalAlignment = Alignment.CenterVertically) {
                        SessionRow(s, Modifier.weight(1f))
                        GMIconButton(TrainIcons.of("ellipsis"), "Opções do treino", { sessionMenu = s }, size = 32.dp)
                    }
                    if (s !== shown.last()) GMDivider()
                }
            }
        }
    }

    // Menus e confirmações
    val r = routineMenu
    GMActions(r != null, { routineMenu = null }, title = r?.name, actions = r?.let { routine ->
        buildList {
            if (inProgress == null) add(GMAction("Começar agora", TrainIcons.of("play.fill")) { start(routine) })
            add(GMAction("Editar", TrainIcons.of("pencil")) { nav.push("routine/${routine.uuid}") })
            if (routine.uuid in published) add(GMAction("Tirar das rotinas públicas", TrainIcons.of("eye.slash")) { unpublishRoutine(env, routine) })
            else if (routine.items.isNotEmpty()) add(GMAction("Publicar rotina", TrainIcons.of("person.2")) { publishRoutine(env, data, routine) })
            add(GMAction("Apagar rotina", TrainIcons.of("trash"), destructive = true) { confirmDelete = routine })
        }
    }.orEmpty())
    val del = confirmDelete
    GMActions(del != null, { confirmDelete = null }, title = del?.let { "Apagar ${it.name}?" }, message = "Os treinos já feitos com ela continuam no histórico.",
              actions = del?.let { listOf(GMAction("Apagar rotina", TrainIcons.of("trash"), destructive = true) { TrainScope.edit(env) { c -> TrainEdits.deleteRoutine(c, it.uuid) } }) }.orEmpty())
    val sm = sessionMenu
    GMActions(sm != null, { sessionMenu = null }, title = sm?.title, message = "O XP desse treino também sai do bro.",
              actions = sm?.let { listOf(GMAction("Apagar treino", TrainIcons.of("trash"), destructive = true) { deleteSession(env, it, nav) }) }.orEmpty())

    TemplatesModal(templates, env, data) { templates = false }
    if (plates) GMSheet({ plates = false }) { PlateCalculator(env, data, 60.0) }
    com.alonsoalmeida.gymbros.ui.profile.ProfileModal(profile, env, home) { profile = false }
}

/** Apaga o treino; com atividade ligada, quem apaga é a atividade (o XP fica com os bros), de outra frente */
internal fun deleteSession(env: AppEnv, s: Session, nav: TrainNav) {
    val activity = s.activityUUID
    if (activity == null) { TrainScope.edit(env) { TrainEdits.deleteSession(it, s.uuid) }; return }
    val hook = TrainHooks.deleteActivity
    if (hook != null) hook(env, activity) else nav.soon = "Apagar atividade"
}

internal fun plannedDayText(d: Instant): String {
    val zone = ZoneId.systemDefault()
    val day = d.atZone(zone).toLocalDate()
    return if (day == java.time.LocalDate.now(zone).plusDays(1)) "Amanhã" else com.alonsoalmeida.gymbros.ui.components.GMDateText.day(d)
}

/** Título, subtítulo e o botão de começar/continuar (TrainView.swift `card`) */
@Composable
internal fun StartCard(title: String, subtitle: String, action: String, onTap: () -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, color = Color.White, style = GMType.headline)
            Text(subtitle, color = GMColors.dim, style = GMType.caption)
        }
        GMButton(action, onTap, icon = TrainIcons.of("play.fill"), full = false, small = true)
    }
}

@Composable
private fun DeloadCard(env: AppEnv, data: TrainData, now: Instant) {
    val zone = ZoneId.systemDefault()
    val until = data.deloadUntil
    if (data.deloadActive(now) && until != null) {
        GMCard {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("🔋", fontSize = 30.sp)
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text("Semana de deload", color = Color.White, style = GMType.headline)
                    Text("Até ${weekdayName(until.minusSeconds(1))}: cargas a 70 % e menos séries. Não conta para a progressão.", color = GMColors.dim, style = GMType.caption)
                }
            }
            GMButton("Encerrar deload", { TrainScope.edit(env) { TrainEdits.number(it, Deload.UNTIL_KEY, 0.0) } }, kind = GMButtonKind.GHOST, full = false, small = true)
        }
        return
    }
    val streak = Deload.streak(data.sessions.filter { it.end != null }.map { it.start to it.isDeload }, now, zone)
    if (!data.deloadActive(now) && !data.snoozed(now) && streak >= Deload.AFTER) {
        GMCard {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("🔋", fontSize = 30.sp)
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text("$streak semanas seguidas pesado", color = Color.White, style = GMType.headline)
                    Text("Uma semana mais leve ajuda o corpo a recuperar e você volta mais forte. Cargas a 70 % e um terço a menos de séries, só nesta semana.",
                         color = GMColors.dim, style = GMType.caption)
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                GMButton("Fazer deload", {
                    // Começa agora e vai até o fim da semana
                    val end = Weeks.end(now, zone)
                    TrainScope.edit(env) { TrainEdits.number(it, Deload.UNTIL_KEY, end.epochSecond.toDouble()) }
                }, Modifier.weight(1f), icon = TrainIcons.of("battery.100.bolt"), small = true)
                GMButton("Agora não", { TrainScope.edit(env) { TrainEdits.number(it, Deload.SNOOZE_KEY, now.plusSeconds(7 * 86_400).epochSecond.toDouble()) } },
                         kind = GMButtonKind.GHOST, full = false, small = true)
            }
        }
    }
}

/** Treino encerrado sozinho que mudou a rotina: oferece atualizar aqui */
@Composable
private fun PendingRoutineCard(env: AppEnv, data: TrainData) {
    val id = data.pendingRoutineUpdate ?: return
    val s = data.sessions.firstOrNull { it.uuid == id && it.end != null } ?: return
    val r = data.routines.firstOrNull { it.uuid == s.routineUUID } ?: return
    val changes = s.routineChanges(r)
    if (changes.isEmpty()) return
    GMCard {
        Text("Atualizar a rotina ${r.name}?", color = Color.White, style = GMType.headline)
        Text("O treino de ${weekdayName(s.start)} foi encerrado ao sair da academia e ficou diferente da rotina:", color = GMColors.dim, style = GMType.caption)
        for (c in changes) Text("• $c", color = Color.White, style = GMType.subheadline)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            GMButton("Salvar na rotina", {
                TrainScope.edit(env) { TrainEdits.text(TrainEdits.saveRoutine(it, s.applyTo(r)), "pendingRoutineUpdate", "") }
            }, Modifier.weight(1f), icon = TrainIcons.of("checkmark"), small = true)
            GMButton("Manter como está", { TrainScope.edit(env) { TrainEdits.text(it, "pendingRoutineUpdate", "") } }, kind = GMButtonKind.GHOST, full = false, small = true)
        }
    }
}

/** Linha de um treino feito (TrainView.swift `SessionRow`): aquecimento fica fora das séries e do volume */
@Composable
internal fun SessionRow(s: Session, modifier: Modifier = Modifier) {
    val done = s.doneWorkSets
    val volume = s.volume
    Column(modifier, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(s.title, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
        Text(listOf(dayMonth(s.start), s.end?.let { ActivityText.duration(maxOf(((it.epochSecond - s.start.epochSecond) / 60).toInt(), 1)) }.orEmpty(),
                    "${done.size} séries", if (volume > 0) "${Progression.fmt(com.alonsoalmeida.gymbros.domain.roundHalfAwayFromZero(volume))} kg" else "")
                 .filter { it.isNotEmpty() }.joinToString(" · "), color = GMColors.dim, style = GMType.caption)
    }
}

/** Botão de voltar das telas empilhadas da aba */
@Composable
internal fun BackButton(nav: TrainNav) = GMIconButton(TrainIcons.back, "Voltar", { nav.pop() })

/** Treino feito: séries tocáveis para corrigir carga ou reps (TrainView.swift `SessionDetailView`) */
@Composable
private fun SessionDetailScreen(env: AppEnv, home: HomeData, data: TrainData, id: String, nav: TrainNav) {
    val session = data.sessions.firstOrNull { it.uuid == id }
    if (session == null) { nav.pop(); return }
    var editing by remember { mutableStateOf<String?>(null) }
    GMScreen(session.title, bottomInset = 120.dp, leading = { BackButton(nav) }) {
        Text(fmt(session.start, "EEEE, d 'de' MMMM 'de' yyyy HH:mm").replaceFirstChar { it.uppercase() }, color = GMColors.dim, style = GMType.subheadline)
        Text("Toque numa série para corrigir carga ou reps.", color = GMColors.dim, style = GMType.caption)
        for (exID in session.exerciseIDs) {
            GMSection(Exercises.name(exID)) {
                val sets = session.setsOf(exID)
                val warm = sets.count { it.warmup }
                for (s in sets) {
                    Row(Modifier.fillMaxWidth().gmPress { editing = s.key }, verticalAlignment = Alignment.CenterVertically) {
                        Text(if (s.warmup) "A" else "${s.index - warm + 1}", color = if (s.warmup) GMColors.streak else GMColors.dim, modifier = Modifier.width(24.dp))
                        Text(setText(s), color = Color.White, style = GMType.body, modifier = Modifier.weight(1f))
                        if (s.done && !s.warmup && s.reps < s.targetReps) {
                            Text("meta ${s.targetReps}", color = GMColors.warning, style = GMType.caption.copy(fontWeight = FontWeight.Bold))
                            Spacer(Modifier.width(8.dp))
                        }
                        Icon(TrainIcons.of(if (s.done) "checkmark.circle.fill" else "xmark.circle"), null, tint = if (s.done) GMColors.accent else GMColors.dim)
                    }
                }
            }
        }
    }
    val set = session.sets.firstOrNull { it.key == editing }
    if (set != null) {
        val ex = Exercises.byID(set.exerciseID)
        val others = session.setsOf(set.exerciseID).filter { it.warmup == set.warmup }
        var weight by remember(editing) { mutableStateOf<Double?>(set.weight) }
        var reps by remember(editing) { mutableStateOf<Double?>(set.reps.toDouble()) }
        var done by remember(editing) { mutableStateOf(set.done) }
        fun save(all: Boolean) {
            val w = maxOf(weight ?: 0.0, 0.0)
            var out = session.updating(set.key) { it.copy(weight = w, reps = (reps ?: it.reps.toDouble()).toInt(), done = done) }
            if (all) { val keys = others.map { it.key }.toSet(); out = out.copy(sets = out.sets.map { if (it.key in keys) it.copy(weight = weight ?: 0.0) else it }) }
            TrainScope.edit(env) { TrainEdits.saveSession(it, out) }
            editing = null
        }
        GMSheet({ editing = null }) {
            Text("${Exercises.name(set.exerciseID)} · ${if (set.warmup) "aquecimento" else "série ${others.indexOfFirst { it.key == set.key } + 1}"}",
                 color = Color.White, style = GMType.headline)
            GMDecimalField("Carga", weight, { weight = it }, ex?.increment ?: 2.5, ex?.weightUnit(session.isCrossfit) ?: "kg", 10.0, clearable = false)
            GMDivider()
            val time = ex?.type == com.alonsoalmeida.gymbros.domain.train.ExerciseType.TIME
            GMDecimalField("Reps", reps, { reps = it?.let { v -> maxOf(0.0, com.alonsoalmeida.gymbros.domain.roundHalfAwayFromZero(v)) } },
                           if (time) 5.0 else 1.0, if (time) "s" else "reps", 10.0, clearable = false)
            GMToggle("Feita", done, { done = it })
            if (others.size > 1) GMButton("Aplicar carga em todas as ${others.size} séries", { save(true) }, kind = GMButtonKind.SECONDARY)
            GMButton("Salvar", { save(false) })
        }
    }
}

/** Modelos prontos (TrainView.swift `TemplatesView`) */
@Composable
private fun TemplatesModal(visible: Boolean, env: AppEnv, data: TrainData, onDismiss: () -> Unit) {
    GMModal(visible, "Modelos prontos", onDismiss) {
        for (t in RoutineTemplate.all) {
            Column(Modifier.gmPress {
                TrainScope.edit(env) { c ->
                    var out = c
                    t.routines.forEachIndexed { i, r ->
                        out = TrainEdits.saveRoutine(out, Routine(TrainEdits.newID(), r.name, r.weekdays.sorted().joinToString(","), data.routines.size + i,
                            r.items.mapIndexed { j, (id, sets, reps) -> RoutineItem(id, sets, reps, RoutineTemplate.rest(id, sets), j) }))
                    }
                    out
                }
                onDismiss()
            }) {
                GMCard {
                    Text(t.name, color = Color.White, style = GMType.headline)
                    Text(t.detail, color = GMColors.dim, style = GMType.subheadline)
                    for (r in t.routines) Text("• ${r.name} (${weekdaysText(r.weekdays)})", color = GMColors.dim, style = GMType.caption)
                }
            }
        }
    }
}

/** Calculadora de anilhas (Profile/BodyTrackerView.swift `PlateCalculatorView`); a barra é a dos ajustes (`barWeight`) */
@Composable
internal fun PlateCalculator(env: AppEnv, data: TrainData, initial: Double) {
    var total by remember { mutableStateOf(initial) }
    var bar by remember { mutableStateOf(data.barWeight) }
    val (plates, rest) = com.alonsoalmeida.gymbros.domain.train.Plates.perSide(total, bar)
    val side = plates.sum()
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text("Calculadora de anilhas", color = Color.White, style = GMType.headline, modifier = Modifier.align(Alignment.CenterHorizontally))
        GMDecimalField("Carga total", total, { total = maxOf(it ?: 0.0, 0.0) }, 2.5, start = 60.0, clearable = false)
        com.alonsoalmeida.gymbros.ui.components.GMChoiceChips(com.alonsoalmeida.gymbros.domain.train.Plates.bars.map { it to if (it == 0.0) "Sem barra" else "${Progression.fmt(it)} kg" },
            bar, { bar = it; TrainScope.edit(env) { c -> TrainEdits.number(c, "barWeight", it) } }, title = "Barra")
        GMCard {
            Barbell(plates)
            if (total <= bar) {
                Text(when { bar == 0.0 -> "Escolha uma carga."; total < bar -> "A carga é menor que a barra (${Progression.fmt(bar)} kg)."
                            else -> "Só a barra: ${Progression.fmt(bar)} kg, sem anilhas." }, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    com.alonsoalmeida.gymbros.ui.components.GMValueRow("Barra", if (bar == 0.0) "—" else "${Progression.fmt(bar)} kg")
                    com.alonsoalmeida.gymbros.ui.components.GMValueRow("Em cada lado", "${Progression.fmt(side)} kg")
                    val counts = LinkedHashMap<Double, Int>().apply { for (p in plates) put(p, (get(p) ?: 0) + 1) }
                    Text(counts.entries.joinToString(" + ") { "${it.value} de ${Progression.fmt(it.key)} kg" }, color = GMColors.accent,
                         style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
                    GMDivider()
                    com.alonsoalmeida.gymbros.ui.components.GMValueRow("Total", "${Progression.fmt(bar)} + 2 × ${Progression.fmt(side)} = ${Progression.fmt(bar + side * 2)} kg")
                }
                if (rest > 0.01) Text("Sobram ${Progression.fmt(rest)} kg que não fecham com as anilhas comuns (25, 20, 15, 10, 5, 2,5 e 1,25 kg).",
                                      color = GMColors.dim, style = GMType.caption)
            }
        }
    }
}

@Composable
private fun Barbell(plates: List<Double>) {
    fun color(p: Double) = when (p) { 25.0 -> Color(0xFFFF453A); 20.0 -> Color(0xFF0A84FF); 15.0 -> Color(0xFFFFD60A); 10.0 -> Color(0xFF30D158); else -> Color.White.copy(alpha = 0.8f) }
    @Composable fun plate(p: Double) = Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Box(Modifier.width(14.dp).size(width = 14.dp, height = (30 + p * 3).dp).background(color(p), com.alonsoalmeida.gymbros.ui.theme.GMRadius.xs))
        Text(Progression.fmt(p), color = GMColors.dim, fontSize = 9.sp, fontWeight = FontWeight.Bold)
    }
    Row(Modifier.fillMaxWidth().padding(vertical = 8.dp).semantics { contentDescription = "Barra com ${plates.size} anilhas de cada lado" },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        Box(Modifier.size(width = 10.dp, height = 8.dp).background(Color.White.copy(alpha = 0.4f)))
        for (p in plates.reversed()) plate(p)
        Box(Modifier.weight(1f).size(height = 8.dp, width = 1.dp).background(Color.White.copy(alpha = 0.4f)))
        for (p in plates) plate(p)
        Box(Modifier.size(width = 10.dp, height = 8.dp).background(Color.White.copy(alpha = 0.4f)))
    }
}

@Composable
internal fun Chevron() = Icon(Icons.Filled.ChevronRight, null, tint = GMColors.dim, modifier = Modifier.size(18.dp))

@Composable
internal fun CircleIcon(symbol: String, on: Boolean, onClick: () -> Unit, label: String) {
    Box(Modifier.size(44.dp).gmPress(onClick = onClick).semantics { contentDescription = label }, contentAlignment = Alignment.Center) {
        Box(Modifier.size(34.dp).background(if (on) GMColors.accent else GMColors.raised, CircleShape), contentAlignment = Alignment.Center) {
            Icon(TrainIcons.of(symbol), null, tint = if (on) Color.Black else Color.White, modifier = Modifier.size(18.dp))
        }
    }
}
