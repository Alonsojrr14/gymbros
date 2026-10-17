# Requisitos não funcionais — GymBros (iOS)

Levantados a partir do código e da configuração do projeto `GymMonsters.xcodeproj` (outubro/2026).
Cada requisito descreve o comportamento atual e traz um critério verificável e a fonte. Quando o item
não é fato do código, e sim algo que o app deveria passar a cumprir, ele aparece marcado como **Recomendação**.

Convenções de fonte: `pbxproj` = `GymMonsters.xcodeproj/project.pbxproj`; `Info.plist` = `GymMonsters/Info.plist`;
chaves `INFOPLIST_KEY_*` são geradas no build a partir do `pbxproj`.

---

## 1. Plataforma e compatibilidade

**RNF-01 — Versão mínima do iOS.** O app, o widget e os testes rodam a partir do iOS 17.0.
Critério: `IPHONEOS_DEPLOYMENT_TARGET = 17.0` em todos os alvos; o app instala e abre num aparelho com iOS 17.
Fonte: `pbxproj` (`IPHONEOS_DEPLOYMENT_TARGET`, `SDKROOT = iphoneos`).

**RNF-02 — Recursos condicionados ao iOS 18.** Recursos que exigem iOS 18 ficam atrás de `#available` e não
quebram o app no iOS 17: tradução no aparelho das instruções em inglês (`TranslationSession`, en → pt-BR) e
controles de treino da Central de Controle / widget interativo.
Critério: no iOS 17 as instruções do wger em inglês aparecem em inglês (com o crédito) e os controles não são oferecidos, sem erro.
Fonte: `GymMonsters/MuscleViews.swift` (`TranslateSteps`), `GymMonstersWidget/WorkoutControls.swift`, `GymMonstersWidget/GymMonstersWidget.swift` (l. 176).

**RNF-03 — Somente iPhone, em retrato e tema escuro.** Não há versão para iPad nem paisagem; a interface é sempre escura.
Critério: `TARGETED_DEVICE_FAMILY = 1`; `UISupportedInterfaceOrientations_iPhone = UIInterfaceOrientationPortrait`;
`UIUserInterfaceStyle = Dark` e `.preferredColorScheme(.dark)`.
Fonte: `pbxproj`; `GymMonsters/App.swift`.

**RNF-04 — Apple Watch via app Saúde.** Não existe app para watchOS; treinos do Apple Watch chegam pelo HealthKit
(importação) e, se o usuário ligar, treinos do app são gravados no Saúde para contar nos anéis.
Critério: nenhum alvo watchOS no projeto; treino feito no Watch aparece como atividade após abrir o app.
Fonte: `GymMonsters/HealthSync.swift`; `INFOPLIST_KEY_NSHealthShareUsageDescription`.

**RNF-05 — Extensões do sistema.** Widgets (tela inicial e bloqueio), Live Activity / Dynamic Island do treino
e do WOD, e Atalhos (App Intents).
Critério: `NSSupportsLiveActivities = YES`; extensão `com.apple.widgetkit-extension`.
Fonte: `pbxproj`; `GymMonstersWidget/Info.plist`; `GymMonstersWidget/WorkoutLiveActivity.swift`, `WodLiveActivity.swift`; `GymMonsters/Shortcuts.swift`.

**RNF-06 — Dependência externa única.** O único pacote SwiftPM é `MuscleMap` (GitHub).
Critério: `packageReferences` contém só esse repositório.
Fonte: `pbxproj` (`repositoryURL = https://github.com/melihcolpan/MuscleMap.git`).
A licença (MIT) está registrada em `CREDITOS.md` e na tela "Créditos e licenças" (RNF-49).
**Recomendação:** fixar versão exata do pacote.

**RNF-49 — Conteúdo de terceiros com licença comercial e atribuição.** Imagens, vídeos e instruções de exercícios vêm só do wger
(CC BY-SA 3.0, CC BY-SA 4.0 ou CC0, por item), com autor, licença e origem guardados em `GymMonsters/wger.json` e exibidos junto
do conteúdo e na tela "Créditos e licenças". Fotos e instruções do free-exercise-db foram removidas porque reproduziam o
bodybuilding.com, sem autorização de uso comercial; imagens marcadas como geradas por IA no wger são ignoradas. Instruções
traduzidas no aparelho seguem a mesma licença (share-alike), o que não se aplica ao código do app.
Critério: todo item exibido do wger mostra autor e licença; não há imagem nem texto do free-exercise-db no bundle.
Fonte: `GymMonsters/Wger.swift` (`WgerLibrary`, `CreditLine`, `CreditsView`), `GymMonsters/ExerciseExtra.swift` (`ExerciseExtraData.remote` vazio), `tools/wger/build.py`, `CREDITOS.md`.

## 2. Privacidade e dados pessoais

**RNF-07 — Dados só no aparelho, sem conta.** Não há cadastro, login nem servidor; todos os dados ficam no SwiftData
local e em `UserDefaults`.
Critério: nenhum uso de `URLSession` no código do app; o app funciona completo após o onboarding sem rede.
Fonte: `README.md`; `GymMonsters/LiveWorkout.swift` (`AppData.container`); grep por `URLSession` sem resultados.

**RNF-08 — Tráfego de rede limitado a conteúdo público.** As únicas saídas de rede são: vídeo de demonstração do wger
tocado no app (`AVPlayer` com URL de `wger.de`), só quando o usuário toca em "Ver vídeo de demonstração"; links de licença e
de origem nas linhas de crédito; busca de academias no Mapas da Apple (`MKLocalSearch`); e o link externo de busca no YouTube.
As imagens de exercícios estão embutidas no app (catálogo `Wger`), sem download. Nenhuma saída envia dados do usuário além da consulta.
Critério: inspeção de tráfego mostra apenas `wger.de` (vídeo e links, por ação explícita), serviços da Apple e abertura do YouTube por ação explícita; nenhum acesso a `cdn.jsdelivr.net`.
Fonte: `GymMonsters/Wger.swift` (`WgerVideoView`, `CreditLine`), `GymMonsters/Exercises.swift` (`videoURL`), `GymMonsters/Location.swift` (`suggestions`), `GymMonsters/MuscleViews.swift`.

**RNF-09 — HealthKit com consentimento separado para leitura e escrita.**
- Leitura (treinos e massa corporal) — texto: "Para transformar seus treinos do iPhone e Apple Watch em XP para o seu bro."
- Escrita (treinos e energia ativa), só se o usuário ligar — texto: "Para gravar seus treinos do GymBros no Saúde e eles contarem nos anéis do Fitness."
Critério: a escrita só ocorre com `healthWrite` ligado e apenas para atividades criadas depois de ligar (janela `healthWriteSince`); atividades vindas do Saúde nunca são regravadas; a primeira importação cobre só 14 dias.
Fonte: `INFOPLIST_KEY_NSHealthShareUsageDescription`, `INFOPLIST_KEY_NSHealthUpdateUsageDescription`; `GymMonsters/HealthSync.swift` (`requestAccess`, `requestWrite`, `exportPending`, `firstImportDays = 14`); entitlement `com.apple.developer.healthkit`.

**RNF-10 — Localização "em uso" e "sempre".**
- Em uso — texto: "Para gravar o percurso de corridas, caminhadas e pedaladas e marcar a sua academia."
- Sempre — texto: "Para saber quando você chega ou sai da academia: sugerir o treino ao chegar e encerrar o treino ao sair. A localização fica só no seu iPhone."
Critério: o percurso com tela bloqueada exibe o indicador azul de localização em segundo plano; o pedido "sempre" só acontece ao ativar automações de academia.
Fonte: `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription`, `INFOPLIST_KEY_NSLocationAlwaysAndWhenInUseUsageDescription`; `GymMonsters/Route.swift` (l. 81–88), `GymMonsters/Location.swift` (l. 149–157).

**RNF-11 — Notificações locais sob demanda.** Permissão (`.alert`, `.sound`) pedida ao ligar lembretes, ao usar o
timer de descanso ou automações; todas as notificações são locais.
Critério: nenhum registro para push remoto (`registerForRemoteNotifications` ausente).
Fonte: `GymMonsters/SettingsView.swift` (l. 43, 57), `GymMonsters/LiveWorkout.swift` (l. 93, 217), `GymMonsters/Companion.swift`.

**RNF-12 — Fotos sem permissão de biblioteca; sem câmera.** Fotos (perfil, check-in, capa de liga, corpo, story)
são escolhidas pelo `PhotosPicker`, que roda fora do processo e dispensa permissão. O app não usa a câmera.
Critério: não existem `NSPhotoLibraryUsageDescription` nem `NSCameraUsageDescription`, e nenhum uso de `AVCapture`/`UIImagePickerController`.
Fonte: `Info.plist`, `pbxproj`; `GymMonsters/ProfileView.swift`, `LeaguesView.swift`, `BodyTrackerView.swift`, `CheckInDetail.swift`, `ActivityDetail.swift`.
**Recomendação:** se a câmera for adicionada, incluir `NSCameraUsageDescription` em pt-BR antes do primeiro uso.

**RNF-13 — Perfil público × privado.** O que os amigos veem é exatamente a aba Público: foto, nome, @usuário, bio e
o card público, com chaves que o usuário pode desligar (`publicMonster`, `publicStats`, `publicAchievements`).
A aba Privado (números, recordes, metas, peso, medidas, calendário de atividades) nunca é exposta.
Critério: com as três chaves desligadas, a prévia pública não mostra bro, números nem conquistas.
Fonte: `GymMonsters/ProfileView.swift` (l. 34–40, 263–267), `GymMonsters/PublicProfile.swift`; `FriendsBackend.profile` em `GymMonsters/Friends.swift`.

**RNF-14 — Backup em JSON, com poucas imagens.** O backup exporta atividades, rotinas, sessões, ligas, check-ins, recados,
comentários, percursos, academias, corpo etc. Imagens: entram só a foto do perfil (512 px) e a capa de cada liga reduzida
(até 640 px, JPEG 0,6, só da temporada atual); imagens dos check-ins e fotos de progresso ficam de fora. O check-in
restaurado volta sem imagem, mas com a marca `hadPhoto`, então a pontuação nas ligas não muda. O arquivo vai para onde
o usuário escolher (Arquivos/iCloud Drive), sem criptografia.
Critério: restaurar um backup recupera todos os registros, a foto do perfil e as capas; imagens de check-in e de progresso não voltam, e o placar das ligas fica igual.
Fonte: `GymMonsters/Backup.swift` (`make`, `restore`, `smallCover`), `GymMonsters/Leagues.swift` (`LeagueCheckIn.hadPhoto`).
**Recomendação:** avisar na tela de backup que as fotos de check-in e de progresso não são incluídas e que o arquivo contém localização (academias e percursos), medidas corporais e a foto do perfil; considerar criptografar o arquivo.

## 3. Segurança

**RNF-15 — Armazenamento no sandbox, com file protection.** O banco SwiftData fica no container padrão do app; arquivos grandes
(fotos, pontos do percurso, capa) usam `@Attribute(.externalStorage)` no mesmo sandbox. Ao abrir o banco, o app aplica
`FileProtectionType.completeUntilFirstUserAuthentication` ao arquivo do banco e aos auxiliares `-wal` e `-shm` (escolhida em vez
de `complete` porque as automações de academia e o Live Activity gravam com o aparelho bloqueado). A pasta de `externalStorage`
não recebe o atributo explicitamente e fica com a proteção padrão do container.
Critério: nenhum dado do usuário é gravado fora do container do app ou do App Group; os três arquivos do banco têm a classe de proteção `completeUntilFirstUserAuthentication`.
Fonte: `GymMonsters/LiveWorkout.swift` (`AppData.protect`), `GymMonsters/Leagues.swift` (`League.cover`, `LeagueCheckIn.photo`), `GymMonsters/Body.swift`, `GymMonsters/Route.swift`.
**Recomendação:** aplicar o mesmo atributo à pasta de `externalStorage` e ao arquivo de backup exportado.

**RNF-16 — App Group só com dados mínimos para o widget.** O app e o widget compartilham
`group.com.alonsoalmeida.gymmonsters` via `UserDefaults(suiteName:)`; o widget não acessa o banco.
Critério: o widget lê somente o estado resumido (bro, humor, XP, sequência, pose).
Fonte: `GymMonsters/GymMonsters.entitlements`, `GymMonstersWidget/GymMonstersWidget.entitlements`, `Shared/WidgetShared.swift` (l. 89–92).

**RNF-17 — Nenhuma credencial no código.** Verificado por busca por `api_key`, `secret`, `token`, `password`, `bearer`,
`private_key`, `sk-…`, `AKIA…`, `ghp_…` e por arquivos `.env` no repositório (excluindo `build/`): nenhuma ocorrência.
Critério: a mesma busca continua sem resultados a cada PR.
Fonte: varredura do repositório.
**Recomendação:** adicionar um verificador de segredos (ex.: gitleaks) no pipeline. Os scripts `tools/artes/chrome.sh` copiam o perfil do Chrome (com cookies) para `~/Library/Caches/gymmonsters-chrome`, fora do repositório; isso deve continuar fora do versionamento.

**RNF-18 — Chamadas futuras ao servidor exigem autenticação.** Hoje os backends são simulados (`MockLeagueBackend`, `MockFriendsBackend`).
**Recomendação:** toda implementação real de `LeagueBackend`/`FriendsBackend` deve usar HTTPS (ATS padrão, sem exceções no `Info.plist`), token de sessão guardado no Keychain e nunca em `UserDefaults` ou no código.
Fonte: `GymMonsters/LeagueRemote.swift` (l. 88–101), `GymMonsters/Friends.swift` (l. 39–50).

## 4. Desempenho

**RNF-19 — Estado do jogo derivado do histórico, com cache.** XP, estágio, atributos e sequência continuam derivados de
todas as atividades, mas as telas usam `Game.cachedSnapshot`: o resultado fica em `SnapshotCache` (até 24 entradas, a mais
antiga sai primeiro, protegido por `NSLock`), com chave = lista inteira de registros na mesma ordem + dia de hoje + calendário.
Editar, apagar ou reordenar uma atividade muda a chave; a virada do dia também (sequência e XP de hoje). Usam o cache: o
`Roster` (um snapshot por bro), o jogador em `MainView.derive`, o perfil público, as estatísticas e o "antes" das prévias de XP.
Continuam sem cache: a montagem do `Roster` a cada render (e o hash da chave, linear no histórico), `LeagueBoard.feed/ranking`
e o bro de cada time (`teamBro`, que roda `Game.snapshot` por membro).
Critério: `testCachedSnapshotMatchesUncached` garante que o cache devolve o mesmo que o cálculo direto (inclusive depois de editar, apagar e mudar o dia).
Fonte: `GymMonsters/Game.swift` (`cachedSnapshot`, `SnapshotCache`), `GymMonsters/Monsters.swift` (`Roster.init`), `GymMonsters/App.swift` (`derive`), `GymMonsters/Leagues.swift` (`LeagueBoard`), `GymMonstersTests/GameTests.swift`.
**Recomendação:** meta de no máximo 16 ms por render da tela principal com 5 mil atividades, num iPhone de referência; se passar, guardar também o `Roster` e o ranking das ligas.

**RNF-20 — Limites de listas.** O feed da liga agrupa no máximo 120 check-ins (`feed.prefix(120)`) e o mural, 150 recados (`lines.prefix(150)`).
Critério: telas de liga e mural não renderizam além desses limites.
Fonte: `GymMonsters/LeaguesView.swift` (l. 371), `GymMonsters/LeagueMural.swift` (l. 34).

**RNF-21 — Imagens comprimidas antes de salvar.** Fotos de check-in, capa de liga e corpo passam por `compressedPhoto`
(lado maior até 1280 px, JPEG qualidade 0,7); a foto do perfil é recortada em quadrado de 512 × 512 px (JPEG 0,8).
Critério: nenhuma imagem salva tem lado maior que 1280 px; a foto do perfil tem 512 px.
Fonte: `GymMonsters/LeaguesView.swift` (l. 771–774), `GymMonsters/ProfileView.swift` (l. 292–301).

**RNF-22 — Dados grandes fora da linha do banco.** Fotos, capa e pontos do percurso usam `.externalStorage`.
Fonte: ver RNF-15.
Observação: a foto do perfil é guardada em `UserDefaults` (`@AppStorage("profilePhoto")`), o que carrega o plist inteiro na memória.
**Recomendação:** mover a foto do perfil para arquivo ou SwiftData com `.externalStorage`.

**RNF-23 — Imagens de exercícios embutidas.** As imagens do wger estão no catálogo de assets do app e funcionam offline desde a
instalação. O `URLCache` de 40 MB de memória e 300 MB de disco configurado no início continua no código, mas não tem mais uso
relevante: não há imagem remota, e o vídeo do wger é transmitido pelo `AVPlayer`.
Fonte: `GymMonsters/Wger.swift` (`photoAssets`, `ExercisePhotos`), `GymMonsters/App.swift` (`init`).
**Recomendação:** remover o `URLCache` ou reduzi-lo, se nenhuma carga remota precisar dele.

## 5. Confiabilidade, offline e segundo plano

**RNF-24 — Funcionamento offline.** Registro de atividades, treino guiado, WOD, GPS, evolução, ligas (simuladas) e as imagens
e instruções dos exercícios funcionam sem rede; dependem da internet só o vídeo do wger, a busca no YouTube, a busca de
academias e, na primeira vez, o download do idioma para a tradução das instruções em inglês (iOS 18).
Fonte: RNF-07, RNF-08, RNF-23.

**RNF-25 — Monitoramento de academias em segundo plano.** `CLMonitor` acompanha até 20 lugares (os visitados mais
recentemente) e acorda o app ao entrar ou sair; ao sair, encerra e salva o treino daquele lugar se durou mais de 10 min.
Critério: com 21 academias salvas, só as 20 mais recentes são monitoradas.
Fonte: `GymMonsters/Location.swift` (l. 45, 186–208); `UIBackgroundModes` = `location` em `Info.plist`.

**RNF-26 — Execução em segundo plano durante o treino.** Percurso GPS com a tela bloqueada
(`allowsBackgroundLocationUpdates`), modo fone que toca silêncio para receber os comandos do fone
(`UIBackgroundModes` = `audio`), timer de descanso por notificação local e Live Activity. A tela não apaga durante treino e WOD.
Fonte: `Info.plist`; `GymMonsters/Route.swift` (l. 87–105), `GymMonsters/HeadphoneControl.swift`, `GymMonsters/LiveWorkout.swift` (l. 93), `GymMonsters/WorkoutView.swift` (l. 161), `GymMonsters/Wod.swift` (l. 315).
**Recomendação:** documentar para a revisão da App Store o uso de `audio` (modo fone) e de `location` (percurso e automações).

**RNF-27 — Consistência ao editar ou apagar.** Toda a evolução é recalculada do histórico; editar ou apagar uma
atividade muda XP, estágio e rankings sem migração de estado.
Fonte: `README.md`; `GymMonsters/Game.swift`.

**RNF-28 — Sem duplicidade com o Saúde.** Treinos que se sobrepõem a algo já registrado não contam duas vezes;
treinos do Saúde apagados no app ficam numa lista de ignorados e não voltam.
Fonte: `GymMonsters/HealthSync.swift` (`ignored`, `healthUUID`, `healthWrittenUUID`).

**RNF-29 — Determinismo dos dados simulados.** Participantes, check-ins, times, mural, perfis e posts simulados e a
espécie que nasce do ovo vêm de `SeededRandom`, com semente estável (UUID da liga, id do participante, dia).
Critério: o mesmo estado de entrada gera sempre a mesma saída (coberto por `testMockBackendIsStableAndSplitsTeams`).
Fonte: `GymMonsters/Leagues.swift` (l. 456, 490), `GymMonsters/LeagueRemote.swift` (l. 160–193), `GymMonsters/Friends.swift` (l. 194, 218), `GymMonsters/Game.swift` (l. 315).

**RNF-30 — Recuperação quando o banco não abre.** O `ModelContainer` é criado com o schema explícito dos 18 modelos
(`AppData.schema`). Se não abrir (ex.: migração que falhou), o app move o banco e os auxiliares `-wal`/`-shm` para o lado, sem
apagar (`default-erro-<timestamp>.store`), e cria um banco novo; se ainda assim falhar, abre com um banco só em memória (não grava,
mas não fecha). Quando houve cópia guardada, a tela principal avisa "Não deu para abrir seus dados", com o nome do arquivo e a
orientação de voltar por um backup em Ajustes → Backup.
Critério: um banco corrompido ou com migração impossível não derruba o app na abertura; o arquivo antigo continua no container.
Fonte: `GymMonsters/LiveWorkout.swift` (`AppData.container`, `setAside`, `recoveredCopy`), `GymMonsters/App.swift` (`MainView`, aviso `recovered`).
**Recomendação:** versionar o schema (`VersionedSchema` + `SchemaMigrationPlan`) antes de alterar modelos, para que a recuperação seja exceção e não a forma de lidar com migrações; oferecer reabrir a cópia guardada.

## 6. Usabilidade e acessibilidade

**RNF-31 — Design system próprio.** Telas, abas, botões, chaves, steppers, campos, sheets e diálogos vêm de
componentes `GM*`; do sistema ficam só teclado, seletor de fotos, compartilhar, seletor de arquivos e pedidos de permissão.
Fonte: `GymMonsters/DesignSystem.swift`; `README.md` (seção Design system).

**RNF-32 — Feedback háptico.** Ações principais (concluir série, salvar atividade, evolução, recorde, check-in,
contagem do WOD) disparam `UIImpactFeedbackGenerator`/`UINotificationFeedbackGenerator`.
Fonte: `GymMonsters/WorkoutView.swift`, `Wod.swift`, `EvolutionView.swift`, `PR.swift`, `LogActivityView.swift`, `DesignSystem.swift`.

**RNF-33 — Dynamic Type e acessibilidade.** A maior parte do texto usa estilos do sistema, que acompanham o Dynamic Type.
Textos com tamanho próprio (títulos de tela, nome do bro, números grandes de liga, WOD, peso e cronômetros, rótulos da barra de
abas e da Dex) usam `gmFont`, que escala com `@ScaledMetric` relativo a um estilo (25 usos), quase sempre com `minimumScaleFactor`.
Restam 30 usos de `.font(.system(size:))` fixos, quase todos em ícones, emojis e no widget do bro. Componentes compactos têm teto:
a `GMTabBar` cresce até `xxLarge` e o pino do mapa até `xLarge`.
VoiceOver: todo `GMIconButton` tem rótulo (explícito em 30 dos 44 usos; nos outros, derivado do ícone: "Fechar", "Voltar", "Ajustes",
"Mais opções"…); `GMFloatingButton`, os botões de `GMCompactStepper` ("Diminuir"/"Aumentar"), as abas (com a contagem do badge),
o botão de série feita, a sequência ("N dias seguidos"), a origem Saúde, o convite da liga e o `GMOnlineDot` também têm rótulo.
Fonte: `GymMonsters/DesignSystem.swift` (`gmFont`, `GMScaledFont`, `GMIconButton.defaultLabel`, `GMTabBar`), grep em `GymMonsters/` e `GymMonstersWidget/`.
**Recomendação:** telas principais utilizáveis até `accessibility3` sem cortar texto; trocar os tamanhos fixos restantes; descrever sprites (forma e estágio do bro) e gráficos para o VoiceOver.

**RNF-34 — Idioma pt-BR e formatação.** Região de desenvolvimento `pt-BR`; textos escritos direto em português
(sem `.strings`/`.xcstrings`); datas formatadas com `Locale("pt_BR")` ("Hoje", "Ontem", "seg, 3 de março");
voz do modo fone em pt-BR. Números internos de configuração usam `en_US_POSIX` para serialização estável.
Fonte: `pbxproj` (`developmentRegion = "pt-BR"`), `GymMonsters/DesignSystem.swift` (l. 531), `GymMonsters/HeadphoneControl.swift` (l. 104), `GymMonsters/Leagues.swift` (l. 246).
**Recomendação:** extrair os textos para String Catalog antes de suportar outro idioma.

## 7. Manutenibilidade e testabilidade

**RNF-35 — Testes rodam no aparelho, dentro do app.** O alvo de testes usa `TEST_HOST`/`BUNDLE_LOADER` do app;
`GymTestCase` salva e restaura as chaves de `UserDefaults` e os recordes manuais e usa banco em memória, para não mexer nos dados reais.
Fonte: `pbxproj` (l. 487, 499), `GymMonstersTests/TestSupport.swift`.

**RNF-36 — Cobertura atual por arquivo de teste (66 testes, contados por `func test` em `GymMonstersTests/`).**

| Arquivo | Testes | O que cobre |
|---|---|---|
| `GameTests.swift` | 9 | fórmula de XP, teto diário, chocar ovo, galhos de evolução, híbrido, sequência, Coelho em treino equilibrado, destino do XP (`Roster.owners`), cache de snapshot igual ao cálculo direto |
| `ProgressionTests.swift` | 22 | progressão de carga, deload, reps/segundos, metas, aquecimento, 1RM Epley, recordes, incremento de 5 kg só com barra, formatação de 1,25, calculadora pelo incremento, melhor marca sem misturar 1RM e carga, esforço do encerramento automático, deload em qualquer prescrição, nome do personalizado, ordem da troca |
| `WorkoutTests.swift` | 16 | superset, descanso, aquecimento fora do log e dos totais, deload semanal, ranking por período, textos de início, renovação de temporada, troca em superset (parcial e total), aviso "Dez segundos", CAP do For Time |
| `LeagueTests.swift` | 17 | pesos por atributo, métricas, janela do mês, desempates, regra de foto, "Vale ½" sem zerar, pontuação de check-in restaurado, ids estáveis e legados de times, ranking com `remote` injetado, mesmo bro em todo lugar, estabilidade do mock, placar do time |
| `NamesAndBarTests.swift` | 2 | nomes únicos de todas as formas (22 por espécie), carga com ou sem barra pelo tipo do treino |

Sem testes: backup/restauração (ida e volta), recuperação do banco, importação/escrita no Saúde, localização, widget, amigos e telas.
**Recomendação:** testes de ida e volta do backup (inclusive `typedSettings` e `hadPhoto`), da recuperação do banco e da deduplicação com o Saúde; meta mínima de cobertura nas regras de `Game`, `Training`, `Leagues` e `Backup`.

**RNF-37 — Contratos de backend substituíveis.** `LeagueBackend` (`fetch`, `send`) e `FriendsBackend` (`fetch`, `add`,
`accept`, `decline`, `remove`, `profile`) são protocolos `Sendable` com tipos `Remote*` `Codable`; trocar o mock pelo
servidor é implementar o protocolo e atribuir `LeagueRemoteStore.shared.backend`.
Fonte: `GymMonsters/LeagueRemote.swift` (l. 88–101), `GymMonsters/Friends.swift` (l. 39–50).

**RNF-38 — Regras isoladas da interface.** Regras de jogo, progressão e ranking ficam em tipos puros (`Game`, `Training`,
`LeagueBoard`), testáveis sem UI.
Fonte: `GymMonsters/Game.swift`, `Training.swift`, `Leagues.swift`.

## 8. Integridade do jogo (anti-farm)

**RNF-39 — Limites de XP.** Cada atividade conta no máximo 240 min; acima de 150 XP no dia o ganho cai para 1/3, com teto de 300 XP/dia.
Critério: `testDailyHardCap` passa; nenhum dia soma mais de 300 XP.
Fonte: `GymMonsters/Game.swift` (l. 371–377: `maxMinutes`, `dailySoftCap`, `dailyHardCap`).

**RNF-40 — Limiares de evolução fixos.** Bebê 60, Rookie 300, Champion 1200, Ultimate 3600 XP; híbrido só com empate próximo (razão 0,9).
Fonte: `GymMonsters/Game.swift` (l. 132–135, 385).

**RNF-41 — Regra de foto nas ligas.** Check-in sem foto vale metade (arredondada para cima) ou não pontua, conforme a liga.
Fonte: `GymMonsters/Leagues.swift` (`PhotoRule`); `testPhotoRule`, `testHalfPhotoNeverZeroesAScore`.
**Recomendação:** no servidor, os limites RNF-39 e RNF-41 devem ser recalculados do lado do servidor; a pontuação enviada pelo aparelho não deve ser confiável.

## 9. Evolução para servidor (requisitos do futuro backend)

Todos os itens desta seção são **Recomendação**: ainda não existe servidor.

**RNF-42 — Autenticação obrigatória.** Nenhum endpoint com acesso anônimo; sessão por token de curta duração com renovação, guardado no Keychain (Sign in with Apple é o caminho natural para app sem conta hoje).

**RNF-43 — Autorização por liga.** Só membros de uma liga leem participantes, check-ins, fotos, times e mural daquela liga;
só o autor apaga o próprio check-in ou recado; código de convite não dá acesso a dados antes de entrar.
Critério: teste de API com usuário de fora da liga recebe 403 em todos os recursos da liga.

**RNF-44 — Amizade e perfil público.** `profile(id)` devolve só o que a pessoa marcou como público (RNF-13), e só para amigos ou colegas de liga.
O perfil privado (peso, medidas, recordes, calendário completo) nunca sai do aparelho.

**RNF-45 — PII e fotos.** Nome, @usuário, bio, foto do perfil e fotos de check-in são dados pessoais: armazenar em ambiente
corporativo aprovado, com criptografia em repouso, URLs de foto assinadas e com expiração, remoção de EXIF/GPS das imagens
e exclusão de conta que apague tudo. Localização de academias e percursos permanece só no aparelho, a menos que haja consentimento explícito.
Em desenvolvimento, usar dados sintéticos (como os do mock atual).

**RNF-46 — Sincronização da caixa de saída.** Recados ficam locais com `syncedAt = nil` até o servidor aceitar; o envio
deve ser idempotente pelo `uuid` do recado (reenvio não duplica), com nova tentativa ao voltar a rede. Os check-ins
ainda não têm envio e devem seguir o mesmo modelo (UUID do cliente, `syncedAt`).
Fonte do comportamento atual: `GymMonsters/LeagueRemote.swift` (l. 11, 120–140), `GymMonsters/LeagueMural.swift` (l. 5, 57).

**RNF-47 — Infraestrutura.** Produção na ORKA; se Vercel ou Supabase forem usados, contas corporativas e, no Supabase,
RLS ligado em todas as tabelas; banco sem porta aberta para a internet.

**RNF-48 — Identidade do app.** Bundle IDs (`com.alonsoalmeida.gymmonsters*`), App Group e `DEVELOPMENT_TEAM = 5UV7WAAAL2`
continuam na conta pessoal (migração ainda não feita). Antes de publicar ou ligar um servidor, migrar para a conta corporativa (o App Group muda junto e exige migração dos dados do widget).
Fonte: `pbxproj`, entitlements.
