package com.alonsoalmeida.gymbros

import android.content.Intent
import android.os.Bundle
import com.alonsoalmeida.gymbros.data.train.LiveWorkout
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
        // Toque na notificação do treino em andamento: abre o treino (só na primeira criação, não ao girar a tela)
        if (savedInstanceState == null) { LiveWorkout.take(intent); com.alonsoalmeida.gymbros.data.route.RouteRecorder.take(intent) }
        setContent { GymBrosTheme { Root(container) } }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        LiveWorkout.take(intent)
        // "Encerrar" na notificação do percurso: abre na conclusão
        com.alonsoalmeida.gymbros.data.route.RouteRecorder.take(intent)
    }
}

/** Portões da raiz, como o RootView do iOS: sem sessão → login (a conta é obrigatória); depois, abrir a conta e o início */
@Composable
private fun Root(container: AppContainer) {
    val user by container.auth.user.collectAsStateWithLifecycle()
    val current = user
    if (current == null) {
        // Sem conta, nenhum lembrete fica agendado (a conta é obrigatória)
        androidx.compose.runtime.LaunchedEffect(Unit) { com.alonsoalmeida.gymbros.data.reminders.LocalReminders.cancelAll(container.context) }
        LoginScreen(viewModel(factory = viewModelFactory { initializer { LoginViewModel(container.auth) } }))
    } else {
        // Um ViewModel por conta: trocar de conta nunca mostra dados da anterior
        val home: HomeViewModel = viewModel(key = "home-${current.id}", factory = viewModelFactory {
            initializer { HomeViewModel(current.id, current.name, container.copies) }
        })
        val signOut = { home.signOut { container.auth.signOut() } }
        when (val state = home.account.collectAsStateWithLifecycle().value) {
            AccountState.Loading -> AccountLoadingScreen(null, home::retry, signOut)
            is AccountState.Failed -> AccountLoadingScreen(state.message, home::retry, signOut)
            is AccountState.Ready -> {
                val friends: FriendsViewModel = viewModel(key = "friends-${current.id}", factory = viewModelFactory {
                    initializer { FriendsViewModel(FriendsRepository(), container.copies, com.alonsoalmeida.gymbros.data.ProfilePhotosRepository(container.context)) }
                })
                var soon by remember { mutableStateOf<String?>(null) }
                val env = remember(current.id) {
                    com.alonsoalmeida.gymbros.ui.AppEnv(current.id, current.name, current.email, container.copies, container.context, signOut, home.signOutError)
                }
                val data = state.home
                com.alonsoalmeida.gymbros.ui.onboarding.OnboardingGate(env, data) {
                    MainScreen(data.snapshot.form,
                               home = { HomeScreen(data, env, home::addActivity) },
                               train = { com.alonsoalmeida.gymbros.ui.train.TrainTab(env, data) },
                               leagues = { com.alonsoalmeida.gymbros.ui.leagues.LeaguesTab(env, data) },
                               map = { com.alonsoalmeida.gymbros.ui.map.MapTab(env, data) },
                               feed = { FeedScreen(data, friends, env) { soon = it } })
                    // Cenas de evolução e de chocar (App.swift `check`) e links de amigo (gymbros://amigo/CÓDIGO)
                    com.alonsoalmeida.gymbros.ui.bros.BroEventsHost(env, data)
                    com.alonsoalmeida.gymbros.ui.friends.FriendLinkHandler(data, friends)
                    // Cerca dos lugares de treino registrada a cada abertura, como o startMonitoring do iOS
                    com.alonsoalmeida.gymbros.ui.map.GymMonitor(env)
                    // Lembrete para treinar e resumo da semana, reagendados quando a conta muda (App.swift `publish`)
                    com.alonsoalmeida.gymbros.ui.settings.ReminderScheduler(env)
                    // Notificação do treino e do WOD em andamento (o Live Activity do iOS)
                    androidx.compose.runtime.LaunchedEffect(current.id) { LiveWorkout.watch(container.context) }
                    // Corrida, caminhada ou bike gravando pelo GPS: a tela fica por cima de qualquer aba
                    com.alonsoalmeida.gymbros.ui.map.RouteHost(env, data)
                }
                SoonModal(soon) { soon = null }
            }
        }
    }
}
