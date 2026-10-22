---
name: android-feature
description: Executa a fase H do GymBros - implementar UMA feature Android aprovada (tarefa AND-xx) com rastreabilidade a requisitos, testes e atualização da matriz de paridade. Use com o ID da tarefa, depois do portão 4.
argument-hint: AND-xx
disable-model-invocation: true
---

# /android-feature AND-xx — fase H (portão 4)

## Pré-condições
1. Fundação concluída (`engenharia/README.md`).
2. A tarefa `$ARGUMENTS` existe em `engenharia/plano/backlog-android.md` com requisitos (RF-…), critérios de aceite, dependências e plano de testes, e o dono aprovou o escopo nesta conversa.
3. Dependências da tarefa concluídas.

## Fluxo
1. Releia os requisitos citados em `engenharia/requisitos/matriz-requisitos.md` e o comportamento de referência no iOS (arquivo e símbolo). Se faltar evidência, investigue antes de implementar.
2. Delegue ao `android-implementation-agent` com o pacote completo (ID, requisitos, critérios, arquivos, testes, limites). Uma feature por vez; nada de juntar tarefas.
3. Confira o diff e rode você mesmo os testes indicados. Compilar não prova funcionamento.
4. Feature crítica (conta, cópia da conta, regras do jogo, ligas, X1, Saúde, permissões) → `independent-reviewer` antes de fechar.
5. UI: siga `referencia-compose.md` (nesta pasta); teste com 1, 5 e 50 itens; tokens do tema; leitor de tela e escala de fonte.
6. Atualize `engenharia/paridade/matriz-ios-android.md` (status da seção 16 do plano), `engenharia/plano/resultados-validacao.md` e pendências em `engenharia/plano/riscos-e-perguntas.md`.

## Proibido
Tocar no iOS, em `firebase/` ou `docs/`; mudar o contrato do Firestore; decisão arquitetural nova sem ADR aprovado.
