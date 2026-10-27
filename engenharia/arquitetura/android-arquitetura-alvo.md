# Arquitetura alvo do Android

**Escopo.** Arquitetura proposta para o app Android nativo do GymBros (Kotlin + Jetpack Compose). As decisões estão em `decisoes.md`, as capacidades em `../requisitos/capacidades-plataforma.md` e as tarefas em `../plano/backlog-android.md`.
**Base de evidência.** Proposta do `android-architect` (Opus 5.5), com ajustes do orquestrador e da revisão com referências de Compose.
**Status.** Proposta para o portão 1. Nada implementado. As versões de dependência estão "a confirmar": sem rede e sem JDK, nada foi resolvido.

## 1. Visão geral

```
                 ┌──────────────────────────── :app (Android) ───────────────────────────┐
  Firebase Auth ─┤ data/firebase  (repositórios: interface + Firestore + falso em memória)  │
  Firestore  ────┤ data/local     (AccountStore = arquivo da cópia + StateFlow; DataStore)  │
  (cache offline)│ sync/          (WorkManager: envio da cópia, só no modo dono)            │
                 │ ui/theme, ui/components (GM*), ui/feature/*, nav/ (rotas tipadas)        │
                 │ di/AppContainer (DI manual, SessionScope por uid)                        │
                 └───────────────────────────────┬─────────────────────────────────────────┘
                                                 │ usa
                 ┌───────────────────── :core:domain (Kotlin/JVM, sem Android) ───────────┐
                 │ rules/  Game, SeededRandom, Swiss, LeagueScore, PhotoRule, ScoringLimits, │
                 │         Ranking, Winners, Duel, Constancy, Progression, Roster           │
                 │ time/   RuleClock(zone, firstDayOfWeek, now)                              │
                 │ backup/ BackupDto, BackupCodec (ISO 8601 em s), ChunkCodec (DEFLATE cru,  │
                 │         900 000), BPlist (accountSettings)                                │
                 │ wire/   JSON em texto (LeagueSettings, CheckInProof, PublicStats, TradeBro)│
                 │ test ← ../../shared-fixtures (vetores A, B, C)                            │
                 └─────────────────────────────────────────────────────────────────────────┘
```

## 2. Estrutura de pastas

```
android/
  settings.gradle.kts, gradle/libs.versions.toml, gradlew (wrapper)
  core/domain/src/{main,test}/kotlin/…
  app/src/main/{AndroidManifest.xml, kotlin/…, res/drawable-nodpi/ (sprites)}
  app/google-services.json   ← fora do git
```

## 3. Dependências (versões a confirmar no portão 3)

| Dependência | Uso | Por que serve a este app |
|---|---|---|
| Kotlin + plugin Compose + `kotlinx.serialization` | linguagem, JSON da cópia e JSON em texto | JSON com chaves ordenadas e datas sob controle |
| Compose BOM, `activity-compose`, `lifecycle-*-compose`, `navigation-compose` | UI, edge-to-edge, voltar predito, rotas tipadas | — |
| `kotlinx-coroutines` (+ `-test`) | assíncrono e testes | — |
| Firebase BoM: `firebase-auth`, `firebase-firestore` (sem Analytics) | contrato | mesmo projeto do iOS |
| `datastore-preferences` | preferências do aparelho | substitui `@AppStorage` |
| `work-runtime-ktx` | envio da cópia da conta | não perder o envio se o processo morrer (ADR-004) |
| `dd-plist` (MIT) | `accountSettings` em plist binário | é o formato que o iOS grava |
| `androidx.credentials` | salvar e preencher a senha | login |
| JUnit 5, Robolectric, `compose-ui-test` | testes sem emulador | não há emulador |
| **Fora da v1** | Hilt, Room, Health Connect, Glance, CameraX, Media3, Play Billing, ML Kit, Maps | ver ADR-010 |

## 4. Fluxo de raiz (igual ao `RootView` do iOS)
Sem sessão → Login. Cópia não pronta → Carregando (decide **dono** ou **companheiro**, ADR-007). `trainerName` vazio → Onboarding. Termos desatualizados → Termos. Caso contrário → Main (`GMTabBar` com pilha por aba).

## 5. Dados

| Dado | Fonte | Offline | Escrita |
|---|---|---|---|
| Pessoal (atividades, rotinas, sessões, bros, ligas locais, medidas…) | `AccountStore` (arquivo) | completo | arquivo na hora; envio pelo WorkManager só no modo dono, em transação com `hash` |
| Social | Firestore + cache persistente | leitura do cache | fila do SDK; `serverTimestamp()` onde a regra exige |
| Preferências do aparelho | DataStore | completo | local |
| Sprites, wger | APK/AAB (e PAD se medido) | completo | — |

## 6. Regras compartilhadas
Todas ficam em `:core:domain`, recebem `RuleClock` (fuso, `firstDayOfWeek`, `minimumDaysInFirstWeek`, calendário gregoriano, `now`) e usam o **uid** como identidade, nunca `"me"`. O arredondamento usa a função própria `roundHalfAwayFromZero`, porque nem `roundToInt` nem `kotlin.math.round` equivalem ao Swift para negativos. Antes de qualquer tela de placar, precisam passar nos vetores dos grupos A, B e C. A v1 replica o fuso do aparelho como o iOS faz hoje (ADR-006), até o dono decidir.

## 7. Segurança
SEC-AND-01 a 12 (`../seguranca/achados.md`). No manifesto: `allowBackup=false`, `exported=false` em tudo exceto a `MainActivity` com os filtros de deep link, R8, sem tráfego em texto puro. Deep link **com tela de confirmação**. Nenhuma conta de demonstração no APK. A cópia local fica em `noBackupFilesDir`.

## 8. Verificação possível em cada ambiente

| Ambiente | O que dá para verificar |
|---|---|
| Só JDK | `./gradlew :core:domain:test` (regras e formatos contra os vetores) |
| JDK + SDK | Robolectric (ViewModels, Compose em 1/5/50 itens, escala de fonte) |
| Aparelho físico | jornadas, permissões, conta nos dois aparelhos, sem rede |
| Emulador | **não será usado** (disco) |

## Perguntas abertas
Ver `../plano/riscos-e-perguntas.md` (P2 a P10 e P15 a P18).
