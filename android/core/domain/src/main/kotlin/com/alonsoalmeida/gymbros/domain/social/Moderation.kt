package com.alonsoalmeida.gymbros.domain.social

import com.alonsoalmeida.gymbros.domain.backup.AppleReferenceDate
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.put
import java.time.Instant

/** O que foi denunciado (Moderation/Moderation.swift `ReportedContent.Kind`) */
enum class ReportedKind(val raw: String, val title: String) {
    CHECK_IN("checkIn", "check-in"), COMMENT("comment", "comentário"), MESSAGE("message", "recado"), PROFILE("profile", "perfil"),
    PHOTO("photo", "foto"), DIRECT_MESSAGE("directMessage", "mensagem");

    fun key(id: String) = "$raw:$id"
}

data class ReportedContent(val kind: ReportedKind, val id: String, val authorID: String, val authorName: String = "") {
    val key: String get() = kind.key(id)
}

enum class ReportReason(val raw: String, val title: String) {
    OFFENSIVE("offensive", "Ofensivo ou assédio"), SEXUAL("sexual", "Nudez ou conteúdo sexual"), VIOLENCE("violence", "Violência"),
    SPAM("spam", "Spam"), OTHER("other", "Outro motivo"),
}

data class BlockedUser(val id: String, val name: String, val date: Instant)

/**
 * O que some da tela para você (`ModerationStore`): o que você denunciou some só para você; quem você bloqueou some de
 * feeds, comentários, amigos e mensagens. Suas coisas nunca somem. A moderação de verdade é do servidor (regras e admin).
 */
data class Moderation(val blocked: List<BlockedUser> = emptyList(), val hidden: Set<String> = emptySet()) {
    private val blockedIDs = blocked.map { it.id }.toSet()

    fun isBlocked(userID: String) = userID in blockedIDs
    fun isHidden(kind: ReportedKind, id: String) = kind.key(id) in hidden

    /** Check-ins: sem quem você bloqueou e sem o que denunciou; foto denunciada some, o post fica */
    fun visiblePosts(items: List<FeedPost>): List<FeedPost> = items.mapNotNull { item ->
        when {
            item.isMe -> item
            isBlocked(item.memberID) || isHidden(ReportedKind.CHECK_IN, item.id) -> null
            isHidden(ReportedKind.PHOTO, item.id) -> item.copy(hasPhoto = false)
            else -> item
        }
    }

    fun visibleComments(list: List<SocialComment>): List<SocialComment> =
        list.filter { it.isMine || !(isBlocked(it.authorID) || isHidden(ReportedKind.COMMENT, it.id)) }

    companion object {
        /** Chaves nos ajustes da conta (as mesmas do iPhone) */
        const val BLOCKED_KEY = "blockedUsers"
        const val HIDDEN_KEY = "hiddenContent"

        /** "A denúncia é analisada em até 24 h." (com servidor) */
        const val REVIEW_NOTE = "A denúncia é analisada em até 24 h."

        /** `[BlockedUser]` do JSONEncoder do iOS: datas em segundos desde 2001 */
        fun decodeBlocked(data: ByteArray?): List<BlockedUser> {
            val arr = data?.let { runCatching { kotlinx.serialization.json.Json.parseToJsonElement(it.decodeToString()) as JsonArray }.getOrNull() } ?: return emptyList()
            return arr.mapNotNull { e ->
                val o = e as? JsonObject ?: return@mapNotNull null
                val id = (o["id"] as? JsonPrimitive)?.content ?: return@mapNotNull null
                BlockedUser(id, (o["name"] as? JsonPrimitive)?.content ?: "",
                            (o["date"] as? JsonPrimitive)?.doubleOrNull?.let(AppleReferenceDate::toInstant) ?: Instant.EPOCH)
            }
        }

        fun encodeBlocked(list: List<BlockedUser>): ByteArray = buildJsonArray {
            for (u in list) add(buildJsonObject {
                put("id", u.id); put("name", u.name); put("date", AppleReferenceDate.fromInstant(u.date))
            })
        }.toString().encodeToByteArray()

        fun decodeHidden(data: ByteArray?): Set<String> =
            data?.let { runCatching { (kotlinx.serialization.json.Json.parseToJsonElement(it.decodeToString()) as JsonArray).mapNotNull { (it as? JsonPrimitive)?.content } }.getOrNull() }
                ?.toSet() ?: emptySet()

        fun encodeHidden(set: Set<String>): ByteArray = buildJsonArray { for (k in set.sorted()) add(JsonPrimitive(k)) }.toString().encodeToByteArray()
    }
}
