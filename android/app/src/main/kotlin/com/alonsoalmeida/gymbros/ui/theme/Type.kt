package com.alonsoalmeida.gymbros.ui.theme

import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

/** Estilos de texto do iOS (Dynamic Type no tamanho padrão), em sp para acompanhar a escala de fonte do Android */
object GMType {
    val largeTitle = TextStyle(fontSize = 34.sp, fontWeight = FontWeight.Black)
    val title3 = TextStyle(fontSize = 20.sp)
    val headline = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
    val body = TextStyle(fontSize = 17.sp)
    val subheadline = TextStyle(fontSize = 15.sp)
    val footnote = TextStyle(fontSize = 13.sp)
    val caption = TextStyle(fontSize = 12.sp)
    val caption2 = TextStyle(fontSize = 11.sp)
}
