package com.alonsoalmeida.gymbros.ui.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.alonsoalmeida.gymbros.data.AccountCopyRepository
import com.alonsoalmeida.gymbros.data.CopyState
import com.alonsoalmeida.gymbros.data.account.ProfilePublisher
import com.alonsoalmeida.gymbros.domain.MonsterForm
import com.alonsoalmeida.gymbros.domain.Roster
import com.alonsoalmeida.gymbros.domain.RuleClock
import com.alonsoalmeida.gymbros.domain.activities.ActivityEdits
import com.alonsoalmeida.gymbros.domain.backup.AccountCopy
import com.alonsoalmeida.gymbros.domain.backup.AccountEdits
import com.alonsoalmeida.gymbros.domain.home.HomeBuilder
import com.alonsoalmeida.gymbros.domain.profile.BodyEdits
import com.alonsoalmeida.gymbros.domain.profile.ContentFilter
import com.alonsoalmeida.gymbros.domain.profile.ProfileBuilder
import com.alonsoalmeida.gymbros.domain.profile.ProfileData
import com.alonsoalmeida.gymbros.domain.profile.ProfileEdits
import com.dd.plist.NSDate
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.time.Instant
import java.time.ZoneId
import java.util.Date

/** O que as telas de perfil, ajustes, histórico e peso leem: os dados prontos e o roster (dono do XP de cada atividade) */
data class ProfileUiState(val data: ProfileData, val roster: Roster, val mainNick: String, val mainForm: MonsterForm, val mainID: String?)

/**
 * Perfil, ajustes, histórico, detalhe e peso (a frente de perfil). Lê a cópia de trabalho da conta e grava nela como o
 * iPhone grava; o que é público (nome, @usuário, bio, números) também vai para `profiles/{uid}` ao salvar.
 */
class ProfileViewModel(private val copies: AccountCopyRepository, private val publisher: ProfilePublisher = ProfilePublisher()) : ViewModel() {
    val state: StateFlow<ProfileUiState?> = copies.state.map { s -> (s as? CopyState.Ready)?.let { build(it.copy) } }
        .flowOn(Dispatchers.Default).stateIn(viewModelScope, SharingStarted.Eagerly, null)

    private val _message = MutableStateFlow<String?>(null)
    /** Aviso passageiro (falha ao publicar o perfil, por exemplo) */
    val message: StateFlow<String?> = _message.asStateFlow()

    private fun build(copy: JsonObject?): ProfileUiState {
        val clock = RuleClock(ZoneId.systemDefault(), Instant.now())
        val home = HomeBuilder.build(copy?.let(AccountCopy::decode), clock)
        val data = ProfileBuilder.build(copy, home.roster, clock)
        val main = home.roster.main
        return ProfileUiState(data, home.roster, main?.name.orEmpty(), home.snapshot.form, main?.uuid)
    }

    private fun edit(change: (JsonObject) -> JsonObject) = viewModelScope.launch {
        copies.edit { copy -> change(copy ?: AccountEdits.empty("", Instant.now())) }
    }

    fun clearMessage() { _message.value = null }

    /** Editar perfil: nome, @usuário e bio só passam com o filtro de palavras; depois o perfil público acompanha */
    fun saveProfile(name: String, username: String, bio: String): Boolean {
        if (!ContentFilter.allows(name, username, bio)) return false
        viewModelScope.launch {
            copies.edit { copy ->
                ProfileEdits.setAll(copy ?: AccountEdits.empty(name, Instant.now()),
                                    mapOf("trainerName" to name.trim(), "profileUsername" to username, "profileBio" to bio))
            }
            publish()
        }
        return true
    }

    /** Interruptores de "O que aparece para os outros" (`publicPhoto`, `publicMonster`, `publicStats`, `publicAchievements`) */
    fun setVisibility(key: String, on: Boolean) = viewModelScope.launch {
        copies.edit { copy -> ProfileEdits.set(copy ?: AccountEdits.empty("", Instant.now()), key, on) }
        if (key == "publicPhoto") publishAvatar() else publish()
    }

    /** Nome do treinador digitado em Ajustes → Perfil e bro (o iPhone grava a cada letra) */
    fun setTrainerName(name: String) = edit { ProfileEdits.set(it, "trainerName", name) }

    /** Apelido do bro principal (`Monster.name`) */
    fun setNick(id: String, nick: String) = edit { copy ->
        val list = (copy["monsters"] as? JsonArray) ?: return@edit copy
        val next = list.map { e ->
            val m = e as? JsonObject
            if (m == null || (m["uuid"] as? JsonPrimitive)?.content?.equals(id, true) != true) e
            else JsonObject(LinkedHashMap<String, JsonElement>(m).apply { put("name", JsonPrimitive(nick)) })
        }
        JsonObject(LinkedHashMap<String, JsonElement>(copy).apply { put("monsters", JsonArray(next)) })
    }

    fun setSetting(key: String, value: Any?) = edit { ProfileEdits.set(it, key, value) }

    /**
     * Foto do perfil escolhida na galeria: vira um JPEG quadrado de 512 (`avatarPhoto` do iOS), vai para a conta e, se
     * "Foto do perfil" estiver ligada, a miniatura vai para os outros
     */
    fun setPhotoFrom(read: () -> ByteArray?) = viewModelScope.launch {
        val jpeg = withContext(Dispatchers.IO) { runCatching { read()?.let(ProfilePublisher::avatarPhoto) }.getOrNull() }
        if (jpeg == null) { _message.value = "Não consegui abrir essa foto."; return@launch }
        copies.edit { copy -> ProfileEdits.setPhoto(copy ?: AccountEdits.empty("", Instant.now()), jpeg) }
        publishAvatar()
    }

    private suspend fun publishAvatar() {
        val ui = state.value
        val copy = (copies.state.value as? CopyState.Ready)?.copy
        val photo = (copy?.get("profilePhoto") as? JsonPrimitive)?.content?.let { runCatching { java.util.Base64.getDecoder().decode(it) }.getOrNull() }
        val show = ProfileEdits.bool(ProfileEdits.settings(copy), "publicPhoto", true)
        if (ui == null && copy == null) return
        withContext(Dispatchers.IO) { runCatching { publisher.publishAvatar(photo, show) } }
    }

    /** Registrar atividade pelo perfil (o mesmo registro da tela inicial) */
    fun addActivity(a: AccountEdits.NewActivity) = edit { AccountEdits.addActivity(it, a) }

    fun deleteActivity(id: String) {
        val roster = state.value?.roster ?: return
        edit { ActivityEdits.delete(it, id, roster) }
    }

    fun editActivity(id: String, change: ActivityEdits.Change) = edit { ActivityEdits.edit(it, id, change) }

    fun saveBody(id: String?, values: BodyEdits.Values) = edit { BodyEdits.save(it, id, values).first }

    fun deleteBody(id: String) = edit { BodyEdits.delete(it, id) }

    /** Apresentação (OnboardingView.receive/start): aceite dos termos, ovo e nome, nessa ordem */
    fun onboard(name: String) = viewModelScope.launch {
        copies.edit { copy ->
            val base = copy ?: AccountEdits.empty("", Instant.now())
            ProfileEdits.setAll(acceptTerms(base), mapOf("lastFormID" to MonsterForm.EGG.id, "trainerName" to name.trim()))
        }
    }

    /** Termos com versão nova (TermsRequiredView) */
    fun acceptTerms() = edit(::acceptTerms)

    private fun acceptTerms(copy: JsonObject): JsonObject = ProfileEdits.setAll(copy, mapOf(
        TERMS_KEY to TERMS_VERSION, "termsAcceptedAt" to NSDate(Date()),
    ))

    private suspend fun publish() {
        val s = (copies.state.value as? CopyState.Ready)?.copy ?: return
        val ui = build(s)
        runCatching {
            publisher.publish(ui.data.name, ui.data.username, ui.data.bio, ui.data.publicNumbers.takeIf { ui.data.showStats }, ui.data.showAchievements)
        }.onFailure { _message.value = "Salvo na conta. O perfil público atualiza quando a internet voltar." }
    }

    companion object {
        const val TERMS_KEY = "termsAcceptedVersion"
        /** `Terms.version` do iOS */
        const val TERMS_VERSION = 2
    }
}
