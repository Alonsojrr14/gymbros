package com.alonsoalmeida.gymbros.ui.friends

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.alonsoalmeida.gymbros.data.AccountCopyRepository
import com.alonsoalmeida.gymbros.data.CopyState
import com.alonsoalmeida.gymbros.data.FriendError
import com.alonsoalmeida.gymbros.data.FriendException
import com.alonsoalmeida.gymbros.data.FriendsRepository
import com.alonsoalmeida.gymbros.data.FriendsState
import com.alonsoalmeida.gymbros.data.LeagueMember
import com.alonsoalmeida.gymbros.data.PublicProfile
import com.alonsoalmeida.gymbros.data.PublicBro
import com.alonsoalmeida.gymbros.domain.backup.AccountEdits
import com.alonsoalmeida.gymbros.domain.RuleClock
import com.alonsoalmeida.gymbros.domain.home.HomeData
import com.alonsoalmeida.gymbros.domain.profile.ProfileBuilder
import com.dd.plist.NSDate
import com.dd.plist.NSNumber
import com.dd.plist.NSString
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Instant
import java.util.Date

/** Sugestão de "Talvez você conheça": quem está nas suas ligas e ainda não é amigo */
data class Suggestion(val member: LeagueMember, val leagues: List<Pair<String, String>>)

/**
 * Amigos (Friends.swift `FriendsStore`). Permissões vêm de `roles/{uid}` (só leitura; as regras do Firestore são a
 * autoridade). Código de amigo, pedidos recusados e termos aceitos ficam nos ajustes da conta e vão para o iPhone.
 */
class FriendsViewModel(private val repo: FriendsRepository, private val copies: AccountCopyRepository,
                       private val photosRepo: com.alonsoalmeida.gymbros.data.ProfilePhotosRepository) : ViewModel() {
    private val _photos = MutableStateFlow<Map<String, ByteArray>>(emptyMap())
    /** Fotos de perfil de quem aparece na tela (quem não tem ou escondeu fica de fora: mostra a inicial) */
    val photos: StateFlow<Map<String, ByteArray>> = _photos.asStateFlow()

    private var stopWatching: (() -> Unit)? = null
    private var watched: List<String> = emptyList()
    private var versions: Map<String, String> = emptyMap()
    /** Tela de amigos aberta e app na frente: só então escuta (economiza o limite do plano grátis) */
    private var watching = false

    /** Quem aparece na tela: amigos, pedidos e sugestões */
    private fun shownIDs() = (_state.value.friends.map { it.id } + _state.value.incoming.map { it.id } +
        _suggestions.value.map { it.member.id }).distinct().sorted()

    private fun loadPhotos(@Suppress("UNUSED_PARAMETER") extra: Collection<String> = emptyList()) {
        if (!watching) return
        val list = shownIDs()
        if (list == watched) return
        watched = list
        stopWatching?.invoke()
        stopWatching = photosRepo.watch(list) { id, version ->
            if (versions[id] == version && (version.isEmpty() || id in _photos.value)) return@watch
            versions = versions + (id to version)
            viewModelScope.launch {
                val data = photosRepo.photo(id, version)
                if (versions[id] != version) return@launch
                _photos.value = if (data != null) _photos.value + (id to data) else _photos.value - id
            }
        }
    }

    /** Tela aberta (e app na frente): escuta as versões das fotos de quem aparece */
    fun startWatching() {
        watching = true
        watched = emptyList()
        loadPhotos()
    }

    fun stopWatching() {
        watching = false
        stopWatching?.invoke()
        stopWatching = null
        watched = emptyList()
    }

    override fun onCleared() {
        stopWatching?.invoke()
    }

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
            loadPhotos()
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
        // O bro do perfil público acompanha o seu (forma, apelido e nível), como no iPhone
        val s = home.snapshot
        val bro = PublicBro(home.monsterName.ifEmpty { s.form.name }, s.form.id, s.level, s.progress)
        runCatching { photosRepo.publish(home.profilePhoto, home.showPhoto) }
        // "Bros e atributos" acompanham os treinos, como o iPhone publica ao abrir; sem a cópia da conta, ficam como estão
        val copy = (copies.state.value as? CopyState.Ready)?.copy
        val data = copy?.let { withContext(Dispatchers.Default) {
            runCatching { ProfileBuilder.build(it, home.roster, RuleClock(java.time.ZoneId.systemDefault(), Instant.now())) }.getOrNull()
        } }
        runCatching { repo.publishBro(code, bro, home.showBro, data?.publicBros?.takeIf { data.showBros }, updateBros = data != null) }.onSuccess { used ->
            if (used != code) copies.edit { copy -> AccountEdits.updateSettings(copy ?: AccountEdits.empty(home.trainerName, Instant.now())) { it["friendCode"] = NSString(used) } }
        }
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
                .onSuccess { f ->
                    runCatching { repo.fetch(home.declinedFriends, blocked) }.onSuccess { _state.value = it }
                    // Amizade são os dois lados: sem o pedido do outro, o que saiu foi só o seu pedido
                    _message.value = if (_state.value.friends.any { it.id == f.id }) "${f.name} agora é seu amigo 🎉"
                                     else "Pedido de amizade enviado para ${f.name}."
                    refresh(home)
                }
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
