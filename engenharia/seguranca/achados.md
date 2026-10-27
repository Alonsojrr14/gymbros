# Achados de segurança e privacidade

**Escopo.** Autenticação, regras do Firestore (teste mental de conta maliciosa usando o SDK direto), deep link, cópia da conta, contas de teste, requisitos de segurança para o Android. **Documento interno: nunca copiar para `docs/` (site público).**
**Base de evidência.** Leitura de código e de `firebase/firestore.rules` no disco em 21/10/2026 (inclui a coleção `comments`, mudança não commitada do dono). Nenhum acesso ao Firebase real: não se sabe se as regras publicadas são iguais ao arquivo.
**Autoria.** `security-analyst` (Opus, somente leitura), com C1, E-04 e B5 conferidos pelo orquestrador no código.
**Status.** Rodada 1. Toda correção de regra é decisão do dono (portão próprio); nada foi alterado.

## Resumo

| ID | Severidade | Título | Status | Exige mudança de regra |
|---|---|---|---|---|
| SEC-C1 | CRÍTICA | Deep link adiciona amigo sem confirmação e expõe a localização ao vivo | VERIFIED (orquestrador) | sim + app |
| SEC-C2 | CRÍTICA | `friendCode` escolhido pelo cliente: dá para copiar o código de outra pessoa | VERIFIED | sim |
| SEC-A1 | ALTA | Perfil totalmente forjável; limpeza da moderação é desfeita pelo dono | VERIFIED | sim |
| SEC-A2 | ALTA | Qualquer conta entra em qualquer liga; aprovação e banimento só no cliente | VERIFIED | sim |
| SEC-A3 | ALTA | `checkIns` com leitura global e conteúdo forjável; placar calculado no cliente | VERIFIED (regras) / INFERRED (placar) | sim |
| SEC-A4 | ALTA | Senha da conta de demonstração compilada no Release | VERIFIED | não |
| SEC-A5 | ALTA (privacidade; diretriz 5.1.3 da App Store) | **kcal do HealthKit do Apple Watch publicada** em check-in, pontuação "calorias" e X1 | VERIFIED (orquestrador) | não (correção no app) |
| SEC-A6 | MÉDIA (privacidade) | Nome da fonte do Saúde (ex.: "iPhone de Fulano") vai na prova do check-in (`CheckInProof.device = activity.source`) | VERIFIED pelo `requirements-analyst` | não |
| SEC-M1 | MÉDIA | `duels`: placar livre, a qualquer momento | VERIFIED | sim |
| SEC-M2 | MÉDIA | `comments`: `owner` e `userName` arbitrários; bloqueio ignorado | VERIFIED | sim |
| SEC-M3 | MÉDIA | `routines`: curtidas e cópias ilimitadas | VERIFIED | sim |
| SEC-M4 | MÉDIA | `reports`: inundação da fila (admin lê 200) | VERIFIED | sim |
| SEC-M5 | MÉDIA | `leagues`: dono muda `code`/`owner` livremente; `settings` em JSON-string impede validação | VERIFIED | sim |
| SEC-M6 | MÉDIA | Leitura ampla + cadastro livre + sem App Check = base inteira legível por qualquer conta nova | VERIFIED | sim + app |
| SEC-M7 | MÉDIA | E-mail não verificado entra e escreve (regras não checam `email_verified`) | VERIFIED (orquestrador) | opcional |
| SEC-B1 | INFO | Cópia da conta tem dados do Saúde, peso, medidas, rotas, sem cifra no cliente (regra correta: só o dono) | VERIFIED | não |
| SEC-B2 | BAIXA | Cabeçalho de `FirebaseBackend.swift:13-14` diz que X1, trocas etc. "continuam simulados" — desatualizado | VERIFIED | não |
| SEC-B4 | BAIXA | `messages.text` sem `is string` | VERIFIED | sim |
| SEC-B5 | INFO | Nonce do Sign in with Apple correto (SHA-256 para a Apple, cru para o Firebase); recurso desligado | VERIFIED (orquestrador) | não |
| SEC-B6 | INFO | Só FirebaseAuth e FirebaseFirestore linkados; Analytics no `Package.resolved` mas não linkado | VERIFIED | não |

## Detalhes

### SEC-C1 — Deep link adiciona amigo sem confirmação e expõe a localização ao vivo (CRÍTICA)
- **Evidência:** `GymBros/App/App.swift:291-293` (`onOpenURL` → `FriendsStore.shared.add(code:)` sem diálogo); `GymBros/Services/FirebaseBackend.swift:246-256` (grava `friendLinks/{você}->{dono do código}`); `firestore.rules` `match /live/{id}` (`get` se existe `friendLinks/{id}->{leitor}`); `GymBros/Friends/LiveShare.swift:13` (`defaultOn = true`); `GymBros/Services/FirebaseSocial.swift:208-213` (grava latitude, longitude, rota ~100 pontos, local, música).
- **Abuso:** o atacante manda um link ou QR com o código dele. A vítima toca, o app cria o vínculo em silêncio. A partir daí o atacante lê o `live` da vítima a cada treino (posição e percurso) e passa a poder mandar DM, X1 e troca (`reachable`).
- **Impacto:** localização em tempo real de quem tocou num link. Risco de perseguição.
- **Mitigação proposta:** confirmação com nome e foto antes de adicionar (iOS e Android); `live` exigir amizade mútua (os dois `friendLinks`); considerar "ao vivo" desligado por padrão; arredondar posição fora de academias salvas.

### SEC-C2 — Código de amigo sequestrável (CRÍTICA)
- **Evidência:** regra de `profiles` (`write` se `id == uid()`, sem restrição de campos); busca por `friendCode` com `limit(1)` (`FirebaseBackend.swift:247`); código gerado no cliente (`GymBros/Friends/Friends.swift:75-79`).
- **Abuso:** `profiles` aceita `list` por qualquer conta: o atacante copia o `friendCode` de alguém para o próprio perfil e passa a receber parte das adições por código/QR. Combinado com C1, recebe o `live` de quem achava que adicionava outra pessoa.
- **Mitigação:** reservar o código no servidor (`friendCodes/{code}` com `create` só se não existir) e restringir campos do perfil.

### SEC-A1 — Perfil forjável (ALTA)
- **Evidência:** `FirebaseBackend.swift:317-325` (campo `public` em JSON com bro, estatísticas, conquistas), renderizado em `:274-283`; limpeza do admin `FirebaseGame.swift:240-242`; `hiddenFrom` legível por todos (`FirebaseBackend.swift:328`).
- **Abuso:** inventar estatísticas, conquistas, forma do bro; usar o nome de outra pessoa (sem unicidade); regravar o perfil depois da moderação; ler de quem a pessoa esconde os treinos.
- **Não há escalada de admin**: `roles` só o admin grava, nunca para si.
- **Mitigação:** `keys().hasOnly`, tipos e tamanhos; marca `moderatedAt` que bloqueie reescrita; `hiddenFrom` em documento privado.

### SEC-A2 — Entrar em qualquer liga (ALTA)
- **Evidência:** regra de `members` (`create` só exige id `liga-uid`); aprovação só no cliente (`FirebaseBackend.swift:460-464`); `RemoteLeague.applying` (`GymBros/Leagues/LeagueRemote.swift:97-113`) só tira `removed`/`banned`.
- **Abuso:** listar `leagues`, criar o próprio `members`, aparecer como membro; escrever em `messages` de qualquer liga; banido continua lendo e escrevendo.
- **Mitigação:** aprovação e banimento como campos de lista lidos pela regra; `messages`/`checkIns` exigirem documento de membro.

### SEC-A3 — Check-ins forjáveis e legíveis por todos (ALTA)
- **Evidência:** regra de `checkIns` (`read: signedIn()`, `create: writesAsMe()` sem validar campos nem associação); campos em `FirebaseBackend.swift:427-433`; leitura em `:341-363,474-484`; pontuação recalculada em cada aparelho a partir do `ScoreInput` remoto (`GymBros/Leagues/Leagues.swift:570-580`, conferido pelo orquestrador).
- **Abuso:** check-in com quaisquer minutos/esforço/distância, datas dentro da temporada, `proof` falsa, em liga de que não é membro; o ranking aceita. Qualquer conta lê academia, kcal e notas de todo mundo.
- **CONFLICTING:** `docs/privacidade.md:37` diz que check-ins são vistos pelos participantes da liga; as regras não garantem.
- **Mitigação:** leitura só para membros; limites e tipos (`minutes <= 600`, `date <= request.time`, dentro da temporada); a médio prazo, pontuação no servidor (exige Functions → plano pago, ou outro backend).

### SEC-A4 — Credencial de demonstração no binário (ALTA)
- **Evidência:** `GymBros/Services/DemoAccount.swift:7-8` (`DemoAccount.email`, `DemoAccount.password`; valor não reproduzido). Uso protegido por `Backend.mode == .mock`, mas a constante vai no Release.
- **Risco:** se a mesma credencial existir no Firebase Auth para a revisão da Apple, fica pública ao extrair o binário.
- **Mitigação:** `#if DEBUG`; senha de revisão só no App Store Connect. **Android: nunca embutir conta de teste.**

### SEC-A5 — kcal do Apple Watch publicada (ALTA)
- **Evidência:** `GymBros/Services/WatchBridge.swift:98-104` (`link`): no treino guiado gravado no relógio, `a.kcal = saved.kcal` (energia ativa lida do HealthKit do relógio) e só `healthWrittenUUID` é preenchido. `Activity.isFromHealth` é `healthUUID != nil` (`GymBros/Leagues/Leagues.swift:102`), então `publishableKcal` devolve essa kcal (`:108`). O mesmo vale para `save(_:)` quando `w.healthUUID` vem nulo (`Shared/WatchLink.swift:72`).
- **Impacto:** dado do Saúde vai para outras pessoas (check-in, placar "calorias" das ligas, X1). Contradiz `docs/privacidade.md` ("Calorias… do Saúde nunca vão para posts nem para o X1"), RNF-07e e RNF-54, e a diretriz 5.1.3 da Apple.
- **Correção proposta (iOS, exige aprovação):** tratar `healthWrittenUUID != nil` ou `source == "Apple Watch"` como origem Saúde em `isFromHealth`/`publishable*`. Teste novo cobrindo `WatchBridge.link`. **Android:** a mesma regra quando houver Health Connect.
- **Relacionado (C3, BAIXA):** o card do Story usa a kcal real do Saúde (`GymBros/Activities/StoryShare.swift:49-51`), compartilhada pela própria pessoa. Citar na política ou trocar pela estimativa.
- **`HealthPrivacyTests` desatualizado:** 6 testes ainda montam `CKRecord` (CloudKit). Não cobrem Firestore, `WatchBridge` nem `proof.device`.

### SEC-M1 a SEC-M7
- **M1 `duels`:** `score_<uid>` aceita qualquer `int`, a qualquer momento, inclusive depois do prazo; o `create` não proíbe `score_*` (quem desafia pode pré-gravar o placar do outro) e aceita nomes forjados. Mitigação: `score >= 0`, teto por métrica, só após `accepted` e dentro da janela, `keys().hasOnly`.
- **M2 `comments`:** `owner` arbitrário tira do dono do post o poder de apagar; `userName` livre; `item` livre; leitura global; bloqueio não é respeitado (`GymBros/Friends/CommentSync.swift:38-44,57-90`). Mitigação: `owner == get(checkIns/item).data.user`, nome vindo de `profiles`, respeitar `blocks`.
- **M3 `routines`:** ±1 por escrita sem registro de quem curtiu. Mitigação: subcoleção `likes/{uid}` + `existsAfter`.
- **M4 `reports`:** sufixo livre no id → denúncias ilimitadas; admin lê 200 (`FirebaseGame.swift:222`). Mitigação: id determinístico `uid-tipo-conteúdo`.
- **M5 `leagues`:** dono troca `code` e `owner` (para não membro); `settings` é JSON em texto e a regra não consegue validar `approved`/`banned`.
- **M6 enumeração:** coleções com `read: signedIn()` + cadastro livre + nenhum App Check (nenhuma referência em `GymBros/`) = despejo da base com uma conta nova.
- **M7 e-mail não verificado:** `signUp` envia a verificação, `signIn` não exige (`FirebaseBackend.swift` `signIn`/`signUp`; aviso só em `GymBros/App/SettingsPages.swift:347`); as regras não checam `request.auth.token.email_verified`.

## Requisitos de segurança para o Android (SEC-AND)

| ID | Requisito |
|---|---|
| SEC-AND-01 | Deep link de amigo por **App Link verificado** (`https://…/amigo/CÓDIGO` + `assetlinks.json`; o domínio do GitHub Pages pode servir) além do esquema `gymbros://` para compatibilidade; **sempre** tela de confirmação com nome e foto antes de criar `friendLinks`; validar o código pelo formato gerado no iOS. |
| SEC-AND-02 | `android:exported="false"` em tudo que não for a Activity de entrada/deep link; nenhum `ContentProvider` exportado; receivers do widget sem ações abertas. |
| SEC-AND-03 | Sessão só pelo Firebase Auth. Segredos próprios (se houver) no Android Keystore; nada sensível em SharedPreferences sem cifra. |
| SEC-AND-04 | `allowBackup="false"` ou `dataExtractionRules` excluindo banco local, cópia da conta e preferências (a cópia tem dados de saúde). |
| SEC-AND-05 | Health Connect: só os tipos usados (exercício, calorias, distância, peso se houver paridade), tela de justificativa (`ACTION_SHOW_PERMISSIONS_RATIONALE`), formulário de dados de saúde no Play Console, mesma regra do iOS de não publicar kcal/distância do Saúde em posts e X1 (conferir RNF de privacidade). |
| SEC-AND-06 | Localização fina só durante o treino, com serviço em primeiro plano visível; segundo plano só se a "visita verificada" for mantida, com justificativa; `POST_NOTIFICATIONS` no Android 13+. |
| SEC-AND-07 | Treino ao vivo com consentimento explícito (decidir padrão com o dono). |
| SEC-AND-08 | `google-services.json` fora do git; chave de API restrita ao pacote e ao SHA-256 da assinatura. |
| SEC-AND-09 | App Check (Play Integrity) só em modo de monitoramento até o iOS ter App Attest. |
| SEC-AND-10 | Release com R8, sem logs de dados pessoais, `debuggable=false`, sem tráfego em texto puro. |
| SEC-AND-11 | Nenhuma conta de teste/demonstração no APK; nenhuma credencial da Apple reaproveitada. |
| SEC-AND-12 | O Android não trata filtros do cliente (aprovação, banimento, `hiddenFrom`, bloqueio de comentários) como segurança; as correções de C1–M7 valem para os dois apps. |

## Lacunas (UNKNOWN)
- Regras publicadas no projeto real × arquivo local (não acessado).
- `HealthSync.swift`, `HealthPrivacyTests.swift`, `KeychainTests.swift`, proteção de arquivos, App Group, `PrivacyInfo.xcprivacy`, `ContentFilter`, coleção `trades` em detalhe: não revisados nesta rodada.
- Se nomes de membro e treinador passam por filtro de palavras em algum ponto do servidor (pelos docs, não).

## Achados de 22/10 (porte dos amigos para o Android)

| ID | Severidade | Achado | Sugestão |
|---|---|---|---|
| SEC-M8 | Média | `profiles/{id}` tem `allow read: if signedIn()`: qualquer conta lê nome, bio, `public` (bro, números, conquistas) e a lista `hiddenFrom` de qualquer pessoa. "Esconder meus treinos" é só no app (o comentário no iOS já diz que não é sigilo). | Mover os números para um documento que só amigos leem (regra com `friendLinks` nos dois sentidos), ou aceitar e documentar como público. |
| SEC-M9 | Média | `members` e `checkIns` têm leitura para qualquer conta logada: membros e check-ins de ligas **privadas** ficam legíveis por quem souber consultar. O app filtra; o servidor não. | Ler só se for membro da liga (`exists(members/{liga}-{uid})`) ou se a liga for pública. |
| SEC-M10 | Média | A conta desativada (`roles/{uid}` com lista vazia) só é barrada no app (AccessStore). As regras do Firestore não consultam `roles` para escrita comum: uma conta desativada com um cliente modificado continua gravando. | Conferir `roles` nas regras de escrita social (`friendLinks`, `checkIns`, `messages`, `directMessages`), ou desativar a conta no Auth. |

Todos ficam para a auditoria antes do APK para testers (pedido do dono: menor privilégio, papéis decididos no servidor).

**23/10:** SEC-M9 corrigido nas regras (commit desta data, falta publicar): `members`, `checkIns`, `messages` e `joinRequests` só para membros da liga (`memberOf`), os próprios documentos, posts do perfil pelo perfil público, posts de liga pública no Feed só para amigos mútuos, admin para moderação. Fica aberto: `comments` (texto dos comentários) continua legível por qualquer conta logada, porque o documento não diz de qual liga é o post.

**24/10:** `comments` fechado (falta publicar). Cada comentário guarda `league` (liga do post, `profile` no perfil), `feed` (liga pública) e `poster` (autor do post); só lê quem pode ver o post (`seesPost`: perfil, membro da liga ou amigo mútuo do autor em liga pública), além do autor, do dono do alvo, do autor do post e do admin. A criação exige os três campos e que quem escreve veja o post. Os dois apps consultam por liga (`league ==` e, fora da liga, `poster ==` e `feed == true`). Comentários antigos, sem `league`, ficam visíveis só para autor e dono. Resíduo aceito: alguém pode gravar um comentário com `feed: true` apontando para post de liga privada; só expõe o próprio texto dele.

**25/10:** SEC-M8 aceito pelo dono como público: o perfil (`profiles/{id}`) pode ser lido por qualquer conta logada, inclusive os campos novos de bros e atributos (maior nível, BroBook, atividade favorita, atributos gerais). Motivo do dono: quem o vê numa liga deve poder abrir o perfil. Controle do usuário: interruptor "Bros e atributos" (`publicBros`, padrão ligado) em "O que aparece para os outros".

**25/10 (auditoria antes do beta Android):**
- SEC-M10 corrigido nas regras (falta publicar): `active()` barra escrita de conta desativada em todas as coleções sociais; bloquear, apagar e a cópia da conta continuam livres.
- SEC-A7 (ALTA, novo) parcial: check-in de liga e mural agora exigem ser membro (`memberAfter`). Fica aberto: qualquer conta lista ligas e cria o próprio `members/{liga}-{uid}` em liga privada, porque privacidade e aprovação moram no JSON `settings` e a regra não lê. Correção completa: campos nativos `isPrivate`/`approved`/`banned` na liga, `list` só de pública, e `members.create` conferindo esses campos (mexe na entrada em liga nos dois apps).
- SEC-M11 (MÉDIA, novo): a chave Web API está no código (`EmailLinks`, `FirebaseEmailLinks`, `docs/acao.html`) e no histórico do git público. Ação do dono no Google Cloud: restringir a chave às APIs Identity Toolkit, Firestore e Token Service e ligar a proteção contra enumeração de e-mail no Auth. Segredos de build (keystore da release em `~/.gymbros/`) ficam fora do repositório, guardados num cofre ou gerenciador de segredos.
- SEC-M12 (MÉDIA, novo) corrigido nos dois apps: encerrar o treino ao vivo apaga `latitude`, `longitude` e `music` de `live/{uid}`.
- B9 corrigido: `dataExtractionRules` e `fullBackupContent=false` tiram os dados do app do backup e da transferência entre aparelhos.
- Abertos de baixo risco: B7 (confirmação do link de amigo sem nome e foto), B8 (esquema `gymbros://` sem App Link), B10 (notificação do treino pública na tela bloqueada, por paridade com o Live Activity).
