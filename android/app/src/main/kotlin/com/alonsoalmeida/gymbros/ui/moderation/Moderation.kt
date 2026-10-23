package com.alonsoalmeida.gymbros.ui.moderation

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Block
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.PanTool
import androidx.compose.material.icons.filled.Sms
import androidx.compose.material.icons.filled.VerifiedUser
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material.icons.filled.MarkEmailUnread
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.alonsoalmeida.gymbros.data.social.SocialCopy
import com.alonsoalmeida.gymbros.domain.social.Moderation
import com.alonsoalmeida.gymbros.domain.social.ReportReason
import com.alonsoalmeida.gymbros.domain.social.ReportedContent
import com.alonsoalmeida.gymbros.domain.social.ReportedKind
import com.alonsoalmeida.gymbros.ui.AppEnv
import com.alonsoalmeida.gymbros.ui.components.GMAction
import com.alonsoalmeida.gymbros.ui.components.GMActions
import com.alonsoalmeida.gymbros.ui.components.GMButton
import com.alonsoalmeida.gymbros.ui.components.GMButtonKind
import com.alonsoalmeida.gymbros.ui.components.GMDivider
import com.alonsoalmeida.gymbros.ui.components.GMModal
import com.alonsoalmeida.gymbros.ui.components.GMSection
import com.alonsoalmeida.gymbros.ui.components.GMSheet
import com.alonsoalmeida.gymbros.ui.components.PersonAvatar
import com.alonsoalmeida.gymbros.ui.copy
import com.alonsoalmeida.gymbros.ui.friends.SocialViewModel
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMType
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** De quem é e o que é (ModerationSheets.swift `ModerationTarget`). Sem `content`, só dá para bloquear a pessoa */
data class ModerationTarget(val userID: String, val userName: String, val content: ReportedContent? = null) {
    val shownName: String get() = userName.ifEmpty { "esta pessoa" }

    constructor(userID: String, userName: String, kind: ReportedKind?, id: String = "") :
        this(userID, userName, kind?.let { ReportedContent(it, id, userID, userName) })

    /** "Denunciar" e "Bloquear" para pôr num menu que já existe */
    fun actions(open: (ModerationRequest) -> Unit): List<GMAction> {
        val list = mutableListOf<GMAction>()
        if (content != null) list += GMAction("Denunciar ${content.kind.title}", Icons.Filled.Flag) { open(ModerationRequest(this, ModerationStep.REPORT)) }
        list += GMAction("Bloquear $shownName", Icons.Filled.Block, destructive = true) { open(ModerationRequest(this, ModerationStep.BLOCK)) }
        return list
    }
}

enum class ModerationStep { MENU, REPORT, BLOCK, THANKS }

data class ModerationRequest(val target: ModerationTarget, val step: ModerationStep = ModerationStep.MENU)

private fun ReportReason.icon(): ImageVector = when (this) {
    ReportReason.OFFENSIVE -> Icons.Filled.Sms
    ReportReason.SEXUAL -> Icons.Filled.VisibilityOff
    ReportReason.VIOLENCE -> Icons.Filled.PanTool
    ReportReason.SPAM -> Icons.Filled.MarkEmailUnread
    ReportReason.OTHER -> Icons.Filled.MoreHoriz
}

/**
 * Menu de denunciar/bloquear, motivo, confirmação do bloqueio e o "obrigado" (ModerationSheets.swift). `onBlocked`: depois
 * de bloquear (ex.: fechar o perfil de quem foi bloqueado).
 */
@Composable
fun ModerationSheets(request: ModerationRequest?, onChange: (ModerationRequest?) -> Unit, vm: SocialViewModel, onBlocked: () -> Unit = {}) {
    val t = request?.target
    val close = { onChange(null) }
    GMActions(request?.step == ModerationStep.MENU, close, title = t?.shownName, actions = t?.actions { onChange(it) }.orEmpty())
    GMActions(request?.step == ModerationStep.REPORT, close, title = "Denunciar ${t?.content?.kind?.title.orEmpty()}",
              message = "Por que você está denunciando? Quem publicou não fica sabendo.",
              actions = t?.content?.let { c ->
                  ReportReason.entries.map { r -> GMAction(r.title, r.icon()) { vm.report(c, r); onChange(ModerationRequest(t, ModerationStep.THANKS)) } }
              }.orEmpty())
    GMActions(request?.step == ModerationStep.BLOCK, close, title = "Bloquear ${t?.shownName.orEmpty()}?",
              message = "Você deixa de ver tudo o que essa pessoa publica e a amizade é desfeita. Ela não recebe aviso, e a pontuação nas ligas não muda. Dá para desbloquear em Ajustes.",
              actions = t?.let { listOf(GMAction("Bloquear", Icons.Filled.Block, destructive = true) { vm.block(it.userID, it.userName); onBlocked() }) }.orEmpty())
    if (request?.step == ModerationStep.THANKS) {
        GMSheet(onDismiss = close) {
            Icon(Icons.Filled.VerifiedUser, null, tint = GMColors.accent, modifier = Modifier.size(40.dp))
            Text("Obrigado pela denúncia", color = Color.White, style = GMType.headline, textAlign = TextAlign.Center)
            Text("O conteúdo já sumiu para você. ${Moderation.REVIEW_NOTE} Para não ver mais nada dessa pessoa, use Bloquear.",
                 color = GMColors.dim, style = GMType.subheadline, textAlign = TextAlign.Center)
            GMButton("Entendi", close)
        }
    }
}

/**
 * Usuários bloqueados (Moderation.swift `BlockedUsersView`), para Ajustes › Privacidade. Ponto de encaixe para a frente
 * de Ajustes: `BlockedUsersModal(visible, env) { fechar }`.
 */
@Composable
fun BlockedUsersModal(visible: Boolean, env: AppEnv, onDismiss: () -> Unit) {
    if (!visible) return
    val vm = SocialViewModel.of(env)
    val blocked = SocialCopy.read(env.copy()).moderation.blocked
    LaunchedEffect(Unit) { vm.refreshBlocked() }
    val fmt = DateTimeFormatter.ofPattern("d 'de' MMM 'de' yyyy", Locale.forLanguageTag("pt-BR"))
    GMModal(true, "Usuários bloqueados", onDismiss) {
        GMSection(footer = "Quem você bloqueia não aparece nos seus feeds, mural, comentários, amigos e mapa. Desbloquear não refaz a amizade: para voltar a ser amigos, adicione a pessoa de novo.") {
            if (blocked.isEmpty()) Text("Ninguém bloqueado.", color = GMColors.dim, style = GMType.subheadline)
            blocked.forEachIndexed { i, u ->
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    PersonAvatar(u.name, size = 40.dp)
                    Column(Modifier.weight(1f)) {
                        Text(u.name, color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
                        Text("Desde ${u.date.atZone(ZoneId.systemDefault()).format(fmt)}", color = GMColors.dim, style = GMType.caption)
                    }
                    Spacer(Modifier.size(4.dp))
                    GMButton("Desbloquear", { vm.unblock(u.id) }, kind = GMButtonKind.SECONDARY, full = false, small = true)
                }
                if (i < blocked.lastIndex) GMDivider()
            }
        }
    }
}
