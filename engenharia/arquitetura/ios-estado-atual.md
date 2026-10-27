# Arquitetura iOS: estado atual

**Escopo.** Arquitetura real do app iOS no disco (HEAD `7ab62342` + mudanças não commitadas), com foco no que importa para o porte Android. **Complementa** `docs/arquitetura.md` (532 linhas), que continua sendo a referência descritiva; aqui ficam as correções e o que o Android precisa.
**Base de evidência.** `ios-architecture-analyst` (Opus 5.5, somente leitura) + conferência do orquestrador nos pontos marcados.
**Status.** Rodada 1. Relógio, widgets e Live Activities foram lidos só por nome (ver lacunas).

## 1. Ciclo de vida e navegação (VERIFIED)

```
GymBrosApp.init (GymBros/App/App.swift:13)
 ├─ AppRuntime.isTesting → Backend.install() e nada mais; cena = Color.black          (:20, :38)
 └─ WatchBridge.activate → MirroredWorkout.install → WodRun → Shortcuts → NotificationRouter
    → GymLocation.startMonitoring → PRBook.reload → Backend.install()                  (:21-31)
WindowGroup { RootView } .modelContainer(AppData.container)                           (:53)
RootView (:58):
   sem sessão                  → LoginView(required: true)          (conta obrigatória)
   !AccountSync.isReady(user)  → AccountLoadingView                 (baixa/restaura a cópia)
   trainerName vazio           → OnboardingView
   termos desatualizados       → TermsRequiredView
   senão                       → MainView
   .task(id: user.id): AccessStore.refresh → finishPendingDeletion → AccountSync.enter
   ModelContext.didSave / UserDefaults.didChange → upload com debounce de 5 s; ao ir para o fundo → upload
MainView (:108): ZStack de páginas preguiçosas + GMTabBar própria (sem TabView)
   abas: home (HomeView) | train (TrainView) | leagues (LeaguesView) | map (MapScreen) | feed (UnifiedFeedView)
   por cima: OnboardingOverlay (spotlight), gmModal, fullScreenCover do treino do relógio
```

## 2. Camadas

- **Persistência:** SwiftData, `SchemaV1`…`SchemaV5` com `AppMigrationPlan` (4 estágios leves), `cloudKitDatabase: .none`, proteção `completeUntilFirstUserAuthentication`, banco corrompido é renomeado `-erro-<ts>` e o app tenta de novo (`GymBros/Models/Schema.swift`). 19 `@Model`; só duas relações reais (`Routine.items`, `WorkoutSession.sets`, ambas em cascata); o resto se liga por UUID/String sem integridade. Enums gravados como `*Raw: String`; regras novas em JSON dentro de `settingsRaw`/`proofRaw`.
- **Estado:** singletons `@MainActor @Observable` (`AuthStore`, `AccountSync`, `LeagueRemoteStore`, `FriendsStore`, `ModerationStore`, `InboxStore`, `DuelStore`, `TradeStore`, `PublicRoutinesStore`, `AccessStore`, `AdminStore`), muito `@AppStorage`/`UserDefaults`. A divisão de atributos por atividade fica em `UserDefaults["activitySplits"]` (`AttributeSplit.swift:279`).
- **Servidor:** contratos (protocolos `Sendable`) ligados por `Backend.install()` (`Backend.swift:63-102`) conforme `Backend.mode`:

| Contrato | `.mock` | `.cloudKit` | `.firebase` (ativo hoje) |
|---|---|---|---|
| AuthBackend | simulado | CloudKit | FirebaseAuthBackend |
| LeagueBackend, FriendsBackend, ModerationBackend, DuelBackend, RoleBackend | simulado | CloudKit | Firebase* |
| AccountDataBackend | arquivo local | lança erro | FirebaseAccountDataBackend (local + nuvem) |
| InboxBackend | simulado | lança erro | FirebaseInboxBackend |
| TradeBackend, RoutinesBackend | simulado | **simulado** | Firebase* |
| AdminBackend | exige servidor confiável | idem | FirebaseAdminBackend |
| PhotoStore | — | — | `NoPhotoStore` (`appleCapabilities = false`) |
| CommentSync (novo, não commitado) | — | — | fala direto com o Firestore, **fora do padrão contrato + mock** |

## 3. Domínio puro × acoplado × plataforma

| Arquivo | Classe | Acoplamento a remover no porte |
|---|---|---|
| `Leagues/Swiss.swift` | puro | — |
| `Duels/Duel.swift` | puro | usa `Game.xp`, `ActivityKind.met` |
| `Bros/Viradas.swift`, `Train/WodMovements.swift`, `Moderation/BlockedTerms.swift` | puro (dados/regras estáticas) | — |
| `Bros/Game.swift` | quase puro | `UIImage(named:)` sob `canImport(UIKit)` |
| `Bros/AttributeSplit.swift` | acoplado | `HKWorkoutActivityType`; `ActivitySplits.stamp` faz fetch no SwiftData |
| `Profile/Constancy.swift` | acoplado | `HKWorkoutActivityType` |
| `Train/Progression.swift` | acoplado | `RoutineTemplate.install(in: ModelContext)` |
| `Leagues/LeagueRules.swift` | acoplado | `HealthSync.activeKcal` (HealthKit), `Calendar.current` |
| `Leagues/Leagues.swift` | acoplado | `LeagueBoard` @MainActor lê `LeagueRemoteStore.shared`, `Cloud.knownID`, `modelContext` |
| `Leagues/LeagueWinners.swift` | acoplado | regra `ClubWinners` no mesmo arquivo da View |
| `Leagues/LeagueRemote.swift` | acoplado | tipos da API + `RemoteLeague.applying` + store/outbox |
| `Services/Backup.swift` | plataforma, **mas o formato é contrato** | — |
| Demais (`Views`, `Services/*`) | plataforma | — |

Conclusão para o Android: as regras estão concentradas em ~12 arquivos, mas metade mistura plataforma. O porte deve extrair as funções puras (entrada → saída), não traduzir os arquivos.

## 4. Fontes de não determinismo nas regras vistas por outras pessoas

| # | Fonte | Evidência | Status | Efeito |
|---|---|---|---|---|
| ND-1 | **Seu id no suíço é `"me"` no modo Firebase** (`LeagueBoard.selfID = Cloud.knownID ?? "me"`; `Cloud.knownID` só é gravado pelo CloudKit) | `Leagues.swift:650`; `Backend.swift:126-140`; confirmado por 3 análises independentes | VERIFIED (código) / INFERRED (efeito) | sorteio do 1º dia e desempates diferentes em cada aparelho. O mesmo `selfID` decide moderadores e banidos (`CheckInProof.swift:170`, `LeaguesView.swift:1238`), que então nunca casam no Firebase |
| ND-2 | "Eu primeiro" no desempate final do ranking | `Leagues.swift:713` (`a.isMe != b.isMe ? a.isMe : a.name < b.name`) | VERIFIED | ranking empatado aparece em ordem diferente para cada pessoa |
| ND-3 | `Calendar.current` (fuso, `firstWeekday` do aparelho) em dias ativos, primeiro check-in do dia, `bestStreak`, janelas semana/mês, tetos, campeões, pose do dia, renovação de temporada | `Leagues.swift:264,298,587,681`; `LeagueRules.swift:90,266,393`; `LeagueWinners.swift:64,242` | VERIFIED | pessoas em fusos diferentes veem placares/campeões diferentes |
| ND-4 | XP do "bro do time" com `Calendar.current` | `Leagues.swift:631-646` | VERIFIED | teto diário em dias diferentes conforme quem olha |
| ND-5 | `AttributeSplit.tidy`: soma e máximo sobre `Dictionary` (ordem muda a cada execução no Swift) | `AttributeSplit.swift:248-258` | VERIFIED (código) / INFERRED (efeito) | em empate, o resto do arredondamento cai em atributo imprevisível; mitigado porque a divisão é gravada e sincronizada |
| ND-6 | Arredondamentos: `.rounded()` (metade para longe do zero), `rounded(.down)`, truncamento em kcal do X1 | `Game.swift:478`; `Leagues.swift:156,164`; `LeagueRules.swift:461`; `Duel.swift:67` | VERIFIED | porte precisa da mesma operação, na mesma ordem |
| ND-7 | `now` do aparelho decide dia encerrado do suíço, X1, campeões | `Swiss.swift:221`; `Duel.swift:129-143` | VERIFIED | relógio errado muda o que aparece |
| ND-8 | `Swiss.table` e `dayStamp` têm `calendar: .current` como padrão (o chamador passa o de Brasília) | `Swiss.swift:189,293` | VERIFIED | armadilha para o porte |

## 5. Divergências com `docs/arquitetura.md` (CONFLICTING; o código vence)

| Doc diz | Código faz | Evidência |
|---|---|---|
| Alvos sem os do relógio; App Group em 2 entitlements | 5 alvos; App Group em 4 entitlements | pbxproj; entitlements |
| Única dependência é MuscleMap | também FirebaseAuth/Firestore | pbxproj |
| Aba 4 é `HistoryView` "Histórico" | `UnifiedFeedView`, "Feed" | `App.swift:165` |
| Modelos de liga sem `activityRuleRaw`, `settingsRaw`, `proofRaw`, `reviewRaw`, `extraPhotosData`, `photo`; sem `CheckInReview`; "18 modelos" | 19 modelos, campos presentes | `Schema.swift`, `League.swift` |
| "Sete contratos", `Backend.mode = .mock` hoje | 11 protocolos + PhotoStore; `.firebase` ativo com o plist | `Backend.swift:51,63-102` |
| Comentários não saem do aparelho | `CommentSync` publica no Firestore (não commitado) | `GymBros/Friends/CommentSync.swift` |
| "me" vira `Cloud.knownID` e todos pareiam igual; dívida 14 corrigida | vale só no CloudKit; no Firebase não | ND-1 |
| Comentário `App.swift:28` "Mock ou CloudKit"; cabeçalho `FirebaseBackend.swift:13-14` "X1, trocas… continuam simulados" | desatualizados | — |

## Lacunas (UNKNOWN)
- Protocolo de mensagens do relógio (`WatchBridge`, `Shared/WatchLink.swift`), formato de `WidgetData`, Live Activities: não lidos (fora da v1 do Android provavelmente; ver ADRs).
- Local exato do `default.store` (App Group por padrão `.automatic`; não conferido no aparelho).
- Mudanças de formato do `Backup` desde `version = 1` (compatibilidade parece ser por campos opcionais).
