package com.alonsoalmeida.gymbros.data

import android.content.Context
import com.alonsoalmeida.gymbros.domain.backup.BackupMerge
import com.alonsoalmeida.gymbros.domain.backup.ChunkCodec
import com.google.firebase.Timestamp
import com.google.firebase.firestore.Blob
import com.google.firebase.firestore.DocumentSnapshot
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.ListenerRegistration
import com.google.firebase.firestore.MetadataChanges
import com.google.firebase.firestore.Source
import com.google.firebase.firestore.firestoreSettings
import com.google.firebase.firestore.memoryCacheSettings
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.tasks.await
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.io.File
import java.security.MessageDigest
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Date

/** Estado da cópia da conta no aparelho */
sealed interface CopyState {
    data object Loading : CopyState
    data class Failed(val message: String) : CopyState
    /** `copy` nulo: a conta ainda não tem dados (conta nova) */
    data class Ready(val copy: JsonObject?) : CopyState
}

/**
 * Cópia da conta (`accounts/{uid}` + `chunks/{n}`), no mesmo formato e com o mesmo protocolo do iOS
 * (FirebaseGame.swift `FirebaseAccountDataBackend` e AccountSync.swift, IOS-08):
 *  · a cópia de trabalho é o JSON inteiro do `Backup` (campo que o Android ainda não conhece passa intacto);
 *  · a base é a última cópia em comum com a nuvem; mudou lá → mescla em três vias (`BackupMerge`, provado pelo vetor M);
 *  · o envio é uma transação que só grava se a nuvem ainda for a versão conhecida (`hash`).
 * Ao vivo: escuta `accounts/{uid}` e mescla assim que o outro aparelho sobe uma cópia nova.
 *
 * Segurança: as regras só deixam o dono ler e gravar `accounts/{uid}`; aqui só se usa o uid de quem está logado. Os
 * arquivos ficam na área privada do app, fora do backup do Android (`noBackupFilesDir`), e saem ao sair da conta.
 * O cache do Firestore fica só na memória.
 */
class AccountCopyRepository(context: Context) {
    private val root = File(context.noBackupFilesDir, "conta")
    /** Fotos de perfil de outras pessoas guardadas (ProfilePhotosRepository): saem junto ao sair da conta */
    private val avatars = File(context.cacheDir, "avatars")
    private val db: FirebaseFirestore = FirebaseFirestore.getInstance().apply {
        firestoreSettings = firestoreSettings { setLocalCacheSettings(memoryCacheSettings {}) }
    }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val lock = Mutex()
    private val json = Json { prettyPrint = false }

    private val _state = MutableStateFlow<CopyState>(CopyState.Loading)
    val state: StateFlow<CopyState> = _state.asStateFlow()

    private var uid: String? = null
    private var work: JsonObject? = null
    private var listener: ListenerRegistration? = null
    private var pendingUpload: Job? = null

    private fun dir(uid: String) = File(root, uid)
    private fun workFile(uid: String) = File(dir(uid), "trabalho.json")
    private fun baseFile(uid: String) = File(dir(uid), "base.json")
    private fun hashFile(uid: String) = File(dir(uid), "hash")
    private fun meta(uid: String) = db.collection("accounts").document(uid)
    private fun chunk(uid: String, n: Int) = meta(uid).collection("chunks").document(n.toString())

    private fun read(f: File): JsonObject? = f.takeIf { it.exists() }?.let { runCatching { Json.parseToJsonElement(it.readText()) as JsonObject }.getOrNull() }
    private fun write(f: File, o: JsonObject) {
        f.parentFile?.mkdirs()
        val tmp = File(f.parentFile, f.name + ".tmp")
        tmp.writeText(json.encodeToString(JsonElement.serializer(), o))
        tmp.renameTo(f)
    }

    /** Entrou (ou abriu o app logado): abre com o que está no aparelho e passa a escutar a nuvem */
    fun start(uid: String) {
        require(uid.isNotEmpty() && !uid.contains('/') && !uid.contains("..")) { "conta inválida" }
        if (this.uid == uid && listener != null) return
        stop()
        this.uid = uid
        work = read(workFile(uid))
        _state.value = if (work != null) CopyState.Ready(work) else CopyState.Loading
        listener = meta(uid).addSnapshotListener(MetadataChanges.EXCLUDE) { snap, error ->
            if (error != null) {
                if (work == null) _state.value = CopyState.Failed(message(error))
                return@addSnapshotListener
            }
            // Escrita deste aparelho ainda não confirmada: nada novo da nuvem
            if (snap == null || snap.metadata.hasPendingWrites()) return@addSnapshotListener
            scope.launch { runCatching { onRemote(uid, snap) }.onFailure { if (work == null) _state.value = CopyState.Failed(message(it)) } }
        }
    }

    private fun message(e: Throwable): String = when ((e as? FirebaseFirestoreException)?.code) {
        FirebaseFirestoreException.Code.PERMISSION_DENIED -> "Sua sessão expirou. Saia e entre de novo."
        else -> "Confira a internet e tente de novo."
    }

    /** Tentar de novo depois de um erro ao abrir */
    fun retry() {
        val u = uid ?: return
        stop()
        start(u)
    }

    /** A cópia da nuvem mudou (ou é a primeira leitura): traz, mescla com a daqui e sobe a mesclagem se precisar */
    private suspend fun onRemote(uid: String, snap: DocumentSnapshot) = lock.withLock {
        if (this.uid != uid) return@withLock
        val count = (snap.getLong("chunks") ?: 0L).toInt()
        val hash = snap.getString("hash")
        val known = hashFile(uid).takeIf { it.exists() }?.readText()
        if (!snap.exists() || count <= 0) {
            // Conta sem dados na nuvem: o que houver aqui sobe
            _state.value = CopyState.Ready(work)
            if (work != null) scheduleUpload(0)
            return@withLock
        }
        if (hash != null && hash == known && work != null) {
            _state.value = CopyState.Ready(work)
            // Mudança feita aqui que não chegou a subir (ex.: em segundo plano, sem rede): sobe agora
            val base = read(baseFile(uid))
            if (base != null && digest(work!!) != digest(base)) scheduleUpload(0)
            return@withLock
        }
        val parts = (0 until count).map { n ->
            chunk(uid, n).get(Source.SERVER).await().getBlob("data")?.toBytes() ?: error("cópia da conta incompleta")
        }
        val remote = Json.parseToJsonElement(ChunkCodec.inflate(ChunkCodec.join(parts)).decodeToString()) as JsonObject
        val local = work
        val merged = if (local == null) remote else BackupMerge.merge(local, remote, read(baseFile(uid))).backup
        work = merged
        write(workFile(uid), merged)
        write(baseFile(uid), remote)
        hash?.let { hashFile(uid).writeText(it) }
        _state.value = CopyState.Ready(merged)
        // Tinha mudança só daqui: sobe a mesclagem
        if (digest(merged) != digest(remote)) scheduleUpload(0)
    }

    /** Muda a cópia de trabalho (registrar atividade…): aparece na hora aqui e sobe logo depois */
    suspend fun edit(change: (JsonObject?) -> JsonObject) {
        lock.withLock {
            val u = uid ?: return
            val next = change(work)
            work = next
            write(workFile(u), next)
            _state.value = CopyState.Ready(next)
        }
        scheduleUpload(1_500)
    }

    /** Sobe já o que mudou (trabalho em segundo plano, que não pode esperar o atraso normal) */
    suspend fun flush() {
        pendingUpload?.cancel()
        runCatching { upload() }
    }

    private fun scheduleUpload(delayMs: Long) {
        pendingUpload?.cancel()
        pendingUpload = scope.launch {
            delay(delayMs)
            runCatching { upload() }
        }
    }

    /** Sobe a cópia de trabalho se a nuvem ainda for a versão conhecida; se outro aparelho subiu antes, a escuta mescla */
    private suspend fun upload() = lock.withLock {
        val u = uid ?: return@withLock
        val copy = work ?: return@withLock
        val stamped = JsonObject(copy + ("exportedAt" to JsonPrimitive(DateTimeFormatter.ISO_INSTANT.format(Instant.now().truncatedTo(ChronoUnit.SECONDS)))))
        val hash = digest(stamped)
        val expected = hashFile(u).takeIf { it.exists() }?.readText()
        if (hash == expected) return@withLock
        val raw = json.encodeToString(JsonElement.serializer(), stamped).encodeToByteArray()
        val parts = ChunkCodec.split(ChunkCodec.deflate(raw))
        val metaRef = meta(u)
        val fields = hashMapOf<String, Any>(
            "user" to u, "chunks" to parts.size, "bytes" to raw.size, "hash" to hash,
            "savedAt" to Timestamp(Date.from(Instant.parse((stamped["exportedAt"] as JsonPrimitive).content))),
            "format" to 2, "updatedAt" to FieldValue.serverTimestamp(),
        )
        val ok = db.runTransaction { txn ->
            val current = txn.get(metaRef)
            val remote = current.getString("hash")
            if (remote != null && remote != expected) return@runTransaction false
            val old = (current.getLong("chunks") ?: 0L).toInt()
            parts.forEachIndexed { n, part -> txn.set(chunk(u, n), mapOf("data" to Blob.fromBytes(part))) }
            for (n in parts.size until minOf(maxOf(old, parts.size), 64)) txn.delete(chunk(u, n))
            txn.set(metaRef, fields)
            true
        }.await()
        if (!ok) return@withLock
        work = stamped
        write(workFile(u), stamped)
        write(baseFile(u), stamped)
        hashFile(u).writeText(hash)
    }

    /** Hash do conteúdo, sem a data de exportação (muda sempre) */
    private fun digest(o: JsonObject): String {
        val text = BackupMerge.canonical(JsonObject(o - "exportedAt"))
        return MessageDigest.getInstance("SHA-256").digest(text.encodeToByteArray()).joinToString("") { "%02x".format(it) }
    }

    private fun stop() {
        listener?.remove()
        listener = null
        pendingUpload?.cancel()
        work = null
        _state.value = CopyState.Loading
    }

    /** Sair: sobe o que falta e só então tira a conta do aparelho. Sem conseguir subir, nada sai (igual ao iOS) */
    suspend fun signOut() {
        pendingUpload?.cancel()
        upload()
        stop()
        uid = null
        root.deleteRecursively()
        avatars.deleteRecursively()
    }
}
