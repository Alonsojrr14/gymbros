# GymMonsters

App de iPhone (SwiftUI + SwiftData, iOS 17) em que seus treinos chocam e evoluem um monstrinho.

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
- Concluir um treino gera uma atividade de musculação, que dá XP ao monstro.

## Ligas

- Inspiradas no GymRats: cada liga é um ranking contínuo de check-ins de qualquer atividade, com pontuação por pontos (XP da atividade), treinos ou minutos; ranking "desde o início" e "esta semana", e feed com foto.
- Check-in em várias ligas de uma vez: ao registrar atividade, ao concluir treino guiado ou pelo botão da liga (nova atividade ou uma já registrada, inclusive do Saúde).
- Cada liga em que você entra dá um ovo próprio, que cresce só com os check-ins dela; o parceiro continua ganhando XP de tudo.
- Sem servidor ainda: convites são só um código para compartilhar. A "Liga dos Amigos" (código `AMIGOS`) tem 5 participantes simulados (`GymMonsters/Leagues.swift`).

## Apple Saúde e backup

- Treinos do iPhone/Apple Watch são importados ao abrir o app (Ajustes → Apple Saúde; na primeira vez, últimos 14 dias). O tipo vira a atividade correspondente e o esforço é estimado pelas calorias ativas em relação ao esperado para a atividade. Treinos que se sobrepõem a algo já registrado (ex.: treino guiado também gravado no Watch) não contam duas vezes. Só leitura.
- Backup completo em JSON (Ajustes → Backup): exportar para o Arquivos/iCloud Drive e restaurar.

## Companheiro, conquistas e widget

- Humor do monstro (animado, feliz, entediado, triste, exausto) pelos dias sem treinar, sequência e excesso no dia; balão com frases que citam a rotina do dia e músculos esquecidos na semana.
- 22 conquistas (Dex → Conquistas), com aviso ao desbloquear.
- Lembretes locais no horário escolhido, só nos dias sem treino (opcional: só em dias de rotina).
- Widget "Meu monstro" (pequeno, médio, grande e tela bloqueada redondo/retangular): muda de pose a cada minuto com transição animada e reage a carinho com um toque (widget interativo).
- Widget "Status do monstro" (pequeno, médio e tela bloqueada) com monstro, humor, XP e sequência. Os dados chegam pelo App Group `group.com.alonsoalmeida.gymmonsters` (`Shared/WidgetShared.swift`).


## Rodar no iPhone

```sh
xcodebuild -project GymMonsters.xcodeproj -scheme GymMonsters \
  -destination 'id=<UDID>' -derivedDataPath build -allowProvisioningUpdates build
xcrun devicectl device install app --device <UDID> build/Build/Products/Debug-iphoneos/GymMonsters.app
```

A versão web anterior (Next.js + Express) continua no branch `main`.

Créditos de terceiros em [NOTICE.md](NOTICE.md).
