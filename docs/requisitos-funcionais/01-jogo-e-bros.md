# Requisitos funcionais 01: jogo e bros

**Escopo.** Este documento descreve, por engenharia reversa do código do app GymBros (SwiftUI + SwiftData, iOS 17), o núcleo de jogo: como uma atividade física é registrada e convertida em XP, como o XP se distribui em atributos, como o bro choca, evolui e escolhe galhos (inclusive híbridos) e espécies, a coleção de bros (principal, apelido, ovo adotado por liga), humor e frases do companheiro, conquistas, Dex, tela inicial, cena de evolução, histórico/edição/exclusão de atividades, lembretes, widgets, Live Activities, atalhos e compartilhamento em Stories. Ficam fora: regras de pontuação das ligas, treino guiado/progressão de carga, WOD, GPS, Apple Saúde e backup (tratados em outros documentos), exceto onde tocam o jogo. Todos os números citados vêm do código; o estado do jogo é sempre recalculado a partir do histórico de atividades (nada além do log é persistido para XP e evolução).

---

## 1. Registro de atividade e XP

### RF-JOG-01: Registrar atividade manualmente
O app deve permitir registrar uma atividade informando tipo, duração, esforço, data/hora e observação opcional.
- **Regras de negócio**
  - 12 tipos: Musculação, Crossfit, Corrida, Caminhada, Bike, Natação, Vôlei, Futebol, Lutas, Dança, Yoga, Outro (grade de 4 colunas).
  - Valores iniciais: Musculação, 60 min, esforço 6, data/hora atual.
  - Duração por stepper de 5 a 240 min, passo de 5, com atalhos de 30, 45, 60 e 90 min.
  - Esforço de 1 (bem leve) a 10 (no limite). Rótulos: ≤3 Leve, 4–6 Moderado, 7–8 Intenso, 9–10 Máximo.
  - A atividade nova guarda o bro principal do momento (`monsterUUID`) como dono padrão do XP.
  - Por padrão, ficam marcados como destino o perfil e todas as ligas ativas e já iniciadas (ver RF-JOG-18 sobre o efeito no XP).
- **Critérios de aceitação**
  - Ao salvar, a atividade aparece no histórico e o feedback háptico de sucesso é emitido.
  - Não é possível escolher duração fora de 5–240 min pelo formulário.
- **Fonte:** `GymMonsters/LogActivityView.swift`, `GymMonsters/Model.swift`, `GymMonsters/LeaguesView.swift` (`LeaguePostSection`)

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
- **Fonte:** `GymMonsters/Game.swift` (`ActivityKind.met`, `Game.xp`, `Game.maxMinutes`)

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
- **Fonte:** `GymMonsters/Game.swift` (`Game.snapshot`), `GymMonsters/LogActivityView.swift`

### RF-JOG-04: Pré-visualização do ganho
O app deve mostrar, antes de salvar, o XP que a atividade vai render, a divisão por atributo e se ela faz algum bro chocar/evoluir.
- **Regras de negócio**
  - Os donos do XP seguem a mesma regra do RF-JOG-18 aplicada aos destinos marcados no momento (`Roster.owners`): representantes das ligas marcadas; sem liga, o principal (na criação) ou o dono gravado na atividade (na edição).
  - Para cada dono, o cálculo usa o histórico dele, retirando a versão antiga na edição. Com vários donos, o "+N XP" mostrado é o maior entre eles (como nas listas).
  - Exibe "+N XP" e, para cada atributo do tipo, "+round(N × peso)".
  - Se algum dono sobe de estágio: "Isso vai fazer o ovo chocar! 🥚" / "Isso vai fazer os ovos chocarem! 🥚" (só ovos) ou "Isso vai fazer seu bro evoluir! ✨" / "Isso vai fazer seus bros evoluírem! ✨".
  - A mesma prévia (XP e aviso de evolução) aparece na conclusão do treino guiado, com os destinos marcados lá.
- **Critérios de aceitação**
  - Editar uma atividade não soma o treino duas vezes na pré-visualização.
  - Marcar só uma liga representada por um ovo novo mostra o XP e o choco desse ovo, não do principal.
- **Fonte:** `GymMonsters/LogActivityView.swift` (`preview`, `previewView`), `GymMonsters/WorkoutView.swift` (`FinishWorkoutView.preview`), `GymMonsters/Monsters.swift` (`Roster.owners`)

### RF-JOG-05: Nível do bro
O app deve exibir um nível derivado do XP total.
- **Regras de negócio:** `nível = floor(√(XP/5)) + 1` (0 XP = nível 1; 60 = 4; 300 = 8; 1200 = 16; 3600 = 27).
- **Critérios de aceitação:** o nível não aparece enquanto o bro é ovo na tela inicial.
- **Fonte:** `GymMonsters/Game.swift` (`Game.level`), `GymMonsters/HomeView.swift`

### RF-JOG-06: Sequência de dias
O app deve calcular a sequência atual e a melhor sequência de dias com atividade.
- **Regras de negócio**
  - Sequência atual: dias consecutivos com ao menos uma atividade terminando hoje ou ontem.
  - Melhor sequência: maior série de dias consecutivos no histórico.
  - Na tela inicial e no widget, sequência e humor usam todas as atividades do jogador (não só as do bro principal).
  - No widget, a sequência zera se a última atividade foi há mais de 1 dia (`liveStreak`).
- **Critérios de aceitação:** treinar ontem e não hoje mantém a sequência; dois dias sem treino zeram.
- **Fonte:** `GymMonsters/Game.swift` (`streak`, `bestStreak`), `GymMonsters/App.swift` (`derive`), `Shared/WidgetShared.swift`

---

## 2. Atributos, estágios e evolução

### RF-JOG-07: Distribuição em atributos
O app deve distribuir o XP ganho de cada atividade entre Força, Resistência, Agilidade e Técnica.
- **Regras de negócio** (pesos somam 1): Musculação F 0,8 / T 0,2; Crossfit F 0,4 / R 0,4 / A 0,2; Corrida R 0,8 / A 0,2; Caminhada R 1; Bike R 0,8 / F 0,2; Natação R 0,6 / T 0,4; Vôlei A 0,6 / T 0,4; Futebol A 0,5 / R 0,5; Lutas A 0,4 / T 0,3 / F 0,3; Dança A 0,5 / T 0,5; Yoga T 1; Outro 0,25 cada.
  - O app mantém atributos da fase (zerados a cada evolução), atributos totais da vida e atributos do choco (os da fase de ovo).
- **Critérios de aceitação:** a tela inicial mostra os atributos da fase; o histórico mostra a distribuição percentual da vida.
- **Fonte:** `GymMonsters/Game.swift` (`ActivityKind.weights`, `Snapshot`)

### RF-JOG-08: Estágios por XP total
O app deve evoluir o bro por limiares de XP total acumulado.
- **Regras de negócio:** Ovo 0 → Bebê 60 → Rookie 300 → Champion 1200 → Ultimate 3600. Ultimate é a forma final. A data da evolução é a data da atividade que cruzou o limiar.
- **Critérios de aceitação**
  - A barra de progresso vai de 0 a 1 entre o limiar atual e o próximo; no Ultimate fica cheia e mostra "forma final".
  - Texto de faltante: "faltam N XP para chocar" (ovo) ou "faltam N XP para evoluir".
  - Apagar ou editar atividades recalcula o estágio, podendo regredir.
- **Fonte:** `GymMonsters/Game.swift` (`Stage`, `Snapshot.progress`, `xpToNext`), `GymMonsters/HomeView.swift`

### RF-JOG-09: Galho da evolução (atributo dominante)
O app deve escolher a forma de Champion e Ultimate pelo atributo mais treinado desde a última evolução.
- **Regras de negócio**
  - Só Champion e Ultimate têm galho; Bebê e Rookie são únicos.
  - Dominante = maior atributo da fase; empate resolvido pela ordem Força → Resistência → Agilidade → Técnica.
  - Ao evoluir, os atributos da fase são zerados; um bro pode mudar de galho entre Champion e Ultimate.
  - Se uma única atividade cruza mais de um limiar, a fase nova ainda está vazia: o galho (e os atributos do choco) usam os atributos da fase anterior.
- **Critérios de aceitação:** com a fase Rookie dominada por corrida, o Champion é o de Resistência; uma atividade que leva do Rookie direto ao Ultimate não nasce sem galho.
- **Fonte:** `GymMonsters/Game.swift` (`Game.snapshot`, `Game.branch`, `Game.dominant`), `EVOLUCAO.md`

### RF-JOG-10: Formas híbridas
O app deve gerar uma forma híbrida quando os dois atributos mais treinados da fase estão quase empatados.
- **Regras de negócio**
  - Híbrido quando o 2º atributo ≥ 90% do 1º (`hybridRatio = 0,9`) e o 1º > 0.
  - 6 duplas × 2 estágios = 12 híbridos por espécie; a dupla é sempre ordenada F, R, A, T.
  - Cada híbrido de cada espécie tem nome próprio e único no jogo (96 nomes, nenhum repete outra forma nem leva a espécie no fim). No Coelho (Champion / Ultimate): F+R Crossbro / Hércubro; F+A Golpebro / Titãbro; F+T Arrancobro / Olimpibro; R+A Chuteirabro / Tufãobro; R+T Nadobro / Marébro; A+T Gingabro / Piruetabro. Lista completa no `HIBRIDOS.md`.
  - Sem arte no app, o bro usa a forma normal do atributo dominante.
- **Critérios de aceitação:** atributos da fase F=100 e R=90 geram Crossbro; F=100 e R=89 geram o Champion de Força.
- **Fonte:** `GymMonsters/Game.swift` (`MonsterForm`, `Species.names`, `Species.hybridKeys`), `GymMonsters/Monsters.swift` (`resolve`), `HIBRIDOS.md`

### RF-JOG-11: Tendência de forma
O app deve indicar na tela inicial em que forma o bro tende a evoluir.
- **Regras de negócio:** exibe "tende a virar {forma}" somente quando o próximo estágio tem galho e há atributos na fase; a forma considera a espécie e o fallback de arte do híbrido.
- **Critérios de aceitação:** no Bebê não aparece; no Rookie com treinos aparece; no Ultimate não aparece.
- **Fonte:** `GymMonsters/Game.swift` (`Snapshot.nextForm`), `GymMonsters/HomeView.swift`

---

## 3. Espécies

### RF-JOG-12: Espécie definida ao chocar
O app deve definir a espécie do bro no momento em que o ovo choca, pelos treinos que o chocaram.
- **Regras de negócio**
  - 8 espécies: Coelho (padrão, sem afinidade), Urso e Rato (Força), Lobo e Cachorro (Resistência), Esquilo e Gato (Agilidade), Coruja (Técnica).
  - Treinos equilibrados chocam Coelho: se o atributo dominante dos atributos do choco tem menos de 35% do total (`balancedShare`), ou se não há atributos, nasce Coelho.
  - Senão, dominante → espécies prontas com essa afinidade; havendo mais de uma, a escolha é determinística por semente do UUID do bro. Sem correspondência, nasce Coelho.
  - Só nasce espécie com as 10 artes no app (`isReady`); hoje todas as 8 estão prontas.
  - Após o choco a espécie é gravada no bro (`speciesID`) e não muda com espécies novas. Se o bro volta a ser ovo (atividades apagadas ou editadas), a espécie gravada é apagada e o próximo choco decide de novo.
  - O ovo é igual para todas as espécies.
- **Critérios de aceitação:** um ovo chocado só com yoga nasce Coruja; um ovo com Força, Resistência, Agilidade e Técnica em 25% cada nasce Coelho; o mesmo bro sempre resolve para a mesma espécie.
- **Fonte:** `GymMonsters/Game.swift` (`Species.hatch`, `Species.balancedShare`, `Species.all`), `GymMonsters/App.swift` (`check`), `GymMonstersTests/GameTests.swift` (`testBalancedHatchIsStandardSpecies`), `EVOLUCAO.md`

---

## 4. Onboarding

### RF-JOG-13: Primeiro acesso e recebimento do ovo
O app deve, no primeiro acesso, pedir o nome do treinador e entregar um ovo.
- **Regras de negócio**
  - Enquanto `trainerName` estiver vazio, o app mostra o onboarding no lugar da tela principal.
  - Passo 1: "Todo treinador começa com um ovo. Como você se chama?" com campo de nome; botão "Receber meu ovo" desabilitado com nome em branco.
  - Passo 2: "Este ovo é seu!" com explicação; "Começar a jornada" grava o nome (sem espaços nas pontas).
  - Ao entrar na tela principal, o app garante um bro inicial (`isStarter`) e o define como principal; ligas sem representante válido passam a ser representadas por ele.
- **Critérios de aceitação:** nome só com espaços não avança; após "Começar a jornada" a tela inicial mostra o ovo com 0 XP.
- **Fonte:** `GymMonsters/OnboardingView.swift`, `GymMonsters/App.swift` (`RootView`), `GymMonsters/Monsters.swift` (`ensureStarter`)

---

## 5. Coleção de bros

### RF-JOG-14: Bro principal
O app deve manter um bro principal, exibido na tela inicial, na barra de abas e nos widgets.
- **Regras de negócio**
  - Principal = o salvo em `mainMonster` se existir; senão o inicial; senão o primeiro.
  - O principal recebe o XP das atividades que não foram postadas em nenhuma liga (o perfil não conta como liga).
  - O dono padrão é gravado na atividade ao criá-la; trocar o principal depois não move atividades antigas.
  - A tela principal observa a chave `mainMonster`: trocar o principal atualiza na hora a tela inicial, a barra de abas e o widget.
- **Critérios de aceitação:** em "Meus bros", "Tornar principal" aparece só para quem não é o principal e o bro passa a exibir o selo "principal".
- **Fonte:** `GymMonsters/Monsters.swift` (`MainMonster`, `Roster`, `MyBrosList`), `GymMonsters/App.swift` (`MainView`)

### RF-JOG-15: Apelido
O app deve permitir dar apelido a cada bro.
- **Regras de negócio:** apelido vazio usa o nome da forma atual; espaços nas pontas são removidos; enquanto ovo, o nome exibido é sempre "Ovo". O apelido do principal também é editável em Ajustes.
- **Critérios de aceitação:** apagar o apelido volta a mostrar o nome da forma.
- **Fonte:** `GymMonsters/Monsters.swift` (`displayName`, `MyBrosList`), `GymMonsters/SettingsView.swift`

### RF-JOG-16: Lista "Meus bros"
O app deve listar todos os bros com estado e ligas que representam, na aba "Meus bros" da tela Bros (RF-JOG-23).
- **Regras de negócio:** ordem por data de criação; cada card mostra sprite animado, nome, "Ovo · N XP para chocar" ou "{Estágio} · Nível N · X XP", barra de progresso e "Liga: …" ou "Não representa nenhuma liga". Toque abre ações (Tornar principal, Dar apelido).
- **Critérios de aceitação:** não há ação de apagar bro.
- **Fonte:** `GymMonsters/Monsters.swift` (`MyBrosList`)

### RF-JOG-17: Representante por liga e ovo adotado
O app deve, ao entrar numa liga, pedir quem representa o jogador: um bro existente ou um ovo novo.
- **Regras de negócio:** "Adotar um ovo novo" cria um bro que começa do zero, só com os check-ins dessa liga. Uma liga com representante apagado/ausente passa ao bro inicial.
- **Critérios de aceitação:** escolher o ovo novo adiciona um bro à coleção.
- **Fonte:** `GymMonsters/Monsters.swift` (`MonsterChoiceSection`, `representative`, `ensureStarter`)

### RF-JOG-18: Destino do XP de cada atividade
O app deve atribuir o XP de cada atividade aos bros corretos.
- **Regras de negócio**
  - Postada em ligas → XP para cada bro representante dessas ligas (um bro conta uma vez mesmo em várias ligas). Bros diferentes recebem o XP integral cada um.
  - Não postada em liga → XP para o bro gravado na atividade; se ele não existe mais, para o inicial.
  - Liga sem representante válido não conta como destino: se nenhuma das ligas marcadas tem representante, vale a regra "não postada em liga".
  - Em listas (Histórico, "Últimas atividades", aviso de importação do Saúde, detalhe), o XP mostrado de uma atividade com vários donos é o maior entre eles.
- **Critérios de aceitação:** uma atividade postada em duas ligas com bros distintos aparece no XP dos dois; a mesma atividade mostra o mesmo XP na tela inicial e no Histórico.
- **Fonte:** `GymMonsters/Monsters.swift` (`Roster.owners`, `Roster.init`, `xpByActivity`), `GymMonsters/App.swift` (`derive`, `syncHealth`), `GymMonstersTests/GameTests.swift` (`testXPOwnersFollowLeagues`)

---

## 6. Humor e companheiro

### RF-JOG-19: Humor do bro
O app deve derivar o humor do bro principal do último treino, da sequência e do XP de hoje.
- **Regras de negócio:** Ovo → "Chocando" 🥚. Sem atividade → Entediado. Treinou hoje: XP de hoje ≥ 300 → Exausto 🥵; sequência ≥ 3 → Animado 🤩; senão Feliz 😊. Último treino há 1 dia → Feliz; 2–3 dias → Entediado 🥱; 4+ → Triste 😢.
  - Visual: saturação 0,35 se triste e 0,7 se entediado (app e widgets).
- **Critérios de aceitação:** sem treinar há 4 dias o bro aparece triste e dessaturado.
- **Fonte:** `Shared/WidgetShared.swift` (`Mood.of`), `GymMonsters/HomeView.swift`

### RF-JOG-20: Frases do balão
O app deve exibir uma frase do bro de acordo com o humor e o contexto.
- **Regras de negócio**
  - Uma frase por dia e humor: índice = ordinal do dia na era mod número de opções (não muda a cada redesenho).
  - Ovo: frases diferentes para 0 XP e para XP > 0 (inclui "Faltam N XP para eu sair!").
  - Feliz e sem treino hoje: prioriza a rotina do dia ("Hoje é dia de {rotina}! Vamos?"); depois um músculo esquecido; treinou hoje: frases de parabéns.
  - Músculos esquecidos: dentre quadríceps, costas superiores, peito, deltoides, posteriores, glúteos, bíceps, tríceps, abdômen e panturrilhas, os sem carga nos treinos guiados dos últimos 7 dias; só se houver algum treino guiado no histórico.
  - Entediado/Triste citam os dias sem treino ("Faz N dias…").
- **Critérios de aceitação:** no mesmo dia e humor, reabrir a tela mostra a mesma frase.
- **Fonte:** `GymMonsters/Companion.swift` (`Companion`), `GymMonsters/App.swift` (`companionContext`)

---

## 7. Tela inicial

### RF-JOG-21: Tela inicial do bro
O app deve ter uma tela inicial centrada no bro principal.
- **Regras de negócio**
  - Cabeçalho "Olá, {nome}", selo de sequência (🔥 N, lido como "N dias seguidos" no VoiceOver) quando > 0, botões Amigos, Bros e Ajustes.
  - Card do bro: balão com emoji do humor, bro animado, nome, estágio · atributo do galho · Nível · humor (os três últimos só fora do ovo), barra e XP. No ovo: "Registre seu primeiro treino para aquecer o ovo." (0 XP) ou "Ele está se mexendo… continue treinando!".
  - Card "Treinos desta fase" (fora do ovo): barras dos 4 atributos proporcionais ao maior.
  - Botão "Registrar atividade" e card "Últimas atividades" com as 3 mais recentes (toque abre o detalhe), com o mesmo XP do Histórico (RF-JOG-18).
  - A barra de abas tem o bro no centro (Início), Treino, Ligas, Mapa e Histórico.
- **Critérios de aceitação:** sem atividades, o card de recentes não aparece.
- **Fonte:** `GymMonsters/HomeView.swift`, `GymMonsters/App.swift`

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
- **Fonte:** `GymMonsters/EvolutionView.swift`, `GymMonsters/App.swift` (`check`, `EvolutionEvent`)

---

## 9. Tela "Bros": Meus bros, Dex e Conquistas

### RF-JOG-23: Navegação da tela Bros
O app deve abrir, pelo botão Bros da tela inicial, uma tela modal com as abas "Meus bros", "Dex" e "Conquistas".
- **Regras de negócio:** o título acompanha a aba; subtítulos: "Seu principal e os que te representam nas ligas"; "N de M formas descobertas"; "N de M desbloqueadas".
- **Fonte:** `GymMonsters/DexView.swift`, `GymMonsters/App.swift`

### RF-JOG-24: Descoberta de formas
O app deve registrar como descoberta toda forma alcançada por qualquer bro.
- **Regras de negócio:** o ovo é sempre descoberto; descobertas são cumulativas (não somem ao apagar atividades). Total = ovo + formas de cada espécie pronta (10 normais + híbridos com arte) = 177 hoje.
- **Fonte:** `GymMonsters/App.swift` (`check`), `GymMonsters/DexView.swift` (`allForms`)

### RF-JOG-25: Dex por espécie
O app deve exibir a árvore de evolução de cada espécie.
- **Regras de negócio**
  - Seletor horizontal com todas as espécies: bebê (silhueta se não descoberto), "vistos/total", ícone da afinidade; espécie sem arte mostra "?" e "Em breve" e não é selecionável. O Coelho é descrito como "Nasce de ovos chocados com treinos equilibrados, sem atributo dominante".
  - Árvore: Ovo → Bebê → Rookie; um galho por atributo (Champion → Ultimate); seção "Formas híbridas" se a espécie tiver alguma arte híbrida, com uma linha por dupla cujo Champion híbrido tenha arte.
  - Forma não descoberta: silhueta e "???"; cada nó mostra estágio e limiar de XP; a forma atual do principal fica destacada.
  - "Revelar todas" mostra tudo sem contar como descoberta (preferência salva).
- **Fonte:** `GymMonsters/DexView.swift`

### RF-JOG-26: Conquistas
O app deve avaliar 28 conquistas e exibi-las em grade.
- **Regras de negócio**
  - Atividades: 1, 10, 50, 100; 5 tipos diferentes; uma de ≥120 min; antes das 7h; a partir das 21h; 1 importada do Saúde.
  - Estágio (do bro mais evoluído): chocar, Rookie, Champion, Ultimate; 2 bros no Ultimate.
  - Melhor sequência: 3, 7, 30 dias.
  - Treino guiado: 10 treinos; 1 e 25 recordes; 10 t e 100 t de volume (peso × reps das séries feitas); todos os músculos do mapa numa janela de 7 dias.
  - Espécies chocadas: 2, 4 e todas as do catálogo (hoje 8); Dex: 25 formas e todas. Com o Coelho nascendo de treinos equilibrados (RF-JOG-12), todas são alcançáveis.
  - Grade ordenada por desbloqueadas e depois por progresso; bloqueadas com barra de progresso e opacidade 0,7.
  - Ao desbloquear, banner "Conquista: {título}" ou "N conquistas novas!" por 4 s (toque fecha); cada conquista é anunciada uma vez.
- **Fonte:** `GymMonsters/Companion.swift` (`Achievements`), `GymMonsters/App.swift` (`announce`), `GymMonsters/DexView.swift`

---

## 10. Histórico, detalhe, edição e exclusão

### RF-JOG-27: Histórico
O app deve listar todas as atividades agrupadas por dia, da mais recente para a mais antiga.
- **Regras de negócio**
  - Resumo: número de atividades, tempo total ("N h" com horas inteiras a partir de 60 min, senão "N min"), XP total e distribuição % dos atributos da vida.
  - Linha: ícone, tipo, duração · esforço · data, destinos (👤 Perfil, ligas, 📍 local), coração se veio do Saúde, "+N XP".
  - Vazio: "Nenhuma atividade ainda".
- **Fonte:** `GymMonsters/HistoryView.swift`, `GymMonsters/HomeView.swift` (`ActivityRow`)

### RF-JOG-28: Detalhe da atividade
O app deve mostrar o detalhe de uma atividade.
- **Regras de negócio:** foto do check-in; título (do post, da observação ou o tipo); data/hora; XP; duração; esforço "N/10 · rótulo"; local; origem Apple Saúde; percurso (se houver); "Publicado em" (perfil primeiro, depois ligas na ordem de entrada, "Liga encerrada" ou "+valor" com unidade, já com pesos e regra de foto da liga, ex.: "+12,4 km", "+3 treinos"); séries do treino guiado vinculado. O lápis tem rótulo "Editar atividade".
- **Fonte:** `GymMonsters/ActivityDetail.swift`, `GymMonsters/Leagues.swift` (`League.score`, `LeagueScoring.format`)

### RF-JOG-29: Editar atividade
O app deve permitir editar tipo, duração, esforço, data, observação e destinos de uma atividade.
- **Regras de negócio:** campos carregados uma única vez; destinos atuais vêm marcados (sem marcar tudo); com destinos, seção "Post" com título, descrição e local; tirar um destino apaga o check-in de lá; se a atividade tinha sido gravada no Saúde, a gravação é apagada para ser refeita. Recalcula XP e evolução.
- **Fonte:** `GymMonsters/LogActivityView.swift`

### RF-JOG-30: Apagar atividade
O app deve permitir apagar uma atividade com confirmação.
- **Regras de negócio:** confirmação "Apagar atividade?" avisando que os check-ins somem; apaga treino guiado vinculado, check-ins (e os comentários deles), percurso e resultado de WOD; se importada do Saúde, entra na lista de ignorados (não reimporta); apaga a gravação feita no Saúde; a tela fecha e a exclusão ocorre 0,5 s depois.
- **Critérios de aceitação:** após apagar, XP, estágio e conquistas dependentes são recalculados.
- **Fonte:** `GymMonsters/ActivityDetail.swift` (`deleteActivity`)

---

## 11. Lembretes

### RF-JOG-31: Lembrete diário de treino
O app deve agendar notificações locais no horário escolhido, só em dias sem treino.
- **Regras de negócio**
  - Desligado por padrão; horário padrão 18:00; opção "Só em dias de rotina". Ligar pede permissão de notificação.
  - Agenda os próximos 7 dias (hoje incluso se o horário não passou), reagendando a cada mudança relevante; hoje é pulado se já treinou.
  - Título: "Seu ovo está esfriando 🥚" (ovo) ou "{bro} está te chamando". Corpo: rotina do dia > sequência em risco (só hoje, "Não deixa a sequência de N dias acabar 🔥") > "Que tal um treino hoje? Qualquer atividade conta."
- **Fonte:** `GymMonsters/Companion.swift` (`Reminders`), `GymMonsters/SettingsView.swift`, `GymMonsters/App.swift` (`publish`)

### RF-JOG-32: Resumo semanal
O app deve enviar no domingo às 19h um resumo da semana.
- **Regras de negócio:** ligado por padrão; últimos 7 dias: nº de treinos, tempo e PRs, ou "Nenhum treino nesta semana…"; posição em até 2 ligas ativas com dias restantes.
- **Fonte:** `GymMonsters/Companion.swift` (`WeeklySummary`)

---

## 12. Widgets e Live Activity

### RF-JOG-33: Dados compartilhados com widgets
O app deve publicar o estado do bro principal no App Group `group.com.alonsoalmeida.gymmonsters` e recarregar os widgets a cada mudança de XP, última atividade, rotinas, lembretes, nome, bro principal ou ao voltar ao app.
- **Regras de negócio:** nome, forma, estágio, sprite, nível, XP, progresso, faltante, sequência, última atividade, XP de hoje, rotinas por dia da semana e última evolução. Aviso: 24 h após chocar/evoluir "🐣 Chocou: X!" / "✨ Evoluiu para X!"; com progresso ≥ 85% "🥚 Quase chocando! N XP" / "⚡ Quase evoluindo! N XP".
- **Fonte:** `Shared/WidgetShared.swift`, `GymMonsters/App.swift` (`publish`)

### RF-JOG-34: Widget "Meu bro"
O app deve oferecer um widget interativo com o bro se mexendo.
- **Regras de negócio:** tamanhos pequeno, médio, grande e tela bloqueada redondo/retangular; uma pose por minuto por 60 min (ciclo por humor: ovo balança; triste/entediado/exausto dorme; comemora nas 24 h após evoluir); toque registra carinho e reage por ~4 s se o último foi há < 5 s; contador de carinhos.
- **Fonte:** `GymMonstersWidget/PetWidget.swift`

### RF-JOG-35: Widget "Status do bro"
O app deve oferecer um widget com humor, nível, XP e sequência.
- **Regras de negócio:** pequeno, médio, retangular e circular (medidor de nível; 🥚 no ovo); linha curta por humor; timeline com entradas na virada dos próximos 3 dias (00:01).
- **Fonte:** `GymMonstersWidget/GymMonstersWidget.swift`

### RF-JOG-36: Widget "Treino do dia"
O app deve mostrar a rotina do dia ("Treino livre" sem rotina) e um botão que abre `gymbros://start`, levando à aba Treino e iniciando/abrindo o treino.
- **Regras de negócio:** pequeno e médio; "FEITO ✅" e "Treinar de novo" se já treinou hoje; médio mostra sequência.
- **Fonte:** `GymMonstersWidget/TodayWidget.swift`, `GymMonsters/App.swift` (`onOpenURL`)

### RF-JOG-37: Live Activity de treino e de WOD
O app deve exibir Live Activities na tela bloqueada e na Dynamic Island.
- **Regras de negócio**
  - Treino: título, cronômetro, exercício atual, série N de M com carga, progresso de séries, sprite "_live" do principal; botões "Série feita", "Pular" (descanso) e "Próxima série" (descanso vencido); conteúdo expira no fim do descanso. Feitas/total contam só séries de trabalho (aquecimento fica de fora, como na conclusão).
  - WOD: nome, formato, cronômetro progressivo ou regressivo, "Pausado", rodadas e botão "+1 rodada".
- **Fonte:** `GymMonstersWidget/WorkoutLiveActivity.swift`, `GymMonstersWidget/WodLiveActivity.swift`, `Shared/WorkoutLive.swift`, `Shared/WorkoutIntents.swift`, `GymMonsters/LiveWorkout.swift`

---

## 13. Atalhos

### RF-JOG-38: Atalhos da Siri e controles
O app deve expor as ações "Série feita" e "Pular descanso" no app Atalhos, na Siri, no Botão de Ação e, no iOS 18+, como controles da Central de Controle.
- **Regras de negócio:** frases como "Série feita no GymBros" e "Pular descanso no GymBros"; respondem com frase de confirmação, numerando a série entre as do mesmo tipo (trabalho ou aquecimento) e usando o nome do exercício personalizado; sem treino: "Nenhum treino em andamento." (ou "Abra um treino no GymBros primeiro." se o app não registrou a ação).
- **Fonte:** `GymMonsters/Shortcuts.swift`, `Shared/WorkoutIntents.swift`, `GymMonstersWidget/WorkoutControls.swift`

---

## 14. Compartilhar nos Stories

### RF-JOG-39: Arte de treino para Stories
O app deve gerar uma imagem 1080 × 1920 do treino guiado e abrir a folha de compartilhar.
- **Regras de negócio**
  - Disponível no detalhe de atividades com treino guiado vinculado: "Compartilhar nos Stories" (usa a foto do check-in, se houver) e "Stories com outra foto".
  - Conteúdo: marca, data, local, título, sprite do principal (padrão `sprite_baby`), duração, nº de séries, volume arredondado a 10 kg ("–" se zero), melhor série por exercício (até 8 sem foto, 5 com foto, "+N exercícios") e até 2 recordes.
  - Margens seguras: 56 pt no topo e 64 pt embaixo (em 360 × 640 × 3).
- **Fonte:** `GymMonsters/StoryShare.swift`, `GymMonsters/ActivityDetail.swift`
