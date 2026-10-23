package com.alonsoalmeida.gymbros.domain.activities

import com.alonsoalmeida.gymbros.domain.ActivityKind
import com.alonsoalmeida.gymbros.domain.AttributeSplit
import com.alonsoalmeida.gymbros.domain.roundToIntSwift
import java.time.Duration
import java.time.Instant
import java.util.UUID

/**
 * Treinos do Health Connect viram atividades, com as regras do Apple Saúde no iOS (Services/HealthSync.swift `sync`):
 * só treinos de 5 min ou mais, de outros apps; os já conhecidos (`healthUUID`, ignorados) não voltam; quem se sobrepõe
 * em mais da metade a algo já registrado é o mesmo treino e fica de fora.
 */
object HealthImport {
    const val FIRST_IMPORT_DAYS = 14L
    const val MIN_SECONDS = 5 * 60L
    /** `LeagueScoring.referenceWeight` */
    const val REFERENCE_WEIGHT = 70.0

    /**
     * Tipo do Health Connect (`ExerciseSessionRecord.EXERCISE_TYPE_*`) → tipo do catálogo (`HKWorkoutActivityType.rawValue`).
     * Sem equivalente: "Outro" (3000).
     */
    val typeMap: Map<Int, Long> = mapOf(
        0 to 3000L, // OTHER_WORKOUT
        2 to 4L, // BADMINTON
        4 to 5L, // BASEBALL
        5 to 6L, // BASKETBALL
        8 to 13L, // BIKING
        9 to 13L, // BIKING_STATIONARY
        10 to 20L, // BOOT_CAMP → treino funcional
        11 to 8L, // BOXING
        13 to 20L, // CALISTHENICS → treino funcional
        14 to 10L, // CRICKET
        16 to 77L, // DANCING
        25 to 16L, // ELLIPTICAL
        26 to 73L, // EXERCISE_CLASS → cardio misto
        27 to 18L, // FENCING
        28 to 1L, // FOOTBALL_AMERICAN
        29 to 3L, // FOOTBALL_AUSTRALIAN
        31 to 75L, // FRISBEE_DISC
        32 to 21L, // GOLF
        33 to 29L, // GUIDED_BREATHING → corpo e mente
        34 to 22L, // GYMNASTICS
        35 to 23L, // HANDBALL
        36 to 63L, // HIGH_INTENSITY_INTERVAL_TRAINING
        37 to 24L, // HIKING
        38 to 25L, // ICE_HOCKEY
        39 to 39L, // ICE_SKATING → patinação
        44 to 28L, // MARTIAL_ARTS
        46 to 31L, // PADDLING
        47 to 3000L, // PARAGLIDING
        48 to 66L, // PILATES
        50 to 34L, // RACQUETBALL
        51 to 9L, // ROCK_CLIMBING
        52 to 25L, // ROLLER_HOCKEY
        53 to 35L, // ROWING
        54 to 35L, // ROWING_MACHINE
        55 to 36L, // RUGBY
        56 to 37L, // RUNNING
        57 to 37L, // RUNNING_TREADMILL
        58 to 38L, // SAILING
        59 to 84L, // SCUBA_DIVING
        60 to 39L, // SKATING
        61 to 61L, // SKIING
        62 to 67L, // SNOWBOARDING
        63 to 40L, // SNOWSHOEING → esportes na neve
        64 to 41L, // SOCCER
        65 to 42L, // SOFTBALL
        66 to 43L, // SQUASH
        68 to 68L, // STAIR_CLIMBING
        69 to 44L, // STAIR_CLIMBING_MACHINE
        70 to 50L, // STRENGTH_TRAINING
        71 to 62L, // STRETCHING → alongamento
        72 to 45L, // SURFING
        73 to 46L, // SWIMMING_OPEN_WATER
        74 to 46L, // SWIMMING_POOL
        75 to 47L, // TABLE_TENNIS
        76 to 48L, // TENNIS
        78 to 51L, // VOLLEYBALL
        79 to 52L, // WALKING
        80 to 54L, // WATER_POLO
        81 to 50L, // WEIGHTLIFTING → musculação
        82 to 70L, // WHEELCHAIR
        83 to 57L, // YOGA
    )

    fun workoutType(exerciseType: Int): Long = typeMap[exerciseType] ?: 3000L

    /** Categoria do jogo pelo tipo do Saúde (HealthSync.kind(for:)), não a do catálogo */
    fun kind(hkType: Long): ActivityKind = when (hkType) {
        37L -> ActivityKind.CORRIDA
        52L, 24L -> ActivityKind.CAMINHADA
        13L, 74L -> ActivityKind.BIKE
        46L, 53L, 54L -> ActivityKind.NATACAO
        51L -> ActivityKind.VOLEI
        41L, 1L, 3L, 36L, 23L, 6L, 25L -> ActivityKind.FUTEBOL
        50L, 20L, 59L -> ActivityKind.MUSCULACAO
        11L, 63L, 73L, 64L -> ActivityKind.CROSSFIT
        28L, 8L, 65L, 56L, 18L -> ActivityKind.LUTAS
        77L, 78L, 58L -> ActivityKind.DANCA
        57L, 66L, 62L, 29L, 72L -> ActivityKind.YOGA
        else -> ActivityKind.OUTRO
    }

    /** Esforço 1–10 pelo gasto real comparado ao esperado em ritmo moderado (HealthSync.effort) */
    fun effort(kind: ActivityKind, minutes: Int, kcal: Double?, weight: Double): Int {
        if (kcal == null || kcal <= 0 || minutes <= 0) return 5
        val expected = kind.met * 3.5 * weight / 200 * minutes
        val ratio = kcal / maxOf(expected - 3.5 * weight / 200 * minutes, 1.0)
        return roundToIntSwift(5 * ratio).coerceIn(1, 10)
    }

    /** Um treino lido do Health Connect */
    data class Workout(
        val id: String,
        val exerciseType: Int,
        val start: Instant,
        val end: Instant,
        /** Nome do app que gravou (vira `source`) */
        val source: String,
        /** Gravado pelo próprio GymBros: não volta como importado */
        val ownApp: Boolean = false,
        val kcal: Double? = null,
        val meters: Double? = null,
    )

    /** Atividade já registrada (para não duplicar) */
    data class Existing(val start: Instant, val minutes: Int, val healthUUID: String?, val healthWritten: String?)

    data class Result(val imported: List<kotlinx.serialization.json.JsonObject>, val skippedOverlap: Int)

    /** Janela da busca: 2 dias antes da última sincronização, ou os primeiros 14 dias */
    fun since(lastSync: Instant?, now: Instant): Instant =
        lastSync?.minus(Duration.ofDays(2)) ?: now.minus(Duration.ofDays(FIRST_IMPORT_DAYS))

    /** Os treinos novos como atividades da cópia (DTO do `Backup`), sem duplicar */
    fun plan(workouts: List<Workout>, existing: List<Existing>, ignored: Set<String>, weight: Double, mainMonster: String?): Result {
        val known = existing.mapNotNull { it.healthUUID }.toSet() + existing.mapNotNull { it.healthWritten } + ignored
        val ranges = existing.map { it.start to it.start.plusSeconds(it.minutes.toLong() * 60) }.toMutableList()
        val out = mutableListOf<kotlinx.serialization.json.JsonObject>()
        var skipped = 0
        for (w in workouts.sortedBy { it.start }) {
            val seconds = Duration.between(w.start, w.end).seconds
            if (w.id in known || w.ownApp || seconds < MIN_SECONDS) continue
            val overlaps = ranges.any { (s, e) ->
                val shared = Duration.between(maxOf(w.start, s), minOf(w.end, e)).toMillis() / 1000.0
                shared > 0 && shared > 0.5 * minOf(seconds.toDouble(), Duration.between(s, e).toMillis() / 1000.0)
            }
            if (overlaps) { skipped++; continue }
            val type = workoutType(w.exerciseType)
            val kind = kind(type)
            val minutes = roundToIntSwift(seconds / 60.0)
            val effort = effort(kind, minutes, w.kcal, weight)
            val split = AttributeSplit.encode(AttributeSplit.split(kind, minutes, effort, w.meters, type))
            out += kotlinx.serialization.json.buildJsonObject {
                put("uuid", kotlinx.serialization.json.JsonPrimitive(UUID.randomUUID().toString().uppercase()))
                put("kind", kotlinx.serialization.json.JsonPrimitive(kind.raw))
                put("date", kotlinx.serialization.json.JsonPrimitive(com.alonsoalmeida.gymbros.domain.backup.AccountEdits.iso(w.start)))
                put("minutes", kotlinx.serialization.json.JsonPrimitive(minutes))
                put("effort", kotlinx.serialization.json.JsonPrimitive(effort))
                put("note", kotlinx.serialization.json.JsonPrimitive(w.kcal?.let { "${it.toInt()} kcal" } ?: ""))
                put("healthUUID", kotlinx.serialization.json.JsonPrimitive(w.id))
                put("source", kotlinx.serialization.json.JsonPrimitive(w.source))
                put("healthType", kotlinx.serialization.json.JsonPrimitive(type))
                put("attributes", kotlinx.serialization.json.JsonPrimitive(split))
                w.kcal?.let { put("kcal", kotlinx.serialization.json.JsonPrimitive(it)) }
                w.meters?.takeIf { it > 0 }?.let { put("meters", kotlinx.serialization.json.JsonPrimitive(it)) }
                mainMonster?.let { put("monsterUUID", kotlinx.serialization.json.JsonPrimitive(it)) }
            }
            ranges += w.start to w.end
        }
        return Result(out, skipped)
    }
}
