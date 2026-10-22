package com.alonsoalmeida.gymbros.ui.settings

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.graphics.Color
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.alonsoalmeida.gymbros.domain.home.HomeData
import com.alonsoalmeida.gymbros.ui.AppEnv
import com.alonsoalmeida.gymbros.ui.components.GMButton
import com.alonsoalmeida.gymbros.ui.components.GMButtonKind
import com.alonsoalmeida.gymbros.ui.components.GMModal
import com.alonsoalmeida.gymbros.ui.components.GMSection
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMType

/** Ajustes (a engrenagem: App/SettingsView.swift). Por enquanto só a conta; ponto de encaixe da frente de ajustes. */
@Composable
fun SettingsModal(visible: Boolean, env: AppEnv, home: HomeData, onDismiss: () -> Unit) {
    val error by env.signOutError.collectAsStateWithLifecycle()
    GMModal(visible, "Ajustes", onDismiss) {
        GMSection("Conta") { Text(env.email, color = Color.White, style = GMType.body) }
        GMButton("Sair", env.signOut, icon = Icons.AutoMirrored.Filled.Logout, kind = GMButtonKind.DANGER)
        error?.let { Text(it, color = GMColors.danger, style = GMType.footnote) }
    }
}
