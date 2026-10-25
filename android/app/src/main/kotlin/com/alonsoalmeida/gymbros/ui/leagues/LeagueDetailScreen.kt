package com.alonsoalmeida.gymbros.ui.leagues

import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.Assignment
import androidx.compose.material.icons.filled.Block
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PersonAddAlt1
import androidx.compose.material.icons.filled.PersonRemove
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.RestartAlt
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.TableChart
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.outlined.RemoveModerator
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
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.alonsoalmeida.gymbros.domain.ActivityText
import com.alonsoalmeida.gymbros.domain.Attribute
import com.alonsoalmeida.gymbros.domain.LeagueScoring
import com.alonsoalmeida.gymbros.domain.PhotoRule
import com.alonsoalmeida.gymbros.domain.Stage
import com.alonsoalmeida.gymbros.domain.SwissBonus
import com.alonsoalmeida.gymbros.domain.SwissResult
import com.alonsoalmeida.gymbros.domain.SwissTally
import com.alonsoalmeida.gymbros.domain.SwissCriterion
import com.alonsoalmeida.gymbros.domain.home.HomeData
import com.alonsoalmeida.gymbros.domain.leagues.ClubWinners
import com.alonsoalmeida.gymbros.domain.leagues.DailyPose
import com.alonsoalmeida.gymbros.domain.leagues.FeedItem
import com.alonsoalmeida.gymbros.domain.leagues.League
import com.alonsoalmeida.gymbros.domain.leagues.LeagueBoard
import com.alonsoalmeida.gymbros.domain.leagues.LeagueFormat
import com.alonsoalmeida.gymbros.domain.leagues.LeagueRenewal
import com.alonsoalmeida.gymbros.domain.leagues.LeagueSettings
import com.alonsoalmeida.gymbros.domain.leagues.LeagueText
import com.alonsoalmeida.gymbros.domain.leagues.LeagueTieBreak
import com.alonsoalmeida.gymbros.domain.leagues.PeriodWin
import com.alonsoalmeida.gymbros.domain.leagues.RankRow
import com.alonsoalmeida.gymbros.domain.leagues.RemoteLeague
import com.alonsoalmeida.gymbros.domain.leagues.RulesCalendar
import com.alonsoalmeida.gymbros.domain.leagues.SwissView
import com.alonsoalmeida.gymbros.domain.leagues.TeamRow
import com.alonsoalmeida.gymbros.domain.leagues.VerificationPreset
import com.alonsoalmeida.gymbros.domain.leagues.WinPeriod
import com.alonsoalmeida.gymbros.ui.AppEnv
import com.alonsoalmeida.gymbros.ui.auth.GMSegmented
import com.alonsoalmeida.gymbros.ui.components.AutoShrinkText
import com.alonsoalmeida.gymbros.ui.components.GMAction
import com.alonsoalmeida.gymbros.ui.components.GMActions
import com.alonsoalmeida.gymbros.ui.components.GMBadge
import com.alonsoalmeida.gymbros.ui.components.GMButton
import com.alonsoalmeida.gymbros.ui.components.GMButtonKind
import com.alonsoalmeida.gymbros.ui.components.GMCard
import com.alonsoalmeida.gymbros.ui.components.GMDivider
import com.alonsoalmeida.gymbros.ui.components.GMEmptyState
import com.alonsoalmeida.gymbros.ui.components.GMFloatingButton
import com.alonsoalmeida.gymbros.ui.components.GMIconButton
import com.alonsoalmeida.gymbros.ui.components.GMModal
import com.alonsoalmeida.gymbros.ui.components.GMProgressBar
import com.alonsoalmeida.gymbros.ui.components.GMPushScreen
import com.alonsoalmeida.gymbros.ui.components.GMRow
import com.alonsoalmeida.gymbros.ui.components.GMSection
import com.alonsoalmeida.gymbros.ui.components.LivingMonster
import com.alonsoalmeida.gymbros.ui.components.MonsterSprite
import com.alonsoalmeida.gymbros.ui.components.PhotoFill
import com.alonsoalmeida.gymbros.ui.components.Photos
import com.alonsoalmeida.gymbros.ui.components.gmPress
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMRadius
import com.alonsoalmeida.gymbros.ui.theme.GMType
import java.time.Instant

/** Janela do ranking (Leagues.swift `RankWindow`) */
private enum class RankWindow(val label: String) { LIGA("Liga toda"), SEMANA("Esta semana"), MES("Este mês") }

private fun RankWindow.since(now: Instant, cal: RulesCalendar): Instant? = when (this) {
    RankWindow.LIGA -> null
    RankWindow.SEMANA -> cal.weekInterval(now).first
    RankWindow.MES -> cal.monthInterval(now).first
}

/** Detalhe da liga (Leagues/LeaguesView.swift `LeagueDetailView`) */
@Composable
fun LeagueDetailScreen(league: League, env: AppEnv, home: HomeData, vm: LeaguesViewModel, onOpen: (String) -> Unit, onDismiss: () -> Unit) {
    val ui by vm.ui.collectAsStateWithLifecycle()
    val cache by vm.cache.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val uid = env.uid
    var tab by rememberSaveable { mutableStateOf(0) }
    var window by rememberSaveable { mutableStateOf(RankWindow.LIGA) }
    var checkingIn by remember { mutableStateOf(false) }
    var menu by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf(false) }
    var leaving by remember { mutableStateOf(false) }
    var opened by remember { mutableStateOf<FeedItem?>(null) }
    var teamChoice by remember { mutableStateOf<TeamRow?>(null) }
    var profile by remember { mutableStateOf<RankRow?>(null) }
    var reviewing by remember { mutableStateOf(false) }
    var restarting by remember { mutableStateOf(false) }
    var memberMenu by remember { mutableStateOf<RankRow?>(null) }
    var confirmBan by remember { mutableStateOf<RankRow?>(null) }
    var choosingSuccessor by remember { mutableStateOf(false) }
    var postingDaily by remember { mutableStateOf(false) }
    var creatingChallenge by remember { mutableStateOf(false) }
    // Treino do dia aberto (LeaguesView.swift `dailySession`)
    var dailySession by rememberSaveable { mutableStateOf<String?>(null) }
    val train = com.alonsoalmeida.gymbros.ui.train.rememberTrainData(env)

    LaunchedEffect(league.code) { vm.refresh(league) }

    val now = Instant.now()
    val remote = vm.remote(cache, league)
    val board = remember(league, ui, remote, home.roster) { LeaguesViewModel.board(league, ui, home, remote, uid, now) }
    val feed = board.feed
    val total = board.total
    val settings = league.settings
    val since = window.since(now, settings.calendar())
    val rank = remember(board, window) {
        if (window == RankWindow.LIGA) total
        else LeagueBoard.ranking(feed, league, home.trainerName, board.avatar, since, null, remote, board.swiss, uid)
    }
    val canModerate = league.canModerate(uid)
    val toReview = if (canModerate) feed.filter { it.pending && !it.isMe } else emptyList()
    val clubWins = remember(board, tab) { if (tab == 1) LeaguesViewModel.winners(league, board, home, remote, uid, now) else emptyList() }
    val tally = ClubWinners.tally(clubWins)

    fun share(text: String) {
        val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
        context.startActivity(Intent.createChooser(send, null))
    }

    GMPushScreen(league.name, onDismiss, bottomInset = 170.dp, trailing = {
        GMIconButton(Icons.Filled.PersonAddAlt1, "Convidar", { share("Entra na minha liga ${league.emoji} ${league.name} no GymBros! Código: ${league.code}") })
        GMIconButton(Icons.Filled.MoreHoriz, "Opções da liga", { menu = true })
    }, overlay = {
        // Liga que ainda não começou não aceita check-in (ficaria fora do período)
        if (!league.isOver(now) && league.hasStarted(now)) {
            GMFloatingButton("Novo check-in", { checkingIn = true }, Modifier.align(Alignment.BottomEnd).padding(end = 20.dp, bottom = 30.dp))
        }
    }) {
        Cover(league, now)
        if (league.isOver(now) && league.format == LeagueFormat.CHALLENGE && !settings.rankingsDisabled) ChallengeFinalCard(league, total, feed, ::share)
        if (!settings.rankingsDisabled) Stats(league, total, now) { tab = 1 }
        if (toReview.isNotEmpty()) {
            GMCard {
                GMRow(if (toReview.size == 1) "1 check-in para revisar" else "${toReview.size} check-ins para revisar", icon = Icons.Filled.Verified,
                      iconTint = GMColors.accent, subtitle = "Aprove ou negue antes de pontuar", chevron = true, onClick = { reviewing = true })
            }
        }
        settings.dailyWorkout?.takeIf { it.isToday(now) }?.let { w ->
            DailyWorkoutCard(w) {
                // LiveWorkout.startSession(routine: w.routine): cargas sugeridas, aquecimento automático e deload, como na aba Treino
                val routine = com.alonsoalmeida.gymbros.domain.train.Routine(com.alonsoalmeida.gymbros.domain.train.Session.newID(), w.title,
                    items = w.items.mapIndexed { i, x -> com.alonsoalmeida.gymbros.domain.train.RoutineItem(x.exerciseID, x.sets, x.reps, rest = 90, order = i) })
                val start = Instant.now()
                val session = com.alonsoalmeida.gymbros.domain.train.WorkoutStart.session(routine, train.history, train.deloadActive(start), train.autoWarmup, start)
                com.alonsoalmeida.gymbros.data.train.TrainScope.edit(env) { com.alonsoalmeida.gymbros.data.train.TrainEdits.saveSession(it, session) }
                dailySession = session.uuid
            }
        }
        settings.parentClub?.let { parent ->
            ui.leagues.firstOrNull { it.seriesKey.equals(parent, true) && !it.isPastSeason }?.let { club ->
                Text("Desafio do clube ${club.emoji} ${club.name}", color = GMColors.dim, style = GMType.caption.copy(fontWeight = FontWeight.SemiBold))
            }
        }
        if (canModerate) RequestsSection(remote.requests) { m, accept ->
            vm.launch { moderate(league) { s -> if (accept) s.copy(approved = s.approved + m) else s.copy(ignored = s.ignored + m) } }
        }
        GMSegmented(listOf(0 to "Check-ins", 1 to (if (settings.rankingsDisabled) "Metas" else "Ranking"), 2 to "Mural"), tab) { tab = it }
        when (tab) {
            0 -> Timeline(league, feed, ui, now) { opened = it }
            2 -> LeagueMural(league, env, home, vm, board.avatar, now)
            else -> {
                GMCard { RepCard(home, league) }
                if (!settings.rankingsDisabled) SwissRoundSection(league, board.swiss, total)
                GMSegmented(RankWindow.entries.map { it to it.label }, window) { window = it }
                val teams = LeagueBoard.teams(league, rank, feed, remote, since, now)
                GoalsCard(league, rank, teams)
                if (settings.rankingsDisabled) {
                    if (settings.individualGoal == 0 && settings.teamGoal == 0) {
                        GMEmptyState(Icons.Filled.Flag, "Sem ranking", "Esta liga não mostra quem está na frente. O dono pode definir uma meta nas regras.")
                    }
                } else {
                    TeamsSection(league, teams, now) { teamChoice = it }
                    GMSection(footer = rankFooter(league)) {
                        rank.forEachIndexed { i, r ->
                            Box(Modifier.gmPress {
                                if (r.isMe) return@gmPress
                                if (canModerate) memberMenu = r else profile = r
                            }) { RankRowView(league, i + 1, r, tally[r.id].orEmpty(), r.id in settings.mods) }
                            if (i < rank.lastIndex) GMDivider()
                        }
                    }
                    if (league.format == LeagueFormat.CLUB) {
                        ClubWinnersSection(league, clubWins)
                        ClubChallengesSection(league, ui, canModerate, now, onOpen) { creatingChallenge = true }
                    }
                    PastSeasons(league, ui, home, vm, cache, uid, now, onOpen)
                }
                RulesSection(league, now)
            }
        }
    }

    if (checkingIn) CheckInFormScreen(env, home, vm, setOf(league.uuid)) { checkingIn = false }
    if (editing) CreateLeagueScreen(env, home, vm, league, null) { editing = false }
    if (creatingChallenge) CreateLeagueScreen(env, home, vm, null, league) { creatingChallenge = false }
    opened?.let { CheckInDetailScreen(it, env, home, vm) { opened = null } }
    profile?.let { r -> MemberProfile(env, home, r) { profile = null } }
    if (reviewing) LeagueReviewQueue(league, toReview, env, home, vm) { reviewing = false }
    if (postingDaily) DailyWorkoutEditor(league, env, vm, now) { postingDaily = false }
    dailySession?.let { id -> com.alonsoalmeida.gymbros.ui.train.WorkoutScreen(env, home, train, id) { dailySession = null } }

    val isOwner = league.isMine
    val canRestart = league.format == LeagueFormat.CHALLENGE && league.isOver(now) && !league.isPastSeason && isOwner
    GMActions(menu, { menu = false }, "${league.emoji} ${league.name}", actions = buildList {
        if (isOwner) add(GMAction("Editar liga", Icons.Filled.Edit) { editing = true })
        if (canRestart) add(GMAction("Reiniciar desafio", Icons.Filled.RestartAlt) { restarting = true })
        if (canModerate && !league.isOver(now)) add(GMAction("Treino do dia", Icons.Filled.Assignment) { postingDaily = true })
        if (canModerate) add(GMAction("Exportar dados (CSV)", Icons.Filled.TableChart) { share(csv(feed)) })
        add(GMAction("Sair da liga", Icons.AutoMirrored.Filled.Logout, destructive = true) { leaving = true })
    })
    teamChoice?.let { t ->
        GMActions(true, { teamChoice = null }, "Entrar no ${t.name}?", "Seus check-ins passam a somar para este time. Dá para trocar depois.",
                  listOf(GMAction("Entrar no time", Icons.Filled.Groups) { vm.launch { saveLeague(league.uuid, mapOf("myTeamID" to t.id), false) } }))
    }
    memberMenu?.let { r ->
        val isMod = r.id in settings.mods
        GMActions(true, { memberMenu = null }, r.name, actions = buildList {
            add(GMAction("Ver perfil", Icons.Filled.Person) { profile = r })
            // Só o dono escolhe moderadores e bane
            if (isOwner) add(if (isMod) GMAction("Tirar de moderador", Icons.Outlined.RemoveModerator) { vm.launch { moderate(league) { s -> s.copy(mods = s.mods - r.id) } } }
                             else GMAction("Tornar moderador", Icons.Filled.Shield) { vm.launch { moderate(league) { s -> s.copy(mods = s.mods + r.id) } } })
            add(GMAction("Remover da liga", Icons.Filled.PersonRemove, destructive = true) {
                vm.launch { moderate(league) { s -> s.copy(removed = s.removed + r.id, mods = s.mods - r.id) } }
            })
            if (isOwner) add(GMAction("Banir da liga", Icons.Filled.Block, destructive = true) { confirmBan = r })
        })
    }
    confirmBan?.let { r ->
        GMActions(true, { confirmBan = null }, "Banir ${r.name}?", "Sai da liga com os check-ins e não volta nem pelo código. Dá para desbanir em Editar liga.",
                  listOf(GMAction("Banir da liga", Icons.Filled.Block, destructive = true) {
                      vm.launch { moderate(league) { s -> s.copy(banned = s.banned + r.id, mods = s.mods - r.id) } }
                  }))
    }
    GMActions(restarting, { restarting = false }, "Reiniciar o desafio?",
              "Começa hoje um desafio novo com as mesmas pessoas, regras e duração (${league.durationDays} dias). Os check-ins zeram; este fica guardado como temporada anterior, com o campeão.",
              listOf(GMAction("Reiniciar", Icons.Filled.RestartAlt) { vm.launch { newSeason(league, LeagueRenewal.restart(league, Instant.now())) }; onDismiss() }))
    GMActions(leaving, { leaving = false }, "Sair de ${league.name}?", "Os check-ins desta liga somem. Suas atividades e seus bros continuam.",
              listOf(GMAction("Sair", Icons.AutoMirrored.Filled.Logout, destructive = true) {
                  if (isOwner && !league.isMock && remote.members.isNotEmpty()) choosingSuccessor = true
                  else { vm.launch { leave(league, ui.leagues) }; onDismiss() }
              }))
    if (choosingSuccessor) SuccessorPicker(league, remote, { choosingSuccessor = false }) { id ->
        vm.launch { leave(league, ui.leagues, id) }
        onDismiss()
    }
}

private fun csv(feed: List<FeedItem>): String {
    fun q(s: String) = "\"" + s.replace("\"", "\"\"") + "\""
    val lines = mutableListOf("data;pessoa;titulo;atividade;minutos;pontos;foto;situacao")
    for (i in feed.sortedBy { it.date }) {
        lines += listOf(i.date.toString(), q(if (i.isMe) "Você" else i.name), q(i.title), q(LeagueFormats.kindName(i.kind)), "${i.minutes}", "${i.score}",
                        if (i.hasPhoto) "sim" else "não", if (i.pending) "em revisão" else "valendo").joinToString(";")
    }
    return lines.joinToString("\n")
}

// MARK: Capa

@Composable
private fun Cover(l: League, now: Instant) {
    val cover = remember(l.j.cover) { Photos.base64(l.j.cover) }
    Box(Modifier.fillMaxWidth().height(190.dp).clip(GMRadius.card)) {
        if (cover != null) PhotoFill(cover, Modifier.fillMaxSize(), 1200)
        else {
            Box(Modifier.fillMaxSize().background(Brush.linearGradient(listOf(GMColors.accent.copy(alpha = 0.55f), GMColors.card),
                start = androidx.compose.ui.geometry.Offset(Float.POSITIVE_INFINITY, 0f), end = androidx.compose.ui.geometry.Offset(0f, Float.POSITIVE_INFINITY))))
            Text(l.emoji, fontSize = 90.sp, modifier = Modifier.align(Alignment.TopEnd).padding(end = 18.dp, top = 10.dp).rotate(12f))
        }
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0.5f to Color.Transparent, 1f to Color.Black.copy(alpha = 0.75f))))
        Column(Modifier.align(Alignment.BottomStart).padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                if (l.isMock) GMBadge("Exemplo", Color.White)
                if (l.season > 1 || l.autoRenew) GMBadge("Temporada ${l.season}", Color.White)
                if (l.isOver(now)) GMBadge("Encerrada", Color.White)
            }
            Text("${l.emoji} ${l.name}", color = Color.White, fontSize = 26.sp, fontWeight = FontWeight.ExtraBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
            val period = l.end?.let { "${LeagueFormats.dayMonth(l.start)} – ${LeagueFormats.dayMonth(it)}" } ?: "Desde ${LeagueFormats.dayMonth(l.start)} · sem fim"
            Text("$period · código ${l.code}", color = Color.White.copy(alpha = 0.8f), style = GMType.caption.copy(fontWeight = FontWeight.SemiBold))
        }
    }
}

// MARK: Líder, você e dias

@Composable
private fun Stats(l: League, rank: List<RankRow>, now: Instant, onTap: () -> Unit) {
    val leader = rank.firstOrNull()
    val mePos = rank.indexOfFirst { it.isMe }.let { if (it < 0) 0 else it } + 1
    val me = rank.firstOrNull { it.isMe }
    Row(Modifier.fillMaxWidth().background(GMColors.card, GMRadius.card).gmPress(onClick = onTap).padding(vertical = 14.dp), verticalAlignment = Alignment.Top) {
        if (leader != null) StatPerson(Modifier.weight(1f), if (l.isOver(now)) "Campeão" else "Líder", leader, true,
                                       if (leader.score > 0) LeagueText.format(l.scoring, leader.score) else "ninguém pontuou")
        Box(Modifier.width(1.dp).height(96.dp).background(GMColors.stroke))
        if (me != null) StatPerson(Modifier.weight(1f), "Você · ${mePos}º", me, false,
                                   if (mePos == 1 || leader == null) LeagueText.format(l.scoring, me.score)
                                   else "${LeagueText.format(l.scoring, me.score)} · −${leader.score - me.score}")
        Box(Modifier.width(1.dp).height(96.dp).background(GMColors.stroke))
        Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            @Composable fun label(t: String) = Text(t, color = GMColors.dim, style = GMType.caption.copy(fontWeight = FontWeight.SemiBold))
            @Composable fun small(t: String) = Text(t, color = GMColors.dim, style = GMType.caption2)
            @Composable fun big(t: String, c: Color = Color.White) =
                Box(Modifier.height(50.dp), contentAlignment = Alignment.Center) { AutoShrinkText(t, 40f, 20f, color = c) }
            val d = l.daysLeft(now)
            when {
                !l.hasStarted(now) -> {
                    val n = l.daysToStart(now)
                    label(if (n == 1) "Começa" else "Começa em")
                    if (n == 1) { big("amanhã"); small(" ") } else { big("$n"); small("dias") }
                }
                l.isOver(now) -> { label("Fim"); big("🏁"); small("liga encerrada") }
                d != null && d == 1 -> { label("Termina"); big("hoje", GMColors.accent); small("último dia") }
                d != null -> { label("Faltam"); big("$d", if (d <= 3) GMColors.accent else Color.White); small("dias") }
                else -> { label("Duração"); big("∞"); small("sem data de fim") }
            }
        }
    }
}

@Composable
private fun StatPerson(modifier: Modifier, label: String, row: RankRow, crown: Boolean, line: String) {
    Column(modifier.padding(horizontal = 4.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(label, color = GMColors.dim, style = GMType.caption.copy(fontWeight = FontWeight.SemiBold), maxLines = 1)
        Box {
            MonsterSprite(row.avatar, Modifier.size(50.dp))
            if (crown) Text("👑", fontSize = 12.sp, modifier = Modifier.align(Alignment.TopEnd).offset(6.dp, (-6).dp))
        }
        Text(if (row.isMe) row.name.ifEmpty { "Você" } else row.name, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.Bold), maxLines = 1)
        Text(line, color = if (row.isMe) GMColors.accent else GMColors.dim, style = GMType.caption2.copy(fontFeatureSettings = "tnum"), maxLines = 1)
    }
}

// MARK: Linha do tempo

@Composable
private fun Timeline(l: League, feed: List<FeedItem>, ui: LeaguesUi, now: Instant, onOpen: (FeedItem) -> Unit) {
    if (feed.isEmpty()) {
        GMEmptyState(Icons.Filled.PhotoCamera, "Nenhum check-in ainda", if (l.isOver(now)) "A liga acabou sem check-ins." else "Toque no + e seja o primeiro!")
        return
    }
    val zone = java.time.ZoneId.systemDefault()
    val days = feed.take(120).groupBy { it.date.atZone(zone).toLocalDate() }
    for (day in days.keys.sortedDescending()) {
        val items = days[day].orEmpty().sortedByDescending { it.date }
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(Modifier.fillMaxWidth()) {
                Text(LeagueFormats.dayTitle(day), color = Color.White, style = GMType.headline)
                Spacer(Modifier.weight(1f))
                Text("${items.size} check-in${if (items.size == 1) "" else "s"}", color = GMColors.dim, style = GMType.caption)
            }
            Column(Modifier.fillMaxWidth().background(GMColors.card, GMRadius.card).padding(horizontal = 12.dp)) {
                items.forEachIndexed { i, item -> TimelineRow(l, item, ui, i == 0, i == items.lastIndex) { onOpen(item) } }
            }
        }
    }
}

@Composable
private fun TimelineRow(l: League, item: FeedItem, ui: LeaguesUi, first: Boolean, last: Boolean, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().gmPress(onClick = onClick).height(androidx.compose.foundation.layout.IntrinsicSize.Min),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Column(Modifier.width(10.dp).fillMaxHeight(), horizontalAlignment = Alignment.CenterHorizontally) {
            Box(Modifier.width(2.dp).weight(1f).background(if (first) Color.Transparent else GMColors.stroke))
            Box(Modifier.size(9.dp).background(if (item.isMe) GMColors.accent else GMColors.dim, CircleShape))
            Box(Modifier.width(2.dp).weight(1f).background(if (last) Color.Transparent else GMColors.stroke))
        }
        Box(Modifier.padding(vertical = 8.dp).size(58.dp).clip(GMRadius.m)) { Thumb(item, ui) }
        Column(Modifier.weight(1f).padding(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(item.title, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold), maxLines = 2)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                MonsterSprite(item.avatar, Modifier.size(20.dp))
                Text(if (item.isMe) "Você" else item.name, color = if (item.isMe) GMColors.accent else Color.White,
                     style = GMType.caption.copy(fontWeight = FontWeight.SemiBold), maxLines = 1)
                Text("· ${ActivityText.duration(item.minutes)}", color = GMColors.dim, style = GMType.caption, maxLines = 1)
            }
            item.place?.let { Text("📍 $it", color = GMColors.dim, style = GMType.caption2, maxLines = 1) }
        }
        Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(LeagueFormats.time(item.date), color = GMColors.dim, style = GMType.caption.copy(fontFeatureSettings = "tnum"))
            if (item.pending) Text("em revisão", color = GMColors.dim, style = GMType.caption.copy(fontWeight = FontWeight.SemiBold))
            else Text((if (item.score < 0) "−" else "+") + LeagueText.short(l.scoring, kotlin.math.abs(item.score)),
                      color = if (item.score < 0) GMColors.danger else GMColors.accent, style = GMType.subheadline.copy(fontWeight = FontWeight.Bold, fontFeatureSettings = "tnum"))
        }
    }
}

/** Miniatura do check-in: a sua foto, o aviso de que o outro tem foto, ou o ícone da atividade */
@Composable
fun Thumb(item: FeedItem, ui: LeaguesUi) {
    val photo = remember(item.id, ui) { if (item.isMe) Photos.base64(ui.checkIn(item.id)?.photo) else null }
    when {
        photo != null -> PhotoFill(photo, Modifier.fillMaxSize(), 300)
        item.hasPhoto -> Box(Modifier.fillMaxSize().background(Brush.linearGradient(listOf(GMColors.accent.copy(alpha = 0.35f), GMColors.raised))),
                             contentAlignment = Alignment.Center) {
            Icon(LeagueFormats.kindIcon(item.kind), null, tint = Color.White, modifier = Modifier.size(26.dp))
            Icon(Icons.Filled.CameraAlt, null, tint = Color.White.copy(alpha = 0.8f), modifier = Modifier.align(Alignment.BottomEnd).padding(5.dp).size(11.dp))
        }
        else -> Box(Modifier.fillMaxSize().background(if (item.isMe) GMColors.accent.copy(alpha = 0.22f) else GMColors.raised), contentAlignment = Alignment.Center) {
            Icon(LeagueFormats.kindIcon(item.kind), null, tint = if (item.isMe) GMColors.accent else Color.White, modifier = Modifier.size(26.dp))
        }
    }
}

// MARK: Ranking

@Composable
private fun RepCard(home: HomeData, l: League) {
    val m = home.roster.snapshot(l.monsterUUID)
    val bro = home.roster.monster(l.monsterUUID)
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        LivingMonster(m.form, Modifier.size(72.dp), progress = m.progress)
        Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text("Te representa nesta liga", color = GMColors.dim, style = GMType.caption)
            Text(bro?.displayName(m.form) ?: m.form.name, color = Color.White, style = GMType.headline)
            Text(if (m.stage == Stage.EGG) "Faltam ${m.xpToNext ?: 0} XP para chocar" else "Nível ${m.level}", color = Color.White, style = GMType.caption)
            GMProgressBar(m.progress, height = 6.dp)
        }
    }
}

@Composable
private fun TeamsSection(l: League, teams: List<TeamRow>, now: Instant, onPick: (TeamRow) -> Unit) {
    if (teams.isEmpty()) return
    val tail = "O bro do time cresce com a média de XP dos membros e evolui pelo atributo que o time mais treina."
    GMSection("Times", footer = if (l.myTeamID == null) "Toque num time para entrar. $tail" else tail) {
        teams.forEachIndexed { i, t ->
            Row(Modifier.fillMaxWidth().gmPress { if (!t.isMine && !l.isOver(now)) onPick(t) }, verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Medal(i + 1)
                LivingMonster(t.form, Modifier.size(44.dp), progress = t.progress)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(t.name, color = Color.White, style = GMType.subheadline.copy(fontWeight = if (t.isMine) FontWeight.Bold else FontWeight.SemiBold))
                        if (t.isMine) GMBadge("Seu time")
                    }
                    Text("${t.members} pessoa${if (t.members == 1) "" else "s"} · bro ${t.form.stage.label.lowercase()}", color = GMColors.dim, style = GMType.caption)
                }
                Text(LeagueText.short(l.scoring, t.score), color = if (t.isMine) GMColors.accent else Color.White,
                     style = GMType.headline.copy(fontFeatureSettings = "tnum"))
            }
            if (i < teams.lastIndex) GMDivider()
        }
    }
}

@Composable
private fun Medal(pos: Int) {
    Box(Modifier.width(32.dp), contentAlignment = Alignment.Center) {
        if (pos <= 3) Text(listOf("🥇", "🥈", "🥉")[pos - 1], fontSize = 20.sp)
        else Text("${pos}º", color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.Bold))
    }
}

@Composable
private fun RankRowView(l: League, pos: Int, r: RankRow, wins: Map<WinPeriod, Int>, mod: Boolean) {
    Row(Modifier.fillMaxWidth().padding(vertical = 2.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Medal(pos)
        MonsterSprite(r.avatar, Modifier.size(38.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(if (r.isMe) "${r.name} (você)" else r.name, color = Color.White,
                     style = GMType.subheadline.copy(fontWeight = if (r.isMe) FontWeight.Bold else FontWeight.SemiBold), maxLines = 1)
                if (mod) GMBadge("Mod")
            }
            val swiss = r.swiss?.let { " · suíço ${LeagueText.swissPoints(it)}" }.orEmpty()
            val tie = if (r.tied) " · " + when (l.tieBreak) {
                LeagueTieBreak.PRIMEIRO -> r.reachedAt?.let { "empate · chegou ${LeagueFormats.dayMonthTime(it)}" } ?: "empate"
                LeagueTieBreak.SEQUENCIA -> "empate · ${r.bestStreak} dia${if (r.bestStreak == 1) "" else "s"} seguido${if (r.bestStreak == 1) "" else "s"}"
                LeagueTieBreak.CHECKINS -> "empate"
            } else ""
            Text("${r.checkIns} check-in${if (r.checkIns == 1) "" else "s"}$swiss$tie", color = GMColors.dim, style = GMType.caption)
            if (wins.isNotEmpty()) {
                Text("🏆 " + WinPeriod.entries.mapNotNull { p -> wins[p]?.let { p.wins(it) } }.joinToString(" · "), color = GMColors.accent,
                     style = GMType.caption2.copy(fontWeight = FontWeight.SemiBold))
            }
        }
        Text(LeagueText.short(l.scoring, r.score), color = if (r.isMe) GMColors.accent else Color.White, style = GMType.headline.copy(fontFeatureSettings = "tnum"))
    }
}

private fun rankFooter(l: League): String {
    val parts = mutableListOf(LeagueText.detail(l.scoring))
    if (l.photoRule != PhotoRule.LIVRE) parts += LeagueText.photoDetail(l.photoRule)
    val w = l.attributeWeights
    if (l.scoring == LeagueScoring.PONTOS && w.isNotEmpty()) {
        parts += "Pesos: " + Attribute.entries.mapNotNull { a -> w[a]?.let { "${a.label} ${LeagueText.weight(it)}" } }.joinToString(", ") + "."
    }
    parts += l.tieBreak.detail
    return parts.joinToString(" ")
}

/** Regras da liga para quem participa (LeagueDetailView.rulesSection) */
@Composable
private fun RulesSection(l: League, now: Instant) {
    val s = l.settings
    val pose = DailyPose.of(now)
    val lines = (if (s.verification.preset != VerificationPreset.OFF) s.verification.bullets else emptyList()) +
        (if (s.reviewRequired) listOf("O dono aprova cada check-in antes de pontuar") else emptyList()) +
        (if (s.posesEnabled) listOf("Pose do dia na foto: hoje, ${pose.emoji} ${pose.name}") else emptyList()) +
        s.limits.summary +
        (if (l.scoring == LeagueScoring.ATIVIDADES) s.pointRules.map { "${it.targetName}: ${it.summary}" } else emptyList()) +
        (s.weekStart?.let { listOf("A semana começa no ${LeagueSettings.weekday(it).lowercase()}") } ?: emptyList())
    if (lines.isEmpty()) return
    GMSection("Regras") {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) { for (t in lines) Text("• $t", color = Color.White, style = GMType.subheadline) }
    }
}

// MARK: Rodada suíça (SwissRoundSection.swift)

@Composable
private fun SwissRoundSection(l: League, rounds: List<com.alonsoalmeida.gymbros.domain.SwissRound>, people: List<RankRow>) {
    val history = SwissView.history(rounds, "me")
    val match = SwissView.today(rounds)?.let { SwissView.match(it, "me") }
    val (win, draw) = SwissBonus.value(SwissResult.VITORIA, l.scoring) to SwissBonus.value(SwissResult.EMPATE, l.scoring)
    val footer = "Todo dia você enfrenta alguém com pontuação suíça parecida, sem repetir adversário enquanto der. " +
        "${LeagueText.swissDetail(l.swiss)} Vitória e folga valem 1, empate ½; se ninguém treinou, 0 para os dois. " +
        "No fim do dia, vitória ou folga soma ${LeagueText.format(l.scoring, win)} no placar" + if (draw > 0) " e empate, ${LeagueText.format(l.scoring, draw)}." else "."
    if (match != null) {
        GMSection("Rodada suíça de hoje", footer = footer) {
            if (match.b == null) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Box(Modifier.size(44.dp).background(GMColors.raised, CircleShape), contentAlignment = Alignment.Center) { Text("☕", fontSize = 20.sp) }
                    Column {
                        Text("Folga hoje: +1", color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.Bold))
                        Text("Número ímpar de pessoas: vale como vitória.", color = GMColors.dim, style = GMType.caption)
                    }
                }
            } else {
                val opp = SwissView.opponent(match, "me")!!
                val mine = SwissView.tally(match, "me")
                val theirs = SwissView.opponentTally(match, "me")
                val a = l.swiss.value(mine)
                val b = l.swiss.value(theirs)
                Row(Modifier.semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    SwissSide(Modifier.weight(1f), l, "me", mine, a > b, people)
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("×", color = GMColors.dim, style = GMType.title3.copy(fontWeight = FontWeight.Bold))
                        Text("em andamento", color = GMColors.dim, style = GMType.caption2)
                    }
                    SwissSide(Modifier.weight(1f), l, opp, theirs, b > a, people)
                }
            }
            if (history.isNotEmpty()) { GMDivider(); SwissHistory(history) }
        }
    } else if (history.isNotEmpty()) {
        GMSection("Rodada suíça", footer = footer) { SwissHistory(history) }
    }
}

@Composable
private fun SwissSide(modifier: Modifier, l: League, id: String, t: SwissTally, ahead: Boolean, people: List<RankRow>) {
    val row = people.firstOrNull { it.id == id }
    val partial = when (l.swiss) {
        SwissCriterion.PONTOS -> LeagueText.short(l.scoring, t.score)
        SwissCriterion.CHECKINS -> "${t.checkIns} check-in${if (t.checkIns == 1) "" else "s"}"
        SwissCriterion.PRESENCA -> if (t.trained) "treinou" else "ainda não"
    }
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        MonsterSprite(row?.avatar ?: com.alonsoalmeida.gymbros.domain.MonsterForm.EGG, Modifier.size(44.dp))
        Text(if (id == "me") "Você" else row?.name ?: "?", color = Color.White, style = GMType.caption.copy(fontWeight = FontWeight.Bold), maxLines = 1)
        Text(partial, color = if (ahead) GMColors.accent else Color.White, style = GMType.headline.copy(fontFeatureSettings = "tnum"), maxLines = 1)
    }
}

@Composable
private fun SwissHistory(history: List<Pair<java.time.LocalDate, SwissResult>>) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("Suas rodadas", color = GMColors.dim, style = GMType.caption.copy(fontWeight = FontWeight.SemiBold))
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            for ((day, r) in history.reversed()) {
                Column(Modifier.semantics(mergeDescendants = true) { contentDescription = "${SwissView.name(r)}, ${LeagueFormats.dayNumMonth(day)}" },
                       horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    GMBadge(SwissView.letter(r), when (r) {
                        SwissResult.VITORIA -> GMColors.accent; SwissResult.EMPATE -> Color.White
                        SwissResult.DERROTA -> GMColors.danger; SwissResult.FOLGA -> GMColors.info
                    })
                    Text(LeagueFormats.dayNumMonth(day), color = GMColors.dim, style = GMType.caption2)
                }
            }
        }
    }
}

// MARK: Metas (LeagueReviewViews.swift `LeagueGoalsCard`)

@Composable
private fun GoalsCard(l: League, people: List<RankRow>, teams: List<TeamRow>) {
    val s = l.settings
    if (s.individualGoal > 0) {
        GMSection("Meta de cada pessoa · ${LeagueText.format(l.scoring, s.individualGoal)}",
                  footer = "${people.count { it.score >= s.individualGoal }} de ${people.size} já bateram a meta.") {
            // Sem ranking, a ordem é por nome (ninguém vê quem está na frente)
            val list = if (s.rankingsDisabled) people.sortedWith(compareBy<RankRow>({ if (it.isMe) 0 else 1 }, { it.name })) else people
            list.forEachIndexed { i, r ->
                GoalBar(l, if (r.isMe) "Você" else r.name, r.avatar, r.score, s.individualGoal, r.isMe)
                if (i < list.lastIndex) GMDivider()
            }
        }
    }
    if (s.teamGoal > 0 && teams.isNotEmpty()) {
        GMSection("Meta de cada time · ${LeagueText.format(l.scoring, s.teamGoal)}") {
            teams.forEachIndexed { i, t ->
                GoalBar(l, t.name, t.form, t.score, s.teamGoal, t.isMine)
                if (i < teams.lastIndex) GMDivider()
            }
        }
    }
}

@Composable
private fun GoalBar(l: League, name: String, avatar: com.alonsoalmeida.gymbros.domain.MonsterForm, value: Int, goal: Int, mine: Boolean) {
    Row(Modifier.semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        MonsterSprite(avatar, Modifier.size(34.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Row {
                Text(name, color = Color.White, style = GMType.subheadline.copy(fontWeight = if (mine) FontWeight.Bold else FontWeight.SemiBold),
                     maxLines = 1, modifier = Modifier.weight(1f))
                Text(if (value >= goal) "✅ ${LeagueText.short(l.scoring, value)}" else "${LeagueText.short(l.scoring, value)} / ${LeagueText.short(l.scoring, goal)}",
                     color = if (mine) GMColors.accent else GMColors.dim, style = GMType.caption.copy(fontFeatureSettings = "tnum"))
            }
            GMProgressBar(minOf(maxOf(value, 0).toDouble() / goal, 1.0), height = 6.dp)
        }
    }
}

// MARK: Campeões, desafios do clube e temporadas

@Composable
private fun ClubWinnersSection(l: League, wins: List<PeriodWin>) {
    var period by rememberSaveable { mutableStateOf(WinPeriod.WEEK) }
    var all by remember(period) { mutableStateOf(false) }
    val list = wins.filter { it.period == period }
    val shown = if (all) list else list.take(6)
    val noun = when (period) { WinPeriod.WEEK -> "semana"; WinPeriod.MONTH -> "mês"; WinPeriod.YEAR -> "ano" }
    GMSection("Campeões", footer = if (list.isEmpty()) "Quando a primeira $noun do clube acabar, o campeão aparece aqui." else "Empate no primeiro lugar divide o título.") {
        GMSegmented(WinPeriod.entries.map { it to it.label }, period) { period = it }
        for (w in shown) {
            GMDivider()
            Row(Modifier.semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Box {
                    MonsterSprite(w.winners[0].avatar, Modifier.size(36.dp))
                    Text("👑", fontSize = 11.sp, modifier = Modifier.align(Alignment.TopEnd).offset(5.dp, (-5).dp))
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(LeagueFormats.winTitle(period, w.start), color = GMColors.dim, style = GMType.caption)
                    Text(ClubWinners.names(w.winners).replaceFirstChar { it.uppercase() }, color = Color.White,
                         style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold), maxLines = 2)
                }
                Text(LeagueText.short(l.scoring, w.score), color = GMColors.accent, style = GMType.subheadline.copy(fontWeight = FontWeight.Bold))
            }
        }
        if (list.size > 6) {
            GMDivider()
            GMRow(if (all) "Mostrar menos" else "Ver os ${list.size}", icon = if (all) Icons.Filled.ChevronRight else Icons.Filled.ChevronRight,
                  iconTint = GMColors.accent, onClick = { all = !all })
        }
    }
}

@Composable
private fun ClubChallengesSection(club: League, ui: LeaguesUi, canModerate: Boolean, now: Instant, onOpen: (String) -> Unit, onCreate: () -> Unit) {
    val list = ui.leagues.filter { it.settings.parentClub.equals(club.seriesKey, true) && !it.isPastSeason }.sortedByDescending { it.start }
    if (list.isEmpty() && !canModerate) return
    GMSection("Desafios do clube", footer = if (list.isEmpty()) "Crie uma competição com prazo para quem já está no clube, sem precisar convidar de novo." else null) {
        list.forEachIndexed { i, l ->
            if (i > 0) GMDivider()
            GMRow("${l.emoji} ${l.name}", subtitle = if (l.isOver(now)) "Encerrado" else if (l.hasStarted(now)) l.daysLeft(now)?.let { "faltam $it dias" } ?: ""
                                                    else League.startsText(l.start, now), chevron = true, onClick = { onOpen(l.uuid) })
        }
        if (canModerate) {
            if (list.isNotEmpty()) GMDivider()
            GMRow("Criar desafio no clube", icon = Icons.Filled.Flag, iconTint = GMColors.accent, chevron = true, onClick = onCreate)
        }
    }
}

@Composable
private fun PastSeasons(l: League, ui: LeaguesUi, home: HomeData, vm: LeaguesViewModel, cache: Map<String, RemoteLeague>, uid: String, now: Instant,
                        onOpen: (String) -> Unit) {
    val past = ui.leagues.filter { it.seriesKey == l.seriesKey && it.season < l.season }.sortedByDescending { it.season }
    if (past.isEmpty()) return
    GMSection("Temporadas anteriores") {
        past.forEachIndexed { i, p ->
            val rank = remember(p, ui) { LeaguesViewModel.board(p, ui, home, vm.remote(cache, p), uid, now).total }
            val pos = rank.indexOfFirst { it.isMe }.let { if (it < 0) 0 else it } + 1
            Row(Modifier.fillMaxWidth().gmPress { onOpen(p.uuid) }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Box(Modifier.size(40.dp).background(GMColors.raised, CircleShape), contentAlignment = Alignment.Center) {
                    Text("T${p.season}", color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.Bold))
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(rank.firstOrNull()?.let { "🏆 ${if (it.isMe) "Você" else it.name} · ${LeagueText.format(p.scoring, it.score)}" } ?: "Sem check-ins",
                         color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
                    Text("${LeagueFormats.dayMonth(p.start)} – ${LeagueFormats.dayMonth(p.end ?: p.start)} · você ficou em ${pos}º", color = GMColors.dim, style = GMType.caption)
                }
                Icon(Icons.Filled.ChevronRight, null, tint = GMColors.dim, modifier = Modifier.size(16.dp))
            }
            if (i < past.lastIndex) GMDivider()
        }
    }
}

/** Fim do desafio: classificação final e resumo (LeagueWinners.swift `ChallengeFinalCard`) */
@Composable
private fun ChallengeFinalCard(l: League, rank: List<RankRow>, feed: List<FeedItem>, share: (String) -> Unit) {
    val top = rank.firstOrNull()
    val winners = if (top != null && top.score > 0) rank.filter { it.score == top.score } else emptyList()
    val counted = feed.filter { !it.pending && it.date >= l.start && it.date <= (l.end ?: Instant.now()) }
    val total = if (l.scoring == LeagueScoring.TREINOS) counted.size else counted.sumOf { it.score }
    val people = rank.size
    val summary = "${LeagueText.format(l.scoring, total)} em ${l.durationDays} dia${if (l.durationDays == 1) "" else "s"}, somados por $people bro${if (people == 1) "" else "s"}. Mandaram bem."
    val congrats = when {
        winners.isEmpty() -> "Ninguém pontuou neste desafio."
        winners.size > 1 -> "Parabéns a ${ClubWinners.names(winners)} por dividirem o primeiro lugar."
        else -> "Parabéns a ${ClubWinners.names(winners)} pelo primeiro lugar."
    }
    GMCard {
        Text("CLASSIFICAÇÃO FINAL", color = GMColors.dim, style = GMType.caption.copy(fontWeight = FontWeight.Bold, letterSpacing = 0.6.sp))
        Text(congrats, color = Color.White, style = GMType.headline)
        Text(summary, color = GMColors.dim, style = GMType.subheadline)
        val podium = rank.take(3).mapIndexed { i, r -> "${listOf("🥇", "🥈", "🥉")[i]} ${if (r.isMe) "Você" else r.name} · ${LeagueText.short(l.scoring, r.score)}" }
        Text("Compartilhar resultado", color = GMColors.accent, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold),
             modifier = Modifier.gmPress { share("${l.emoji} ${l.name}\nClassificação final\n${podium.joinToString("\n")}\n$congrats\n$summary\nGymBros") })
    }
}

/** Treino do dia (LeagueModerationViews.swift `DailyWorkoutCard`): "Começar" abre o treino guiado com os exercícios do dia */
@Composable
private fun DailyWorkoutCard(w: com.alonsoalmeida.gymbros.domain.leagues.DailyWorkout, start: () -> Unit) {
    GMCard {
        Text("TREINO DO DIA", color = GMColors.accent, style = GMType.caption2.copy(fontWeight = FontWeight.Black))
        Text(w.title, color = Color.White, style = GMType.headline)
        if (w.items.isNotEmpty()) Text(w.items.joinToString(" · ") { "${com.alonsoalmeida.gymbros.domain.train.Exercises.name(it.exerciseID)} ${it.sets}×${it.reps}" },
                                        color = GMColors.dim, style = GMType.caption, maxLines = 3)
        if (w.note.isNotEmpty()) Text(w.note, color = GMColors.dim, style = GMType.caption, maxLines = 6)
        if (w.items.isNotEmpty()) GMButton("Começar", start, icon = Icons.Filled.PlayArrow, full = false, small = true)
    }
}

/** Pedidos para entrar: o dono (ou um moderador) aceita ou ignora */
@Composable
private fun RequestsSection(requests: List<com.alonsoalmeida.gymbros.domain.leagues.RemoteMember>, decide: (String, Boolean) -> Unit) {
    if (requests.isEmpty()) return
    GMSection("Pedidos para entrar", footer = "Aceito, a pessoa entra na liga. Ignorado, o pedido some (ela pode pedir de novo).") {
        requests.forEachIndexed { i, m ->
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                MonsterSprite(m.form, Modifier.size(38.dp))
                Text(m.name.ifEmpty { "Treinador" }, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold),
                     maxLines = 1, modifier = Modifier.weight(1f))
                GMButton("Ignorar", { decide(m.id, false) }, kind = GMButtonKind.SECONDARY, full = false, small = true)
                GMButton("Aceitar", { decide(m.id, true) }, full = false, small = true)
            }
            if (i < requests.lastIndex) GMDivider()
        }
    }
}

/** O dono sai e escolhe quem fica no lugar (ou sorteia) */
@Composable
private fun SuccessorPicker(l: League, remote: RemoteLeague, onDismiss: () -> Unit, leave: (String) -> Unit) {
    var choice by remember { mutableStateOf<String?>(null) }
    val members = remote.members
    GMModal(true, "Quem fica de dono?", onDismiss, confirm = "Sair", onConfirm = {
        // Sem escolha: sorteia, dando preferência a quem já modera
        val pool = members.filter { it.id in l.settings.mods }
        val id = choice ?: (pool.ifEmpty { members }).randomOrNull()?.id
        onDismiss()
        if (id != null) leave(id)
    }) {
        Text("A liga continua sem você. Escolha quem passa a cuidar das regras, dos pedidos e da revisão. Sem escolha, alguém é sorteado.",
             color = GMColors.dim, style = GMType.subheadline)
        GMSection {
            members.forEachIndexed { i, m ->
                GMRow(m.name.ifEmpty { "Treinador" }, subtitle = if (m.id in l.settings.mods) "Moderador" else null, onClick = { choice = m.id }) {
                    SelectDot(choice == m.id)
                }
                if (i < members.lastIndex) GMDivider()
            }
        }
    }
}

/** checkmark.circle.fill / circle */
@Composable
fun SelectDot(on: Boolean) {
    Icon(if (on) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked, null, tint = if (on) GMColors.accent else GMColors.dim,
         modifier = Modifier.size(24.dp))
}
