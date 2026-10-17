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

- Inspiradas no GymRats: cada liga é um ranking contínuo de check-ins de qualquer atividade, com pontuação por pontos (XP da atividade), treinos ou minutos; ranking "desde o início" e "esta semana", e feed com foto.
- Check-in em várias ligas de uma vez: ao registrar atividade, ao concluir treino guiado ou pelo botão da liga (nova atividade ou uma já registrada, inclusive do Saúde).
- Coleção de bros (`GymMonsters/Monsters.swift`): ao entrar numa liga você escolhe quem te representa, um bro seu ou um ovo novo adotado na hora. Os check-ins da liga dão XP só para ele; atividades fora de ligas vão para o bro principal (tela inicial e widgets), que pode ser trocado em "Meus bros".
- Sem servidor ainda: convites são só um código para compartilhar. A "Liga dos Amigos" (código `AMIGOS`) tem 5 participantes simulados (`GymMonsters/Leagues.swift`).

## Biblioteca e CrossFit

- ~230 exercícios: 80 embutidos (com fotos no app) + 150 do free-exercise-db (domínio público), com fotos carregadas da internet e guardadas em cache (`GymMonsters/ExerciseExtra.swift`). Instruções em inglês traduzidas no próprio iPhone (iOS 18+). Botão "Ver vídeo" abre a busca no YouTube.
- CrossFit: 42 movimentos (olímpicos, ginásticos, metcon) e modo WOD (`GymMonsters/Wod.swift`) com benchmarks (Fran, Grace, Cindy, Helen, Murph, DT…), cronômetro For Time / AMRAP / EMOM / Tabata, resultados com RX e recorde por WOD. Cada WOD vira atividade de crossfit.

## Localização

- Aba Mapa (`GymMonsters/MapScreen.swift`): mapa com academia e percursos, status (na academia ou a que distância), automações, frequência (visitas no mês e tempo médio) e atividades ao ar livre.
- Minha academia (`GymMonsters/Location.swift`): local e raio no mapa; ao chegar, notificação e oferta de começar o treino do dia; ao sair, o treino em andamento (com mais de 10 min) é encerrado e salvo automaticamente. Usa `CLMonitor`, que acorda o app em segundo plano. Check-ins feitos na academia mostram o local.
- Corrida, caminhada e bike com GPS (`GymMonsters/Route.swift`): percurso no mapa, distância, tempo e ritmo, com a tela bloqueada; percurso salvo e visível no histórico.
- Tudo fica só no iPhone.

## Apple Saúde e backup

- Treinos do iPhone/Apple Watch são importados ao abrir o app (Ajustes → Apple Saúde; na primeira vez, últimos 14 dias). O tipo vira a atividade correspondente e o esforço é estimado pelas calorias ativas em relação ao esperado para a atividade. Treinos que se sobrepõem a algo já registrado (ex.: treino guiado também gravado no Watch) não contam duas vezes. Só leitura.
- Backup completo em JSON (Ajustes → Backup): exportar para o Arquivos/iCloud Drive e restaurar.

## Companheiro, conquistas e widget

- Humor do bro (animado, feliz, entediado, triste, exausto) pelos dias sem treinar, sequência e excesso no dia; balão com frases que citam a rotina do dia e músculos esquecidos na semana.
- 22 conquistas (Dex → Conquistas), com aviso ao desbloquear.
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

Créditos de terceiros em [NOTICE.md](NOTICE.md).
