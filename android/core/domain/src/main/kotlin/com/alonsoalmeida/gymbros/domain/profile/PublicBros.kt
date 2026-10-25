package com.alonsoalmeida.gymbros.domain.profile

import com.alonsoalmeida.gymbros.domain.ActivityKind
import com.alonsoalmeida.gymbros.domain.Attribute
import com.alonsoalmeida.gymbros.domain.MonsterForm
import com.alonsoalmeida.gymbros.domain.Roster
import com.alonsoalmeida.gymbros.domain.Snapshot
import kotlinx.serialization.Serializable
import kotlin.math.floor

/**
 * Bros e atributos do perfil público ("Bros e atributos", chave `publicBros`; PublicProfile.swift `PublicProfile.Bros`).
 * No JSON de `public` fica em `bros`, com os mesmos nomes do iPhone: `top` {name, formID, level} = o bro de maior XP;
 * `dexFound`/`dexTotal` = formas descobertas no BroBook e o total; `favorite` {kind, count} = o `ActivityKind.raw` mais
 * postado e quantas vezes; `attributes` {forca, resistencia, agilidade, tecnica} = percentual inteiro (soma 100) dos
 * atributos de todos os treinos. Perfis antigos não têm `bros`.
 */
@Serializable
data class PublicBros(
    val top: Top? = null,
    val dexFound: Int,
    val dexTotal: Int,
    val favorite: Favorite? = null,
    val attributes: Map<String, Int>? = null,
) {
    @Serializable
    data class Top(val name: String, val formID: String, val level: Int) {
        val form: MonsterForm get() = MonsterForm.byID(formID) ?: MonsterForm.EGG
    }

    @Serializable
    data class Favorite(val kind: String, val count: Int) {
        val activity: ActivityKind get() = ActivityKind.of(kind)
    }

    val dominant: Attribute? get() = PublicBrosRules.dominant(attributes)
    fun percent(a: Attribute): Int = attributes?.get(a.raw) ?: 0
}

/** Regras puras de "Bros e atributos", iguais às do iPhone (vetor `gymbros-public-bros.json`) */
object PublicBrosRules {
    /**
     * Bro de maior XP, BroBook, atividade mais postada (as não postadas ficam privadas, como nos números) e atributos
     * gerais, somados de todos os treinos (`player` = snapshot do jogador, sem a divisão entre os bros)
     */
    fun build(roster: Roster, player: Snapshot, postedKinds: List<ActivityKind>, dexFound: Int, dexTotal: Int): PublicBros {
        val top = topIndex(roster.monsters.map { roster.snapshot(it.uuid).totalXP })?.let { i ->
            val m = roster.monsters[i]
            val s = roster.snapshot(m.uuid)
            val name = ContentFilter.publishable(m.displayName(s.form))
            PublicBros.Top(name.ifEmpty { s.form.name }, s.form.id, s.level)
        }
        return PublicBros(top, dexFound, dexTotal, favorite(postedKinds), percentages(player.lifetimeAttributes))
    }

    /** Percentual inteiro de cada atributo, somando 100 (maior resto; empate na ordem de `Attribute`). Sem treino: null. */
    fun percentages(attrs: Map<Attribute, Double>): Map<String, Int>? {
        val values = Attribute.entries.map { maxOf(attrs[it] ?: 0.0, 0.0) }
        val total = values.fold(0.0) { acc, v -> acc + v }
        if (total <= 0) return null
        val exact = values.map { it * 100 / total }
        val out = exact.map { floor(it).toInt() }.toMutableList()
        val rest = 100 - out.sum()
        val ranked = exact.indices.sortedWith(compareByDescending<Int> { exact[it] - floor(exact[it]) }.thenBy { it })
        for (i in ranked.take(rest)) out[i] += 1
        return Attribute.entries.mapIndexed { i, a -> a.raw to out[i] }.toMap()
    }

    /** O de maior percentual; empate fica com o primeiro de `Attribute` */
    fun dominant(percent: Map<String, Int>?): Attribute? {
        if (percent == null) return null
        var best: Attribute? = null
        for (a in Attribute.entries) if (best == null || (percent[a.raw] ?: 0) > (percent[best.raw] ?: 0)) best = a
        return best
    }

    /** A atividade que mais aparece; empate fica com a primeira de `ActivityKind` */
    fun favorite(kinds: List<ActivityKind>): PublicBros.Favorite? {
        val counts = kinds.groupingBy { it }.eachCount()
        var best: ActivityKind? = null
        for (k in ActivityKind.entries) {
            val n = counts[k] ?: 0
            if (n > 0 && (best == null || n > counts.getValue(best))) best = k
        }
        return best?.let { PublicBros.Favorite(it.raw, counts.getValue(it)) }
    }

    /** Posição do bro de maior XP (o nível acompanha o XP); empate fica com o primeiro */
    fun topIndex(xp: List<Int>): Int? {
        var best: Int? = null
        for ((i, v) in xp.withIndex()) if (best == null || v > xp[best]) best = i
        return best
    }
}
