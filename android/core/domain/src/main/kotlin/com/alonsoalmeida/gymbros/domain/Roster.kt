package com.alonsoalmeida.gymbros.domain

import com.alonsoalmeida.gymbros.domain.backup.AppleReferenceDate
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import java.time.Instant
import java.time.temporal.ChronoUnit

/** Divisão dos atributos gravada como texto (`forca:0.62,tecnica:0.38`). Fonte: AttributeSplit.swift (`decode`) */
object AttributeSplit {
    fun decode(s: String): Map<Attribute, Double>? {
        val w = LinkedHashMap<Attribute, Double>()
        for (pair in s.split(",")) {
            val p = pair.split(":")
            if (p.size != 2) continue
            val a = Attribute.of(p[0]) ?: continue
            w[a] = p[1].toDoubleOrNull() ?: continue
        }
        return w.ifEmpty { null }
    }
}

/** Um bro da coleção, como a cópia da conta guarda */
data class Bro(val uuid: String, val name: String, val createdAt: Instant, val isStarter: Boolean, val speciesID: String? = null) {
    /** Apelido; vazio (ou ovo) usa o nome da forma. Fonte: Monster.swift (`displayName`) */
    fun displayName(form: MonsterForm): String = if (form.stage == Stage.EGG || name.isEmpty()) form.name else name
}

/** Atividade com o bro dono gravado (`monsterUUID`) */
data class OwnedActivity(val record: ActivityRecord, val owner: String?)

/** Atividade apagada que continua valendo XP para os bros que a receberam. Fonte: RetiredActivities.swift */
data class RetiredActivity(
    val id: String,
    val kind: String,
    val date: Instant,
    val minutes: Int,
    val effort: Int,
    val healthType: Long? = null,
    val weights: String? = null,
    val owners: List<String>,
    val shares: Map<String, Double>? = null,
) {
    val record: ActivityRecord
        get() = ActivityRecord(id, ActivityKind.of(kind), date, minutes, effort, weights?.let(AttributeSplit::decode), healthType = healthType)
}

/**
 * Registros do bro guardados nos ajustes da conta (`accountSettings`): JSON do `JSONEncoder` padrão do iOS, com datas em
 * segundos desde 2001. Fontes: RetiredActivities.swift e Trade.swift (`TradeLedger`).
 */
object BroLedger {
    const val MAIN_KEY = "mainMonster"
    const val RETIRED_KEY = "retiredActivities"
    const val BASES_KEY = "tradeBases"
    const val GONE_KEY = "tradeGone"

    private fun date(o: JsonObject, key: String): Instant = AppleReferenceDate.toInstant(o[key]!!.jsonPrimitive.double)
    private fun opt(o: JsonObject, key: String) = o[key]?.takeIf { it !is JsonNull }

    fun retired(json: String?): List<RetiredActivity> {
        if (json.isNullOrEmpty()) return emptyList()
        return runCatching {
            Json.parseToJsonElement(json).jsonArray.map { e ->
                val o = e.jsonObject
                RetiredActivity(
                    id = o["id"]!!.jsonPrimitive.content.uppercase(), kind = o["kind"]!!.jsonPrimitive.content, date = date(o, "date"),
                    minutes = o["minutes"]!!.jsonPrimitive.int, effort = o["effort"]!!.jsonPrimitive.int,
                    healthType = opt(o, "healthType")?.jsonPrimitive?.long, weights = opt(o, "weights")?.jsonPrimitive?.content,
                    owners = o["owners"]!!.jsonArray.map { it.jsonPrimitive.content.uppercase() },
                    shares = opt(o, "shares")?.jsonObject?.entries?.associate { it.key.uppercase() to it.value.jsonPrimitive.double },
                )
            }
        }.getOrDefault(emptyList())
    }

    fun bases(json: String?): Map<String, SnapshotBase> {
        if (json.isNullOrEmpty()) return emptyMap()
        return runCatching {
            Json.parseToJsonElement(json).jsonObject.entries.associate { (k, v) ->
                val o = v.jsonObject
                k.uppercase() to SnapshotBase(
                    formID = o["formID"]!!.jsonPrimitive.content, xp = o["xp"]!!.jsonPrimitive.int,
                    attributes = o["attributes"]!!.jsonObject.mapValues { it.value.jsonPrimitive.double }, date = date(o, "date"),
                    history = opt(o, "history")?.jsonArray?.map { h ->
                        OwnerXP(h.jsonObject["name"]!!.jsonPrimitive.content, h.jsonObject["xp"]!!.jsonPrimitive.int)
                    },
                )
            }
        }.getOrDefault(emptyMap())
    }
}

/**
 * Coleção de bros e para onde vai o XP de cada atividade. Fonte: Monsters.swift (`struct Roster`).
 *   · sempre, inteiro  → para o bro dono da atividade (o gravado, ou o inicial)
 *   · postada em ligas → também para quem representa o jogador em cada uma, com `LEAGUE_SHARE`
 */
class Roster(
    val monsters: List<Bro>,
    activities: List<OwnedActivity>,
    /** Pares (liga, atividade) dos check-ins */
    checkIns: List<Pair<String, String>>,
    /** Representante de cada liga (`League.monsterUUID`) */
    leagueMonster: Map<String, String?>,
    mainMonster: String?,
    retired: List<RetiredActivity>,
    bases: Map<String, SnapshotBase>,
    gone: Set<String>,
    clock: RuleClock,
) {
    val mainID: String?
    val records: Map<String, List<ActivityRecord>>
    val snapshots: Map<String, Snapshot>
    private val known: Set<String> = monsters.map { it.uuid }.toSet()
    private val leagueMonster = leagueMonster
    private val starterID: String?

    val main: Bro? get() = monsters.firstOrNull { it.uuid == mainID } ?: monsters.firstOrNull { it.isStarter } ?: monsters.firstOrNull()
    val mainSnapshot: Snapshot get() = main?.let { snapshots[it.uuid] } ?: Snapshot()

    fun snapshot(id: String?): Snapshot = id?.let { snapshots[it] } ?: Snapshot()
    fun monster(id: String?): Bro? = monsters.firstOrNull { it.uuid == id }

    /** XP que cada atividade rendeu (para listas); se foi para mais de um bro, o maior */
    val xpByActivity: Map<String, Int>
        get() = HashMap<String, Int>().also { acc ->
            for (s in snapshots.values) for ((k, v) in s.xpByActivity) acc[k] = maxOf(acc[k] ?: v, v)
        }

    /** Mesma regra, para uma atividade ainda não salva */
    fun shares(leagueIDs: Set<String>, owner: String?): Map<String, Double> =
        shares(leagueIDs, owner, known, leagueMonster, starterID)

    init {
        val starter = monsters.firstOrNull { it.isStarter } ?: monsters.firstOrNull()
        starterID = starter?.uuid
        mainID = mainMonster?.uppercase()?.takeIf { id -> monsters.any { it.uuid == id } } ?: starter?.uuid
        val posted = HashMap<String, MutableSet<String>>()
        for ((league, activity) in checkIns) posted.getOrPut(activity) { mutableSetOf() } += league

        val recs = LinkedHashMap<String, MutableList<ActivityRecord>>()
        for (a in activities) {
            val shares = shares(posted[a.record.id] ?: emptySet(), a.owner, known, leagueMonster, starter?.uuid, gone)
            for ((o, share) in shares) recs.getOrPut(o) { mutableListOf() } += a.record.copy(share = share)
        }
        // Apagadas: o XP continua com quem recebeu (se ainda não voltou, ex.: backup restaurado)
        val live = activities.map { it.record.id }.toSet()
        for (e in retired) {
            if (e.id in live) continue
            for (o in e.owners) if (o in known) recs.getOrPut(o) { mutableListOf() } += e.record.copy(share = e.shares?.get(o) ?: 1.0)
        }
        records = recs
        snapshots = monsters.associate { m ->
            val list = recs[m.uuid] ?: emptyList()
            val s = SnapshotRules.snapshot(list, clock, bases[m.uuid])
            // Espécie gravada no bro; se acabou de chocar e ainda não foi gravada, calcula pelos treinos do ovo
            if (s.stage > Stage.EGG) {
                val hatched = s.evolutions.firstOrNull()?.date ?: Instant.MAX
                val species = m.speciesID ?: Species.hatch(list.filter { it.date <= hatched }, m.uuid).id
                // Híbrido sem arte ainda: segue a forma normal do atributo dominante
                fun resolve(f: MonsterForm) = f.with(species).resolved
                s.form = resolve(s.form)
                s.evolutions = s.evolutions.map { Evolution(it.date, resolve(it.form)) }
            }
            m.uuid to s
        }
    }

    companion object {
        /** Parte do XP que o representante de uma liga recebe (o principal recebe tudo) */
        const val LEAGUE_SHARE = 0.8

        /**
         * Quanto do XP vai para cada bro: o principal da atividade (o dono gravado, ou o inicial) leva tudo, e o
         * representante de cada liga marcada leva `LEAGUE_SHARE`. Dono que saiu numa troca (`gone`): o XP foi junto.
         */
        fun shares(leagueIDs: Set<String>, owner: String?, known: Set<String>, leagueMonster: Map<String, String?>, starter: String?,
                   gone: Set<String> = emptySet()): Map<String, Double> {
            val out = LinkedHashMap<String, Double>()
            for (id in leagueIDs) {
                val rep = leagueMonster[id] ?: continue
                if (rep in known) out[rep] = LEAGUE_SHARE
            }
            if (owner != null && owner in gone) return out
            val main = owner?.takeIf { it in known } ?: starter
            if (main != null) out[main] = 1.0
            return out
        }
    }
}

/** Humor do bro. Fonte: Shared/WidgetShared.swift (`enum Mood`) */
enum class Mood(val raw: String, val emoji: String, val label: String) {
    OVO("ovo", "🥚", "Chocando"), ANIMADO("animado", "🤩", "Animado"), FELIZ("feliz", "😊", "Feliz"),
    ENTEDIADO("entediado", "🥱", "Entediado"), TRISTE("triste", "😢", "Triste"), EXAUSTO("exausto", "🥵", "Exausto");

    companion object {
        /** Humor do dia, só a partir de quando foi o último treino e quanto já treinou hoje (fuso do aparelho) */
        fun of(isEgg: Boolean, lastActivity: Instant?, todayXP: Int, streak: Int, clock: RuleClock): Mood {
            if (isEgg) return OVO
            val last = lastActivity ?: return ENTEDIADO
            val days = ChronoUnit.DAYS.between(clock.day(last), clock.today)
            return when {
                days <= 0 -> if (todayXP >= 300) EXAUSTO else if (streak >= 3) ANIMADO else FELIZ
                days == 1L -> FELIZ
                days <= 3 -> ENTEDIADO
                else -> TRISTE
            }
        }
    }
}

/** Frases do bro na tela inicial. Fonte: Companion.swift (`enum Companion`) */
object Companion {
    data class Context(
        val name: String,
        val mood: Mood,
        val snapshot: Snapshot,
        val trainedToday: Boolean,
        val todayRoutine: String?,
        /** Músculos sem treino nos últimos 7 dias (nome em português), só para quem usa o treino guiado */
        val neglected: List<String>,
        val daysAway: Int,
    )

    /** Dia na era do calendário gregoriano do iOS (`ordinality(of: .day, in: .era)`): 1º de janeiro de 1970 é 719163 */
    private const val ERA_DAY_OF_EPOCH = 719_163L

    fun eraDay(clock: RuleClock): Long = clock.today.toEpochDay() + ERA_DAY_OF_EPOCH

    /** Uma frase por dia e humor: muda ao longo do tempo, mas não a cada vez que a tela redesenha */
    fun line(c: Context, clock: RuleClock): String {
        val options = candidates(c)
        return options[(eraDay(clock) % options.size).toInt()]
    }

    fun candidates(c: Context): List<String> {
        val s = c.snapshot
        return when (c.mood) {
            Mood.OVO -> if (s.totalXP == 0)
                listOf("Toc toc… tem alguém aqui dentro.", "Um treino e eu começo a esquentar!", "Estou esperando você se mexer!")
            else listOf("Tá ficando quentinho aqui dentro…", "Faltam ${s.xpToNext ?: 0} XP para eu sair!", "Senti esse último treino! Mais um!")
            Mood.EXAUSTO -> listOf("Ufa… hoje já deu, né? Descanso também me faz crescer.", "Bati o limite do dia. Amanhã tem mais!",
                                   "Tô suado até a alma. Bora descansar?")
            Mood.ANIMADO -> listOf("${s.streak} dias seguidos! Ninguém segura a gente! 🔥", "Tô me sentindo mais forte a cada dia!",
                                   "Que sequência! Já sinto a próxima evolução chegando.")
            Mood.FELIZ -> when {
                !c.trainedToday && c.todayRoutine != null -> listOf("Hoje é dia de ${c.todayRoutine}! Vamos?", "${c.todayRoutine} hoje, hein? Tô pronto!")
                !c.trainedToday && c.neglected.isNotEmpty() -> {
                    val m = c.neglected.first().lowercase()
                    listOf("Faz uma semana que a gente não treina $m. Que tal hoje?", "E se hoje fosse dia de $m?")
                }
                c.trainedToday -> listOf("Treino feito! Agora é comer bem e descansar.", "Boa! Senti essa.", "Mais um treino no bolso 💪")
                else -> listOf("Bora treinar hoje?", "Tô com energia sobrando!", "Que tal mexer o corpo hoje?")
            }
            Mood.ENTEDIADO -> if (c.todayRoutine != null) listOf("Faz ${c.daysAway} dias… hoje tem ${c.todayRoutine}, vamos?")
            else listOf("Faz ${c.daysAway} dias que a gente não treina… tô ficando mole.", "Tô entediado. Bora sair um pouco?",
                        "Qualquer treino serve! Até uma caminhada.")
            Mood.TRISTE -> listOf("Faz ${c.daysAway} dias… senti sua falta. 😢", "Será que você me esqueceu?",
                                  "Uma caminhada curtinha já me deixaria feliz.")
        }
    }
}

/** Textos curtos das atividades. Fonte: Models/Activity.swift */
object ActivityText {
    fun effortLabel(e: Int): String = when {
        e <= 3 -> "Leve"
        e <= 6 -> "Moderado"
        e <= 8 -> "Intenso"
        else -> "Máximo"
    }

    fun duration(minutes: Int): String = when {
        minutes < 60 -> "$minutes min"
        minutes % 60 == 0 -> "${minutes / 60} h"
        else -> "${minutes / 60} h ${minutes % 60} min"
    }
}
