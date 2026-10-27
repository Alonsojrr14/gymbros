# GymRats × GymBros: análise comparativa

Data: 21/10/2026.

## Fontes

- **GymRats**: os quatro relatórios da engenharia reversa do APK Android 2026.9.21, feitos numa sessão anterior: desafios e pontuação, treino e registro, social e monetização, backend e modelo de dados. O que eles descrevem vem do cliente decompilado. Sobre o servidor do GymRats só se sabe o que o cliente revela: Elixir/Phoenix, REST e ranking já calculado no servidor. Este documento não presume nada além disso.
- **GymBros**: o código como está hoje, incluindo as mudanças ainda não commitadas (comentários no Firestore e feed com ligas públicas), `README.md`, `docs/arquitetura.md`, `docs/firebase.md`, `docs/servidor-real.md` e `firebase/firestore.rules`.

Para entender a classificação:
- **Existente** quer dizer que está no código do app. Quando só o aparelho garante a regra, aparece "só no cliente".
- **Parcial** quer dizer que falta uma parte relevante, quase sempre a conferência no servidor.
- **Planejada** quer dizer que está prevista em `docs/servidor-real.md`, num TODO ou atrás de uma flag.
- **Inexistente** quer dizer que não há nada no código.

---

## 1. Resposta curta

| Pergunta | Resposta |
|---|---|
| O que do GymRats é relevante? | Quatro grupos: as regras de grupo (clube ou desafio, pontuação, limites, verificação, revisão, moderação), o check-in publicado em vários destinos, a constância (sequências, metas, recordes) e o social leve (feed, deck, reações, ranking entre amigos). Integrações Android, anúncios, Rat Pack geolocalizado e o deep link por fingerprint não servem ao GymBros. |
| O que já está implementado? | Quase tudo do grupo acima, **no cliente**. O GymBros já passou o GymRats em musculação, na gamificação (bros, evolução, X1, trocas, rodada suíça) e em denúncia de conteúdo. A diferença está no servidor: as regras de liga valem só no aparelho e o Firestore aceita qualquer gravação feita "em seu nome". |
| O que pede cache ou processamento assíncrono? | Os pedidos de hoje: (1) o `fetch` da liga relê toda a temporada a cada abertura, e o clube nunca fecha temporada; (2) o feed de amigos lê todos os posts de cada amigo; (3) X1 e caixa de entrada consultam o servidor a cada 45 s; (4) `ranking`/`swiss` são recalculados a cada render. Os pedidos futuros que precisam de servidor: push, placar oficial e campeões fechados. |
| O que deve continuar síncrono? | XP e evolução, a validação do check-in antes de postar, entrar/banir/aprovar, a resposta do X1 e da troca com hora do servidor, a revisão do dono, curtidas e cópias de rotina, a exclusão de conta e, quando existir, a atribuição de treino pelo coach. |
| Agora, depois, nunca? | Seção 7. **Agora**: limitar as consultas, aplicar as regras de liga no `firestore.rules`, cache local incremental da liga e cache do ranking no aparelho. **Depois** (Blaze + conta paga da Apple): Cloud Functions para push, placar e campeões. **Nunca**: Redis, filas próprias, workers dedicados, WebSocket próprio, anúncios, fingerprint. |
| Qual arquitetura? | A atual, endurecida: **local primeiro** (SwiftData como fonte da verdade, estado derivado) + **Firestore como registro compartilhado**, com consultas limitadas e regras que conferem a liga. Quando o push ou o tamanho das ligas exigirem, entram **triggers do Firestore** (Cloud Functions) como a única camada assíncrona. Não há fila nem worker antes disso. |

---

## 2. Funcionalidades do GymRats contra o GymBros

### 2.1 Treino, biblioteca e evolução

| Funcionalidade (GymRats) | GymBros | Status | Implicação | Decisão |
|---|---|---|---|---|
| Treino ao vivo "Guiado" (uma série por vez, último/alvo, desfazer) | Modo guiado em `Train/WorkoutView.swift`, Live Activity, controles e Watch | Existente | Local, sem rede | — |
| Tipos de série: peso×reps, reps, tempo, distância×tempo, peso×tempo | Tem peso×reps, reps (peso do corpo), isometria e distância×tempo. **Não tem peso×tempo** (carry, prancha com anilha) | Parcial | Local; muda o modelo `LoggedSet` (SchemaV6) | Depois, se aparecer demanda real |
| Recordes por exercício (maior carga, volume, reps) | `PRBook`, 1RM Epley, gráfico por exercício (GymRats não tem 1RM) | Existente (à frente) | Local | — |
| Progressão automática, deload, superset, aquecimento | `Progression.swift` (o GymRats não tem) | Existente (à frente) | Local | — |
| Biblioteca de exercícios | 262 exercícios embutidos (`wger.json`), personalizados, mapa muscular | Existente | Estática, já embutida: não precisa de cache remoto | — |
| Rotinas públicas (salvar, curtir, ordenar, dos amigos) | `Train/PublicRoutines.swift` + coleção `routines` com contador ±1 nas regras | Existente | Leitura com `limit(300)` (`FirebaseGame.swift:265`): basta por ora. Os contadores precisam continuar síncronos | — |
| Estatística da rotina (última vez, tempo médio, 8 semanas) | README: "frequência e tempo médio" | Existente | Derivada localmente | — |
| Importar do Saúde com dedup, agrupado por dia | `HealthSync` (uuid, sobreposição > 50%) + "Postar automaticamente" (`health.autoPost`) | Existente | Assíncrono no aparelho, ao ficar ativo; a caixa de saída já reenvia | — |
| Fila de sync com retry e backoff (Room `integration_sync`) | `LeagueRemoteStore` com `syncedAt == nil` + `LeagueOutbox`; o envio para no primeiro erro (dívida 6) | Existente | É a fila que o app precisa. Falta só o backoff explícito e mostrar o erro | Agora (pequeno) |
| **Coach cria treinos e atribui a alunos ou grupos** | Não existe papel de coach. Existem: "Treino do coach" importado por texto/OCR, só local (`Train/WodImport.swift`), e o **treino do dia** que o dono posta na liga (`DailyWorkout`, `LeagueRules.swift:553`), um por dia, para o grupo inteiro | Parcial (grupo, sem acompanhamento); inexistente (aluno individual, aderência) | Gravação síncrona; aderência derivada dos check-ins; aviso ao aluno precisa de push | Seção 6 |

### 2.2 Check-in e verificação

| Funcionalidade | GymBros | Status | Implicação | Decisão |
|---|---|---|---|---|
| Um check-in em vários grupos e no perfil, editar/apagar "em todos" ou "escolher onde" | "Postar em" com várias ligas, perfil como destino (`ProfileFeed.id`) | Existente | Um documento por destino em `checkIns`, envio em lote | — |
| Presets de verificação (Standard / Rat-ification / Custom) e as 6 políticas | `CheckInVerification` (`LeagueRules.swift:193`): Padrão, Bro-verificação, Personalizar | Existente **só no cliente** | O Firestore aceita qualquer check-in de quem está logado (`firestore.rules:55`) | Agora: parte nas regras. O resto depois, numa Function |
| Hora verificada (EXIF ou aparelho) e `verification_method` | `CheckInProof` (origem da foto, aparelho, pose) vai no check-in (`proof`) | Existente | O servidor não confere a prova, que é declarada pelo próprio aparelho | Aceitar como "honra + revisão do dono" até haver Function |
| Validação antes de postar, com "como corrigir" por grupo | `VerificationProblem` com `fix` (`LeagueRules.swift:322`) | Existente | Síncrona, no aparelho. Mantém | — |
| Revisão do dono (aprovar/negar) | `CheckInReview`, `reviewRequired` | Existente só no cliente | Decisão síncrona; o efeito no ranking é derivado | — |
| Pose do dia | `posesEnabled`, a pose vai no `proof` | Existente | Determinística pelo dia, sem servidor | — |
| Várias atividades por check-in, até 5 fotos | Existente (`extraPhotosData`) | Existente | Fotos não sobem: `NoPhotoStore`, decisão do usuário | Depois (Blaze ou conta Apple) |
| Check-in automático por academia parceira (Smart Fit/TotalPass) | Visita verificada por geofence (`GymLocation`, `CLMonitor`) vale como prova | Parcial (sem parceria) | Local | Parceria: depois, e só com acordo comercial |

### 2.3 Ligas, pontuação e moderação

| Funcionalidade | GymBros | Status | Implicação | Decisão |
|---|---|---|---|---|
| Clube permanente e desafio com datas, reiniciar, temporadas | `LeagueFormat`, `LeagueRenewal`, `nextUUID`/`seriesID` | Existente | A renovação é calculada em cada aparelho; temporadas antigas só existem localmente | Mantém |
| Converter desafio em clube e vice-versa | Não encontrado | Inexistente | — | Nunca, salvo pedido real (baixo valor) |
| Modos de pontuação (treinos, dias, distância, duração, kcal, pontos) e pontos por atividade (por vez/quantidade, negativos) | `LeagueScoring` + `pointRules` + "Você diz" | Existente | O placar é derivado no aparelho a partir do feed inteiro | Agora: cache no aparelho. Depois: placar oficial no servidor |
| Limites diário, semanal, mensal e total, por pessoa e por time | `ScoringLimits` | Existente | `min()` na agregação, barato | — |
| Ranking desligado e metas coletivas | `rankingsDisabled`, `individualGoal`, `teamGoal` | Existente | — | — |
| Campeões da semana, do mês e do ano no clube | `LeagueWinners.swift`, derivados do feed desde o início do clube | Existente | **Consistência**: com retroativo "Qualquer", um check-in novo muda o campeão de um período já encerrado. **Escala**: o clube precisa do feed inteiro | Agora: período fecha depois da janela de retroativo. Depois: campeões gravados por Function |
| Desempate | Três critérios à escolha (o GymRats só divide o 1º lugar) | Existente (à frente) | — | — |
| Times | Existente, com o "bro do time" | Existente | `teams` roda `Game.snapshot` por membro, sem cache (dívida 1) | Agora: memoizar |
| Admin, mod, ban, aprovação de entrada, prévia, troca de dono, export CSV | Tudo na interface (`LeagueModerationViews.swift`) | Existente só no cliente | `mods`, `banned`, `approved` e `isPrivate` ficam dentro de `settings`, **uma string JSON** (`FirebaseBackend.swift:396`), que as regras não conseguem ler. Banido entra e posta direto pela API; liga privada é legível por qualquer conta logada; mod não grava nada na liga (só o `owner`, `firestore.rules:41`) | **Agora** |
| Desafios dentro do clube, treino do dia | `parentClub`, `ClubChallengesSection`, `DailyWorkout` | Existente | `servidor-real.md`: "o servidor precisa pôr quem é do clube no desafio novo" | Agora, junto das regras |
| Rat Pack (desafios públicos por mapa) | Não existe | Inexistente | Precisa de índice geográfico, moderação pública e escala | Nunca no curto prazo |

### 2.4 Social

| Funcionalidade | GymBros | Status | Implicação | Decisão |
|---|---|---|---|---|
| Feed unificado (Todos/Amigos/grupo), sem repetir post | `FriendsFeed.swift` (em andamento: ligas públicas no feed) | Existente | Montado na leitura, por amigo. `leaguePosts` traz **todos** os check-ins `feed == true` da pessoa e só depois filtra os 7 dias no cliente (`FirebaseBackend.swift:298-302`); `profile` traz todos os posts do perfil, sem data nem limite (`:289`) | **Agora**: filtro de data na consulta + índice |
| Rat Deck | Deck dos Bros (`SocialExtras.swift`) | Existente | "Visto" guardado no aparelho | — |
| Reações e comentários em check-ins | Coleção `comments` sendo criada (diff não commitado, `firestore.rules:63`) | Parcial (em andamento) | Contagem e "quem reagiu": derivadas da consulta por `item`. Sem contador desnormalizado enquanto não houver Function | Terminar o que já começou |
| Esconder treinos de um amigo, silenciar, arquivar, limpar só do seu lado | `hiddenFrom` no perfil | Existente, **não é sigilo** | O próprio código avisa (`FirebaseBackend.swift:328`): o app respeita, mas qualquer conta lê `checkIns` | Agora: dizer na interface ou aplicar nas regras |
| Ranking entre amigos sem liga | "Ranking dos bros" | Existente | Derivado dos posts de perfil já baixados | Herda o limite de data acima |
| Amigos por código, link e QR; por contatos | Código e QR existem; contatos não | Parcial | Contatos pede hash de telefone no servidor | Depois, se o crescimento pedir |
| Mensagens diretas, voz, GIF | DM com texto, força e convite, em tempo real (`directMessages`); sem voz nem GIF | Parcial | Listener com 90 dias, índice já existe | GIF/voz: nunca no curto prazo (Klipy, custo de mídia) |
| Notificações por grupo e sininho | `LeagueNotifications.swift`, `NotificationTopic` | Existente, **só locais** | Push com o app fechado precisa de Function + APNs | Depois |
| Denúncia de conteúdo | `Moderation/` + `reports` (o GymRats não tem) | Existente (à frente) | A fila de 24 h é manual (guideline 1.2) | — |

### 2.5 Constância, engajamento e monetização

| Funcionalidade | GymBros | Status | Implicação | Decisão |
|---|---|---|---|---|
| Sequências diária, semanal e mensal; metas por cadência; recordes; madrugador e coruja | `Profile/Constancy.swift` (11 modelos com os temas do GymRats) | Existente | Derivados localmente | — |
| Ratrospective em vídeo | `Activities/Retrospective.swift` (`AVAssetWriter`) | Existente | No aparelho; dispensa worker | — |
| Widget com a última foto | "Último treino dos bros" | Existente | Lê do App Group | — |
| Fake door ("interessado / não é pra mim") | "Vem aí", **gravado só em `UserDefaults`** (`ProAndComingSoon.swift:128`) | Parcial | O voto não chega a ninguém | Depois: um documento por voto, se for usado para decidir |
| Pro (RevenueCat no GymRats) | `ProStore` com StoreKit, `enforced = false` | Planejada | Validação de recibo: StoreKit 2 no aparelho basta | Ao publicar |
| Anúncios, desafios patrocinados, AdMob | Não existe | Inexistente | — | Nunca (identidade e privacidade) |
| Temas (18 presets) | Identidade fixa escura + #A3E636 | Inexistente por decisão | — | Nunca |
| Deep link por fingerprint (Lantern) | Não existe | Inexistente | Arriscado no iOS (ATT) | Nunca; Universal Links + código |
| Health Connect, Samsung, Garmin, Fitbit, Strava | HealthKit cobre Watch, Garmin e Strava, que gravam no Saúde | Inexistente (não precisa) | — | Strava direto: nunca no curto prazo |

### 2.6 Só no GymBros (sem equivalente no GymRats)

Bros com evolução derivada do histórico, BroBook, X1 com hora do servidor, trocas, rodada suíça, treino ao vivo no mapa, "Ouvindo agora", WOD com OCR e Apple Intelligence, mapa muscular e progressão de carga. A arquitetura precisa proteger esses diferenciais. Nada aqui pede infraestrutura nova.

---

## 3. O que o código mostra sobre cache, filas e escala

**Leituras sem limite (Spark: 50 mil leituras por dia para o projeto inteiro)**

1. **Liga.** `FirebaseLeagueBackend.fetch` (`FirebaseBackend.swift:341`) lê numa só abertura todos os membros, todos os check-ins desde `league.start`, todos os recados (sem data) e todos os pedidos de entrada. `LeaguesView.swift:65` chama isso para **todas** as ligas ao abrir a lista. No clube, `start` é a criação, então a leitura só cresce. `docs/firebase.md` já calcula 100 a 300 leituras por abertura numa liga de 20 pessoas. Com 50 pessoas abrindo 3 ligas 5 vezes por dia, isso dá cerca de 150 mil leituras, três vezes a cota do dia.
2. **Feed de amigos.** `leaguePosts` filtra os 7 dias no cliente, mas cobra o histórico inteiro; `profile` lê todos os posts do perfil. O custo é N amigos × histórico.
3. **Polling.** A caixa de entrada atualiza a cada 45 s e o X1 a cada 3 ou 30 s (dívida 1). Cada `getDocuments` cobra todos os documentos do resultado, mesmo sem mudança: o SDK só aproveita o cache local quando há listeners.

**Consistência**

4. As regras de liga ficam numa string JSON (`settings`), e por isso o servidor não confere banimento, aprovação, privacidade nem moderador (`firestore.rules:41-84`). Qualquer pessoa logada cria `members/{liga}-{eu}` e posta em qualquer liga.
5. Campeões e temporadas são derivados e podem mudar depois de encerrados quando o retroativo é livre.
6. Trocas: cada aparelho aplica a sua parte, com um registro local idempotente (`TradeLedger.applied`). Não há duplicação no mesmo aparelho. Sem Function, o servidor não garante que os dois lados aplicaram. É aceitável porque o bro é cosmético e a regra está documentada.

**CPU no aparelho**

7. `LeagueBoard.ranking/teams/swiss` não têm cache. A rodada suíça percorre todos os dias da liga, com até 5 mil passos por rodada, e é chamada sem `swiss:` no card da lista e no `WeeklySummary`. É uma necessidade concreta de memoização, não de servidor.

**O que já está certo e deve ficar**

- Caixa de saída com `syncedAt` e envio serializado (`LeagueRemoteStore.flush`).
- `Game.cachedSnapshot` e hash do perfil público (só publica se mudou).
- Cópia da conta com debounce de 5 s, comprimida e em pedaços.
- Fotos em `Caches/Photos`.
- Mensagens e "ao vivo" por listener, com gravação a cada 30 s no máximo.

---

## 4. Síncrono ou assíncrono

**Continuam síncronos** (a resposta ao usuário depende do resultado, ou a regra de negócio quebra se atrasar):

| Operação | Por quê |
|---|---|
| XP, evolução, espécie fixada na chocagem | Estado derivado do log local. Não pode depender de rede |
| Validar o check-in contra as regras da liga, antes de postar | O usuário precisa saber na hora o que corrigir |
| Entrar, banir, aprovar, transferir dono | Acesso: se atrasar, um banido posta no intervalo |
| Responder X1 (24 h) e troca (48 h) com `request.time` | O prazo é a regra. Já está nas regras do Firestore |
| Decisão de revisão do dono | É ela que libera o check-in para o ranking |
| Curtir e salvar rotina (±1) | Contador conferido nas regras |
| Excluir conta (servidor primeiro, depois o aparelho) | Requisito da Apple (5.1.1(v)). Já está assim |
| Coach atribuir treino; aluno concluir com `assignmentID` | O aluno precisa ver o treino ao abrir e o coach precisa ver a conclusão (seção 6) |

**Podem ser assíncronos** (o resultado pode chegar depois sem quebrar nada):

| Operação | Como já é ou como deve ser |
|---|---|
| Subir check-ins, recados, retiradas | Caixa de saída (já existe) |
| Cópia da conta | Debounce e segundo plano (já existe) |
| Importar do Saúde e postar automaticamente | Ao ficar ativo (já existe) |
| Notificações | Locais hoje. Depois, push por trigger |
| Placar oficial e campeões fechados | Derivados no aparelho hoje. Depois, trigger `onCreate/onDelete` de `checkIns` e um agendamento semanal |
| Upload de fotos e miniaturas | Redimensionar no aparelho e subir em segundo plano, sem worker |
| Retrospectiva, card de stories, export CSV | No aparelho |

---

## 5. Por que não há fila nem worker agora

- O único processamento que não cabe no aparelho é **reagir a gravações de outras pessoas**: push, placar oficial, conferir regras que o `firestore.rules` não expressa. No ecossistema já escolhido, a ferramenta para isso é o trigger do Firestore (Cloud Functions). Ele já entrega o evento de forma assíncrona e pelo menos uma vez. Redis, Pub/Sub, Cloud Tasks ou um worker próprio duplicariam essa entrega sem resolver nada a mais.
- O Blaze e a conta paga da Apple bloqueiam essas peças, e o usuário decidiu ficar no custo zero (memória: fotos fora da nuvem "por enquanto"). A sequência certa é usar o que o Spark já oferece (regras, índices, consultas limitadas, listeners) e ligar Functions quando o push for necessário.
- O cache que faz falta é **no aparelho**: liga incremental e ranking memoizado. Um cache de servidor não diminuiria as leituras cobradas.

---

## 6. Coach: o que existe e o menor desenho que resolve

**Hoje**
- O coach é externo. O aluno importa o texto ou o print do WOD (`WodImport.swift`), que fica só no aparelho (`UserDefaults("plannedWods")`).
- O dono de uma liga posta **um** treino do dia para todos (`DailyWorkout`: título, exercícios com séries e reps, observação), gravado dentro de `settings`.
- Ninguém vê se o treino foi feito.
- O RBAC tem só ADMIN, DEVELOPER e USER (`Access/Access.swift`), papéis globais, e coach não deve ser um deles.

**Desenho proposto (cabe no Spark, sem Function)**
1. **O papel de coach é por grupo, não global.**
   - Para grupos, quem é dono ou moderador de um clube já é o coach daquele clube.
   - Para alunos individuais, o **aluno** cria `coachLinks/{aluno}->{coach}`, o que registra o consentimento. Funciona como o `friendLinks`, e as regras conferem com `exists()`.
2. **Coleção `assignments/{id}`**, com os campos:
   - `coach`, `target` (`league:<código>` ou `user:<uid>`), `day`, `title`;
   - `items` (exerciseID, séries, reps, carga alvo opcional) ou `wod` (texto já estruturado pelo `WodParser`);
   - `note` e `createdAt == request.time`.
   - Só o coach do alvo grava. Leem os membros do clube ou o aluno.
   - O `DailyWorkout` passa a ser um caso particular: alvo = clube, um por dia.
3. **Conclusão = check-in com `assignmentID`.** O aluno conclui pelo treino guiado ou pelo WOD que já existem. O check-in sobe pela caixa de saída de hoje, com o campo novo. O coach vê a aderência consultando `checkIns` por `assignmentID` (índice novo). Não existe estado "concluído" separado para ficar fora de sincronia.
4. **Privacidade.** Séries e cargas registradas no app podem ir para o coach. Valores do Saúde não vão, pela mesma regra de `OutgoingCheckIn` (5.1.3(ii)). Isso precisa entrar nos termos e na política.
5. **Aviso ao aluno.**
   - Agora: notificação local quando o app abre, igual à caixa de entrada.
   - Depois: push por trigger `onCreate` de `assignments`. É a primeira Function que se paga.

O que não fazer agora: planos de periodização com várias semanas, marketplace de coaches e cobrança. Nenhum deles aparece nos requisitos atuais.

---

## 7. Agora, depois, nunca

### Agora (Spark, sem custo novo)

1. **Limitar as consultas.**
   - `leaguePosts`: `whereField("date", isGreaterThanOrEqualTo: since)` + índice `user, feed, date`.
   - `profile`: posts de 90 dias ou `limit`.
   - `fetch`: recados com janela de data.
   - Clube: carregar só o período em uso (ano corrente ou janela do ranking pedido).
2. **Cache incremental da liga no aparelho.**
   - Gravar `RemoteLeague` em disco por `LeagueKey`.
   - Na próxima abertura, buscar só `updatedAt > última busca`.
   - Apagar vira `deleted: true` em vez de `delete`, porque a busca incremental não enxerga exclusões.
   - Na lista de ligas, atualizar só a liga aberta e as que mudaram, não todas.
3. **Regras de liga no `firestore.rules`.**
   - Promover `mods`, `banned`, `approved`, `requiresApproval` e `isPrivate` a campos nativos do documento da liga. `settings` continua com o resto.
   - Regras:
     - `members` só se não estiver banido e, quando há aprovação, se estiver aprovado;
     - `checkIns` só para membros;
     - leitura de liga privada só para membros;
     - mod pode atualizar só esses campos.
   - Testar com contas temporárias via REST, como já é feito.
4. **Memoizar `ranking`, `teams` e `swiss`** por (chave da liga, hash do feed, dia). Passar a tabela suíça pronta no card e no `WeeklySummary`.
5. **Trocar o polling por listeners.**
   - X1 e trocas: `addSnapshotListener` enquanto a tela estiver aberta.
   - Caixa de entrada: só ao ficar ativo, como as mensagens já fazem.
6. **Fechar períodos.** Campeão de semana ou mês só é final depois da janela de retroativo da liga. Antes disso, a interface mostra "provisório".
7. **`hiddenFrom`.** Ou a interface deixa claro que não é sigilo, ou a regra entra junto com o item 3.
8. **Caixa de saída**: backoff simples e o erro visível nos Ajustes (dívida 6).
9. Coach, passos 1 a 3 da seção 6, se for a próxima frente de produto.

### Depois (com Blaze e/ou conta paga da Apple, quando houver usuários reais)

- **Push** por trigger (mensagens, X1, trocas, treino atribuído, campeões) com APNs.
- **Placar oficial**: trigger em `checkIns` grava `leagueScores/{código}/{período}`, idempotente pelo id do check-in, em transação. O aparelho continua calculando a prévia.
- **Campeões** gravados por agendamento semanal e mensal.
- Conferir no servidor a verificação e a revisão que as regras não expressam (`servidor-real.md`).
- Fotos (Cloud Storage ou CloudKit), já redimensionadas no aparelho.
- Votos do "Vem aí" no Firestore; tipo de série peso×tempo, se for pedido; amigos por contatos, só com opt-in.

### Nunca (ou só com uma razão nova e explícita)

Redis ou cache de servidor, filas próprias (Pub/Sub, Cloud Tasks), workers dedicados, WebSocket próprio, backend próprio no lugar do Firebase antes do Firebase ficar pequeno, AdMob e desafios patrocinados, deep link por fingerprint, temas de cor, converter desafio em clube, Rat Pack geolocalizado, integrações Android, cópia da arquitetura híbrida Kotlin + RN do GymRats.

---

## 8. Arquitetura recomendada

```
iPhone (fonte da verdade)                         Firestore (registro compartilhado)
──────────────────────────                        ─────────────────────────────────
SwiftData: atividades, treinos, bros  ──derivado──▶ XP, evolução, metas, recordes (só local)
Caixa de saída (syncedAt, retiradas)  ──lote────▶ checkIns, messages, members, assignments
Cache em disco por liga (incremental) ◀─updatedAt── consultas limitadas por data
Memo de ranking/suíço/times                        regras: dono, mods, banidos, privados, coach
Listeners só com a tela aberta        ◀─tempo real─ directMessages, live, duels, trades

                         ── só quando o push ou o tamanho pedirem ──
                         Cloud Functions (triggers): push, placar, campeões
```

Princípios:
1. O que é do usuário continua local e derivado.
2. O servidor guarda só o que é compartilhado, e as regras conferem quem pode gravar.
3. O cache é no aparelho e incremental.
4. O assíncrono no servidor entra como trigger, não como fila.
5. Cada peça nova precisa de um número que a justifique: leituras por dia, tamanho da liga ou push pedido pelos usuários.
