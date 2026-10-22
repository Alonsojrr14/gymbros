package com.alonsoalmeida.gymbros.domain.home

import com.alonsoalmeida.gymbros.domain.ActivityKind
import com.alonsoalmeida.gymbros.domain.ActivityRecord
import com.alonsoalmeida.gymbros.domain.Attribute
import com.alonsoalmeida.gymbros.domain.Game
import com.alonsoalmeida.gymbros.domain.Roster
import com.alonsoalmeida.gymbros.domain.RuleClock
import com.alonsoalmeida.gymbros.domain.SnapshotRules
import com.alonsoalmeida.gymbros.domain.Stage
import java.time.Instant

/** Prévia do registro de atividade: XP, divisão e quem evolui. Fonte: LogActivityView.swift (`preview`) */
data class LogPreview(val xp: Int, val grows: List<Stage>, val split: Map<Attribute, Double>, val full: Int) {
    /** Frase de baixo da prévia, igual à do iOS (nula: nada a dizer) */
    val message: String?
        get() {
            if (grows.isNotEmpty()) {
                val eggs = grows.all { it == Stage.EGG }
                val many = grows.size > 1
                return if (eggs) (if (many) "Isso vai fazer os ovos chocarem! 🥚" else "Isso vai fazer o ovo chocar! 🥚")
                else (if (many) "Isso vai fazer seus bros evoluírem! ✨" else "Isso vai fazer seu bro evoluir! ✨")
            }
            return if (xp < full) "Você já treinou bastante nesse dia, então rende menos XP. Descanso também faz parte." else null
        }

    /** XP de cada atributo, como o iOS mostra (`Int((xp × parte).rounded())`) */
    fun attributeXP(a: Attribute): Int? = split[a]?.let { com.alonsoalmeida.gymbros.domain.roundToIntSwift(xp * it) }

    companion object {
        fun compute(roster: Roster, kind: ActivityKind, minutes: Int, effort: Int, date: Instant, split: Map<Attribute, Double>,
                    clock: RuleClock): LogPreview {
            val id = "previa"
            var xp = 0
            val grows = mutableListOf<Stage>()
            // Atividade nova: vai para o principal (e para as ligas marcadas, quando o Android postar)
            for ((o, share) in roster.shares(emptySet(), roster.mainID)) {
                val new = ActivityRecord(id, kind, date, minutes, effort, split, share)
                val current = roster.records[o].orEmpty()
                val before = SnapshotRules.snapshot(current, clock)
                val after = SnapshotRules.snapshot(current.filter { it.id != id } + new, clock)
                xp = maxOf(xp, after.xpByActivity[id] ?: 0)
                if (after.stage > before.stage) grows += before.stage
            }
            return LogPreview(xp, grows, split, Game.xp(kind, minutes, effort))
        }
    }
}
