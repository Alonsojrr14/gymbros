package com.alonsoalmeida.gymbros.ui.friends

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.alonsoalmeida.gymbros.domain.home.HomeData
import com.alonsoalmeida.gymbros.domain.social.FriendQR
import com.alonsoalmeida.gymbros.ui.components.GMAction
import com.alonsoalmeida.gymbros.ui.components.GMActions
import com.alonsoalmeida.gymbros.ui.components.GMButton
import com.alonsoalmeida.gymbros.ui.components.GMButtonKind
import com.alonsoalmeida.gymbros.ui.components.GMCard
import com.alonsoalmeida.gymbros.ui.components.GMModal
import com.alonsoalmeida.gymbros.ui.components.GMSegmented
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import com.alonsoalmeida.gymbros.ui.theme.GMRadius
import com.alonsoalmeida.gymbros.ui.theme.GMType
import com.google.zxing.BarcodeFormat
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.EncodeHintType
import com.google.zxing.RGBLuminanceSource
import com.google.zxing.common.HybridBinarizer
import com.google.zxing.qrcode.QRCodeReader
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel

/** QR do link (correção M, como o `CIFilter.qrCodeGenerator` do iOS), um pixel por módulo: desenhado sem suavizar */
private fun qrBitmap(text: String): Bitmap? = runCatching {
    val m = QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, 0, 0, mapOf(EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.M, EncodeHintType.MARGIN to 0))
    val px = IntArray(m.width * m.height) { i -> if (m.get(i % m.width, i / m.width)) android.graphics.Color.BLACK else android.graphics.Color.WHITE }
    Bitmap.createBitmap(px, m.width, m.height, Bitmap.Config.ARGB_8888)
}.getOrNull()

/** Lê o QR de uma foto da galeria (reduzida a 1600 px para não pesar na memória) */
private fun readQR(context: android.content.Context, uri: Uri): String? = runCatching {
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
    var sample = 1
    while (maxOf(bounds.outWidth, bounds.outHeight) / sample > 1600) sample *= 2
    val bmp = context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample }) }
        ?: return null
    val px = IntArray(bmp.width * bmp.height)
    bmp.getPixels(px, 0, bmp.width, 0, 0, bmp.width, bmp.height)
    QRCodeReader().decode(BinaryBitmap(HybridBinarizer(RGBLuminanceSource(bmp.width, bmp.height, px))), mapOf(DecodeHintType.TRY_HARDER to true)).text
}.getOrNull()

/**
 * Mostrar o QR (para quem está do lado) e ler o QR de outra pessoa (SocialExtras.swift `FriendQRView`). Ler: a câmera do
 * próprio Android abre o link `gymbros://amigo/…` (o app pergunta antes de adicionar), ou uma foto do QR na galeria
 * (seletor de fotos do sistema, sem pedir permissão de câmera nem de arquivos).
 */
@Composable
fun FriendQRModal(visible: Boolean, myCode: String, onDismiss: () -> Unit, add: (String) -> Unit) {
    if (!visible) return
    var scanning by remember { mutableStateOf(false) }
    var note by remember { mutableStateOf<String?>(null) }
    val context = LocalContext.current
    val pick = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        val code = readQR(context, uri)?.let(FriendQR::code)
        when {
            code == null -> note = "Não achei um QR do GymBros nessa foto."
            code == myCode -> note = "Esse é o seu código 🙂"
            else -> { onDismiss(); add(code) }
        }
    }
    GMModal(true, "QR do amigo", onDismiss) {
        GMSegmented(listOf(false to "Mostrar meu QR", true to "Ler um QR"), scanning, { scanning = it; note = null })
        if (scanning) {
            GMCard {
                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Icon(Icons.Filled.QrCodeScanner, null, tint = GMColors.accent, modifier = Modifier.size(48.dp))
                    Text("Aponte a câmera do celular para o QR na tela do seu amigo: o GymBros abre e pergunta antes de adicionar.",
                         color = Color.White, style = GMType.subheadline, textAlign = TextAlign.Center)
                    GMButton("Abrir a câmera", {
                        runCatching { context.startActivity(Intent(android.provider.MediaStore.INTENT_ACTION_STILL_IMAGE_CAMERA)) }
                            .onFailure { note = "Não achei o app da câmera neste aparelho." }
                    }, icon = Icons.Filled.CameraAlt)
                    GMButton("Escolher foto do QR", { pick.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
                             icon = Icons.Filled.PhotoLibrary, kind = GMButtonKind.SECONDARY)
                }
            }
            Text(note ?: "Aponte para o QR na tela do seu amigo.", color = if (note != null) GMColors.danger else GMColors.dim, style = GMType.footnote)
        } else {
            val image = remember(myCode) { qrBitmap(FriendQR.link(myCode))?.asImageBitmap() }
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                if (image != null) {
                    Image(image, null, filterQuality = FilterQuality.None,
                          modifier = Modifier.widthIn(max = 280.dp).fillMaxWidth().aspectRatio(1f).background(Color.White, GMRadius.card).padding(18.dp)
                              .semantics { contentDescription = "QR do seu código de amigo" })
                }
                Text(myCode, color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace)
                Text("Para quem está do seu lado: a pessoa lê este QR no app e vocês viram amigos.", color = GMColors.dim, style = GMType.footnote,
                     textAlign = TextAlign.Center)
            }
        }
    }
}

/**
 * Link de amigo (`gymbros://amigo/CÓDIGO`, do QR lido pela câmera ou de um convite): pergunta antes de adicionar, como o
 * App.swift (um link qualquer não vira amizade sozinho, SEC-AND-01). Lê o link que abriu o app e os que chegam com ele
 * aberto. Ponto de encaixe: a raiz do app (MainActivity `Root`) põe `FriendLinkHandler(home, friendsViewModel)` uma vez.
 */
@Composable
fun FriendLinkHandler(home: HomeData, vm: FriendsViewModel) {
    val activity = LocalContext.current as? ComponentActivity ?: return
    var code by remember { mutableStateOf<String?>(null) }
    fun take(intent: Intent?) {
        val uri = intent?.data ?: return
        if (uri.scheme != "gymbros" || uri.host != "amigo") return
        // Consome o link: girar a tela ou voltar ao app não pergunta de novo
        intent.data = null
        code = FriendQR.code(uri.toString())
    }
    DisposableEffect(activity) {
        take(activity.intent)
        val listener = androidx.core.util.Consumer<Intent> { take(it) }
        activity.addOnNewIntentListener(listener)
        onDispose { activity.removeOnNewIntentListener(listener) }
    }
    val c = code ?: return
    GMActions(true, { code = null }, title = "Adicionar amigo?",
              message = "Código $c. Só adicione quem você conhece: quem também te adicionar vê seus treinos ao vivo.",
              actions = listOf(GMAction("Adicionar", Icons.Filled.PersonAdd) { vm.addByCode(c, home) }))
}
