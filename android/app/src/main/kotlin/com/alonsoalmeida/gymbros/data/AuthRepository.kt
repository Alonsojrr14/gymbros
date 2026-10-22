package com.alonsoalmeida.gymbros.data

import com.alonsoalmeida.gymbros.domain.auth.AuthError
import com.alonsoalmeida.gymbros.domain.auth.AuthException
import com.alonsoalmeida.gymbros.domain.auth.AuthRules
import com.google.firebase.FirebaseNetworkException
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.FirebaseAuthException
import com.google.firebase.auth.FirebaseUser
import com.google.firebase.auth.userProfileChangeRequest
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.tasks.await

/** Quem está logado (o mesmo uid do iOS no Firebase) */
data class AuthUser(val id: String, val name: String, val email: String, val emailVerified: Boolean)

interface AuthRepository {
    val user: StateFlow<AuthUser?>
    suspend fun signIn(email: String, password: String)
    suspend fun signUp(name: String, email: String, password: String)
    suspend fun resetPassword(email: String)
    fun signOut()
}

/** Login por e-mail e senha no Firebase, igual ao iOS (ios/GymBros/Services/FirebaseBackend.swift `FirebaseAuthBackend`) */
class FirebaseAuthRepository(private val auth: FirebaseAuth = FirebaseAuth.getInstance()) : AuthRepository {
    private val state = MutableStateFlow(auth.currentUser?.toUser())
    override val user: StateFlow<AuthUser?> = state.asStateFlow()

    init {
        // A sessão do Firebase sobrevive a fechar o app; mudanças (sair, token expirado) chegam aqui
        auth.addAuthStateListener { state.value = it.currentUser?.toUser() }
    }

    override suspend fun signIn(email: String, password: String) {
        AuthRules.validate(email, password)
        run { auth.signInWithEmailAndPassword(AuthRules.clean(email), password).await() }
    }

    override suspend fun signUp(name: String, email: String, password: String) {
        AuthRules.validateSignUp(name, email, password)
        val result = run { auth.createUserWithEmailAndPassword(AuthRules.clean(email), password).await() }
        val user = result.user ?: return
        runCatching { user.updateProfile(userProfileChangeRequest { displayName = name.trim() }).await() }
        auth.setLanguageCode("pt-BR")
        runCatching { user.sendEmailVerification().await() }
        state.value = user.toUser(name.trim())
    }

    override suspend fun resetPassword(email: String) {
        if (email.isBlank()) throw AuthException(AuthError.EMPTY_EMAIL_FOR_RESET)
        auth.setLanguageCode("pt-BR")
        run { auth.sendPasswordResetEmail(AuthRules.clean(email)).await() }
    }

    override fun signOut() = auth.signOut()

    /** Erros do Firebase com as mensagens do app (com a proteção contra enumeração, senha errada e conta inexistente são iguais) */
    private suspend fun <T> run(block: suspend () -> T): T = try {
        block()
    } catch (e: FirebaseNetworkException) {
        throw AuthException(AuthError.OFFLINE)
    } catch (e: FirebaseAuthException) {
        throw AuthException(
            when (e.errorCode) {
                "ERROR_EMAIL_ALREADY_IN_USE" -> AuthError.EMAIL_IN_USE
                "ERROR_INVALID_EMAIL" -> AuthError.INVALID_EMAIL
                "ERROR_WEAK_PASSWORD" -> AuthError.SHORT_PASSWORD
                else -> AuthError.WRONG_PASSWORD
            },
        )
    }

    private fun FirebaseUser.toUser(name: String? = null) =
        AuthUser(id = uid, name = name ?: displayName.orEmpty(), email = email.orEmpty(), emailVerified = isEmailVerified)
}
