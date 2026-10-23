package com.alonsoalmeida.gymbros.domain.leagues

import com.alonsoalmeida.gymbros.domain.ActivityKind
import com.alonsoalmeida.gymbros.domain.ActivityRecord
import com.alonsoalmeida.gymbros.domain.Attribute
import com.alonsoalmeida.gymbros.domain.BroCatalog
import com.alonsoalmeida.gymbros.domain.Game
import com.alonsoalmeida.gymbros.domain.LeagueScoring
import com.alonsoalmeida.gymbros.domain.MonsterForm
import com.alonsoalmeida.gymbros.domain.RuleClock
import com.alonsoalmeida.gymbros.domain.ScoreInput
import com.alonsoalmeida.gymbros.domain.SnapshotRules
import com.alonsoalmeida.gymbros.domain.Stage
import com.alonsoalmeida.gymbros.domain.SwissBonus
import com.alonsoalmeida.gymbros.domain.SwissMatch
import com.alonsoalmeida.gymbros.domain.SwissResult
import com.alonsoalmeida.gymbros.domain.SwissRound
import com.alonsoalmeida.gymbros.domain.SwissTable
import com.alonsoalmeida.gymbros.domain.SwissTally
import java.time.Instant
import java.time.LocalDate

// Ranking, feed, times, rodada suíça e campeões das ligas (Leagues.swift `LeagueBoard`, LeagueWinners.swift
// `ClubWinners`, Swiss.swift `SwissTable`). Tudo derivado do feed, de forma determinística: o mesmo placar em todo
// aparelho. "me" é você; os outros são o uid do Firebase.

data class RemoteMember(val id: String, val name: String, val formID: String, val teamID: String? = null, val joinedAt: Instant? = null) {
    val form: MonsterForm get() = MonsterForm.byID(formID) ?: MonsterForm.EGG
}

data class RemoteCheckIn(
    val id: String,
    val memberID: String,
    val date: Instant,
    val kindRaw: String,
    val minutes: Int,
    val effort: Int,
    val meters: Double? = null,
    val kcal: Double? = null,
    val title: String,
    val note: String = "",
    val hasPhoto: Boolean = false,
    val workoutTypeID: Long? = null,
    val place: String? = null,
    val proof: CheckInProof? = null,
) {
    val kind: ActivityKind get() = ActivityKind.of(kindRaw)
    val input: ScoreInput get() = ScoreInput(kind, minutes, effort, meters, kcal, workoutTypeID ?: BroCatalog.classicType[kind.raw])
}

data class RemoteTeam(val id: String, val name: String, val memberIDs: List<String> = emptyList())
data class RemoteMessage(val id: String, val memberID: String, val date: Instant, val text: String)

data class RemoteLeague(
    val members: List<RemoteMember> = emptyList(),
    val checkIns: List<RemoteCheckIn> = emptyList(),
    val teams: List<RemoteTeam> = emptyList(),
    val messages: List<RemoteMessage> = emptyList(),
    val requests: List<RemoteMember> = emptyList(),
) {
    fun member(id: String) = members.firstOrNull { it.id == id }

    /**
     * Com as decisões do dono: quem saiu ou foi banido some, pedido aceito vira membro e os pedidos que sobram são os ainda
     * sem resposta. Aplicar duas vezes dá o mesmo resultado (LeagueRemote.swift `applying`).
     */
    fun applying(league: League): RemoteLeague {
        val s = league.settings
        val out = (s.removed + s.banned).toSet()
        val ids = members.map { it.id }.toSet()
        val ms = members.toMutableList()
        for (m in requests) if (m.id in s.approved && m.id !in ids && m.id !in out) ms += m
        ms.removeAll { it.id in out }
        val now = ms.map { it.id }.toSet()
        return copy(
            members = ms,
            checkIns = checkIns.filter { it.memberID !in out },
            messages = messages.filter { it.memberID !in out },
            requests = requests.filter { it.id !in now && it.id !in s.ignored && it.id !in s.banned && it.id !in s.approved },
        )
    }

    companion object { val EMPTY = RemoteLeague() }
}

data class FeedItem(
    val id: String,
    val memberID: String,
    val name: String,
    val avatar: MonsterForm,
    val isMe: Boolean,
    val date: Instant,
    val title: String,
    val note: String,
    val kind: ActivityKind,
    val minutes: Int,
    val score: Int,
    val place: String? = null,
    val hasPhoto: Boolean = false,
    val effort: Int = 5,
    val teamID: String? = null,
    /** Modo da liga, para o placar com unidade; nil = post do perfil (vale XP) */
    val scoring: LeagueScoring? = null,
    /** Esperando o dono aprovar: aparece, mas ainda não pontua */
    val pending: Boolean = false,
    val proof: CheckInProof = CheckInProof(),
    /** Pontos cortados pelo teto da liga */
    val capped: Int = 0,
    val leagueID: String? = null,
    /** Fotos a mais do post (só as suas ficam guardadas) */
    val extraPhotos: Int = 0,
)

data class RankRow(
    val id: String,
    val name: String,
    val avatar: MonsterForm,
    val isMe: Boolean,
    val score: Int = 0,
    val checkIns: Int = 0,
    val reachedAt: Instant? = null,
    val bestStreak: Int = 0,
    val tied: Boolean = false,
    val swiss: Double? = null,
    val bonus: Int = 0,
)

data class TeamRow(val id: String, val name: String, val isMine: Boolean, val score: Int, val members: Int, val form: MonsterForm, val progress: Double)

/** Seu check-in como as ligas precisam (LeagueCheckIn) */
data class MyCheckIn(val c: CheckInJson) {
    val uuid get() = c.uuid.uppercase()
    val leagueUUID get() = c.leagueUUID.uppercase()
    val activityUUID get() = c.activityUUID.uppercase()
    val proof: CheckInProof by lazy { CheckInProof.parse(c.proof) }
}

/** Resultado de um confronto suíço para alguém (Swiss.swift `SwissMatch.result`) */
object SwissView {
    fun involves(m: SwissMatch, id: String) = m.a == id || m.b == id
    fun opponent(m: SwissMatch, id: String): String? = if (m.a == id) m.b else m.a
    fun tally(m: SwissMatch, id: String): SwissTally = if (m.a == id) m.tallyA else m.tallyB
    fun opponentTally(m: SwissMatch, id: String): SwissTally = if (m.a == id) m.tallyB else m.tallyA

    fun result(m: SwissMatch, id: String): SwissResult {
        if (m.b == null) return SwissResult.FOLGA
        val mine = if (m.a == id) m.pointsA else m.pointsB
        val theirs = if (m.a == id) m.pointsB else m.pointsA
        if (mine == theirs) return if (mine > 0) SwissResult.EMPATE else SwissResult.DERROTA
        return if (mine > theirs) SwissResult.VITORIA else SwissResult.DERROTA
    }

    fun letter(r: SwissResult) = when (r) { SwissResult.VITORIA -> "V"; SwissResult.EMPATE -> "E"; SwissResult.DERROTA -> "D"; SwissResult.FOLGA -> "F" }
    fun name(r: SwissResult) = when (r) { SwissResult.VITORIA -> "Vitória"; SwissResult.EMPATE -> "Empate"; SwissResult.DERROTA -> "Derrota"; SwissResult.FOLGA -> "Folga" }

    fun today(rounds: List<SwissRound>): SwissRound? = rounds.lastOrNull()?.takeIf { !it.finished }
    fun match(r: SwissRound, id: String) = r.matches.firstOrNull { involves(it, id) }

    /** Rodadas encerradas de alguém, da mais recente para a mais antiga */
    fun history(rounds: List<SwissRound>, id: String, limit: Int = 7): List<Pair<LocalDate, SwissResult>> =
        rounds.asReversed().asSequence().filter { it.finished }.mapNotNull { r -> match(r, id)?.let { r.day to result(it, id) } }.take(limit).toList()

    /** Bônus de cada um nas rodadas encerradas da janela, com o fim do último dia que rendeu bônus */
    fun bonuses(rounds: List<SwissRound>, scoring: LeagueScoring, since: Instant?, until: Instant?, cal: RulesCalendar = RulesCalendar.RULES): Map<String, Pair<Int, Instant>> {
        val out = HashMap<String, Pair<Int, Instant>>()
        for (r in rounds) {
            if (!r.finished) continue
            val dayStart = cal.start(r.day)
            if (since != null && r.day.isBefore(cal.day(since))) continue
            if (until != null && dayStart >= until) continue
            val end = cal.start(r.day.plusDays(1)).minusSeconds(1)
            for (m in r.matches) for (id in listOfNotNull(m.a, m.b)) {
                val v = SwissBonus.value(result(m, id), scoring)
                if (v <= 0) continue
                out[id] = ((out[id]?.first ?: 0) + v) to end
            }
        }
        return out
    }
}

object LeagueBoard {
    /**
     * Feed da liga: seus check-ins e os dos outros, com a pontuação final (revisão, "dias ativos" e teto por pessoa).
     * `activities` são as suas atividades pelo uuid; `reviews` as decisões do dono (itemID → aprovado).
     */
    fun feed(league: League, mine: List<MyCheckIn>, activities: Map<String, LeagueActivityJson>, me: String, myAvatar: MonsterForm,
             remote: RemoteLeague, reviews: Map<String, Boolean>): List<FeedItem> {
        val r = remote.applying(league)
        val settings = league.settings
        val items = mutableListOf<FeedItem>()
        for (c in mine) {
            val a = activities[c.activityUUID] ?: continue
            if (c.c.review == "denied") continue
            // Atividades do mesmo dia agrupadas neste check-in somam junto
            val extra = c.proof.grouped.mapNotNull { activities[it.uppercase()] }
            items += FeedItem(
                id = c.uuid, memberID = "me", name = me, avatar = myAvatar, isMe = true, date = c.c.date, title = c.c.title, note = c.c.note,
                kind = a.kindEnum, minutes = a.minutes + extra.sumOf { it.minutes },
                score = league.score(listOf(a.scoreInput) + extra.map { it.scoreInput }, c.c.hasPhoto),
                place = c.c.place, hasPhoto = c.c.hasPhoto, effort = a.effort, teamID = league.myTeamID, scoring = league.scoring,
                pending = settings.reviewRequired && c.c.review == "pending", proof = c.proof, leagueID = league.uuid,
                extraPhotos = if (c.c.extraPhotos != null) 1 else 0,
            )
        }
        for (rc in r.checkIns) {
            val m = r.member(rc.memberID) ?: continue
            if (reviews[rc.id] == false) continue
            val extra = rc.proof?.groupedParts.orEmpty()
            items += FeedItem(
                id = rc.id, memberID = m.id, name = m.name, avatar = m.form, isMe = false, date = rc.date, title = rc.title, note = rc.note,
                kind = rc.kind, minutes = rc.minutes + extra.sumOf { it.minutes },
                score = league.score(listOf(rc.input) + extra.map { it.input }, rc.hasPhoto),
                place = rc.place, hasPhoto = rc.hasPhoto, effort = rc.effort, teamID = m.teamID, scoring = league.scoring,
                proof = rc.proof ?: CheckInProof(), leagueID = league.uuid,
                // Check-in de antes da revisão ser ligada já valia
                pending = settings.reviewRequired && reviews[rc.id] == null && rc.date >= (settings.reviewSince ?: Instant.MIN),
            )
        }
        for (i in items.indices) if (items[i].pending) items[i] = items[i].copy(score = 0)
        // Dias ativos: só o primeiro check-in de cada pessoa em cada dia vale
        if (league.scoring == LeagueScoring.DIAS) {
            val cal = RulesCalendar.RULES
            val seen = HashSet<String>()
            for (i in items.indices.sortedBy { items[it].date }) {
                if (items[i].score <= 0) continue
                if (!seen.add("${items[i].memberID}|${cal.day(items[i].date)}")) items[i] = items[i].copy(score = 0)
            }
        }
        // Teto por pessoa, dentro do período da liga
        if (settings.limits.individual.values.any { it > 0 }) {
            val inLeague = items.filter { it.date >= league.start && it.date <= (league.end ?: Instant.MAX) }
            val cut = ScoringLimits.apply(settings.limits.individual, inLeague, { it.id }, { it.date }, { it.score }, { it.memberID }, settings.calendar())
            for (i in items.indices) cut[items[i].id]?.let { c -> items[i] = items[i].copy(score = items[i].score - c, capped = c) }
        }
        return items.sortedByDescending { it.date }
    }

    /** Rodadas suíças da liga, derivadas do feed e dos membros */
    fun swiss(league: League, feed: List<FeedItem>, remote: RemoteLeague, selfID: String, now: Instant): List<SwissRound> {
        val r = remote.applying(league)
        val cal = RulesCalendar.RULES
        val tallies = HashMap<LocalDate, HashMap<String, SwissTally>>()
        for (f in feed) {
            if (f.date < league.start || f.date > (league.end ?: Instant.MAX) || f.date > now) continue
            val day = cal.day(f.date)
            val t = tallies.getOrPut(day) { HashMap() }[f.memberID] ?: SwissTally()
            tallies[day]!![f.memberID] = SwissTally(t.score + f.score, t.checkIns + if (league.photoRule.apply(1, f.hasPhoto) > 0) 1 else 0)
        }
        val joined = HashMap<String, Instant>()
        joined["me"] = league.swissJoinedAt
        for (m in r.members) m.joinedAt?.let { joined[m.id] = it } ?: joined.remove(m.id)
        return SwissTable.table(listOf("me") + r.members.map { it.id }, tallies, league.start, league.end, RuleClock(cal.zone, now),
                                league.code.ifEmpty { league.uuid }, league.swiss, mapOf("me" to selfID), joined)
    }

    /** Ranking da janela [since, until) (LeagueBoard.ranking) */
    fun ranking(feed: List<FeedItem>, league: League, me: String, myAvatar: MonsterForm, since: Instant?, until: Instant? = null,
                remote: RemoteLeague, swiss: List<SwissRound>, selfID: String): List<RankRow> {
        val r = remote.applying(league)
        val rows = LinkedHashMap<String, RankRow>()
        val days = HashMap<String, MutableSet<LocalDate>>()
        rows["me"] = RankRow("me", me, myAvatar, true)
        for (m in r.members) rows[m.id] = RankRow(m.id, m.name, m.form, false)
        val cal = RulesCalendar.RULES
        for (f in feed.asReversed()) {
            if (f.pending) continue
            if (since != null && f.date < since) continue
            if (until != null && f.date >= until) continue
            if (f.date < league.start || f.date > (league.end ?: Instant.MAX)) continue
            val row = rows[f.memberID] ?: RankRow(f.memberID, f.name, f.avatar, f.isMe)
            rows[f.memberID] = row.copy(score = row.score + f.score, checkIns = row.checkIns + 1, reachedAt = if (f.score > 0) f.date else row.reachedAt)
            days.getOrPut(f.memberID) { HashSet() }.add(cal.day(f.date))
        }
        for ((id, d) in days) rows[id]?.let { rows[id] = it.copy(bestStreak = SnapshotRules.bestStreak(d)) }
        for ((id, b) in SwissView.bonuses(swiss, league.scoring, since, until)) {
            val row = rows[id] ?: continue
            rows[id] = row.copy(score = row.score + b.first, bonus = b.first, reachedAt = maxOf(row.reachedAt ?: Instant.MIN, b.second))
        }
        for ((id, p) in SwissTable.points(swiss)) rows[id]?.let { rows[id] = it.copy(swiss = p) }
        // Último desempate pelo id global (o seu é o do servidor)
        val global = { x: RankRow -> if (x.isMe) selfID else x.id }
        val sorted = rows.values.sortedWith { a, b ->
            if (a.score != b.score) return@sortedWith b.score.compareTo(a.score)
            when (league.tieBreak) {
                LeagueTieBreak.PRIMEIRO -> if (a.reachedAt != b.reachedAt) return@sortedWith (a.reachedAt ?: Instant.MAX).compareTo(b.reachedAt ?: Instant.MAX)
                LeagueTieBreak.SEQUENCIA -> if (a.bestStreak != b.bestStreak) return@sortedWith b.bestStreak.compareTo(a.bestStreak)
                LeagueTieBreak.CHECKINS -> if (a.checkIns != b.checkIns) return@sortedWith b.checkIns.compareTo(a.checkIns)
            }
            global(a).compareTo(global(b))
        }.toMutableList()
        for (i in sorted.indices) {
            if (sorted[i].score <= 0) continue
            val tied = (i > 0 && sorted[i - 1].score == sorted[i].score) || (i < sorted.size - 1 && sorted[i + 1].score == sorted[i].score)
            sorted[i] = sorted[i].copy(tied = tied)
        }
        return sorted
    }

    /** Placar dos times: soma do placar de cada membro na janela, com o teto por time */
    fun teams(league: League, ranking: List<RankRow>, feed: List<FeedItem>, remote: RemoteLeague, since: Instant?, now: Instant): List<TeamRow> {
        val r = remote.applying(league)
        val teams = league.teams.map { t -> RemoteTeam(t.id, t.name, r.members.filter { it.teamID == t.id }.map { it.id }) }
        val byMember = ranking.groupBy { it.id }.mapValues { e -> e.value.sumOf { it.score } }
        val inLeague = feed.filter { it.date >= league.start && it.date <= (league.end ?: Instant.MAX) }
        val cut = ScoringLimits.apply(league.settings.limits.team, inLeague, { it.id }, { it.date }, { it.score }, { it.teamID }, league.settings.calendar())
        val cutInWindow = HashMap<String, Int>()
        for (f in inLeague) {
            if (since != null && f.date < since) continue
            val c = cut[f.id] ?: continue
            val t = f.teamID ?: continue
            cutInWindow[t] = (cutInWindow[t] ?: 0) + c
        }
        return teams.map { t ->
            val ids = t.memberIDs + if (league.myTeamID == t.id) listOf("me") else emptyList()
            val (form, progress) = teamBro(ids.map { id -> inLeague.filter { it.memberID == id } }, now)
            val total = ids.sumOf { byMember[it] ?: 0 } - (cutInWindow[t.id] ?: 0)
            TeamRow(t.id, t.name, league.myTeamID == t.id, total, ids.size, form, progress)
        }.sortedWith(compareByDescending<TeamRow> { it.score }.thenBy { it.id })
    }

    /** Média do XP de cada membro (time grande não leva vantagem) e atributos somados */
    private fun teamBro(members: List<List<FeedItem>>, now: Instant): Pair<MonsterForm, Double> {
        if (members.isEmpty()) return MonsterForm.EGG to 0.0
        val attrs = LinkedHashMap<Attribute, Double>()
        var xp = 0
        val clock = RuleClock(RuleClock.LEAGUE_ZONE, now)
        for (items in members) {
            val s = SnapshotRules.snapshot(items.map { ActivityRecord(it.id, it.kind, it.date, it.minutes, it.effort) }, clock)
            xp += s.totalXP
            for ((a, v) in s.lifetimeAttributes) attrs[a] = (attrs[a] ?: 0.0) + v
        }
        val avg = xp / members.size
        val stage = Stage.entries.last { avg >= it.threshold }
        val progress = stage.next?.let { minOf(maxOf((avg - stage.threshold).toDouble() / (it.threshold - stage.threshold).toDouble(), 0.0), 1.0) } ?: 1.0
        if (!stage.branches || attrs.isEmpty()) return MonsterForm(stage, null) to progress
        val (a, b) = Game.branch(attrs)
        return MonsterForm(stage, a, b).resolved to progress
    }
}

// MARK: - Campeões do clube

enum class WinPeriod(val label: String) {
    WEEK("Semana"), MONTH("Mês"), YEAR("Ano");

    /** "2 vitórias semanais" */
    fun wins(n: Int): String {
        val adj = when (this) {
            WEEK -> if (n == 1) "semanal" else "semanais"
            MONTH -> if (n == 1) "mensal" else "mensais"
            YEAR -> if (n == 1) "anual" else "anuais"
        }
        return "$n vitória${if (n == 1) "" else "s"} $adj"
    }

    fun interval(i: Instant, cal: RulesCalendar): Pair<Instant, Instant> = when (this) {
        WEEK -> cal.weekInterval(i)
        MONTH -> cal.monthInterval(i)
        YEAR -> cal.yearInterval(i)
    }
}

data class PeriodWin(val period: WinPeriod, val start: Instant, val end: Instant, val winners: List<RankRow>, val score: Int) {
    val id: String get() = "${period.name}-${start.epochSecond}"
}

object ClubWinners {
    /** Campeões de cada semana, mês e ano encerrados desde o início do clube, do mais recente para o mais antigo */
    fun all(league: League, feed: List<FeedItem>, me: String, myAvatar: MonsterForm, remote: RemoteLeague, swiss: List<SwissRound>,
            selfID: String, now: Instant): List<PeriodWin> {
        val cal = league.settings.calendar()
        val limit = minOf(now, league.end ?: now)
        val out = mutableListOf<PeriodWin>()
        for (p in WinPeriod.entries) {
            var interval = p.interval(league.start, cal)
            var guard = 0
            while (interval.second <= limit && guard++ < 2000) {
                val rank = LeagueBoard.ranking(feed, league, me, myAvatar, interval.first, interval.second, remote, swiss, selfID)
                val top = rank.firstOrNull()
                if (top != null && top.score > 0) out += PeriodWin(p, interval.first, interval.second, rank.filter { it.score == top.score }, top.score)
                interval = p.interval(interval.second, cal)
            }
        }
        return out.sortedByDescending { it.end }
    }

    fun tally(wins: List<PeriodWin>): Map<String, Map<WinPeriod, Int>> {
        val out = HashMap<String, HashMap<WinPeriod, Int>>()
        for (w in wins) for (r in w.winners) out.getOrPut(r.id) { HashMap() }.merge(w.period, 1, Int::plus)
        return out
    }

    /** "Ana", "Ana e Bruno", "Ana, Bruno e Carla" */
    fun names(rows: List<RankRow>): String {
        val names = rows.map { if (it.isMe) "você" else it.name }
        if (names.size <= 1) return names.firstOrNull().orEmpty()
        return names.dropLast(1).joinToString(", ") + " e " + names.last()
    }
}
