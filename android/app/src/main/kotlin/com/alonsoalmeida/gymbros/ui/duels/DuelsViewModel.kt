package com.alonsoalmeida.gymbros.ui.duels

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.alonsoalmeida.gymbros.data.AccountCopyRepository
import com.alonsoalmeida.gymbros.data.CopyState
import com.alonsoalmeida.gymbros.data.DuelRepository
import com.alonsoalmeida.gymbros.data.FriendsRepository
import com.alonsoalmeida.gymbros.data.RemoteFriend
import com.alonsoalmeida.gymbros.domain.MonsterForm
import com.alonsoalmeida.gymbros.domain.Stage
import com.alonsoalmeida.gymbros.domain.backup.AccountCopy
import com.alonsoalmeida.gymbros.domain.backup.AccountEdits
import com.alonsoalmeida.gymbros.domain.duel.DuelActivity
import com.alonsoalmeida.gymbros.domain.duel.DuelMetric
import com.alonsoalmeida.gymbros.domain.duel.DuelPerson
import com.alonsoalmeida.gymbros.domain.duel.DuelPhase
import com.alonsoalmeida.gymbros.domain.duel.DuelRecord
import com.alonsoalmeida.gymbros.domain.duel.DuelRefusal
import com.alonsoalmeida.gymbros.domain.duel.DuelRefusalException
import com.alonsoalmeida.gymbros.domain.duel.DuelScore
import com.alonsoalmeida.gymbros.domain.duel.Duels
import com.alonsoalmeida.gymbros.domain.duel.RemoteDuel
import com.alonsoalmeida.gymbros.domain.home.HomeData
import com.alonsoalmeida.gymbros.ui.friends.FriendsViewModel
import com.dd.plist.NSDictionary
import com.dd.plist.NSString
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject
import java.time.Instant
import java.util.Base64

/** Um bro da coleção que pode lutar (ovo não entra no X1) */
data class Fighter(val uuid: String, val name: String, val form: MonsterForm)

/**
 * O que a tela do X1 precisa. As listas derivadas (recebidos, valendo, enviados, encerrados) saem das funções puras de
 * `Duels` com o `now` da tela, que avança sozinho como o `TimelineView` do iOS.
 */
data class DuelsUiState(
    /** Todos os X1 dos últimos 30 dias, com o seu id trocado por "me" */
    val all: List<RemoteDuel> = emptyList(),
    val loaded: Boolean = false,
    val lastError: String? = null,
    val friends: List<RemoteFriend> = emptyList(),
    val blocked: Set<String> = emptySet(),
    /** Quem recusou seu desafio por ter te bloqueado (o servidor avisa ao desafiar) */
    val blockedBy: Set<String> = emptySet(),
    /** Quem te representa em cada X1 (id do X1 → UUID do bro), nos ajustes da conta (`duelMonsters`) */
    val representatives: Map<String, String> = emptyMap(),
    val activities: List<DuelActivity> = emptyList(),
    val fighters: List<Fighter> = emptyList(),
    val mainID: String? = null,
    val me: DuelPerson = DuelPerson(Duels.ME, "", MonsterForm.EGG.id),
    val termsOK: Boolean = true,
    val busy: Boolean = false,
    val message: String? = null,
) {
    /** `DuelStore.duels`: sem bloqueados e sem desafio recebido de quem não é amigo */
    val duels: List<RemoteDuel> get() = Duels.visible(all, blocked, friends.map { it.id }.toSet())
    val friendIDs: Set<String> get() = friends.map { it.id }.toSet()

    fun incoming(now: Instant) = duels.filter { it.challenged.id == Duels.ME && it.isPending(now) }.sortedBy { it.createdAt }
    fun active(now: Instant) = duels.filter { it.acceptedAt != null && it.isOpen(now) }.sortedBy { it.endsAt ?: Instant.MAX }
    fun sent(now: Instant) = duels.filter { it.challenger.id == Duels.ME && it.isPending(now) }
    fun records(now: Instant): List<DuelRecord> = Duels.records(duels, activities = activities, now = now)
    fun score(d: RemoteDuel, now: Instant): DuelScore = Duels.score(d, activities = activities, now = now)

    fun busyFighters(now: Instant) = Duels.busyFighters(all, representatives, now = now)
    fun availableFighters(now: Instant): List<Fighter> = busyFighters(now).let { busy -> fighters.filter { it.uuid !in busy } }
    /** O principal, se já chocou e está livre; senão o primeiro livre */
    fun defaultFighter(now: Instant): Fighter? = availableFighters(now).let { l -> l.firstOrNull { it.uuid == mainID } ?: l.firstOrNull() }

    fun fighterRefusal(monster: String?, now: Instant): DuelRefusal? {
        if (fighters.isEmpty()) return DuelRefusal.NO_HATCHED_BRO
        if (monster != null) return if (monster in busyFighters(now)) DuelRefusal.FIGHTER_BUSY else null
        return if (availableFighters(now).isEmpty()) DuelRefusal.ALL_FIGHTERS_BUSY else null
    }

    fun personRefusal(opponentID: String, now: Instant): DuelRefusal? =
        Duels.refusal(Duels.ME, opponentID, all, blocked, blockedBy, now) ?: if (opponentID in friendIDs) null else DuelRefusal.NOT_FRIEND

    fun refusal(opponentID: String, now: Instant): DuelRefusal? = fighterRefusal(null, now) ?: personRefusal(opponentID, now)

    /** Você no X1 com um bro específico (o nome é o seu; o bro, o escolhido) */
    fun person(with: String?): DuelPerson = fighters.firstOrNull { it.uuid == with }?.let { me.copy(formID = it.form.id) } ?: me

    /** Bro que luta por você neste X1 (o escolhido, com a forma de agora); de antes da escolha, o do servidor */
    fun myForm(d: RemoteDuel): MonsterForm {
        representatives[d.id]?.let { id -> fighters.firstOrNull { it.uuid == id }?.let { return it.form } }
        val mine = d.side(Duels.ME).formID
        return if (mine.isEmpty()) me.form else MonsterForm.byID(mine) ?: me.form
    }

    fun nextFighterFree(now: Instant): Instant? = Duels.nextFighterFree(all, representatives, now)
}

/**
 * X1 (Duels/DuelStore.swift). Os X1 vêm do Firestore (`DuelRepository`); suas atividades, bros e a escolha de quem
 * luta vêm da cópia da conta. A escolha do bro (`duelMonsters`) vai nos ajustes da conta, como no iPhone.
 */
class DuelsViewModel(
    private val repo: DuelRepository,
    private val friendsRepo: FriendsRepository,
    private val copies: AccountCopyRepository,
) : ViewModel() {
    private val _state = MutableStateFlow(DuelsUiState())
    val state: StateFlow<DuelsUiState> = _state.asStateFlow()

    /** Último valor seu informado por X1 (não reenvia o mesmo) */
    private val reportedByMe = HashMap<String, Int>()
    private var home: HomeData? = null
    private var polling: Job? = null
    private var pollers = 0

    init {
        viewModelScope.launch {
            copies.state.collect { s -> if (s is CopyState.Ready) readCopy(s.copy) }
        }
    }

    private fun readCopy(copy: JsonObject?) {
        val dto = copy?.let { runCatching { AccountCopy.decode(it) }.getOrNull() }
        val acts = dto?.activities.orEmpty().map(DuelActivity::of)
        val settings = dto?.accountSettings?.let { runCatching { AccountCopy.settings(Base64.getDecoder().decode(it)) }.getOrNull() }.orEmpty()
        @Suppress("UNCHECKED_CAST")
        val reps = (settings[KEY] as? Map<String, Any?>).orEmpty().mapNotNull { (k, v) -> (v as? String)?.let { k to it.uppercase() } }.toMap()
        _state.update { it.copy(activities = acts, representatives = reps) }
    }

    /** Dados da conta que mudam com a tela inicial: bros, principal, nome e termos */
    fun update(h: HomeData) {
        if (home === h) return
        home = h
        val roster = h.roster
        val fighters = roster.monsters.sortedBy { it.createdAt }.mapNotNull { b ->
            val form = roster.snapshot(b.uuid).form
            if (form.stage == Stage.EGG) null else Fighter(b.uuid, b.displayName(form), form)
        }
        val me = DuelPerson(Duels.ME, h.trainerName, h.snapshot.form.id)
        _state.update { it.copy(fighters = fighters, mainID = roster.main?.uuid, me = me, termsOK = h.termsVersion >= FriendsViewModel.TERMS_VERSION) }
    }

    fun refresh() {
        viewModelScope.launch { load() }
    }

    private suspend fun load() {
        val now = Instant.now()
        val declined = home?.declinedFriends.orEmpty()
        val blocked = runCatching { friendsRepo.blocked() }.getOrDefault(_state.value.blocked)
        val friends = runCatching { friendsRepo.fetch(declined, blocked).friends }.getOrNull()
        runCatching { repo.duels(now) }
            .onSuccess { list ->
                val me = runCatching { repo.me() }.getOrNull()
                val local = if (me != null) list.map { Duels.local(it, me) } else list
                _state.update { it.copy(all = local, lastError = null, loaded = true, blocked = blocked, friends = friends ?: it.friends) }
            }
            .onFailure { _state.update { s -> s.copy(lastError = "Sem conexão com o X1 agora. Confira a internet.", loaded = true, blocked = blocked,
                                                     friends = friends ?: s.friends) } }
        reportMine(now)
    }

    /** Manda o seu valor dos X1 em andamento (e do que acabou há menos de 1 h) quando mudou */
    private suspend fun reportMine(now: Instant) {
        val s = _state.value
        for (d in s.all) {
            if (d.acceptedAt == null) continue
            val phase = d.phase(now)
            if (phase is DuelPhase.Finished && now.epochSecond - phase.ended.epochSecond > 3600) continue
            val v = Duels.myValue(d, s.activities, now)
            if (reportedByMe[d.id] == v) continue
            if (runCatching { repo.report(v, d.id) }.isSuccess) reportedByMe[d.id] = v
        }
    }

    /** Tela do X1 aberta e app na frente: busca de novo no ritmo do iOS (3 s logo depois de desafiar, senão 30 s) */
    fun startPolling() {
        pollers++
        if (polling?.isActive == true) return
        polling = viewModelScope.launch {
            while (isActive) {
                load()
                delay(Duels.refreshInterval(_state.value.duels, now = Instant.now()) * 1000)
            }
        }
    }

    fun stopPolling() {
        pollers = maxOf(0, pollers - 1)
        if (pollers == 0) { polling?.cancel(); polling = null }
    }

    fun challenge(opponent: DuelPerson, metric: DuelMetric, monster: String?, done: () -> Unit) {
        val now = Instant.now()
        val s = _state.value
        if (!s.termsOK) { _state.update { it.copy(message = TERMS) }; return }
        (s.refusal(opponent.id, now) ?: s.fighterRefusal(monster, now))?.let { r -> _state.update { it.copy(message = r.message) }; return }
        val fighter = monster ?: s.defaultFighter(now)?.uuid
        _state.update { it.copy(busy = true) }
        viewModelScope.launch {
            try {
                val duel = repo.challenge(opponent, s.person(fighter), metric, now)
                if (fighter != null) saveRepresentative(duel.id, fighter)
                val me = runCatching { repo.me() }.getOrNull()
                _state.update { it.copy(all = it.all + (if (me != null) Duels.local(duel, me) else duel)) }
                done()
            } catch (e: DuelRefusalException) {
                _state.update { st -> st.copy(message = e.refusal.message, blockedBy = if (e.refusal == DuelRefusal.BLOCKED) st.blockedBy + opponent.id else st.blockedBy) }
            } catch (e: Exception) {
                _state.update { it.copy(message = "Não deu para desafiar agora. Confira a internet.") }
            } finally {
                _state.update { it.copy(busy = false) }
            }
        }
    }

    fun respond(duel: RemoteDuel, accept: Boolean, monster: String?) {
        val now = Instant.now()
        val s = _state.value
        if (accept) {
            if (!s.termsOK) { _state.update { it.copy(message = TERMS) }; return }
            val r = s.fighterRefusal(monster, now)
                ?: (if (duel.challenger.id !in s.friendIDs) DuelRefusal.NOT_FRIEND else null)
                ?: Duels.acceptRefusal(duel, Duels.ME, s.all, s.blocked, now)
            if (r != null) { _state.update { it.copy(message = r.message) }; return }
        }
        val fighter = monster ?: s.defaultFighter(now)?.uuid
        _state.update { it.copy(busy = true) }
        viewModelScope.launch {
            try {
                repo.respond(duel.id, accept, s.person(fighter))
                if (accept && fighter != null) saveRepresentative(duel.id, fighter)
                _state.update { st ->
                    st.copy(all = st.all.map {
                        if (it.id == duel.id) it.copy(answer = if (accept) com.alonsoalmeida.gymbros.domain.duel.DuelAnswer.ACCEPTED
                                                               else com.alonsoalmeida.gymbros.domain.duel.DuelAnswer.DECLINED, answeredAt = now)
                        else it
                    })
                }
            } catch (e: DuelRefusalException) {
                _state.update { it.copy(message = e.refusal.message) }
            } catch (e: Exception) {
                _state.update { it.copy(message = "Não deu para responder agora. Confira a internet.") }
            } finally {
                _state.update { it.copy(busy = false) }
            }
        }
    }

    private suspend fun saveRepresentative(duelID: String, monster: String) {
        val h = home
        copies.edit { copy ->
            AccountEdits.updateSettings(copy ?: AccountEdits.empty(h?.trainerName ?: "", Instant.now())) { map ->
                val dict = (map[KEY] as? NSDictionary)?.let { old -> NSDictionary().also { n -> old.hashMap.forEach { (k, v) -> n[k] = v } } } ?: NSDictionary()
                dict[duelID] = NSString(monster)
                map[KEY] = dict
            }
        }
    }

    /** Aceite dos termos pelo X1 (termsGate do iOS): mesma gravação do `FriendsViewModel.acceptTerms` */
    fun acceptTerms() {
        val h = home ?: return
        viewModelScope.launch {
            copies.edit { copy ->
                AccountEdits.updateSettings(copy ?: AccountEdits.empty(h.trainerName, Instant.now())) {
                    it["termsAcceptedVersion"] = com.dd.plist.NSNumber(FriendsViewModel.TERMS_VERSION)
                    it["termsAcceptedAt"] = com.dd.plist.NSDate(java.util.Date())
                }
            }
        }
    }

    fun showMessage(text: String) = _state.update { it.copy(message = text) }

    fun clearMessage() = _state.update { it.copy(message = null) }

    companion object {
        /** `DuelStore.fightersKey` */
        const val KEY = "duelMonsters"
        const val TERMS = "Aceite os termos de uso (na aba Feed, em Amigos) para entrar no X1."
    }
}
