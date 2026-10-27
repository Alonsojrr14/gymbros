# Inventário do repositório e do ambiente

**Escopo.** Estrutura do repositório `gymbros/`, alvos Xcode, pacotes, recursos, scripts, caminhos referenciados e ambiente da máquina, como base para a reorganização (`../plano/reorganizacao-repositorio.md`) e para o Android.
**Base de evidência.** Comandos somente leitura do orquestrador e do `repository-analyst` (Haiku 5.5) em 21/10/2026, HEAD `7ab62342`.
**Status.** Rodada 1, concluído. Perguntas abertas no fim.

## 1. Git

| Item | Valor | Status |
|---|---|---|
| Repositório | `gymbros/` independente; o pai `local-tests/` é outro repositório | VERIFIED |
| Branch / remoto | `swift` / `https://github.com/Alonsojrr14/gymbros.git` | VERIFIED |
| HEAD | `7ab62342` "Docs e artes: requisitos, arquitetura, README e sprite do ovo" | VERIFIED |
| Trabalho do dono não commitado | 22 modificados (ligas, social, Firebase, onboarding, testes, `firestore.rules`) + `ANALISE-GYMRATS.md` e `GymBros/Friends/CommentSync.swift` não rastreados | VERIFIED |
| Criado por esta rodada (não rastreado) | `CLAUDE.md`, `.claude/agents/*`, `.claude/skills/*`, `.claude/settings.json`, `engenharia/**` | VERIFIED |
| CI | nenhum (`.github/`, `ci_scripts/`, fastlane, Makefile ausentes) | VERIFIED |
| Tamanhos | `.git` 400 MB; `build/` 10 GB (ignorado); `tools/artes` 588 MB, dos quais `.work-viradas` 580 MB (ignorado) | VERIFIED |

## 2. Alvos Xcode (`GymBros.xcodeproj/project.pbxproj`, 956 linhas)

Todos com `DEVELOPMENT_TEAM = 5UV7WAAAL2`, assinatura automática, `SWIFT_VERSION = 5.0`.

| Alvo | Bundle id | Info.plist | Entitlements | Mínimo |
|---|---|---|---|---|
| GymBros | `com.alonsoalmeida.gymbros` | `GymBros/Resources/Info.plist` | `GymBros/Resources/GymBros.entitlements` (HealthKit, App Group) | iOS 17.0 |
| GymBrosWidget | `….widget` | `GymBrosWidget/Info.plist` | App Group | iOS 17.0 |
| GymBrosWatch | `….watchkitapp` | `GymBrosWatch/Info.plist` | HealthKit, App Group | watchOS 10.0 |
| GymBrosWatchWidget | `….watchkitapp.complications` | `GymBrosWatchWidget/Info.plist` | App Group | watchOS 10.0 |
| GymBrosTests | `….tests` | gerado | — | iOS 17.0; `TEST_HOST` = app |

- **Grupos sincronizados** (`PBXFileSystemSynchronizedRootGroup`): `GymBros`, `GymBrosWidget`, `GymBrosWatch`, `GymBrosWatchWidget`, `Shared`, `GymBrosTests`, todos com caminho relativo ao projeto. Exceções: os 4 `Info.plist`; `Shared/WorkoutIntents.swift` e `Shared/WorkoutLive.swift` fora dos alvos do relógio. VERIFIED.
- Nenhum caminho absoluto nem `../` de arquivo; nenhum Run Script. VERIFIED. **Consequência: mover `GymBros.xcodeproj` junto com as seis pastas para `ios/` não exige editar o pbxproj.** INFERRED (a confirmar com build no iPhone).
- Esquema compartilhado `GymBros.xcscheme`: build `GymBros.app` (extensões por dependência), teste `GymBrosTests`.
- Entitlements: **sem** `com.apple.developer.applesignin`, sem iCloud, sem push. VERIFIED.
- `Info.plist` do app: esquema de URL `gymbros`; `UIBackgroundModes` = `location`, `workout-processing`; descrições de uso como `INFOPLIST_KEY_*` no pbxproj (localização, Música, Saúde leitura/escrita, câmera, salvar fotos, Live Activities). VERIFIED.
- `PrivacyInfo.xcprivacy`: app (UserDefaults, 9 tipos de dado coletados, sem rastreamento) e widget. Relógio sem manifesto. VERIFIED.

## 3. Pacotes (SPM, `Package.resolved` v3)

| Pacote | Versão | Licença | Uso |
|---|---|---|---|
| firebase-ios-sdk | 13.0.1 (até a próxima major) | Apache-2.0 (INFERRED; não lido) | só FirebaseAuth e FirebaseFirestore linkados |
| MuscleMap | 1.9.0 (exata) | **MIT** (VERIFIED em `build/SourcePackages/checkouts/MuscleMap/LICENSE`) | mapa muscular |
| Transitivos | abseil, app-check, gRPC, leveldb, nanopb, promises, GoogleUtilities, GoogleAppMeasurement (não linkado), google-ads-on-device-conversion (não linkado) | — | — |

## 4. Recursos

| Item | Contagem / tamanho | Status |
|---|---|---|
| `GymBros/Resources/Assets.xcassets` | 176 MB; 757 imagesets (421 `sprite_*` + 336 em `Wger/`), 671 PNG, 87 JPEG; **nenhum PDF, SVG ou colorset** | VERIFIED |
| `GymBrosWidget/Assets.xcassets` | 842 PNG (421 `sprite_*` + 421 `sprite_*_live`) | VERIFIED |
| Fontes | **nenhum .ttf/.otf; sem `UIAppFonts`; sem `Font.custom`. O app usa a fonte do sistema (SF) via `gmFont`** (`docs/design-system.md:84`). Jersey 10 só no site (`docs/assets/site.css`, `docs/_layouts/`) | VERIFIED; **CONFLICTING com o prompt** ("títulos em Jersey 10") |
| Cores | em código: `Shared/Theme.swift:6-8` (`bg` 0,05/0,06/0,08 ≈ `#0D0F14`; `card` 0,10/0,11/0,14 ≈ `#1A1C24`; `accent` 0,64/0,90/0,21 ≈ `#A3E636`) | VERIFIED |
| `GymBros/Resources/wger.json` | 252 KB. README diz 262 exercícios; grep simples conta 237 entradas `"wger":` | CONFLICTING/UNKNOWN (contar com parser) |

## 5. Scripts em `tools/` (nada foi executado)

| Script | Gera | Caminho de saída | Risco ao mover o app para `ios/` |
|---|---|---|---|
| `tools/wger/build.py` (+ `commons.py`, `everkinetic.py`) | `wger.json` e imagesets `Wger/` | `GymBros/Resources/…` relativo à raiz (`build.py:11-13`) | ALTO: escreve no lugar errado |
| `tools/artes/instalar.sh` | sprites nos dois catálogos | `ROOT=${0:A:h:h:h}` + `GymBros/…`, `GymBrosWidget/…` (`:2,16,20`) | ALTO |
| `tools/artes/prompts.py`, `viradas.py` | jobs de geração de arte | leem `HIBRIDOS.md`, `GymBrosWidget/Assets.xcassets`, `GymBros/Bros/Game.swift`, `Viradas.swift` | ALTO |
| `tools/artes/codex.py`, `cursor.py`, `gerar.mjs`, `chrome.sh`, `grade.py`, `folha.swift`, `recortar-*.swift`, `tools/recortar-*.swift` | imagens intermediárias | `ARTES_WORK`, `$TMPDIR`, argumentos | BAIXO |

## 6. Caminhos referenciados (para o manifesto)

| Referência | Onde | Risco |
|---|---|---|
| `GymBros/Resources/GoogleService-Info.plist` | `.gitignore:8` | **ALTO**: sem atualizar, o segredo pode ser commitado depois da mudança |
| `build/`, `xcuserdata/`, `graphify-out/` | `.gitignore:1,2,5` (padrões sem `/` valem em qualquer nível) | BAIXO |
| comandos `-project GymBros.xcodeproj` | `CLAUDE.md`, `README.md:101-110`, `docs/rbac.md:148`, `docs/publicacao.md:48` | MÉDIO (texto de comando) |
| `tools/*` | ver seção 5 | ALTO |
| caminhos em texto `GymBros/…` | `README.md` (~28 linhas), `CREDITOS.md`, `NOTICE.md:4`, `VIRADAS.md:3`, `EVOLUCAO.md` (119), `docs/*.md` (~470 no total) | BAIXO (texto); `docs/` é o site |
| links `github.com/.../blob/swift/GymBros…` | nenhum | — |
| `wger.json` e `GoogleService-Info.plist` em tempo de execução | `Wger.swift:46`, `Backend.swift:51` | nenhum (busca no bundle por nome) |
| `firebase/firebase.json` | relativo a `firebase/` | nenhum |

## 7. Ambiente da máquina (21/10/2026)

| Item | Valor | Status / divergência com o prompt |
|---|---|---|
| macOS / Xcode / Swift | Darwin 25.6, Xcode 27.1 (27A9275), Swift 6.4 | VERIFIED |
| Claude Code | 2.1.307 | VERIFIED |
| Disco | 228 GB, 4,4 GB livres em 21/10; **18 GB depois da limpeza autorizada em 22/10** (V-09) | CONFLICTING: prompt dizia ~3,2 GB |
| Simuladores | **Ainda há runtimes** iOS 26.0 e watchOS 27.0 e dispositivos simulados ("iPhone Duo", "Apple Watch SE 3") | CONFLICTING: prompt dizia desinstalados. Não foram usados nem mexidos |
| iPhone | "iPhone de Zero", `00008150-001E15363C04C01C`, iPhone 17 Pro Max, **conectado** ("available (paired)") | VERIFIED |
| JDK | nenhum (`/usr/libexec/java_home`: "Unable to locate a Java Runtime"; `/usr/bin/java` é o stub) | VERIFIED |
| gradle / adb no PATH | ausentes | VERIFIED |
| `~/Library/Android/sdk` | 5,0 GB: `system-images` 3,1 GB (só `android-30/google_apis`), `emulator` 1,1 GB, `platforms` 368 MB (android-30, 34, 35), `build-tools` 187 MB (34.0.0), `cmdline-tools` 158 MB, `platform-tools` 37 MB | VERIFIED (nada apagado) |
| `build/` do repositório | 10 GB (DerivedData local, ignorado pelo git) | VERIFIED; candidato óbvio a liberar espaço, **decisão do dono** |
| Aparelho Android | desconhecido | UNKNOWN: pergunta ao dono |
| `.claude/` existente em `gymbros/` | já havia `.claude/settings.local.json` (desliga o servidor MCP `supabase`) | CONFLICTING: prompt dizia que não havia `.claude/` aqui. Não foi alterado |

## Perguntas abertas
- Contagem real de exercícios no `wger.json` (237 × 262).
- O relógio precisa de `PrivacyInfo.xcprivacy` próprio?
- O `GoogleService-Info.plist` é exigido para compilar ou só para rodar no modo Firebase? (`Backend.swift:51` sugere só para rodar.)
