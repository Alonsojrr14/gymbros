package com.alonsoalmeida.gymbros.data

import com.alonsoalmeida.gymbros.domain.MonsterForm
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FieldPath
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.tasks.await
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import java.util.Date

/** Amigo como o servidor devolve (Friends.swift `RemoteFriend`) */
data class RemoteFriend(val id: String, val name: String, val formID: String, val code: String) {
    val form: MonsterForm get() = MonsterForm.byID(formID) ?: MonsterForm.EGG
}

data class FriendsState(val friends: List<RemoteFriend> = emptyList(), val incoming: List<RemoteFriend> = emptyList())

/** Perfil público (PublicProfile.swift): só o que a pessoa deixou aparecer */
@Serializable
data class PublicExtra(val bro: PublicBro? = null, val stats: PublicStats? = null, val achievements: List<Badge>? = null,
                       val bros: com.alonsoalmeida.gymbros.domain.profile.PublicBros? = null)

@Serializable
data class PublicBro(val name: String, val formID: String, val level: Int, val progress: Double) {
    val form: MonsterForm get() = MonsterForm.byID(formID) ?: MonsterForm.EGG
}

@Serializable
data class PublicStats(val checkIns: Int, val activeDays: Int, val leagues: Int)

@Serializable
data class Badge(val title: String, val symbol: String)

data class PublicProfile(val id: String, val name: String, val username: String, val bio: String, val extra: PublicExtra)

/** Membro de uma liga (para "Talvez você conheça") */
data class LeagueMember(val id: String, val name: String, val formID: String) {
    val form: MonsterForm get() = MonsterForm.byID(formID) ?: MonsterForm.EGG
}

enum class FriendError(val message: String) {
    NOT_FOUND("Ninguém com esse código."),
    YOURSELF("Esse é o seu código 🙂"),
    ALREADY("Vocês já são amigos."),
    FORBIDDEN("Sua conta não tem permissão para isso."),
}

class FriendException(val error: FriendError) : Exception(error.message)

/**
 * Amigos no Firestore, igual ao iOS (FirebaseBackend.swift `FirebaseFriendsBackend`, FirebaseGame.swift moderação e roles).
 * Amizade = `friendLinks/{a}->{b}` nos dois sentidos. As regras do Firestore são a autoridade: cada um só grava o
 * próprio vínculo e o próprio bloqueio; papéis (`roles/{uid}`) só são lidos aqui, nunca gravados.
 */
class FriendsRepository(private val db: FirebaseFirestore = FirebaseFirestore.getInstance()) {
    private val json = Json { ignoreUnknownKeys = true }
    private fun me(): String = FirebaseAuth.getInstance().currentUser?.uid ?: throw IllegalStateException("sem sessão")

    private fun friend(id: String, d: Map<String, Any?>) =
        RemoteFriend(id, d["name"] as? String ?: "", d["broFormID"] as? String ?: MonsterForm.EGG.id, d["friendCode"] as? String ?: "")

    /** Perfis por id, em lotes de 10 (limite do `in` do Firestore) */
    private suspend fun profiles(ids: List<String>): List<RemoteFriend> {
        val byID = HashMap<String, Map<String, Any?>>()
        for (chunk in ids.chunked(10)) {
            db.collection("profiles").whereIn(FieldPath.documentId(), chunk).get().await().documents.forEach { byID[it.id] = it.data.orEmpty() }
        }
        return ids.mapNotNull { id -> byID[id]?.let { friend(id, it) } }
    }

    /** Papéis da conta: sem atribuição, USER; atribuição vazia, conta desativada (nenhuma permissão) */
    suspend fun roles(): Set<String> {
        val doc = db.collection("roles").document(me()).get().await()
        if (!doc.exists()) return setOf("USER")
        @Suppress("UNCHECKED_CAST")
        return ((doc.get("roles") as? List<String>) ?: emptyList()).toSet()
    }

    suspend fun fetch(declined: Set<String>, blocked: Set<String>): FriendsState = coroutineScope {
        val me = me()
        val out = async { db.collection("friendLinks").whereEqualTo("from", me).get().await() }
        val inc = async { db.collection("friendLinks").whereEqualTo("to", me).get().await() }
        val sent = out.await().documents.mapNotNull { it.getString("to") }.toSet()
        val received = inc.await().documents.mapNotNull { it.getString("from") }.toSet()
        FriendsState(
            friends = profiles((sent intersect received).sorted()).filter { it.id !in blocked },
            incoming = profiles((received - sent - declined).sorted()).filter { it.id !in blocked },
        )
    }

    suspend fun addByCode(code: String): RemoteFriend {
        // O código reservado vale; a busca no perfil só para códigos de antes da reserva
        // Regras antigas no servidor (sem `friendCodes`) negam a leitura: segue pela busca no perfil
        val reserved = runCatching { db.collection("friendCodes").document(code).get().await().getString("user") }.getOrNull()
        if (reserved != null) {
            if (!db.collection("profiles").document(reserved).get().await().exists()) throw FriendException(FriendError.NOT_FOUND)
            return addById(reserved)
        }
        val d = db.collection("profiles").whereEqualTo("friendCode", code).limit(1).get().await().documents.firstOrNull()
            ?: throw FriendException(FriendError.NOT_FOUND)
        return addById(d.id)
    }

    suspend fun addById(id: String): RemoteFriend {
        val me = me()
        if (id == me) throw FriendException(FriendError.YOURSELF)
        db.collection("friendLinks").document("$me->$id").set(mapOf("from" to me, "to" to id)).await()
        return profiles(listOf(id)).firstOrNull() ?: RemoteFriend(id, "", MonsterForm.EGG.id, "")
    }

    suspend fun remove(id: String) {
        db.collection("friendLinks").document("${me()}->$id").delete().await()
    }

    suspend fun profile(id: String): PublicProfile {
        val d = db.collection("profiles").document(id).get().await()
        var extra = (d.getString("public"))?.let { runCatching { json.decodeFromString(PublicExtra.serializer(), it) }.getOrNull() } ?: PublicExtra()
        // A pessoa escondeu os treinos de você: sem números (nem a atividade favorita, que sai dos posts)
        @Suppress("UNCHECKED_CAST")
        if ((d.get("hiddenFrom") as? List<String>)?.contains(me()) == true) extra = extra.copy(stats = null, bros = extra.bros?.copy(favorite = null))
        return PublicProfile(id, d.getString("name") ?: "", d.getString("username") ?: "", d.getString("bio") ?: "", extra)
    }

    /** Quem você bloqueou (`blocks/{você}->{pessoa}`) */
    suspend fun blocked(): Set<String> =
        db.collection("blocks").whereEqualTo("user", me()).get().await().documents.mapNotNull { it.getString("blocked") }.toSet()

    /** Bloqueio: as regras usam para impedir mensagens e X1; aqui também desfaz a amizade */
    suspend fun block(id: String, name: String) {
        val me = me()
        db.collection("blocks").document("$me->$id").set(mapOf("user" to me, "blocked" to id, "name" to name, "date" to Date())).await()
        runCatching { remove(id) }
    }

    /** Membros das suas ligas em andamento (pelo código da liga) */
    suspend fun members(leagueCodes: List<String>): Map<String, List<LeagueMember>> = coroutineScope {
        val me = me()
        leagueCodes.distinct().associateWith { code ->
            async {
                db.collection("members").whereEqualTo("league", code).get().await().documents.mapNotNull { d ->
                    val user = d.getString("user") ?: return@mapNotNull null
                    if (user == me) null else LeagueMember(user, d.getString("name") ?: "", d.getString("formID") ?: MonsterForm.EGG.id)
                }
            }
        }.mapValues { it.value.await() }
    }

    /**
     * Conta sem perfil publicado (nunca abriu o iPhone): reserva o código e publica o mínimo (nome e bro), para os
     * amigos te acharem. Perfil que já existe não é tocado: quem publica o completo é o iPhone (FS-AND-06).
     */
    suspend fun publishIfMissing(code: String, name: String, broFormID: String): Boolean {
        val me = me()
        val profile = db.collection("profiles").document(me)
        if (profile.get().await().exists()) return true
        val reservation = db.collection("friendCodes").document(code)
        val fields = mapOf("name" to name, "username" to "", "bio" to "", "friendCode" to code, "broFormID" to broFormID,
                           "hiddenFrom" to emptyList<String>())
        val owner = try {
            reservation.get().await().getString("user")
        } catch (e: Exception) {
            // Regras antigas no servidor (sem `friendCodes`): publica o perfil sem a reserva, como o iOS antes dela
            profile.set(fields).await()
            return true
        }
        if (owner != null && owner != me) return false
        val batch = db.batch()
        if (owner == null) batch.set(reservation, mapOf("user" to me, "createdAt" to FieldValue.serverTimestamp()))
        batch.set(profile, fields)
        batch.commit().await()
        return true
    }

    /**
     * Mantém o bro do seu perfil público em dia (forma, apelido, nível) e "Bros e atributos" (`bros`; nulo = escondido;
     * `updateBros` falso = deixa como está), como o iPhone faz ao publicar o perfil. Números e conquistas continuam os que o iPhone publicou. As regras exigem a reserva do
     * código (`friendCodes`); sem ela, reserva antes. Devolve o código em uso (outro, se o seu já era de alguém).
     */
    suspend fun publishBro(code: String, bro: PublicBro?, show: Boolean, bros: com.alonsoalmeida.gymbros.domain.profile.PublicBros?,
                           updateBros: Boolean): String {
        val me = me()
        val profile = db.collection("profiles").document(me)
        val current = profile.get().await()
        val publicJson = current.getString("public")?.let { runCatching { Json.parseToJsonElement(it).jsonObject }.getOrNull() }
            ?: kotlinx.serialization.json.JsonObject(emptyMap())
        val newPublic = kotlinx.serialization.json.JsonObject(LinkedHashMap(publicJson).apply {
            if (show && bro != null) put("bro", json.encodeToJsonElement(PublicBro.serializer(), bro)) else remove("bro")
            if (updateBros) {
                if (bros != null) put("bros", json.encodeToJsonElement(com.alonsoalmeida.gymbros.domain.profile.PublicBros.serializer(), bros)) else remove("bros")
            }
        })
        val text = Json.encodeToString(kotlinx.serialization.json.JsonElement.serializer(), newPublic)
        val formID = if (show) bro?.formID else null
        if (current.getString("broFormID") == formID && current.getString("public") == text && current.getString("friendCode") == code) return code
        var use = code
        repeat(3) {
            val reservation = db.collection("friendCodes").document(use)
            val owner = reservation.get().await().getString("user")
            if (owner != null && owner != me) { use = newCode(); return@repeat }
            val batch = db.batch()
            if (owner == null) batch.set(reservation, mapOf("user" to me, "createdAt" to FieldValue.serverTimestamp()))
            batch.set(profile, mapOf("friendCode" to use, "broFormID" to formID, "public" to text), com.google.firebase.firestore.SetOptions.merge())
            batch.commit().await()
            return use
        }
        throw IllegalStateException("código indisponível")
    }

    companion object {
        /** Código de amigo: 6 letras e números sem os que se confundem (League.newCode do iOS) */
        fun newCode(): String {
            val chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
            val rng = java.security.SecureRandom()
            return (1..6).map { chars[rng.nextInt(chars.length)] }.joinToString("")
        }
    }
}

/**
 * Fotos de perfil que os outros veem, iguais às do iPhone (ProfilePhotos.swift): a miniatura (160 px) em `avatars/{uid}` e a
 * versão dela (`avatarVersion`) no perfil público. A sua só sobe com "Foto do perfil" ligada (`publicPhoto`, padrão sim).
 *
 * Para não gastar o limite do plano grátis: escuta só a versão (no perfil, poucos bytes), guarda cada foto no aparelho
 * (cache privado do app) e só baixa de novo quando a versão muda. Quem chama liga a escuta só com a tela aberta.
 */
class ProfilePhotosRepository(context: android.content.Context, private val db: FirebaseFirestore = FirebaseFirestore.getInstance()) {
    private val folder = java.io.File(context.cacheDir, "avatars")
    private var published: String? = null

    private fun clean(s: String) = s.filter { it.isLetterOrDigit() }
    private fun file(id: String, version: String) = java.io.File(folder, "${clean(id)}-${clean(version)}.jpg")

    /** Foto na versão pedida: do aparelho, ou baixa uma vez e guarda (apagando as versões antigas da pessoa) */
    suspend fun photo(id: String, version: String): ByteArray? {
        if (version.isEmpty()) return null
        val f = file(id, version)
        if (f.exists()) return f.readBytes()
        val data = runCatching { db.collection("avatars").document(id).get().await().getBlob("data")?.toBytes() }.getOrNull() ?: return null
        folder.mkdirs()
        folder.listFiles { x -> x.name.startsWith("${clean(id)}-") }?.forEach { it.delete() }
        f.writeBytes(data)
        return data
    }

    /** Escuta as versões das fotos (no perfil público): `onChange(id, versão)`, versão vazia = sem foto. Devolve como parar */
    fun watch(ids: List<String>, onChange: (String, String) -> Unit): () -> Unit {
        val regs = ids.distinct().filter { it.isNotEmpty() }.chunked(10).map { chunk ->
            db.collection("profiles").whereIn(FieldPath.documentId(), chunk).addSnapshotListener { snap, _ ->
                if (snap == null) return@addSnapshotListener
                val found = snap.documents.associate { it.id to (it.getString("avatarVersion") ?: "") }
                for (id in chunk) onChange(id, found[id] ?: "")
            }
        }
        return { regs.forEach { it.remove() } }
    }

    /** Outra conta: apaga as fotos guardadas */
    fun clear() { folder.deleteRecursively() }

    /** Publica (ou tira do ar) a sua foto se mudou: a miniatura e, por último, a versão no perfil */
    suspend fun publish(photo: ByteArray?, show: Boolean) {
        val me = FirebaseAuth.getInstance().currentUser?.uid ?: return
        val thumb = if (show) photo?.let(::thumbnail) else null
        val version = thumb?.let { stableHash(it) } ?: ""
        val fingerprint = "$me:$version"
        if (published == fingerprint) return
        val ref = db.collection("avatars").document(me)
        if (thumb != null) ref.set(mapOf("data" to com.google.firebase.firestore.Blob.fromBytes(thumb), "updatedAt" to FieldValue.serverTimestamp())).await()
        else ref.delete().await()
        db.collection("profiles").document(me).set(mapOf("avatarVersion" to version), com.google.firebase.firestore.SetOptions.merge()).await()
        published = fingerprint
    }

    /** Mesmo resumo do iPhone (djb2 em 64 bits, em hexadecimal) */
    private fun stableHash(b: ByteArray): String {
        var h = 5381UL
        for (x in b) h = h * 33UL + x.toUByte().toULong()
        return h.toString(16)
    }

    /** 160 px no lado maior, JPEG: ~10 KB */
    private fun thumbnail(data: ByteArray): ByteArray? {
        val bmp = android.graphics.BitmapFactory.decodeByteArray(data, 0, data.size) ?: return null
        val scale = minOf(1f, 160f / maxOf(bmp.width, bmp.height))
        val out = android.graphics.Bitmap.createScaledBitmap(bmp, (bmp.width * scale).toInt().coerceAtLeast(1), (bmp.height * scale).toInt().coerceAtLeast(1), true)
        val stream = java.io.ByteArrayOutputStream()
        out.compress(android.graphics.Bitmap.CompressFormat.JPEG, 75, stream)
        return stream.toByteArray()
    }
}
