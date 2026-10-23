package com.alonsoalmeida.gymbros.data.health

import android.content.Context
import android.content.pm.PackageManager
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
import androidx.health.connect.client.records.DistanceRecord
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.WeightRecord
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import com.alonsoalmeida.gymbros.data.AccountCopyRepository
import com.alonsoalmeida.gymbros.data.CopyState
import com.alonsoalmeida.gymbros.data.account.AccountDeletion
import com.alonsoalmeida.gymbros.domain.activities.ActivityEdits
import com.alonsoalmeida.gymbros.domain.activities.HealthImport
import com.alonsoalmeida.gymbros.domain.backup.AccountEdits
import com.alonsoalmeida.gymbros.domain.profile.BodyEdits
import com.alonsoalmeida.gymbros.domain.profile.ProfileEdits
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.intOrNull
import java.time.Duration
import java.time.Instant
import java.time.ZoneId

/**
 * Health Connect, o "Apple Saúde" do Android (Services/HealthSync.swift). Lê os treinos gravados por relógios e apps e
 * os transforma em atividades da conta, sem duplicar (`healthUUID`, ignorados, sobreposição). Ligar e a data da última
 * leitura são deste aparelho (a permissão é do aparelho); os treinos importados vão para a conta, que é privada: nada
 * daqui vai para o perfil público nem para as ligas.
 */
class HealthConnectSync(private val context: Context, private val copies: AccountCopyRepository) {
    private val prefs = context.getSharedPreferences(AccountDeletion.HEALTH_PREFS, Context.MODE_PRIVATE)

    val available: Boolean get() = HealthConnectClient.getSdkStatus(context) == HealthConnectClient.SDK_AVAILABLE
    /** Instalado, mas precisa atualizar o app Health Connect */
    val needsUpdate: Boolean get() = HealthConnectClient.getSdkStatus(context) == HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED

    private val client by lazy { HealthConnectClient.getOrCreate(context) }

    var enabled: Boolean
        get() = prefs.getBoolean("enabled", false)
        set(v) { prefs.edit().putBoolean("enabled", v).apply() }

    private var lastSync: Instant?
        get() = prefs.getLong("lastSync", 0L).takeIf { it > 0 }?.let(Instant::ofEpochSecond)
        set(v) { prefs.edit().putLong("lastSync", v?.epochSecond ?: 0L).apply() }

    suspend fun granted(): Set<String> = runCatching { client.permissionController.getGrantedPermissions() }.getOrDefault(emptySet())

    suspend fun hasAccess(): Boolean = WORKOUTS in granted()

    data class Result(val imported: Int, val skippedOverlap: Int)

    /** Busca os treinos novos e grava como atividades (a primeira vez, os últimos 14 dias) */
    suspend fun sync(force: Boolean = false): Result {
        if (!available || (!enabled && !force) || !hasAccess()) return Result(0, 0)
        val granted = granted()
        val now = Instant.now()
        val since = HealthImport.since(lastSync, now)
        val sessions = mutableListOf<ExerciseSessionRecord>()
        var page: String? = null
        do {
            val r = client.readRecords(ReadRecordsRequest(ExerciseSessionRecord::class, TimeRangeFilter.after(since), pageToken = page))
            sessions += r.records
            page = r.pageToken
        } while (!page.isNullOrEmpty())

        val workouts = sessions.map { s ->
            val origin = s.metadata.dataOrigin
            // Calorias e distância do mesmo app que gravou o treino, se a pessoa deixou ler
            val totals = runCatching {
                val metrics = buildSet {
                    if (KCAL in granted) add(ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL)
                    if (DISTANCE in granted) add(DistanceRecord.DISTANCE_TOTAL)
                }
                if (metrics.isEmpty()) null
                else client.aggregate(AggregateRequest(metrics, TimeRangeFilter.between(s.startTime, s.endTime), setOf(origin)))
            }.getOrNull()
            HealthImport.Workout(
                id = s.metadata.id, exerciseType = s.exerciseType, start = s.startTime, end = s.endTime,
                source = appName(origin.packageName), ownApp = origin.packageName == context.packageName,
                kcal = totals?.get(ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL)?.inKilocalories?.takeIf { it > 0 },
                meters = totals?.get(DistanceRecord.DISTANCE_TOTAL)?.inMeters?.takeIf { it > 0 },
            )
        }

        var result = Result(0, 0)
        val weight = weight(granted)
        copies.edit { current ->
            val copy = current ?: AccountEdits.empty("", now)
            val acts = (copy["activities"] as? JsonArray).orEmpty().mapNotNull { it as? JsonObject }
            fun JsonObject.str(k: String) = (this[k] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.content
            val existing = acts.mapNotNull { a ->
                val d = runCatching { Instant.parse(a.str("date")) }.getOrNull() ?: return@mapNotNull null
                HealthImport.Existing(d, (a["minutes"] as? JsonPrimitive)?.intOrNull ?: 0, a.str("healthUUID"), a.str("healthWritten"))
            }
            val ignored = ProfileEdits.strings(ProfileEdits.settings(copy), ActivityEdits.IGNORED_KEY).toSet()
            val main = ((copy["settings"] as? JsonObject)?.get("mainMonster") as? JsonPrimitive)?.content
            val plan = HealthImport.plan(workouts, existing, ignored, weight, main)
            result = Result(plan.imported.size, plan.skippedOverlap)
            if (plan.imported.isEmpty()) copy
            else JsonObject(LinkedHashMap<String, JsonElement>(copy).apply { put("activities", JsonArray(acts + plan.imported)) })
        }
        lastSync = now
        return result
    }

    /** Pesos dos últimos 2 anos (Peso e medidas → "Importar peso") */
    suspend fun importWeights(): Int {
        if (WEIGHT !in granted()) return 0
        val since = Instant.now().minus(Duration.ofDays(730))
        val samples = mutableListOf<BodyEdits.WeightSample>()
        var page: String? = null
        do {
            val r = client.readRecords(ReadRecordsRequest(WeightRecord::class, TimeRangeFilter.after(since), pageToken = page))
            samples += r.records.map { BodyEdits.WeightSample(it.metadata.id, it.time, it.weight.inKilograms) }
            page = r.pageToken
        } while (!page.isNullOrEmpty())
        var added = 0
        copies.edit { current ->
            val (out, n) = BodyEdits.importWeights(current ?: AccountEdits.empty("", Instant.now()), samples, ZoneId.systemDefault())
            added = n
            out
        }
        return added
    }

    /** Peso para estimar o esforço: o último do Health Connect, o de Peso e medidas, ou o de referência */
    private suspend fun weight(granted: Set<String>): Double {
        if (WEIGHT in granted) {
            runCatching {
                client.readRecords(ReadRecordsRequest(WeightRecord::class, TimeRangeFilter.after(Instant.now().minus(Duration.ofDays(365)))))
                    .records.maxByOrNull { it.time }?.weight?.inKilograms
            }.getOrNull()?.let { return it }
        }
        val copy = (copies.state.value as? CopyState.Ready)?.copy
        return (ProfileEdits.settings(copy)["profileLastWeight"] as? Number)?.toDouble()?.takeIf { it > 0 } ?: HealthImport.REFERENCE_WEIGHT
    }

    /** Nome do app que gravou; sem visibilidade do pacote (o app não pede a lista de apps instalados), "Health Connect" */
    @Suppress("DEPRECATION")
    private fun appName(pkg: String): String = runCatching {
        val pm: PackageManager = context.packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
    }.getOrDefault("Health Connect")

    companion object {
        val WORKOUTS = HealthPermission.getReadPermission(ExerciseSessionRecord::class)
        val KCAL = HealthPermission.getReadPermission(ActiveCaloriesBurnedRecord::class)
        val DISTANCE = HealthPermission.getReadPermission(DistanceRecord::class)
        val WEIGHT = HealthPermission.getReadPermission(WeightRecord::class)
        /** Só leitura: o Android ainda não grava treinos no Health Connect */
        val PERMISSIONS = setOf(WORKOUTS, KCAL, DISTANCE, WEIGHT)
    }
}
