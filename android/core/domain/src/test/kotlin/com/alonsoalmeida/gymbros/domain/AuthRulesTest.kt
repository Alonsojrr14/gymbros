package com.alonsoalmeida.gymbros.domain

import com.alonsoalmeida.gymbros.domain.auth.AuthError
import com.alonsoalmeida.gymbros.domain.auth.AuthException
import com.alonsoalmeida.gymbros.domain.auth.AuthRules
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertDoesNotThrow
import org.junit.jupiter.api.assertThrows

/** Mesmas regras do formulário de login do iOS */
class AuthRulesTest {
    private fun error(block: () -> Unit) = assertThrows<AuthException>(block).error

    @Test
    fun cleansEmail() = assertEquals("ana@gymbros.app", AuthRules.clean("  Ana@GymBros.app "))

    @Test
    fun validatesLikeIOS() {
        assertDoesNotThrow { AuthRules.validate(" Ana@gymbros.app ", "12345678") }
        for (bad in listOf("ana", "ana@", "@gymbros.app", "ana@gymbros", "ana@gymbros.", "a na@gymbros.app", "a@b@c.com")) {
            assertEquals(AuthError.INVALID_EMAIL, error { AuthRules.validate(bad, "12345678") }, bad)
        }
        assertEquals(AuthError.SHORT_PASSWORD, error { AuthRules.validate("ana@gymbros.app", "1234567") })
        assertEquals(AuthError.MISSING_NAME, error { AuthRules.validateSignUp("  ", "ana@gymbros.app", "12345678") })
    }

    @Test
    fun resetNoticeDoesNotRevealTheAccount() =
        assertEquals("Se ana@gymbros.app tiver conta, chega um link para criar uma senha nova. Veja também o spam.",
                     AuthRules.resetNotice(" Ana@GymBros.app"))
}
