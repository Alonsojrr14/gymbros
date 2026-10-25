package com.alonsoalmeida.gymbros.ui.onboarding

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.DirectionsRun
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.automirrored.filled.Reply
import androidx.compose.material.icons.automirrored.filled.TrendingUp
import androidx.compose.material.icons.filled.AccountTree
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.Archive
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.CardGiftcard
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.ConfirmationNumber
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FitnessCenter
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.Forum
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.MilitaryTech
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.NotificationsActive
import androidx.compose.material.icons.filled.Pets
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.Publish
import androidx.compose.material.icons.filled.Scale
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material.icons.filled.Swipe
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material.icons.filled.TouchApp
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.compose.currentStateAsState
import com.alonsoalmeida.gymbros.data.CopyState
import com.alonsoalmeida.gymbros.domain.onboarding.ScreenTip
import com.alonsoalmeida.gymbros.domain.onboarding.ScreenTipCard
import com.alonsoalmeida.gymbros.domain.onboarding.ScreenTips
import com.alonsoalmeida.gymbros.domain.profile.ProfileEdits
import com.alonsoalmeida.gymbros.ui.AppEnv
import com.alonsoalmeida.gymbros.ui.components.GMButton
import com.alonsoalmeida.gymbros.ui.components.GMButtonKind
import com.alonsoalmeida.gymbros.ui.components.GMSheet
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMRadius
import com.alonsoalmeida.gymbros.ui.theme.GMType
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.Instant

/**
 * Uma dica por vez no app inteiro (ScreenTipView.swift `ScreenTipCenter`). O que foi visto vai para `tipsSeen` na cópia
 * da conta; `marked` segura as vistas nesta sessão até a cópia gravada voltar.
 */
object ScreenTipCenter {
    var showing by mutableStateOf<String?>(null)
        private set
    private val marked = mutableSetOf<String>()
    private val scope = MainScope()
    const val DELAY_MS = 700L

    fun canShow(tip: ScreenTip, settings: Map<String, Any?>): Boolean =
        tip.id !in marked && ScreenTips.shouldShow(tip, settings, blocked = showing != null)

    fun claim(tip: ScreenTip, settings: Map<String, Any?>): Boolean {
        if (!canShow(tip, settings)) return false
        showing = tip.id
        return true
    }

    /** Fechou de qualquer jeito (Entendi, Pular, voltar, toque fora ou arrastar): conta como vista */
    fun finish(env: AppEnv, tip: ScreenTip) {
        marked += tip.id
        if (showing == tip.id) showing = null
        edit(env) { copy -> ScreenTips.markSeen(tip.id, ProfileEdits.settings(copy)[ScreenTips.KEY] as? String)?.let { ProfileEdits.set(copy, ScreenTips.KEY, it) } ?: copy }
    }

    /** "Rever dicas das telas" nos Ajustes */
    fun reset(env: AppEnv) {
        marked.clear()
        edit(env) { copy -> ProfileEdits.set(copy, ScreenTips.KEY, null) }
    }

    private fun edit(env: AppEnv, change: (kotlinx.serialization.json.JsonObject) -> kotlinx.serialization.json.JsonObject) {
        if ((env.copies.state.value as? CopyState.Ready)?.copy == null) return
        scope.launch { env.copies.edit { copy -> copy?.let(change) ?: com.alonsoalmeida.gymbros.domain.backup.AccountEdits.empty("", Instant.now()) } }
    }
}

/**
 * Mostra a dica da tela na primeira vez que ela aparece (`.screenTip` do iOS), 700 ms depois de a tela ficar à vista.
 * Só com a cópia da conta pronta, o app na frente e a janela da tela com o foco: folha, modal, menu ou outra dica por
 * cima tiram o foco e seguram a dica; numa aba escondida também não aparece. `blocked`: a tela está abrindo algo que não é janela própria.
 */
@Composable
fun ScreenTipHost(env: AppEnv, tip: ScreenTip, blocked: Boolean = false) {
    val state by env.copies.state.collectAsStateWithLifecycle()
    val copy = (state as? CopyState.Ready)?.copy
    val settings = remember(copy) { ProfileEdits.settings(copy) }
    val focused = LocalWindowInfo.current.isWindowFocused && com.alonsoalmeida.gymbros.ui.map.LocalTabVisible.current
    val resumed = LocalLifecycleOwner.current.lifecycle.currentStateAsState().value.isAtLeast(Lifecycle.State.RESUMED)
    var presented by remember(tip.id) { mutableStateOf(false) }
    val ready = copy != null && focused && resumed && !blocked && !presented && ScreenTipCenter.canShow(tip, settings)
    LaunchedEffect(ready) {
        if (!ready) return@LaunchedEffect
        delay(ScreenTipCenter.DELAY_MS)
        if (ScreenTipCenter.claim(tip, settings)) presented = true
    }
    val shown by rememberUpdatedState(presented)
    DisposableEffect(tip.id) { onDispose { if (shown) ScreenTipCenter.finish(env, tip) } }
    if (presented) {
        val close = { presented = false; ScreenTipCenter.finish(env, tip) }
        GMSheet(onDismiss = close) { ScreenTipSheet(tip, close) }
    }
}

/** Folha paginada (ScreenTipView.swift `ScreenTipSheet`): selo, cartões de 2 a 4, bolinhas e Pular/Avançar, Voltar/Entendi */
@Composable
private fun ScreenTipSheet(tip: ScreenTip, close: () -> Unit) {
    val haptic = LocalHapticFeedback.current
    var index by rememberSaveable(tip.id) { mutableIntStateOf(0) }
    val isLast = index == tip.cards.size - 1
    val go: (Int) -> Unit = { i ->
        if (i in tip.cards.indices && i != index) {
            haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
            index = i
        }
    }

    Column(Modifier.fillMaxWidth().padding(horizontal = 4.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
        Row(
            Modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = "Dica da tela ${tip.screen}" },
            horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Filled.Lightbulb, null, tint = GMColors.accent, modifier = Modifier.size(14.dp))
            Text("DICA · ${tip.screen.uppercase()}", color = GMColors.dim, style = GMType.caption.copy(fontWeight = FontWeight.Bold, letterSpacing = 0.6.sp))
        }

        // Todos os cartões empilhados: a folha fica com a altura do maior e não pula ao trocar
        Box(Modifier.fillMaxWidth().pointerInput(tip.id) {
            var dx = 0f
            detectHorizontalDragGestures(
                onDragStart = { dx = 0f },
                onDragEnd = { if (kotlin.math.abs(dx) > 50.dp.toPx()) go(if (dx < 0) index + 1 else index - 1) },
            ) { _, amount -> dx += amount }
        }) {
            tip.cards.forEachIndexed { i, card -> TipCard(card, i, index, tip.cards.size) }
        }

        if (tip.cards.size > 1) PageDots(index, tip.cards.size, go)

        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            when {
                isLast && index > 0 -> GMButton("Voltar", { go(index - 1) }, Modifier.weight(1f), icon = Icons.Filled.ChevronLeft, kind = GMButtonKind.GHOST)
                !isLast -> GMButton("Pular", close, Modifier.weight(1f), kind = GMButtonKind.GHOST)
            }
            GMButton(if (isLast) "Entendi" else "Avançar", { if (isLast) close() else go(index + 1) }, Modifier.weight(1f),
                     icon = if (isLast) Icons.Filled.Check else Icons.Filled.ChevronRight)
        }
    }
}

@Composable
private fun TipCard(card: ScreenTipCard, i: Int, index: Int, count: Int) {
    val alpha by animateFloatAsState(if (i == index) 1f else 0f, tween(280), label = "tipAlpha")
    val shift by animateDpAsState(if (i == index) 0.dp else if (i < index) (-24).dp else 24.dp, tween(280), label = "tipShift")
    Row(
        Modifier.fillMaxWidth().graphicsLayer { this.alpha = alpha; translationX = shift.toPx() }
            .then(if (i == index) Modifier.semantics(mergeDescendants = true) {
                if (count > 1) stateDescription = "${i + 1} de $count"
            } else Modifier.clearAndSetSemantics {}),
        horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.Top,
    ) {
        Box(Modifier.size(52.dp).background(Brush.verticalGradient(listOf(GMColors.accent, GMColors.accent.copy(alpha = 0.8f))), GMRadius.m),
            contentAlignment = Alignment.Center) {
            Icon(ScreenTipIcons.of(card.symbol), null, tint = Color.Black, modifier = Modifier.size(26.dp))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(card.title, color = Color.White, style = GMType.title3.copy(fontWeight = FontWeight.Bold), modifier = Modifier.semantics { heading() })
            Text(card.text, color = Color.White.copy(alpha = 0.85f), style = GMType.subheadline)
        }
    }
}

@Composable
private fun PageDots(index: Int, count: Int, go: (Int) -> Unit) {
    Row(
        Modifier.fillMaxWidth().semantics(mergeDescendants = true) {
            contentDescription = "Dica ${index + 1} de $count"
            customActions = listOf(
                CustomAccessibilityAction("Próxima") { go(index + 1); true },
                CustomAccessibilityAction("Anterior") { go(index - 1); true },
            )
        },
        horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
    ) {
        repeat(count) { i ->
            val w by animateDpAsState(if (i == index) 18.dp else 7.dp, label = "dot")
            Box(Modifier.width(w).height(7.dp).background(if (i == index) GMColors.accent else GMColors.track, CircleShape))
        }
    }
}

/** SF Symbols do catálogo → Material */
private object ScreenTipIcons {
    fun of(symbol: String): ImageVector = when (symbol) {
        "square.grid.3x3.fill" -> Icons.Filled.GridView
        "star.fill" -> Icons.Filled.Star
        "flag.fill" -> Icons.Filled.Flag
        "arrow.left.arrow.right" -> Icons.Filled.SwapHoriz
        "book.closed.fill" -> Icons.AutoMirrored.Filled.MenuBook
        "sparkles" -> Icons.Filled.AutoAwesome
        "arrow.triangle.branch" -> Icons.Filled.AccountTree
        "eye" -> Icons.Filled.Visibility
        "trophy.fill" -> Icons.Filled.EmojiEvents
        "ticket" -> Icons.Filled.ConfirmationNumber
        "pawprint.fill" -> Icons.Filled.Pets
        "plus.circle.fill" -> Icons.Filled.AddCircle
        "chart.bar.fill" -> Icons.Filled.BarChart
        "bubble.left.and.bubble.right" -> Icons.Filled.Forum
        "ellipsis" -> Icons.Filled.MoreHoriz
        "bolt.shield.fill" -> Icons.Filled.Shield
        "clock" -> Icons.Filled.Schedule
        "medal.fill" -> Icons.Filled.MilitaryTech
        "lock.fill" -> Icons.Filled.Lock
        "gift.fill" -> Icons.Filled.CardGiftcard
        "person.2.fill" -> Icons.Filled.Group
        "hand.tap.fill" -> Icons.Filled.TouchApp
        "rectangle.stack.fill" -> Icons.Filled.Layers
        "hand.draw.fill" -> Icons.Filled.Swipe
        "arrowshape.turn.up.left" -> Icons.AutoMirrored.Filled.Reply
        "dumbbell.fill" -> Icons.Filled.FitnessCenter
        "gearshape" -> Icons.Filled.Settings
        "figure.run" -> Icons.AutoMirrored.Filled.DirectionsRun
        "mappin.and.ellipse" -> Icons.Filled.Place
        "list.bullet" -> Icons.AutoMirrored.Filled.List
        "checkmark.circle.fill" -> Icons.Filled.CheckCircle
        "flame.fill" -> Icons.Filled.LocalFireDepartment
        "timer" -> Icons.Filled.Timer
        "doc.on.clipboard" -> Icons.Filled.ContentPaste
        "chart.line.uptrend.xyaxis" -> Icons.AutoMirrored.Filled.TrendingUp
        "bell.badge.fill" -> Icons.Filled.NotificationsActive
        "envelope.fill" -> Icons.Filled.Email
        "archivebox" -> Icons.Filled.Archive
        "square.and.arrow.up" -> Icons.Filled.Publish
        "scalemass.fill" -> Icons.Filled.Scale
        "heart" -> Icons.Filled.Favorite
        else -> Icons.Filled.Lightbulb
    }
}
