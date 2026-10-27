# Estratégia de testes (iOS atual e Android)

**Escopo.** Cobertura real dos testes iOS, riscos de instabilidade, checklist de regressão da reorganização, estratégia de testes do Android e avaliação dos vetores de teste compartilhados.
**Base de evidência.** `qa-strategy-analyst` (Opus 5.5) + contagem conferida pelo orquestrador. **Nenhum teste foi executado nesta rodada.**
**Status.** Rodada 1. Vetores compartilhados: recomendados, a aprovar.

## 1. Linha de base iOS

| Item | Valor | Status |
|---|---|---|
| Testes | **358 `func test` em 41 arquivos** (+ `TestSupport.swift`), todos XCTest herdando de `GymTestCase`; nenhum `@Test` | VERIFIED (contagem no disco) |
| No commit HEAD | 359 (`NowFeaturesTests` tinha 9; o trabalho em andamento deixou 8) | VERIFIED |
| `docs/arquitetura.md:463` | diz 262 em 31 arquivos | CONFLICTING (desatualizado) |
| Última execução conhecida | 19/10/2026, 262 testes, 0 falhas (segundo os docs) | não verificado |
| Execução nesta rodada | **não executada**: roda no iPhone do dono com dados reais; aguardando concordância | — |
| CI | nenhum; o esquema não fixa idioma, região, fuso nem variáveis de ambiente | VERIFIED |

Cobertura por arquivo: Access 24 · AccountDeletion 6 · AccountSync 10 · AttributeSplit 8 · Backup 2 · Constancy 7 · ContentFilter 8 · DemoAccount 5 · DexEntry 2 · DuelFighter 2 · Duel 16 · Game 13 · HealthPrivacy 6 · Inbox 14 · Keychain 1 · LeagueFlush 2 · LeagueRules 23 · League 23 · LiveShare 4 · ManualWorkout 2 · Moderation 9 · MusicShare 5 · NamesAndBar 2 · NowFeatures 8 · Onboarding 19 · Progression 25 · RetiredActivity 1 · RetroAndPro 4 · SocialExtras 5 · Store 5 · Story 4 · Swiss 19 · Terms 4 · Trade 3 · TrainingExtras 4 · WodFormats 12 · WodImport 17 · WodLevels 14 · WodTimeline 2 · Workout 16 · WorkoutType 2.

## 2. Lacunas críticas de teste no iOS

| Regra | Lacuna |
|---|---|
| `SeededRandom` | nenhum teste direto (base do sorteio do suíço) |
| Cópia da conta | só ida e volta Swift→Swift; nada cobre `.zlib`, pedaços de 900 000, plist de `accountSettings` |
| Suíço com identidade real | nenhum teste com `identity` = uid do Firebase (não pegaria ND-1) |
| Exclusão de conta no Firebase | `AccountDeletionTests` usa o mock; a recusa da consulta a `reports` (ver contrato) não é coberta |
| Calendário | `Swiss.table`, ranking, campeões e constância testados com `Calendar.current` e `.now` |

## 3. Riscos de instabilidade nos testes iOS (INFERRED)
- Virada de meia-noite durante `SwissTests`, `LeagueTests.testMonthWindowStartsOnFirstDay`, `GameTests.testCachedSnapshotMatchesUncached`.
- Antes das 10h: `GymTestCase.day(0)` cria atividades às 10h de hoje (futuro).
- `firstWeekday` da localidade: `ConstancyTests`, `LeagueRulesTests:219,244`.
- Fuso no parse: `WodLevelsTests:27`, `WodImportTests:123,206`.
- Estado real: `StoreTests.testDeviceStoreOpensWithCurrentSchema` abre o banco real; 11 arquivos tocam `UserDefaults.standard`.
- **Regra prática para rodar no iPhone:** entre 10h e 23h50, e registrar data/hora da execução.

## 4. Checklist de regressão da reorganização (iOS)
1. Mover juntos `GymBros.xcodeproj`, `GymBros/`, `GymBrosTests/`, `GymBrosWidget/`, `GymBrosWatch/`, `GymBrosWatchWidget/`, `Shared/` (caminhos do pbxproj são relativos; `Package.resolved` vai dentro do projeto).
2. `.gitignore`: `GoogleService-Info.plist` no caminho novo **antes** do primeiro `git status` pós-mudança.
3. `tools/`: atualizar `instalar.sh`, `prompts.py`, `viradas.py`, `wger/*.py` (ver manifesto).
4. Build + instalação no iPhone ("App installed"); widget e relógio compilados (vêm por dependência no esquema).
5. Com a concordância do dono: suíte completa no iPhone, **358 testes, 0 falhas** (mesma contagem de antes).
6. Manual: login no Firebase, cópia da conta sobe (ver `updatedAt` no app, não no console), widget aparece, relógio pareia.

## 5. Estratégia Android (por risco)

| Camada | Ferramenta | Roda sem emulador? | Prioridade |
|---|---|---|---|
| Regras de domínio (XP, snapshot, suíço, pontuação, desempate, X1, progressão, constância) | JUnit 5 na JVM, `:core:domain` puro | **sim** | 1 |
| Codificação (cópia da conta: DEFLATE cru, bplist, ISO 8601, JSON-em-string com datas de 2001) | JUnit na JVM + vetores gerados pelo iOS | **sim** | 1 |
| ViewModels | JUnit + `kotlinx-coroutines-test`, repositórios falsos (interfaces) | sim | 2 |
| Repositórios Firestore | interface + implementação falsa em memória; emulador do Firebase **só** se couber no disco (precisa de JDK) e nunca o projeto real | sim (falsa) | 2 |
| UI Compose | testes de Compose com Robolectric (JVM) para estados 1/5/50 itens e escala de fonte | sim (Robolectric) | 3 |
| Instrumentados / jornadas | aparelho Android físico | **não**: exige aparelho | 3 |

Jornadas críticas a cobrir (aparelho): login certo/errado; sessão expirada; sem rede (cache offline do Firestore); estados vazios; entradas inválidas; limites do teto diário; permissão negada/revogada (localização, notificações, câmera); Health Connect ausente; **conta usada no iPhone e no Android**; ação duplicada (check-in, curtida, X1).

## 6. Vetores de teste compartilhados (`shared-fixtures/`)

**Recomendação: sim, com escopo controlado.** É o único jeito de provar paridade das regras por teste e não por leitura; os testes Swift já têm vários casos de entrada/saída fixa.

| Grupo | Regras | Custo | Como |
|---|---|---|---|
| A (fazer primeiro) | `Game.xp`, `PhotoRule`/`League.score`, `Progression`, `SeededRandom`, `Swiss.pair`, `SwissBonus` | pequeno | casos fixos; *golden* gerado uma vez pelo Swift |
| B | `Game.snapshot` (teto diário, galhos), `Swiss.table`, ranking/desempate, X1, streak | médio | fixar `now`, fuso e `firstWeekday` no vetor |
| C (codificação) | cópia da conta (JSON + DEFLATE cru + pedaços), `accountSettings` bplist, `LeagueSettings`/`CheckInProof` com datas de 2001 | médio | arquivos binários em base64 gerados no iPhone |
| D (adiar) | campeões, constância, `AttributeSplit` com empates | grande | testes de propriedade dos dois lados |

- **Formato:** JSON por regra com `version`, `timeZone` explícito, datas em ISO 8601 com deslocamento e dias como `"aaaa-mm-dd"`. `Double` de atributos é comparado com tolerância, **mas `SeededRandom` e tudo que decide ordem é comparado exatamente**, de preferência pelo estado `UInt64` em texto. Valores esperados são *golden* do Swift atual, congelados. Arredondamento com vetor negativo (−2,5).
- **Atenção ao `dayStamp`:** o texto do sorteio é `"<id>-<seed>-<ano>-<mês>-<dia>"`, **sem zeros à esquerda** (`Swiss.swift:213,286-289`).
- **Leitura no Swift:** `GymBrosTests/` é pasta sincronizada sem exceções; um JSON dentro dela entra no bundle de teste sem editar o pbxproj (INFERRED; confirmar no 1º build). Para a fonte única ficar em `shared-fixtures/` na raiz, há duas saídas: (a) um segundo grupo sincronizado no pbxproj com o alvo de teste (edição pequena do pbxproj, exige aprovação), ou (b) o gerador Swift escreve em `shared-fixtures/` e um teste do Android lê de lá; o Swift lê sua própria cópia. **Recomendado: (a)**, numa mudança separada da reorganização.
- **Leitura no Kotlin:** `sourceSets["test"].resources.srcDir("../shared-fixtures")`; JUnit 5 `@TestFactory`.
- **Geração dos *golden*:** um teste Swift "gerador" desligado por padrão (ativado por variável de ambiente) que imprime os resultados; precisa rodar no iPhone **com concordância do dono**.
- **Exemplos** (forma; valores reais vêm do *golden*):
  ```json
  {"version":1,"timeZone":"America/Sao_Paulo",
   "xp":[{"kind":"musculacao","minutes":60,"effort":5,"expect":30}]}
  ```
  ```json
  {"version":1,"random":[{"seed":"uidA-LIGA01-2026-1-5","state":["<golden UInt64>"],"next":["<golden>"]}],
   "pair":[{"ranked":["a","b","c","d"],"met":{"a":{"b":1},"b":{"a":1},"c":{"d":1},"d":{"c":1}},"byes":{},
            "expect":{"pairs":[["a","c"],["b","d"]],"bye":null}}]}
  ```
  `xp(musculacao, 60, 5) == 30` está em `GymBrosTests/GameTests.swift:10`; o caso de `pair` está em `SwissTests.testAvoidsRematchWhenPossible`.

## 7. Critérios de prontidão
- iOS: mesma contagem de testes antes e depois de cada mudança; 0 falhas no iPhone.
- Android: grupos **A, B e C** passando na JVM antes de qualquer tela que mostre placar (ranking, tetos e bro do time são do grupo B; correção da revisão).
- Robolectric roda em JUnit 4: com JUnit 5, usar o motor *vintage*. Robolectric baixa os jars `android-all` pela rede e ocupa disco (RSK-08).
- Nenhum vetor depende de `.now` ou `Calendar.current`.
- Compilar não conta como prova.
