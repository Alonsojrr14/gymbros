package com.alonsoalmeida.gymbros.ui

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.alonsoalmeida.gymbros.data.AccountCopyRepository
import com.alonsoalmeida.gymbros.data.CopyState
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.json.JsonObject

/**
 * O que toda tela recebe: a conta aberta e a cópia de trabalho da conta (o JSON inteiro do `Backup` do iOS).
 * Ler: `env.copy()` (muda sozinho quando a conta muda aqui ou chega do iPhone ao vivo).
 * Gravar: `env.copies.edit { copy -> ... }` devolvendo o JSON novo (preserve o que não conhece; ids em UUID maiúsculo).
 */
class AppEnv(
    val uid: String,
    val name: String,
    val email: String,
    val copies: AccountCopyRepository,
    val context: Context,
    val signOut: () -> Unit,
    val signOutError: StateFlow<String?>,
)

@Composable
fun AppEnv.copy(): JsonObject? = (copies.state.collectAsStateWithLifecycle().value as? CopyState.Ready)?.copy
