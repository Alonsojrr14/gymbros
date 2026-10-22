package com.alonsoalmeida.gymbros

import android.app.Application
import com.alonsoalmeida.gymbros.data.AuthRepository
import com.alonsoalmeida.gymbros.data.FirebaseAuthRepository

/** Injeção manual (ADR-003): um container por processo; os ViewModels pegam o que precisam daqui */
class AppContainer {
    val auth: AuthRepository by lazy { FirebaseAuthRepository() }
}

class GymBrosApp : Application() {
    val container by lazy { AppContainer() }
}
