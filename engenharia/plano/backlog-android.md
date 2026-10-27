# Backlog Android

**Escopo.** Tarefas `AND-xx` em ordem de dependência, com requisitos, critério de aceite e como verificar. Inclui as tarefas `IOS-xx`, correções no iOS que são pré-requisito da paridade e só acontecem com aprovação.
**Base de evidência.** Sequência do `android-architect`, ajustada pelo orquestrador: WorkManager, achados do lote 2 (SEC-A5, regras de treino) e revisão com referências de Compose.
**Status.** Proposta. Nenhuma tarefa aprovada. As fases G (fundação) e H (features) só começam depois dos portões 3 e 4.

## 0. Pré-requisitos do dono e do iOS (antes do Android)

| ID | Tarefa | Requisitos / risco | Aceite | Aprovação |
|---|---|---|---|---|
| IOS-01 ✅ código (testes pendentes) | `LeagueBoard.selfID` = `Backend.myID` (uid do Firebase) | RSK-01, ND-1 | teste novo com `identity` = uid; mesmo pareamento em dois aparelhos (conta de teste) | dono (edita Swift) |
| IOS-02 ✅ código (testes pendentes) | Exclusão de conta: (a) `reports` (liberar `list` do autor ou tirar da exclusão); (b) `allow delete` em `live/{id}` para o dono; (c) reautenticar antes de apagar; (d) corrigir `docs/excluir-conta.md` | RSK-02 | regras simuladas no emulador ou no Rules Playground; depois conta descartável excluída de ponta a ponta no iPhone | dono (regras + Swift + docs) |
| IOS-06 ✅ código (testes pendentes) | Fotos perdidas ao sair e entrar (`exportedAt` truncado × `savedAt` com fração) | RSK-15 | teste: sair e entrar com foto de medida, e a foto volta | dono (Swift) |
| IOS-03 ✅ código (testes pendentes) | kcal e fonte do Saúde fora de posts, X1 e prova (relógio incluído) | SEC-A5, SEC-A6, RNF-56 | teste novo em `WatchBridge.link` e `proof.device` | dono (edita Swift) |
| IOS-04 ✅ (vetores em `ios/GymBrosTests/Fixtures`, sem mexer no pbxproj) | Teste "gerador" de vetores *golden* (grupos A, B e C), desligado por padrão, e `shared-fixtures/` no pbxproj | estratégia §6 | JSON e binários gerados no iPhone e versionados | dono (pbxproj + execução no iPhone) |
| IOS-05 ✅ código e regras (C1, C2); **deploy pendente com o dono** | Regras do Firestore: C1 (`live` exige amizade mútua), C2 (código de amigo reservado) e confirmação no deep link do iOS | SEC-C1, SEC-C2 | revisão de regras + teste com emulador do Firebase **ou** conta de teste | dono (deploy de regras) |
| IOS-07 ✅ | Fuso fixo `America/Sao_Paulo` em todas as regras de liga (dias ativos, tetos, janelas, campeões, pose do dia, renovação, bro do time) e desempate final por `uid` no lugar de "eu primeiro" | ADR-006, ND-2/3/4 | testes com fuso fixo; iPhone em outro fuso vê o mesmo placar | **aprovado (22/10)** |
| IOS-08 ✅ aprovado e implementado (`4b28c7c`, `125fd72`); falta teste com dois aparelhos reais | Fase C da cópia da conta: ler o metadado antes de enviar, mesclar por UUID, lápides, `updatedAt` por entidade, `accountSettings` por chave, lote dividido (RSK-17) | ADR-007, RSK-03/18 | iPhone + segundo aparelho (ou segunda instalação) sem perda; testes de mesclagem | **aprovado (22/10)**; desenho detalhado antes |
| ENV-01 ✅ disco e JDK; falta conectar o aparelho Android | Liberar disco (ex.: `build/` com 10 GB), instalar JDK 17, plataforma alvo do SDK, ter um aparelho Android | RSK-08 | `java -version`, `df -h /`, `adb devices` | dono |
| ENV-02 ✅ | Registrar `com.alonsoalmeida.gymbros` e `.debug` no Firebase; `google-services.json` fora do git | ADR-011 | `git check-ignore` confirma | dono |

**Aprovados pelo dono em 22/10:** IOS-01 a IOS-08 (incluindo regras C1/C2) acontecem antes do Android, depois que o dono commitar o trabalho em andamento. Sem eles, o Android ou reproduz os bugs (para ficar igual) ou diverge do iOS.

## 1. Fundação (fase G, `/android-foundation`)

| ID | Tarefa | Depende | Requisitos | Aceite / verificação |
|---|---|---|---|---|
| AND-001 ✅ | Esqueleto `android/` (wrapper Gradle, catálogo de versões, `:core:domain`, `:app`, `.gitignore` do Android) | ENV-01 | ADR-001/002 | `./gradlew help` roda; `google-services.json` ignorado |
| AND-002 ✅ XP, SeededRandom, Swiss.pair, bônus, foto (pontuação de liga por modo e Progression ainda não) | Domínio grupo A: `Game.xp`, `SeededRandom`, `Swiss.pair`, `SwissBonus`, `PhotoRule`/`League.score` (todos os modos, `pointRules`), `Progression`/PR/anilhas | AND-001, IOS-04 | CC-1, CC-4, RF-TRE regras | `./gradlew :core:domain:test` verde com os vetores A |
| AND-003 parcial: DEFLATE, pedaços, datas, bplist e DTOs de atividades/bros/rotinas/ligas ✅; demais DTOs pendentes | Formatos grupo C: `BackupDto` completo, ISO 8601 em segundos, DEFLATE cru + pedaços de 900 000, bplist (`dd-plist`), JSON em texto com datas desde 2001, `Setting` | AND-001, IOS-04 | FS-AND-03/04 | o Android decodifica os vetores do iPhone; o que o Android grava **o iPhone decodifica** (teste no aparelho), com comparação semântica. Ida e volta byte a byte não é exigida, porque o JSON *pretty* do Swift e a escrita de `Double` diferem. O bplist preserva o tipo de cada valor (inteiro, real, booleano) |
| AND-004 parcial: snapshot e tabela suíça ✅; ranking, tetos, campeões, X1 pendentes | Domínio grupo B com `RuleClock`: snapshot (teto, galhos, viradas, espécie), roster 1,0/0,8 + aposentadas, dias ativos e tetos, ranking, campeões, X1, bro do time | AND-002 | RF-JOG-43/44/45, RF-SOC-57/58, CC-2/3/5/6/8 | vetores B verdes |
| AND-005 parcial: tema, tokens, GMCard/GMButton/GMEmptyState ✅ | Tema, tokens (frações RGB), escala de fonte, ~35 `GM*`, `GMTabBar`, spotlight | AND-001 | ADR-005; `referencia-compose.md` | Robolectric: 1/5/50 itens, fonte 1,0 e 2,0, toque ≥ 48 dp |
| AND-006 | Conversão de sprites e do wger (ADR-008) + medição do AAB | dono | RSK-09 | AAB medido; decisão sobre PAD registrada |

## 2. Features (fase H, `/android-feature AND-xx`, uma por vez)

| ID | Tarefa | Depende | Requisitos | Aceite / verificação |
|---|---|---|---|---|
| AND-010 ✅ login (falta conferir login real com a conta do dono) | `AppContainer`, `AuthRepo`, portões da raiz, login/cadastro/redefinição (pt-BR), Credential Manager | AND-005, ENV-02 | ADR-003/009 | aparelho: login certo e errado, sem rede, sessão expirada |
| AND-011 | `AccountStore` + `AccountCopyRepo` com a **mesclagem por UUID do IOS-08** + envio por WorkManager | AND-003, AND-010, **IOS-08** | ADR-004/007, FS-AND-05 | aparelho + iPhone com conta de teste: **nenhum dado perdido em nenhum dos dois** nos cenários do ADR-007, incluindo "iPhone continua logado" e "Android dono + iPhone reinstalado"; estado local guardado à parte antes de qualquer restauração |
| AND-012 | Onboarding, termos, tutorial de 10 passos | AND-010 | RF-JOG-13/41/47 | aparelho; voltar do sistema tratado |
| AND-013 | Bro: XP, evolução, BroBook (897), conquistas, humor | AND-004, AND-006, AND-011 | RF-JOG-05…26, 45 | vetores B + rolagem do BroBook medida |
| AND-014 | Registrar atividade, histórico, editar/apagar (aposentar), treino com rotinas e progressão (modo dono) | AND-011, AND-013 | RF-JOG-01…04, 27…30, 44; RF-TRE | aparelho; cópia sobe e o iPhone (após sair/entrar) vê o treino |
| AND-015 | Amigos + deep link/App Link **com confirmação** | AND-010 | SEC-AND-01 | link de outra pessoa não adiciona sem o toque de confirmação |
| AND-016 | Ligas completas (entrar, pedidos, chat, check-in sem foto e agrupado com `groupedParts`, feed, ranking, suíço, campeões, times), ouvintes econômicos | AND-004, AND-011, **IOS-01**, decisão do ADR-006 | RF-SOC ligas, ADR-013 | **mesmo ranking e mesmo pareamento que o iPhone** numa liga de teste |
| AND-017 | Feed, comentários, DMs, X1, rotinas públicas, denúncia, bloqueio | AND-015, AND-016 | RF-SOC, RF-SOC-58 | aparelho; ações duplicadas não duplicam |
| AND-018 | Perfil público e privado, constância, metas, medidas, mapa muscular, aba Mapa (lista) | AND-013 | RF-SOC-59/60, ADR-012 | Robolectric + aparelho |
| AND-019 | Ajustes, créditos e licenças (wger CC BY-SA, MuscleMap MIT), sair, excluir conta (**reautenticar antes de apagar qualquer coisa**) | AND-011 | RNF, IOS-02 | exclusão de ponta a ponta com conta descartável; nada parcial |
| AND-020 | Segurança: manifesto, R8, backup desligado, componentes não exportados | AND-019 | SEC-AND-02/04/10/11 | `aapt dump`/lint; revisão do `independent-reviewer` |
| AND-021 | Jornadas no aparelho: sem rede, conta nos dois aparelhos, permissão negada, ação duplicada; faixa interna do Play | todas | estratégia §5 | checklist assinado em `resultados-validacao.md` |

## 3. v1.1 e depois (fora da v1, ADR-010)
Health Connect (com a regra do RNF-56), Glance, notificação de treino em andamento e compartilhar ao vivo (depois de SEC-C1), câmera e prova EXIF, story, trocas de bros, cerca de academia, atalhos, mapa visual, mesclagem por UUID na cópia da conta (fase C, iOS + Android), Wear OS.
