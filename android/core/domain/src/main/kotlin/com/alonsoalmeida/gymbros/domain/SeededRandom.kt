package com.alonsoalmeida.gymbros.domain

/**
 * Sorteio determinístico, igual em todo aparelho: FNV-1a 64 sobre os bytes UTF-8 da semente e um LCG de 64 bits.
 * Fonte: GymBros/Leagues/Leagues.swift (`struct SeededRandom`). Aritmética com `ULong` (o `&*` e `&+` do Swift).
 */
class SeededRandom(seed: String) {
    var state: ULong
        private set

    init {
        var h = 0xcbf29ce484222325uL
        for (b in seed.encodeToByteArray()) h = (h xor (b.toUByte().toULong())) * 0x100000001b3uL
        state = h
    }

    fun next(): Double {
        state = state * 6364136223846793005uL + 1442695040888963407uL
        return (state shr 11).toDouble() / (1uL shl 53).toDouble()
    }
}
