package com.alonsoalmeida.gymbros.data.account

import android.content.Context
import com.alonsoalmeida.gymbros.data.AccountCopyRepository
import com.alonsoalmeida.gymbros.data.CopyState
import com.google.firebase.FirebaseNetworkException
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.FirebaseAuthRecentLoginRequiredException
import com.google.firebase.firestore.DocumentReference
import com.google.firebase.firestore.FirebaseFirestore
import kotlinx.coroutines.tasks.await
import java.io.File

class DeleteAccountException(message: String) : Exception(message)

/**
 * Excluir a conta, na ordem do iOS (AccountSync.deleteAccount + FirebaseBackend.swift `checkCanDelete`/`deleteAccount`):
 *  1. só com login recente: sem isso o cadastro não sai e os dados não podem sair antes dele;
 *  2. a cópia da conta (`accounts/{uid}` e pedaços);
 *  3. o que você criou no Firestore (lugar nas ligas, check-ins, recados, pedidos, amizades, bloqueios, denúncias,
 *     rotinas publicadas, comentários, perfil, treino ao vivo, bros para troca, foto, reservas do código de amigo);
 *  4. por último o cadastro no Firebase Auth. Mensagens, X1 e trocas ficam com a outra pessoa (são dela também).
 * Se o cadastro continuar existindo, a cópia volta para a nuvem. Tudo só com o uid de quem está logado.
 */
class AccountDeletion(private val context: Context, private val copies: AccountCopyRepository,
                      private val db: FirebaseFirestore = FirebaseFirestore.getInstance()) {
    private val auth = FirebaseAuth.getInstance()

    /** O Firebase só exclui com login de até 5 min: compara dois horários do servidor (login e emissão do token novo) */
    suspend fun checkCanDelete() {
        val user = auth.currentUser ?: return
        val token = runCatching { user.getIdToken(true).await() }.getOrElse { throw DeleteAccountException(OFFLINE) }
        if (token.issuedAtTimestamp - token.authTimestamp > 3 * 60) throw DeleteAccountException(RECENT_LOGIN)
    }

    suspend fun delete(friendCode: String?) {
        val user = auth.currentUser ?: return
        val me = user.uid
        checkCanDelete()
        val saved = (copies.state.value as? CopyState.Ready)?.copy
        // Sobe o que falta e para a sincronização (nada volta para a nuvem no meio da exclusão); sem conseguir, nada sai
        runCatching { copies.signOut() }.onFailure {
            throw DeleteAccountException("Não deu para salvar seus dados antes de excluir. Confira a internet e tente de novo.")
        }
        try {
            val meta = db.collection("accounts").document(me)
            val count = (runCatching { meta.get().await().getLong("chunks") }.getOrNull() ?: 0L).toInt()
            delete((0 until count).map { meta.collection("chunks").document(it.toString()) } + meta)

            val refs = mutableListOf<DocumentReference>()
            for (c in listOf("members", "checkIns", "messages", "joinRequests")) {
                refs += db.collection(c).whereEqualTo("user", me).get().await().documents.map { it.reference }
            }
            refs += db.collection("friendLinks").whereEqualTo("from", me).get().await().documents.map { it.reference }
            for (c in listOf("blocks", "reports", "routines", "comments")) {
                refs += db.collection(c).whereEqualTo("user", me).get().await().documents.map { it.reference }
            }
            refs += listOf(db.collection("profiles").document(me), db.collection("live").document(me),
                           db.collection("tradeBros").document(me), db.collection("avatars").document(me))
            // Reservas do código de amigo: as da conta e a do perfil publicado, só as que existem e são suas
            val published = runCatching { db.collection("profiles").document(me).get().await().getString("friendCode") }.getOrNull()
            for (code in setOfNotNull(friendCode, published).filter { it.isNotEmpty() }) {
                val r = db.collection("friendCodes").document(code)
                if (runCatching { r.get().await().getString("user") }.getOrNull() == me) refs += r
            }
            delete(refs)
            user.delete().await()
        } catch (e: Exception) {
            // A conta continua: a cópia volta para o aparelho e para a nuvem
            if (auth.currentUser != null) {
                copies.start(me)
                if (saved != null) runCatching { copies.edit { saved } }
            }
            throw DeleteAccountException(when (e) {
                is DeleteAccountException -> e.message ?: OFFLINE
                is FirebaseAuthRecentLoginRequiredException -> RECENT_LOGIN
                is FirebaseNetworkException -> OFFLINE
                else -> "Confira a internet e tente de novo."
            })
        }
        wipeLocal()
        auth.signOut()
    }

    private suspend fun delete(refs: List<DocumentReference>) {
        for (chunk in refs.chunked(450)) {
            val batch = db.batch()
            chunk.forEach { batch.delete(it) }
            batch.commit().await()
        }
    }

    /** Tudo da conta no aparelho: cópia, fotos de outras pessoas, ajustes do Health Connect e fotos de medidas */
    private fun wipeLocal() {
        File(context.noBackupFilesDir, "conta").deleteRecursively()
        File(context.noBackupFilesDir, "medidas").deleteRecursively()
        File(context.cacheDir, "avatars").deleteRecursively()
        context.getSharedPreferences(HEALTH_PREFS, Context.MODE_PRIVATE).edit().clear().apply()
    }

    companion object {
        const val HEALTH_PREFS = "gymbros_health"
        const val RECENT_LOGIN = "Por segurança, saia e entre de novo antes de excluir a conta."
        const val OFFLINE = "Sem conexão. Tente de novo."
    }
}
