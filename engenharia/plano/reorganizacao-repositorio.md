# Plano de reorganização do repositório (fase F)

**Escopo.** Levar o app iOS para `ios/` e preparar a raiz para `android/`, sem quebrar o build do iPhone, o GitHub Pages nem os scripts. **Só plano**: nada foi movido.
**Base de evidência.** `../descoberta/inventario-repositorio.md` (pbxproj, esquema, `.gitignore`, `tools/`); `git branch -a` do orquestrador; checklist do `qa-strategy-analyst`.
**Status.** Proposta para o portão 2. Precisa de árvore limpa, aprovação do manifesto e decisão de branch.

## 1. Estrutura proposta

```text
gymbros/
├── ios/                    # app iOS completo (projeto + 6 pastas)
│   ├── GymBros.xcodeproj/
│   ├── GymBros/  GymBrosWidget/  GymBrosWatch/  GymBrosWatchWidget/  GymBrosTests/  Shared/
│   └── tools/              # geradores que escrevem no app iOS (wger, artes)
├── android/                # fase G
├── shared-fixtures/        # vetores de teste compartilhados (se aprovado; mudança separada)
├── firebase/               # contrato dos dois apps (fica)
├── docs/                   # GitHub Pages (NÃO pode mudar de lugar)
├── engenharia/  .claude/  CLAUDE.md
├── README.md  CREDITOS.md  NOTICE.md            # do produto: ficam na raiz
├── EVOLUCAO.md  HIBRIDOS.md  VIRADAS.md         # ver seção 3
└── ANALISE-GYMRATS.md                           # do dono, não rastreado: não mexer
```

## 2. Manifesto (origem → destino), só `git mv`

| # | Origem | Destino | Ajuste necessário | Evidência |
|---|---|---|---|---|
| M1 | `GymBros.xcodeproj/` | `ios/GymBros.xcodeproj/` | nenhum: todos os caminhos do pbxproj são relativos ao projeto; `Package.resolved` está dentro dele | inventário §2 |
| M2 | `GymBros/` | `ios/GymBros/` | — | grupo sincronizado `path = GymBros` |
| M3 | `GymBrosWidget/` | `ios/GymBrosWidget/` | — | idem |
| M4 | `GymBrosWatch/` | `ios/GymBrosWatch/` | — | idem |
| M5 | `GymBrosWatchWidget/` | `ios/GymBrosWatchWidget/` | — | idem |
| M6 | `GymBrosTests/` | `ios/GymBrosTests/` | — | idem |
| M7 | `Shared/` | `ios/Shared/` | — | idem |
| M8 | `tools/` | `ios/tools/` | **nenhum nos scripts**: `build.py`, `commons.py`, `everkinetic.py` calculam a raiz 3 níveis acima (`tools/wger/x.py` → raiz) e `instalar.sh` usa `${0:A:h:h:h}`; dentro de `ios/` a "raiz" deles passa a ser `ios/`, onde estão `GymBros/` e `GymBrosWidget/`. `prompts.py` usa `../..` → `ios/`. **Exceção:** `prompts.py:44` lê `HIBRIDOS.md` na raiz deles → mover `HIBRIDOS.md` junto ou ajustar 1 linha | VERIFIED pelo orquestrador: `tools/wger/build.py:11`, `everkinetic.py:12`, `commons.py:10`, `tools/artes/prompts.py:7,44`, `instalar.sh:4`, `viradas.py:20,33` |
| M9 | `HIBRIDOS.md`, `VIRADAS.md` | `ios/` | listas de arte usadas pelos scripts de `tools/artes` | `prompts.py:44`; `VIRADAS.md:3` |
| M10 | `EVOLUCAO.md` | fica na raiz | histórico do produto | — |
| A1 | `.gitignore` | editar **antes** do `git mv` | trocar a entrada por `**/GoogleService-Info.plist` e já acrescentar `google-services.json`, `local.properties`, `.gradle/`, `*.jks`, `*.keystore` (SEC-AND-08). `build/`, `xcuserdata/`, `graphify-out/` já valem em qualquer nível | `.gitignore:8`; revisão |
| A2 | `GoogleService-Info.plist` e pastas ignoradas dentro de `tools/` (`.work*` 580 MB, `node_modules`) | **vão junto** no `git mv` do diretório (renomeação no disco) | **corrigido na revisão:** a versão anterior dizia que `git mv` não move o plist, e isso está errado. Conferir antes com `git mv -n` e `git status --ignored`, com A1 já aplicado | revisão (INFERRED; conferir com `-n`) |
| A3 | `CLAUDE.md`, `.claude/skills/*`, `.claude/settings.json` | editar | comandos com `-project ios/GymBros.xcodeproj`; deny de leitura do plist já cobre `ios/…` | — |
| A4 | `README.md`, `CREDITOS.md`, `NOTICE.md`, `tools/README.md` | editar | caminhos em texto e comandos (`README.md:101-110`) | inventário §6 |
| A5 | `docs/*.md` | **proposta**, decisão do dono | ~470 menções em texto a `GymBros/…` (não quebram o site, só ficam desatualizadas); comandos em `docs/rbac.md:148`, `docs/publicacao.md:48` | inventário §6 |
| A6 | `build/` (10 GB, ignorado) | não mover; apagar é **decisão do dono** | o novo build usa `-derivedDataPath build` a partir da raiz ou de `ios/` | — |
| A7 | `graphify-out/` | não mover; regenerar depois (ignorado) | — | — |

**Não muda:** `firebase/`, `docs/`, `engenharia/`, `.claude/agents/`, `ANALISE-GYMRATS.md`.

## 3. Arquivos da raiz

| Arquivo | Decisão proposta | Motivo |
|---|---|---|
| `README.md` | raiz | apresenta o produto (iOS + Android) |
| `CREDITOS.md`, `NOTICE.md` | raiz | licenças valem para os dois apps (wger CC BY-SA, MuscleMap MIT) |
| `EVOLUCAO.md` | raiz | histórico do produto |
| `HIBRIDOS.md`, `VIRADAS.md` | `ios/` | insumo dos scripts de arte do iOS |
| `ANALISE-GYMRATS.md` | raiz, intocado | trabalho do dono, não rastreado |

## 4. Riscos

| ID | Risco | Mitigação |
|---|---|---|
| RSK-R1 | `GoogleService-Info.plist` ser commitado depois da mudança | A1 no mesmo commit; `git check-ignore -v ios/GymBros/Resources/GoogleService-Info.plist` antes de qualquer `git add` |
| RSK-R2 | Xcode reescrever o pbxproj ao abrir (formato, `objectVersion`) | build só por `xcodebuild`; conferir `git diff --stat` do pbxproj = vazio |
| RSK-R3 | Script de `tools/` escrever no lugar errado em silêncio | conferir `ROOT` de cada script por leitura antes de mover; não rodar scripts na validação |
| RSK-R4 | Pacotes SPM re-resolvidos com versão nova | `Package.resolved` vai junto; build com `-onlyUsePackageVersionsFromResolvedFile` (a confirmar com o Xcode 27.1) |
| RSK-R5 | Histórico do `git log` por arquivo | `git log --follow` funciona com `git mv` puro (sem editar conteúdo no mesmo commit, exceto `.gitignore`) |
| RSK-R6 | Disco (4,4 GB livres) não aguentar um build limpo novo | reaproveitar `build/` (DerivedData) na raiz com `-derivedDataPath build`; medir antes |

Scripts de `tools/` conferidos na revisão como relativos ao próprio arquivo: `codex.py`, `cursor.py`, `grade.py`, `gerar.mjs`, `lote-viradas.sh`. **Ainda não conferidos** (fazer antes de mover): `chrome.sh`, `folha.swift`, `recortar-final.swift`, `tools/recortar-*.swift`.

## 5. Validação depois de mover
0. Antes: `git mv -n` de cada item do manifesto e `git status --ignored`.
1. `git status`: só renomeações + `.gitignore` + documentos; `git check-ignore -v ios/GymBros/Resources/GoogleService-Info.plist`.
2. Build no iPhone:
   ```sh
   UDID=00008150-001E15363C04C01C
   xcodebuild -project ios/GymBros.xcodeproj -scheme GymBros -destination "id=$UDID" \
     -derivedDataPath build -allowProvisioningUpdates build
   xcrun devicectl device install app --device $UDID build/Build/Products/Debug-iphoneos/GymBros.app
   ```
   Pronto só com "App installed". Widget e relógio vêm por dependência do esquema.
3. Com a concordância do dono: `xcodebuild test …` no iPhone, **358 testes, 0 falhas**, entre 10h e 23h50.
4. Manual: abrir o app logado (dados presentes, sem nova restauração), widget aparece, relógio pareia.

## 6. Rollback
- Antes do commit: `git mv` de volta, na ordem inversa do manifesto, + reverter `.gitignore`.
- Depois do commit: commit isolado só com a reorganização → `git revert <commit>`. O plist (não rastreado) volta com `mv`.

## 7. Branch (recomendação)

Fatos (VERIFIED, `git branch -a`): a `main` (`origin/HEAD`) é **um projeto web antigo** (Next.js + `backend/`), e a `swift` contém tudo da `main` mais 123 commits. O GitHub Pages publica de `swift:/docs` (segundo o dono; configuração do GitHub não consultada).

| Opção | Prós | Contras |
|---|---|---|
| **A. Continuar na `swift`, com branches curtas por fase** (`reorg/ios`, `android/fundacao`, `android/AND-xx`) mescladas na `swift` depois de validadas | Pages não muda; um só tronco; rollback por merge/revert | o nome "swift" fica estranho com Android dentro |
| B. Branch longa `android` separada | isola o Android | dois troncos divergindo; a reorganização para `ios/` teria de entrar nos dois |
| C. Transformar a `main` em monorepo agora | nome certo | exige decidir o destino do projeto web da `main`, mudar o Pages e o branch padrão no GitHub (ação externa) |

**Recomendação: A agora**; C mais tarde, quando você decidir o que fazer com o projeto web da `main` (arquivar numa tag, por exemplo). Nenhuma ação no GitHub sem a sua aprovação.

## Pré-condições do portão 2
1. Você commita o trabalho em andamento (22 modificados + `CommentSync.swift`) e decide o que fazer com os arquivos novos desta rodada (`CLAUDE.md`, `.claude/`, `engenharia/`).
2. Aprovação explícita deste manifesto e da opção de branch.
3. iPhone conectado; linha de base do build registrada antes de mover.
