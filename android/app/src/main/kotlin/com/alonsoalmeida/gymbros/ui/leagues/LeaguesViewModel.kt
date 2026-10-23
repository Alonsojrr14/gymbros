package com.alonsoalmeida.gymbros.ui.leagues

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.alonsoalmeida.gymbros.data.CopyState
import com.alonsoalmeida.gymbros.data.leagues.LeagueStore
import com.alonsoalmeida.gymbros.data.leagues.PROFILE_FEED
import com.alonsoalmeida.gymbros.domain.MonsterForm
import com.alonsoalmeida.gymbros.domain.SwissRound
import com.alonsoalmeida.gymbros.domain.home.HomeData
import com.alonsoalmeida.gymbros.domain.leagues.ClubWinners
import com.alonsoalmeida.gymbros.domain.leagues.CommentJson
import com.alonsoalmeida.gymbros.domain.leagues.FeedItem
import com.alonsoalmeida.gymbros.domain.leagues.League
import com.alonsoalmeida.gymbros.domain.leagues.LeagueActivityJson
import com.alonsoalmeida.gymbros.domain.leagues.LeagueBoard
import com.alonsoalmeida.gymbros.domain.leagues.LeagueEdits
import com.alonsoalmeida.gymbros.domain.leagues.LeagueFormat
import com.alonsoalmeida.gymbros.domain.leagues.LeaguesCopy
import com.alonsoalmeida.gymbros.domain.leagues.MyCheckIn
import com.alonsoalmeida.gymbros.domain.leagues.PeriodWin
import com.alonsoalmeida.gymbros.domain.leagues.RankRow
import com.alonsoalmeida.gymbros.domain.leagues.RemoteLeague
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.time.Instant

/** O que as telas das ligas leem da cópia da conta */
data class LeaguesUi(
    val copy: LeaguesCopy = LeaguesCopy(),
    /** Na ordem em que entrou (o @Query(sort: \League.joinedAt) do iOS) */
    val leagues: List<League> = emptyList(),
    val activities: Map<String, LeagueActivityJson> = emptyMap(),
    val settings: Map<String, Any?> = emptyMap(),
    val pendingJoins: List<LeagueEdits.PendingJoin> = emptyList(),
) {
    fun mine(league: League): List<MyCheckIn> = copy.checkIns.orEmpty().filter { it.leagueUUID.equals(league.uuid, true) }.map(::MyCheckIn)
    fun reviews(league: League): Map<String, Boolean> =
        copy.reviews.orEmpty().filter { it.leagueUUID.equals(league.uuid, true) }.associate { it.itemID to it.approved }
    fun comments(item: String): List<CommentJson> = copy.comments.orEmpty().filter { it.itemID.equals(item, true) }.sortedBy { it.date }
    fun checkIn(id: String) = copy.checkIns.orEmpty().firstOrNull { it.uuid.equals(id, true) }
    fun league(uuid: String?) = leagues.firstOrNull { it.uuid.equals(uuid, true) }
    val current: List<League> get() = leagues.filter { !it.isPastSeason }
}

/** Placar de uma liga, derivado do feed (LeagueDetailView.body) */
data class Board(
    val feed: List<FeedItem>,
    val swiss: List<SwissRound>,
    val total: List<RankRow>,
    val avatar: MonsterForm,
)

/** Ligas da conta aberta (LeaguesView, LeagueRemoteStore). Lê a cópia da conta e o cache do servidor do `LeagueStore`. */
class LeaguesViewModel(val store: LeagueStore) : ViewModel() {
    val ui: StateFlow<LeaguesUi> = store.copies.state.map { s ->
        val c = (s as? CopyState.Ready)?.copy
        val data = LeagueEdits.read(c)
        val settings = store.settings(c)
        LeaguesUi(data, data.leagues.orEmpty().map(::League).sortedBy { it.j.joinedAt }, data.activities.associateBy { it.uuid.uppercase() },
                  settings, LeagueEdits.pendingJoins(settings))
    }.flowOn(Dispatchers.Default).stateIn(viewModelScope, SharingStarted.Eagerly, LeaguesUi())

    val cache = store.cache
    val comments = store.comments
    val roles = store.roles
    val error = store.lastError

    init {
        store.loadRoles()
    }

    fun remote(cache: Map<String, RemoteLeague>, l: League): RemoteLeague = (cache[l.code] ?: RemoteLeague.EMPTY).applying(l)

    /** Ao abrir a aba: renova temporadas, confere pedidos aceitos, relê as ligas e manda o que está pendente */
    fun onOpen() = viewModelScope.launch {
        val u = ui.value
        store.renewIfNeeded(u.current)
        store.refresh(u.current)
        store.checkPendingJoins()
        store.flush()
    }

    fun refresh(l: League, force: Boolean = false) = store.refresh(listOf(l), force)

    fun launch(block: suspend LeagueStore.() -> Unit) = viewModelScope.launch { store.block() }

    companion object {
        fun board(l: League, ui: LeaguesUi, home: HomeData, remote: RemoteLeague, selfID: String, now: Instant): Board {
            val avatar = home.roster.snapshot(l.monsterUUID).form
            val feed = LeagueBoard.feed(l, ui.mine(l), ui.activities, home.trainerName, avatar, remote, ui.reviews(l))
            val swiss = LeagueBoard.swiss(l, feed, remote, selfID, now)
            val total = LeagueBoard.ranking(feed, l, home.trainerName, avatar, null, null, remote, swiss, selfID)
            return Board(feed, swiss, total, avatar)
        }

        fun winners(l: League, b: Board, home: HomeData, remote: RemoteLeague, selfID: String, now: Instant): List<PeriodWin> =
            if (l.format == LeagueFormat.CLUB && !l.settings.rankingsDisabled) ClubWinners.all(l, b.feed, home.trainerName, b.avatar, remote, b.swiss, selfID, now)
            else emptyList()

        const val PROFILE = PROFILE_FEED
    }
}
