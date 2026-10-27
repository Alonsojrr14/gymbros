# Matriz de requisitos conferidos no código

**Escopo.** Requisitos de `docs/requisitos-funcionais/` e `docs/requisitos-nao-funcionais.md` conferidos no código, com os IDs existentes; requisitos novos no mesmo padrão; regras de negócio críticas para a paridade com o Android. **Não duplica `docs/`**: a descrição de cada requisito continua lá; aqui ficam status, evidência e divergência.
**Base de evidência.** `requirements-analyst` (Opus 5.5, dois recortes) + conferência do orquestrador (O) nas regras críticas. HEAD `7ab62342` + trabalho não commitado.
**Status.** Rodada 1, concluída nas três seções. Os itens marcados como I ficam para conferência linha a linha numa rodada futura. IDs novos: RF-JOG-43…47, RF-SOC-57…63, RF-TRE-50…55, RNF-56/57.

Legenda: **V** VERIFIED · **C** CONFLICTING (doc ≠ código; o código vence) · **I** INFERRED/não conferido linha a linha · **U** UNKNOWN.

## 1. RF-JOG (`01-jogo-e-bros.md`, 42 IDs)

| ID | St | Evidência / divergência |
|---|---|---|
| RF-JOG-01 | V | `LogActivityView.swift:19-20,93` (60 min, esforço 6, 5–240 de 5 em 5) |
| RF-JOG-02 | V (O) | `Game.swift:475-479` |
| RF-JOG-03 | V | `Game.swift:516-531`; entrada agora é `round(xp × share)` antes dos tetos (ver RF-JOG-43) |
| RF-JOG-04 | C | textos conferem (`LogActivityView.swift:196-200`); a regra de donos herda a mudança do RF-JOG-18 |
| RF-JOG-05 | V | `Game.swift:481` `Int(sqrt(xp/5)) + 1` |
| RF-JOG-06 | V | `Game.swift:568-592`; `WidgetShared.swift:45-49` |
| RF-JOG-07 | V | `Game.swift:95-108`, `:450` |
| RF-JOG-08 | C | limiares 0/60/300/1200/3600 conferem (`Game.swift:127-135`); "apagar recalcula e pode regredir" é falso → RF-JOG-44 |
| RF-JOG-09 | C | dominante e desempate F→R→A→T conferem (`Game.swift:497`); Atleta→Lenda com galho diferente vira **Lenda de virada** → RF-JOG-45 |
| RF-JOG-10 | V (O) | `Game.swift:484-494` (híbrido se 2º ≥ 90%) |
| RF-JOG-11 | V | `Game.swift:458-465` (inclui `origin`) |
| RF-JOG-12 | V | `Hatch.swift`; `Game.swift:418-428`; `App.swift:471` |
| RF-JOG-13 | V | `OnboardingView.swift:80` |
| RF-JOG-14 | C (O) | doc: principal recebe só o XP não postado. Código: principal recebe **sempre 100%** (`Monsters.swift:46-57`) |
| RF-JOG-15 | I | — |
| RF-JOG-16 | V | `Monsters.swift:258`; bro pode sair por troca (RF-JOG-46) |
| RF-JOG-17 | C (O) | ovo adotado pela liga recebe **80%** (`leagueShare = 0.8`), não 100% |
| RF-JOG-18 | C (O) | ver RF-JOG-43 |
| RF-JOG-19 | V | `WidgetShared.swift:31-42`; `HomeView.swift:74` |
| RF-JOG-20 | I | — |
| RF-JOG-21 | C | barra: **Feed**, Treino, [bro], Ligas, Mapa (`App.swift:172-176`); não há aba Histórico |
| RF-JOG-22 | V | `EvolutionView.swift:68-73` |
| RF-JOG-23 | I | — |
| RF-JOG-24 | C | BroBook tem **897** formas (ovo + 8 espécies × 112, incluindo 90 viradas), não 177 (`DexView.swift:149-151`) |
| RF-JOG-25 | C | herda o 24 |
| RF-JOG-26 | V | `Companion.swift:120-147` (28 conquistas) |
| RF-JOG-27 | V | `HistoryView.swift:19` (fora da barra) |
| RF-JOG-28 | I | — |
| RF-JOG-29 | I | editar ainda recalcula (não chama `retire`) |
| RF-JOG-30 | C (O) | apagar chama `RetiredActivities.retire` (`ActivityDetail.swift:224-227`): o XP **fica** |
| RF-JOG-31 | V | `SettingsPages.swift:38-40` |
| RF-JOG-32 | V | `Companion.swift:204` |
| RF-JOG-33 | V | `WidgetShared.swift:79` |
| RF-JOG-34…38 | I | — |
| RF-JOG-39 | V | `StoryShare.swift:305` (1080×1920) |
| RF-JOG-40 | V (O) | divisão gravada por atividade; `AttributeSplit.swift:248-309`; ver ND-5 |
| RF-JOG-41 | C | tutorial tem **10** passos (bro, registrar, aba-treino, treino-hoje, ligas, mapa, feed, voltar-bro, atalhos, pronto; `OnboardingStep.swift:51-80`), não 9 |
| RF-JOG-42 | I | `DexEntryTests` existem; lista deve incluir viradas |

### Novos (RF-JOG)
| ID | Nome | Evidência | Testes |
|---|---|---|---|
| RF-JOG-43 | XP compartilhado: principal 1,0×; cada representante de liga distinto 0,8× (uma vez por bro); principal que também representa recebe só 1,0×; dono que saiu em troca não recebe | `Monsters.swift:46-57` (O); `Game.swift:517` | `GameTests.testMainAlwaysGetsXPAndLeagueRepGetsAShare`, `testLeagueShareGivesLessXP` |
| RF-JOG-44 | Atividade apagada mantém o XP (`RetiredActivities`, sincronizado na conta; "Recomeçar jornada" limpa) | `RetiredActivities.swift`; `Monsters.swift:94-101`; `ActivityDetail.swift:227` (O) | `RetiredActivityTests.testDeletingActivityKeepsTheBroXP` |
| RF-JOG-45 | Lendas de virada: chave `ultimate_<origem>_to_<saída>`, 90 por espécie, nomes em `Viradas.swift`, no BroBook mesmo sem arte | `Game.swift:143-162`; `Viradas.swift` | `testLegendTurnsWithinChampionLine`, `testEveryChampionHasItsOwnTenLegends` |
| RF-JOG-46 | Troca de bros entre amigos: 1 por 1, 48 h, ovo/bro em X1/representante não entram; bro chega com `SnapshotBase` e histórico; quem sai perde o XP | `Trades/Trade.swift:6-8,47,59-63` | `TradeTests.testArrivingBroKeepsFormAndXPAndLeavingOneTakesItsXP`, `testEggsCannotBeTraded` |
| RF-JOG-47 | Aba Feed na barra e no tutorial | `App.swift:172`; `OnboardingStep.swift` | `OnboardingTests` |

## 2. Ligas, suíço, X1, metas e constância (`03-social-e-dados.md`)

### Divergências
| ID | St | Divergência |
|---|---|---|
| RF-SOC-06 | V; texto do app C | doc correto (distância/kcal do Saúde não contam); `LeagueScoring.detail` (`Leagues.swift:141-142`) diz o contrário na interface |
| RF-SOC-12 | C | critério "o principal não recebe aquele XP" invertido (ver RF-JOG-43) |
| RF-SOC-37 | C | tabela do bônus suíço omite `dias 1/0` e `atividades 10/5` (`Swiss.swift:116-125`) |
| RF-SOC-38 | C | X1 é **só entre amigos** (`DuelStore.swift:135,193`) e **cada bro luta um X1 por vez** (`Duel.swift:247-249`); doc diz "qualquer pessoa" |

### Regras críticas (porte bit a bit)

**Bro e XP** (V, O): estágios 0/60/300/1200/3600; `xp = max(round(clamp(min,0,240) × MET × (0,6 + 0,08 × clamp(esforço,1,10)) / 10), min>0 ? 1 : 0)`; MET por categoria (`Game.swift:77-91`: musculação 5, crossfit 8, corrida 9,5, caminhada 3,5, bike 7, natação 8, vôlei 5, futebol 7, lutas 9, dança 5, yoga 3, outro 5); pesos de atributo por categoria (`Game.swift:95-108`); no `snapshot`: ordenar por data, `raw = round(xp × share)`, dia pelo fuso do aparelho, até 150 cheio, excedente /3 (divisão inteira), teto 300/dia; atributos `gained × peso`; ao cruzar limiar usa atributos da fase (ou os da anterior se vazia); galho = dominante (empate na ordem F, R, A, T) e híbrido se 2º ≥ 90%; Lenda guarda `origin` (virada se diferente). Espécie: `speciesID` gravado ou `Species.hatch` (maioria > 0,5 dos minutos por `Hatch.species`, sorteio `SeededRandom(uuid.uuidString)` entre candidatas, índice `Int(next × n) % n`; sem maioria: coelho; ordem fixa de `Species.all`).

**Pontos do check-in** (V): `League.score` = 0 se `activityRule` não aceita (`"only:1,2"`/`"except:…"`/`""`; `workoutTypeID` nil sempre aceito) → bruto por modo → foto (`(s+1)/2` na metade; 0 se obrigatória; negativo não passa). Por modo (`Leagues.swift:150-166`): **pontos** `Game.xp` sem teto e sem share, com pesos `round(xp × Σ kind.weights[a] × (w[a] ?? 1))` usando a **tabela fixa da categoria**, não a divisão gravada; **treinos/dias** 1; **minutos** `min(min,240)`; **distância** `Int(meters ?? 0)`; **calorias** `Int(round(kcal ?? activeKcal))` com `activeKcal = max(MET×(0,6+0,08e) − 1, 0) × 3,5 × 70/200 × min` (minutos sem teto); **atividades** pela tabela `pointRules` (linha mais específica: tipo > seção; `perCheckIn` = pontos; `perAmount` = `floor(amount/every) × pontos`, `every ≤ 0` → 0; padrões 1/30/minutos). Atividade do Saúde entra com esforço 5, sem metros nem kcal. Check-in agrupado soma partes, foto por parte.

**Feed, tetos, ranking** (V): pendentes valem 0 → dias ativos (primeiro check-in > 0 por `pessoa|dia` no **fuso do aparelho**) → tetos `ScoringLimits.apply` (do mais antigo ao mais novo, corte no mais novo; períodos dia/semana/mês/total em `settings.calendar()` = fuso do aparelho + `weekStart`) → ranking: todos aparecem; `checkIns` conta também os de 0; `reachedAt` = último que pontuou; soma bônus suíço; desempate `primeiro` (reachedAt asc, nil no fim) | `sequencia` (bestStreak desc) | `checkins` (desc) → **"eu primeiro"** → `name <` (sem locale). Times: soma dos membros − corte do teto do time; ids `t0…` antigos, novos `"x" + 8 hex`.

**Suíço** (V, O): ver `../descoberta/indice-evidencias.md` E-09/E-10. Bônus (`Swiss.swift:116-125`): pontos 10/5, minutos 5/2, distância 500/250, calorias 50/25, treinos 1/0, dias 1/0, atividades 10/5; folga = vitória.

**Campeões** (V): para semana/mês/ano, períodos de `settings.calendar()` desde `league.start` até `min(now, end)`; vencedores = todos com o placar do 1º se > 0.

**X1** (V): métricas xp (`Game.xp`, sem teto diário) | treinos 1 | minutos sem teto | distância `Int(meters ?? 0)` | calorias `Int(kcal ?? min × MET × 1,2)` (trunca); janela 24 h (pendente expira em `createdAt + 24 h`; ativo até `answeredAt + 24 h`); conta atividades com `date ≥ aceite && < fim && ≤ now`; empate se igual; valor informado até 3 600 s após o fim; par cruzado: vale o mais antigo por `(createdAt, id)`.

**Metas** (V, `Constancy.swift:7-205`): métricas check-ins, dias ativos, minutos, distância (inclui Saúde; local), calorias; filtro por tipos; cadência dia/semana/mês/ano ou prazo único; sequência descarta o período atual não batido. **Constância** (`:236-270`): `topWeekday`/`topHour` usam `Dictionary.max` (**não determinístico em empate**).

**Outras constantes**: verificação exata −30 min/+60 min (`LeagueRules.swift:262-263`); `backlogOptions` [0,1,7,30,−1]; pose do dia `SeededRandom("pose-A-M-D") % 14` no fuso do aparelho (`LeagueRules.swift:393-397`; comentário diz "igual em todos os aparelhos" — **C**); código de liga com 6 de `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`.

### Novos (RF-SOC)
| ID | Nome | Evidência | Testes |
|---|---|---|---|
| RF-SOC-57 | Dias ativos e tetos (ordem do pipeline; corte nos mais novos) | `Leagues.swift:586-593`; `LeagueRules.swift:518-537` | `testActiveDaysCountOncePerDay`, `testIndividualDailyCap` |
| RF-SOC-58 | X1 só entre amigos e um X1 por bro | `DuelStore.swift:135,193`; `Duel.swift:247-249` | `TradeTests.testDuelsOnlyBetweenFriends`, `DuelTests.testEachBroFightsOneDuelAtATime` |
| RF-SOC-59 | Metas pessoais com cadência, prazo e modelos | `Constancy.swift:7-205` | `ConstancyTests` (6) |
| RF-SOC-60 | Recordes de constância | `Constancy.swift:236-270` | `testConstancyRunsAndHabits` |
| RF-SOC-61 | Check-in agrupado pontua por parte | `CheckInProof.swift:341` | **sem teste** |

## 3. RF-TRE, restante do RF-SOC e RNF (lote 2)

**Achado geral:** muitas linhas "Situação" do RF-SOC e boa parte dos RNF ainda descrevem um servidor simulado ou o CloudKit. O backend ativo é o Firebase (`Backend.swift:51,88-99`). `docs/privacidade.md` está quase toda certa; os RNF de privacidade, não.

### RF-TRE (`02-treino.md`)
| ID | St | Evidência / divergência |
|---|---|---|
| 01–07, 13, 15–21, 38, 40, 46, 47, 49 | I | símbolos existem (`TrainView`, `WorkoutView`, `LiveWorkout`, `Retrospective`); números não conferidos |
| 03 | V | `Progression.swift:355-404`; descanso do modelo pronto = 120 s (grupo pesado e ≥4 séries) ou 90 s, que a doc não cita |
| 08 | V | `Progression.swift:150-160` (`rampShare` 0,8) |
| 09, 10, 11, 12, 22, 23, 25, 26 | V | `Progression.swift:35-136,166-335`; `PR.swift:33-45`; `LiveWorkout.swift:203-229` |
| 14 | V | `SwapExercise.swift:22-35` |
| 24 | V* | `PR.swift:16-45`; PR com mais de 12 reps não tem 1RM e usa a própria carga se `pr.reps ≥ reps` (a doc não diz) |
| 27 | V | `wger.json`: 237 entradas (227 com imagem, 33 com vídeo) + 34 em `new`. **README diz 262: C** |
| 30, 31 | V | `MuscleViews.swift:74`; `WeeklyVolume.swift:9,58` |
| 32 | C | a doc lista 4 formatos de WOD; o código tem 6, com `.every` e `.intervals` (`Wod.swift:8-16`) |
| 33, 36 | V | `Wod.swift:818,907-937`; `BodyTrackerView.swift:369-371` |
| 34 | C | data = abertura do treino (com aquecimento), minutos = `max(editável, wodMinutes)`, nota leva o nível (`Wod.swift:988-1104`) |
| 41 | V* | sem sexo informado usa a fórmula masculina (`BodyProfile.swift:101-131`) |
| 42–45 | I/V | `WodImport`, `WodTimeline`, `WodMovements`, `ManualWorkout` com testes |

### RF-SOC (fora ligas/suíço/X1/metas/constância)
| ID | St | Divergência |
|---|---|---|
| 13–16, 18, 28, 30, 33–35, 52 | C | "Situação: simulado/CloudKit"; rodam no Firebase |
| 23 | C | doc: ao vivo "não envia nada"; envia a cada 30 s (`FirebaseSocial.swift:157,206-213`) |
| 39 | C | doc: a música "não sai do iPhone"; vai no ao vivo |
| 24, 25, 26, 50, 51 | V | `HealthSync.swift:13,43-188`; `ProStore.enforced = false`; `NoPhotoStore` |
| 55 | C | o post leva também o nome da fonte do Saúde (SEC-A6) |
| 17, 19–22, 27, 29, 31, 32, 36, 47–49, 53, 54, 56 | I | — |

### RNF
| ID | St | Divergência |
|---|---|---|
| 01, 09, 11, 14, 20, 21, 23, 25, 28, 38, 39 | V | — |
| 04 | C | existe app do relógio (watchOS 10) |
| 06 | C | há uma segunda dependência (firebase-ios-sdk 13.x) |
| 07, 07a, 07e, 08, 18, 24, 37, 42–47, 51 | C | descrevem servidor simulado ou CloudKit e "nada sobe"; hoje sobem a cópia da conta (com peso, medidas e dados do Saúde), DMs, ao vivo e música |
| 10 | C | o texto da permissão de localização mudou para "seus amigos veem onde você está treinando" (pbxproj:592) |
| 12 | C | a câmera existe (`CheckInProof.swift:269`) |
| 26 | C | `UIBackgroundModes` também tem `workout-processing` |
| 30 | C | o schema é `SchemaV5`, não V2 |
| 36 | C | 358 testes em 41 arquivos |
| 49 | C | conteúdo vem também do Everkinetic e do Commons |
| 50 | C | a música sobe no ao vivo |
| demais | I | — |

### Novos (lote 2)
| ID | Nome | Evidência | Testes |
|---|---|---|---|
| RF-TRE-50 | Formatos "A cada" (E2MOM) e blocos com descanso | `Wod.swift:49-55,880-884` | `testEveryFormats`, `testTecnofitBlocks` |
| RF-TRE-51 | Níveis do WOD do coach (Scale/Amador/RX) | `WodImport.swift:137-191`; `Wod.swift:98-102,522-527` | `WodLevelsTests` |
| RF-TRE-52 | Cargas do WOD e % do PR (barra 20/15/10; % entre 30 e 110; Epley; arredondamento ao incremento, nunca abaixo da barra) | `WodLoads.swift:19-160` | `testPercentOfPR`, `testFirstSetCountsBar` |
| RF-TRE-53 | Complex | `WodImport.swift:236-270` | `testComplexIsBrokenIntoItsMovements` |
| RF-TRE-54 | Esquema do WOD e cronômetro por parte | `WodLoads.swift:374-420`, `WodRun.swift` | `testRoundsAndLadder`, `testChipper` |
| RF-TRE-55 | Barra: "kg anilhas" na musculação × "kg total" no CrossFit; mínimo de 20 kg no aquecimento só com barra incluída | `Exercises.swift:111-118`; `LiveWorkout.swift:225` | `NamesAndBarTests` |
| RF-SOC-62 | Gravação no Apple Watch e ponte com o iPhone | `WatchBridge.swift:98-157` | **sem teste** |
| RF-SOC-63 | Tela de abertura da conta e envio da cópia (carregando, falha, tentar de novo, sair; espera de 5 s) | `AccountSync.swift:317-340` | `AccountSyncTests` |
| RNF-56 | Dado do Saúde (inclusive do relógio) fora de posts, X1 e prova | — | **hoje C** (SEC-A5, SEC-A6) |
| RNF-57 | Firebase como backend ativo (substitui RNF-07, 08, 18, 37, 42–47) | `Backend.swift:51` | — |

### Regras de treino para portar exatamente (V, `Progression.swift`, `PR.swift`, `Exercises.swift`, `WodResult.swift`)
- **Incremento:** 5 kg só se o grupo é pesado (costas, quadríceps, posterior, glúteos, panturrilha) **e** o equipamento é barra; senão 2,5 kg.
- **Séries de trabalho:** peso ≥ 0,8 × a maior carga do exercício no treino. Sessões de deload não entram no histórico.
- **Progressão sem objetivo:** sucesso = todas as séries pedidas com reps ≥ meta → +incremento. Por tempo: +5 s. Peso do corpo: +1 rep. 3 falhas seguidas → `floor(carga × 0,9 / inc) × inc`.
- **Dupla progressão por objetivo:** Força 3–6 / 180 s; Hipertrofia 8–12 / 90 s; Resistência 15–20 / 60 s.
- **Deload semanal:** com ≥ 5 semanas seguidas; carga `round(s × 0,7 / inc) × inc`; séries `max(1, round(sets × 2/3))`.
- **Aquecimento:** 40%×10, 60%×6, 80%×3 (round), só no 1º exercício com sugestão ≥ 20 kg.
- **1RM:** Epley `w × (1 + r/30)` para 1 a 12 reps. Primeira carga a partir do PR: `floor(1RM / (1 + r/30) × 0,92 / inc) × inc`. `repTable` com 12, 10, 8, 5 e 3 reps (round).
- **Arredondamentos:** a falha e a primeira carga do PR arredondam **para baixo**; o deload semanal, o aquecimento, o % do PR e o `repTable` arredondam **para o mais próximo**.
- **Anilhas:** [25, 20, 15, 10, 5, 2,5, 1,25], escolha gulosa com tolerância 1e-4.
- **Pontuação do WOD:** CAP = −10 000 000 + reps; For Time = −segundos; AMRAP = rodadas × 1000 + reps.
- **Esforço de treino do Saúde:** `clamp(round(5 × kcal / max(esperado − basal, 1)), 1…10)`, ou 5 sem kcal.
- **Formatação:** vírgula decimal; 2 casas só quando exatas.

### Erro, sem rede, carregando e vazio (V)
- Conta: `AccountLoadingView` com carregando, falha, "Tentar de novo" e "Sair". O envio falha em silêncio (`try?`).
- Ligas: itens com `syncedAt = nil` são reenviados ao abrir e 2 s depois de cada mudança; `LeagueOutbox`; o erro só aparece no diagnóstico de Ajustes.
- Moderação: fila com reenvio. Caixa de entrada e trocas: estado "indisponível" e `ProgressView`. Login: "Sem conexão. Tente de novo."
- 34 `GMEmptyState`. **Não existe** monitor de rede nem configuração explícita do cache do Firestore.

### wger (para o Android)
`wger.json` com passos, textos, imagens e vídeos com autor e licença: CC BY-SA 4.0 (410), CC BY-SA 3.0 (147), domínio público, CC0, CC BY. **Share-alike:** traduções e adaptações mantêm a licença. O Android precisa:
- dos mesmos nomes de imagem;
- de uma linha de crédito por item;
- de uma tela de créditos agrupada;
- de vídeo por streaming do wger.de, citado na política de privacidade;
- de juntar os 34 exercícios de `new`;
- de nunca usar o free-exercise-db. `NOTICE.md` está desatualizado e ainda cita fotos que foram removidas: C.

## Lacunas
- RF-JOG 15, 20, 23, 28, 34–38, 42 não conferidos linha a linha.
- Sem teste: dias ativos em outro fuso, bro do time, `myWins`, desempate alfabético, agrupado no modo Treinos, `topWeekday`/`topHour`.
