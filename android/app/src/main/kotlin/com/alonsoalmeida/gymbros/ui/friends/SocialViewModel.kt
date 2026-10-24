package com.alonsoalmeida.gymbros.ui.friends

import com.alonsoalmeida.gymbros.domain.social.CommentScope

import androidx.compose.runtime.Composable
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.alonsoalmeida.gymbros.data.FriendsRepository
import com.alonsoalmeida.gymbros.data.ProfilePhotosRepository
import com.alonsoalmeida.gymbros.data.RemoteFriend
import com.alonsoalmeida.gymbros.data.social.RemoteCheckIn
import com.alonsoalmeida.gymbros.data.social.SocialCopy
import com.alonsoalmeida.gymbros.data.social.SocialEdits
import com.alonsoalmeida.gymbros.data.social.SocialRepository
import com.alonsoalmeida.gymbros.domain.Game
import com.alonsoalmeida.gymbros.domain.MonsterForm
import com.alonsoalmeida.gymbros.domain.home.HomeBuilder
import com.alonsoalmeida.gymbros.domain.social.BlockedUser
import com.alonsoalmeida.gymbros.domain.social.BroDeck
import com.alonsoalmeida.gymbros.domain.social.ContentFilter
import com.alonsoalmeida.gymbros.domain.social.DeckPerson
import com.alonsoalmeida.gymbros.domain.social.DirectKind
import com.alonsoalmeida.gymbros.domain.social.DirectMessage
import com.alonsoalmeida.gymbros.domain.social.FeedPost
import com.alonsoalmeida.gymbros.domain.social.FriendPrefs
import com.alonsoalmeida.gymbros.domain.social.FriendRank
import com.alonsoalmeida.gymbros.domain.social.FriendsMetric
import com.alonsoalmeida.gymbros.domain.social.FriendsRanking
import com.alonsoalmeida.gymbros.domain.social.InboxMarks
import com.alonsoalmeida.gymbros.domain.social.InboxPeer
import com.alonsoalmeida.gymbros.domain.social.InboxRules
import com.alonsoalmeida.gymbros.domain.social.LeagueFeed
import com.alonsoalmeida.gymbros.domain.social.RankPerson
import com.alonsoalmeida.gymbros.domain.social.ReportReason
import com.alonsoalmeida.gymbros.domain.social.ReportedContent
import com.alonsoalmeida.gymbros.domain.social.SocialComment
import com.alonsoalmeida.gymbros.domain.social.TrainInvite
import com.alonsoalmeida.gymbros.domain.social.UnifiedFeed
import com.alonsoalmeida.gymbros.domain.social.UnifiedPost
import com.alonsoalmeida.gymbros.ui.AppEnv
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.Instant
import java.util.UUID

/** O que veio do servidor para o Feed: posts dos amigos (perfil e ligas públicas) e os check-ins deles nas suas ligas */
data class FeedRemote(
    val profilePosts: Map<String, List<RemoteCheckIn>> = emptyMap(),
    val leaguePosts: Map<String, List<RemoteCheckIn>> = emptyMap(),
    /** Código da liga → check-ins dos outros nela (temporada atual) */
    val inLeagues: Map<String, List<RemoteCheckIn>> = emptyMap(),
    /** Amigos que esconderam os treinos de você */
    val hiddenFromMe: Set<String> = emptySet(),
    /** Forma do bro público de cada amigo (avatar dos posts) */
    val forms: Map<String, MonsterForm> = emptyMap(),
    val loaded: Boolean = false,
)

data class InboxRemote(
    val messages: List<DirectMessage> = emptyList(),
    val peers: Map<String, InboxPeer> = emptyMap(),
    val loaded: Boolean = false,
    val error: String? = null,
)

/** O feed montado: o que a aba mostra, o ranking da semana e os stories */
data class FeedModel(
    val shown: List<UnifiedPost>,
    val leagueFeeds: List<LeagueFeed>,
    val friendPosts: List<FeedPost>,
    val ranking: List<FriendRank>,
    val stories: List<DeckPerson>,
)

/**
 * Feed, comentários, caixa de entrada e moderação (FriendsFeed.swift, CommentSync.swift, Inbox.swift e Moderation.swift).
 * O que é da conta (comentários, bloqueados, denunciados, por amigo, lido/arquivado) fica na cópia da conta e vai para o
 * iPhone; o que é dos outros vem do Firestore, com escutas ligadas só com a tela aberta.
 */
class SocialViewModel(private val env: AppEnv, private val repo: SocialRepository = SocialRepository()) : ViewModel() {
    private val _feed = MutableStateFlow(FeedRemote())
    val feed: StateFlow<FeedRemote> = _feed.asStateFlow()
    private val _inbox = MutableStateFlow(InboxRemote())
    val inbox: StateFlow<InboxRemote> = _inbox.asStateFlow()
    private val _error = MutableStateFlow<String?>(null)
    /** Último erro de envio (mensagem, comentário), para mostrar perto do campo */
    val error: StateFlow<String?> = _error.asStateFlow()
    /** Conversa aberta: o que chega nela já conta como lido */
    var openPeer: String? = null

    private var stopMessages: (() -> Unit)? = null
    private var inboxWatchers = 0
    private var lastPulled: Set<String> = emptySet()

    private val name: String get() = SocialCopy.read(copyNow()).trainerName.ifEmpty { env.name }
    private fun copyNow() = (env.copies.state.value as? com.alonsoalmeida.gymbros.data.CopyState.Ready)?.copy

    private fun edit(change: (kotlinx.serialization.json.JsonObject?) -> kotlinx.serialization.json.JsonObject?) = viewModelScope.launch {
        env.copies.edit { copy -> change(copy) ?: copy ?: com.alonsoalmeida.gymbros.domain.backup.AccountEdits.empty(env.name, Instant.now()) }
    }

    fun clearError() { _error.value = null }

    // MARK: Feed

    /** Posts dos amigos (perfil + ligas públicas dos últimos 7 dias) e os check-ins deles nas suas ligas públicas */
    fun refreshFeed(friends: List<RemoteFriend>, social: SocialCopy) = viewModelScope.launch {
        val ids = friends.map { it.id }
        val cards = runCatching { repo.profileCards(ids) }.getOrDefault(emptyMap())
        val me = runCatching { repo.me() }.getOrNull() ?: return@launch
        val hidden = cards.filter { me in it.value.hiddenFrom }.keys
        val profile = HashMap<String, List<RemoteCheckIn>>()
        val league = HashMap<String, List<RemoteCheckIn>>()
        for (id in ids) {
            if (id in hidden) continue
            runCatching { repo.profilePosts(id, emptyList()) }.getOrNull()?.let { profile[id] = it }
            runCatching { repo.leaguePosts(id) }.getOrNull()?.let { league[id] = it }
        }
        val inLeagues = HashMap<String, List<RemoteCheckIn>>()
        if (ids.isNotEmpty()) for (l in social.publicLeagues()) {
            runCatching { repo.leagueCheckIns(l.code, l.start) }.getOrNull()?.let { list -> inLeagues[l.code] = list.filter { it.memberID in ids } }
        }
        _feed.value = FeedRemote(profile, league, inLeagues, hidden,
                                 cards.mapNotNull { (k, v) -> v.formID?.let(MonsterForm::byID)?.let { k to it } }.toMap(), loaded = true)
    }

    /** Monta o feed (FriendsFeed.swift `UnifiedFeedView.body`): só você e os seus amigos */
    fun model(social: SocialCopy, remote: FeedRemote, friends: List<RemoteFriend>, myAvatar: MonsterForm, now: Instant = Instant.now()): FeedModel {
        val mod = social.moderation
        val visibleFriends = friends.filter { !mod.isBlocked(it.id) }
        val byID = visibleFriends.associateBy { it.id }
        fun post(r: RemoteCheckIn, leagueID: String?, scope: CommentScope): FeedPost? {
            val f = byID[r.memberID] ?: return null
            return FeedPost(r.id, f.id, f.name, remote.forms[f.id] ?: f.form, false, r.date, r.title, r.note, r.kind, r.minutes,
                            Game.xp(r.kind, r.minutes, r.effort), r.hasPhoto, r.effort, r.place, r.postedIn, leagueID, scope)
        }
        val leagueFeeds = social.publicLeagues().map { l ->
            val items = social.myPosts(l.uuid, myAvatar) +
                remote.inLeagues[l.code].orEmpty().mapNotNull { post(it, l.uuid.uppercase(), CommentScope(l.code, it.memberID, isPublic = true, member = true)) }
            LeagueFeed("${l.emoji} ${l.name}", l.uuid.uppercase(), mod.visiblePosts(items))
        }
        val profile = remote.profilePosts.values.flatten().mapNotNull { post(it, null, CommentScope(CommentScope.PROFILE_CODE, it.memberID, false, true)) }
        // Liga pública em que você não está: só por ser amigo de quem postou
        val fromLeagues = remote.leaguePosts.values.flatten().mapNotNull {
            post(it, null, CommentScope(it.league ?: CommentScope.PROFILE_CODE, it.memberID, it.feed, member = false))
        }
        val friendPosts = mod.visiblePosts(profile + fromLeagues)
        val all = UnifiedFeed.build(leagueFeeds, friendPosts)
        val shown = all.filter { it.item.isMe || it.item.memberID in byID }
        val mine = social.myPosts(HomeBuilder.PROFILE_FEED, myAvatar)
        val ranking = FriendsRanking.rank(mine, mod.visiblePosts(profile), visibleFriends.map { RankPerson(it.id, it.name, remote.forms[it.id] ?: it.form) },
                                          social.trainerName, myAvatar, FriendsMetric.CHECK_INS,
                                          com.alonsoalmeida.gymbros.domain.social.RankWindow.SEMANA.since(now))
        val stories = BroDeck.people(leagueFeeds, friendPosts, social.deckSeen.toSet(), now).filter { it.id in byID }
        return FeedModel(shown, leagueFeeds, friendPosts, ranking, stories)
    }

    /** Ranking completo (FriendsRankingView): métrica e janela escolhidas */
    fun ranking(social: SocialCopy, remote: FeedRemote, friends: List<RemoteFriend>, myAvatar: MonsterForm, metric: FriendsMetric, since: Instant?): List<FriendRank> {
        val mod = social.moderation
        val visible = friends.filter { !mod.isBlocked(it.id) }
        val posts = remote.profilePosts.values.flatten().mapNotNull { r ->
            visible.firstOrNull { it.id == r.memberID }?.let { f ->
                FeedPost(r.id, f.id, f.name, f.form, false, r.date, r.title, r.note, r.kind, r.minutes, Game.xp(r.kind, r.minutes, r.effort))
            }
        }
        return FriendsRanking.rank(social.myPosts(HomeBuilder.PROFILE_FEED, myAvatar), mod.visiblePosts(posts),
                                   visible.map { RankPerson(it.id, it.name, remote.forms[it.id] ?: it.form) }, social.trainerName, myAvatar, metric, since)
    }

    /** Reações e número de comentários dos posts na tela (CommentSync.pull, os 60 primeiros), uma leitura por abertura */
    fun pullComments(posts: List<FeedPost>) {
        val items = posts.take(60).map { it.id to it.comments }
        val asked = items.map { it.first }.toSet()
        if (asked.isEmpty() || asked == lastPulled) return
        lastPulled = asked
        viewModelScope.launch {
            val remote = runCatching { repo.comments(items) }.getOrNull() ?: return@launch
            edit { copy -> SocialEdits.syncRemote(copy, name, asked, remote) }
        }
    }

    private var stopComments: (() -> Unit)? = null

    /** Post aberto: os comentários de todo mundo nele (e as reações a eles) chegam ao vivo */
    fun watchComments(itemIDs: List<String>, scope: CommentScope) {
        stopComments?.invoke()
        val asked = itemIDs.toSet()
        stopComments = repo.watchComments(itemIDs.map { it to scope }) { remote ->
            edit { copy -> SocialEdits.syncRemote(copy, name, asked, remote) }
        }
    }

    fun stopWatchingComments() { stopComments?.invoke(); stopComments = null }

    /** Comentário ou reação seu: na conta (vai para o iPhone) e no servidor (os outros veem). Falso se o filtro barrou */
    fun comment(text: String, itemID: String, owner: String, scope: CommentScope): Boolean {
        val t = text.trim()
        if (t.isEmpty()) return true
        if (!ContentFilter.allows(t)) return false
        val c = SocialComment(UUID.randomUUID().toString().uppercase(), itemID, t, Instant.now())
        viewModelScope.launch {
            env.copies.edit { copy -> SocialEdits.addComment(copy, name, c) }
            runCatching { repo.publishComment(c, owner, name, scope) }
        }
        return true
    }

    /** Apaga o seu comentário (e as reações a ele) aqui e no servidor */
    fun removeComment(c: SocialComment, reactions: List<SocialComment> = emptyList()) {
        val ids = (reactions.filter { it.isMine } + c).map { it.id }.toSet()
        viewModelScope.launch {
            env.copies.edit { copy -> SocialEdits.removeComments(copy, name, ids) }
            for (id in ids) runCatching { repo.retractComment(id) }
        }
    }

    /** Força é uma reação 💪 (o mesmo do deck e do detalhe); de novo, tira */
    fun toggleStrength(post: FeedPost, mine: SocialComment?) {
        if (mine != null) removeComment(mine) else comment("💪", post.id, post.memberID, post.comments)
    }

    /** Apagar o seu check-in: sai do servidor e da conta, com os comentários dele; a atividade continua no histórico */
    fun deleteCheckIn(id: String, comments: List<SocialComment>) = viewModelScope.launch {
        val ids = comments.map { it.id }.toSet()
        env.copies.edit { copy -> SocialCopy.removeCheckIn(SocialEdits.removeComments(copy, name, ids), id) }
        runCatching { repo.retractCheckIn(id) }
        for (c in comments.filter { it.isMine }) runCatching { repo.retractComment(c.id) }
    }

    private val _profile = MutableStateFlow<Map<String, ProfileExtras>>(emptyMap())
    /** Perfil de um amigo aberto: posts e ligas em comum */
    val profile: StateFlow<Map<String, ProfileExtras>> = _profile.asStateFlow()

    data class ProfileExtras(val posts: List<RemoteCheckIn>?, val commonLeagues: Set<String>)

    /** Posts do perfil (nulo se a pessoa escondeu os treinos de você) e as suas ligas em que ela também está */
    fun loadProfile(id: String, social: SocialCopy) = viewModelScope.launch {
        val hidden = runCatching { repo.profileCards(listOf(id))[id]?.hiddenFrom }.getOrNull().orEmpty()
        val posts = runCatching { repo.profilePosts(id, hidden) }.getOrElse { emptyList() }
        val codes = social.leagues.filter { !it.isPastSeason }.map { it.code }
        val common = if (codes.isEmpty()) emptySet() else runCatching { repo.leaguesWith(id, codes) }.getOrDefault(emptySet())
        _profile.value = _profile.value + (id to ProfileExtras(posts, common))
    }

    fun markDeckSeen(ids: List<String>) = edit { copy ->
        SocialEdits.settings(copy, name) { it[BroDeck.SEEN_KEY] = SocialEdits.strings(BroDeck.markSeen(SocialCopy.read(copy).deckSeen, ids)) }
    }

    // MARK: Por amigo (SocialExtras.swift)

    fun setHideMine(id: String, hide: Boolean) = viewModelScope.launch {
        var raw: String? = null
        env.copies.edit { copy ->
            raw = FriendPrefs.set(SocialCopy.read(copy).friendPrefsRaw, id) { it.copy(hideMine = hide) }
            SocialEdits.settings(copy, name) { it[FriendPrefs.KEY] = com.dd.plist.NSString(raw!!) }
        }
        runCatching { repo.setHidden(FriendPrefs.hiddenFrom(raw)) }
    }

    fun setMuted(id: String, muted: Boolean) = edit { copy ->
        val raw = FriendPrefs.set(SocialCopy.read(copy).friendPrefsRaw, id) { it.copy(muted = muted) }
        SocialEdits.settings(copy, name) { it[FriendPrefs.KEY] = com.dd.plist.NSString(raw) }
    }

    // MARK: Moderação (Moderation.swift `ModerationStore`)

    /** Some na hora para você; a denúncia vai para a moderação (o servidor guarda, só admin lê) */
    fun report(content: ReportedContent, reason: ReportReason) = viewModelScope.launch {
        env.copies.edit { copy ->
            val hidden = SocialCopy.read(copy).moderation.hidden + content.key
            SocialEdits.settings(copy, name) { it[com.alonsoalmeida.gymbros.domain.social.Moderation.HIDDEN_KEY] = SocialEdits.hidden(hidden) }
        }
        runCatching { repo.report(content, reason) }
    }

    /** Bloquear: some de tudo, a amizade é desfeita; as regras do servidor impedem mensagens, X1 e trocas */
    fun block(userID: String, userName: String, after: () -> Unit = {}) = viewModelScope.launch {
        edit { copy ->
            val list = SocialCopy.read(copy).moderation.blocked
            if (list.any { it.id == userID }) null else
                SocialEdits.settings(copy, name) { it[com.alonsoalmeida.gymbros.domain.social.Moderation.BLOCKED_KEY] = SocialEdits.blocked(list + BlockedUser(userID, userName, Instant.now())) }
        }.join()
        runCatching { repo.block(userID, userName) }
        after()
    }

    /** A amizade não volta sozinha */
    fun unblock(userID: String) = viewModelScope.launch {
        env.copies.edit { copy ->
            val list = SocialCopy.read(copy).moderation.blocked.filter { it.id != userID }
            SocialEdits.settings(copy, name) { it[com.alonsoalmeida.gymbros.domain.social.Moderation.BLOCKED_KEY] = SocialEdits.blocked(list) }
        }
        runCatching { repo.unblock(userID) }
    }

    /** Lista de bloqueados: a do servidor vira a da conta (ModerationStore.refresh) */
    fun refreshBlocked() = viewModelScope.launch {
        val server = runCatching { repo.blockedUsers() }.getOrNull() ?: return@launch
        val local = SocialCopy.read(copyNow()).moderation.blocked
        if (server.map { it.id }.toSet() == local.map { it.id }.toSet()) return@launch
        env.copies.edit { copy -> SocialEdits.settings(copy, name) { it[com.alonsoalmeida.gymbros.domain.social.Moderation.BLOCKED_KEY] = SocialEdits.blocked(server) } }
    }

    // MARK: Caixa de entrada (Inbox.swift `InboxStore`)

    /** Tela da caixa de entrada (ou conversa) aberta e app na frente: escuta as mensagens; a última a fechar desliga */
    fun startInbox(friends: () -> List<RemoteFriend>) {
        inboxWatchers++
        if (stopMessages != null) return
        stopMessages = repo.watchMessages({ list ->
            _inbox.value = _inbox.value.copy(messages = list, loaded = true, error = null)
            openPeer?.let { markRead(it) }
            val known = friends().map { it.id }.toSet() + _inbox.value.peers.keys
            val missing = list.map { it.peerID }.toSet() - known
            if (missing.isNotEmpty()) viewModelScope.launch {
                runCatching { repo.peers(missing) }.onSuccess { found -> _inbox.value = _inbox.value.copy(peers = _inbox.value.peers + found.associateBy { it.id }) }
            }
        }, { e -> _inbox.value = _inbox.value.copy(loaded = true, error = if (_inbox.value.messages.isEmpty()) e else null) })
    }

    fun stopInbox() {
        inboxWatchers = maxOf(0, inboxWatchers - 1)
        if (inboxWatchers > 0) return
        stopMessages?.invoke()
        stopMessages = null
    }

    override fun onCleared() {
        stopMessages?.invoke()
        stopComments?.invoke()
    }

    fun peer(id: String, friends: List<RemoteFriend>): InboxPeer =
        _inbox.value.peers[id] ?: friends.firstOrNull { it.id == id }?.let { InboxPeer(it.id, it.name, it.formID) } ?: InboxPeer(id, "Treinador", MonsterForm.EGG.id)

    /**
     * Manda uma mensagem direta (InboxStore.send): só para amigos ou quem já falou com você, sem bloqueio e sem palavra
     * barrada. As regras do Firestore conferem de novo no servidor.
     */
    fun send(kind: DirectKind, peerID: String, social: SocialCopy, friends: List<RemoteFriend>, text: String = "", invite: TrainInvite? = null,
             replyTo: String? = null, accepted: Boolean? = null, onSent: () -> Unit = {}) {
        val t = text.trim()
        _error.value = when {
            social.moderation.isBlocked(peerID) -> "Você bloqueou essa pessoa."
            friends.none { it.id == peerID } && _inbox.value.messages.none { it.peerID == peerID } -> "Só dá para mandar mensagem para amigos."
            !ContentFilter.allows(t) -> "Essa mensagem tem palavras que não são permitidas."
            else -> null
        }
        if (_error.value != null) return
        val m = DirectMessage(UUID.randomUUID().toString().uppercase(), peerID, true, Instant.now(), kind, t, invite, replyTo, accepted)
        viewModelScope.launch {
            runCatching { repo.send(m) }
                .onSuccess {
                    if (_inbox.value.messages.none { it.id == m.id }) _inbox.value = _inbox.value.copy(messages = _inbox.value.messages + m)
                    markRead(peerID)
                    onSent()
                }
                .onFailure { _error.value = "Não deu para enviar agora. Confira a internet." }
        }
    }

    private fun marks(change: (InboxMarks) -> Pair<String, com.dd.plist.NSObject>?) = edit { copy ->
        val pair = change(SocialCopy.read(copy).marks) ?: return@edit null
        SocialEdits.settings(copy, name) { it[pair.first] = pair.second }
    }

    fun markRead(peerID: String) {
        val last = _inbox.value.messages.filter { it.peerID == peerID }.maxOfOrNull { it.date } ?: Instant.now()
        val at = maxOf(last, Instant.now())
        marks { m ->
            if ((m.readUntil[peerID] ?: Instant.MIN) >= last) null
            else InboxMarks.READ to SocialEdits.nsDates(m.readUntil + (peerID to at))
        }
    }

    fun markActivitySeen() = marks { InboxMarks.SEEN to SocialEdits.nsDate(Instant.now()) }

    fun archive(peerID: String) = marks { InboxMarks.ARCHIVED to SocialEdits.nsDates(it.archived + (peerID to Instant.now())) }
    fun unarchive(peerID: String) = marks { InboxMarks.ARCHIVED to SocialEdits.nsDates(it.archived - peerID) }
    /** Apaga a conversa só do seu lado: a outra pessoa continua com todas as mensagens */
    fun clear(peerID: String) = marks { InboxMarks.CLEARED to SocialEdits.nsDates(it.cleared + (peerID to Instant.now())) }

    /** Quando cada pedido de amizade apareceu pela primeira vez (o servidor não manda data) */
    fun rememberRequests(ids: Set<String>) = marks { m ->
        val next = InboxRules.rememberRequests(m.requestsSeen, ids, Instant.now())
        if (next == m.requestsSeen) null else InboxMarks.REQUESTS to SocialEdits.nsDates(next)
    }

    companion object {
        /** Um por conta, o mesmo no Feed, no perfil do amigo e na caixa de entrada */
        @Composable
        fun of(env: AppEnv): SocialViewModel = viewModel(key = "social-${env.uid}", factory = viewModelFactory { initializer { SocialViewModel(env) } })

        /** O mesmo FriendsViewModel que a raiz do app cria (mesma chave) */
        @Composable
        fun friends(env: AppEnv): FriendsViewModel = viewModel(key = "friends-${env.uid}", factory = viewModelFactory {
            initializer { FriendsViewModel(FriendsRepository(), env.copies, ProfilePhotosRepository(env.context)) }
        })
    }
}
