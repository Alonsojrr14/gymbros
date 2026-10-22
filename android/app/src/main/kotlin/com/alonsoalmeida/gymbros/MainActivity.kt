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
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.alonsoalmeida.gymbros.data.AuthRepository
import com.alonsoalmeida.gymbros.data.AuthUser
import com.alonsoalmeida.gymbros.ui.auth.LoginScreen
import com.alonsoalmeida.gymbros.ui.auth.LoginViewModel
import com.alonsoalmeida.gymbros.ui.components.GMButton
import com.alonsoalmeida.gymbros.ui.components.GMCard
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GymBrosTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Sempre escuro: ícones claros nas barras do sistema
        enableEdgeToEdge(statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
                         navigationBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT))
        super.onCreate(savedInstanceState)
        val auth = (application as GymBrosApp).container.auth
        setContent { GymBrosTheme { Root(auth) } }
    }
}

/** Portões da raiz, como o RootView do iOS: sem sessão → login (a conta é obrigatória). Os próximos vêm com a cópia da conta. */
@Composable
private fun Root(auth: AuthRepository) {
    val user by auth.user.collectAsStateWithLifecycle()
    val current = user
    if (current == null) {
        LoginScreen(viewModel(factory = viewModelFactory { initializer { LoginViewModel(auth) } }))
    } else {
        SignedIn(current, onSignOut = auth::signOut)
    }
}

/** Provisório até a cópia da conta (AND-011): mostra quem entrou */
@Composable
private fun SignedIn(user: AuthUser, onSignOut: () -> Unit) {
    Column(
        Modifier.fillMaxSize().background(GMColors.bg).safeDrawingPadding().padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text("GymBros", color = GMColors.accent, fontWeight = FontWeight.Black, fontSize = 34.sp)
        GMCard {
            Text(user.name.ifEmpty { "Sua conta" }, color = Color.White, fontWeight = FontWeight.Bold, fontSize = 17.sp)
            Text(user.email, color = GMColors.dim)
            if (!user.emailVerified) Text("Confirme seu e-mail pelo link que enviamos.", color = GMColors.warning, fontSize = 15.sp)
        }
        Text("Seus treinos e bros chegam na próxima etapa (cópia da conta).", color = GMColors.dim, fontSize = 15.sp)
        GMButton("Sair", onClick = onSignOut)
    }
}
