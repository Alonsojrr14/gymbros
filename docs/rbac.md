# Controle de acesso (RBAC)

Código em `GymBros/Access/` (`Access.swift`: catálogo, matriz e contexto; `AccessStore.swift`: estado da sessão, fonte das roles e ações administrativas). Testes em `GymBrosTests/AccessTests.swift`.

## Conceitos

- **Role** (`AppRole`): quem a pessoa é para o app. Identificadores estáveis, persistidos como texto: `ADMIN`, `DEVELOPER`, `USER`. O nome na tela é localizado (`AppRole.title`: "Administrador", "Desenvolvedor", "Usuário") sem mudar o identificador.
- **Permissão** (`Permission`): uma ação autorizável, com chave estável (`leagues.update`, `moderation.review`…). Nunca um texto de interface.
- **Escopo** (`PermissionScope`): `.own` vale só para o que é seu (ou para o que você está criando); `.any` vale também para o dos outros. Recursos com dono implementam `OwnedResource` (`League.isMine` = criada neste aparelho, `!joined`).
- **Política** (`RolePolicy.standard`): a matriz role → permissões. Nega por padrão: o que não está escrito não existe. Nenhuma role tem curinga, nem `ADMIN`.
- **Contexto** (`AccessContext`): `signedOut`, `loading(userID)` ou `resolved(userID, roles, source)`. Só `resolved` concede algo.
- **Autorização** (`AccessStore.shared`): o único ponto de decisão. Autenticação continua no `AuthStore`; o `AccessStore` só lê quem é o usuário atual.

## Matriz de permissões

Roles se somam: uma conta pode ter `USER` e `DEVELOPER`. `DEVELOPER` e `ADMIN` **não herdam** `USER`; a atribuição lista todas as roles da conta.

| Permissão | O que protege | USER | DEVELOPER | ADMIN |
|---|---|:-:|:-:|:-:|
| `profile.read` | Ver perfil público dos outros | ✅ qualquer | — | — |
| `profile.update` | Aba Público do perfil e publicar o próprio perfil (`FriendsStore.publish`) | ✅ próprio | — | — |
| `friends.read` | Tela de amigos, "Amigos agora" no Mapa | ✅ próprio | — | — |
| `friends.manage` | Adicionar e aceitar amigos (`FriendsStore.add`, `accept`) | ✅ próprio | — | — |
| `leagues.read` | Aba Ligas | ✅ qualquer | — | — |
| `leagues.create` | Criar liga e publicar as regras dela | ✅ própria | — | — |
| `leagues.join` | Publicar seu lugar numa liga (`setMembership`) | ✅ próprio | — | — |
| `leagues.update` | "Editar liga" e salvar a edição | ✅ só a que criou | — | — |
| `checkIns.publish` | Postar check-in em liga ou perfil (`Terms.canPublish`, flush) | ✅ próprio | — | — |
| `messages.publish` | Recado no mural (tela e flush) | ✅ próprio | — | — |
| `comments.create` | Comentar check-in | ✅ próprio | — | — |
| `directMessages.send` | Mandar mensagem, força ou convite a um amigo | ✅ próprio | — | — |
| `moderation.report` | Denunciar conteúdo | ✅ qualquer | — | — |
| `moderation.block` | Bloquear pessoa | ✅ qualquer | — | — |
| `moderation.review` | Ler a fila de denúncias (`AdminActions.reports`) | — | — | ✅ |
| `moderation.removeContent` | Tirar conteúdo do ar para todos (`AdminActions.remove`) | — | — | ✅ |
| `users.manageRoles` | Mudar roles de outra conta (`AdminActions.setRoles`) | — | — | ✅ |
| `diagnostics.read` | Seção "Diagnóstico" em Ajustes (backend, origem das roles, filas, último erro) | — | ✅ | — |

Decisões inferidas (não havia regra no código):

- `ADMIN` recebe só o que a moderação já pedia em `docs/cloudkit.md` (analisar denúncias em 24 h, tirar conteúdo do ar) e a gestão de roles. Não edita ligas dos outros nem vê diagnóstico.
- `DEVELOPER` recebe só o diagnóstico, que existia pela metade (`LeagueRemoteStore.lastError`, "para mostrar se precisar") e passou a aparecer em Ajustes.
- "Editar liga" aparecia para qualquer participante; quem entrou pelo código editava as regras só no próprio aparelho (o ranking dele divergia do resto). Agora só quem criou a liga edita. Trocar de time continua livre.
- Retirar o que é seu nunca depende de permissão: apagar check-in publicado, sair de liga, desbloquear, recusar e desfazer amizade, excluir conta.

## Onde mora a atribuição

| Modo | Fonte | Sem atribuição | Falha na consulta |
|---|---|---|---|
| `.mock` | `MockRoleBackend` (nada guardado) | `USER` | — |
| `.cloudKit` | `CloudKitRoleBackend`: registro `RoleAssignment` com nome `role-<id do iCloud>` e campo `roles` (lista de String) no banco público | `USER` | só `USER` |

Regras de resolução (`AccessContext.resolve`):

- Sem registro → `USER` (`source: .standard`). Isso preserva todos os usuários existentes sem migração: `USER` concede exatamente o que qualquer conta autenticada do iCloud já consegue fazer no banco público.
- Registro com valores → só os identificadores exatos valem (`AppRole.parse`); `admin`, ` ADMIN` ou `ROOT` são descartados.
- Registro vazio ou só com valores inválidos → **nenhuma role** (é assim que se desativa uma conta).
- Falha de rede ou de iCloud → só `USER` (`source: .fallback`), nunca as roles atribuídas antes. Assim a caixa de saída continua funcionando offline e nada privilegiado é liberado sem confirmação.
- Nenhum caminho resulta em `ADMIN` por falta de dado.

O app **nunca grava** atribuição. Não existe tela, chamada ou chave local para escolher a própria role. Nada de role vai para SwiftData, `UserDefaults` ou backup.

## Sessão

- `RootView` chama `AccessStore.refresh()` sempre que `AuthStore.user?.id` muda (login, logout, troca de conta). `MainView` chama de novo ao app ficar ativo, antes da caixa de saída.
- `can` só usa o contexto se o `userID` dele for o do usuário atual: depois de logout ou troca de conta, tudo é negado na hora, mesmo antes do `refresh`.
- Enquanto carrega, nada é concedido: `SocialGate` mostra um indicador de progresso em vez do conteúdo, e controles privilegiados não aparecem.

## Como consultar

```swift
@State private var access = AccessStore.shared               // em views (observável)

if access.can(.diagnosticsRead) { … }                        // ação sem dono ou no que é seu
if access.can(.leaguesUpdate, on: league) { … }              // recurso com dono
try access.authorize(.friendsManage)                         // em serviços: lança AccessError.forbidden
SocialGate("motivo", requires: .leaguesRead) { conteúdo }    // tela inteira
```

Nunca compare roles (`roles.contains(.admin)`) fora de `RolePolicy`.

## Como proteger uma nova ação

1. Escolha (ou crie) a permissão.
2. Confira no serviço que executa a ação (`try access.authorize(...)` ou `guard access.can(...)`). Os stores têm `var access: AccessStore = .shared`, trocável nos testes.
3. Esconda o controle na tela com `access.can(...)` ou `SocialGate`. A tela é conveniência; a conferência do passo 2 é obrigatória.
4. Se a ação mexe em dados de outras pessoas no servidor, ela precisa de servidor confiável (ver Garantias).
5. Teste a negação na camada do serviço.

## Como adicionar uma permissão

1. Novo `case` em `Permission` com chave estável.
2. Em `RolePolicy.standard`, conceda explicitamente às roles que devem tê-la (ou a nenhuma).
3. Atualize `AccessTests.expected`: `testEveryPermissionHasAnExplicitDecision` falha até a decisão ser registrada para cada role.
4. Atualize a matriz deste documento.

## Como adicionar uma role

1. Novo `case` em `AppRole` (identificador estável em maiúsculas) e `title`.
2. Entrada em `RolePolicy.standard` com as permissões dela; nenhuma outra role muda.
3. `AccessTests.expected` e a matriz deste documento.
4. Crie as atribuições no CloudKit Dashboard.

Roles e permissões são enums Swift: uma role nova só passa a valer para quem instalar a versão do app que a conhece. Em versões antigas, o identificador novo é desconhecido e é descartado (a conta fica com as outras roles da lista).

## Garantias de segurança

**O RBAC do app não protege o servidor.** O CloudKit só aplica as próprias permissões (Security Roles do Dashboard e o dono de cada registro); ele não conhece `ADMIN`, `DEVELOPER` ou `USER`. Um app modificado pode ignorar a política. O que cada camada garante:

| Garantia | Quem garante |
|---|---|
| Só altera ou apaga o que criou (perfil, liga, lugar na liga, check-ins, recados, amizades, denúncias, bloqueios) | CloudKit: `Creator: Write` em todos os tipos |
| Ninguém lê denúncias e bloqueios de outra pessoa | CloudKit: `Report` e `Block` sem `World: Read` |
| Ninguém cria ou altera atribuição de role pelo app | CloudKit: `RoleAssignment` sem `Create`/`Write` para `Authenticated`/`World` |
| Usuário comum não vê nem aciona ações de outra role | App (`AccessStore`), só para clientes não modificados |
| Conta desativada não publica pelo app | App; o CloudKit ainda aceita escritas dessa conta |
| `ADMIN` ler denúncias e tirar conteúdo do ar | **Ninguém ainda.** Exige servidor confiável |

Por isso as ações de `ADMIN` passam por `AdminActions`, que confere a permissão e chama um `AdminBackend`. Hoje o único é `TrustedServerRequired`, que sempre lança `AccessError.requiresTrustedServer`: o app **não** finge executar moderação. Até existir o servidor, a moderação é feita no CloudKit Dashboard.

### Servidor confiável necessário

Para `moderation.review`, `moderation.removeContent`, `users.manageRoles` (e para desativar contas de verdade), é preciso um serviço que:

1. Receba a identidade do usuário de forma verificável (ex.: o token de identidade do Sign in with Apple, validado no servidor) e nunca uma role enviada pelo cliente.
2. Leia `RoleAssignment` do lado dele e decida pela mesma matriz.
3. Execute com a chave server-to-server do CloudKit, guardada num cofre/gerenciador de segredos (nunca no app nem em texto puro no repositório).
4. Registre cada ação privilegiada (quem, o quê, quando).

No app, basta implementar `AdminBackend` com esse serviço e passá-lo para `AdminActions`.

## Configuração no CloudKit Dashboard

Tipo `RoleAssignment` (esquema e permissões também em `cloudkit.md`):

- Nome do registro: `role-<recordName do usuário do iCloud>`. Campo `roles`: String List (ex.: `["USER", "DEVELOPER"]`).
- Security Roles: **Authenticated: Read** e nada mais para `World`/`Authenticated`. Escrita só por uma Security Role própria (ex.: `RoleManagers`) ou pela chave de servidor.
- Criar e alterar atribuições pelo Dashboard (ou pelo servidor). Cada mudança deve ser registrada fora do app (o Dashboard não tem histórico próprio).
- Limitação: qualquer conta autenticada que souber o id de outra pode ler as roles dela. O CloudKit não tem "só o próprio usuário lê" para registros criados pelo Dashboard.

Recuperação: apagar o registro devolve a conta para `USER`; um registro com `roles` vazio desativa a conta no app.

## Testes

Rodam dentro do app instalado no aparelho (`TEST_HOST`), como o resto da suíte:

```sh
xcodebuild test -project GymBros.xcodeproj -scheme GymBros -destination 'id=<UDID>' -derivedDataPath build -allowProvisioningUpdates
```

`AccessTests` cobre a matriz (exata e exaustiva), negação de tudo fora da matriz, ausência de privilégio de `ADMIN` em `USER`/`DEVELOPER`, escopo próprio, roles somadas, mudança numa role sem efeito nas outras, role sem concessão, valores inválidos, usuário deslogado, sem atribuição, atribuição vazia, carregando, falha da consulta, troca de conta, logout, dono da liga, caixa de saída sem permissão (nada sobe e tudo fica pendente), moderação e amigos sem permissão, e `AdminActions` (nega antes do servidor; com `ADMIN`, cai no "precisa de servidor"; ninguém muda a própria role). `GymTestCase.signedInAccess(_:)` cria uma sessão de teste com a atribuição desejada.

O `CloudKitRoleBackend` não tem teste automatizado: depende de conta paga, container do iCloud e registros no Dashboard.

## Limitações que continuam

- Sem servidor, nenhuma ação de `ADMIN` executa; a moderação é manual no Dashboard.
- Desativar uma conta só vale no app; o CloudKit continua aceitando as escritas dela nos próprios registros.
- Em `.mock` todo mundo é `USER`. Só em builds Debug, a tela de login tem a seção "Desenvolvimento" (`GymBros/Access/DevAccounts.swift`) com contas fixas de cada role (`dev-user`, `dev-developer`, `dev-admin`, `dev-disabled`); o arquivo inteiro fica em `#if DEBUG` e não existe no Release nem no modo `.cloudKit`. Antes de publicar, apague o arquivo junto com as chamadas `signIn(as:)`, `DevAccountPicker` e `DevAccount.assignments`.
- As roles de qualquer conta são legíveis por contas autenticadas.
- Ligas são lidas por quem souber o código (regra existente, não muda com RBAC).
