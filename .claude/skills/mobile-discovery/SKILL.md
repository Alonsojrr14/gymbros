---
name: mobile-discovery
description: Orquestra a descoberta do app iOS do GymBros e o planejamento do Android (fases A a E) com os especialistas de .claude/agents, somente leitura, até o portão 1. Use quando o dono pedir /mobile-discovery, "descobrir o app", "planejar o Android" ou retomar a descoberta.
disable-model-invocation: true
---

# /mobile-discovery — fases A a E

Você (sessão principal) é o orquestrador. Os especialistas não delegam; só você integra e escreve em `engenharia/`. Responda em português do Brasil.

## Antes de tudo
1. Leia `engenharia/README.md` (estado, portões, pendências). Se uma fase já está concluída, **continue dela**; não refaça.
2. Confirme o ambiente: `git status --short`, `git rev-parse HEAD`, `df -h /`, `xcrun devicectl list devices`. Se HEAD mudou desde a última rodada, liste os arquivos alterados (`git diff --stat <commit-anterior>`) e reabra só os achados afetados.

## Fase A — ambiente e repositório
- `repository-analyst`: inventário, caminhos referenciados, comandos de build. Resultado → `engenharia/descoberta/inventario-repositorio.md`.

## Fase B — análises em paralelo (no máximo 4 agentes ao mesmo tempo)
Lote 1: `ios-architecture-analyst`, `firebase-contract-analyst`, `security-analyst`, `requirements-analyst` (recorte: regras críticas + RF-JOG).
Lote 2: `requirements-analyst` (RF-TRE, RF-SOC, RNF), `ui-parity-analyst`, `qa-strategy-analyst`.
No prompt de cada um: recorte exato, o que já se sabe (para não repetir), formato de saída curto, status VERIFIED/INFERRED/UNKNOWN/CONFLICTING obrigatório. Rode em segundo plano e consolide à medida que chegam.

## Fase C — consolidação (você)
- Confira pessoalmente as afirmações críticas no código: login e sessão, regras do Firestore, cópia da conta, XP/anti-farm/evolução/divisão de atributos, pareamento suíço, pontuação das ligas, dados do Saúde.
- Divergência entre agentes: nomeie a diferença exata e investigue (leitura sua ou pergunta pontual a um agente). Nunca escolha a mais conveniente.
- Escreva: `engenharia/arquitetura/ios-estado-atual.md`, `engenharia/requisitos/matriz-requisitos.md`, `engenharia/requisitos/contrato-firestore.md`, `engenharia/seguranca/achados.md`, `engenharia/descoberta/indice-evidencias.md`. Não duplique `docs/`: referencie e registre divergências com proposta de correção.

## Fase D — desenho
- `android-architect` com os documentos consolidados → `engenharia/arquitetura/android-arquitetura-alvo.md`, `engenharia/arquitetura/decisoes.md`, `engenharia/requisitos/capacidades-plataforma.md`.
- Você: `engenharia/plano/reorganizacao-repositorio.md` (manifesto, impacto, rollback), `engenharia/plano/backlog-android.md`, `engenharia/plano/estrategia-testes.md`, `engenharia/paridade/matriz-ios-android.md`, `engenharia/plano/riscos-e-perguntas.md`.

## Fase E — revisão independente e portão 1
- `independent-reviewer` sobre os documentos acima, conferindo no código as 5+ afirmações mais críticas.
- Incorpore ou conteste cada bloqueio. Registre em `engenharia/plano/riscos-e-perguntas.md`.
- Atualize `engenharia/README.md` (fase, data, HEAD, o que rodou, o que não rodou) e `engenharia/plano/resultados-validacao.md`.
- **Pare.** Apresente: o que foi criado, agentes que rodaram (modelo configurado), divergências doc × código, manifesto resumido, arquitetura Android e fora da v1, riscos e bloqueios, perguntas ao dono, próximo passo exato.

## Proibido nesta skill
Mover/renomear/apagar arquivos do app, editar Swift/pbxproj/entitlements/Info.plist, commit/push/branch/stash/reset/clean/checkout, qualquer acesso ao Firebase real, instalar qualquer coisa, rodar scripts do repositório, rodar testes iOS sem o dono concordar (rodam no iPhone dele, com dados reais).

## Evidência
VERIFIED exige código, configuração, teste ou saída de comando observada; documentação sozinha nunca basta. Cadeia: evidência → RF → ADR → AND → teste → paridade.
