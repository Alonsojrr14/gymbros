package com.alonsoalmeida.gymbros.domain.leagues

import com.alonsoalmeida.gymbros.domain.LeagueScoring
import com.alonsoalmeida.gymbros.domain.MonsterForm
import com.alonsoalmeida.gymbros.domain.backup.AccountEdits
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.time.Instant
import java.time.LocalDate

/** Regras das ligas portadas de Leagues.swift, LeagueRules.swift e CheckInProof.swift */
class LeaguesTest {
    private val cal = RulesCalendar.RULES
    private fun at(s: String) = Instant.parse(s)

    @Test
    fun settingsReadTheIOSFormatAndKeepUnknownKeys() {
        // O JSONEncoder do iOS grava `[LimitPeriod: Int]` como lista alternada
        val raw = """{"approved":[],"banned":["x"],"futuro":1,"ignored":[],"individualGoal":0,"isPrivate":true,
            "limits":{"individual":["day",100,"week",300],"team":[]},"mods":["m1"],"pointRules":[],"posesEnabled":false,
            "rankingsDisabled":false,"removed":[],"requiresApproval":true,"reviewRequired":true,"reviewSince":782000000,
            "teamGoal":0,"verification":{"backlogDays":0,"deviceRequired":false,"library":"verified_only","locationRequired":false,
            "media":"device_optional","preset":"verificado","time":"none"},"weekStart":2}"""
        val s = LeagueSettings.parse(raw)
        assertEquals(mapOf(LimitPeriod.DAY to 100, LimitPeriod.WEEK to 300), s.limits.individual)
        assertEquals(VerificationPreset.VERIFICADO, s.verification.preset)
        assertEquals(listOf("m1"), s.mods)
        assertTrue(s.isPrivate && s.requiresApproval && s.reviewRequired)
        assertEquals(at("2025-10-12T22:13:20Z"), s.reviewSince)
        assertEquals(2, s.calendar().firstWeekday)
        val back = Json.parseToJsonElement(s.rawValue).jsonObject
        assertEquals("1", back["futuro"]!!.jsonPrimitive.content)
        assertEquals(listOf("day", "100", "week", "300"), back["limits"]!!.jsonObject["individual"]!!.jsonArray.map { it.jsonPrimitive.content })
        assertEquals(s, LeagueSettings.parse(s.rawValue))
        // Sem nada ligado, o texto fica vazio (como o iOS)
        assertEquals("", LeagueSettings().rawValue)
        assertEquals(LeagueSettings(), LeagueSettings.parse("lixo"))
    }

    @Test
    fun proofRoundTrip() {
        val p = CheckInProof(PhotoProof(PhotoProof.LIBRARY, at("2026-10-21T10:42:00Z"), true), true, "Apple Watch", "paz", "Smart Fit",
                             listOf("A1"), listOf(ScorePart("corrida", 30, 5, 5000.0, null, 37)))
        assertEquals(p, CheckInProof.parse(p.rawValue))
        assertEquals("", CheckInProof().rawValue)
        assertEquals("Da galeria · tirada 21/10 07:42", CheckInProof.photoLabel(p.photo!!, java.time.ZoneId.of("America/Sao_Paulo")))
        assertEquals(listOf("Gravado no Apple Watch", "📍 Visita verificada na Smart Fit", "✌️ Pose do dia: Sinal de paz"), p.lines.drop(1))
        assertEquals("Apple Watch", CheckInProof.publicDevice("Apple Watch de Ana"))
        assertEquals(null, CheckInProof.publicDevice("Strava"))
    }

    @Test
    fun verificationProblems() {
        val now = at("2026-10-22T15:00:00Z")
        val s = PostSubject(50, at("2026-10-20T12:00:00Z"), 60)
        val v = CheckInVerification.VERIFICADO
        val p = v.problems(s, now)
        assertEquals(listOf("media", "backlog"), p.map { it.kind })
        assertEquals("Só vale treino de hoje.", p[1].message)
        assertTrue(CheckInVerification.OFF.problems(s, now).isEmpty())
        val withPhoto = s.copy(date = at("2026-10-22T12:00:00Z"), photo = PhotoProof(PhotoProof.LIBRARY, null))
        assertEquals(listOf("Foto da galeria sem hora verificada."), v.problems(withPhoto, now).map { it.message })
        val strict = CheckInVerification.PADRAO.copy(preset = VerificationPreset.PERSONALIZADO, time = CheckInTimePolicy.STRICT)
        val cam = withPhoto.copy(photo = PhotoProof(PhotoProof.CAMERA, at("2026-10-22T13:30:00Z")))
        assertTrue(strict.problems(cam, now).isEmpty())
        assertEquals("time", strict.problems(cam.copy(date = at("2026-10-22T09:00:00Z")), now).single().kind)
    }

    @Test
    fun poseIsTheSameForTheWholeDayInBrasilia() {
        val a = DailyPose.of(at("2026-10-22T03:00:00Z"))
        val b = DailyPose.of(at("2026-10-23T02:59:59Z"))
        assertEquals(a, b)
        assertTrue(a in DailyPose.all)
    }

    @Test
    fun textsAndTeams() {
        assertEquals("2,2 km", LeagueText.km(2250))
        assertEquals("12 km", LeagueText.km(12400))
        assertEquals("1 h 20 min", LeagueText.format(LeagueScoring.MINUTOS, 80))
        assertEquals("1 treino", LeagueText.format(LeagueScoring.TREINOS, 1))
        assertEquals("4,5", LeagueText.swissPoints(4.5))
        assertEquals("0,5×", LeagueText.weight(0.5))
        assertEquals("forca:2,tecnica:0.5", LeagueText.weightsRaw(mapOf(com.alonsoalmeida.gymbros.domain.Attribute.FORCA to 2.0,
            com.alonsoalmeida.gymbros.domain.Attribute.TECNICA to 0.5, com.alonsoalmeida.gymbros.domain.Attribute.AGILIDADE to 1.0)))
        val teams = LeagueTeams.parse("Verde\nRoxo")
        assertEquals(listOf(LeagueTeam("t0", "Verde"), LeagueTeam("t1", "Roxo")), teams)
        assertEquals("t0\tVerde\nt1\tRoxo", LeagueTeams.encode(teams))
        assertEquals(LocalDate.of(2026, 10, 18), cal.weekStart(LocalDate.of(2026, 10, 22)))
        assertEquals(LocalDate.of(2026, 10, 19), RulesCalendar(firstWeekday = 2).weekStart(LocalDate.of(2026, 10, 22)))
    }

    private fun league(scoring: String = "treinos", settings: String = "", tie: String = "primeiro") = League(LeagueJson(
        uuid = "L", name = "Liga", scoring = scoring, start = at("2026-10-01T03:00:00Z"), code = "ABCDEF",
        joinedAt = at("2026-10-01T03:00:00Z"), end = at("2026-11-01T02:59:59Z"), settings = settings, tieBreak = tie, joined = false))

    private fun act(id: String, date: String) = LeagueActivityJson(id, "musculacao", at(date), 60, 6)
    private fun mine(id: String, act: String, date: String, review: String? = null) =
        MyCheckIn(CheckInJson(id, "L", act, "Treino", date = at(date), review = review))

    @Test
    fun feedAndRanking() {
        val now = at("2026-10-10T15:00:00Z")
        val l = league("dias")
        val acts = listOf(act("A1", "2026-10-05T12:00:00Z"), act("A2", "2026-10-05T18:00:00Z"), act("A3", "2026-10-06T12:00:00Z")).associateBy { it.uuid }
        val my = listOf(mine("C1", "A1", "2026-10-05T12:00:00Z"), mine("C2", "A2", "2026-10-05T18:00:00Z"), mine("C3", "A3", "2026-10-06T12:00:00Z", "denied"))
        val remote = RemoteLeague(members = listOf(RemoteMember("u2", "Ana", "egg")),
                                  checkIns = listOf(RemoteCheckIn("R1", "u2", at("2026-10-04T12:00:00Z"), "corrida", 30, 5, title = "Corrida")))
        val feed = LeagueBoard.feed(l, my, acts, "Eu", MonsterForm.EGG, remote, emptyMap())
        assertEquals(listOf("C2", "C1", "R1"), feed.map { it.id })
        // Dias ativos: o segundo do mesmo dia vale 0
        assertEquals(listOf(0, 1, 1), feed.map { it.score })
        val swiss = LeagueBoard.swiss(l, feed, remote, "me-uid", now)
        val rank = LeagueBoard.ranking(feed, l, "Eu", MonsterForm.EGG, null, null, remote, swiss, "me-uid")
        assertEquals(2, rank.size)
        assertTrue(rank.all { it.swiss != null })
        // Revisão negada some do feed
        assertFalse(feed.any { it.id == "C3" })
        // Liga com revisão: o do outro espera e não pontua
        val reviewed = league("treinos", LeagueSettings(reviewRequired = true).rawValue)
        val f2 = LeagueBoard.feed(reviewed, emptyList(), acts, "Eu", MonsterForm.EGG, remote, emptyMap())
        assertTrue(f2.single().pending && f2.single().score == 0)
        val f3 = LeagueBoard.feed(reviewed, emptyList(), acts, "Eu", MonsterForm.EGG, remote, mapOf("R1" to true))
        assertEquals(1, f3.single().score)
    }

    @Test
    fun individualCapCutsOldestFirst() {
        val s = LeagueSettings(limits = ScoringLimits(individual = mapOf(LimitPeriod.DAY to 1)))
        val l = league("treinos", s.rawValue)
        val acts = listOf(act("A1", "2026-10-05T12:00:00Z"), act("A2", "2026-10-05T13:00:00Z")).associateBy { it.uuid }
        val feed = LeagueBoard.feed(l, listOf(mine("C1", "A1", "2026-10-05T12:00:00Z"), mine("C2", "A2", "2026-10-05T13:00:00Z")),
                                    acts, "Eu", MonsterForm.EGG, RemoteLeague(), emptyMap())
        assertEquals(mapOf("C1" to 1, "C2" to 0), feed.associate { it.id to it.score })
        assertEquals(1, feed.first { it.id == "C2" }.capped)
    }

    @Test
    fun moderationAppliesToRemote() {
        val s = LeagueSettings(removed = listOf("u2"), approved = listOf("u3"), ignored = listOf("u4"))
        val r = RemoteLeague(members = listOf(RemoteMember("u2", "B", "egg")),
                             requests = listOf(RemoteMember("u3", "C", "egg"), RemoteMember("u4", "D", "egg"), RemoteMember("u5", "E", "egg")))
            .applying(league(settings = s.rawValue))
        assertEquals(listOf("u3"), r.members.map { it.id })
        assertEquals(listOf("u5"), r.requests.map { it.id })
    }

    @Test
    fun renewalSkipsSeasonsMissed() {
        val l = league()
        val n = LeagueRenewal.next(l, at("2026-12-15T12:00:00Z"))
        assertEquals(31, l.durationDays)
        assertEquals(at("2026-12-02T03:00:00Z"), n.start)
        assertEquals(3, n.season)
        assertEquals(at("2027-01-02T02:59:59Z"), n.end)
    }

    @Test
    fun editsKeepUnknownFields() {
        val copy = Json.parseToJsonElement("""{"version":1,"checkIns":[{"uuid":"A","leagueUUID":"L","activityUUID":"X","title":"t","note":"",
            "date":"2026-10-05T12:00:00Z","novo":true}],"outro":[1]}""").jsonObject
        val up = LeagueEdits.update(copy, "checkIns", "a", mapOf("title" to "u", "syncedAt" to at("2026-10-05T13:00:00Z")))
        val c = (up["checkIns"] as JsonArray)[0].jsonObject
        assertEquals("u", c["title"]!!.jsonPrimitive.content)
        assertEquals("2026-10-05T13:00:00Z", c["syncedAt"]!!.jsonPrimitive.content)
        assertTrue(c.containsKey("novo") && up.containsKey("outro"))
        assertEquals(1, LeagueEdits.read(up).checkIns!!.size)
        val (withEgg, egg) = LeagueEdits.addEgg(AccountEdits.empty("Eu", at("2026-10-05T12:00:00Z")), at("2026-10-05T12:00:00Z"))
        assertTrue((withEgg["monsters"] as JsonArray).any { (it as JsonObject)["uuid"]!!.jsonPrimitive.content == egg })
        val pj = LeagueEdits.PendingJoin("ABCDEF", "Liga", "🔥", at("2026-10-05T12:00:00Z"), null)
        val s2 = LeagueEdits.setPendingJoins(withEgg, listOf(pj))
        val settings = com.alonsoalmeida.gymbros.domain.backup.AccountCopy.settings(java.util.Base64.getDecoder().decode(s2["accountSettings"]!!.jsonPrimitive.content))
        assertEquals(listOf(pj), LeagueEdits.pendingJoins(settings))
        val s3 = LeagueEdits.setRetractions(s2, mapOf("L" to listOf("C1")))
        val st3 = com.alonsoalmeida.gymbros.domain.backup.AccountCopy.settings(java.util.Base64.getDecoder().decode(s3["accountSettings"]!!.jsonPrimitive.content))
        assertEquals(mapOf("L" to listOf("C1")), LeagueEdits.retractions(st3))
    }
}
