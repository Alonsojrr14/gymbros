package com.alonsoalmeida.gymbros.ui.leagues

import android.content.Context
import android.media.ExifInterface
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.platform.LocalContext
import com.alonsoalmeida.gymbros.domain.leagues.PhotoProof
import com.alonsoalmeida.gymbros.ui.components.Photos
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Instant
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter

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
    // Câmera do sistema sem arquivo: o Android devolve uma foto pequena. A hora é a do toque, como a câmera do app no iPhone.
    val camera = rememberLauncherForActivityResult(ActivityResultContracts.TakePicturePreview()) { bmp ->
        if (bmp != null) onPicked(PickedPhoto(Photos.compressed(bmp), PhotoProof(PhotoProof.CAMERA, Instant.now()), pose))
    }
    val req = PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)
    return PhotoPickers({ gallery.launch(req) }, { runCatching { camera.launch(null) } }, { many.launch(req) })
}

private fun read(context: Context, uri: Uri): ByteArray? = runCatching { context.contentResolver.openInputStream(uri)?.use { it.readBytes() } }.getOrNull()

/** A hora e o local saem do arquivo original (a versão reduzida não tem EXIF), como PhotoProof.library */
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
