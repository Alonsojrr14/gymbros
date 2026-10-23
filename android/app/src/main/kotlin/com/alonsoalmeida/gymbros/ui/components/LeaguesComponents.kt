package com.alonsoalmeida.gymbros.ui.components

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.animation.slideInHorizontally
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.semantics.toggleableState
import androidx.compose.ui.state.ToggleableState
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMRadius
import com.alonsoalmeida.gymbros.ui.theme.GMType
import java.io.ByteArrayOutputStream
import java.util.Base64

// Componentes do design system que as telas das ligas usam e que ainda não existiam no Android
// (ios/GymBros/DesignSystem: GMSurfaces, GMChips, GMToggles, GMIndicators, GMSheets, GMButtons).






/** GMFlow: itens que quebram linha */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun GMFlow(spacing: Dp = 8.dp, content: @Composable () -> Unit) =
    FlowRow(horizontalArrangement = Arrangement.spacedBy(spacing), verticalArrangement = Arrangement.spacedBy(spacing)) { content() }



/** GMFloatingButton: círculo verde de 62 com sombra, no canto da tela */
@Composable
fun GMFloatingButton(label: String, onClick: () -> Unit, modifier: Modifier = Modifier, icon: ImageVector = Icons.Filled.Add) {
    Box(modifier.size(62.dp).shadow(10.dp, CircleShape).background(GMColors.accent, CircleShape).gmPress(onClick = onClick)
            .semantics { contentDescription = label }, contentAlignment = Alignment.Center) {
        Icon(icon, null, tint = Color.Black, modifier = Modifier.size(28.dp))
    }
}

/**
 * Tela empilhada (NavigationLink + GMScreen com `back: true, large: false`): seta de voltar, título pequeno no meio,
 * botões à direita e o conteúdo rolando com espaçamento 18. Abre por cima de tudo; o voltar do sistema volta.
 */
@Composable
fun GMPushScreen(title: String, onBack: () -> Unit, trailing: @Composable RowScope.() -> Unit = {},
                 overlay: @Composable BoxScope.() -> Unit = {}, bottomInset: Dp = 40.dp, content: @Composable ColumnScope.() -> Unit) {
    Dialog(onDismissRequest = onBack, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        val shown = remember { MutableTransitionState(false).apply { targetState = true } }
        AnimatedVisibility(shown, enter = slideInHorizontally { it }) {
            Box(Modifier.fillMaxSize().background(GMColors.bg).safeDrawingPadding()) {
                Column(Modifier.fillMaxSize()) {
                    Box(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), contentAlignment = Alignment.Center) {
                        Text(title, color = Color.White, style = GMType.headline, maxLines = 1, overflow = TextOverflow.Ellipsis,
                             modifier = Modifier.padding(horizontal = 96.dp))
                        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            GMIconButton(Icons.AutoMirrored.Filled.ArrowBack, "Voltar", onBack)
                            Spacer(Modifier.weight(1f))
                            trailing()
                        }
                    }
                    Column(
                        Modifier.verticalScroll(rememberScrollState()).padding(start = 16.dp, end = 16.dp, top = 4.dp, bottom = bottomInset),
                        verticalArrangement = Arrangement.spacedBy(18.dp), content = content,
                    )
                }
                overlay()
            }
        }
        BackHandler(onBack = onBack)
    }
}

/** Foto em JPEG (bytes ou base64), decodificada uma vez */
object Photos {
    fun decode(bytes: ByteArray?, maxSide: Int = 1600): ImageBitmap? = bytes?.let {
        runCatching {
            val o = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(it, 0, it.size, o)
            var sample = 1
            while (maxOf(o.outWidth, o.outHeight) / sample > maxSide) sample *= 2
            BitmapFactory.decodeByteArray(it, 0, it.size, BitmapFactory.Options().apply { inSampleSize = sample })?.asImageBitmap()
        }.getOrNull()
    }

    fun base64(s: String?): ByteArray? = s?.let { runCatching { Base64.getDecoder().decode(it) }.getOrNull() }

    /** Reduz a foto para algo razoável de guardar: lado maior 1280, JPEG 70% (LeaguesView.swift `compressedPhoto`) */
    fun compressed(data: ByteArray): ByteArray? = runCatching {
        val o = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(data, 0, data.size, o)
        var sample = 1
        while (maxOf(o.outWidth, o.outHeight) / (sample * 2) >= 1280) sample *= 2
        val b = BitmapFactory.decodeByteArray(data, 0, data.size, BitmapFactory.Options().apply { inSampleSize = sample }) ?: return null
        compressed(b)
    }.getOrNull()

    fun compressed(b: Bitmap): ByteArray {
        val scale = minOf(1f, 1280f / maxOf(b.width, b.height))
        val s = if (scale < 1f) Bitmap.createScaledBitmap(b, (b.width * scale).toInt(), (b.height * scale).toInt(), true) else b
        return ByteArrayOutputStream().also { s.compress(Bitmap.CompressFormat.JPEG, 70, it) }.toByteArray()
    }
}

/** Foto preenchendo o espaço (scaledToFill) */
@Composable
fun PhotoFill(bytes: ByteArray?, modifier: Modifier = Modifier, maxSide: Int = 800) {
    val img = remember(bytes) { Photos.decode(bytes, maxSide) }
    if (img != null) Image(img, null, contentScale = ContentScale.Crop, modifier = modifier)
    else Box(modifier.background(GMColors.raised))
}
