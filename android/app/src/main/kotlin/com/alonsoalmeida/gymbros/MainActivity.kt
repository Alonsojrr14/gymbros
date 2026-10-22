package com.alonsoalmeida.gymbros

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.Text
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.alonsoalmeida.gymbros.domain.ActivityKind
import com.alonsoalmeida.gymbros.domain.Game
import com.alonsoalmeida.gymbros.ui.components.GMButton
import com.alonsoalmeida.gymbros.ui.components.GMCard
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GymBrosTheme

/**
 * Fundação (AND-005): tema, edge-to-edge e componentes base. As telas de verdade vêm nas tarefas AND-010 em diante,
 * depois do login (que precisa do app registrado no Firebase).
 */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Sempre escuro: ícones claros nas barras do sistema
        enableEdgeToEdge(statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
                         navigationBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT))
        super.onCreate(savedInstanceState)
        setContent {
            GymBrosTheme {
                Column(
                    Modifier.fillMaxSize().background(GMColors.bg).safeDrawingPadding().padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    Text("GymBros", color = GMColors.accent, fontWeight = FontWeight.Black, fontSize = 34.sp)
                    GMCard {
                        Text("Fundação Android", fontWeight = FontWeight.Bold, fontSize = 17.sp, color = androidx.compose.ui.graphics.Color.White)
                        Text("60 min de musculação, esforço 5 = ${Game.xp(ActivityKind.MUSCULACAO, 60, 5)} XP (igual ao iPhone)", color = GMColors.dim)
                    }
                    GMButton("Em breve: entrar", onClick = {})
                }
            }
        }
    }
}
