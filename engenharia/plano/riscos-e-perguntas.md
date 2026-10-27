# Riscos e perguntas

**Escopo.** Riscos (RSK-xx) do porte para o Android e da reorganização, e as perguntas que só o dono pode decidir. Nenhuma incerteza crítica fica escondida numa suposição de implementação.
**Base de evidência.** Todos os documentos de `engenharia/`; evidências em `../descoberta/indice-evidencias.md`.
**Status.** Rodada 1. Revisão independente: ver seção 4.

## 1. Riscos

| ID | Risco | Sev. | Prob. | Evidência | Mitigação | Status |
|---|---|---|---|---|---|---|
| RSK-01 | **Pareamento suíço diverge entre aparelhos já hoje no iOS** (`selfID = "me"` no modo Firebase) | ALTA | alta | E-10; ND-1 | corrigir no iOS (`Backend.myID`) antes do Android; vetor de teste com identidade real | aberto: decisão do dono (mudança no iOS) |
| RSK-02 | **Exclusão de conta falha no Firebase**: consulta a `reports` negada **e** `live` sem `allow delete`; exclusão parcial possível com `requiresRecentLogin`; `docs/excluir-conta.md` promete o contrário | ALTA (requisito da App Store e LGPD) | alta (INFERRED, não executado) | contrato §3 | liberar `list` do próprio autor em `reports` ou tirar `reports` da exclusão; testar no aparelho com conta descartável | aberto: decisão do dono |
| RSK-03 | **Cópia da conta é "última escrita vence" sem mesclagem**, e o aparelho que já é dono nunca baixa de novo: usar a mesma conta no iPhone e no Android apaga dados | ALTA | certa se os dois gravarem | E-07; contrato §5 | ADR-007 | aberto |
| RSK-04 | Regras compartilhadas dependem do fuso do aparelho (dias ativos, tetos, campeões, XP do time) | MÉDIA | média (público de um fuso) | ND-3, ND-4 | ADR-006 | aberto |
| RSK-05 | Porte numérico errado (arredondamento `round` × `roundToInt`, divisão inteira, `Double`, ordem de operações, FNV-1a/LCG com `ULong`) | ALTA | média | E-13; contrato §7 | vetores compartilhados grupos A e B antes de qualquer tela de placar | aberto |
| RSK-06 | Formato da cópia da conta mal lido (DEFLATE cru, plist binário, ISO 8601 em segundos, datas de 2001 nos JSONs, enum `Setting`) | ALTA | média | E-05, E-06; contrato §1, §4 | vetores do grupo C gerados no iPhone | aberto |
| RSK-07 | Segurança das regras (C1, C2, A1–A3) vale para os dois apps; o Android herda as falhas | ALTA | — | `../seguranca/achados.md` | corrigir regras (decisão do dono) antes de ampliar a base de usuários | aberto |
| RSK-08 | Ambiente: sem JDK (disco resolvido em 22/10: 18 GB livres; o dono tem Android físico) | BLOQUEIO do portão 3 | certa | inventário §7 | liberar espaço (decisão do dono) + JDK + aparelho físico | aberto: só o JDK |
| RSK-09 | Tamanho do app: ~157 MB de sprites PNG + 18 MB de wger | MÉDIA | alta | `ui-parity-analyst` | WebP sem perda; Play Asset Delivery se passar do limite | aberto |
| RSK-10 | Cota do Spark: o segundo app dobra leituras por pessoa; `fetch` de liga relê tudo | MÉDIA | média | contrato §8 | cache offline do Firestore no Android; não repetir o padrão de reler tudo | aberto |
| RSK-11 | `AttributeSplit.tidy` e `Constancy` com empates não determinísticos no próprio iOS | BAIXA | baixa | ND-5; matriz §2 | Android importa a divisão gravada; regra de empate fixa para atividades novas | aberto |
| RSK-12 | Documentação defasada induz erro (README `.mock`, 262 testes, 9 passos, 177 formas, "qualquer pessoa" no X1, Jersey 10) | BAIXA | — | ver seção 3 | corrigir `docs/` (decisão do dono) | aberto |
| RSK-13 | **kcal do HealthKit do Apple Watch publicada** em check-in, ligas e X1; nome da fonte do Saúde vai na prova | ALTA (privacidade, diretriz 5.1.3) | certa no fluxo do relógio | SEC-A5, SEC-A6 | IOS-03 | aberto: decisão do dono |
| RSK-14 | Muitos RNF e "Situação" do RF-SOC descrevem servidor simulado/CloudKit e "nada sobe"; política pública pode prometer menos coleta que a real (ao vivo envia posição e música) | MÉDIA | — | matriz §3 | revisar `docs/privacidade.md` e RNF | aberto |
| RSK-15 | Fotos perdidas ao sair e entrar no mesmo iPhone (`exportedAt` truncado × `savedAt` com fração) | MÉDIA | alta (INFERRED) | E-18 | IOS-06 | aberto |
| RSK-16 | `proof.groupedParts` é entrada de pontuação escrita pelo cliente: inflável sem limite (agrava SEC-A3), diverge se o autor edita a atividade, e vaza kcal do relógio | ALTA | média | E-20; FS-AND-09 | regras/validação (dono); Android grava igual | aberto |
| RSK-17 | Cópia da conta num único lote: acima de ~10 MiB (≈ 11 pedaços) a sincronização para | MÉDIA | depende do tamanho (P10) | contrato §4 | medir `bytes`; dividir em lotes | aberto |
| RSK-18 | ADR-007 reduz mas não elimina perda de dados com a mesma conta nos dois aparelhos sem a fase C | ALTA | média | ADR-007 (revisão B3) | exigências 1–4 do ADR-007; fase C | aberto |
| RSK-R1…R6 | Riscos da reorganização | — | — | `reorganizacao-repositorio.md` §4 | idem | aberto |

## 2. Perguntas ao dono

| # | Pergunta | Por que importa | Recomendação |
|---|---|---|---|
| P1 | Corrigir já no iOS os bugs de paridade, conta e privacidade (IOS-01 `selfID`; IOS-02 exclusão: `reports` + `live` + reautenticação; IOS-03 kcal do relógio; IOS-06 fotos ao sair/entrar)? | sem isso o Android herda placares diferentes e exclusão quebrada | sim, como mudança iOS pequena e separada (exige aprovação para editar Swift e, no caso de `reports`, as regras) |
| P2 | `applicationId` do Android | definitivo depois de publicado | `com.alonsoalmeida.gymbros` (igual ao iOS; são lojas separadas) |
| P3 | Escopo da v1 | define o backlog | ver `../paridade/matriz-ios-android.md` coluna "v1?" e ADRs |
| P4 | Login no Android: só e-mail/senha? Google? Apple? | hoje o iOS só tem e-mail/senha ativo | v1 só e-mail/senha (paridade com o que roda hoje); Google/Apple depois, nos dois apps |
| P5 | Tem aparelho Android físico? Modelo e versão? | o emulador não cabe no disco | — |
| P6 | Liberar espaço: apagar `build/` do repositório (10 GB, regenerável) e/ou a imagem do emulador `android-30` (3,1 GB)? Instalar um JDK 17/21? | bloqueio do portão 3 | apagar `build/` resolve sem perder nada; a imagem do emulador só se não houver aparelho |
| P7 | Branch: seguir na `swift` com branches curtas (recomendado) ou transformar a `main` (hoje um projeto web antigo) em monorepo? | Pages publica da `swift` | `swift` agora |
| P8 | Mesma conta no iPhone e no Android: aceita o ADR-007 (um aparelho dono por vez; o outro fica companheiro, com dados pessoais só leitura), sabendo que sem a fase C (mesclagem, que exige mudar o iOS) o risco cai mas não some? Ou quer a fase C antes da v1? | RSK-03, RSK-18 | ADR-007 (c) na v1 + fase C logo depois |
| P9 | Fuso das regras: manter o do aparelho (como hoje) ou fixar Brasília nos dois apps? | RSK-04 | ver ADR-006 |
| P10 | Corrigir as regras do Firestore apontadas em `../seguranca/achados.md` (C1, C2, A1–A3, M1–M7)? Em que ordem? | vale para os dois apps | C1 e C2 primeiro (localização ao vivo) |
| P11 | Posso rodar a suíte de testes no seu iPhone para registrar a linha de base (358 testes)? Ela usa o app instalado com os seus dados | linha de base exigida antes da fase F | sim, entre 10h e 23h50 |
| P12 | O "Pro" (StoreKit) é real ou é tela de "em breve"? | define se há Play Billing | — |
| P13 | Atualizar `docs/` com as divergências (seção 3)? | `docs/` é o site público | sim, só o que não for de segurança |
| P14 | Vetores compartilhados: aprovar `shared-fixtures/` e um teste Swift "gerador" desligado por padrão (mexe no pbxproj: segundo grupo sincronizado)? | é o que prova a paridade | sim, em mudança separada |

### Decisões do dono (22/10/2026, nesta conversa)

| # | Decisão |
|---|---|
| P1, P10 | **Corrigir tudo no iOS**: IOS-01 (suíço), IOS-02 (exclusão: `reports` + `live` + reautenticação), IOS-03 (kcal e fonte do Saúde), IOS-06 (fotos), regras C1 (`live` com amizade mútua + confirmação no deep link) e C2 (código de amigo reservado). Deploy das regras só com confirmação do dono na hora. **Pré-condição: o dono commita o trabalho em andamento antes** (as correções tocam os mesmos arquivos). |
| P11 | Pode rodar a suíte no iPhone, entre 10h e 23h50. |
| P7 | Dono commita; o trabalho segue na `swift` com branches curtas. |
| P5 | **Tem Android físico** (modelo e versão a informar). |
| P6 | Não autorizou apagar `build/` nem instalar JDK por enquanto: o portão 3 continua bloqueado. |
| P9 | **Fixar `America/Sao_Paulo` em todas as regras de liga, nos dois apps** (IOS-07). |
| P8 | **Mesclagem por UUID antes da v1 do Android** (fase C vira IOS-08, pré-requisito do AND-011). |
| P2, P3, P4 | `com.alonsoalmeida.gymbros`; escopo da v1 conforme ADR-010; login só e-mail e senha. |
| P12 | O Pro é só "em breve": fora do Android. |
| P13 | Atualizar `docs/` com as divergências, sem detalhes de segurança. |
| P14 | Aprovados `shared-fixtures/` + teste gerador desligado por padrão (mexe no pbxproj). |

### Revisão do código da noite (22/10, Fable 5.1)
Corrigidos em `81d9f34`: B1 (perfil antigo sem reserva travaria "esconder treinos"), A1 (diálogo do link travado), A2 (login recente pelo relógio do aparelho), A3 (posts antigos com kcal do relógio e nome do aparelho), A4 (dia trocado a leste de Brasília), A5 (reservas órfãs), M1, M2, M3, M6, robustez do `inflate` no Android.
Abertos: **M4** testes de liga usam o fuso do Mac (fixar `TZ` no esquema ou usar `League.rulesCalendar`); **M5** avisar no "O que há de novo" que o pareamento suíço e o desempate final podem mudar uma vez (efeito da IOS-01/IOS-07); **ND-9** corrigido no iOS em `33bfb7b` (soma na ordem fixa dos atributos, igual ao Android); falta rodar a suíte no iPhone. **ND-10** (novo, 22/10): `AttributeSplit.tidy` do iOS dá o resto do arredondamento ao maior atributo com `max(by:)` sobre dicionário; no empate, o escolhido varia entre execuções (168 de 14.400 casos do vetor S). O Android desempata pela ordem F, R, A, T. Efeito: ±0,01 entre dois atributos empatados, gravado uma vez ao salvar. Correção sugerida no iOS: desempatar em `Attribute.allCases` (aguarda aprovação).

### UX do Android igual à do iPhone (decisão do dono, 22/10)
Toda tela Android reproduz a View SwiftUI correspondente (estrutura, textos, ordem, arte, estados). Pendência: os textos
de termos e privacidade mencionam iPhone, Apple Saúde e o contrato da Apple; antes da Play Store precisam de versão
Android (Health Connect, Google) — decisão do dono sobre o texto.

## 3. Divergências de documentação a corrigir (propostas; decisão do dono)

| Documento | Diz | Código | Evidência |
|---|---|---|---|
| `README.md:59` | `Backend.mode` é `.mock` | `.firebase` com o plist | E-01 |
| `docs/arquitetura.md` | 262 testes em 31 arquivos; aba Histórico; 18 modelos; 7 contratos; "me" pareia igual | 358 em 41; aba Feed; 19 modelos; 11 contratos; não no Firebase | `../arquitetura/ios-estado-atual.md` §5 |
| `docs/requisitos-funcionais/01-jogo-e-bros.md` | 9 passos no tutorial; 177 formas; principal só recebe o não postado; apagar regride | 10 passos; 897; principal sempre 100% e representante 80%; apagar mantém o XP | `../requisitos/matriz-requisitos.md` §1 |
| `docs/requisitos-funcionais/03-social-e-dados.md` | X1 com qualquer pessoa; tabela de bônus sem dias/atividades | só amigos, um por bro; dias 1/0, atividades 10/5 | matriz §2 |
| `docs/excluir-conta.md:18,26` | "se algo der errado nada é apagado"; "nada fica guardado em outro lugar"; servidor simulado | exclusão pode ser parcial; dados ficam no Firestore | E-17 (página exigida pelo Play) |
| `docs/privacidade.md:37` | check-ins vistos pelos participantes da liga | qualquer conta logada lê | `../seguranca/achados.md` SEC-A3 (**não publicar o detalhe do abuso**) |
| Interface `Leagues.swift:141-142` | distância/kcal do Saúde contam | não contam | matriz §2 |
| Cabeçalhos `FirebaseBackend.swift:13-14`, `App.swift:28`, `AccountSync.swift:9-11` | X1/trocas simulados; "Mock ou CloudKit"; cópia "com fotos" | ativos no Firebase; cópia sem fotos | contrato |
| Prompt do dono | "títulos em Jersey 10"; disco 3,2 GB; simuladores desinstalados; sem `.claude/` | fonte do sistema; 4,4 GB; runtimes iOS 26/watchOS 27 presentes; `.claude/settings.local.json` existia | inventário |

## 4. Revisão independente (fase E)

**Revisor:** `independent-reviewer`, chamado pelo nome. O frontmatter pede `fable`, e o agente se identificou como Fable 5.1 (`claude-fable-5-1`), de família diferente do orquestrador (Opus 5.5). Só leitura; 61 consultas ao código.

**Veredito inicial:** "não, por enquanto", com 3 bloqueios que se resolvem editando documentos. O orquestrador conferiu os três no código e incorporou:

| Bloqueio | Correção feita |
|---|---|
| B1: a exclusão de conta também é barrada por `live` | contrato §3, proposta 1, IOS-02, RSK-02, E-17 |
| B2: exclusão parcial com `requiresRecentLogin`; `docs/excluir-conta.md` desatualizada | contrato §3, IOS-02, AND-019, seção 3 |
| B3: caminho de perda de dados no ADR-007 | ADR-007 (exigências 1–4 + limite real), AND-011, RSK-18, P8 |

**Alta prioridade incorporados:** A1 → RSK-15/IOS-06; A2 → FS-AND-09/RSK-16/AND-016; A3 → ADR-006 (`roundHalfAwayFromZero`); A4 → critério A+B+C, `SeededRandom` exato, exemplo corrigido; A5 → P8 alinhada; A6 → CC-8; A7 → RSK-17. Melhorias: `.gitignore` com `**/` e arquivos do Android, `git mv` move as pastas ignoradas (A2 da reorganização corrigido), scripts de `tools/` a conferir, `RuleClock` com calendário fixo, Robolectric/JUnit 4, critério semântico no AND-003.

**Afirmações confirmadas pelo revisor no código:** E-10/ND-1, primeira falha da exclusão em `reports`, E-05/E-06 (DEFLATE ainda INFERRED), E-07, E-09, E-12, RF-JOG-43, SEC-C1, SEC-A5, mecanismo `writer`, 358 testes, pbxproj só com caminhos relativos.

**Recomendação depois das correções (conforme o próprio revisor):** **sim, com ressalvas** (A1–A7 registrados como riscos). Pendente de evidência executada: exclusão de ponta a ponta, teste de fotos ao sair e entrar, vetor C real, `git mv -n`, tamanho da cópia, regras publicadas × arquivo.
