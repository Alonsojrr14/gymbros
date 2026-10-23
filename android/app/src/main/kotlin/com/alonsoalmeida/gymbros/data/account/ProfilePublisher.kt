package com.alonsoalmeida.gymbros.data.account

import com.alonsoalmeida.gymbros.domain.profile.ContentFilter
import com.alonsoalmeida.gymbros.domain.profile.PublicNumbers
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.SetOptions
import kotlinx.coroutines.tasks.await
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put

/**
 * Perfil público (`profiles/{uid}`) acompanhando o que você muda no Android, como o iPhone publica
 * (FirebaseBackend.swift `publish`, PublicProfile.mine): nome, @usuário e bio passam pelo filtro de palavras; o que você
 * escondeu sai do ar na hora. Os números (regra simples) são publicados daqui; as conquistas continuam as que o iPhone
 * publicou (o Android ainda não calcula todas). Só mexe num perfil que já existe: quem cria (com a reserva do código) é
 * o FriendsViewModel. As regras exigem o código reservado por você (`codeIsMine`), que o merge preserva.
 */
class ProfilePublisher(private val db: FirebaseFirestore = FirebaseFirestore.getInstance()) {
    suspend fun publish(name: String, username: String, bio: String, numbers: PublicNumbers?, showAchievements: Boolean) {
        val me = FirebaseAuth.getInstance().currentUser?.uid ?: return
        val ref = db.collection("profiles").document(me)
        val doc = ref.get().await()
        if (!doc.exists()) return
        val old = doc.getString("public")?.let { runCatching { Json.parseToJsonElement(it).jsonObject }.getOrNull() } ?: JsonObject(emptyMap())
        val extra = LinkedHashMap<String, JsonElement>(old)
        if (numbers != null) {
            extra["stats"] = buildJsonObject { put("checkIns", numbers.checkIns); put("activeDays", numbers.activeDays); put("leagues", numbers.leagues) }
        } else extra.remove("stats")
        if (!showAchievements) extra.remove("achievements")
        val text = Json.encodeToString(JsonElement.serializer(), JsonObject(extra))
        val fields = mapOf("name" to ContentFilter.publishable(name), "username" to ContentFilter.publishable(username),
                           "bio" to ContentFilter.publishable(bio), "public" to text)
        if (fields.all { (k, v) -> doc.getString(k) == v }) return
        ref.set(fields, SetOptions.merge()).await()
    }

    /**
     * Foto do perfil para os outros (ProfilePhotos.publish): a miniatura de 160 px em `avatars/{uid}` e, por último, a
     * versão dela no perfil. Escondida ("Foto do perfil" desligada) ou sem foto: tira do ar. Só se a versão mudou.
     */
    suspend fun publishAvatar(photo: ByteArray?, show: Boolean) {
        val me = FirebaseAuth.getInstance().currentUser?.uid ?: return
        val profile = db.collection("profiles").document(me)
        val doc = profile.get().await()
        if (!doc.exists()) return
        val thumb = if (show) photo?.let(::thumbnail) else null
        val version = thumb?.let(::stableHash).orEmpty()
        if ((doc.getString("avatarVersion") ?: "") == version) return
        val ref = db.collection("avatars").document(me)
        if (thumb != null) ref.set(mapOf("data" to com.google.firebase.firestore.Blob.fromBytes(thumb),
                                         "updatedAt" to com.google.firebase.firestore.FieldValue.serverTimestamp())).await()
        else ref.delete().await()
        profile.set(mapOf("avatarVersion" to version), SetOptions.merge()).await()
    }

    companion object {
        /** Lado maior da miniatura (ProfilePhotos.side) */
        const val SIDE = 160

        /** 160 px no lado maior, JPEG 75 % (~10 KB; as regras aceitam até 150 KB) */
        fun thumbnail(jpeg: ByteArray): ByteArray? {
            val img = android.graphics.BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size) ?: return null
            val scale = minOf(1f, SIDE.toFloat() / maxOf(img.width, img.height))
            val out = android.graphics.Bitmap.createScaledBitmap(img, maxOf(1, (img.width * scale).toInt()), maxOf(1, (img.height * scale).toInt()), true)
            return java.io.ByteArrayOutputStream().also { out.compress(android.graphics.Bitmap.CompressFormat.JPEG, 75, it) }.toByteArray()
        }

        /** Resumo estável entre aparelhos (djb2 de 64 bits, igual ao `stableHash` do iOS) */
        fun stableHash(data: ByteArray): String {
            var h = 5381uL
            for (b in data) h = h * 33uL + b.toUByte().toULong()
            return h.toString(16)
        }

        /** Foto do perfil quadrada de 512 px, JPEG 80 % (`avatarPhoto` do iOS) */
        fun avatarPhoto(data: ByteArray): ByteArray? {
            // Lê já reduzida (foto de câmera tem dezenas de MB em memória), mantendo o lado menor acima de 512
            val bounds = android.graphics.BitmapFactory.Options().apply { inJustDecodeBounds = true }
            android.graphics.BitmapFactory.decodeByteArray(data, 0, data.size, bounds)
            var sample = 1
            while (minOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= 512) sample *= 2
            val opts = android.graphics.BitmapFactory.Options().apply { inSampleSize = sample }
            val img = android.graphics.BitmapFactory.decodeByteArray(data, 0, data.size, opts) ?: return null
            val side = minOf(img.width, img.height)
            val crop = android.graphics.Bitmap.createBitmap(img, (img.width - side) / 2, (img.height - side) / 2, side, side)
            val out = android.graphics.Bitmap.createScaledBitmap(crop, 512, 512, true)
            return java.io.ByteArrayOutputStream().also { out.compress(android.graphics.Bitmap.CompressFormat.JPEG, 80, it) }.toByteArray()
        }
    }
}
