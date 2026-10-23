package com.alonsoalmeida.gymbros

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Text
import androidx.compose.ui.graphics.Color
import com.alonsoalmeida.gymbros.ui.components.GMIconButton
import com.alonsoalmeida.gymbros.ui.components.GMScreen
import com.alonsoalmeida.gymbros.ui.components.GMSection
import com.alonsoalmeida.gymbros.ui.legal.Legal
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMType
import com.alonsoalmeida.gymbros.ui.theme.GymBrosTheme

/**
 * Política de privacidade aberta pelo Health Connect ("Por que o GymBros pede isso?"), exigida para pedir permissões de
 * saúde (SEC-AND-05). Só mostra o texto; não lê nem grava nada.
 */
class HealthRationaleActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge(statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
                         navigationBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT))
        super.onCreate(savedInstanceState)
        setContent {
            GymBrosTheme {
                GMScreen("Privacidade", leading = { GMIconButton(Icons.Filled.Close, "Fechar", { finish() }) }) {
                    GMSection(footer = "Do Health Connect, o GymBros só lê treinos, calorias, distância e peso, para transformá-los em atividades e no gráfico de peso. Nada disso vai para posts nem para o X1.") {
                        Text("O que o GymBros faz com os dados de saúde", color = Color.White, style = GMType.headline)
                    }
                    for ((title, body) in Legal.privacy.sections) {
                        GMSection(title) { Text(body, color = GMColors.dim, style = GMType.footnote) }
                    }
                }
            }
        }
    }
}
