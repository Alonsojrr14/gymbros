package com.alonsoalmeida.gymbros.data.train

import android.content.Context
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Imagens, vídeos e instruções do wger (wger.de), sob CC BY-SA 3.0/4.0 ou CC0 (Exercises/Wger.swift). A licença exige
 * crédito a cada item: autor, licença e origem aparecem junto do conteúdo e em Créditos. Dados: assets/wger.json (o
 * mesmo do iPhone) e as ilustrações em assets/wger.
 */
data class WgerCredit(val license: String, val licenseURL: String, val author: String) {
    val line: String get() = "$author · $license"
}

data class WgerMedia(val asset: String?, val source: String?, val url: String?, val credit: WgerCredit)

data class WgerEntry(val wger: Int, val url: String, val language: String, val steps: List<String>, val text: WgerCredit,
                     val images: List<WgerMedia>, val videos: List<WgerMedia>)

object WgerLibrary {
    @Volatile private var entries: Map<String, WgerEntry>? = null

    fun load(context: Context): Map<String, WgerEntry> {
        entries?.let { return it }
        val parsed = runCatching {
            val root = Json.parseToJsonElement(context.assets.open("wger.json").use { it.readBytes().decodeToString() }) as JsonObject
            (root["exercises"] as JsonObject).mapValues { (_, v) -> entry(v as JsonObject) }
        }.getOrDefault(emptyMap())
        entries = parsed
        return parsed
    }

    private fun str(o: JsonObject, k: String) = (o[k] as? JsonPrimitive)?.content
    private fun credit(o: JsonObject) = WgerCredit(str(o, "license").orEmpty(), str(o, "licenseURL").orEmpty(), str(o, "author").orEmpty())
    private fun media(o: JsonObject) = WgerMedia(str(o, "asset"), str(o, "source"), str(o, "url"), credit(o))

    private fun entry(o: JsonObject) = WgerEntry(
        (o["wger"] as? JsonPrimitive)?.content?.toIntOrNull() ?: 0, str(o, "url").orEmpty(), str(o, "language") ?: "pt",
        (o["steps"] as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.content }.orEmpty(), credit(o["text"] as? JsonObject ?: JsonObject(emptyMap())),
        (o["images"] as? JsonArray)?.mapNotNull { (it as? JsonObject)?.let(::media) }.orEmpty(),
        (o["videos"] as? JsonArray)?.mapNotNull { (it as? JsonObject)?.let(::media) }.orEmpty(),
    )

    fun entry(context: Context, id: String): WgerEntry? = load(context)[id]
    fun photoAssets(context: Context, id: String): List<String> = entry(context, id)?.images?.mapNotNull { it.asset }.orEmpty()

    /** Nome curto da origem de um link */
    fun sourceName(url: String): String = if (url.contains("everkinetic")) "Everkinetic" else if (url.contains("wikimedia")) "Commons" else "wger.de"

    /** Autores e licenças distintos, para a tela de créditos */
    fun allCredits(context: Context): List<Pair<WgerCredit, Int>> {
        val count = LinkedHashMap<WgerCredit, Int>()
        for (e in load(context).values) {
            for (m in e.images + e.videos) count[m.credit] = (count[m.credit] ?: 0) + 1
            if (e.steps.isNotEmpty()) count[e.text] = (count[e.text] ?: 0) + 1
        }
        return count.entries.sortedByDescending { it.value }.map { it.key to it.value }
    }
}
