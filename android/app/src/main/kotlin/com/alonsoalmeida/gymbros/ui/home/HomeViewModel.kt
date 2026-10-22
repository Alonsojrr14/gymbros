package com.alonsoalmeida.gymbros.ui.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.alonsoalmeida.gymbros.data.AccountCopyRepository
import com.alonsoalmeida.gymbros.data.CopyState
import com.alonsoalmeida.gymbros.domain.RuleClock
import com.alonsoalmeida.gymbros.domain.backup.AccountCopy
import com.alonsoalmeida.gymbros.domain.backup.AccountEdits
import com.alonsoalmeida.gymbros.domain.home.HomeBuilder
import com.alonsoalmeida.gymbros.domain.home.HomeData
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId

/** Fases da abertura da conta, como o `AccountSync.phase` do iOS */
sealed interface AccountState {
    data object Loading : AccountState
    data class Failed(val message: String) : AccountState
    data class Ready(val home: HomeData) : AccountState
}

/** A conta aberta: a tela inicial acompanha a cópia de trabalho, que muda aqui e chega ao vivo do outro aparelho */
class HomeViewModel(private val uid: String, private val name: String, private val copies: AccountCopyRepository) : ViewModel() {
    val account: StateFlow<AccountState> = copies.state.map { s ->
        when (s) {
            CopyState.Loading -> AccountState.Loading
            is CopyState.Failed -> AccountState.Failed(s.message)
            // XP do dia e sequência no fuso do aparelho, como o Calendar.current do iOS
            is CopyState.Ready -> AccountState.Ready(HomeBuilder.build(s.copy?.let(AccountCopy::decode), RuleClock(ZoneId.systemDefault(), Instant.now())))
        }
    }.flowOn(Dispatchers.Default).stateIn(viewModelScope, SharingStarted.Eagerly, AccountState.Loading)

    private val _signOutError = MutableStateFlow<String?>(null)
    val signOutError: StateFlow<String?> = _signOutError.asStateFlow()

    init {
        copies.start(uid)
    }

    fun retry() = copies.retry()

    fun addActivity(a: AccountEdits.NewActivity) {
        viewModelScope.launch {
            copies.edit { copy -> AccountEdits.addActivity(copy ?: AccountEdits.empty(name, Instant.now()), a) }
        }
    }

    /** Sobe o que falta antes de sair; sem conseguir subir, a sessão continua (igual ao iOS) */
    fun signOut(done: () -> Unit) {
        viewModelScope.launch {
            _signOutError.value = null
            runCatching { copies.signOut() }
                .onSuccess { done() }
                .onFailure { _signOutError.value = "Não deu para salvar seus dados na nuvem. Confira a internet e tente de novo." }
        }
    }
}
