package com.alonsoalmeida.gymbros.ui.main

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.FitnessCenter
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.ViewAgenda
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.hideFromAccessibility
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.alonsoalmeida.gymbros.domain.Attribute
import com.alonsoalmeida.gymbros.domain.MonsterForm
import com.alonsoalmeida.gymbros.ui.components.GMEmptyState
import com.alonsoalmeida.gymbros.ui.components.GMScreen
import com.alonsoalmeida.gymbros.ui.components.MonsterSprite
import com.alonsoalmeida.gymbros.ui.components.gmPress
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.color

private data class TabItem(val icon: ImageVector, val title: String, val tag: Int)

/**
 * Abas do app (App.swift `MainView` + DesignSystem/GMTabBar.swift): Feed e Treino à esquerda, o bro no meio (início),
 * Ligas e Mapa à direita. Cada aba é criada na primeira visita e continua viva (guarda a rolagem).
 */
@Composable
fun MainScreen(form: MonsterForm, home: @Composable () -> Unit, feed: @Composable () -> Unit) {
    var tab by rememberSaveable { mutableIntStateOf(0) }
    var visited by rememberSaveable { mutableStateOf(listOf(0)) }
    Box(Modifier.fillMaxSize().background(GMColors.bg)) {
        for (i in 0..4) {
            if (i !in visited && i != tab) continue
            val on = tab == i
            Box(Modifier.fillMaxSize().graphicsLayer { alpha = if (on) 1f else 0f }
                    .then(if (on) Modifier else Modifier.semantics { hideFromAccessibility() })) {
                when (i) {
                    0 -> home()
                    1 -> Soon("Treino", Icons.Filled.FitnessCenter, "Rotinas, treino guiado e WOD estão chegando no Android.")
                    2 -> Soon("Ligas", Icons.Filled.EmojiEvents, "Ligas, X1 e ranking estão chegando no Android.")
                    3 -> Soon("Mapa", Icons.Filled.Map, "Academias, amigos ao vivo e rotas estão chegando no Android.")
                    4 -> feed()
                }
            }
        }
        GMTabBar(
            left = listOf(TabItem(Icons.Filled.ViewAgenda, "Feed", 4), TabItem(Icons.Filled.FitnessCenter, "Treino", 1)),
            right = listOf(TabItem(Icons.Filled.EmojiEvents, "Ligas", 2), TabItem(Icons.Filled.Map, "Mapa", 3)),
            selection = tab, form = form,
            onSelect = { tab = it; if (it !in visited) visited = visited + it },
            modifier = Modifier.align(Alignment.BottomCenter),
        )
    }
}

@Composable
private fun Soon(title: String, icon: ImageVector, message: String) {
    GMScreen(title, bottomInset = 120.dp) {
        GMEmptyState(icon, "Em breve no Android", "$message No iPhone já funciona.", Modifier.padding(top = 60.dp))
    }
}

@Composable
private fun GMTabBar(left: List<TabItem>, right: List<TabItem>, selection: Int, form: MonsterForm, onSelect: (Int) -> Unit,
                     modifier: Modifier = Modifier) {
    val haptic = LocalHapticFeedback.current
    val select = { t: Int ->
        if (t != selection) haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
        onSelect(t)
    }
    Row(
        modifier.navigationBarsPadding().padding(horizontal = 14.dp, vertical = 8.dp).fillMaxWidth()
            .background(GMColors.card.copy(alpha = 0.98f), CircleShape).border(1.dp, GMColors.stroke, CircleShape).padding(5.dp),
        horizontalArrangement = Arrangement.spacedBy(2.dp), verticalAlignment = Alignment.CenterVertically,
    ) {
        for (item in left) Tab(item, item.tag == selection) { select(item.tag) }
        Center(form, selection == 0) { select(0) }
        for (item in right) Tab(item, item.tag == selection) { select(item.tag) }
    }
}

@Composable
private fun RowScope.Tab(item: TabItem, on: Boolean, onClick: () -> Unit) {
    val bg by animateColorAsState(if (on) GMColors.accent else Color.Transparent, spring(), label = "tab")
    val fg = if (on) Color.Black else Color.White.copy(alpha = 0.6f)
    Column(
        Modifier.weight(1f).gmPress(role = Role.Tab, onClick = onClick).background(bg, CircleShape).padding(vertical = 8.dp)
            .semantics { selected = on; contentDescription = item.title },
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        Icon(item.icon, null, tint = fg, modifier = Modifier.size(20.dp))
        Text(item.title, color = fg, fontSize = 10.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
    }
}

/** O bro do meio: círculo com anel colorido, sobe 16 acima da barra e pula ao tocar */
@Composable
private fun Center(form: MonsterForm, on: Boolean, onClick: () -> Unit) {
    var bump by rememberSaveable { mutableStateOf(false) }
    val scale by animateFloatAsState(if (bump) 1.18f else 1f, spring(dampingRatio = Spring.DampingRatioMediumBouncy),
                                     label = "bump", finishedListener = { bump = false })
    Box(Modifier.width(72.dp).semantics { contentDescription = "Bro"; selected = on }, contentAlignment = Alignment.Center) {
        Box(
            Modifier.offset(y = (-16).dp).size(66.dp)
                .shadow(if (on) 14.dp else 8.dp, CircleShape, ambientColor = if (on) GMColors.accent else Color.Black,
                        spotColor = if (on) GMColors.accent else Color.Black)
                .background(if (on) GMColors.accent else GMColors.card, CircleShape)
                .border(3.dp, Brush.sweepGradient(listOf(GMColors.accent, Attribute.RESISTENCIA.color(), Attribute.TECNICA.color(),
                                                         Attribute.FORCA.color(), GMColors.accent)), CircleShape)
                .gmPress(role = Role.Tab) { bump = true; onClick() },
            contentAlignment = Alignment.Center,
        ) { MonsterSprite(form, Modifier.size(48.dp).graphicsLayer { scaleX = scale; scaleY = scale }) }
    }
}

/** "Em breve" para o que ainda não chegou no Android (abre por cima de tudo) */
@Composable
fun SoonModal(title: String?, onDismiss: () -> Unit) {
    com.alonsoalmeida.gymbros.ui.components.GMModal(title != null, title.orEmpty(), onDismiss) {
        GMEmptyState(Icons.Filled.FitnessCenter, "Em breve no Android", "Esta parte do GymBros ainda está chegando no Android. No iPhone ela já funciona.")
    }
}
