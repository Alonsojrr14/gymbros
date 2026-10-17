# 02 — Treino: musculação guiada, CrossFit, recordes e corpo

Este documento descreve os requisitos funcionais da área de treino do GymBros, extraídos do código atual (SwiftUI + SwiftData, tudo local no aparelho). Cobre rotinas e modelos prontos, o treino guiado (séries, cargas sugeridas, progressão, deload, aquecimento, superséries, troca de exercício), o timer de descanso e os controles fora da tela (Live Activity, Siri/Atalhos e modo fone), a conclusão do treino, recordes e 1RM, a biblioteca de exercícios (inclusive personalizados, com imagens, vídeos e instruções do wger e a tela de créditos), mapa muscular e volume semanal, CrossFit/WOD, peso, medidas e calculadora de anilhas, e as metas e estatísticas do perfil privado. XP, ligas, lugares de treino e Apple Saúde aparecem só onde tocam o treino; o detalhe deles fica em outros documentos. Caminhos de fonte são relativos à raiz do projeto.

## 1. Rotinas
### RF-TRE-01 — Tela Treino
**Descrição:** O app deve oferecer uma aba "Treino" que reúne o treino do dia, as rotinas, CrossFit, evolução e treinos recentes.  
**Regras de negócio:**
- Com treino em andamento (sessão sem `end`), mostra só o cartão "Em andamento desde HH:MM" com "Continuar", no lugar da seção "Hoje".
- Sem treino em andamento, "Hoje" lista as rotinas cujo dia da semana é o atual, cada uma com "N exercícios · M séries" e "Começar", mais a linha "Treino livre".
- Sem rotina no dia: "Crie uma rotina ou use um modelo pronto." (sem rotinas) ou "Nenhuma rotina para hoje. Descanso também evolui o bro.".
- "Evolução" dá acesso a Meus PRs, Exercícios e recordes, Volume semanal, Mapa muscular, Biblioteca, Peso e medidas e Calculadora de anilhas (que abre com 60 kg).
- "Treinos recentes" mostra os 10 últimos treinos concluídos.

**Critérios de aceitação:** Com uma rotina marcada para segunda, abrir o app numa segunda exibe essa rotina em "Hoje · segunda-feira"; com uma sessão aberta, não é possível começar outra pela seção "Hoje" nem pelo menu da rotina.  
**Fonte:** `GymMonsters/TrainView.swift`
### RF-TRE-02 — Criar, editar e apagar rotinas
**Descrição:** O app deve permitir criar rotinas com nome, dias da semana e lista ordenada de exercícios.  
**Regras de negócio:**
- "Nova rotina" cria uma rotina chamada "Nova rotina", sem dias, no fim da lista.
- Dias são alternados por botões Seg…Dom (1 = domingo … 7 = sábado no calendário); sem dias, a lista mostra "Sem dia fixo".
- Exercício adicionado entra com 3 séries, 10 reps (30 s se for por tempo) e 90 s de descanso.
- Por item: séries de 1 a 10 e reps de 1 a 300 (passo 5 em exercícios por tempo), em `GMCompactStepper`; descanso escolhido numa roleta de 0 a 10 min, em passos de 5 s.
- Menu do item: mover para cima/baixo, "Superset com <próximo>"/"Separar de <próximo>" e "Remover da rotina".
- Com exercícios, a seção "O que essa rotina treina" mostra o mapa muscular das séries planejadas (RF-TRE-30).
- Menu da rotina na lista: "Começar agora" (só sem treino em andamento), "Editar" e "Apagar rotina", que pede confirmação ("Apagar <nome>?" · "Os treinos já feitos com ela continuam no histórico.").

**Critérios de aceitação:** Alterações são salvas ao sair da tela de edição; remover um item renumera a ordem dos restantes.  
**Fonte:** `GymMonsters/RoutineEditView.swift`, `GymMonsters/TrainView.swift`, `GymMonsters/Training.swift`
### RF-TRE-03 — Modelos prontos
**Descrição:** O app deve instalar conjuntos de rotinas prontas com um toque.  
**Regras de negócio:**
- Seis modelos: ABC (A/B/C em seg+qui, ter+sex, qua+sáb), Full body (seg, qua, sex), Superior/Inferior (seg+qui, ter+sex), CrossFit (A seg, B qua, C sex), Kettlebell e metcon (ter, sex) e Em casa (seg, qua, sex, só peso do corpo).
- As rotinas são adicionadas depois das existentes, sem substituir nada.
- Descanso de cada item: 120 s se o grupo muscular é "pesado" (costas, quadríceps, posterior, glúteos, panturrilha) e o item tem 4 séries ou mais; senão 90 s.

**Critério de aceitação:** Instalar "ABC" cria 3 rotinas; o agachamento (quadríceps, 4×8) fica com 120 s de descanso.  
**Fonte:** `GymMonsters/Training.swift` (`RoutineTemplate`), `GymMonsters/TrainView.swift` (`TemplatesView`)

## 2. Treino guiado
### RF-TRE-04 — Começar um treino
**Descrição:** O app deve iniciar um treino de rotina ou livre já com as cargas sugeridas pelo histórico.  
**Regras de negócio:**
- Treino livre começa vazio com o título "Treino livre"; o de rotina recebe o nome da rotina e cria as séries de cada item com a sugestão de RF-TRE-09.
- Se o app já sabe que a pessoa está num lugar salvo, a sessão nasce com esse lugar; senão detecta ou pergunta uma vez por treino (chip "Onde você está?" / "Sem local", tocável para trocar).
- Ao chegar na academia (notificação), o app abre o treino em andamento ou começa a primeira rotina do dia. Pede permissão de notificações ao começar.

**Critério de aceitação:** Começar uma rotina com 4×8 de supino gera 4 séries com a carga e as reps sugeridas e o descanso da rotina.  
**Fonte:** `GymMonsters/LiveWorkout.swift` (`startSession`), `GymMonsters/TrainView.swift`, `GymMonsters/WorkoutView.swift`
### RF-TRE-05 — Registro de séries
**Descrição:** O app deve exibir um cartão por exercício em que a pessoa ajusta carga e reps e marca cada série como feita.  
**Regras de negócio:**
- Carga: passo igual ao incremento do exercício (RF-TRE-09) nos exercícios com carga e 2,5 kg nos de peso do corpo/tempo, rotulados "+kg" (carga extra opcional); nunca negativa; digitável com até 2 casas (ex.: 1,25).
- Reps: passo 1 (passo 5 s nos exercícios por tempo). Se as reps ficam abaixo da meta, o campo fica laranja e mostra "de <meta>"; a série feita fica com check vazado laranja.
- Rótulo da carga: "kg total" ou "kg anilhas" em exercícios com barra, decidido automaticamente pelo treino: num treino de CrossFit (algum exercício da biblioteca de CrossFit) a carga é o total com a barra; na musculação, só as anilhas, mesmo em agachamento e terra. Fora de um treino vale a marcação CrossFit do próprio exercício. "kg" nos demais. Não há mais ajuste manual ("Carga na barra" saiu de Ajustes).
- O cartão mostra "N/M séries", a razão da sugestão, "Última vez: carga×reps[/meta]…" e, se a sugestão supera a maior carga feita da última vez, "Subir para X kg (+Y kg)".
- Se há sugestão de carga e todas as séries pendentes estão com 0 kg, aparece "Usar X kg nas séries", que preenche todas.
- "+ Série" copia carga, meta de reps e descanso da última série.
- Tocar no nome recolhe/expande; ao concluir todas as séries o cartão recolhe sozinho e a tela rola até o próximo exercício pendente.
- O botão play marca o exercício "fazendo agora" (destacado e enviado ao Live Activity); sem marcação, vale o primeiro com série pendente.
- A tela mantém o aparelho aceso e mostra o cronômetro desde o início; "minimizar" fecha a tela sem encerrar o treino.

**Critérios de aceitação:** Marcar 8 reps numa série com meta 10 destaca a série em laranja; fechar e reabrir o app mantém o treino e as séries marcadas.  
**Fonte:** `GymMonsters/WorkoutView.swift` (`exerciseCard`, `SetRow`), `GymMonsters/Exercises.swift` (`weightIncludesBar(in:)`, `weightUnit(in:)`, `WorkoutSession.isCrossfit`), `GymMonstersTests/NamesAndBarTests.swift` (`testBarWeightFollowsWorkoutType`)
### RF-TRE-06 — Menu do exercício no treino
**Descrição:** O app deve oferecer, por exercício, ações de apoio durante o treino.  
**Regras de negócio:**
- "Ver como fazer"; "Calcular anilhas" (só exercícios com carga; usa a carga da última série ou 60 kg e soma a barra escolhida na calculadora, padrão 20 kg, quando no treino a carga anotada é só das anilhas).
- "Tempo de descanso": altera o descanso das séries ainda não feitas daquele exercício neste treino.
- "Superset com <próximo>"/"Separar de <próximo>" (exceto no último exercício).
- "Adicionar aquecimento"/"Tirar aquecimento" (RF-TRE-12); "Objetivo" (RF-TRE-10); "Trocar exercício (aparelho ocupado)" só se há série pendente (RF-TRE-14); "Histórico de cargas" (RF-TRE-26).
- Nota do exercício ("Ajuste da máquina, pegada…"): salva sem espaços nas pontas; texto vazio apaga a nota; a nota aparece em amarelo no cartão e no detalhe do exercício.
- "Remover exercício" pede confirmação ("Remover <exercício>?" · "As séries dele neste treino, feitas ou não, saem do treino.") e então apaga as séries e desfaz o elo de superset dele.

**Critério de aceitação:** Uma nota salva aparece no próximo treino com o mesmo exercício; cancelar a confirmação de remover mantém as séries.  
**Fonte:** `GymMonsters/WorkoutView.swift` (`exerciseActions`), `GymMonsters/Body.swift` (`ExerciseNote`)
### RF-TRE-07 — Adicionar exercício e descartar treino
**Descrição:** O app deve permitir adicionar exercícios a qualquer treino e descartar o treino inteiro.  
**Regras de negócio:**
- "+ Exercício" abre a biblioteca; o escolhido entra no fim com 3 séries de 10 reps (30 s se por tempo), descanso de 90 s e carga sugerida pelo histórico. Num treino de deload, segue a regra do RF-TRE-11 (70 % da carga, 2 séries).
- Barra fixa inferior: "+ Exercício", recolher/expandir todos e descartar.
- Descartar pede confirmação ("Descartar este treino? Nada dele será salvo."), apaga a sessão, cancela o descanso, desliga o modo fone e encerra o Live Activity.

**Critério de aceitação:** Treino vazio mostra "Treino vazio — Toque em + Exercício, aqui embaixo, para começar.".  
**Fonte:** `GymMonsters/WorkoutView.swift`

## 3. Progressão, deload e aquecimento
### RF-TRE-08 — Histórico usado na progressão
**Descrição:** O app deve calcular sugestões só a partir de treinos concluídos, excluindo aquecimentos e semanas de deload.  
**Regras de negócio:**
- Séries de aquecimento não entram no log da sessão (progressão, recordes, mapa e volume).
- Sessões feitas em deload não contam como referência de carga.
- Uma sessão é "sucesso" quando tem pelo menos o número de séries prescritas e as primeiras N foram feitas com reps ≥ meta.

**Critério de aceitação:** Treino feito em semana de deload não altera a sugestão do treino seguinte.  
**Fonte:** `GymMonsters/Training.swift` (`WorkoutSession.log`, `SessionLog`, `Progression.suggest`)
### RF-TRE-09 — Sugestão de carga sem objetivo (reps fixas)
**Descrição:** O app deve sugerir carga e reps de cada exercício a partir do último treino em que ele apareceu.  
**Regras de negócio:**
- Incremento: 5 kg só se o grupo é pesado (costas, quadríceps, posterior, glúteos, panturrilha) e o equipamento é "Barra" (agachamento, terra, stiff…); máquina, polia, halteres e o resto sobem de 2,5 kg.
- Primeira vez, com carga e com PR registrado à mão: carga de trabalho = 1RM estimado ÷ (1 + reps/30) × 0,92, arredondada para baixo ao incremento ("com 1–2 de sobra"). Sem PR: carga 0 e "Primeira vez: escolha uma carga…".
- Carga de referência = maior carga entre as séries feitas da última vez.
- Se a meta da rotina subiu em relação à última, mantém a carga com a nova meta.
- Com carga: sucesso → +incremento; falha → mesma carga, com contador "(n/3 antes do deload)"; 3 treinos seguidos sem completar na mesma carga → deload de 10 %: carga × 0,9 arredondada para baixo ao incremento.
- Peso do corpo sem carga extra: sucesso → +1 rep; senão mesmas reps. Com carga extra, progride por carga como acima.
- Por tempo: sucesso → +5 s; senão mesmo tempo.

**Critérios de aceitação:** Supino 4×8 com 60 kg feito por completo → próximo treino sugere 62,5 kg × 8; agachamento com barra falhado 3 vezes em 100 kg → sugere 90 kg; cadeira extensora e leg press sobem de 2,5 kg.  
**Fonte:** `GymMonsters/Training.swift` (`Progression.suggest`), `GymMonsters/PR.swift` (`PRBook.workingWeight`), `GymMonsters/Exercises.swift` (`increment`), `GymMonstersTests/ProgressionTests.swift` (`testFiveKiloStepOnlyForBarbellInHeavyGroups`)
### RF-TRE-10 — Objetivo por exercício (dupla progressão)
**Descrição:** O app deve permitir escolher, para exercícios com carga, um objetivo que define faixa de reps, regra de progressão e descanso.  
**Regras de negócio:**
- Força 3–6 reps, 180 s; Hipertrofia 8–12 reps, 90 s; Resistência 15–20 reps, 60 s; ou "Sem objetivo (reps fixas)".
- Com objetivo, a meta começa no início da faixa; completou todas as séries na meta → +1 rep (até o topo); completou no topo → +incremento e volta ao início da faixa; senão repete.
- Escolhido no treino: as séries pendentes recebem as novas reps e o descanso do objetivo e, se estavam com 0 kg, a carga sugerida.
- Também é escolhido no detalhe do exercício; fica guardado por exercício e entra no backup.

**Critério de aceitação:** Supino reto em Hipertrofia, 3×12 completas com 40 kg → próxima sugestão 42,5 kg × 8.  
**Fonte:** `GymMonsters/Training.swift` (`TrainingGoal`), `GymMonsters/WorkoutView.swift` (`setGoal`), `GymMonsters/ExerciseStatsView.swift`, `GymMonsters/Backup.swift`
### RF-TRE-11 — Semana de deload
**Descrição:** O app deve sugerir uma semana mais leve após várias semanas seguidas de treino e aplicá-la às rotinas.  
**Regras de negócio:**
- Sequência = semanas consecutivas (contando desta ou da passada) com treino concluído, parando numa semana sem treino ou com treino de deload.
- Sugere quando a sequência ≥ 5, não há deload ativo e não foi adiado; "Agora não" adia por 7 dias.
- "Fazer deload" vale até o fim da semana do calendário; "Encerrar deload" termina antes.
- Em deload, cada prescrição usa 70 % da carga sugerida (arredondada ao incremento) e max(1, arredondamento de 2/3 das séries); a sessão fica marcada como deload. A regra (`Deload.apply`) vale para os itens da rotina, para exercícios adicionados no treino e para o exercício que entra numa troca (que herda as séries já reduzidas).

**Critério de aceitação:** Item 3×10 com 100 kg em deload vira 2 séries de 70 kg; exercício adicionado num treino de deload também entra com 70 % e 2 séries.  
**Fonte:** `GymMonsters/Training.swift` (`Deload.apply`), `GymMonsters/LiveWorkout.swift`, `GymMonsters/WorkoutView.swift` (`add`, `swap`), `GymMonsters/TrainView.swift` (`deloadCard`), `GymMonstersTests/ProgressionTests.swift` (`testDeloadAppliesToAnyPrescription`)
### RF-TRE-12 — Aquecimento
**Descrição:** O app deve gerar séries de aquecimento antes da carga de trabalho.  
**Regras de negócio:**
- Três séries: 40 % × 10, 60 % × 6 e 80 % × 3 da carga de trabalho, arredondadas ao incremento; descanso de 60 s; marcadas "A" em laranja.
- Em exercício com barra cuja carga inclui a barra, o mínimo é 20 kg; séries com carga ≥ a de trabalho são omitidas.
- Automático (Ajustes → "Aquecimento automático", ligado por padrão): só no primeiro exercício com carga da rotina cuja sugestão seja ≥ 20 kg.
- Manual pelo menu, em exercício com carga cuja primeira série tenha carga > 0; "Tirar aquecimento" remove e renumera.
- Aquecimento não conta para progressão, recordes, volume nem mapa muscular, nem nas séries feitas/total da conclusão, de "Treinos recentes" e do Live Activity (`workSets`, `doneWorkSets`, `volume`).

**Critério de aceitação:** Trabalho de 100 kg (incremento 2,5) gera 40 × 10, 60 × 6 e 80 × 3.  
**Fonte:** `GymMonsters/Training.swift` (`Progression.warmup`, `WorkoutSession.workSets`), `GymMonsters/LiveWorkout.swift`, `GymMonsters/WorkoutView.swift`, `GymMonsters/SettingsView.swift`, `GymMonstersTests/WorkoutTests.swift` (`testWarmupStaysOutOfTotalsEverywhere`)
### RF-TRE-13 — Superséries
**Descrição:** O app deve encadear exercícios em superset, sem descanso entre eles.  
**Regras de negócio:**
- O elo liga um exercício ao seguinte; elos consecutivos formam um bloco.
- Ao marcar uma série, o app vai para o próximo exercício do bloco com série pendente, sem descanso; ao fechar a volta, descansa com o descanso da série marcada e volta ao primeiro pendente do bloco; terminado o bloco, segue para o próximo exercício pendente.
- O cartão mostra "Superset i/n · descanso depois de <último do bloco>". Elos da rotina são copiados para a sessão ao começar.

**Critério de aceitação:** Bloco A+B: marcar A não inicia descanso e destaca B; marcar B inicia o descanso.  
**Fonte:** `GymMonsters/Training.swift` (`group`, `advance`), `GymMonsters/WorkoutView.swift`, `GymMonsters/RoutineEditView.swift`
### RF-TRE-14 — Trocar exercício (aparelho ocupado)
**Descrição:** O app deve trocar as séries pendentes de um exercício por outro do mesmo grupo muscular.  
**Regras de negócio:**
- Alternativas: mesmo grupo, sem o atual e sem os que já estão no treino, incluindo personalizados; ordenadas por quantas vezes já foram feitas ("já fez N×"), depois o mesmo equipamento do atual primeiro (barra por barra, máquina por máquina) e por nome.
- As séries pendentes de trabalho passam para o novo, com carga e reps sugeridas para ele (com deload, se o treino for de deload); aquecimentos pendentes do antigo são apagados.
- Se o antigo já tinha séries feitas, o novo entra logo depois dele; se nenhuma, ocupa o lugar. Nos dois casos, se o antigo estava em superset com o próximo, é o novo que herda o elo e o antigo sai do bloco.

**Critério de aceitação:** Trocar supino reto após 1 de 4 séries mantém a série feita e cria 3 séries do novo exercício logo abaixo; num bloco supino + barra, a troca parcial deixa o novo em superset com a barra e o supino fora do bloco.  
**Fonte:** `GymMonsters/SwapExercise.swift` (`ranked`), `GymMonsters/Training.swift` (`WorkoutSession.swapPending`), `GymMonsters/WorkoutView.swift` (`swap`), `GymMonstersTests/WorkoutTests.swift` (`testPartialSwapInSupersetDoesNotLinkOldToNew`, `testFullSwapTakesThePlaceAndTheLink`), `GymMonstersTests/ProgressionTests.swift` (`testSwapAlternativesPutSameEquipmentFirst`)

## 4. Descanso e controles fora da tela
### RF-TRE-15 — Timer de descanso
**Descrição:** O app deve iniciar o descanso ao marcar uma série e permitir ajustá-lo.  
**Regras de negócio:**
- Duração = descanso da série marcada; descanso 0 não inicia timer.
- Barra com anel de progresso e tempo restante; −15 s (chegando a 0, encerra), +15 s e "Pular".
- Tocar no tempo abre a roleta (0–10 min, passos de 5 s) com o restante arredondado a 5 s (mínimo 5 s); 0 cancela.
- No fim: vibração de aviso e a barra some, mesmo que o descanso tenha sido iniciado pelo Live Activity.
- Notificação "Descanso acabou / Bora para a próxima série 💪" só com Ajustes → "Notificação no fim do descanso" ligado (desligado por padrão).

**Critério de aceitação:** Com notificação ligada e o app em segundo plano, a notificação chega no fim do descanso; pular ou concluir o treino cancela a pendente.  
**Fonte:** `GymMonsters/LiveWorkout.swift` (`startRest`, `cancelRest`), `GymMonsters/WorkoutView.swift` (`restBar`, `watchRest`), `GymMonsters/SettingsView.swift`
### RF-TRE-16 — Live Activity, Siri e Atalhos
**Descrição:** O app deve mostrar o treino na tela bloqueada/Dynamic Island e aceitar "Série feita" e "Pular descanso" fora do app.  
**Regras de negócio:**
- Estado: exercício atual, série x de y, texto da série (com "Aquecimento ·" se for o caso), séries de trabalho feitas/total (sem aquecimento) e fim do descanso.
- Só um Live Activity de treino por vez; outro é encerrado antes.
- "Série feita": marca a próxima série pendente do exercício atual, aplica a regra de superset/descanso e devolve frase (numerando entre as séries do mesmo tipo e com o nome do exercício personalizado, ou "Exercício personalizado" se ele foi apagado) como "Supino reto: série 2 de 4 feita. Descanso de 1 minuto e 30 segundos. Próximo: …"; com tudo feito, "Última série feita! Treino completo, é só concluir no app.".
- Sem treino: "Nenhum treino em andamento."; atalhos por voz: "Série feita no GymBros", "Pular descanso no GymBros" etc.

**Critério de aceitação:** Marcar série pelo Live Activity com o app fechado inicia o descanso e atualiza a tela do app ao reabrir.  
**Fonte:** `GymMonsters/LiveWorkout.swift`, `Shared/WorkoutIntents.swift`, `GymMonsters/Shortcuts.swift`
### RF-TRE-17 — Modo fone
**Descrição:** O app deve permitir controlar o treino pelo play/pause do fone, com respostas faladas.  
**Regras de negócio:**
- Na primeira vez explica que a música de outro app pausa enquanto o modo estiver ligado; depois liga direto.
- Play, pause, play/pause e próxima faixa: em descanso, pulam o descanso; fora dele, marcam a série (RF-TRE-16).
- Fala em pt-BR ("×" lido como "por"): ao ligar, "Dez segundos" antes do fim do descanso e "Descanso acabou. <exercício>, série n, <carga>".
- "Dez segundos" sai uma vez por descanso, mesmo que o laço (≈1 s) pule o segundo 10 exato, e só se o descanso foi visto com mais de 10 s restantes (não fala em descanso curto nem depois de um −15 s que já caiu abaixo de 10). Um +15 s cria um descanso novo e um novo aviso.
- O "tocando agora" mostra exercício (ou "Descanso") e "Série n de m · <série>".
- Desliga ao concluir ou descartar o treino.

**Critério de aceitação:** Com o celular bloqueado, apertar play no fone marca a série e o app fala a confirmação.  
**Fonte:** `GymMonsters/HeadphoneControl.swift` (`TenSecondCue`), `GymMonsters/WorkoutView.swift`, `GymMonstersTests/WorkoutTests.swift` (`testTenSecondCueSpeaksOncePerRest`)

## 5. Concluir treino e histórico
### RF-TRE-18 — Tela de conclusão
**Descrição:** O app deve resumir o treino antes de salvar.  
**Regras de negócio:**
- Mostra duração (mínimo 1 min), séries feitas/total de trabalho, volume (Σ carga × reps das séries de trabalho feitas) e mapa dos músculos trabalhados.
- "No próximo treino, suba a carga": exercícios em que a regra sugere mais carga ou mais reps/tempo.
- "Onde melhorar": exercícios com séries feitas abaixo da meta, com as reps de cada série e a meta.
- "Recordes 🏆" (RF-TRE-23), esforço 1–10 (padrão 7), postagem nas ligas com foto opcional e prévia do XP (atributo Força) pelos bros das ligas marcadas, com aviso de choco/evolução (mesma regra do RF-JOG-04).
- "Salvar" só habilitado com ao menos uma série de trabalho feita ("Marque ao menos uma série feita para salvar.").

**Critério de aceitação:** Treino só com aquecimentos marcados não pode ser salvo.  
**Fonte:** `GymMonsters/WorkoutView.swift` (`FinishWorkoutView`)
### RF-TRE-19 — Salvar treino e atualizar rotina
**Descrição:** O app deve registrar o treino como atividade de musculação e, se pedido, atualizar a rotina de origem.  
**Regras de negócio:**
- Cria atividade de musculação com data de início, minutos, esforço, título como nota e o lugar; posta nas ligas escolhidas com os recordes no texto.
- Diferenças em relação à rotina (entra/sai exercício, nova ordem, séries, reps, descanso, superset) são listadas; o toggle "Salvar essas mudanças na rotina" recria os itens. Cargas nunca entram; com objetivo, as reps da rotina são mantidas.
- Ao salvar: encerra a sessão, cancela a notificação de descanso, encerra o Live Activity e desliga o modo fone.

**Critério de aceitação:** Adicionar um exercício no treino e ligar o toggle faz a rotina passar a conter esse exercício com as séries/reps/descanso feitos.  
**Fonte:** `GymMonsters/WorkoutView.swift` (`save`), `GymMonsters/Training.swift` (`WorkoutSession.routineChanges`, `apply(to:context:)`)
### RF-TRE-20 — Encerramento automático
**Descrição:** O app deve poder encerrar e salvar o treino sem a tela de conclusão (ex.: ao sair da academia), com os mesmos padrões do "Salvar" da conclusão.  
**Regras de negócio:**
- Sem nenhuma série de trabalho feita (só aquecimento não conta), o treino é descartado ("Nenhuma série marcada, então o treino foi descartado.").
- Com séries, cria a atividade de musculação com nota "<título> · 📍 <lugar>" e esforço igual à média dos últimos 10 treinos de musculação (ou 7, o padrão da conclusão, sem histórico).
- Posta no perfil e nas ligas em andamento, com os recordes no texto ("🏆 …"), como a conclusão faz por padrão.
- Se o treino ficou diferente da rotina de origem, não pergunta na hora: guarda a oferta (`PendingRoutineUpdate`) e a aba Treino mostra o card "Atualizar a rotina <nome>?" com as diferenças, "Salvar na rotina" e "Manter como está".
- Devolve "<título>: <duração>, N séries. +X XP pro seu bro." e, se houver oferta, " A rotina <nome> mudou: abra a aba Treino para atualizar.".

**Critério de aceitação:** O treino encerrado automaticamente aparece em "Treinos recentes", no perfil e nas ligas em andamento; com a rotina alterada, a aba Treino oferece atualizar.  
**Fonte:** `GymMonsters/LiveWorkout.swift` (`autoFinish`), `GymMonsters/Training.swift` (`Progression.estimatedEffort`, `PendingRoutineUpdate`), `GymMonsters/TrainView.swift` (`pendingRoutineCard`), `GymMonstersTests/ProgressionTests.swift` (`testAutoFinishEffortIsAverageOfRecentWorkouts`)
### RF-TRE-21 — Treinos recentes e correção de séries
**Descrição:** O app deve listar treinos concluídos e permitir corrigir séries e apagar treinos.  
**Regras de negócio:**
- Linha: título, data, duração, nº de séries de trabalho feitas e volume (aquecimento fora).
- Detalhe: séries por exercício, "meta N" em laranja quando abaixo; tocar abre edição de carga, reps e "Feita", com "Aplicar carga em todas as N séries" (do mesmo tipo: trabalho ou aquecimento); botão de compartilhar em story.
- "Apagar treino" avisa "O XP desse treino também sai do bro." e apaga também a atividade gerada.

**Critério de aceitação:** Corrigir a carga de uma série passada muda a sugestão do próximo treino.  
**Fonte:** `GymMonsters/TrainView.swift` (`SessionRow`, `SessionDetailView`, `deleteSession`)

## 6. Recordes e 1RM
### RF-TRE-22 — 1RM estimado
**Descrição:** O app deve estimar o 1RM pela fórmula de Epley.  
**Regras de negócio:**
- 1RM = carga × (1 + reps/30), só com carga > 0 e 1 a 12 reps; com 1 rep, a própria carga; acima de 12 reps não estima.

**Critério de aceitação:** 100 kg × 5 → ~116,7 kg; 60 kg × 15 → sem 1RM.  
**Fonte:** `GymMonsters/Training.swift` (`Progression.oneRM`)
### RF-TRE-23 — Recordes no treino
**Descrição:** O app deve apontar recordes batidos ao concluir o treino.  
**Regras de negócio:**
- Compara as séries feitas com todo o histórico anterior e os PRs registrados à mão; sem histórico do exercício, não há recorde. Exercício personalizado aparece pelo nome.
- Por exercício, um recorde, na ordem: "maior carga, X kg"; senão "1RM estimado X kg" (maior que o anterior + 0,01); senão, se nunca houve carga, "N reps".

**Critério de aceitação:** Primeira vez num exercício não gera recorde.  
**Fonte:** `GymMonsters/Training.swift` (`Progression.records`)
### RF-TRE-24 — Meus PRs e sessão de PR
**Descrição:** O app deve mostrar a melhor marca de cada exercício e permitir registrar PRs à mão.  
**Regras de negócio:**
- Melhor marca entre PRs manuais e séries feitas com carga > 0, pela força na escala de 1RM (`Progression.strength`: séries acima de 12 reps contam como 12, sem misturar 1RM com carga bruta), depois maior carga e mais reps; mostra carga × reps, 1RM, data e "registrado"/"no treino"; ordem alfabética.
- Sessão de PR: já traz os exercícios com carga das rotinas, sem repetir; aceita adicionar/remover; exercícios sem carga > 0 e reps ≥ 1 são ignorados; data editável; selo "🏆 novo PR" quando a marca supera a atual pela mesma régua (`PRBook.beats`); repetir a mesma marca não é PR.
- Menu por exercício: "Registrar novo PR" e "Apagar PRs registrados à mão (N)".
- PRs manuais alimentam a primeira sugestão de carga (RF-TRE-09) e a comparação de recordes.

**Critério de aceitação:** Registrar 100 kg × 5 de supino faz o primeiro treino de supino 3×8 sugerir 82,5 kg (116,7 ÷ 1,267 × 0,92 = 84,7, arredondado para baixo); 60 kg × 15 supera 70 kg × 5 (conta como 60 × 12 ≈ 84 contra 81,7).  
**Fonte:** `GymMonsters/PR.swift` (`best`, `beats`), `GymMonsters/Training.swift` (`Progression.strength`), `GymMonstersTests/ProgressionTests.swift` (`testBestMarkDoesNotMixOneRMWithRawLoad`)
### RF-TRE-25 — Exercícios e recordes
**Descrição:** O app deve listar os exercícios já treinados com a melhor marca.  
**Regras de negócio:**
- Ordem por nº de treinos; melhor marca: "1RM ~X kg", senão "máx. X kg", senão "máx. N reps" (ou "s").
- Acessível pela aba Treino e pelo atalho "Recordes" do perfil privado.

**Critério de aceitação:** Sem treinos: "Sem recordes ainda — Conclua um treino guiado para ver seus recordes aqui.".  
**Fonte:** `GymMonsters/ExerciseStatsView.swift` (`ExerciseStatsList`), `GymMonsters/ProfileView.swift`
### RF-TRE-26 — Detalhe do exercício (histórico de cargas)
**Descrição:** O app deve mostrar a evolução de um exercício em gráfico e lista.  
**Regras de negócio:**
- Para exercícios com carga, permite escolher o objetivo (RF-TRE-10).
- O tipo do gráfico vem do tipo do exercício: carga × reps → gráfico em kg; peso do corpo e por tempo → mais reps/melhor tempo, mesmo que algum treino tenha tido carga extra. Personalizado sem tipo conhecido decide pelo que já teve carga.
- No gráfico em kg só entram séries com carga. A escala é "1RM estimado (kg)" quando todo ponto (treinos e PRs) tem 1RM; se algum não tem (só séries acima de 12 reps), todos usam "Maior carga (kg)". As duas escalas nunca se misturam. PRs manuais aparecem como losangos (`Theme.trophy`); exige 2 pontos ("O gráfico aparece a partir do segundo treino.").
- "Melhor 1RM estimado" usa só séries de até 12 reps e PRs; calculadora de 12, 10, 8, 5 e 3 reps arredondada ao incremento do exercício (`Progression.repTable`); lista de PRs registrados e histórico por data.

**Critério de aceitação:** Com melhor 1RM de 100 kg, a calculadora mostra 5×85 nos dois passos e 12×72,5 (passo 2,5) ou 12×70 (passo 5).  
**Fonte:** `GymMonsters/ExerciseStatsView.swift` (`ExerciseDetailView`), `GymMonsters/Training.swift` (`Progression.repTable`), `GymMonstersTests/ProgressionTests.swift` (`testRepCalculatorRoundsToExerciseIncrement`)

## 7. Biblioteca de exercícios
### RF-TRE-27 — Catálogo e busca
**Descrição:** O app deve oferecer uma biblioteca pesquisável de exercícios.  
**Regras de negócio:**
- 262 exercícios embutidos: 78 da biblioteca original (instruções em português), 150 extras (dos quais 42 de CrossFit) e 34 que vieram só do wger (`WgerLibrary.newExercises`). Fotos e instruções do free-exercise-db foram removidas (copiavam o bodybuilding.com, sem uso comercial); nomes e músculos continuam.
- Imagens, vídeos e instruções vêm do wger (`GymMonsters/wger.json`, gerado por `tools/wger/build.py`): 152 exercícios com dados, 128 com imagem embutida no app (funciona sem internet), 33 com vídeo e 146 com instruções (20 em português, 126 em inglês). Licenças CC BY-SA 3.0/4.0 ou CC0, com autor por item; imagens geradas por IA no wger ficam de fora.
- Miniatura na lista: a primeira imagem do wger sobre fundo branco; sem imagem, o símbolo do grupo (ou de CrossFit).
- 12 grupos musculares; tipos: carga × reps, peso do corpo (progride em reps, aceita carga extra) e por tempo (segundos).
- Busca por nome, grupo ou equipamento; filtro Todos/Academia/CrossFit; seções por grupo com contagem; "Meus exercícios" no topo.
- Exercícios da biblioteca original que são clássicos do CrossFit (ex.: burpee, thruster, agachamento) aparecem também na seção CrossFit.

- O seletor termina com "Imagens e vídeos: wger.de · créditos e licenças", que abre a tela de créditos (RF-TRE-39).

**Critério de aceitação:** Buscar "Polia" lista os exercícios com esse equipamento.  
**Fonte:** `GymMonsters/Exercises.swift`, `GymMonsters/ExerciseExtra.swift`, `GymMonsters/Wger.swift` (`WgerLibrary`), `GymMonsters/wger.json`, `GymMonsters/RoutineEditView.swift` (`ExercisePicker`, `ExerciseThumb`), `CREDITOS.md`
### RF-TRE-28 — Detalhe "como fazer"
**Descrição:** O app deve mostrar como executar cada exercício.  
**Regras de negócio:**
- Imagens do wger (fundo branco) alternando a cada 1,2 s quando há mais de uma, com a linha de crédito da imagem atual ("Imagem: <autor> · <licença> · wger.de", com links).
- Com vídeo no wger, "Ver vídeo de demonstração" toca o vídeo no próprio app (carregado de wger.de), com o crédito embaixo. "Buscar vídeos no YouTube" abre a busca ("como fazer <nome> exercício|crossfit").
- Grupo, equipamento e registro; passos: os da biblioteca original em português; senão os do wger, em português ou traduzidos do inglês no aparelho (iOS 18+; antes, em inglês). O rodapé credita o texto ("Texto: <autor> · <licença> · wger.de", com "(traduzido no iPhone)" quando for o caso).
- Mapa de músculos: principais com intensidade 1,0 e auxiliares 0,45, listados por nome; nota pessoal e descrição do personalizado; botão "Créditos e licenças" nos exercícios com dados do wger.

**Critério de aceitação:** Exercício com instruções do wger em inglês, no iOS 17, exibe o texto em inglês com o crédito; exercício sem imagem não mostra a área de fotos.  
**Fonte:** `GymMonsters/MuscleViews.swift` (`ExerciseInfoView`, `TranslateSteps`), `GymMonsters/Wger.swift` (`ExercisePhotos`, `CreditLine`, `WgerVideoView`), `GymMonsters/ExerciseInstructions.swift`, `GymMonsters/ExerciseMuscles.swift`
### RF-TRE-29 — Exercícios personalizados
**Descrição:** O app deve permitir criar, editar e apagar exercícios próprios.  
**Regras de negócio:**
- Nome obrigatório (sem espaços nas pontas); grupo (padrão Peito), equipamento entre 12 opções (padrão Máquina), registro (padrão carga × reps) e descrição opcional.
- Músculos derivados do grupo; incremento pela mesma regra dos embutidos.
- Criado a partir do seletor de um treino/rotina, já é adicionado.
- Apagar pede confirmação; "O histórico de treinos com ele continua salvo.". Depois de apagado, aparece no histórico, recordes, Live Activity e modo fone como "Exercício personalizado" (nunca o id `custom-…`).

**Critério de aceitação:** O botão Salvar fica desabilitado com nome vazio.  
**Fonte:** `GymMonsters/CustomExercise.swift`, `GymMonsters/MuscleViews.swift`, `GymMonsters/Exercises.swift` (`Exercise.name`), `GymMonstersTests/ProgressionTests.swift` (`testCustomExerciseNameResolves`)

### RF-TRE-39 — Créditos e licenças
**Descrição:** O app deve creditar o conteúdo de terceiros numa tela própria.  
**Regras de negócio:**
- "Créditos e licenças" abre pelo seletor de exercícios e pelo detalhe de exercícios com dados do wger.
- Seção wger: link para wger.de e lista de autores e licenças distintos, cada um com link da licença e a contagem de itens ("N itens"); o rodapé explica que instruções traduzidas seguem a mesma licença (CC BY-SA).
- Seções MuscleMap (MIT, Copyright (c) 2026 Melih Colpan), vídeos do YouTube (de seus autores) e Bros (artes e textos próprios).

**Critério de aceitação:** Todo autor que aparece numa linha de crédito de imagem, vídeo ou texto aparece também na tela de créditos.  
**Fonte:** `GymMonsters/Wger.swift` (`CreditsView`, `WgerLibrary.allCredits`), `CREDITOS.md`

## 8. Mapa muscular e volume
### RF-TRE-30 — Mapa muscular
**Descrição:** O app deve mostrar em mapa de calor (frente e costas) quais músculos foram treinados.  
**Regras de negócio:**
- Cada série feita conta 1 no músculo principal e 0,5 nos auxiliares; intensidade normalizada = 0,25 + 0,75 × valor/maior valor.
- Na tela: períodos 7 dias, 30 dias e Tudo; corpo masculino ou feminino (preferência salva); "Séries por músculo" (arredondado a 0,5) e "Sem treino no período" entre 15 músculos acompanhados.
- Também aparece na edição de rotina, na conclusão do treino e no detalhe do exercício.

**Critério de aceitação:** Com todos os 15 músculos treinados: "Você treinou todos os grupos no período. 💪".  
**Fonte:** `GymMonsters/MuscleViews.swift`
### RF-TRE-31 — Volume semanal por músculo
**Descrição:** O app deve comparar as séries semanais de cada grupo com a faixa de 10–20.  
**Regras de negócio:**
- Conta séries de trabalho feitas na semana do calendário, pelo grupo principal; "Corpo todo" fica de fora (11 grupos).
- Abaixo de 10: laranja "faltam N"; 10–20: "na faixa"; acima de 20: ciano "acima"; barra com escala até 26.
- Navegação para semanas anteriores; não avança além da atual. Cabeçalho "N séries · X de 11 grupos na faixa".

**Critério de aceitação:** 12 séries de peito na semana aparecem como "na faixa".  
**Fonte:** `GymMonsters/WeeklyVolume.swift`

## 9. CrossFit / WOD
### RF-TRE-32 — Benchmarks e WOD livre
**Descrição:** O app deve oferecer WODs clássicos e um WOD montado na hora.  
**Regras de negócio:**
- 15 benchmarks: 13 "Girls" (Fran, Grace, Isabel, Diane, Elizabeth, Helen, Cindy, Annie, Karen, Jackie, Nancy, Kelly, Chelsea) e 2 "Heróis" (Murph, DT), com formato, limite de tempo e movimentos ligados à biblioteca.
- Formatos: For Time (com limite opcional), AMRAP, EMOM e Tabata (20 s de esforço / 10 s de descanso).
- WOD livre: For Time, AMRAP (padrão) ou EMOM de 1 a 90 min (padrão 12) ou Tabata de 1 a 20 rodadas (padrão 8); movimentos opcionais, um por linha.
- Lista mostra o recorde de cada benchmark e os 10 últimos resultados; detalhe mostra recorde e histórico.

**Critério de aceitação:** Abrir "Fran" mostra "21-15-9", "For Time" e limite de 10 min.  
**Fonte:** `GymMonsters/Wod.swift`
### RF-TRE-33 — Cronômetro do WOD
**Descrição:** O app deve cronometrar o WOD com avisos sonoros e contador de rodadas.  
**Regras de negócio:**
- Contagem regressiva de 10 s antes de começar; tela sempre acesa; pausar/continuar e "Terminar".
- For Time: cronômetro crescente, encerra ao atingir o limite; chegar ao limite é CAP (não terminou), não um tempo. AMRAP: regressivo, bipe curto nos 3 s finais, encerra no fim. EMOM: bipe longo a cada minuto e curtos nos segundos 57–59. Tabata: bipe longo no início do esforço e do descanso; mostra "ESFORÇO"/"DESCANSO" e "Rodada n de r".
- Contador de rodadas (+/−) em For Time e AMRAP, também pelo botão "+1 rodada" do Live Activity.
- Sair depois de começar pede confirmação ("O tempo não será salvo.").

**Critério de aceitação:** AMRAP de 20 min abre o resultado automaticamente aos 20:00.  
**Fonte:** `GymMonsters/Wod.swift` (`WodTimerView`), `GymMonsters/LiveWorkout.swift` (`LiveWod`)
### RF-TRE-34 — Resultado do WOD
**Descrição:** O app deve registrar o resultado e gerar uma atividade de crossfit.  
**Regras de negócio:**
- For Time grava o tempo; For Time no limite grava CAP ("CAP" em laranja, "Tempo esgotado no limite de mm:ss: não conta como terminado." e "Repetições feitas" de 0 a 2000), exibido como "CAP · N reps"; AMRAP grava rodadas (0–200, pré-preenchidas pelo contador) e repetições extras (0–500); EMOM/Tabata gravam "Concluído".
- RX (padrão ligado), esforço (padrão 8), observação e postagem nas ligas.
- Recorde: For Time, menor tempo; qualquer CAP fica abaixo de qualquer tempo terminado e, entre CAPs, mais reps é melhor; AMRAP, rodadas × 1000 + reps.
- Atividade de crossfit com minutos = max(segundos ativos/60, 1), data no início real do WOD (contando as pausas) e nota "<WOD> · <resultado>".

**Critério de aceitação:** Fran em 5:30 aparece como recorde "5:30 RX" se for o menor tempo; um CAP com 80 reps nunca supera um tempo de 9:50.  
**Fonte:** `GymMonsters/Wod.swift` (`WodResultForm`, `WodResult.capped`, `WodTimerView.FinishedWod`), `GymMonstersTests/WorkoutTests.swift` (`testForTimeCapIsNotAFinishTime`)

## 10. Peso, medidas e anilhas
### RF-TRE-35 — Peso e medidas
**Descrição:** O app deve registrar peso, medidas e fotos de progresso.  
**Regras de negócio:**
- Registro com data, peso (passo 0,1, começa no último ou 70 kg), cintura, peito, braço, coxa e quadril (passo 0,5 cm, começam no último ou 80) e fotos de frente e de lado; salvar exige ao menos um campo.
- Peso atual, variação "no período" (primeiro × último) e gráfico a partir de 2 registros.
- Medidas: valor mais recente e variação desde o primeiro registro; com 2+ valores, gráfico ao tocar.
- Comparar antes e depois (2+ registros com foto): divisória arrastável, frente/lado, escolha de datas e variação de peso em dias.
- Importar do Apple Saúde: peso dos últimos 2 anos, ignorando amostras já importadas e dias que já têm peso, arredondado a 0,1 kg.
- Registros editáveis e apagáveis; apagar pede confirmação ("Apagar o registro de <data>?" · "Peso, medidas e fotos desse dia saem do app.").

**Critério de aceitação:** Importar duas vezes seguidas mostra "Nada novo no Saúde." na segunda.  
**Fonte:** `GymMonsters/BodyTrackerView.swift`, `GymMonsters/Body.swift`
### RF-TRE-36 — Calculadora de anilhas
**Descrição:** O app deve calcular as anilhas de cada lado para uma carga total.  
**Regras de negócio:**
- Anilhas: 25, 20, 15, 10, 5, 2,5 e 1,25 kg, da maior para a menor; barra de 20 (padrão), 15, 10 kg ou sem barra (preferência salva).
- Carga com passo de 2,5 kg e régua de 0 a 300 kg; mostra barra, kg por lado, contagem por anilha, conta do total e o que sobra sem fechar.
- Carga menor ou igual à barra: mensagens específicas.

**Critério de aceitação:** 100 kg com barra de 20 → 40 kg por lado: "1 de 25 kg + 1 de 15 kg".  
**Fonte:** `GymMonsters/BodyTrackerView.swift` (`PlateCalculatorView`), `GymMonsters/Body.swift` (`Plates`)

## 11. Perfil privado: metas e estatísticas
### RF-TRE-37 — Metas
**Descrição:** O app deve acompanhar metas semanais e de peso.  
**Regras de negócio:**
- Treinos na semana: meta de 1 a 14 (padrão 4); conta todas as atividades da semana do calendário.
- Tempo na semana: 30 a 1200 min em passos de 30 (padrão 180). Anéis de progresso com check ao bater a meta.
- Peso alvo (passo 0,5): mostra "faltam X kg para perder/ganhar" ou "Você chegou no peso alvo! 🎯".

**Critério de aceitação:** 4 atividades na semana com meta 4 mostram o anel completo com check.  
**Fonte:** `GymMonsters/ProfileView.swift` (`GoalsView`)
### RF-TRE-38 — Estatísticas
**Descrição:** O app deve mostrar estatísticas de todas as atividades.  
**Regras de negócio:**
- Melhor sequência, treinos/semana (atividades ÷ semanas desde a primeira, mínimo 1) e maior treino.
- Mapa de calor das últimas 16 semanas (opacidade 0,3 + minutos/120). Por atividade: quantidade e tempo, barra relativa ao tipo com mais minutos. Atributos treinados em %.
- Perfil privado mostra também atividades, dias ativos, duração total e atalhos Recordes, Estatísticas, Metas e Peso.

**Critério de aceitação:** Dias futuros da semana atual ficam vazios no mapa de calor.  
**Fonte:** `GymMonsters/ProfileView.swift` (`ProfileStatsView`, `privatePart`)
