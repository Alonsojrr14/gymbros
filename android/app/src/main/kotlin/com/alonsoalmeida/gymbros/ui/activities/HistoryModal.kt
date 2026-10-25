package com.alonsoalmeida.gymbros.ui.activities

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.automirrored.filled.DirectionsRun
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.Watch
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.alonsoalmeida.gymbros.domain.ActivityText
import com.alonsoalmeida.gymbros.domain.Attribute
import com.alonsoalmeida.gymbros.domain.activities.ActivityEdits
import com.alonsoalmeida.gymbros.domain.backup.AccountEdits
import com.alonsoalmeida.gymbros.domain.home.HomeData
import com.alonsoalmeida.gymbros.domain.profile.ProfileActivity
import com.alonsoalmeida.gymbros.ui.AppEnv
import com.alonsoalmeida.gymbros.ui.components.GMButton
import com.alonsoalmeida.gymbros.ui.components.GMButtonKind
import com.alonsoalmeida.gymbros.ui.components.GMCard
import com.alonsoalmeida.gymbros.ui.components.GMEmptyState
import com.alonsoalmeida.gymbros.ui.components.GMIconButton
import com.alonsoalmeida.gymbros.ui.components.GMModal
import com.alonsoalmeida.gymbros.ui.components.GMSection
import com.alonsoalmeida.gymbros.ui.components.PersonAvatar
import com.alonsoalmeida.gymbros.ui.components.Symbols
import com.alonsoalmeida.gymbros.ui.log.LogActivityScreen
import com.alonsoalmeida.gymbros.ui.profile.ConfirmDialog
import com.alonsoalmeida.gymbros.ui.profile.Hairline
import com.alonsoalmeida.gymbros.ui.profile.ProfileActivityRow
import com.alonsoalmeida.gymbros.ui.profile.ValueRow
import com.alonsoalmeida.gymbros.ui.profile.profileViewModel
import com.alonsoalmeida.gymbros.ui.profile.ptBR
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMRadius
import com.alonsoalmeida.gymbros.ui.theme.GMType
import com.alonsoalmeida.gymbros.ui.theme.color
import java.time.ZoneId
import java.time.format.DateTimeFormatter

private val dayTitle = DateTimeFormatter.ofPattern("EEEE, d 'de' MMMM", ptBR)
private val dateTime = DateTimeFormatter.ofPattern("EEEE, d 'de' MMMM, HH:mm", ptBR)

/** Histórico ("Ver tudo": Activities/HistoryView.swift): resumo e as atividades por dia; cada uma abre o detalhe */
@Composable
fun HistoryModal(visible: Boolean, env: AppEnv, home: HomeData, onDismiss: () -> Unit) {
    if (!visible) return
    val ui by profileViewModel(env).state.collectAsStateWithLifecycle()
    var detail by rememberSaveable { mutableStateOf<String?>(null) }
    val zone = ZoneId.systemDefault()
    GMModal(true, "Histórico", onDismiss) {
        val acts = ui?.data?.activities ?: return@GMModal
        if (acts.isEmpty()) {
            GMEmptyState(Icons.AutoMirrored.Filled.DirectionsRun, "Nenhuma atividade ainda", "Seus treinos aparecem aqui.")
            return@GMModal
        }
        Summary(acts, home)
        // Lista de tamanho variável dentro da rolagem do modal; os dias saem em ordem, os mais novos primeiro
        for ((day, items) in acts.groupBy { it.date.atZone(zone).toLocalDate() }.toSortedMap(compareByDescending { it })) {
            GMSection(day.format(dayTitle).replaceFirstChar { it.uppercase() }) {
                items.sortedByDescending { it.date }.forEachIndexed { i, a ->
                    if (i > 0) Hairline()
                    ProfileActivityRow(a.copy(xp = home.snapshot.xpByActivity[a.id] ?: a.xp)) { detail = a.id }
                }
            }
        }
    }
    ActivityDetailModal(detail, env, home) { detail = null }
}

@Composable
private fun Summary(acts: List<ProfileActivity>, home: HomeData) {
    val total = acts.sumOf { it.minutes }
    val attrs = home.snapshot.lifetimeAttributes
    val sum = attrs.values.sum().coerceAtLeast(1.0)
    GMCard {
        Row(Modifier.fillMaxWidth()) {
            for ((v, l) in listOf("${acts.size}" to "atividades", (if (total >= 60) "${total / 60} h" else "$total min") to "treinando",
                                  "${home.snapshot.totalXP}" to "XP")) {
                Column(Modifier.weight(1f).semantics(mergeDescendants = true) {}, horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(v, color = Color.White, style = GMType.title3.copy(fontWeight = FontWeight.ExtraBold, fontFeatureSettings = "tnum"))
                    Text(l, color = GMColors.dim, style = GMType.caption)
                }
            }
        }
        Row(Modifier.fillMaxWidth().height(10.dp).clip(CircleShape), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
            for (a in Attribute.entries) {
                val w = ((attrs[a] ?: 0.0) / sum).toFloat()
                if (w > 0f) Box(Modifier.weight(w).height(10.dp).background(a.color()))
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            for (a in Attribute.entries) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp),
                    modifier = Modifier.semantics(mergeDescendants = true) { contentDescription = "${a.label} ${Math.round((attrs[a] ?: 0.0) / sum * 100)}%" }) {
                    Icon(Symbols.of(a), null, tint = a.color(), modifier = Modifier.size(14.dp))
                    Text("${Math.round((attrs[a] ?: 0.0) / sum * 100)}%", color = a.color(), style = GMType.caption.copy(fontWeight = FontWeight.SemiBold))
                }
            }
        }
    }
}

/**
 * Detalhe de uma atividade (Activities/ActivityDetail.swift): dados, onde foi publicada, as séries do treino guiado,
 * editar e apagar. Foto de check-in, percurso, Stories e postar pelo lápis ainda não chegaram ao Android.
 */
@Composable
fun ActivityDetailModal(activityID: String?, env: AppEnv, home: HomeData, onDismiss: () -> Unit) {
    if (activityID == null) return
    val vm = profileViewModel(env)
    val ui by vm.state.collectAsStateWithLifecycle()
    var editing by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }
    var sets by remember { mutableStateOf(false) }
    val train = com.alonsoalmeida.gymbros.ui.train.rememberTrainData(env)
    val a = ui?.data?.activities?.firstOrNull { it.id.equals(activityID, true) }
    // Apagada aqui ou no outro aparelho: a tela fecha
    if (ui != null && a == null) {
        androidx.compose.runtime.LaunchedEffect(Unit) { onDismiss() }
        return
    }
    GMModal(true, a?.typeName ?: "Atividade", onDismiss) {
        if (a == null) return@GMModal
        Row(Modifier.fillMaxWidth()) {
            Spacer(Modifier.weight(1f))
            GMIconButton(Icons.Filled.Edit, "Editar atividade", { editing = true })
        }
        val title = a.postTitle ?: a.note.ifEmpty { a.typeName }
        GMCard {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Box(Modifier.size(48.dp).background(GMColors.raised, GMRadius.m), contentAlignment = Alignment.Center) {
                    Icon(Symbols.of(a.typeSymbol), null, tint = Color.White, modifier = Modifier.size(26.dp))
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(title, color = Color.White, style = GMType.headline)
                    Text(a.date.atZone(ZoneId.systemDefault()).format(dateTime), color = GMColors.dim, style = GMType.caption)
                    a.source?.let { src ->
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                            Icon(Icons.Filled.Watch, null, tint = GMColors.dim, modifier = Modifier.size(12.dp))
                            Text("Gravado no $src", color = GMColors.dim, style = GMType.caption2)
                        }
                    }
                }
                Text("+${home.snapshot.xpByActivity[a.id] ?: a.xp} XP", color = GMColors.accent, style = GMType.headline.copy(fontFeatureSettings = "tnum"))
            }
            Hairline()
            ValueRow("Duração", ActivityText.duration(a.minutes))
            ValueRow("Esforço", "${a.effort}/10 · ${ActivityText.effortLabel(a.effort)}")
            a.place?.let { ValueRow("Local", it) }
            // O iPhone importa do Apple Saúde e o Android do Health Connect; o registro não diz de qual veio
            if (a.fromHealth) ValueRow("Origem", "Apple Saúde / Health Connect")
            a.postNote?.takeIf { it.isNotEmpty() }?.let {
                Hairline()
                Text(it, color = Color.White, style = GMType.subheadline)
            }
        }

        val leagues = home.leagues.associateBy { it.uuid.uppercase() }
        val dests = a.postedIn.sortedBy { id -> if (id == ActivityEdits.PROFILE_FEED) -1 else home.leagues.indexOfFirst { it.uuid.equals(id, true) }.let { if (it < 0) 999 else it } }
        GMSection("Publicado em", footer = if (dests.isEmpty()) "Ainda não foi postada. Para postar no perfil ou numa liga, abra uma liga, toque em \"Novo check-in\" e escolha \"Já registrada\" (vale para os últimos 7 dias)." else null) {
            if (dests.isEmpty()) Text("Nenhum destino", color = GMColors.dim, style = GMType.subheadline)
            dests.forEachIndexed { i, id ->
                if (i > 0) Hairline()
                val isProfile = id == ActivityEdits.PROFILE_FEED
                val league = leagues[id]
                Row(Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    if (isProfile) PersonAvatar(home.trainerName, size = 40.dp, photo = home.profilePhoto)
                    else Box(Modifier.size(40.dp).background(GMColors.raised, CircleShape), contentAlignment = Alignment.Center) {
                        if (league?.emoji.isNullOrEmpty()) Icon(Icons.Filled.EmojiEvents, null, tint = GMColors.trophy, modifier = Modifier.size(20.dp))
                        else Text(league!!.emoji, style = GMType.title3)
                    }
                    Column(Modifier.weight(1f)) {
                        Text(if (isProfile) "Meu perfil" else league?.name ?: "Liga removida", color = Color.White,
                             style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold))
                        Text(if (isProfile) "Visível no seu perfil público" else if (league?.end != null) "Liga encerrada" else "Liga",
                             color = GMColors.dim, style = GMType.caption)
                    }
                }
            }
        }
        // Treino guiado ligado: "Ver séries" abre o treino feito, como no iPhone (o WOD não tem essa seção lá)
        train.sessions.firstOrNull { it.activityUUID.equals(a.id, true) }?.let { s ->
            GMSection("Treino") {
                com.alonsoalmeida.gymbros.ui.components.GMRow("Ver séries", com.alonsoalmeida.gymbros.ui.components.TrainIcons.of("list.bullet.rectangle"),
                    subtitle = "${s.doneWorkSets.size} séries · ${s.exerciseIDs.size} exercícios", chevron = true, onClick = { sets = true })
            }
        }
        GMButton("Apagar atividade", { confirmDelete = true }, icon = Icons.Filled.Delete, kind = GMButtonKind.SECONDARY)
    }
    if (a != null) {
        LogActivityScreen(editing, home, onDismiss = { editing = false }, initial = AccountEdits.NewActivity(
            a.kind.raw, a.date, a.minutes, a.effort, a.note, a.type, "", a.gymUUID, id = a.id,
        ), onSave = { n ->
            vm.editActivity(a.id, ActivityEdits.Change(n.type, com.alonsoalmeida.gymbros.domain.ActivityKind.of(n.kind), n.date, n.minutes,
                                                       n.effort, n.note, n.gymUUID))
            editing = false
        })
    }
    if (a != null) {
        val session = train.sessions.firstOrNull { it.activityUUID.equals(a.id, true) }
        com.alonsoalmeida.gymbros.ui.train.TrainPageModal(if (sets && session != null) "session/${session.uuid}" else null, env, home) { sets = false }
    }
    if (confirmDelete && a != null) {
        ConfirmDialog("Apagar atividade?", "Os check-ins dela no perfil e nas ligas também somem.", "Apagar",
                      onConfirm = { onDismiss(); vm.deleteActivity(a.id) }, onDismiss = { confirmDelete = false })
    }
}
