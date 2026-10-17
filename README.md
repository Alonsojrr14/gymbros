# GymBros

App de iPhone (SwiftUI + SwiftData, iOS 17) em que seus treinos chocam e evoluem um bro.

- Ao começar você ganha um **ovo**, que choca com 60 XP de atividade.
- Cada atividade (musculação, corrida, crossfit, vôlei…) rende XP por **duração × MET da atividade × esforço (1–10)** e soma em quatro atributos: **Força, Resistência, Agilidade e Técnica**.
- Estágios: Ovo → Bebê (60 XP) → Rookie (300) → Champion (1200) → Ultimate (3600).
  Em Champion e Ultimate, o atributo mais treinado desde a última evolução decide o galho.
- Anti-farm: no máximo 240 min por atividade; acima de 150 XP no dia o ganho cai para 1/3, com teto de 300 XP/dia.
- Tudo é derivado do histórico (`GymMonsters/Game.swift`): apagar ou editar uma atividade recalcula a evolução.
- Os dados ficam só no aparelho, sem conta e sem servidor.

## Musculação guiada

- Rotinas por dia da semana (ou modelos prontos: ABC, Full body, Superior/Inferior, Em casa) sobre uma biblioteca de ~80 exercícios em português.
- Treino guiado: cargas sugeridas a partir do histórico, timer de descanso com aviso em segundo plano, tela sempre acesa.
- Progressão (`GymMonsters/Training.swift`): completou todas as séries → +2,5 kg (+5 kg em pernas/costas); 3 treinos seguidos sem completar → deload de 10 %. Peso do corpo progride em reps, isometria em segundos.
- Recordes de carga e 1RM estimado (Epley, até 12 reps), gráfico por exercício.
- Biblioteca com fotos animadas (posição inicial/final), instruções em português e músculos trabalhados; exercícios personalizados.
- Peso do corpo e isometria aceitam carga extra (cinto de peso, colete); com carga, a progressão volta a ser por peso.
- Mapa muscular (frente e costas): por exercício, por rotina, ao concluir o treino e por período (7/30 dias/tudo), com a lista do que ficou sem treino.
- Concluir um treino gera uma atividade de musculação, que dá XP ao bro.

## Design system

O app não usa controles padrão do iOS: telas, cabeçalhos, barra de abas, botões, abas segmentadas, chaves, steppers, seletor de esforço, data/hora, campos, bottom sheets de ações/confirmação e diálogos ficam em `GymMonsters/DesignSystem.swift` (prefixo `GM`). Só continuam do sistema o teclado, o seletor de fotos, a tela de compartilhar, o seletor de arquivos e os pedidos de permissão.

## Ligas

- Inspiradas no GymRats: cada liga é um ranking contínuo de check-ins de qualquer atividade, com ranking da liga toda, da semana e do mês, e feed com foto.
- Pontuação (`GymMonsters/Leagues.swift`): pontos (XP da atividade), treinos, minutos, distância (GPS do app ou Apple Saúde) ou calorias (do Saúde ou estimadas). No modo pontos, cada liga define um peso de 0× a 3× por atributo (ex.: Resistência 2× favorece cardio; 0× tira o atributo da conta).
- Desempate escolhido na liga: quem chegou antes à pontuação, maior sequência de dias seguidos ou mais check-ins. O ranking mostra quando a posição foi decidida no desempate.
- Foto do treino: opcional, sem foto vale metade, ou obrigatória (sem foto não pontua). O formulário de check-in avisa quando falta a foto.
- Times: o placar do time é a soma dos membros, e cada time tem um bro que cresce com a média de XP dos membros e evolui pelo atributo que o time mais treina. Você escolhe o time tocando nele no ranking.
- Mural: recados da galera da liga, cada um com o seu bro.
- Amigos (botão na tela inicial, `GymMonsters/Friends.swift`): seu código de amigo para compartilhar, adicionar por código, pedidos recebidos e sugestões de quem está nas suas ligas e ainda não é seu amigo. Mesmo esquema das ligas: `FriendsBackend` com `MockFriendsBackend` simulado; quem deixa de ser amigo some do mapa.
- Perfil do amigo (toque na lista de amigos, `GymMonsters/PublicProfile.swift`): foto, nome, @usuário, bio, se está treinando agora, e o mesmo card público da prévia do seu perfil (bro principal, números e conquistas, respeitando o que a pessoa escondeu), ligas em comum e posts em calendário (toque no dia para ver os posts). Vem de `FriendsBackend.profile`.
- Seu perfil: a aba Público é exatamente o que os amigos veem (card público e posts em calendário); a aba Privado tem seus números, recordes, estatísticas, metas, peso e o calendário de todas as atividades. Nome, @usuário, bio e o que aparece para os outros ficam em "Editar perfil".
- Check-in em várias ligas de uma vez: ao registrar atividade, ao concluir treino guiado ou pelo botão da liga (nova atividade ou uma já registrada, inclusive do Saúde).
- Coleção de bros (`GymMonsters/Monsters.swift`): ao entrar numa liga você escolhe quem te representa, um bro seu ou um ovo novo adotado na hora. Os check-ins da liga dão XP só para ele; atividades fora de ligas vão para o bro principal (tela inicial e widgets), que pode ser trocado em "Meus bros".
- Sem servidor ainda, mas o contrato já existe (`GymMonsters/LeagueRemote.swift`): `LeagueBackend` busca participantes, check-ins, times e mural (tipos `Remote*`, Codable, no formato da API) e envia seus recados. Hoje quem responde é o `MockLeagueBackend`, com dados simulados e determinísticos; para ligar um servidor, basta implementar o protocolo e trocar `LeagueRemoteStore.shared.backend`. Seus recados ficam no aparelho como caixa de saída (`LeagueMessage.syncedAt`). Os seus check-ins ainda não têm envio: é o próximo passo quando houver API. A "Liga dos Bros" (código `AMIGOS`) tem 8 participantes simulados divididos em dois times (Gui, Lia e Rafa ainda não são seus amigos).

## Biblioteca e CrossFit

- ~230 exercícios: 80 embutidos (com fotos no app) + 150 do free-exercise-db (domínio público), com fotos carregadas da internet e guardadas em cache (`GymMonsters/ExerciseExtra.swift`). Instruções em inglês traduzidas no próprio iPhone (iOS 18+). Botão "Ver vídeo" abre a busca no YouTube.
- CrossFit: 42 movimentos (olímpicos, ginásticos, metcon) e modo WOD (`GymMonsters/Wod.swift`) com benchmarks (Fran, Grace, Cindy, Helen, Murph, DT…), cronômetro For Time / AMRAP / EMOM / Tabata, resultados com RX e recorde por WOD. Cada WOD vira atividade de crossfit.

## Localização

- Aba Mapa (`GymMonsters/MapScreen.swift`): mapa com academia e percursos, status (na academia ou a que distância), automações, frequência (visitas no mês e tempo médio) e atividades ao ar livre.
- Lugares de treino (`GymMonsters/Location.swift`): histórico de academias. Ao começar musculação ou WOD, o app identifica o lugar salvo em que você está ou pergunta (lugares salvos por perto, academias reais sugeridas pelo mapa da Apple, novo lugar, ou sem local). Ao chegar num lugar salvo, notificação e oferta de começar o treino do dia; ao sair, o treino daquele lugar (com mais de 10 min) é encerrado e salvo. Usa `CLMonitor` (até 20 lugares), que acorda o app em segundo plano. Atividades e check-ins guardam o lugar.
- Corrida, caminhada e bike com GPS (`GymMonsters/Route.swift`): percurso no mapa, distância, tempo e ritmo, com a tela bloqueada; percurso salvo e visível no histórico.
- Tudo fica só no iPhone.

## Apple Saúde e backup

- Treinos do iPhone/Apple Watch são importados ao abrir o app (Ajustes → Apple Saúde; na primeira vez, últimos 14 dias). O tipo vira a atividade correspondente e o esforço é estimado pelas calorias ativas em relação ao esperado para a atividade. Treinos que se sobrepõem a algo já registrado (ex.: treino guiado também gravado no Watch) não contam duas vezes. Opcionalmente, as atividades registradas no app também são gravadas no Saúde (Ajustes → Apple Saúde).
- Backup completo em JSON (Ajustes → Backup): exportar para o Arquivos/iCloud Drive e restaurar.

## Companheiro, conquistas e widget

- Humor do bro (animado, feliz, entediado, triste, exausto) pelos dias sem treinar, sequência e excesso no dia; balão com frases que citam a rotina do dia e músculos esquecidos na semana.
- 28 conquistas (Bros → Conquistas), com aviso ao desbloquear.
- Lembretes locais no horário escolhido, só nos dias sem treino (opcional: só em dias de rotina).
- Widget "Meu bro" (pequeno, médio, grande e tela bloqueada redondo/retangular): muda de pose a cada minuto com transição animada e reage a carinho com um toque (widget interativo).
- Widget "Status do bro" (pequeno, médio e tela bloqueada) com bro, humor, XP e sequência. Os dados chegam pelo App Group `group.com.alonsoalmeida.gymmonsters` (`Shared/WidgetShared.swift`).


## Rodar no iPhone

```sh
xcodebuild -project GymMonsters.xcodeproj -scheme GymMonsters \
  -destination 'id=<UDID>' -derivedDataPath build -allowProvisioningUpdates build
xcrun devicectl device install app --device <UDID> build/Build/Products/Debug-iphoneos/GymMonsters.app
```

A versão web anterior (Next.js + Express) continua no branch `main`.

Requisitos, arquitetura e design system em [docs/](docs/README.md).

Créditos de terceiros em [NOTICE.md](NOTICE.md).
