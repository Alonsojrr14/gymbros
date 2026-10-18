# Documentação do GymBros

Documentação levantada a partir do código (outubro de 2026) e atualizada depois das correções de bugs, do design system revisado, da troca da biblioteca de exercícios para o wger, do login simulado com o backend CloudKit atrás de um interruptor e da espécie definida pela atividade. Cada requisito cita o arquivo de origem; quando o código mudar, atualize o requisito junto.

| Documento | O que tem |
|---|---|
| [Arquitetura](arquitetura.md) | Alvos, pastas, navegação, modelo de dados (SwiftData), regras derivadas, contratos de servidor (mock e CloudKit), integrações, testes e dívidas técnicas |
| [Requisitos funcionais · Jogo e bros](requisitos-funcionais/01-jogo-e-bros.md) | `RF-JOG-01…39`: XP, atributos, evolução, espécies, coleção de bros, humor, Dex, conquistas, histórico, lembretes, widgets, atalhos |
| [Requisitos funcionais · Treino](requisitos-funcionais/02-treino.md) | `RF-TRE-01…39`: rotinas, treino guiado, progressão e deload, descanso, recordes, biblioteca (wger) e créditos, mapa muscular, CrossFit/WOD, peso e metas |
| [Requisitos funcionais · Social e dados](requisitos-funcionais/03-social-e-dados.md) | `RF-SOC-01…27`: ligas, times, mural, amigos, perfil público e privado, mapa e localização, Apple Saúde, backup e ajustes |
| [Requisitos não funcionais](requisitos-nao-funcionais.md) | `RNF-01…49`: plataforma, privacidade, segurança, desempenho, confiabilidade, usabilidade, testabilidade e o que o futuro servidor precisa atender |
| [Backend com CloudKit](cloudkit.md) | Interruptor mock/CloudKit, esquema do banco público, permissões, caixa de saída e o que falta |
| [Design system](design-system.md) | Princípios, tokens (cores, tipografia, raios), catálogo de componentes `GM*`, padrões de tela, componentes de domínio e checklist |

## Convenções

- IDs são estáveis: não reaproveite um ID apagado; requisito novo entra no fim da seção com o próximo número.
- "Situação" nos requisitos sociais diz se roda só no aparelho, se usa dados simulados ou se depende de servidor.
- O que não é fato do código aparece como **Recomendação**.

## Situação dos achados

A primeira versão destes documentos listava bugs e pendências encontrados no código. Esta seção resume o que já foi corrigido e o que continua aberto (detalhes e fontes em cada arquivo).

### Corrigido

**Jogo e bros**
- A espécie sai da atividade com mais da metade dos minutos que chocaram o ovo (`GymBros/Bros/Hatch.swift`); toda atividade do app e do Apple Saúde tem um animal e mistura sem atividade principal (ou "Outro") choca Coelho, então "Zoológico completo" e "Dex completa" são possíveis; um bro que volta a ser ovo perde a espécie gravada.
- A prévia de XP (registrar atividade e concluir treino) usa os bros das ligas marcadas, pela mesma regra do `Roster`, e avisa quando mais de um bro vai chocar ou evoluir.
- "Últimas atividades", Histórico e o aviso de importação do Saúde mostram o mesmo XP (o maior entre os bros que receberam a atividade).
- Dois bros evoluindo juntos entram numa fila de cenas, uma depois da outra.
- Uma atividade que cruza mais de um estágio de uma vez escolhe o galho pelos treinos da fase anterior.

**Treino**
- Exercício personalizado aparece pelo nome (ou "Exercício personalizado", se apagado) em recordes, Live Activity e modo fone.
- Aquecimento fica fora de séries e volume em todos os lugares (conclusão, Treinos recentes, Live Activity).
- O encerramento automático usa a média de esforço dos últimos treinos, posta no perfil e nas ligas em andamento com os recordes e deixa na aba Treino a oferta de atualizar a rotina.
- Incremento de 5 kg só com barra em grupo pesado; carga "total" ou "só anilhas" decidida pelo tipo do treino (o ajuste "Carga na barra" saiu).
- Deload vale também para exercício adicionado ou trocado; troca em superset passa o elo para o novo.
- For Time que estoura o limite vira CAP; aviso "Dez segundos" do modo fone sai uma vez por descanso; apagar rotina, exercício do treino e registro de peso pedem confirmação.
- Biblioteca trocada para o wger (imagens, vídeos e instruções com licença comercial e crédito por item), com tela "Créditos e licenças".

**Social e dados**
- Perfil público conta só atividades postadas e só as ligas atuais; "Vale ½" arredonda para cima (no modo Treinos, 1 continua 1).
- Backup guarda se o check-in tinha foto (a pontuação não muda ao restaurar), lugar do check-in, capa reduzida da liga, configurações completas das ligas, recados, foto do perfil, distância e calorias, autor dos comentários, CAP do WOD e mais ajustes de treino, com o tipo de cada ajuste.
- Times com id estável: renomear, reordenar ou tirar um time não troca ninguém de time.
- Placar com unidade no feed, no ranking, no detalhe do check-in e no campeão das temporadas passadas.
- Comentários guardam o autor; só os seus podem ser apagados. Sair da liga apaga também comentários e recados.
- A mesma pessoa simulada tem o mesmo bro na liga, no mapa e nos amigos.
- Códigos de liga e de amigo exigem 6 caracteres; liga com participantes de exemplo não oferece convite; ligas que não começaram não aceitam check-in.
- A saída de um lugar fecha a visita daquele lugar; restaurar backup reinicia o monitoramento e não cria lugar inexistente.
- "Recomeçar jornada" descreve exatamente o que apaga e não apaga mais o nome do treinador.

**Não funcionais**
- O banco não derruba mais o app: se não abrir, o arquivo é guardado ao lado, o app abre com um banco novo e avisa como voltar pelo backup. O banco tem file protection (`completeUntilFirstUserAuthentication`).
- Cache de snapshot (`Game.cachedSnapshot`) evita recalcular o histórico a cada render.
- Textos de tamanho próprio passaram a usar `gmFont` (acompanha o Dynamic Type); botões só com ícone têm rótulo do VoiceOver.
- 90 testes (eram 43).

**Design system**
- Cores em `Shared/Theme.swift` (app e widget), com tokens semânticos no lugar de `.orange`, `.yellow`, `.cyan`, `.pink` e da cor fixa do vídeo.
- Escala de raios (`radiusXS` a `radiusXL`); cards da Home, Dex, Mapa, rota e treino usam `GMCard` ou os tokens.
- Novos `GMFloatingButton`, `GMCompactStepper`, `GMMonth` e `gmFont`; `GMTextButton` em uso; `GMModal` sem `cancel:`; `GMScreen(close:)` no perfil; cena de evolução por `gmModal`; `GMCalendar` e `ActivityCalendar` com a mesma grade.

### Continua pendente

**Decisões de produto**
- Pontos de liga e posts do perfil usam o XP bruto, sem o teto diário do bro.
- No modo Calorias, os seus check-ins usam as calorias do Saúde e os simulados sempre a estimativa com 70 kg.
- Backup em JSON sem criptografia, com localização, medidas corporais e perfil físico; fotos de check-in e de progresso continuam fora. Lembretes, preferências do Saúde e de lugares e a visibilidade do perfil também não entram.
- Servidor: login, ligas (criar, entrar, check-ins, times, recados) e amigos com perfil público já têm contrato e implementação CloudKit, mas `Backend.mode` segue `.mock` (login simulado, sem rede) até o app ter iCloud. Comentários, foto do perfil, fotos de outras pessoas e amigos ao vivo ainda não sobem (`cloudkit.md`).
- Schema versionado só no `SchemaV1`: a próxima mudança de modelo precisa de um `SchemaV2` e um estágio no `AppMigrationPlan`, ou a migração que falhar ainda começa o app do zero (com o arquivo antigo guardado).
- Foto do perfil em `UserDefaults`; Dynamic Type ainda com tamanhos fixos em ícones, emojis e widgets.
- Design: cores do sistema na escala de esforço e nas rotas do mapa, `GMRangeCalendar` com grade própria e alguns cards montados à mão com os tokens.

**Migração para a conta corporativa (não feita)**
- Bundle IDs (`com.alonsoalmeida.gymbros*`), App Group e time de assinatura `5UV7WAAAL2` continuam na conta pessoal. Antes de publicar ou ligar um servidor, migrar para a conta corporativa (o App Group muda junto e exige migrar o banco SwiftData, que está no container do grupo, e os dados do widget). Credenciais do futuro servidor ficam em cofre ou gerenciador de segredos, nunca no código ou em texto puro.
