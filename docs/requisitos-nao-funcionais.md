# Requisitos não funcionais — GymBros (iOS)

Levantados a partir do código e da configuração do projeto `GymBros.xcodeproj` (outubro/2026).
Cada requisito descreve o comportamento atual e traz um critério verificável e a fonte. Quando o item
não é fato do código, e sim algo que o app deveria passar a cumprir, ele aparece marcado como **Recomendação**.

Convenções de fonte: `pbxproj` = `GymBros.xcodeproj/project.pbxproj`; `Info.plist` = `GymBros/Resources/Info.plist`;
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
Fonte: `GymBros/Exercises/MuscleViews.swift` (`TranslateSteps`), `GymBrosWidget/WorkoutControls.swift`, `GymBrosWidget/GymBrosWidget.swift` (l. 176).

**RNF-03 — Somente iPhone, em retrato e tema escuro.** Não há versão para iPad nem paisagem; a interface é sempre escura.
Critério: `TARGETED_DEVICE_FAMILY = 1`; `UISupportedInterfaceOrientations_iPhone = UIInterfaceOrientationPortrait`;
`UIUserInterfaceStyle = Dark` e `.preferredColorScheme(.dark)`.
Fonte: `pbxproj`; `GymBros/App/App.swift`.

**RNF-04 — Apple Watch via app Saúde.** Não existe app para watchOS; treinos do Apple Watch chegam pelo HealthKit
(importação) e, se o usuário ligar, treinos do app são gravados no Saúde para contar nos anéis.
Critério: nenhum alvo watchOS no projeto; treino feito no Watch aparece como atividade após abrir o app.
Fonte: `GymBros/Services/HealthSync.swift`; `INFOPLIST_KEY_NSHealthShareUsageDescription`.

**RNF-05 — Extensões do sistema.** Widgets (tela inicial e bloqueio), Live Activity / Dynamic Island do treino
e do WOD, e Atalhos (App Intents).
Critério: `NSSupportsLiveActivities = YES`; extensão `com.apple.widgetkit-extension`.
Fonte: `pbxproj`; `GymBrosWidget/Info.plist`; `GymBrosWidget/WorkoutLiveActivity.swift`, `WodLiveActivity.swift`; `GymBros/App/Shortcuts.swift`.

**RNF-06 — Dependência externa única, com versão fixa.** O único pacote SwiftPM é `MuscleMap` (GitHub), fixado na versão 1.9.0.
Critério: `packageReferences` contém só esse repositório, com `kind = exactVersion`.
Fonte: `pbxproj` (`repositoryURL = https://github.com/melihcolpan/MuscleMap.git`, `version = 1.9.0`).
A licença (MIT) está registrada em `CREDITOS.md` e na tela "Créditos e licenças" (RNF-49).

**RNF-49 — Conteúdo de terceiros com licença comercial e atribuição.** Imagens, vídeos e instruções de exercícios vêm só do wger
(CC BY-SA 3.0, CC BY-SA 4.0 ou CC0, por item), com autor, licença e origem guardados em `GymBros/Resources/wger.json` e exibidos junto
do conteúdo e na tela "Créditos e licenças". Fotos e instruções do free-exercise-db foram removidas porque reproduziam o
bodybuilding.com, sem autorização de uso comercial; imagens marcadas como geradas por IA no wger são ignoradas. Instruções
traduzidas no aparelho seguem a mesma licença (share-alike), o que não se aplica ao código do app.
Critério: todo item exibido do wger mostra autor e licença; não há imagem nem texto do free-exercise-db no bundle.
Fonte: `GymBros/Exercises/Wger.swift` (`WgerLibrary`, `CreditLine`, `CreditsView`), `GymBros/Exercises/ExerciseExtra.swift` (`ExerciseExtraData.remote` vazio), `tools/wger/build.py`, `CREDITOS.md`.

## 2. Privacidade e dados pessoais

**RNF-07 — Conta obrigatória, dados da conta e servidor simulado.** A conta é obrigatória e os dados (treinos, bros, rotinas, recordes,
medidas, fotos, lugares, ligas e ajustes) são dela: o aparelho guarda a cópia de trabalho (SwiftData e `UserDefaults`) e a cópia da conta
(`AccountDataBackend`, formato do backup) sobe depois das mudanças e volta ao entrar; sair tira os dados do aparelho e outra conta nunca vê os
da anterior. No modo padrão (`Backend.mode = .mock`) tudo é simulado: não há rede, a sessão fica no Keychain, nenhuma senha é guardada e o
"servidor" da conta é um arquivo por conta em `Application Support/MockServer/` (sai junto com o app). Com `Backend.mode = .cloudKit`
(exige iCloud, ainda não configurado), sobe para o banco público do CloudKit só o que é compartilhado: perfil público, ligas, seu lugar nelas,
check-ins postados, recados, denúncias, bloqueios e X1 (desafio, resposta e o seu valor). Mensagens diretas não vão para o banco público (RNF-51). A cópia da conta tem dados do Apple Saúde e por isso nunca vai para o iCloud (RNF-07e): fica para um servidor
próprio (ou CloudKit privado sem nenhum campo vindo do Saúde); até lá, `ServerAccountDataBackend` lança erro (`docs/cloudkit.md`).
Critério: com `.mock`, nenhum uso de `URLSession` nem chamada ao CloudKit, e o app funciona completo sem rede depois do login;
os dados locais de antes da conta obrigatória são adotados pela primeira conta que entra, sem perda (`AccountSyncTests`).

**RNF-07b — Exclusão de conta (guideline 5.1.1(v)).** Ajustes > Conta > "Excluir conta" apaga a cópia da conta (`AccountDataBackend.delete`),
chama `AuthBackend.deleteAccount` e, só se o servidor confirmar, apaga tudo da conta no aparelho (`AccountData.wipeAll`: banco inteiro, chaves de
usuário, aceite dos termos, bloqueios, denúncias, resumo do widget) e a sessão do Keychain, e volta ao login. No CloudKit apaga os registros criados pelo usuário
(perfil, `Member`, `CheckIn`, `Message`, `FriendLink` de saída, `Report`, `Block` e `Duel`). Pendências no servidor real: revogar o token do Sign in with Apple (exige servidor
com a chave .p8) e vínculos de amizade criados por outras pessoas (`docs/cloudkit.md`).
Também saem as cópias da conta guardadas em `Application Support/AccountSync/`. Se a limpeza do aparelho falhar depois de o servidor confirmar (ou o app
fechar no meio), `accountDataPendingWipe` guarda a conta e a limpeza termina ao abrir o app ou antes de outra conta entrar; esses dados nunca são adotados.
Critério: depois de excluir, nada da conta fica no aparelho nem no servidor simulado (`AccountSyncTests`, `AccountDeletionTests`).

**RNF-07c — Conteúdo de usuários (guideline 1.2).** Denunciar e bloquear existem em check-ins, fotos, comentários, recados e perfis de outras pessoas,
nunca no próprio conteúdo. Denúncia esconde na hora para quem denunciou e vai por uma fila que sobrevive a falta de rede; bloqueio esconde a pessoa
em tudo menos na pontuação das ligas e desfaz a amizade. Tudo passa por `ModerationBackend` (`ModerationStore`); listas no `UserDefaults`, sem `@Model` novo.
Pendência no servidor real: analisar denúncias em até 24 h e tirar do ar para todos (`docs/cloudkit.md`).
Critério: `ModerationTests`.

**RNF-07d — Termos de uso e filtro (guideline 1.2).** Termos com tolerância zero em Ajustes e na web (`docs/termos.md`, gerada do texto de
`GymBros/App/TermsView.swift`), com aceite no primeiro acesso, guardado com a versão (`OnboardingView`, `TermsRequiredView`; `TermsGate` e `Terms.canPublish` como proteção).
`ContentFilter` (puro, no aparelho, lista em `BlockedTerms.swift`) barra o texto antes de enviar; o que sobe sem tela (nome nas ligas, perfil
público) sai vazio se barrado. Critério: `TermsTests` e `ContentFilterTests`.

**RNF-07e — Dado do Apple Saúde não vai para o iCloud (guideline 5.1.3(ii)).** Check-in de atividade importada do Saúde
(`healthUUID`) sobe sem `kcal` e sem `meters`, e com esforço neutro (5), porque o esforço importado é derivado das kcal do Saúde
(`HealthSync.effort`). Sobem só porque você posta: tipo, data e duração do treino do Saúde (aceito e dito na política e no aviso "Postar em"), mais
título, nota e foto. Quem vê estima as
calorias com o peso de referência; distância só sobe quando é do GPS do próprio app. O título sugerido ao postar uma atividade do Saúde não reusa a nota
importada ("512 kcal"). Seu placar usa os mesmos dados que os outros recebem (`Activity.scoreInput`). Peso, medidas e perfil físico nunca sobem.
Critério: `HealthPrivacyTests` (`OutgoingCheckIn(_:activity:)` e `CKRecord(cloud:)` sem `kcal`/`meters` e com esforço 5 em atividade do Saúde).
Fonte: `GymBros/Leagues/Leagues.swift` (`isFromHealth`, `publishableEffort`, `publishableMeters`, `publishableKcal`), `GymBros/Leagues/LeagueRemote.swift` (`OutgoingCheckIn`).
O tipo exato (`healthType`) também é gravado nas atividades criadas no app e não marca a origem: só o `healthUUID` torna a atividade "do Saúde" (`testAppActivityWithHealthTypeIsNotHealth`).

**RNF-07a — Manifesto e política de privacidade.** App e widget têm `PrivacyInfo.xcprivacy` (sem rastreamento, sem dados
coletados no modo `.mock`, `UserDefaults` com os motivos CA92.1 e 1C8F.1 no app e 1C8F.1 no widget), e o app declara
`ITSAppUsesNonExemptEncryption = NO`. A política de privacidade fica em Ajustes > Privacidade (`GymBros/App/PrivacyPolicyView.swift`)
e na web em `docs/privacidade.md` (https://alonsojrr14.github.io/gymbros/privacidade/), gerada a partir do mesmo texto.
A política diz que a conta é obrigatória, que os dados são da conta e que, nesta versão, o servidor é simulado no aparelho.
Critério: ao ligar `Backend.mode = .cloudKit`, login real ou o servidor dos dados da conta, atualizar `NSPrivacyCollectedDataTypes` (dados de
saúde e fitness, localização, fotos, identificadores e conteúdo do usuário ligados à identidade) e as duas versões da política antes de publicar.
Fonte: `GymBros/Resources/PrivacyInfo.xcprivacy`, `GymBrosWidget/PrivacyInfo.xcprivacy`, `GymBros/Resources/Info.plist`.
Fonte: `GymBros/Services/Backend.swift` (`Backend.mode`, `install`), `GymBros/Services/Auth.swift` (`AuthStore`, `MockAuthBackend`), `GymBros/Models/Schema.swift` (`AppData.container`), `docs/cloudkit.md`; grep por `URLSession` sem resultados.

**RNF-08 — Tráfego de rede limitado a conteúdo público.** As únicas saídas de rede são: vídeo de demonstração do wger
tocado no app (`AVPlayer` com URL de `wger.de`), só quando o usuário toca em "Ver vídeo de demonstração"; links de licença e
de origem nas linhas de crédito; busca de academias no Mapas da Apple (`MKLocalSearch`); e o link externo de busca no YouTube.
As imagens de exercícios estão embutidas no app (catálogo `Wger`), sem download. Nenhuma saída envia dados do usuário além da consulta. No modo `.cloudKit` (desligado), entra também o CloudKit da Apple (RNF-07).
A leitura de prints do WOD (Vision), a estruturação com Apple Intelligence (Foundation Models, iOS 26) e a música do app Música (MediaPlayer) rodam no aparelho;
o Spotify (Web API) só passa a existir quando `SpotifyNowPlaying.clientID` for preenchido.
Critério: inspeção de tráfego mostra apenas `wger.de` (vídeo e links, por ação explícita), serviços da Apple e abertura do YouTube por ação explícita; nenhum acesso a `cdn.jsdelivr.net`.
Fonte: `GymBros/Exercises/Wger.swift` (`WgerVideoView`, `CreditLine`), `GymBros/Exercises/Exercises.swift` (`videoURL`), `GymBros/Services/Location.swift` (`suggestions`), `GymBros/Exercises/MuscleViews.swift`, `GymBros/Train/WodImport.swift` (`WodOCR`, `WodAI`), `GymBros/Music/Music.swift`.

**RNF-09 — HealthKit com consentimento separado para leitura e escrita.**
- Leitura (treinos e massa corporal) — texto: "Para transformar seus treinos do iPhone e Apple Watch em XP para o seu bro."
- Escrita (treinos e energia ativa), só se o usuário ligar — texto: "Para gravar seus treinos do GymBros no Saúde e eles contarem nos anéis do Fitness."
Critério: a escrita só ocorre com `healthWrite` ligado e apenas para atividades criadas depois de ligar (janela `healthWriteSince`); atividades vindas do Saúde nunca são regravadas; a primeira importação cobre só 14 dias.
Fonte: `INFOPLIST_KEY_NSHealthShareUsageDescription`, `INFOPLIST_KEY_NSHealthUpdateUsageDescription`; `GymBros/Services/HealthSync.swift` (`requestAccess`, `requestWrite`, `exportPending`, `firstImportDays = 14`); entitlement `com.apple.developer.healthkit`.

**RNF-10 — Localização "em uso" e "sempre".**
- Em uso — texto: "Para gravar o percurso de corridas, caminhadas e pedaladas e marcar a sua academia."
- Sempre — texto: "Para saber quando você chega ou sai da academia: sugerir o treino ao chegar e encerrar o treino ao sair. A localização fica só no seu iPhone."
Critério: o percurso com tela bloqueada exibe o indicador azul de localização em segundo plano; o pedido "sempre" só acontece ao ativar automações de academia.
Fonte: `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription`, `INFOPLIST_KEY_NSLocationAlwaysAndWhenInUseUsageDescription`; `GymBros/Services/Route.swift` (l. 51–60), `GymBros/Services/Location.swift` (l. 111–119).

**RNF-11 — Notificações locais sob demanda.** Permissão (`.alert`, `.sound`) pedida ao ligar lembretes, ao usar o
timer de descanso ou automações, ou pelo cartão de permissão das notificações sociais (`NotificationPermissionCard`, que leva aos
Ajustes do iPhone se a permissão foi negada); todas as notificações são locais. As sociais (mensagens, força, convites, X1, amigo
treinando, reações, pedidos de amizade) são geradas pelo `InboxStore` com o app ativo, por tópico (todos começam ligados, chaves `notify.*`)
e com pausa geral; na primeira busca de uma conta nada é notificado, e o que chega na conversa aberta não vira notificação.
Critério: nenhum registro para push remoto (`registerForRemoteNotifications` ausente); `InboxTests` (tópico, pausa, conversa aberta, itens antigos).
Fonte: `GymBros/App/SettingsPages.swift` (`NotificationSettingsPage`), `GymBros/Inbox/NotificationPrefs.swift` (`NotificationTopic`, `NotificationPrefs`, `SocialNotifier`), `GymBros/Inbox/Inbox.swift` (`InboxStore.refresh`), `GymBros/Train/LiveWorkout.swift`, `GymBros/Bros/Companion.swift`.

**RNF-12 — Fotos sem permissão de biblioteca; sem câmera.** Fotos (perfil, check-in, capa de liga, corpo, story, prints do treino do coach)
são escolhidas pelo `PhotosPicker`, que roda fora do processo e dispensa permissão. O app não usa a câmera.
Critério: não existem `NSPhotoLibraryUsageDescription` nem `NSCameraUsageDescription`, e nenhum uso de `AVCapture`/`UIImagePickerController`.
Fonte: `Info.plist`, `pbxproj`; `GymBros/Profile/ProfileView.swift`, `GymBros/Leagues/LeaguesView.swift`, `GymBros/Profile/BodyTrackerView.swift`, `GymBros/Leagues/CheckInDetail.swift`, `GymBros/Activities/ActivityDetail.swift`, `GymBros/Train/WodImport.swift` (até 6 prints).
**Recomendação:** se a câmera for adicionada, incluir `NSCameraUsageDescription` em pt-BR antes do primeiro uso.

**RNF-13 — Perfil público × privado.** O que os amigos veem é exatamente a aba Público: foto, nome, @usuário, bio e
o card público, com chaves que o usuário pode desligar (`publicMonster`, `publicStats`, `publicAchievements`).
A aba Privado (números, recordes, metas, peso, medidas, calendário de atividades) nunca é exposta.
Critério: com as três chaves desligadas, a prévia pública não mostra bro, números nem conquistas.
Fonte: `GymBros/Profile/ProfileView.swift` (l. 34–40, 263–267), `GymBros/Friends/PublicProfile.swift`; `FriendsBackend.profile` em `GymBros/Friends/Friends.swift`.

**RNF-14 — Backup em JSON, com poucas imagens.** O backup exporta atividades, rotinas, sessões, ligas, check-ins, recados,
comentários, percursos, academias, corpo etc. Imagens: entram só a foto do perfil (512 px) e a capa de cada liga reduzida
(até 640 px, JPEG 0,6, só da temporada atual); imagens dos check-ins e fotos de progresso ficam de fora. O check-in
restaurado volta sem imagem, mas com a marca `hadPhoto`, então a pontuação nas ligas não muda. O arquivo vai para onde
o usuário escolher no Arquivos, sem criptografia. O app não sugere o iCloud Drive porque o arquivo leva dados do Apple Saúde (guideline 5.1.3(ii)).
O estado no servidor das ligas e check-ins (`syncedAt`, `joined`) vai junto, e a restauração é atômica (falhou, nada muda).
Critério: restaurar um backup recupera todos os registros, a foto do perfil e as capas; imagens de check-in e de progresso não voltam, e o placar das ligas fica igual; restaurar não recria ligas no servidor nem republica check-ins já enviados.
Fonte: `GymBros/Services/Backup.swift` (`make`, `restore`, `smallCover`), `GymBros/Models/League.swift` (`LeagueCheckIn.hadPhoto`); `GymBrosTests/BackupTests.swift`.
**Recomendação:** avisar na tela de backup que as fotos de check-in e de progresso não são incluídas e que o arquivo contém localização (academias e percursos), medidas corporais e a foto do perfil; considerar criptografar o arquivo.

## 3. Segurança

**RNF-15 — Armazenamento no container do App Group, com file protection.** O banco SwiftData (`default.store`) fica no container do
App Group `group.com.alonsoalmeida.gymbros` (`Library/Application Support/`), porque o app tem a entitlement de App Group e o
`ModelConfiguration` padrão grava lá (conferido no aparelho); arquivos grandes (fotos, pontos do percurso, capa) usam
`@Attribute(.externalStorage)` ao lado do banco. Ao abrir o banco, o app aplica
`FileProtectionType.completeUntilFirstUserAuthentication` ao arquivo do banco e aos auxiliares `-wal` e `-shm` (escolhida em vez
de `complete` porque as automações de academia e o Live Activity gravam com o aparelho bloqueado). A pasta de `externalStorage`
não recebe o atributo explicitamente e fica com a proteção padrão do container.
Critério: nenhum dado do usuário é gravado fora do container do app ou do App Group; os três arquivos do banco têm a classe de proteção `completeUntilFirstUserAuthentication`.
Fonte: `GymBros/Models/Schema.swift` (`AppData.protect`), `GymBros/Models/League.swift` (`League.cover`, `LeagueCheckIn.photo`), `GymBros/Models/Body.swift`, `GymBros/Models/RouteRecord.swift`.
**Recomendação:** aplicar o mesmo atributo à pasta de `externalStorage` e ao arquivo de backup exportado.

**RNF-16 — App Group só com dados mínimos para o widget.** O app e o widget compartilham
`group.com.alonsoalmeida.gymbros` via `UserDefaults(suiteName:)`; o banco SwiftData também fica no container do grupo (RNF-15), mas o widget não o abre.
Critério: o widget lê somente o estado resumido (bro, humor, XP, sequência, pose).
Fonte: `GymBros/Resources/GymBros.entitlements`, `GymBrosWidget/GymBrosWidget.entitlements`, `Shared/WidgetShared.swift` (l. 89–92).

**RNF-17 — Nenhuma credencial no código.** Verificado por busca por `api_key`, `secret`, `token`, `password`, `bearer`,
`private_key`, `sk-…`, `AKIA…`, `ghp_…` e por arquivos `.env` no repositório (excluindo `build/`): nenhuma credencial. `token` e
`password` só aparecem como nomes de campo e parâmetro do login (`GymBros/Services/Auth.swift`, `GymBros/Services/Backend.swift`); o token do mock é um UUID gerado na hora.
Critério: a mesma busca continua sem resultados a cada PR.
Fonte: varredura do repositório.
**Recomendação:** adicionar um verificador de segredos (ex.: gitleaks) no pipeline. Os scripts `tools/artes/chrome.sh` copiam o perfil do Chrome (com cookies) para `~/Library/Caches/gymbros-chrome`, fora do repositório; isso deve continuar fora do versionamento.

**RNF-18 — Chamadas ao servidor exigem autenticação.** O backend ativo é o simulado (`MockAuthBackend`, `MockLeagueBackend`, `MockFriendsBackend`).
A implementação CloudKit já existente usa a conta do iCloud do aparelho como identidade (`CloudKitAuthBackend`) e o banco público com
permissões World: Read · Authenticated: Create · Creator: Write (`docs/cloudkit.md`).
O `AuthUser`, com o token da sessão, fica no Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, não vai para backups de outro aparelho); sessões gravadas em `UserDefaults` por versões antigas migram na primeira leitura.
**Recomendação:** manter tokens só no Keychain, nunca em `UserDefaults` ou no código; implementações HTTP de `AuthBackend`/`LeagueBackend`/`FriendsBackend` devem usar HTTPS (ATS padrão, sem exceções no `Info.plist`). Credenciais de servidor ficam em cofre ou gerenciador de segredos.
Fonte: `GymBros/Services/Auth.swift` (`AuthStore.finish`, `Keychain`), `GymBros/Services/Backend.swift`, `GymBros/Leagues/LeagueRemote.swift` (`LeagueBackend`), `GymBros/Friends/Friends.swift` (`FriendsBackend`).

## 4. Desempenho

**RNF-19 — Estado do jogo derivado do histórico, com cache.** XP, estágio, atributos e sequência continuam derivados de
todas as atividades, mas as telas usam `Game.cachedSnapshot`: o resultado fica em `SnapshotCache` (até 24 entradas, a mais
antiga sai primeiro, protegido por `NSLock`), com chave = lista inteira de registros na mesma ordem + dia de hoje + calendário.
Editar, apagar ou reordenar uma atividade muda a chave; a virada do dia também (sequência e XP de hoje). Usam o cache: o
`Roster` (um snapshot por bro), o jogador em `MainView.derive`, o perfil público, as estatísticas e o "antes" das prévias de XP.
Continuam sem cache: a montagem do `Roster` a cada render (e o hash da chave, linear no histórico), `LeagueBoard.feed/ranking`,
a tabela suíça (`Swiss.table`, refeita por `ranking` quando a tela não passa `swiss:`) e o bro de cada time (`teamBro`, que roda `Game.snapshot` por membro).
Critério: `testCachedSnapshotMatchesUncached` garante que o cache devolve o mesmo que o cálculo direto (inclusive depois de editar, apagar e mudar o dia).
Fonte: `GymBros/Bros/Game.swift` (`cachedSnapshot`, `SnapshotCache`), `GymBros/Bros/Monsters.swift` (`Roster.init`), `GymBros/App/App.swift` (`derive`), `GymBros/Leagues/Leagues.swift` (`LeagueBoard`), `GymBrosTests/GameTests.swift`.
**Recomendação:** meta de no máximo 16 ms por render da tela principal com 5 mil atividades, num iPhone de referência; se passar, guardar também o `Roster` e o ranking das ligas.

**RNF-20 — Limites de listas.** O feed da liga agrupa no máximo 120 check-ins (`feed.prefix(120)`) e o mural, 150 recados (`lines.prefix(150)`).
Critério: telas de liga e mural não renderizam além desses limites.
Fonte: `GymBros/Leagues/LeaguesView.swift` (l. 405), `GymBros/Leagues/LeagueMural.swift` (l. 38).

**RNF-21 — Imagens comprimidas antes de salvar.** Fotos de check-in, capa de liga e corpo passam por `compressedPhoto`
(lado maior até 1280 px, JPEG qualidade 0,7); a foto do perfil é recortada em quadrado de 512 × 512 px (JPEG 0,8).
Critério: nenhuma imagem salva tem lado maior que 1280 px; a foto do perfil tem 512 px.
Fonte: `GymBros/Leagues/LeaguesView.swift` (`compressedPhoto`, l. 867), `GymBros/Profile/ProfileView.swift`.

**RNF-22 — Dados grandes fora da linha do banco.** Fotos, capa e pontos do percurso usam `.externalStorage`.
Fonte: ver RNF-15.
Observação: a foto do perfil é guardada em `UserDefaults` (`@AppStorage("profilePhoto")`), o que carrega o plist inteiro na memória.
**Recomendação:** mover a foto do perfil para arquivo ou SwiftData com `.externalStorage`.

**RNF-23 — Imagens de exercícios embutidas.** As imagens do wger estão no catálogo de assets do app e funcionam offline desde a
instalação. O `URLCache` de 40 MB de memória e 300 MB de disco configurado no início continua no código, mas não tem mais uso
relevante: não há imagem remota, e o vídeo do wger é transmitido pelo `AVPlayer`.
Fonte: `GymBros/Exercises/Wger.swift` (`photoAssets`, `ExercisePhotos`), `GymBros/App/App.swift` (`init`).
**Recomendação:** remover o `URLCache` ou reduzi-lo, se nenhuma carga remota precisar dele.

## 5. Confiabilidade, offline e segundo plano

**RNF-24 — Funcionamento offline.** Registro de atividades, treino guiado, WOD, GPS, evolução, ligas (simuladas) e as imagens
e instruções dos exercícios funcionam sem rede; dependem da internet só o vídeo do wger, a busca no YouTube, a busca de
academias e, na primeira vez, o download do idioma para a tradução das instruções em inglês (iOS 18).
Fonte: RNF-07, RNF-08, RNF-23.

**RNF-25 — Monitoramento de academias em segundo plano.** `CLMonitor` acompanha até 20 lugares (os visitados mais
recentemente) e acorda o app ao entrar ou sair; ao sair, encerra e salva o treino daquele lugar se durou mais de 10 min.
Critério: com 21 academias salvas, só as 20 mais recentes são monitoradas.
Fonte: `GymBros/Services/Location.swift` (l. 148, 170, 204–221); `UIBackgroundModes` = `location` em `Info.plist`.

**RNF-26 — Execução em segundo plano durante o treino.** Percurso GPS com a tela bloqueada
(`allowsBackgroundLocationUpdates`), timer de descanso por notificação local e Live Activity. O modo fone só fala
com o app aberto e não toca áudio em segundo plano. A tela não apaga durante treino e WOD.
Fonte: `Info.plist`; `GymBros/Services/Route.swift` (l. 57–60), `GymBros/Train/HeadphoneControl.swift`, `GymBros/Train/LiveWorkout.swift` (l. 236), `GymBros/Train/WorkoutView.swift` (l. 170), `GymBros/Train/Wod.swift` (l. 281).
`UIBackgroundModes` tem só `location` (o `audio` saiu).
**Recomendação:** documentar para a revisão da App Store o uso de `location` (percurso e automações).

**RNF-27 — Consistência ao editar ou apagar.** Toda a evolução é recalculada do histórico; editar ou apagar uma
atividade muda XP, estágio e rankings sem migração de estado.
Fonte: `README.md`; `GymBros/Bros/Game.swift`.

**RNF-28 — Sem duplicidade com o Saúde.** Treinos que se sobrepõem a algo já registrado não contam duas vezes;
treinos do Saúde apagados no app ficam numa lista de ignorados e não voltam.
Fonte: `GymBros/Services/HealthSync.swift` (`ignored`, `healthUUID`, `healthWrittenUUID`).

**RNF-29 — Determinismo dos dados simulados.** Participantes, check-ins, times, mural, perfis e posts simulados, a
espécie que nasce do ovo, as respostas e os valores do X1 simulado e as conversas e reações da caixa de entrada simulada vêm de
`SeededRandom`, com semente estável (UUID da liga, id do participante, id do X1, dia; ids de mensagem por `UUID(seed:)`).
Critério: o mesmo estado de entrada gera sempre a mesma saída (coberto por `testMockBackendIsStableAndSplitsTeams`, `testSimulatedPeopleMostlyAccept`, `testStableSeededUUID`).
Fonte: `GymBros/Leagues/Leagues.swift`, `GymBros/Leagues/LeagueRemote.swift` (`MockLeagueBackend`), `GymBros/Friends/Friends.swift` (`MockFriendsBackend`), `GymBros/Bros/Game.swift`, `GymBros/Duels/DuelStore.swift` (`MockDuelServer`), `GymBros/Inbox/InboxMock.swift`.

**RNF-30 — Migração versionada e recuperação quando o banco não abre.** O `ModelContainer` é criado com o schema versionado dos 18 modelos
(`AppData.schema` = `SchemaV2`, 2.0.0; o `AppMigrationPlan` leva `SchemaV1` → `SchemaV2` num estágio `.lightweight`, porque a V2 só acrescenta
`League.swissRaw` com valor padrão, e a `League` da V1 fica congelada em `SchemaV1.League`) e `cloudKitDatabase: .none`, para ligar o iCloud do backend não espelhar o banco local. Se não abrir (ex.: migração que falhou), o app move o banco e os auxiliares `-wal`/`-shm` para o lado, sem
apagar (`default-erro-<timestamp>.store`), e cria um banco novo; se ainda assim falhar, abre com um banco só em memória (não grava,
mas não fecha). Quando houve cópia guardada, a tela principal avisa "Não deu para abrir seus dados", com o nome do arquivo e a
orientação de voltar por um backup em Ajustes → Backup.
Critério: um banco corrompido ou com migração impossível não derruba o app na abertura; o arquivo antigo continua no container; o banco existente abre com o schema atual sem ser movido (`testDeviceStoreOpensWithCurrentSchema`); um banco gravado na V1 migra para a V2 sem perder dados (`testV1StoreMigratesToV2`).
Fonte: `GymBros/Models/Schema.swift` (`AppData.container`, `setAside`, `recoveredCopy`), `GymBros/App/App.swift` (`MainView`, aviso `recovered`), `GymBrosTests/StoreTests.swift`.
**Recomendação:** toda mudança de modelo entra como nova `VersionedSchema` (próxima: `SchemaV3`) + estágio no `AppMigrationPlan`, com um teste de migração em disco como o da V2; oferecer reabrir a cópia guardada.

## 6. Usabilidade e acessibilidade

**RNF-31 — Design system próprio.** Telas, abas, botões, chaves, steppers, campos, sheets e diálogos vêm de
componentes `GM*`; do sistema ficam só teclado, seletor de fotos, compartilhar, seletor de arquivos e pedidos de permissão.
Exceções no código: três `.sheet` nativos com detents (ficha do BroBook em `DexView` e `Monsters.swift`, lista de tipos de treino em `ActivityTypePicker`) e o `fullScreenCover` do `TermsGate`.
Fonte: `GymBros/DesignSystem/`; `README.md` (seção Design system).

**RNF-32 — Feedback háptico.** Ações principais (concluir série, salvar atividade, evolução, recorde, check-in,
contagem do WOD) disparam `UIImpactFeedbackGenerator`/`UINotificationFeedbackGenerator`.
Fonte: `GymBros/Train/WorkoutView.swift`, `GymBros/Train/Wod.swift`, `GymBros/Bros/EvolutionView.swift`, `GymBros/Train/PR.swift`, `GymBros/Activities/LogActivityView.swift`, `GymBros/DesignSystem/`.

**RNF-33 — Dynamic Type e acessibilidade.** A maior parte do texto usa estilos do sistema, que acompanham o Dynamic Type.
Textos com tamanho próprio (títulos de tela, nome do bro, números grandes de liga, WOD, peso e cronômetros, rótulos da barra de
abas e do BroBook) usam `gmFont`, que escala com `@ScaledMetric` relativo a um estilo (47 usos), quase sempre com `minimumScaleFactor`.
Restam 51 usos de `.font(.system(size:))` fixos (44 no app e 7 no widget do bro), quase todos em ícones e emojis. Componentes compactos têm teto:
a `GMTabBar` cresce até `xxLarge` e o pino do mapa até `xLarge`.
VoiceOver: todo `GMIconButton` tem rótulo (explícito em 42 dos 56 usos; nos outros, derivado do ícone: "Fechar", "Voltar", "Ajustes",
"Mais opções"…); `GMFloatingButton`, os botões de `GMCompactStepper` ("Diminuir"/"Aumentar"), as abas (com a contagem do badge),
o botão de série feita, a sequência ("N dias seguidos"), a origem Saúde, o convite da liga e o `GMOnlineDot` também têm rótulo.
`GMToggle` é um elemento só, com o título como rótulo, o subtítulo como dica, valor "Ativado"/"Desativado", traço `.isToggle` e ação padrão que alterna (VoiceOver, Controle por Botão e Controle por Voz).
As caixas de aceite dos termos e da política (`LegalConsent`) são um elemento só, com rótulo "Li e concordo com os Termos de uso"/"…a Política de privacidade", valor "Marcado"/"Desmarcado" e a ação "Ler os Termos de uso"/"Ler a Política de privacidade";
os bros da Box e as formas do BroBook têm rótulo com nome e estágio (ou "Forma não descoberta"); a música do amigo é lida como "Ouvindo …".
Movimento reduzido: com `accessibilityReduceMotion`, o pulso e a animação do card do amigo ao vivo param e o tutorial troca as molas e a escala por transição simples.
Fonte: `GymBros/DesignSystem/DesignSystem.swift` (`gmFont`, `GMScaledFont`), `GymBros/DesignSystem/GMButtons.swift` (`GMIconButton.defaultLabel`), `GymBros/DesignSystem/GMTabBar.swift`, `GymBros/App/TermsView.swift` (`LegalConsent`), `GymBros/Bros/Monsters.swift`, `GymBros/Bros/DexView.swift`, `GymBros/Friends/FriendsLive.swift`, `GymBros/Onboarding/SpotlightOverlay.swift`, grep em `GymBros/` e `GymBrosWidget/`.
**Recomendação:** telas principais utilizáveis até `accessibility3` sem cortar texto; trocar os tamanhos fixos restantes; descrever sprites (forma e estágio do bro) e gráficos para o VoiceOver.

**RNF-34 — Idioma pt-BR e formatação.** Região de desenvolvimento `pt-BR`; textos escritos direto em português
(sem `.strings`/`.xcstrings`); datas formatadas com `Locale("pt_BR")` ("Hoje", "Ontem", "seg, 3 de março");
voz do modo fone em pt-BR. Números internos de configuração usam `en_US_POSIX` para serialização estável.
Fonte: `pbxproj` (`developmentRegion = "pt-BR"`), `GymBros/DesignSystem/GMCalendar.swift` (l. 20), `GymBros/Train/HeadphoneControl.swift` (l. 61), `GymBros/Models/League.swift` (l. 85).
**Recomendação:** extrair os textos para String Catalog antes de suportar outro idioma.

## 7. Manutenibilidade e testabilidade

**RNF-35 — Testes rodam no aparelho, dentro do app.** O alvo de testes usa `TEST_HOST`/`BUNDLE_LOADER` do app;
`GymTestCase` salva e restaura as chaves de `UserDefaults` e os recordes manuais e usa banco em memória, para não mexer nos dados reais.
Fonte: `pbxproj` (l. 487, 499), `GymBrosTests/TestSupport.swift`.

**RNF-36 — Cobertura atual por arquivo de teste (262 testes em 31 arquivos, contados por `func test` em `GymBrosTests/`; todos XCTest).**
A mesma contagem saiu do `xcodebuild test` no iPhone em 19/10/2026: 262 executados, 0 falhas.

| Arquivo | Testes | O que cobre |
|---|---|---|
| `GameTests.swift` | 10 | fórmula de XP, teto diário, chocar ovo, galhos de evolução, híbrido, espécie pela atividade com mais da metade dos minutos (tipo exato do Saúde, mistura vira Coelho), toda atividade com animal, sequência, destino do XP (`Roster.owners`), cache de snapshot igual ao cálculo direto |
| `AttributeSplitTests.swift` | 8 | divisão dos atributos pela categoria, pelas séries (pesado × leve, olímpico), pelo ritmo e distância, pelo WOD e pelo tipo do Saúde; texto guardado ida e volta; `Game` usa a divisão guardada |
| `ProgressionTests.swift` | 25 | progressão de carga, deload, reps/segundos, metas, aquecimento, 1RM Epley, recordes, incremento de 5 kg só com barra, formatação de 1,25, calculadora pelo incremento, melhor marca sem misturar 1RM e carga, esforço do encerramento automático, deload em qualquer prescrição, nome do personalizado, ordem da troca, rampa feita à mão fora das séries de trabalho, carga e séries sem subir juntas, pirâmide perto do topo conta como trabalho |
| `WorkoutTests.swift` | 16 | superset, descanso, aquecimento fora do log e dos totais, deload semanal, ranking por período, textos de início, renovação de temporada, troca em superset (parcial e total), aviso "Dez segundos", CAP do For Time |
| `ManualWorkoutTests.swift` | 2 | treino feito sem "Começar": rotina vira sessão encerrada, WOD vira resultado |
| `WorkoutTypeTests.swift` | 2 | catálogo de tipos do Saúde e busca |
| `LeagueTests.swift` | 19 | pesos por atributo, métricas, janela do mês, desempates, regra de foto, "Vale ½" sem zerar, pontuação de check-in restaurado, ids estáveis e legados de times, ranking com `remote` injetado, mesmo bro em todo lugar, estabilidade do mock, placar do time, `LeagueDraft` ida e volta, retirada só de check-in já publicado |
| `SwissTests.swift` | 19 | rodada suíça: pareamento sem revanche (e revanche quando inevitável), folga rotativa, determinismo com ids globais, resultado por critério, hoje não pontua, bônus no ranking, regra de foto, quem entra depois só a partir do dia em que entrou |
| `LiveShareTests.swift` | 4 | Treino ao vivo: padrão ligado, ajuste e escolha por treino, chaves da conta |
| `DuelTests.swift` | 14 | X1: janela de 24 h, valor só na janela, métricas, resultado e retrospecto, atualização rápida, expiração, um aberto por par, bloqueio, mock (resposta, ~80% de aceite, recusas), resposta persistida |
| `DuelFighterTests.swift` | 2 | ovo não luta; o bro escolhido te representa |
| `NamesAndBarTests.swift` | 2 | nomes únicos de todas as formas (22 por espécie), carga com ou sem barra pelo tipo do treino |
| `DexEntryTests.swift` | 2 | ficha do BroBook: linha evolutiva e como conseguir |
| `StoryTests.swift` | 4 | card do story: sem peso não há calorias, com peso há estimativa, kcal do Saúde vence a estimativa, corrida com distância, pace e trajeto |
| `KeychainTests.swift` | 1 | gravar, sobrescrever e apagar a sessão no Keychain |
| `WodImportTests.swift` | 13 | leitura do treino do coach (seções, formatos, time cap, seções numeradas, formato não achado, blocos e linhas, data do título), movimentos reconhecidos e apelidos válidos, prints juntados, WOD importado pendente até ter resultado |
| `WodTimelineTests.swift` | 2 | linha do tempo dos WODs: resultado no importado, resultados avulsos e planos antigos mantidos |
| `StoreTests.swift` | 3 | banco do aparelho abre com o schema atual sem ser movido, container em memória com o `AppMigrationPlan`, migração V1 → V2 em disco |
| `LeagueFlushTests.swift` | 2 | `flush` concorrente envia cada item uma vez e grava `syncedAt`; item apagado durante o envio não derruba o app |
| `BackupTests.swift` | 2 | ida e volta do backup com `syncedAt`/`joined` das ligas e check-ins e os ajustes com tipo; backup antigo restaura ligas e check-ins como já enviados e de outra pessoa |
| `HealthPrivacyTests.swift` | 6 | check-in de atividade do Saúde sobe sem kcal e distância (também no `CKRecord`), atividade do app mantém o esforço, `healthType` sozinho conta como Saúde, distância do GPS do app sobe, seu placar igual ao que os outros calculam |
| `AccountDeletionTests.swift` | 6 | `wipeSocial` apaga ligas, check-ins, recados, comentários e chaves sociais; excluir conta chama o servidor primeiro e apaga tudo do aparelho e a sessão do Keychain; falha no servidor não apaga nada; sem sessão nada é postado; mock libera o e-mail e volta aos amigos de exemplo |
| `AccountSyncTests.swift` | 10 | dados sem dono adotados, sair limpa e entrar restaura (e os stores de denúncias e caixa de entrada releem depois de restaurar), troca de conta não mistura (nem o estado dos servidores simulados), dados de outra conta guardados antes de sair, excluir apaga servidor simulado, aparelho e cópias guardadas da conta, exclusão interrompida termina antes da próxima conta, falha ao excluir mantém tudo (banco em memória, suites e pastas temporárias) |
| `ModerationTests.swift` | 9 | denúncia esconde só o conteúdo e chega ao servidor (inclusive sem rede, com reenvio), foto denunciada, bloqueio em tudo sem mudar o placar, desbloqueio, lista do servidor, exclusão de conta, mock |
| `InboxTests.swift` | 14 | caixa de entrada: notificações (primeira busca, tópico, pausa, conversa aberta, itens antigos, X1 uma vez), não lidos, convite, só amigos e filtro, bloqueio e denúncia, sem permissão nada sai, UUID estável |
| `MusicShareTests.swift` | 5 | "Ouvindo agora" desligado por padrão, ligar lê a música, acesso negado, Spotify escondido sem registro, chaves vão com a conta |
| `ContentFilterTests.swift` | 8 | termos, acentos, trocas de letras, palavras inocentes, lista própria, `publishable`, check-in barrado |
| `TermsTests.swift` | 4 | aceite com versão e data, versão nova pede de novo, `TermsGate` espera o aceite, excluir conta apaga o aceite |
| `AccessTests.swift` | 24 | RBAC: matriz exata e exaustiva, escopo próprio, roles somadas, valores inválidos, deslogado, carregando, falha, troca de conta, contas de teste, envios sem permissão, `AdminActions` |
| `DemoAccountTests.swift` | 5 | conta de demonstração só no `.mock`, entra uma vez na liga de exemplo, credenciais fixas, `demoSeeded` é chave da conta |
| `OnboardingTests.swift` | 19 | tutorial: roteiro, persistência por conta, pular, retomar, não abrir sobre modais ou treino, alvo ausente pulado, recorte, barra de abas, rolagem até o alvo, argumentos de lançamento |

Sem testes: rollback da restauração do backup, recuperação do banco, importação/escrita no Saúde, localização, widget, amigos (só o bloqueio por permissão), validação do login com e-mail/Apple (`AuthStore`), `ActivitySplits.stamp`, leitura de prints (`WodOCR`) e `WodAI`, backends CloudKit (inclusive `CloudKitDuelBackend`) e telas.
**Recomendação:** testes do rollback da restauração e do `hadPhoto` no backup, da recuperação do banco e da deduplicação com o Saúde; meta mínima de cobertura nas regras de `Game`, `Training`, `Leagues` e `Backup`.

**RNF-37 — Contratos de backend substituíveis.** `AuthBackend` (`signInWithApple`, `signIn`, `signUp`, `signOut`, `deleteAccount`),
`AccountDataBackend` (`upload`, `download`, `delete`), `LeagueBackend` (`fetch`, `send`, `create`, `join`, `setMembership`, `publish`, `retract`, `leave`),
`DuelBackend` (`duels`, `challenge`, `respond`, `report`), `FriendsBackend` (`fetch`, `add`, `accept`, `decline`, `remove`, `profile`, `publish`),
`ModerationBackend` (`report`, `block`, `unblock`, `blockedUsers`) e `InboxBackend` (`fetch`, `send`), além do `RoleBackend` do RBAC, são protocolos `Sendable` com tipos `Codable`; as telas falam só
com eles. `Backend.install()` escolhe mock ou CloudKit pelo interruptor `Backend.mode`; outro servidor é mais uma implementação.
No `.cloudKit`, `AccountDataBackend` e `InboxBackend` ainda são implementações que só lançam erro (`ServerAccountDataBackend`, `ServerInboxBackend`).
Fonte: `GymBros/Services/Backend.swift`, `GymBros/Services/Auth.swift`, `GymBros/Services/AccountSync.swift`, `GymBros/Leagues/LeagueRemote.swift` (`LeagueBackend`), `GymBros/Duels/DuelStore.swift` (`DuelBackend`), `GymBros/Friends/Friends.swift` (`FriendsBackend`), `GymBros/Moderation/Moderation.swift`, `GymBros/Inbox/Inbox.swift` (`InboxBackend`).

**RNF-38 — Regras isoladas da interface.** Regras de jogo, divisão dos atributos, progressão, ranking, rodada suíça e X1 ficam em tipos puros
(`Game`, `AttributeSplit`, `Training`, `LeagueBoard`, `Swiss`, `Duels`), testáveis sem UI.
Fonte: `GymBros/Bros/Game.swift`, `GymBros/Bros/AttributeSplit.swift`, `GymBros/Train/Progression.swift`, `GymBros/Leagues/Leagues.swift`, `GymBros/Leagues/Swiss.swift`, `GymBros/Duels/Duel.swift`.

## 8. Integridade do jogo (anti-farm)

**RNF-39 — Limites de XP.** Cada atividade conta no máximo 240 min; acima de 150 XP no dia o ganho cai para 1/3, com teto de 300 XP/dia.
Critério: `testDailyHardCap` passa; nenhum dia soma mais de 300 XP.
Fonte: `GymBros/Bros/Game.swift` (l. 371–377: `maxMinutes`, `dailySoftCap`, `dailyHardCap`).

**RNF-40 — Limiares de evolução fixos.** Bebê 60, Novato 300, Atleta 1200, Lenda 3600 XP; híbrido só com empate próximo (razão 0,9).
Fonte: `GymBros/Bros/Game.swift` (l. 132–135, 385).

**RNF-41 — Regra de foto nas ligas.** Check-in sem foto vale metade (arredondada para cima) ou não pontua, conforme a liga.
Fonte: `GymBros/Leagues/Leagues.swift` (`PhotoRule`); `testPhotoRule`, `testHalfPhotoNeverZeroesAScore`.
**Recomendação:** no servidor, os limites RNF-39 e RNF-41 devem ser recalculados do lado do servidor; a pontuação enviada pelo aparelho não deve ser confiável.

## 9. Evolução para servidor (requisitos do futuro backend)

Todos os itens desta seção são **Recomendação**: o servidor não está ligado. Existe uma implementação CloudKit desligada (`docs/cloudkit.md`); estes requisitos valem para ela ao ligar e para qualquer servidor próprio.

**RNF-42 — Autenticação obrigatória.** Nenhum endpoint com acesso anônimo; sessão por token de curta duração com renovação, guardado no Keychain (no modo CloudKit a identidade já é a conta do iCloud; Sign in with Apple é o caminho natural para o login da Apple de verdade).

**RNF-43 — Autorização por liga.** Só membros de uma liga leem participantes, check-ins, fotos, times e mural daquela liga;
só o autor apaga o próprio check-in ou recado; código de convite não dá acesso a dados antes de entrar.
Critério: teste de API com usuário de fora da liga recebe 403 em todos os recursos da liga.

**RNF-44 — Amizade e perfil público.** `profile(id)` devolve só o que a pessoa marcou como público (RNF-13), e só para amigos ou colegas de liga.
O perfil privado (peso, medidas, recordes, calendário completo) nunca é mostrado a outras pessoas; vai só na cópia da conta (RNF-07).

**RNF-45 — PII e fotos.** Nome, @usuário, bio, foto do perfil e fotos de check-in são dados pessoais: armazenar em ambiente
corporativo aprovado, com criptografia em repouso, URLs de foto assinadas e com expiração, remoção de EXIF/GPS das imagens
e exclusão de conta que apague tudo. Academias e percursos vão só na cópia da conta (dita na política) e nunca são compartilhados sem consentimento explícito.
Em desenvolvimento, usar dados sintéticos (como os do mock atual).

**RNF-46 — Sincronização da caixa de saída.** Ligas, check-ins e recados ficam locais com `syncedAt = nil` até o servidor
aceitar; check-ins apagados depois de publicados entram em `LeagueOutbox` para serem retirados. `LeagueRemoteStore.flush` roda ao
abrir o app e 2 s depois de cada mudança (`scheduleFlush`), um envio por vez (chamadas concorrentes esperam o anterior); erro
deixa tudo pendente para a próxima vez. O envio deve ser
idempotente pelo `uuid` gerado no aparelho (reenvio ou edição atualiza, não duplica).
Fonte do comportamento atual: `GymBros/Leagues/LeagueRemote.swift` (`flush`, `scheduleFlush`, `LeagueOutbox`), `GymBros/Leagues/LeagueMural.swift`; `testOnlyPublishedCheckInsAreRetracted`, `GymBrosTests/LeagueFlushTests.swift`.

**RNF-47 — Infraestrutura.** Produção na ORKA; se Vercel ou Supabase forem usados, contas corporativas e, no Supabase,
RLS ligado em todas as tabelas; banco sem porta aberta para a internet.

**RNF-48 — Identidade do app.** Bundle IDs (`com.alonsoalmeida.gymbros*`), App Group e `DEVELOPMENT_TEAM = 5UV7WAAAL2`
continuam na conta pessoal (migração ainda não feita). Antes de publicar ou ligar um servidor, migrar para a conta corporativa (o App Group muda junto e exige migrar o banco SwiftData, que está no container do grupo, e os dados do widget).
Fonte: `pbxproj`, entitlements.

## 10. Requisitos acrescentados (outubro/2026)

**RNF-50 — "Ouvindo agora" opcional e desligado por padrão.** A música só é lida se a pessoa ligar Ajustes > Música; ligar pede o acesso ao
Apple Music (`MPMediaLibrary`, texto "Para mostrar aos seus amigos a música que está tocando enquanto você treina, se você ligar essa opção.")
e, se negado, a opção continua desligada com a explicação. A leitura é local (app Música, sem a capability MusicKit) e, nesta versão, nada
sobe: a música dos amigos no mapa é simulada. O Spotify não aparece enquanto `SpotifyNowPlaying.clientID` for `nil`. A escolha (`shareMusic`,
`musicSource`) vai com a conta.
Critério: com a opção desligada, `MusicShareStore` não consulta o provedor; acesso negado mantém desligado (`MusicShareTests`).
Fonte: `GymBros/Music/Music.swift`, `GymBros/App/SettingsPages.swift` (`MusicSettingsPage`), `INFOPLIST_KEY_NSAppleMusicUsageDescription` no `pbxproj`.
**Recomendação:** ao enviar a música junto com o treino ao vivo, mandar só título, artista e serviço, só para amigos e só enquanto o treino estiver ao vivo; incluir o dado na política de privacidade e no `PrivacyInfo.xcprivacy`.

**RNF-51 — Mensagens diretas fora do banco público.** Mensagens, força e convites para treinar junto (com lugar e hora) passam pelo `InboxBackend`.
No `.mock` ficam no aparelho (`mockInbox`, estacionado por conta); no `.cloudKit`, `ServerInboxBackend` lança `InboxError.needsServer`, porque
no banco público qualquer conta do iCloud leria as conversas. Só se manda para amigos (ou para quem já conversou com você), com a permissão
`directMessagesSend`, sem bloqueados e com o `ContentFilter`; mensagens denunciadas e de bloqueados somem.
Critério: `InboxTests` (só amigos e filtro, bloqueio, denúncia, sem permissão nada é enviado).
Fonte: `GymBros/Inbox/Inbox.swift` (`InboxStore.send`, `ServerInboxBackend`), `GymBros/Inbox/InboxMock.swift`.
**Recomendação:** no servidor próprio, mensagens cifradas em repouso, acesso só dos dois participantes, retenção de 90 dias (o que o contrato já assume) e push filtrado pelas preferências de notificação.

**RNF-52 — Rodada suíça determinística e igual em todos os aparelhos.** O pareamento diário sai só do feed, dos membros e da data:
1º dia por hash (id global + código da liga + dia), depois por pontos suíços com desempate pelo id global (`"me"` vira `Cloud.knownID`);
busca de pareamento sem revanche limitada a 5 mil passos por rodada, com recuo para a menor revanche. Só dias encerrados contam, e cada
membro entra a partir do dia em que entrou (`joinedAt`). O critério (`swissRaw`) passa para a próxima temporada na renovação.
Critério: `SwissTests` (determinismo com ids globais, sem revanche quando possível, hoje não pontua, entrada tardia).
Fonte: `GymBros/Leagues/Swiss.swift` (`Swiss.table`, `pair`, `dayStamp`), `GymBros/Leagues/Leagues.swift` (`LeagueBoard.swiss`, `LeagueRenewal`).
O dia da rodada, a semente e o corte "dia encerrado" usam um fuso fixo (`Swiss.calendar`, America/Sao_Paulo), não o do aparelho: membros em fusos diferentes chegam ao mesmo pareamento.

**RNF-53 — Divisão dos atributos estável depois de salva.** A divisão do XP entre os atributos é calculada uma vez, ao salvar a atividade, e guardada
por id (`activitySplits`); mudar as regras de `AttributeSplit` não reescreve atividades antigas, e atividades sem divisão guardada seguem a tabela da categoria.
A divisão soma 1, sem fatias abaixo de 3%, e vai no backup e na cópia da conta (dentro de cada atividade).
Critério: `testGameUsesStoredSplit`, `testEncodeRoundTrip`, `testPlainActivityKeepsCategoryTable`.
Fonte: `GymBros/Bros/AttributeSplit.swift` (`AttributeSplit.split`, `tidy`, `ActivitySplits`), `GymBros/Services/Backup.swift` (`ActivityDTO.attributes`).
Ao sair ou excluir a conta, `wipeAll` zera `activitySplits` (e o cache em memória); `duelMonsters`, `duelScoreRecords` e `recentWorkoutTypes` estão em `AccountData.userKeys`. No restore do backup, a divisão só é trocada depois do `save()`.
Apagar uma atividade apaga a entrada dela.

**RNF-54 — X1 sem efeito nas ligas e com regras conferidas.** O X1 dura 24 h a partir do aceite (o pendente expira em 24 h), vale qualquer atividade
na janela e não mexe em placar, pontos nem rodada suíça. Um X1 aberto por par; ninguém desafia a si mesmo, quem bloqueou ou foi bloqueado; ovo não luta.
Critério: `DuelTests`, `DuelFighterTests`.
Fonte: `GymBros/Duels/Duel.swift` (`Duels.refusal`, `acceptRefusal`, `phase`), `GymBros/Duels/DuelStore.swift`.
O valor informado usa só dados publicáveis (`publishableEffort`, `publishableMeters`, `publishableKcal`): kcal, distância e esforço do Apple Saúde não saem do aparelho. Desafios cruzados quase juntos: só o mais antigo pode ser aceito. No CloudKit, só vale o registro `Duel` criado pela própria pessoa (`creatorUserRecordID` igual a `user`), e o valor usa um nome de registro aleatório guardado no aparelho (`duelScoreRecords`), para ninguém travar o envio do outro.
Observação: as regras ainda são conferidas no aparelho, e cada lado informa o próprio valor; `CloudKitDuelBackend` grava no banco público, legível por qualquer conta.
**Recomendação:** no servidor, recalcular o valor de cada lado a partir dos check-ins ou atividades enviados, conferir par aberto e bloqueio do lado do servidor e restringir a leitura dos registros `Duel` aos dois participantes (vale o RNF-41).

**RNF-55 — Atualização periódica limitada ao app ativo.** Sem push, a caixa de entrada (e com ela os X1) é consultada ao app ficar ativo e a cada
45 s enquanto ele está ativo e com sessão; a tela do X1 atualiza a cada 3 s nos 2 min depois de você desafiar e a cada 30 s no resto. Nada roda em segundo plano.
Critério: com o app em segundo plano, nenhuma consulta da caixa de entrada nem do X1.
Fonte: `GymBros/App/App.swift` (`.task(id: phase)`), `GymBros/Duels/Duel.swift` (`refreshInterval`, `fastWindow`), `GymBros/Duels/DuelViews.swift`.
**Recomendação:** com servidor, trocar o intervalo fixo por push (APNs ou `CKQuerySubscription`) e consultar só ao abrir.
