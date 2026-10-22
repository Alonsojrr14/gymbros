package com.alonsoalmeida.gymbros.data

import android.content.Context
import com.alonsoalmeida.gymbros.domain.backup.AccountCopy
import com.alonsoalmeida.gymbros.domain.backup.BackupDto
import com.alonsoalmeida.gymbros.domain.backup.ChunkCodec
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.Source
import com.google.firebase.firestore.firestoreSettings
import com.google.firebase.firestore.memoryCacheSettings
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Cópia da conta no Firestore (`accounts/{uid}` + `chunks/{n}`), o mesmo formato que o iOS grava
 * (FirebaseGame.swift `FirebaseAccountDataBackend`). Por enquanto só leitura: o Android grava a cópia depois da
 * mesclagem por UUID (IOS-08), para nunca sobrescrever o que o iPhone mudou.
 *
 * Segurança: as regras só deixam o dono ler `accounts/{uid}`; aqui só se pede o uid de quem está logado. A cópia em
 * disco fica na área privada do app, fora do backup do Android (`noBackupFilesDir`), e é apagada ao sair da conta.
 * O cache do Firestore fica só na memória, para não sobrar dado de uma conta no aparelho depois de sair.
 */
class AccountCopyRepository(context: Context) {
    private val dir = File(context.noBackupFilesDir, "conta")
    private val db: FirebaseFirestore = FirebaseFirestore.getInstance().apply {
        firestoreSettings = firestoreSettings { setLocalCacheSettings(memoryCacheSettings {}) }
    }

    private fun copyFile(uid: String) = File(dir, "$uid.json")
    private fun hashFile(uid: String) = File(dir, "$uid.hash")

    /** A cópia mais nova: a da nuvem se mudou desde a última vez, senão a guardada aqui. Sem cópia (conta nova): null */
    suspend fun load(uid: String): BackupDto? = withContext(Dispatchers.IO) {
        require(uid.isNotEmpty() && !uid.contains('/') && !uid.contains("..")) { "conta inválida" }
        val cached = copyFile(uid).takeIf { it.exists() }
        val meta = try {
            db.collection("accounts").document(uid).get(Source.SERVER).await()
        } catch (e: Exception) {
            // Sem internet: abre com a última cópia baixada, se houver
            return@withContext cached?.let { AccountCopy.decode(it.readBytes()) } ?: throw e
        }
        val count = (meta.getLong("chunks") ?: 0L).toInt()
        if (!meta.exists() || count <= 0) return@withContext null
        val hash = meta.getString("hash")
        if (cached != null && hash != null && hashFile(uid).takeIf { it.exists() }?.readText() == hash) {
            return@withContext AccountCopy.decode(cached.readBytes())
        }
        val parts = (0 until count).map { n ->
            val doc = db.collection("accounts").document(uid).collection("chunks").document(n.toString()).get(Source.SERVER).await()
            doc.getBlob("data")?.toBytes() ?: error("cópia da conta incompleta")
        }
        val raw = ChunkCodec.inflate(ChunkCodec.join(parts))
        val copy = AccountCopy.decode(raw)
        dir.mkdirs()
        copyFile(uid).writeBytes(raw)
        hash?.let { hashFile(uid).writeText(it) }
        copy
    }

    /** Sair da conta: nada dela fica no aparelho */
    fun clear() {
        dir.deleteRecursively()
    }
}
