// Regras do jogo e das ligas e formatos da cópia da conta: Kotlin puro, sem Android (ADR-001).
// Os testes rodam só com o JDK e provam a paridade com o iOS caso a caso.
plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
}

kotlin {
    jvmToolchain(17)
}

// Vetores compartilhados gerados pelo iOS (GoldenVectorsTests): a mesma pasta que o teste Swift lê
sourceSets["test"].resources.srcDir("../../../ios/GymBrosTests/Fixtures")

dependencies {
    implementation(libs.serialization.json)
    // accountSettings da cópia da conta é um plist binário do iOS (MIT)
    implementation(libs.ddplist)
    testImplementation(platform(libs.junit.bom))
    testImplementation(libs.junit.jupiter)
    testRuntimeOnly(libs.junit.launcher)
}

tasks.test {
    useJUnitPlatform()
}
