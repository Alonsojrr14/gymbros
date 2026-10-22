package com.alonsoalmeida.gymbros.ui.auth

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.autofill.ContentType
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.contentType
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.alonsoalmeida.gymbros.R
import com.alonsoalmeida.gymbros.ui.components.GMButton
import com.alonsoalmeida.gymbros.ui.components.GMModal
import com.alonsoalmeida.gymbros.ui.components.GMOrDivider
import com.alonsoalmeida.gymbros.ui.components.GMSection
import com.alonsoalmeida.gymbros.ui.components.LivingMonster
import com.alonsoalmeida.gymbros.domain.MonsterForm
import com.alonsoalmeida.gymbros.domain.Stage
import com.alonsoalmeida.gymbros.ui.components.gmPress
import com.alonsoalmeida.gymbros.ui.legal.Legal
import com.alonsoalmeida.gymbros.ui.legal.LegalText
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMRadius
import com.alonsoalmeida.gymbros.ui.theme.GMType

/**
 * Entrar ou criar conta, igual ao LoginView do iOS (ios/GymBros/Services/Auth.swift) no modo Firebase: bro bebê
 * animado, "GymBros", subtítulo, Entrar/Criar conta, campos, erro/aviso, "Esqueci minha senha", botão com seta, "ou",
 * texto legal com Termos de uso e Privacidade, e o carregando no centro. Sem o botão da Apple (ADR-009), como no iOS
 * enquanto ele não está ligado.
 */
@Composable
fun LoginScreen(vm: LoginViewModel) {
    val ui by vm.ui.collectAsStateWithLifecycle()
    var showTerms by rememberSaveable { mutableStateOf(false) }
    var showPrivacy by rememberSaveable { mutableStateOf(false) }

    Box(Modifier.fillMaxSize().background(GMColors.bg)) {
        Column(
            Modifier.fillMaxSize().safeDrawingPadding().imePadding().verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp).padding(bottom = 40.dp),
            verticalArrangement = Arrangement.spacedBy(22.dp),
        ) {
            Column(
                Modifier.fillMaxWidth().padding(top = 40.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                LivingMonster(MonsterForm(Stage.BABY, null), Modifier.size(120.dp))
                Text("GymBros", color = GMColors.accent, style = GMType.largeTitle)
                Text("Seus treinos chocam e evoluem um bro.", color = GMColors.dim, style = GMType.subheadline, textAlign = TextAlign.Center)
            }

            GMSegmented(listOf(false to "Entrar", true to "Criar conta"), ui.creating, vm::setCreating)
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                if (ui.creating) {
                    GMTextField(ui.name, vm::setName, "Seu nome", ContentType.PersonFullName,
                                KeyboardOptions(capitalization = KeyboardCapitalization.Words, imeAction = ImeAction.Next))
                }
                GMTextField(ui.email, vm::setEmail, "E-mail", ContentType.EmailAddress + ContentType.Username,
                            KeyboardOptions(keyboardType = KeyboardType.Email, autoCorrectEnabled = false, imeAction = ImeAction.Next))
                // No iOS o campo de senha (SecureField) tem fundo de card e padding 14, diferente do GMTextField
                GMTextField(ui.password, vm::setPassword, "Senha (mínimo 8 caracteres)",
                            if (ui.creating) ContentType.NewPassword else ContentType.Password,
                            KeyboardOptions(keyboardType = KeyboardType.Password, imeAction = ImeAction.Done),
                            secure = true, onDone = { if (ui.canSubmit) vm.submit() })
            }
            ui.error?.let { Message(it, GMColors.danger) }
            ui.notice?.let { Message(it, GMColors.accent) }
            if (!ui.creating) {
                Text(
                    "Esqueci minha senha", color = GMColors.accent, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold),
                    modifier = Modifier.align(Alignment.CenterHorizontally).gmPress(enabled = !ui.busy) { vm.forgot() }.padding(12.dp),
                )
            }
            GMButton(
                if (ui.creating) "Criar conta" else "Entrar",
                onClick = vm::submit,
                icon = if (ui.busy) null else Icons.AutoMirrored.Filled.ArrowForward,
                enabled = ui.canSubmit,
            )
            GMOrDivider()
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("Antes de publicar, você aceita os termos de uso: tolerância zero para conteúdo ofensivo e abuso.",
                     color = GMColors.dim, style = GMType.caption, textAlign = TextAlign.Center)
                Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    LegalLink("Termos de uso") { showTerms = true }
                    LegalLink("Privacidade") { showPrivacy = true }
                }
            }
        }
        if (ui.busy) CircularProgressIndicator(color = GMColors.accent, modifier = Modifier.align(Alignment.Center).size(48.dp))
        LegalModal(showTerms, "Termos de uso", Legal.terms, "Atualizados") { showTerms = false }
        LegalModal(showPrivacy, "Privacidade", Legal.privacy, "Atualizada") { showPrivacy = false }
    }
}

@Composable
private fun Message(text: String, color: Color) =
    Text(text, color = color, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold), textAlign = TextAlign.Center,
         modifier = Modifier.fillMaxWidth())

@Composable
private fun LegalLink(title: String, onClick: () -> Unit) =
    Text(title, color = GMColors.accent, style = GMType.caption.copy(fontWeight = FontWeight.SemiBold),
         modifier = Modifier.gmPress(onClick = onClick).padding(vertical = 12.dp))

/** TermsView / PrivacyPolicyView do iOS: uma seção por tópico e o rodapé com a data e o link para a web */
@Composable
private fun LegalModal(visible: Boolean, title: String, text: LegalText, updatedWord: String, onDismiss: () -> Unit) {
    val uri = LocalUriHandler.current
    GMModal(visible, title, onDismiss) {
        for ((section, body) in text.sections) {
            GMSection(section) { Text(body, color = GMColors.dim, style = GMType.footnote) }
        }
        GMSection(footer = "$updatedWord em ${text.updated}.") {
            Row(Modifier.gmPress(role = Role.Button) { uri.openUri(text.url) }, horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Link, contentDescription = null, tint = GMColors.accent, modifier = Modifier.size(18.dp))
                Text("Ver na web", color = GMColors.accent, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
            }
        }
    }
}

/** GMTextField (fundo `raised`, padding 14×12, raio 12); com `secure`, o campo de senha do iOS (fundo de card, padding 14) */
@Composable
fun GMTextField(
    value: String,
    onChange: (String) -> Unit,
    placeholder: String,
    contentType: ContentType? = null,
    keyboard: KeyboardOptions = KeyboardOptions.Default,
    secure: Boolean = false,
    onDone: () -> Unit = {},
) {
    // Campo de senha: o olho mostra ou oculta o que foi digitado (GMSecureField do iOS)
    var visible by rememberSaveable { mutableStateOf(false) }
    BasicTextField(
        value = value,
        onValueChange = onChange,
        singleLine = true,
        textStyle = GMType.body.copy(color = Color.White),
        cursorBrush = SolidColor(GMColors.accent),
        keyboardOptions = keyboard,
        keyboardActions = KeyboardActions(onDone = { onDone() }),
        visualTransformation = if (secure && !visible) PasswordVisualTransformation() else VisualTransformation.None,
        modifier = Modifier.fillMaxWidth().semantics { contentType?.let { this.contentType = it } },
        decorationBox = { inner ->
            Row(
                Modifier.fillMaxWidth()
                    .background(if (secure) GMColors.card else GMColors.raised, GMRadius.m)
                    .padding(start = 14.dp, end = if (secure) 4.dp else 14.dp, top = if (secure) 4.dp else 12.dp, bottom = if (secure) 4.dp else 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Box(Modifier.weight(1f).padding(vertical = if (secure) 10.dp else 0.dp)) {
                    if (value.isEmpty()) Text(placeholder, color = GMColors.dim, style = GMType.body)
                    inner()
                }
                if (secure) {
                    Box(
                        Modifier.size(40.dp).gmPress { visible = !visible }
                            .semantics { contentDescription = if (visible) "Ocultar senha" else "Mostrar senha" },
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(if (visible) Icons.Filled.VisibilityOff else Icons.Filled.Visibility, contentDescription = null,
                             tint = GMColors.dim, modifier = Modifier.size(22.dp))
                    }
                }
            }
        },
    )
}

/** GMSegmented: pílula de card com a opção escolhida em pílula verde (texto preto); as outras em branco 75% */
@Composable
fun <T> GMSegmented(options: List<Pair<T, String>>, selection: T, onSelect: (T) -> Unit) {
    Row(Modifier.fillMaxWidth().background(GMColors.card, CircleShape).padding(4.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        for ((value, label) in options) {
            val on = value == selection
            val bg by animateColorAsState(if (on) GMColors.accent else Color.Transparent, spring(), label = "seg")
            Box(
                Modifier.weight(1f).background(bg, CircleShape).semantics { selected = on }
                    .gmPress(role = Role.Tab) { onSelect(value) }.padding(vertical = 9.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(label, color = if (on) Color.Black else Color.White.copy(alpha = 0.75f),
                     style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold), maxLines = 1)
            }
        }
    }
}
