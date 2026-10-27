# Resultados de validação

**Escopo.** O que foi executado de fato nesta rodada, com o comando, o ambiente, a saída e as limitações, e o que não foi executado e por quê.
**Base de evidência.** Saídas de comandos observadas pelo orquestrador em 21/10/2026.
**Status.** Rodada 1 (fases A a E). Nada foi compilado, nenhum teste rodou e o app não foi alterado.

## 1. Executado

| # | O quê | Comando / mecanismo | Resultado |
|---|---|---|---|
| V-01 | Ambiente | `git status`, `git log`, `git branch -a`, `df -h /`, `du -sh ~/Library/Android/sdk/*`, `/usr/libexec/java_home`, `which java gradle adb`, `xcodebuild -version`, `swift --version`, `xcrun devicectl list devices`, `xcrun simctl list runtimes` | ver `../descoberta/inventario-repositorio.md` §7 |
| V-02 | Formato de agentes e skills na versão instalada | agente `claude-code-guide` consultando code.claude.com/docs (sub-agents, skills, settings, permissions, cli-reference) | campos confirmados: `name`, `description`, `tools`, `disallowedTools`, `model` (`haiku`/`sonnet`/`opus`/`fable`/`inherit`/ID), `permissionMode`, `skills`, `effort`, `isolation: worktree`, `memory`, `background` etc.; o `model` passado na chamada vence o do frontmatter; **subagente pode criar subagente** (até 3 níveis, se tiver `Agent` nas ferramentas); existe `claude --agent` |
| V-03 | **Carga real de um agente do projeto** | `claude -p --agent repository-analyst --output-format json "…"` num processo novo, na raiz do repositório | `is_error: false`, 3 turnos, `modelUsage` = **`claude-haiku-5-5`** (igual ao frontmatter), sem permissão negada. O agente relatou só `Read` e `Bash` disponíveis: **nesta versão não há ferramentas `Grep`/`Glob`**. Correção aplicada: todos os analistas receberam `Bash` com lista explícita de comandos só de leitura |
| V-04 | Agentes do projeto na sessão principal | ferramenta Agent com `subagent_type: repository-analyst` | **falhou**: "Agent type 'repository-analyst' not found". Os arquivos de `.claude/agents/` são carregados quando a sessão começa; os que foram criados no meio dela não aparecem. Mais tarde, na mesma sessão, o runtime recarregou a pasta e os 10 tipos passaram a aparecer na lista (recarga com atraso, não imediata). **Contorno usado até então:** cada especialista rodou como agente `Explore` (sem Edit/Write, portanto só leitura de verdade), com o `model` do frontmatter passado na chamada e o corpo do arquivo do agente como papel |
| V-05 | Contagem de testes iOS | `grep -h 'func test' GymBrosTests/*.swift \| wc -l` | 358 no disco; 359 no HEAD |
| V-06 | Avaliação das skills externas indicadas pelo dono | agente de leitura pela web | ver a resposta ao dono; nada instalado |

| V-07 | **Linha de base do build iOS** (22/10/2026 00h10, com o trabalho não commitado do dono) | `xcodebuild -project GymBros.xcodeproj -scheme GymBros -destination 'id=00008150-001E15363C04C01C' -derivedDataPath build -allowProvisioningUpdates build` (Xcode 27.1) | `exit 0`, **BUILD SUCCEEDED**, 113 s, 18 avisos. Não instalado. Disco: 3,6 GB → **2,3 GB** livres |
| V-08 | Suíte de testes iOS | adiada pelo orquestrador: autorizada pelo dono, mas eram 00h10, fora da janela segura (10h–23h50) | — |

| V-09 | **Limpeza autorizada pelo dono** ("pode apagar tudo que você não precisa mais ou pode regenerar depois"), 22/10/2026 | `rm -rf` em `build/` (10 GB, ignorado pelo git), DerivedData do Xcode (GymBros, GymMonsters, documentos sem nome, `ModuleCache.noindex`, `SDKExplicitPrecompiledModules`) e `~/Library/Android/sdk/{system-images,emulator}` | 15 GB liberados; disco de 2,3 GB para **18 GB livres**. **Mantidos de propósito:** AVD `~/.android/avd/flw1868old` (2,6 GB, guarda dados próprios; pergunta ao dono), `tools/artes/.work-viradas` (580 MB, artes geradas por IA, sem garantia de gerar igual), DerivedData de outro projeto (`ArCondicionado`), `graphify-out`, runtimes de simulador (montados pelo sistema). Efeito: o próximo build iOS é completo e baixa de novo os pacotes SPM. A licença MIT da MuscleMap, antes lida em `build/SourcePackages`, volta a ficar disponível depois desse build |

| V-10 | **Lote 1 de correções iOS** (branch `ios/correcoes-paridade`, commit do lote): IOS-01, IOS-02 (app + regras), IOS-03, IOS-06, C1 (regra + confirmação no deep link) | `xcodebuild … build-for-testing` (exit 0, `TEST BUILD SUCCEEDED`) e `xcrun devicectl device install app …` (**App installed**), 22/10 de madrugada | compila; instalado. **Testes ainda não executados** (janela das 10h; ver P11). **Regras não publicadas**: deploy é ação do dono |

| V-11 | **Linha de base dos testes iOS** sobre `0f5c116b` (cópia em `git worktree`), 22/10 00h55–01h01 | `xcodebuild test … -resultBundlePath base.xcresult` no iPhone | **358 testes, 0 falhas** |
| V-12 | Testes da branch de correções (IOS-01/02/03/06, C1, IOS-07, C2) | `xcodebuild test` no iPhone, 01h02 | **367 testes, 0 falhas** (358 + 9 novos); comparação com V-11: nenhuma regressão |
| V-13 | Instalação do JDK | Temurin 17.0.20.1 (`.tar.gz` oficial, checksum SHA-256 da API da Adoptium conferido) em `~/Library/Java/JavaVirtualMachines`, sem senha | `java -version` OK; `/usr/libexec/java_home -v 17` encontra |
| V-14 | Gradle | distribuição 8.14.3 com checksum oficial conferido; wrapper gerado em `android/` | — |
| V-15 | Domínio Android, grupo A | `./gradlew :core:domain:test` | 11 testes, 0 falhas |
| V-16 | **Vetores golden gerados no iPhone** | `TEST_RUNNER_GYMBROS_GOLDEN=1 xcodebuild test -only-testing:GymBrosTests/GoldenVectorsTests`; anexos extraídos com `xcresulttool export attachments` | 3 vetores (A 196 KB, B 235 KB, C 5 KB). **E-06 confirmado**: DEFLATE cru (1º byte `0x8d`; abre com `wbits=-15`); datas de 2001 confirmadas |
| V-17 | Conferência dos vetores no iOS | `-only-testing:GymBrosTests/GoldenVectorsCheckTests` | 2 testes, 0 falhas; JSON só no pacote de testes |
| V-18 | **Paridade Android × iOS por vetores** | `./gradlew :core:domain:test` | 19 testes, 0 falhas: 1 344 XP, `SeededRandom` bit a bit, 60 pareamentos, foto; 12 snapshots (atributos bit a bit), 10 tabelas suíças; cópia da conta (DEFLATE, JSON, datas, bplist) |
| V-19 | **Reorganização para `ios/`** | `git mv` + `xcodebuild test -project ios/GymBros.xcodeproj` + `devicectl install` | **372 testes, 0 falhas, 3 pulados** (geradores); **App installed**; pbxproj intacto; Android 19/19 com o caminho novo |
| V-20 | Módulo `:app` Android | `./gradlew :app:assembleDebug` | APK de depuração compila (10 MB). **Não instalado**: nenhum aparelho Android conectado (`adb devices` vazio) |

| V-21 | Grupo L (pontuação de check-in) | gerador no iPhone + `GoldenVectorsCheckTests` (3/3) + `LeagueScoreTest` | 600/600 check-ins iguais; kcal bit a bit; catálogo de 80 tipos; 0 casos de ND-9 em 43 com pesos |
| V-22 | **Revisão independente do código da noite** (`independent-reviewer`, Fable 5.1) | leitura de `0f5c116b..HEAD` | 1 bloqueio (B1) + 5 de alta prioridade + melhorias; todos corrigidos no commit `81d9f34`, exceto M4 (fuso dos testes) e M5 (aviso de "O que há de novo") |
| V-23 | Correções da revisão | `xcodebuild build-for-testing` (`TEST BUILD SUCCEEDED`); Android 23/23 | **Suíte no iPhone NÃO executada**: o aparelho bloqueou a tela às ~01h40 ("Lost connection to testmanagerd"; `lockState passcodeRequired: true`). Instalado no iPhone continua o build de `e139cd7` (antes destas correções) |

| V-24 | **Suíte completa no iPhone sobre `33bfb7b`** (correções da revisão + ND-9), 22/10 10h29 | `xcodebuild test -project ios/GymBros.xcodeproj …` + `devicectl install` | **375 testes, 0 falhas, 4 pulados** (geradores A, B, C, L); **App installed**. Fecha a pendência do V-23 |
| V-32 | Grupo R (formas, espécies, humor, plantel) | gerador no iPhone + `GroupRTest` | 904 formas, 30 plantéis (1.037 atividades, apagadas, trocas, ligas) bit a bit; dia na era e humor iguais |
| V-33 | Grupo M (mesclagem IOS-08) | gerador no iPhone + `GroupMTest` | 80/80 mesclagens iguais (42 com conflito, 16 sem base), inclusive o plist de ajustes |
| V-34 | Grupo S (divisão do XP entre atributos) | gerador no iPhone + `GroupSTest` | 14.400 casos; 168 diferem só no desempate não determinístico do iOS (ND-10) |
| V-35 | Android no Redmi com a conta real | instalação + capturas | tela inicial, foto do perfil, abas e Nova atividade abrindo com os dados reais; nenhuma atividade de teste gravada |

| V-25 | Registro dos apps Android no Firebase (pedido do dono) | Firebase CLI 14.27.0 instalada em `~/.local/firebase-tools` (sem senha; login já existente do dono); `apps:create ANDROID` × 2; `apps:sdkconfig` | `com.alonsoalmeida.gymbros` e `.debug` registrados; `google-services.json` em `android/app/` com os dois pacotes, ignorado pelo git; valores não exibidos |
| V-26 | Branches mescladas na `swift` (pedido do dono) | `git merge --ff-only reorg/ios` | `swift` local com 16 commits à frente do `origin`; **sem push** |
| V-27 | IOS-08 parte 1: `BackupMerge` | 13 testes no iPhone | 13/13 |
| V-28 | IOS-08 parte 2: fluxo (transação, base só depois da confirmação, `syncOnOpen`) | suíte completa no iPhone + `devicectl install` | **388 testes, 0 falhas, 4 pulados; App installed**. Mesclagem entre dois aparelhos reais **ainda não exercitada** (precisa do Android ou de um segundo iPhone com a mesma conta) |
| V-29 | Instalação no Android | `adb devices` | primeiro `unauthorized`; depois, autorizado pelo dono |
| V-30 | **App Android no aparelho** (Redmi Note 9S, Android 11 / API 30) | `adb install -r app-debug.apk` (depois de liberar "Instalar via USB" da MIUI e confirmar no celular) + `am start` | **Success**; o app abre sem crash (pid ativo, nenhum `FATAL` no logcat); tela escura com o tema e o XP do domínio (30 XP, igual ao iPhone). O placar "26 - 19" na captura é uma sobreposição de outro app do celular |

| V-31 | **Login no Android (AND-010)** | domínio 26/26 na JVM; `assembleDebug`; `adb install` (Success) | tela de login no aparelho; e-mail inválido mostra "E-mail inválido." (igual ao iOS). **Login real com a conta do dono ainda não testado** (feito por ele no aparelho) |

## 2. Especialistas que rodaram (fase A a E)

| Agente (papel) | Mecanismo | Modelo pedido | Confirmado por metadados? |
|---|---|---|---|
| repository-analyst | `Explore` + papel | haiku | não (só o V-03 confirmou o Haiku no modo `--agent`) |
| ios-architecture-analyst | `Explore` + papel | opus | não |
| firebase-contract-analyst | `Explore` + papel | opus | não |
| security-analyst | `Explore` + papel | opus | não |
| requirements-analyst (2 recortes) | `Explore` + papel | opus | não |
| ui-parity-analyst | `Explore` + papel | sonnet | não |
| qa-strategy-analyst | `Explore` + papel | opus | não |
| android-architect | `Explore` + papel | opus | não |
| independent-reviewer | **tipo do projeto, pelo nome** (frontmatter aplicado) | fable (frontmatter) | só pela identificação do próprio agente ("Fable 5.1, claude-fable-5-1"); a notificação de término não informa o modelo |
| avaliação e revisão com as skills externas (2 agentes) | `general-purpose` | sonnet | não |

"Não confirmado" quer dizer o seguinte: o modelo foi pedido na chamada e a documentação diz que esse parâmetro tem precedência, mas a notificação de término não informa o modelo usado. Numa sessão nova, os agentes serão chamados pelo nome e o frontmatter vale direto.

## 3. Não executado (e por quê)

| O quê | Motivo |
|---|---|
| Build iOS | não havia mudança no app para validar. A linha de base do build será registrada antes da fase F |
| Suíte de testes iOS (358) | roda no iPhone do dono, com os dados reais dele. Precisa da concordância do dono (pergunta P11) |
| Emulador Android | não será usado (imagens apagadas com autorização; o dono tem aparelho físico) |
| Deploy das regras do Firestore | decisão do orquestrador: produção, com o dono dormindo; a regra do C2 recusaria perfis de versões antigas do app. Fica para o dono |
| Qualquer leitura do Firebase real | proibido nesta fase. As regras publicadas não foram comparadas com o arquivo local |
| Scripts de `tools/` | proibido. O cálculo de raiz foi conferido por leitura |
| Hipóteses que dependem de execução | E-06 (DEFLATE cru), E-10 (efeito do `selfID`), exclusão de conta (RSK-02): conferidas só pelo código |
| V-36 | Regras do Firestore publicadas pelo dono (22/10, 17h30) | `firebase deploy --only firestore:rules` | compilou e foi ao ar: reserva `friendCodes`, `live` só entre amigos, `reports` listáveis pelo autor, `live` apagável pelo dono |
