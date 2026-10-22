package com.alonsoalmeida.gymbros.ui.components

import android.annotation.SuppressLint
import android.content.Context
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Image
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ColorMatrix
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.painter.BitmapPainter
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.imageResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.alonsoalmeida.gymbros.domain.MonsterForm
import com.alonsoalmeida.gymbros.domain.SpriteArt
import com.alonsoalmeida.gymbros.domain.Stage
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.color
import java.util.concurrent.ConcurrentHashMap

/** Sprites do app (res/drawable-nodpi, gerados dos imagesets do iOS) pelo nome, como o `Image(named:)` */
object Sprites {
    private val ids = ConcurrentHashMap<String, Int>()
    private lateinit var app: Context

    @SuppressLint("DiscouragedApi") // nome da arte vem das regras do jogo (forma + espécie), como no iOS
    fun install(context: Context) {
        app = context.applicationContext
        SpriteArt.exists = { id(it) != 0 }
    }

    fun id(name: String): Int = ids.getOrPut(name) { app.resources.getIdentifier(name, "drawable", app.packageName) }
}

/**
 * Pixel art do bro, sem suavização (MonsterSprite.swift). Lenda de virada ainda sem arte: espaço reservado tracejado na
 * cor do galho. `saturation` < 1 tira a cor (bro triste ou entediado).
 */
@Composable
fun MonsterSprite(form: MonsterForm, modifier: Modifier = Modifier, saturation: Float = 1f) {
    if (form.isVirada && !form.hasArt) {
        val tint = form.attribute?.color() ?: GMColors.dim
        Box(
            modifier.aspectRatio(1f).padding(6.dp).drawBehind {
                drawCircle(tint.copy(alpha = 0.08f))
                drawCircle(tint.copy(alpha = 0.6f), radius = size.minDimension / 2 - 1.dp.toPx(),
                           style = Stroke(2.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(5.dp.toPx(), 4.dp.toPx()))))
            },
            contentAlignment = Alignment.Center,
        ) { Icon(Icons.Filled.Image, contentDescription = null, tint = tint.copy(alpha = 0.7f), modifier = Modifier.size(18.dp)) }
        return
    }
    val res = Sprites.id(form.sprite)
    if (res == 0) return
    val bitmap: ImageBitmap = ImageBitmap.imageResource(res)
    val filter = remember(saturation) { if (saturation >= 1f) null else ColorFilter.colorMatrix(ColorMatrix().apply { setToSaturation(saturation) }) }
    Image(BitmapPainter(bitmap, filterQuality = FilterQuality.None), contentDescription = null, modifier = modifier,
          contentScale = ContentScale.Fit, colorFilter = filter)
}

/** Sprite pelo nome do recurso (tela de login: o bebê) */
@Composable
fun MonsterSprite(sprite: String, modifier: Modifier = Modifier) {
    val res = Sprites.id(sprite)
    if (res == 0) return
    Image(BitmapPainter(ImageBitmap.imageResource(res), filterQuality = FilterQuality.None), contentDescription = null, modifier = modifier,
          contentScale = ContentScale.Fit)
}

/** Roteiro da animação ociosa: passos (valor, duração em s) para cada eixo. Fonte: MonsterSprite.swift (`MotionScript`) */
private class MotionScript(
    val scaleX: List<Pair<Float, Float>> = listOf(1f to 1f),
    val scaleY: List<Pair<Float, Float>> = listOf(1f to 1f),
    val offsetY: List<Pair<Float, Float>> = listOf(0f to 1f),
    val rotation: List<Pair<Float, Float>> = listOf(0f to 1f),
) {
    val duration: Float get() = listOf(scaleX, scaleY, offsetY, rotation).maxOf { t -> t.sumOf { it.second.toDouble() }.toFloat() }

    companion object {
        fun of(species: String): MotionScript = when (species) {
            // Respiração lenta e pesada, balançando o corpo
            "urso" -> MotionScript(scaleX = listOf(1.04f to 1.4f, 1f to 1.4f), rotation = listOf(-2f to 1.4f, 2f to 1.4f))
            // Agitado: pulinhos curtos e rápidos, depois uma pausa
            "rato" -> MotionScript(offsetY = listOf(-5f to 0.12f, 0f to 0.12f, -4f to 0.12f, 0f to 0.12f, 0f to 1.4f))
            // Estufa o peito, orgulhoso
            "lobo" -> MotionScript(scaleY = listOf(1.05f to 1.2f, 1f to 1.0f), rotation = listOf(-1.5f to 1.2f, 0f to 1.0f))
            // Balança de um lado para o outro, como abanando o rabo
            "cachorro" -> MotionScript(rotation = listOf(4f to 0.18f, -4f to 0.18f, 4f to 0.18f, 0f to 0.18f, 0f to 1.0f))
            // Saltinho com inclinação
            "esquilo" -> MotionScript(offsetY = listOf(-10f to 0.25f, 0f to 0.25f, 0f to 1.3f), rotation = listOf(-5f to 0.25f, 0f to 0.25f, 0f to 1.3f))
            // Espreguiçada lenta
            "gato" -> MotionScript(scaleX = listOf(1f to 1.2f, 0.96f to 0.8f, 1.03f to 0.5f, 1f to 0.5f),
                                   scaleY = listOf(1f to 1.2f, 1.07f to 0.8f, 0.97f to 0.5f, 1f to 0.5f))
            // Flutua, como se planasse
            "coruja" -> MotionScript(offsetY = listOf(-8f to 1.3f, 0f to 1.3f), rotation = listOf(2f to 1.3f, -2f to 1.3f))
            // Coelho: respira e dá um pulinho de leve
            else -> MotionScript(scaleY = listOf(1.03f to 1.0f, 0.98f to 1.0f), offsetY = listOf(-3f to 1.0f, 0f to 1.0f))
        }

        /**
         * Valor da trilha no instante `t`: cada passo vai do valor anterior ao seu com suavização (as CubicKeyframe do iOS);
         * a trilha mais curta fica parada no último valor até o ciclo recomeçar, e o ciclo começa de onde o anterior parou.
         */
        fun at(track: List<Pair<Float, Float>>, t: Float): Float {
            var from = track.last().first
            var start = 0f
            for ((v, d) in track) {
                if (t < start + d) {
                    val x = ((t - start) / d).coerceIn(0f, 1f)
                    return from + (v - from) * (x * x * (3 - 2 * x))
                }
                from = v
                start += d
            }
            return track.last().first
        }
    }
}

/** Bro "vivo" (MonsterSprite.swift `LivingMonster`): respira conforme a espécie; o ovo dá tremidinhas, mais perto de chocar, mais fortes */
@Composable
fun LivingMonster(form: MonsterForm, modifier: Modifier = Modifier, progress: Double = 0.0, saturation: Float = 1f) {
    val transition = rememberInfiniteTransition(label = "bro")
    if (form.stage == Stage.EGG) {
        val pause = maxOf(3.2f - 2.2f * progress.toFloat(), 1.0f)
        val amp = 5f + 7f * progress.toFloat()
        val steps = listOf(0f to pause, amp to 0.07f, -amp * 0.9f to 0.1f, amp * 0.6f to 0.1f, -amp * 0.35f to 0.09f, 0f to 0.09f)
        val total = steps.sumOf { it.second.toDouble() }.toFloat()
        val t by transition.animateFloat(0f, total, infiniteRepeatable(tween((total * 1000).toInt(), easing = LinearEasing), RepeatMode.Restart),
                                         label = "egg")
        MonsterSprite(form, modifier.graphicsLayer {
            transformOrigin = TransformOrigin(0.5f, 1f)
            rotationZ = MotionScript.at(steps, t)
        }, saturation)
        return
    }
    val m = remember(form.species) { MotionScript.of(form.species) }
    val total = m.duration
    val t by transition.animateFloat(0f, total, infiniteRepeatable(tween((total * 1000).toInt(), easing = LinearEasing), RepeatMode.Restart),
                                     label = "motion")
    MonsterSprite(form, modifier.graphicsLayer {
        transformOrigin = TransformOrigin(0.5f, 1f)
        scaleX = MotionScript.at(m.scaleX, t)
        scaleY = MotionScript.at(m.scaleY, t)
        rotationZ = MotionScript.at(m.rotation, t)
        translationY = MotionScript.at(m.offsetY, t).dp.toPx()
    }, saturation)
}

/** Bros que ganharam XP de uma atividade, em bolinhas sobrepostas (BroGains.swift `BroAvatars`) */
@Composable
fun BroAvatars(forms: List<MonsterForm>, modifier: Modifier = Modifier, size: Dp = 22.dp) {
    Row(modifier.semantics { contentDescription = if (forms.size == 1) "1 bro" else "${forms.size} bros" },
        horizontalArrangement = Arrangement.spacedBy(-size * 0.4f)) {
        for (f in forms.take(3)) {
            Box(Modifier.size(size).background(GMColors.card, CircleShape).border(1.dp, GMColors.raised, CircleShape), contentAlignment = Alignment.Center) {
                MonsterSprite(f, Modifier.size(size * 0.85f))
            }
        }
        if (forms.size > 3) {
            Box(Modifier.size(size).background(GMColors.card, CircleShape), contentAlignment = Alignment.Center) {
                Text("+${forms.size - 3}", color = GMColors.dim, fontSize = 9.sp, fontWeight = FontWeight.Black)
            }
        }
    }
}

