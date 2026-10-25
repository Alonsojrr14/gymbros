package com.alonsoalmeida.gymbros.domain

import com.alonsoalmeida.gymbros.domain.backup.AccountEdits
import com.alonsoalmeida.gymbros.domain.onboarding.ScreenTip
import com.alonsoalmeida.gymbros.domain.onboarding.ScreenTips
import com.alonsoalmeida.gymbros.domain.profile.ProfileEdits
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File
import java.time.Instant

/** Dicas por tela (ScreenTipTests.swift): catálogo, formato da chave `tipsSeen` e quando mostrar */
class ScreenTipTest {
    private fun settings(raw: String?): Map<String, Any?> = if (raw == null) emptyMap() else mapOf(ScreenTips.KEY to raw)

    @Test
    fun catalogHasStableUniqueKebabIDsAndShortCards() {
        val ids = ScreenTip.ALL.map { it.id }
        assertEquals(ids.size, ids.toSet().size)
        for (tip in ScreenTip.ALL) {
            assertTrue(Regex("^[a-z0-9]+(-[a-z0-9]+)*$").matches(tip.id), tip.id)
            assertTrue(tip.cards.size in 2..4, "${tip.id} tem ${tip.cards.size} cartões")
            for (c in tip.cards) {
                assertTrue(c.title.isNotEmpty())
                assertTrue(c.symbol.isNotEmpty())
                assertTrue(c.text.length <= 200, "${tip.id}: ${c.title}")
            }
        }
    }

    @Test
    fun parseIgnoresEmptiesSpacesAndRepeats() {
        assertEquals(emptyList<String>(), ScreenTips.parse(null))
        assertEquals(emptyList<String>(), ScreenTips.parse(""))
        assertEquals(listOf("box"), ScreenTips.parse("box"))
        assertEquals(listOf("box", "brobook", "x1"), ScreenTips.parse(" box, ,brobook,,box ,x1,"))
        assertEquals("box,x1", ScreenTips.encode(listOf("box", "", "x1", "box")))
    }

    @Test
    fun notSeenShowsAndMarkingHidesForGood() {
        var raw: String? = null
        assertTrue(ScreenTips.shouldShow(ScreenTip.BOX, settings(raw)))
        assertFalse(ScreenTips.shouldShow(ScreenTip.BOX, settings(raw), blocked = true))

        for (id in listOf("box", "x1", "box")) ScreenTips.markSeen(id, raw)?.let { raw = it }
        assertEquals("box,x1", raw)
        assertNull(ScreenTips.markSeen("box", raw))
        assertFalse(ScreenTips.shouldShow(ScreenTip.BOX, settings(raw)))
        assertFalse(ScreenTips.shouldShow(ScreenTip.DUELS, settings(raw)))
        assertTrue(ScreenTips.shouldShow(ScreenTip.BROBOOK, settings(raw)))
    }

    @Test
    fun resetShowsEverythingAgain() {
        var copy = AccountEdits.empty("Zé", Instant.parse("2026-10-25T12:00:00Z"))
        for (tip in ScreenTip.ALL) {
            val raw = ProfileEdits.settings(copy)[ScreenTips.KEY] as? String
            ScreenTips.markSeen(tip.id, raw)?.let { copy = ProfileEdits.set(copy, ScreenTips.KEY, it) }
        }
        assertEquals(ScreenTip.ALL.map { it.id }.toSet(), ScreenTips.seen(ProfileEdits.settings(copy)))
        copy = ProfileEdits.set(copy, ScreenTips.KEY, null)
        assertFalse(ScreenTips.KEY in ProfileEdits.settings(copy))
        assertTrue(ScreenTip.ALL.all { ScreenTips.shouldShow(it, ProfileEdits.settings(copy)) })
    }

    /** Vem de outro aparelho com espaços ou ids que este app ainda não conhece: lê o que entende e não perde o resto */
    @Test
    fun unknownIDsSurviveMarking() {
        val raw = "dica-nova, box"
        assertFalse(ScreenTips.shouldShow(ScreenTip.BOX, settings(raw)))
        assertEquals("dica-nova,box,feed", ScreenTips.markSeen("feed", raw))
    }

    /** Texto no plist `accountSettings` (como `UserDefaults.set(String)` do iOS) e fora das `settingKeys` do backup */
    @Test
    fun keyGoesWithTheAccountCopyAsText() {
        val copy = ProfileEdits.set(AccountEdits.empty("Zé", Instant.parse("2026-10-25T12:00:00Z")), ScreenTips.KEY, "box,x1")
        assertEquals("box,x1", ProfileEdits.settings(copy)[ScreenTips.KEY])
        assertFalse(ScreenTips.KEY in ProfileEdits.SETTING_KEYS)
    }

    /**
     * Mesmo catálogo do iPhone, lido de ios/GymBros/Onboarding/ScreenTip.swift. Diferenças de propósito: o Health Connect
     * no lugar do Apple Saúde, o treino do coach só por texto (o Android não lê print) e a localização "Permitir o tempo
     * todo" (o nome do Android para o "Sempre" do iOS) e a caixa de entrada sem X1 (no Android ela traz pedidos de amizade) e o
     * peso sem fotos de progresso (ainda não chegaram ao Android).
     */
    @Test
    fun catalogMatchesTheIPhone() {
        val swift = File("../../../ios/GymBros/Onboarding/ScreenTip.swift").takeIf { it.exists() }?.readText() ?: return
        val tipRe = Regex("""ScreenTip\(id: "([^"]+)", screen: "([^"]+)", cards: \[(.*?)\]\)""", RegexOption.DOT_MATCHES_ALL)
        val cardRe = Regex("""\.init\(title: "([^"]+)", text: "([^"]+)",\s*symbol: "([^"]+)"\)""")
        val ios = tipRe.findAll(swift).map { m ->
            ScreenTip(m.groupValues[1], m.groupValues[2], cardRe.findAll(m.groupValues[3]).map {
                com.alonsoalmeida.gymbros.domain.onboarding.ScreenTipCard(it.groupValues[1], it.groupValues[2], it.groupValues[3])
            }.toList())
        }.toList()
        val android = setOf(ScreenTip.WOD.cards[2], ScreenTip.MAP.cards[1], ScreenTip.INBOX.cards[0],
                             ScreenTip.BODY.cards[0], ScreenTip.BODY.cards[2])
        assertEquals(ios.map { it.id }, ScreenTip.ALL.map { it.id })
        for ((a, i) in ScreenTip.ALL.zip(ios)) {
            assertEquals(i.screen, a.screen, a.id)
            assertEquals(i.cards.size, a.cards.size, a.id)
            for ((ac, ic) in a.cards.zip(i.cards)) {
                if (ac in android) continue
                assertEquals(ic.copy(title = ic.title.replace("Apple Saúde", "Health Connect"), text = ic.text.replace("Apple Saúde", "Health Connect")), ac, a.id)
            }
        }
    }
}
