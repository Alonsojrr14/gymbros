package com.alonsoalmeida.gymbros.domain

import com.alonsoalmeida.gymbros.domain.backup.AccountCopy
import com.alonsoalmeida.gymbros.domain.backup.AccountEdits
import com.alonsoalmeida.gymbros.domain.backup.LeagueDto
import com.alonsoalmeida.gymbros.domain.bros.BroEdits
import com.alonsoalmeida.gymbros.domain.bros.BroSettings
import com.alonsoalmeida.gymbros.domain.bros.Dex
import com.alonsoalmeida.gymbros.domain.bros.MyTradeBro
import com.alonsoalmeida.gymbros.domain.bros.TradeAnswer
import com.alonsoalmeida.gymbros.domain.bros.TradeBro
import com.alonsoalmeida.gymbros.domain.bros.TradeLedger
import com.alonsoalmeida.gymbros.domain.bros.TradeOwner
import com.alonsoalmeida.gymbros.domain.bros.TradePerson
import com.alonsoalmeida.gymbros.domain.bros.TradeProposal
import com.alonsoalmeida.gymbros.domain.bros.TradeRefusal
import com.alonsoalmeida.gymbros.domain.bros.TradeRules
import com.alonsoalmeida.gymbros.domain.home.HomeBuilder
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.time.Instant
import java.time.ZoneId

/** Box, BroBook e trocas (Monsters.swift, DexView.swift, Trade.swift) sobre a cópia que o iPhone exportou (vetor C) */
class BrosTradesTest {
    private val c = Json.parseToJsonElement(javaClass.getResource("/gymbros-golden-C.json")!!.readText()).jsonObject
    /** A corrida do vetor aponta para um bro que não existe (cai no inicial); aqui ela é do inicial de verdade */
    private val iphone = (Json.parseToJsonElement(c["backupJSON"]!!.jsonPrimitive.content) as JsonObject).let { o ->
        val acts = (o["activities"] as JsonArray).map { a ->
            JsonObject(a.jsonObject + ("monsterUUID" to kotlinx.serialization.json.JsonPrimitive("E9960F7C-A8CB-4E48-A105-147353092279")))
        }
        JsonObject(o + ("activities" to JsonArray(acts)))
    }
    private val now = Instant.parse("2027-01-16T12:00:00Z")
    private val clock = RuleClock(ZoneId.of("America/Sao_Paulo"), now)
    private val starter = "E9960F7C-A8CB-4E48-A105-147353092279"

    private fun home(o: JsonObject) = HomeBuilder.build(AccountCopy.decode(o), clock)

    private fun bro(id: String, form: String = "champion_forca", xp: Int = 1500, history: List<TradeOwner> = emptyList()) =
        TradeBro(id, MonsterForm.byID(form)!!.name, form, xp, mapOf("forca" to 900.0, "tecnica" to 300.0), history)

    private val me = TradePerson(TradeProposal.ME, "Treinadora", "egg")
    private val bruno = TradePerson("uidBruno", "Bruno", "champion_forca")

    /** Bruno aceitou a minha proposta: dou o inicial e recebo o Atleta dele */
    private fun accepted(give: String = starter, history: List<TradeOwner> = listOf(TradeOwner("Lia", 1000), TradeOwner("Bruno", 500))) =
        TradeProposal("T1", me, bruno, bro(give, "rookie"), bro("uidBruno-b1", history = history), now.minusSeconds(3600),
                      TradeAnswer.ACCEPTED, now.minusSeconds(60))

    @Test
    fun tradeBroJsonIsTheIPhoneFormat() {
        // Como o JSONEncoder do iOS grava (Double inteiro sem ".0")
        val swift = """{"id":"A","name":"Coelhão","formID":"cachorro/champion_forca","xp":1500,"attributes":{"forca":900,"tecnica":300.5},"history":[{"name":"Lia","xp":1500}]}"""
        val b = TradeRules.decode(swift)!!
        assertEquals("cachorro", b.form.species)
        assertEquals(300.5, b.attributes["tecnica"])
        assertEquals(listOf(TradeOwner("Lia", 1500)), b.history)
        assertEquals(b, TradeRules.decode(TradeRules.encode(b)))
        // Todos os campos sempre presentes (o Decodable sintetizado do Swift exige as chaves)
        val keys = Json.parseToJsonElement(TradeRules.encode(TradeBro("x", "n", "egg", 0))).jsonObject.keys
        assertEquals(setOf("id", "name", "formID", "xp", "attributes", "history"), keys)
    }

    @Test
    fun acceptedTradeSwapsTheBroOnceAndKeepsItsXP() {
        val p = accepted()
        val r = TradeLedger.apply(iphone, p, emptySet(), now, newUUID = "NEW-BRO")!!
        val h = home(r.copy)
        // O inicial saiu; o novo chegou com a forma, a espécie e o XP que tinha
        assertNull(h.roster.monster(starter))
        val s = h.roster.snapshot("NEW-BRO")
        assertEquals("champion_forca", s.form.id)
        assertEquals(1500, s.totalXP)
        assertEquals(listOf(OwnerXP("Lia", 1000), OwnerXP("Bruno", 500)), s.inherited)
        assertEquals(0, s.myXP)
        assertEquals(p.answeredAt, s.arrivedAt)
        val settings = BroSettings.read(AccountCopy.decode(r.copy))
        assertEquals(setOf("T1"), settings.tradeApplied)
        // Os treinos do inicial foram com ele: não passam para o bro novo
        assertTrue(h.roster.records["NEW-BRO"].isNullOrEmpty())
        assertTrue(h.roster.snapshot("NEW-BRO").xpByActivity.isEmpty())
        // Uma vez só
        assertNull(TradeLedger.apply(r.copy, p, settings.tradeApplied, now))
        // Nada do iPhone se perde além do que a troca muda
        for ((k, v) in iphone) if (k != "monsters" && k != "accountSettings") assertEquals(v, r.copy[k], k)
    }

    @Test
    fun arrivalWithoutHistoryCreditsTheFriend() {
        val r = TradeLedger.apply(iphone, accepted(history = emptyList()), emptySet(), now, newUUID = "NEW")!!
        assertEquals(listOf(OwnerXP("Bruno", 1500)), home(r.copy).roster.snapshot("NEW").inherited)
    }

    @Test
    fun pendingOrDeclinedChangesNothing() {
        val p = accepted().copy(answer = null, answeredAt = null)
        assertNull(TradeLedger.apply(iphone, p, emptySet(), now))
        assertNull(TradeLedger.apply(iphone, p.copy(answer = TradeAnswer.DECLINED), emptySet(), now))
    }

    @Test
    fun listsFollowTheIPhone() {
        val incoming = TradeProposal("IN", bruno, me, bro("b"), bro("m"), now.minusSeconds(100))
        val old = TradeProposal("OLD", bruno, me, bro("b"), bro("m"), now.minus(TradeProposal.WINDOW).minusSeconds(1))
        val sent = TradeProposal("OUT", me, bruno, bro("m2"), bro("b2"), now.minusSeconds(50))
        val ready = accepted()
        val doneIn = TradeProposal("DONE", bruno, me, bro("b3"), bro("m3"), now.minusSeconds(9000), TradeAnswer.ACCEPTED, now.minusSeconds(8000))
        val all = listOf(incoming, old, sent, ready, doneIn)
        assertEquals(listOf("IN"), TradeRules.incoming(all, now).map { it.id })
        assertEquals(listOf("OUT"), TradeRules.sent(all, now).map { it.id })
        assertEquals(listOf("T1"), TradeRules.ready(all, emptySet()).map { it.id })
        assertEquals(listOf("DONE"), TradeRules.done(all, emptySet()).map { it.id })
        assertEquals(listOf("T1", "DONE"), TradeRules.done(all, setOf("T1")).map { it.id })
        assertEquals(listOf("DONE"), TradeRules.toApply(all, emptySet()).map { it.id })
        assertTrue(TradeRules.ready(all, setOf("T1")).isEmpty())
        // Do meu ponto de vista
        assertEquals("b", incoming.theirs.id)
        assertEquals("m", incoming.mine.id)
        assertEquals("Bruno", incoming.friend.name)
    }

    @Test
    fun refusalsInTheIPhoneOrder() {
        fun mine(id: String, form: String? = "champion_forca", starter: Boolean = false) = MyTradeBro(id, starter, form, bro(id))
        val league = LeagueDto(uuid = "L", name = "Firma", emoji = "🏆", scoring = "xp", code = "ABC", isMock = false, monsterUUID = "R1",
                               start = now.minusSeconds(86_400), joinedAt = now.minusSeconds(86_400))
        fun refusal(m: MyTradeBro, all: List<TradeProposal> = emptyList(), busy: Set<String> = emptySet(), applied: Set<String> = emptySet()) =
            TradeRules.refusal(m, "MAIN", listOf(league), busy, all, applied, now)
        assertEquals(TradeRefusal.Egg, refusal(mine("E", "egg")))
        assertEquals(TradeRefusal.Egg, refusal(mine("E", null)))
        assertEquals(TradeRefusal.Main, refusal(mine("MAIN")))
        assertEquals(TradeRefusal.League("Firma"), refusal(mine("R1")))
        assertEquals(TradeRefusal.InDuel, refusal(mine("X"), busy = setOf("x")))
        val sent = TradeProposal("S", me, bruno, bro("FREE"), bro("b"), now.minusSeconds(10))
        assertEquals(TradeRefusal.Busy, refusal(mine("FREE"), all = listOf(sent)))
        val ready = accepted(give = "GIVEN")
        assertEquals(TradeRefusal.Busy, refusal(mine("GIVEN"), all = listOf(ready)))
        assertNull(refusal(mine("GIVEN"), all = listOf(ready), applied = setOf("T1")))
        assertNull(refusal(mine("FREE")))
        // Sem principal gravado, o inicial é o principal
        assertEquals(TradeRefusal.Main, TradeRules.refusal(mine("S0", starter = true), null, emptyList(), emptySet(), emptyList(), emptySet(), now))
    }

    @Test
    fun myBrosSplitTheXPByOwner() {
        val after = TradeLedger.apply(iphone, accepted(), emptySet(), now, newUUID = "NEW")!!.copy
        val withRun = AccountEdits.addActivity(BroEdits.setMain(after, "NEW"), AccountEdits.NewActivity("corrida", now.minusSeconds(600), 30, 5, "", 37,
            AttributeSplit.encode(AttributeSplit.split(ActivityKind.CORRIDA, 30, 5, healthType = 37))))
        val h = home(withRun)
        val list = TradeRules.myBros(h.roster, emptyMap(), "")
        val b = list.single { it.uuid == "NEW" }.bro
        val gained = h.roster.snapshot("NEW").myXP
        assertTrue(gained > 0)
        assertEquals(listOf(TradeOwner("Lia", 1000), TradeOwner("Bruno", 500), TradeOwner("Você", gained)), b.history)
        assertEquals(b.xp, b.history.sumOf { it.xp })
    }

    @Test
    fun mainAndNicknameReachTheIPhoneKeys() {
        val two = TradeLedger.apply(
            AccountEdits.addActivity(iphone, AccountEdits.NewActivity("corrida", now.minusSeconds(600), 30, 5, "", 37, "")),
            accepted(give = "NOT-MINE"), emptySet(), now, newUUID = "NEW")!!.copy
        val main = BroEdits.setMain(two, "new")
        assertEquals("NEW", home(main).roster.mainID)
        assertEquals("NEW", (main["settings"] as JsonObject)["mainMonster"]!!.jsonPrimitive.content)
        val plist = AccountCopy.settings(java.util.Base64.getDecoder().decode((main["accountSettings"])!!.jsonPrimitive.content))
        assertEquals("NEW", plist["mainMonster"])
        // A atividade nova vai para o principal novo
        val run = AccountEdits.addActivity(main, AccountEdits.NewActivity("corrida", now.minusSeconds(60), 20, 5, "", 37, "", id = "R2"))
        assertTrue(home(run).roster.records["NEW"]!!.any { it.id == "R2" })

        val named = BroEdits.rename(main, "NEW", "  Tanque ")
        val m = (named["monsters"] as JsonArray).map { it.jsonObject }.single { it["uuid"]!!.jsonPrimitive.content == "NEW" }
        assertEquals("Tanque", m["name"]!!.jsonPrimitive.content)
        assertEquals("Tanque", home(named).roster.monster("NEW")!!.displayName(home(named).roster.snapshot("NEW").form))
        assertFalse(BroSettings.read(AccountCopy.decode(BroEdits.setRevealAll(named, false))).revealAll)
        assertTrue(BroSettings.read(AccountCopy.decode(BroEdits.setRevealAll(named, true))).revealAll)
    }

    @Test
    fun broBookCountsLikeTheIPhone() {
        val all = Dex.allForms()
        assertEquals("egg", all.first().id)
        assertEquals(all.size, all.map { it.id }.toSet().size)
        // Sem arte carregada (JVM): por espécie, 10 normais + 90 viradas, sem híbridos
        assertEquals(1 + Species.catalog.size * 100, all.size)
        val h = home(iphone)
        val seen = Dex.discovered("baby,rookie", h.roster)
        assertTrue("egg" in seen && "baby" in seen && "rookie" in seen)
        assertNotNull(BroSettings.read(AccountCopy.decode(iphone)))
    }

    @Test
    fun hatchingBecomesASceneOnceAndFixesTheSpecies() {
        // 300 min de corrida chocam o ovo do inicial
        var copy = iphone
        repeat(3) { i ->
            copy = AccountEdits.addActivity(copy, AccountEdits.NewActivity("corrida", now.minusSeconds(3600L * (i + 2)), 100, 7, "", 37,
                AttributeSplit.encode(AttributeSplit.split(ActivityKind.CORRIDA, 100, 7, healthType = 37)), id = "H$i"))
        }
        val h = home(copy)
        val r = com.alonsoalmeida.gymbros.domain.bros.BroEvents.check(copy, h.roster)
        val e = r.events.single()
        assertEquals(starter, e.monster)
        assertTrue(e.hatching)
        val written = r.copy!!
        val m = (written["monsters"] as JsonArray).map { it.jsonObject }.single { it["uuid"]!!.jsonPrimitive.content == starter }
        assertEquals(h.roster.snapshot(starter).form.id, m["lastFormID"]!!.jsonPrimitive.content)
        assertEquals(h.roster.snapshot(starter).form.species, m["speciesID"]!!.jsonPrimitive.content)
        val seen = BroSettings.read(AccountCopy.decode(written)).discovered!!.split(",")
        assertTrue(h.roster.snapshot(starter).form.id in seen)
        // Uma vez só: a segunda conferência não acha cena nem grava de novo
        val again = com.alonsoalmeida.gymbros.domain.bros.BroEvents.check(written, home(written).roster)
        assertTrue(again.events.isEmpty())
        assertNull(again.copy)
    }
}
