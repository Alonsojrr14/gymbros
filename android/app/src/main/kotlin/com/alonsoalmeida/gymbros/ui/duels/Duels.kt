package com.alonsoalmeida.gymbros.ui.duels

import androidx.compose.runtime.Composable
import com.alonsoalmeida.gymbros.domain.home.HomeData
import com.alonsoalmeida.gymbros.ui.AppEnv
import com.alonsoalmeida.gymbros.ui.main.SoonContent
import com.alonsoalmeida.gymbros.ui.main.SoonModal

/** Card do X1 na tela inicial (Duels: DuelHomeCard). Ponto de encaixe: sem conteúdo até a frente do X1. */
@Composable
fun DuelHomeCard(env: AppEnv, home: HomeData) {}

/** X1 (Duels/DuelsView). `opponentID`: abre já desafiando essa pessoa. Ponto de encaixe. */
@Composable
fun DuelsModal(visible: Boolean, env: AppEnv, home: HomeData, onDismiss: () -> Unit, opponentID: String? = null) =
    SoonModal(if (visible) "X1" else null, onDismiss)
