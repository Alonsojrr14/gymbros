# IOS-08 — Mesclagem da cópia da conta (desenho para aprovação)

**Escopo.** Trocar o "última escrita vence" da cópia da conta (`accounts/{uid}`) por uma mesclagem por entidade. Assim a mesma conta funciona em dois aparelhos (iPhone + Android, ou dois iPhones) sem perder dados. Decisão do dono em 22/10: a mesclagem vem antes da v1 do Android (P8).
**Base de evidência.** `GymBros/Services/AccountSync.swift` (`enter`, `upload`), `FirebaseGame.swift:301-358` (`FirebaseAccountDataBackend`), `Backup.swift` (DTOs), contrato §4–5, ADR-007, RSK-03/17/18.
**Status.** **Desenho, não implementado.** Implementar só depois da aprovação do dono.

## 1. O problema hoje
- O envio grava a cópia inteira, sem ler a da nuvem (`FirebaseGame.swift:317-336`).
- O aparelho que já é dono nunca baixa de novo (`AccountSync.swift:153-157`).
- Com dois aparelhos ativos, cada envio apaga da nuvem o que o outro fez.

## 2. A ideia: mesclagem em três vias com a última cópia sincronizada como base

Cada aparelho já guarda um arquivo com a última cópia que enviou ou recebeu (`MockAccountDataBackend` local, com fotos). Esse arquivo vira a **base**. Para sincronizar:

```
remoto = cópia da nuvem (se o hash mudou desde a base)
mesclado = merge(local, remoto, base)
aplica `mesclado` no aparelho (sem apagar o que só existe aqui)
envia `mesclado` com transação: só grava se o hash da nuvem ainda for o de `remoto`
base = mesclado
```

Regra por entidade com UUID (`activities`, `routines`, `sessions`, `customExercises`, `leagues`, `monsters`, `body`, `checkIns`, `routes`, `visits`, `gyms`, `wods`, `prs`, `comments`, `messages`, `reviews`):

| Local | Remoto | Base | Resultado |
|---|---|---|---|
| igual à base | mudou | existe | remoto (o outro aparelho editou) |
| mudou | igual à base | existe | local |
| mudou | mudou | existe | **conflito**: fica a versão do lado com a cópia mais nova (`exportedAt` local × `savedAt` remoto, comparados em segundos), e a outra vai para `setAside` |
| existe | não existe | existe | apagado no outro aparelho → apaga aqui, a menos que tenha mudado aqui (aí fica) |
| não existe | existe | existe | apagado aqui → não volta, a menos que tenha mudado lá (aí volta) |
| existe | não existe | não existe | novo aqui → fica |
| não existe | existe | não existe | novo lá → entra |

- Sem base (primeiro uso da versão nova, ou aparelho novo): **união** por UUID. Em conflito, fica a cópia mais nova. Nada é apagado.
- "Mudou" = o JSON da entidade é diferente (comparação estável, com `sortedKeys`).
- Entidades sem UUID próprio vão junto do pai: itens da rotina com a rotina, séries com a sessão. Notas de exercício usam `exerciseID` como chave.
- Ajustes da conta (`settings`, `typedSettings`, `accountSettings` em plist): três vias **por chave**, com a mesma tabela. Listas guardadas em ajustes que funcionam como registro (`RetiredActivities`, `duelScoreRecords`, livro de trocas): **união por id**, nunca substituição.
- Fotos: continuam fora da nuvem; a mesclagem preserva a foto local de quem tem.

**Por que não `updatedAt` por entidade nem marcadores de exclusão:** exigiriam o `SchemaV6` no SwiftData (migração) e mudanças em todo lugar que grava. A base de três vias dá o mesmo resultado com o que já existe, e o único caso ambíguo, a mesma entidade editada nos dois aparelhos entre duas sincronizações, é raro e não perde a outra versão.

## 3. Mudanças no iOS
1. `AccountSync.enter`: o aparelho que já é dono também consulta o metadado; se o `hash` da nuvem ≠ hash da base, mescla.
2. `FirebaseAccountDataBackend.upload`: lê o metadado; se mudou, baixa, mescla e aplica antes de enviar. Envio em **transação** comparando o `hash`. Pedaços em mais de um lote quando passar de ~8 MB (RSK-17).
3. `Backup.merge(local:remote:base:)`: função pura, com testes de cada linha da tabela.
4. `Backup.restore(into:)` ganha um modo "aplicar mesclado", que atualiza por UUID em vez de apagar tudo e recriar.
5. Metadado com `format: 2`. Um aparelho com a versão antiga continua no "última escrita vence", e a interface avisa "atualize o app no outro aparelho" quando vê `format: 2`.
6. Mudança de comportamento visível: nenhuma, além de não perder dados.

## 4. Android
A mesma `merge` em `:core:domain`, provada por um **grupo D** de vetores gerado pelo Swift (casos da tabela + casos aleatórios). O modo dono/companheiro do ADR-007 deixa de ser necessário quando os dois lados tiverem `format: 2`. Fica só como proteção enquanto houver um aparelho com versão antiga.

## 5. Testes
- Swift: uma linha da tabela por teste; união sem base; conflito com `setAside`; registros unidos; idempotência (`merge(x, x, x) == x`); `merge(local, remoto, base)` aplicado duas vezes dá o mesmo resultado.
- Aparelho: iPhone + segunda instalação (ou Android), editando os dois sem rede e sincronizando nas duas ordens.
- Vetores D compartilhados com o Kotlin.

## 6. Riscos
| Risco | Mitigação |
|---|---|
| Restaurar por UUID deixa lixo de relações (rotina sem itens) | aplicar por agregado (rotina com itens, sessão com séries) |
| Cópia grande + mesclagem no envio de segundo plano | mesclar só quando o hash mudou; envio pelo WorkManager no Android e `beginBackgroundTask` no iOS |
| Aparelho com versão antiga sobrescreve | `format: 2` + aviso; pedir para atualizar os dois |

## 7. Esforço estimado
iOS: médio a grande (função de mesclagem pura e testada, restauração por UUID, transação). Android: médio, depois do iOS. Sugestão de ordem: (1) `Backup.merge` + testes; (2) restauração por UUID; (3) fluxo de envio e entrada; (4) vetores D; (5) Android.
