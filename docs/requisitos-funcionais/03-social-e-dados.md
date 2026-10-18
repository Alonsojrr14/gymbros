# Requisitos funcionais 03: social, localização e dados

## Escopo

Este documento cobre a parte social do GymBros (ligas, check-ins, mural, comentários, amigos e perfil público), a localização (lugares de treino, chegada e saída, rotas GPS e amigos ao vivo no mapa), a integração com o Apple Saúde, o backup, os ajustes, o login e o compartilhamento nos Stories. Tudo foi levantado a partir do código atual, sem inventar comportamento. Os dados do usuário ficam no aparelho (SwiftData e `UserDefaults`), e tudo o que envolve servidor passa por três contratos: `AuthBackend` (login), `LeagueBackend` (ligas, check-ins e mural) e `FriendsBackend` (amigos e perfil público). Um interruptor em `GymBros/Services/Backend.swift` (`Backend.mode`) escolhe quem responde: hoje é `.mock`, com implementações simuladas e determinísticas (`MockAuthBackend`, `MockLeagueBackend`, `MockFriendsBackend`, `FriendsLive.simulated`); em `.cloudKit`, as implementações do CloudKit já escritas (`CloudKitAuthBackend`, `CloudKitLeagueBackend`, `CloudKitFriendsBackend`) assumem, o que exige conta paga do Apple Developer (ver `docs/cloudkit.md`). A liga de exemplo `AMIGOS` continua simulada nos dois modos. Cada requisito traz uma linha **Situação**, que pode ser:

- **Local**: funciona de verdade, só no aparelho.
- **Simulado**: hoje mostra dados de exemplo gerados no próprio app.
- **Depende de servidor**: já existe o contrato ou a interface, mas só vai funcionar entre pessoas reais com `Backend.mode = .cloudKit` (ou, onde indicado, quando houver um backend que ainda não existe).

---

## 1. Ligas

### RF-SOC-01 · Lista de ligas
**Descrição:** O app deve listar as ligas em que o usuário está, com o atalho para criar, entrar por código ou experimentar a liga de exemplo.
**Regras:**
- A lista é ordenada por data de entrada (`joinedAt`) e esconde as temporadas passadas (ligas com `nextUUID`).
- Cada linha mostra o emoji, o nome, o selo "exemplo" (quando `isMock`), o ícone de renovação, "T{n} · " quando a temporada é maior que 1, a posição ("3º de 9") e o tempo restante: "encerrada", "último dia", "faltam N dias" ou, sem data de fim, o nome do modo de pontuação. Também mostra o bro que representa o usuário na liga.
- O atalho "Experimentar a liga de exemplo" só aparece enquanto o usuário não tem uma liga com o código `AMIGOS`.
- Ao abrir a aba, o app define 30 dias de duração para ligas de exemplo antigas que não têm data de fim, roda a renovação (RF-SOC-05) e atualiza os dados remotos.
**Critérios de aceitação:**
- Sem ligas ativas, a tela mostra o estado vazio "Nenhuma liga".
- Depois de uma renovação, só a temporada vigente aparece na lista.
**Situação:** Local. Os participantes e o placar de outras pessoas são simulados.
**Fonte:** `GymBros/Leagues/LeaguesView.swift` (`LeaguesView`, `LeagueRow`)

### RF-SOC-02 · Criar e editar liga
**Descrição:** O app deve permitir criar uma liga e editar todas as configurações de uma liga existente.
**Regras:**
- Campos: nome (obrigatório, sem espaços nas pontas), emoji (10 opções: 🏆 🔥 💪 🏃 ⚡️ 🦁 🐉 ⭐️ 🏐 🧘), capa opcional (foto reduzida a no máximo 1280 px, JPEG com qualidade 0,7), período, renovação, modo de pontuação (chips), pesos, desempate, regra de foto e times.
- Com "Vale ½" no modo Treinos, o rodapé avisa que a metade arredonda para cima e que, para cobrar a foto, é preciso usar "Obrigatória".
- Valores padrão: começa hoje, termina em 30 dias (hoje + 29), com data de fim, sem renovação, modo Pontos, pesos 1×, desempate "Chegou antes", foto "Opcional", sem times.
- O código da liga tem 6 caracteres sorteados entre `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (sem I, O, 0 e 1).
- Só na criação: escolha do representante (RF-SOC-12) e a chave "Participantes de exemplo", que marca a liga como `isMock`.
- Na edição, todas as regras são aplicadas de forma retroativa a todos os check-ins, porque o placar é recalculado.
**Critérios de aceitação:**
- O botão "Criar" ou "Salvar" fica desabilitado enquanto o nome estiver vazio.
- Uma liga criada com "Participantes de exemplo" ligada mostra os 8 participantes simulados (RF-SOC-04).
**Situação:** Local. Sem servidor, ninguém mais consegue entrar numa liga criada pelo usuário: o próprio formulário avisa que "os convites não chegam em outras pessoas".
**Fonte:** `GymBros/Leagues/LeaguesView.swift` (`CreateLeagueView`), `GymBros/Models/League.swift` (`League.newCode`)

### RF-SOC-03 · Entrar numa liga por código e convidar
**Descrição:** O app deve permitir entrar numa liga digitando o código e compartilhar o convite de uma liga.
**Regras:**
- O código é convertido para maiúsculas e sem espaços nas pontas. O botão "Entrar" é liberado com 6 caracteres (o tamanho do código).
- Código de uma liga em que o usuário já está: mostra "Você já está nessa liga.".
- Código `AMIGOS`: cria a liga de exemplo (RF-SOC-04).
- Qualquer outro código: mostra "Procurando…" e pergunta ao backend (`LeagueRemoteStore.join`). Achando, a liga entra na lista com as regras do dono, o bro representante escolhido e a sua inscrição na caixa de saída (`joined = true`, você não cria a liga no servidor). Sem achar: no modo simulado, "Liga não encontrada. Sem servidor, só a liga de exemplo (AMIGOS) existe."; no CloudKit, "Liga não encontrada. Confira o código.". Erro de rede mostra "Não deu para procurar agora: {erro}".
- O botão de convite no detalhe da liga compartilha o texto "Entra na minha liga {emoji} {nome} no GymBros! Código: {código}".
- Uma liga criada com "Participantes de exemplo" (exceto a `AMIGOS`) não oferece convite: o botão explica "Os participantes desta liga são simulados e o código dela só existe neste iPhone…", e a capa mostra "participantes simulados" no lugar do código.
**Critérios de aceitação:**
- Digitar `amigos` cria a "Liga dos Bros".
- Digitar o código de uma liga criada pelo próprio usuário retorna "Você já está nessa liga.".
- Com 5 caracteres, "Entrar" fica desabilitado.
**Situação:** Depende de servidor. No modo simulado (atual), só o código `AMIGOS` funciona; no CloudKit, qualquer liga publicada pode ser encontrada pelo código.
**Fonte:** `GymBros/Leagues/LeaguesView.swift` (`JoinLeagueView`, `inviteText`, `canInvite`), `GymBros/Leagues/LeagueRemote.swift` (`LeagueBackend.join`, `LeagueRemoteStore.join`)

### RF-SOC-04 · Liga de exemplo "Liga dos Bros"
**Descrição:** O app deve oferecer uma liga simulada para o usuário experimentar ranking, times, feed e mural.
**Regras:**
- Nome "Liga dos Bros", emoji 🔥, modo Pontos, começa 12 dias antes da entrada, dura 30 dias e tem os times "Time Verde" e "Time Roxo".
- Tem 8 participantes simulados: Ana, Bruno, Carla, Diego, Fê, Gui, Lia e Rafa. Cada um tem atividades típicas, uma frequência diária entre 0,45 e 0,8, uma faixa de minutos e títulos próprios.
- Os check-ins simulados são determinísticos (sementes por liga, pessoa e dia): horário entre 6h e 21h, duração arredondada para múltiplos de 5, esforço de 5 a 8, distância estimada pelo ritmo típico ±15% (corrida 6, caminhada 11, bike 2,5 e natação 25 min/km) e 75% de chance de ter foto. A foto em si não existe; o app mostra um marcador no lugar dela.
- Os participantes são distribuídos entre os times em rodízio, começando por um time sorteado.
- Esses check-ins não trazem calorias, então no modo Calorias o valor é estimado com peso de referência de 70 kg.
**Critérios de aceitação:**
- Reabrir o app no mesmo dia gera exatamente os mesmos check-ins e recados.
- Não aparece nenhum check-in simulado com horário no futuro nem depois do fim da liga.
**Situação:** Simulado.
**Fonte:** `GymBros/Leagues/Leagues.swift` (`FakeMember`, `MockLeague`), `GymBros/Leagues/LeagueRemote.swift` (`MockLeagueBackend.build`), `GymBros/Leagues/LeaguesView.swift` (`MockLeague.make`)

### RF-SOC-05 · Período, temporadas e renovação automática
**Descrição:** O app deve controlar o início e o fim da liga e, quando configurado, abrir uma nova temporada ao fim do período.
**Regras:**
- O início vale do começo do dia e o fim vale até 23:59:59 do último dia. Sem data de fim, a liga é contínua (∞). Na criação, o início não pode ser anterior a hoje; na edição, o limite é o início que a liga já tinha.
- Contagem: "Começa amanhã" ou "Começa em N dias" antes do início; "Faltam N dias" contando o dia de hoje (o número fica destacado quando é 3 ou menos); "Termina hoje" no último dia; "Fim 🏁" depois do fim.
- Check-ins fora do período não contam. Numa liga encerrada, o botão "+", o campo do mural e a troca de time ficam ocultos.
- A renovação automática só existe para ligas com data de fim. Quando a liga termina, é criada a temporada seguinte com a mesma duração, nome, emoji, código, capa, representante, pesos, desempate, regra de foto, times e time do usuário. O placar começa do zero.
- Se o app ficou fechado durante mais de uma temporada, o app pula direto para a temporada em andamento, e o número da temporada avança conforme as temporadas puladas.
- A renovação roda ao abrir a aba Ligas e sempre que o app volta para o primeiro plano.
- As temporadas anteriores aparecem no ranking da temporada atual em "Temporadas anteriores", com T{n}, o campeão (🏆 nome · placar com unidade, ex.: "120 pts", "12,4 km"), o período e a posição do usuário.
- Uma liga que ainda não começou não aceita check-in: o botão "+" fica oculto e ela não aparece em "Postar em" (RF-SOC-10).
**Critérios de aceitação:**
- Uma liga de 7 dias com renovação, aberta 20 dias depois do fim, vira a temporada em andamento com o número correto, e as temporadas intermediárias não são criadas.
- Sair da liga apaga todas as temporadas da série (RF-SOC-07).
**Situação:** Local.
**Fonte:** `GymBros/Models/League.swift` (`setPeriod`, `daysLeft`), `GymBros/Leagues/Leagues.swift` (`LeagueRenewal`), `GymBros/Leagues/LeaguesView.swift` (`stats`, `pastSeasons`), `GymBros/App/App.swift`

### RF-SOC-06 · Modos de pontuação, pesos e regra de foto
**Descrição:** O app deve calcular o valor de cada check-in conforme o modo da liga.
**Regras:**
- **Pontos:** o XP da atividade (duração limitada a 240 min × MET × esforço). Com pesos, o XP é multiplicado por Σ(peso do atributo na atividade × peso da liga). Os pesos vão de 0× a 3×, em passos de 0,5 (0× tira o atributo da conta). O rodapé do formulário mostra quanto vale 1 h com esforço 6 de corrida, musculação e yoga.
- **Treinos:** cada check-in vale 1.
- **Minutos:** a duração, limitada a 240.
- **Distância:** os metros da atividade (GPS do app ou Apple Saúde), exibidos em km com 1 casa decimal abaixo de 10 km e sem casas a partir disso. Uma atividade sem distância vale 0.
- **Calorias:** as calorias ativas do Saúde ou, na falta delas, uma estimativa: (MET × (0,6 + 0,08 × esforço) − 1) × 3,5 × 70 / 200 × minutos.
- **Foto:** "Opcional" (sem efeito), "Vale ½" (sem foto, o valor é dividido por 2 com arredondamento para cima, para nunca zerar: no modo Treinos, 1 continua 1) ou "Obrigatória" (sem foto, o valor é 0).
- "Tem foto" é a imagem guardada ou a marca `hadPhoto` (check-in postado com foto). Um backup restaurado volta sem a imagem, mas com a marca, então a pontuação não muda; tirar a foto na edição só apaga a marca se havia imagem para tirar.
- O placar aparece sempre com unidade: "pts", "treino(s)", duração, "km" e "kcal" (`LeagueScoring.format`; nas colunas, `short`).
- O rodapé do ranking explica o modo, a regra de foto (quando não é Opcional), os pesos diferentes de 1× e o desempate.
**Critérios de aceitação:**
- Na regra "Obrigatória", um check-in sem foto aparece no feed como "+0".
- Na regra "Vale ½", um check-in sem foto no modo Treinos vale 1.
- Uma corrida registrada manualmente, sem GPS nem Saúde, vale 0 no modo Distância.
- Restaurar um backup não muda o placar de ligas com foto obrigatória.
**Situação:** Local.
**Fonte:** `GymBros/Leagues/Leagues.swift` (`LeagueScoring`, `PhotoRule`), `GymBros/Models/League.swift` (`League.score`, `LeagueCheckIn.hasPhoto`, `setPhoto`), `GymBros/Services/HealthSync.swift` (`activeKcal`), `LeagueTests.swift` (`testHalfPhotoNeverZeroesAScore`, `testRestoredCheckInKeepsPhotoScore`)

### RF-SOC-07 · Detalhe da liga, ranking, janelas e desempate
**Descrição:** O app deve mostrar a liga com capa, um resumo e as abas Check-ins, Ranking e Mural.
**Regras:**
- A capa mostra a foto (ou um degradê com o emoji), os selos "exemplo", "temporada N" e "encerrada", o período e o código.
- O resumo mostra o líder (ou "Campeão", se a liga acabou; "ninguém pontuou" quando o placar é 0), a posição do usuário com a diferença para o líder ("−N") e a contagem de dias. Tocar no resumo abre o Ranking. O resumo usa sempre a janela "Liga toda".
- O ranking tem três janelas: "Liga toda", "Esta semana" (semana do calendário atual) e "Este mês". Todos os participantes aparecem, mesmo com placar zero.
- Desempate: "Chegou antes" (horário do último check-in que pontuou; quem não pontuou fica atrás), "Sequência" (mais dias seguidos com check-in na janela) ou "Check-ins" (mais check-ins). Persistindo o empate, o usuário fica na frente e, depois dele, vale a ordem alfabética.
- As linhas empatadas com placar maior que 0 mostram o motivo: "empate · chegou {data e hora}", "empate · N dias seguidos" ou "empate".
- O pódio usa 🥇 🥈 🥉; a partir daí, "Nº".
- A aba Check-ins agrupa por dia ("Hoje", "Ontem", dia por extenso), mostra no máximo 120 check-ins, e cada item traz miniatura (check-in de outra pessoa com foto mostra um marcador com câmera), título, autor, duração, lugar (📍), hora e "+valor" com unidade. O ranking também mostra o placar com unidade.
- Menu "⋯": "Editar liga" e "Sair da liga". Sair pede confirmação e apaga todas as temporadas da série com os check-ins, os comentários desses check-ins e os recados; as atividades e os bros continuam.
**Critérios de aceitação:**
- Com o desempate "Check-ins" e dois participantes com o mesmo placar, quem tem mais check-ins fica acima e a linha mostra "empate".
- Ao trocar para "Esta semana", só entram check-ins feitos desde o início da semana atual.
**Situação:** Local. Os participantes e check-ins de outras pessoas são simulados.
**Fonte:** `GymBros/Leagues/LeaguesView.swift` (`LeagueDetailView`), `GymBros/Leagues/Leagues.swift` (`LeagueBoard.ranking`, `RankWindow`, `LeagueTieBreak`)

### RF-SOC-08 · Times e bro do time
**Descrição:** O app deve permitir competir em times, cada um com placar e bro próprios.
**Regras:**
- A liga tem de 2 a 4 times. Ao ligar a opção, são criados "Time Verde" e "Time Roxo"; novos times recebem o nome "Time N". Só dá para remover times quando há mais de 2. Nomes vazios são descartados (quem estava no time fica sem time).
- Cada time tem id estável, gerado na criação (`teamsRaw` com uma linha "id⇥nome" por time). Renomear, reordenar ou remover outro time não troca ninguém de time; se o time do usuário é removido, ele fica sem time. Ligas antigas, só com nomes, mantêm os ids por posição (`t0`, `t1`…), e a liga de exemplo usa `t0`/`t1`.
- O usuário escolhe o time tocando nele no Ranking e confirmando "Entrar no {time}?". Dá para trocar depois. Numa liga encerrada não é possível trocar. O rodapé do formulário diz isso: "Cada pessoa escolhe o time no Ranking da liga e pode trocar depois. Renomear um time não tira ninguém dele."
- O placar do time é a soma do placar dos membros na janela selecionada.
- O bro do time cresce com a média de XP dos membros (calculada só com os check-ins da liga, dentro do período) e evolui pelo atributo que o time mais treina. Exibe o estágio e "N pessoas".
- Ordenação: pelo placar; no empate, o time do usuário fica na frente.
**Critérios de aceitação:**
- Ao entrar num time, ele recebe o selo "seu time" e o placar dele passa a incluir os check-ins do usuário.
- Um time sem check-ins mostra o bro em forma de ovo.
- Renomear o time do usuário mantém o selo "seu time".
**Situação:** Local. A divisão dos outros participantes entre os times é simulada.
**Fonte:** `GymBros/Leagues/Leagues.swift` (`LeagueTeam`, `LeagueTeams`, `LeagueBoard.teams`, `teamBro`), `GymBros/Models/League.swift` (`League.teams`), `GymBros/Leagues/LeaguesView.swift` (`teamsSection`), `LeagueTests.swift` (`testTeamIDsAreStable`, `testLegacyTeamsKeepPositionalIDs`)

### RF-SOC-09 · Mural da liga
**Descrição:** O app deve oferecer um mural de recados por liga, com o bro de cada autor.
**Regras:**
- O texto não pode ficar vazio depois de remover espaços e quebras de linha. O recado é salvo no aparelho (`LeagueMessage`) e enviado logo em seguida (`flush`).
- Enquanto `syncedAt` estiver vazio, o recado mostra um ícone de relógio (caixa de saída). O backend simulado aceita tudo na hora.
- Os recados são agrupados por dia, até 150 no total. Os do usuário ficam à direita, em destaque.
- Tocar e segurar um recado próprio permite "Apagar recado". A remoção só acontece no aparelho (o contrato não apaga recados no servidor).
- Recados simulados: por pessoa e por dia, 30% de chance de existir, entre 7h e 22h. Quando a pessoa tem time, 35% de chance de ser uma frase de torcida ("Vamos, {time}! 🔥").
- Numa liga encerrada, o campo de escrita fica oculto.
**Critérios de aceitação:**
- Um recado enviado aparece no topo do dia "Hoje" e perde o relógio depois que o envio é aceito.
**Situação:** Depende de servidor. No modo simulado (atual) o envio é aceito na hora e os recados dos outros são simulados; no CloudKit, o recado vira um registro `Message` da liga.
**Fonte:** `GymBros/Leagues/LeagueMural.swift`, `GymBros/Models/League.swift` (`LeagueMessage`), `GymBros/Leagues/LeagueRemote.swift` (`flush`, `MockLeagueBackend.messages`)

### RF-SOC-10 · Check-in em várias ligas e no perfil
**Descrição:** O app deve permitir publicar a mesma atividade, com título, descrição e foto, no perfil e em várias ligas de uma vez.
**Regras:**
- A seção "Postar em" lista "Meu perfil" e as ligas em andamento (já começaram e não acabaram), além das encerradas ou futuras em que a atividade já foi postada (para permitir tirar). Ligas que ainda não começaram não aparecem.
- Ao registrar uma atividade, concluir um treino guiado, um WOD ou uma rota GPS, todos os destinos começam marcados: o perfil e as ligas já iniciadas e não encerradas. No botão "+" da liga, só ela começa marcada. Na edição, o que vale é o que já estava postado.
- "Marcar todos" e "Desmarcar" alternam o conjunto completo. Sem destino, a atividade fica só no histórico.
- Se não houver foto e algum destino cobrar foto, aparece o aviso "📷 Sem foto, o check-in não pontua em X e vale metade em Y.".
- O formulário da liga tem "Nova atividade" (tipo, duração de 5 a 240 min em passos de 5, esforço e data) ou "Já registrada" (atividades dos últimos 7 dias, inclusive do Saúde, com a marca "já postada"). O botão "Postar" exige ao menos um destino.
- A mesma atividade nunca é postada duas vezes na mesma liga. Sem título, o post usa o nome da atividade. O lugar é o do treino ou, na falta dele, o lugar salvo em que o usuário está no momento.
- Ao editar uma atividade, os destinos ficam exatamente como foram escolhidos (os check-ins são criados ou removidos), e o mesmo título, descrição, foto, lugar e data valem para todos.
**Critérios de aceitação:**
- Postar uma atividade em 2 ligas e no perfil cria 3 check-ins com o mesmo título e a mesma foto.
- Desmarcar uma liga na edição remove o check-in só daquela liga.
- Caixa de saída: todo check-in novo ou editado fica com `syncedAt` vazio e é publicado no próximo envio (`LeagueRemoteStore.flush`, ao abrir o app e 2 s depois de cada mudança; posts do perfil vão como liga `profile`). Check-ins já publicados e depois apagados ou desmarcados vão para `LeagueOutbox` e são retirados do servidor (`retract`). Sair de uma liga leva junto, no servidor, os check-ins dela. Sem rede, nada se perde: fica pendente e tenta de novo.
**Situação:** Depende de servidor. O fluxo é local; o envio usa `LeagueBackend.publish` e `retract`, aceitos na hora no modo simulado (atual) e gravados como registros `CheckIn` no CloudKit (a foto como `CKAsset`). As telas ainda mostram o quadro colorido no lugar da foto de outras pessoas.
**Fonte:** `GymBros/Leagues/LeaguesView.swift` (`LeaguePostSection`, `CheckInForm`, `postCheckIns`, `syncCheckIns`), `GymBros/Leagues/LeagueRemote.swift` (`flush`, `scheduleFlush`, `LeagueOutbox`), `GymBros/Activities/LogActivityView.swift`, `GymBros/Services/Route.swift`, `GymBros/Train/Wod.swift`, `GymBros/Train/WorkoutView.swift`

### RF-SOC-11 · Detalhe do check-in, comentários e reações
**Descrição:** O app deve abrir um check-in em tela cheia, com comentários e reações.
**Regras:**
- Mostra a foto em destaque com fundo desfocado ou, sem foto, o bro e o tipo. Também mostra autor, quando ("Hoje, 07:30", "Ontem, …"), lugar, título, descrição e os chips de duração, tipo, "+valor" e lugar.
- O chip de valor mostra a unidade da liga ("+5,2 km", "+1 h 30 min"); post do perfil mostra "XP".
- Comentários: texto não vazio, de até 4 linhas no campo de escrita. As reações rápidas são 💪 🔥 👏 😮‍💨 🏆 ❤️ e ficam salvas como comentários. Um comentário de até 3 caracteres feito só de emoji aparece em tamanho grande.
- Cada comentário guarda o autor (`authorID`: "me" ou o `memberID` de outra pessoa, e `authorName`). Os seus aparecem com sua foto e seu nome atual; os de outras pessoas, com a inicial e o nome guardado. Comentários antigos, sem autor, contam como seus. Tocar e segurar só permite apagar os seus.
- Menu: "Compartilhar" (foto e o texto "{título} · {tipo}, {duração} no GymBros 💪") está sempre disponível. Nos check-ins do próprio usuário também há "Editar" (abre a edição da atividade com os destinos) e "Apagar check-in" (tira o check-in desta liga e apaga os comentários dele, mas a atividade continua).
**Critérios de aceitação:**
- Um comentário enviado aparece na lista com o nome do usuário e a data relativa.
- Tocar e segurar um comentário de outra pessoa não abre o menu de apagar.
**Situação:** Local. Os comentários e reações ficam só no aparelho, inclusive nos check-ins de participantes simulados; a troca entre pessoas depende de servidor (o modelo já guarda o autor).
**Fonte:** `GymBros/Models/League.swift` (`CheckInComment`), `GymBros/Leagues/CheckInDetail.swift` (`CheckInDetailView`)

### RF-SOC-12 · Representante (bro) por liga
**Descrição:** O app deve permitir escolher qual bro representa o usuário em cada liga.
**Regras:**
- Ao criar ou entrar numa liga, a escolha é entre um bro da coleção (o padrão é o bro principal) ou "Adotar um ovo novo", que cria um monstro novo.
- Os check-ins da liga dão XP só ao representante dela. Uma atividade postada em várias ligas dá XP a cada representante. Uma atividade fora das ligas (ou postada só no perfil) vai para o bro gravado nela ou, na falta dele, para o inicial.
- Dentro da liga, o usuário aparece com o representante, e o cartão "Te representa nesta liga" mostra o nível ou o XP que falta para chocar.
- Uma liga sem representante válido (versão antiga ou monstro apagado) passa a usar o bro inicial.
**Critérios de aceitação:**
- Postar uma atividade numa liga representada por um ovo novo faz o ovo ganhar XP, e o bro principal não recebe aquele XP.
**Situação:** Local.
**Fonte:** `GymBros/Bros/Monsters.swift` (`Roster`, `MonsterChoiceSection`, `representative`, `ensureStarter`)

---

## 2. Amigos e perfil

### RF-SOC-13 · Código de amigo e adicionar amigo
**Descrição:** O app deve dar ao usuário um código de amigo e permitir adicionar pessoas por código.
**Regras:**
- O código pessoal tem 6 caracteres, no mesmo alfabeto das ligas, é gerado uma única vez e pode ser compartilhado com o texto "Me adiciona no GymBros! Meu código de amigo: {código}".
- O botão "Adicionar" é liberado com 6 caracteres. O código vai para maiúsculas e perde os espaços.
- Erros: "Esse é o seu código 🙂", "Vocês já são amigos." e "Ninguém com esse código.". Quando dá certo, mostra "{nome} agora é seu amigo 🎉".
- No backend simulado, a pessoa vira amiga na hora, sem pedido pendente. Os códigos simulados são o id em maiúsculas seguido de "2026", cortado em 6 caracteres (ex.: `ANA202`, `BRUNO2`); a Mari usa `MARI42`.
**Critérios de aceitação:**
- Digitar `MARI42` adiciona a Mari e remove o pedido dela da lista.
**Situação:** Depende de servidor. No modo simulado (atual), o diretório só tem as pessoas simuladas; no CloudKit, o código é procurado nos registros `Profile` (`friendCode`) e a amizade é um `FriendLink` em cada direção (pedir cria o seu, aceitar cria o de volta, desfazer apaga o seu).
**Fonte:** `GymBros/Friends/Friends.swift` (`FriendsStore`, `MockFriendsBackend`, `FriendsView`)

### RF-SOC-14 · Pedidos, lista de amigos e sugestões
**Descrição:** O app deve mostrar os pedidos recebidos, os amigos e as sugestões vindas das ligas.
**Regras:**
- Estado inicial simulado: 5 amigos (Bruno, Ana, Diego, Fê e Carla) e um pedido da Mari. O estado fica guardado no aparelho (`mockFriends`). Com outro backend, o estado inicial começa vazio.
- Cada pessoa simulada tem o mesmo bro em todo lugar (liga, mapa, amigos): a forma vem de `FakeMember`.
- Os pedidos podem ser aceitos (✓) ou recusados (✕).
- A lista "Seus amigos · N" mostra o bro, o status ("{atividade} agora · {lugar}", a última vez visto ou o nome da forma) e o indicador online.
- "Talvez você conheça" mostra quem está nas ligas em andamento do usuário e ainda não é amigo nem mandou pedido, ordenando primeiro quem divide mais ligas. O subtítulo traz a liga ou "N ligas em comum". Na liga de exemplo, as sugestões são Gui, Lia e Rafa.
- Desfazer amizade (no perfil do amigo) pede confirmação ("Vocês continuam nas mesmas ligas.") e tira a pessoa do mapa ao vivo.
**Critérios de aceitação:**
- Sem ligas, a seção de sugestões mostra "Entre numa liga para ver aqui quem treina com você.".
- Adicionar uma sugestão faz a pessoa sair das sugestões e entrar na lista de amigos.
**Situação:** Simulado no modo atual. Com `Backend.mode = .cloudKit`, pedidos, amigos e sugestões vêm do `CloudKitFriendsBackend`.
**Fonte:** `GymBros/Friends/Friends.swift` (`FriendsStore.initialState`, `MockFriendsBackend`), `GymBros/Friends/FriendsLive.swift`, `LeagueTests.swift` (`testSimulatedPeopleHaveSameBroEverywhere`)

### RF-SOC-15 · Perfil do amigo
**Descrição:** O app deve abrir o perfil público de um amigo.
**Regras:**
- Mostra a inicial do nome, nome, @usuário, bio, indicador online e "{atividade} agora · {lugar}" quando a pessoa está treinando.
- Mostra o card público (bro, números e conquistas) com apenas as partes que a pessoa deixou visíveis, as ligas do usuário em que a pessoa também está (com link) e "Posts · N" num calendário.
- Dados simulados: o nível é sorteado de forma determinística; de 20 a 179 check-ins; dias ativos entre 70% e 95% dos check-ins; de 1 a 4 ligas; cada conquista tem 55% de chance de aparecer. A Fê esconde os números e a Carla esconde as conquistas. Os posts cobrem os últimos 90 dias, com 30% de chance por dia e 80% marcados com foto (sem imagem real).
**Critérios de aceitação:**
- O perfil da Fê não mostra a linha de números.
- Tocar num dia com posts abre a lista dos posts daquele dia, e cada post abre o detalhe (RF-SOC-11).
**Situação:** Simulado no modo atual. No CloudKit, o perfil vem do registro `Profile` do amigo (`FriendsBackend.profile`), só com as partes que ele deixou visíveis.
**Fonte:** `GymBros/Friends/PublicProfile.swift` (`FriendProfileView`), `GymBros/Friends/Friends.swift` (`MockFriendsBackend.profile`, `posts`)

### RF-SOC-16 · Perfil próprio: público e privado
**Descrição:** O app deve separar o que os amigos veem (aba Público) dos dados pessoais (aba Privado).
**Regras:**
- A tela é um `GMScreen` com X para fechar e engrenagem de Ajustes; o botão flutuante registra atividade. O cabeçalho mostra a foto (recortada em quadrado de 512 px, JPEG com qualidade 0,8; tocar troca a foto), o nome ("Treinador" quando vazio), o @usuário, a bio e o botão "Editar perfil".
- **Público:** "É assim que seus amigos te veem": o card com o bro principal, os números e as conquistas desbloqueadas (no máximo 6 chips, com o total no título), mais o calendário dos posts do perfil.
- Números públicos: "Check-ins" conta só atividades postadas (no perfil ou em alguma liga); "Dias ativos", só os dias dessas atividades; "Ligas", só as ligas atuais (temporadas passadas da mesma liga não contam de novo).
- **Privado:** atividades (todas), dias ativos, duração total, Recordes, Estatísticas, Metas, o calendário de todas as atividades (com a foto do check-in quando existe), "Ver todas as atividades" e "Peso".
- "Editar perfil" (modal): nome, @usuário (convertido para minúsculas, aceitando só letras, números, "_" e ".") e bio. As chaves de visibilidade são "Bro principal", "Números (check-ins, dias, ligas)" e "Conquistas", todas ligadas por padrão.
- Sempre visíveis: foto, nome, @usuário, bio e posts do perfil. Sempre privados: peso, medidas, recordes, metas, notas e atividades não postadas.
**Critérios de aceitação:**
- Desligar "Conquistas" tira as conquistas da prévia pública.
- Uma atividade não postada aumenta "Atividades" no Privado, mas não "Check-ins" no Público.
- Sem posts, aparece a dica: marcar "Meu perfil" em "Postar em".
- Ao abrir o app, o perfil público é montado (`PublicProfile.mine`, respeitando as chaves de visibilidade) e publicado com o código de amigo (`FriendsStore.publish`) só se mudou desde o último envio: a comparação usa um hash SHA-256 guardado por modo de backend, então trocar de simulado para CloudKit publica de novo.
**Situação:** Depende de servidor. A prévia é local; a publicação usa `FriendsBackend.publish`, que não faz nada no modo simulado (atual) e grava o registro `Profile` no CloudKit. A foto do perfil não sobe.
**Fonte:** `GymBros/Profile/ProfileView.swift` (`ProfileView`, `publicStats`, `EditProfileView`, `avatarPhoto`), `GymBros/Friends/PublicProfile.swift` (`PublicProfileCard`, `PublicProfile.stats`, `PublicProfile.mine`), `GymBros/Friends/Friends.swift` (`FriendsStore.publish`), `GymBros/App/App.swift`

### RF-SOC-17 · Calendário de posts e atividades
**Descrição:** O app deve exibir atividades e posts num calendário mensal.
**Regras:**
- A semana começa no domingo (Dom a Sáb), com a mesma grade do calendário de datas (`GMMonth`). As setas navegam entre os meses, mas não passam do mês atual.
- Um dia com foto mostra a foto em círculo e, havendo outra, uma segunda foto menor. Um dia sem foto mostra o ícone do tipo e, quando há mais de um item, um contador. Hoje fica destacado.
- Tocar num dia com itens abre a lista daquele dia. Um dia vazio não reage.
- O mesmo componente atende o histórico privado, os posts do próprio perfil e os posts de um amigo.
**Critérios de aceitação:**
- No mês atual, a seta para frente fica apagada e não muda de mês.
**Situação:** Local. Nos amigos, os posts são simulados.
**Fonte:** `GymBros/Profile/ProfileCalendar.swift` (`ActivityCalendar`, `PostsCalendar`), `GymBros/DesignSystem/GMCalendar.swift` (`GMMonth`)

### RF-SOC-18 · Indicador online
**Descrição:** O app deve sinalizar quais amigos estão treinando agora.
**Regras:**
- Uma bolinha verde pulsante aparece ao lado do nome na lista de amigos, no perfil do amigo e no pino do mapa, sempre que o amigo tem um treino ao vivo em andamento.
- Na simulação, Bruno, Ana, Diego e Fê estão ao vivo (começaram 38, 24, 51 e 17 min antes da abertura do app); a Carla aparece como "Yoga há 3 h".
**Critérios de aceitação:**
- A Carla não mostra a bolinha; Bruno mostra "Musculação agora · Smart Fit".
**Situação:** Simulado. O estado online real depende de servidor.
**Fonte:** `GymBros/Friends/FriendsLive.swift`, `GymBros/Friends/Friends.swift` (`isLive`, `status`), `GymBros/DesignSystem/GMIndicators.swift` (`GMOnlineDot`)

---

## 3. Mapa e localização

### RF-SOC-19 · Lugares de treino
**Descrição:** O app deve permitir cadastrar, editar e apagar lugares de treino no mapa.
**Regras:**
- O lugar é marcado tocando no mapa ou com "Estou aqui". O raio pode ser de 50, 100 (padrão), 150 ou 250 m. Sem nome, o lugar se chama "Academia".
- Sugestões de academias reais vêm do mapa da Apple (categoria fitness, num raio de 400 m, as 5 mais próximas). Se a primeira estiver a menos de 150 m e o nome estiver vazio, o nome dela é preenchido.
- Apagar pede confirmação e mantém o histórico de treinos.
- A lista "Lugares de treino" vem ordenada pelo número de treinos (o maior valor entre visitas detectadas e atividades no lugar), com a data do último treino e a distância até o usuário.
- O status sobre o mapa mostra "Você está na {lugar}" (e "Treino em andamento" ou "Bora treinar 💪"), ou o lugar mais próximo com a distância, ou "Nenhum lugar salvo". Tocar no status lê a posição de novo e enquadra o lugar mais próximo (sem lugar salvo, centraliza no usuário). O botão de mira leva à posição do usuário.
**Critérios de aceitação:**
- O botão "Salvar" fica desabilitado até um ponto ser marcado.
**Situação:** Local.
**Fonte:** `GymBros/Services/Route.swift` (`GymEditorView`), `GymBros/Friends/MapScreen.swift` (`gymSection`, `statusPill`), `GymBros/Models/Gym.swift` (`Gym`), `GymBros/Services/Location.swift` (`suggestions`)

### RF-SOC-20 · Identificar o lugar ao começar um treino
**Descrição:** O app deve identificar em que lugar o usuário está ao começar uma musculação ou um WOD.
**Regras:**
- Se houver um lugar marcado como "dentro", ele é usado. Senão, o app lê a posição e escolhe o lugar salvo cuja distância seja menor ou igual ao maior valor entre o raio e a precisão do GPS (o mais próximo, se houver mais de um).
- Sem correspondência, o app pergunta "Onde você está treinando?", oferecendo os lugares salvos a até 3 km, as academias sugeridas, a criação de um lugar novo ou "Não estou numa academia".
- Sem localização, o app orienta o usuário a conferir a permissão nos Ajustes do iPhone.
**Critérios de aceitação:**
- Dentro do raio de um lugar salvo, o treino começa associado a ele sem a pergunta.
**Situação:** Local.
**Fonte:** `GymBros/Services/Route.swift` (`PlaceDetector`, `GymChooserView`), `GymBros/Services/Location.swift` (`gym(containing:)`, `nearby`)

### RF-SOC-21 · Chegada e saída automáticas
**Descrição:** O app deve detectar a chegada e a saída de lugares salvos, mesmo em segundo plano.
**Regras:**
- O monitoramento usa `CLMonitor`, com no máximo 20 lugares (os visitados mais recentemente), e é reiniciado sempre que o app abre.
- Chegada: registra uma visita. Se "Avisar ao chegar" estiver ligado (padrão) e não houver treino em andamento, envia a notificação "Chegou na {lugar} 💪" com o texto "Começar {rotina do dia}?" e a ação "Começar treino". Ao abrir o app até 1 h depois, sem treino em andamento, o app oferece começar.
- Saída: fecha a visita aberta daquele lugar (com mais de um lugar, não mexe na de outro). Se o usuário já estava marcado em outro lugar, só fecha a visita. Senão, com "Encerrar treino ao sair" ligado (padrão), o treino em andamento daquele lugar (ou sem lugar) com pelo menos 10 min é encerrado e salvo (RF-TRE-20), com a notificação "Treino encerrado ao sair da {lugar}".
- Com lugares salvos e sem a permissão "Sempre", aparece um aviso que leva aos Ajustes.
- O mês mostra as idas à academia, o tempo médio (só visitas de 5 min ou mais) e os km ao ar livre.
**Critérios de aceitação:**
- Sair do lugar 8 min depois de começar não encerra o treino.
**Situação:** Local.
**Fonte:** `GymBros/Services/Location.swift` (`startMonitoring`, `arrived`, `left`, `NotificationRouter`), `GymBros/Friends/MapScreen.swift`, `GymBros/App/App.swift`

### RF-SOC-22 · Corrida, caminhada e bike com GPS
**Descrição:** O app deve gravar percursos com GPS e salvá-los como atividade.
**Regras:**
- Só grava pontos com precisão melhor que 30 m, com filtro de 5 m, e ignora saltos acima de 15 m/s. Continua com a tela bloqueada e mantém a tela acesa durante a gravação.
- Mostra tempo, distância (km com 2 casas) e ritmo (min/km) ou, na bike, velocidade (km/h). Com menos de 20 m percorridos, o ritmo aparece como "–". Dá para pausar e continuar; o tempo pausado não conta.
- Fechar depois de começar pede confirmação "Sair sem salvar?".
- Ao terminar: esforço, destinos de check-in (todos marcados) e foto. Salva a atividade (duração mínima de 1 min, distância em metros na própria atividade e uma nota com km e ritmo), o percurso e os check-ins com o título "{tipo} · {km}".
- No mapa: os 10 percursos mais recentes aparecem desenhados e os 20 mais recentes ficam listados, com detalhe de tempo, distância e ritmo. "Começar ao ar livre" mostra o total do mês por tipo.
**Critérios de aceitação:**
- Uma corrida salva aparece em "Percursos" e vale pela distância em ligas do modo Distância.
**Situação:** Local.
**Fonte:** `GymBros/Services/Route.swift` (`RouteTracker`, `RouteRunView`, `RouteFinishView`), `GymBros/Friends/MapScreen.swift`

### RF-SOC-23 · Amigos ao vivo no mapa
**Descrição:** O app deve mostrar no mapa os amigos que estão treinando agora.
**Regras:**
- Só aparecem as pessoas simuladas que ainda são amigas. Elas ficam em volta do lugar salvo mais próximo, do primeiro lugar salvo ou da posição do usuário.
- O pino mostra o bro, o ícone da atividade, o ponto online (`GMOnlineDot`) e "{nome} · N min". A posição se atualiza a cada 2 s, e quem corre se move pelo percurso com um rastro dos últimos ~800 m (a Ana a 3,1 m/s).
- O botão no mapa liga e desliga a camada e mostra "N ao vivo". A lista "Amigos agora" vem ordenada com quem está ao vivo primeiro.
- O card do amigo mostra "AO VIVO" com o ponto online verde, estatísticas que mudam com o tipo (tempo, distância e ritmo; séries; metros nadados; kcal; bpm), o exercício atual e os já feitos, "Mandar força 💪", "Treinar junto com {nome}" e "Ver no mapa".
- Tudo é declarado como prévia: depois de tocar, os botões viram "Força enviada (prévia)" e "Convite simulado", e o texto diz "Prévia com amigos simulados: nada foi enviado. Força e convites chegam a {nome} quando o app tiver servidor." Esse estado é só visual.
- O ajuste "Compartilhar treino ao vivo" (desligado por padrão) diz "Ainda não envia nada: chega quando o app tiver servidor".
**Critérios de aceitação:**
- Desfazer a amizade com o Bruno tira o Bruno do mapa e da lista.
**Situação:** Simulado. "Mandar força", "Treinar junto" e "Compartilhar treino ao vivo" não enviam nada; dependem de servidor.
**Fonte:** `GymBros/Friends/FriendsLive.swift`, `GymBros/Friends/MapScreen.swift` (`friendsSection`, `friendsBase`, `settingsSheet`)

---

## 4. Apple Saúde, backup e ajustes

### RF-SOC-24 · Importar treinos do Apple Saúde
**Descrição:** O app deve importar os treinos do iPhone e do Apple Watch como atividades.
**Regras:**
- É ligado em Ajustes e pede leitura de treinos e de peso. A importação roda ao ligar, em "Sincronizar agora" e sempre que o app volta para o primeiro plano.
- Janela: na primeira vez, os últimos 14 dias; depois, a partir de 2 dias antes da última sincronização.
- Ficam de fora os treinos com menos de 5 min, os já importados, os gravados pelo próprio GymBros e os apagados pelo usuário (lista de ignorados).
- Quando um treino coincide em mais da metade do mais curto com algo já registrado, ele é contado como "já registrado aqui" e não é importado.
- O tipo do treino é mapeado para a atividade (ex.: HIIT vira CrossFit; pilates vira Yoga; basquete vira Futebol). O esforço vai de 1 a 10, igual a 5 × calorias ativas ÷ calorias ativas esperadas (5 quando não há dado). A atividade guarda as calorias ativas (`kcal`), a distância (`meters`: a maior entre caminhada/corrida, bike e natação, quando houver), a fonte e a nota "N kcal".
- Mostra o aviso "N treinos do Saúde · +X XP", com o XP pela regra do histórico (os bros que recebem, RF-JOG-18), e um status com o total de importados e de repetidos.
- Atividades importadas não são postadas automaticamente em ligas.
**Critérios de aceitação:**
- Um treino do Watch que se sobrepõe a um treino guiado já salvo não é duplicado.
- Um treino importado e depois apagado não volta na sincronização seguinte.
**Situação:** Local (somente leitura do Saúde).
**Fonte:** `GymBros/Services/HealthSync.swift` (`sync`, `effort`, `kind(for:)`), `GymBros/App/SettingsView.swift`, `GymBros/App/App.swift` (`syncHealth`), `GymBros/Activities/ActivityDetail.swift`

### RF-SOC-25 · Gravar treinos no Apple Saúde
**Descrição:** O app deve, quando configurado, gravar no Saúde as atividades registradas no app.
**Regras:**
- Só grava o que foi registrado a partir de 1 h antes de ligar a opção, já terminado (com tolerância de 2 min) e que não veio do Saúde.
- As calorias são estimadas pela fórmula do RF-SOC-06, usando o peso mais recente do app, do Saúde ou 70 kg. Corrida, caminhada, bike, futebol e vôlei são gravados como treino ao ar livre.
- Editar ou apagar a atividade remove o treino gravado, que é gravado de novo com os dados atualizados.
**Critérios de aceitação:**
- Desligar mostra "Não grava mais. O que já foi para o Saúde continua lá.".
**Situação:** Local.
**Fonte:** `GymBros/Services/HealthSync.swift` (`exportPending`, `write`, `deleteWritten`), `GymBros/Activities/LogActivityView.swift`

### RF-SOC-26 · Backup e restauração
**Descrição:** O app deve exportar e restaurar uma cópia completa dos dados em JSON.
**Regras:**
- Exporta para o Arquivos ou iCloud Drive com o nome `GymBros-AAAA-MM-DD.json` (versão 1, datas ISO 8601; campos novos são opcionais, então backups antigos continuam abrindo).
- Inclui: atividades (com distância e calorias), rotinas, sessões e séries, exercícios próprios, ligas com todas as configurações (pesos, desempate, regra de foto, times, seu time) e a capa reduzida (até 640 px, JPEG 0,6, só na temporada atual; ao restaurar, as passadas usam a mesma), bros, medidas, notas, check-ins (sem a imagem, mas com "tinha foto" e o lugar), percursos, visitas, lugares, WODs (com CAP), recordes, comentários (com autor), recados do mural, a foto do perfil (512 px) e os ajustes `trainerName`, `monsterNick`, `lastFormID`, `discovered`, `bodyGender`, `mainMonster`, `profileUsername`, `profileBio`, `exerciseGoals`, `autoWarmup`, `restNotification` e `barWeight`.
- Os ajustes vão também com o tipo (`typedSettings`: booleano, número ou texto) e são restaurados com ele; backups antigos só têm a versão em texto. Backup sem foto do perfil mantém a atual.
- Ficam de fora: as imagens dos check-ins e as fotos de progresso, as chaves de visibilidade do perfil, metas, o código e a lista de amigos, além das preferências de Saúde, de lugares e de lembretes.
- Visitas de backups antigos ficam no lugar de mesmo nome; sem correspondente, ficam sem lugar (contam nas idas do mês com o nome guardado). Depois de restaurar, o monitoramento dos lugares recomeça.
- Restaurar mostra a data e o número de atividades e pede confirmação ("Substituir tudo"): todos os dados atuais são apagados antes da restauração.
**Critérios de aceitação:**
- Depois de restaurar, aparece "Backup restaurado: N atividades." e um bro inicial é garantido.
- Um check-in que tinha foto continua pontuando numa liga com foto obrigatória depois de restaurar.
**Situação:** Local.
**Fonte:** `GymBros/Services/Backup.swift` (`Backup.make`, `restore`, `Setting`, `smallCover`), `GymBros/App/SettingsView.swift`

### RF-SOC-27 · Ajustes
**Descrição:** O app deve concentrar as preferências gerais.
**Regras:**
- Nome do treinador; apelido do bro principal (vazio usa o nome da forma).
- Lembrete diário (desligado por padrão, às 18:00), só nos dias sem treino, com a opção "Só em dias de rotina". Resumo da semana no domingo às 19h (ligado por padrão), com treinos, tempo, PRs e posição nas ligas. Notificação no fim do descanso (desligada).
- Aquecimento automático (ligado): 3 séries a 40%, 60% e 80% da carga no primeiro exercício com carga. Não há mais o ajuste "Carga na barra": é automático pelo tipo do treino (RF-TRE-05).
- Apple Saúde (RF-SOC-24 e RF-SOC-25), Backup (RF-SOC-26) e Conta (RF-SOC-28).
- "Recomeçar jornada" pede confirmação com o mesmo texto do rodapé: apaga as atividades e tudo ligado a elas (treinos guiados concluídos, check-ins no perfil e nas ligas com seus comentários, percursos, WODs), os bros, as conquistas já vistas, a Dex descoberta e os carinhos do widget, e devolve um ovo novo, que passa a representar o usuário nas ligas, com placar zerado. Rotinas, lugares, medidas, ligas e o nome continuam; um treino em andamento continua. As próximas importações do Saúde partem do momento atual.
**Critérios de aceitação:**
- Ligar um lembrete pede a permissão de notificações.
- Depois de "Recomeçar jornada", o app continua na tela principal (sem voltar ao onboarding) com um ovo de 0 XP.
**Situação:** Local.
**Fonte:** `GymBros/App/SettingsView.swift` (`reset`, `resetText`)

---

## 5. Conta e compartilhamento

### RF-SOC-28 · Login e conta
**Descrição:** O app deve pedir login antes de qualquer outra tela e permitir sair da conta nos Ajustes.
**Regras:**
- Sem conta salva, a primeira tela é o login (antes do onboarding): bro bebê animado, "GymBros", "Seus treinos chocam e evoluem um bro." e o seletor "Entrar" / "Criar conta".
- "Criar conta" pede nome, e-mail e senha; "Entrar", e-mail e senha. O e-mail perde os espaços e vai para minúsculas. Erros: "Diga seu nome.", "E-mail inválido.", "A senha precisa de pelo menos 8 caracteres." e "Já existe uma conta com esse e-mail. Entre em vez de criar.". O botão só é liberado com e-mail e senha preenchidos.
- "Continuar com a Apple" (botão branco com o logo) é a outra opção. O rodapé avisa: "Ainda não há servidor: o login é simulado e tudo continua só neste iPhone.".
- Login simulado (`MockAuthBackend`): qualquer senha válida entra, porque não há como conferi-la; as contas criadas guardam só e-mail e nome no aparelho (a senha nunca é guardada). A Apple simulada devolve um e-mail de retransmissão (`…@privaterelay.appleid.com`).
- A sessão (`AuthUser`: id, nome, e-mail, provedor e token) fica no aparelho. O nome da conta vira o nome de treinador se ainda não houver um; com nome de treinador, o app pula o onboarding e abre direto a tela principal.
- Ajustes, seção "Conta": nome (ou "Sua conta"), e-mail, ícone do provedor e "Sair da conta", que pede confirmação ("Seus treinos e bros continuam neste iPhone.") e volta para o login sem apagar nada.
- No modo CloudKit, a conta é a do iCloud do aparelho; entrar por e-mail responde "Por enquanto, entre com a Apple (usa a sua conta do iCloud)." e exigiria servidor próprio.
**Critérios de aceitação:**
- Senha de 7 caracteres mostra "A senha precisa de pelo menos 8 caracteres.".
- Criar conta duas vezes com o mesmo e-mail mostra o erro de e-mail em uso.
- Sair da conta e entrar de novo mantém atividades, bros e ligas.
**Situação:** Simulado. Sign in with Apple e iCloud exigem conta paga do Apple Developer (o Personal Team não tem).
**Fonte:** `GymBros/Services/Auth.swift` (`AuthStore`, `MockAuthBackend`, `LoginView`, `AuthError`), `GymBros/App/App.swift` (`RootView`), `GymBros/App/SettingsView.swift`, `GymBros/Services/Backend.swift`

### RF-SOC-29 · Compartilhar nos Stories
**Descrição:** O app deve gerar uma arte 9:16 de qualquer atividade, com escolha de moldura e de foto, e abrir o compartilhar do iPhone.
**Regras:**
- Pontos de entrada: no detalhe de uma atividade com treino guiado, "Compartilhar nos Stories" e "Stories com outra foto"; no detalhe de qualquer outra atividade (corrida, caminhada, bike, esportes, importadas do Saúde), a mesma seção "Compartilhar", com o subtítulo "Arte com distância, pace e o trajeto" quando há percurso GPS ou "Arte com a atividade e as calorias" quando não há; e o botão de compartilhar no detalhe de uma sessão de treino guiado (`SessionDetailView`). A foto inicial é a do check-in da atividade, se houver.
- Antes do compartilhar, a tela "Story" mostra a prévia em 9:16, o botão de adicionar ou trocar foto e as molduras em miniatura: **Completo** (foto inteira com tudo por cima), **Mínimo**, **Polaroid** (foto inclinada com moldura branca) e **Bro** (o bro grande no centro). A moldura escolhida fica salva (`storyFrame`). "Compartilhar" renderiza a arte em 1080 × 1920 (360 × 640 em escala 3).
- Números (só entra o que existe, nunca "–"):
  - Treino guiado: duração, séries feitas (sem aquecimento) e kcal; a melhor série de cada exercício e até 2 recordes.
  - Atividade com percurso de mais de 20 m: distância, pace por km (velocidade na bike) e tempo do percurso, além do trajeto desenhado.
  - Outras atividades: duração e kcal.
- Calorias: o número real do Apple Saúde quando a atividade veio de lá; senão, estimativa pelo peso mais recente (medidas ou perfil físico). Sem peso, as calorias somem. O volume em kg não aparece mais.
- Título: o do check-in; sem ele, o nome do tipo (atividades do Saúde) ou a nota. Local: o do check-in ou o lugar de treino. Sprite: o do bro principal (`sprite_baby` sem widget).
- Trajeto: as coordenadas do GPS viram uma linha na cor de destaque com brilho, ponto branco no início e ponto de destaque no fim, sem distorcer pela latitude.
**Critérios de aceitação:**
- Musculação de 60 min sem peso cadastrado não mostra kcal; com 80 kg cadastrados, mostra mais de 100 kcal.
- Corrida importada do Saúde com "312 kcal" na nota mostra 312.
- Corrida de 5 km em 25 min mostra "distância" primeiro, pace 5'00" e o trajeto.
**Situação:** Local.
**Fonte:** `GymBros/Activities/StoryShare.swift` (`StoryData`, `StoryComposerView`, `StoryFrame`, `WorkoutStoryCard`, `RouteDrawing`), `GymBros/Activities/ActivityDetail.swift`, `GymBros/Train/TrainView.swift`, `StoryTests.swift`

---

## Comportamentos ambíguos ou possíveis bugs

Os itens corrigidos desde a primeira versão (meia foto zerando o modo Treinos, backup sem foto/lugar/capa, números do perfil público, texto da escolha de time, times por posição, placar sem unidade, comentários que sobravam ao sair da liga, "Recomeçar jornada", visitas de backups antigos, saída fechando a visita errada, ligas futuras em "Postar em", convite de liga com participantes de exemplo, comentários sem autor, `CheckInEditView` sem uso, trava de 4 caracteres e textos de "Mandar força"/"Treinar junto") saíram desta lista. Continua:

1. **Diferença no modo Calorias:** os check-ins do usuário usam as calorias reais do Saúde, enquanto os participantes simulados usam sempre a estimativa com 70 kg (`MockLeague.checkIns` não gera calorias).
2. **Pontos da liga e posts do perfil sem teto diário:** o modo Pontos e o "+XP" dos posts usam o XP bruto da atividade (`Game.xp`), não o XP com os limites diários do bro (RF-JOG-03).
