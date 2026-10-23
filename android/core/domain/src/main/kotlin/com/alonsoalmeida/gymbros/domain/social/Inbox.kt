package com.alonsoalmeida.gymbros.domain.social

import com.alonsoalmeida.gymbros.domain.ActivityKind
import com.alonsoalmeida.gymbros.domain.MonsterForm
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

// Caixa de entrada (Inbox/Inbox.swift): mensagens diretas (texto, força, convite para treinar junto, reação) e a
// atividade social. Regras puras: conversas, não lidas, arquivar/limpar só do seu lado, notificações.

enum class DirectKind(val raw: String) {
    TEXT("text"), CHEER("cheer"), INVITE("invite"), INVITE_REPLY("inviteReply"), REACTION("reaction");

    companion object { fun of(raw: String?) = entries.firstOrNull { it.raw == raw } ?: TEXT }
}

/** Convite para treinar junto. `whenAt` nulo = agora */
data class TrainInvite(val kindRaw: String, val place: String, val whenAt: Instant? = null, val latitude: Double? = null, val longitude: Double? = null) {
    val kind: ActivityKind get() = ActivityKind.of(kindRaw)

    /** "Agora", "Hoje, 19:00", "Amanhã, 07:00" ou "sáb., 25 de out., 08:00" */
    fun whenText(now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): String {
        val w = whenAt ?: return "Agora"
        val d = w.atZone(zone).toLocalDate()
        val today = now.atZone(zone).toLocalDate()
        val t = SocialText.time(w, zone)
        return when (d) {
            today -> "Hoje, $t"
            today.plusDays(1) -> "Amanhã, $t"
            else -> "${d.format(DateTimeFormatter.ofPattern("EEE, d 'de' MMM", Locale.forLanguageTag("pt-BR")))}, $t"
        }
    }
}

data class DirectMessage(
    val id: String,
    /** A outra pessoa da conversa */
    val peerID: String,
    val outgoing: Boolean,
    val date: Instant,
    val kind: DirectKind = DirectKind.TEXT,
    val text: String = "",
    val invite: TrainInvite? = null,
    val replyTo: String? = null,
    val accepted: Boolean? = null,
) {
    /** Uma linha na lista de conversas */
    fun preview(now: Instant = Instant.now()): String = when (kind) {
        DirectKind.TEXT -> (if (outgoing) "Você: " else "") + text
        DirectKind.CHEER -> if (outgoing) "Você mandou força 💪" else "💪 Mandou força" + if (text.isEmpty()) "" else ": $text"
        DirectKind.INVITE -> (if (outgoing) "Você convidou: " else "Convite: ") + (invite?.let { "${it.kind.label} · ${it.whenText(now)}" } ?: "treinar junto")
        DirectKind.INVITE_REPLY -> if (accepted == true) (if (outgoing) "Você topou o convite 🤝" else "Topou o convite 🤝")
                                   else (if (outgoing) "Você recusou o convite" else "Recusou o convite")
        DirectKind.REACTION -> (if (outgoing) "Você reagiu " else "Reagiu ") + text
    }
}

data class InboxPeer(val id: String, val name: String, val formID: String) {
    val form: MonsterForm get() = MonsterForm.byID(formID) ?: MonsterForm.EGG
}

/** Uma linha da aba Notificações (o Android traz as sociais: força, convites e pedidos de amizade) */
data class InboxEvent(
    val id: String,
    val kind: Kind,
    val actorID: String,
    val actorName: String,
    val actorFormID: String,
    val date: Instant,
    val text: String = "",
    val detail: String = "",
    val targetID: String? = null,
    val accepted: Boolean? = null,
) {
    enum class Kind { REACTION, COMMENT, LIVE_START, FRIEND_REQUEST, CHEER, INVITE, INVITE_REPLY }

    val actorForm: MonsterForm get() = MonsterForm.byID(actorFormID) ?: MonsterForm.EGG

    /** O que vem depois do nome (InboxView.swift `InboxEventRow.phrase`) */
    val phrase: String
        get() = when (kind) {
            Kind.REACTION -> "reagiu $text ao seu check-in"
            Kind.COMMENT -> "comentou no seu check-in"
            Kind.LIVE_START -> "começou a treinar: $text · $detail"
            Kind.FRIEND_REQUEST -> "quer ser seu amigo"
            Kind.CHEER -> "mandou força pra você 💪"
            Kind.INVITE -> "te chamou pra treinar junto"
            Kind.INVITE_REPLY -> if (accepted == true) "topou treinar junto 🤝" else "não vai poder dessa vez"
        }

    val quote: String
        get() = when (kind) {
            Kind.REACTION -> detail
            Kind.COMMENT -> "“$text” · $detail"
            Kind.CHEER -> text
            Kind.INVITE -> detail + if (text.isEmpty()) "" else "\n$text"
            else -> ""
        }
}

/** Uma conversa: a pessoa e a última mensagem */
data class Conversation(val peer: InboxPeer, val last: DirectMessage, val unread: Int) {
    val id: String get() = peer.id
}

/**
 * Estado da caixa de entrada guardado na conta (vai para o iPhone): até quando leu cada conversa, arquivadas e limpas
 * (só do seu lado), quando viu a aba Notificações e quando cada pedido de amizade apareceu.
 */
data class InboxMarks(
    val seenAt: Instant? = null,
    val readUntil: Map<String, Instant> = emptyMap(),
    val archived: Map<String, Instant> = emptyMap(),
    val cleared: Map<String, Instant> = emptyMap(),
    val requestsSeen: Map<String, Instant> = emptyMap(),
) {
    companion object {
        const val SEEN = "inboxSeenAt"
        const val READ = "inboxReadUntil"
        const val ARCHIVED = "inboxArchived"
        const val CLEARED = "inboxCleared"
        const val REQUESTS = "inboxRequestsSeen"
    }
}

object InboxRules {
    /** O servidor guarda 90 dias */
    const val WINDOW_SECONDS = 90L * 86_400

    /** Sem quem você bloqueou e sem o que você denunciou */
    fun visible(messages: List<DirectMessage>, mod: Moderation): List<DirectMessage> =
        messages.filter { !mod.isBlocked(it.peerID) && (it.outgoing || !mod.isHidden(ReportedKind.DIRECT_MESSAGE, it.id)) }

    /** A conversa, sem o que você limpou do seu lado, da mais antiga para a mais nova */
    fun messages(all: List<DirectMessage>, peerID: String, marks: InboxMarks): List<DirectMessage> {
        val since = marks.cleared[peerID] ?: Instant.MIN
        return all.filter { it.peerID == peerID && it.date > since }.sortedBy { it.date }
    }

    fun unread(list: List<DirectMessage>, peerID: String, marks: InboxMarks, openPeer: String?): Int {
        if (openPeer == peerID) return 0
        val since = marks.readUntil[peerID] ?: Instant.MIN
        return list.count { !it.outgoing && it.date > since }
    }

    /** Conversas (as arquivadas sem mensagem nova só com `archived`), da mais recente para a mais antiga */
    fun conversations(all: List<DirectMessage>, marks: InboxMarks, peer: (String) -> InboxPeer, archived: Boolean, openPeer: String? = null): List<Conversation> =
        all.groupBy { it.peerID }.mapNotNull { (id, list0) ->
            val since = marks.cleared[id] ?: Instant.MIN
            val list = list0.filter { it.date > since }
            val last = list.maxByOrNull { it.date } ?: return@mapNotNull null
            Conversation(peer(id), last, unread(list, id, marks, openPeer))
        }.filter { c -> (marks.archived[c.peer.id]?.let { it >= c.last.date } ?: false) == archived }
            .sortedByDescending { it.last.date }

    /** Resposta ao convite: true topou, false recusou, nulo sem resposta */
    fun answer(all: List<DirectMessage>, invite: DirectMessage): Boolean? =
        all.lastOrNull { it.kind == DirectKind.INVITE_REPLY && it.replyTo == invite.id }?.accepted

    /** Notificações: força e convites recebidos e pedidos de amizade, mais novas primeiro */
    fun activity(messages: List<DirectMessage>, requests: List<InboxPeer>, marks: InboxMarks, peer: (String) -> InboxPeer,
                 extra: List<InboxEvent> = emptyList(), mod: Moderation = Moderation(), now: Instant = Instant.now()): List<InboxEvent> {
        val out = extra.filter { !mod.isBlocked(it.actorID) && !mod.isHidden(ReportedKind.COMMENT, it.id) }.toMutableList()
        for (m in messages) {
            if (m.outgoing || m.kind == DirectKind.TEXT || m.kind == DirectKind.REACTION) continue
            val p = peer(m.peerID)
            val kind = when (m.kind) {
                DirectKind.CHEER -> InboxEvent.Kind.CHEER
                DirectKind.INVITE -> InboxEvent.Kind.INVITE
                else -> InboxEvent.Kind.INVITE_REPLY
            }
            out.add(InboxEvent("dm-${m.id}", kind, p.id, p.name, p.formID, m.date, m.text,
                               m.invite?.let { "${it.kind.label} · ${it.place}" } ?: "", m.id, m.accepted))
        }
        for (f in requests) {
            out.add(InboxEvent("request-${f.id}", InboxEvent.Kind.FRIEND_REQUEST, f.id, f.name, f.formID, marks.requestsSeen[f.id] ?: now))
        }
        return out.sortedByDescending { it.date }
    }

    fun isNew(e: InboxEvent, marks: InboxMarks) = marks.seenAt?.let { e.date > it } ?: true

    /** Força e convites contam nas mensagens, não duas vezes */
    fun unreadActivity(events: List<InboxEvent>, marks: InboxMarks) = events.count { isNew(it, marks) && !it.id.startsWith("dm-") }

    /** Primeira vez que cada pedido de amizade apareceu (o servidor não manda data); os que sumiram saem */
    fun rememberRequests(seen: Map<String, Instant>, ids: Set<String>, now: Instant): Map<String, Instant> =
        ids.associateWith { seen[it] ?: now }
}
