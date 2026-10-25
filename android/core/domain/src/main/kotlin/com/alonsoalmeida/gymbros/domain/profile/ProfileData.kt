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
import com.alonsoalmeida.gymbros.domain.bros.Dex
import com.alonsoalmeida.gymbros.domain.train.ExerciseType
import com.alonsoalmeida.gymbros.domain.train.Exercises
import com.alonsoalmeida.gymbros.domain.train.Muscle
import com.alonsoalmeida.gymbros.domain.train.Progression
import com.alonsoalmeida.gymbros.domain.train.SessionLog
import com.alonsoalmeida.gymbros.domain.train.muscleLoad
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
    val progress: Double get() = minOf(current / goal, 1.0)
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
    /** "Bros e atributos" (`publicBros`, padrão sim) */
    val showBros: Boolean,
    val activities: List<ProfileActivity>,
    val publicNumbers: PublicNumbers,
    val achievements: List<AchievementItem>,
    /** Bros e atributos como saem no perfil público (mesmo com o interruptor desligado: o próprio perfil mostra) */
    val publicBros: PublicBros,
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

    /**
     * `logs` são os treinos guiados concluídos (do mais antigo ao mais novo) e `dexTotal` o total de formas do BroBook:
     * com eles entram as conquistas de recordes, toneladas, "Corpo inteiro" e "BroBook completo", como no iPhone.
     */
    fun build(copy: JsonObject?, roster: Roster, clock: RuleClock, logs: List<SessionLog>? = null, dexTotal: Int? = null): ProfileData {
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

        val posted = checkIns.mapNotNull { it.str("activityUUID")?.uppercase() }.toSet()
        val postedKinds = activities.filter { it.id in posted }.map { it.kind }
        val dex = Dex.allForms()
        val seen = Dex.discovered(ProfileEdits.text(copy, "discovered"), roster)
        val bros = PublicBrosRules.build(roster, player, postedKinds, dex.count { it.id in seen }, dex.size)

        val finished = sessions.count { it.str("end") != null }
        val discovered = (ProfileEdits.text(copy, "discovered") ?: "").split(",").count { it.isNotEmpty() }
        val achievements = achievements(records, activities.count { it.fromHealth }, player, finished,
                                        species = roster.snapshots.values.filter { it.stage > Stage.EGG }.map { it.form.species }.toSet().size,
                                        ultimates = roster.snapshots.values.count { it.stage == Stage.ULTIMATE }, discovered = discovered, clock = clock,
                                        logs = logs, dexTotal = dexTotal)

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
            showBros = ProfileEdits.bool(settings, "publicBros", true),
            activities = activities, publicNumbers = numbers, achievements = achievements, publicBros = bros, player = player, body = body, settings = settings,
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
     * Conquistas (Achievements.evaluate). Recordes, toneladas e "Corpo inteiro" dependem das séries do treino guiado
     * (`logs`, do mais antigo ao mais novo, com o catálogo de exercícios e o PR Book já instalados) e "BroBook completo"
     * do total de formas (`dexTotal`): sem eles, essas conquistas ficam de fora.
     */
    fun achievements(acts: List<ActivityRecord>, fromHealth: Int, s: Snapshot, sessions: Int, species: Int, ultimates: Int,
                     discovered: Int, clock: RuleClock, logs: List<SessionLog>? = null, dexTotal: Int? = null): List<AchievementItem> {
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
            a("guiado10", "Disciplina", "10 treinos guiados", "list.clipboard", (logs?.size ?: sessions).toDouble(), 10.0),
        ) + guided(logs) + listOf(
            a("especies2", "Nova espécie", "Choque um bro de outra espécie", "pawprint", species.toDouble(), 2.0),
            a("especies4", "Colecionador", "Bros de 4 espécies diferentes", "pawprint.fill", species.toDouble(), 4.0),
            a("especies8", "Zoológico completo", "Bros das 8 espécies", "tortoise.fill", species.toDouble(), maxOf(Species.catalog.size, 2).toDouble()),
            a("ultimate2", "Treinador de elite", "2 bros no estágio Lenda", "crown.fill", ultimates.toDouble(), 2.0),
            a("dex25", "Pesquisador", "Descubra 25 formas no BroBook", "book", discovered.toDouble(), 25.0),
        ) + listOfNotNull(
            dexTotal?.let { a("dexall", "BroBook completo", "Descubra todas as formas", "book.fill", discovered.toDouble(), it.toDouble()) },
        ) + listOf(
            a("saude", "Conectado", "Importe um treino do Apple Saúde", "heart.text.square", fromHealth.toDouble(), 1.0),
        )
    }

    /** As conquistas que saem das séries do treino guiado (recordes, toneladas e "Corpo inteiro") */
    private fun guided(logs: List<SessionLog>?): List<AchievementItem> {
        if (logs == null) return emptyList()
        val done = logs.flatMap { it.sets }.filter { it.done }
        val tons = done.filter { Exercises.byID(it.exerciseID)?.type != ExerciseType.DISTANCE }.sumOf { it.weight * it.reps } / 1000
        var prs = 0
        for (k in 1 until logs.size) prs += Progression.records(logs[k], logs.subList(0, k)).size
        // Semana completa: todos os músculos do mapa trabalhados em alguma janela de 7 dias
        val fullWeek = logs.any { s ->
            val from = s.date.minusSeconds(7 * 86_400L)
            val hit = muscleLoad(logs.filter { it.date <= s.date && it.date > from }.flatMap { it.sets }).keys
            Muscle.tracked.all { it in hit }
        }
        fun a(id: String, t: String, d: String, sym: String, cur: Double, goal: Double) = AchievementItem(id, t, d, sym, cur, goal)
        return listOf(
            a("pr1", "Recordista", "Bata seu primeiro recorde", "medal", prs.toDouble(), 1.0),
            a("pr25", "Máquina de PRs", "25 recordes", "medal.fill", prs.toDouble(), 25.0),
            a("ton10", "Dez toneladas", "10 t levantadas no total", "scalemass", tons, 10.0),
            a("ton100", "Cem toneladas", "100 t levantadas no total", "scalemass.fill", tons, 100.0),
            a("corpo", "Corpo inteiro", "Treine todos os músculos do mapa em 7 dias", "figure.stand", if (fullWeek) 1.0 else 0.0, 1.0),
        )
    }
}
