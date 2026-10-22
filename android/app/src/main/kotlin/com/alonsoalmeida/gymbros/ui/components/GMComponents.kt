package com.alonsoalmeida.gymbros.ui.components

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMRadius
import com.alonsoalmeida.gymbros.ui.theme.GMType

/** GMPress: encolhe para 0,96 e fica 85% opaco ao toque, com mola (ios/GymBros/DesignSystem/GMButtons.swift) */
@Composable
fun Modifier.gmPress(enabled: Boolean = true, role: Role = Role.Button, onClick: () -> Unit): Modifier {
    val source = remember { MutableInteractionSource() }
    val pressed by source.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed) 0.96f else 1f, spring(), label = "press")
    val alpha by animateFloatAsState(if (pressed) 0.85f else 1f, spring(), label = "pressAlpha")
    return graphicsLayer { scaleX = scale; scaleY = scale; this.alpha = alpha }
        .clickable(interactionSource = source, indication = null, enabled = enabled, role = role, onClick = onClick)
}

enum class GMButtonKind { PRIMARY, SECONDARY, DANGER, GHOST }

/** GMButton: título em "headline", padding 15×20, raio 16; desabilitado fica com 40% de opacidade */
@Composable
fun GMButton(
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    kind: GMButtonKind = GMButtonKind.PRIMARY,
    enabled: Boolean = true,
) {
    val bg = when (kind) {
        GMButtonKind.PRIMARY -> GMColors.accent
        GMButtonKind.SECONDARY -> GMColors.raised
        GMButtonKind.DANGER -> GMColors.danger.copy(alpha = 0.15f)
        GMButtonKind.GHOST -> Color.Transparent
    }
    val fg = when (kind) {
        GMButtonKind.PRIMARY -> GMColors.onAccent
        GMButtonKind.DANGER -> GMColors.danger
        else -> Color.White
    }
    Row(
        modifier
            .fillMaxWidth()
            .graphicsLayer { alpha = if (enabled) 1f else 0.4f }
            .gmPress(enabled, onClick = onClick)
            .background(bg, GMRadius.l)
            .padding(vertical = 15.dp, horizontal = 20.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) Icon(icon, contentDescription = null, tint = fg, modifier = Modifier.size(20.dp))
        Text(title, color = fg, style = GMType.headline)
    }
}

/** GMIconButton: círculo `raised` de 40 (ícone a 42% do tamanho) */
@Composable
fun GMIconButton(icon: ImageVector, label: String, onClick: () -> Unit, size: Dp = 40.dp) {
    Box(
        Modifier.size(size).gmPress(onClick = onClick).background(GMColors.raised, CircleShape).semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) { Icon(icon, contentDescription = null, tint = Color.White, modifier = Modifier.size(size * 0.42f)) }
}

/** GMCard: padding 16, espaçamento 12, raio 20, fundo do card */
@Composable
fun GMCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier.fillMaxWidth().background(GMColors.card, GMRadius.card).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        content = content,
    )
}

/** GMSection: título pequeno em maiúsculas, card e rodapé (substitui as seções de formulário) */
@Composable
fun GMSection(title: String? = null, footer: String? = null, content: @Composable ColumnScope.() -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (title != null) {
            Text(title.uppercase(), color = GMColors.dim, style = GMType.caption.copy(fontWeight = FontWeight.Bold, letterSpacing = 0.6.sp),
                 modifier = Modifier.padding(horizontal = 4.dp))
        }
        GMCard(content = content)
        if (footer != null) Text(footer, color = GMColors.dim, style = GMType.caption, modifier = Modifier.padding(horizontal = 4.dp))
    }
}

/**
 * GMModal: tela cheia por cima, com o título no meio e o X à esquerda; o conteúdo rola com espaçamento 18.
 * O voltar do sistema fecha, como o gesto de arrastar no iOS.
 */
@Composable
fun GMModal(visible: Boolean, title: String, onDismiss: () -> Unit, content: @Composable ColumnScope.() -> Unit) {
    AnimatedVisibility(visible, enter = slideInVertically { it }, exit = slideOutVertically { it }) {
        BackHandler(onBack = onDismiss)
        Column(Modifier.fillMaxSize().background(GMColors.bg).safeDrawingPadding()) {
            Box(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), contentAlignment = Alignment.Center) {
                Text(title, color = Color.White, style = GMType.headline)
                Row(Modifier.fillMaxWidth()) {
                    GMIconButton(Icons.Filled.Close, "Fechar", onDismiss, size = 36.dp)
                    Spacer(Modifier.weight(1f))
                }
            }
            Column(
                Modifier.verticalScroll(rememberScrollState()).padding(16.dp).padding(bottom = 40.dp),
                verticalArrangement = Arrangement.spacedBy(18.dp),
                content = content,
            )
        }
    }
}

/** GMEmptyState: ícone, título e mensagem, para listas vazias */
@Composable
fun GMEmptyState(icon: ImageVector, title: String, message: String, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(icon, contentDescription = null, tint = GMColors.dim)
        Text(title, color = Color.White, style = GMType.headline)
        Text(message, color = GMColors.dim, style = GMType.subheadline)
    }
}

/** Linha fina com "ou" no meio */
@Composable
fun GMOrDivider() {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(Modifier.weight(1f).height(1.dp).background(GMColors.stroke))
        Text("ou", color = GMColors.dim, style = GMType.caption)
        Box(Modifier.weight(1f).height(1.dp).background(GMColors.stroke))
    }
}
