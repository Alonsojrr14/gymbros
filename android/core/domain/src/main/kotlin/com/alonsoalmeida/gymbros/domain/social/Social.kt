package com.alonsoalmeida.gymbros.domain.social

import com.alonsoalmeida.gymbros.domain.ActivityKind
import com.alonsoalmeida.gymbros.domain.ActivityText
import com.alonsoalmeida.gymbros.domain.MonsterForm
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put
import java.text.BreakIterator
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.TemporalAdjusters
import java.util.Locale

/** Nome de cada tipo de atividade (Bros/Game.swift `ActivityKind.name`) */
val ActivityKind.label: String
    get() = when (this) {
        ActivityKind.MUSCULACAO -> "Musculação"
        ActivityKind.CROSSFIT -> "Crossfit"
        ActivityKind.CORRIDA -> "Corrida"
        ActivityKind.CAMINHADA -> "Caminhada"
        ActivityKind.BIKE -> "Bike"
        ActivityKind.NATACAO -> "Natação"
        ActivityKind.VOLEI -> "Vôlei"
        ActivityKind.FUTEBOL -> "Futebol"
        ActivityKind.LUTAS -> "Lutas"
        ActivityKind.DANCA -> "Dança"
        ActivityKind.YOGA -> "Yoga"
        ActivityKind.OUTRO -> "Outro"
    }

/** SF Symbol de cada tipo (o app troca pelo Material equivalente) */
val ActivityKind.symbol: String
    get() = when (this) {
        ActivityKind.MUSCULACAO -> "figure.strengthtraining.traditional"
        ActivityKind.CROSSFIT -> "figure.cross.training"
        ActivityKind.CORRIDA -> "figure.run"
        ActivityKind.CAMINHADA -> "figure.walk"
        ActivityKind.BIKE -> "figure.outdoor.cycle"
        ActivityKind.NATACAO -> "figure.pool.swim"
        ActivityKind.VOLEI -> "figure.volleyball"
        ActivityKind.FUTEBOL -> "figure.soccer"
        ActivityKind.LUTAS -> "figure.martial.arts"
        ActivityKind.DANCA -> "figure.dance"
        ActivityKind.YOGA -> "figure.yoga"
        ActivityKind.OUTRO -> "figure.mixed.cardio"
    }

/**
 * Um check-in no feed (Leagues.swift `FeedItem`), seu (`memberID` "me") ou de outra pessoa. `postedIn`: liga pública de
 * onde veio o post do amigo ("🔥 Liga"); nulo = perfil.
 */
data class FeedPost(
    val id: String,
    val memberID: String,
    val name: String,
    val avatar: MonsterForm,
    val isMe: Boolean,
    val date: Instant,
    val title: String,
    val note: String,
    val kind: ActivityKind,
    val minutes: Int,
    val score: Int,
    val hasPhoto: Boolean = false,
    val effort: Int = 5,
    val place: String? = null,
    val postedIn: String? = null,
    val leagueID: String? = null,
)

/** Um check-in no feed unificado, com todos os lugares em que foi postado (FriendsFeed.swift `UnifiedPost`) */
data class UnifiedPost(val item: FeedPost, val places: List<String>, val leagueIDs: Set<String>, val fromFriendProfile: Boolean = false) {
    val id: String get() = item.id
}

/** Feed de uma liga pública: rótulo ("🔥 Liga"), uuid e os check-ins dela já filtrados pela moderação */
data class LeagueFeed(val label: String, val leagueID: String, val items: List<FeedPost>)

object UnifiedFeed {
    /** Mesmo treino = mesma pessoa, título e minuto (o mesmo check-in postado em várias ligas) */
    fun key(f: FeedPost): String = "${f.memberID}|${f.title}|${Math.floorDiv(f.date.epochSecond, 60L)}"

    /**
     * Junta ligas e perfis dos amigos (FriendsFeed.swift `UnifiedFeed.build`): o mesmo treino aparece uma vez, com os
     * lugares. Quem chama já tirou liga privada e temporada passada e passou tudo pela moderação.
     */
    fun build(leagues: List<LeagueFeed>, friends: List<FeedPost>): List<UnifiedPost> {
        val posts = LinkedHashMap<String, UnifiedPost>()
        for (l in leagues) for (f in l.items) {
            val k = key(f)
            val p = posts[k]
            posts[k] = if (p != null) p.copy(places = p.places + l.label, leagueIDs = p.leagueIDs + l.leagueID)
                       else UnifiedPost(f, listOf(l.label), setOf(l.leagueID))
        }
        for (f in friends) {
            val k = key(f)
            val place = f.postedIn ?: "Perfil"
            val p = posts[k]
            posts[k] = if (p != null) (if (place in p.places) p else p.copy(places = p.places + place))
                       else UnifiedPost(f, listOf(place), emptySet(), fromFriendProfile = f.postedIn == null)
        }
        return posts.values.sortedByDescending { it.item.date }
    }

    /** "🔥 Liga · 👤 Perfil +2": até dois lugares e quantos mais */
    fun placesText(places: List<String>): String =
        if (places.size > 2) "${places.take(2).joinToString(" · ")} +${places.size - 2}" else places.joinToString(" · ")

    /** "Corrida · 45 min · 🔥 pesado" */
    fun statsText(f: FeedPost): String = "${f.kind.label} · ${ActivityText.duration(f.minutes)}" + if (f.effort >= 8) " · 🔥 pesado" else ""
}

// MARK: Ranking dos bros

enum class FriendsMetric(val title: String) {
    XP("XP"), CHECK_INS("Treinos"), DAYS("Dias ativos"), MINUTES("Minutos");

    fun format(v: Int): String = when (this) {
        XP -> "$v XP"
        CHECK_INS -> "$v treino${if (v == 1) "" else "s"}"
        DAYS -> "$v dia${if (v == 1) "" else "s"}"
        MINUTES -> ActivityText.duration(v)
    }
}

/** Janela do ranking (Leagues.swift `RankWindow`); "liga" no ranking dos bros aparece como "Sempre" */
enum class RankWindow(val title: String) {
    LIGA("Liga toda"), SEMANA("Esta semana"), MES("Este mês");

    /** Começo da semana (domingo) ou do mês no fuso das ligas, como o `League.rulesCalendar` com o idioma pt-BR */
    fun since(now: Instant, zone: ZoneId = ZoneId.of("America/Sao_Paulo")): Instant? {
        val today = now.atZone(zone).toLocalDate()
        return when (this) {
            LIGA -> null
            SEMANA -> today.with(TemporalAdjusters.previousOrSame(DayOfWeek.SUNDAY)).atStartOfDay(zone).toInstant()
            MES -> today.withDayOfMonth(1).atStartOfDay(zone).toInstant()
        }
    }
}

data class FriendRank(val id: String, val name: String, val avatar: MonsterForm, val isMe: Boolean, val value: Int)

data class RankPerson(val id: String, val name: String, val form: MonsterForm)

object FriendsRanking {
    /**
     * Placar dos posts do perfil na janela (FriendsFeed.swift `FriendsRanking.rank`). Empate: você na frente; entre
     * amigos empatados fica a ordem da lista (no iOS a ordem do empate não é garantida).
     */
    fun rank(me: List<FeedPost>, friends: List<FeedPost>, people: List<RankPerson>, myName: String, myAvatar: MonsterForm,
             metric: FriendsMetric, since: Instant?, zone: ZoneId = ZoneId.systemDefault()): List<FriendRank> {
        fun value(items: List<FeedPost>): Int {
            val w = items.filter { since == null || it.date >= since }
            return when (metric) {
                FriendsMetric.XP -> w.sumOf { it.score }
                FriendsMetric.CHECK_INS -> w.size
                FriendsMetric.DAYS -> w.map { it.date.atZone(zone).toLocalDate() }.toSet().size
                FriendsMetric.MINUTES -> w.sumOf { it.minutes }
            }
        }
        val rows = mutableListOf(FriendRank("me", myName.ifEmpty { "Você" }, myAvatar, true, value(me)))
        for (p in people) rows.add(FriendRank(p.id, p.name, p.form, false, value(friends.filter { it.memberID == p.id })))
        return rows.sortedWith(compareByDescending<FriendRank> { it.value }.thenByDescending { if (it.isMe) 1 else 0 })
    }

    fun medal(i: Int): String = if (i < 3) listOf("🥇", "🥈", "🥉")[i] else "${i + 1}º"
}

// MARK: Deck dos Bros (stories)

data class DeckCard(val item: FeedPost, val place: String, val leagueID: String?) {
    val id: String get() = item.id
}

data class DeckPerson(val id: String, val cards: List<DeckCard>, val unseen: Int) {
    val latest: FeedPost get() = cards.last().item
    /** Onde o deck começa: no primeiro que você não viu, ou do começo se já viu tudo */
    val start: Int get() = if (unseen > 0) cards.size - unseen else 0
}

object BroDeck {
    const val SEEN_KEY = "deck.seen"

    /** Marca como visto (guarda os 600 mais recentes) */
    fun markSeen(list: List<String>, ids: List<String>): List<String> {
        val out = list.toMutableList()
        for (id in ids) if (id !in out) out.add(id)
        return out.takeLast(600)
    }

    /** Check-ins dos outros dos últimos 3 dias (ligas e perfis dos amigos) que você não viu, do mais antigo ao mais novo */
    fun cards(leagues: List<LeagueFeed>, friends: List<FeedPost>, seen: Set<String>, includeSeen: Boolean = false, now: Instant): List<DeckCard> {
        val since = now.minusSeconds(3 * 86_400)
        val skip = if (includeSeen) emptySet() else seen
        val out = mutableListOf<DeckCard>()
        val ids = HashSet<String>()
        for (l in leagues) for (f in l.items) {
            if (!f.isMe && f.date >= since && f.id !in skip && ids.add(f.id)) out.add(DeckCard(f, l.label, l.leagueID))
        }
        for (f in friends) if (f.date >= since && f.id !in skip && ids.add(f.id)) out.add(DeckCard(f, f.postedIn ?: "Perfil", null))
        return out.sortedBy { it.item.date }
    }

    /** Pessoas com check-in nos últimos 3 dias: quem tem novidade primeiro, depois quem você já viu (mais recentes antes) */
    fun people(leagues: List<LeagueFeed>, friends: List<FeedPost>, seen: Set<String>, now: Instant): List<DeckPerson> {
        val all = cards(leagues, friends, seen, includeSeen = true, now = now)
        val people = all.groupBy { it.item.memberID }.map { (id, cards) ->
            val ordered = cards.filter { it.id in seen } + cards.filter { it.id !in seen }
            DeckPerson(id, ordered, cards.count { it.id !in seen })
        }
        return people.sortedWith(compareByDescending<DeckPerson> { it.unseen > 0 }.thenByDescending { p -> p.cards.maxOf { it.item.date } })
    }
}

// MARK: Comentários e reações

/**
 * Comentário ou reação num check-in (Models/League.swift `CheckInComment`, `comments` na cópia da conta). `authorID`
 * "me" = você. Reação a um comentário fica no item "c:<id do comentário>".
 */
data class SocialComment(val id: String, val itemID: String, val text: String, val date: Instant, val authorID: String = "me",
                         val authorName: String = "") {
    val isMine: Boolean get() = authorID == "me"
    val isReaction: Boolean get() = Reactions.isReaction(text)
}

object Reactions {
    /** Emojis da reação rápida no detalhe, nos comentários, no deck e nas mensagens */
    val detail = listOf("💪", "🔥", "👏", "😮‍💨", "🏆", "❤️")
    val quick = listOf("👍", "❤️‍🔥", "💪", "😂")
    val deck = listOf("👍", "❤️‍🔥", "💪", "🥚")

    private fun graphemes(s: String): Int {
        val it = BreakIterator.getCharacterInstance(Locale.ROOT)
        it.setText(s)
        var n = 0
        while (it.next() != BreakIterator.DONE) n++
        return n
    }

    /**
     * Comentário só com emoji é uma reação (`CheckInComment.isReaction`): até 3 caracteres, todos emoji. O iOS usa as
     * propriedades Unicode de emoji; aqui, as faixas de emoji (o Java 17 não tem essas propriedades).
     */
    fun isReaction(s: String): Boolean {
        if (s.isEmpty() || graphemes(s) > 3) return false
        var i = 0
        while (i < s.length) {
            val cp = s.codePointAt(i)
            if (!emojiScalar(cp)) return false
            i += Character.charCount(cp)
        }
        return true
    }

    private fun emojiScalar(v: Int): Boolean = v == 0x200D || v == 0xFE0F ||
        (v in 0x238D..0x23FF) || (v in 0x24C2..0x24C2) || (v in 0x25AA..0x27BF) || (v in 0x2934..0x2935) ||
        (v in 0x2B05..0x2BFF) || v == 0x3030 || v == 0x303D || v == 0x3297 || v == 0x3299 || v >= 0x1F000 && v <= 0x1FAFF

    /** "💪 3 ❤️‍🔥 1": os 3 emojis mais usados (o post no feed) */
    fun feedSummary(list: List<SocialComment>): String =
        list.groupBy { it.text }.entries.sortedByDescending { it.value.size }.take(3).joinToString(" ") { "${it.key} ${it.value.size}" }

    /** "💪 2 · 👍": todos, o número só quando passa de 1 (detalhe e mensagens) */
    fun summary(texts: List<String>): String =
        texts.groupingBy { it }.eachCount().entries.sortedByDescending { it.value }.joinToString(" · ") { if (it.value > 1) "${it.key} ${it.value}" else it.key }
}

// MARK: Por amigo

/** O que você controla por amigo (SocialExtras.swift `FriendPrefs`): esconder seus treinos e silenciar */
data class FriendPrefs(val hideMine: Boolean = false, val muted: Boolean = false) {
    companion object {
        const val KEY = "friends.prefs"

        fun all(raw: String?): Map<String, FriendPrefs> {
            if (raw.isNullOrEmpty()) return emptyMap()
            val o = runCatching { Json.parseToJsonElement(raw).jsonObject }.getOrNull() ?: return emptyMap()
            return o.mapValues { (_, v) ->
                val p = v as? JsonObject
                FriendPrefs((p?.get("hideMine") as? JsonPrimitive)?.booleanOrNull ?: false, (p?.get("muted") as? JsonPrimitive)?.booleanOrNull ?: false)
            }
        }

        fun of(raw: String?, id: String): FriendPrefs = all(raw)[id] ?: FriendPrefs()

        /** Muda um amigo; o padrão sai da lista. Volta o texto JSON que vai nos ajustes da conta (os dois campos sempre) */
        fun set(raw: String?, id: String, change: (FriendPrefs) -> FriendPrefs): String {
            val all = LinkedHashMap(all(raw))
            val p = change(all[id] ?: FriendPrefs())
            if (p == FriendPrefs()) all.remove(id) else all[id] = p
            return buildJsonObject {
                for ((k, v) in all.toSortedMap()) put(k, buildJsonObject { put("hideMine", v.hideMine); put("muted", v.muted) })
            }.toString()
        }

        /** Quem não vê seus treinos (vai em `profiles/{você}.hiddenFrom`) */
        fun hiddenFrom(raw: String?): List<String> = all(raw).filter { it.value.hideMine }.keys.sorted()
    }
}

// MARK: QR do código de amigo

object FriendQR {
    fun link(code: String) = "gymbros://amigo/$code"

    /** Lê o código de um QR ou link do GymBros (ou o próprio código, se alguém mostrou só ele) */
    fun code(text: String): String? {
        val t = text.trim()
        val marker = "gymbros://amigo/"
        val at = t.indexOf(marker)
        if (at >= 0) return t.substring(at + marker.length).uppercase()
        val plain = t.uppercase()
        return if (plain.length == 6 && plain.all { it.isLetterOrDigit() }) plain else null
    }
}

// MARK: Datas curtas

object SocialText {
    private val locale = Locale.forLanguageTag("pt-BR")

    /** "agora", "5 min", "3 h", "ontem", "12 de out." (InboxView.swift `shortAgo`) */
    fun shortAgo(date: Instant, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): String {
        val s = now.epochSecond - date.epochSecond
        if (s < 60) return "agora"
        if (s < 3600) return "${s / 60} min"
        val d = date.atZone(zone).toLocalDate()
        val today = now.atZone(zone).toLocalDate()
        if (d == today) return "${s / 3600} h"
        if (d == today.minusDays(1)) return "ontem"
        return d.format(DateTimeFormatter.ofPattern("d 'de' MMM", locale))
    }

    fun time(date: Instant, zone: ZoneId = ZoneId.systemDefault()): String = date.atZone(zone).format(DateTimeFormatter.ofPattern("HH:mm", locale))

    /** "Hoje, 07:30", "Ontem, 19:00" ou "sáb., 25 de out., 08:00" (CheckInDetail.swift `when`) */
    fun whenText(date: Instant, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): String {
        val d = date.atZone(zone).toLocalDate()
        val today = now.atZone(zone).toLocalDate()
        val t = time(date, zone)
        return when (d) {
            today -> "Hoje, $t"
            today.minusDays(1) -> "Ontem, $t"
            else -> "${d.format(DateTimeFormatter.ofPattern("EEE, d 'de' MMM", locale))}, $t"
        }
    }

    /** "Hoje", "Ontem" ou "quinta-feira, 23 de outubro" (ConversationView.swift `dayText`) */
    fun dayText(date: Instant, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): String {
        val d = date.atZone(zone).toLocalDate()
        val today = now.atZone(zone).toLocalDate()
        return when (d) {
            today -> "Hoje"
            today.minusDays(1) -> "Ontem"
            else -> d.format(DateTimeFormatter.ofPattern("EEEE, d 'de' MMMM", locale))
        }
    }

    /** "outubro de 2026" */
    fun monthTitle(d: LocalDate): String = d.format(DateTimeFormatter.ofPattern("MMMM 'de' yyyy", locale)).replaceFirstChar { it.uppercase() }
}
