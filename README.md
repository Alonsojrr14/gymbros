# GymBros

App de iPhone (SwiftUI + SwiftData, iOS 17) em que seus treinos chocam e evoluem um bro.

- Ao começar você ganha um **ovo**, que choca com 60 XP de atividade.
- Cada atividade (um dos 80 tipos de treino do Apple Saúde: musculação, corrida, crossfit, vôlei…) rende XP por **duração × MET da atividade × esforço (1–10)** e soma em quatro atributos: **Força, Resistência, Agilidade e Técnica**. A divisão entre os atributos é calculada para cada treino pelas séries, pelos movimentos do WOD, pelo ritmo e pelo esforço (`GymBros/Bros/AttributeSplit.swift`), e fica gravada com a atividade.
- Estágios: Ovo → Bebê (60 XP) → Novato (300) → Atleta (1200) → Lenda (3600).
  Em Atleta e Lenda, o atributo mais treinado desde a última evolução decide o galho.
- Anti-farm: no máximo 240 min por atividade; acima de 150 XP no dia o ganho cai para 1/3, com teto de 300 XP/dia.
- Tudo é derivado do histórico (`GymBros/Bros/Game.swift`): apagar ou editar uma atividade recalcula a evolução.
- Na primeira vez, um tutorial de 9 passos destaca cada parte do app (`GymBros/Onboarding/`).
- Conta obrigatória (e-mail ou Apple): treinos, bros e o resto do progresso são da conta, saem do iPhone ao sair e voltam ao entrar (`GymBros/Services/AccountSync.swift`). Nesta versão o login e o servidor da conta são simulados no próprio iPhone (um arquivo por conta).

## Musculação guiada

- Rotinas por dia da semana (ou modelos prontos: ABC, Full body, Superior/Inferior, Em casa) sobre a biblioteca de exercícios (ver Biblioteca e CrossFit).
- Treino guiado: cargas sugeridas a partir do histórico, timer de descanso com aviso em segundo plano, tela sempre acesa.
- Progressão (`GymBros/Train/Progression.swift`): completou todas as séries → +2,5 kg (+5 kg em pernas/costas); 3 treinos seguidos sem completar → deload de 10 %. Peso do corpo progride em reps, isometria em segundos.
- Recordes de carga e 1RM estimado (Epley, até 12 reps), gráfico por exercício.
- Biblioteca com imagens, vídeos, instruções e músculos trabalhados; exercícios personalizados.
- Peso do corpo e isometria aceitam carga extra (cinto de peso, colete); com carga, a progressão volta a ser por peso.
- **Rotinas públicas**: publique as suas, curta e salve cópias das dos bros (mais salvas, curtidas, novas ou dos amigos); cada rotina mostra a sua frequência e o tempo médio.
- **Modo guiado**: uma série por vez, com "da última vez", alvo, registrar, desfazer, anterior e próxima.
- Exercícios de **distância × tempo** (remo, esteira, bike, elíptico): metros e segundos por série, progressão por tempo e recorde de maior distância.
- Mapa muscular (frente e costas): por exercício, por rotina, ao concluir o treino e por período (7/30 dias/tudo), com a lista do que ficou sem treino.
- Concluir um treino gera uma atividade de musculação, que dá XP ao bro.
- Esqueceu de dar "Começar"? Ao registrar a atividade dá para informar o que foi feito depois: uma rotina, um treino livre, o WOD do coach ou um WOD clássico (`GymBros/Activities/ManualWorkout.swift`).

## Design system

O app quase não usa controles padrão do iOS: telas, cabeçalhos, barra de abas, botões, abas segmentadas, chaves, steppers, seletor de esforço, data/hora, campos, bottom sheets de ações/confirmação e diálogos ficam em `GymBros/DesignSystem/` (prefixo `GM`). Só continuam do sistema o teclado, o seletor de fotos, a tela de compartilhar, o seletor de arquivos e os pedidos de permissão.

## Ligas

- Inspiradas no GymRats: escolha entre um **Clube** permanente, com ranking total, semanal e mensal, ou um **Desafio** com início, fim, vencedor e temporadas renováveis. Ambos recebem check-ins de qualquer atividade e têm feed com foto.
- Pontuação (`GymBros/Leagues/Leagues.swift`): pontos (XP da atividade), treinos, minutos, distância (GPS do app ou Apple Saúde) ou calorias (do Saúde ou estimadas). No modo pontos, cada liga define um peso de 0× a 3× por atributo (ex.: Resistência 2× favorece cardio; 0× tira o atributo da conta).
- Quem cria define se **todos** os tipos de treino contam, se contam **só os selecionados** (ex.: musculação e crossfit) ou se todos contam **exceto os selecionados** (ex.: bike e skate). A escolha usa os ~80 tipos do catálogo, não só categorias genéricas.
- Desempate escolhido na liga: quem chegou antes à pontuação, maior sequência de dias seguidos ou mais check-ins. O ranking mostra quando a posição foi decidida no desempate.
- Mais modos de pontuação: **dias ativos** (um por dia, por mais treinos que a pessoa faça) e **por atividade** (o dono monta a tabela: cada tipo vale pontos por vez ou por quantidade, e pode até tirar pontos). **Limite de pontos** por dia, semana, mês e total, por pessoa e por time, e **metas** com barra de progresso, com ou sem ranking. O dono escolhe o dia em que a semana começa.
- **Verificação do check-in** (`GymBros/Leagues/LeagueRules.swift`): presets Padrão, Bro-verificação e Personalizar (foto obrigatória, galeria só com hora verificada pelo EXIF, mesmo dia, retroativo, aparelho e local obrigatórios). A câmera do app vale como foto verificada; liga que barra o check-in aparece bloqueada em "Postar em" com o que fazer. **Revisão do dono** (aprovar ou negar cada check-in) e **pose do dia** na foto.
- Clube guarda os **campeões** da semana, do mês e do ano (títulos no perfil); desafio encerrado mostra a classificação final para compartilhar e pode ser **reiniciado** com as mesmas pessoas e regras.
- **Moderação**: moderadores, remover e banir, pedidos de entrada com aprovação, prévia da liga antes de entrar, quem fica de dono quando o dono sai, exportar os check-ins em CSV e notificações por liga (mural com @menções, check-ins, reações, campeões e moderação).
- Check-in com **várias atividades do mesmo dia** somando juntas e **até 5 fotos**; mural com fotos e a aba **Mídia**.
- **Visita verificada** (a localização registrou você na academia durante o treino) vale como prova; modo **"Você diz"** (cada um informa os pontos); **treino do dia** do dono e **desafios dentro do clube**.
- **Feed** com Todos, Amigos e cada liga, sem repetir o mesmo post, e **Ranking dos bros** entre amigos sem precisar de liga.
- **Deck dos Bros** (`GymBros/Friends/SocialExtras.swift`): os check-ins que você ainda não viu, um por vez; arrasta para passar, toque duplo manda força, e responde no check-in ou por mensagem.
- Foto do treino: opcional, sem foto vale metade, ou obrigatória (sem foto não pontua). O formulário de check-in avisa quando falta a foto.
- Rodada suíça diária (`GymBros/Leagues/Swiss.swift`): todo dia cada membro enfrenta alguém com pontuação suíça parecida, pelo critério da liga (mais pontos, mais check-ins ou presença). Vitória ou folga dá um bônus pequeno no placar. O pareamento é determinístico, igual em todos os aparelhos do mesmo fuso.
- Times: o placar do time é a soma dos membros, e cada time tem um bro que cresce com a média de XP dos membros e evolui pelo atributo que o time mais treina. Você escolhe o time tocando nele no ranking.
- Mural: recados da galera da liga, cada um com o seu bro.
- X1 (`GymBros/Duels/`): desafio direto entre duas pessoas quaisquer, sem relação com ligas. Quem desafia escolhe a métrica (XP, treinos, minutos, distância ou calorias) e o bro que luta; aceito, vale tudo o que cada um registrar nas 24 h seguintes. Um X1 aberto por par; o retrospecto aparece na tela inicial e no perfil.
- Caixa de entrada (`GymBros/Inbox/`): mensagens diretas com amigos, convites para treinar junto e notificações sociais (força, pedidos de amizade, X1), com tópicos ligáveis em Ajustes → Notificações.
- Amigos (botão na tela inicial, `GymBros/Friends/Friends.swift`): seu código de amigo para compartilhar, adicionar por código, pedidos recebidos e sugestões de quem está nas suas ligas e ainda não é seu amigo. Mesmo esquema das ligas: `FriendsBackend` com `MockFriendsBackend` simulado; quem deixa de ser amigo some do mapa.
- Perfil do amigo (toque na lista de amigos, `GymBros/Friends/PublicProfile.swift`): foto, nome, @usuário, bio, se está treinando agora, e o mesmo card público da prévia do seu perfil (bro principal, números e conquistas, respeitando o que a pessoa escondeu), ligas em comum e posts em calendário (toque no dia para ver os posts). Vem de `FriendsBackend.profile`.
- Seu perfil: a aba Público é exatamente o que os amigos veem (card público e posts em calendário); a aba Privado tem seus números, recordes, estatísticas, metas, peso e o calendário de todas as atividades. Nome, @usuário, bio e o que aparece para os outros ficam em "Editar perfil".
- Check-in em várias ligas de uma vez: ao registrar atividade, ao concluir treino guiado ou pelo botão da liga (nova atividade ou uma já registrada, inclusive do Saúde).
- Por amigo: esconder os seus treinos, silenciar, arquivar e limpar a conversa (só do seu lado), reagir às mensagens e aos comentários, e adicionar por **QR** (`gymbros://amigo/CÓDIGO`).
- Coleção de bros (`GymBros/Bros/Monsters.swift`): ao entrar numa liga você escolhe quem te representa, um bro seu ou um ovo novo adotado na hora. Os check-ins da liga dão XP só para ele; atividades fora de ligas vão para o bro principal (tela inicial e widgets), que pode ser trocado em "Meus bros".
- Sem servidor ainda: tudo o que envolve servidor passa por sete contratos (login, dados da conta, ligas, amigos, moderação, caixa de entrada e X1). Um interruptor em `GymBros/Services/Backend.swift` (`Backend.mode`) escolhe quem responde: hoje é `.mock`, com dados simulados e determinísticos no próprio iPhone; as implementações do CloudKit já existem e esperam a conta paga do Apple Developer ([docs/cloudkit.md](docs/cloudkit.md), [docs/servidor-real.md](docs/servidor-real.md)). A "Liga dos Bros" (código `AMIGOS`) tem 8 participantes simulados divididos em dois times (Gui, Lia e Rafa ainda não são seus amigos).

## Metas e constância

- **Metas pessoais** (`GymBros/Profile/Constancy.swift`): treinos, dias ativos, minutos, km ou kcal por dia, semana, mês ou ano (ou até uma data), só com os treinos que você escolher; bater a meta mantém a sequência viva. 11 modelos prontos.
- **Sequências e recordes**: dias, semanas e meses seguidos (atual e melhor), melhor dia, semana, mês e ano, dia e hora mais ativos, madrugador e coruja.
- **Retrospectiva em vídeo** (`GymBros/Activities/Retrospective.swift`): as fotos dos check-ins do ano, em 9:16, 1:1 ou 3:4, abrindo com os seus números.
- Widget **"Último treino dos bros"** com o check-in mais recente das suas ligas.
- Ajustes → GymBros: **GymBros Pro** (fica tudo liberado até o app estar na App Store) e **Vem aí**, para votar no que sai primeiro.

## Biblioteca e CrossFit

- 262 exercícios, com imagens, vídeos e instruções de licença comercial e crédito por item, embutidos em `GymBros/Resources/wger.json`: wger (CC BY-SA/CC0), ilustrações do Everkinetic (CC BY-SA 4.0) e fotos do Wikimedia Commons. Instruções em inglês traduzidas no próprio iPhone (iOS 18+). Tela "Créditos e licenças" nos Ajustes; detalhes em [CREDITOS.md](CREDITOS.md).
- CrossFit: 42 movimentos (olímpicos, ginásticos, metcon) e modo WOD (`GymBros/Train/Wod.swift`) com 15 benchmarks (Fran, Grace, Cindy, Helen, Murph, DT…), cronômetro For Time / AMRAP / EMOM / Tabata, resultados com RX e recorde por WOD. Cada WOD vira atividade de crossfit.
- Treino do coach (`GymBros/Train/WodImport.swift`): colar o texto ou ler até 6 prints do app do box; o app reconhece formato, data e movimentos (`WodMovements.swift`), agenda o WOD do dia e oferece começar ao chegar no box. "Meus WODs" (`WodTimeline.swift`) junta os WODs trazidos e os resultados numa linha do tempo.

## Localização

- Aba Mapa (`GymBros/Friends/MapScreen.swift`): mapa com academia e percursos, status (na academia ou a que distância), automações, frequência (visitas no mês e tempo médio) e atividades ao ar livre.
- Lugares de treino (`GymBros/Services/Location.swift`): histórico de academias. Ao começar musculação ou WOD, o app identifica o lugar salvo em que você está ou pergunta (lugares salvos por perto, academias reais sugeridas pelo mapa da Apple, novo lugar, ou sem local). Ao chegar num lugar salvo, notificação e oferta de começar o treino do dia; ao sair, o treino daquele lugar (com mais de 10 min) é encerrado e salvo. Usa `CLMonitor` (até 20 lugares), que acorda o app em segundo plano. Atividades e check-ins guardam o lugar.
- Corrida, caminhada e bike com GPS (`GymBros/Services/Route.swift`): percurso no mapa, distância, tempo e ritmo, com a tela bloqueada; percurso salvo e visível no histórico.
- Lugares e percursos fazem parte dos dados da conta. Treino ao vivo (`GymBros/Friends/LiveShare.swift`, ligado por padrão): durante um treino, os amigos veem no mapa onde você está, a atividade e o exercício atual; o primeiro acesso explica e deixa desligar, e cada treino tem o chip "Ao vivo" para escolher só para ele.
- "Ouvindo agora" (`GymBros/Music/Music.swift`, desligado por padrão): enquanto você treina ao vivo, os amigos veem a música que toca no app Música. O Spotify só aparece quando o app for registrado no Spotify for Developers.

## Apple Saúde e backup

- Treinos do iPhone/Apple Watch são importados ao abrir o app (Ajustes → Apple Saúde; na primeira vez, últimos 14 dias). O tipo vira a atividade correspondente e o esforço é estimado pelas calorias ativas em relação ao esperado para a atividade. Treinos que se sobrepõem a algo já registrado (ex.: treino guiado também gravado no Watch) não contam duas vezes. Opcionalmente, as atividades registradas no app também são gravadas no Saúde (Ajustes → Apple Saúde).
- Backup completo em JSON (Ajustes → Backup): exportar para o Arquivos/iCloud Drive e restaurar.

## Companheiro, conquistas e widget

- Humor do bro (animado, feliz, entediado, triste, exausto) pelos dias sem treinar, sequência e excesso no dia; balão com frases que citam a rotina do dia e músculos esquecidos na semana.
- 28 conquistas (Bros → Conquistas), com aviso ao desbloquear.
- BroBook com a ficha de cada forma (número, tipos, atributos, como conseguir e linha de evolução) e "Meus bros" numa Box.
- Lembretes locais no horário escolhido, só nos dias sem treino (opcional: só em dias de rotina).
- Widget "Meu bro" (pequeno, médio, grande e tela bloqueada redondo/retangular): muda de pose a cada minuto com transição animada e reage a carinho com um toque (widget interativo).
- Widget "Status do bro" (pequeno, médio e tela bloqueada) com bro, humor, XP e sequência. Os dados chegam pelo App Group `group.com.alonsoalmeida.gymbros` (`Shared/WidgetShared.swift`).


## Rodar no iPhone

```sh
xcodebuild -project GymBros.xcodeproj -scheme GymBros \
  -destination 'id=<UDID>' -derivedDataPath build -allowProvisioningUpdates build
xcrun devicectl device install app --device <UDID> build/Build/Products/Debug-iphoneos/GymBros.app
```

Testes (262, XCTest) no iPhone:

```sh
xcodebuild test -project GymBros.xcodeproj -scheme GymBros \
  -destination 'id=<UDID>' -derivedDataPath build -allowProvisioningUpdates
```

A versão web anterior (Next.js + Express) continua no branch `main`.

Requisitos, arquitetura e design system em [docs/](docs/README.md).

Créditos de terceiros em [NOTICE.md](NOTICE.md).
