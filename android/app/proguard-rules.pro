# Release do GymBros (R8). Mantém o que é lido por reflexão ou por nome.

# kotlinx.serialization: serializers gerados e companions das classes @Serializable
-keepattributes *Annotation*, InnerClasses, Signature, EnclosingMethod
-keepclassmembers @kotlinx.serialization.Serializable class ** {
    *** Companion;
    static ** INSTANCE;
    kotlinx.serialization.KSerializer serializer(...);
}
-keepclasseswithmembers class ** {
    kotlinx.serialization.KSerializer serializer(...);
}
-keep,includedescriptorclasses class com.alonsoalmeida.gymbros.**$$serializer { *; }

# Plist da conta (dd-plist) cria NSObject por nome
-keep class com.dd.plist.** { *; }
-dontwarn com.dd.plist.**

# MapLibre: código nativo chama classes Java por nome
-keep class org.maplibre.** { *; }
-dontwarn org.maplibre.**

# Firestore/Firebase usam reflexão nos próprios tipos
-keepattributes RuntimeVisibleAnnotations
-dontwarn com.google.firebase.**

# Avisos de dependências opcionais
-dontwarn org.slf4j.**
-dontwarn javax.annotation.**
