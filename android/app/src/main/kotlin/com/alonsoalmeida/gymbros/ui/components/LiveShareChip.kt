package com.alonsoalmeida.gymbros.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Sensors
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.alonsoalmeida.gymbros.data.live.LiveShareStore
import com.alonsoalmeida.gymbros.ui.AppEnv
import com.alonsoalmeida.gymbros.ui.copy
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMType

/**
 * Chip ao lado do lugar, no começo de cada treino (LiveShare.swift `LiveShareChip`): toque liga ou desliga o ao vivo só
 * para este treino. A escolha vai nos ajustes da conta (`shareLiveWorkouts`), como no iPhone.
 */
@Composable
fun LiveShareChip(env: AppEnv, workoutID: String, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val haptic = LocalHapticFeedback.current
    val saved = LiveShareStore.isSharing(env.copy(), workoutID)
    // O toque vale na hora; a cópia da conta confirma logo depois
    var chosen by remember(workoutID) { mutableStateOf<Boolean?>(null) }
    LaunchedEffect(saved) { if (chosen == saved) chosen = null }
    val on = chosen ?: saved
    fun toggle() {
        chosen = !on
        LiveShareStore.set(context, workoutID, !on)
        haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
    }
    val tint = if (on) GMColors.accent else Color.White
    Row(
        modifier.heightIn(min = 32.dp).gmPress(onClick = ::toggle)
            .background(if (on) GMColors.accent.copy(alpha = 0.18f) else GMColors.raised, CircleShape)
            .padding(horizontal = 12.dp, vertical = 6.dp)
            .clearAndSetSemantics {
                role = Role.Button
                contentDescription = if (on) "Treino ao vivo para amigos, ligado" else "Treino ao vivo para amigos, desligado"
                onClick(label = "${if (on) "não compartilhar" else "compartilhar"} a sua localização neste treino") { toggle(); true }
            },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Icon(if (on) Icons.Filled.Sensors else Icons.Filled.VisibilityOff, null, tint = tint, modifier = Modifier.size(14.dp))
        Text(if (on) "Ao vivo para amigos" else "Só você", color = tint, style = GMType.caption.copy(fontWeight = FontWeight.Bold), maxLines = 1)
    }
}
