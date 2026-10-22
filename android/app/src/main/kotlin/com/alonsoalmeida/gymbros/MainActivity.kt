package com.alonsoalmeida.gymbros

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.alonsoalmeida.gymbros.ui.auth.LoginScreen
import com.alonsoalmeida.gymbros.ui.auth.LoginViewModel
import com.alonsoalmeida.gymbros.ui.home.AccountLoadingScreen
import com.alonsoalmeida.gymbros.ui.home.AccountState
import com.alonsoalmeida.gymbros.ui.home.HomeScreen
import com.alonsoalmeida.gymbros.ui.home.HomeViewModel
import com.alonsoalmeida.gymbros.ui.main.MainScreen
import com.alonsoalmeida.gymbros.ui.main.SoonModal
import com.alonsoalmeida.gymbros.ui.friends.FeedScreen
import com.alonsoalmeida.gymbros.ui.friends.FriendsViewModel
import com.alonsoalmeida.gymbros.data.FriendsRepository
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import com.alonsoalmeida.gymbros.ui.theme.GymBrosTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Sempre escuro: ícones claros nas barras do sistema
        enableEdgeToEdge(statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
                         navigationBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT))
        super.onCreate(savedInstanceState)
        val container = (application as GymBrosApp).container
        setContent { GymBrosTheme { Root(container) } }
    }
}

/** Portões da raiz, como o RootView do iOS: sem sessão → login (a conta é obrigatória); depois, abrir a conta e o início */
@Composable
private fun Root(container: AppContainer) {
    val user by container.auth.user.collectAsStateWithLifecycle()
    val current = user
    if (current == null) {
        LoginScreen(viewModel(factory = viewModelFactory { initializer { LoginViewModel(container.auth) } }))
    } else {
        // Um ViewModel por conta: trocar de conta nunca mostra dados da anterior
        val home: HomeViewModel = viewModel(key = "home-${current.id}", factory = viewModelFactory {
            initializer { HomeViewModel(current.id, current.name, container.copies) }
        })
        val signOutError by home.signOutError.collectAsStateWithLifecycle()
        val signOut = { home.signOut { container.auth.signOut() } }
        when (val state = home.account.collectAsStateWithLifecycle().value) {
            AccountState.Loading -> AccountLoadingScreen(null, home::retry, signOut)
            is AccountState.Failed -> AccountLoadingScreen(state.message, home::retry, signOut)
            is AccountState.Ready -> {
                val friends: FriendsViewModel = viewModel(key = "friends-${current.id}", factory = viewModelFactory {
                    initializer { FriendsViewModel(FriendsRepository(), container.copies, com.alonsoalmeida.gymbros.data.ProfilePhotosRepository(container.context)) }
                })
                var soon by remember { mutableStateOf<String?>(null) }
                MainScreen(state.home.snapshot.form,
                           home = { HomeScreen(state.home, current.email, signOutError, signOut, home::addActivity) },
                           feed = { FeedScreen(state.home, friends) { soon = it } })
                SoonModal(soon) { soon = null }
            }
        }
    }
}
