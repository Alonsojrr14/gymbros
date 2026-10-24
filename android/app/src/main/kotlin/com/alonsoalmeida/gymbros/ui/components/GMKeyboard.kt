package com.alonsoalmeida.gymbros.ui.components

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.isImeVisible
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.focus.onFocusChanged
import kotlinx.coroutines.delay

/** O campo em foco nunca fica atrás do teclado: quando ele abre (ou muda de campo), a lista rola até o campo (GMKeyboard.swift) */
@OptIn(ExperimentalFoundationApi::class, ExperimentalLayoutApi::class)
fun Modifier.gmRevealOnFocus(): Modifier = composed {
    val requester = remember { BringIntoViewRequester() }
    var focused by remember { mutableStateOf(false) }
    val ime = WindowInsets.isImeVisible
    LaunchedEffect(focused, ime) {
        if (focused && ime) {
            delay(80)
            requester.bringIntoView()
        }
    }
    bringIntoViewRequester(requester).onFocusChanged { focused = it.isFocused }
}
