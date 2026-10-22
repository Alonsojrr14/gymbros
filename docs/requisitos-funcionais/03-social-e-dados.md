# Requisitos funcionais 03: social, localização e dados

## Escopo

Este documento cobre a parte social do GymBros (ligas, rodada suíça, check-ins, mural, comentários, amigos, X1, perfil público, mensagens e caixa de entrada), a localização (lugares de treino, chegada e saída, rotas GPS e amigos ao vivo no mapa, com a música que estão ouvindo), a integração com o Apple Saúde, o backup, os ajustes, o login e o compartilhamento nos Stories. Tudo foi levantado a partir do código atual, sem inventar comportamento. Os dados do usuário são da conta: o aparelho guarda a cópia de trabalho (SwiftData e `UserDefaults`) e a cópia da conta vai para o servidor (RF-SOC-33). Tudo o que envolve servidor passa por sete contratos: `AuthBackend` (login), `AccountDataBackend` (dados da conta), `LeagueBackend` (ligas, check-ins e mural), `FriendsBackend` (amigos e perfil público), `ModerationBackend` (denúncias e bloqueios), `InboxBackend` (mensagens diretas e notificações sociais) e `DuelBackend` (X1). Um interruptor em `GymBros/Services/Backend.swift` (`Backend.mode`) escolhe quem responde: hoje é `.mock`, com implementações simuladas e determinísticas (`MockAuthBackend`, `MockAccountDataBackend`, `MockLeagueBackend`, `MockFriendsBackend`, `MockModerationBackend`, `MockInboxBackend`, `MockDuelBackend`, `FriendsLive.simulated`); em `.cloudKit`, as implementações do CloudKit já escritas (`CloudKitAuthBackend`, `CloudKitLeagueBackend`, `CloudKitFriendsBackend`, `CloudKitModerationBackend`, `CloudKitDuelBackend`) assumem (os dados da conta e as mensagens diretas ficam para um servidor próprio, `ServerAccountDataBackend` e `ServerInboxBackend`), o que exige conta paga do Apple Developer (ver `docs/cloudkit.md`). A liga de exemplo `AMIGOS` continua simulada nos dois modos. Cada requisito traz uma linha **Situação**, que pode ser:

- **Local**: funciona de verdade no aparelho (os dados entram na cópia da conta).
- **Simulado**: hoje mostra dados de exemplo gerados no próprio app.
- **Depende de servidor**: já existe o contrato ou a interface, mas só vai funcionar entre pessoas reais com `Backend.mode = .cloudKit` (ou, onde indicado, quando houver um backend que ainda não existe).

---

## 1. Ligas

### RF-SOC-01 · Lista de ligas
**Descrição:** O app deve listar as ligas em que o usuário está, com o atalho para criar, entrar por código ou experimentar a liga de exemplo.
**Regras:**
- A lista é ordenada por data de entrada (`joinedAt`) e esconde as temporadas passadas (ligas com `nextUUID`).
- Cada linha mostra o emoji, o nome, o selo "Exemplo" (quando `isMock`), o ícone de renovação, "T{n} · " quando a temporada é maior que 1, a posição ("3º de 9") e o tempo restante: "encerrada", "último dia", "faltam N dias" ou, sem data de fim, o nome do modo de pontuação. Também mostra o bro que representa o usuário na liga.
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
- Campos: nome (obrigatório, sem espaços nas pontas), emoji (10 opções: 🏆 🔥 💪 🏃 ⚡️ 🦁 🐉 ⭐️ 🏐 🧘), capa opcional (foto reduzida a no máximo 1280 px, JPEG com qualidade 0,7), período, renovação, modo de pontuação (chips), pesos, desempate, regra de foto, critério da rodada suíça (RF-SOC-37) e times.
- Com "Vale ½" no modo Treinos, o rodapé avisa que a metade arredonda para cima e que, para cobrar a foto, é preciso usar "Obrigatória".
- Valores padrão: começa hoje, termina em 30 dias (hoje + 29), com data de fim, sem renovação, modo Pontos, pesos 1×, desempate "Chegou antes", foto "Opcional", rodada suíça "Mais pontos no dia", sem times.
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
- A renovação automática só existe para ligas com data de fim. Quando a liga termina, é criada a temporada seguinte com a mesma duração, nome, emoji, código, capa, representante, pesos, desempate, regra de foto, critério suíço, times e time do usuário. O placar começa do zero.
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
- **Distância:** os metros do GPS do app, exibidos em km com 1 casa decimal abaixo de 10 km e sem casas a partir disso. Uma atividade sem distância vale 0, e a distância do Apple Saúde não conta.
- **Calorias:** as calorias da atividade que podem ser publicadas (nunca as do Saúde) ou, na falta delas, uma estimativa com o peso de referência: (MET × (0,6 + 0,08 × esforço) − 1) × 3,5 × 70 / 200 × minutos.
- Para o placar ser igual em todos os aparelhos, os seus check-ins pontuam com os mesmos dados que os outros recebem (`scoreInput`): atividade do Apple Saúde entra com esforço 5, sem distância e sem calorias (RF-SOC-24).
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
**Fonte:** `GymBros/Leagues/Leagues.swift` (`LeagueScoring`, `PhotoRule`, `isFromHealth`, `scoreInput`), `GymBros/Models/League.swift` (`League.score`, `LeagueCheckIn.hasPhoto`, `setPhoto`), `GymBros/Services/HealthSync.swift` (`activeKcal`), `LeagueTests.swift` (`testHalfPhotoNeverZeroesAScore`, `testRestoredCheckInKeepsPhotoScore`)

### RF-SOC-07 · Detalhe da liga, ranking, janelas e desempate
**Descrição:** O app deve mostrar a liga com capa, um resumo e as abas Check-ins, Ranking e Mural.
**Regras:**
- A capa mostra a foto (ou um degradê com o emoji), os selos "Exemplo", "Temporada N" e "Encerrada", o período e o código.
- O resumo mostra o líder (ou "Campeão", se a liga acabou; "ninguém pontuou" quando o placar é 0), a posição do usuário com a diferença para o líder ("−N") e a contagem de dias. Tocar no resumo abre o Ranking. O resumo usa sempre a janela "Liga toda".
- O ranking tem três janelas: "Liga toda", "Esta semana" (semana do calendário atual) e "Este mês". Todos os participantes aparecem, mesmo com placar zero.
- Desempate: "Chegou antes" (horário do último check-in que pontuou; quem não pontuou fica atrás), "Sequência" (mais dias seguidos com check-in na janela) ou "Check-ins" (mais check-ins). Persistindo o empate, o usuário fica na frente e, depois dele, vale a ordem alfabética.
- As linhas empatadas com placar maior que 0 mostram o motivo: "empate · chegou {data e hora}", "empate · N dias seguidos" ou "empate".
- O pódio usa 🥇 🥈 🥉; a partir daí, "Nº".
- O placar de cada janela soma o bônus da rodada suíça (RF-SOC-37), e a linha mostra "suíço N" depois da primeira rodada encerrada. Tocar em outra pessoa do ranking abre o perfil dela (`FriendProfileView`, RF-SOC-15), de onde dá para desafiar para um X1 (RF-SOC-38); a sua linha não reage.
- A aba Check-ins agrupa por dia ("Hoje", "Ontem", dia por extenso), mostra no máximo 120 check-ins, e cada item traz miniatura (check-in de outra pessoa com foto mostra um marcador com câmera), título, autor, duração, lugar (📍), hora e "+valor" com unidade. O ranking também mostra o placar com unidade.
- Menu "⋯": "Editar liga" e "Sair da liga". Sair pede confirmação e apaga todas as temporadas da série com os check-ins, os comentários desses check-ins e os recados; as atividades e os bros continuam.
**Critérios de aceitação:**
- Com o desempate "Check-ins" e dois participantes com o mesmo placar, quem tem mais check-ins fica acima e a linha mostra "empate".
- Ao trocar para "Esta semana", só entram check-ins feitos desde o início da semana atual.
**Situação:** Local. Os participantes e check-ins de outras pessoas são simulados.
**Fonte:** `GymBros/Leagues/LeaguesView.swift` (`LeagueDetailView`, `rankRow`, `swissNote`), `GymBros/Leagues/Leagues.swift` (`LeagueBoard.ranking`, `RankWindow`, `LeagueTieBreak`), `GymBros/Friends/PublicProfile.swift` (`FriendProfileView`)

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
- Ao entrar num time, ele recebe o selo "Seu time" e o placar dele passa a incluir os check-ins do usuário.
- Um time sem check-ins mostra o bro em forma de ovo.
- Renomear o time do usuário mantém o selo "Seu time".
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
- Sem os termos aceitos (ou sem permissão da role), "Postar em" não mostra destinos e nenhum check-in é criado, nem pelo fim automático do treino; editar uma atividade nessa situação não mexe nos posts já feitos. Se a sessão acabar com uma tela aberta, nada é publicado.
- Ao registrar uma atividade, concluir um treino guiado, um WOD ou uma rota GPS, todos os destinos começam marcados: o perfil e as ligas já iniciadas e não encerradas. No botão "+" da liga, só ela começa marcada. Na edição, o que vale é o que já estava postado.
- "Marcar todos" e "Desmarcar" alternam o conjunto completo. Com a conta podendo postar, salvar exige pelo menos um destino (perfil ou liga): sem nenhum, o Salvar fica desabilitado e o rodapé diz "Escolha pelo menos um lugar para salvar." (`hasPostDestination`). Vale no registro, na edição, no fim do treino guiado, no resultado do WOD e no fim da corrida/caminhada. Sem termos aceitos ou sem permissão de postar, salva só no histórico.
- Se não houver foto e algum destino cobrar foto, aparece o aviso "📷 Sem foto, o check-in não pontua em X e vale metade em Y.".
- O formulário da liga tem "Nova atividade" (tipo de treino na lista do Apple Saúde, `ActivityTypePicker`, duração de 5 a 240 min em passos de 5, esforço e data) ou "Já registrada" (atividades dos últimos 7 dias, inclusive do Saúde, com a marca "já postada"). O botão "Postar" exige ao menos um destino.
- A mesma atividade nunca é postada duas vezes na mesma liga. Sem título, o post usa o nome do tipo de treino (`typeName`). O lugar é o do treino ou, na falta dele, o lugar salvo em que o usuário está no momento.
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
- Cada comentário guarda o autor (`authorID`: "me" ou o `memberID` de outra pessoa, e `authorName`). Os seus aparecem com sua foto e seu nome atual; os de outras pessoas, com a inicial e o nome guardado. Comentários antigos, sem autor, contam como seus. Tocar e segurar abre as reações rápidas do comentário (👍 ❤️‍🔥 💪 😂) e permite apagar os seus; nos dos outros, denunciar (RF-SOC-30).
- Reação a um comentário fica guardada como comentário no id `c:<uuid do comentário>` e aparece embaixo dele ("💪 2 · 👍"). As reações do check-in somam numa linha ("💪 3 · 🔥") que abre "Quem reagiu", por emoji. @menções aparecem em destaque.
- O detalhe mostra a prova do check-in (foto da câmera do app, da galeria com a hora gravada, aparelho que gravou), a pose do dia sobre a foto, "Em revisão" quando o dono ainda não aprovou e o corte do teto de pontos. Dono e moderadores têm "Remover check-in da liga" no menu dos outros.
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

### RF-SOC-37 · Rodada suíça diária
**Descrição:** Todo dia, cada liga deve ter uma rodada suíça: os membros se enfrentam em pares, e o resultado dá pontos suíços e um bônus pequeno no placar.
**Regras:**
- O dia segue um fuso fixo, o de Brasília (00:00–23:59, `Swiss.calendar`), em qualquer aparelho. O 1º dia da liga é pareado por uma ordem determinística (hash do id da pessoa, código da liga e data); depois, por pontos suíços acumulados (quem tem mais enfrenta quem tem parecido), desempate pelo id (o seu é o id do servidor, igual em todo aparelho). Revanche só quando não há outro jeito. Com menos de 2 membros não há rodada.
- Cada pessoa só é pareada a partir do dia em que entrou na liga (quem criou está desde o início); dias anteriores não contam para ela, nem para a folga. Quem sai deixa de aparecer nas rodadas, inclusive nas antigas.
- Critério escolhido ao criar/editar a liga (padrão "Mais pontos no dia"): "Mais pontos no dia", "Mais check-ins no dia" (só check-ins válidos pela regra de foto) ou "Presença" (treinou e o outro não = vitória; os dois = empate). Empate = ½ para cada; ninguém treinou = 0 para os dois.
- Número ímpar: quem sobra folga e ganha 1 (como vitória). Ninguém folga de novo antes de todos terem folgado.
- Pontos suíços: vitória 1, empate ½, derrota 0, folga 1. Só rodadas de dias encerrados contam; a de hoje aparece "em andamento" com o placar parcial do dia.
- Bônus no placar da liga (vitória ou folga / empate): pontos +10/+5, minutos +5/+2, distância +500 m/+250 m, calorias +50/+25, treinos +1/+0, dias ativos +1/+0, por atividade +10/+5. Entra no ranking geral, semanal e mensal pelo dia do confronto; o desempate da liga continua valendo.
- No Ranking: seção "Rodada suíça de hoje" (adversário com o bro dele e placar parcial, ou "Folga hoje: +1"), as últimas rodadas (V/E/D/F, até 7) e o texto da regra no rodapé. Sem rodada hoje, mas com histórico, a seção se chama "Rodada suíça". Cada linha do ranking mostra "suíço N" depois da 1ª rodada encerrada.
- Tudo é derivado do feed e dos membros: ao servidor só vão o critério da liga (`League.swiss`) e o dia em que cada um entrou (`Member.joinedAt`, `swissJoinedAt`). O critério vai também no backup e na renovação da temporada (RF-SOC-05).
- Para o pareamento ser igual em todos os aparelhos, o sorteio e o desempate usam o id do servidor (`Cloud.knownID`) no lugar de "me" e a semente é o código da liga.
**Critérios de aceitação:**
- Com 4 membros, nos 3 primeiros dias encerrados cada um enfrenta os outros 3.
- Com 3 membros, em 3 dias cada um folga uma vez.
- Vencer ontem numa liga de pontos soma +10 no "Liga toda" e não entra numa janela que começa hoje.
**Situação:** Local. Os membros simulados (`FakeMember`) participam das rodadas (quem entra atrasado na liga de exemplo não tem rodadas passadas). Com servidor, todos os aparelhos calculam o mesmo pareamento, em qualquer fuso (o dia é sempre o de Brasília).
**Fonte:** `GymBros/Leagues/Swiss.swift` (`Swiss`, `SwissCriterion`, `SwissBonus`, `SwissTable`, `League.swissJoinedAt`), `GymBros/Leagues/Leagues.swift` (`LeagueBoard.swiss`, `ranking`), `GymBros/Leagues/SwissRoundSection.swift`, `GymBros/Leagues/LeagueRemote.swift` (`LeagueDraft.swiss`, `Membership.joinedAt`), `GymBros/Models/League.swift` (`swissRaw`, `SchemaV2`), `GymBros/Services/Backup.swift`, `SwissTests.swift`

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
- Abre também para quem não é amigo (tocar alguém no ranking de uma liga, RF-SOC-07). "Mensagem" e "Mandar força" só aparecem para amigos; "Desafiar para um X1" só funciona com amigos (RF-SOC-38).
- Dados simulados: o nível é sorteado de forma determinística; de 20 a 179 check-ins; dias ativos entre 70% e 95% dos check-ins; de 1 a 4 ligas; cada conquista tem 55% de chance de aparecer. A Fê esconde os números e a Carla esconde as conquistas. Os posts cobrem os últimos 90 dias, com 30% de chance por dia e 80% marcados com foto (sem imagem real).
**Critérios de aceitação:**
- O perfil da Fê não mostra a linha de números.
- Tocar num dia com posts abre a lista dos posts daquele dia, e cada post abre o detalhe (RF-SOC-11).
**Situação:** Simulado no modo atual. No CloudKit, o perfil vem do registro `Profile` do amigo (`FriendsBackend.profile`), só com as partes que ele deixou visíveis.
**Fonte:** `GymBros/Friends/PublicProfile.swift` (`FriendProfileView`, `friendActions`), `GymBros/Friends/Friends.swift` (`MockFriendsBackend.profile`, `posts`), `GymBros/Leagues/LeaguesView.swift` (`LeagueDetailView`)

### RF-SOC-16 · Perfil próprio: público e privado
**Descrição:** O app deve separar o que os amigos veem (aba Público) dos dados pessoais (aba Privado).
**Regras:**
- A tela é um `GMScreen` com X para fechar e engrenagem de Ajustes; o botão flutuante registra atividade. O cabeçalho mostra a foto (recortada em quadrado de 512 px, JPEG com qualidade 0,8; tocar troca a foto), o nome ("Treinador" quando vazio), o @usuário, a bio e o botão "Editar perfil".
- **Público:** "É assim que seus amigos te veem": o card com o bro principal, os números e as conquistas desbloqueadas (no máximo 6 chips, com o total no título), mais o calendário dos posts do perfil.
- Números públicos: "Check-ins" conta só atividades postadas (no perfil ou em alguma liga); "Dias ativos", só os dias dessas atividades; "Ligas", só as ligas atuais (temporadas passadas da mesma liga não contam de novo).
- **Privado:** atividades (todas), dias ativos, duração total, Recordes, Estatísticas, Metas, o calendário de todas as atividades (com a foto do check-in quando existe), a seção "X1" com os últimos 5 X1 encerrados e o retrospecto (só quando há algum, RF-SOC-38), "Ver todas as atividades" e "Peso".
- "Editar perfil" (modal): nome, @usuário (convertido para minúsculas, aceitando só letras, números, "_" e ".") e bio. As chaves de visibilidade são "Bro principal", "Números (check-ins, dias, ligas)" e "Conquistas", todas ligadas por padrão.
- Sempre visíveis: foto, nome, @usuário, bio e posts do perfil. Sempre privados: peso, medidas, recordes, metas, notas e atividades não postadas.
**Critérios de aceitação:**
- Desligar "Conquistas" tira as conquistas da prévia pública.
- Uma atividade não postada aumenta "Atividades" no Privado, mas não "Check-ins" no Público.
- Sem posts, aparece a dica: marcar "Meu perfil" em "Postar em".
- Ao abrir o app, o perfil público é montado (`PublicProfile.mine`, respeitando as chaves de visibilidade) e publicado com o código de amigo (`FriendsStore.publish`) só se mudou desde o último envio: a comparação usa um hash SHA-256 guardado por modo de backend, então trocar de simulado para CloudKit publica de novo.
**Situação:** Depende de servidor. A prévia é local; a publicação usa `FriendsBackend.publish`, que não faz nada no modo simulado (atual) e grava o registro `Profile` no CloudKit. A foto do perfil não sobe.
**Fonte:** `GymBros/Profile/ProfileView.swift` (`ProfileView`, `publicStats`, `EditProfileView`, `avatarPhoto`), `GymBros/Duels/DuelViews.swift` (`DuelHistorySection`), `GymBros/Friends/PublicProfile.swift` (`PublicProfileCard`, `PublicProfile.stats`, `PublicProfile.mine`), `GymBros/Friends/Friends.swift` (`FriendsStore.publish`), `GymBros/App/App.swift`

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

### RF-SOC-38 · X1 (desafio direto)
**Descrição:** Amigos podem se desafiar para um X1. O X1 não tem nenhuma relação com ligas. Só entre amigos (`FriendError`/`.notFriend`), e cada bro luta um X1 por vez (`Duels.busyFighters`).
**Regras:**
- Sem vínculo com liga: não depende de liga, não usa a pontuação nem o feed de nenhuma liga e não mexe em placar, pontos ou rodada suíça. A rodada suíça continua só entre membros da mesma liga (RF-SOC-37). As ligas só servem para achar gente para desafiar.
- Quem desafia escolhe a métrica: XP (duração × tipo × esforço), treinos (cada atividade vale 1), minutos, distância (metros do GPS do app) ou calorias (as informadas no app ou, sem elas, minutos × MET × 1,2) (`DuelMetric`). Vale qualquer atividade registrada (inclusive as do Apple Saúde, que entram como nas ligas: esforço 5, sem a distância e com as calorias estimadas, porque o valor vai ao servidor) nas 24 h seguintes ao aceite. Vence quem somar mais; mesma soma é empate. O composer resume: "24 h para aceitar", "Vale 24 h", "Saúde conta".
- Ovos não entram no X1: sem nenhum bro chocado, desafiar e aceitar dão "Ovos não entram no X1. Choque um ovo (no principal ou numa liga) para lutar." Com mais de um bro chocado, quem desafia escolhe "Quem vai lutar?" e quem aceita escolhe o bro antes de confirmar (`FighterChoice`); o padrão é o bro principal, se já chocou, ou o primeiro chocado. O bro escolhido para cada X1 fica só no aparelho (`duelMonsters`) e aparece com a forma atual (pode evoluir durante o X1).
- Onde desafiar: "Desafiar para um X1" no perfil de qualquer pessoa (tocar alguém no ranking de uma liga abre o perfil), botão "X1" na conversa (RF-SOC-34), a linha "X1 · Desafie qualquer pessoa" na tela de Amigos (com o número de desafios esperando você) e o cartão X1 da tela inicial. A escolha de pessoa ("Desafiar quem?") tem busca pelo nome, "Revanche" (até 8 adversários recentes), "Amigos", "Das suas ligas" (sem bloqueados e sem temporadas passadas) e, no fim e desabilitados com o motivo, "Com X1 aberto ou indisponível". Desafiar e aceitar passam pelo aceite dos termos (`TermsGate`).
- O desafiado aceita ou recusa; pendente sem resposta expira 24 h depois do desafio.
- No máximo um X1 aberto (pendente ou em andamento) por par, nos dois sentidos. Se os dois se desafiarem quase ao mesmo tempo, só o desafio mais antigo pode ser aceito. Não dá para desafiar a si mesmo, quem você bloqueou nem quem te bloqueou ("Não dá para desafiar essa pessoa."). X1 com quem você bloqueou some das listas.
- Cada aparelho calcula o próprio valor com as suas atividades e informa ao servidor (`DuelBackend.report`, só quando muda, até 1 h depois do fim); o do adversário vem do servidor. A lista é buscada a cada 3 s nos 2 primeiros minutos depois de você desafiar e a cada 30 s no resto do tempo, com a tela X1 aberta.
- Tela X1: retrospecto (vitórias, empates, derrotas), desafios recebidos (Aceitar/Recusar, com o tempo até expirar), "Valendo agora" (placar ao vivo e tempo restante), "Esperando resposta" e "Encerrados". Sem nenhum, "Nenhum X1 ainda" com "Novo X1".
- Tela inicial: o cartão X1 aparece sempre. Mostra o retrospecto (V · E · D), até 3 linhas (desafios esperando você, o mais antigo primeiro, depois os X1 valendo, o que acaba antes primeiro) e "Ver mais N"; sem nenhum, convida a desafiar, com atalho para até 4 amigos e "Desafiar alguém".
- Perfil próprio (aba Privado): os últimos 5 X1 encerrados e o retrospecto (RF-SOC-16).
- Caixa de entrada: desafio recebido, aceito e resultado; recusado e expirado só para quem desafiou (tópico "X1" em Ajustes → Notificações, RF-SOC-35 e RF-SOC-36).
**Critérios de aceitação:** `DuelTests` (janela de 24 h, valor só na janela, métricas, resultado e texto, retrospecto, busca rápida só logo depois de desafiar, um aberto por par, qualquer pessoa menos você e bloqueados, mock responde e treina, mock recusa par aberto/bloqueio/pessoa inexistente, desafio recebido respondido e persistido) e `DuelFighterTests` (ovo não luta, o bro escolhido te representa).
**Situação:** Simulado no modo atual (`MockDuelBackend`): seus desafios e respostas ficam no aparelho (`mockDuels`, que vai com a conta como os outros servidores simulados); as pessoas simuladas (`MockFriendsBackend.directory`) respondem entre 3 e 9 s depois (~80% aceitam), treinam durante o X1 e às vezes desafiam você (até um por dia, nos últimos 3 dias). Depende de servidor para valer entre pessoas reais: no CloudKit, `CloudKitDuelBackend` grava registros `Duel` (desafio, resposta e valor, cada um escrito por quem é dono). Lá, "quem te bloqueou" não é conferido ao desafiar (os `Block` não são legíveis por outros); o desafio chega e fica escondido do lado de quem bloqueou.
**Fonte:** `GymBros/Duels/Duel.swift` (`RemoteDuel`, `DuelMetric`, `Duels`, `DuelRefusal`), `GymBros/Duels/DuelStore.swift` (`DuelStore`, `DuelBackend`, `MockDuelServer`), `GymBros/Duels/DuelViews.swift` (`DuelsView`, `DuelComposer`, `DuelPeoplePicker`, `DuelHomeCard`, `DuelHistorySection`, `FighterChoice`), `GymBros/Friends/Friends.swift` (`FriendsView`), `GymBros/Friends/PublicProfile.swift`, `GymBros/Inbox/ConversationView.swift`, `GymBros/Bros/HomeView.swift`, `GymBros/Services/Backend.swift` (`CloudKitDuelBackend`), `DuelTests.swift`, `DuelFighterTests.swift`

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
- Tocar no pino centraliza o mapa no amigo e abre o card. O card mostra o bro (com um anel pulsando, se o movimento não estiver reduzido), "AO VIVO" com o tempo de treino, a atividade e o lugar, uma faixa de estatísticas que mudam com o tipo (tempo, distância e ritmo; séries; metros nadados; kcal; bpm), "AGORA" com o exercício atual e os já feitos, a música que a pessoa está ouvindo (RF-SOC-39) e as ações "Mandar força", "Mensagem" (abre a conversa, RF-SOC-34) e "Treinar junto" (convite para agora, no lugar do amigo). Não há mais "Ver no mapa": o card já abre com o mapa centrado.
- "Mandar força" e "Treinar junto" passam pelo aceite dos termos e vão pela caixa de entrada (`InboxStore.cheer`, `invite`); depois de enviar, o card mostra "Força enviada" ou "Convite enviado" e "Chegou para {nome}. A resposta aparece no sino da tela inicial.".
- Treino ao vivo (`LiveShare`): vem ligado por padrão; o último passo do primeiro acesso explica e deixa desligar (RF-JOG-13). O ajuste "Compartilhar treino ao vivo" (Mapa > Ajustes) é o padrão dos próximos treinos e diz "Padrão dos próximos treinos: amigos veem onde você treina e o exercício atual, só durante o treino. Cada treino pode mudar no chip \"Ao vivo\". Ainda não envia nada: chega quando o app tiver servidor". No treino guiado, no cronômetro do WOD e na corrida/caminhada/bike com GPS, o chip "Ao vivo para amigos" / "Só você", ao lado do lugar, liga ou desliga só aquele treino; a escolha some quando o treino termina ou é descartado. Padrão e escolhas vão com a conta (`AccountData.userKeys`). O rodapé de "Amigos agora" avisa que é uma prévia com amigos simulados.
**Critérios de aceitação:**
- Desfazer a amizade com o Bruno tira o Bruno do mapa e da lista.
**Situação:** Simulado. Força, convite e mensagem vão para a caixa de entrada simulada (RF-SOC-34), e os amigos simulados respondem; com servidor, dependem do `InboxBackend` real. "Compartilhar treino ao vivo" não envia nada: depende de servidor.
**Fonte:** `GymBros/Friends/FriendsLive.swift` (`LiveFriendCard`, `FriendPin`), `GymBros/Friends/MapScreen.swift` (`friendsSection`, `friendsBase`, `settingsSheet`), `GymBros/Friends/LiveShare.swift` (`LiveShare`, `LiveShareChip`), `GymBros/Train/WorkoutView.swift`, `GymBros/Train/Wod.swift`, `GymBros/Services/Route.swift`, `LiveShareTests.swift`

### RF-SOC-39 · Música que você está ouvindo
**Descrição:** Quem quiser pode mostrar aos amigos a música que está tocando enquanto treina ao vivo.
**Regras:**
- Desligado por padrão (`shareMusic`). Fica em Ajustes > Música e em Ajustes > Privacidade > "Mostrar o que estou ouvindo". Rodapé: "Enquanto você treina ao vivo, seus amigos veem a música que está tocando. Só a música atual: nada do seu histórico ou da sua biblioteca é enviado. Desligado, nada é lido."
- Ligar pede o acesso ao serviço. Apple Music: permissão da biblioteca de mídia do iOS (`MPMediaLibrary`, texto em `NSAppleMusicUsageDescription`), e o app lê só o item que está tocando no app Música (`MPMusicPlayerController.systemMusicPlayer`: título, artista e serviço). Sem acesso, o interruptor volta para desligado e aparece "Sem acesso ao Apple Music. Libere em Ajustes do iPhone > GymBros.".
- Spotify só aparece quando o app tiver um `SpotifyNowPlaying.clientID` (hoje `nil`): até lá, a lista "Serviço" não aparece e só o Apple Music existe.
- Ligado, a seção "Agora" mostra o que está tocando (atualiza a cada 5 s com a tela aberta) ou "Nada tocando no Apple Music"; no `.mock`, o rodapé avisa "Nesta versão sem servidor, só você vê; os amigos veem quando o app tiver servidor.".
- Nos amigos ao vivo (RF-SOC-23), quem tem música mostra uma etiqueta com o título em cima do pino e uma linha no card com título, artista e serviço. Na simulação, o Bruno ouve "Till I Collapse" (Apple Music) e a Ana "Run Boy Run" (Spotify).
- A preferência e o serviço escolhido (`shareMusic`, `musicSource`) vão com a conta (`AccountData.userKeys`) e saem do aparelho ao sair; não entram no arquivo de backup. A música lida não é guardada.
**Critérios de aceitação:** `MusicShareTests` (desligado não lê nada, ligar lê a música atual, acesso negado continua desligado com mensagem, Spotify escondido até ser registrado, preferência vai com a conta).
**Situação:** Local (leitura no aparelho). O envio aos amigos depende de servidor: `MusicShareStore.current` ainda não sai do iPhone, e a música dos amigos é simulada.
**Fonte:** `GymBros/Music/Music.swift` (`MusicShareStore`, `AppleMusicNowPlaying`, `SpotifyNowPlaying`, `NowPlayingTrack`), `GymBros/App/SettingsPages.swift` (`MusicSettingsPage`, `PrivacySettingsPage`), `GymBros/App/SettingsView.swift`, `GymBros/Friends/FriendsLive.swift` (`LiveFriend.music`), `GymBros/Services/Auth.swift` (`AccountData.userKeys`), `MusicShareTests.swift`

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
- O treino vai com o tipo escolhido no registro (`healthType`, da lista de tipos do Saúde) ou, sem ele, com o tipo equivalente à categoria (`activityType`). As calorias são estimadas pela fórmula do RF-SOC-06, usando o peso mais recente do app, do Saúde ou 70 kg. Corrida, caminhada, bike, futebol e vôlei são gravados como treino ao ar livre.
- Editar ou apagar a atividade remove o treino gravado, que é gravado de novo com os dados atualizados.
**Critérios de aceitação:**
- Desligar mostra "Não grava mais. O que já foi para o Saúde continua lá.".
**Situação:** Local.
**Fonte:** `GymBros/Services/HealthSync.swift` (`exportPending`, `write`, `deleteWritten`), `GymBros/Activities/LogActivityView.swift`

### RF-SOC-26 · Backup e restauração
**Descrição:** O app deve exportar e restaurar uma cópia completa dos dados em JSON.
**Regras:**
- Exporta para o Arquivos (o app não sugere o iCloud Drive, porque o arquivo leva dados do Apple Saúde) com o nome `GymBros-AAAA-MM-DD.json` (versão 1, datas ISO 8601; campos novos são opcionais, então backups antigos continuam abrindo).
- Inclui: atividades (com distância, calorias, tipo de treino e a divisão do XP entre os atributos, `attributes`), rotinas, sessões e séries, exercícios próprios, ligas com todas as configurações (pesos, desempate, regra de foto, critério da rodada suíça, times, seu time) e a capa reduzida (até 640 px, JPEG 0,6, só na temporada atual; ao restaurar, as passadas usam a mesma), bros, medidas, notas, check-ins (sem a imagem, mas com "tinha foto" e o lugar), percursos, visitas, lugares, WODs (com CAP), recordes, comentários (com autor), recados do mural, a foto do perfil (512 px) e os ajustes `trainerName`, `monsterNick`, `lastFormID`, `discovered`, `bodyGender`, `mainMonster`, `profileUsername`, `profileBio`, `exerciseGoals`, `autoWarmup`, `restNotification`, `barWeight`, os WODs agendados (`plannedWods`) e o perfil físico e as metas (`profileHeight`, `profileBirthYear`, `profileGoal`, `profileExperience`, `profileLastWeight`, `goalWeight`, `goalWeekly`, `goalMinutes`).
- Os ajustes vão também com o tipo (`typedSettings`: booleano, número ou texto) e são restaurados com ele; backups antigos só têm a versão em texto. Backup sem foto do perfil mantém a atual.
- Ficam de fora do arquivo: as imagens dos check-ins e as fotos de progresso, as chaves de visibilidade do perfil, o código e a lista de amigos, além das preferências de Saúde, de lugares, de lembretes, de notificações e de música (RF-SOC-39). Tudo isso vai na cópia da conta (RF-SOC-33); o arquivo é uma cópia extra. Os X1 (RF-SOC-38) ficam no servidor e também não entram; o bro escolhido para cada X1 (`duelMonsters`) fica só no aparelho, fora do backup e da cópia da conta.
- Rodapé: "Seus dados são da sua conta e voltam quando você entra nela. O backup é uma cópia extra em arquivo…"; no `.mock`, avisa que o servidor é simulado no iPhone e que, se o app for apagado, só o backup recupera tudo.
- Visitas de backups antigos ficam no lugar de mesmo nome; sem correspondente, ficam sem lugar (contam nas idas do mês com o nome guardado). Depois de restaurar, o monitoramento dos lugares recomeça.
- Restaurar mostra a data e o número de atividades e pede confirmação ("Substituir tudo"): todos os dados atuais são apagados antes da restauração.
**Critérios de aceitação:**
- Depois de restaurar, aparece "Backup restaurado: N atividades." e um bro inicial é garantido.
- Um check-in que tinha foto continua pontuando numa liga com foto obrigatória depois de restaurar.
**Situação:** Local.
**Fonte:** `GymBros/Services/Backup.swift` (`Backup.make`, `restore`, `settingKeys`, `Setting`, `smallCover`), `GymBros/Bros/AttributeSplit.swift` (`ActivitySplits`), `GymBros/Profile/BodyProfile.swift` (`BodyProfile.keys`), `GymBros/Train/WodImport.swift` (`WodPlan.key`), `GymBros/App/SettingsView.swift`

### RF-SOC-27 · Ajustes
**Descrição:** O app deve concentrar as preferências gerais.
**Regras:**
- Nome do treinador; apelido do bro principal (vazio usa o nome da forma).
- Lembrete diário (desligado por padrão, às 18:00), só nos dias sem treino, com a opção "Só em dias de rotina". Resumo da semana no domingo às 19h (ligado por padrão), com treinos, tempo, PRs e posição nas ligas. Notificação no fim do descanso (desligada).
- Aquecimento automático (ligado): 3 séries a 40%, 60% e 80% da carga no primeiro exercício com carga. Não há mais o ajuste "Carga na barra": é automático pelo tipo do treino (RF-TRE-05).
- Música (RF-SOC-39), Apple Saúde (RF-SOC-24 e RF-SOC-25), Backup (RF-SOC-26), Conta (RF-SOC-28) e Privacidade > "Termos de uso" (RF-SOC-31), "Mostrar o que estou ouvindo" (RF-SOC-39) e "Usuários bloqueados" (RF-SOC-30).
- "Recomeçar jornada" existe só em builds de desenvolvimento (`#if DEBUG`), para testes, e vai sair do app. Pede confirmação com o texto de `SettingsView.resetText`: apaga as atividades e tudo ligado a elas (treinos guiados concluídos, check-ins no perfil e nas ligas com seus comentários, percursos, WODs), os bros, as conquistas já vistas, o BroBook descoberto e os carinhos do widget, e devolve um ovo novo, que passa a representar o usuário nas ligas, com placar zerado. Rotinas, lugares, medidas, ligas e o nome continuam; um treino em andamento continua. As próximas importações do Saúde partem do momento atual.
**Critérios de aceitação:**
- Ligar um lembrete pede a permissão de notificações.
- Depois de "Recomeçar jornada", o app continua na tela principal (sem voltar ao onboarding) com um ovo de 0 XP.
**Situação:** Local.
**Fonte:** `GymBros/App/SettingsView.swift` (`reset`, `resetText`), `GymBros/App/SettingsPages.swift`

---

## 5. Conta e compartilhamento

### RF-SOC-28 · Login e conta
**Descrição:** A conta é obrigatória e os dados são dela (como no GymRats e no Strava): sem sessão, o app só mostra o login. Nos Ajustes dá para sair e excluir a conta (guidelines 5.1.1(v) e 4.8); as duas ações voltam para o login.
**Regras:**
- Sem sessão, `RootView` mostra só o `LoginView` (sem X para fechar); com sessão, "Abrindo sua conta…" até os dados da conta estarem no aparelho (RF-SOC-33); depois vem o onboarding (se ainda não houver nome de treinador) e o app. Nada do app é acessível sem login.
- O login mostra o bro bebê animado, "GymBros", "Seus treinos chocam e evoluem um bro." e o seletor "Entrar" / "Criar conta". As telas sociais só pedem o aceite dos termos e a permissão da role (`SocialGate`).
- Quem já tinha sessão continua logado.
- "Criar conta" pede nome, e-mail e senha; "Entrar", e-mail e senha. O e-mail perde os espaços e vai para minúsculas. Erros: "Diga seu nome.", "E-mail inválido.", "A senha precisa de pelo menos 8 caracteres." e "Já existe uma conta com esse e-mail. Entre em vez de criar.". O botão só é liberado com e-mail e senha preenchidos.
- "Continuar com a Apple" usa o botão oficial (`SignInWithAppleButton`, estilo branco, 50 pt). O toque vai para `AuthStore`: no `.mock` chama o login simulado; no `.cloudKit` abre a folha da Apple (`AppleIDAuthorization`, nome e e-mail). No `.mock` o rodapé avisa: "Ainda não há servidor: o login é simulado e os dados da conta ficam guardados neste iPhone.".
- Login simulado (`MockAuthBackend`): qualquer senha válida entra, porque não há como conferi-la; as contas criadas guardam só e-mail e nome no aparelho (a senha nunca é guardada). A Apple simulada devolve sempre o mesmo usuário neste aparelho, com e-mail de retransmissão (`…@privaterelay.appleid.com`).
- Conta de demonstração (revisão da Apple, só no `.mock`, inclusive no Release): o botão "Entrar com conta de demonstração" entra pelo `AuthBackend` com `revisao@gymbros.app` / `GymBros2026` (nome "Bro Revisor"); digitar essas credenciais dá no mesmo. Na primeira vez que ela abre a aba Ligas, já está na liga de exemplo (RF-SOC-04); sair da liga não a traz de volta (`demoSeeded`, chave da conta). No `.cloudKit` o botão some (`docs/app-review.md`).
- A sessão (`AuthUser`: id, nome, e-mail, provedor e token) fica no Keychain. O nome da conta vira o nome de treinador se ainda não houver um; com nome de treinador, o app pula o onboarding e abre direto a tela principal.
- Ajustes, seção "Conta": nome (ou "Sua conta"), e-mail, ícone do provedor, "Sair da conta" e "Excluir conta". Rodapé: "Treinos, bros e o resto do progresso são da conta: ao sair, saem do iPhone e voltam quando você entra de novo." (no `.mock`, antes, "Login e servidor simulados neste iPhone.").
- "Sair da conta" pede confirmação ("Seus treinos, bros e o resto do progresso ficam salvos na conta e saem deste iPhone. Tudo volta quando você entrar de novo."), salva a cópia da conta e só então tira os dados do aparelho e volta ao login. Se não der para salvar, nada sai e aparece "Não deu para salvar seus dados na conta: … Nada saiu do iPhone; tente de novo.".
- "Excluir conta" pede confirmação destrutiva (`SettingsView.deleteAccountText`): "Apaga a conta e tudo dela, na conta e neste iPhone: treinos, bros, rotinas, medidas, fotos, recordes, ligas, check-ins, recados, mensagens, amizades, bloqueios e denúncias. Você volta para a tela de entrar. Não dá para desfazer.". Apaga a cópia da conta no servidor, a conta e o que ela publicou (perfil, lugar nas ligas, check-ins, recados, amizades, denúncias, bloqueios e, no CloudKit, os registros `Duel` dos X1) e, no aparelho, o banco inteiro, as chaves de usuário (inclusive aceite dos termos, bloqueios e denúncias), o resumo do widget e a sessão do Keychain. Se o servidor falhar, nada é apagado do aparelho e aparece "Não deu para excluir a conta: … tente de novo.". "Recomeçar jornada" continua existindo e mantém a conta.
- No modo CloudKit, a conta é a do iCloud do aparelho; entrar por e-mail responde "Por enquanto, entre com a Apple (usa a sua conta do iCloud)." e exigiria servidor próprio.
**Critérios de aceitação:**
- Senha de 7 caracteres mostra "A senha precisa de pelo menos 8 caracteres.".
- Criar conta duas vezes com o mesmo e-mail mostra o erro de e-mail em uso.
- Sair da conta tira atividades, bros, ligas e ajustes do aparelho; entrar de novo traz tudo de volta (`AccountSyncTests`).
- Instalação nova abre no login; sem entrar, não há como chegar ao onboarding nem ao app.
- "Sair da conta" volta para o login, sem X para fechar.
- A conta de demonstração entra na liga de exemplo uma única vez, só no `.mock` e só ela (`DemoAccountTests`).
- Excluir conta apaga a cópia no servidor simulado, tudo do aparelho e as cópias guardadas da conta; se a limpeza do aparelho for interrompida, ela termina ao abrir o app ou antes de outra conta entrar (`AccountSyncTests`, `AccountDeletionTests`).
- Depois de entrar de novo, o que você denunciou continua oculto, as conversas lidas continuam lidas e as academias salvas voltam a ser monitoradas.
**Situação:** Simulado. Sign in with Apple e iCloud exigem conta paga do Apple Developer (o Personal Team não tem).
**Fonte:** `GymBros/Services/Auth.swift` (`AuthStore`, `AccountData`, `MockAuthBackend`, `LoginView`, `AuthError`), `GymBros/Services/DemoAccount.swift`, `GymBros/Services/AccountSync.swift`, `GymBros/App/SocialGate.swift`, `GymBros/App/App.swift` (`RootView`), `GymBros/App/SettingsView.swift`, `GymBros/Services/Backend.swift` (`CloudKitAuthBackend`, `AppleIDAuthorization`)

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

### RF-SOC-30 · Denunciar e bloquear (guideline 1.2)
**Descrição:** O usuário deve poder denunciar conteúdo de outras pessoas e bloquear quem quiser.
**Regras:**
- Onde: menu ⋯ do detalhe de um check-in de outra pessoa (feed da liga e posts do perfil: "Denunciar check-in", "Denunciar foto" quando há foto, "Bloquear {nome}"), tocar e segurar um comentário ou recado do mural de outra pessoa, e menu ⋯ do perfil de outra pessoa ("Denunciar perfil", "Bloquear {nome}"). Nunca aparece no seu próprio conteúdo.
- Denunciar pede o motivo (Ofensivo ou assédio, Nudez ou conteúdo sexual, Violência, Spam, Outro motivo) e mostra "Obrigado pela denúncia" (análise em até 24 h). O conteúdo some na hora só para quem denunciou (check-in vira "Check-in denunciado"; de quem você bloqueou, "Check-in oculto" com o caminho para desbloquear; foto some e o check-in fica; perfil mostra "Perfil denunciado").
- Bloquear pede confirmação explicando o efeito. A pessoa some dos check-ins da liga, posts, comentários, mural, amigos, pedidos, sugestões, mapa, mensagens e notificações (RF-SOC-34 e RF-SOC-35) e dos X1 (não pode ser desafiada nem ter desafio aceito, e os X1 com ela saem das listas, RF-SOC-38), e a amizade é desfeita. O ranking, a pontuação e a rodada suíça da liga não mudam.
- Ajustes > Privacidade > "Usuários bloqueados" lista quem foi bloqueado, com "Desbloquear" (a amizade não volta sozinha).
- Excluir a conta apaga bloqueios e denúncias do aparelho e do servidor.
**Critérios de aceitação:**
- Denunciar um check-in o tira da lista da liga sem mudar o ranking (`ModerationTests`).
- Sem rede, a denúncia fica na fila e é enviada depois; o conteúdo continua oculto.
**Situação:** Simulado (`MockModerationBackend` guarda no aparelho). No CloudKit, `Report` e `Block` no banco público; a análise em 24 h depende de moderação fora do app (`docs/cloudkit.md`).
**Fonte:** `GymBros/Moderation/Moderation.swift`, `GymBros/Moderation/ModerationSheets.swift`, `GymBros/Leagues/CheckInDetail.swift`, `GymBros/Leagues/LeagueMural.swift`, `GymBros/Friends/PublicProfile.swift`, `GymBros/Duels/DuelStore.swift` (`duels`, `refusal`), `GymBros/App/SettingsPages.swift` (`PrivacySettingsPage`)

### RF-SOC-31 · Termos de uso e aceite (guideline 1.2)
**Descrição:** O app deve ter termos de uso com tolerância zero para conteúdo ofensivo e usuários abusivos, e pedir o aceite no primeiro acesso.
**Regras:**
- Os termos explicam denúncia, bloqueio, análise em até 24 h, remoção do conteúdo e expulsão de quem o publicou. Ficam em Ajustes > Privacidade > "Termos de uso" e na web (https://alonsojrr14.github.io/gymbros/termos/, `docs/termos.md`, mesmo texto). A tela de login tem links para os termos e a política de privacidade.
- Primeiro acesso: na tela do ovo há duas caixas, "Li e concordo com os Termos de uso" e "Li e concordo com a Política de privacidade" (`LegalConsent`). Tocar na caixa (ou no texto) só marca e desmarca; o documento abre só pelo link sublinhado no nome dele. "Receber meu ovo" só libera com as duas marcadas. O mesmo componente aparece antes de publicar (`TermsAcceptView`) e quando a versão dos termos muda (`TermsRequiredView`), com o botão "Aceitar e continuar" liberado só com as duas caixas marcadas.
- Os avisos nas telas sociais ("Aceite os termos para continuar", `TermsGate`) ficam só como proteção: com o aceite na entrada, não aparecem no uso normal.
- O aceite fica no aparelho com a versão (`Terms.version`) e a data. Subir a versão pede o aceite de novo. Excluir a conta apaga o aceite.
- Sem aceite nada é publicado: `postCheckIns`/`syncCheckIns` não criam nem mudam check-ins e o perfil público não sobe.
**Critérios de aceitação:** `TermsTests` (versão, novo aceite, espera do aceite, exclusão de conta).
**Situação:** Implementado; o aceite não vai ao servidor.
**Fonte:** `GymBros/App/TermsView.swift`, `GymBros/App/SocialGate.swift`, `GymBros/Leagues/LeaguesView.swift`, `GymBros/Services/Auth.swift`

---

### RF-SOC-32 · Filtro de palavras
**Descrição:** Texto com termos ofensivos não deve ser publicado.
**Regras:**
- Vale para recados, comentários (inclusive reações), título e descrição de check-ins publicados (e a observação, que vira título), nome, @usuário e bio do perfil, o apelido do bro no perfil público e o nome da liga e dos times.
- No fim do treino guiado o título do post é o nome da rotina; barrado, aparece o campo "Título do post" para ajustar antes de salvar.
- O filtro só impede publicar e republicar: tirar destinos de uma atividade sempre apaga os check-ins de lá, mesmo com título barrado.
- Barrado, o texto não é enviado e aparece "Esse texto tem palavras que não são permitidas no GymBros. Ajuste e tente de novo." perto do campo. Em Ajustes > Treinador, um nome barrado mostra um aviso e sobe vazio (perfil e ligas).
- A lista fica em `GymBros/Moderation/BlockedTerms.swift` (português e inglês). O filtro ignora acentos e maiúsculas, troca @→a, 4→a, 0→o, 1→i, !→i, 3→e, 5→s, $→s, 7→t grudados em letras, aceita letras repetidas ("merdaaa") e separadas ("p u t a") e compara palavras inteiras; `*` no fim do termo pega o que começa com ele.
**Critérios de aceitação:** `ContentFilterTests` (variações, palavras inocentes como "computador", "Scunthorpe" e "putativo", check-in barrado não é criado nem alterado, tirar destino apaga mesmo com texto barrado).
**Situação:** Implementado, no aparelho.
**Fonte:** `GymBros/Moderation/ContentFilter.swift`, `GymBros/Moderation/BlockedTerms.swift`

### RF-SOC-33 · Dados vinculados à conta
**Descrição:** Treinos, atividades, bros, rotinas, recordes, medidas, fotos, lugares, ligas e ajustes pertencem à conta, não ao aparelho.
**Regras:**
- A cópia da conta tem o formato do backup (RF-SOC-26) mais todas as chaves de usuário (`AccountData.userKeys`: inclui notificações, caixa de entrada, termos, moderação, Saúde e música), as fotos dos check-ins e de progresso e as capas das ligas. Sobe 5 s depois da última mudança (banco ou ajustes) e ao ir para segundo plano. Fica de fora o bro escolhido para cada X1 (`duelMonsters`): só no aparelho.
- O aparelho guarda de quem são os dados locais (hash da conta). Ao entrar: se são da mesma conta, nada muda; se são de outra, viram uma cópia de segurança em `Application Support/AccountSync/` e saem; se o servidor tem dados da conta, eles voltam; se não tem, os dados locais sem dono (instalação de antes da conta obrigatória) passam a ser da conta e sobem. Nenhum dado local é apagado sem antes virar uma cópia, exceto os de uma conta excluída (que saem junto com as cópias dela).
- Entrar com outra conta nunca mostra dados da anterior, nem amigos, mensagens, denúncias, bloqueios e X1 simulados (no `.mock`, esse estado, `MockAccountDataBackend.socialKeys`, vai para o arquivo da conta ao sair e volta ao entrar). Depois de restaurar, os stores do aparelho são relidos (moderação, caixa de entrada, música, lugares monitorados e recordes).
- Sair e excluir: RF-SOC-28. Ao limpar o aparelho, também saem o resumo do widget no App Group (widgets recarregam), a Live Activity, as notificações agendadas e os lugares monitorados.
- No `.mock`, o servidor é simulado: um arquivo por conta em `Application Support/MockServer/` (nome = hash da conta), fora do banco, que sai junto com o app. No `.cloudKit`, a cópia não vai para o iCloud porque tem dados do Apple Saúde (guideline 5.1.3(ii)); `ServerAccountDataBackend` responde "Os dados da conta precisam do servidor próprio do GymBros, que ainda não existe." e o login para em "Não deu para abrir sua conta" (com "Tentar de novo" e "Sair").
**Critérios de aceitação:** `AccountSyncTests` (adoção dos dados sem dono, sair limpa e entrar restaura, troca de conta não mistura, servidores simulados por conta, dados de outra conta guardados antes de sair, stores relidos depois de restaurar, excluir apaga servidor simulado, aparelho e cópias guardadas, exclusão interrompida termina antes da próxima conta, falha ao excluir mantém tudo).
**Situação:** Simulado (servidor no próprio aparelho). Depende de servidor próprio para valer entre aparelhos.
**Fonte:** `GymBros/Services/AccountSync.swift` (`socialKeys`, `park`, `unpark`, `deviceReload`), `GymBros/Services/Auth.swift` (`AccountData`), `GymBros/Services/Backup.swift` (`make(account:)`, `accountSettings`), `GymBros/App/App.swift` (`RootView`)


### RF-SOC-34 · Mensagens diretas (força, convite e texto)
**Descrição:** Conversa privada entre amigos, com três tipos de mensagem além do texto: "Mandar força" (incentivo com texto opcional), convite para treinar junto (atividade, lugar e quando: agora, ou hoje, amanhã ou outro dia num horário) e resposta ao convite ("Bora!" ou "Hoje não").
**Regras:**
- Só entre amigos. Dá para responder a quem já conversou com você mesmo depois de desfazer a amizade. Quem você bloqueou some das conversas e não recebe nada (`InboxError.blocked`).
- Texto, lugar e recado passam pelo `ContentFilter`; enviar exige o aceite dos termos (`TermsGate`) e a permissão `directMessages.send`.
- Segurar uma mensagem recebida abre denunciar (tipo `directMessage`) ou bloquear; a denunciada some na hora só para você.
- Convite: os lugares salvos aparecem como chips acima do campo "Onde?"; o padrão é o lugar em que você está agora (ou o sugerido pelo card ao vivo). "Quando" tem "Agora", "Hoje", "Amanhã" e "Outro dia" (com data a partir de hoje); fora de "Agora", escolhe o horário (padrão 19:00). Horário que já passou mostra "Esse horário já passou" e não envia. Se o lugar é um dos salvos (mesmo nome do chip), o convite leva as coordenadas dele (`TrainInvite.latitude`/`longitude`), e quem recebe vê o lugar sublinhado com "Ver no mapa" (abre o Apple Maps). Os termos (versão 2) e a política avisam que o nome e as coordenadas da academia salva vão para o amigo convidado; local digitado à mão leva só o texto.
- Pontos de entrada: sino da tela inicial (caixa de entrada → Mensagens, "Nova mensagem" lista os amigos), botões "Mensagem" e "Mandar força" no perfil do amigo, "Mandar força", "Mensagem" e "Treinar junto" no card do amigo ao vivo no Mapa. Na conversa, os atalhos são "Mandar força", "Treinar junto" e "X1" (abre o desafio, RF-SOC-38).
- No `.mock`, os amigos simulados respondem em 3 a 8 s (força de volta, 75 % de chance de topar o convite, texto do jeito de cada um) e há conversas de exemplo na primeira vez (força do Bruno, convite da Ana, papo com o Diego). No `.cloudKit`, `ServerInboxBackend` responde "Mensagens diretas precisam do servidor do GymBros": conversas privadas não podem ir para o banco público do CloudKit.
**Critérios de aceitação:** `InboxTests` (só amigos, bloqueio, denúncia, permissão, resposta ao convite).
**Situação:** Simulado. Depende de servidor próprio (HTTPS, token da sessão, mensagens cifradas em repouso, push pelo APNs).
**Fonte:** `GymBros/Inbox/Inbox.swift` (`TrainInvite`, `mapsURL`), `GymBros/Inbox/InboxMock.swift`, `GymBros/Inbox/ConversationView.swift` (`InviteComposer`, `MessageView`), `GymBros/Friends/FriendsLive.swift`, `GymBros/Friends/MapScreen.swift`, `GymBros/Friends/PublicProfile.swift`

### RF-SOC-35 · Caixa de entrada e notificações sociais
**Descrição:** O sino da tela inicial (com contador de não lidos) abre a caixa de entrada com as abas Notificações e Mensagens.
**Regras:**
- Notificações reúne: reação ou comentário num check-in seu (também vira comentário no check-in), amigo que começou a treinar, pedido de amizade, força recebida, convite e resposta a convite. Também os X1 (`DuelStore.notices`): desafio recebido (com "Aceitar ⚔️"/"Recusar" na linha, depois do aceite dos termos), aceito e resultado; recusado e expirado só para quem desafiou. Tocar numa notificação de X1 abre a tela X1. Separadas em "Novas" e "Anteriores"; abrir a aba marca como visto. Força, convite e pedido de amizade têm botões na própria linha (devolver força, "Bora!"/"Hoje não", aceitar/recusar).
- O contador soma mensagens não lidas por conversa e notificações novas; força e convites contam uma vez só (nas mensagens).
- Cada novidade vira notificação do iOS uma vez, se o tópico estiver ligado e nada estiver pausado. A primeira busca da conta só marca o histórico; itens com mais de 6 h não tocam; a conversa aberta na tela não gera notificação nem banner.
- Ações na notificação: "Responder" (texto) nas mensagens, "Mandar força de volta" na força, "Bora!"/"Hoje não" no convite. Tocar abre a caixa de entrada na conversa ou na aba Notificações.
- Busca a cada 45 s com o app aberto, a cada 15 s com a caixa aberta e a cada 3 s dentro de uma conversa (com servidor, viria por push). Cada busca também atualiza os X1 (`InboxStore.loadDuels`). A recusa de um X1 não tem data no servidor: vale a primeira vez que o aparelho a viu (`inboxFirstSeen`, que vai com a conta).
- Textos das notificações de X1: "{nome} te desafiou para um X1 ⚔️" ("X1 de {métrica} · 24 h para aceitar…"), "{nome} aceitou seu X1 ⚔️", "{nome} recusou seu X1", "Seu X1 com {nome} expirou" e "X1 encerrado · X1 de {métrica}" com o resultado ("Você venceu Bruno no X1 · 3 a 1 treinos").
**Critérios de aceitação:** `InboxTests` (primeira busca não toca, nada duas vezes, tópico desligado, pausa, conversa aberta, itens antigos, não lidos, eventos de X1 conforme quem desafiou, X1 notifica uma vez e respeita o tópico).
**Situação:** Simulado (notificações locais).
**Fonte:** `GymBros/Inbox/Inbox.swift` (`InboxStore`, `events(from:)`, `answerDuel`), `GymBros/Inbox/InboxView.swift`, `GymBros/Duels/DuelStore.swift` (`notices`), `GymBros/Inbox/NotificationPrefs.swift` (`SocialNotifier`), `GymBros/Services/Location.swift` (`NotificationRouter`), `GymBros/Bros/HomeView.swift`

### RF-SOC-36 · Preferências de notificação
**Descrição:** Ajustes → Notificações liga e desliga cada tipo: mensagens diretas, força recebida, convites, X1, amigo começou a treinar, reações e comentários, pedidos de amizade; e, no grupo Treino, lembrete para treinar (horário e só em dias de rotina), resumo da semana, fim do descanso e chegada no lugar de treino.
**Regras:**
- O tópico "X1" (`notify.duels`, "Desafios, respostas e resultado dos seus X1") controla desafios, respostas e resultados.
- Tópicos sociais começam ligados (`notify.<tópico>`). "Pausar todas" (`notify.paused`) silencia tudo, inclusive lembretes, resumo, descanso e chegada; o que chega continua na caixa de entrada.
- Sem permissão do iOS, a tela mostra "Ativar notificações" (pede a permissão) ou, se negada, "Abrir Ajustes do iPhone". Ligar um tópico pede a permissão se ela ainda não foi pedida.
- As preferências e o estado de leitura vão com a conta (`AccountData.userKeys`) e saem do aparelho ao sair.
**Critérios de aceitação:** `InboxTests.testTopicsStartOnAndCount`, `testTopicOffAndPauseSilence`.
**Situação:** Roda no aparelho. Com servidor, as mesmas chaves filtram o push.
**Fonte:** `GymBros/App/SettingsPages.swift` (`NotificationSettingsPage`), `GymBros/Inbox/NotificationPrefs.swift`, `GymBros/App/App.swift`, `GymBros/Train/LiveWorkout.swift`

---


### RF-SOC-40 · Clube ou desafio, treinos que valem e regras novas de pontuação
**Descrição:** Cada liga deve ser um clube (sem fim) ou um desafio (com início e fim) e ter regras de quais treinos e quanto valem.
**Regras:**
- Clube não tem data de fim; desafio sempre tem. O tipo vem do período (`League.format`), então ligas antigas viram clube ou desafio sem migração.
- "Treinos que valem": todos, só os selecionados ou todos exceto os selecionados, pelos ~80 tipos do catálogo. Liga que não aceita o treino aparece bloqueada em "Postar em", com o motivo.
- Modos novos: "Dias ativos" (só o primeiro check-in de cada pessoa em cada dia vale 1) e "Por atividade" (tabela do dono: cada linha vale para tipos ou seções do catálogo, por vez ou por quantidade, a cada X min, km ou kcal, e pode tirar pontos; treino fora da tabela vale 0; vale a linha mais específica).
- Limite de pontos: teto por dia, semana, mês e total, por pessoa e por time; o que passa do teto não conta (o corte cai nos check-ins mais novos).
- Metas no lugar do ranking: meta por pessoa e por time com barra de progresso; "Esconder o ranking" deixa só as metas.
- Início da semana do ranking semanal escolhido pelo dono.
- As regras ficam em `League.settingsRaw` (`LeagueSettings` em JSON; campo novo entra sem mudar o banco) e sobem com a liga (`LeagueDraft.settings`).
**Critérios de aceitação:** dois check-ins da mesma pessoa no mesmo dia valem 1 em "Dias ativos"; com teto de 90 min por dia, 60 + 60 min contam 90.
**Situação:** Local, igual em todos os aparelhos pelas regras da liga.
**Fonte:** `GymBros/Leagues/LeagueRules.swift`, `GymBros/Leagues/LeagueRulesViews.swift`, `GymBros/Leagues/Leagues.swift` (`LeagueBoard.feed`), `GymBrosTests/LeagueRulesTests.swift`

### RF-SOC-41 · Verificação do check-in
**Descrição:** O dono deve escolher como os check-ins da liga são verificados.
**Regras:**
- Presets: Desligada (ligas antigas), Padrão (liga nova: foto ou treino gravado por aparelho; câmera e galeria; qualquer data), Bro-verificação (foto da galeria só com hora verificada; só treino de hoje) e Personalizar.
- Regras do personalizado: foto obrigatória (sempre, dispensada com aparelho, opcional), foto da galeria (liberada, só verificada, proibida), horário (livre, mesmo dia, exato), retroativo (só hoje, 1, 7, 30 dias ou qualquer), aparelho obrigatório e local obrigatório.
- Hora verificada: a do treino gravado por aparelho (Apple Saúde, Apple Watch, GPS do app), a da foto da galeria (EXIF `DateTimeOriginal`, lida do arquivo original antes de reduzir) ou, na câmera do app, a do post. "Exato" aceita de 30 min antes do início a 1 h depois do fim.
- Em "Postar em", liga com problema aparece bloqueada com o motivo e o que fazer ("Para postar aqui: adicione uma foto"); trocar a foto ou o treino libera de novo. `postCheckIns` não posta onde as regras barram.
- "Tirar foto" abre a câmera do app (com a pose do dia, quando alguma liga cobra). A prova vai junto do check-in (`LeagueCheckIn.proofRaw`: origem e hora da foto, se tem local, aparelho, pose).
**Critérios de aceitação:** no Padrão, check-in sem foto e sem aparelho é barrado; na Bro-verificação, foto da galeria de ontem é barrada.
**Situação:** Local; o servidor vai precisar conferir as mesmas regras (docs/servidor-real.md).
**Fonte:** `GymBros/Leagues/LeagueRules.swift` (`CheckInVerification`), `GymBros/Leagues/CheckInProof.swift`, `GymBros/Leagues/LeaguesView.swift` (`LeaguePostSection`, `postCheckIns`)

### RF-SOC-42 · Revisão do dono e pose do dia
**Descrição:** O dono deve poder aprovar cada check-in antes de pontuar e cobrar a pose do dia.
**Regras:**
- Com "Revisar check-ins", check-in de outra pessoa feito depois de ligar fica "em revisão": aparece no feed sem pontuar e sem contar como check-in. O do dono (e o de um moderador) entra aprovado.
- "N check-ins para revisar" abre a fila com a prova de cada um: Aprovar pontua; Negar (com confirmação) tira da liga. As decisões ficam em `CheckInReview` (SchemaV4).
- Pose do dia: uma pose sorteada por dia (igual em todos os aparelhos), mostrada na câmera do app e no formulário ("Sem a pose do dia na foto, o check-in não pontua"); fica gravada no check-in e aparece sobre a foto. Quem fiscaliza é o dono, negando.
**Critério de aceitação:** um check-in negado some do feed e do ranking; aprovado, pontua.
**Fonte:** `GymBros/Leagues/LeagueReviewViews.swift`, `GymBros/Leagues/LeagueRules.swift` (`DailyPose`)

### RF-SOC-43 · Campeões do clube, fim do desafio e reiniciar
**Descrição:** Clubes devem guardar o campeão de cada semana, mês e ano; desafios, a classificação final.
**Regras:**
- Campeões de cada período encerrado, derivados do feed (empate no primeiro lugar divide o título), em "Campeões" (semana, mês, ano; 6 mais recentes e "Ver todos"). O ranking mostra as vitórias de cada um e o perfil mostra "Títulos nos clubes".
- Desafio encerrado mostra "Classificação final", os parabéns ("por dividirem o primeiro lugar" no empate), o resumo ("{total} em {dias} dias, somados por {n} bros") e uma arte 9:16 para compartilhar.
- "Reiniciar desafio" (dono, desafio encerrado): nova temporada começando hoje com as mesmas pessoas, regras, times e duração; a anterior fica guardada.
**Fonte:** `GymBros/Leagues/LeagueWinners.swift`

### RF-SOC-44 · Moderação, pedidos de entrada e prévia
**Descrição:** O dono deve moderar a liga com ajuda de moderadores.
**Regras:**
- Tocando em alguém no ranking, dono e moderadores têm "Ver perfil", "Remover da liga" e, só o dono, "Tornar/Tirar moderador" e "Banir da liga" (não volta nem pelo código; desbanir em Editar liga). Quem sai ou é banido some do ranking, do feed e do mural.
- "Novos membros precisam de aprovação": entrar pelo código manda um pedido ("Esperando aprovação" na lista de ligas, com "Cancelar"); o dono vê "Pedidos para entrar" e aceita ou ignora. A liga entra no aparelho quando o pedido é aceito.
- Antes de entrar, a prévia mostra tipo, pontuação, treinos que valem, verificação, revisão, pose, limites e se precisa de aprovação.
- O dono que sai de uma liga com outras pessoas escolhe quem fica de dono (sem escolha, sorteia, dando preferência a moderadores).
- As decisões ficam nas regras da liga e sobem com ela.
**Situação:** A liga de exemplo simula dois pedidos (Paula e Téo). Pedidos e troca de dono reais dependem de servidor (`requestJoin`, `isApproved`, `transfer`).
**Fonte:** `GymBros/Leagues/LeagueModerationViews.swift`, `GymBros/Leagues/LeagueRemote.swift` (`RemoteLeague.applying`)

### RF-SOC-45 · Notificações de cada liga
**Descrição:** Cada liga deve ter as próprias preferências de notificação.
**Regras:**
- Mural (tudo, quando me marcam com @usuário ou @nome, nada), check-ins dos outros (desligado por padrão), reações e comentários nos seus check-ins, campeões e moderação (pedidos, check-ins para revisar, check-in seu removido). Valem para todas as temporadas da liga.
- Os eventos entram na aba Notificações e no tópico "Ligas" de Ajustes → Notificações.
**Fonte:** `GymBros/Leagues/LeagueNotifications.swift`, `GymBros/Inbox/Inbox.swift` (`leagueEvents`)

### RF-SOC-46 · Check-in com várias atividades
**Descrição:** Atividades do mesmo dia devem poder ir juntas num check-in.
**Regras:**
- Em "Já registrada", tocar em mais de uma atividade do mesmo dia junta todas; de outro dia, recomeça a escolha. A primeira é a principal.
- O check-in soma minutos e pontos de todas (`CheckInProof.grouped` e `groupedParts`, que sobem para os outros aparelhos pontuarem igual).
**Fonte:** `GymBros/Leagues/CheckInProof.swift` (`ScorePart`), `GymBros/Leagues/LeaguesView.swift` (`CheckInForm`)

### RF-SOC-47 · Deck dos Bros
**Descrição:** O app deve mostrar, um por vez, os check-ins dos outros que você ainda não viu.
**Regras:**
- Check-ins dos últimos 3 dias das suas ligas, do mais antigo ao mais novo; um leque com até 3 bros abre o deck ("Novos dos bros" na lista de ligas, "Novos em {liga}" dentro dela).
- Arrastar para o lado passa; toque duplo manda 💪; a barra tem 👍 ❤️‍🔥 💪 🥚. "Responder" escolhe entre comentar no check-in (todo mundo da liga vê) e mensagem direta (só vocês dois; só entre amigos). No fim, "Ver de novo".
- Visto fica em `deck.seen` (vai com a conta).
**Fonte:** `GymBros/Friends/SocialExtras.swift` (`BroDeck`, `BroDeckView`, `DeckPeek`)

### RF-SOC-48 · Privacidade por amigo e conversa
**Descrição:** O usuário deve controlar o que cada amigo vê e recebe.
**Regras:**
- No perfil do amigo: "Esconder meus treinos de {nome}" (o perfil público dele mostra você sem posts nem números; o que você posta numa liga em comum continua lá) e "Silenciar" (as mensagens e eventos chegam, mas não tocam).
- Na conversa: "Arquivar conversa" (some da lista até chegar mensagem nova; "Arquivadas" na caixa de entrada) e "Limpar conversa" (só do seu lado). Segurar uma mensagem reage (👍 ❤️‍🔥 💪 😂); a reação aparece embaixo do balão e notifica no tópico de reações.
**Situação:** Local; com CloudKit, quem foi escondido fica em `hiddenFrom` no perfil público (o app de quem foi escondido respeita, mas o campo é legível).
**Fonte:** `GymBros/Friends/SocialExtras.swift` (`FriendPrefs`), `GymBros/Inbox/Inbox.swift`, `GymBros/Inbox/ConversationView.swift`

### RF-SOC-49 · QR do código de amigo
**Descrição:** Amigos lado a lado devem poder se adicionar por QR.
**Regras:**
- "QR do código" mostra o QR de `gymbros://amigo/{código}` e lê o QR de outra pessoa pela câmera; ler adiciona o amigo. O link também abre o app e adiciona.
**Fonte:** `GymBros/Friends/SocialExtras.swift` (`FriendQR`, `FriendQRView`), `GymBros/App/App.swift` (`onOpenURL`)

### RF-SOC-50 · Widget "Último treino dos bros", "Vem aí" e Pro
**Descrição:** O app deve ter o widget do último check-in das ligas, uma lista do que vem por aí e a página do Pro.
**Regras:**
- Widget (pequeno e médio): o check-in mais recente das suas ligas, com a foto (só a sua, por enquanto) ou o bro, quem, quando e a liga. Atualiza ao abrir o app e as ligas.
- "Vem aí" (Ajustes → GymBros): recursos que ainda não existem, com "Quero!" e "Não pra mim" (`featureFeedback`).
- GymBros Pro: ligas ilimitadas (sem Pro, 2 criadas), limites de pontuação, moderadores, exportar a liga em CSV, recordes e constância e retrospectiva. Assinatura por StoreKit 2; enquanto o app não estiver na App Store (`ProStore.enforced = false`), tudo fica liberado.
- Exportar dados (dono e moderadores): CSV com data, pessoa, título, atividade, minutos, pontos, foto e situação.
**Fonte:** `GymBrosWidget/BrosWidget.swift`, `GymBros/Leagues/BrosWidgetFeed.swift`, `GymBros/App/ProAndComingSoon.swift`, `GymBros/Leagues/LeagueModerationViews.swift` (`LeagueExport`)


### RF-SOC-51 · Várias fotos no check-in e fotos no mural
**Descrição:** O check-in deve aceitar até 5 fotos e o mural, recados com foto.
**Regras:**
- Depois da primeira foto, a faixa de miniaturas aceita mais 4 (câmera do app ou galeria, várias de uma vez); tirar a principal sobe a próxima. As fotos a mais ficam em `LeagueCheckIn.extraPhotosData` (SchemaV5) e vão com a conta.
- O detalhe passa as fotos de lado; a linha do tempo mostra "+N".
- Mural: recado com foto (texto opcional) e a aba "Mídia" com as fotos do mural e dos check-ins da liga (`LeagueMessage.photo`, SchemaV5).
**Situação:** Local; as fotos a mais e as do mural sobem quando houver servidor (hoje só a principal tem campo no CloudKit).
**Fonte:** `GymBros/Leagues/LeaguesView.swift` (`extraStrip`), `GymBros/Leagues/LeagueMural.swift`

### RF-SOC-52 · Rotinas públicas
**Descrição:** O usuário deve poder publicar rotinas e usar as dos outros.
**Regras:**
- Em Treinar → Minhas rotinas → "Rotinas públicas": ordenar por mais salvas, mais curtidas, novas ou dos amigos; cada rotina mostra arte (o primeiro exercício), autor, exercícios, séries, curtidas e cópias salvas.
- No detalhe: "Curtir" e "Salvar cópia" (vira uma rotina sua, sem dias fixos). O menu de uma rotina sua tem "Publicar rotina" e "Tirar das rotinas públicas"; a lista mostra "pública".
- A rotina mostra os seus números com ela: última vez, quantas vezes, tempo médio e as últimas 8 semanas.
**Situação:** Simulado (`MockRoutinesBackend`, com rotinas dos participantes de exemplo montadas dos modelos prontos); contrato `RoutinesBackend` para o servidor.
**Fonte:** `GymBros/Train/PublicRoutines.swift`

### RF-SOC-53 · Ranking dos bros e feed unificado
**Descrição:** O app deve comparar você com os amigos sem liga e juntar todos os check-ins num feed.
**Regras:**
- Ranking dos bros: XP, treinos, dias ativos ou minutos, na semana, no mês ou sempre, pelo que cada um postou no perfil (o que os amigos veem).
- Feed: pílulas Todos, Amigos e cada liga (a escolha fica salva); o mesmo treino postado em várias ligas aparece uma vez, com "Em N lugares".
**Fonte:** `GymBros/Friends/FriendsFeed.swift`

### RF-SOC-54 · Visita verificada, "Você diz" e treino do dia
**Descrição:** As ligas devem aceitar mais formas de prova e de pontuação.
**Regras:**
- Visita verificada: se a localização registrou uma visita numa academia salva durante o treino, o check-in leva "📍 Visita verificada na {academia}". Vale como local, como hora verificada e, na verificação Padrão, dispensa a foto.
- Modo "Você diz": cada pessoa informa de 0 a 100 pontos por check-in (em "Quanto vale", no formulário).
- Treino do dia (dono e moderadores): título, exercícios copiados de uma rotina e texto livre; quem abre a liga no dia vê o card e começa o treino com um toque.
- Desafios dentro do clube: "Criar desafio no clube" já vem com as regras, os times e o tipo de liga do clube; a seção "Desafios do clube" lista os desafios dele.
**Fonte:** `GymBros/Leagues/LeagueRules.swift` (`DailyWorkout`, `PostSubject.gymVisit`), `GymBros/Leagues/LeagueModerationViews.swift` (`ClubChallengesSection`, `DailyWorkoutEditor`), `GymBros/Services/Location.swift` (`visit`)

### RF-SOC-55 · Apple Saúde: origem e postar sozinho
**Descrição:** Treinos importados devem mostrar de onde vieram e poder virar check-in sozinhos.
**Regras:**
- O detalhe da atividade mostra "Gravado no {aparelho ou app}".
- "Postar automaticamente" (Ajustes → Apple Saúde): os treinos novos viram check-in no perfil e nas ligas em andamento que aceitam o treino; vários do mesmo dia entram num check-in só. Do Saúde, o post leva só tipo, data e duração.
**Fonte:** `GymBros/Leagues/BrosWidgetFeed.swift` (`HealthAutoPost`), `GymBros/App/SettingsPages.swift`

### RF-SOC-56 · Força pela notificação, pergunta inicial e novidades
**Descrição:** O app deve encurtar caminhos no começo e nas notificações.
**Regras:**
- A notificação de amigo que começou a treinar tem o botão "Mandar força 💪".
- Depois do tutorial, quem ainda não tem atividades nem ligas responde "O que você quer fazer aqui?" (criar uma liga, entrar com código ou só acompanhar os treinos); as duas primeiras abrem a tela da liga.
- A cada versão com novidades, quem já usava o app vê "Novidades no GymBros" uma vez.
**Fonte:** `GymBros/Onboarding/IntentAndWhatsNew.swift`, `GymBros/Inbox/NotificationPrefs.swift` (`forceCategory`)


## Comportamentos ambíguos ou possíveis bugs

Os itens corrigidos desde a primeira versão (meia foto zerando o modo Treinos, backup sem foto/lugar/capa, números do perfil público, texto da escolha de time, times por posição, placar sem unidade, comentários que sobravam ao sair da liga, "Recomeçar jornada", visitas de backups antigos, saída fechando a visita errada, ligas futuras em "Postar em", convite de liga com participantes de exemplo, comentários sem autor, `CheckInEditView` sem uso, trava de 4 caracteres, textos de "Mandar força"/"Treinar junto" e a diferença no modo Calorias entre o Saúde e a estimativa) saíram desta lista. Continua:

1. **Pontos da liga e posts do perfil sem teto diário:** o modo Pontos e o "+XP" dos posts usam o XP bruto da atividade (`Game.xp`), não o XP com os limites diários do bro (RF-JOG-03).
2. ~~Atividade manual tratada como importada do Saúde~~: corrigido, `isFromHealth` olha só o `healthUUID`.
3. ~~X1 sem rastro na conta~~: corrigido, `duelMonsters` está em `AccountData.userKeys` (vai com a conta e sai do aparelho ao sair).
4. ~~Excluir conta no `.mock` não apaga os X1~~: corrigido, `MockAuthBackend.deleteAccount` apaga `mockDuels`.
5. ~~Divisão de atributos fica no aparelho ao sair~~: corrigido, `wipeAll` zera `activitySplits`.
6. **X1 sem permissão da role:** desafiar e responder passam pelo aceite dos termos, mas `DuelStore` não consulta o `AccessStore` (não existe permissão de X1). Uma conta desativada (sem roles) continua desafiando. Ver `docs/rbac.md`.
7. ~~Rodada suíça e fuso horário~~: corrigido, o dia da rodada usa o fuso de Brasília em qualquer aparelho.
8. ~~Valor do X1 usa dados do Saúde e iria para o iCloud~~: corrigido, o valor usa só os dados publicáveis (`publishableEffort`, `publishableMeters`, `publishableKcal`). No CloudKit, os registros `Duel` só valem quando criados pela própria pessoa.
9. ~~Convite leva a localização da academia sem aviso~~: as coordenadas são necessárias e agora estão na política (Localização) e nos termos (O que você publica), versão 2, com novo aceite.
