package com.alonsoalmeida.gymbros.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMRadius

/** GMCard: raio 20, padding 16, fundo do card (ios/GymBros/DesignSystem/GMSurfaces.swift) */
@Composable
fun GMCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier.fillMaxWidth().background(GMColors.card, GMRadius.card).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
        content = content,
    )
}

/** GMButton principal: verde com texto preto; alvo de toque de pelo menos 48 dp */
@Composable
fun GMButton(title: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    Box(
        modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 52.dp)
            .background(GMColors.accent, GMRadius.l)
            .clickable(role = Role.Button, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(title, color = GMColors.onAccent, fontWeight = FontWeight.Bold, fontSize = 17.sp)
    }
}

/** GMEmptyState: ícone, título e mensagem, para listas vazias */
@Composable
fun GMEmptyState(icon: ImageVector, title: String, message: String, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(icon, contentDescription = null, tint = GMColors.dim)
        Text(title, fontWeight = FontWeight.Bold, fontSize = 17.sp)
        Text(message, color = GMColors.dim, fontSize = 15.sp)
    }
}
