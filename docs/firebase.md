# Firebase (plano grátis) + fotos no CloudKit

Modo `.firebase` de `GymBros/Services/Backend.swift`. Ele liga sozinho quando o arquivo `GymBros/Resources/GoogleService-Info.plist` existe. Sem o arquivo, o app continua no `.mock`.

| O quê | Onde |
|---|---|
| Login (e-mail e senha; Apple quando houver conta paga) | Firebase Auth |
| Perfil público, amigos, ligas, membros, check-ins, mural, pedidos de entrada | Firestore (`FirebaseBackend.swift`) |
| Fotos dos check-ins | CloudKit, banco público, tipo `Photo` (`PhotoStore.swift`) |
| Mensagens diretas (texto, força, convites) | Firestore `directMessages`, em tempo real com o app aberto (`FirebaseSocial.swift`) |
| Treino ao vivo no mapa e "começou a treinar" | Firestore `live/{uid}`, em tempo real (`LivePresence` e `LiveFriendsStore`) |
| X1 (`duels`), trocas (`trades`, `tradeBros`) | Firestore, com datas do servidor (`FirebaseGame.swift`) |
| Denúncias (`reports`), bloqueios (`blocks`), roles (`roles`) e ações de admin | Firestore; o role ADMIN dá poder nas regras |
| Rotinas públicas (`routines`) | Firestore |
| Cópia da conta (`accounts/{uid}/chunks`) | Firestore, comprimida e sem fotos; a cópia completa fica num arquivo no iPhone |

## Por que as fotos ficam no CloudKit

No plano Spark não existe Cloud Storage (desde fev/2026 ele exige o Blaze). Por isso, cada foto vira um registro `Photo` (campo `image`, um `CKAsset`) no banco público do container `iCloud.com.alonsoalmeida.gymbros`. O check-in no Firestore guarda só o nome do registro, no campo `photo` (`photo-<id do check-in>`).

- **Ler** o banco público não precisa de conta do iCloud.
- **Gravar** precisa. Sem iCloud no aparelho, o check-in sobe sem a foto: `hasPhoto` continua verdadeiro e só a imagem não aparece para os outros.
- **Cache**: as fotos baixadas ficam em `Caches/Photos`.
- **Plano Blaze, depois**: basta escrever um `PhotoStore` com o Cloud Storage e trocar `Backend.photos`. As ligas não mudam.

O CloudKit só funciona com a conta paga do Apple Developer. Até lá, `Backend.appleCapabilities = false` usa o `NoPhotoStore`: os check-ins sobem sem a foto.

## Projeto

- **Projeto:** `gymbros-zerobyte`, no plano Spark.
- **App iOS:** `1:839807463430:ios:77c64675b9534d8bdc9387`, com o bundle `com.alonsoalmeida.gymbros`.
- **Firestore:** `(default)`, edição Standard, em `southamerica-east1`, com proteção contra exclusão ligada.
- **Login:** e-mail e senha.

Para baixar o plist de novo:
```sh
npx -y firebase-tools@latest apps:sdkconfig IOS 1:839807463430:ios:77c64675b9534d8bdc9387 --project gymbros-zerobyte --out GymBros/Resources/GoogleService-Info.plist
```

Para publicar mudanças de regras, índices ou login (pasta `firebase/`):
```sh
cd firebase && npx -y firebase-tools@latest deploy --only firestore,auth
```

## Passo a passo (já feito em 21/10/2026)

1. **Criar o projeto Firebase.** No [console do Firebase](https://console.firebase.google.com), crie o projeto no plano Spark. Não ligue o Google Analytics.
2. **Registrar o app iOS.** Use o bundle id `com.alonsoalmeida.gymbros`. Baixe o `GoogleService-Info.plist` e coloque em `GymBros/Resources/`. O arquivo está no `.gitignore`.
3. **Ligar o login por senha.** Em Authentication → Sign-in method, ative **E-mail/senha**.
   - Em Settings → User account linking, mantenha "Link accounts that use the same email" (uma conta por e-mail, o padrão).
   - Mantenha também a proteção contra enumeração de e-mails, que vem ligada.
4. **Criar o banco.** Em Firestore Database → Create database, escolha a região `southamerica-east1` (São Paulo), em modo de produção.
5. **Publicar regras e índices** a partir da pasta `firebase/`:
   ```sh
   npm i -g firebase-tools && firebase login
   cd firebase && firebase use --add   # escolha o projeto
   firebase deploy --only firestore
   ```
   Sem as regras, o banco fica fechado (modo de produção) ou aberto para qualquer um (modo de teste). As regras de `firestore.rules` exigem login e só deixam cada um gravar o que é seu.
6. **Instalar o app.** Na primeira abertura, a sessão do login simulado sai e os dados do aparelho ficam sem dono. A primeira conta do Firebase que entrar adota esses dados (`Backend.adoptLocalSession` + `AccountSync.enter`).

### Quando assinar o Apple Developer Program

1. **Trocar o time de assinatura.** Mude o `DEVELOPMENT_TEAM` do Personal Team para o time pago.
2. **Ligar as capabilities.** Em Signing & Capabilities, adicione **iCloud → CloudKit** com o container `iCloud.com.alonsoalmeida.gymbros` e **Sign in with Apple**.
3. **Liberar no código.** Mude `Backend.appleCapabilities` para `true`.
4. **Ligar a Apple no Firebase.** Em Authentication, ative o provedor **Apple**.
5. **Criar o tipo `Photo` no CloudKit Dashboard.** O campo `image` é um Asset. As permissões ficam assim:
   - World: leitura;
   - Authenticated: criação;
   - Creator: escrita.

   Não precisa de índice consultável: as fotos só são buscadas pelo nome.

## Mesmo e-mail na Apple e na senha

Regra padrão do Firebase: **uma conta por e-mail**. As duas formas de entrar levam à mesma conta, e nunca nascem duas contas com o mesmo e-mail.

| Situação | O que acontece |
|---|---|
| Criou com senha e depois tocou em "Continuar com a Apple" (mesmo e-mail) | O Firebase recusa (`accountExistsWithDifferentCredential`). O app pede para entrar uma vez com e-mail e senha e, ao entrar, liga o login da Apple a essa conta (`PendingLink`). Daí em diante, a Apple entra direto. |
| Criou com a Apple e depois tenta "Criar conta" com o mesmo e-mail | "Esse e-mail já tem conta. Entre com a senha ou com a Apple." |
| Errou a senha, ou a conta é só da Apple | "E-mail ou senha incorretos. Se você criou a conta com a Apple, use “Continuar com a Apple”." Com a proteção contra enumeração ligada, o Firebase não diz qual dos dois é. |
| Usou "Ocultar meu e-mail" na Apple | O e-mail é `…@privaterelay.appleid.com`. Ele não colide com o e-mail real, então são contas diferentes. É o comportamento esperado da Apple. |

## Quanto cabe no plano grátis

O Spark dá 50 mil leituras, 20 mil gravações e 20 mil exclusões por dia, 1 GiB guardado e 10 GiB de download por mês. Ao passar do limite, o Firestore para até o dia seguinte, sem cobrança.

O que mais lê é o `fetch` da liga, porque cada abertura lê todos os membros, check-ins da temporada, recados e pedidos. Numa liga de 20 pessoas com 3 check-ins por semana, isso dá algo como 100 a 300 leituras por abertura. Com ligas grandes, o próximo passo é guardar o placar calculado num documento, o que já pede Cloud Functions (Blaze).

## Mensagens diretas e treino ao vivo

**Mensagens**
- Cada mensagem é um documento com `from`, `to` e `participants`. Só as duas pontas leem.
- Só dá para mandar para quem adicionou você (`friendLinks/{destinatário}->{você}`). Isso vale para amigos e para quem já tinha pedido amizade.
- Mensagens não são editadas nem apagadas. "Limpar conversa" é só do seu lado.
- O app ouve os últimos 90 dias (índice `participants` + `date`). Cada mensagem nova custa uma leitura para quem recebe.

**Treino ao vivo**
- Fica em `live/{uid}` e é publicado durante musculação, CrossFit, corrida, caminhada e bike, se o "Ao vivo" estiver ligado naquele treino.
- No máximo uma gravação a cada 30 s.
- Na academia vai o ponto salvo da academia. Fora dela, a posição atual. Na corrida, os últimos cerca de 100 pontos do percurso.
- Só lê quem a pessoa adicionou como amigo: um ouvinte por amigo.
- Sem notícia há 15 minutos, o treino conta como encerrado. Quem terminou há mais de 12 h some do mapa.

**Sem push:** com o app fechado, nada toca. Push precisa de Cloud Functions (plano Blaze) e do APNs (conta paga da Apple). Até lá, o que chegou vira notificação local quando o app abre.

Testado em 21/10/2026 com contas temporárias, já apagadas. Todos os casos deram o resultado esperado:

| Caso | Resultado |
|---|---|
| Mandar mensagem antes de ser adicionado | Negado |
| Mandar mensagem depois de ser adicionado | Aceito |
| Estranho mandando mensagem | Negado |
| Destinatário lendo as próprias mensagens | Aceito |
| Estranho lendo mensagens dos outros | Negado |
| Amigo lendo o ao vivo | Aceito |
| Estranho lendo o ao vivo | Negado |
| Estranho escrevendo no ao vivo dos outros | Negado |

## X1, trocas, moderação, rotinas e cópia da conta

**X1 e trocas**
- Só dá para desafiar ou propor troca a quem adicionou você e não te bloqueou.
- A data de criação e a da resposta são do servidor (`request.time`): ninguém mexe no relógio do aparelho para ganhar tempo.
- O desafiado responde uma vez, em até 24 h. No X1, cada lado só escreve o próprio valor (`score_<uid>`). Na troca, o outro lado aceita ou recusa em até 48 h, e quem propôs pode cancelar antes da resposta.
- Cada aparelho aplica a sua parte da troca aceita. Sem Cloud Functions, o valor do X1 e os bros da troca confiam no que cada aparelho informa.

**Moderação**
- Denúncias só podem ser lidas por admins.
- Bloquear impede mensagem, X1 e troca, e as regras do Firestore conferem isso.
- Admin apaga check-in, recado, mensagem e limpa um perfil denunciado (`FirebaseAdminBackend`).
- **Primeiro admin:** depois de criar a sua conta no app, crie no console do Firebase o documento `roles/<seu uid>`, com o campo `roles` (array) = `["USER", "ADMIN"]`. O uid aparece em Authentication → Users. A partir daí, admins dão roles para outras pessoas pelo app, nunca para si mesmos.

**Rotinas públicas**
- Só o autor edita e apaga. Os outros só mudam curtidas (+1 ou −1) e cópias salvas (+1).

**Cópia da conta**
- É o `Backup` comprimido (zlib), em pedaços de até 900 KB, e só sobe quando muda.
- Na nuvem vai sem as fotos de medidas, check-ins e mural. A cópia completa, com fotos, fica em `Application Support/MockServer`, no iPhone.
- Ao entrar, vale a cópia mais nova (a do iPhone, se ela for mais recente). Num iPhone novo, os dados voltam sem essas fotos.

**Excluir conta** apaga do servidor o login, o perfil, a cópia da conta, check-ins, recados, amizades, bloqueios, denúncias, rotinas, o ao vivo e os bros para troca. Mensagens, X1 e trocas continuam com a outra pessoa (as regras não deixam apagar).

Testado em 21/10/2026 com contas temporárias, já apagadas. Os 35 casos deram o resultado esperado:
- **X1:** criar, responder uma vez, valor só o próprio, sem data inventada, sem estranho e sem bloqueado.
- **Trocas:** propor, aceitar, sem cancelar depois de aceita, bros visíveis só para amigos.
- **Denúncia:** criar, sem leitura por quem não é admin.
- **Roles:** ninguém se faz admin.
- **Rotinas:** curtida +1, sem 999 curtidas, sem editar nem apagar a dos outros.
- **Cópia da conta:** só o dono lê.
- **Mensagem:** entre amigos passa; para quem te bloqueou, não.

As ações de admin com um role ADMIN de verdade ainda não foram testadas.

## O que falta

- **Moderação e regras da liga conferidas no servidor** (Cloud Functions, plano Blaze). Hoje só as regras de acesso protegem o banco: cada um grava o que é seu, e o placar continua sendo calculado no aparelho.
- **Push com o app fechado** (mensagens, trocas, X1). Precisa de Cloud Functions (Blaze) e do APNs (conta paga da Apple).
- **Fotos na nuvem** (check-ins, mural, medidas). Precisa do CloudKit, que depende da conta paga da Apple, ou do Cloud Storage (Blaze).
- **Reações e comentários em check-ins de outras pessoas.** Ainda não têm coleção no Firestore.
- **Rótulos de privacidade no App Store Connect**, iguais ao `PrivacyInfo.xcprivacy` (preenchido em 21/10/2026).
