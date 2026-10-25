package com.alonsoalmeida.gymbros.ui.bros

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.DirectionsWalk
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.Accessibility
import androidx.compose.material.icons.filled.ArrowCircleUp
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.AutoStories
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material.icons.filled.CrueltyFree
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.MilitaryTech
import androidx.compose.material.icons.filled.MonitorHeart
import androidx.compose.material.icons.filled.MonitorWeight
import androidx.compose.material.icons.filled.NightsStay
import androidx.compose.material.icons.filled.Scale
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.filled.WbTwilight
import androidx.compose.material.icons.filled.Whatshot
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Pets
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.hideFromAccessibility
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.alonsoalmeida.gymbros.data.FriendsRepository
import com.alonsoalmeida.gymbros.data.TradesRepository
import com.alonsoalmeida.gymbros.domain.Attribute
import com.alonsoalmeida.gymbros.domain.Bro
import com.alonsoalmeida.gymbros.domain.MonsterForm
import com.alonsoalmeida.gymbros.domain.Snapshot
import com.alonsoalmeida.gymbros.domain.Species
import com.alonsoalmeida.gymbros.domain.Stage
import com.alonsoalmeida.gymbros.domain.bros.Dex
import com.alonsoalmeida.gymbros.domain.bros.TradeRules
import com.alonsoalmeida.gymbros.domain.home.HomeData
import com.alonsoalmeida.gymbros.domain.profile.AchievementItem
import com.alonsoalmeida.gymbros.ui.AppEnv
import com.alonsoalmeida.gymbros.domain.onboarding.ScreenTip
import com.alonsoalmeida.gymbros.ui.onboarding.ScreenTipHost
import com.alonsoalmeida.gymbros.ui.copy
import com.alonsoalmeida.gymbros.ui.components.GMCard
import com.alonsoalmeida.gymbros.ui.components.GMModal
import com.alonsoalmeida.gymbros.ui.components.GMProgressBar
import com.alonsoalmeida.gymbros.ui.components.LivingMonster
import com.alonsoalmeida.gymbros.ui.components.MonsterSprite
import com.alonsoalmeida.gymbros.ui.components.gmPress
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMRadius
import com.alonsoalmeida.gymbros.ui.theme.GMType
import com.alonsoalmeida.gymbros.ui.theme.color

/**
 * Bros (o botão da pata na tela inicial): DexView.swift com as abas "Meus bros" (a Box de Monsters.swift),
 * "BroBook" e "Conquistas". A Box abre a ficha de cada bro e a central de trocas.
 */
@Composable
fun BrosModal(visible: Boolean, env: AppEnv, home: HomeData, onDismiss: () -> Unit) {
    if (!visible) return
    val vm: BrosViewModel = viewModel(key = "bros-${env.uid}", factory = viewModelFactory {
        initializer { BrosViewModel(env.copies, TradesRepository(), FriendsRepository()) }
    })
    androidx.compose.runtime.SideEffect { vm.bind(home) }
    val settings by vm.settings.collectAsStateWithLifecycle()
    val trades by vm.state.collectAsStateWithLifecycle()
    var tab by rememberSaveable { mutableIntStateOf(0) }
    var selected by rememberSaveable { mutableStateOf<String?>(null) }
    var entry by rememberSaveable { mutableStateOf<String?>(null) }
    var trading by rememberSaveable { mutableStateOf(false) }
    // Ofertas e trocas aceitas para o selo do botão Trocar (como o `.task { refresh }` da Box)
    LaunchedEffect(Unit) { vm.refresh() }

    // Atividades que ainda existem (as outras são apagadas que continuam valendo XP)
    val copy = env.copy()
    val liveIDs = remember(copy) {
        (copy?.get("activities") as? kotlinx.serialization.json.JsonArray).orEmpty().mapNotNull {
            ((it as? kotlinx.serialization.json.JsonObject)?.get("uuid") as? kotlinx.serialization.json.JsonPrimitive)?.content?.uppercase()
        }.toSet()
    }
    val discovered = remember(settings.discovered, home.roster) { Dex.discovered(settings.discovered, home.roster) }
    val revealAll = settings.revealAll
    val isKnown: (MonsterForm) -> Boolean = { revealAll || it.id in discovered }
    // Conquistas (Achievements.evaluate): as mesmas que o perfil monta, com os treinos guiados e o total do BroBook
    val profile by com.alonsoalmeida.gymbros.ui.profile.profileViewModel(env).state.collectAsStateWithLifecycle()
    val achievements = profile?.data?.achievements.orEmpty()

    GMModal(true, "Bros", onDismiss) {
        Text(when (tab) {
            0 -> "Seu principal e os que te representam nas ligas"
            1 -> "Todas as formas de todas as espécies"
            else -> "Marcas que você já bateu e as que faltam"
        }, color = GMColors.dim, style = GMType.subheadline)
        Hero(home.snapshot, discovered, achievements)
        BroSegmented(listOf(0 to "Meus bros", 1 to "BroBook", 2 to "Conquistas"), tab) { tab = it }
        when (tab) {
            0 -> {
                val now = java.time.Instant.now()
                val offers = TradeRules.incoming(trades.all, now).size + TradeRules.ready(trades.all, settings.tradeApplied).size
                BroBox(home, offers, onTrade = { trading = true }, onSelect = { selected = it })
                ScreenTipHost(env, ScreenTip.BOX, blocked = trading || selected != null)
                Text("Toque num bro para ver a ficha dele: treinos, evoluções e X1. O principal aparece na tela inicial e nos widgets e recebe o XP de todas as atividades. O bro que te representa numa liga também ganha 80% do XP dos check-ins dela. Ovos novos você adota ao entrar numa liga.",
                     color = GMColors.dim, style = GMType.caption)
            }
            1 -> {
                BroBook(home.snapshot, revealAll, isKnown, onReveal = { vm.setRevealAll(!revealAll) }, onOpen = { entry = it.id })
                ScreenTipHost(env, ScreenTip.BROBOOK, blocked = entry != null)
            }
            else -> Trophies(achievements)
        }
    }

    selected?.let { id ->
        BroSheet(home, id, vm, liveIDs, isKnown, onSelect = { selected = it }, onDismiss = { selected = null })
    }
    entry?.let { id -> MonsterForm.byID(id)?.let { DexEntry(it, home.snapshot, isKnown) { entry = null } } }
    TradeHub(trading, env, home, vm, settings.tradeApplied) { trading = false }
    trades.arrived?.let { TradeArrived(home, it) { vm.dismissArrival() } }
}

/** Seu bro em destaque, o anel do BroBook e os números da coleção */
@Composable
private fun Hero(s: Snapshot, discovered: Set<String>, achievements: List<AchievementItem>) {
    val all = remember { Dex.allForms() }
    val known = all.count { it.id in discovered }
    val progress = known.toFloat() / maxOf(all.size, 1)
    val hatched = Species.all.count { MonsterForm(Stage.BABY, null, species = it.id).id in discovered }
    val ring = Brush.sweepGradient(listOf(GMColors.accent, Attribute.RESISTENCIA.color(), Attribute.TECNICA.color(), GMColors.accent))
    Row(
        Modifier.fillMaxWidth().background(GMColors.card, GMRadius.card).border(1.dp, Color.White.copy(alpha = 0.08f), GMRadius.card)
            .padding(18.dp).semantics(mergeDescendants = true) {},
        horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(96.dp).drawBehind {
            val w = 7.dp.toPx()
            drawCircle(Color.White.copy(alpha = 0.1f), radius = size.minDimension / 2 - w / 2, style = Stroke(w))
            drawArc(ring, -90f, 360f * progress, false, topLeft = Offset(w / 2, w / 2),
                    size = androidx.compose.ui.geometry.Size(size.width - w, size.height - w), style = Stroke(w, cap = StrokeCap.Round))
        }, contentAlignment = Alignment.Center) { LivingMonster(s.form, Modifier.size(68.dp), progress = s.progress) }
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("${Math.round(progress * 100)} % do BroBook", color = Color.White, fontSize = 24.sp, fontWeight = FontWeight.ExtraBold)
            Stat(Icons.Filled.AutoAwesome, GMColors.accent, "$known de ${all.size} formas")
            Stat(Icons.Filled.Pets, Attribute.AGILIDADE.color(), "$hatched de ${Species.all.count { it.isReady }} espécies chocadas")
            Stat(Icons.Filled.EmojiEvents, GMColors.trophy, "${achievements.count { it.unlocked }} de ${achievements.size} conquistas")
        }
    }
}

@Composable
private fun Stat(icon: androidx.compose.ui.graphics.vector.ImageVector, tint: Color, text: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = tint, modifier = Modifier.size(14.dp))
        Text(text, color = Color.White.copy(alpha = 0.85f), style = GMType.caption.copy(fontWeight = FontWeight.SemiBold))
    }
}

// MARK: Conquistas

/** Aba Conquistas (DexView.swift `trophies`): contagem no topo e a grade, desbloqueadas primeiro e depois as mais perto */
@Composable
private fun Trophies(list: List<AchievementItem>) {
    val unlocked = list.count { it.unlocked }
    val sorted = remember(list) { list.sortedWith(compareBy({ if (it.unlocked) 0 else 1 }, { -it.progress })) }
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        GMCard {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Desbloqueadas", color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
                Spacer(Modifier.weight(1f))
                Text("$unlocked/${list.size}", color = GMColors.trophy, style = GMType.subheadline.copy(fontWeight = FontWeight.Bold, fontFeatureSettings = "tnum"))
            }
            GMProgressBar(unlocked.toDouble() / maxOf(list.size, 1), tint = GMColors.trophy)
        }
        for (row in sorted.chunked(2)) PairRow(10.dp, row)
    }
}

/** Duas colunas da mesma altura (a do card mais alto), como a linha do LazyVGrid */
@Composable
private fun PairRow(spacing: androidx.compose.ui.unit.Dp, row: List<AchievementItem>) {
    androidx.compose.ui.layout.SubcomposeLayout { c ->
        val gap = spacing.roundToPx()
        val w = (c.maxWidth - gap) / 2
        val h = subcompose("medir") { row.forEach { Trophy(it) } }
            .maxOfOrNull { it.measure(androidx.compose.ui.unit.Constraints(minWidth = w, maxWidth = w)).height } ?: 0
        val placed = subcompose("pôr") { row.forEach { Trophy(it) } }.map { it.measure(androidx.compose.ui.unit.Constraints.fixed(w, h)) }
        layout(c.maxWidth, h) { placed.forEachIndexed { i, p -> p.placeRelative(i * (w + gap), 0) } }
    }
}

@Composable
private fun Trophy(a: AchievementItem) {
    val pct = (a.progress * 100).toInt()
    Column(
        Modifier.fillMaxSize().heightIn(min = 176.dp).background(GMColors.card, GMRadius.card)
            .border(1.dp, if (a.unlocked) GMColors.trophy.copy(alpha = 0.4f) else Color.Transparent, GMRadius.card).padding(14.dp)
            .semantics(mergeDescendants = true) { stateDescription = if (a.unlocked) "Feito" else "$pct%" },
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Box(
            Modifier.size(54.dp).then(if (a.unlocked) Modifier.shadow(10.dp, CircleShape, ambientColor = GMColors.trophy, spotColor = GMColors.trophy) else Modifier)
                .background(if (a.unlocked) Brush.linearGradient(listOf(GMColors.trophy, GMColors.streak)) else SolidColor(GMColors.raised), CircleShape),
            contentAlignment = Alignment.Center,
        ) { AchievementIcon(a.symbol, if (a.unlocked) Color.Black else GMColors.dim) }
        Text(a.title, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.Bold), textAlign = TextAlign.Center)
        Text(a.detail, color = GMColors.dim, style = GMType.caption, textAlign = TextAlign.Center)
        Spacer(Modifier.weight(1f))
        if (a.unlocked) {
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Verified, null, tint = GMColors.trophy, modifier = Modifier.size(12.dp))
                Text("Feito", color = GMColors.trophy, style = GMType.caption2.copy(fontWeight = FontWeight.Bold))
            }
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                GMProgressBar(a.progress, Modifier.weight(1f), tint = GMColors.trophy, height = 5.dp)
                Text("$pct%", color = GMColors.dim, fontSize = 10.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace)
            }
        }
    }
}

/** O SF Symbol de cada conquista no equivalente Material; os números ("10.circle") viram o próprio número */
@Composable
private fun AchievementIcon(symbol: String, tint: Color) {
    val number = symbol.substringBefore(".circle", "").takeIf { it.isNotEmpty() && it.all(Char::isDigit) }
    if (number != null) {
        Box(Modifier.size(26.dp).border(2.5.dp, tint, CircleShape), contentAlignment = Alignment.Center) {
            Text(number, color = tint, fontSize = if (number.length > 2) 9.sp else 11.sp, fontWeight = FontWeight.Black)
        }
        return
    }
    val icon = when (symbol) {
        "figure.walk" -> Icons.AutoMirrored.Filled.DirectionsWalk
        "sparkles" -> Icons.Filled.AutoAwesome
        "arrow.up.circle" -> Icons.Filled.ArrowCircleUp
        "trophy" -> Icons.Filled.EmojiEvents
        "crown", "crown.fill" -> Icons.Filled.WorkspacePremium
        "flame" -> Icons.Filled.Whatshot
        "flame.fill" -> Icons.Filled.LocalFireDepartment
        "bolt.heart" -> Icons.Filled.MonitorHeart
        "square.grid.2x2" -> Icons.Filled.GridView
        "timer" -> Icons.Filled.Timer
        "sunrise" -> Icons.Filled.WbTwilight
        "moon.stars" -> Icons.Filled.NightsStay
        "list.clipboard" -> Icons.Filled.ContentPaste
        "medal", "medal.fill" -> Icons.Filled.MilitaryTech
        "scalemass" -> Icons.Filled.Scale
        "scalemass.fill" -> Icons.Filled.MonitorWeight
        "figure.stand" -> Icons.Filled.Accessibility
        "pawprint", "pawprint.fill" -> Icons.Filled.Pets
        "tortoise.fill" -> Icons.Filled.CrueltyFree
        "book" -> Icons.AutoMirrored.Filled.MenuBook
        "book.fill" -> Icons.Filled.AutoStories
        "heart.text.square" -> Icons.Filled.Favorite
        else -> Icons.Filled.EmojiEvents
    }
    Icon(icon, null, tint = tint, modifier = Modifier.size(24.dp))
}

// MARK: Box

/** Todos os bros em slots, 4 por fileira, sempre fileiras cheias e pelo menos 3 */
@Composable
private fun BroBox(home: HomeData, offers: Int, onTrade: () -> Unit, onSelect: (String) -> Unit) {
    val monsters = home.roster.monsters
    val slots = maxOf(12, (monsters.size + 3) / 4 * 4)
    Column(
        Modifier.fillMaxWidth().background(GMColors.card, GMRadius.card)
            .background(Brush.verticalGradient(listOf(GMColors.accent.copy(alpha = 0.08f), Color.Transparent)), GMRadius.card)
            .border(1.dp, Color.White.copy(alpha = 0.08f), GMRadius.card).padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(Icons.Filled.GridView, null, tint = Color.White, modifier = Modifier.size(18.dp))
            Text("Box", color = Color.White, style = GMType.headline)
            Spacer(Modifier.weight(1f))
            Text("${monsters.size} ${if (monsters.size == 1) "bro" else "bros"}", color = GMColors.dim,
                 style = GMType.subheadline.copy(fontWeight = FontWeight.Bold))
            Box {
                Row(
                    Modifier.gmPress(onClick = onTrade).background(GMColors.trophy.copy(alpha = 0.15f), CircleShape)
                        .padding(horizontal = 10.dp, vertical = 6.dp)
                        .semantics(mergeDescendants = true) {
                            contentDescription = if (offers > 0) "Trocas, $offers proposta${if (offers == 1) "" else "s"} para você" else "Trocas"
                        },
                    horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.Filled.SwapHoriz, null, tint = GMColors.trophy, modifier = Modifier.size(14.dp))
                    Text("Trocar", color = GMColors.trophy, style = GMType.caption.copy(fontWeight = FontWeight.Bold))
                }
                if (offers > 0) {
                    Text("$offers", color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Black,
                         modifier = Modifier.align(Alignment.TopEnd).offset(x = 6.dp, y = (-6).dp).background(GMColors.badge, CircleShape)
                             .padding(horizontal = 5.dp, vertical = 1.dp).semantics { hideFromAccessibility() })
                }
            }
        }
        for (row in 0 until slots / 4) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                for (c in 0 until 4) {
                    val i = row * 4 + c
                    Box(Modifier.weight(1f)) {
                        val m = monsters.getOrNull(i)
                        if (m != null) Slot(home, m) { onSelect(m.uuid) } else EmptySlot()
                    }
                }
            }
        }
    }
}

@Composable
private fun EmptySlot() {
    Box(Modifier.fillMaxWidth().aspectRatio(0.82f).semantics { hideFromAccessibility() }.drawBehind {
        drawRoundRect(Color.White.copy(alpha = 0.08f), cornerRadius = androidx.compose.ui.geometry.CornerRadius(12.dp.toPx()),
                      style = Stroke(1.5.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(5.dp.toPx(), 5.dp.toPx()))))
    })
}

@Composable
private fun Slot(home: HomeData, m: Bro, onClick: () -> Unit) {
    val s = home.roster.snapshot(m.uuid)
    val isMain = m.uuid == home.roster.mainID
    val rep = home.leagues.firstOrNull { it.monsterUUID?.equals(m.uuid, ignoreCase = true) == true }
    val haptic = LocalHapticFeedback.current
    val label = "${m.displayName(s.form)}${if (isMain) ", principal" else ""}, ${if (s.stage == Stage.EGG) "ovo" else "nível ${s.level}"}"
    Box {
        Column(
            Modifier.fillMaxWidth().aspectRatio(0.82f).background(GMColors.raised, GMRadius.m)
                .gmPress { haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove); onClick() }
                .semantics(mergeDescendants = true) { contentDescription = label }.padding(horizontal = 4.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
        ) {
            MonsterSprite(s.form, Modifier.size(52.dp))
            Text(m.displayName(s.form), color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(if (s.stage == Stage.EGG) "Ovo" else "Nv ${s.level}", color = GMColors.dim, fontSize = 9.sp, fontWeight = FontWeight.SemiBold,
                 fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace)
        }
        if (isMain) {
            Box(Modifier.offset((-4).dp, (-4).dp).size(18.dp).background(GMColors.accent, CircleShape), contentAlignment = Alignment.Center) {
                Icon(Icons.Filled.Star, null, tint = Color.Black, modifier = Modifier.size(11.dp))
            }
        }
        if (rep != null) {
            Box(Modifier.align(Alignment.TopEnd).offset(4.dp, (-4).dp).size(20.dp).background(GMColors.bg, CircleShape), contentAlignment = Alignment.Center) {
                Text(rep.emoji, fontSize = 11.sp)
            }
        }
    }
}

// MARK: BroBook

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun BroBook(s: Snapshot, revealAll: Boolean, isKnown: (MonsterForm) -> Boolean, onReveal: () -> Unit, onOpen: (MonsterForm) -> Unit) {
    val ready = remember { Species.all.filter { it.isReady } }
    var speciesID by rememberSaveable { mutableStateOf(Species.STANDARD) }
    val haptic = LocalHapticFeedback.current
    Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
        Row(Modifier.padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("ESPÉCIES", color = GMColors.dim, style = GMType.caption.copy(fontWeight = FontWeight.Bold, letterSpacing = 0.6.sp))
            Spacer(Modifier.weight(1f))
            Row(
                Modifier.gmPress { haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove); onReveal() }
                    .background(if (revealAll) GMColors.accent else GMColors.raised, CircleShape).padding(horizontal = 14.dp, vertical = 9.dp)
                    .semantics(mergeDescendants = true) { stateDescription = if (revealAll) "ligado" else "desligado" },
                horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically,
            ) {
                val fg = if (revealAll) Color.Black else Color.White
                Icon(if (revealAll) Icons.Filled.Visibility else Icons.Filled.VisibilityOff, null, tint = fg, modifier = Modifier.size(16.dp))
                Text(if (revealAll) "Revelando" else "Revelar todas", color = fg, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
            }
        }
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            for (sp in ready) SpeciesCard(sp, sp.id == speciesID, isKnown) {
                haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove); speciesID = sp.id
            }
        }
        val sp = Species.byID(speciesID)?.takeIf { it.isReady } ?: return@Column
        val forms = remember(sp.id) { Dex.forms(sp) }
        val found = forms.count(isKnown)
        GMCard {
            Row(verticalAlignment = Alignment.Top) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(sp.name, color = Color.White, fontSize = 26.sp, fontWeight = FontWeight.ExtraBold)
                    Text(hatchText(sp), color = GMColors.dim, style = GMType.caption)
                }
                Text("$found/${forms.size}", color = GMColors.accent, style = GMType.subheadline.copy(fontWeight = FontWeight.Bold),
                     modifier = Modifier.background(GMColors.accent.copy(alpha = 0.15f), CircleShape).padding(horizontal = 10.dp, vertical = 6.dp))
            }
            val ks = kinds(sp)
            if (ks.isNotEmpty()) {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    for (k in ks) Row(Modifier.background(GMColors.raised, CircleShape).padding(horizontal = 9.dp, vertical = 5.dp),
                                      horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(com.alonsoalmeida.gymbros.ui.components.Symbols.of(kindSymbol(k.raw)), null, tint = Color.White, modifier = Modifier.size(12.dp))
                        Text(kindName(k.raw), color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                    }
                }
            }
        }
        // Linha evolutiva por fase: Bebê, Novato, Atletas e Lendas (as de virada por último)
        val groups = listOf(
            "Bebê e Novato" to forms.filter { it.stage == Stage.BABY || it.stage == Stage.ROOKIE },
            "Atletas" to forms.filter { it.stage == Stage.CHAMPION },
            "Lendas" to forms.filter { it.stage == Stage.ULTIMATE && !it.isVirada },
            "Lendas de virada" to forms.filter { it.isVirada },
        )
        for ((title, list) in groups) {
            if (list.isEmpty()) continue
            Text(title.uppercase(), color = GMColors.dim, style = GMType.caption.copy(fontWeight = FontWeight.Bold, letterSpacing = 0.6.sp),
                 modifier = Modifier.padding(horizontal = 4.dp))
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp), maxItemsInEachRow = 4) {
                for (f in list) FormCell(f, isKnown(f), f == s.form, Modifier.weight(1f)) { onOpen(f) }
                // Completa a última fileira para as células ficarem do mesmo tamanho
                repeat((4 - list.size % 4) % 4) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}

@Composable
private fun FormCell(f: MonsterForm, known: Boolean, current: Boolean, modifier: Modifier, onClick: () -> Unit) {
    val tint = f.attribute?.color() ?: GMColors.accent
    Column(
        modifier.background(if (current) tint.copy(alpha = 0.2f) else GMColors.card, GMRadius.m)
            .border(if (current) 2.dp else 0.dp, if (current) tint else Color.Transparent, GMRadius.m)
            .gmPress(onClick = onClick).padding(6.dp)
            .semantics(mergeDescendants = true) { contentDescription = if (known) f.name else "Forma não descoberta"; selected = current },
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        BroSprite(f, Modifier.size(48.dp), hidden = !known)
        Text(if (known) f.name else "???", color = if (known) Color.White else GMColors.dim, fontSize = 10.sp, fontWeight = FontWeight.Bold,
             maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun SpeciesCard(sp: Species, selected: Boolean, isKnown: (MonsterForm) -> Boolean, onClick: () -> Unit) {
    val forms = remember(sp.id) { Dex.forms(sp) }
    val seen = forms.count(isKnown)
    // Sempre o bebê, que representa a espécie sem puxar para nenhum galho
    val baby = MonsterForm(Stage.BABY, null, species = sp.id)
    Column(
        Modifier.width(100.dp).background(GMColors.card, GMRadius.card)
            .border(if (selected) 2.dp else 1.dp, if (selected) GMColors.accent else GMColors.stroke, GMRadius.card)
            .gmPress(onClick = onClick).padding(vertical = 12.dp)
            .semantics(mergeDescendants = true) { contentDescription = "${sp.name}, $seen de ${forms.size} formas"; this.selected = selected },
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Box(Modifier.size(68.dp).background(if (selected) GMColors.accent.copy(alpha = 0.22f) else GMColors.raised, CircleShape).padding(6.dp),
            contentAlignment = Alignment.Center) { BroSprite(baby, hidden = !isKnown(baby)) }
        Text(sp.name, color = Color.White, style = GMType.caption.copy(fontWeight = FontWeight.Bold), maxLines = 1)
        GMProgressBar(seen.toDouble() / maxOf(forms.size, 1), Modifier.padding(horizontal = 10.dp),
                      tint = if (seen == forms.size) GMColors.trophy else GMColors.accent, height = 4.dp)
        Text("$seen/${forms.size}", color = GMColors.dim, fontSize = 10.sp, fontWeight = FontWeight.SemiBold,
             fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace)
    }
}

/** De onde a espécie nasce (DexView.swift `hatchText`) */
private fun hatchText(sp: Species): String {
    val names = kinds(sp).map { kindName(it.raw).lowercase() }
    val list = if (names.size > 1) names.dropLast(1).joinToString(", ") + " ou " + names.last() else names.firstOrNull().orEmpty()
    return if (sp.id == Species.STANDARD) "Nasce quando o ovo choca com \"Outro\" ou com treinos variados, sem atividade principal"
    else "Nasce quando o ovo choca com $list (e parecidos no Apple Saúde)"
}

/** Categorias de onde a espécie nasce, na ordem do iOS (`Species.kinds` sem "Outro") */
private fun kinds(sp: Species) = com.alonsoalmeida.gymbros.domain.ActivityKind.entries
    .filter { it != com.alonsoalmeida.gymbros.domain.ActivityKind.OUTRO && com.alonsoalmeida.gymbros.domain.BroCatalog.kindSpecies[it.raw]?.contains(sp.id) == true }

/** Nome da categoria (Game.swift `ActivityKind.name`) */
internal fun kindName(raw: String): String = when (raw) {
    "musculacao" -> "Musculação"; "crossfit" -> "Crossfit"; "corrida" -> "Corrida"; "caminhada" -> "Caminhada"; "bike" -> "Bike"
    "natacao" -> "Natação"; "volei" -> "Vôlei"; "futebol" -> "Futebol"; "lutas" -> "Lutas"; "danca" -> "Dança"; "yoga" -> "Yoga"
    else -> "Outro"
}

/** SF Symbol da categoria (Game.swift `ActivityKind.symbol`) */
internal fun kindSymbol(raw: String): String = when (raw) {
    "musculacao" -> "figure.strengthtraining.traditional"; "crossfit" -> "figure.cross.training"; "corrida" -> "figure.run"
    "caminhada" -> "figure.walk"; "bike" -> "figure.outdoor.cycle"; "natacao" -> "figure.pool.swim"; "volei" -> "figure.volleyball"
    "futebol" -> "figure.soccer"; "lutas" -> "figure.martial.arts"; "danca" -> "figure.dance"; "yoga" -> "figure.yoga"
    else -> "figure.mixed.cardio"
}
