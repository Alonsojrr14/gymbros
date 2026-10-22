package com.alonsoalmeida.gymbros.ui.onboarding

import androidx.compose.runtime.Composable
import com.alonsoalmeida.gymbros.domain.home.HomeData
import com.alonsoalmeida.gymbros.ui.AppEnv
import com.alonsoalmeida.gymbros.ui.main.SoonContent
import com.alonsoalmeida.gymbros.ui.main.SoonModal

/**
 * Portões depois de abrir a conta (App.swift `RootView`): sem nome de treinador → apresentação (Onboarding), termos de
 * versão nova → aceite; senão o app. Ponto de encaixe: por enquanto deixa passar.
 */
@Composable
fun OnboardingGate(env: AppEnv, home: HomeData, content: @Composable () -> Unit) = content()
