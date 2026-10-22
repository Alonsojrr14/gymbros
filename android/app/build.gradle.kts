// App Android do GymBros (ADR-001/002/005). O plugin do Firebase entra quando o dono registrar o app no console
// e o google-services.json (fora do git) estiver em android/app/.
plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
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

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
        }
    }

    buildFeatures { compose = true }
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    implementation(project(":core:domain"))
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.foundation)
    implementation(libs.compose.material3)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.activity.compose)
    implementation(libs.core.ktx)
}
