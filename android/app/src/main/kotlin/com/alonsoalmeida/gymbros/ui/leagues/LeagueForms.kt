package com.alonsoalmeida.gymbros.ui.leagues

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AddCircleOutline
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Checklist
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.RemoveCircleOutline
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.SelectableDates
import androidx.compose.material3.Text
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.alonsoalmeida.gymbros.data.leagues.LeagueDraft
import com.alonsoalmeida.gymbros.domain.ActivityKind
import com.alonsoalmeida.gymbros.domain.ActivityPointRule
import com.alonsoalmeida.gymbros.domain.Attribute
import com.alonsoalmeida.gymbros.domain.LeagueActivityRule
import com.alonsoalmeida.gymbros.domain.LeagueScore
import com.alonsoalmeida.gymbros.domain.LeagueScoring
import com.alonsoalmeida.gymbros.domain.MonsterForm
import com.alonsoalmeida.gymbros.domain.PhotoRule
import com.alonsoalmeida.gymbros.domain.ScoreInput
import com.alonsoalmeida.gymbros.domain.Stage
import com.alonsoalmeida.gymbros.domain.SwissCriterion
import com.alonsoalmeida.gymbros.domain.WorkoutType
import com.alonsoalmeida.gymbros.domain.home.HomeData
import com.alonsoalmeida.gymbros.domain.leagues.CheckInTimePolicy
import com.alonsoalmeida.gymbros.domain.leagues.CheckInVerification
import com.alonsoalmeida.gymbros.domain.leagues.DailyPose
import com.alonsoalmeida.gymbros.domain.leagues.League
import com.alonsoalmeida.gymbros.domain.leagues.LeagueEdits
import com.alonsoalmeida.gymbros.domain.leagues.LeagueFormat
import com.alonsoalmeida.gymbros.domain.leagues.LeagueSettings
import com.alonsoalmeida.gymbros.domain.leagues.LeagueTeam
import com.alonsoalmeida.gymbros.domain.leagues.LeagueTeams
import com.alonsoalmeida.gymbros.domain.leagues.LeagueText
import com.alonsoalmeida.gymbros.domain.leagues.LeagueTieBreak
import com.alonsoalmeida.gymbros.domain.leagues.LibraryMediaPolicy
import com.alonsoalmeida.gymbros.domain.leagues.LimitPeriod
import com.alonsoalmeida.gymbros.domain.leagues.MediaPolicy
import com.alonsoalmeida.gymbros.domain.leagues.PointRuleRow
import com.alonsoalmeida.gymbros.domain.leagues.ScoringLimits
import com.alonsoalmeida.gymbros.domain.leagues.VerificationPreset
import com.alonsoalmeida.gymbros.ui.AppEnv
import com.alonsoalmeida.gymbros.ui.auth.GMSegmented
import com.alonsoalmeida.gymbros.ui.auth.GMTextField
import com.alonsoalmeida.gymbros.ui.components.GMButton
import com.alonsoalmeida.gymbros.ui.components.GMButtonKind
import com.alonsoalmeida.gymbros.ui.components.GMCard
import com.alonsoalmeida.gymbros.ui.components.GMChip
import com.alonsoalmeida.gymbros.ui.components.GMChoiceChips
import com.alonsoalmeida.gymbros.ui.components.GMDivider
import com.alonsoalmeida.gymbros.ui.components.GMFlow
import com.alonsoalmeida.gymbros.ui.components.GMIconButton
import com.alonsoalmeida.gymbros.ui.components.GMModal
import com.alonsoalmeida.gymbros.ui.components.GMRow
import com.alonsoalmeida.gymbros.ui.components.GMSection
import com.alonsoalmeida.gymbros.ui.components.GMSheet
import com.alonsoalmeida.gymbros.ui.components.GMStepper
import com.alonsoalmeida.gymbros.ui.components.GMToggle
import com.alonsoalmeida.gymbros.ui.components.MonsterSprite
import com.alonsoalmeida.gymbros.ui.components.PhotoFill
import com.alonsoalmeida.gymbros.ui.components.Photos
import com.alonsoalmeida.gymbros.ui.components.Symbols
import com.alonsoalmeida.gymbros.ui.components.gmPress
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMRadius
import com.alonsoalmeida.gymbros.ui.theme.GMType
import com.alonsoalmeida.gymbros.ui.theme.color
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.temporal.ChronoUnit
import java.util.Base64

private val EMOJIS = listOf("🏆", "🔥", "💪", "🏃", "⚡️", "🦁", "🐉", "⭐️", "🏐", "🧘")

/** Cria uma liga nova, edita uma existente ou cria um desafio dentro de um clube (LeaguesView.swift `CreateLeagueView`) */
@Composable
fun CreateLeagueScreen(env: AppEnv, home: HomeData, vm: LeaguesViewModel, league: League?, parentClub: League?, onDismiss: () -> Unit) {
    val cache by vm.cache.collectAsStateWithLifecycle()
    val zone = ZoneId.systemDefault()
    val today = LocalDate.now(zone)
    val src = league ?: parentClub
    var name by remember { mutableStateOf(league?.name.orEmpty()) }
    var emoji by remember { mutableStateOf(src?.emoji ?: "🏆") }
    var scoring by remember { mutableStateOf(src?.scoring ?: LeagueScoring.PONTOS) }
    var format by remember { mutableStateOf(if (parentClub != null) LeagueFormat.CHALLENGE else league?.format ?: LeagueFormat.CHALLENGE) }
    var ruleMode by remember { mutableStateOf(league?.activityRule?.mode ?: "all") }
    var types by remember { mutableStateOf(league?.activityRule?.workoutTypeIDs ?: emptySet()) }
    var choosingTypes by remember { mutableStateOf(false) }
    // Peso de cada atributo em meios (2 = 1×), para o stepper andar de 0,5 em 0,5
    var halves by remember { mutableStateOf(Attribute.entries.associateWith { a -> league?.attributeWeights?.get(a)?.let { Math.round(it * 2).toInt() } ?: 2 }) }
    var tieBreak by remember { mutableStateOf(league?.tieBreak ?: LeagueTieBreak.PRIMEIRO) }
    var photoRule by remember { mutableStateOf(league?.photoRule ?: PhotoRule.LIVRE) }
    var swiss by remember { mutableStateOf(league?.swiss ?: SwissCriterion.PONTOS) }
    var teams by remember { mutableStateOf(src?.teams ?: emptyList()) }
    var start by remember { mutableStateOf(league?.let { League.CAL.day(it.start) } ?: today) }
    var end by remember { mutableStateOf(league?.end?.let { League.CAL.day(it) } ?: today.plusDays(29)) }
    var autoRenew by remember { mutableStateOf(league?.autoRenew ?: false) }
    var cover by remember { mutableStateOf(league?.j?.cover?.let(Photos::base64)) }
    var settings by remember {
        mutableStateOf(league?.settings ?: parentClub?.let { it.settings.copy(parentClub = it.seriesKey, dailyWorkout = null) } ?: LeagueSettings.NEW_LEAGUE)
    }
    var rep by remember { mutableStateOf(home.roster.main?.uuid) }
    val scope = rememberCoroutineScope()
    val coverPicker = rememberPhotoPickers(onPicked = { cover = it.bytes })
    val rule = LeagueActivityRule(ruleMode, types)
    val canSave = name.isNotBlank() && (ruleMode != "only" || types.isNotEmpty())

    fun save() {
        val now = Instant.now()
        val (s, e) = League.period(start.atStartOfDay(zone).toInstant(), if (format == LeagueFormat.CHALLENGE) end.atStartOfDay(zone).toInstant() else null)
        val fields = mapOf(
            "name" to name.trim(), "emoji" to emoji, "scoring" to scoring.raw, "activityRule" to LeagueText.ruleRaw(rule),
            "weights" to LeagueText.weightsRaw(halves.mapValues { it.value / 2.0 }), "tieBreak" to tieBreak.raw, "photoRule" to photoRule.raw,
            "swiss" to swiss.raw, "settings" to settings.rawValue, "teams" to LeagueTeams.encode(teams),
            "myTeamID" to league?.myTeamID?.takeIf { id -> teams.any { it.id == id } },
            "cover" to cover?.let { Base64.getEncoder().encodeToString(it) }, "start" to s, "end" to e,
            "autoRenew" to (format == LeagueFormat.CHALLENGE && autoRenew),
        )
        scope.launch {
            if (league != null) vm.store.saveLeague(league.uuid, fields, isNew = false)
            else {
                val monster = vm.store.representative(rep)
                vm.store.saveLeague(LeagueEdits.newID(), fields + mapOf("code" to League.newCode(), "isMock" to false, "joinedAt" to now,
                                                                        "monsterUUID" to monster, "season" to 1, "joined" to false), isNew = true)
            }
        }
        onDismiss()
    }

    GMModal(true, parentClub?.let { "Desafio no ${it.name}" } ?: if (league == null) "Novo grupo" else "Editar grupo", onDismiss,
            confirm = if (league == null) "Criar" else "Salvar", confirmEnabled = canSave, onConfirm = ::save) {
        GMSection("Nome") {
            GMTextField(name, { name = it }, "Nome da liga")
            GMFlow {
                for (e in EMOJIS) Box(Modifier.size(48.dp).gmPress { emoji = e }
                                          .background(if (emoji == e) GMColors.accent.copy(alpha = 0.3f) else GMColors.raised, GMRadius.m),
                                      contentAlignment = Alignment.Center) { Text(e, fontSize = 26.sp) }
            }
        }
        GMSection("Capa") {
            Box(Modifier.fillMaxWidth().height(120.dp).clip(GMRadius.m).gmPress(onClick = coverPicker.gallery).background(GMColors.raised), contentAlignment = Alignment.Center) {
                val c = cover
                if (c != null) PhotoFill(c, Modifier.fillMaxSize(), 1200)
                else Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Icon(Icons.Filled.Image, null, tint = Color.White, modifier = Modifier.size(18.dp))
                    Text("Escolher foto de capa", color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
                }
            }
            if (cover != null) GMButton("Tirar capa", { cover = null }, kind = GMButtonKind.SECONDARY, small = true)
        }
        if (parentClub == null) GMSection("Tipo", footer = format.detail) {
            GMSegmented(LeagueFormat.entries.map { it to it.label }, format) { format = it; if (it == LeagueFormat.CLUB) autoRenew = false }
        }
        GMSection("Quem vê os posts", footer = if (settings.isPrivate) "Os posts ficam só aqui dentro: não aparecem no Feed nem nos stories de ninguém, nem dos seus amigos."
                                              else "Os posts também aparecem no Feed dos amigos de quem postou, mesmo de quem não está na liga.") {
            GMSegmented(listOf(false to "Pública", true to "Privada"), settings.isPrivate) { settings = settings.copy(isPrivate = it) }
        }
        if (format == LeagueFormat.CHALLENGE) {
            GMSection("Período", footer = "Ganha quem estiver na frente no último dia. Check-ins fora do período não contam.") {
                // Não deixa começar no passado; ao editar, mantém o início que a liga já tinha
                PeriodField(start, end, minOf(today, league?.let { League.CAL.day(it.start) } ?: today)) { s, e -> start = s; end = e }
            }
            GMSection(footer = "Quando acabar, começa outra temporada com o mesmo nome, pessoas e duração, e os check-ins zeram. As temporadas passadas ficam guardadas na liga, com o campeão de cada uma.") {
                GMToggle("Renovar automaticamente", autoRenew, { autoRenew = it }, "Nova temporada ao fim de cada período")
            }
        }
        GMSection("Pontuação", footer = LeagueText.detail(scoring)) {
            GMChoiceChips(LeagueText.scoringOrder.map { it to LeagueText.name(it) }, scoring) { scoring = it }
        }
        if (scoring == LeagueScoring.ATIVIDADES) PointsSection(settings.pointRules) { settings = settings.copy(pointRules = it) }
        GMSection("Treinos que valem", footer = LeagueText.ruleDetail(rule)) {
            GMSegmented(listOf("all", "only", "except").map { it to LeagueText.ruleModeName(it) }, ruleMode) { ruleMode = it }
            if (ruleMode != "all") {
                GMDivider()
                val names = WorkoutType.all.filter { it.id in types }.map { it.name }
                GMRow(if (types.isEmpty()) "Escolher treinos" else "${types.size} treino${if (types.size == 1) "" else "s"} selecionado${if (types.size == 1) "" else "s"}",
                      icon = Icons.Filled.Checklist, iconTint = GMColors.accent, chevron = true,
                      subtitle = if (names.isEmpty()) (if (ruleMode == "only") "Apenas estes entram no ranking" else "Estes ficam fora do ranking")
                                 else names.take(2).joinToString(", ") + if (names.size > 2) " +${names.size - 2}" else "",
                      onClick = { choosingTypes = true })
            }
        }
        if (scoring == LeagueScoring.PONTOS) {
            val w = halves.mapValues { it.value / 2.0 }
            val ex = listOf(ActivityKind.CORRIDA, ActivityKind.MUSCULACAO, ActivityKind.YOGA).joinToString(" · ") { k ->
                "${LeagueFormats.kindName(k)} ${LeagueScore.byScoring(LeagueScoring.PONTOS, ScoreInput(k, 60, 6), w)}"
            }
            GMSection("Peso por atributo", footer = "Multiplica a parte de cada atributo nos pontos; 0× tira o atributo da conta. 1 h em esforço 6 vale: $ex pts.") {
                Attribute.entries.forEachIndexed { i, a ->
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Icon(Symbols.of(a), null, tint = a.color(), modifier = Modifier.width(22.dp))
                        Text(a.label, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold), modifier = Modifier.weight(1f))
                        GMStepper(halves[a] ?: 2, { v -> halves = halves + (a to v) }, 0..6, format = { LeagueText.weight(it / 2.0) })
                    }
                    if (i < Attribute.entries.lastIndex) GMDivider()
                }
            }
        }
        GMSection("Desempate", footer = tieBreak.detail) { GMSegmented(LeagueTieBreak.entries.map { it to it.label }, tieBreak) { tieBreak = it } }
        GMSection("Foto do treino", footer = if (photoRule == PhotoRule.METADE && scoring == LeagueScoring.TREINOS)
            LeagueText.photoDetail(photoRule) + " No modo Treinos cada check-in vale 1 e a metade arredonda para cima: para cobrar a foto, use Obrigatória."
            else LeagueText.photoDetail(photoRule)) {
            GMSegmented(PhotoRule.entries.map { it to LeagueText.photoName(it) }, photoRule) { photoRule = it }
        }
        VerificationSection(settings) { settings = it }
        ProofSection(settings) { settings = it }
        LimitsSection(settings.limits, scoring, teams.isNotEmpty()) { settings = settings.copy(limits = it) }
        GoalsSection(settings, scoring, teams.isNotEmpty()) { settings = settings.copy(individualGoal = it.individualGoal, teamGoal = it.teamGoal,
                                                                                         rankingsDisabled = it.rankingsDisabled, weekStart = it.weekStart) }
        GMSection("Entrada", footer = "Com aprovação, quem entra pelo código ou pelo link manda um pedido e você aprova ou ignora.") {
            GMToggle("Novos membros precisam de aprovação", settings.requiresApproval, { settings = settings.copy(requiresApproval = it) })
        }
        if (league != null && settings.banned.isNotEmpty()) {
            val names = cache[league.code]?.members.orEmpty().associate { it.id to it.name }
            GMSection("Banidos", footer = "Quem foi banido não volta nem pelo código.") {
                settings.banned.forEachIndexed { i, id ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(names[id] ?: id, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold), modifier = Modifier.weight(1f))
                        GMButton("Desbanir", { settings = settings.copy(banned = settings.banned - id, removed = settings.removed - id) },
                                 kind = GMButtonKind.SECONDARY, full = false, small = true)
                    }
                    if (i < settings.banned.lastIndex) GMDivider()
                }
            }
        }
        GMSection("Rodada suíça", footer = "Todo dia cada pessoa enfrenta alguém com pontuação suíça parecida. " + LeagueText.swissDetail(swiss)) {
            GMChoiceChips(SwissCriterion.entries.map { it to LeagueText.swissName(it) }, swiss) { swiss = it }
        }
        GMSection("Times", footer = if (teams.isEmpty()) "Divida a liga em times: o placar do time é a soma dos membros, e cada time tem um bro que evolui junto."
                                    else "O placar do time é a soma dos membros. Cada pessoa escolhe o time no Ranking da liga e pode trocar depois. Renomear um time não tira ninguém dele.") {
            GMToggle("Competir em times", teams.isNotEmpty(), { on ->
                teams = if (on) listOf(LeagueTeam(LeagueTeams.newID(), "Time Verde"), LeagueTeam(LeagueTeams.newID(), "Time Roxo")) else emptyList()
            })
            for (t in teams) {
                GMDivider()
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Box(Modifier.weight(1f)) { GMTextField(t.name, { v -> teams = teams.map { if (it.id == t.id) it.copy(name = v) else it } }, "Nome do time") }
                    if (teams.size > 2) GMIconButton(Icons.Filled.Remove, "Remover time", { teams = teams.filter { it.id != t.id } })
                }
            }
            if (teams.isNotEmpty() && teams.size < 4) {
                GMDivider()
                GMRow("Adicionar time", icon = Icons.Filled.AddCircleOutline, iconTint = GMColors.accent,
                      onClick = { teams = teams + LeagueTeam(LeagueTeams.newID(), "Time ${teams.size + 1}") })
            }
        }
        if (league == null) MonsterChoiceSection(home, rep) { rep = it }
    }
    if (choosingTypes) WorkoutTypeSheet(types, except = ruleMode == "except", onDismiss = { choosingTypes = false }) { types = it; choosingTypes = false }
}

/** Escolha de quem representa você na liga: um bro seu ou um ovo novo (Monsters.swift `MonsterChoiceSection`) */
@Composable
fun MonsterChoiceSection(home: HomeData, choice: String?, onChoice: (String?) -> Unit) {
    GMSection("Quem te representa nesta liga", footer = "Os check-ins desta liga dão XP só para ele.") {
        for (m in home.roster.monsters) {
            val s = home.roster.snapshot(m.uuid)
            ChoiceRow(choice == m.uuid, s.form, m.displayName(s.form), if (s.stage == Stage.EGG) "Ovo" else "${s.stage.label} · Nível ${s.level}") { onChoice(m.uuid) }
            GMDivider()
        }
        ChoiceRow(choice == null, MonsterForm.EGG, "Adotar um ovo novo", "Começa do zero, só com os check-ins desta liga") { onChoice(null) }
    }
}

@Composable
private fun ChoiceRow(selected: Boolean, form: MonsterForm, title: String, subtitle: String, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().gmPress(onClick = onClick), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        MonsterSprite(form, Modifier.size(40.dp))
        Column(Modifier.weight(1f)) {
            Text(title, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
            Text(subtitle, color = GMColors.dim, style = GMType.caption)
        }
        SelectDot(selected)
    }
}

/** Linha "Período": toca e escolhe início e fim, com atalhos (PeriodPicker.swift `LeaguePeriodField`) */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PeriodField(start: LocalDate, end: LocalDate, minDate: LocalDate, onChange: (LocalDate, LocalDate) -> Unit) {
    var open by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf<String?>(null) }
    val now = Instant.now()
    fun range(s: LocalDate, e: LocalDate) = "${LeagueFormats.dayMonth(s.atStartOfDay(ZoneOffset.UTC).toInstant(), ZoneOffset.UTC)} → ${LeagueFormats.dayMonth(e.atStartOfDay(ZoneOffset.UTC).toInstant(), ZoneOffset.UTC)}"
    fun detail(s: LocalDate, e: LocalDate): String {
        val n = ChronoUnit.DAYS.between(s, e).toInt() + 1
        val begins = League.startsText(League.CAL.start(s), now)
        return if (n == 1) "1 dia · $begins" else "$n dias · $begins"
    }
    Row(Modifier.fillMaxWidth().gmPress { open = true }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.size(40.dp).background(GMColors.raised, GMRadius.m), contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.CalendarMonth, null, tint = Color.White, modifier = Modifier.size(20.dp))
        }
        Column(Modifier.weight(1f)) {
            Text(range(start, end), color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.Bold))
            Text(detail(start, end), color = GMColors.dim, style = GMType.caption)
        }
        Icon(Icons.Filled.ChevronRight, null, tint = GMColors.dim, modifier = Modifier.size(16.dp))
    }
    if (open) GMSheet({ open = false }) {
        Text("Período da liga", color = Color.White, style = GMType.headline)
        GMRow("Início", subtitle = range(start, start).substringBefore(" →"), onClick = { editing = "start" })
        GMRow("Último dia", subtitle = range(end, end).substringBefore(" →"), onClick = { editing = "end" })
        GMFlow {
            for ((n, label) in listOf(7 to "1 sem", 14 to "2 sem", 30 to "30 dias", 60 to "60 dias")) GMChip(label, false) { onChange(start, start.plusDays(n - 1L)) }
            GMChip("Fim do mês", false) { onChange(start, start.withDayOfMonth(start.lengthOfMonth())) }
        }
        Text(range(start, end) + " · " + detail(start, end), color = GMColors.dim, style = GMType.caption)
        GMButton("Confirmar", { open = false })
    }
    editing?.let { which ->
        val initial = if (which == "start") start else end
        val min = if (which == "start") minDate else start
        val state = rememberDatePickerState(initialSelectedDateMillis = initial.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli(),
            selectableDates = object : SelectableDates {
                override fun isSelectableDate(utcTimeMillis: Long) = !Instant.ofEpochMilli(utcTimeMillis).atZone(ZoneOffset.UTC).toLocalDate().isBefore(min)
            })
        GMSheet({ editing = null }) {
            DatePicker(state, title = null, headline = null, showModeToggle = false, colors = DatePickerDefaults.colors(
                containerColor = GMColors.bg, selectedDayContainerColor = GMColors.accent, selectedDayContentColor = Color.Black,
                todayDateBorderColor = GMColors.accent, todayContentColor = GMColors.accent))
            GMButton("Confirmar", {
                state.selectedDateMillis?.let { ms ->
                    val d = Instant.ofEpochMilli(ms).atZone(ZoneOffset.UTC).toLocalDate()
                    if (which == "start") onChange(d, maxOf(end, d)) else onChange(start, maxOf(d, start))
                }
                editing = null
            })
        }
    }
}

// MARK: Regras (LeagueRulesViews.swift)

@Composable
private fun VerificationSection(s: LeagueSettings, onChange: (LeagueSettings) -> Unit) {
    val v = s.verification
    fun set(n: CheckInVerification) = onChange(s.copy(verification = n))
    GMSection("Verificação do check-in", footer = v.preset.detail) {
        GMChoiceChips(VerificationPreset.entries.map { it to it.label }, v.preset) { set(CheckInVerification.preset(it)) }
        if (v.preset != VerificationPreset.OFF) {
            GMDivider()
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) { for (b in v.bullets) Text("• $b", color = GMColors.dim, style = GMType.caption) }
        }
    }
    if (v.preset == VerificationPreset.PERSONALIZADO) {
        GMSection("Foto obrigatória", footer = v.media.detail) { GMSegmented(MediaPolicy.entries.map { it to it.label }, v.media) { set(v.copy(media = it)) } }
        GMSection("Foto da galeria", footer = v.library.detail) { GMSegmented(LibraryMediaPolicy.entries.map { it to it.label }, v.library) { set(v.copy(library = it)) } }
        GMSection("Horário do check-in", footer = v.time.detail + " A hora verificada é a do aparelho que gravou o treino ou a da foto da galeria; na câmera do app, a hora do post.") {
            GMSegmented(CheckInTimePolicy.entries.map { it to it.label }, v.time) { set(v.copy(time = it)) }
        }
        GMSection("Retroativo", footer = "Até quantos dias para trás dá para postar um treino.") {
            GMChoiceChips(CheckInVerification.backlogOptions.map { it to CheckInVerification.backlogName(it) }, v.backlogDays) { set(v.copy(backlogDays = it)) }
        }
        GMSection {
            GMToggle("Aparelho obrigatório", v.deviceRequired, { set(v.copy(deviceRequired = it)) }, "Só vale treino gravado pelo Apple Watch, pelo Apple Saúde ou pelo GPS do app")
            GMDivider()
            GMToggle("Local obrigatório", v.locationRequired, { set(v.copy(locationRequired = it)) }, "O check-in precisa ter o local (academia marcada ou foto com local)")
        }
    }
}

@Composable
private fun ProofSection(s: LeagueSettings, onChange: (LeagueSettings) -> Unit) {
    val pose = DailyPose.of(Instant.now())
    GMSection(footer = "Com a revisão ligada, cada check-in espera você aprovar ou negar antes de pontuar. Negado, ele sai da liga. A pose do dia muda todo dia e precisa aparecer na foto: sem ela, você pode negar o check-in.") {
        // O que já estava postado continua valendo
        GMToggle("Revisar check-ins", s.reviewRequired, { onChange(s.copy(reviewRequired = it, reviewSince = if (it) Instant.now() else null)) }, "Você aprova ou nega cada check-in")
        GMDivider()
        GMToggle("Pose do dia", s.posesEnabled, { onChange(s.copy(posesEnabled = it)) }, "Hoje: ${pose.emoji} ${pose.name}")
    }
}

@Composable
private fun PointsSection(rules: List<PointRuleRow>, onChange: (List<PointRuleRow>) -> Unit) {
    var editing by remember { mutableStateOf<PointRuleRow?>(null) }
    GMSection("Tabela de pontos", footer = "Cada treino vale a linha mais específica que o cobre (um tipo antes de uma seção). Treino fora da tabela vale 0.") {
        if (rules.isEmpty()) Text("Nenhuma atividade ainda: todo check-in vale 0.", color = GMColors.dim, style = GMType.subheadline)
        for (r in rules) {
            GMRow(r.targetName, icon = if (r.rule.points < 0) Icons.Filled.RemoveCircleOutline else Icons.Filled.AddCircleOutline,
                  iconTint = if (r.rule.points < 0) GMColors.danger else GMColors.accent, subtitle = r.summary, chevron = true, onClick = { editing = r })
            GMDivider()
        }
        GMRow("Adicionar atividade", icon = Icons.Filled.Add, iconTint = GMColors.accent, onClick = { editing = PointRuleRow(LeagueEdits.newID(), ActivityPointRule()) })
    }
    editing?.let { r ->
        PointRuleEditor(r, rules.none { it.id == r.id }, { editing = null }) { saved ->
            onChange(if (saved == null) rules.filter { it.id != r.id } else if (rules.any { it.id == saved.id }) rules.map { if (it.id == saved.id) saved else it } else rules + saved)
            editing = null
        }
    }
}

@Composable
private fun PointRuleEditor(initial: PointRuleRow, isNew: Boolean, onDismiss: () -> Unit, done: (PointRuleRow?) -> Unit) {
    var rule by remember { mutableStateOf(initial.rule) }
    var choosing by remember { mutableStateOf(false) }
    val sections = WorkoutType.all.map { it.section }.distinct()
    GMModal(true, if (isNew) "Nova atividade" else "Editar atividade", onDismiss, confirm = "Salvar",
            confirmEnabled = rule.workoutTypeIDs.isNotEmpty() || rule.sections.isNotEmpty(), onConfirm = { done(initial.copy(rule = rule)) }) {
        GMSection("Treinos", footer = "Escolha tipos de treino ou seções inteiras do catálogo.") {
            GMRow(if (rule.workoutTypeIDs.isEmpty()) "Escolher tipos" else "${rule.workoutTypeIDs.size} tipo${if (rule.workoutTypeIDs.size == 1) "" else "s"}",
                  icon = Icons.Filled.Checklist, iconTint = GMColors.accent, chevron = true,
                  subtitle = rule.workoutTypeIDs.mapNotNull { WorkoutType.byID(it)?.name }.take(4).joinToString(", "), onClick = { choosing = true })
            GMDivider()
            GMFlow {
                for (s in sections) {
                    val on = s in rule.sections
                    GMChip(s, on) { rule = rule.copy(sections = if (on) rule.sections - s else rule.sections + s) }
                }
            }
        }
        GMSection("Como pontua", footer = if (rule.method == "perCheckIn") "Vale os pontos toda vez que a atividade é registrada."
                                          else "Vale os pontos a cada quantidade completa: 59 min num \"a cada 30 min\" valem 1 vez.") {
            GMSegmented(listOf("perCheckIn" to "Por vez", "perAmount" to "Por quantidade"), rule.method) { rule = rule.copy(method = it) }
            GMDivider()
            StepRow("Pontos") { GMStepper(rule.points, { rule = rule.copy(points = it) }, -100..100, format = { if (it < 0) "−${-it}" else "$it" }) }
            if (rule.method == "perAmount") {
                GMDivider()
                GMChoiceChips(listOf("minutes", "km", "kcal").map { it to PointRuleRow.metricName(it) }, rule.metric) { rule = rule.copy(metric = it) }
                GMDivider()
                StepRow("A cada") { GMStepper(rule.every, { rule = rule.copy(every = it) }, 1..600, step = if (rule.metric == "km") 1 else 5,
                                              format = { "$it ${PointRuleRow.metricName(rule.metric)}" }) }
            }
        }
        if (rule.points < 0) Text("Pontos negativos: esta atividade tira pontos de quem registrar.", color = GMColors.dim, style = GMType.footnote)
        if (!isNew) GMButton("Tirar da tabela", { done(null) }, icon = Icons.Filled.Delete, kind = GMButtonKind.DANGER)
    }
    if (choosing) WorkoutTypeSheet(rule.workoutTypeIDs.toSet(), onDismiss = { choosing = false }) { rule = rule.copy(workoutTypeIDs = it.sorted()); choosing = false }
}

@Composable
private fun StepRow(title: String, stepper: @Composable () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(title, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold), modifier = Modifier.weight(1f))
        stepper()
    }
}

private fun limitStep(s: LeagueScoring) = when (s) {
    LeagueScoring.TREINOS, LeagueScoring.DIAS -> 1; LeagueScoring.MINUTOS -> 15; LeagueScoring.DISTANCIA -> 1000
    LeagueScoring.CALORIAS -> 50; LeagueScoring.PONTOS, LeagueScoring.ATIVIDADES -> 10
}

private fun defaultCap(s: LeagueScoring) = when (s) {
    LeagueScoring.TREINOS, LeagueScoring.DIAS -> 1; LeagueScoring.MINUTOS -> 120; LeagueScoring.DISTANCIA -> 20_000
    LeagueScoring.CALORIAS -> 1000; LeagueScoring.PONTOS, LeagueScoring.ATIVIDADES -> 100
}

@Composable
private fun LimitsSection(limits: ScoringLimits, scoring: LeagueScoring, hasTeams: Boolean, onChange: (ScoringLimits) -> Unit) {
    val step = limitStep(scoring)
    val fmt = { v: Int -> if (v == 0) "—" else LeagueText.short(scoring, v) }
    GMSection("Limite de pontos", footer = "Deixa a disputa justa: o que passar do teto no período não conta. 0 = sem teto.") {
        GMToggle("Usar limites", limits.isEnabled, { on -> onChange(if (on) ScoringLimits(mapOf(LimitPeriod.DAY to defaultCap(scoring))) else ScoringLimits()) })
        if (limits.isEnabled) {
            for (p in LimitPeriod.entries) {
                GMDivider()
                StepRow("Pessoa · ${p.label.lowercase()}") {
                    GMStepper(limits.individual[p] ?: 0, { v -> onChange(limits.copy(individual = if (v == 0) limits.individual - p else limits.individual + (p to v))) },
                              0..step * 200, step = step, format = fmt)
                }
            }
            if (hasTeams) for (p in LimitPeriod.entries) {
                GMDivider()
                StepRow("Time · ${p.label.lowercase()}") {
                    GMStepper(limits.team[p] ?: 0, { v -> onChange(limits.copy(team = if (v == 0) limits.team - p else limits.team + (p to v))) },
                              0..step * 2000, step = step, format = fmt)
                }
            }
        }
    }
}

@Composable
private fun GoalsSection(s: LeagueSettings, scoring: LeagueScoring, hasTeams: Boolean, onChange: (LeagueSettings) -> Unit) {
    val step = when (scoring) {
        LeagueScoring.TREINOS, LeagueScoring.DIAS -> 1; LeagueScoring.MINUTOS -> 30; LeagueScoring.DISTANCIA -> 1000
        LeagueScoring.CALORIAS -> 100; LeagueScoring.PONTOS, LeagueScoring.ATIVIDADES -> 50
    }
    val fmt = { v: Int -> if (v == 0) "—" else LeagueText.format(scoring, v) }
    GMSection("Metas", footer = if (s.rankingsDisabled) "Sem ranking: cada pessoa vê só a barra de progresso até a meta. Bom para grupos de constância, sem competição."
                                else "Com meta, cada pessoa (e cada time) vê a barra de progresso até ela, junto do ranking.") {
        StepRow("Meta por pessoa") { GMStepper(s.individualGoal, { onChange(s.copy(individualGoal = it)) }, 0..step * 500, step = step, format = fmt) }
        if (hasTeams) {
            GMDivider()
            StepRow("Meta por time") { GMStepper(s.teamGoal, { onChange(s.copy(teamGoal = it)) }, 0..step * 5000, step = step, format = fmt) }
        }
        GMDivider()
        GMToggle("Esconder o ranking", s.rankingsDisabled, { onChange(s.copy(rankingsDisabled = it)) }, "Só as metas aparecem")
    }
    GMSection("Início da semana", footer = "Dia em que o ranking da semana zera.") {
        GMChoiceChips(listOf(0 to "Padrão (domingo)") + (1..7).map { it to LeagueSettings.weekday(it) }, s.weekStart ?: 0) {
            onChange(s.copy(weekStart = if (it == 0) null else it))
        }
    }
}

// MARK: Entrar com código (LeaguesView.swift `JoinLeagueView`)

@Composable
fun JoinLeagueScreen(env: AppEnv, home: HomeData, vm: LeaguesViewModel, initial: String, onDismiss: () -> Unit) {
    val ui by vm.ui.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    var code by remember { mutableStateOf(initial) }
    var message by remember { mutableStateOf<String?>(null) }
    var found by remember { mutableStateOf<LeagueDraft?>(null) }
    var rep by remember { mutableStateOf(home.roster.main?.uuid) }
    val clean = code.trim().uppercase()
    val needsApproval = found?.let { LeagueSettings.parse(it.settings).requiresApproval } ?: false

    fun look() {
        when {
            ui.leagues.any { it.code == clean } -> message = "Você já está nessa liga."
            ui.pendingJoins.any { it.code == clean } -> message = "Você já pediu para entrar. Espere o dono aprovar."
            else -> {
                message = "Procurando…"
                scope.launch {
                    runCatching { vm.store.remote.join(clean) }.onSuccess { d ->
                        if (d == null) { message = "Liga não encontrada. Confira o código."; return@onSuccess }
                        val banned = env.uid in LeagueSettings.parse(d.settings).banned
                        message = if (banned) "Você foi banido desta liga." else null
                        found = if (banned) null else d
                    }.onFailure { message = "Não deu para procurar agora: confira a internet e tente de novo." }
                }
            }
        }
    }

    fun join() {
        val d = found ?: return
        scope.launch {
            if (needsApproval) {
                // O pedido vai para o dono; a liga entra no aparelho quando ele aceitar
                runCatching { vm.store.requestJoin(d, home.trainerName, rep) }
                    .onSuccess { onDismiss() }.onFailure { message = "Não deu para mandar o pedido: confira a internet e tente de novo." }
            } else {
                vm.store.join(d, vm.store.representative(rep))
                onDismiss()
            }
        }
    }

    LaunchedEffect(Unit) { if (code.length >= 6) look() }
    GMModal(true, "Entrar numa liga", onDismiss, confirm = if (found == null) "Procurar" else if (needsApproval) "Pedir para entrar" else "Entrar",
            confirmEnabled = clean.length >= 6, onConfirm = { if (found == null) look() else join() }) {
        GMSection("Código", footer = message ?: "Peça o código para quem criou a liga.") {
            GMTextField(code, { code = it.uppercase().take(12); found = null; message = null }, "Código da liga",
                        keyboard = KeyboardOptions(capitalization = KeyboardCapitalization.Characters, autoCorrectEnabled = false))
        }
        found?.let { d ->
            PreviewCard(d)
            MonsterChoiceSection(home, rep) { rep = it }
        }
    }
}

/** O que a pessoa vê antes de entrar (LeagueModerationViews.swift `LeaguePreviewCard`) */
@Composable
private fun PreviewCard(d: LeagueDraft) {
    val s = LeagueSettings.parse(d.settings)
    val scoring = LeagueScoring.entries.firstOrNull { it.raw == d.scoring } ?: LeagueScoring.PONTOS
    val rule = LeagueActivityRule.parse(d.activityRule ?: "")
    val period = d.end?.let { " · ${LeagueFormats.dayMonth(d.start)} – ${LeagueFormats.dayMonth(it)}" }.orEmpty()
    GMCard {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(d.emoji, fontSize = 34.sp)
            Column {
                Text(d.name, color = Color.White, style = GMType.headline)
                Text((if (d.end == null) "Clube" else "Desafio") + " · " + LeagueText.name(scoring) + period, color = GMColors.dim, style = GMType.caption)
            }
        }
        val lines = listOf(LeagueText.detail(scoring)) + (if (rule.mode == "all") emptyList() else listOf(LeagueText.ruleDetail(rule))) +
            (if (s.verification.preset == VerificationPreset.OFF) emptyList() else s.verification.bullets) +
            (if (s.reviewRequired) listOf("O dono aprova cada check-in antes de pontuar") else emptyList()) +
            (if (s.posesEnabled) listOf("Pose do dia na foto de todo check-in") else emptyList()) + s.limits.summary +
            (if (s.requiresApproval) listOf("Para entrar, o dono precisa aprovar o seu pedido") else emptyList())
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) { for (t in lines) Text("• $t", color = GMColors.dim, style = GMType.caption) }
    }
}

