package com.alonsoalmeida.gymbros

import android.app.Application
import android.content.Context
import com.alonsoalmeida.gymbros.data.AccountCopyRepository
import com.alonsoalmeida.gymbros.data.AuthRepository
import com.alonsoalmeida.gymbros.data.FirebaseAuthRepository
import com.alonsoalmeida.gymbros.ui.components.Sprites

/** Injeção manual (ADR-003): um container por processo; os ViewModels pegam o que precisam daqui */
class AppContainer(val context: Context) {
    val auth: AuthRepository by lazy { FirebaseAuthRepository() }
    val copies: AccountCopyRepository by lazy { AccountCopyRepository(context) }
}

class GymBrosApp : Application() {
    val container by lazy { AppContainer(this) }

    override fun onCreate() {
        super.onCreate()
        Sprites.install(this)
    }
}
