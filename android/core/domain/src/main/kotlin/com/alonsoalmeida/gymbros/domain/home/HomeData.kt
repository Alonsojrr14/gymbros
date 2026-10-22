package com.alonsoalmeida.gymbros.domain.home

import com.alonsoalmeida.gymbros.domain.ActivityKind
import com.alonsoalmeida.gymbros.domain.ActivityRecord
import com.alonsoalmeida.gymbros.domain.AttributeSplit
import com.alonsoalmeida.gymbros.domain.Bro
import com.alonsoalmeida.gymbros.domain.BroCatalog
import com.alonsoalmeida.gymbros.domain.BroLedger
import com.alonsoalmeida.gymbros.domain.Companion
import com.alonsoalmeida.gymbros.domain.Mood
import com.alonsoalmeida.gymbros.domain.MonsterForm
import com.alonsoalmeida.gymbros.domain.OwnedActivity
import com.alonsoalmeida.gymbros.domain.Roster
import com.alonsoalmeida.gymbros.domain.RuleClock
import com.alonsoalmeida.gymbros.domain.Snapshot
import com.alonsoalmeida.gymbros.domain.SnapshotRules
import com.alonsoalmeida.gymbros.domain.Stage
import com.alonsoalmeida.gymbros.domain.WorkoutType
import com.alonsoalmeida.gymbros.domain.backup.AccountCopy
import com.alonsoalmeida.gymbros.domain.backup.BackupDto
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.Base64

/** Uma linha de "Últimas atividades" (ActivityRow do iOS) */
data class HomeActivity(
    val id: String,
    val typeName: String,
    /** SF Symbol do tipo de treino; o app troca pelo ícone Material equivalente */
    val typeSymbol: String,
    val minutes: Int,
    val effort: Int,
    val date: Instant,
    val fromHealth: Boolean,
    val xp: Int,
    /** Onde foi postada: "👤 Perfil · 🏆 Liga · 📍 Lugar" */
    val destinations: String?,
    /** Bros que ganharam XP, do maior quinhão para o menor */
    val bros: List<MonsterForm>,
)

/** Horário ocupado por um treino (dois treinos não acontecem ao mesmo tempo) */
data class BusySpan(val start: Instant, val minutes: Int, val typeName: String) {
    val end: Instant get() = start.plusSeconds(minutes.toLong() * 60)
    fun overlaps(from: Instant, minutes: Int): Boolean = start < from.plusSeconds(minutes.toLong() * 60) && end > from
}

/** O que a tela inicial mostra. Fonte: App.swift (`derive`, `companionContext`) e HomeView.swift */
data class HomeData(
    val trainerName: String,
    val snapshot: Snapshot,
    val mood: Mood,
    val line: String,
    val monsterName: String,
    val recent: List<HomeActivity>,
    val hasActivities: Boolean,
    /** Para a prévia do registro de atividade */
    val roster: Roster,
    /** Tipo de treino das atividades, da mais nova para a mais antiga (atalhos do seletor de tipo) */
    val typeHistory: List<Long>,
    /** Foto do perfil (JPEG), que vai na cópia da conta */
    val profilePhoto: ByteArray?,
    /** Academias salvas (onde foi o treino) */
    val gyms: List<Pair<String, String>>,
    /** Treinos já registrados, para não deixar registrar outro no mesmo horário */
    val busy: List<BusySpan>,
    /** Seu código de amigo (gerado e reservado uma vez; vem do iPhone na cópia da conta) */
    val friendCode: String?,
    /** Pedidos de amizade recusados (o pedido do outro não some do servidor; só some daqui) */
    val declinedFriends: Set<String>,
    /** Versão dos termos de uso aceita (`termsAcceptedVersion`) */
    val termsVersion: Int,
    val leagues: List<com.alonsoalmeida.gymbros.domain.backup.LeagueDto>,
    /** "O que aparece para os outros": mostrar o bro no perfil público (`publicMonster`, padrão sim) */
    val showBro: Boolean = true,
)

object HomeBuilder {
    /** Liga especial dos posts no perfil (`ProfileFeed.id`) */
    const val PROFILE_FEED = "00000000-0000-0000-0000-0000000000AA"

    fun build(copy: BackupDto?, clock: RuleClock): HomeData {
        val settings = copy?.accountSettings?.let { runCatching { AccountCopy.settings(Base64.getDecoder().decode(it)) }.getOrNull() } ?: emptyMap()
        fun text(key: String): String? = copy?.settings?.get(key) ?: settings[key] as? String
        fun json(key: String): String? = when (val v = settings[key]) {
            is ByteArray -> v.decodeToString()
            is String -> v
            else -> null
        }
        @Suppress("UNCHECKED_CAST")
        val splits = (settings["activitySplits"] as? Map<String, Any?>).orEmpty()

        // Mais recentes primeiro, como o @Query do iOS
        val activities = copy?.activities.orEmpty().sortedByDescending { it.date }
        val records = activities.map { a ->
            val weights = (a.attributes ?: splits[a.uuid] as? String)?.let(AttributeSplit::decode)
            OwnedActivity(ActivityRecord(a.uuid.uppercase(), ActivityKind.of(a.kind), a.date, a.minutes, a.effort, weights, healthType = a.healthType),
                          a.monsterUUID?.uppercase())
        }
        val monsters = copy?.monsters.orEmpty().sortedBy { it.createdAt }
        val bros = monsters.map { Bro(it.uuid.uppercase(), it.name, it.createdAt, it.isStarter, it.speciesID) }
        val leagues = copy?.leagues.orEmpty()
        val leagueMonster = leagues.associate { it.uuid.uppercase() to it.monsterUUID?.uppercase() }
        val checkIns = copy?.checkIns.orEmpty()
        @Suppress("UNCHECKED_CAST")
        val gone = ((settings[BroLedger.GONE_KEY] as? List<Any?>).orEmpty()).mapNotNull { (it as? String)?.uppercase() }.toSet()
        val roster = Roster(bros, records, checkIns.map { it.leagueUUID.uppercase() to it.activityUUID.uppercase() }, leagueMonster,
                            text(BroLedger.MAIN_KEY), BroLedger.retired(json(BroLedger.RETIRED_KEY)), BroLedger.bases(json(BroLedger.BASES_KEY)),
                            gone, clock)

        // derive(): o bro principal com a sequência e o XP do dia do jogador (todas as atividades)
        val player = SnapshotRules.snapshot(records.map { it.record }, clock)
        val main = roster.mainSnapshot.copy().apply {
            streak = player.streak
            bestStreak = player.bestStreak
            lastActivity = player.lastActivity
            todayXP = player.todayXP
            xpByActivity = roster.xpByActivity
        }
        val mainName = roster.main?.displayName(main.form) ?: main.form.name

        // companionContext()
        val trainedToday = activities.any { clock.day(it.date) == clock.today }
        val away = main.lastActivity?.let { ChronoUnit.DAYS.between(clock.day(it), clock.today).toInt() } ?: 0
        val weekday = clock.today.dayOfWeek.value % 7 + 1 // domingo = 1, como o Calendar do iOS
        val routine = copy?.routines.orEmpty().sortedBy { it.order }
            .firstOrNull { r -> r.weekdays.split(",").mapNotNull { it.trim().toIntOrNull() }.contains(weekday) }?.name
        val mood = Mood.of(main.stage == Stage.EGG, main.lastActivity, main.todayXP, main.streak, clock)
        // Músculos esquecidos vêm do treino guiado (AND seguinte); sem eles, a frase cai nas outras opções, como no iOS sem treinos guiados
        val context = Companion.Context(mainName, mood, main, trainedToday, routine, emptyList(), away)

        val formsByMonster = monsters.associate { it.uuid.uppercase() to (it.lastFormID?.let(MonsterForm::byID)) }
        val postsByActivity = checkIns.groupBy { it.activityUUID.uppercase() }
        val xp = roster.xpByActivity
        val recent = records.take(3).map { (r, owner) ->
            val dto = activities.first { it.uuid.uppercase() == r.id }
            val type = WorkoutType.byID(dto.healthType) ?: WorkoutType.byID(BroCatalog.classicType[r.kind.raw])
            val posts = postsByActivity[r.id].orEmpty()
            val ids = posts.map { it.leagueUUID.uppercase() }.toSet()
            val destinations = if (posts.isEmpty()) null else {
                val out = mutableListOf<String>()
                if (PROFILE_FEED in ids) out += "👤 Perfil"
                out += leagues.filter { it.uuid.uppercase() in ids }.map { "${it.emoji} ${it.name}" }
                out.joinToString(" · ") + (posts.firstNotNullOfOrNull { it.place }?.let { " · 📍 $it" } ?: "")
            }
            val shares = roster.shares(ids, owner).entries.sortedByDescending { it.value }
            HomeActivity(
                id = r.id, typeName = type?.name ?: r.kind.raw, typeSymbol = type?.let { BroCatalog.workoutSymbols[it.id] } ?: "figure.mixed.cardio",
                minutes = r.minutes, effort = r.effort, date = r.date, fromHealth = dto.healthUUID != null, xp = xp[r.id] ?: 0,
                destinations = destinations, bros = shares.mapNotNull { formsByMonster[it.key] },
            )
        }
        val types = activities.map { a -> a.healthType ?: BroCatalog.classicType[ActivityKind.of(a.kind).raw] ?: 3000L }
        val photo = copy?.profilePhoto?.let { runCatching { Base64.getDecoder().decode(it) }.getOrNull() }
        val gyms = copy?.gyms.orEmpty().sortedBy { it.createdAt }.map { it.uuid.uppercase() to it.name }
        return HomeData(text("trainerName").orEmpty(), main, mood, Companion.line(context, clock), mainName, recent, activities.isNotEmpty(),
                        roster, types, photo, gyms,
                        activities.map { a ->
                            val t = WorkoutType.byID(a.healthType) ?: WorkoutType.byID(BroCatalog.classicType[ActivityKind.of(a.kind).raw])
                            BusySpan(a.date, a.minutes, t?.name ?: a.kind)
                        },
                        friendCode = text("friendCode"),
                        declinedFriends = AccountEditsRead.strings(settings["declinedFriendRequests"]).toSet(),
                        termsVersion = (settings["termsAcceptedVersion"] as? Number)?.toInt() ?: 0,
                        leagues = leagues,
                        showBro = settings["publicMonster"] as? Boolean ?: true)
    }
}

internal object AccountEditsRead {
    fun strings(v: Any?): List<String> = (v as? List<*>)?.mapNotNull { it as? String }.orEmpty()
}
