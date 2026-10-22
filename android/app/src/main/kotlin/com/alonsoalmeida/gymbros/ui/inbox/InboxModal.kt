package com.alonsoalmeida.gymbros.ui.inbox

import androidx.compose.runtime.Composable
import com.alonsoalmeida.gymbros.domain.home.HomeData
import com.alonsoalmeida.gymbros.ui.AppEnv
import com.alonsoalmeida.gymbros.ui.main.SoonContent
import com.alonsoalmeida.gymbros.ui.main.SoonModal

/** Caixa de entrada (o sino: Inbox/InboxView.swift). Ponto de encaixe. */
@Composable
fun InboxModal(visible: Boolean, env: AppEnv, home: HomeData, onDismiss: () -> Unit) = SoonModal(if (visible) "Caixa de entrada" else null, onDismiss)
