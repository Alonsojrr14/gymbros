package com.alonsoalmeida.gymbros.ui.bros

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.alonsoalmeida.gymbros.data.AccountCopyRepository
import com.alonsoalmeida.gymbros.data.CopyState
import com.alonsoalmeida.gymbros.data.FriendsRepository
import com.alonsoalmeida.gymbros.data.RemoteFriend
import com.alonsoalmeida.gymbros.data.TradesRepository
import com.alonsoalmeida.gymbros.domain.backup.AccountCopy
import com.alonsoalmeida.gymbros.domain.bros.BroEdits
import com.alonsoalmeida.gymbros.domain.bros.BroSettings
import com.alonsoalmeida.gymbros.domain.bros.MyTradeBro
import com.alonsoalmeida.gymbros.domain.bros.TradeBro
import com.alonsoalmeida.gymbros.domain.bros.TradeException
import com.alonsoalmeida.gymbros.domain.bros.TradeLedger
import com.alonsoalmeida.gymbros.domain.bros.TradePerson
import com.alonsoalmeida.gymbros.domain.bros.TradeProposal
import com.alonsoalmeida.gymbros.domain.bros.TradeRefusal
import com.alonsoalmeida.gymbros.domain.bros.TradeRules
import com.alonsoalmeida.gymbros.domain.home.HomeData
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.time.Instant

/** Bro que acabou de chegar por troca (para a tela de comemoração) */
data class Arrival(val broUUID: String, val proposal: TradeProposal)

/** O que a Box e as trocas mostram (o resto vem da `HomeData`) */
data class TradesUiState(
    val all: List<TradeProposal> = emptyList(),
    val loaded: Boolean = false,
    val lastError: String? = null,
    val busyFighters: Set<String> = emptySet(),
    val friends: List<RemoteFriend> = emptyList(),
    val friendsLoaded: Boolean = false,
    val arrived: Arrival? = null,
)

/**
 * Box de bros e trocas (Monsters.swift `MyBrosList` e Trade.swift `TradeStore`). O servidor guarda só as propostas; a
 * cópia da conta guarda a Box e o livro das trocas (`tradeBases`, `tradeGone`, `tradeApplied`), que vão para o iPhone.
 */
class BrosViewModel(
    private val copies: AccountCopyRepository,
    private val trades: TradesRepository,
    private val friendsRepo: FriendsRepository,
) : ViewModel() {
    /** Ajustes da conta que a Box lê (descobertas, trocas aplicadas, bros em X1) */
    val settings: StateFlow<BroSettings> = copies.state.map { s ->
        BroSettings.read((s as? CopyState.Ready)?.copy?.let(AccountCopy::decode))
    }.flowOn(Dispatchers.Default).stateIn(viewModelScope, SharingStarted.Eagerly, BroSettings(null, false, emptySet(), emptyMap()))

    private val _state = MutableStateFlow(TradesUiState())
    val state: StateFlow<TradesUiState> = _state.asStateFlow()

    private var home: HomeData? = null
    private var polling: Job? = null

    /** A tela passa a `HomeData` atual (muda quando a conta muda) */
    fun bind(h: HomeData) { home = h }

    /** Forma de cada bro para a recusa do "ovo" (o iPhone usa a gravada em `lastFormID`, que ele mantém igual à de agora) */
    private fun lastForms(h: HomeData): Map<String, String?> = h.roster.monsters.associate { it.uuid to h.roster.snapshot(it.uuid).form.id }

    /** Muda a cópia só se a conta já tem cópia (sem ela não há bro para mudar) */
    private suspend fun editExisting(f: (kotlinx.serialization.json.JsonObject) -> kotlinx.serialization.json.JsonObject) {
        if ((copies.state.value as? CopyState.Ready)?.copy == null) return
        copies.edit { c -> c?.let(f) ?: com.alonsoalmeida.gymbros.domain.backup.AccountEdits.empty(home?.trainerName.orEmpty(), Instant.now()) }
    }

    fun myBros(h: HomeData): List<MyTradeBro> = TradeRules.myBros(h.roster, lastForms(h), h.trainerName)

    fun refusal(h: HomeData, m: MyTradeBro, now: Instant = Instant.now()): TradeRefusal? =
        TradeRules.refusal(m, h.roster.mainID, h.leagues, _state.value.busyFighters, _state.value.all, settings.value.tradeApplied, now)

    /** Você como o amigo te vê */
    fun me(h: HomeData) = TradePerson(TradeProposal.ME, h.trainerName, h.snapshot.form.id)

    fun refresh() {
        val h = home ?: return
        viewModelScope.launch { load(h) }
    }

    private suspend fun load(h: HomeData) {
        val now = Instant.now()
        runCatching {
            val busy = runCatching { trades.busyFighters(settings.value.duelMonsters, now) }.getOrDefault(_state.value.busyFighters)
            _state.update { it.copy(busyFighters = busy) }
            val mine = myBros(h).filter { refusal(h, it, now) == null }.map { it.bro }
            trades.proposals(now, mine)
        }.onSuccess { list -> _state.update { it.copy(all = list, lastError = null, loaded = true) } }
            .onFailure { e -> _state.update { it.copy(lastError = message(e), loaded = true) } }
        applyAccepted()
    }

    private fun message(e: Throwable): String = (e as? TradeException)?.refusal?.message
        ?: "Não deu para falar com o servidor. Confira a internet e tente de novo."

    /** Central de trocas aberta: atualiza a cada 30 s (3 s logo depois de propor, a resposta pode vir em segundos) */
    fun startPolling() {
        if (polling?.isActive == true) return
        polling = viewModelScope.launch {
            while (isActive) {
                home?.let { load(it) }
                val fresh = TradeRules.sent(_state.value.all, Instant.now()).any { Instant.now().epochSecond - it.createdAt.epochSecond < 120 }
                delay(if (fresh) 3_000 else 30_000)
            }
        }
    }

    fun stopPolling() { polling?.cancel(); polling = null }

    fun loadFriends() {
        val h = home ?: return
        viewModelScope.launch {
            runCatching { friendsRepo.fetch(h.declinedFriends, runCatching { friendsRepo.blocked() }.getOrDefault(emptySet())) }
                .onSuccess { f -> _state.update { it.copy(friends = f.friends, friendsLoaded = true) } }
                .onFailure { _state.update { it.copy(friendsLoaded = true) } }
        }
    }

    suspend fun bros(friendID: String): List<TradeBro> = runCatching { trades.bros(friendID) }.getOrDefault(emptyList())

    /** Troca aceita por você (ou o app fechou no meio): aplica na Box uma vez só */
    private suspend fun applyAccepted() {
        for (p in TradeRules.toApply(_state.value.all, settings.value.tradeApplied)) {
            apply(p)?.let { uuid -> _state.update { it.copy(arrived = Arrival(uuid, p)) } }
        }
    }

    private suspend fun apply(p: TradeProposal): String? {
        var bro: String? = null
        editExisting { c ->
            // O livro da própria cópia decide (outro aparelho pode já ter aplicado)
            val applied = BroSettings.read(AccountCopy.decode(c)).tradeApplied
            val r = TradeLedger.apply(c, p, applied, Instant.now()) ?: return@editExisting c
            bro = r.broUUID
            r.copy
        }
        return bro
    }

    /** Recebe a troca aceita: o seu bro vai, o do amigo chega na Box e a cena começa */
    fun receive(p: TradeProposal) {
        if (TradeRules.ready(_state.value.all, settings.value.tradeApplied).none { it.id == p.id }) return
        viewModelScope.launch { apply(p)?.let { uuid -> _state.update { it.copy(arrived = Arrival(uuid, p)) } } }
    }

    fun dismissArrival() = _state.update { it.copy(arrived = null) }

    suspend fun propose(friend: RemoteFriend, give: MyTradeBro, get: TradeBro): String? {
        val h = home ?: return "Tente de novo."
        val now = Instant.now()
        refusal(h, give, now)?.let { return it.message }
        if (get.isEgg) return TradeRefusal.Egg.message
        val mine = myBros(h).firstOrNull { it.uuid == give.uuid }?.bro ?: return TradeRefusal.Gone.message
        return runCatching { trades.propose(TradePerson(friend.id, friend.name, friend.formID), me(h), mine, get, now) }
            .fold({ p -> _state.update { it.copy(all = it.all + p) }; startQuickCheck(); null }, { message(it) })
    }

    /** A resposta pode chegar em segundos: confere de novo para mostrar mesmo fora da central */
    private fun startQuickCheck() {
        viewModelScope.launch { delay(12_000); home?.let { load(it) } }
    }

    suspend fun respond(p: TradeProposal, accept: Boolean): String? {
        val h = home ?: return "Tente de novo."
        val now = Instant.now()
        if (!p.isPending(now) || p.to.id != TradeProposal.ME) return TradeRefusal.NotPending.message
        if (accept) {
            val m = myBros(h).firstOrNull { it.bro.id.equals(p.get.id, ignoreCase = true) } ?: return TradeRefusal.Gone.message
            refusal(h, m, now)?.let { return it.message }
        }
        return runCatching { trades.respond(p.id, accept) }.fold({
            val answered = p.copy(answer = if (accept) com.alonsoalmeida.gymbros.domain.bros.TradeAnswer.ACCEPTED
                                          else com.alonsoalmeida.gymbros.domain.bros.TradeAnswer.DECLINED, answeredAt = now)
            _state.update { s -> s.copy(all = s.all.map { if (it.id == p.id) answered else it }) }
            applyAccepted()
            null
        }, { message(it) })
    }

    fun cancel(p: TradeProposal) {
        viewModelScope.launch {
            runCatching { trades.cancel(p.id) }.onSuccess { _state.update { s -> s.copy(all = s.all.filter { it.id != p.id }) } }
        }
    }

    // Box

    fun setMain(uuid: String) { viewModelScope.launch { editExisting { BroEdits.setMain(it, uuid) } } }

    fun rename(uuid: String, name: String) { viewModelScope.launch { editExisting { BroEdits.rename(it, uuid, name) } } }

    fun setRevealAll(on: Boolean) { viewModelScope.launch { editExisting { BroEdits.setRevealAll(it, on) } } }

    override fun onCleared() { stopPolling() }
}
