package com.alonsoalmeida.gymbros.domain.backup

import com.dd.plist.NSArray
import com.dd.plist.NSData
import com.dd.plist.NSDate
import com.dd.plist.NSDictionary
import com.dd.plist.NSNumber
import com.dd.plist.NSObject
import com.dd.plist.NSString
import com.dd.plist.PropertyListParser
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import java.io.ByteArrayOutputStream
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.zip.Deflater
import java.util.zip.Inflater

/**
 * Formato da cópia da conta no Firestore (`accounts/{uid}/chunks/{n}`), o mesmo que o iOS grava.
 * Fontes: GymBros/Services/FirebaseGame.swift (`FirebaseAccountDataBackend`) e Backup.swift. Contrato:
 * engenharia/requisitos/contrato-firestore.md §4.
 */
object ChunkCodec {
    const val CHUNK_SIZE = 900_000

    /** O `.zlib` do NSData é DEFLATE cru, sem cabeçalho zlib (confirmado no vetor C) */
    fun inflate(packed: ByteArray): ByteArray {
        val inflater = Inflater(true)
        inflater.setInput(packed)
        val out = ByteArrayOutputStream()
        val buf = ByteArray(64 * 1024)
        while (!inflater.finished()) {
            val n = inflater.inflate(buf)
            if (n == 0 && (inflater.needsInput() || inflater.needsDictionary())) break
            out.write(buf, 0, n)
        }
        val complete = inflater.finished()
        inflater.end()
        // Pedaços faltando ou lidos no meio de um envio do outro aparelho: erro, nunca uma cópia pela metade
        check(complete) { "cópia da conta incompleta" }
        return out.toByteArray()
    }

    fun deflate(raw: ByteArray): ByteArray {
        val deflater = Deflater(Deflater.DEFAULT_COMPRESSION, true)
        deflater.setInput(raw)
        deflater.finish()
        val out = ByteArrayOutputStream()
        val buf = ByteArray(64 * 1024)
        while (!deflater.finished()) out.write(buf, 0, deflater.deflate(buf))
        deflater.end()
        return out.toByteArray()
    }

    fun split(packed: ByteArray): List<ByteArray> =
        (packed.indices step CHUNK_SIZE).map { packed.copyOfRange(it, minOf(it + CHUNK_SIZE, packed.size)) }

    fun join(parts: List<ByteArray>): ByteArray {
        val out = ByteArrayOutputStream(parts.sumOf { it.size })
        for (p in parts) out.write(p)
        return out.toByteArray()
    }
}

/** Datas da cópia: ISO 8601 sem fração de segundo (o `.iso8601` do JSONEncoder do iOS recusa fração) */
object Iso8601Seconds : KSerializer<Instant> {
    override val descriptor = PrimitiveSerialDescriptor("Iso8601Seconds", PrimitiveKind.STRING)
    override fun serialize(encoder: Encoder, value: Instant) =
        encoder.encodeString(DateTimeFormatter.ISO_INSTANT.format(value.truncatedTo(ChronoUnit.SECONDS)))
    override fun deserialize(decoder: Decoder): Instant = Instant.parse(decoder.decodeString())
}

/** Datas dentro dos JSON em texto (`settings`, `proof`): segundos desde 2001-01-01 (`.deferredToDate` do iOS) */
object AppleReferenceDate {
    const val OFFSET = 978_307_200.0
    fun toInstant(seconds: Double): Instant {
        val unix = seconds + OFFSET
        val whole = kotlin.math.floor(unix).toLong()
        return Instant.ofEpochSecond(whole, ((unix - whole) * 1e9).toLong())
    }
    fun fromInstant(i: Instant): Double = i.epochSecond - OFFSET + i.nano / 1e9
}

@Serializable
data class ActivityDto(
    val uuid: String,
    val kind: String,
    @Serializable(Iso8601Seconds::class) val date: Instant,
    val minutes: Int,
    val effort: Int,
    val note: String = "",
    val healthUUID: String? = null,
    val source: String? = null,
    val monsterUUID: String? = null,
    val gymUUID: String? = null,
    val meters: Double? = null,
    val kcal: Double? = null,
    val healthType: Long? = null,
    val healthWritten: String? = null,
    /** Divisão de atributos gravada para a atividade (`forca:0.80,tecnica:0.20`): importar, nunca recalcular */
    val attributes: String? = null,
)

@Serializable
data class MonsterDto(
    val uuid: String,
    val name: String,
    @Serializable(Iso8601Seconds::class) val createdAt: Instant,
    val isStarter: Boolean,
    val lastFormID: String? = null,
    val speciesID: String? = null,
)

@Serializable
data class CheckInDto(
    val uuid: String,
    val leagueUUID: String,
    val activityUUID: String,
    val title: String = "",
    @Serializable(Iso8601Seconds::class) val date: Instant,
    val place: String? = null,
)

@Serializable
data class GymDto(val uuid: String, val name: String, @Serializable(Iso8601Seconds::class) val createdAt: Instant)

@Serializable
data class RoutineItemDto(val exerciseID: String, val sets: Int, val reps: Int, val rest: Int, val order: Int, val supersetNext: Boolean? = null)

@Serializable
data class RoutineDto(val uuid: String, val name: String, val weekdays: String, val order: Int, val items: List<RoutineItemDto> = emptyList())

@Serializable
data class LeagueDto(
    val uuid: String,
    val name: String,
    val emoji: String,
    val scoring: String,
    @Serializable(Iso8601Seconds::class) val start: Instant,
    val code: String,
    val isMock: Boolean,
    @Serializable(Iso8601Seconds::class) val joinedAt: Instant,
    val monsterUUID: String? = null,
    @Serializable(Iso8601Seconds::class) val end: Instant? = null,
    val settings: String? = null,
    val swiss: String? = null,
    val tieBreak: String? = null,
    val photoRule: String? = null,
    val weights: String? = null,
    val activityRule: String? = null,
    val joined: Boolean? = null,
    /** Temporada seguinte (esta já é passada) */
    val nextUUID: String? = null,
) {
    fun isOver(now: Instant): Boolean = end?.let { it < now } ?: false
    val isPastSeason: Boolean get() = nextUUID != null
}

/**
 * A cópia da conta (`Backup` v1). Por enquanto só as partes que o bro e as ligas usam; o resto do JSON é preservado
 * por quem grava (o Android só grava a cópia depois da mesclagem por UUID, IOS-08/AND-011).
 */
@Serializable
data class BackupDto(
    val version: Int = 1,
    @Serializable(Iso8601Seconds::class) val exportedAt: Instant,
    /** Ajustes em texto (`Backup.settingKeys`: trainerName, mainMonster…) */
    val settings: Map<String, String> = emptyMap(),
    val activities: List<ActivityDto> = emptyList(),
    val checkIns: List<CheckInDto>? = null,
    val monsters: List<MonsterDto>? = null,
    val routines: List<RoutineDto> = emptyList(),
    val leagues: List<LeagueDto>? = null,
    val gyms: List<GymDto>? = null,
    /** Foto do perfil (JPEG em base64) */
    val profilePhoto: String? = null,
    /** Plist binário (base64 no JSON) com os ajustes da conta */
    val accountSettings: String? = null,
)

object AccountCopy {
    val json = Json { ignoreUnknownKeys = true; explicitNulls = false }

    fun decode(raw: ByteArray): BackupDto = json.decodeFromString(BackupDto.serializer(), raw.decodeToString())

    /** A cópia de trabalho do Android é o JSON inteiro; as telas leem só o que conhecem */
    fun decode(o: kotlinx.serialization.json.JsonObject): BackupDto = json.decodeFromJsonElement(BackupDto.serializer(), o)

    /** Do jeito que está no Firestore: pedaços → DEFLATE cru → JSON */
    fun fromChunks(parts: List<ByteArray>): BackupDto = decode(ChunkCodec.inflate(ChunkCodec.join(parts)))

    /** `accountSettings`: plist binário do iOS → valores Kotlin com o tipo preservado (Boolean ≠ Long ≠ Double) */
    fun settings(plist: ByteArray): Map<String, Any?> {
        val root = PropertyListParser.parse(plist) as NSDictionary
        return root.hashMap.entries.associate { it.key to plain(it.value) }
    }

    private fun plain(o: NSObject?): Any? = when (o) {
        null -> null
        is NSString -> o.content
        is NSNumber -> when (o.type()) {
            NSNumber.BOOLEAN -> o.boolValue()
            NSNumber.INTEGER -> o.longValue()
            else -> o.doubleValue()
        }
        is NSDate -> o.date.toInstant()
        is NSData -> o.bytes()
        is NSArray -> o.array.map { plain(it) }
        is NSDictionary -> o.hashMap.entries.associate { it.key to plain(it.value) }
        else -> o.toJavaObject()
    }
}
