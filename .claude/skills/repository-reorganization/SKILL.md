---
name: repository-reorganization
description: Executa a fase F do GymBros - mover o app iOS para ios/ conforme o manifesto aprovado em engenharia/plano/reorganizacao-repositorio.md, com commit isolado e reversível, e validar com build e instalação no iPhone. Só depois do portão 2 aprovado pelo dono.
disable-model-invocation: true
---

# /repository-reorganization — fase F (portão 2)

## Pré-condições (todas, senão pare e diga qual falta)
1. Dono aprovou explicitamente o manifesto **nesta conversa**.
2. `git status --short` vazio (árvore limpa: o dono commitou o trabalho em andamento).
3. Branch combinada com o dono (ver `engenharia/plano/reorganizacao-repositorio.md`, seção de branch).
4. iPhone conectado: `xcrun devicectl list devices` mostra "iPhone de Zero" disponível.
5. Linha de base registrada em `engenharia/plano/resultados-validacao.md` (build antes da mudança).

## Execução
1. Releia o manifesto. Confira que cada origem existe (`git ls-files`) e que nenhum destino existe.
2. Só `git mv` para as movimentações (preserva histórico). Nada de copiar e apagar.
3. Ajustes de caminho listados no manifesto (`.gitignore`, `tools/wger/build.py`, README), um por um, mostrando o diff. Não edite `project.pbxproj` à mão salvo se o manifesto disser exatamente o quê; o projeto inteiro vai junto para `ios/` e as referências relativas internas continuam válidas.
4. Fora de `ios/` ficam: `firebase/`, `docs/` (GitHub Pages, não pode mudar de lugar), `engenharia/`, `.claude/`, `CLAUDE.md`, `README.md` e o que o manifesto decidir.
5. Build e instalação:
   ```sh
   UDID=00008150-001E15363C04C01C
   xcodebuild -project ios/GymBros.xcodeproj -scheme GymBros -destination "id=$UDID" \
     -derivedDataPath build -allowProvisioningUpdates build
   xcrun devicectl device install app --device $UDID build/Build/Products/Debug-iphoneos/GymBros.app
   ```
   Entregue só com "App installed". Testes (`xcodebuild test …`) só se o dono concordar.
6. Atualize `CLAUDE.md` (mapa e comandos) e `engenharia/README.md`.
7. Commit isolado só com a reorganização, se o dono pedir o commit. Mensagem em português.

## Rollback
`git revert <commit>` (ou, antes do commit, `git mv` de volta conforme o manifesto). Registre o caminho de volta em `engenharia/plano/resultados-validacao.md`.

## Proibido
Apagar arquivos, mexer em `docs/`, tocar no Firebase, `reset --hard`, `clean`, `stash`, push sem pedido.
