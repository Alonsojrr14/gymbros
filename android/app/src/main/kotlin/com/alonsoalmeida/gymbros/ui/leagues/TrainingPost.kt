package com.alonsoalmeida.gymbros.ui.leagues

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.alonsoalmeida.gymbros.GymBrosApp
import com.alonsoalmeida.gymbros.data.leagues.LeagueStore
import com.alonsoalmeida.gymbros.domain.backup.AccountEdits
import com.alonsoalmeida.gymbros.domain.home.HomeData
import com.alonsoalmeida.gymbros.domain.leagues.League
import com.alonsoalmeida.gymbros.domain.leagues.LeagueActivityJson
import com.alonsoalmeida.gymbros.domain.leagues.PostSubject
import com.google.firebase.auth.FirebaseAuth
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import java.time.Instant

/**
 * "Postar em" no fim do treino guiado e do WOD (WorkoutView.swift `FinishWorkoutView`, Wod.swift): a mesma seção do
 * registro de atividade, com a foto, e o check-in em cada destino escolhido depois de salvar (postCheckIns).
 */
class TrainingPost internal constructor(val vm: LeaguesViewModel, private val scope: CoroutineScope) {
    internal var leagues: List<League> = emptyList()
    var publish: Boolean = false
        internal set
    var destinations by mutableStateOf(setOf<String>())
    var photo by mutableStateOf<PickedPhoto?>(null)
    var extras by mutableStateOf(listOf<ByteArray>())

    /** Toda atividade vai para pelo menos um lugar quando a conta pode postar (hasPostDestination) */
    val canSave: Boolean get() = hasPostDestination(publish, destinations)

    fun post(activity: LeagueActivityJson, title: String, note: String) {
        val chosen = destinations
        if (!publish || chosen.isEmpty()) return
        val p = photo
        val more = extras
        scope.launch { vm.store.post(LeagueStore.NewPost(activity, title, note, p?.bytes, p?.proof, p?.pose, more), chosen, leagues) }
    }
}

@Composable
fun rememberTrainingPost(home: HomeData): TrainingPost {
    val app = LocalContext.current.applicationContext as GymBrosApp
    val uid = FirebaseAuth.getInstance().currentUser?.uid.orEmpty()
    val vm: LeaguesViewModel = viewModel(key = "leagues-$uid", factory = viewModelFactory {
        initializer { LeaguesViewModel(LeagueStore.of(app, uid, app.container.copies)) }
    })
    val ui by vm.ui.collectAsStateWithLifecycle()
    val roles by vm.roles.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    val post = remember(vm) { TrainingPost(vm, scope) }
    post.leagues = ui.leagues
    post.publish = canPublish(home, roles)
    return post
}

@Composable
fun TrainingPostSection(home: HomeData, post: TrainingPost, subject: PostSubject) {
    val app = LocalContext.current.applicationContext as GymBrosApp
    val roles by post.vm.roles.collectAsStateWithLifecycle()
    val ui by post.vm.ui.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    LeaguePostSection(
        home, ui.leagues, roles, post.destinations, { post.destinations = it }, post.photo, { post.photo = it }, post.extras, { post.extras = it },
        subject = subject,
        onAcceptTerms = {
            scope.launch {
                app.container.copies.edit { c ->
                    AccountEdits.updateSettings(c ?: AccountEdits.empty(home.trainerName, Instant.now())) {
                        it["termsAcceptedVersion"] = com.dd.plist.NSNumber(2); it["termsAcceptedAt"] = com.dd.plist.NSDate(java.util.Date())
                    }
                }
            }
        },
    )
}
