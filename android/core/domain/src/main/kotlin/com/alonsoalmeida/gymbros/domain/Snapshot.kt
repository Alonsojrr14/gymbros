package com.alonsoalmeida.gymbros.domain

import java.time.Instant
import java.time.LocalDate

/** Estágios e limiares de XP. Fonte: Game.swift (`enum Stage`) */
enum class Stage(val raw: String, val threshold: Int, val label: String) {
    EGG("egg", 0, "Ovo"), BABY("baby", 60, "Bebê"), ROOKIE("rookie", 300, "Novato"), CHAMPION("champion", 1200, "Atleta"),
    ULTIMATE("ultimate", 3600, "Lenda");

    val next: Stage? get() = entries.getOrNull(ordinal + 1)
    /** Estágios em que o atributo dominante escolhe o galho */
    val branches: Boolean get() = this == CHAMPION || this == ULTIMATE
}

/**
 * Arte disponível no app (o iOS pergunta ao `UIImage(named:)`). O app Android pergunta aos drawables;
 * sem preencher, nenhum híbrido ou virada tem arte, como no iOS fora do UIKit.
 */
object SpriteArt {
    @Volatile var exists: (String) -> Boolean = { false }
    fun has(sprite: String): Boolean = exists(sprite)
}

/**
 * Forma do bro = estágio + galho + espécie. Dupla sempre na ordem F, R, A, T; a Lenda guarda o galho do Atleta de
 * origem só quando é de virada. O ovo é igual para todas as espécies. Fonte: Game.swift (`struct MonsterForm`).
 */
class MonsterForm(
    val stage: Stage,
    attribute: Attribute?,
    attribute2: Attribute? = null,
    origin: Attribute? = null,
    origin2: Attribute? = null,
    species: String = Species.STANDARD,
) {
    val attribute: Attribute?
    val attribute2: Attribute?
    val origin: Attribute?
    val origin2: Attribute?
    val species: String = if (stage == Stage.EGG) Species.STANDARD else species

    init {
        val (a, b) = ordered(attribute, attribute2)
        this.attribute = a
        this.attribute2 = b
        val (o1, o2) = ordered(origin, origin2)
        val virada = stage == Stage.ULTIMATE && o1 != null && (o1 != a || o2 != b)
        this.origin = if (virada) o1 else null
        this.origin2 = if (virada) o2 else null
    }

    val isHybrid: Boolean get() = attribute2 != null
    val isVirada: Boolean get() = origin != null

    /** "champion_forca", "champion_forca_resistencia", "ultimate_forca_to_resistencia" */
    val key: String
        get() {
            val a = attribute ?: return stage.raw
            val branch = listOfNotNull(a, attribute2).joinToString("_") { it.raw }
            val o = origin ?: return "${stage.raw}_$branch"
            val from = listOfNotNull(o, origin2).joinToString("_") { it.raw }
            return "${stage.raw}_${from}_to_$branch"
        }

    /** A espécie padrão mantém os ids antigos, para não perder descobertas do BroBook */
    val id: String get() = if (species == Species.STANDARD) key else "$species/$key"

    /** Atleta de onde a Lenda veio (para a Lenda pura, o do mesmo galho) */
    val champion: MonsterForm?
        get() {
            if (stage != Stage.ULTIMATE) return null
            return if (isVirada) MonsterForm(Stage.CHAMPION, origin, origin2, species = species)
            else MonsterForm(Stage.CHAMPION, attribute, attribute2, species = species)
        }

    /** Lenda pura da linha (a de virada sem arte usa ela) */
    val lineage: MonsterForm get() = if (isVirada) MonsterForm(Stage.ULTIMATE, origin, origin2, species = species) else this

    /** Forma que aparece no app: híbrido sem arte segue a forma normal do dominante; a virada aparece mesmo sem arte */
    val resolved: MonsterForm get() = if (isVirada || hasArt) this else single

    /** Arte para onde não dá para mostrar um espaço vazio: a virada sem arte usa a da Lenda pura da linha */
    val spriteWithFallback: String get() = if (isVirada && !hasArt) lineage.resolved.sprite else sprite

    /** Sem o segundo atributo (forma normal do dominante) */
    val single: MonsterForm get() = MonsterForm(stage, attribute, species = species)

    fun with(species: String): MonsterForm = MonsterForm(stage, attribute, attribute2, origin, origin2, species)

    /** Tem arte no app (híbridos e viradas chegam aos poucos) */
    val hasArt: Boolean get() = !(isHybrid || isVirada) || SpriteArt.has(sprite)

    val speciesInfo: Species get() = Species.byID(species) ?: Species.standard
    val name: String
        get() {
            if (stage == Stage.EGG) return "Ovo"
            return BroCatalog.formNames[species]?.get(key) ?: if (isHybrid) "Híbrido" else key
        }
    val sprite: String get() = if (stage == Stage.EGG) "sprite_egg" else speciesInfo.sprite(key)

    override fun equals(other: Any?): Boolean = other is MonsterForm && other.id == id
    override fun hashCode(): Int = id.hashCode()
    override fun toString(): String = id

    companion object {
        val EGG = MonsterForm(Stage.EGG, null)

        private fun ordered(a: Attribute?, b: Attribute?): Pair<Attribute?, Attribute?> {
            if (a == null || b == null || a == b) return a to null
            return if (a.ordinal > b.ordinal) b to a else a to b
        }

        fun all(species: String = Species.STANDARD): List<MonsterForm> = Stage.entries.flatMap { s ->
            if (s.branches) Attribute.entries.map { MonsterForm(s, it, species = species) }
            else listOf(MonsterForm(s, null, species = species))
        }

        /** As 12 formas híbridas de uma espécie (6 duplas × Atleta e Lenda) */
        fun hybrids(species: String = Species.STANDARD): List<MonsterForm> = listOf(Stage.CHAMPION, Stage.ULTIMATE).flatMap { st ->
            Attribute.pairs.map { MonsterForm(st, it.first, it.second, species = species) }
        }

        /** Os 10 galhos possíveis numa fase: os 4 atributos sozinhos e as 6 duplas */
        val branches: List<Pair<Attribute, Attribute?>> = Attribute.entries.map { it to null } + Attribute.pairs

        /** As Lendas de virada que saem de um Atleta (as 9 saídas diferentes do galho dele) */
        fun viradas(from: MonsterForm): List<MonsterForm> = branches
            .map { MonsterForm(Stage.ULTIMATE, it.first, it.second, from.attribute, from.attribute2, from.species) }
            .filter { it.isVirada }

        /** As 90 Lendas de virada de uma espécie (10 Atletas × 9 saídas) */
        fun viradas(species: String = Species.STANDARD): List<MonsterForm> =
            branches.flatMap { viradas(MonsterForm(Stage.CHAMPION, it.first, it.second, species = species)) }

        fun byID(id: String): MonsterForm? {
            val parts = id.split("/")
            val species = if (parts.size == 2) parts[0] else Species.STANDARD
            if (id.contains("_to_")) return viradas(species).firstOrNull { it.id == id }
            return (all(species) + hybrids(species)).firstOrNull { it.id == id }
        }
    }
}

/** Espécie: nomes e artes de cada forma. Fonte: Game.swift (`struct Species`) e Hatch.swift */
class Species private constructor(val id: String, val name: String, private val spritePrefix: String) {
    /** Arte: sprite_<prefixo><chave>. A padrão usa os nomes antigos (sem prefixo) */
    fun sprite(key: String): String = "sprite_$spritePrefix$key"

    /** Tem as 10 artes no app */
    val isReady: Boolean get() = id == STANDARD || KEYS.all { SpriteArt.has(sprite(it)) }

    companion object {
        const val STANDARD = "coelho"

        val all: List<Species> = BroCatalog.speciesNames.map { (id, name) -> Species(id, name, if (id == STANDARD) "" else "${id}_") }
        val standard: Species = all.first { it.id == STANDARD }

        /** Ordem das formas nas listas de nomes */
        val KEYS = listOf("baby", "rookie", "champion_forca", "champion_resistencia", "champion_agilidade", "champion_tecnica",
                          "ultimate_forca", "ultimate_resistencia", "ultimate_agilidade", "ultimate_tecnica")

        /** Espécies com arte pronta */
        val catalog: List<Species> get() = all.filter { it.isReady }

        fun byID(id: String): Species? = all.firstOrNull { it.id == id }

        /** Fatia mínima dos minutos do ovo para a atividade principal decidir a espécie */
        const val MAJORITY = 0.5

        /** Espécies candidatas de uma atividade: o tipo exato do Apple Saúde, se houver, senão a categoria */
        fun candidates(r: ActivityRecord): List<String> =
            r.healthType?.let { BroCatalog.healthSpecies[it] ?: listOf(STANDARD) } ?: BroCatalog.kindSpecies[r.kind.raw] ?: listOf(STANDARD)

        /**
         * Espécie de um ovo que acabou de chocar: a atividade com mais da metade dos minutos treinados no ovo decide;
         * sem atividade principal, nasce a padrão. Entre candidatas (Urso e Rato), sorteio fixo pelo id do bro.
         */
        fun hatch(records: List<ActivityRecord>, seed: String): Species {
            val votes = LinkedHashMap<List<String>, Double>()
            for (r in records) votes[candidates(r)] = (votes[candidates(r)] ?: 0.0) + maxOf(r.minutes, 0).toDouble()
            val total = votes.values.fold(0.0) { a, b -> a + b }
            // Maioria estrita: dois empatados no topo nunca passam da metade, então a ordem do empate não importa
            val top = votes.entries.maxByOrNull { it.value } ?: return standard
            if (total <= 0 || top.value / total <= MAJORITY) return standard
            val matches = catalog.filter { it.id in top.key }
            if (matches.isEmpty()) return standard
            val rng = SeededRandom(seed)
            return matches[(rng.next() * matches.size).toInt() % matches.size]
        }
    }
}

/** Uma atividade como o jogo a vê. `share`: 1 no principal, 0,8 no representante de liga (RF-JOG-43) */
data class ActivityRecord(
    val id: String,
    val kind: ActivityKind,
    val date: Instant,
    val minutes: Int,
    val effort: Int,
    val weights: Map<Attribute, Double>? = null,
    val share: Double = 1.0,
    /** Tipo exato do treino no Apple Saúde (decide a espécie com mais precisão que a categoria) */
    val healthType: Long? = null,
) {
    val split: Map<Attribute, Double> get() = weights ?: kind.weights
}

data class Evolution(val date: Instant, val form: MonsterForm)

/** XP que um dono deu a um bro */
data class OwnerXP(val name: String, val xp: Int)

/** Ponto de partida de um bro que chegou por troca. Fonte: Game.swift (`struct SnapshotBase`) */
data class SnapshotBase(
    val formID: String,
    val xp: Int,
    val attributes: Map<String, Double>,
    val date: Instant,
    val history: List<OwnerXP>? = null,
) {
    val form: MonsterForm get() = MonsterForm.byID(formID) ?: MonsterForm.EGG
    val owners: List<OwnerXP> get() = history ?: listOf(OwnerXP("Dono anterior", xp))
}

class Snapshot {
    var totalXP = 0
    var form = MonsterForm.EGG
    /** Atributos acumulados desde a última evolução: decidem o próximo galho */
    val stageAttributes = LinkedHashMap<Attribute, Double>()
    val lifetimeAttributes = LinkedHashMap<Attribute, Double>()
    /** XP que veio com o bro numa troca, de quem o treinou antes */
    var inherited: List<OwnerXP> = emptyList()
    val inheritedXP: Int get() = inherited.sumOf { it.xp }
    val myXP: Int get() = totalXP - inheritedXP
    var arrivedAt: Instant? = null
    var hatchAttributes: Map<Attribute, Double> = emptyMap()
    var evolutions: List<Evolution> = emptyList()
    var xpByActivity: Map<String, Int> = HashMap()
    var streak = 0
    var bestStreak = 0
    var lastActivity: Instant? = null
    var todayXP = 0

    val stage: Stage get() = form.stage
    val level: Int get() = Game.level(totalXP)

    val progress: Double
        get() {
            val next = stage.next ?: return 1.0
            val span = (next.threshold - stage.threshold).toDouble()
            return minOf(maxOf((totalXP - stage.threshold).toDouble() / span, 0.0), 1.0)
        }

    val xpToNext: Int? get() = stage.next?.let { maxOf(it.threshold - totalXP, 0) }

    /** Forma que viria se evoluísse agora */
    val nextForm: MonsterForm?
        get() {
            val next = stage.next ?: return null
            if (!next.branches) return MonsterForm(next, null, species = form.species)
            val (a, b) = Game.branch(stageAttributes)
            return MonsterForm(next, a, b, form.attribute, form.attribute2, form.species).resolved
        }

    fun copy(): Snapshot = Snapshot().also { c ->
        c.totalXP = totalXP; c.form = form; c.stageAttributes.putAll(stageAttributes); c.lifetimeAttributes.putAll(lifetimeAttributes)
        c.inherited = inherited; c.arrivedAt = arrivedAt; c.hatchAttributes = hatchAttributes; c.evolutions = evolutions
        c.xpByActivity = xpByActivity; c.streak = streak; c.bestStreak = bestStreak; c.lastActivity = lastActivity; c.todayXP = todayXP
    }
}

/** O bro é função do histórico. Fonte: Game.swift (`Game.snapshot`, `streak`, `bestStreak`) */
object SnapshotRules {
    fun snapshot(records: List<ActivityRecord>, clock: RuleClock, base: SnapshotBase? = null): Snapshot {
        val s = Snapshot()
        if (base != null) {
            s.form = base.form
            s.totalXP = base.xp
            for ((k, v) in base.attributes) Attribute.of(k)?.let { s.lifetimeAttributes[it] = v }
            s.evolutions = listOf(Evolution(base.date, base.form))
            s.inherited = base.owners
            s.arrivedAt = base.date
        }
        val evolutions = s.evolutions.toMutableList()
        val xpByActivity = HashMap<String, Int>()
        val dayTotals = HashMap<LocalDate, Int>()
        val dayGained = HashMap<LocalDate, Int>()
        for (r in records.sortedBy { it.date }) {
            val raw = roundToIntSwift(Game.xp(r.kind, r.minutes, r.effort).toDouble() * r.share)
            val day = clock.day(r.date)
            val before = dayTotals[day] ?: 0
            val full = maxOf(minOf(raw, Game.DAILY_SOFT_CAP - before), 0)
            val gainedBefore = dayGained[day] ?: 0
            val gained = minOf(full + (raw - full) / 3, maxOf(Game.DAILY_HARD_CAP - gainedBefore, 0))
            dayTotals[day] = before + raw
            dayGained[day] = gainedBefore + gained
            xpByActivity[r.id] = gained
            s.totalXP += gained
            for ((attr, w) in r.split) {
                s.stageAttributes[attr] = (s.stageAttributes[attr] ?: 0.0) + gained.toDouble() * w
                s.lifetimeAttributes[attr] = (s.lifetimeAttributes[attr] ?: 0.0) + gained.toDouble() * w
            }
            // Vários estágios numa atividade só: a fase nova ainda está vazia, então o galho usa a anterior
            var carried: Map<Attribute, Double> = emptyMap()
            while (true) {
                val next = s.form.stage.next ?: break
                if (s.totalXP < next.threshold) break
                val attrs: Map<Attribute, Double> = if (s.stageAttributes.isEmpty()) carried else HashMap(s.stageAttributes)
                if (s.form.stage == Stage.EGG) s.hatchAttributes = attrs
                s.form = if (next.branches) {
                    // A Lenda continua a linha do Atleta: galho diferente do dele vira Lenda de virada, só dele
                    val (a, b) = Game.branch(attrs)
                    MonsterForm(next, a, b, origin = s.form.attribute, origin2 = s.form.attribute2)
                } else {
                    MonsterForm(next, null)
                }
                evolutions += Evolution(r.date, s.form)
                carried = attrs
                s.stageAttributes.clear()
            }
        }
        s.evolutions = evolutions
        s.xpByActivity = xpByActivity
        s.streak = streak(dayTotals.keys, clock.today)
        s.bestStreak = bestStreak(dayTotals.keys)
        s.lastActivity = records.maxOfOrNull { it.date }
        s.todayXP = dayGained[clock.today] ?: 0
        return s
    }

    /** Dias seguidos com atividade, terminando hoje ou ontem */
    fun streak(days: Set<LocalDate>, today: LocalDate): Int {
        var day = if (days.contains(today)) today else today.minusDays(1)
        var count = 0
        while (days.contains(day)) {
            count++
            day = day.minusDays(1)
        }
        return count
    }

    /** Maior sequência de dias seguidos já feita */
    fun bestStreak(days: Set<LocalDate>): Int {
        var best = 0
        for (d in days) {
            if (days.contains(d.minusDays(1))) continue
            var n = 1
            var cur = d
            while (days.contains(cur.plusDays(1))) {
                n++
                cur = cur.plusDays(1)
            }
            best = maxOf(best, n)
        }
        return best
    }
}
