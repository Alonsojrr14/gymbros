# Servidor real: decisões e pendências

Lista do que muda quando o app sair do `Backend.mode = .mock`. Confira cada item antes de publicar com servidor.

## Dados do Apple Saúde não vão para o iCloud (guideline 5.1.3(ii))

A conta é obrigatória e treinos, atividades e bros pertencem a ela (`AccountDataBackend`). Parte desses dados vem do Apple Saúde: tipo do treino, duração, calorias e distância importados pelo `HealthSync` (atividades com `healthUUID`/`healthType`).

A Apple proíbe guardar dados do HealthKit no iCloud. Por isso a sincronização real da conta:

- **Não pode** usar CloudKit (público ou privado) para o snapshot completo da conta.
- **Opção A — servidor próprio** (recomendada): o snapshot vai inteiro, com o consentimento já pedido na permissão do Saúde, sem uso para publicidade e sem repasse a terceiros.
- **Opção B — CloudKit sem os campos do Saúde**: sobe só o que o app calculou (XP, minutos, esforço, kcal estimada pelo app, distância do GPS do próprio app). Ao restaurar num aparelho novo, as atividades vindas do Saúde voltam pela reimportação do `HealthSync`, não pelo iCloud.

O mesmo vale para check-ins e perfil público: calorias e distância do Saúde nunca são publicados (já tratado na publicação das ligas, `OutgoingCheckIn`). O X1 segue a mesma regra: o valor que cada lado informa (`Duels.myValue`) usa `Activity.duelActivity`, com os dados publicáveis (esforço 5, sem distância e com as calorias estimadas nas atividades do Saúde).

## Não enviar para a App Store com o social simulado

A auditoria de 18/10/2026 concluiu que um build com `Backend.mode = .mock` é rejeitado: é uma rede social em que as outras pessoas, ligas, mural, mensagens e o mapa "ao vivo" são simulados (guidelines 2.2 e 2.3.1), e o login é obrigatório para uma conta que não existe de verdade (5.1.1(v)). Até o servidor existir, distribuir só pelo TestFlight. A App Store vem depois do servidor real, com conta de demonstração real nas notas (`docs/app-review.md`).

## Regras das ligas que o servidor precisa conferir

Hoje cada aparelho aplica as regras da liga ao montar o placar (o mesmo resultado em todos). Com servidor de verdade, ele precisa conferir no recebimento, para ninguém burlar mandando direto para a API:

- Verificação (`LeagueSettings.verification`): foto obrigatória, galeria só com hora verificada ou proibida, horário, retroativo, aparelho e local obrigatórios.
- Revisão: check-in de quem não é dono nem moderador entra pendente; só dono e moderadores aprovam, negam ou removem.
- Moderação: removidos e banidos não publicam nem leem; banido não entra pelo código; pedidos de entrada só viram membro quando aceitos; troca de dono passa as permissões de edição.
- Limites, pontos por atividade e dias ativos: o placar oficial deve ser calculado no servidor.
- "Esconder meus treinos" (`hiddenFrom`): o servidor não deve entregar os posts para quem foi escondido.
- Fotos a mais do check-in e fotos do mural: hoje ficam no aparelho e na cópia da conta; o servidor precisa de campos para elas.
- Rotinas públicas: implementar `RoutinesBackend` (publicar, tirar, curtir, contar cópias) no lugar do `MockRoutinesBackend`.
- Treino do dia e desafios dentro do clube: o servidor precisa pôr quem é do clube no desafio novo.
- GymBros Pro: ligar `ProStore.enforced` e cadastrar os produtos `com.alonsoalmeida.gymbros.pro.mensal` e `.anual` no App Store Connect.

## Checklist da troca

Caminho escolhido em 21/10/2026: Firebase no plano grátis, com as fotos no CloudKit (`docs/firebase.md`).

- [ ] Assinar o Apple Developer Program e trocar o `DEVELOPMENT_TEAM` (hoje Personal Team 5UV7WAAAL2).
- [ ] Capabilities: iCloud/CloudKit (se usado) e Sign in with Apple. O botão da Apple só aparece com `Backend.mode == .cloudKit` (`GymBros/Services/Auth.swift`).
- [ ] Implementar `AccountDataBackend` real seguindo a decisão acima.
- [ ] Trocar `Backend.mode` para o modo real em `GymBros/Services/Backend.swift`.
- [ ] Esquema do CloudKit (`docs/cloudkit.md`, inclusive `Duel`, `League.swiss` e `Member.joinedAt`) ou API do servidor próprio.
- [x] X1: valor informado sem distância e calorias do Saúde (`docs/cloudkit.md` → "Checklist do que falta no servidor (X1)").
- [ ] Fila de moderação: denúncias analisadas e conteúdo removido em até 24 h (guideline 1.2). O texto mostrado ao denunciar vem de `ModerationStore.reviewNote` e passa a prometer as 24 h sozinho fora do `.mock`.
- [ ] `PrivacyInfo.xcprivacy`: preencher `NSPrivacyCollectedDataTypes` (bloco pronto em `docs/app-review.md`).
- [ ] Atualizar a política de privacidade e os termos de uso (app e `docs/`) antes de publicar. Hoje nenhum dos dois cita o X1 (nome, bro e o total na métrica vão para o adversário e para o servidor). As coordenadas da academia no convite para treinar junto (`TrainInvite.latitude`/`longitude`) já estão na política (Localização) e nos termos (O que você publica), versão 2.
- [ ] App Store Connect: rótulos de privacidade iguais ao manifesto.
- [ ] Música ("Mostrar o que estou ouvindo", `GymBros/Music/Music.swift`): enviar `MusicShareStore.current` junto com o status ao vivo e mostrar em `LiveFriend.music`. Declarar no manifesto e nos rótulos (uso do app / outros dados de uso, vinculado à conta, para funcionalidade).
- [ ] Spotify: registrar o app no Spotify for Developers (redirect `gymbros://spotify`), preencher `SpotifyNowPlaying.clientID` e implementar o login PKCE e `GET /me/player/currently-playing` (escopo `user-read-currently-playing`). Conferir o limite do modo de desenvolvimento do Spotify e pedir o acesso ampliado antes de abrir para todos.
