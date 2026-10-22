package com.alonsoalmeida.gymbros.ui.leagues

import androidx.compose.runtime.Composable
import com.alonsoalmeida.gymbros.domain.home.HomeData
import com.alonsoalmeida.gymbros.ui.AppEnv
import com.alonsoalmeida.gymbros.ui.main.SoonContent
import com.alonsoalmeida.gymbros.ui.main.SoonModal

/** Aba Ligas (Leagues/LeaguesView.swift). Ponto de encaixe: a frente das ligas substitui o conteúdo. */
@Composable
fun LeaguesTab(env: AppEnv, home: HomeData) = SoonContent("Ligas", "Ligas, X1 e ranking estão chegando no Android.")
