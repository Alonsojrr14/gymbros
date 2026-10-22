package com.alonsoalmeida.gymbros.ui.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.alonsoalmeida.gymbros.data.AccountCopyRepository
import com.alonsoalmeida.gymbros.domain.RuleClock
import com.alonsoalmeida.gymbros.domain.home.HomeBuilder
import com.alonsoalmeida.gymbros.domain.home.HomeData
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Instant
import java.time.ZoneId

/** Fases da abertura da conta, como o `AccountSync.phase` do iOS */
sealed interface AccountState {
    data object Loading : AccountState
    data class Failed(val message: String) : AccountState
    data class Ready(val home: HomeData) : AccountState
}

class HomeViewModel(private val uid: String, private val copies: AccountCopyRepository) : ViewModel() {
    private val state = MutableStateFlow<AccountState>(AccountState.Loading)
    val account: StateFlow<AccountState> = state.asStateFlow()

    init {
        load()
    }

    fun load() {
        state.value = AccountState.Loading
        viewModelScope.launch {
            state.value = try {
                val copy = copies.load(uid)
                // XP do dia e sequência no fuso do aparelho, como o Calendar.current do iOS
                AccountState.Ready(withContext(Dispatchers.Default) { HomeBuilder.build(copy, RuleClock(ZoneId.systemDefault(), Instant.now())) })
            } catch (e: Exception) {
                AccountState.Failed("Confira a internet e tente de novo.")
            }
        }
    }
}
