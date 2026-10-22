package com.alonsoalmeida.gymbros.ui.map

import androidx.compose.runtime.Composable
import com.alonsoalmeida.gymbros.domain.home.HomeData
import com.alonsoalmeida.gymbros.ui.AppEnv
import com.alonsoalmeida.gymbros.ui.main.SoonContent
import com.alonsoalmeida.gymbros.ui.main.SoonModal

/** Aba Mapa (Friends/MapScreen.swift). Ponto de encaixe: a frente do mapa substitui o conteúdo. */
@Composable
fun MapTab(env: AppEnv, home: HomeData) = SoonContent("Mapa", "Academias, amigos ao vivo e rotas estão chegando no Android.")
