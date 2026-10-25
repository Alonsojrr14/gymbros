package com.alonsoalmeida.gymbros.ui.leagues

import android.content.Context
import android.media.ExifInterface
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.FileProvider
import com.alonsoalmeida.gymbros.domain.leagues.PhotoProof
import com.alonsoalmeida.gymbros.ui.components.Photos
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.time.Instant
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.UUID

/** Foto escolhida, já reduzida, com a prova de onde veio (CheckInProof.swift `PhotoProofs`) */
data class PickedPhoto(val bytes: ByteArray, val proof: PhotoProof, val pose: String? = null)

/** Escolher da galeria e tirar na câmera. As fotos ficam no aparelho (cópia da conta), nunca no servidor. */
class PhotoPickers(val gallery: () -> Unit, val camera: () -> Unit, val galleryMany: () -> Unit)

@Composable
fun rememberPhotoPickers(pose: String? = null, onPicked: (PickedPhoto) -> Unit, onMany: (List<ByteArray>) -> Unit = {}): PhotoPickers {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val gallery = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) scope.launch {
            val p = withContext(Dispatchers.IO) { fromGallery(context, uri) }
            if (p != null) onPicked(p)
        }
    }
    val many = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(4)) { uris ->
        if (uris.isNotEmpty()) scope.launch {
            onMany(withContext(Dispatchers.IO) { uris.mapNotNull { u -> read(context, u)?.let(Photos::compressed) } })
        }
    }
    // Câmera do sistema gravando em arquivo (resolução cheia) no cache privado; depois de reduzida, o arquivo some.
    // A hora é a da foto tirada, como a câmera do app no iPhone.
    var shot by rememberSaveable { mutableStateOf<String?>(null) }
    val camera = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { ok ->
        val name = shot ?: return@rememberLauncherForActivityResult
        shot = null
        scope.launch {
            val bytes = withContext(Dispatchers.IO) {
                val file = CameraFiles.file(context, name)
                (if (ok) runCatching { file.readBytes() }.getOrNull()?.let(Photos::compressed) else null).also { file.delete() }
            }
            if (bytes != null) onPicked(PickedPhoto(bytes, PhotoProof(PhotoProof.CAMERA, Instant.now()), pose))
        }
    }
    val req = PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)
    return PhotoPickers({ gallery.launch(req) }, {
        runCatching {
            val (name, uri) = CameraFiles.new(context)
            shot = name
            camera.launch(uri)
        }
    }, { many.launch(req) })
}

/**
 * Arquivo da câmera em `cache/camera/`, entregue ao app da câmera por um FileProvider não exportado (só esse arquivo,
 * com permissão de escrita só durante a captura). Nada fica: o arquivo some depois de lido.
 */
object CameraFiles {
    private fun dir(context: Context) = File(context.cacheDir, "camera").apply { mkdirs() }

    fun file(context: Context, name: String) = File(dir(context), name)

    /** Arquivo novo e a URI para a câmera; sobras de uma captura interrompida (app fechado no meio) somem antes */
    fun new(context: Context): Pair<String, Uri> {
        dir(context).listFiles()?.forEach { it.delete() }
        val name = "${UUID.randomUUID()}.jpg"
        return name to FileProvider.getUriForFile(context, "${context.packageName}.camera", file(context, name))
    }
}

private fun read(context: Context, uri: Uri): ByteArray? = runCatching { context.contentResolver.openInputStream(uri)?.use { it.readBytes() } }.getOrNull()

/** A hora e o local saem do arquivo original (a versão reduzida, já de pé, não tem EXIF), como PhotoProof.library */
private fun fromGallery(context: Context, uri: Uri): PickedPhoto? {
    val raw = read(context, uri) ?: return null
    val small = Photos.compressed(raw) ?: return null
    val exif = runCatching { ExifInterface(raw.inputStream()) }.getOrNull()
    val date = exif?.let { e -> (e.getAttribute(ExifInterface.TAG_DATETIME_ORIGINAL) ?: e.getAttribute(ExifInterface.TAG_DATETIME_DIGITIZED)
        ?: e.getAttribute(ExifInterface.TAG_DATETIME))?.let { exifDate(it, e.getAttribute("OffsetTimeOriginal") ?: e.getAttribute("OffsetTime")) } }
    val hasLocation = exif?.getLatLong(FloatArray(2)) == true
    return PickedPhoto(small, PhotoProof(PhotoProof.LIBRARY, date, hasLocation))
}

/** "2026:10:21 07:42:10" com o fuso "-03:00" (sem fuso, o do aparelho) */
fun exifDate(s: String, offset: String?): Instant? = runCatching {
    val f = DateTimeFormatter.ofPattern("yyyy:MM:dd HH:mm:ss")
    if (offset != null) OffsetDateTime.parse(s.trim() + offset.trim(), DateTimeFormatter.ofPattern("yyyy:MM:dd HH:mm:ssXXX")).toInstant()
    else LocalDateTime.parse(s.trim(), f).atZone(ZoneId.systemDefault()).toInstant()
}.getOrNull()
