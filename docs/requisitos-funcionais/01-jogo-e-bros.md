# Requisitos funcionais 01: jogo e bros

**Escopo.** Este documento descreve, por engenharia reversa do código do app GymBros (SwiftUI + SwiftData, iOS 17), o núcleo de jogo: como uma atividade física é registrada e convertida em XP, como o XP se distribui em atributos (tabela da categoria ou divisão calculada para cada treino), como o bro choca, evolui e escolhe galhos (inclusive híbridos) e espécies, o tutorial de primeira utilização, a coleção de bros (Box, principal, apelido, ovo adotado por liga), humor e frases do companheiro, conquistas, BroBook e ficha de cada forma, tela inicial, cena de evolução, histórico/edição/exclusão de atividades, lembretes, widgets, Live Activities, atalhos e compartilhamento em Stories. Ficam fora: regras de pontuação das ligas, treino guiado/progressão de carga, WOD, GPS, Apple Saúde e backup (tratados em outros documentos), exceto onde tocam o jogo. Todos os números citados vêm do código; o estado do jogo é sempre recalculado a partir do histórico de atividades (para XP e evolução, só o log e a divisão de atributos gravada por atividade, RF-JOG-40, são persistidos).

---

## 1. Registro de atividade e XP

### RF-JOG-01: Registrar atividade manualmente
O app deve permitir registrar uma atividade informando tipo, duração, esforço, data/hora e observação opcional.
- **Regras de negócio**
  - O tipo é o tipo exato de treino do Apple Saúde (`WorkoutType`, 80 tipos em 10 seções, como "Academia e funcional", "Esportes com bola" e "Raquete"), gravado em `Activity.healthType`. Grade de 4 colunas com 7 atalhos e "Todas": os atalhos são os tipos mais frequentes nas últimas 60 atividades salvas somados às 10 escolhas recentes (`recentWorkoutTypes`); os 12 tipos clássicos completam a grade. Um tipo escolhido fora dos atalhos ocupa a última casa. "Todas" abre a lista completa por seção, com busca por nome e apelidos ("futsal", "padel", "jiu-jitsu"…).
  - A categoria do jogo (`ActivityKind`, 12: Musculação, Crossfit, Corrida, Caminhada, Bike, Natação, Vôlei, Futebol, Lutas, Dança, Yoga, Outro) sai do tipo (`HealthSync.kind(for:)`; tipo sem categoria vira Outro) e continua decidindo MET, espécie e ligas. Listas e detalhe mostram o nome e o ícone do tipo exato (`typeName`, `typeSymbol`).
  - Valores iniciais: Musculação, 60 min, esforço 6, data/hora atual.
  - Duração por stepper de 5 a 240 min, passo de 5, com atalhos de 30, 45, 60 e 90 min.
  - Esforço de 1 (bem leve) a 10 (no limite). Rótulos: ≤3 Leve, 4–6 Moderado, 7–8 Intenso, 9–10 Máximo.
  - Só em atividade nova, a seção "Treino feito" deixa informar uma rotina, um treino livre ou um WOD feito sem o treino guiado (`ManualWorkoutSection`; regras em `02-treino.md`). Rotina troca o tipo para Musculação; WOD troca para Crossfit e, se o formato tiver duração, ajusta os minutos. Sem observação, o treino informado vira o título.
  - A atividade nova guarda o bro principal do momento (`monsterUUID`) como dono padrão do XP.
  - Por padrão, ficam marcados como destino o perfil e todas as ligas ativas e já iniciadas (ver RF-JOG-18 sobre o efeito no XP). Com sessão, termos aceitos e permissão de publicar (`Terms.canPublish`), "Salvar" exige ao menos um destino (`hasPostDestination`).
  - Ao salvar, a divisão do XP entre atributos é calculada e gravada (RF-JOG-40).
- **Critérios de aceitação**
  - Ao salvar, a atividade aparece no histórico e o feedback háptico de sucesso é emitido.
  - Não é possível escolher duração fora de 5–240 min pelo formulário.
  - Escolher "Basquete" grava a categoria Futebol, e o histórico mostra "Basquete".
- **Fonte:** `GymBros/Activities/LogActivityView.swift`, `GymBros/Activities/WorkoutTypes.swift` (`WorkoutType`, `ActivityTypePicker`, `WorkoutTypeList`), `GymBros/Activities/ManualWorkout.swift`, `GymBros/Services/HealthSync.swift` (`kind(for:)`), `GymBros/Models/Activity.swift`, `GymBros/Leagues/LeaguesView.swift` (`LeaguePostSection`, `hasPostDestination`), `GymBrosTests/WorkoutTypeTests.swift`

### RF-JOG-02: Fórmula de XP por atividade
O app deve calcular o XP bruto de uma atividade por duração × MET do tipo × intensidade do esforço.
- **Regras de negócio**
  - `xp = round(min(max(minutos,0),240) × MET × (0,6 + 0,08 × esforço) / 10)`, com esforço limitado a 1–10 (esforço 5 = fator 1,0; 1 = 0,68; 10 = 1,4).
  - Mínimo de 1 XP se minutos > 0; 0 XP se minutos = 0.
  - MET por tipo: Musculação 5; Crossfit 8; Corrida 9,5; Caminhada 3,5; Bike 7; Natação 8; Vôlei 5; Futebol 7; Lutas 9; Dança 5; Yoga 3; Outro 5.
  - Duração acima de 240 min é truncada em 240 (anti-farm). Máximo bruto por atividade: 319 XP (Corrida, 240 min, esforço 10).
- **Critérios de aceitação**
  - Musculação 60 min esforço 6 rende 32 XP brutos; Corrida 30 min esforço 7 rende 33.
  - Atividade de 300 min rende o mesmo que uma de 240 min.
- **Fonte:** `GymBros/Bros/Game.swift` (`ActivityKind.met`, `Game.xp`, `Game.maxMinutes`)

### RF-JOG-03: Tetos diários (anti-farm)
O app deve reduzir o XP de um mesmo dia acima de um limiar e impor teto diário.
- **Regras de negócio**
  - Atividades são processadas em ordem cronológica; o dia é o dia civil da data da atividade (não da data de registro).
  - Enquanto a soma bruta do dia não passa de 150 XP (`dailySoftCap`), o XP conta inteiro; o excedente conta 1/3 (divisão inteira).
  - O XP ganho no dia não passa de 300 (`dailyHardCap`); são necessários 600 XP brutos para atingi-lo.
  - Os tetos são calculados por bro (cada bro tem seu próprio snapshot).
- **Critérios de aceitação**
  - Com 150 XP brutos já no dia, uma atividade de 60 XP brutos rende 20.
  - Uma atividade retroativa inserida mais cedo no mesmo dia pode reduzir o XP de atividades posteriores desse dia.
  - Na pré-visualização, quando o XP calculado é menor que o bruto (e não há evolução), o app exibe "Você já treinou bastante nesse dia, então rende menos XP. Descanso também faz parte."
- **Fonte:** `GymBros/Bros/Game.swift` (`Game.snapshot`), `GymBros/Activities/LogActivityView.swift`

### RF-JOG-03a: Um treino por horário e até 2 h 30 por treino (anti-farm)
O bro só conta o tempo que um treino ocupa sozinho, e no máximo 2 h 30 por treino.
- **Regras de negócio**
  - Um treino vai do início (data da atividade) até início + duração. Em ordem de início, o trecho de um treino que cai em cima de um treino anterior não conta XP para o bro.
  - Cada treino conta no máximo 150 minutos para o bro (`broMaxMinutes`); o registro continua aceitando até 240.
  - Vale para todo o histórico, inclusive treinos importados do Apple Saúde e do relógio. As ligas seguem com a fórmula de RF-JOG-02 (até 240 min).
  - Os tetos diários de RF-JOG-03 continuam valendo depois desta regra.
  - O registro de atividade não deixa salvar um treino num horário já ocupado e mostra qual treino está lá.
- **Critérios de aceitação**
  - Dois treinos de 60 min começando no mesmo horário rendem o XP de um só.
  - Um treino de 60 min que começa 30 min depois de outro de 60 min rende o XP de 30 min.
  - Caminhada de 4 h rende o XP de 2 h 30 para o bro.
  - Treinos encostados (um termina, o outro começa) contam inteiros.
- **Fonte:** `GymBros/Bros/Game.swift` (`Game.broMinutes`, `Game.snapshot`), `GymBros/Activities/LogActivityView.swift` (`clash`)

### RF-JOG-04: Pré-visualização do ganho
O app deve mostrar, antes de salvar, o XP que a atividade vai render, a divisão por atributo e se ela faz algum bro chocar/evoluir.
- **Regras de negócio**
  - Os donos do XP seguem a mesma regra do RF-JOG-18 aplicada aos destinos marcados no momento (`Roster.owners`): representantes das ligas marcadas; sem liga, o principal (na criação) ou o dono gravado na atividade (na edição).
  - Para cada dono, o cálculo usa o histórico dele, retirando a versão antiga na edição. Com vários donos, o "+N XP" mostrado é o maior entre eles (como nas listas).
  - Exibe "+N XP" e, para cada atributo da divisão, "+round(N × peso)". A divisão é a mesma conta do RF-JOG-40 com o que está na tela (tipo exato, minutos, esforço e o "Treino feito", com descanso de 90 s por série); na edição, sem mudar o tipo exato, os minutos e o esforço, vale a divisão já gravada (trocar Futebol → Basquete recalcula a prévia, como o salvar).
  - Se algum dono sobe de estágio: "Isso vai fazer o ovo chocar! 🥚" / "Isso vai fazer os ovos chocarem! 🥚" (só ovos) ou "Isso vai fazer seu bro evoluir! ✨" / "Isso vai fazer seus bros evoluírem! ✨".
  - A mesma prévia (XP e aviso de evolução) aparece na conclusão do treino guiado, com os destinos marcados lá.
- **Critérios de aceitação**
  - Editar uma atividade não soma o treino duas vezes na pré-visualização.
  - Marcar só uma liga representada por um ovo novo mostra o XP e o choco desse ovo, não do principal.
- **Fonte:** `GymBros/Activities/LogActivityView.swift` (`split`, `preview`, `previewView`), `GymBros/Train/WorkoutView.swift` (`FinishWorkoutView.preview`), `GymBros/Bros/Monsters.swift` (`Roster.owners`)

### RF-JOG-05: Nível do bro
O app deve exibir um nível derivado do XP total.
- **Regras de negócio:** `nível = floor(√(XP/5)) + 1` (0 XP = nível 1; 60 = 4; 300 = 8; 1200 = 16; 3600 = 27).
- **Critérios de aceitação:** o nível não aparece enquanto o bro é ovo na tela inicial.
- **Fonte:** `GymBros/Bros/Game.swift` (`Game.level`), `GymBros/Bros/HomeView.swift`

### RF-JOG-06: Sequência de dias
O app deve calcular a sequência atual e a melhor sequência de dias com atividade.
- **Regras de negócio**
  - Sequência atual: dias consecutivos com ao menos uma atividade terminando hoje ou ontem.
  - Melhor sequência: maior série de dias consecutivos no histórico.
  - Na tela inicial e no widget, sequência e humor usam todas as atividades do jogador (não só as do bro principal).
  - No widget, a sequência zera se a última atividade foi há mais de 1 dia (`liveStreak`).
- **Critérios de aceitação:** treinar ontem e não hoje mantém a sequência; dois dias sem treino zeram.
- **Fonte:** `GymBros/Bros/Game.swift` (`streak`, `bestStreak`), `GymBros/App/App.swift` (`derive`), `Shared/WidgetShared.swift`

---

## 2. Atributos, estágios e evolução

### RF-JOG-07: Distribuição em atributos
O app deve distribuir o XP ganho de cada atividade entre Força, Resistência, Agilidade e Técnica.
- **Regras de negócio**
  - Cada atividade usa a divisão gravada para ela (RF-JOG-40); sem divisão gravada (atividades de antes do cálculo), usa a tabela fixa da categoria (`ActivityRecord.split`).
  - Tabela fixa (pesos somam 1): Musculação F 0,8 / T 0,2; Crossfit F 0,4 / R 0,4 / A 0,2; Corrida R 0,8 / A 0,2; Caminhada R 1; Bike R 0,8 / F 0,2; Natação R 0,6 / T 0,4; Vôlei A 0,6 / T 0,4; Futebol A 0,5 / R 0,5; Lutas A 0,4 / T 0,3 / F 0,3; Dança A 0,5 / T 0,5; Yoga T 1; Outro 0,25 cada.
  - O app mantém atributos da fase (zerados a cada evolução), atributos totais da vida e atributos do choco (os da fase de ovo).
- **Critérios de aceitação:** a tela inicial mostra os atributos da fase; o histórico e o resumo do bro em "Meus bros" mostram os atributos da vida; uma atividade com divisão gravada só de Técnica não soma nada em Força.
- **Fonte:** `GymBros/Bros/Game.swift` (`ActivityKind.weights`, `ActivityRecord.weights`, `ActivityRecord.split`, `Game.snapshot`, `Snapshot`), `GymBros/Models/Activity.swift` (`record`), `GymBrosTests/AttributeSplitTests.swift` (`testGameUsesStoredSplit`)

### RF-JOG-08: Estágios por XP total
O app deve evoluir o bro por limiares de XP total acumulado.
- **Regras de negócio:** Ovo 0 → Bebê 60 → Novato 300 → Atleta 1200 → Lenda 3600. Lenda é a forma final. A data da evolução é a data da atividade que cruzou o limiar.
- **Critérios de aceitação**
  - A barra de progresso vai de 0 a 1 entre o limiar atual e o próximo; na Lenda fica cheia e mostra "forma final".
  - Texto de faltante: "faltam N XP para chocar" (ovo) ou "faltam N XP para evoluir".
  - Apagar ou editar atividades recalcula o estágio, podendo regredir.
- **Fonte:** `GymBros/Bros/Game.swift` (`Stage`, `Snapshot.progress`, `xpToNext`), `GymBros/Bros/HomeView.swift`

### RF-JOG-09: Galho da evolução (atributo dominante)
O app deve escolher a forma de Atleta e Lenda pelo atributo mais treinado desde a última evolução.
- **Regras de negócio**
  - Só Atleta e Lenda têm galho; Bebê e Novato são únicos.
  - Dominante = maior atributo da fase; empate resolvido pela ordem Força → Resistência → Agilidade → Técnica.
  - Ao evoluir, os atributos da fase são zerados; um bro pode mudar de galho entre Atleta e Lenda.
  - Se uma única atividade cruza mais de um limiar, a fase nova ainda está vazia: o galho (e os atributos do choco) usam os atributos da fase anterior.
- **Critérios de aceitação:** com a fase Novato dominada por corrida, o Atleta é o de Resistência; uma atividade que leva do Novato direto à Lenda não nasce sem galho.
- **Fonte:** `GymBros/Bros/Game.swift` (`Game.snapshot`, `Game.branch`, `Game.dominant`), `EVOLUCAO.md`

### RF-JOG-10: Formas híbridas
O app deve gerar uma forma híbrida quando os dois atributos mais treinados da fase estão quase empatados.
- **Regras de negócio**
  - Híbrido quando o 2º atributo ≥ 90% do 1º (`hybridRatio = 0,9`) e o 1º > 0.
  - 6 duplas × 2 estágios = 12 híbridos por espécie; a dupla é sempre ordenada F, R, A, T.
  - Cada híbrido de cada espécie tem nome próprio e único no jogo (96 nomes, nenhum repete outra forma nem leva a espécie no fim). No Coelho (Atleta / Lenda): F+R Crossbro / Hércubro; F+A Golpebro / Titãbro; F+T Arrancobro / Olimpibro; R+A Chuteirabro / Tufãobro; R+T Nadobro / Marébro; A+T Gingabro / Piruetabro. Lista completa no `HIBRIDOS.md`.
  - Sem arte no app, o bro usa a forma normal do atributo dominante.
- **Critérios de aceitação:** atributos da fase F=100 e R=90 geram Crossbro; F=100 e R=89 geram o Atleta de Força.
- **Fonte:** `GymBros/Bros/Game.swift` (`MonsterForm`, `Species.names`, `Species.hybridKeys`), `GymBros/Bros/Monsters.swift` (`resolve`), `HIBRIDOS.md`

### RF-JOG-11: Tendência de forma
O app deve indicar na tela inicial em que forma o bro tende a evoluir.
- **Regras de negócio:** exibe "tende a virar {forma}" somente quando o próximo estágio tem galho e há atributos na fase; a forma considera a espécie e o fallback de arte do híbrido.
- **Critérios de aceitação:** no Bebê não aparece; no Novato com treinos aparece; na Lenda não aparece.
- **Fonte:** `GymBros/Bros/Game.swift` (`Snapshot.nextForm`), `GymBros/Bros/HomeView.swift`

### RF-JOG-40: Divisão de atributos calculada para cada treino
O app deve calcular, ao salvar cada atividade, como o XP dela se divide entre os atributos, a partir do que foi treinado, e gravar essa divisão.
- **Regras de negócio**
  - Calculada uma vez por atividade (`ActivitySplits.stamp`) em todos os caminhos que criam atividade: registro manual e edição, conclusão do treino guiado (inclusive o encerramento automático), WOD, percurso com GPS, check-in de liga com atividade nova e importação do Apple Saúde. Fica gravada por id no `UserDefaults` (`activitySplits`), fora do SwiftData: mudar as regras depois não reescreve atividades antigas; editar uma atividade recalcula a dela.
  - Ponto de partida: a tabela do tipo exato do Apple Saúde quando existe (`AttributeSplit.health`; ex.: basquete A 0,5 / R 0,3 / T 0,2, pilates T 0,6 / F 0,4, escalada F 0,5 / T 0,4 / R 0,1, golfe T 1); senão, a tabela da categoria (RF-JOG-07).
  - Com detalhe do treino ligado à atividade, a divisão vira 25% ponto de partida + 75% detalhe:
    - Treino com séries: média das séries de trabalho feitas (aquecimento fica de fora), cada uma pelo padrão do exercício: técnico (snatch, clean, jerk, HSPU, muscle-up, pistol…) T 0,6 / F 0,25 / A 0,15; pliométrico (saltos, burpee, double-under) A 0,6 / R 0,25 / F 0,15; cardio (esteira, remo, bike, corda) R 0,8 / A 0,2; carregar peso F 0,55 / R 0,45; isometria (exercício por tempo) T 0,5 / R 0,3 / F 0,2; peso do corpo até 10 reps F 0,55 / T 0,3 / R 0,15, acima R 0,5 / F 0,3 / T 0,2; carga livre ou máquina pela faixa de reps (≤5, 6–12, 13–20, >20), indo de Força para Resistência, com Técnica 0,15 no peso livre e 0,05 na máquina/polia/Smith. Descanso de 1 a 45 s leva 25% para Resistência.
    - WOD: 60% movimentos (reconhecidos na lista do WOD ou no texto, `WodMovements.ids`) + 40% formato; sem movimento reconhecido, só o formato. EMOM F 0,4 / T 0,3 / R 0,3; Tabata A 0,5 / R 0,5; AMRAP e For Time com cap de 15 min ou mais R 0,6 / F 0,2 / A 0,2, de até 8 min A 0,4 / F 0,3 / R 0,3, entre os dois (e For Time sem cap) R 0,4 / F 0,3 / A 0,3.
  - Duração e esforço: a partir de 75 min, leva para Resistência min(25%, (minutos − 60) / 240); sem séries nem WOD, até 25 min com esforço ≥ 8 leva 12% para Força (musculação) ou Agilidade (demais); esforço ≤ 3 leva 10% para Técnica (exceto caminhada).
  - Ritmo, com distância ≥ 300 m: corrida com pace abaixo de 4:30/km +25% Agilidade (abaixo de 5:30, +10%) e 15 km ou mais +15% Resistência; caminhada a 6,5 km/h ou mais +10% Agilidade e 12 km ou mais +10% Força; bike a 30 km/h ou mais +15% Agilidade e 60 km ou mais +10% Resistência; natação abaixo de 2:00/100 m +10% Técnica e +10% Agilidade, 2.000 m ou mais +15% Resistência.
  - "Levar X% para um atributo" tira dos outros na proporção de cada um (`shift`). No fim, a divisão soma 1, descarta fatias abaixo de 3%, usa duas casas e o resto do arredondamento vai para o maior (`tidy`).
  - A divisão gravada entra no backup (campo `attributes` de cada atividade); "Recomeçar jornada" apaga todas. Sair ou excluir a conta zera `activitySplits` (`AccountData.wipeAll`), restaurar um backup só troca a divisão depois de salvar o banco, e apagar uma atividade apaga a entrada dela (`deleteActivity`).
  - **Recomendação:** apagar a entrada junto com a atividade e incluir `activitySplits` na limpeza de saída da conta.
- **Critérios de aceitação**
  - Atividade sem detalhe, sem tipo do Saúde, de 50 min e esforço 6 mantém a tabela da categoria.
  - Agachamento 4×3 dá mais de 80% de Força; cadeira flexora 4×20 com 40 s de descanso dá mais Resistência que Força; snatch 4×2 dá mais de 35% de Técnica.
  - Corrida de 5 km em 20 min dá mais de 40% de Agilidade; 18 km em 110 min, mais de 85% de Resistência.
  - AMRAP de 12 min com HSPU, pistol e toes-to-bar dá mais de 25% de Técnica; For Time de 30 min com remo e esteira, mais de 60% de Resistência.
  - Basquete (categoria Futebol) tem Técnica; pilates (categoria Yoga) tem Força.
- **Fonte:** `GymBros/Bros/AttributeSplit.swift` (`AttributeSplit`, `ActivitySplits`), `GymBros/Bros/Game.swift` (`ActivityRecord.split`), `GymBros/Models/Activity.swift` (`record`), `GymBros/Activities/LogActivityView.swift`, `GymBros/Services/Backup.swift`, `GymBros/App/SettingsView.swift`, `GymBrosTests/AttributeSplitTests.swift`

---

## 3. Espécies

### RF-JOG-12: Espécie definida ao chocar
O app deve definir a espécie do bro no momento em que o ovo choca, pelos treinos que o chocaram.
- **Regras de negócio**
  - A espécie sai da **atividade** dos treinos do ovo: a família com mais da metade dos minutos treinados até o choco (`Hatch.majority = 0,5`) define o animal. Minutos, não XP.
  - 8 espécies: Urso e Rato (musculação, crossfit), Lobo (corrida, bike, natação), Cachorro (caminhada, futebol), Esquilo (vôlei), Gato (lutas, dança), Coruja (yoga), Coelho (Outro ou mistura sem atividade principal).
  - Treinos do Apple Saúde usam o tipo exato do treino (`Activity.healthType`); todas as atividades que o iPhone e o Watch gravam têm animal (`Hatch.species(for: HKWorkoutActivityType)`).
  - Família com mais de uma espécie (Urso e Rato): escolha determinística por semente do UUID do bro. Sem espécie pronta, nasce Coelho.
  - Só nasce espécie com as 10 artes no app (`isReady`); hoje todas as 8 estão prontas.
  - Após o choco a espécie é gravada no bro (`speciesID`) e não muda com espécies novas. Se o bro volta a ser ovo (atividades apagadas ou editadas), a espécie gravada é apagada e o próximo choco decide de novo.
  - O ovo é igual para todas as espécies.
- **Critérios de aceitação:** um ovo chocado só com yoga nasce Coruja; musculação 60 min + corrida 40 min nasce Urso ou Rato; corrida 30 min + yoga 30 min nasce Coelho; só "Outro" nasce Coelho; o mesmo bro sempre resolve para a mesma espécie.
- **Fonte:** `GymBros/Bros/Hatch.swift`, `GymBros/Bros/Game.swift` (`Species.hatch`, `Species.all`), `GymBros/Bros/Monsters.swift`, `GymBrosTests/GameTests.swift` (`testHatchFollowsMainActivity`, `testEveryActivityHasAnimal`), `EVOLUCAO.md`

---

## 4. Onboarding

### RF-JOG-13: Primeiro acesso e recebimento do ovo
O app deve, no primeiro acesso, pedir o nome do treinador e entregar um ovo.
- **Regras de negócio**
  - Enquanto `trainerName` estiver vazio, o app mostra o onboarding no lugar da tela principal.
  - Passo 1: "Todo treinador começa com um ovo. Como você se chama?" com campo de nome; botão "Receber meu ovo" desabilitado com nome em branco.
  - Se os termos ainda não foram aceitos, o passo 1 mostra o aceite (`LegalConsent`): uma caixa por documento, "Li e concordo com os Termos de uso" e "Li e concordo com a Política de privacidade", com o nome do documento como link que abre o texto. "Receber meu ovo" só habilita com as duas marcadas, e tocar nele grava o aceite (`Terms.accept()`). Quem já aceitou não vê as caixas.
  - Passo 2: "Este ovo é seu!" com explicação e "Continuar".
  - Passo 3: "Treine ao vivo com os amigos": explica que, durante um treino, os amigos veem no mapa onde você está treinando, a atividade e o exercício atual, e que fora do treino nada é compartilhado; chave "Compartilhar treino ao vivo" ligada por padrão ("Dá para mudar em cada treino, no chip \"Ao vivo\", ou em Mapa > Ajustes."). "Começar a jornada" grava a escolha (`LiveShare.key`) e o nome (sem espaços nas pontas).
  - Ao entrar na tela principal, o app garante um bro inicial (`isStarter`) e o define como principal; ligas sem representante válido passam a ser representadas por ele.
- **Critérios de aceitação:** nome só com espaços não avança; sem marcar os dois documentos não avança; após "Começar a jornada" a tela inicial mostra o ovo com 0 XP; sem mexer na chave do passo 3, o treino ao vivo fica ligado.
- **Fonte:** `GymBros/App/OnboardingView.swift`, `GymBros/App/TermsView.swift` (`LegalConsent`, `Terms`), `GymBros/Friends/LiveShare.swift`, `GymBros/App/App.swift` (`RootView`), `GymBros/Bros/Monsters.swift` (`ensureStarter`)

### RF-JOG-41: Tutorial de primeira utilização
O app deve, depois do nome do treinador, apresentar um tutorial que destaca os elementos reais da interface, um por etapa.
- **Regras de negócio**
  - 10 etapas, nesta ordem (`OnboardingStep.tour`): o bro (Início), "Registrar atividade", aba Treino (só avança quando a aba abre), o treino de hoje (na aba Treino), aba Ligas, aba Mapa, aba Feed, o bro da barra (só avança quando volta ao Início), os atalhos do cabeçalho (Amigos, Bros, caixa de entrada, Ajustes) e "Bora treinar!", sem destaque.
  - Abre sozinho quando a tela principal está livre (sem cena de evolução, BroBook, aviso ou banco recuperado por cima) e sem treino em andamento. O estado é por conta (hash do id da conta na chave `onboardingTour`): não apresentado, em andamento numa etapa (retoma dela na próxima abertura), concluído ou dispensado. Trocar de conta interrompe sem marcar nada.
  - Cada etapa navega até a aba dela, espera 350 ms o layout assentar e até 2 s o elemento aparecer; sem elemento visível, pula a etapa (no sentido em que estava indo) e registra em log o motivo.
  - Um elemento de tela que fica embaixo da barra de abas (com 16 pt de folga acima dela, por causa do bro do centro) não é destacado. Para não perder a etapa, a tela com rolagem (`GMScreen`) rola o primeiro alvo que não é da barra até o centro (`scrollTarget`).
  - Reabrir: Ajustes → grupo "Ajuda" → "Ver tutorial do app" (fecha os Ajustes e começa do início mesmo se concluído ou com treino em andamento).
- **Critérios de aceitação**
  - Com "Registrar atividade" atrás da barra de abas, a etapa só destaca o botão depois de ele rolar para cima da barra; as abas da barra são destacadas normalmente.
  - Ao chegar na etapa "registrar", a tela pede para rolar até o botão; pular o tutorial limpa o pedido.
  - Fechar o app na etapa 4 e abrir de novo retoma na etapa 4.
- **Fonte:** `GymBros/Onboarding/OnboardingStep.swift` (`tour`, `OnboardingTarget.isInTabBar`), `GymBros/Onboarding/OnboardingCoordinator.swift` (`startIfEligible`, `scrollTarget`, `OnboardingPersistence`), `GymBros/Onboarding/SpotlightTarget.swift` (`OnboardingTargetRegistry.spotlight`, `tabBar`, `OnboardingScroll`), `GymBros/Onboarding/SpotlightOverlay.swift`, `GymBros/DesignSystem/GMScreen.swift`, `GymBros/DesignSystem/GMTabBar.swift`, `GymBros/App/SettingsView.swift`, `GymBrosTests/OnboardingTests.swift`

---

## 5. Coleção de bros

### RF-JOG-14: Bro principal
O app deve manter um bro principal, exibido na tela inicial, na barra de abas e nos widgets.
- **Regras de negócio**
  - Principal = o salvo em `mainMonster` se existir; senão o inicial; senão o primeiro.
  - O principal recebe o XP integral de toda atividade (postada ou não). O representante de cada liga marcada recebe 80% (RF-JOG-18).
  - O dono padrão é gravado na atividade ao criá-la; trocar o principal depois não move atividades antigas.
  - A tela principal observa a chave `mainMonster`: trocar o principal atualiza na hora a tela inicial, a barra de abas e o widget.
- **Critérios de aceitação:** em "Meus bros", o botão "Principal" do bro selecionado aparece só para quem não é o principal; depois de tocado, o bro passa a exibir o selo "Principal" no resumo e a estrela na casa da Box.
- **Fonte:** `GymBros/Bros/Monsters.swift` (`MainMonster`, `Roster`, `MyBrosList`), `GymBros/App/App.swift` (`MainView`)

### RF-JOG-15: Apelido
O app deve permitir dar apelido a cada bro.
- **Regras de negócio:** em "Meus bros", o botão "Apelido" do bro selecionado abre o diálogo "Apelido" ("Vazio usa o nome da forma atual."); apelido vazio usa o nome da forma atual; espaços nas pontas são removidos; enquanto ovo, o nome exibido é sempre "Ovo". Com apelido (e fora do ovo), o resumo mostra também o nome da forma. O apelido do principal também é editável em Ajustes.
- **Critérios de aceitação:** apagar o apelido volta a mostrar o nome da forma.
- **Fonte:** `GymBros/Models/Monster.swift` (`displayName`), `GymBros/Bros/Monsters.swift` (`MyBrosList`), `GymBros/App/SettingsView.swift`

### RF-JOG-16: "Meus bros" (Box e resumo do bro)
O app deve mostrar todos os bros numa Box de casas e, embaixo, o resumo do bro selecionado, na aba "Meus bros" da tela Bros (RF-JOG-23).
- **Regras de negócio**
  - Box: cabeçalho "Box" com a contagem ("1 bro", "N bros"); grade de 4 colunas em ordem de criação, sempre com fileiras cheias e no mínimo 12 casas (as vazias, tracejadas, lembram que dá para ter mais). Cada casa mostra o sprite, o nome e "Ovo" ou "Nv N"; estrela no principal; emoji da primeira liga que o bro representa.
  - Começa selecionado o principal; tocar numa casa seleciona o bro (vibração de seleção), com fundo e contorno na cor do atributo do galho.
  - Resumo do selecionado: bro animado, nome com selo "Principal", nome da forma se tiver apelido, "Ovo · N XP para chocar" ou "{Estágio} · Nível N · X XP", barra de progresso na cor do atributo; barras dos 4 atributos da vida relativas ao maior (só se ele já treinou algo); ligas que representa ou "Não representa nenhuma liga"; botões "Principal" (RF-JOG-14), "Apelido" (RF-JOG-15) e "BroBook", que abre a ficha da forma atual dele (RF-JOG-42).
  - Rodapé: o principal aparece na tela inicial e nos widgets e recebe o XP das atividades sem liga; cada liga dá XP só ao bro que representa você nela; ovos novos vêm de entrar numa liga.
- **Critérios de aceitação:** não há ação de apagar bro; com 13 bros a Box tem 16 casas.
- **Fonte:** `GymBros/Bros/Monsters.swift` (`MyBrosList`: `box`, `slot`, `summary`, `attributes`)

### RF-JOG-17: Representante por liga e ovo adotado
O app deve, ao entrar numa liga, pedir quem representa o jogador: um bro existente ou um ovo novo.
- **Regras de negócio:** "Adotar um ovo novo" cria um bro que começa do zero e cresce com 80% do XP dos check-ins dessa liga (RF-JOG-18). Uma liga com representante apagado/ausente passa ao bro inicial.
- **Critérios de aceitação:** escolher o ovo novo adiciona um bro à coleção.
- **Fonte:** `GymBros/Bros/Monsters.swift` (`MonsterChoiceSection`, `representative`, `ensureStarter`)

### RF-JOG-18: Destino do XP de cada atividade
O app deve atribuir o XP de cada atividade aos bros corretos.
- **Regras de negócio**
  - O bro principal da atividade (o dono gravado nela; se ele não existe mais, o inicial) recebe o XP integral (fração 1,0).
  - Cada bro representante das ligas marcadas recebe 80% (`Roster.leagueShare`), uma vez só mesmo em várias ligas; o principal que também representa uma liga recebe só o integral.
  - Se o dono gravado saiu numa troca, o XP dele foi junto e não passa para ninguém daqui.
  - O XP de cada bro é `round(xp × fração)` antes dos tetos diários (RF-JOG-03).
  - Em listas (Histórico, "Últimas atividades", aviso de importação do Saúde, detalhe), o XP mostrado de uma atividade com vários donos é o maior entre eles.
- **Critérios de aceitação:** uma atividade postada numa liga dá o XP integral ao principal e 80% ao representante; a mesma atividade mostra o mesmo XP na tela inicial e no Histórico. Testes: `GameTests.testMainAlwaysGetsXPAndLeagueRepGetsAShare`, `testLeagueShareGivesLessXP`.
- **Fonte:** `GymBros/Bros/Monsters.swift` (`Roster.owners`, `Roster.init`, `xpByActivity`), `GymBros/App/App.swift` (`derive`, `syncHealth`), `GymBrosTests/GameTests.swift` (`testXPOwnersFollowLeagues`)

---

## 6. Humor e companheiro

### RF-JOG-19: Humor do bro
O app deve derivar o humor do bro principal do último treino, da sequência e do XP de hoje.
- **Regras de negócio:** Ovo → "Chocando" 🥚. Sem atividade → Entediado. Treinou hoje: XP de hoje ≥ 300 → Exausto 🥵; sequência ≥ 3 → Animado 🤩; senão Feliz 😊. Último treino há 1 dia → Feliz; 2–3 dias → Entediado 🥱; 4+ → Triste 😢.
  - Visual: saturação 0,35 se triste e 0,7 se entediado (app e widgets).
- **Critérios de aceitação:** sem treinar há 4 dias o bro aparece triste e dessaturado.
- **Fonte:** `Shared/WidgetShared.swift` (`Mood.of`), `GymBros/Bros/HomeView.swift`

### RF-JOG-20: Frases do balão
O app deve exibir uma frase do bro de acordo com o humor e o contexto.
- **Regras de negócio**
  - Uma frase por dia e humor: índice = ordinal do dia na era mod número de opções (não muda a cada redesenho).
  - Ovo: frases diferentes para 0 XP e para XP > 0 (inclui "Faltam N XP para eu sair!").
  - Feliz e sem treino hoje: prioriza a rotina do dia ("Hoje é dia de {rotina}! Vamos?"); depois um músculo esquecido; treinou hoje: frases de parabéns.
  - Músculos esquecidos: dentre quadríceps, costas superiores, peito, deltoides, posteriores, glúteos, bíceps, tríceps, abdômen e panturrilhas, os sem carga nos treinos guiados dos últimos 7 dias; só se houver algum treino guiado no histórico.
  - Entediado/Triste citam os dias sem treino ("Faz N dias…").
- **Critérios de aceitação:** no mesmo dia e humor, reabrir a tela mostra a mesma frase.
- **Fonte:** `GymBros/Bros/Companion.swift` (`Companion`), `GymBros/App/App.swift` (`companionContext`)

---

## 7. Tela inicial

### RF-JOG-21: Tela inicial do bro
O app deve ter uma tela inicial centrada no bro principal.
- **Regras de negócio**
  - Cabeçalho "Olá, {nome}" com a bolinha do perfil, selo de sequência (🔥 N, lido como "N dias seguidos" no VoiceOver) quando > 0, botões Amigos, Bros, caixa de entrada (sino com contador de novas) e Ajustes.
  - Card do bro: balão com emoji do humor, bro animado, nome, estágio · atributo do galho · Nível · humor (os três últimos só fora do ovo), barra e XP. No ovo: "Registre seu primeiro treino para aquecer o ovo." (0 XP) ou "Ele está se mexendo… continue treinando!".
  - Card "Treinos desta fase" (fora do ovo): barras dos 4 atributos proporcionais ao maior.
  - Botão "Registrar atividade", card "X1" (`DuelHomeCard`, regras em RF-SOC-38 de `03-social-e-dados.md`) e card "Últimas atividades" com as 3 mais recentes (toque abre o detalhe), com nome e ícone do tipo exato e o mesmo XP do Histórico (RF-JOG-18).
  - O card "X1" aparece sempre: com desafio esperando resposta ou X1 valendo, mostra até 3 linhas ("Ver mais N" abre a tela X1); sem nenhum, convida a desafiar ("Ninguém no X1 com você agora…"), com atalho para até 4 amigos e o botão "Desafiar alguém". O cabeçalho mostra o retrospecto "NV · NE · ND" quando há X1 encerrado.
  - A barra de abas tem o bro no centro (Início), Treino, Ligas, Mapa e Histórico.
- **Critérios de aceitação:** sem atividades, o card de recentes não aparece.
- **Fonte:** `GymBros/Bros/HomeView.swift`, `GymBros/Duels/DuelViews.swift` (`DuelHomeCard`), `GymBros/App/App.swift`

---

## 8. Cena de evolução

### RF-JOG-22: Animação de choco/evolução
O app deve exibir em tela cheia uma cena quando qualquer bro da coleção sobe de estágio.
- **Regras de negócio**
  - Disparo: a forma atual difere da última vista (`lastFormID`) e tem estágio maior; a forma vista é atualizada sempre.
  - Vários bros evoluindo ao mesmo tempo entram numa fila (uma cena por bro e transição, sem repetir): só o "Continuar" tira a cena da fila e abre a próxima. A cena é apresentada por `gmModal`.
  - 14 alternâncias entre forma antiga e silhueta da nova, intervalo inicial 0,5 s multiplicado por 0,82 a cada passo (mínimo 0,07 s), com háptico; após 0,2 s revela com háptico de sucesso.
  - Textos: "O ovo está chocando…" / "{forma} está evoluindo…" → "O ovo chocou!" / "Evoluiu!", nome, estágio e atributo; brilho de fundo na cor do atributo; botão "Continuar" fecha.
  - Ao chocar, a espécie é gravada no bro.
- **Critérios de aceitação:** regredir de estágio (apagando atividade) não exibe cena; uma atividade postada em duas ligas que faz dois ovos chocarem mostra as duas cenas, uma depois da outra.
- **Fonte:** `GymBros/Bros/EvolutionView.swift`, `GymBros/App/App.swift` (`check`, `EvolutionEvent`)

---

## 9. Tela "Bros": Meus bros, BroBook e Conquistas

### RF-JOG-23: Navegação da tela Bros
O app deve abrir, pelo botão Bros da tela inicial, uma tela modal "Bros" com as abas "Meus bros", "BroBook" e "Conquistas".
- **Regras de negócio**
  - Título fixo "Bros", com voltar; o subtítulo acompanha a aba: "Seu principal e os que te representam nas ligas", "Todas as formas de todas as espécies" e "Marcas que você já bateu e as que faltam".
  - Acima das abas, um card com o bro principal animado dentro de um anel com o progresso do BroBook, "N % do BroBook", "N de M formas", "N de M espécies chocadas" e "N de M conquistas".
- **Fonte:** `GymBros/Bros/DexView.swift` (`hero`, `subtitle`), `GymBros/App/App.swift`

### RF-JOG-24: Descoberta de formas
O app deve registrar como descoberta toda forma alcançada por qualquer bro.
- **Regras de negócio:** o ovo é sempre descoberto; descobertas são cumulativas (não somem ao apagar atividades). Total = ovo + 8 espécies × 112 formas (10 normais, 12 híbridos e 90 Lendas de virada, que entram mesmo sem arte) = 897.
- **Fonte:** `GymBros/App/App.swift` (`check`), `GymBros/Bros/DexView.swift` (`allForms`)

### RF-JOG-25: BroBook por espécie
O app deve exibir a árvore de evolução de cada espécie.
- **Regras de negócio**
  - Seletor horizontal com as espécies prontas (`isReady`, hoje as 8): bebê (silhueta se não descoberto), nome, barra e "vistos/total" (barra dourada com a espécie completa).
  - Cabeçalho da espécie: nome, de onde nasce (ex.: "Nasce quando o ovo choca com musculação ou crossfit (e parecidos no Apple Saúde)"; o Coelho, "com \"Outro\" ou com treinos variados, sem atividade principal"), "vistos/total" e as atividades que a chocam.
  - Árvore: "Começo" (Ovo → Bebê → Novato); "Galhos", um por atributo (Atleta → Lenda); "Formas híbridas" se a espécie tiver alguma arte híbrida, com uma linha por dupla cujo Atleta híbrido tenha arte.
  - Forma não descoberta: silhueta e "???"; cada nó mostra "{Estágio} · N XP" ("início" no ovo); a forma atual do principal fica destacada com o selo "VOCÊ". Tocar num nó abre a ficha da forma (RF-JOG-42).
  - Chip "Revelar todas" / "Revelando" mostra tudo sem contar como descoberta (preferência salva em `dexRevealAll`).
- **Fonte:** `GymBros/Bros/DexView.swift` (`speciesPicker`, `tree`, `node`)

### RF-JOG-26: Conquistas
O app deve avaliar 28 conquistas e exibi-las em grade.
- **Regras de negócio**
  - Atividades: 1, 10, 50, 100; 5 tipos diferentes; uma de ≥120 min; antes das 7h; a partir das 21h; 1 importada do Saúde.
  - Estágio (do bro mais evoluído): chocar, Novato, Atleta, Lenda; 2 bros na Lenda.
  - Melhor sequência: 3, 7, 30 dias.
  - Treino guiado: 10 treinos; 1 e 25 recordes; 10 t e 100 t de volume (peso × reps das séries feitas); todos os músculos do mapa numa janela de 7 dias.
  - Espécies chocadas: 2, 4 e todas as do catálogo (hoje 8); BroBook: 25 formas e todas. Como toda espécie nasce de alguma atividade e o Coelho nasce de "Outro" ou de treinos variados (RF-JOG-12), todas são alcançáveis.
  - Grade ordenada por desbloqueadas e depois por progresso; bloqueadas com barra de progresso e opacidade 0,7.
  - Ao desbloquear, banner "Conquista: {título}" ou "N conquistas novas!" por 4 s (toque fecha); cada conquista é anunciada uma vez.
- **Fonte:** `GymBros/Bros/Companion.swift` (`Achievements`), `GymBros/App/App.swift` (`announce`), `GymBros/Bros/DexView.swift`

### RF-JOG-42: Ficha da forma no BroBook
O app deve mostrar a ficha de uma forma (arte, tipos, números, descrição, como conseguir e linha evolutiva) quando o jogador toca nela.
- **Regras de negócio**
  - Abre num painel de meia altura que expande para tela cheia, por um nó da árvore do BroBook (com o bro principal como referência) ou pelo botão "BroBook" do resumo em "Meus bros" (com o bro selecionado como referência).
  - Topo: arte animada (silhueta se não descoberta), número "Nº 000" pela posição da forma no catálogo do BroBook (`DexView.allForms`; o ovo é o 000) e botão "Fechar".
  - Nome (ou "???") e pílulas dos atributos da forma (uma, ou duas no híbrido); "Ovo" no ovo; não descoberta mostra "???" e "Ainda não descoberta", e a espécie também aparece como "???".
  - Três números: Espécie ("—" no ovo), Fase e "XP para chegar" (limiar do estágio).
  - Se o bro de referência está nesta forma: "Seu bro está nesta forma · nível N · faltam X XP para evoluir" ("para chocar" no ovo) com barra de progresso, ou "· forma final"; se já passou por ela: "Seu bro passou por aqui em {data}".
  - Descrição por estágio; no Atleta e na Lenda, uma frase por atributo da forma. Não descoberta: "Você ainda não encontrou esta forma. Treine para descobrir quem ela é."
  - "Como conseguir": ovo choca com 60 XP; bebê choca com 60 XP quando os treinos do ovo são das atividades da espécie (o Coelho, variados ou "Outro"); Novato evolui do bebê com 300 XP, com qualquer treino; Atleta evolui do Novato e Lenda de qualquer Atleta, no limiar do estágio, "se {atributo} for o atributo mais treinado" ou, no híbrido, "se {A} e {B} forem os atributos mais treinados, quase empatados (até 10% de diferença)", desde a última evolução. Chips "Treinos que chocam" no bebê (as atividades da espécie, sem Outro) ou "Treinos que mais ajudam" no Atleta e na Lenda (categorias, sem Outro, cuja soma dos pesos fixos de RF-JOG-07 nos atributos da forma é pelo menos 0,3, da maior para a menor); ovo e Novato não têm chips.
  - "Evolução": "Vem de" ↓ a forma (selo "ESTA") ↓ "Pode virar" ("· depende do que você treinar" quando há mais de uma). Galhos de um atributo primeiro e híbridos com arte num bloco à parte ("Híbridos · dois atributos quase empatados"). O ovo pode virar o bebê de cada espécie pronta; a Lenda vem de qualquer Atleta da espécie (inclusive híbridos com arte). Cada linha diz a condição (início; espécie e até 3 atividades; "Novato · 300 XP"; atributos e XP) e, tocada, troca a ficha para aquela forma no mesmo painel.
  - Formas não descobertas seguem em silhueta e "???" também nas linhas; "Revelar todas" (RF-JOG-25) vale para a ficha.
- **Critérios de aceitação**
  - A ficha do Novato vem do bebê e pode virar o Atleta de Força; a Lenda de Técnica vem (entre outros) do Atleta de Força e não vira nada.
  - O ovo pode virar tantos bebês quantas espécies prontas existirem.
  - O Atleta de Força diz "Força for o atributo mais treinado" e tem Musculação como primeiro treino que mais ajuda; a Lenda híbrida de Força e Técnica cita "Força e Técnica".
- **Fonte:** `GymBros/Bros/DexEntryView.swift` (`DexEntryView`, `DexEntry`), `GymBros/Bros/DexView.swift` (`node`, `allForms`), `GymBros/Bros/Monsters.swift` (`MyBrosList`), `GymBrosTests/DexEntryTests.swift`

---

## 10. Histórico, detalhe, edição e exclusão

### RF-JOG-27: Histórico
O app deve listar todas as atividades agrupadas por dia, da mais recente para a mais antiga.
- **Regras de negócio**
  - Resumo: número de atividades, tempo total ("N h" com horas inteiras a partir de 60 min, senão "N min"), XP total e distribuição % dos atributos da vida.
  - Linha: ícone e nome do tipo exato (RF-JOG-01), duração · esforço · data, destinos (👤 Perfil, ligas, 📍 local), coração se veio do Saúde, "+N XP".
  - Vazio: "Nenhuma atividade ainda".
- **Fonte:** `GymBros/Activities/HistoryView.swift`, `GymBros/Bros/HomeView.swift` (`ActivityRow`)

### RF-JOG-28: Detalhe da atividade
O app deve mostrar o detalhe de uma atividade.
- **Regras de negócio:** cabeçalho com o nome do tipo exato; foto do check-in; título (do post, da observação ou o nome do tipo exato) com o ícone do tipo; data/hora; XP; duração; esforço "N/10 · rótulo"; local; origem Apple Saúde; percurso (se houver); "Publicado em" (perfil primeiro, depois ligas na ordem de entrada, "Liga encerrada" ou "+valor" com unidade, já com pesos e regra de foto da liga, ex.: "+12,4 km", "+3 treinos"); séries do treino guiado vinculado. O lápis tem rótulo "Editar atividade".
- **Fonte:** `GymBros/Activities/ActivityDetail.swift`, `GymBros/Leagues/Leagues.swift` (`League.score`, `LeagueScoring.format`)

### RF-JOG-29: Editar atividade
O app deve permitir editar tipo, duração, esforço, data, observação e destinos de uma atividade.
- **Regras de negócio:** campos carregados uma única vez (o tipo exato gravado, ou o equivalente da categoria); a seção "Treino feito" não aparece na edição; destinos atuais vêm marcados (sem marcar tudo); com destinos, seção "Post" com título, descrição e local; tirar um destino apaga o check-in de lá; se a atividade tinha sido gravada no Saúde, a gravação é apagada para ser refeita. Ao salvar, grava o tipo exato, recalcula a divisão de atributos (RF-JOG-40), o XP e a evolução.
- **Fonte:** `GymBros/Activities/LogActivityView.swift`, `GymBros/Bros/AttributeSplit.swift` (`ActivitySplits.stamp`)

### RF-JOG-30: Apagar atividade
O app deve permitir apagar uma atividade com confirmação.
- **Regras de negócio:** confirmação "Apagar atividade?" avisando que os check-ins somem; apaga treino guiado vinculado, check-ins (e os comentários deles), percurso e resultado de WOD; se importada do Saúde, entra na lista de ignorados (não reimporta); apaga a gravação feita no Saúde; a tela fecha e a exclusão ocorre 0,5 s depois.
- **Critérios de aceitação:** apagar não faz o bro voltar de forma: o XP que a atividade deu fica com os bros que o receberam (`RetiredActivities`, sincronizado com a conta; "Recomeçar jornada" limpa). Teste: `RetiredActivityTests.testDeletingActivityKeepsTheBroXP`.
- **Fonte:** `GymBros/Activities/ActivityDetail.swift` (`deleteActivity`)

---

## 11. Lembretes

### RF-JOG-31: Lembrete diário de treino
O app deve agendar notificações locais no horário escolhido, só em dias sem treino.
- **Regras de negócio**
  - Desligado por padrão; horário padrão 18:00; opção "Só em dias de rotina". Ligar pede permissão de notificação.
  - Agenda os próximos 7 dias (hoje incluso se o horário não passou), reagendando a cada mudança relevante; hoje é pulado se já treinou.
  - Título: "Seu ovo está esfriando 🥚" (ovo) ou "{bro} está te chamando". Corpo: rotina do dia > sequência em risco (só hoje, "Não deixa a sequência de N dias acabar 🔥") > "Que tal um treino hoje? Qualquer atividade conta."
- **Fonte:** `GymBros/Bros/Companion.swift` (`Reminders`), `GymBros/App/SettingsView.swift`, `GymBros/App/App.swift` (`publish`)

### RF-JOG-32: Resumo semanal
O app deve enviar no domingo às 19h um resumo da semana.
- **Regras de negócio:** ligado por padrão; últimos 7 dias: nº de treinos, tempo e PRs, ou "Nenhum treino nesta semana…"; posição em até 2 ligas ativas com dias restantes.
- **Fonte:** `GymBros/Bros/Companion.swift` (`WeeklySummary`)

---

## 12. Widgets e Live Activity

### RF-JOG-33: Dados compartilhados com widgets
O app deve publicar o estado do bro principal no App Group `group.com.alonsoalmeida.gymbros` e recarregar os widgets a cada mudança de XP, última atividade, rotinas, lembretes, nome, bro principal ou ao voltar ao app.
- **Regras de negócio:** nome, forma, estágio, sprite, nível, XP, progresso, faltante, sequência, última atividade, XP de hoje, rotinas por dia da semana e última evolução. Aviso: 24 h após chocar/evoluir "🐣 Chocou: X!" / "✨ Evoluiu para X!"; com progresso ≥ 85% "🥚 Quase chocando! N XP" / "⚡ Quase evoluindo! N XP".
- **Fonte:** `Shared/WidgetShared.swift`, `GymBros/App/App.swift` (`publish`)

### RF-JOG-34: Widget "Meu bro"
O app deve oferecer um widget interativo com o bro se mexendo.
- **Regras de negócio:** tamanhos pequeno, médio, grande e tela bloqueada redondo/retangular; uma pose por minuto por 60 min (ciclo por humor: ovo balança; triste/entediado/exausto dorme; comemora nas 24 h após evoluir); toque registra carinho e reage por ~4 s se o último foi há < 5 s; contador de carinhos.
- **Fonte:** `GymBrosWidget/PetWidget.swift`

### RF-JOG-35: Widget "Status do bro"
O app deve oferecer um widget com humor, nível, XP e sequência.
- **Regras de negócio:** pequeno, médio, retangular e circular (medidor de nível; 🥚 no ovo); linha curta por humor; timeline com entradas na virada dos próximos 3 dias (00:01).
- **Fonte:** `GymBrosWidget/GymBrosWidget.swift`

### RF-JOG-36: Widget "Treino do dia"
O app deve mostrar a rotina do dia ("Treino livre" sem rotina) e um botão que abre `gymbros://start`, levando à aba Treino e iniciando/abrindo o treino.
- **Regras de negócio:** pequeno e médio; "FEITO ✅" e "Treinar de novo" se já treinou hoje; médio mostra sequência.
- **Fonte:** `GymBrosWidget/TodayWidget.swift`, `GymBros/App/App.swift` (`onOpenURL`)

### RF-JOG-37: Live Activity de treino e de WOD
O app deve exibir Live Activities na tela bloqueada e na Dynamic Island.
- **Regras de negócio**
  - Treino: título, cronômetro, exercício atual, série N de M com carga, progresso de séries, sprite "_live" do principal; botões "Série feita", "Pular" (descanso) e "Próxima série" (descanso vencido); conteúdo expira no fim do descanso. Feitas/total contam só séries de trabalho (aquecimento fica de fora, como na conclusão).
  - WOD: nome, formato, cronômetro progressivo ou regressivo, "Pausado", rodadas e botão "+1 rodada".
- **Fonte:** `GymBrosWidget/WorkoutLiveActivity.swift`, `GymBrosWidget/WodLiveActivity.swift`, `Shared/WorkoutLive.swift`, `Shared/WorkoutIntents.swift`, `GymBros/Train/LiveWorkout.swift`

---

## 13. Atalhos

### RF-JOG-38: Atalhos da Siri e controles
O app deve expor as ações "Série feita" e "Pular descanso" no app Atalhos, na Siri, no Botão de Ação e, no iOS 18+, como controles da Central de Controle.
- **Regras de negócio:** frases como "Série feita no GymBros" e "Pular descanso no GymBros"; respondem com frase de confirmação, numerando a série entre as do mesmo tipo (trabalho ou aquecimento) e usando o nome do exercício personalizado; sem treino: "Nenhum treino em andamento." (ou "Abra um treino no GymBros primeiro." se o app não registrou a ação).
- **Fonte:** `GymBros/App/Shortcuts.swift`, `Shared/WorkoutIntents.swift`, `GymBrosWidget/WorkoutControls.swift`

---

## 14. Compartilhar nos Stories

### RF-JOG-39: Arte de treino para Stories
O app deve gerar uma imagem 1080 × 1920 da atividade, com o sprite do bro principal, e abrir a folha de compartilhar.
- **Regras de negócio**
  - A arte mostra o sprite do principal (padrão `sprite_baby`); conteúdo, molduras, calorias, distância, pace e trajeto estão em RF-SOC-29 (`03-social-e-dados.md`).
- **Fonte:** `GymBros/Activities/StoryShare.swift`, `GymBros/Activities/ActivityDetail.swift`
