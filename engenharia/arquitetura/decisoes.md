# Decisões de arquitetura (ADRs) do Android

**Escopo.** Decisões do app Android do GymBros. Cada ADR traz contexto, opções, escolha, motivo, consequências, opções rejeitadas, confiança e perguntas.
**Base de evidência.** Feitas pelo `android-architect` (Opus 5.5, somente leitura) a partir dos documentos de `engenharia/`, com conferência no código. A revisão com referências de Compose (kiln, compose-guide) e o orquestrador ajustaram os ADRs 004 e 005, e as mudanças estão marcadas.
**Status.** Todas **propostas**: nenhuma foi aprovada pelo dono. A revisão independente (Fable 5.1) corrigiu o ADR-006 (arredondamento, calendário) e o ADR-007 (caminho de perda de dados); ver a seção 4 de `../plano/riscos-e-perguntas.md`.

| ADR | Decisão | Confiança | Depende do dono |
|---|---|---|---|
| 001 | Módulos `:app` + `:core:domain` (Kotlin/JVM puro: regras **e** formatos da cópia) | alta | não |
| 002 | `minSdk 26`; `targetSdk`/`compileSdk` = o exigido pelo Play para apps novos (provável 36, a confirmar) | alta / média | não |
| 003 | DI manual (`AppContainer`), sem Hilt/Koin | alta | não |
| 004 | Persistência: arquivo da cópia da conta + cache offline do Firestore + DataStore; sem Room na v1; **envio por WorkManager** | média-alta | P10 (tamanho da cópia) |
| 005 | UI própria `GM*` sobre Compose, só escuro, `GMTabBar` com pilha por aba, edge-to-edge, voltar predito | alta | não |
| 006 | Regras recebem `RuleClock`; **decidido (22/10): fuso fixo `America/Sao_Paulo` em todas as regras de liga, nos dois apps** (IOS-07) | alta | decidido |
| 007 | Cópia da conta: **decidido (22/10): mesclagem por UUID (fase C) antes da v1**, no iOS (IOS-08) e no Android; o modo dono/companheiro fica só como proteção de transição | média | decidido |
| 008 | Sprites: medir se é pixel art ampliada → grade nativa; senão WebP sem perda; `drawable-nodpi`; PAD só se medido | média | sim (script em `tools/`) |
| 009 | Login só e-mail/senha (Credential Manager opcional; o autofill do Compose basta) | alta | **aprovado (22/10)** |
| 010 | Escopo da v1 (ver abaixo) | média | **aprovado (22/10)** |
| 011 | `applicationId` `com.alonsoalmeida.gymbros` (+ `.debug`) | alta | **aprovado (22/10)** |
| 012 | Mapa muscular próprio em Compose (`Canvas` + traçados) | média | não |
| 013 | Firestore econômico: ouvinte só do que está na tela, paginação, cache | alta | não |

---

### ADR-001 — `:app` + `:core:domain`
- **Contexto:** cerca de 12 arquivos de regra no iOS, metade misturada com a plataforma (`ios-estado-atual.md` §3). A paridade bit a bit (CC-1 a CC-10) só se prova com vetores compartilhados. Não há emulador.
- **Opções:** só `:app`; `:app` + `:core:domain`; módulos por feature.
- **Escolha:** `:app` + `:core:domain` em Kotlin/JVM, com regras (`rules/`), relógio (`time/RuleClock`), formatos da cópia (`backup/`) e JSON em texto (`wire/`).
- **Motivo:** os testes rodam só com JDK, em segundos, sem SDK Android. O compilador impede que `Context` ou o fuso do aparelho entrem nas regras (evita repetir ND-3 e ND-8). `shared-fixtures/` vira recurso de teste direto.
- **Consequências:** um `build.gradle.kts` a mais. O domínio não conhece Firebase (`Timestamp` → `Instant` na borda).
- **Rejeitadas:** só `:app` (isolamento depende de disciplina; testes precisam do plugin Android); módulos por feature (sem porte que justifique).

### ADR-002 — Níveis de SDK
- **Escolha:** `minSdk 26` (`java.time` nativo sem desugaring, mínimo do Health Connect, canais de notificação). `targetSdk` igual ao exigido pelo Play na data da publicação.
- **Consequências:** baixar a plataforma alvo (~100 MB; o SDK local tem 30, 34 e 35). Edge-to-edge e voltar predito obrigatórios. `POST_NOTIFICATIONS` quando houver notificação.
- **Rejeitadas:** 24 (desugaring); 28+ (corta aparelhos baratos sem ganho).

### ADR-003 — DI manual
- **Escolha:** `AppContainer` na `Application`, ViewModels por `viewModelFactory {}`, `SessionScope` recriado quando o `uid` muda.
- **Motivo:** cerca de 13 repositórios. Sem KSP/kapt, com build e disco curtos. Nos testes basta trocar o container.
- **Rejeitadas:** Hilt (custo desproporcional); Koin (erros em tempo de execução). Rever se o grafo passar de ~30 dependências.

### ADR-004 — Persistência e offline (ajustado)
- **Contexto:** o `Backup` v1 já é contrato (FS-AND-04) e cobre os 19 modelos. O XP é recalculado das atividades. O iOS serializa a cópia inteira com 5 s de espera.
- **Escolha:**
  - **Dados pessoais:** `AccountStore` mantém o `BackupDto` num `StateFlow` e grava de forma atômica (temporário + `rename`) em `noBackupFilesDir/account.json`, com `hash` e `savedAt` do último envio ou recebimento.
  - **Dados sociais:** cache persistente do Firestore, com ouvintes por tela.
  - **Preferências do aparelho:** DataStore. A primeira tela espera o primeiro valor (splash retido), sem piscar o padrão.
  - **Envio da cópia (ajuste do orquestrador):** `WorkManager`, trabalho único (`REPLACE`) com restrição de rede, agendado 5 s depois da última mudança, ao ir para o fundo e ao sair. **Motivo da mudança:** a proposta original (corrotina em `ON_STOP`) perde o envio se o processo morrer, e isso é perda de dados. A revisão com referências apontou o problema (item A3) e o orquestrador o confirmou. Custo: uma dependência pequena.
- **Rejeitadas:** Room na v1 (duplica esquema e migrações; volta se a fase C pedir índices); só o cache do Firestore (a cópia são pedaços comprimidos).
- **Pergunta:** tamanho real da cópia do dono (campo `bytes` no metadado; P10).

### ADR-005 — UI e navegação
- **Escolha:** design system próprio (`GM*`) em Compose, com Material 3 só como base. Tema só escuro, com as frações RGB de `Shared/Theme.swift`. Fonte do sistema em `sp`, com teto onde o iOS tem. `GMTabBar` própria (Feed, Treino, [bro], Ligas, Mapa), cada aba com pilha e estado salvos. Rotas tipadas (Navigation Compose). Edge-to-edge com `WindowInsets`. Spotlight do tutorial como camada no topo, com alvos medidos por `onGloballyPositioned`.
- **Voltar do sistema (complemento da revisão, A5):** desempilha a aba atual e depois volta para o bro. No treino em andamento e no tutorial pede confirmação. Usa a API de voltar predito.
- **Estado (A1):** repositórios de escopo do app publicam `StateFlow`; cada tela tem `ViewModel` → `UiState` imutável; coleta com `collectAsStateWithLifecycle`. Checklist completo em `.claude/skills/android-feature/referencia-compose.md`.
- **Rejeitadas:** `NavigationBar` do Material (descaracteriza a marca); Navigation 3 (estabilidade não verificada).

### ADR-006 — Fuso das regras compartilhadas
- **Contexto:** ND-3/ND-4 (dias ativos, tetos, campeões, pose do dia, renovação, bro do time usam o fuso do aparelho); o suíço usa Brasília fixo (E-09); ND-8 (padrão `.current` como armadilha). Hoje nem dois iPhones em fusos diferentes concordam.
- **Opções:** (a) Android replica o fuso do aparelho; (b) fuso fixo `America/Sao_Paulo` nos dois apps (ou `settings.timeZone` na liga, com esse padrão); (c) Android sozinho com fuso fixo.
- **Escolha:** nenhuma regra lê o fuso sozinha: todas recebem `RuleClock`. **A v1 replica o iOS de hoje** (FS-AND-08). Fica como **proposta ao dono** a opção (b), na mesma versão dos dois apps, junto com as correções de ND-1 (`selfID` = `Backend.myID`) e ND-2 (desempate por `uid` no lugar de "eu primeiro").
- **Motivo:** (c) faria o Android divergir do iOS agora, que é pior do que divergir só entre fusos. (b) é a única que entrega o mesmo ranking em todo aparelho. Com o relógio injetado, trocar depois é mudar um parâmetro.
- **Consequências:** os vetores do grupo B fixam fuso, `firstWeekday` e `now`. O `RuleClock` fixa também o **calendário gregoriano** e `minimumDaysInFirstWeek` (revisão). **Arredondamento (corrigido na revisão):** o Swift `.rounded()` arredonda a metade para longe do zero. Em Kotlin, `roundToInt()`/`Math.round` levam a metade para +∞, e `kotlin.math.round` usa metade para o par. Só os dois primeiros coincidem com o Swift, e só para positivos. O domínio usa uma função própria `roundHalfAwayFromZero`, com vetor que inclui −2,5.

### ADR-007 — Cópia da conta com dois aparelhos
- **Contexto:** a cópia segue "última escrita vence" no documento inteiro, e quem já é dono nunca baixa (E-07). As regras aceitam qualquer campo no metadado, e o iOS regrava o metadado **sem `merge`** (VERIFIED pelo orquestrador: `FirebaseGame.swift:332`), apagando campos alheios.
- **Opções:** (a) somente leitura sempre; (b) mesclagem por UUID (só funciona se o iOS também mesclar); (c) um aparelho dono por vez, com detecção e troca explícita, sem mudar o iOS; (d) documento por aparelho.
- **Escolha:** **(c) na v1**; **(b) como fase C**, se o dono aceitar mudar o iOS.
  - **Detecção:** o Android grava `writer: "android-<installId>"` no metadado; o iOS apaga o campo ao gravar.

    | Metadado remoto | Modo do Android |
    |---|---|
    | não existe | **dono** |
    | `writer` = este aparelho e `hash` = último conhecido | **dono** |
    | `writer` ausente ou diferente, ou `hash` desconhecido | baixa e restaura → **companheiro**: dados pessoais só leitura; social completo, exceto o que nasce de atividade (check-in, placar de X1, perfil público) |

  - **Troca de aparelho:** em Ajustes, "Usar este Android como principal" orienta a sair da conta no iPhone (o iPhone sobe a cópia ao sair). O Android então baixa e assume.
  - **Envio (só no modo dono):** transação que lê o metadado, aborta se o `hash` mudou e grava pedaços + metadado. O hash usa `exportedAt = distantPast`, como no iOS.
- **Consequências:** no modo companheiro não há registro de atividade, treino nem check-in pelo Android (evita check-in órfão ou dobrado, E-11). Ler pedaços durante um envio concorrente pode falhar: repetir com recuo e conferir `bytes` e `hash`.
- **Caminho de perda de dados (bloqueio B3 da revisão, incorporado):** a troca de aparelho só *orienta* a sair do iPhone, e o Android não consegue verificar que isso aconteceu. Se o iPhone continua logado como dono, ele nunca baixa (`AccountSync.swift:153-157`) e, na próxima mudança local, sobe a cópia inteira sem `merge`. O Android então detecta (`writer` sumiu) e cai para companheiro. Sem proteção, **perderia tudo o que gravou como dono**, e os check-ins publicados ficariam órfãos. O caminho inverso também existe: o Android dono apaga da nuvem mudanças feitas só no iPhone. **Exigências acrescentadas:**
  1. antes de qualquer restauração, guardar à parte o estado local não enviado, como o iOS faz com `setAside` (`AccountSync.swift:162-169`), e oferecer exportá-lo;
  2. bloquear "Usar este Android como principal" enquanto o `savedAt` remoto for mais novo que o último envio conhecido, e exigir que a pessoa confirme que saiu da conta no iPhone;
  3. aviso explícito e permanente no modo dono: "não use a conta no iPhone ao mesmo tempo";
  4. o critério de aceite do AND-011 cobre os cenários "iPhone continua logado" e "Android dono + iPhone reinstalado".
- **Limite real:** sem a fase C (mudança no iOS), o (c) **reduz** o risco, mas não o elimina, porque depende de a pessoa seguir a orientação. Isso precisa ser dito ao dono (P8).
- **Fase C (iOS + Android):** ler o metadado antes de enviar; mesclar por UUID; lápides para itens apagados; `updatedAt` por entidade; `accountSettings` mesclado por chave.
- **Rejeitadas:** (a) inútil para quem só tem Android; (b) sem mudar o iOS, perde dados com certeza; (d) custo maior.

### ADR-008 — Sprites e tamanho do app
- **Contexto:** 421 sprites PNG de 512 a 640 px (~157 MB; o `sprite_baby` tem 640×640 e 340 KB, conferido), 336 imagens do wger (18 MB). Limite de 200 MB no download base do AAB.
- **Escolha:**
  1. Ferramenta fora do app (executar é decisão do dono) que verifica se cada sprite é uma ampliação por vizinho mais próximo. Se for, grava na grade nativa e o app amplia com `FilterQuality.None`.
  2. Se não for, WebP sem perda nos sprites e WebP q80 no wger.
  3. Tudo em `drawable-nodpi`.
  4. Asset pack `fast-follow` do Play Asset Delivery para as viradas, só se o AAB medido passar de ~120 MB.
  5. Sem os sprites `_live` do widget na v1.
- **Rejeitadas:** PNG cru (pesado demais); WebP com perda nos sprites (borra os contornos da pixel art).

### ADR-009 — Login
- **Escolha:** só e-mail e senha, com redefinição. Verificação enviada em pt-BR, sem ser exigida, como no iOS (E-04). Credential Manager para salvar e preencher a senha.
- **Rejeitadas:** Google (criaria contas que o iPhone não abre sem ligar provedores); Apple no Android (provedor desligado; exige conta paga e Services ID).

### ADR-010 — Escopo da v1 (proposta)
- **Dentro:**
  - login, restauração da cópia, onboarding, termos, tutorial de 10 passos;
  - bro (XP, evolução, BroBook, conquistas);
  - registrar atividade e treino com rotinas (só no modo dono);
  - ligas completas com pontuação idêntica, check-in sem foto e sem prova EXIF;
  - suíço, campeões, X1, feed e comentários;
  - amigos **com confirmação**;
  - DMs com o app aberto;
  - rotinas públicas, denúncias, bloqueio, perfil público;
  - mapa muscular;
  - aba Mapa como lista;
  - excluir conta (na ordem do iOS, com erro explícito enquanto RSK-02 estiver aberto);
  - créditos e licenças.
- **Fora, com motivo:**

| Item | Motivo |
|---|---|
| Wear OS e complicações | outro app e outro aparelho |
| Glance (widgets) | v1.1 |
| Notificação de treino em andamento e compartilhar ao vivo | serviço em primeiro plano + localização; SEC-C1 aberto |
| Health Connect | v1.1, junto com SEC-AND-05 |
| Importar WOD por foto (Vision, FoundationModels) | custo alto |
| Translation, Atalhos | sem ganho na v1 |
| Música | permissão sensível |
| Câmera e prova EXIF | v1.1 |
| Story, retrospectiva em vídeo | v1.1 |
| Cerca da academia | localização em segundo plano exige justificativa no Play |
| Pro / Play Billing | o Pro não é cobrado no iOS (`ProStore.enforced = false`, conferido) |
| Trocas de bros | dependem do registro de trocas no plist e de um modo dono estável; v1.1 |

### ADR-011 — `applicationId`
- **Escolha:** `com.alonsoalmeida.gymbros` (mesmo do iOS; as lojas são separadas) e `com.alonsoalmeida.gymbros.debug` para depuração. Os dois apps Android são registrados no Firebase **pelo dono**. `google-services.json` fica fora do git. Chave de API restrita por pacote + SHA-256.
- **Pergunta:** o id está livre no Play Console?

### ADR-012 — Mapa muscular
- **Escolha:** componente próprio (`Canvas` + traçados SVG). Os traçados do MuscleMap podem ser reaproveitados (MIT, com o aviso em Licenças/`NOTICE`) **se** forem do próprio pacote. Se forem de terceiros, desenhar traçados próprios para os 15 músculos.

### ADR-013 — Firestore econômico
- **Escolha:** ouvinte só da liga aberta; check-ins por `league == code && date >= start` com ouvinte (o cache entrega o diff); mensagens com `limit` e paginação; `live` dos amigos só com a aba Mapa visível; DMs nos 90 dias do iOS; X1 e trocas nos 30 dias; nunca `get()` em laço; um cliente por sessão com `persistentCacheSettings`.

> **Atualização da ADR-010 (23/10/2026):** o dono pediu sincronizar e importar treinos de relógios e apps nos dois aparelhos (22/10). O Health Connect entra na v1 do Android: sincronização automática opcional, "Importar agora", permissões de leitura (treino, calorias ativas, distância, peso) e a tela de justificativa exigida pelo Google Play. Gravar no Health Connect continua fora.
