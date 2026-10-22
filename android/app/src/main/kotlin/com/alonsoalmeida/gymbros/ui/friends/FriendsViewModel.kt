package com.alonsoalmeida.gymbros.ui.friends

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.alonsoalmeida.gymbros.data.AccountCopyRepository
import com.alonsoalmeida.gymbros.data.FriendError
import com.alonsoalmeida.gymbros.data.FriendException
import com.alonsoalmeida.gymbros.data.FriendsRepository
import com.alonsoalmeida.gymbros.data.FriendsState
import com.alonsoalmeida.gymbros.data.LeagueMember
import com.alonsoalmeida.gymbros.data.PublicProfile
import com.alonsoalmeida.gymbros.domain.backup.AccountEdits
import com.alonsoalmeida.gymbros.domain.home.HomeData
import com.dd.plist.NSDate
import com.dd.plist.NSNumber
import com.dd.plist.NSString
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.Instant
import java.util.Date

/** Sugestão de "Talvez você conheça": quem está nas suas ligas e ainda não é amigo */
data class Suggestion(val member: LeagueMember, val leagues: List<Pair<String, String>>)

/**
 * Amigos (Friends.swift `FriendsStore`). Permissões vêm de `roles/{uid}` (só leitura; as regras do Firestore são a
 * autoridade). Código de amigo, pedidos recusados e termos aceitos ficam nos ajustes da conta e vão para o iPhone.
 */
class FriendsViewModel(private val repo: FriendsRepository, private val copies: AccountCopyRepository) : ViewModel() {
    private val _state = MutableStateFlow(FriendsState())
    val state: StateFlow<FriendsState> = _state.asStateFlow()
    private val _roles = MutableStateFlow<Set<String>?>(null)
    /** null: carregando */
    val roles: StateFlow<Set<String>?> = _roles.asStateFlow()
    private val _profiles = MutableStateFlow<Map<String, PublicProfile>>(emptyMap())
    val profiles: StateFlow<Map<String, PublicProfile>> = _profiles.asStateFlow()
    private val _suggestions = MutableStateFlow<List<Suggestion>>(emptyList())
    val suggestions: StateFlow<List<Suggestion>> = _suggestions.asStateFlow()
    private val _message = MutableStateFlow<String?>(null)
    val message: StateFlow<String?> = _message.asStateFlow()
    private var blocked: Set<String> = emptySet()

    /** USER (ou mais) pode ver e gerenciar amigos; conta desativada (sem papéis) não */
    val canUseFriends: Boolean get() = _roles.value?.isNotEmpty() == true

    fun refresh(home: HomeData) {
        viewModelScope.launch {
            runCatching { _roles.value = repo.roles() }.onFailure { if (_roles.value == null) _roles.value = setOf("USER") }
            if (!canUseFriends) return@launch
            blocked = runCatching { repo.blocked() }.getOrDefault(blocked)
            runCatching { repo.fetch(home.declinedFriends, blocked) }.onSuccess { _state.value = it }
            ensureCode(home)
            loadSuggestions(home)
        }
    }

    /** Conta que nunca abriu o iPhone: gera o código, guarda na conta e publica o perfil mínimo */
    private suspend fun ensureCode(home: HomeData) {
        if (home.termsVersion < TERMS_VERSION) return
        var code = home.friendCode
        if (code == null) {
            code = FriendsRepository.newCode()
            val c = code
            copies.edit { copy -> AccountEdits.updateSettings(copy ?: AccountEdits.empty(home.trainerName, Instant.now())) { it["friendCode"] = NSString(c) } }
        }
        runCatching { repo.publishIfMissing(code, home.trainerName, home.snapshot.form.id) }
    }

    private suspend fun loadSuggestions(home: HomeData) {
        val now = Instant.now()
        val active = home.leagues.filter { !it.isPastSeason && !it.isOver(now) }
        if (active.isEmpty()) { _suggestions.value = emptyList(); return }
        val members = runCatching { repo.members(active.map { it.code }) }.getOrDefault(emptyMap())
        val known = (_state.value.friends + _state.value.incoming).map { it.id }.toSet()
        val found = LinkedHashMap<String, Suggestion>()
        for (l in active) for (m in members[l.code].orEmpty()) {
            if (m.id in known || m.id in blocked) continue
            val s = found[m.id] ?: Suggestion(m, emptyList())
            found[m.id] = s.copy(leagues = s.leagues + (l.emoji to l.name))
        }
        // Quem divide mais ligas com você vem primeiro
        _suggestions.value = found.values.sortedWith(compareByDescending<Suggestion> { it.leagues.size }.thenBy { it.member.name })
    }

    fun addByCode(raw: String, home: HomeData) = add(home) {
        val c = raw.trim().uppercase()
        if (c == home.friendCode) throw FriendException(FriendError.YOURSELF)
        if (_state.value.friends.any { it.code == c }) throw FriendException(FriendError.ALREADY)
        repo.addByCode(c)
    }

    fun addById(id: String, home: HomeData) = add(home) { repo.addById(id) }

    private fun add(home: HomeData, request: suspend () -> com.alonsoalmeida.gymbros.data.RemoteFriend) {
        viewModelScope.launch {
            if (!canUseFriends) { _message.value = FriendError.FORBIDDEN.message; return@launch }
            runCatching { request() }
                .onSuccess { _message.value = "${it.name} agora é seu amigo 🎉"; refresh(home) }
                .onFailure { _message.value = (it as? FriendException)?.message ?: "Não deu para adicionar agora. Confira a internet." }
        }
    }

    fun accept(id: String, home: HomeData) = viewModelScope.launch { runCatching { repo.addById(id) }; refresh(home) }

    /** Recusar: o pedido do outro continua no servidor; some daqui e do iPhone (ajustes da conta) */
    fun decline(id: String, home: HomeData) = viewModelScope.launch {
        copies.edit { copy ->
            AccountEdits.updateSettings(copy ?: AccountEdits.empty(home.trainerName, Instant.now())) {
                it["declinedFriendRequests"] = AccountEdits.nsList(AccountEdits.stringList(it["declinedFriendRequests"]) + id)
            }
        }
        _state.value = _state.value.copy(incoming = _state.value.incoming.filter { it.id != id })
    }

    fun remove(id: String, home: HomeData) = viewModelScope.launch { runCatching { repo.remove(id) }; refresh(home) }

    fun block(id: String, name: String, home: HomeData) = viewModelScope.launch { runCatching { repo.block(id, name) }; refresh(home) }

    fun loadProfile(id: String) = viewModelScope.launch {
        runCatching { repo.profile(id) }.onSuccess { _profiles.value = _profiles.value + (id to it) }
    }

    fun clearMessage() { _message.value = null }

    /** Aceite dos termos de uso, igual ao do iPhone (vai para a conta) */
    fun acceptTerms(home: HomeData) = viewModelScope.launch {
        copies.edit { copy ->
            AccountEdits.updateSettings(copy ?: AccountEdits.empty(home.trainerName, Instant.now())) {
                it["termsAcceptedVersion"] = NSNumber(TERMS_VERSION)
                it["termsAcceptedAt"] = NSDate(Date())
            }
        }
    }

    companion object {
        /** `Terms.version` do iOS */
        const val TERMS_VERSION = 2
    }
}
