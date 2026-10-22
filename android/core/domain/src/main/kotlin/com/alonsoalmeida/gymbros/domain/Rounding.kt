package com.alonsoalmeida.gymbros.domain

import kotlin.math.floor

/**
 * Arredonda como o `.rounded()` do Swift: metade para longe do zero (2,5 → 3; −2,5 → −3).
 * `kotlin.math.round` usa metade para o par e `roundToInt` leva a metade para +∞: nenhum dos dois serve (ADR-006).
 */
fun roundHalfAwayFromZero(x: Double): Double {
    if (x.isNaN() || x.isInfinite()) return x
    val a = kotlin.math.abs(x)
    val f = floor(a)
    val r = if (a - f >= 0.5) f + 1 else f
    return if (x < 0) -r else r
}

/** `Int(x.rounded())` do Swift */
fun roundToIntSwift(x: Double): Int = roundHalfAwayFromZero(x).toInt()
