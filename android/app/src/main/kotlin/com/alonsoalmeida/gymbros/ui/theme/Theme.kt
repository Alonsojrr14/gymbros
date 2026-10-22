package com.alonsoalmeida.gymbros.ui.theme

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

/**
 * Tokens de ios/Shared/Theme.swift, com as mesmas frações RGB (não o hex arredondado). O app é sempre escuro e não usa
 * cor dinâmica: a marca é fixa (ADR-005).
 */
object GMColors {
    val bg = Color(red = 0.05f, green = 0.06f, blue = 0.08f)
    val card = Color(red = 0.10f, green = 0.11f, blue = 0.14f)
    val accent = Color(red = 0.64f, green = 0.90f, blue = 0.21f)
    /** Texto sobre o verde é preto */
    val onAccent = Color.Black
    val dim = Color.White.copy(alpha = 0.55f)
    val raised = Color.White.copy(alpha = 0.06f)
    val stroke = Color.White.copy(alpha = 0.08f)
    val track = Color.White.copy(alpha = 0.1f)
    val danger = Color(red = 1.0f, green = 0.38f, blue = 0.38f)
    val online = Color(red = 0.25f, green = 0.88f, blue = 0.42f)
    val video = Color(red = 0.9f, green = 0.2f, blue = 0.2f)

    // Cores do sistema que o iOS usa sem valor fixo: os valores do iOS no modo escuro (o único do app). Decisão de design, revisável.
    val streak = Color(0xFFFF9F0A)
    val warning = Color(0xFFFF9F0A)
    val info = Color(0xFF64D2FF)
    val trophy = Color(0xFFFFD60A)
    val note = Color(0xFFFFD60A)
    val health = Color(0xFFFF375F)
    val badge = Color(0xFFFF453A)
}

/** Raios de ios/GymBros/DesignSystem/DesignSystem.swift */
object GMRadius {
    val xs = RoundedCornerShape(4.dp)
    val s = RoundedCornerShape(10.dp)
    val m = RoundedCornerShape(12.dp)
    val l = RoundedCornerShape(16.dp)
    val card = RoundedCornerShape(20.dp)
    val xl = RoundedCornerShape(28.dp)
}

@Composable
fun GymBrosTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = darkColorScheme(
            primary = GMColors.accent,
            onPrimary = GMColors.onAccent,
            background = GMColors.bg,
            surface = GMColors.card,
            error = GMColors.danger,
        ),
        content = content,
    )
}
