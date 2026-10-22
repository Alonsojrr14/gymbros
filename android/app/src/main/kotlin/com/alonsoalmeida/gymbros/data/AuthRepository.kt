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
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

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
        runCatching { EmailLinks.verify(user.getIdToken(false).await().token.orEmpty()) }
        state.value = user.toUser(name.trim())
    }

    override suspend fun resetPassword(email: String) {
        if (email.isBlank()) throw AuthException(AuthError.EMPTY_EMAIL_FOR_RESET)
        EmailLinks.reset(AuthRules.clean(email))
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

/**
 * E-mails de redefinir senha e confirmar endereço pela API REST do Firebase, com a chave na URL (igual ao iOS,
 * FirebaseEmailLinks): pelo SDK o link chega com "apiKey=" vazio e a página do Firebase dá erro. A chave é a do app Web
 * do projeto, pública por natureza; os dados ficam protegidos pelas regras.
 */
object EmailLinks {
    private const val WEB_API_KEY = "AIzaSyDpAw0dR1EvpSOJPr1SYHALpWdlYJLY1tc"

    suspend fun reset(email: String) {
        val error = send(JSONObject().put("requestType", "PASSWORD_RESET").put("email", email))
        // Sem conta com esse e-mail: a mesma resposta de quando há (não revela quem tem conta)
        if (error != null && !error.startsWith("EMAIL_NOT_FOUND")) throw AuthException(if (error.startsWith("INVALID_EMAIL")) AuthError.INVALID_EMAIL else AuthError.OFFLINE)
    }

    suspend fun verify(idToken: String) {
        send(JSONObject().put("requestType", "VERIFY_EMAIL").put("idToken", idToken))
    }

    /** null = enviado; senão a mensagem de erro do servidor */
    private suspend fun send(body: JSONObject): String? = withContext(Dispatchers.IO) {
        try {
            val c = URL("https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=$WEB_API_KEY").openConnection() as HttpURLConnection
            c.requestMethod = "POST"
            c.doOutput = true
            c.setRequestProperty("Content-Type", "application/json")
            c.setRequestProperty("X-Firebase-Locale", "pt-BR")
            c.outputStream.use { it.write(body.toString().toByteArray()) }
            if (c.responseCode == 200) null
            else JSONObject(c.errorStream?.bufferedReader()?.readText() ?: "{}").optJSONObject("error")?.optString("message").orEmpty()
        } catch (e: IOException) {
            throw AuthException(AuthError.OFFLINE)
        }
    }
}
