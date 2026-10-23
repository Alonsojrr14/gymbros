package com.alonsoalmeida.gymbros.ui.settings

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.alonsoalmeida.gymbros.data.AccountCopyRepository
import com.alonsoalmeida.gymbros.data.account.AccountDeletion
import com.alonsoalmeida.gymbros.data.health.HealthConnectSync
import com.alonsoalmeida.gymbros.ui.AppEnv
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** Health Connect na tela de Ajustes (HealthSettingsPage) */
data class HealthUiState(
    val available: Boolean = false,
    val needsUpdate: Boolean = false,
    val enabled: Boolean = false,
    val syncing: Boolean = false,
    val status: String? = null,
)

data class AccountUiState(val deleting: Boolean = false, val message: String? = null)

/** Ajustes: Health Connect (importar treinos e peso) e excluir a conta */
class SettingsViewModel(context: Context, copies: AccountCopyRepository) : ViewModel() {
    val health = HealthConnectSync(context, copies)
    private val deletion = AccountDeletion(context, copies)

    private val _health = MutableStateFlow(HealthUiState())
    val healthState: StateFlow<HealthUiState> = _health.asStateFlow()

    private val _account = MutableStateFlow(AccountUiState())
    val accountState: StateFlow<AccountUiState> = _account.asStateFlow()

    init { refresh() }

    fun refresh() {
        _health.update { it.copy(available = health.available, needsUpdate = health.needsUpdate, enabled = health.available && health.enabled) }
    }

    /** Desligar não apaga nada; ligar pede a permissão (a tela abre o pedido) e importa */
    fun turnOff() {
        health.enabled = false
        _health.update { it.copy(enabled = false, status = "Desligado. O que já foi importado continua.") }
    }

    /** Resposta do pedido de permissão do Health Connect */
    fun onPermissions(granted: Set<String>) {
        if (HealthConnectSync.WORKOUTS !in granted) {
            _health.update { it.copy(enabled = false, status = "Sem acesso aos treinos do Health Connect. Dá para permitir no app Health Connect → Permissões do app → GymBros.") }
            return
        }
        health.enabled = true
        _health.update { it.copy(enabled = true) }
        syncNow()
    }

    suspend fun hasAccess(): Boolean = health.hasAccess()

    fun syncNow() = viewModelScope.launch {
        _health.update { it.copy(syncing = true) }
        val status = runCatching { health.sync(force = true) }.fold(
            onSuccess = { r ->
                val parts = mutableListOf(if (r.imported == 0) "Nenhum treino novo" else "${r.imported} treino(s) importado(s)")
                if (r.skippedOverlap > 0) parts += "${r.skippedOverlap} já registrado(s) aqui"
                parts.joinToString(", ") + ". Se esperava algo, confira no app Health Connect → Permissões do app → GymBros."
            },
            onFailure = { "Falha ao sincronizar: ${it.message ?: "tente de novo."}" },
        )
        _health.update { it.copy(syncing = false, status = status) }
    }

    /** Ao abrir o app (HealthSync ao entrar em primeiro plano): só com o importar ligado e a permissão dada */
    fun autoSync() = viewModelScope.launch {
        if (!health.available || !health.enabled) return@launch
        runCatching { health.sync() }
    }

    /** Peso e medidas → "Importar peso": devolve a mensagem */
    suspend fun importWeights(): String = runCatching { health.importWeights() }.fold(
        onSuccess = { n -> if (n == 0) "Nada novo no Health Connect." else "$n registro${if (n == 1) "" else "s"} de peso importado${if (n == 1) "" else "s"}." },
        onFailure = { "Não consegui ler o Health Connect: ${it.message ?: "tente de novo."}" },
    )

    fun deleteAccount(friendCode: String?) = viewModelScope.launch {
        _account.value = AccountUiState(deleting = true)
        runCatching { deletion.delete(friendCode) }
            .onSuccess { _account.value = AccountUiState() }
            .onFailure { _account.value = AccountUiState(message = "Não deu para excluir a conta: ${it.message} Nada foi apagado; tente de novo.") }
    }
}

@Composable
fun settingsViewModel(env: AppEnv): SettingsViewModel =
    viewModel(key = "settings-${env.uid}", factory = viewModelFactory { initializer { SettingsViewModel(env.context, env.copies) } })
