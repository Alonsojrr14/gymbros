# Contrato do Firestore e da cópia da conta

**Escopo.** O que o app Android tem de ler e gravar para conviver com o iOS no mesmo projeto Firebase (`gymbros-zerobyte`, plano Spark: Auth e-mail/senha + Firestore, sem Functions nem Storage), sem mudar o servidor. Complementa `docs/firebase.md` e `docs/servidor-real.md`.
**Base de evidência.** `firebase-contract-analyst` (Opus 5.5) lendo `GymBros/Services/Firebase*.swift`, `AccountSync.swift`, `Backup.swift`, `CommentSync.swift`, `firebase/*`; conferências do orquestrador marcadas com (O). **Nenhum acesso ao Firebase real.**
**Status.** Rodada 1. Mudanças não commitadas do dono incluídas e marcadas "novo".

## 1. Convenções de tipo (valem para todas as coleções)

| Swift | Firestore | Android (Kotlin) | Nota |
|---|---|---|---|
| `Date` | Timestamp | `com.google.firebase.Timestamp` | |
| `Int` | integer (int64) | `Long` | o iOS lê `as? Int`: double com fração é ignorado. Grave sempre inteiro |
| `Double` | double | `Double` | |
| `nil` via `Fire.fields` | **null explícito** | aceitar ausente **e** null | `FirebaseBackend.swift:31-33` |
| UUID | string **maiúscula** (`uuidString`) | `UUID.toString().uppercase()` | ids de checkIns, messages, comments, trades |
| struct em campo texto | **string com JSON** (`settings`, `proof`, `public`, `give`/`get`, `bros`, `items`) | kotlinx.serialization para string | chaves ordenadas (`sortedKeys`); valor padrão grava `""` |
| `Date` dentro desses JSONs | **Double de segundos desde 2001-01-01** (`.deferredToDate`, referência da Apple) | converter com o deslocamento 978 307 200 s | (O) `LeagueRules.swift:83-85`; `CheckInProof.swift:100` usa o padrão do `JSONEncoder` (mesmo efeito) |
| hora de servidor | `FieldValue.serverTimestamp()` | `FieldValue.serverTimestamp()` | **obrigatória** onde a regra exige `== request.time` (duels, trades, reports, routines) |

## 2. Coleções

| Coleção / id | Campos | Hora | Evidência |
|---|---|---|---|
| `profiles/{uid}` | name, username, bio, friendCode: str; broFormID: str?; public: str? (JSON `{bro:{name,formID,level,progress}?, stats:{checkIns,activeDays,leagues}?, achievements:[{title,symbol}]?}`); hiddenFrom: [str]; leaguePosts (novo) | — | `FirebaseBackend.swift:297-332` |
| `friendLinks/{from}->{to}` | from, to | — | `:256`. Amizade = os dois sentidos; recusa só no aparelho (`declinedFriendRequests`) |
| `leagues/{code}` (6 car. de `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`) | code, owner, name, emoji, scoring, weights, tieBreak, photoRule, teams: str; activityRule, settings (JSON `LeagueSettings`), swiss: str?; start: TS; end: TS?; autoRenew: bool | aparelho | `:391-410,468` |
| `members/{code}-{uid}` | league, user, name, formID; teamID?; joinedAt: TS? | aparelho | `:412-418` |
| `checkIns/{UUID}` | league (código ou `"profile"`), user, date: TS, kind, minutes, effort: int, meters?, kcal?: double, title, note, hasPhoto: bool, photo: str? (hoje sempre null), workoutType: int?, place?, proof? (JSON), feed: bool (novo) | aparelho | `:421-437,474-484` |
| `comments/{UUID}` (novo) | user, userName, item, owner, text (1–500), date: TS | aparelho | `CommentSync.swift:35-47`; lido com `item in [≤30]` |
| `messages/{UUID}` | league, user, text (≤1000), date | aparelho | `:380-389` |
| `joinRequests/{code}-pedido-{uid}` | league, user, name, formID, date | aparelho | `:452-457`; aprovação = uid em `settings.approved` |
| `directMessages/{id}` | from, to, participants `[from,to]`, date, kind, text (≤2000), replyTo?, accepted?, invite? `{kind, place, when?, latitude?, longitude?}` | aparelho | `FirebaseSocial.swift:43-54`; ouvinte `participants array-contains` + últimos 90 dias |
| `live/{uid}` | user, name, formID, kind, place, now, start?, done: [str], sets?, meters?, latitude?, longitude?, route: [double] (pares lat,lon achatados, ≤100 pontos), music? `{title,artist,source}`, endedAt, updatedAt | aparelho | `FirebaseSocial.swift:193-215`; "parado" após 15 min |
| `duels/duel-{UUID}` | challenger, challengerName, challengerFormID, challenged…, metric, participants, createdAt (servidor), answer, answeredAt (servidor), `score_{uid}`: int | servidor | `FirebaseGame.swift:70-98` |
| `trades/{UUID}` | from, fromName, fromFormID, to…, participants, give/get (JSON `TradeBro {id,name,formID,xp,attributes,history}`), createdAt/answeredAt (servidor), answer | servidor | `:143-168`; `Trades/Trade.swift:11-24` |
| `tradeBros/{uid}` | user, bros (JSON [TradeBro] ordenado por id), updatedAt | aparelho | `:137-141` |
| `reports/{uid}-{chave}` | user, kind, contentID, author, authorName, reason, date (servidor) | servidor | `:176-182` |
| `blocks/{uid}->{blocked}` | user, blocked, name, date | aparelho | `:184-189` |
| `roles/{uid}` | roles: [str] | — | `:208-254` |
| `routines/{id}` | user, name, authorName, authorFormID, items (JSON `[{exerciseID,sets,reps,rest}]`), likes, saves (increment), createdAt (servidor) | servidor | `:275-298` |
| `accounts/{uid}` + `chunks/{n}` | ver seção 4 | misto | `FirebaseGame.swift:301-358` |

Consultas com índice composto (`firebase/firestore.indexes.json`): checkIns `league == code && date >= start`; checkIns `user == id && feed == true`; checkIns `league == "profile" && user == id`; duels/trades `participants array-contains && createdAt >= agora-30d`; routines `createdAt desc limit 300`; reports `date desc limit 200`.

## 3. Ciclo de vida da conta

| Etapa | Comportamento | Status |
|---|---|---|
| Cadastro | e-mail/senha; grava `displayName`; envia verificação em pt-BR | VERIFIED |
| Verificação de e-mail | **não exigida** para entrar nem pelas regras; só aviso em Ajustes | VERIFIED (O) |
| Sign in with Apple | código real (nonce SHA-256, ligação por mesmo e-mail via `PendingLink`), mas **desligado**: botão só com `appleCapabilities` (false); sem entitlement; provedor ausente em `firebase.json` | VERIFIED (O) |
| Entrar | `AccountSync.enter`: se este aparelho já é o dono (`accountDataOwner == hash(uid)`), **não baixa nada**; senão guarda os dados locais à parte, baixa e restaura **tudo** | VERIFIED (O) `AccountSync.swift:151-182` |
| Sair | sobe a cópia, apaga local, `signOut`; se a cópia não sobe, continua logado | VERIFIED |
| Excluir conta | apaga `accounts` + chunks; depois consulta e apaga `members`, `checkIns`, `messages`, `joinRequests`, `friendLinks` (from), `blocks`, **`reports`**, `routines`, `comments`; depois `profiles`, `live`, `tradeBros`; por último o Auth. Ficam: DMs, X1, trocas, vínculos de outros para você, ligas de que você é dono (órfãs), roles | VERIFIED |
| **Bug provável na exclusão (1)** | a consulta `reports where user == me` (`FirebaseBackend.swift:155-157`) é negada a quem não é admin (`allow read: if isAdmin()`), e o Firestore recusa a consulta inteira. `deleteAccount` lança erro, `AccountSync.deleteAccount` (`:233-251`) devolve a cópia ao servidor e **a conta não é excluída** (requisito da App Store) | VERIFIED (código e semântica das regras, O) / não executado |
| **Bug provável na exclusão (2)** (revisor, confirmado por O) | mesmo com `reports` corrigido, `live/{me}` está no lote de `Fire.delete` (`FirebaseBackend.swift:159-162`), e a regra de `live` só tem `allow write` exigindo `request.resource.data.user == uid()` (`firestore.rules:193`). Na exclusão, `request.resource` é nulo e a operação é negada. Até 450 referências o lote é atômico e nada é apagado; acima disso os lotes anteriores já foram gravados e a exclusão fica pela metade (`FirebaseBackend.swift:35-41`) | VERIFIED (código e regras) / não executado |
| **Exclusão parcial** (revisor, confirmado por O) | a ordem é cópia → dados sociais → Auth. Se `currentUser.delete()` falhar com `requiresRecentLogin`, os dados sociais já foram apagados e a conta continua; a cópia é reenviada. Contradiz `docs/excluir-conta.md:18` ("nada é apagado") e `:26` ("nada fica guardado em outro lugar"; falso no modo Firebase) | VERIFIED (código) / INFERRED (cenário) |

## 4. Cópia da conta (`accounts/{uid}`)

- **Formato:** `Backup` (`Backup.swift:8-156`, `version = 1`): `version`, `exportedAt`, `settings{str:str}`, `typedSettings{str:Setting}`, `activities`, `routines`, `sessions`, `customExercises`, `leagues`, `monsters`, `body`, `notes`, `checkIns`, `routes`, `visits`, `gyms`, `wods`, `prs`, `comments`, `messages`, `reviews`, `profilePhoto`, `hasSyncState`, `accountSettings`.
- **Codificação:** JSON `sortedKeys` + `prettyPrinted`; datas **ISO 8601 sem fração de segundo**; `Data` em base64 (`Backup.swift:500-511`). `accountSettings` é **plist binário** com as `AccountData.userKeys` (`Auth.swift:221-241`: `friendCode`, ledger de trocas, `RetiredActivities`, `duelScoreRecords`, `activitySplits`…). `Setting` é enum com valor associado (`{"bool":{"_0":true}}`, INFERRED). `RouteDTO.points` é `Data` em formato próprio (UNKNOWN).
- **Envio** (`FirebaseGame.swift:317-336`): grava arquivo local com fotos → tira fotos (body, check-ins, mensagens) → hash SHA-256 do JSON com `exportedAt = distantPast` → se igual ao último enviado, para → `NSData.compressed(using: .zlib)` (**DEFLATE cru, RFC 1951**, INFERRED pela documentação da Apple; Android: `Inflater(nowrap = true)`) → pedaços de **900 000 bytes** em `chunks/{n}` (`{data: Bytes}`) → apaga pedaços sobrando → meta `{user, chunks, bytes, hash, savedAt (relógio do aparelho), updatedAt (servidor)}`, tudo num batch.
- **Quando sobe:** 5 s depois de qualquer gravação no banco ou nos `UserDefaults`; ao ir para o fundo; ao entrar; ao sair.
- **Restauração:** fica a cópia local se `exportedAt` local ≥ `savedAt`; senão lê todos os pedaços (sem transação), descomprime, decodifica e substitui tudo.
- **Bug provável (revisor, confirmado por O; INFERRED, não executado):** o arquivo local grava `exportedAt` em ISO 8601 **sem fração** (`Backup.swift:500-504`), enquanto `savedAt` na nuvem é um Timestamp **com fração** do mesmo instante (`FirebaseGame.swift:332`). Ao sair e entrar no mesmo iPhone, `mine.exportedAt >= saved` (`:342`) quase sempre dá falso, vence a cópia da nuvem, que não tem fotos, e **as fotos locais se perdem**. Isso contradiz o comentário em `FirebaseGame.swift:303-306`. O Android não deve repetir essa comparação: comparar por `hash` ou truncar os dois lados.
- **Limite do lote:** a cópia vai num único lote com todos os pedaços. Uma requisição do Firestore tem teto de cerca de 10 MiB (INFERRED), ou seja, uns 11 pedaços. Acima disso a sincronização para de funcionar. Ver P10.
- **XP não é guardado:** é recalculado por `Game.snapshot` a partir de `activities` (+ `attributes` gravados por atividade). Bros recebidos por troca têm a base na ledger do plist.

## 5. Mesma conta no iPhone e no Android

**Hoje é "última escrita vence", para a cópia inteira, e quem já é dono nunca rebaixa.** Com os dois aparelhos ativos: A sobe; B sobe e apaga o que A mandou; A sobe de novo na próxima mudança e apaga o de B. Cada aparelho mantém só os próprios dados locais; a nuvem guarda o último. Um terceiro aparelho recebe o snapshot de quem gravou por último. Leitura de pedaços durante um envio concorrente pode falhar na descompressão (INFERRED). `profiles.friendCode`/`public`, `tradeBros`, `live` e `score_*` do X1 também se sobrescrevem.

**Consequência de projeto (RSK-03):** o Android não pode simplesmente subir a cópia dele. Opções no ADR-007.

## 6. Garantias: servidor × só cliente

| Coleção | Regra protege | Não protege (só o cliente) |
|---|---|---|
| profiles | gravação só pelo dono | campos, unicidade de `friendCode`/nome, `hiddenFrom` público |
| friendLinks | id `from->to`, `from` é você | consentimento do outro; existência de `to` |
| leagues | criação com você dono; edição só pelo dono | leitura (todos), `settings`, aprovados, banidos |
| members | membro é você | poder entrar (privada, aprovação, ban) |
| checkIns | autor é você | valores, data, ser membro; **leitura de qualquer liga por qualquer conta** |
| comments (novo) | autor, texto 1–500 | `owner` correto, visibilidade, bloqueios |
| messages | autor, texto ≤1000 no create | tamanho no update; leitura ampla |
| directMessages | só as duas pontas; `reachable`; ≤2000 | `date` do aparelho |
| duels | criação/resposta com hora do servidor, 24 h, cada lado só seu placar | **placar autodeclarado e alterável a qualquer momento** |
| trades | 48 h, hora do servidor | conteúdo de `give`/`get`; troca aplicada no cliente |
| routines | likes/saves de 1 em 1 | quem curtiu (curtidas repetidas) |
| reports, blocks, roles, accounts, live | adequadas ao propósito | tamanho e frequência |

Detalhes e severidade em `../seguranca/achados.md`.

## 7. Cálculos do cliente que outras pessoas veem (porte bit a bit)

| # | Cálculo | Onde | Entradas sensíveis |
|---|---|---|---|
| CC-1 | Pontos do check-in: `activityRule.accepts` → `LeagueScoring.score` ou `pointRules.score` → `PhotoRule.apply` (metade = `(s+1)/2`, negativo não passa) | `League.swift:126-131`; `Leagues.swift:150-176,239-247`; `LeagueRules.swift:451-483` | tabelas `ActivityKind.met`/`weights`; `activeKcal = max(met×(0,6+0,08e) − 1, 0) × 3,5 × 70/200 × min`; atividades do Saúde = esforço 5, sem distância/kcal |
| CC-2 | Feed da liga e "dias ativos", tetos por período, revisão pendente vale 0 | `Leagues.swift:551-601`; `ScoringLimits.apply` | **fuso do aparelho**; `settings.weekStart` |
| CC-3 | Ranking e desempate (`tieBreak` → "eu primeiro" → nome) | `Leagues.swift:672-718` | fuso; "eu primeiro" (ND-2) |
| CC-4 | Rodada suíça e bônus | `Swiss.swift:177-300`; `Leagues.swift:437-451,652-669` | fuso fixo de Brasília; `dayStamp` sem zeros; FNV-1a 64 + LCG; orçamento 5 000; `selfID` (ND-1) |
| CC-5 | Times e "bro do time" (média de XP, galho 90%) | `Leagues.swift:610-648` | `Game.snapshot` com fuso do aparelho |
| CC-6 | Campeões (semana/mês/ano; empate divide) | `LeagueWinners.swift:62-80` | `settings.calendar()` = fuso do aparelho + `firstWeekday` da liga |
| CC-7 | Renovação de temporada | `Leagues.swift:297-328` | `Calendar.current`; não atualiza `start`/`end` no Firestore (INFERRED) |
| CC-8 | X1: janela `[answeredAt, +24 h)`; métrica; kcal = `min × met × 1,2` truncado (**diferente da liga**); XP **sem** teto diário | `Duel.swift:61-67,218,252-257` | relógio; usa `publishableKcal` (o Saúde fica fora), **exceto** pelo vazamento do relógio (SEC-A5) |
| CC-9 | Perfil público: `stats`, `level = floor(sqrt(xp/5)) + 1`, `progress` | `Game.swift:481`; `FirebaseBackend.swift:317-325` | — |
| CC-10 | Ao vivo: parado após 15 min; some 12 h após o fim | `FirebaseSocial.swift:322` | relógio de quem lê × `updatedAt` do aparelho de quem grava |

## 8. Limites do Spark que afetam o desenho

50 mil leituras, 20 mil escritas e 20 mil exclusões por dia; 1 GiB armazenado; 10 GiB/mês de saída; 1 MiB por documento; 500 operações por batch. Pontos caros hoje: `fetch` da liga lê **todas** as mensagens, pedidos e check-ins da temporada a cada atualização; um ouvinte por amigo em `live`; ao vivo grava a cada ≥30 s; cada `isAdmin()` custa 2 leituras. **Um segundo app dobra o consumo por pessoa ativa**: o Android deve usar o cache offline do Firestore e não repetir o padrão de reler tudo.

## 9. Requisitos de compatibilidade do Android (sem mudar o servidor)

| ID | Requisito |
|---|---|
| FS-AND-01 | Mesmos nomes, tipos e ids da seção 2; inteiros como `Long`; UUID maiúsculo; `participants` exatamente `[eu, outro]`. |
| FS-AND-02 | `serverTimestamp()` onde a regra exige `request.time`. |
| FS-AND-03 | JSON em string com chaves ordenadas e datas em segundos desde 2001; valor padrão = `""`. |
| FS-AND-04 | Cópia da conta: ler DEFLATE cru, pedaços de 900 000, ISO 8601 em segundos, plist binário em `accountSettings` (precisa de leitor/gravador de bplist). **Vetores reais do iOS para provar** (ver `../plano/estrategia-testes.md`). |
| FS-AND-05 | Não sobrescrever a cópia do iPhone sem baixar e mesclar antes (ADR-007). |
| FS-AND-06 | Não gerar `friendCode` novo se o perfil já tem um. |
| FS-AND-07 | Usar o uid do Firebase como identidade própria em todo cálculo compartilhado (não repetir ND-1). |
| FS-AND-08 | Calcular regras compartilhadas com o mesmo fuso que o iOS usar (hoje: fuso do aparelho, exceto o suíço). Corrigir no iOS é decisão do dono (ADR-006). |
| FS-AND-09 | `proof` também é **entrada de pontuação**: check-in agrupado soma `groupedParts` (`Leagues.swift:573-576`; `CheckInProof.swift:72-74,333-336`). O Android grava `grouped` e `groupedParts` exatamente como o iOS, senão os check-ins agrupados dele pontuam menos nos iPhones. Não determinismo: o autor pontua com as atividades locais **atuais** e os outros com as partes congeladas; editar uma atividade agrupada diverge o placar. |

## Propostas que dependem do dono (não são fatos)
1. Exclusão de conta: (a) `reports`: liberar `list` para o próprio autor ou tirar `reports` do `deleteAccount`; **e** (b) `live`: acrescentar `allow delete: if signedIn() && id == uid()`; **e** (c) reautenticar **antes** de apagar qualquer coisa (evita exclusão parcial). Só (a) não resolve.
2. iOS: `LeagueBoard.selfID` = `Backend.myID` (corrige ND-1).
3. `checkIns`/`comments`: leitura só para membros ou `feed == true`.
4. `messages`: validar tamanho e tipo no update.
5. `duels`: travar `score_*` após `answeredAt + 24 h`; `score >= 0`.
6. Curtidas por usuário em `routines`.
7. Versão/`updatedAt` comparada na cópia da conta, para aparelhos já donos baixarem quando o remoto for mais novo.

## Lacunas
- Regras publicadas × arquivo local (não acessado).
- Formato de `RouteDTO.points` e codificação exata de `Backup.Setting`.
- `hasPhoto` pode ser `true` sem foto na nuvem (`NoPhotoStore`), e afeta `photoRule` (INFERRED).
