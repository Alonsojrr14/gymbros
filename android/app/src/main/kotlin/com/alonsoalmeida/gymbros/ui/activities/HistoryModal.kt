package com.alonsoalmeida.gymbros.ui.activities

import androidx.compose.runtime.Composable
import com.alonsoalmeida.gymbros.domain.home.HomeData
import com.alonsoalmeida.gymbros.ui.AppEnv
import com.alonsoalmeida.gymbros.ui.main.SoonContent
import com.alonsoalmeida.gymbros.ui.main.SoonModal

/** Histórico ("Ver tudo": Activities/HistoryView) e detalhe de uma atividade (ActivityDetail.swift). Pontos de encaixe. */
@Composable
fun HistoryModal(visible: Boolean, env: AppEnv, home: HomeData, onDismiss: () -> Unit) = SoonModal(if (visible) "Histórico" else null, onDismiss)

@Composable
fun ActivityDetailModal(activityID: String?, env: AppEnv, home: HomeData, onDismiss: () -> Unit) = SoonModal(if (activityID != null) "Atividade" else null, onDismiss)
