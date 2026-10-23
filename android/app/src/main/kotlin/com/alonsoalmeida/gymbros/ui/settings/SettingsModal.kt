package com.alonsoalmeida.gymbros.ui.settings

import android.content.Intent
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.HelpOutline
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.automirrored.filled.DirectionsWalk
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FitnessCenter
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.NoAccounts
import androidx.compose.material.icons.filled.PanTool
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material.icons.filled.SystemUpdate
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.health.connect.client.PermissionController
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.alonsoalmeida.gymbros.data.health.HealthConnectSync
import com.alonsoalmeida.gymbros.domain.Attribute
import com.alonsoalmeida.gymbros.domain.home.HomeData
import com.alonsoalmeida.gymbros.domain.profile.ContentFilter
import com.alonsoalmeida.gymbros.domain.profile.ProfileEdits
import com.alonsoalmeida.gymbros.ui.AppEnv
import com.alonsoalmeida.gymbros.ui.auth.GMTextField
import com.alonsoalmeida.gymbros.ui.auth.LegalModal
import com.alonsoalmeida.gymbros.ui.components.GMButton
import com.alonsoalmeida.gymbros.ui.components.GMButtonKind
import com.alonsoalmeida.gymbros.ui.components.GMModal
import com.alonsoalmeida.gymbros.ui.components.GMSection
import com.alonsoalmeida.gymbros.ui.components.MonsterSprite
import com.alonsoalmeida.gymbros.ui.components.PersonAvatar
import com.alonsoalmeida.gymbros.ui.components.gmPress
import com.alonsoalmeida.gymbros.ui.legal.Legal
import com.alonsoalmeida.gymbros.ui.profile.ConfirmDialog
import com.alonsoalmeida.gymbros.ui.profile.Hairline
import com.alonsoalmeida.gymbros.ui.profile.NavRow
import com.alonsoalmeida.gymbros.ui.profile.ToggleRow
import com.alonsoalmeida.gymbros.ui.profile.ValueRow
import com.alonsoalmeida.gymbros.ui.profile.profileViewModel
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMRadius
import com.alonsoalmeida.gymbros.ui.theme.GMType
import com.alonsoalmeida.gymbros.ui.theme.color
import kotlinx.coroutines.launch

private enum class Page { PROFILE, TRAINING, HEALTH, ACCOUNT, PRIVACY, HOW }

/**
 * Ajustes (App/SettingsView.swift + SettingsPages.swift): cartão do perfil e grupos que levam às telas de cada assunto.
 * O que o Android ainda não tem (notificações, música, backup em arquivo, Pro, "Vem aí", tutorial, diagnóstico) fica de
 * fora em vez de aparecer quebrado.
 */
@Composable
fun SettingsModal(visible: Boolean, env: AppEnv, home: HomeData, onDismiss: () -> Unit) {
    if (!visible) return
    val error by env.signOutError.collectAsStateWithLifecycle()
    val vm = settingsViewModel(env)
    val health by vm.healthState.collectAsStateWithLifecycle()
    val profile by profileViewModel(env).state.collectAsStateWithLifecycle()
    var page by rememberSaveable { mutableStateOf<Page?>(null) }
    var confirmSignOut by remember { mutableStateOf(false) }
    val settings = profile?.data?.settings.orEmpty()
    LaunchedEffect(Unit) { vm.refresh() }

    GMModal(true, "Ajustes", onDismiss) {
        Hero(env, home, profile?.mainNick.orEmpty()) { page = Page.PROFILE }

        GMSection("App") {
            val warmup = ProfileEdits.bool(settings, "autoWarmup", true)
            NavRow(Icons.Filled.FitnessCenter, GMColors.streak, "Treino", if (warmup) "Aquecimento ligado" else null) { page = Page.TRAINING }
            if (health.available || health.needsUpdate) {
                Hairline()
                NavRow(Icons.Filled.Favorite, GMColors.health, "Health Connect", if (health.enabled) "Importando" else "Desligado") { page = Page.HEALTH }
            }
        }

        GMSection("Conta e dados") {
            NavRow(Icons.Filled.AccountCircle, GMColors.info, "Conta", "E-mail") { page = Page.ACCOUNT }
            Hairline()
            NavRow(Icons.Filled.PanTool, Attribute.TECNICA.color(), "Privacidade") { page = Page.PRIVACY }
        }

        GMSection("Ajuda") {
            NavRow(Icons.AutoMirrored.Filled.HelpOutline, Attribute.AGILIDADE.color(), "Como funciona") { page = Page.HOW }
        }

        GMSection(footer = error) {
            NavRow(Icons.AutoMirrored.Filled.Logout, GMColors.warning, "Sair da conta") { confirmSignOut = true }
        }

        Footer()
    }

    when (page) {
        Page.PROFILE -> ProfileSettingsPage(env) { page = null }
        Page.TRAINING -> TrainingSettingsPage(env) { page = null }
        Page.HEALTH -> HealthSettingsPage(vm) { page = null }
        Page.ACCOUNT -> AccountSettingsPage(env, home, vm) { page = null }
        Page.PRIVACY -> PrivacySettingsPage { page = null }
        Page.HOW -> HowItWorksPage { page = null }
        null -> Unit
    }

    if (confirmSignOut) {
        ConfirmDialog("Sair da conta?", SIGN_OUT_TEXT, "Sair", onConfirm = env.signOut, onDismiss = { confirmSignOut = false })
    }
}

private const val SIGN_OUT_TEXT = "Seus treinos, bros e o resto do progresso ficam salvos na conta e saem deste aparelho. Tudo volta quando você entrar de novo."
private const val ACCOUNT_FOOTER = "Treinos, bros e o resto do progresso são da conta: ao sair, saem do aparelho e voltam quando você entra de novo."
private const val DELETE_TEXT = "Apaga a conta e tudo dela, na conta e neste aparelho: treinos, bros, rotinas, medidas, fotos, recordes, ligas, check-ins, recados, mensagens, amizades, bloqueios e denúncias. Você volta para a tela de entrar. Não dá para desfazer."

/** Você e seu bro, em destaque; abre "Perfil e bro" */
@Composable
private fun Hero(env: AppEnv, home: HomeData, nick: String, onClick: () -> Unit) {
    val form = home.snapshot.form
    val nameOK = ContentFilter.allows(home.trainerName)
    Row(
        Modifier.fillMaxWidth().gmPress(onClick = onClick).clip(GMRadius.card)
            .background(GMColors.card)
            // Brilho verde no canto (o círculo desfocado do iOS)
            .drawBehind {
                val c = androidx.compose.ui.geometry.Offset(size.width - 30.dp.toPx(), -20.dp.toPx())
                drawRect(androidx.compose.ui.graphics.Brush.radialGradient(listOf(GMColors.accent.copy(alpha = 0.22f), Color.Transparent),
                                                                          center = c, radius = 170.dp.toPx()))
            }
            .border(1.dp, GMColors.accent.copy(alpha = 0.25f), GMRadius.card).padding(18.dp)
            .semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        PersonAvatar(home.trainerName, size = 62.dp, photo = home.profilePhoto)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(home.trainerName.ifEmpty { "Treinador" }, color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.ExtraBold,
                 maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (!nameOK) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Icon(Icons.Filled.Warning, null, tint = GMColors.danger, modifier = Modifier.size(13.dp))
                    Text("Nome não permitido", color = GMColors.danger, style = GMType.caption.copy(fontWeight = FontWeight.Bold))
                }
            } else if (env.email.isNotEmpty()) {
                Text(env.email, color = GMColors.dim, style = GMType.caption, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            val broName = if (form.stage == com.alonsoalmeida.gymbros.domain.Stage.EGG || nick.isEmpty()) form.name else nick
            Text("$broName · ${form.stage.label}", color = Color.White, style = GMType.caption.copy(fontWeight = FontWeight.Bold),
                 modifier = Modifier.background(GMColors.raised, CircleShape).padding(horizontal = 10.dp, vertical = 5.dp), maxLines = 1)
        }
        MonsterSprite(form, Modifier.size(64.dp))
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = GMColors.dim, modifier = Modifier.size(20.dp))
    }
}

@Composable
private fun Footer() {
    val context = LocalContext.current
    val version = remember {
        runCatching { context.packageManager.getPackageInfo(context.packageName, 0) }.getOrNull()?.let { info ->
            val code = androidx.core.content.pm.PackageInfoCompat.getLongVersionCode(info)
            "Versão ${info.versionName ?: "1.0"} ($code)"
        } ?: "Versão 1.0"
    }
    Column(Modifier.fillMaxWidth().padding(top = 4.dp), horizontalAlignment = Alignment.CenterHorizontally,
           verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text("GymBros", color = GMColors.accent, fontSize = 15.sp, fontWeight = FontWeight.Black)
        Text(version, color = GMColors.dim, style = GMType.caption2)
    }
}

// MARK: Perfil e bro

@Composable
private fun ProfileSettingsPage(env: AppEnv, onBack: () -> Unit) {
    val vm = profileViewModel(env)
    val ui by vm.state.collectAsStateWithLifecycle()
    val state = ui ?: return
    // Digitado aqui; vai para a conta a cada letra, como o @AppStorage do iOS
    var name by rememberSaveable { mutableStateOf(state.data.name) }
    var nick by rememberSaveable { mutableStateOf(state.mainNick) }
    GMModal(true, "Perfil e bro", onBack) {
        val ok = ContentFilter.allows(name)
        GMSection("Treinador", footer = if (ok) "É o nome que aparece para os amigos e nas ligas."
                                       else "Esse nome tem palavras que não são permitidas e não aparece para os outros. Escolha outro.") {
            GMTextField(name, { name = it; vm.setTrainerName(it) }, "Seu nome")
        }
        state.mainID?.let { id ->
            GMSection("Bro principal", footer = "Vazio usa o nome da forma atual.") {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    MonsterSprite(state.mainForm, Modifier.size(44.dp))
                    Column(Modifier.weight(1f)) { GMTextField(nick, { nick = it; vm.setNick(id, it) }, "Apelido") }
                }
            }
        }
    }
}

// MARK: Treino

@Composable
private fun TrainingSettingsPage(env: AppEnv, onBack: () -> Unit) {
    val vm = profileViewModel(env)
    val ui by vm.state.collectAsStateWithLifecycle()
    val settings = ui?.data?.settings.orEmpty()
    GMModal(true, "Treino", onBack) {
        GMSection("Aquecimento", footer = "Ao começar uma rotina, o primeiro exercício com carga ganha 3 séries leves (40 %, 60 % e 80 % da carga). Elas não contam para recordes, progressão nem volume. No menu ⋯ de cada exercício dá para adicionar ou tirar.") {
            ToggleRow("Aquecimento automático", ProfileEdits.bool(settings, "autoWarmup", true), { vm.setSetting("autoWarmup", it) },
                      icon = Icons.Filled.LocalFireDepartment, tint = GMColors.streak)
        }
        GMSection("Lugares de treino", footer = "Com um lugar salvo no Mapa, o treino em andamento termina sozinho quando você sai de lá (depois de pelo menos alguns minutos).") {
            ToggleRow("Encerrar treino ao sair", ProfileEdits.bool(settings, "gymAutoFinish", true), { vm.setSetting("gymAutoFinish", it) },
                      icon = Icons.AutoMirrored.Filled.DirectionsWalk, tint = GMColors.health)
        }
    }
}

// MARK: Health Connect (Apple Saúde no iOS)

@Composable
private fun HealthSettingsPage(vm: SettingsViewModel, onBack: () -> Unit) {
    val state by vm.healthState.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val ask = rememberLauncherForActivityResult(PermissionController.createRequestPermissionResultContract()) { vm.onPermissions(it) }
    GMModal(true, "Health Connect", onBack) {
        if (state.needsUpdate) {
            GMSection(footer = "O Health Connect deste aparelho precisa de atualização para o GymBros ler os treinos.") {
                NavRow(Icons.Filled.SystemUpdate, GMColors.info, "Atualizar o Health Connect") {
                    val uri = Uri.parse("market://details?id=com.google.android.apps.healthdata&url=healthconnect%3A%2F%2Fonboarding")
                    runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, uri).setPackage("com.android.vending").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
                }
            }
        }
        GMSection("Importar", footer = "Corridas, caminhadas, vôlei e outros treinos gravados pelo relógio ou por outros apps viram atividades automaticamente ao abrir o app (na primeira vez, os últimos 14 dias). Treinos que coincidem com algo já registrado aqui não contam duas vezes.") {
            ToggleRow("Importar treinos do Health Connect", state.enabled, { on ->
                if (!on) vm.turnOff()
                else scope.launch { if (vm.hasAccess()) vm.onPermissions(setOf(HealthConnectSync.WORKOUTS)) else ask.launch(HealthConnectSync.PERMISSIONS) }
            }, icon = Icons.Filled.Favorite, tint = GMColors.health, enabled = state.available)
            if (state.enabled) {
                GMButton(if (state.syncing) "Sincronizando…" else "Sincronizar agora", { vm.syncNow() }, icon = Icons.Filled.Sync,
                         kind = GMButtonKind.SECONDARY, small = true, enabled = !state.syncing)
            }
        }
        GMSection(footer = "Do Health Connect, o GymBros só lê treinos, calorias, distância e peso. Calorias e distância ficam na sua conta e nunca vão para posts nem para o X1. Gravar treinos no Health Connect e postar automaticamente ainda estão chegando no Android.") {
            Text("Só leitura, por enquanto.", color = GMColors.dim, style = GMType.footnote)
        }
        state.status?.let { Text(it, color = GMColors.dim, style = GMType.footnote, modifier = Modifier.padding(horizontal = 4.dp)) }
    }
}

// MARK: Conta

@Composable
private fun AccountSettingsPage(env: AppEnv, home: HomeData, vm: SettingsViewModel, onBack: () -> Unit) {
    val state by vm.accountState.collectAsStateWithLifecycle()
    var confirm by remember { mutableStateOf(false) }
    GMModal(true, "Conta", onBack) {
        GMSection(footer = state.message ?: ACCOUNT_FOOTER) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                com.alonsoalmeida.gymbros.ui.profile.Tile(Icons.Filled.Email, GMColors.info)
                Column(Modifier.weight(1f)) {
                    Text(env.name.ifEmpty { "Sua conta" }, color = Color.White, style = GMType.body)
                    Text(env.email, color = GMColors.dim, style = GMType.caption)
                }
            }
            Hairline()
            ValueRow("Entrou com", "E-mail")
        }
        GMSection("Zona de perigo") {
            NavRow(Icons.Filled.NoAccounts, GMColors.danger, if (state.deleting) "Excluindo…" else "Excluir conta",
                   subtitle = "Apaga a conta e todos os dados") { if (!state.deleting) confirm = true }
        }
    }
    if (confirm) {
        ConfirmDialog("Excluir sua conta?", DELETE_TEXT, "Excluir conta", onConfirm = { vm.deleteAccount(home.friendCode) },
                      onDismiss = { confirm = false })
    }
}

// MARK: Privacidade

@Composable
private fun PrivacySettingsPage(onBack: () -> Unit) {
    var privacy by remember { mutableStateOf(false) }
    var terms by remember { mutableStateOf(false) }
    GMModal(true, "Privacidade", onBack) {
        GMSection(footer = "Seus dados ficam na sua conta. Sem anúncios e sem rastreamento.") {
            NavRow(Icons.Filled.PanTool, GMColors.info, "Política de privacidade") { privacy = true }
            Hairline()
            NavRow(Icons.Filled.Description, Attribute.TECNICA.color(), "Termos de uso") { terms = true }
        }
    }
    LegalModal(privacy, "Privacidade", Legal.privacy, "Atualizada", onDismiss = { privacy = false })
    LegalModal(terms, "Termos de uso", Legal.terms, "Atualizados", onDismiss = { terms = false })
}

// MARK: Como funciona

@Composable
private fun HowItWorksPage(onBack: () -> Unit) {
    GMModal(true, "Como funciona", onBack) {
        for ((title, text) in listOf(
            "XP e atributos" to "Cada atividade rende XP pela duração, tipo e esforço, e soma em Força, Resistência, Agilidade e Técnica. Acima de 150 XP no mesmo dia o ganho cai, com teto de 300 por dia.",
            "Evolução" to "Nas evoluções para Atleta e Lenda, o atributo que você mais treinou na fase decide a forma.",
            "Amigos" to "Mande força para quem está treinando, chame para treinar junto e converse pelas mensagens. Reações nos seus check-ins chegam no sino da tela inicial.",
        )) {
            GMSection(title) { Text(text, color = Color.White.copy(alpha = 0.85f), style = GMType.subheadline) }
        }
    }
}
