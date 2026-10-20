# Backend com CloudKit

O app fala com o servidor só por contratos: `AuthBackend` (`GymBros/Services/Auth.swift`), `AccountDataBackend` (`GymBros/Services/AccountSync.swift`), `LeagueBackend` (`GymBros/Leagues/LeagueRemote.swift`), `FriendsBackend` (`GymBros/Friends/Friends.swift`), `ModerationBackend` (`GymBros/Moderation/Moderation.swift`), `InboxBackend` (`GymBros/Inbox/Inbox.swift`) e `DuelBackend` (`GymBros/Duels/DuelStore.swift`). Quem responde é escolhido em `GymBros/Services/Backend.swift`:

```swift
static let mode: BackendMode = .mock   // .cloudKit quando o app tiver iCloud
```

| Contrato | `.mock` | `.cloudKit` |
|---|---|---|
| `AuthBackend` | `MockAuthBackend`: e-mail ou Apple simulados; excluir conta apaga o cadastro e os amigos simulados | `CloudKitAuthBackend`: folha da Apple (Sign in with Apple) + id do iCloud do aparelho; excluir conta apaga os registros do usuário |
| `LeagueBackend` | `MockLeagueBackend`: participantes simulados | `CloudKitLeagueBackend` |
| `FriendsBackend` | `MockFriendsBackend`: pessoas simuladas | `CloudKitFriendsBackend` |
| `ModerationBackend` | `MockModerationBackend`: denúncias e bloqueios guardados no aparelho | `CloudKitModerationBackend`: registros `Report` e `Block` |
| `AccountDataBackend` | `MockAccountDataBackend`: servidor simulado, um arquivo por conta em `Application Support/MockServer/` | `ServerAccountDataBackend`: lança erro (servidor próprio a definir; ver "Dados da conta") |
| `InboxBackend` | `MockInboxBackend`: amigos simulados respondem mensagens, força e convites | `ServerInboxBackend`: lança `InboxError.needsServer` (conversas privadas não vão para o banco público) |
| `DuelBackend` | `MockDuelBackend`: X1 com pessoas simuladas, guardado no aparelho (`mockDuels`) | `CloudKitDuelBackend`: registros `Duel` |
| `RoleBackend` (`GymBros/Access/AccessStore.swift`) | `MockRoleBackend`: sem atribuição, todo mundo é `USER` | `CloudKitRoleBackend`: lê `RoleAssignment` (só leitura) |

A liga de exemplo (`AMIGOS`) continua simulada nos dois modos. A conta de demonstração da revisão (`DemoAccount`) só existe no `.mock` e não cria tipo de registro; com servidor, a conta demo precisa existir de verdade nele (`docs/app-review.md`).

## Ligar o CloudKit

1. Conta paga do Apple Developer (o Personal Team não tem iCloud nem Sign in with Apple).
2. Xcode → alvo GymBros → Signing & Capabilities → **+ iCloud** → marcar **CloudKit** → container `iCloud.com.alonsoalmeida.gymbros` (o mesmo de `Backend.containerID`). Isso adiciona ao `GymBros.entitlements` as chaves `com.apple.developer.icloud-container-identifiers` e `com.apple.developer.icloud-services`.
   Na mesma tela, **+ Sign in with Apple** (`com.apple.developer.applesignin` = `Default`). Sem ela, "Continuar com a Apple" no modo `.cloudKit` falha (erro 1000 do `ASAuthorizationController`). No `.mock` o botão oficial chama o login simulado e não precisa da capability.
3. Criar o esquema abaixo no CloudKit Dashboard (ambiente Development), com índices e permissões.
4. Trocar `Backend.mode` para `.cloudKit`, rodar no aparelho com uma conta do iCloud e testar com duas contas.
5. Antes de publicar: **Deploy Schema Changes** para Production. TestFlight e App Store usam Production; sem o deploy, o app funciona no Xcode e falha para os usuários. Depois do deploy, o esquema de Production só aceita acréscimos (não dá para apagar nem renomear campos ou tipos).

## Por que o banco local não sincroniza sozinho (SwiftData + CloudKit)

O `AppData.container` (`GymBros/Models/Schema.swift`) usa `cloudKitDatabase: .none` de propósito. A combinação "SwiftData offline + iCloud sincronizando em segundo plano" parece resolver tudo, mas não serve ao GymBros:

- **Só o banco privado.** A sincronização do SwiftData não fala com o banco público nem com o compartilhado. Ligas, amigos, perfis, X1 e moderação precisam de `CKDatabase` direto (é o que os backends `CloudKit*` fazem) e o trabalho offline fica na caixa de saída do próprio app.
- **Apple Saúde não vai para o iCloud** (guideline 5.1.3(ii)). Treinos importados, kcal, distância e peso estão no mesmo banco local. Ligar a sincronização exigiria separar esses modelos num `ModelConfiguration` próprio, sem CloudKit.
- **Separar contas por campo não é segurança.** O banco privado é do iCloud do aparelho, não da conta do app: filtrar por um id do app só esconde na tela. No banco público qualquer instalação lê tudo (World: Read); o CloudKit controla só quem escreve, e pelo usuário do iCloud. A identidade é o `userRecordID` + Sign in with Apple.
- **Regras extras do `@Model` com CloudKit:** toda propriedade com valor padrão ou opcional, relacionamentos opcionais, sem `@Attribute(.unique)` e sem `deleteRule: .deny`.
- **Comportamentos a tratar se algum dia ligar:** o banco privado ocupa o iCloud do usuário (cheio = sincronização para sem aviso); trocar de conta do iCloud apaga a cópia local sincronizada; apagar em Ajustes > iCloud remove só o privado, nunca o público (por isso "Excluir conta" dentro do app, guideline 5.1.1(v)).

Custo: o banco público tem cota grátis que cresce com o número de usuários; acima dela a Apple limita (ou cobra). Na escala do GymBros, é zero.

## Esquema (banco público)

Todos os ids de usuário são o `recordName` do usuário do iCloud (`CKContainer.userRecordID()`).

| Tipo | Nome do registro | Campos | Índices |
|---|---|---|---|
| `Profile` | id do usuário | `name`, `username`, `bio` (String), `friendCode` (String), `broFormID` (String), `public` (String, JSON com bro, números e conquistas; partes escondidas não vão) | `friendCode` Queryable |
| `League` | código da liga | `code`, `owner`, `name`, `emoji`, `scoring`, `weights`, `tieBreak`, `photoRule`, `swiss` (critério da rodada suíça; ausente = `pontos`), `teams` (String), `start`, `end` (Date), `autoRenew` (Int64) | `recordName` Queryable |
| `Member` | `<código>-<usuário>` | `league`, `user`, `name`, `formID`, `teamID` (String), `joinedAt` (Date: dia em que entrou, para a rodada suíça; ausente = `creationDate`) | `league`, `user` Queryable |
| `CheckIn` | uuid do check-in | `league` (código, ou `profile` para posts do perfil), `user`, `date`, `kind`, `minutes`, `effort` (5 em atividade do Apple Saúde), `meters` (só GPS do app), `kcal` (nunca do Apple Saúde), `title`, `note`, `hasPhoto`, `photo` (Asset) | `league`, `user` Queryable; `date` Queryable e Sortable |
| `Message` | uuid do recado | `league`, `user`, `date`, `text` | `league`, `user` Queryable; `date` Sortable |
| `FriendLink` | `<de>-><para>` | `from`, `to` (String) | `from`, `to` Queryable |
| `Report` | `report-<eu>-<tipo>:<id>` | `user` (quem denunciou), `kind` (`checkIn`, `comment`, `message`, `profile`, `photo`), `contentID`, `author`, `authorName`, `reason` (`offensive`, `sexual`, `violence`, `spam`, `other`), `date` | `user` Queryable; `date` Queryable e Sortable (fila da moderação) |
| `Block` | `block-<eu>-><bloqueado>` | `user`, `blocked`, `name` (String), `date` | `user` Queryable |
| `Duel` | desafio: `duel-<uuid>`; resposta: `duel-<uuid>-answer-<id>`; valor: `duel-<uuid>-score-<aleatório>` (nome guardado no aparelho em `duelScoreRecords`). Na leitura só vale o registro cujo `creatorUserRecordID` é o `user` | `kind` (`challenge`, `answer` ou `score`), `user` (quem escreveu), `date`; no desafio `name`, `formID`, `opponent`, `opponentName`, `opponentFormID` e `metric`; na resposta `duel`, `answer` (`accepted`/`declined`) e, ao aceitar, `formID` (bro que vai lutar); no valor `duel` e `value` (Int64) | `kind`, `user`, `opponent`, `duel`, `date` Queryable |
| `RoleAssignment` | `role-<usuário>` | `roles` (String List: `USER`, `DEVELOPER`, `ADMIN`) | nenhum (lido pelo nome) |

X1 não tem liga: quem desafia cria o desafio, quem foi desafiado cria a resposta e cada lado escreve o próprio valor, cada um no próprio registro. Datas valem pelo `creationDate`; a resposta só conta se `user` for o `opponent`. O app busca os desafios dos últimos 30 dias em que é `user` ou `opponent` (duas consultas, o CloudKit não tem OR) e os registros `duel IN [...]`. O valor informado é um agregado das atividades (`Duels.myValue`), que hoje soma também distância e calorias vindas do Apple Saúde; gravado no banco público, isso contraria a guideline 5.1.3(ii) e a política de privacidade. **Recomendação:** antes de ligar o CloudKit, calcular o valor só com os dados publicáveis (os mesmos do `CheckIn`) ou levar o X1 para o servidor próprio. "Um X1 aberto por par" é checado no aparelho (de quem desafia e de quem aceita). "Não desafiar quem te bloqueou" só existe no servidor simulado: no CloudKit, `Block` não é legível por outras contas, então o desafio é gravado e fica escondido só do lado de quem bloqueou (`DuelStore.duels` tira os bloqueados). Com as permissões padrão (World: Read), qualquer instalação lê os `Duel` (nomes, bros, métrica e valores); para restringir, seria preciso servidor próprio ou zonas compartilhadas.

Amizade é um vínculo em cada direção: pedir é criar `eu->você`, aceitar é criar o de volta, desfazer é apagar o seu. Assim ninguém precisa escrever registro de outra pessoa.

### Excluir conta

`CloudKitAuthBackend.deleteAccount` consulta por `user == <eu>` em `Member`, `CheckIn` (ligas e posts do perfil), `Message`, `Report`, `Block` e `Duel`, por `from == <eu>` em `FriendLink`, e apaga tudo junto com o `Profile` (nome do registro = id do usuário), em lotes de 300. Por isso `user` precisa ser Queryable em `Member`, `CheckIn`, `Message`, `Report`, `Block` e `Duel`. Os desafios, respostas e valores de outras pessoas nos seus X1 continuam (são delas). Com a permissão Creator: Write, o usuário só consegue apagar o que criou. Depois o app apaga os dados sociais do aparelho e a sessão.

## Permissões (Security Roles)

Em todos os tipos: **World: Read · Authenticated: Create · Creator: Write**. Nunca dar Write para Authenticated ou World: cada um só altera o que criou.

Exceção: `Report` e `Block` **sem World: Read** (só **Authenticated: Create · Creator: Read/Write**). Ninguém deve ver quem denunciou ou bloqueou quem; a moderação lê pelo Dashboard.

Exceção: `RoleAssignment` só **Authenticated: Read**, sem Create/Write para World ou Authenticated. Atribuições são criadas e alteradas pelo Dashboard (Security Role própria, ex.: `RoleManagers`) ou por um servidor com a chave server-to-server num cofre/gerenciador de segredos. As roles do app (`ADMIN`, `DEVELOPER`, `USER`) não mudam nenhuma permissão do CloudKit; regras, garantias e limitações em [rbac.md](rbac.md).

O banco público é legível por qualquer instalação do app. Nome, @usuário, bio, bro e posts do perfil já são públicos por definição; peso, medidas, recordes, metas, atividades não postadas e kcal/distância/esforço vindos do Apple Saúde **nunca** sobem; de atividade do Saúde postada, sobem só tipo, data e duração (dito na política) (guideline 5.1.3(ii); `OutgoingCheckIn(_:activity:)`). Check-ins e recados de uma liga ficam legíveis por quem souber o código; códigos de 6 caracteres (32⁶ ≈ 1 bilhão) dificultam adivinhar, mas não são segredo. Se precisar de ligas fechadas, o próximo passo é mover ligas para zonas compartilhadas (`CKShare`) do banco privado.

## Caixa de saída

Tudo o que é seu fica no aparelho e sobe depois (`LeagueRemoteStore.flush`, chamado ao abrir o app e 2 s depois de cada mudança):

- `League.syncedAt == nil`: cria a liga (se foi você que criou) e publica o seu lugar nela (nome, bro, time).
- `LeagueCheckIn.syncedAt == nil`: publica o check-in, inclusive editado (o id é o mesmo, então atualiza). Posts do perfil vão como liga `profile`.
- `LeagueOutbox`: check-ins já publicados e depois apagados aqui.
- `LeagueMessage.syncedAt == nil`: recados do mural.
- Perfil público: publicado ao abrir o app, só se mudou (`FriendsStore.publish`).

X1 não passa pela caixa de saída: desafiar e responder gravam na hora (sem rede, a tela mostra o erro e nada fica pendente), e o seu valor é reenviado a cada atualização da lista enquanto mudar (`DuelStore.refresh`, até 1 h depois do fim).

Sem rede ou sem iCloud, nada se perde: fica pendente e tenta de novo.

## Dados da conta

A conta é obrigatória e treinos, atividades, bros, rotinas, recordes, medidas, fotos, lugares, ligas e ajustes são dela. O `AccountSync` sobe a cópia da conta (formato do `Backup`, com `accountSettings`) alguns segundos depois de cada mudança e ao ir para segundo plano, e a baixa ao entrar.

A cópia tem dados vindos do Apple Saúde (tipo, duração, kcal e distância de treinos importados, `healthUUID`, peso). Pela guideline 5.1.3(ii), dados do HealthKit não podem ser guardados no iCloud. Decisão:

- **Servidor próprio** (recomendado): HTTPS, autenticado pelo token da sessão do `AuthBackend`, cópia cifrada em repouso, `delete` apagando de verdade (inclusive backups do servidor).
- **Alternativa**: CloudKit **privado** (`privateCloudDatabase`, nunca o público) só com os campos que não vêm do Saúde. Exigiria tirar da cópia as atividades importadas (ou os campos `healthUUID`, `healthType`, kcal e distância delas) e o peso vindo do Saúde.

Até a decisão, `ServerAccountDataBackend` lança `AccountSyncError.noServer` e, no `.cloudKit`, o login para em "Não deu para abrir sua conta". Nenhum tipo de registro é criado no CloudKit para isso.

### Checklist do que falta no servidor (dados da conta)

- [ ] Escolher entre servidor próprio e CloudKit privado sem dados do Saúde, e implementar `ServerAccountDataBackend` (`upload`, `download`, `delete`).
- [ ] Autenticação obrigatória em todas as rotas (RNF-42) e uma cópia por conta, legível só por ela.
- [ ] Conflito entre aparelhos: hoje vale a última cópia enviada (um aparelho por vez). Com dois aparelhos na mesma conta, mesclar por registro (uuid e data de alteração).
- [ ] Fotos (check-ins e progresso) como arquivos separados, em vez de dentro do JSON.
- [ ] "Excluir conta" chama `delete` antes de `AuthBackend.deleteAccount`; o servidor precisa apagar a cópia e os backups dele.
- [ ] Atualizar a política de privacidade e `NSPrivacyCollectedDataTypes` antes de ligar o servidor.

## Ainda sem servidor (próximos passos)

- Comentários e reações (`CheckInComment`) continuam só no aparelho.
- Fotos de outras pessoas: o `RemoteCheckIn.photoURL` (CKAsset) já vem, mas as telas ainda mostram o quadro colorido; falta carregar a imagem.
- Foto do perfil não sobe.
- Renovação de temporada: hoje cada aparelho calcula a sua; com servidor, check-ins da temporada são filtrados por data (`start`), o que já funciona, mas o ranking de temporadas passadas só existe no aparelho.
- Treino ao vivo no mapa (amigos treinando agora) segue simulado, inclusive a música dos amigos. A música que você ouve (`MusicShareStore.current`) só é lida no aparelho; quando o status ao vivo subir, ela vai junto (`docs/servidor-real.md`).
- Notificações push (novo check-in, pedido de amizade, desafio de X1): `CKQuerySubscription`. Desafio recebido já vai para a caixa de entrada (`InboxStore`), por enquanto buscando de tempos em tempos.
- Login com e-mail exige servidor próprio; no modo CloudKit só a conta Apple/iCloud existe.

## Moderação (denunciar e bloquear, guideline 1.2)

- Denunciar (check-in, foto, comentário, recado ou perfil) esconde o conteúdo na hora só para quem denunciou (`ModerationStore.hidden`, no aparelho) e põe a denúncia na fila `moderationOutbox`, enviada ao abrir o app e logo depois de cada ação; sem rede, tenta de novo.
- Bloquear grava `Block`, desfaz a amizade (`FriendsBackend.remove`, ou recusa o pedido pendente) e esconde a pessoa em feeds, comentários, mural, amigos, sugestões, mapa e perfil. A pontuação das ligas não muda. A lista de bloqueados do servidor substitui a do aparelho quando a fila está vazia (`ModerationStore.refresh`).
- Desbloquear apaga o `Block`; a amizade não volta sozinha.

### Checklist do que falta no servidor (moderação)

- [ ] Criar `Report` e `Block` no Dashboard com as permissões acima e os índices da tabela.
- [ ] Processo para analisar denúncias em até 24 h (prazo prometido no app): uma pessoa na fila do Dashboard (`Report` por `date`) ou um servidor com chave de servidor do CloudKit guardada num cofre/gerenciador de segredos (nunca no app).
- [ ] Tirar do ar para todos o que for confirmado: hoje o app não apaga registros de outras pessoas; isso é feito pelo Dashboard/servidor (e banir o autor, se for o caso).
- [ ] Comentários (`CheckInComment`) ainda não sobem: quando subirem, entram no mesmo fluxo (`kind = comment`).
- [ ] Opcional: esconder no servidor o conteúdo de quem te bloqueou (hoje o bloqueio é só do lado de quem bloqueia).
- [ ] Filtro de palavras: hoje só no aparelho (`ContentFilter`, lista em `BlockedTerms.swift`). Com servidor próprio, repetir a checagem no servidor ao receber `CheckIn`, `Message`, `Profile` e comentários (o CloudKit não valida conteúdo) e atualizar a lista sem nova versão do app.
- [ ] Aceite dos termos: hoje só no aparelho (`termsAcceptedVersion` e `termsAcceptedAt`). Para ter registro de quem aceitou qual versão, gravar um campo `termsVersion` (Int) e `termsAcceptedAt` (Date) no `Profile` (ou um tipo `TermsAcceptance`, Creator: Read/Write, sem World: Read) e recusar publicações sem aceite no servidor.
- [ ] Expulsão: suspender ou excluir a conta de quem violar os termos exige servidor ou ação administrativa no Dashboard (apagar `Profile`, `Member`, `CheckIn` e `Message` do autor).

## Checklist do que falta no servidor (X1)

- [ ] Criar `Duel` no Dashboard com os índices da tabela (`kind`, `user`, `opponent`, `duel`, `date` Queryable).
- [x] Tirar do valor informado a distância e as calorias do Apple Saúde (`Activity.duelActivity` usa os dados publicáveis).
- [x] Ignorar registros `Duel` que não foram criados pela pessoa do campo `user` (`creatorUserRecordID`) e usar nome aleatório no valor, para ninguém forjar nem travar o do outro.
- [ ] Notificar o desafio, a resposta e o resultado por push (`CKQuerySubscription` em `opponent == <eu>` e em `duel`); hoje a caixa de entrada busca de tempos em tempos.
- [ ] Recusar no servidor desafio para quem bloqueou quem desafia (exige servidor que leia `Block`).
- [ ] Decidir se os valores são conferidos no servidor: hoje cada lado informa o próprio número e o outro confia.

## Checklist do que falta no servidor (roles)

- [ ] Criar `RoleAssignment` no Dashboard com as permissões acima e as atribuições de `ADMIN`/`DEVELOPER` (cada uma listando também `USER`).
- [ ] Servidor confiável para as ações de `ADMIN` (`AdminBackend`): validar a identidade do lado dele, ler `RoleAssignment`, usar a chave server-to-server guardada num cofre/gerenciador de segredos e registrar cada ação.

## Checklist do que falta no servidor (conta)

- [ ] Capability Sign in with Apple no alvo (conta paga) e teste da folha da Apple no aparelho.
- [ ] Índice `user` Queryable em `Member`, `Message` e `Duel` (e já existente em `CheckIn`) antes de testar "Excluir conta".
- [ ] Vínculos `FriendLink` criados por outras pessoas para o usuário excluído (`<outro>-><eu>`) não podem ser apagados por ele: hoje somem da vista porque o `Profile` não existe mais; limpeza de verdade exige servidor ou função administrativa.
- [ ] Ligas criadas pelo usuário (`League.owner`) continuam para os outros participantes, sem dono. Decidir se passam para outro membro ou se são apagadas.
- [ ] Revogar o token do Sign in with Apple ao excluir a conta (`POST https://appleid.apple.com/auth/revoke`) exige servidor com a chave .p8 guardada num cofre/gerenciador de segredos (nunca no app).
- [ ] O usuário do iCloud (`CKContainer.userRecordID`) não é apagável pelo app; só os registros dele.
