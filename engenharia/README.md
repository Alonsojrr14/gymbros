# Engenharia do GymBros (iOS → Android)

**Escopo.** Documentos internos da descoberta do app iOS e do planejamento do app Android. Não é publicado (o site público é `docs/`). Achados de segurança ficam só aqui.
**Status.** Fase E concluída em 21/10/2026 (rodada 1). Portão 1 respondido pelo dono em 22/10/2026.

## Estado

| Item | Valor |
|---|---|
| Rodada | 1 (21/10/2026) |
| HEAD analisado | `7ab62342` (branch `swift`) + 22 arquivos modificados e 2 não rastreados do dono (analisados como estão no disco) |
| Fase atual | Noite de 22/10: correções iOS (IOS-01/02/03/04/06/07, C1, C2), `docs/` atualizado, reorganização para `ios/` (fase F) e fundação Android (`:core:domain` com paridade provada por vetores; `:app` compilando). IOS-08 desenhado, aguardando aprovação |
| Próximo portão | 1 → 2 (reorganização), ver `plano/riscos-e-perguntas.md` |
| Testes | iOS 372 (0 falhas) no iPhone; Android 19 (0 falhas) na JVM. Ver `plano/resultados-validacao.md` V-11…V-20 |
| Branches | `swift` (+2 commits: trabalho do dono e infraestrutura) → `ios/correcoes-paridade` → `reorg/ios` (atual). **Nada foi enviado ao GitHub** |
| Caminhos | o app iOS mudou para `ios/`; os documentos desta pasta anteriores a 22/10 citam os caminhos antigos (`GymBros/…` = `ios/GymBros/…`) |

## Para o dono, de manhã (22/10)

1. ✅ Suíte no iPhone sobre `33bfb7b`: 375 testes, 0 falhas, instalado (V-24). Volte o bloqueio automático ao normal.
2. **Regras do Firestore** (`firebase/firestore.rules`, nada foi publicado): só depois do item 1 e com o app novo instalado em todo celular que usa o GymBros (a regra do código de amigo recusa perfis de versões antigas). Comando: `cd firebase && firebase deploy --only firestore:rules`.
3. ✅ IOS-08 aprovada e implementada (V-27/V-28). ~~Aprovar ou ajustar o desenho da IOS-08~~ (`arquitetura/ios-08-mesclagem.md`): mesclagem em três vias da cópia da conta.
4. ✅ Apps Android registrados e `google-services.json` no lugar (V-25). ~~Firebase: registrar~~ os apps Android `com.alonsoalmeida.gymbros` e `com.alonsoalmeida.gymbros.debug` e colocar o `google-services.json` em `android/app/` (fica fora do git).
5. ✅ App Android instalado e abrindo no Redmi Note 9S (V-30). ~~Celular Android ligado por cabo~~
6. ✅ Mesclado na `swift` local (V-26); falta só o push, decisão do dono. ~~Mesclar as branches~~ na `swift` quando estiver satisfeito: `swift` ← `ios/correcoes-paridade` ← `reorg/ios` (atual). Nada foi enviado ao GitHub.
7. Decidir se a política de privacidade deve dizer que check-ins de liga podem ser lidos por outras contas (SEC-A3) ou se as regras são corrigidas antes.

## Portões

| Portão | Status | Bloqueios |
|---|---|---|
| 1. Descoberta concluída | **aprovado com ressalvas** (revisor) e decisões do dono em 22/10 | perguntas P1–P14 e riscos RSK-01…18 em `plano/riscos-e-perguntas.md` |
| 2. Reorganização | **feita** na branch `reorg/ios`, validada no iPhone (V-19) | mesclar na `swift` quando o dono aprovar |
| 3. Fundação Android | **em andamento**: JDK e disco resolvidos, `applicationId` decidido, domínio e `:app` prontos | registro do app no Firebase (dono), aparelho Android conectado para instalar |
| 4. Features | não iniciado | portão 3 |
| 5. Publicação | não iniciado | — |

## Mapa dos documentos

| Documento | Conteúdo |
|---|---|
| `descoberta/inventario-repositorio.md` | alvos, pacotes, recursos, scripts, caminhos referenciados, ambiente |
| `descoberta/indice-evidencias.md` | afirmações críticas → evidência → status; o que cada agente fez |
| `arquitetura/ios-estado-atual.md` | arquitetura real do iOS (complementa `docs/arquitetura.md`) e divergências |
| `arquitetura/android-arquitetura-alvo.md` | arquitetura proposta para o Android |
| `arquitetura/decisoes.md` | ADRs |
| `requisitos/matriz-requisitos.md` | requisitos conferidos no código (IDs de `docs/requisitos-*`), novos, regras de negócio críticas |
| `requisitos/contrato-firestore.md` | contrato do Firestore e da cópia da conta |
| `requisitos/capacidades-plataforma.md` | capacidades Apple → Android |
| `paridade/matriz-ios-android.md` | status de paridade por requisito |
| `plano/reorganizacao-repositorio.md` | manifesto de movimentação para `ios/`, impacto, rollback, branch |
| `plano/backlog-android.md` | tarefas AND-xx |
| `plano/estrategia-testes.md` | QA iOS atual, estratégia Android, vetores compartilhados |
| `plano/riscos-e-perguntas.md` | riscos RSK-xx e perguntas ao dono |
| `plano/resultados-validacao.md` | o que foi executado, comandos, saídas, o que não rodou |
| `seguranca/achados.md` | achados de segurança e privacidade |

## Como retomar
Rode `/mobile-discovery` (ela lê este arquivo e continua do estado acima). Fases seguintes: `/repository-reorganization`, `/android-foundation`, `/android-feature AND-xx`, `/parity-audit`.

Status de evidência usado em todos os documentos: **VERIFIED** (código, configuração, teste ou saída observada), **INFERRED**, **UNKNOWN**, **CONFLICTING** (fontes divergem; o código vence).
