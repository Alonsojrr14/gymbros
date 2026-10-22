# Referência de Compose do GymBros

Checklist escrito para este projeto. Usado pelo `android-implementation-agent` ao implementar e pelo `independent-reviewer` ao revisar telas Android.

**Origem.** Foi escrito com palavras próprias, depois da leitura de três fontes MIT, das quais nenhum trecho foi copiado: o comando `adapt-ios-to-android` do kiln (MoonlightByte/kiln), o agente `compose-guide` do pacote everything-claude-code-mobile (ahmed3elshaer) e a skill `ios-to-android` (michaelboeding/skills). A revisão de 21/10/2026 apontou o que essas fontes erram para o caso do GymBros. Ver "O que não seguir" no fim.

## Estado e ViewModel
1. Cada tela tem um `ViewModel` que expõe um único `UiState` imutável em `StateFlow`. A tela nunca chama o repositório.
2. Os singletons `@MainActor @Observable` do iOS (`AuthStore`, `AccountSync`, `LeagueRemoteStore`…) viram repositórios com escopo do app que publicam `StateFlow`. Eles não guardam estado de tela.
3. A coleta é sempre com `collectAsStateWithLifecycle`.
4. Estado local e passageiro (texto digitado, aba aberta) fica em `rememberSaveable`. O treino em andamento e o rascunho de check-in sobrevivem à morte do processo (`SavedStateHandle` ou banco local).
5. O que no iOS é `@AppStorage` vai para o DataStore. A primeira tela espera o primeiro valor, para não piscar o padrão errado.
6. Os componentes `GM*` recebem valor e callback. A fonte da verdade fica em quem chama.
7. A carga de dados começa no `ViewModel`. `LaunchedEffect` só serve para o que depende da composição (foco, rolagem, medição).

## Listas
8. Toda lista preguiçosa tem `key` estável (UUID da atividade, id da forma do bro) e `contentType` quando mistura tipos de linha.
9. O BroBook (897 formas) é `LazyVerticalGrid`, com sprites decodificados num tamanho limitado.
10. Toda lista funciona com 1, 5 e 50 itens, mostra `GMEmptyState` quando vazia e aplica os mesmos truncamentos de negócio do iOS (feed 150, comentários dos 60 primeiros, X1 20, trocas 20, vencedores 6).
11. A posição de rolagem sobrevive à rotação e ao voltar.

## Efeitos e segundo plano
12. Nada de rede, disco ou `launch` solto no corpo do composable.
13. Efeito de vida longa (descanso, tutorial) usa `rememberUpdatedState` no callback.
14. Observadores de ciclo de vida usam `LifecycleEventEffect`/`DisposableEffect`, com limpeza.
15. O envio da cópia da conta e outros envios usam WorkManager (trabalho único, com rede como restrição). `ON_STOP` sozinho não basta, porque o processo pode morrer.

## Tema e tokens
16. As cores saem das frações RGB de `Shared/Theme.swift` (`Color(0.05f, 0.06f, 0.08f)` etc.), nunca do hex arredondado.
17. Sem cor dinâmica do Material e sem seguir o tema do sistema: a marca é fixa e o app é sempre escuro. Janela e splash pretos, ícones claros nas barras do sistema.
18. O Material 3 só serve de base. Cada `GM*` define forma, cor e estados (pressionado, desabilitado) pelos tokens. Raios: 4, 10, 12, 16, 20, 28.
19. Texto em `sp` pela escala equivalente ao `gmFont`. A barra de abas e o ao vivo têm teto de escala, como no iOS. O layout não pode quebrar em 200%.
20. Pixel art em `drawable-nodpi`, desenhada com `FilterQuality.None`. Nunca deixar o sistema reescalar por densidade.

## Navegação, voltar e janela
21. Rotas tipadas. A raiz segue o estado de sessão do iOS: sem sessão, carregando a conta, tutorial, termos, principal.
22. O voltar do sistema é tratado nas abas, `gmModal`, sheets, tutorial e treino em andamento, com confirmação quando houver perda. Usar a API de voltar predito.
23. Edge-to-edge: `WindowInsets` na barra de abas, nas sheets e nos campos; `imePadding` com teclado aberto.

## Acessibilidade
24. Alvo de toque de pelo menos 48 dp em todo controle, mesmo quando o desenho é menor (`GMPress`, `GMChip`).
25. Cards agrupam a semântica (`mergeDescendants`). Ícone decorativo fica sem descrição. Ícone com função recebe `contentDescription` com o mesmo texto do `accessibilityLabel` do iOS.
26. `GMStepper`, `GMSegmented`, `GMWheel` e `GMCalendar` expõem `Role`, `stateDescription` e ações de ajuste.
27. Campos com `ImeAction` coerente, autofill no login e ordem de foco previsível.

## Desempenho e testes de UI
28. Valores que mudam rápido (cronômetro, animação) são lidos dentro de `graphicsLayer`/`Canvas`, não no corpo.
29. Medir antes de otimizar (macrobenchmark na rolagem do BroBook e do feed).
30. Testes de UI cobrem 1/5/50 itens, fonte em 1,0 e 2,0, alvo de toque e semântica.

## SwiftUI do GymBros → Compose
| SwiftUI | Compose | Nota |
|---|---|---|
| `VStack`/`HStack`/`ZStack` | `Column`/`Row`/`Box` | `Arrangement.spacedBy` |
| `LazyVStack`/`LazyVGrid` | `LazyColumn`/`LazyVerticalGrid` | `key` + `contentType` |
| `NavigationStack` | `NavHost` com rotas tipadas | |
| `gmModal`/`gmSheet` | `ModalBottomSheet` ou componente próprio | conferir ao implementar |
| `@State` | `remember`/`rememberSaveable` | |
| `@Observable` singleton | repositório + `StateFlow` → `ViewModel` → `UiState` | não há equivalente direto |
| `@AppStorage` | DataStore | assíncrono |
| `scenePhase` | `LifecycleEventEffect`/`LifecycleResumeEffect` | |
| `.task(id:)`, `.onChange(of:)` | `LaunchedEffect(chave)`, `snapshotFlow` | só para efeito de UI |
| `GeometryReader` | `BoxWithConstraints`/`onSizeChanged` | |
| `.accessibilityLabel`, `.accessibilityElement(children: .combine)` | `semantics { contentDescription }`, `mergeDescendants` | |
| `@FocusState` | `FocusRequester` + `LocalFocusManager` | |
| `.sensoryFeedback` | `LocalHapticFeedback` | os tipos diferem |
| `Menu`/`.alert` | `DropdownMenu`/`AlertDialog` estilizados | |
| SF Symbols | Material Symbols ou vetores próprios | os símbolos da Apple não podem ser redistribuídos; mapear à mão |

## O que não seguir (erros das fontes para este projeto)
- "Use sempre `MaterialTheme.colorScheme`/tipografia e cor dinâmica": a marca é fixa e o app é sempre escuro.
- "`@EnvironmentObject` → `CompositionLocal` para dados": `CompositionLocal` fica só para tokens e escala. Dados de domínio são injetados no `ViewModel`.
- "`collectAsState`" e "carregar em `LaunchedEffect(Unit)`/`onAppear`": use `collectAsStateWithLifecycle` e carregue no `ViewModel`.
- Rotas de texto com `navArgument`: use rotas tipadas.
- `@Immutable`/`ImmutableList` em todo lugar: com o *strong skipping* (padrão nos compiladores atuais) é exceção. O que importa é `UiState` imutável.
- "Copie os assets do iOS": `.xcassets`, SF Symbols e a fonte SF exigem conversão ou substituição, não cópia.
