# Capacidades de plataforma: Apple → Android

**Escopo.** Para cada framework da Apple usado no app, o equivalente no Android, a adaptação necessária ou a saída da v1, com o motivo.
**Base de evidência.** Uso de cada framework levantado por `grep` pelo `android-architect`, e inventário do repositório. "Status v1" é proposta (ADR-010).
**Status.** Rodada 1.

| Apple (onde se usa) | Android | Status v1 | Motivo / nota |
|---|---|---|---|
| SwiftUI | Jetpack Compose + `GM*` próprios | equivalente | ADR-005 |
| SwiftData (19 `@Model`) | `AccountStore` em arquivo (formato `Backup`) | adaptação | ADR-004; Room só na fase C |
| CloudKit (modo legado) | — | fora | não roda no modo Firebase; exige conta paga |
| HealthKit (`HealthSync`, `WatchBridge`, `Hatch`, `AttributeSplit`) | Health Connect (`ExerciseSession`, `ActiveCaloriesBurned`, `Distance`, `Weight`) | v1.1 | o domínio já trata atividade "do Saúde": esforço 5, sem kcal nem distância |
| WidgetKit (widget, `BrosWidgetFeed`) | Glance | v1.1 | — |
| ActivityKit (Live Activities) | notificação contínua + serviço em primeiro plano (tipo `health`/`location` declarado) | fora da v1 | junto com o ao vivo; SEC-C1 |
| AppIntents, Controls, Siri, botão de ação | App Shortcuts | fora da v1 | — |
| WatchKit / WatchConnectivity; complicações | Wear OS + Data Layer; Tiles | fora | outro produto |
| CoreLocation `CLMonitor` (até 20 academias) | `GeofencingClient` + `ACCESS_BACKGROUND_LOCATION` | fora da v1 | justificativa no Play |
| CoreLocation durante o treino / rota GPS | Fused Location em serviço em primeiro plano | fora da v1 | vem com o ao vivo |
| MapKit (`MapScreen`, `FriendsLive`, `Route`) | Maps Compose (chave com faturamento) ou MapLibre | v1: lista | P15 |
| PhotosUI | Photo Picker (`PickVisualMedia`) | v1.1 | foto de perfil e prova ficam no aparelho |
| ImageIO / EXIF (`CheckInProof`) | `androidx.exifinterface` | v1.1 | com a câmera |
| AVFoundation: câmera / vídeo / fone | CameraX / Media3 Transformer / MediaSession | v1.1 / fora / fora | — |
| Vision (OCR do WOD) | ML Kit Text Recognition | fora da v1 | — |
| FoundationModels | Gemini Nano / ML Kit GenAI | fora | poucos aparelhos suportam |
| Translation | ML Kit Translation | fora | textos já em pt-BR |
| StoreKit (Pro com `enforced = false`) | Play Billing | fora | o Pro não é cobrado |
| MediaPlayer ("Ouvindo agora") | `MediaSessionManager` + acesso a notificações | fora | permissão sensível |
| Charts | `Canvas` do Compose | equivalente | gráficos simples |
| CryptoKit (SHA-256) | `java.security.MessageDigest` | equivalente | sem dependência |
| Keychain (sessão) | sessão do Firebase Auth; Keystore se surgir segredo próprio | equivalente | SEC-AND-03 |
| UserNotifications | `NotificationManager` + canais + `POST_NOTIFICATIONS` | mínimo na v1 | sem push, como no iOS |
| AuthenticationServices (Apple) | Credential Manager (senha) | adaptação | Apple fora (ADR-009) |
| Deep link `gymbros://amigo/CÓDIGO` | filtro do esquema + App Link https verificado + **confirmação** | equivalente com correção | SEC-AND-01 |
| MuscleMap (SPM, MIT) | componente Compose próprio | equivalente | ADR-012 |
| `UserDefaults` / `@AppStorage` | `accountSettings` (chaves da conta) + DataStore (chaves do aparelho) | equivalente | — |
| Dynamic Type / `accessibilityLabel` | `sp` / `contentDescription` + `semantics` | equivalente | referencia-compose |
| SF Symbols, fonte SF | Material Symbols ou vetores próprios; fonte do sistema | adaptação | os da Apple não podem ser redistribuídos |
