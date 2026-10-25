// App Android do GymBros (ADR-001/002/005). Firebase pelo google-services.json em android/app/ (fora do git; os dois
// pacotes, normal e .debug, registrados no projeto do Firebase).
import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.google.services)
}

android {
    namespace = "com.alonsoalmeida.gymbros"
    // 35 é a plataforma instalada nesta máquina; o alvo final é o exigido pelo Play na publicação (ADR-002)
    compileSdk = 35

    defaultConfig {
        applicationId = "com.alonsoalmeida.gymbros"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "0.1"
    }

    // Chave da release fora do repositório (~/.gymbros/keystore.properties); sem ela, a release sai sem assinatura
    val keystoreFile = file("${System.getProperty("user.home")}/.gymbros/keystore.properties")
    val keystore = Properties().apply { if (keystoreFile.exists()) keystoreFile.inputStream().use { load(it) } }
    signingConfigs {
        if (keystore.isNotEmpty()) create("release") {
            storeFile = file(keystore.getProperty("storeFile"))
            storePassword = keystore.getProperty("storePassword")
            keyAlias = keystore.getProperty("keyAlias")
            keyPassword = keystore.getProperty("keyPassword")
        }
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfigs.findByName("release")?.let { signingConfig = it }
            // APK enviado por e-mail: só os processadores de celular (o motor do mapa vem por ABI)
            ndk { abiFilters += listOf("arm64-v8a", "armeabi-v7a") }
        }
    }

    buildFeatures { compose = true }
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    implementation(project(":core:domain"))
    // A cópia da conta é JSON: o app guarda e grava o documento inteiro
    implementation(libs.serialization.json)
    // Ajustes da conta (plist binário do iOS) mudados pelo app: código de amigo, pedidos recusados, termos
    implementation(libs.ddplist)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.foundation)
    implementation(libs.compose.material3)
    implementation(libs.compose.icons.extended)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.activity.compose)
    implementation(libs.core.ktx)
    implementation(libs.lifecycle.viewmodel.compose)
    implementation(libs.lifecycle.runtime.compose)
    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.auth)
    implementation(libs.firebase.firestore)
    implementation(libs.coroutines.play.services)
    // QR do código de amigo (FriendQRView do iOS): gerar o QR e ler o QR de uma foto da galeria; núcleo Java puro, Apache-2.0
    implementation(libs.zxing.core)
    // Health Connect: importa treinos gravados por relógios e apps (o Apple Saúde do Android)
    implementation(libs.health.connect)
    // Aba Mapa: mapa vetorial (OpenFreeMap) e localização/cerca das academias
    implementation(libs.maplibre)
    implementation(libs.play.services.location)
}
