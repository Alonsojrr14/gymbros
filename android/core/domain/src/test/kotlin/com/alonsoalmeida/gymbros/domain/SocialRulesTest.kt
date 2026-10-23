package com.alonsoalmeida.gymbros.domain

import com.alonsoalmeida.gymbros.domain.social.BlockedTerms
import com.alonsoalmeida.gymbros.domain.social.BlockedUser
import com.alonsoalmeida.gymbros.domain.social.BroDeck
import com.alonsoalmeida.gymbros.domain.social.ContentFilter
import com.alonsoalmeida.gymbros.domain.social.DirectKind
import com.alonsoalmeida.gymbros.domain.social.DirectMessage
import com.alonsoalmeida.gymbros.domain.social.FeedPost
import com.alonsoalmeida.gymbros.domain.social.FriendPrefs
import com.alonsoalmeida.gymbros.domain.social.FriendQR
import com.alonsoalmeida.gymbros.domain.social.FriendsMetric
import com.alonsoalmeida.gymbros.domain.social.FriendsRanking
import com.alonsoalmeida.gymbros.domain.social.InboxMarks
import com.alonsoalmeida.gymbros.domain.social.InboxPeer
import com.alonsoalmeida.gymbros.domain.social.InboxRules
import com.alonsoalmeida.gymbros.domain.social.LeagueFeed
import com.alonsoalmeida.gymbros.domain.social.Moderation
import com.alonsoalmeida.gymbros.domain.social.RankPerson
import com.alonsoalmeida.gymbros.domain.social.RankWindow
import com.alonsoalmeida.gymbros.domain.social.Reactions
import com.alonsoalmeida.gymbros.domain.social.ReportedKind
import com.alonsoalmeida.gymbros.domain.social.SocialComment
import com.alonsoalmeida.gymbros.domain.social.SocialText
import com.alonsoalmeida.gymbros.domain.social.UnifiedFeed
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.time.Instant
import java.time.ZoneId

/** Regras sociais portadas do iOS (ContentFilterTests, SocialExtrasTests, NowFeaturesTests e InboxTests do Swift) */
class SocialRulesTest {
    private val now = Instant.parse("2026-10-23T15:00:00Z")
    private val utc = ZoneId.of("UTC")

    private fun item(who: String, minutes: Int, hoursAgo: Long, title: String = "", id: String = "$who-$hoursAgo-$title") =
        FeedPost(id, who, who, MonsterForm.EGG, who == "me", now.minusSeconds(hoursAgo * 3600), title, "", ActivityKind.CORRIDA, minutes, minutes)

    // MARK: Filtro de palavras (ContentFilterTests.swift)

    @Test
    fun blocksOffensiveTermsInPortugueseAndEnglish() {
        for (t in listOf("Que treino de merda", "vai se matar", "you piece of shit", "kill yourself", "FDP", "seu otário")) assertFalse(ContentFilter.allows(t), t)
    }

    @Test
    fun normalizesAccentsCaseAndCommonSwaps() {
        for (t in listOf("CUZÃO", "P0RR4", "c@ralho", "\$h1t", "merda!", "Merdaaa", "porrraaa", "p u t a", "putaria123", "Fucking hell")) {
            assertFalse(ContentFilter.allows(t), t)
        }
    }

    @Test
    fun respectsWordBoundaries() {
        val innocent = listOf("computador", "Scunthorpe", "class", "assessoria", "cuidado", "escuta", "putativo", "Fagundes",
                              "as pernas", "Bora treinar!", "3x10 supino", "Dia de perna 🦵", "e o a", "Cucumber", "Shiitake", "")
        for (t in innocent) assertTrue(ContentFilter.allows(t), t)
    }

    @Test
    fun prefixTermsAndCustomList() {
        assertEquals("caralho*", ContentFilter.match("caralhooo", listOf("caralho*")))
        assertNull(ContentFilter.match("caralh", listOf("caralho*")))
        assertEquals("frango", ContentFilter.match("abc frango xyz", listOf("frango")))
        assertNull(ContentFilter.match("frangos", listOf("frango")))
        assertEquals("dia de perna", ContentFilter.match("nossa, dia de perna", listOf("dia de perna")))
    }

    @Test
    fun everyListedTermIsCaughtByItself() {
        for (term in BlockedTerms.all) assertFalse(ContentFilter.allows(term.removeSuffix("*")), term)
    }

    @Test
    fun publishableBlanksBlockedText() {
        assertEquals("Zero", ContentFilter.publishable("Zero"))
        assertEquals("", ContentFilter.publishable("Rei da porra"))
    }

    // MARK: Por amigo e QR (SocialExtrasTests.swift)

    @Test
    fun friendPrefsPerFriend() {
        var raw: String? = null
        assertEquals(FriendPrefs(), FriendPrefs.of(raw, "ana"))
        raw = FriendPrefs.set(raw, "ana") { it.copy(hideMine = true) }
        raw = FriendPrefs.set(raw, "bruno") { it.copy(muted = true) }
        assertTrue(FriendPrefs.of(raw, "ana").hideMine)
        assertTrue(FriendPrefs.of(raw, "bruno").muted)
        assertEquals(listOf("ana"), FriendPrefs.hiddenFrom(raw))
        raw = FriendPrefs.set(raw, "ana") { it.copy(hideMine = false) }
        assertEquals(emptyList<String>(), FriendPrefs.hiddenFrom(raw))
        // O formato do iPhone: os dois campos de cada amigo
        assertEquals("""{"bruno":{"hideMine":false,"muted":true}}""", raw)
        assertTrue(FriendPrefs.of("""{"x":{"hideMine":true,"muted":false}}""", "x").hideMine)
    }

    @Test
    fun friendQRCode() {
        assertEquals("gymbros://amigo/ABC123", FriendQR.link("ABC123"))
        assertEquals("ABC123", FriendQR.code("gymbros://amigo/abc123"))
        assertEquals("XYZ789", FriendQR.code(" XYZ789 "))
        assertNull(FriendQR.code("https://exemplo.com"))
    }

    // MARK: Feed unificado e ranking (NowFeaturesTests.swift)

    @Test
    fun unifiedFeedMergesSamePostInManyLeagues() {
        val mine = item("me", 60, 1, "Peito", id = "A")
        val sameInOther = mine.copy(id = "B")
        val feed = UnifiedFeed.build(listOf(LeagueFeed("1️⃣ Um", "L1", listOf(mine)), LeagueFeed("2️⃣ Dois", "L2", listOf(sameInOther))), emptyList())
        assertEquals(1, feed.size)
        assertEquals(listOf("1️⃣ Um", "2️⃣ Dois"), feed[0].places)
        assertEquals(setOf("L1", "L2"), feed[0].leagueIDs)
        // Post do amigo no perfil e na liga: um só, com os dois lugares; sozinho, vem do perfil
        val ana = item("ana", 30, 2, "Corrida")
        val both = UnifiedFeed.build(listOf(LeagueFeed("🔥 Liga", "L", listOf(ana))), listOf(ana.copy(id = "x"), item("ana", 20, 5, "Outra")))
        assertEquals(listOf("🔥 Liga", "Perfil"), both[0].places)
        assertTrue(both[1].fromFriendProfile)
        assertEquals("a · b +1", UnifiedFeed.placesText(listOf("a", "b", "c")))
    }

    @Test
    fun friendsRankingByMetric() {
        val rows = FriendsRanking.rank(listOf(item("me", 30, 1)), listOf(item("ana", 20, 1), item("ana", 20, 2)),
                                       listOf(RankPerson("ana", "Ana", MonsterForm.EGG)), "Eu", MonsterForm.EGG, FriendsMetric.CHECK_INS, null)
        assertEquals("ana", rows.first().id)
        val byMinutes = FriendsRanking.rank(listOf(item("me", 50, 1)), listOf(item("ana", 20, 1)),
                                            listOf(RankPerson("ana", "Ana", MonsterForm.EGG)), "Eu", MonsterForm.EGG, FriendsMetric.MINUTES, null)
        assertEquals("me", byMinutes.first().id)
        // Empate: você na frente
        val tie = FriendsRanking.rank(listOf(item("me", 20, 1)), listOf(item("ana", 20, 1)),
                                      listOf(RankPerson("ana", "Ana", MonsterForm.EGG)), "", MonsterForm.EGG, FriendsMetric.CHECK_INS, null)
        assertEquals(listOf("me", "ana"), tie.map { it.id })
        assertEquals("Você", tie[0].name)
        assertEquals("1 treino", FriendsMetric.CHECK_INS.format(1))
        assertEquals("1 h 5 min", FriendsMetric.MINUTES.format(65))
    }

    @Test
    fun rankWindowStartsOnSundayInBrasilia() {
        // 23/10/2026 é sexta-feira: a semana começou no domingo 18/10, 00:00 de Brasília (03:00 UTC)
        assertEquals(Instant.parse("2026-10-18T03:00:00Z"), RankWindow.SEMANA.since(now))
        assertEquals(Instant.parse("2026-10-01T03:00:00Z"), RankWindow.MES.since(now))
        assertNull(RankWindow.LIGA.since(now))
    }

    // MARK: Deck, reações e moderação

    @Test
    fun deckShowsOthersUnseenFirst() {
        val l = LeagueFeed("🔥 Liga", "L", listOf(item("me", 30, 1), item("ana", 30, 2), item("bia", 30, 5), item("ana", 30, 100)))
        val cards = BroDeck.cards(listOf(l), emptyList(), emptySet(), now = now)
        assertEquals(listOf("bia", "ana"), cards.map { it.item.memberID })
        val people = BroDeck.people(listOf(l), emptyList(), setOf(cards[1].id), now)
        assertEquals(listOf("bia", "ana"), people.map { it.id })
        assertEquals(0, people[1].unseen)
        assertEquals(0, people[1].start)
        assertEquals(listOf("a", "b"), BroDeck.markSeen(listOf("a"), listOf("a", "b")))
    }

    @Test
    fun reactionsAreEmojiOnly() {
        for (e in listOf("💪", "❤️‍🔥", "👍🏽", "🔥🔥", "😮‍💨", "❤️")) assertTrue(Reactions.isReaction(e), e)
        for (t in listOf("ok", "💪 boa", "1", "", "💪💪💪💪")) assertFalse(Reactions.isReaction(t), t)
        val list = listOf("💪", "💪", "👍").mapIndexed { i, t -> SocialComment("$i", "p", t, now) }
        assertEquals("💪 2 👍 1", Reactions.feedSummary(list))
        assertEquals("💪 2 · 👍", Reactions.summary(list.map { it.text }))
    }

    @Test
    fun moderationHidesBlockedAndReported() {
        val mod = Moderation(listOf(BlockedUser("bia", "Bia", now)), setOf(ReportedKind.CHECK_IN.key("ana-2-"), ReportedKind.PHOTO.key("ana-3-")))
        val posts = listOf(item("me", 1, 1), item("ana", 1, 2), item("ana", 1, 3).copy(hasPhoto = true), item("bia", 1, 4))
        val shown = mod.visiblePosts(posts)
        assertEquals(listOf("me-1-", "ana-3-"), shown.map { it.id })
        assertFalse(shown[1].hasPhoto)
        // Mesmo formato do iPhone (JSONEncoder: datas em segundos desde 2001)
        val back = Moderation.decodeBlocked(Moderation.encodeBlocked(mod.blocked))
        assertEquals(mod.blocked, back)
        assertEquals(setOf("x:1"), Moderation.decodeHidden("""["x:1"]""".encodeToByteArray()))
        val ios = """[{"id":"u1","name":"Ana","date":782000000.5}]""".encodeToByteArray()
        assertEquals(Instant.parse("2025-10-12T22:13:20.500Z"), Moderation.decodeBlocked(ios)[0].date)
    }

    // MARK: Caixa de entrada

    @Test
    fun conversationsUnreadArchiveAndClear() {
        fun dm(id: String, peer: String, min: Long, out: Boolean = false, kind: DirectKind = DirectKind.TEXT) =
            DirectMessage(id, peer, out, now.minusSeconds(min * 60), kind, "oi $id")
        val all = listOf(dm("1", "ana", 30), dm("2", "ana", 20, out = true), dm("3", "ana", 10), dm("4", "bia", 5), dm("5", "caio", 50))
        val peer = { id: String -> InboxPeer(id, id.uppercase(), "egg") }
        var marks = InboxMarks(readUntil = mapOf("ana" to now.minusSeconds(25 * 60)))
        val list = InboxRules.conversations(all, marks, peer, archived = false)
        assertEquals(listOf("bia", "ana", "caio"), list.map { it.id })
        assertEquals(1, list[1].unread)
        assertEquals(0, InboxRules.conversations(all, marks, peer, archived = false, openPeer = "ana")[1].unread)
        // Arquivada some até chegar mensagem nova; limpar esconde só o que já tinha
        marks = marks.copy(archived = mapOf("caio" to now), cleared = mapOf("bia" to now))
        assertEquals(listOf("ana"), InboxRules.conversations(all, marks, peer, archived = false).map { it.id })
        assertEquals(listOf("caio"), InboxRules.conversations(all, marks, peer, archived = true).map { it.id })
        assertEquals("Você: oi 2", dm("2", "ana", 1, out = true).preview())
        assertEquals("💪 Mandou força: oi 9", dm("9", "ana", 1, kind = DirectKind.CHEER).preview())
    }

    @Test
    fun activityHasCheersInvitesAndRequests() {
        val peer = { id: String -> InboxPeer(id, "Ana", "egg") }
        val msgs = listOf(DirectMessage("1", "ana", false, now.minusSeconds(60), DirectKind.CHEER),
                          DirectMessage("2", "ana", false, now.minusSeconds(120), DirectKind.TEXT, "oi"),
                          DirectMessage("3", "ana", true, now.minusSeconds(30), DirectKind.CHEER))
        val marks = InboxMarks(seenAt = now.minusSeconds(90), requestsSeen = mapOf("bia" to now.minusSeconds(300)))
        val events = InboxRules.activity(msgs, listOf(InboxPeer("bia", "Bia", "egg")), marks, peer, now = now)
        assertEquals(listOf("dm-1", "request-bia"), events.map { it.id })
        assertEquals(0, InboxRules.unreadActivity(events, marks))
        assertEquals(mapOf("bia" to now.minusSeconds(300), "caio" to now),
                     InboxRules.rememberRequests(marks.requestsSeen + ("velho" to now), setOf("bia", "caio"), now))
    }

    @Test
    fun shortTimes() {
        assertEquals("agora", SocialText.shortAgo(now.minusSeconds(30), now, utc))
        assertEquals("5 min", SocialText.shortAgo(now.minusSeconds(300), now, utc))
        assertEquals("3 h", SocialText.shortAgo(now.minusSeconds(3 * 3600), now, utc))
        assertEquals("ontem", SocialText.shortAgo(now.minusSeconds(20 * 3600), now, utc))
        assertEquals("12 de out.", SocialText.shortAgo(Instant.parse("2026-10-12T12:00:00Z"), now, utc))
    }
}
