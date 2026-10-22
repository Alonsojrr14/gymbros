package com.alonsoalmeida.gymbros.ui.components

import androidx.annotation.DrawableRes
import androidx.compose.animation.core.InfiniteRepeatableSpec
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.keyframes
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.foundation.Image
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import androidx.compose.ui.graphics.painter.BitmapPainter
import androidx.compose.ui.res.imageResource
import androidx.compose.ui.graphics.ImageBitmap

/**
 * Pixel art do bro, sem suavização (ios/GymBros/Bros/MonsterSprite.swift `MonsterSprite`).
 */
@Composable
fun MonsterSprite(@DrawableRes sprite: Int, modifier: Modifier = Modifier) {
    val bitmap: ImageBitmap = ImageBitmap.imageResource(sprite)
    Image(BitmapPainter(bitmap, filterQuality = FilterQuality.None), contentDescription = null, modifier = modifier, contentScale = ContentScale.Fit)
}

/**
 * Bro "vivo" (LivingMonster do iOS). Coelho: respira e dá um pulinho de leve, a partir da base
 * (escala Y 1,03 em 1 s e 0,98 em 1 s; deslocamento −3 em 1 s e 0 em 1 s), repetindo.
 */
@Composable
fun LivingMonster(@DrawableRes sprite: Int, modifier: Modifier = Modifier) {
    val t = rememberInfiniteTransition(label = "bro")
    val spec: (Float, Float) -> InfiniteRepeatableSpec<Float> = { a, b ->
        infiniteRepeatable(keyframes { durationMillis = 2000; a at 1000; b at 2000 }, RepeatMode.Restart)
    }
    // Começa da pose parada (escala 1, sem deslocamento), como o Motion() inicial do iOS
    val scaleY by t.animateFloat(1f, 0.98f, spec(1.03f, 0.98f), label = "scaleY")
    val offsetY by t.animateFloat(0f, 0f, spec(-3f, 0f), label = "offsetY")
    MonsterSprite(
        sprite,
        modifier.graphicsLayer {
            transformOrigin = TransformOrigin(0.5f, 1f)
            this.scaleY = scaleY
            translationY = offsetY.dp.toPx()
        },
    )
}
