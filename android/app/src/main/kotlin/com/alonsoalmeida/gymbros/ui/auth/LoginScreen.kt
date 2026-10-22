package com.alonsoalmeida.gymbros.ui.auth

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.autofill.ContentType
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentType
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.alonsoalmeida.gymbros.ui.components.GMButton
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMRadius

/** Entrar ou criar conta (a conta é obrigatória). Espelha o LoginView do iOS, sem o botão da Apple (ADR-009). */
@Composable
fun LoginScreen(vm: LoginViewModel) {
    val ui by vm.ui.collectAsStateWithLifecycle()
    Column(
        Modifier.fillMaxSize().background(GMColors.bg).safeDrawingPadding().imePadding().verticalScroll(rememberScrollState()).padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Column(Modifier.padding(top = 40.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("GymBros", color = GMColors.accent, fontWeight = FontWeight.Black, fontSize = 34.sp)
            Text("Seus treinos chocam e evoluem um bro.", color = GMColors.dim, fontSize = 15.sp, textAlign = TextAlign.Center)
        }
        GMSegmented(listOf(false to "Entrar", true to "Criar conta"), ui.creating, vm::setCreating)
        if (ui.creating) {
            GMTextField(ui.name, vm::setName, "Seu nome", ContentType.PersonFullName,
                        KeyboardOptions(capitalization = KeyboardCapitalization.Words, imeAction = ImeAction.Next))
        }
        GMTextField(ui.email, vm::setEmail, "E-mail", ContentType.EmailAddress + ContentType.Username,
                    KeyboardOptions(keyboardType = KeyboardType.Email, autoCorrectEnabled = false, imeAction = ImeAction.Next))
        GMTextField(ui.password, vm::setPassword, "Senha (mínimo 8 caracteres)",
                    if (ui.creating) ContentType.NewPassword else ContentType.Password,
                    KeyboardOptions(keyboardType = KeyboardType.Password, imeAction = ImeAction.Done),
                    secret = true, onDone = { if (ui.canSubmit) vm.submit() })
        ui.error?.let { Text(it, color = GMColors.danger, fontWeight = FontWeight.SemiBold, fontSize = 15.sp, textAlign = TextAlign.Center) }
        ui.notice?.let { Text(it, color = GMColors.accent, fontWeight = FontWeight.SemiBold, fontSize = 15.sp, textAlign = TextAlign.Center) }
        if (!ui.creating) {
            Text("Esqueci minha senha", color = GMColors.accent, fontWeight = FontWeight.SemiBold, fontSize = 15.sp,
                 modifier = Modifier.heightIn(min = 48.dp).clickable(role = Role.Button, enabled = !ui.busy) { vm.forgot() }.padding(12.dp))
        }
        GMButton(
            title = when {
                ui.busy -> "Aguarde…"
                ui.creating -> "Criar conta"
                else -> "Entrar"
            },
            onClick = { if (ui.canSubmit) vm.submit() },
        )
    }
}

/** GMTextField: campo no card, raio 12 (ios/GymBros/DesignSystem/GMFields.swift) */
@Composable
fun GMTextField(
    value: String,
    onChange: (String) -> Unit,
    placeholder: String,
    contentType: ContentType,
    keyboard: KeyboardOptions,
    secret: Boolean = false,
    onDone: () -> Unit = {},
) {
    BasicTextField(
        value = value,
        onValueChange = onChange,
        singleLine = true,
        textStyle = TextStyle(color = Color.White, fontSize = 17.sp),
        cursorBrush = SolidColor(GMColors.accent),
        keyboardOptions = keyboard,
        keyboardActions = KeyboardActions(onDone = { onDone() }),
        visualTransformation = if (secret) PasswordVisualTransformation() else VisualTransformation.None,
        modifier = Modifier.fillMaxWidth().semantics { this.contentType = contentType },
        decorationBox = { inner ->
            Box(Modifier.fillMaxWidth().heightIn(min = 52.dp).background(GMColors.card, GMRadius.m).padding(14.dp), contentAlignment = Alignment.CenterStart) {
                if (value.isEmpty()) Text(placeholder, color = GMColors.dim, fontSize = 17.sp)
                inner()
            }
        },
    )
}

/** GMSegmented: duas ou mais opções, a escolhida em verde (ios/GymBros/DesignSystem/GMChips.swift) */
@Composable
fun <T> GMSegmented(options: List<Pair<T, String>>, selection: T, onSelect: (T) -> Unit) {
    Row(Modifier.fillMaxWidth().background(GMColors.card, GMRadius.m).padding(4.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        for ((value, label) in options) {
            val on = value == selection
            Box(
                Modifier.weight(1f).heightIn(min = 44.dp)
                    .background(if (on) GMColors.accent else Color.Transparent, GMRadius.s)
                    .semantics { selected = on }
                    .clickable(role = Role.Tab) { onSelect(value) },
                contentAlignment = Alignment.Center,
            ) {
                Text(label, color = if (on) GMColors.onAccent else Color.White, fontWeight = FontWeight.Bold, fontSize = 15.sp)
            }
        }
    }
}
