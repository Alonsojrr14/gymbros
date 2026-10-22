---
name: android-foundation
description: Executa a fase G do GymBros - criar o projeto Android em android/ (Gradle, tema, regras de domínio puras com vetores de teste compartilhados) conforme a arquitetura aprovada. Só depois do portão 3 (ambiente com JDK e espaço, applicationId decidido, app Android registrado no Firebase pelo dono).
disable-model-invocation: true
---

# /android-foundation — fase G (portão 3)

## Pré-condições (todas)
1. Dono aprovou o portão 3 nesta conversa.
2. `applicationId` decidido e registrado em `engenharia/arquitetura/decisoes.md`.
3. Ambiente resolvido e verificado por comando: `java -version` (JDK real), espaço livre suficiente (`df -h /`), aparelho Android físico (`adb devices`) ou decisão explícita de testar só na JVM. Não instale nada você mesmo.
4. App Android registrado no Firebase **pelo dono**; `google-services.json` em `android/app/` e ignorado pelo git (`git check-ignore` confirma) antes de qualquer build.
5. ADRs da fundação aprovados.

## Ordem
Tarefas AND da fundação em `engenharia/plano/backlog-android.md`, uma por vez, cada uma delegada ao `android-implementation-agent` com: ID, requisitos, critérios de aceite, arquivos esperados, comando de teste.
1. Esqueleto Gradle (wrapper, catálogo de versões, módulos aprovados), `.gitignore` do Android.
2. Tema e componentes base equivalentes aos `GM*` (tokens de `ios/Shared/Theme.swift`).
3. Regras de domínio puras em Kotlin + testes JVM consumindo `ios/GymBrosTests/Fixtures` (vetores gerados pelo iOS). Divergência numérica com o Swift é falha.

Depois de cada tarefa: confira você mesmo o diff e a saída dos testes, atualize `engenharia/paridade/matriz-ios-android.md` e `engenharia/plano/resultados-validacao.md`. Regras de domínio passam pelo `independent-reviewer`.

## Proibido
Tocar `ios/` (ou `GymBros*/`, `ios/Shared/`), `firebase/`, `docs/`; deploy de regras; dependência fora da matriz aprovada; declarar pronto sem testes rodados.
