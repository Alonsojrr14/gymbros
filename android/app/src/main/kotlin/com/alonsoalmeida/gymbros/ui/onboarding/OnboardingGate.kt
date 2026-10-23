package com.alonsoalmeida.gymbros.ui.onboarding

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckBox
import androidx.compose.material.icons.filled.CheckBoxOutlineBlank
import androidx.compose.material.icons.filled.VerifiedUser
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.foundation.border
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.toggleableState
import androidx.compose.ui.state.ToggleableState
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.LifecycleResumeEffect
import com.alonsoalmeida.gymbros.domain.MonsterForm
import com.alonsoalmeida.gymbros.domain.home.HomeData
import com.alonsoalmeida.gymbros.ui.AppEnv
import com.alonsoalmeida.gymbros.ui.auth.GMTextField
import com.alonsoalmeida.gymbros.ui.auth.LegalModal
import com.alonsoalmeida.gymbros.ui.components.GMButton
import com.alonsoalmeida.gymbros.ui.components.GMScreen
import com.alonsoalmeida.gymbros.ui.components.LivingMonster
import com.alonsoalmeida.gymbros.ui.components.gmPress
import com.alonsoalmeida.gymbros.ui.legal.Legal
import com.alonsoalmeida.gymbros.ui.profile.ProfileViewModel
import com.alonsoalmeida.gymbros.ui.profile.profileViewModel
import com.alonsoalmeida.gymbros.ui.settings.settingsViewModel
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMRadius
import com.alonsoalmeida.gymbros.ui.theme.GMType

/**
 * Portões depois de abrir a conta (App.swift `RootView`): sem nome de treinador → apresentação (OnboardingView),
 * termos com versão nova → aceite (TermsRequiredView); senão o app, que ao voltar para a frente importa os treinos novos
 * do Health Connect (se ligado).
 */
@Composable
fun OnboardingGate(env: AppEnv, home: HomeData, content: @Composable () -> Unit) {
    val vm = profileViewModel(env)
    when {
        home.trainerName.isEmpty() -> OnboardingScreen(home.termsVersion >= ProfileViewModel.TERMS_VERSION) { vm.onboard(it) }
        home.termsVersion < ProfileViewModel.TERMS_VERSION -> TermsRequiredScreen { vm.acceptTerms() }
        else -> {
            val settings = settingsViewModel(env)
            LifecycleResumeEffect(Unit) {
                settings.autoSync()
                onPauseOrDispose {}
            }
            content()
        }
    }
}

/** Apresentação (App/OnboardingView.swift): o nome, o aceite e o ovo. O passo do treino ao vivo ainda não chegou ao Android */
@Composable
private fun OnboardingScreen(alreadyAccepted: Boolean, onStart: (String) -> Unit) {
    val haptic = LocalHapticFeedback.current
    var name by rememberSaveable { mutableStateOf("") }
    var received by rememberSaveable { mutableStateOf(false) }
    var agreed by rememberSaveable { mutableStateOf(alreadyAccepted) }
    val nameOK = name.isNotBlank()
    val scale by animateFloatAsState(if (received) 1.1f else 0.9f, spring(dampingRatio = 0.6f), label = "egg")

    Column(
        Modifier.fillMaxSize().background(GMColors.bg).safeDrawingPadding().imePadding().verticalScroll(rememberScrollState())
            .padding(horizontal = 24.dp, vertical = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(28.dp),
    ) {
        Spacer(Modifier.size(24.dp))
        AnimatedContent(received, transitionSpec = { fadeIn() togetherWith fadeOut() }, label = "title") { r ->
            Text(if (r) "Este ovo é seu!" else "GymBros", color = Color.White, fontSize = 34.sp, fontWeight = FontWeight.ExtraBold, maxLines = 1)
        }
        LivingMonster(MonsterForm.EGG, Modifier.size(180.dp).graphicsLayer { scaleX = scale; scaleY = scale }, progress = if (received) 0.4 else 0.1)
        Text(
            if (received) "Dentro dele está o seu bro, seu parceiro de treino. Ele choca com seus treinos: musculação, corrida, vôlei, o que você fizer conta. E o jeito que você treina decide no que ele vai se transformar."
            else "Todo treinador começa com um ovo. Como você se chama?",
            color = GMColors.dim, style = GMType.body, textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 8.dp),
        )
        if (!received) {
            GMTextField(name, { name = it }, "Seu nome",
                        keyboard = KeyboardOptions(capitalization = KeyboardCapitalization.Words, imeAction = ImeAction.Done))
            if (!alreadyAccepted) LegalConsent(agreed) { agreed = it }
        }
        Spacer(Modifier.weight(1f))
        GMButton(if (received) "Começar a jornada" else "Receber meu ovo", {
            if (!received) {
                if (nameOK && agreed) {
                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                    received = true
                }
            } else onStart(name.trim())
        }, enabled = nameOK && agreed)
    }
}

/** Termos com versão nova (TermsView.swift `TermsRequiredView`) */
@Composable
private fun TermsRequiredScreen(onAccept: () -> Unit) {
    val haptic = LocalHapticFeedback.current
    var accepted by rememberSaveable { mutableStateOf(false) }
    GMScreen("Termos e privacidade") {
        Text("Os termos mudaram. Leia e aceite para continuar.", color = GMColors.dim, style = GMType.subheadline)
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(Icons.Filled.VerifiedUser, null, tint = GMColors.accent, modifier = Modifier.size(36.dp))
            Text("Antes de continuar", color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.ExtraBold)
            Text("Abra cada documento para ler e marque que concorda. O GymBros tem tolerância zero para conteúdo ofensivo e abuso.",
                 color = GMColors.dim, style = GMType.subheadline)
        }
        LegalConsent(accepted) { accepted = it }
        GMButton("Aceitar e continuar", { haptic.performHapticFeedback(HapticFeedbackType.LongPress); onAccept() },
                 icon = Icons.Filled.Check, enabled = accepted)
    }
}

/**
 * Aceite (TermsView.swift `LegalConsent`): uma caixa para cada documento; a linha marca e desmarca, o nome do documento
 * abre o texto. Só vale com as duas marcadas.
 */
@Composable
private fun LegalConsent(accepted: Boolean, onChange: (Boolean) -> Unit) {
    var agreed by rememberSaveable { mutableStateOf(if (accepted) listOf("terms", "privacy") else emptyList()) }
    var open by rememberSaveable { mutableStateOf<String?>(null) }
    val haptic = LocalHapticFeedback.current
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        for ((doc, article, title) in listOf(Triple("terms", "os", "Termos de uso"), Triple("privacy", "a", "Política de privacidade"))) {
            val on = doc in agreed
            Row(
                Modifier.fillMaxWidth().background(GMColors.card, GMRadius.l)
                    .border(1.dp, if (on) GMColors.accent.copy(alpha = 0.6f) else GMColors.stroke, GMRadius.l)
                    .gmPress(role = Role.Checkbox) {
                        haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                        agreed = if (on) agreed - doc else agreed + doc
                        onChange(agreed.size == 2)
                    }
                    .semantics {
                        toggleableState = ToggleableState(on)
                        contentDescription = "Li e concordo com $article $title"
                        customActions = listOf(CustomAccessibilityAction("Ler $article $title") { open = doc; true })
                    }
                    .padding(horizontal = 8.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Box(Modifier.size(44.dp), contentAlignment = Alignment.Center) {
                    Icon(if (on) Icons.Filled.CheckBox else Icons.Filled.CheckBoxOutlineBlank, null,
                         tint = if (on) GMColors.accent else Color.White, modifier = Modifier.size(26.dp))
                }
                Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically) {
                    Text("Li e concordo com $article ", color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
                    Text(title, color = GMColors.accent, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold,
                                                                                         textDecoration = TextDecoration.Underline),
                         modifier = Modifier.gmPress { open = doc })
                }
            }
        }
    }
    LegalModal(open == "terms", "Termos de uso", Legal.terms, "Atualizados", onDismiss = { open = null })
    LegalModal(open == "privacy", "Privacidade", Legal.privacy, "Atualizada", onDismiss = { open = null })
}
