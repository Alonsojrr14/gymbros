package com.alonsoalmeida.gymbros.domain.auth

/** Erros de login com as mensagens do iOS (ios/GymBros/Services/Auth.swift `AuthError`, FirebaseBackend `FirebaseAuthError`) */
enum class AuthError(val message: String) {
    INVALID_EMAIL("E-mail inválido."),
    SHORT_PASSWORD("A senha precisa de pelo menos 8 caracteres."),
    MISSING_NAME("Diga seu nome."),
    WRONG_PASSWORD("E-mail ou senha incorretos."),
    EMAIL_IN_USE("Esse e-mail já tem conta. Entre com a senha."),
    OFFLINE("Sem conexão. Tente de novo."),
    EMPTY_EMAIL_FOR_RESET("Digite seu e-mail acima e toque de novo."),
}

class AuthException(val error: AuthError) : Exception(error.message)

/** Validações do formulário, iguais às do iOS (`AuthStore.clean`, `validate`, `signUp`) */
object AuthRules {
    const val MIN_PASSWORD = 8

    fun clean(email: String): String = email.trim().lowercase()

    fun validate(email: String, password: String) {
        val e = clean(email)
        val parts = e.split("@")
        val ok = parts.size == 2 && parts[0].isNotEmpty() && parts[1].contains(".") && !parts[1].endsWith(".") && !e.contains(" ")
        if (!ok) throw AuthException(AuthError.INVALID_EMAIL)
        if (password.length < MIN_PASSWORD) throw AuthException(AuthError.SHORT_PASSWORD)
    }

    fun validateSignUp(name: String, email: String, password: String) {
        if (name.isBlank()) throw AuthException(AuthError.MISSING_NAME)
        validate(email, password)
    }

    /** Por segurança o Firebase não diz se o e-mail tem conta: a mensagem é a mesma */
    fun resetNotice(email: String): String =
        "Se ${clean(email)} tiver conta, chega um link para criar uma senha nova. Veja também o spam."
}
