package com.alonsoalmeida.gymbros.ui.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.alonsoalmeida.gymbros.data.AuthRepository
import com.alonsoalmeida.gymbros.domain.auth.AuthException
import com.alonsoalmeida.gymbros.domain.auth.AuthRules
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class LoginUiState(
    val creating: Boolean = false,
    val name: String = "",
    val email: String = "",
    val password: String = "",
    val busy: Boolean = false,
    val error: String? = null,
    val notice: String? = null,
) {
    val canSubmit: Boolean get() = !busy && email.isNotEmpty() && password.isNotEmpty()
}

class LoginViewModel(private val auth: AuthRepository) : ViewModel() {
    private val state = MutableStateFlow(LoginUiState())
    val ui: StateFlow<LoginUiState> = state.asStateFlow()

    fun setCreating(v: Boolean) = state.update { it.copy(creating = v, error = null, notice = null) }
    fun setName(v: String) = state.update { it.copy(name = v) }
    fun setEmail(v: String) = state.update { it.copy(email = v) }
    fun setPassword(v: String) = state.update { it.copy(password = v) }

    fun submit() = work {
        val s = state.value
        if (s.creating) auth.signUp(s.name, s.email, s.password) else auth.signIn(s.email, s.password)
        null
    }

    fun forgot() = work {
        auth.resetPassword(state.value.email)
        AuthRules.resetNotice(state.value.email)
    }

    private fun work(block: suspend () -> String?) {
        if (state.value.busy) return
        state.update { it.copy(busy = true, error = null, notice = null) }
        viewModelScope.launch {
            try {
                val notice = block()
                state.update { it.copy(busy = false, notice = notice) }
            } catch (e: AuthException) {
                state.update { it.copy(busy = false, error = e.error.message) }
            } catch (e: Exception) {
                state.update { it.copy(busy = false, error = "Não deu certo agora. Tente de novo.") }
            }
        }
    }
}
