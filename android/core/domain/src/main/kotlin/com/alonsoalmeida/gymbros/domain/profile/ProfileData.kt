package com.alonsoalmeida.gymbros.domain.profile

import com.alonsoalmeida.gymbros.domain.ActivityKind
import com.alonsoalmeida.gymbros.domain.ActivityRecord
import com.alonsoalmeida.gymbros.domain.AttributeSplit
import com.alonsoalmeida.gymbros.domain.BroCatalog
import com.alonsoalmeida.gymbros.domain.Roster
import com.alonsoalmeida.gymbros.domain.RuleClock
import com.alonsoalmeida.gymbros.domain.Snapshot
import com.alonsoalmeida.gymbros.domain.SnapshotRules
import com.alonsoalmeida.gymbros.domain.Species
import com.alonsoalmeida.gymbros.domain.Stage
import com.alonsoalmeida.gymbros.domain.WorkoutType
import com.alonsoalmeida.gymbros.domain.activities.ActivityEdits
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.longOrNull
import java.time.Instant

/** Uma atividade como as telas de perfil, histórico e detalhe mostram */
data class ProfileActivity(
    val id: String,
    val type: Long,
    val typeName: String,
    /** SF Symbol do tipo; o app troca pelo ícone Material */
    val typeSymbol: String,
    val kind: ActivityKind,
    val date: Instant,
    val minutes: Int,
    val effort: Int,
    val note: String,
    val fromHealth: Boolean,
    /** App ou relógio que gravou ("Gravado no …") */
    val source: String?,
    val gymUUID: String?,
    val meters: Double?,
    val kcal: Double?,
    val owner: String?,
    /** Ligas (e o perfil) onde foi postada */
    val postedIn: List<String>,
    val postTitle: String?,
    val postNote: String?,
    val place: String?,
    /** Treino guiado ou WOD ligado */
    val hasWorkout: Boolean,
    val xp: Int,
)

data class PublicNumbers(val checkIns: Int, val activeDays: Int, val leagues: Int)

data class AchievementItem(val id: String, val title: String, val detail: String, val symbol: String, val current: Double, val goal: Double) {
    val unlocked: Boolean get() = current >= goal
}

/** Registro de peso e medidas (Models/Body.swift `BodyEntry`) */
data class BodyEntryData(
    val id: String,
    val date: Instant,
    val weight: Double?,
    val waist: Double?,
    val chest: Double?,
    val arm: Double?,
    val thigh: Double?,
    val hip: Double?,
    val healthUUID: String?,
) {
    val hasMeasures: Boolean get() = listOf(waist, chest, arm, thigh, hip).any { it != null }
}

enum class Measure(val raw: String, val label: String) {
    WAIST("waist", "Cintura"), CHEST("chest", "Peito"), ARM("arm", "Braço"), THIGH("thigh", "Coxa"), HIP("hip", "Quadril");

    fun value(e: BodyEntryData): Double? = when (this) {
        WAIST -> e.waist
        CHEST -> e.chest
        ARM -> e.arm
        THIGH -> e.thigh
        HIP -> e.hip
    }
}

/** O que o perfil mostra. Fontes: Profile/ProfileView.swift, Friends/PublicProfile.swift, Bros/Companion.swift (conquistas) */
data class ProfileData(
    val name: String,
    val username: String,
    val bio: String,
    val showPhoto: Boolean,
    val showMonster: Boolean,
    val showStats: Boolean,
    val showAchievements: Boolean,
    val activities: List<ProfileActivity>,
    val publicNumbers: PublicNumbers,
    val achievements: List<AchievementItem>,
    /** Snapshot do jogador com todas as atividades (`Game.cachedSnapshot`) */
    val player: Snapshot,
    val body: List<BodyEntryData>,
    val settings: Map<String, Any?>,
) {
    /** Dias com alguma atividade, no fuso do aparelho */
    fun activeDays(zone: java.time.ZoneId): Int = activities.map { it.date.atZone(zone).toLocalDate() }.toSet().size
    val totalMinutes: Int get() = activities.sumOf { it.minutes }
}

object ProfileBuilder {
    private fun JsonObject.str(k: String): String? = (this[k] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.content
    private fun list(copy: JsonObject?, key: String): List<JsonObject> = (copy?.get(key) as? JsonArray)?.mapNotNull { it as? JsonObject }.orEmpty()

    fun build(copy: JsonObject?, roster: Roster, clock: RuleClock): ProfileData {
        val settings = ProfileEdits.settings(copy)
        val checkIns = list(copy, "checkIns")
        val postsBy = checkIns.groupBy { it.str("activityUUID")?.uppercase() }
        val sessions = list(copy, "sessions")
        val wods = list(copy, "wods")
        val withWorkout = (sessions + wods).mapNotNull { it.str("activityUUID")?.uppercase() }.toSet()
        val gyms = list(copy, "gyms").associate { it.str("uuid")?.uppercase() to it.str("name") }
        @Suppress("UNCHECKED_CAST")
        val splits = (settings[ActivityEdits.SPLITS_KEY] as? Map<String, Any?>).orEmpty()
        val xp = roster.xpByActivity

        val activities = list(copy, "activities").mapNotNull { a ->
            val id = a.str("uuid")?.uppercase() ?: return@mapNotNull null
            val date = runCatching { Instant.parse(a.str("date")) }.getOrNull() ?: return@mapNotNull null
            val kind = ActivityKind.of(a.str("kind") ?: "outro")
            val type = (a["healthType"] as? JsonPrimitive)?.longOrNull ?: BroCatalog.classicType[kind.raw] ?: 3000L
            val wt = WorkoutType.byID(type)
            val posts = postsBy[id].orEmpty()
            ProfileActivity(
                id = id, type = type, typeName = wt?.name ?: kind.raw, typeSymbol = BroCatalog.workoutSymbols[type] ?: "figure.mixed.cardio",
                kind = kind, date = date, minutes = (a["minutes"] as? JsonPrimitive)?.intOrNull ?: 0,
                effort = (a["effort"] as? JsonPrimitive)?.intOrNull ?: 5, note = a.str("note").orEmpty(),
                fromHealth = a.str("healthUUID") != null, source = a.str("source"), gymUUID = a.str("gymUUID")?.uppercase(),
                meters = (a["meters"] as? JsonPrimitive)?.doubleOrNull, kcal = (a["kcal"] as? JsonPrimitive)?.doubleOrNull,
                owner = a.str("monsterUUID")?.uppercase(),
                postedIn = posts.mapNotNull { it.str("leagueUUID")?.uppercase() },
                postTitle = posts.firstOrNull()?.str("title"), postNote = posts.firstOrNull()?.str("note"),
                place = posts.firstNotNullOfOrNull { it.str("place") } ?: a.str("gymUUID")?.uppercase()?.let { gyms[it] },
                hasWorkout = id in withWorkout, xp = xp[id] ?: 0,
            )
        }.sortedByDescending { it.date }

        // Game.cachedSnapshot(activities.map(\.record)): o jogador, com todas as atividades
        val records = list(copy, "activities").mapNotNull { a ->
            val id = a.str("uuid")?.uppercase() ?: return@mapNotNull null
            val date = runCatching { Instant.parse(a.str("date")) }.getOrNull() ?: return@mapNotNull null
            val weights = (a.str("attributes") ?: splits[id] as? String)?.let(AttributeSplit::decode)
            ActivityRecord(id, ActivityKind.of(a.str("kind") ?: "outro"), date, (a["minutes"] as? JsonPrimitive)?.intOrNull ?: 0,
                           (a["effort"] as? JsonPrimitive)?.intOrNull ?: 5, weights, healthType = (a["healthType"] as? JsonPrimitive)?.longOrNull)
        }
        val player = SnapshotRules.snapshot(records, clock)

        val leagues = list(copy, "leagues")
        val numbers = publicNumbers(activities.map { it.id to it.date }, checkIns.mapNotNull { it.str("activityUUID")?.uppercase() },
                                    leagues.count { it.str("nextUUID") == null }, clock)

        val finished = sessions.count { it.str("end") != null }
        val discovered = (ProfileEdits.text(copy, "discovered") ?: "").split(",").count { it.isNotEmpty() }
        val achievements = achievements(records, activities.count { it.fromHealth }, player, finished,
                                        species = roster.snapshots.values.filter { it.stage > Stage.EGG }.map { it.form.species }.toSet().size,
                                        ultimates = roster.snapshots.values.count { it.stage == Stage.ULTIMATE }, discovered = discovered, clock = clock)

        val body = list(copy, "body").mapNotNull { b ->
            BodyEntryData(
                id = b.str("uuid")?.uppercase() ?: return@mapNotNull null,
                date = runCatching { Instant.parse(b.str("date")) }.getOrNull() ?: return@mapNotNull null,
                weight = (b["weight"] as? JsonPrimitive)?.doubleOrNull, waist = (b["waist"] as? JsonPrimitive)?.doubleOrNull,
                chest = (b["chest"] as? JsonPrimitive)?.doubleOrNull, arm = (b["arm"] as? JsonPrimitive)?.doubleOrNull,
                thigh = (b["thigh"] as? JsonPrimitive)?.doubleOrNull, hip = (b["hip"] as? JsonPrimitive)?.doubleOrNull,
                healthUUID = b.str("healthUUID"),
            )
        }.sortedByDescending { it.date }

        return ProfileData(
            name = ProfileEdits.text(copy, "trainerName").orEmpty(), username = ProfileEdits.text(copy, "profileUsername").orEmpty(),
            bio = ProfileEdits.text(copy, "profileBio").orEmpty(),
            showPhoto = ProfileEdits.bool(settings, "publicPhoto", true), showMonster = ProfileEdits.bool(settings, "publicMonster", true),
            showStats = ProfileEdits.bool(settings, "publicStats", true), showAchievements = ProfileEdits.bool(settings, "publicAchievements", true),
            activities = activities, publicNumbers = numbers, achievements = achievements, player = player, body = body, settings = settings,
        )
    }

    /**
     * Números públicos (PublicProfile.stats): só o que foi postado (perfil ou ligas) conta; ligas = as que você está
     * agora (sem temporadas passadas).
     */
    fun publicNumbers(activities: List<Pair<String, Instant>>, postedActivityIDs: List<String>, currentLeagues: Int, clock: RuleClock): PublicNumbers {
        val existing = activities.map { it.first }.toSet()
        val posted = postedActivityIDs.toSet() intersect existing
        val days = activities.filter { it.first in posted }.map { clock.day(it.second) }.toSet()
        return PublicNumbers(posted.size, days.size, currentLeagues)
    }

    /**
     * Conquistas (Achievements.evaluate). Recordes, toneladas e "Corpo inteiro" dependem das séries do treino guiado e
     * do catálogo de exercícios, que ainda não chegaram ao Android: ficam de fora daqui.
     */
    fun achievements(acts: List<ActivityRecord>, fromHealth: Int, s: Snapshot, sessions: Int, species: Int, ultimates: Int,
                     discovered: Int, clock: RuleClock): List<AchievementItem> {
        val n = acts.size.toDouble()
        val kinds = acts.map { it.kind }.toSet().size.toDouble()
        val longest = (acts.maxOfOrNull { it.minutes } ?: 0).toDouble()
        val hours = acts.map { it.date.atZone(clock.zone).hour }
        val stage = s.stage.ordinal.toDouble()
        val best = s.bestStreak.toDouble()
        fun a(id: String, t: String, d: String, sym: String, cur: Double, goal: Double) = AchievementItem(id, t, d, sym, cur, goal)
        return listOf(
            a("primeiro", "Primeiro passo", "Registre sua primeira atividade", "figure.walk", n, 1.0),
            a("chocou", "Chocou!", "Choque o ovo", "sparkles", stage, 1.0),
            a("rookie", "Crescendo", "Chegue ao estágio Novato", "arrow.up.circle", stage, 2.0),
            a("champion", "Campeão", "Chegue ao estágio Atleta", "trophy", stage, 3.0),
            a("ultimate", "Forma final", "Chegue ao estágio Lenda", "crown", stage, 4.0),
            a("treinos10", "Pegando o ritmo", "10 atividades", "10.circle", n, 10.0),
            a("treinos50", "Rotina de atleta", "50 atividades", "50.circle", n, 50.0),
            a("treinos100", "Centenário", "100 atividades", "100.circle", n, 100.0),
            a("seq3", "Embalado", "3 dias seguidos", "flame", best, 3.0),
            a("seq7", "Semana cheia", "7 dias seguidos", "flame.fill", best, 7.0),
            a("seq30", "Imparável", "30 dias seguidos", "bolt.heart", best, 30.0),
            a("variado", "Eclético", "5 tipos de atividade diferentes", "square.grid.2x2", kinds, 5.0),
            a("maratona", "Maratonista", "Uma atividade de 2 horas", "timer", longest, 120.0),
            a("madrugador", "Madrugador", "Treine antes das 7h", "sunrise", if (hours.any { it < 7 }) 1.0 else 0.0, 1.0),
            a("coruja", "Coruja", "Treine depois das 21h", "moon.stars", if (hours.any { it >= 21 }) 1.0 else 0.0, 1.0),
            a("guiado10", "Disciplina", "10 treinos guiados", "list.clipboard", sessions.toDouble(), 10.0),
            a("especies2", "Nova espécie", "Choque um bro de outra espécie", "pawprint", species.toDouble(), 2.0),
            a("especies4", "Colecionador", "Bros de 4 espécies diferentes", "pawprint.fill", species.toDouble(), 4.0),
            a("especies8", "Zoológico completo", "Bros das 8 espécies", "tortoise.fill", species.toDouble(), maxOf(Species.catalog.size, 2).toDouble()),
            a("ultimate2", "Treinador de elite", "2 bros no estágio Lenda", "crown.fill", ultimates.toDouble(), 2.0),
            a("dex25", "Pesquisador", "Descubra 25 formas no BroBook", "book", discovered.toDouble(), 25.0),
            a("saude", "Conectado", "Importe um treino do Apple Saúde", "heart.text.square", fromHealth.toDouble(), 1.0),
        )
    }
}
