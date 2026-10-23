package com.alonsoalmeida.gymbros.ui.bros

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.scaleIn
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.painter.BitmapPainter
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.imageResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.alonsoalmeida.gymbros.data.AccountCopyRepository
import com.alonsoalmeida.gymbros.data.CopyState
import com.alonsoalmeida.gymbros.domain.MonsterForm
import com.alonsoalmeida.gymbros.domain.bros.BroEvents
import com.alonsoalmeida.gymbros.domain.bros.EvolutionEvent
import com.alonsoalmeida.gymbros.domain.home.HomeData
import com.alonsoalmeida.gymbros.ui.AppEnv
import com.alonsoalmeida.gymbros.ui.components.MonsterSprite
import com.alonsoalmeida.gymbros.ui.components.Sprites
import com.alonsoalmeida.gymbros.ui.components.Symbols
import com.alonsoalmeida.gymbros.ui.components.gmPress
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMType
import com.alonsoalmeida.gymbros.ui.theme.color
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/**
 * Fila das cenas de evolução e de chocar (App.swift `check` + `evolutions`). A cada mudança da Box confere quem subiu
 * de fase e grava na cópia a forma de agora, a espécie fixada e as formas descobertas, para a cena aparecer uma vez só
 * (aqui ou no iPhone, que lê o mesmo `lastFormID`).
 */
class BroEventsViewModel(private val copies: AccountCopyRepository) : ViewModel() {
    private val _queue = MutableStateFlow<List<EvolutionEvent>>(emptyList())
    val queue: StateFlow<List<EvolutionEvent>> = _queue.asStateFlow()
    private val lock = Mutex()

    fun onChange(home: HomeData) {
        viewModelScope.launch {
            lock.withLock {
                val copy = (copies.state.value as? CopyState.Ready)?.copy ?: return@withLock
                val r = withContext(Dispatchers.Default) { BroEvents.check(copy, home.roster) }
                if (r.copy == null) return@withLock
                var found = r.events
                // Na hora de gravar, confere de novo sobre a cópia mais nova (pode ter mudado no meio)
                copies.edit { latest ->
                    val base = latest ?: copy
                    val again = BroEvents.check(base, home.roster)
                    found = again.events
                    again.copy ?: base
                }
                _queue.update { q -> q + found.filter { e -> q.none { it.id == e.id } } }
            }
        }
    }

    fun next() = _queue.update { it.drop(1) }
}

/** Mostra as cenas de evolução e de chocar de qualquer bro da Box, uma de cada vez, por cima de tudo */
@Composable
fun BroEventsHost(env: AppEnv, home: HomeData) {
    val vm: BroEventsViewModel = viewModel(key = "broEvents-${env.uid}", factory = viewModelFactory {
        initializer { BroEventsViewModel(env.copies) }
    })
    LaunchedEffect(home) { vm.onChange(home) }
    val queue by vm.queue.collectAsStateWithLifecycle()
    val e = queue.firstOrNull() ?: return
    EvolutionScene(e, vm::next)
}

/**
 * Cena de evolução no estilo clássico (EvolutionView.swift): o bro pisca alternando com a silhueta da nova forma, cada
 * vez mais rápido, até a revelação. Do ovo, é a cena de chocar.
 */
@Composable
private fun EvolutionScene(e: EvolutionEvent, done: () -> Unit) {
    var showingNew by remember(e.id) { mutableStateOf(false) }
    var flash by remember(e.id) { mutableStateOf(false) }
    var revealed by remember(e.id) { mutableStateOf(false) }
    val haptic = LocalHapticFeedback.current
    LaunchedEffect(e.id) {
        // Intervalos cada vez menores
        var wait = 0.5
        repeat(14) {
            delay((wait * 1000).toLong())
            showingNew = !showingNew
            flash = !flash
            haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
            wait = maxOf(wait * 0.82, 0.07)
        }
        showingNew = true
        delay(200)
        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
        revealed = true
    }
    val tint = e.to.attribute?.color() ?: GMColors.accent
    val glow by animateFloatAsState(if (revealed) 0.45f else 0.1f, label = "glow")
    val scale by animateFloatAsState(if (revealed) 1.15f else 1f, spring(dampingRatio = Spring.DampingRatioMediumBouncy), label = "scale")
    val title = if (revealed) (if (e.hatching) "O ovo chocou!" else "Evoluiu!")
                else (if (e.hatching) "O ovo está chocando…" else "${e.from.name} está evoluindo…")

    // Sem fechar pelo voltar antes da revelação, como o modal do iOS (o Continuar fecha)
    Dialog(onDismissRequest = { if (revealed) done() },
           properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false, dismissOnClickOutside = false)) {
        Box(Modifier.fillMaxSize().background(Color.Black).background(Brush.radialGradient(listOf(tint.copy(alpha = glow), Color.Transparent)))
                .safeDrawingPadding(), contentAlignment = Alignment.Center) {
            Column(Modifier.padding(horizontal = 24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(30.dp)) {
                Text(title, color = Color.White, fontSize = 26.sp, fontWeight = FontWeight.ExtraBold, textAlign = TextAlign.Center,
                     modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
                FlashSprite(if (showingNew) e.to else e.from, if (revealed) 0f else if (flash) 1f else 0.3f,
                            Modifier.size(240.dp).graphicsLayer { scaleX = scale; scaleY = scale })
                AnimatedVisibility(revealed, enter = scaleIn() + fadeIn()) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(30.dp)) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Text(e.to.name, color = Color.White, fontSize = 34.sp, fontWeight = FontWeight.ExtraBold, maxLines = 1)
                            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                                Text(e.to.stage.label, color = GMColors.dim, style = GMType.body)
                                e.to.attribute?.let { a ->
                                    Text("·", color = GMColors.dim, style = GMType.body)
                                    Icon(Symbols.of(a), null, tint = a.color(), modifier = Modifier.size(16.dp))
                                    Text(a.label, color = a.color(), style = GMType.body)
                                }
                            }
                        }
                        Text("Continuar", color = Color.Black, style = GMType.headline,
                             modifier = Modifier.gmPress(onClick = done).background(GMColors.accent, CircleShape).padding(horizontal = 40.dp, vertical = 14.dp))
                    }
                }
            }
        }
    }
}

/** Sprite com o clarão da cena (`brightness` do iOS): 0 = normal, 1 = branco */
@Composable
private fun FlashSprite(form: MonsterForm, brightness: Float, modifier: Modifier) {
    val res = Sprites.id(form.spriteWithFallback)
    if (res == 0 || brightness == 0f) return MonsterSprite(form, modifier)
    Image(BitmapPainter(ImageBitmap.imageResource(res), filterQuality = FilterQuality.None), contentDescription = null,
          modifier = modifier.aspectRatio(1f), contentScale = ContentScale.Fit,
          colorFilter = ColorFilter.tint(Color.White.copy(alpha = brightness), BlendMode.SrcAtop))
}
