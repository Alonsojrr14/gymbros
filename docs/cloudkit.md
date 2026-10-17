# Backend com CloudKit

O app fala com o servidor só por três contratos: `AuthBackend` (`Auth.swift`), `LeagueBackend` (`LeagueRemote.swift`) e `FriendsBackend` (`Friends.swift`). Quem responde é escolhido em `GymMonsters/Backend.swift`:

```swift
static let mode: BackendMode = .mock   // .cloudKit quando o app tiver iCloud
```

| Contrato | `.mock` | `.cloudKit` |
|---|---|---|
| `AuthBackend` | `MockAuthBackend`: e-mail ou Apple simulados | `CloudKitAuthBackend`: a conta do iCloud do aparelho |
| `LeagueBackend` | `MockLeagueBackend`: participantes simulados | `CloudKitLeagueBackend` |
| `FriendsBackend` | `MockFriendsBackend`: pessoas simuladas | `CloudKitFriendsBackend` |

A liga de exemplo (`AMIGOS`) continua simulada nos dois modos.

## Ligar o CloudKit

1. Conta paga do Apple Developer (o Personal Team não tem iCloud nem Sign in with Apple).
2. Xcode → alvo GymMonsters → Signing & Capabilities → **+ iCloud** → marcar **CloudKit** → container `iCloud.com.alonsoalmeida.gymmonsters` (o mesmo de `Backend.containerID`). Isso adiciona ao `GymMonsters.entitlements` as chaves `com.apple.developer.icloud-container-identifiers` e `com.apple.developer.icloud-services`.
3. Criar o esquema abaixo no CloudKit Dashboard (ambiente Development), com índices e permissões.
4. Trocar `Backend.mode` para `.cloudKit`, rodar no aparelho com uma conta do iCloud e testar com duas contas.
5. Antes de publicar: **Deploy Schema Changes** para Production.

## Esquema (banco público)

Todos os ids de usuário são o `recordName` do usuário do iCloud (`CKContainer.userRecordID()`).

| Tipo | Nome do registro | Campos | Índices |
|---|---|---|---|
| `Profile` | id do usuário | `name`, `username`, `bio` (String), `friendCode` (String), `broFormID` (String), `public` (String, JSON com bro, números e conquistas; partes escondidas não vão) | `friendCode` Queryable |
| `League` | código da liga | `code`, `owner`, `name`, `emoji`, `scoring`, `weights`, `tieBreak`, `photoRule`, `teams` (String), `start`, `end` (Date), `autoRenew` (Int64) | `recordName` Queryable |
| `Member` | `<código>-<usuário>` | `league`, `user`, `name`, `formID`, `teamID` (String) | `league` Queryable |
| `CheckIn` | uuid do check-in | `league` (código, ou `profile` para posts do perfil), `user`, `date`, `kind`, `minutes`, `effort`, `meters`, `kcal`, `title`, `note`, `hasPhoto`, `photo` (Asset) | `league`, `user` Queryable; `date` Queryable e Sortable |
| `Message` | uuid do recado | `league`, `user`, `date`, `text` | `league` Queryable; `date` Sortable |
| `FriendLink` | `<de>-><para>` | `from`, `to` (String) | `from`, `to` Queryable |

Amizade é um vínculo em cada direção: pedir é criar `eu->você`, aceitar é criar o de volta, desfazer é apagar o seu. Assim ninguém precisa escrever registro de outra pessoa.

## Permissões (Security Roles)

Em todos os tipos: **World: Read · Authenticated: Create · Creator: Write**. Nunca dar Write para Authenticated ou World: cada um só altera o que criou.

O banco público é legível por qualquer instalação do app. Nome, @usuário, bio, bro e posts do perfil já são públicos por definição; peso, medidas, recordes, metas e atividades não postadas **nunca** sobem. Check-ins e recados de uma liga ficam legíveis por quem souber o código; códigos de 6 caracteres (32⁶ ≈ 1 bilhão) dificultam adivinhar, mas não são segredo. Se precisar de ligas fechadas, o próximo passo é mover ligas para zonas compartilhadas (`CKShare`) do banco privado.

## Caixa de saída

Tudo o que é seu fica no aparelho e sobe depois (`LeagueRemoteStore.flush`, chamado ao abrir o app e 2 s depois de cada mudança):

- `League.syncedAt == nil`: cria a liga (se foi você que criou) e publica o seu lugar nela (nome, bro, time).
- `LeagueCheckIn.syncedAt == nil`: publica o check-in, inclusive editado (o id é o mesmo, então atualiza). Posts do perfil vão como liga `profile`.
- `LeagueOutbox`: check-ins já publicados e depois apagados aqui.
- `LeagueMessage.syncedAt == nil`: recados do mural.
- Perfil público: publicado ao abrir o app, só se mudou (`FriendsStore.publish`).

Sem rede ou sem iCloud, nada se perde: fica pendente e tenta de novo.

## Ainda sem servidor (próximos passos)

- Comentários e reações (`CheckInComment`) continuam só no aparelho.
- Fotos de outras pessoas: o `RemoteCheckIn.photoURL` (CKAsset) já vem, mas as telas ainda mostram o quadro colorido; falta carregar a imagem.
- Foto do perfil não sobe.
- Renovação de temporada: hoje cada aparelho calcula a sua; com servidor, check-ins da temporada são filtrados por data (`start`), o que já funciona, mas o ranking de temporadas passadas só existe no aparelho.
- Treino ao vivo no mapa (amigos treinando agora) segue simulado.
- Notificações push (novo check-in, pedido de amizade): `CKQuerySubscription`.
- Login com e-mail exige servidor próprio; no modo CloudKit só a conta Apple/iCloud existe.
