package com.alonsoalmeida.gymbros.ui.components

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Message
import androidx.compose.material.icons.filled.Block
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.SentimentSatisfied
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.WifiTethering
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.alonsoalmeida.gymbros.domain.Attribute
import com.alonsoalmeida.gymbros.domain.MonsterForm
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMType
import com.alonsoalmeida.gymbros.ui.theme.color

/** Linha fina entre itens (GMSurfaces.swift `GMDivider`) */
@Composable
fun GMDivider(modifier: Modifier = Modifier) = Box(modifier.fillMaxWidth().height(1.dp).background(GMColors.stroke))

/** Abas em cápsula (GMChips.swift `GMSegmented`): a escolhida em verde */
@Composable
fun <T> GMSegmented(options: List<Pair<T, String>>, selection: T, onSelect: (T) -> Unit, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth().background(GMColors.card, CircleShape).padding(4.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        for ((value, label) in options) {
            val on = value == selection
            val bg by animateColorAsState(if (on) GMColors.accent else Color.Transparent, spring(), label = "seg")
            Text(label, color = if (on) Color.Black else Color.White.copy(alpha = 0.75f), maxLines = 1, overflow = TextOverflow.Ellipsis,
                 textAlign = TextAlign.Center, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold),
                 modifier = Modifier.weight(1f).defaultMinSize(minHeight = 40.dp).background(bg, CircleShape)
                     .gmPress(role = Role.Tab) { onSelect(value) }.semantics { selected = on }.padding(vertical = 9.dp))
        }
    }
}

/** Uma ação de folha (GMSheets.swift `GMAction`) */
data class GMAction(val title: String, val icon: ImageVector? = null, val destructive: Boolean = false, val action: () -> Unit)

/** Folha de ações (gmActions do iOS): título, mensagem, um botão por ação e "Cancelar" */
@Composable
fun GMActions(visible: Boolean, onDismiss: () -> Unit, title: String? = null, message: String? = null, actions: List<GMAction>) {
    if (!visible) return
    GMSheet(onDismiss = onDismiss) {
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (title != null) Text(title, color = Color.White, style = GMType.headline, textAlign = TextAlign.Center)
            if (message != null) Text(message, color = GMColors.dim, style = GMType.subheadline, textAlign = TextAlign.Center)
            for (a in actions) GMButton(a.title, { onDismiss(); a.action() }, icon = a.icon,
                                         kind = if (a.destructive) GMButtonKind.DANGER else GMButtonKind.SECONDARY)
            GMButton("Cancelar", onDismiss, kind = GMButtonKind.GHOST)
        }
    }
}

/** Número de não lidas (GMSettings.swift `GMCountBadge`) */
@Composable
fun GMCountBadge(count: Int, tint: Color = GMColors.badge) {
    Text(if (count > 99) "99+" else "$count", color = if (tint == GMColors.accent) Color.Black else Color.White, fontSize = 11.sp,
         fontWeight = FontWeight.Black, textAlign = TextAlign.Center,
         modifier = Modifier.defaultMinSize(20.dp, 20.dp).background(tint, CircleShape).padding(horizontal = 6.dp, vertical = 2.dp)
             .clearAndSetSemantics { contentDescription = "$count não lidas" })
}

/** Campo do comentário e da mensagem: cápsula do card, cresce até `maxLines` (TextField com axis .vertical do iOS) */
@Composable
fun ComposerField(value: String, onChange: (String) -> Unit, placeholder: String, modifier: Modifier = Modifier, maxLines: Int = 5,
                  trailing: @Composable () -> Unit = {}) {
    Row(modifier.background(GMColors.card, androidx.compose.foundation.shape.RoundedCornerShape(24.dp)).padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.weight(1f)) {
            if (value.isEmpty()) Text(placeholder, color = GMColors.dim, style = GMType.body)
            androidx.compose.foundation.text.BasicTextField(
                value, onChange, maxLines = maxLines, textStyle = GMType.body.copy(color = Color.White),
                cursorBrush = androidx.compose.ui.graphics.SolidColor(GMColors.accent),
                keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(capitalization = androidx.compose.ui.text.input.KeyboardCapitalization.Sentences),
                modifier = Modifier.fillMaxWidth().semantics { contentDescription = placeholder },
            )
        }
        trailing()
    }
}

/** Bolinha verde de "treinando agora" */
@Composable
fun GMOnlineDot(size: Dp = 8.dp) = Box(Modifier.size(size).background(GMColors.online, CircleShape))

/** Aviso de texto barrado pelo filtro de palavras, perto do campo (ContentFilter.swift `ContentBlockedNote`) */
@Composable
fun ContentBlockedNote() {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Filled.Warning, null, tint = GMColors.danger, modifier = Modifier.size(16.dp))
        Text(com.alonsoalmeida.gymbros.domain.social.ContentFilter.MESSAGE, color = GMColors.danger,
             style = GMType.footnote.copy(fontWeight = FontWeight.SemiBold))
    }
}

/** Bro da pessoa num círculo, com o ícone do tipo de notificação no canto (InboxView.swift `InboxAvatar`) */
@Composable
fun InboxAvatar(form: MonsterForm, size: Dp = 46.dp, badge: ImageVector? = null, tint: Color = GMColors.accent, live: Boolean = false) {
    Box(Modifier.size(size)) {
        Box(Modifier.size(size).background(GMColors.raised, CircleShape).border(2.dp, if (live) GMColors.online else Color.Transparent, CircleShape),
            contentAlignment = Alignment.Center) { MonsterSprite(form, Modifier.size(size * 0.74f)) }
        if (badge != null) {
            Box(Modifier.align(Alignment.BottomEnd).offset(3.dp, 3.dp).size(size * 0.42f).background(tint, CircleShape)
                    .border(2.dp, GMColors.card, CircleShape), contentAlignment = Alignment.Center) {
                Icon(badge, null, tint = Color.Black, modifier = Modifier.size(size * 0.22f))
            }
        }
    }
}

/** Ícone e cor de cada tópico de notificação (NotificationPrefs.swift `NotificationTopic`) */
object SocialSymbols {
    val messages: ImageVector = Icons.AutoMirrored.Filled.Message
    val cheers: ImageVector = Icons.Filled.Bolt
    val invites: ImageVector = Icons.Filled.Group
    val friendsTraining: ImageVector = Icons.Filled.WifiTethering
    val reactions: ImageVector = Icons.Filled.SentimentSatisfied
    val friendRequests: ImageVector = Icons.Filled.PersonAdd
    val leagues: ImageVector = Icons.Filled.EmojiEvents
    val more: ImageVector = Icons.Filled.MoreHoriz
    val flag: ImageVector = Icons.Filled.Flag
    val block: ImageVector = Icons.Filled.Block
    val eye: ImageVector = Icons.Filled.Visibility
    val eyeSlash: ImageVector = Icons.Filled.VisibilityOff

    val messagesTint = GMColors.info
    val cheersTint = GMColors.accent
    val invitesTint get() = Attribute.AGILIDADE.color()
    val trainingTint = GMColors.online
    val reactionsTint = GMColors.streak
    val requestsTint get() = Attribute.TECNICA.color()
}
