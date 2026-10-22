package com.alonsoalmeida.gymbros.ui.bros

import androidx.compose.runtime.Composable
import com.alonsoalmeida.gymbros.domain.home.HomeData
import com.alonsoalmeida.gymbros.ui.AppEnv
import com.alonsoalmeida.gymbros.ui.main.SoonContent
import com.alonsoalmeida.gymbros.ui.main.SoonModal

/** Bros (o botão da pata na tela inicial: Bros/DexView.swift e a box de Monsters.swift). Ponto de encaixe. */
@Composable
fun BrosModal(visible: Boolean, env: AppEnv, home: HomeData, onDismiss: () -> Unit) = SoonModal(if (visible) "Bros" else null, onDismiss)
