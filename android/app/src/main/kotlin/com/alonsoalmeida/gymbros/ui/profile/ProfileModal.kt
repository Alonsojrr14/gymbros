package com.alonsoalmeida.gymbros.ui.profile

import androidx.compose.runtime.Composable
import com.alonsoalmeida.gymbros.domain.home.HomeData
import com.alonsoalmeida.gymbros.ui.AppEnv
import com.alonsoalmeida.gymbros.ui.main.SoonContent
import com.alonsoalmeida.gymbros.ui.main.SoonModal

/** Perfil (a bolinha no topo das abas: Profile/ProfileView.swift). Ponto de encaixe. */
@Composable
fun ProfileModal(visible: Boolean, env: AppEnv, home: HomeData, onDismiss: () -> Unit) = SoonModal(if (visible) "Perfil" else null, onDismiss)
