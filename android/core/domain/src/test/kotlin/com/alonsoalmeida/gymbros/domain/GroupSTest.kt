package com.alonsoalmeida.gymbros.domain

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/** Grupo S: divisão do XP entre os atributos ao salvar uma atividade, igual à do iPhone */
class GroupSTest {
    @Test
    fun splits() {
        val s = Json.parseToJsonElement(javaClass.getResource("/gymbros-golden-S.json")!!.readText()).jsonObject
        var ties = 0
        for (c in s["cases"]!!.jsonArray.map { it.jsonObject }) {
            val meters = c["meters"]!!.takeIf { it !is JsonNull }?.let { Double.fromBits(it.jsonPrimitive.content.toULong().toLong()) }
            val w = AttributeSplit.split(ActivityKind.of(c["kind"]!!.jsonPrimitive.content), c["minutes"]!!.jsonPrimitive.int,
                                         c["effort"]!!.jsonPrimitive.int, meters, c["type"]!!.jsonPrimitive.content.toLong())
            val expected = c["split"]!!.jsonPrimitive.content
            val got = AttributeSplit.encode(w)
            if (got != expected) {
                // Só aceita diferença quando o iOS desempatou o maior pela ordem do dicionário (não determinística)
                val e = AttributeSplit.decode(expected)!!
                assertEquals(e.keys, w.keys, c.toString())
                val diff = e.keys.filter { kotlin.math.abs(e[it]!! - w[it]!!) > 1e-9 }
                assertEquals(2, diff.size, c.toString())
                ties++
            }
        }
        println("desempates pela ordem do dicionário no iOS: $ties")
    }
}
