package com.alonsoalmeida.gymbros.data.social

import com.alonsoalmeida.gymbros.domain.ActivityKind
import com.alonsoalmeida.gymbros.domain.Game
import com.alonsoalmeida.gymbros.domain.MonsterForm
import com.alonsoalmeida.gymbros.domain.backup.AccountCopy
import com.alonsoalmeida.gymbros.domain.backup.AccountEdits
import com.alonsoalmeida.gymbros.domain.backup.ActivityDto
import com.alonsoalmeida.gymbros.domain.backup.Iso8601Seconds
import com.alonsoalmeida.gymbros.domain.backup.LeagueDto
import com.alonsoalmeida.gymbros.domain.home.HomeBuilder
import com.alonsoalmeida.gymbros.domain.social.BlockedUser
import com.alonsoalmeida.gymbros.domain.social.BroDeck
import com.alonsoalmeida.gymbros.domain.social.FeedPost
import com.alonsoalmeida.gymbros.domain.social.FriendPrefs
import com.alonsoalmeida.gymbros.domain.social.InboxMarks
import com.alonsoalmeida.gymbros.domain.social.Moderation
import com.alonsoalmeida.gymbros.domain.social.SocialComment
import com.dd.plist.NSArray
import com.dd.plist.NSData
import com.dd.plist.NSDate
import com.dd.plist.NSDictionary
import com.dd.plist.NSNumber
import com.dd.plist.NSObject
import com.dd.plist.NSString
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.time.Instant
import java.util.Base64
import java.util.Date

/** Comentário na cópia da conta (Backup.swift `CommentDTO`) */
@Serializable
data class CommentRow(val uuid: String, val itemID: String, val text: String, @Serializable(Iso8601Seconds::class) val date: Instant,
                      val authorID: String? = null, val authorName: String? = null)

/** Check-in na cópia da conta (Backup.swift `CheckInDTO`), com o que o feed usa */
@Serializable
data class CheckInRow(val uuid: String, val leagueUUID: String, val activityUUID: String, val title: String = "", val note: String = "",
                      @Serializable(Iso8601Seconds::class) val date: Instant, val hadPhoto: Boolean? = null, val place: String? = null,
                      val review: String? = null)

@Serializable
private data class Slice(
    val settings: Map<String, String> = emptyMap(),
    val activities: List<ActivityDto> = emptyList(),
    val checkIns: List<CheckInRow>? = null,
    val comments: List<CommentRow>? = null,
    val leagues: List<LeagueDto>? = null,
    val accountSettings: String? = null,
)

/**
 * O que a parte social lê da cópia da conta (a mesma do iPhone): comentários, check-ins, ligas e os ajustes sociais do
 * plist `accountSettings` (bloqueados, denunciados, por amigo, caixa de entrada e deck). Ler: [SocialCopy.read]. Gravar:
 * as funções de [SocialEdits] dentro de `env.copies.edit { }` (o resto do JSON fica intacto).
 */
data class SocialCopy(
    val trainerName: String,
    val comments: List<SocialComment>,
    val checkIns: List<CheckInRow>,
    val activities: Map<String, ActivityDto>,
    val leagues: List<LeagueDto>,
    val moderation: Moderation,
    val friendPrefsRaw: String?,
    val marks: InboxMarks,
    val deckSeen: List<String>,
) {
    /** Liga pública e da temporada atual (o que entra no Feed e nos stories) */
    fun publicLeagues(): List<LeagueDto> = leagues.filter { !it.isPastSeason && !isPrivate(it) }

    /** Seus posts numa liga, no formato do feed (LeagueBoard.feed: o reprovado pelo dono não aparece) */
    fun myPosts(leagueUUID: String, avatar: MonsterForm): List<FeedPost> = checkIns.filter { it.leagueUUID.equals(leagueUUID, true) && it.review != "denied" }
        .mapNotNull { c -> post(c, avatar, leagueUUID.uppercase().takeIf { it != HomeBuilder.PROFILE_FEED }) }

    fun post(c: CheckInRow, avatar: MonsterForm, leagueID: String?): FeedPost? {
        val a = activities[c.activityUUID.uppercase()] ?: return null
        val kind = ActivityKind.of(a.kind)
        return FeedPost(c.uuid.uppercase(), "me", trainerName, avatar, true, c.date, c.title, c.note, kind, a.minutes,
                        Game.xp(kind, a.minutes, a.effort), c.hadPhoto == true, a.effort, c.place, null, leagueID)
    }

    fun prefs(id: String) = FriendPrefs.of(friendPrefsRaw, id)

    companion object {
        private val json = Json { ignoreUnknownKeys = true; explicitNulls = false }

        /** Foto do seu check-in (só na cópia da conta, nunca no servidor), decodificada sob demanda */
        fun photo(copy: JsonObject?, checkInID: String): ByteArray? {
            val list = copy?.get("checkIns") as? JsonArray ?: return null
            val item = list.firstOrNull { ((it as? JsonObject)?.get("uuid") as? JsonPrimitive)?.content?.equals(checkInID, true) == true } as? JsonObject
            val b64 = (item?.get("photo") as? JsonPrimitive)?.content ?: return null
            return runCatching { Base64.getDecoder().decode(b64) }.getOrNull()
        }

        /** Tira o seu check-in da cópia da conta (a atividade continua no histórico) */
        fun removeCheckIn(copy: JsonObject, checkInID: String): JsonObject {
            val list = (copy["checkIns"] as? JsonArray).orEmpty().filter { ((it as? JsonObject)?.get("uuid") as? JsonPrimitive)?.content?.equals(checkInID, true) != true }
            return JsonObject(LinkedHashMap<String, JsonElement>(copy).apply { put("checkIns", JsonArray(list)) })
        }

        fun isPrivate(l: LeagueDto): Boolean = l.settings?.let {
            runCatching { ((Json.parseToJsonElement(it) as JsonObject)["isPrivate"] as? JsonPrimitive)?.content == "true" }.getOrNull()
        } ?: false

        fun read(copy: JsonObject?): SocialCopy {
            val s = copy?.let { runCatching { json.decodeFromJsonElement(Slice.serializer(), it) }.getOrNull() } ?: Slice()
            val plist = s.accountSettings?.let { runCatching { AccountCopy.settings(Base64.getDecoder().decode(it)) }.getOrNull() } ?: emptyMap()
            fun dates(key: String): Map<String, Instant> = (plist[key] as? Map<*, *>).orEmpty().mapNotNull { (k, v) ->
                val secs = (v as? Number)?.toDouble() ?: return@mapNotNull null
                (k as? String ?: return@mapNotNull null) to Instant.ofEpochMilli((secs * 1000).toLong())
            }.toMap()
            return SocialCopy(
                trainerName = s.settings["trainerName"] ?: plist["trainerName"] as? String ?: "",
                comments = s.comments.orEmpty().map { SocialComment(it.uuid.uppercase(), it.itemID, it.text, it.date, it.authorID ?: "me", it.authorName ?: "") }
                    .sortedBy { it.date },
                checkIns = s.checkIns.orEmpty(),
                activities = s.activities.associateBy { it.uuid.uppercase() },
                leagues = s.leagues.orEmpty().sortedBy { it.joinedAt },
                moderation = Moderation(Moderation.decodeBlocked(plist[Moderation.BLOCKED_KEY] as? ByteArray),
                                        Moderation.decodeHidden(plist[Moderation.HIDDEN_KEY] as? ByteArray)),
                friendPrefsRaw = plist[FriendPrefs.KEY] as? String,
                marks = InboxMarks(plist[InboxMarks.SEEN] as? Instant, dates(InboxMarks.READ), dates(InboxMarks.ARCHIVED), dates(InboxMarks.CLEARED),
                                   dates(InboxMarks.REQUESTS)),
                deckSeen = (plist[BroDeck.SEEN_KEY] as? List<*>).orEmpty().filterIsInstance<String>(),
            )
        }
    }
}

/** Mudanças sociais na cópia da conta: o iPhone recebe na próxima mesclagem (ids em UUID maiúsculo, datas ISO sem fração) */
object SocialEdits {
    private fun base(copy: JsonObject?, name: String) = copy ?: AccountEdits.empty(name, Instant.now())

    private fun comments(copy: JsonObject): List<JsonObject> = (copy["comments"] as? JsonArray)?.filterIsInstance<JsonObject>().orEmpty()

    private fun withComments(copy: JsonObject, list: List<JsonObject>) =
        JsonObject(LinkedHashMap<String, JsonElement>(copy).apply { put("comments", JsonArray(list)) })

    fun row(c: SocialComment): JsonObject = buildJsonObject {
        put("uuid", c.id.uppercase()); put("itemID", c.itemID); put("text", c.text); put("date", AccountEdits.iso(c.date))
        put("authorID", c.authorID); put("authorName", c.authorName)
    }

    fun addComment(copy: JsonObject?, name: String, c: SocialComment): JsonObject {
        val b = base(copy, name)
        return withComments(b, comments(b) + row(c))
    }

    fun removeComments(copy: JsonObject?, name: String, ids: Set<String>): JsonObject {
        val b = base(copy, name)
        val up = ids.map { it.uppercase() }.toSet()
        return withComments(b, comments(b).filter { ((it["uuid"] as? JsonPrimitive)?.content?.uppercase()) !in up })
    }

    /**
     * Comentários dos outros nesses posts, como vieram do servidor (CommentSync.pull): os novos entram, os que sumiram de
     * lá (apagados por quem escreveu, pelo dono do post ou pela moderação) saem. Devolve nulo se nada mudou.
     */
    fun syncRemote(copy: JsonObject?, name: String, asked: Set<String>, remote: List<SocialComment>): JsonObject? {
        val b = base(copy, name)
        val list = comments(b)
        val remoteIDs = remote.map { it.id.uppercase() }.toSet()
        val have = list.mapNotNull { (it["uuid"] as? JsonPrimitive)?.content?.uppercase() }.toSet()
        val kept = list.filter { o ->
            val author = (o["authorID"] as? JsonPrimitive)?.content ?: "me"
            val item = (o["itemID"] as? JsonPrimitive)?.content
            val id = (o["uuid"] as? JsonPrimitive)?.content?.uppercase()
            author == "me" || item !in asked || id in remoteIDs
        }
        val added = remote.filter { it.id.uppercase() !in have }.map(::row)
        if (added.isEmpty() && kept.size == list.size) return null
        return withComments(b, kept + added)
    }

    /** Muda chaves do plist `accountSettings` */
    fun settings(copy: JsonObject?, name: String, change: (MutableMap<String, NSObject>) -> Unit): JsonObject =
        AccountEdits.updateSettings(base(copy, name), change)

    fun nsDates(map: Map<String, Instant>): NSDictionary = NSDictionary().apply {
        for ((k, v) in map) put(k, NSNumber(v.toEpochMilli() / 1000.0))
    }

    fun nsDate(i: Instant) = NSDate(Date.from(i))

    fun blocked(list: List<BlockedUser>) = NSData(Moderation.encodeBlocked(list))
    fun hidden(set: Set<String>) = NSData(Moderation.encodeHidden(set))
    fun strings(list: List<String>) = NSArray(*list.map { NSString(it) }.toTypedArray())
}
