package com.alonsoalmeida.gymbros.ui.home

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.CloudOff
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Pets
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.alonsoalmeida.gymbros.domain.ActivityText
import com.alonsoalmeida.gymbros.domain.Attribute
import com.alonsoalmeida.gymbros.domain.Mood
import com.alonsoalmeida.gymbros.domain.Stage
import com.alonsoalmeida.gymbros.domain.home.HomeActivity
import com.alonsoalmeida.gymbros.domain.home.HomeData
import com.alonsoalmeida.gymbros.ui.components.AutoShrinkText
import com.alonsoalmeida.gymbros.ui.components.BroAvatars
import com.alonsoalmeida.gymbros.ui.components.GMButton
import com.alonsoalmeida.gymbros.ui.components.GMButtonKind
import com.alonsoalmeida.gymbros.ui.components.GMCard
import com.alonsoalmeida.gymbros.ui.components.GMEmptyState
import com.alonsoalmeida.gymbros.ui.components.GMIconButton
import com.alonsoalmeida.gymbros.ui.components.GMModal
import com.alonsoalmeida.gymbros.ui.components.GMProgressBar
import com.alonsoalmeida.gymbros.ui.components.GMScreen
import com.alonsoalmeida.gymbros.ui.components.GMSection
import com.alonsoalmeida.gymbros.ui.components.LivingMonster
import com.alonsoalmeida.gymbros.ui.components.PersonAvatar
import com.alonsoalmeida.gymbros.ui.components.Symbols
import com.alonsoalmeida.gymbros.ui.components.gmPress
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMRadius
import com.alonsoalmeida.gymbros.ui.theme.GMType
import com.alonsoalmeida.gymbros.ui.theme.color
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** Abrindo a conta / não deu (AccountSync.swift `AccountLoadingView`) */
@Composable
fun AccountLoadingScreen(failed: String?, onRetry: () -> Unit, onSignOut: () -> Unit) {
    Column(
        Modifier.fillMaxSize().background(GMColors.bg).padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        if (failed != null) {
            GMEmptyState(Icons.Filled.CloudOff, "Não deu para abrir sua conta", failed)
            GMButton("Tentar de novo", onRetry, icon = Icons.Filled.Refresh)
            GMButton("Sair", onSignOut, icon = Icons.AutoMirrored.Filled.Logout, kind = GMButtonKind.SECONDARY)
        } else {
            CircularProgressIndicator(color = GMColors.accent)
            Text("Abrindo sua conta…", color = GMColors.dim, style = GMType.subheadline)
        }
    }
}

/** Tela inicial (Bros/HomeView.swift) */
@Composable
fun HomeScreen(home: HomeData, email: String, onSignOut: () -> Unit) {
    val s = home.snapshot
    var settings by remember { mutableStateOf(false) }
    var soon by remember { mutableStateOf<String?>(null) }

    Box(Modifier.fillMaxSize()) {
        GMScreen(
            "Olá, ${home.trainerName}",
            leading = { PersonAvatar(home.trainerName, modifier = Modifier.gmPress { soon = "Perfil" }) },
            trailing = {
                if (s.streak > 0) {
                    Row(
                        Modifier.background(GMColors.raised, CircleShape).padding(horizontal = 12.dp, vertical = 9.dp)
                            .clearAndSetSemantics { contentDescription = "${s.streak} dias seguidos" },
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        Icon(Icons.Filled.LocalFireDepartment, null, tint = GMColors.streak, modifier = Modifier.size(16.dp))
                        Text("${s.streak}", color = GMColors.streak, style = GMType.subheadline.copy(fontWeight = FontWeight.Bold))
                    }
                }
                GMIconButton(Icons.Filled.Pets, "Bros", { soon = "Bros" })
                GMIconButton(Icons.Filled.Notifications, "Caixa de entrada", { soon = "Caixa de entrada" })
                GMIconButton(Icons.Outlined.Settings, "Ajustes", { settings = true })
            },
        ) {
            MonsterCard(home)
            if (s.stage != Stage.EGG) AttributesCard(home)
            GMButton("Registrar atividade", { soon = "Registrar atividade" }, icon = Icons.Filled.AddCircle)
            if (home.hasActivities) RecentCard(home) { soon = "Histórico" }
        }

        // Ajustes: por enquanto só a conta (o resto dos Ajustes chega com as próximas telas)
        GMModal(settings, "Ajustes", onDismiss = { settings = false }) {
            GMSection("Conta") {
                Text(email, color = Color.White, style = GMType.body)
            }
            GMButton("Sair", onSignOut, icon = Icons.AutoMirrored.Filled.Logout, kind = GMButtonKind.DANGER)
        }
        GMModal(soon != null, soon.orEmpty(), onDismiss = { soon = null }) {
            GMEmptyState(Icons.Filled.Pets, "Em breve no Android", "Esta parte do GymBros ainda está chegando no Android. No iPhone ela já funciona.")
        }
    }
}

@Composable
private fun MonsterCard(home: HomeData) {
    val s = home.snapshot
    GMCard(padding = 18.dp) {
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
            SpeechBubble(home.line, home.mood.emoji)
            // Triste ou entediado, o bro perde a cor
            val saturation = when (home.mood) { Mood.TRISTE -> 0.35f; Mood.ENTEDIADO -> 0.7f; else -> 1f }
            LivingMonster(s.form, Modifier.height(200.dp).fillMaxWidth(), progress = s.progress, saturation = saturation)

            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                AutoShrinkText(home.monsterName, maxSize = 28f, minSize = 17f, weight = FontWeight.Black)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    val style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold)
                    Text(s.stage.label, color = GMColors.dim, style = style)
                    s.form.attribute?.let { a ->
                        Text("·", color = GMColors.dim, style = style)
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                            Icon(Symbols.of(a), null, tint = a.color(), modifier = Modifier.size(15.dp))
                            Text(a.label, color = a.color(), style = style)
                        }
                    }
                    if (s.stage != Stage.EGG) {
                        Text("·", color = GMColors.dim, style = style)
                        Text("Nível ${s.level}", color = GMColors.dim, style = style)
                        Text("·", color = GMColors.dim, style = style)
                        Text(home.mood.label, color = GMColors.dim, style = style)
                    }
                }
            }

            Column(Modifier.fillMaxWidth().padding(horizontal = 4.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                GMProgressBar(s.progress)
                Row(Modifier.fillMaxWidth()) {
                    val style = GMType.caption.copy(fontFeatureSettings = "tnum")
                    Text("${s.totalXP} XP", color = GMColors.dim, style = style)
                    Spacer(Modifier.weight(1f))
                    val left = s.xpToNext
                    Text(
                        when {
                            left == null -> "forma final"
                            s.stage == Stage.EGG -> "faltam $left XP para chocar"
                            else -> "faltam $left XP para evoluir"
                        },
                        color = GMColors.dim, style = style,
                    )
                }
            }

            if (s.stage == Stage.EGG) {
                Text(
                    if (s.totalXP == 0) "Registre seu primeiro treino para aquecer o ovo." else "Ele está se mexendo… continue treinando!",
                    color = GMColors.dim, style = GMType.footnote, textAlign = TextAlign.Center,
                )
            }
        }
    }
}

@Composable
private fun AttributesCard(home: HomeData) {
    val s = home.snapshot
    val attrs = s.stageAttributes
    val max = maxOf(attrs.values.maxOrNull() ?: 0.0, 1.0)
    val next = s.nextForm
    GMCard(padding = 18.dp) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("Treinos desta fase", color = Color.White, style = GMType.headline)
            Spacer(Modifier.weight(1f))
            if (next != null && next.stage.branches && attrs.isNotEmpty()) {
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text("tende a virar", color = GMColors.dim, style = GMType.caption)
                    Text(next.name, color = next.attribute?.color() ?: Color.White, style = GMType.caption.copy(fontWeight = FontWeight.Bold))
                }
            }
        }
        for (a in Attribute.entries) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Box(Modifier.width(20.dp), contentAlignment = Alignment.Center) {
                    Icon(Symbols.of(a), null, tint = a.color(), modifier = Modifier.size(17.dp))
                }
                Text(a.label, color = Color.White, style = GMType.subheadline, maxLines = 1, modifier = Modifier.width(96.dp))
                GMProgressBar((attrs[a] ?: 0.0) / max, Modifier.weight(1f), tint = a.color())
                Text("${(attrs[a] ?: 0.0).toInt()}", color = GMColors.dim, style = GMType.caption.copy(fontFeatureSettings = "tnum"),
                     textAlign = TextAlign.End, modifier = Modifier.width(34.dp))
            }
        }
        Text(
            if (next?.stage?.branches == true) "O atributo que você mais treinar até a próxima evolução decide a forma."
            else "Cada atividade soma em atributos diferentes.",
            color = GMColors.dim, style = GMType.caption,
        )
    }
}

@Composable
private fun RecentCard(home: HomeData, onSeeAll: () -> Unit) {
    GMCard(padding = 18.dp) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("Últimas atividades", color = Color.White, style = GMType.headline)
            Spacer(Modifier.weight(1f))
            Text("Ver tudo", color = GMColors.accent, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold),
                 modifier = Modifier.gmPress(onClick = onSeeAll))
        }
        for (a in home.recent) ActivityRow(a, Modifier.gmPress(onClick = onSeeAll))
    }
}

private val dayMonth = DateTimeFormatter.ofPattern("d 'de' MMM", Locale.forLanguageTag("pt-BR"))

/** Linha de atividade (HomeView.swift `ActivityRow`) */
@Composable
fun ActivityRow(a: HomeActivity, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box {
            Box(Modifier.size(40.dp).background(GMColors.raised, GMRadius.s), contentAlignment = Alignment.Center) {
                Icon(Symbols.of(a.typeSymbol), null, tint = Color.White, modifier = Modifier.size(22.dp))
            }
            if (a.bros.isNotEmpty()) BroAvatars(a.bros, Modifier.align(Alignment.BottomEnd).offset(6.dp, 6.dp), size = 18.dp)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(a.typeName, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
            val date = a.date.atZone(ZoneId.systemDefault()).format(dayMonth)
            Text("${ActivityText.duration(a.minutes)} · ${ActivityText.effortLabel(a.effort)} · $date", color = GMColors.dim, style = GMType.caption)
            a.destinations?.let {
                Text(it, color = GMColors.accent, style = GMType.caption2.copy(fontWeight = FontWeight.SemiBold), maxLines = 1,
                     overflow = TextOverflow.Ellipsis)
            }
        }
        if (a.fromHealth) {
            Icon(Icons.Filled.Favorite, null, tint = GMColors.health,
                 modifier = Modifier.size(11.dp).semantics { contentDescription = "Do app Saúde" })
        }
        Text("+${a.xp} XP", color = GMColors.accent, style = GMType.subheadline.copy(fontWeight = FontWeight.Bold, fontFeatureSettings = "tnum"))
    }
}

/** Balão de fala do bro, com a pontinha apontando para ele (HomeView.swift `SpeechBubble`) */
@Composable
fun SpeechBubble(text: String, emoji: String) {
    Box(Modifier.padding(bottom = 4.dp)) {
        Row(
            Modifier.fillMaxWidth()
                .drawBehind {
                    // Pontinha embaixo, no meio: 16 × 8
                    val w = 16.dp.toPx(); val h = 8.dp.toPx()
                    val path = Path().apply {
                        moveTo(size.width / 2 - w / 2, size.height)
                        lineTo(size.width / 2 + w / 2, size.height)
                        lineTo(size.width / 2, size.height + h)
                        close()
                    }
                    drawPath(path, GMColors.raised)
                }
                .background(GMColors.raised, GMRadius.m).padding(12.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.Top,
        ) {
            Text(emoji, fontSize = 20.sp)
            Text(text, color = Color.White, style = GMType.subheadline, modifier = Modifier.weight(1f))
        }
    }
}
