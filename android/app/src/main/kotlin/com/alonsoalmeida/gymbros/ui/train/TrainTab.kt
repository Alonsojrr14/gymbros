package com.alonsoalmeida.gymbros.ui.train

import androidx.compose.runtime.Composable
import com.alonsoalmeida.gymbros.domain.home.HomeData
import com.alonsoalmeida.gymbros.ui.AppEnv
import com.alonsoalmeida.gymbros.ui.main.SoonContent
import com.alonsoalmeida.gymbros.ui.main.SoonModal

/** Aba Treino (Train/TrainView.swift). Ponto de encaixe: a frente do treino substitui o conteúdo. */
@Composable
fun TrainTab(env: AppEnv, home: HomeData) = SoonContent("Treino", "Rotinas, treino guiado e WOD estão chegando no Android.")
