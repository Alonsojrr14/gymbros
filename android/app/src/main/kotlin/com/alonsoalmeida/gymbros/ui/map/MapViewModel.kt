package com.alonsoalmeida.gymbros.ui.map

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.alonsoalmeida.gymbros.data.AccountCopyRepository
import com.alonsoalmeida.gymbros.data.CopyState
import com.alonsoalmeida.gymbros.data.FriendsRepository
import com.alonsoalmeida.gymbros.data.LiveFriend
import com.alonsoalmeida.gymbros.data.LiveFriendsRepository
import com.alonsoalmeida.gymbros.domain.home.HomeData
import com.alonsoalmeida.gymbros.domain.map.MapData
import com.alonsoalmeida.gymbros.ui.friends.FriendsViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.Instant

data class MapUiState(
    val data: MapData = MapData.build(null, Instant.now()),
    /** Amigos treinando agora ou que terminaram há menos de 12 h, ao vivo primeiro */
    val live: List<LiveFriend> = emptyList(),
    /** Termos aceitos e conta com permissão social (SocialGate `.friendsRead`); null: ainda conferindo */
    val social: Boolean? = null,
    val hasFriends: Boolean = false,
)

/**
 * Aba Mapa em lista (MapScreen.swift). Lugares, idas e percursos vêm da cópia da conta. Os amigos ao vivo só são
 * escutados com a aba visível e o app na frente (ADR-013): `start()`/`stop()` seguem o ciclo de vida da tela.
 */
class MapViewModel(
    private val copies: AccountCopyRepository,
    private val friendsRepo: FriendsRepository,
    private val liveRepo: LiveFriendsRepository,
) : ViewModel() {
    private val _state = MutableStateFlow(MapUiState())
    val state: StateFlow<MapUiState> = _state.asStateFlow()

    private var stopLive: (() -> Unit)? = null
    private val docs = HashMap<String, Map<String, Any?>>()
    private var home: HomeData? = null

    init {
        viewModelScope.launch {
            copies.state.collect { s -> if (s is CopyState.Ready) _state.update { it.copy(data = MapData.build(s.copy, Instant.now())) } }
        }
    }

    fun update(h: HomeData) { home = h }

    /** Aba visível: confere a permissão, busca os amigos e liga um ouvinte por amigo em `live/{uid}` */
    fun start() {
        val h = home ?: return
        viewModelScope.launch {
            if (h.termsVersion < FriendsViewModel.TERMS_VERSION) { _state.update { it.copy(social = false) }; return@launch }
            val roles = runCatching { friendsRepo.roles() }.getOrDefault(setOf("USER"))
            if (roles.isEmpty()) { _state.update { it.copy(social = false) }; return@launch }
            val blocked = runCatching { friendsRepo.blocked() }.getOrDefault(emptySet())
            val friends = runCatching { friendsRepo.fetch(h.declinedFriends, blocked).friends }.getOrNull() ?: return@launch
            _state.update { it.copy(social = true, hasFriends = friends.isNotEmpty()) }
            stopLive?.invoke()
            docs.clear()
            stopLive = liveRepo.watch(friends.map { it.id }) { id, d ->
                if (d == null) docs.remove(id) else docs[id] = d
                rebuild()
            }
            rebuild()
        }
    }

    fun stop() {
        stopLive?.invoke()
        stopLive = null
    }

    /** Recalcula quem está ao vivo (chamado também a cada minuto: quem ficou 15 min sem notícia passa a encerrado) */
    fun rebuild() {
        val now = Instant.now()
        val list = docs.mapNotNull { (id, d) -> LiveFriend.of(id, d, now) }
            .filter { it.isLive || (it.endedAt?.let { e -> now.epochSecond - e.epochSecond < LiveFriend.RECENT_SECONDS } ?: false) }
            // Ao vivo primeiro, depois quem começou antes (a lista do iOS)
            .sortedWith(compareBy<LiveFriend>({ if (it.isLive) 0 else 1 }, { it.start ?: Instant.MAX }, { it.name }))
        _state.update { it.copy(live = list) }
    }

    override fun onCleared() = stop()
}
