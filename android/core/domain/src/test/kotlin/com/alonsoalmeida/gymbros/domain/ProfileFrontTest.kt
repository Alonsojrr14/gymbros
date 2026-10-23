package com.alonsoalmeida.gymbros.domain

import com.alonsoalmeida.gymbros.domain.activities.ActivityEdits
import com.alonsoalmeida.gymbros.domain.activities.HealthImport
import com.alonsoalmeida.gymbros.domain.backup.AccountCopy
import com.alonsoalmeida.gymbros.domain.backup.AccountEdits
import com.alonsoalmeida.gymbros.domain.home.HomeBuilder
import com.alonsoalmeida.gymbros.domain.profile.BlockedTerms
import com.alonsoalmeida.gymbros.domain.profile.BodyEdits
import com.alonsoalmeida.gymbros.domain.profile.ContentFilter
import com.alonsoalmeida.gymbros.domain.profile.Measure
import com.alonsoalmeida.gymbros.domain.profile.ProfileBuilder
import com.alonsoalmeida.gymbros.domain.profile.ProfileEdits
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.time.Instant
import java.time.ZoneId

/** Frente do perfil: filtro de palavras, ajustes da conta, apagar/editar atividade, Health Connect e peso */
class ProfileFrontTest {
    private val clock = RuleClock(ZoneId.of("America/Sao_Paulo"), Instant.parse("2027-01-16T12:00:00Z"))
    private val c = Json.parseToJsonElement(javaClass.getResource("/gymbros-golden-C.json")!!.readText()).jsonObject
    private val iphone = Json.parseToJsonElement(c["backupJSON"]!!.jsonPrimitive.content) as JsonObject

    // MARK: ContentFilter (os mesmos casos de ContentFilterTests.swift)

    @Test
    fun blocksOffensiveTerms() {
        for (t in listOf("Que treino de merda", "vai se matar", "you piece of shit", "kill yourself", "FDP", "seu otário")) assertFalse(ContentFilter.allows(t), t)
    }

    @Test
    fun normalizesAccentsCaseAndSwaps() {
        for (t in listOf("CUZÃO", "P0RR4", "c@ralho", "\$h1t", "merda!", "Merdaaa", "porrraaa", "p u t a", "putaria123", "Fucking hell")) {
            assertFalse(ContentFilter.allows(t), t)
        }
    }

    @Test
    fun respectsWordBoundaries() {
        for (t in listOf("computador", "Scunthorpe", "class", "assessoria", "cuidado", "escuta", "putativo", "Fagundes", "as pernas",
                         "Bora treinar!", "3x10 supino", "Dia de perna 🦵", "e o a", "Cucumber", "Shiitake", "")) assertTrue(ContentFilter.allows(t), t)
    }

    @Test
    fun prefixTermsAndCustomList() {
        assertEquals("caralho*", ContentFilter.match("caralhooo", listOf("caralho*")))
        assertNull(ContentFilter.match("caralh", listOf("caralho*")))
        assertEquals("frango", ContentFilter.match("abc frango xyz", listOf("frango")))
        assertNull(ContentFilter.match("frangos", listOf("frango")))
        assertEquals("dia de perna", ContentFilter.match("nossa, dia de perna", listOf("dia de perna")))
        for (term in BlockedTerms.all) assertFalse(ContentFilter.allows(term.removeSuffix("*")), term)
        assertEquals("Zero", ContentFilter.publishable("Zero"))
        assertEquals("", ContentFilter.publishable("Rei da porra"))
    }

    // MARK: Ajustes da conta

    @Test
    fun settingsGoToPlistSettingsAndTypedSettings() {
        val out = ProfileEdits.setAll(iphone, mapOf("trainerName" to "Zé", "publicStats" to false, "reminderMinute" to 1140))
        val plist = ProfileEdits.settings(out)
        assertEquals("Zé", plist["trainerName"])
        assertEquals(false, plist["publicStats"])
        assertEquals(1140L, plist["reminderMinute"])
        assertEquals("Zé", (out["settings"] as JsonObject)["trainerName"]!!.jsonPrimitive.content)
        assertEquals("Zé", (out["typedSettings"] as JsonObject)["trainerName"]!!.jsonObject["text"]!!.jsonObject["_0"]!!.jsonPrimitive.content)
        assertEquals("Zé", HomeBuilder.build(AccountCopy.decode(out), clock).trainerName)
        // Nada mais muda
        for ((k, v) in iphone) if (k !in setOf("settings", "typedSettings", "accountSettings")) assertEquals(v, out[k], k)
    }

    // MARK: Apagar e editar atividade

    private fun copyWithPostedRun(): Pair<JsonObject, String> {
        val id = "AAAAAAAA-0000-0000-0000-000000000001"
        var copy = AccountEdits.addActivity(iphone, AccountEdits.NewActivity("corrida", Instant.parse("2027-01-15T10:00:00Z"), 40, 6, "", 37,
            AttributeSplit.encode(AttributeSplit.split(ActivityKind.CORRIDA, 40, 6, healthType = 37)), id = id))
        val post = buildJsonObject {
            put("uuid", "BBBBBBBB-0000-0000-0000-000000000001"); put("leagueUUID", ActivityEdits.PROFILE_FEED); put("activityUUID", id)
            put("title", "Corrida"); put("date", "2027-01-15T11:00:00Z"); put("syncedAt", "2027-01-15T11:00:01Z")
        }
        val comment = buildJsonObject { put("uuid", "CCCCCCCC-0000-0000-0000-000000000001"); put("itemID", "BBBBBBBB-0000-0000-0000-000000000001"); put("text", "boa"); put("date", "2027-01-15T12:00:00Z") }
        copy = JsonObject(copy + ("checkIns" to JsonArray((copy["checkIns"] as? JsonArray).orEmpty() + post)) +
                          ("comments" to JsonArray((copy["comments"] as? JsonArray).orEmpty() + comment)))
        return copy to id
    }

    @Test
    fun deletingKeepsXPWithTheBrosAndQueuesTheRetraction() {
        val (copy, id) = copyWithPostedRun()
        val before = HomeBuilder.build(AccountCopy.decode(copy), clock)
        val out = ActivityEdits.delete(copy, id, before.roster)
        assertNull(ActivityEdits.activity(out, id))
        assertTrue(ActivityEdits.posts(out, id).isEmpty())
        assertTrue((out["comments"] as JsonArray).none { it.jsonObject["itemID"]!!.jsonPrimitive.content.startsWith("BBBBBBBB") })
        // O bro não volta de forma: o XP continua com quem recebeu
        val after = HomeBuilder.build(AccountCopy.decode(out), clock)
        assertEquals(before.snapshot.totalXP, after.snapshot.totalXP)
        assertEquals(before.snapshot.form, after.snapshot.form)
        val retired = BroLedger.retired((ProfileEdits.settings(out)[BroLedger.RETIRED_KEY] as ByteArray).decodeToString())
        assertEquals(listOf(id), retired.map { it.id })
        @Suppress("UNCHECKED_CAST")
        val queue = ProfileEdits.settings(out)[ActivityEdits.RETRACTIONS_KEY] as Map<String, List<String>>
        assertEquals(listOf("BBBBBBBB-0000-0000-0000-000000000001"), queue[ActivityEdits.PROFILE_FEED])
        // Já tirado do servidor aqui: não entra na fila
        val direct = ActivityEdits.delete(copy, id, before.roster, retracted = setOf("BBBBBBBB-0000-0000-0000-000000000001"))
        assertNull(ProfileEdits.settings(direct)[ActivityEdits.RETRACTIONS_KEY])
    }

    @Test
    fun deletingAnImportedWorkoutIgnoresItNextTime() {
        val w = HealthImport.Workout("hc-1", 56, Instant.parse("2027-01-14T10:00:00Z"), Instant.parse("2027-01-14T10:30:00Z"), "Fit")
        val item = HealthImport.plan(listOf(w), emptyList(), emptySet(), 70.0, null).imported.single()
        val copy = JsonObject(iphone + ("activities" to JsonArray((iphone["activities"] as JsonArray) + item)))
        val id = item["uuid"]!!.jsonPrimitive.content
        val out = ActivityEdits.delete(copy, id, HomeBuilder.build(AccountCopy.decode(copy), clock).roster)
        val ignored = ProfileEdits.strings(ProfileEdits.settings(out), ActivityEdits.IGNORED_KEY).toSet()
        assertEquals(setOf("hc-1"), ignored)
        assertTrue(HealthImport.plan(listOf(w), emptyList(), ignored, 70.0, null).imported.isEmpty())
    }

    @Test
    fun editingChangesTheActivityAndRedoesTheSplit() {
        val (copy, id) = copyWithPostedRun()
        val out = ActivityEdits.edit(copy, id, ActivityEdits.Change(50, ActivityKind.MUSCULACAO, Instant.parse("2027-01-15T09:00:00Z"), 60, 8, "Peito", null))
        val a = ActivityEdits.activity(out, id)!!
        assertEquals("musculacao", a["kind"]!!.jsonPrimitive.content)
        assertEquals(50L, a["healthType"]!!.jsonPrimitive.content.toLong())
        assertEquals("2027-01-15T09:00:00Z", a["date"]!!.jsonPrimitive.content)
        assertEquals(AttributeSplit.encode(AttributeSplit.split(ActivityKind.MUSCULACAO, 60, 8, healthType = 50)), a["attributes"]!!.jsonPrimitive.content)
    }

    // MARK: Health Connect

    @Test
    fun healthConnectTypesMapToTheCatalog() {
        for ((hc, hk) in HealthImport.typeMap) assertTrue(WorkoutType.byID(hk) != null, "HC $hc → $hk")
        assertEquals(37L, HealthImport.workoutType(56))
        assertEquals(50L, HealthImport.workoutType(70))
        assertEquals(3000L, HealthImport.workoutType(999))
        assertEquals(ActivityKind.CORRIDA, HealthImport.kind(37))
        assertEquals(ActivityKind.CAMINHADA, HealthImport.kind(24))
        assertEquals(ActivityKind.OUTRO, HealthImport.kind(16))
    }

    @Test
    fun importSkipsShortOwnKnownAndOverlapping() {
        val t0 = Instant.parse("2027-01-10T10:00:00Z")
        val workouts = listOf(
            HealthImport.Workout("a", 56, t0, t0.plusSeconds(1800), "Fit", kcal = 300.0, meters = 5000.0),
            HealthImport.Workout("short", 56, t0.plusSeconds(7200), t0.plusSeconds(7200 + 240), "Fit"),
            HealthImport.Workout("own", 70, t0.plusSeconds(9000), t0.plusSeconds(12600), "GymBros", ownApp = true),
            HealthImport.Workout("known", 79, t0.plusSeconds(20000), t0.plusSeconds(22000), "Fit"),
            // Metade+ em cima de "a": o mesmo treino
            HealthImport.Workout("dup", 56, t0.plusSeconds(300), t0.plusSeconds(1700), "Outro relógio"),
            // Em cima de uma atividade registrada à mão
            HealthImport.Workout("manual", 70, Instant.parse("2027-01-11T10:05:00Z"), Instant.parse("2027-01-11T10:55:00Z"), "Fit"),
        )
        val existing = listOf(HealthImport.Existing(Instant.parse("2027-01-11T10:00:00Z"), 60, null, null),
                              HealthImport.Existing(t0.plusSeconds(30000), 10, "known", null))
        val r = HealthImport.plan(workouts, existing, emptySet(), 70.0, "MAIN")
        assertEquals(listOf("a"), r.imported.map { it["healthUUID"]!!.jsonPrimitive.content })
        assertEquals(2, r.skippedOverlap)
        val a = r.imported.single()
        assertEquals(30, a["minutes"]!!.jsonPrimitive.content.toInt())
        assertEquals("300 kcal", a["note"]!!.jsonPrimitive.content)
        assertEquals("Fit", a["source"]!!.jsonPrimitive.content)
        assertEquals("MAIN", a["monsterUUID"]!!.jsonPrimitive.content)
        // O iPhone lê a atividade importada
        val copy = JsonObject(iphone + ("activities" to JsonArray((iphone["activities"] as JsonArray) + a)))
        assertTrue(AccountCopy.decode(copy).activities.any { it.healthUUID == "a" })
    }

    @Test
    fun effortFollowsCalories() {
        assertEquals(5, HealthImport.effort(ActivityKind.CORRIDA, 30, null, 70.0))
        // Esperado: 9,5 × 3,5 × 70 / 200 × 30 = 349,1; sem o basal (36,75): 312,4 → 300 kcal = 0,96 → 5
        assertEquals(5, HealthImport.effort(ActivityKind.CORRIDA, 30, 300.0, 70.0))
        assertEquals(10, HealthImport.effort(ActivityKind.CORRIDA, 30, 2000.0, 70.0))
        assertEquals(1, HealthImport.effort(ActivityKind.CORRIDA, 30, 10.0, 70.0))
    }

    // MARK: Perfil e peso

    @Test
    fun publicNumbersCountOnlyPostedActivities() {
        val acts = listOf("A" to Instant.parse("2027-01-10T12:00:00Z"), "B" to Instant.parse("2027-01-10T20:00:00Z"),
                          "C" to Instant.parse("2027-01-11T12:00:00Z"))
        val n = ProfileBuilder.publicNumbers(acts, listOf("A", "B", "B", "GONE"), 2, clock)
        assertEquals(2, n.checkIns)
        assertEquals(1, n.activeDays)
        assertEquals(2, n.leagues)
    }

    @Test
    fun bodyEntriesSaveEditAndDelete() {
        val (one, id) = BodyEdits.save(iphone, null, BodyEdits.Values(Instant.parse("2027-01-10T08:00:00Z"), 80.5, mapOf(Measure.WAIST to 90.0)))
        val (two, _) = BodyEdits.save(one, id, BodyEdits.Values(Instant.parse("2027-01-10T08:00:00Z"), 79.0, mapOf(Measure.WAIST to null)))
        val p = ProfileBuilder.build(two, HomeBuilder.build(AccountCopy.decode(two), clock).roster, clock)
        val e = p.body.first { it.id == id }
        assertEquals(79.0, e.weight)
        assertNull(e.waist)
        assertEquals(79.0, ProfileEdits.settings(two)["profileLastWeight"])
        assertTrue(BodyEdits.delete(two, id)["body"]!!.let { it as JsonArray }.none { it.jsonObject["uuid"]!!.jsonPrimitive.content == id })
        assertEquals("80", BodyEdits.fmt(80.0))
        assertEquals("80,5", BodyEdits.fmt(80.5))
        assertEquals("72,25", BodyEdits.fmt(72.25))
    }

    @Test
    fun achievementsFromActivities() {
        val p = ProfileBuilder.build(iphone, HomeBuilder.build(AccountCopy.decode(iphone), clock).roster, clock)
        val first = p.achievements.first { it.id == "primeiro" }
        assertEquals(p.activities.isNotEmpty(), first.unlocked)
        assertTrue(p.achievements.none { it.id == "pr1" })
        assertEquals(JsonPrimitive("x"), JsonPrimitive("x"))
    }
}
