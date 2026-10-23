package com.alonsoalmeida.gymbros.ui.train

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.alonsoalmeida.gymbros.data.FriendsRepository
import com.alonsoalmeida.gymbros.data.train.TrainData
import com.alonsoalmeida.gymbros.data.train.TrainEdits
import com.alonsoalmeida.gymbros.data.train.TrainScope
import com.alonsoalmeida.gymbros.domain.MonsterForm
import com.alonsoalmeida.gymbros.domain.train.ExerciseType
import com.alonsoalmeida.gymbros.domain.train.Exercises
import com.alonsoalmeida.gymbros.domain.train.Routine
import com.alonsoalmeida.gymbros.domain.train.RoutineItem
import com.alonsoalmeida.gymbros.ui.AppEnv
import com.alonsoalmeida.gymbros.ui.components.GMButton
import com.alonsoalmeida.gymbros.ui.components.GMButtonKind
import com.alonsoalmeida.gymbros.ui.components.GMCard
import com.alonsoalmeida.gymbros.ui.components.GMChoiceChips
import com.alonsoalmeida.gymbros.ui.components.GMDivider
import com.alonsoalmeida.gymbros.ui.components.GMEmptyState
import com.alonsoalmeida.gymbros.ui.components.GMModal
import com.alonsoalmeida.gymbros.ui.components.GMScreen
import com.alonsoalmeida.gymbros.ui.components.GMSection
import com.alonsoalmeida.gymbros.ui.components.MonsterSprite
import com.alonsoalmeida.gymbros.ui.components.TrainIcons
import com.alonsoalmeida.gymbros.ui.components.gmPress
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMType
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.Query
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.intOrNull
import java.time.Instant

/** Rotina publicada (PublicRoutines.swift `PublicRoutine`); `authorID` "me" = sua */
data class PublicRoutine(val id: String, val name: String, val authorID: String, val authorName: String, val authorFormID: String,
                         val items: List<RoutineItem>, val likes: Int, val saves: Int, val createdAt: Instant) {
    val author: MonsterForm get() = MonsterForm.byID(authorFormID) ?: MonsterForm.EGG
    val setCount: Int get() = items.sumOf { it.sets }
}

/**
 * `routines/{id}` no Firestore, com os mesmos campos do iOS (FirebaseGame.swift `FirebaseRoutinesBackend`): só o autor edita;
 * os outros só mexem em curtidas e cópias, de 1 em 1 (firestore.rules). Quem você curtiu fica nos ajustes da conta
 * (`routines.liked`), como no iPhone. Consulta limitada às 300 mais novas (plano grátis).
 */
object PublicRoutinesRepository {
    private val db get() = FirebaseFirestore.getInstance()
    private val col get() = db.collection("routines")
    val all = MutableStateFlow<List<PublicRoutine>>(emptyList())

    private fun itemsJson(items: List<RoutineItem>): String =
        JsonArray(items.map { JsonObject(mapOf("exerciseID" to JsonPrimitive(it.exerciseID), "sets" to JsonPrimitive(it.sets), "reps" to JsonPrimitive(it.reps),
                                                "rest" to JsonPrimitive(it.rest))) }).toString()

    private fun items(raw: Any?): List<RoutineItem>? = (raw as? String)?.let { s ->
        runCatching {
            (Json.parseToJsonElement(s) as JsonArray).mapIndexed { i, e ->
                val o = e as JsonObject
                RoutineItem((o["exerciseID"] as JsonPrimitive).content, (o["sets"] as JsonPrimitive).intOrNull ?: 3, (o["reps"] as JsonPrimitive).intOrNull ?: 10,
                            (o["rest"] as? JsonPrimitive)?.intOrNull ?: 90, i)
            }
        }.getOrNull()
    }

    suspend fun refresh(me: String) {
        val docs = runCatching { col.orderBy("createdAt", Query.Direction.DESCENDING).limit(300).get().await().documents }.getOrNull() ?: return
        all.value = docs.mapNotNull { d ->
            val user = d.getString("user") ?: return@mapNotNull null
            PublicRoutine(d.id, d.getString("name").orEmpty(), if (user == me) "me" else user, d.getString("authorName").orEmpty(),
                          d.getString("authorFormID") ?: MonsterForm.EGG.id, items(d.get("items")) ?: return@mapNotNull null,
                          (d.getLong("likes") ?: 0).toInt(), (d.getLong("saves") ?: 0).toInt(),
                          d.getTimestamp("createdAt", com.google.firebase.firestore.DocumentSnapshot.ServerTimestampBehavior.ESTIMATE)?.toDate()?.toInstant() ?: Instant.now())
        }
    }

    suspend fun publish(me: String, r: Routine, name: String, formID: String) {
        val ref = col.document(r.uuid)
        val exists = runCatching { ref.get().await().exists() }.getOrDefault(false)
        val data = hashMapOf<String, Any>("user" to me, "name" to r.name, "authorName" to name.ifEmpty { "Você" }, "authorFormID" to formID,
                                          "items" to itemsJson(r.sortedItems))
        // Republicar mantém curtidas, cópias e a data
        if (!exists) data += mapOf("likes" to 0, "saves" to 0, "createdAt" to FieldValue.serverTimestamp())
        runCatching { ref.set(data, com.google.firebase.firestore.SetOptions.merge()).await() }
        refresh(me)
    }

    suspend fun unpublish(me: String, id: String) { runCatching { col.document(id).delete().await() }; refresh(me) }

    suspend fun like(me: String, id: String, on: Boolean) {
        runCatching { col.document(id).update("likes", FieldValue.increment(if (on) 1 else -1)).await() }
        refresh(me)
    }

    suspend fun saved(me: String, id: String) { runCatching { col.document(id).update("saves", FieldValue.increment(1)).await() }; refresh(me) }
}

/** Ids das suas rotinas que estão publicadas (para o "· pública" e o menu) */
@Composable
internal fun rememberPublished(env: AppEnv): Set<String> {
    val all by PublicRoutinesRepository.all.collectAsState()
    LaunchedEffect(env.uid) { PublicRoutinesRepository.refresh(env.uid) }
    return all.filter { it.authorID == "me" }.map { it.id.uppercase() }.toSet()
}

internal fun publishRoutine(env: AppEnv, data: TrainData, r: Routine) {
    TrainScope.scope.launch { PublicRoutinesRepository.publish(env.uid, r, data.trainerName, data.lastFormID ?: MonsterForm.EGG.id) }
}

internal fun unpublishRoutine(env: AppEnv, r: Routine) { TrainScope.scope.launch { PublicRoutinesRepository.unpublish(env.uid, r.uuid) } }

private enum class RoutineSort(val label: String) { SAVED("Mais salvas"), LIKED("Mais curtidas"), NEWEST("Novas"), FRIENDS("Dos amigos") }

/** Explorar rotinas públicas (PublicRoutines.swift `PublicRoutinesView`) */
@Composable
internal fun PublicRoutinesScreen(env: AppEnv, data: TrainData, nav: TrainNav) {
    val all by PublicRoutinesRepository.all.collectAsState()
    var sort by remember { mutableStateOf(RoutineSort.SAVED) }
    var opened by remember { mutableStateOf<String?>(null) }
    var friends by remember { mutableStateOf<Set<String>>(emptySet()) }
    LaunchedEffect(Unit) { PublicRoutinesRepository.refresh(env.uid) }
    LaunchedEffect(sort) {
        if (sort == RoutineSort.FRIENDS) friends = runCatching { FriendsRepository().fetch(emptySet(), emptySet()).friends.map { it.id }.toSet() }.getOrDefault(friends)
    }
    val list = when (sort) {
        RoutineSort.SAVED -> all.sortedByDescending { it.saves }
        RoutineSort.LIKED -> all.sortedByDescending { it.likes }
        RoutineSort.NEWEST -> all.sortedByDescending { it.createdAt }
        RoutineSort.FRIENDS -> all.filter { it.authorID in friends }.sortedByDescending { it.createdAt }
    }
    GMScreen("Rotinas públicas", bottomInset = 120.dp, leading = { BackButton(nav) }) {
        GMChoiceChips(RoutineSort.entries.map { it to it.label }, sort, { sort = it })
        if (list.isEmpty()) {
            GMEmptyState(TrainIcons.of("person.2"), if (sort == RoutineSort.FRIENDS) "Nenhuma rotina dos seus amigos" else "Nenhuma rotina ainda",
                         "Publique uma rotina sua pelo menu dela em Treinar.")
        }
        for (r in list) {
            Column(Modifier.gmPress { opened = r.id }) {
                GMCard {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Thumb(r.items.firstOrNull()?.exerciseID ?: "", 56.dp)
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            Text(r.name, color = Color.White, style = GMType.headline, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                                MonsterSprite(r.author, Modifier.size(18.dp))
                                Text(if (r.authorID == "me") "Você" else r.authorName, color = Color.White, style = GMType.caption.copy(fontWeight = FontWeight.SemiBold))
                            }
                            Text("${r.items.size} exercícios · ${r.setCount} séries · ❤️ ${r.likes} · 📥 ${r.saves}", color = GMColors.dim, style = GMType.caption)
                        }
                        Chevron()
                    }
                }
            }
        }
    }
    val current = all.firstOrNull { it.id == opened }
    if (current != null) PublicRoutineDetail(env, data, current) { opened = null }
}

@Composable
private fun PublicRoutineDetail(env: AppEnv, data: TrainData, r: PublicRoutine, onDismiss: () -> Unit) {
    var saved by remember { mutableStateOf(false) }
    val liked = r.id in data.liked
    GMModal(true, r.name, onDismiss) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            MonsterSprite(r.author, Modifier.size(36.dp))
            Text("por ${if (r.authorID == "me") "você" else r.authorName}", color = Color.White, style = GMType.subheadline, modifier = Modifier.weight(1f))
            Text("❤️ ${r.likes} · 📥 ${r.saves}", color = GMColors.dim, style = GMType.subheadline)
        }
        GMSection("Exercícios") {
            r.items.forEachIndexed { i, item ->
                if (i > 0) GMDivider()
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Thumb(item.exerciseID, 40.dp)
                    Text(Exercises.name(item.exerciseID), color = Color.White, style = GMType.subheadline.copy(fontWeight = FontWeight.SemiBold), modifier = Modifier.weight(1f))
                    val t = Exercises.byID(item.exerciseID)?.type
                    Text("${item.sets} × ${item.reps}${if (t == ExerciseType.TIME || t == ExerciseType.DISTANCE) " s" else ""}", color = GMColors.dim, style = GMType.subheadline)
                }
            }
        }
        if (r.authorID != "me") {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                GMButton(if (liked) "Curtida" else "Curtir", {
                    val on = !liked
                    TrainScope.edit(env) { TrainEdits.strings(it, "routines.liked", (if (on) data.liked + r.id else data.liked - r.id).toList()) }
                    TrainScope.scope.launch { PublicRoutinesRepository.like(env.uid, r.id, on) }
                }, Modifier.weight(1f), icon = TrainIcons.of(if (liked) "heart.fill" else "heart"), kind = GMButtonKind.SECONDARY)
                GMButton(if (saved) "Salva nas suas rotinas" else "Salvar cópia", {
                    saved = true
                    TrainScope.edit(env) { TrainEdits.saveRoutine(it, Routine(TrainEdits.newID(), r.name, order = data.routines.size, items = r.items.mapIndexed { i, x -> x.copy(order = i) })) }
                    TrainScope.scope.launch { PublicRoutinesRepository.saved(env.uid, r.id) }
                }, Modifier.weight(1f), icon = TrainIcons.of(if (saved) "checkmark" else "square.and.arrow.down"), enabled = !saved)
            }
        }
    }
}
