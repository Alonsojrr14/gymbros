# Design system do GymBros

Documentação do design system do app, extraída do código. Fontes principais:

- `Shared/Theme.swift`: `enum Theme` com todas as cores, compilado no app e no widget.
- `GymBros/DesignSystem/`: componentes com prefixo `GM`, um arquivo por família: `GymBros/DesignSystem/DesignSystem.swift` (escala de raios em `extension Theme` e `gmFont`), `GymBros/DesignSystem/GMButtons.swift`, `GymBros/DesignSystem/GMSurfaces.swift` (cards, seções, linhas), `GymBros/DesignSystem/GMIndicators.swift` (progresso, badge, online), `GymBros/DesignSystem/GMChips.swift` e `GymBros/DesignSystem/GMFlow.swift`, `GymBros/DesignSystem/GMToggles.swift`, `GymBros/DesignSystem/GMFields.swift`, `GymBros/DesignSystem/GMSteppers.swift`, `GymBros/DesignSystem/GMCalendar.swift` (datas, `GMMonth`, roletas), `GymBros/DesignSystem/GMScreen.swift` (cabeçalho, tela, modal), `GymBros/DesignSystem/GMSheets.swift` (bottom sheet, ações, prompt), `GymBros/DesignSystem/GMTabBar.swift`, `GymBros/DesignSystem/GMKeyboard.swift`, `GymBros/DesignSystem/GMExtensions.swift` e `GymBros/DesignSystem/PeriodPicker.swift`.
- `GymBros/Models/Activity.swift`: `Attribute.color`.
- `GymBros/Bros/Game.swift`: nomes e SF Symbols de `Attribute` e `ActivityKind`.
- Componentes de domínio: `GymBros/Bros/MonsterSprite.swift`, `GymBros/Profile/ProfileView.swift`, `GymBros/Friends/PublicProfile.swift`, `GymBros/Profile/ProfileCalendar.swift`, `GymBros/Leagues/LeaguesView.swift`, `GymBros/Bros/HomeView.swift`, `GymBros/Friends/FriendsLive.swift`, `GymBros/Activities/LogActivityView.swift`.

## 1. Princípios

1. **Nada de controles padrão do iOS.** `Form`, `List`, `Picker`, `Toggle`, `Stepper`, `Slider`, `DatePicker`, `Menu`, `alert`, `confirmationDialog`, barra de navegação e `TabView` são substituídos por componentes `GM`. A busca no código confirma isso: nenhum desses aparece fora de comentários.
2. **O que continua do sistema** (o iOS não deixa substituir): teclado, seletor de fotos (`PhotosPicker`), tela de compartilhar, seletor de arquivos e pedidos de permissão. A navegação por pilha continua com `NavigationStack`/`NavigationLink`, com a barra escondida (`.toolbar(.hidden, for: .navigationBar)`); o gesto de voltar pela borda é reativado por uma extensão de `UINavigationController` em `GymBros/DesignSystem/GMExtensions.swift`.
3. **Sempre escuro.** `GymBros/App/App.swift` aplica `.preferredColorScheme(.dark)` e `gmModal` repete `.preferredColorScheme(.dark).tint(Theme.accent)` nas telas modais (inclusive na cena de evolução). Não existe variante clara.
4. **Tom:** jogo, mas sem infantilizar. Títulos grandes em `.rounded`/`.heavy`, um único acento verde-limão, tudo tocável encolhe de leve (`GMPress`), vibração em toda escolha. Textos em português, informais ("Bora treinar?", "Mande o primeiro recado pra galera da liga.").
5. **O bro é o centro.** A barra de abas tem o bro numa bolinha elevada no meio; o monstro aparece em listas, ligas, perfil e amigos.
6. **Acessível por padrão.** Texto de tamanho próprio passa por `gmFont` (cresce com o Dynamic Type) e todo botão só com ícone tem rótulo do VoiceOver.

## 2. Tokens

### 2.1 Cores

Todas em `Shared/Theme.swift`, compartilhado entre app e widget (widgets e Live Activities usam `Theme.*`, sem cópias locais).

**Base**

| Token | Definição no código | RGB (0–255) | Hex aprox. | Uso |
|---|---|---|---|---|
| `Theme.bg` | `Color(red: 0.05, green: 0.06, blue: 0.08)` | 13, 15, 20 | `#0D0F14` | Fundo de todas as telas (`GMScreen`, `GMModal`), widgets e Live Activities |
| `Theme.card` | `Color(red: 0.10, green: 0.11, blue: 0.14)` | 26, 28, 36 | `#1A1C24` | Cards, sheets, fundo do `GMSegmented` e da busca |
| `Theme.accent` | `Color(red: 0.64, green: 0.90, blue: 0.21)` | 163, 230, 54 | `#A3E636` | Ação primária, seleção, XP, destaques. Texto sobre ele é **preto** |
| `Theme.dim` | `Color.white.opacity(0.55)` | branco 55 % | — | Texto secundário, rótulos de seção, ícones apagados |
| `Theme.raised` | `Color.white.opacity(0.06)` | branco 6 % | — | Superfície elevada dentro de card: botão secundário, campos, ícone de linha, balão do bro, steppers |
| `Theme.stroke` | `Color.white.opacity(0.08)` | branco 8 % | — | Divisores e contornos |
| `Theme.track` | `Color.white.opacity(0.1)` | branco 10 % | — | Trilho vazio de barras (`GMProgressBar`, `GMEffortPicker`) |
| `Theme.danger` | `Color(red: 1.0, green: 0.38, blue: 0.38)` | 255, 97, 97 | `#FF6161` | Ações destrutivas (`GMButtonKind.danger`, ícone de apagar) |
| Texto principal | `.white` | 255, 255, 255 | `#FFFFFF` | — |

**Semânticas** (substituem as cores do sistema usadas soltas)

| Token | Valor | Uso |
|---|---|---|
| `Theme.streak` | `.orange` | Fogo: sequência de dias, WOD, série de aquecimento ("A") |
| `Theme.warning` | `.orange` | Alerta: meta não batida, volume abaixo do ideal, CAP, descanso do Tabata, aviso de permissão |
| `Theme.info` | `.cyan` | Superset e volume acima do ideal |
| `Theme.trophy` | `.yellow` | Conquistas, recordes, PR no gráfico |
| `Theme.note` | `.yellow` | Nota do exercício no treino |
| `Theme.health` | `.pink` | Origem Apple Saúde |
| `Theme.online` | `Color(red: 0.25, green: 0.88, blue: 0.42)` (`#40E06B`) | Amigo online / treinando agora (`GMOnlineDot`) |
| `Theme.badge` | `.red` | Contador de notificação na aba |
| `Theme.video` | `Color(red: 0.9, green: 0.2, blue: 0.2)` | Botão "Buscar vídeos no YouTube" |

`streak` e `warning` (e `trophy` e `note`) têm o mesmo valor hoje, mas significados diferentes: use o token pelo significado.

Uso no código (ocorrências de `Theme.*` em app, widget e `Shared/`): `dim` 241, `accent` 170, `raised` 54, `bg` 26, `card` 23, `warning` 11, `stroke` 10, `streak` 10, `trophy` 7, `danger` 5, `info` 5, `track` 2, `health` 2, `note`, `online`, `badge` e `video` 1 cada.

**Cores dos atributos** (`extension Attribute` em `GymBros/Models/Activity.swift`):

| Atributo | Definição | RGB | Hex aprox. | Símbolo |
|---|---|---|---|---|
| Força (`.forca`) | `Color(red: 1.0, green: 0.45, blue: 0.30)` | 255, 115, 77 | `#FF734D` | `dumbbell.fill` |
| Resistência (`.resistencia`) | `Color(red: 0.35, green: 0.70, blue: 1.0)` | 89, 179, 255 | `#59B3FF` | `heart.fill` |
| Agilidade (`.agilidade`) | `Color(red: 0.98, green: 0.82, blue: 0.20)` | 250, 209, 51 | `#FAD133` | `bolt.fill` |
| Técnica (`.tecnica`) | `Color(red: 0.72, green: 0.52, blue: 1.0)` | 184, 133, 255 | `#B885FF` | `sparkles` |

As cores de atributo também colorem o anel da bolinha central da `GMTabBar` (gradiente angular acento → resistência → técnica → força) e o status "ao vivo" dos amigos (`LiveFriend.color(kind)` em `GymBros/Friends/FriendsLive.swift` mapeia o tipo de atividade para um atributo).

**Cores que ainda ficam fora dos tokens**

| Onde | Cor | Papel |
|---|---|---|
| `GMEffortPicker` | `Theme.accent` (1–3), `.yellow` (4–6), `.orange` (7–8), `.red` (9–10) | Escala de esforço |
| `MapScreen` (`color(kind)`) | `.orange` (bike), `.cyan` (caminhada), acento (resto) | Cor do percurso por tipo |
| `MuscleViews` (`HeatmapColorScale`) | cinza → `.yellow` → `.orange` → `.red` | Mapa de calor muscular |
| `PlateCalculatorView` | `.red`, `.blue`, `.yellow`, `.green`… por anilha | Cores olímpicas das anilhas (domínio) |
| `PetWidget` | `Color(red: 0.12, green: 0.16, blue: 0.10)` → `Theme.bg` | Degradê de fundo do widget |
| `GMSwitch` desligado / `XPBar` do widget | `.white.opacity(0.15)` / `.white.opacity(0.12)` | Trilhos |
| Overlays (`gmSheet` etc.) | `.black.opacity(0.55)` | Fundo escurecido |
| Ilustrações do wger | `Color.white` | Fundo das imagens (vêm com fundo branco) |

### 2.2 Tipografia

Só a fonte do sistema (SF). Estilos do sistema (`.headline`, `.caption`…) para quase tudo; tamanho próprio sempre por `gmFont(size, weight:, design:, mono:, relativeTo:)`, que usa `@ScaledMetric` relativo ao estilo indicado e cresce com o Dynamic Type (25 usos).

| Papel | Estilo | Onde |
|---|---|---|
| Título de tela (grande) | `gmFont(32, weight: .heavy, design: .rounded, relativeTo: .largeTitle)` | `GMHeader` (`large`) |
| Título de tela com voltar | `gmFont(26, weight: .heavy, design: .rounded, relativeTo: .title)` | `GMScreen` com `back: true`, título do check-in, nome da liga |
| Nome do bro | `gmFont(28, weight: .heavy, design: .rounded, relativeTo: .title)` | `HomeView` |
| Números de destaque | `.title2.weight(.heavy).monospacedDigit()`, `gmFont(34…120, weight: .heavy, design: .rounded, mono: true, relativeTo: .largeTitle)` com `minimumScaleFactor` | Prévia de XP, cronômetros, dias da liga, peso |
| Título de modal / sheet | `.headline` | `GMModal`, `gmActions`, `gmPrompt` |
| Botão | `.headline` (normal) / `.subheadline.bold()` (`small`) | `GMButton` |
| Título de linha, chip, segmento | `.subheadline.weight(.semibold)` | `GMRow`, `GMChip`, `GMSegmented`, `GMToggle` |
| Subtítulo, rodapé, metadado | `.caption` + `Theme.dim` | `GMRow`, `GMSection` (footer) |
| Rótulo de seção | `.caption.weight(.bold)`, caixa alta, `tracking(0.6)`, `Theme.dim` | `GMSection` |
| Badge | `.caption2.bold()` | `GMBadge` |
| Aba | `gmFont(10, weight: .semibold, relativeTo: .caption2)`; ícone `.system(size: 18, weight: .semibold)`; barra limitada a `xxLarge` | `GMTabBar` |
| Roleta | `.system(size: 30/24, weight: .bold/.medium, design: .rounded).monospacedDigit()` | `GMWheel` |

Regras práticas: **números sempre `.monospacedDigit()`** (ou `gmFont(…, mono: true)`) e `.contentTransition(.numericText())` quando o valor muda em tela (`GMStepper`, `GMCompactStepper`). Nada de `.font(.system(size:))` em texto: os 30 que restam são ícones, emojis e o widget do bro.

### 2.3 Espaçamentos

| Valor | Uso recorrente |
|---|---|
| 16 | Margem lateral das telas (`GMScreen`, `GMModal`, `GMHeader`); padding padrão do `GMCard` |
| 18 | Espaço vertical entre blocos da tela (`VStack(spacing: 18)` em `GMScreen`/`GMModal`) |
| 12 | Espaço interno do `GMCard`; entre ícone e texto em `GMRow` |
| 8–10 | Entre título/card/rodapé no `GMSection` (8); entre itens de sheet (10); chips (`GMFlow`, 8) |
| 2–4 | Título ↔ subtítulo (2), padding horizontal de rótulo de seção (4) |
| 100 | `bottomInset` padrão do `GMScreen`, para o conteúdo não ficar sob a `GMTabBar` |

Contagem no código: `spacing: 2` (49), `12` (45), `10` (43), `8` (28), `4` (27), `6` (23).

### 2.4 Raios

Escala única em `extension Theme` (`GymBros/DesignSystem/DesignSystem.swift`). Não há mais raio numérico solto no app nem no widget.

| Token | Valor | Onde |
|---|---|---|
| `Theme.radiusXS` | 4 | Barras finas: `GMEffortPicker`, mapa de calor das estatísticas, anilhas |
| `Theme.radiusS` | 10 | Quadrado de ícone (`GMRow`, campos de data/hora, `ActivityRow`), miniaturas, dias da rotina |
| `Theme.radiusM` | 12 | `GMTextField`, `GMButton` `small`, `GMCompactStepper`, roletas, fotos em lista, `ActivityKindGrid`, balão do bro, imagens e vídeo do wger |
| `Theme.radiusL` | 16 | `GMButton` normal, blocos dentro de card, mapas, status do mapa |
| `Theme.radius` | 20 | `GMCard` (e `GMSection`), cards de exercício e barra de descanso do treino, cards da Dex e da liga |
| `Theme.radiusXL` | 28 | `GMSheetCard` (topo do bottom sheet) e diálogo `gmPrompt` |
| `.capsule` | — | Chips, segmentado, busca, badge, barra de abas, valor dos campos de data |
| `.circle` | — | `GMIconButton`, botões do stepper, avatar, `GMFloatingButton` |

### 2.5 Ícones

Somente SF Symbols (as imagens de exercícios são ilustrações do wger, não ícones). Peso típico `.semibold`; ícone de linha em quadrado 34×34 com `Theme.raised`.

| Atividade (`ActivityKind.symbol`) | Símbolo |
|---|---|
| Musculação | `figure.strengthtraining.traditional` |
| Crossfit | `figure.cross.training` |
| Corrida | `figure.run` |
| Caminhada | `figure.walk` |
| Bike | `figure.outdoor.cycle` |
| Natação | `figure.pool.swim` |
| Vôlei | `figure.volleyball` |
| Futebol | `figure.indoor.soccer` |
| Lutas | `figure.martial.arts` |
| Dança | `figure.dance` |
| Yoga | `figure.yoga` |
| Outro | `figure.mixed.cardio` |

Abas (`GymBros/App/App.swift`): Treino `dumbbell.fill`, Ligas `trophy.fill`, Mapa `map.fill`, Histórico `list.bullet`; o centro é o sprite do bro. Ícones de ação recorrentes, com o rótulo do VoiceOver que `GMIconButton` dá a eles por padrão: `chevron.left` (Voltar), `xmark` (Fechar), `ellipsis` (Mais opções), `pencil` (Editar), `trash` (Apagar), `plus` (Adicionar), `gearshape` (Ajustes), `person.2.fill` (Amigos), `pawprint.fill` (Bros), `square.and.arrow.up` (Compartilhar).

### 2.6 Movimento

- Toque: `GMPress` (escala 0,96, opacidade 0,85, `.spring(duration: 0.25)`).
- Seleção deslizante: `matchedGeometryEffect` em `GMSegmented` e `GMTabBar`, `.spring(duration: 0.3)`.
- Overlays: entrada `.spring(duration: 0.35, bounce: 0.15)`, saída `.easeOut(duration: 0.2)`; sheet sobe da borda inferior e fecha arrastando mais de 120 pt; diálogo central entra com `scale(0.9)` + opacidade.

## 3. Catálogo de componentes

### Estrutura de tela

#### `GMScreen`
Tela padrão: cabeçalho próprio (`GMHeader`) + `ScrollView` com `VStack(spacing: 18)`, fundo `Theme.bg`, botão "OK" do teclado e barra de navegação escondida.
Parâmetros: `title`, `subtitle`, `back` (mostra `chevron.left` e usa título de 26 pt abaixo da barra), `avatar` (bolinha do perfil à esquerda, telas raiz das abas), `close` (X à esquerda, para tela apresentada com `gmModal` que não é formulário, como o perfil), `large`, `bottomInset` (100), `trailing` (botões à direita), `content`.

```swift
// ActivityDetail.swift
GMScreen(activity.kind.name, back: true) {
    GMIconButton(icon: "pencil", label: "Editar atividade") { editing = true }
} content: { ... }

// ProfileView.swift
GMScreen("", close: true, large: false, bottomInset: 110) {
    GMIconButton(icon: "gearshape", label: "Ajustes") { settings = true }
} content: { ... }
```
Não usar: em formulários apresentados como modal (use `GMModal`); dentro de sheet.

#### `GMHeader`
Cabeçalho usado internamente por `GMScreen` (`leading`, `trailing`, `large`, `inlineTitle`). O título pequeno da barra fica no centro da tela (num `ZStack` com 100 pt de folga de cada lado), não entre os botões: com a seta só de um lado, ele era empurrado para fora do centro. Com `back` e título grande, o título grande fica embaixo da barra e o pequeno não se repete (`inlineTitle: false`). Não é usado diretamente em nenhuma tela; prefira `GMScreen`.

#### `GMModal` + `gmModal(isPresented:)` / `gmModal(item:)`
Tela cheia de formulário: `xmark` à esquerda (rótulo "Fechar"), título central, `GMButton` pequeno de confirmação à direita. `gmModal` apresenta com `fullScreenCover`, força tema escuro e tinta de acento.
Parâmetros: `title`, `confirm`, `confirmEnabled`, `onConfirm`, `content`. Não há mais `cancel:`: o fechar é sempre o ícone `xmark`.

```swift
// CustomExerciseForm.swift
GMModal(editing == nil ? "Novo exercício" : "Editar exercício", confirm: "Salvar",
        confirmEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty, onConfirm: save) { ... }

// HomeView.swift
.gmModal(isPresented: $logging) { LogActivityView(snapshot: snapshot) }
```
Não usar: para escolher um único valor (use `gmSheet`) ou para confirmar (use `gmActions`). Não use `.sheet` nem `.fullScreenCover` direto.

#### `GMSection`
Rótulo pequeno em caixa alta + `GMCard` + rodapé explicativo. Substitui seções de `Form`.
Parâmetros: `title`, `footer`, `trailing: AnyView?`, `content`.

```swift
// LogActivityView.swift
GMSection(footer: "Quão puxado foi, de 1 (bem leve) a 10 (no limite).") {
    GMEffortPicker(value: $effort)
}
```
Não usar: para um card sem rótulo nem rodapé (use `GMCard`).

#### `GMCard`
Superfície `Theme.card`, raio `Theme.radius` (20), `padding` (padrão 16; a Home e a corrida usam 18), `VStack(alignment: .leading, spacing: 12)`, largura total.

```swift
// DexView.swift
GMCard { GMToggle(title: "Revelar todas", subtitle: "Mostra todas as formas, sem contar como descoberta", isOn: $revealAll) }
```
Não usar: aninhado em outro card (use `Theme.raised` para a camada interna).

#### `GMDivider`
Linha de 1 pt em `Theme.stroke`, entre itens de um card. Ver padrão de listas na seção 4.

#### `GMIconTile`, `GMNavRow`, `GMIconToggle`, `GMCountBadge`

Peças das telas de ajustes (`GymBros/DesignSystem/GMSettings.swift`). `GMIconTile` é o quadrado `Theme.radiusS` com gradiente da cor do grupo e ícone preto; cada grupo tem a sua cor (Notificações `Theme.badge`, Treino `Theme.streak`, Saúde `Theme.health`, Conta `Theme.info`, Privacidade técnica, Zona de perigo `Theme.danger`). `GMNavRow` é o label de `NavigationLink` com título, valor atual à direita e seta. `GMIconToggle` é um `GMToggle` com o quadrado à esquerda. `GMCountBadge` é o contador de não lidos; `.gmCountBadge(n)` põe o contador no canto de um `GMIconButton` (sino da tela inicial). `GMRow` aceita `tile:` para usar o quadrado colorido no lugar do fundo discreto.

```swift
NavigationLink { NotificationSettingsPage() } label: {
    GMNavRow(icon: "bell.badge.fill", tint: Theme.badge, title: "Notificações", value: "6 de 6")
}
.buttonStyle(GMPress())
```

Ajustes é um índice (`SettingsView`): cartão do perfil com o bro, grupos "App", "Conta e dados" e "Ajuda", "Recomeçar jornada" (só em builds de desenvolvimento) e a versão. Cada assunto é uma tela `GMScreen(back: true)` empurrada no `NavigationStack` (`SettingsPages.swift`).

#### `GMRow`
Linha tocável: ícone em quadrado 34×34, título, subtítulo, conteúdo à direita (`trailing`) e `chevron` opcional. Sem `action`, é só visual.

```swift
// LeaguesView.swift
GMRow(icon: "plus.circle", iconTint: Theme.accent, title: "Criar liga", chevron: true) { creating = true }
```
Não usar: para par rótulo/valor somente leitura (use `GMValueRow`) ou interruptor (use `GMToggle`).

#### `GMValueRow`
Rótulo em `Theme.dim` à esquerda, valor em semibold à direita. Substitui `LabeledContent`.

```swift
// ActivityDetail.swift
GMValueRow(label: "Duração", value: durationText(activity.minutes))
```

### Botões

#### `GMButton` e `GMButtonKind`

| `kind` | Fundo | Texto | Uso |
|---|---|---|---|
| `.primary` | `Theme.accent` | preto | Ação principal da tela (uma por tela) |
| `.secondary` | `Theme.raised` | branco | Ações neutras, itens de `gmActions` |
| `.danger` | `Theme.danger` 15 % | `Theme.danger` | Ação destrutiva confirmada |
| `.ghost` | transparente | branco | "Cancelar", "Ir para hoje" |

Parâmetros: `title`, `icon`, `kind`, `full` (largura total, padrão `true`), `small`, `enabled` (opacidade 0,4 quando falso).

```swift
// HomeView.swift
GMButton("Registrar atividade", icon: "plus.circle.fill") { logging = true }
// WorkoutView.swift
GMButton("Série", icon: "plus", kind: .secondary, full: false, small: true) { ... }
```
Não usar: `.danger` para abrir a confirmação; o botão que *abre* a confirmação é `.secondary` (`"Apagar atividade"` em `GymBros/Activities/ActivityDetail.swift`), e o `.danger` fica dentro do `gmActions`.

#### `GMIconButton`
Círculo `Theme.raised` com SF Symbol. Parâmetros: `icon`, `size` (40), `tint` (branco), `label` (rótulo do VoiceOver). Sem `label`, o rótulo vem de `defaultLabel(icon)` ("Fechar", "Voltar", "Mais opções", "Ajustes"…; ícones desconhecidos viram o nome do símbolo sem pontos). Passe `label` sempre que o ícone sozinho não disser a ação (30 dos 44 usos passam).

```swift
// HomeView.swift
GMIconButton(icon: "gearshape", label: "Ajustes") { settings = true }
// WorkoutView.swift
GMIconButton(icon: "minus", size: 38, label: "Menos 15 segundos") { ... }
```
Não usar: para a ação principal (use `GMButton` ou `GMFloatingButton`).

#### `GMFloatingButton`
Círculo de acento 62×62 com ícone preto (`icon`, padrão `plus`), sombra `.black.opacity(0.4), radius: 10, y: 4`, `GMPress` e `label` obrigatório para o VoiceOver. Quem usa posiciona com `.overlay(alignment: .bottomTrailing)` e o padding (acima da barra de abas: `padding(.trailing, 20).padding(.bottom, 90)`).

```swift
// LeaguesView.swift
GMFloatingButton(label: "Novo check-in") { checkingIn = true }
    .padding(.trailing, 20).padding(.bottom, 90)
// ProfileView.swift
GMFloatingButton(label: "Registrar atividade") { logging = true }.padding(20)
```
Não usar: mais de um por tela, ou para ação que não seja a criação principal de uma tela longa.

#### `GMTextButton`
Texto em acento, para cabeçalhos de tela ou de seção. Parâmetros: `title`, `icon` (opcional, vira `Label`), `bold`, `small` (tamanho de rótulo de seção, `.caption.bold()`, sem padding), `enabled`.

```swift
// MapScreen.swift (trailing de GMSection)
GMTextButton(title: "Adicionar", icon: "plus", small: true) { editing = GymEdit(gym: nil) }
```

#### `GMPress`
`ButtonStyle` aplicado a tudo que é tocável, inclusive `NavigationLink` e botões customizados (`.buttonStyle(GMPress())`). Não use `.plain` em itens tocáveis comuns; só `GMSegmented` e `GMTabBar` usam `.plain`, porque têm animação própria.

### Seleção

#### `GMSegmented`
Abas segmentadas com cápsula de acento deslizante. Parâmetros: `options: [(T, String)]`, `selection`.

```swift
// LeaguesView.swift
GMSegmented(options: [(0, "Check-ins"), (1, "Ranking"), (2, "Mural")], selection: $tab)
```
Não usar: com mais de 3–4 opções ou rótulos longos (o texto encolhe até 80 %); use `GMChoiceChips`.

#### `GMChoiceChips` e `GMChip`
`GMChoiceChips` substitui `Picker` de menu: título opcional + chips em `GMFlow`, com vibração de seleção. `GMChip` é o chip isolado (`title`, `icon`, `selected`, `action`).

```swift
// CustomExerciseForm.swift
GMChoiceChips(title: "Grupo muscular", options: MuscleGroup.allCases.map { ($0, $0.name) }, selection: $group)
// LogActivityView.swift (atalhos de duração)
GMChip(title: "\(m) min", selected: minutes == m) { minutes = m }
```
Não usar: `GMChip` solto quando há uma única seleção entre opções fixas (prefira `GMChoiceChips`, que já vibra).

#### `GMFlow`
`Layout` que quebra linha (`spacing` 8). Usado por chips e conquistas. Ocupa toda a largura oferecida e quebra com 1 pt de folga (`slack`) para o arredondamento de pixels; sem isso, a linha mais larga cabia no cálculo da altura, quebrava na hora de posicionar e os chips vazavam do card.

```swift
// PublicProfile.swift
GMFlow { ForEach(a.prefix(6), id: \.self) { b in Label(b.title, systemImage: b.symbol) ... } }
```

#### `GMToggle` / `GMSwitch`
`GMToggle` = título + subtítulo + `GMSwitch` (cápsula 50×30, acento ligado, vibração leve). `GMSwitch` não é usado diretamente.

```swift
// SettingsView.swift
GMToggle(title: "Resumo da semana", subtitle: "Domingo às 19h: treinos, tempo, PRs e sua posição nas ligas", isOn: $weeklySummary)
```

### Valores numéricos

#### `GMStepper`
"− valor +", com vibração e `numericText`. Parâmetros: `title`, `value`, `range`, `step`, `format`.

```swift
// LogActivityView.swift
GMStepper(value: $minutes, range: 5...Game.maxMinutes, step: 5, format: durationText)
```
Não usar: para decimais opcionais (use `GMDecimalField`) nem em grades apertadas (use `GMCompactStepper`).

#### `GMCompactStepper`
Bloco "− valor/rótulo +" em `Theme.raised`, raio `radiusM`, para grades e linhas apertadas; vibra (`.light`) e anima o valor. Parâmetros: `value: Double`, `range`, `step`, `label: Text`, `decimals` (até 2 casas), `editable` (o valor vira campo digitável, com teclado numérico). Há um `init` inteiro (`value: Binding<Int>`, `label: String`). Os botões têm rótulo "Diminuir"/"Aumentar". Substituiu o `MiniStepper` da rotina e o campo próprio das séries do treino.

```swift
// RoutineEditView.swift
GMCompactStepper(value: $item.sets, range: 1...10, step: 1, label: "séries")
// WorkoutView.swift (SetRow)
GMCompactStepper(value: weight, step: increment, label: Text(unit), decimals: true, editable: true)
```

#### `GMDecimalField`
Decimal opcional com − + e digitação (`.decimalPad`); vazio mostra "—". Parâmetros: `title`, `value: Double?`, `step` (0,5), `unit` ("kg"), `start` (70), `clearable`, `grouping` (padrão `true`; `false` tira o separador de milhar, para anos e números que não levam ponto).

```swift
// BodyTrackerView.swift
GMDecimalField(title: "Peso", value: $weight, step: 0.1, start: lastWeight)
// BodyProfile.swift (ano mostra 1995, não 1.995)
GMDecimalField(title: "", value: year, step: 1, unit: "", start: 1995, grouping: false)
```

#### `GMLockedRow`
Valor salvo que não fica editável o tempo todo: título à esquerda, valor à direita ("Não informado" em `Theme.dim` quando vazio, `.monospacedDigit()`) e um botão redondo de lápis (34 pt, `Theme.raised`). Tocar no lápis abre o editor embaixo, esconde o valor e troca o ícone por um ✓ em acento (texto preto); tocar no ✓ fecha. Vibração leve e rótulos "Editar {título}" / "Concluir {título}". Parâmetros: `title`, `value: String`, `editor`.

```swift
// BodyProfile.swift
GMLockedRow(title: "Altura", value: height > 0 ? "\(Int(height)) cm" : "") { GMDecimalField(title: "", value: ..., step: 1, unit: "cm", start: 170) }
// ProfileView.swift (metas)
GMLockedRow(title: "Peso alvo", value: weightGoal > 0 ? "\(Progression.fmt(weightGoal)) kg" : "") { ... }
```
Não usar: para valores que mudam a cada uso, como carga e reps no treino (use `GMCompactStepper`); separe as linhas com `GMDivider`.

#### `GMRuler`
Régua horizontal que encaixa no passo e vibra a cada um; acompanha mudanças externas do valor. Parâmetros: `value`, `range` (0…300), `step` (2,5), `majorEvery` (4).

```swift
// BodyTrackerView.swift (calculadora de anilhas)
GMRuler(value: $total, range: 0...300, step: 2.5)
```

#### `GMEffortPicker`
Esforço 1–10 em barras crescentes, toque ou arraste, cor de verde a vermelho e rótulo de `effortLabel` (Leve, Moderado, Intenso, Máximo).

```swift
// Route.swift
GMSection { GMEffortPicker(value: $effort) }
```

### Campos de texto

#### `GMTextField`
Campo em `Theme.raised`, raio 12, placeholder em `Theme.dim`. Parâmetros: `placeholder`, `text`, `axis` (`.vertical` = 2 a 6 linhas), `keyboard`, `capitalization`.

```swift
// CheckInDetail.swift
GMTextField(placeholder: "Descrição (opcional)", text: $note, axis: .vertical)
```

#### `GMSearchField`
Cápsula `Theme.card` com lupa e botão de limpar.

```swift
// RoutineEditView.swift
GMSearchField(placeholder: "Buscar exercício", text: $search)
```

### Data e hora

| Componente | Função |
|---|---|
| `GMDateTimePicker` | `GMDateField` + `GMDivider` + `GMTimeField`; `limitToNow` (padrão `true`) bloqueia o futuro |
| `GMDateField` | Linha "Dia · Hoje" que abre `GMCalendar` num `gmSheet` |
| `GMTimeField` | Linha "Horário · 14:30" que abre `GMTimeWheel` num `gmSheet` |
| `GMCalendar` | Mês em pt-BR começando no domingo (grade de `GMMonth`); `maxDate`, `minDate`; "Ir para hoje"; setas "Mês anterior"/"Próximo mês" |
| `GMMonth` | Grade do mês compartilhada por `GMCalendar` e `ActivityCalendar`: `calendar` (gregoriano, pt-BR, domingo primeiro), `cells(month)` (com `nil` antes do dia 1), `start(of:)`, `title` ("Outubro de 2026") e `header` ("Dom Seg Ter…") |
| `GMTimeWheel` | Duas `GMWheel` (0–23 e 0–59) |
| `GMDurationWheel` | Minutos (0…`maxMinutes`) e segundos de 5 em 5 |
| `GMWheel` | Roleta vertical genérica de `Int`, com encaixe e vibração |
| `GMDateText` | Formatação: "Hoje", "Ontem", "Seg, 3 de março"; hora `HH:mm` |

```swift
// LeaguesView.swift
GMSection("Quando") { GMDateTimePicker(date: $date) }
// SettingsView.swift
GMTimeField(date: Binding(get: { ... }, set: { ... }))
// PeriodPicker.swift
GMCalendar(selection: $draftStart, minDate: minDate)
// WorkoutView.swift
GMDurationWheel(seconds: $restDraft)
```
Não usar: `GMCalendar`/`GMWheel` soltos na tela; eles vivem dentro de `gmSheet` com um `GMButton("Confirmar")`.

### Feedback e status

#### `GMBadge`
Cápsula pequena com tinta a 20 %. Parâmetros: `text`, `tint` (acento).

```swift
// LeaguesView.swift
if league.isMock { GMBadge(text: "exemplo", tint: .white) }
```

#### `GMProgressBar`
Barra em cápsula animada; `value` 0…1, `tint`, `height` (8).

```swift
// DexView.swift
GMProgressBar(value: a.progress, height: 6)
```

#### `GMEmptyState`
Ícone de 40 pt em `Theme.dim`, título e mensagem centralizados.

```swift
// LeagueMural.swift
GMEmptyState(icon: "bubble.left.and.bubble.right", title: "Mural vazio", message: "Mande o primeiro recado pra galera da liga.")
```

#### `GMOnlineDot`
Ponto `Theme.online` com névoa pulsante (1,8 s, infinito); `size` (8), `color`. Tem `accessibilityLabel("Online")`. É o único indicador de "online / treinando agora": lista de amigos, perfil do amigo, pino do mapa, "AO VIVO" do card e da lista de amigos ao vivo.

```swift
// FriendsLive.swift
if friend.isLive { GMOnlineDot(size: 6) }
```

### Overlays

| Modificador | Substitui | Conteúdo |
|---|---|---|
| `gmSheet(isPresented:) { close in … }` | `.sheet` | Livre, dentro de `GMSheetCard` (alça, raio 28, `Theme.card`) |
| `gmActions(isPresented:title:message:actions:)` | `Menu`, `confirmationDialog` | Lista de `GMAction` (`.secondary` ou `.danger`) + "Cancelar" `.ghost` |
| `gmPrompt(isPresented:title:message:placeholder:text:confirm:onConfirm:)` | `alert` com `TextField` | Diálogo central com `GMTextField` e dois botões |
| `gmKeyboardDone()` | barra do teclado | Botão "OK" em acento acima do teclado; instala o toque-fora-fecha-teclado |

Os três primeiros usam `GMOverlayHost` (`fullScreenCover` transparente). A ação de um `GMAction` roda **depois** que a camada fecha, então pode abrir outra tela em seguida.

```swift
// Monsters.swift
.gmPrompt(isPresented: $renaming, title: "Apelido", message: "Vazio usa o nome da forma atual.",
          placeholder: "Apelido", text: $newName) { ... }

// LogActivityView.swift
.gmActions(isPresented: $choosingPlace, title: "Onde foi?", actions:
    gyms.map { g in GMAction(g.name, icon: "dumbbell.fill") { place = g.name } }
    + [GMAction("Sem local", icon: "xmark") { place = nil }])
```
`gmKeyboardDone()` já vem em `GMScreen` e `GMModal`; só aplique à mão em telas montadas sem eles.

### Navegação

#### `GMTabBar` e `GMTabItem`
Cápsula `.ultraThinMaterial` com contorno `Theme.stroke`; abas com cápsula de acento deslizante; centro com o bro em círculo de 66 pt, anel em gradiente dos atributos, sombra e "pulo" ao tocar. `GMTabItem.badge` mostra contador em `Theme.badge`, lido no VoiceOver junto do título ("Mapa, 4"). O texto cresce com o Dynamic Type até `xxLarge`.

```swift
// App.swift
GMTabBar(left: [GMTabItem(icon: "dumbbell.fill", title: "Treino", tag: 1),
                GMTabItem(icon: "trophy.fill", title: "Ligas", tag: 2)],
         right: [GMTabItem(icon: "map.fill", title: "Mapa", tag: 3, badge: FriendsLive.liveCount),
                 GMTabItem(icon: "list.bullet", title: "Histórico", tag: 4)],
         centerTag: 0, selection: $tab) { MonsterSprite(form: s.form) }
```
Existe uma só, em `MainView`. As páginas ficam vivas depois da primeira visita (guardam rolagem e navegação).

## 4. Padrões de tela

### Montar uma tela
1. `NavigationStack` na raiz da aba, `GMScreen(título, avatar: true)` dentro.
2. Telas empurradas: `GMScreen(título, back: true) { botões } content: { … }`.
3. Conteúdo = sequência de `GMSection`/`GMCard`/`GMButton`; não adicione padding lateral (o `GMScreen` já dá 16).
4. Ações de cabeçalho no `trailing` com `GMIconButton` (`ellipsis` abre `gmActions`).

### Formulários modais
`GMModal("Nova atividade", confirm: "Salvar", onConfirm: save)` apresentado com `gmModal`. Corpo em `GMSection`s com rótulo e rodapé explicativo; `confirmEnabled` valida o mínimo (ex.: nome não vazio). Ao salvar com sucesso, `UINotificationFeedbackGenerator().notificationOccurred(.success)` e `dismiss()` (`GymBros/Activities/LogActivityView.swift`, `GymBros/Leagues/LeaguesView.swift`).

### Listas com divisores
Itens dentro de um `GMSection`, `GMDivider()` entre eles e nunca depois do último:

```swift
// HistoryView.swift
ForEach(group.items) { a in
    NavigationLink { ActivityDetailView(activity: a, snapshot: snapshot) } label: {
        ActivityRow(activity: a, xp: snapshot.xpByActivity[a.uuid] ?? 0).contentShape(Rectangle())
    }
    .buttonStyle(GMPress())
    if a.id != group.items.last?.id { GMDivider() }
}
```

### Estados vazios
`GMEmptyState` no lugar da lista, com ícone ligado ao assunto e uma mensagem que diz o próximo passo ("Crie uma liga e chame os amigos, ou entre com um código."). Em seções pequenas, basta um `Text` `.subheadline` em `Theme.dim` dentro do card (`GymBros/Friends/MapScreen.swift`).

### Ações destrutivas
1. Gatilho neutro: `GMButton(…, icon: "trash", kind: .secondary)` ou `GMRow(icon: "trash", iconTint: Theme.danger, …)`.
2. Confirmação com `gmActions`: título em pergunta, mensagem com a consequência, `GMAction("Apagar", icon: "trash", destructive: true)`.
3. Se a tela mostra o objeto apagado, `dismiss()` antes e apaga depois:

```swift
// ActivityDetail.swift
.gmActions(isPresented: $confirmDelete, title: "Apagar atividade?",
           message: "Os check-ins dela no perfil e nas ligas também somem.", actions: [
    GMAction("Apagar", icon: "trash", destructive: true) {
        let a = activity, ctx = context
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { deleteActivity(a, context: ctx) }
    }
])
```

### Botão flutuante "+"
Use `GMFloatingButton` (seção 3) em `.overlay(alignment: .bottomTrailing)`, com `padding(.trailing, 20)` e `padding(.bottom, 90)` quando houver barra de abas. Só para a ação de criação principal de uma tela longa (check-in na liga, registrar atividade no perfil).

### Feedback háptico

| Gerador | Quando | Ocorrências |
|---|---|---|
| `UISelectionFeedbackGenerator().selectionChanged()` | Trocar seleção (chips, aba, dia do calendário, roleta, régua, esforço, grade de atividades) | 15 |
| `UIImpactFeedbackGenerator(style: .light)` | Incremento (stepper, `GMCompactStepper`, switch), atualizar posição no mapa | 10+ |
| `UIImpactFeedbackGenerator(style: .medium)` | Ação física de treino (contar rodada no WOD, evolução) | 3 |
| `UINotificationFeedbackGenerator().notificationOccurred(.success)` | Salvou, check-in feito, amizade aceita, evoluiu | 11 |
| `.warning` | Alerta | 1 |

Componentes `GM` de seleção já vibram; não duplique a vibração no `action`.

## 5. Componentes de domínio

| Componente | Arquivo | Descrição |
|---|---|---|
| `MonsterSprite(form:hidden:)` | `GymBros/Bros/MonsterSprite.swift` | Pixel art sem suavização (`.interpolation(.none)`), `hueRotation` por forma; `hidden` vira silhueta preta a 60 % (Dex). Usado em listas (44 pt), amigos (42–56 pt) e no centro da barra de abas |
| `LivingMonster(form:progress:)` | `GymBros/Bros/MonsterSprite.swift` | Sprite animado: ovo treme com frequência e força crescentes conforme `progress`; demais formas têm animação ociosa por espécie (`MotionScript`: urso balança, rato pula, coruja flutua…). Usado na Home (200 pt) e no `PublicProfileCard` (60 pt) |
| `PersonAvatar(name:photo:size:)` | `GymBros/Friends/PublicProfile.swift` | Círculo com foto ou inicial em `.heavy .rounded` preta sobre acento; contorno `Theme.stroke` |
| `Avatar(size:)` | `GymBros/Profile/ProfileView.swift` | `PersonAvatar` do próprio usuário (lê `@AppStorage`) |
| `ProfileAvatarButton` | `GymBros/Profile/ProfileView.swift` | `Avatar(40)` que abre o perfil em `gmModal`; aparece via `GMScreen(avatar: true)` |
| `PublicProfileCard` | `GymBros/Friends/PublicProfile.swift` | Cabeçalho (avatar 52), bro, números (Check-ins, Dias ativos, Ligas) e até 6 conquistas, separados por `GMDivider` |
| `ActivityCalendar(marks:onDay:)` | `GymBros/Profile/ProfileCalendar.swift` | Mês (grade de `GMMonth`) com foto do dia (até duas sobrepostas) ou círculo de acento com o símbolo da atividade e contador; usado também no perfil privado |
| `PostsCalendar` | `GymBros/Profile/ProfileCalendar.swift` | `ActivityCalendar` + `gmSheet` com os posts do dia |
| `LeagueRow` (privado) | `GymBros/Leagues/LeaguesView.swift` | Card de liga: emoji `.largeTitle`, nome, `GMBadge` "exemplo", posição e dias restantes, sprite do representante e chevron, dentro de `GMCard` |
| `ActivityRow` | `GymBros/Bros/HomeView.swift` | Ícone da atividade 40×40 em `Theme.raised`, tipo, duração · esforço · data, destinos em acento, `heart.fill` em `Theme.health` se veio do Saúde (rótulo "Do app Saúde"), "+XP" em acento |
| `ActivityKindGrid` | `GymBros/Activities/LogActivityView.swift` | Grade 4 colunas dos 12 tipos; selecionado com fundo de acento 20 % e contorno de acento |
| `SpeechBubble` | `GymBros/Bros/HomeView.swift` | Balão do bro com emoji de humor e pontinha apontando para baixo |
| `LiveFriendCard` / `LiveFriendRow` / `FriendPin` | `GymBros/Friends/FriendsLive.swift` | Amigo treinando agora: sprite com anel na cor do atributo da atividade, `GMOnlineDot` e "AO VIVO"; pino com teto de Dynamic Type `xLarge` |
| `ExercisePhotos` / `CreditLine` / `WgerVideoView` / `CreditsView` | `GymBros/Exercises/Wger.swift` | Imagens do wger sobre fundo branco alternando com o crédito embaixo; linha "Imagem: autor · licença · wger.de" em `.caption2`/`Theme.dim`; vídeo no app; tela "Créditos e licenças" |
| `ExerciseThumb` | `GymBros/Train/RoutineEditView.swift` | Miniatura do exercício: primeira imagem do wger em fundo branco, ou símbolo do grupo; raio `radiusS` |
| `GMOnlineDot` | `GymBros/DesignSystem/GMIndicators.swift` | Indicador online em listas de amigos (`GymBros/Friends/Friends.swift`) e no perfil do amigo (`GymBros/Friends/PublicProfile.swift`, 10 pt) |
| `StoryComposerView` | `GymBros/Activities/StoryShare.swift` | Tela cheia (tema escuro) entre "Compartilhar" e a folha do iPhone: `xmark`, título "Story", botão de foto, prévia 9:16 com raio `radiusL` e sombra, faixa horizontal de miniaturas das molduras (contorno de acento 3 pt na escolhida) e `GMButton` "Compartilhar" |
| `WorkoutStoryCard` | `GymBros/Activities/StoryShare.swift` | Arte 360 × 640 (renderizada em escala 3 = 1080 × 1920) em quatro molduras (`StoryFrame`): **Completo** (foto em tela cheia com marca, data em cápsula, título, sprite, até 4 números, trajeto e exercícios por cima), **Mínimo** (uma linha de números e sprite pequeno), **Polaroid** (foto com borda branca inclinada −3°, trajeto no canto) e **Bro** (sprite grande no centro, trajeto atrás a 55 %). Usa tamanhos fixos (`.system(size:)`) de propósito, porque a arte não acompanha o Dynamic Type |
| `RouteDrawing(coords:lineWidth:)` | `GymBros/Activities/StoryShare.swift` | Trajeto do GPS desenhado sem mapa: linha em `Theme.accent` com brilho (2,6× a espessura, desfocado), ponto branco no início e de acento no fim, longitude corrigida pela latitude |
| `LoginView` | `GymBros/Services/Auth.swift` | Tela de entrada: `LivingMonster` bebê, "GymBros" em acento 34 pt, `GMSegmented` Entrar/Criar conta, `GMTextField`s, erro em `Theme.danger`, `GMButton` e botão "Continuar com a Apple" no visual oficial (fundo branco, texto preto, raio `radiusM`) |

## 6. Regras de consistência

1. Cores só de `Theme` ou `Attribute.color`. Nada de `Color(red:…)` nem de `.orange`/`.yellow`/`.cyan` com significado em tela; se precisar de uma cor nova, crie o token em `Shared/Theme.swift` (assim o widget também enxerga).
2. Texto sobre `Theme.accent` é sempre `.black`; sobre fundo escuro, `.white` ou `Theme.dim`.
3. Superfícies em três níveis: `Theme.bg` → `Theme.card` → `Theme.raised`. Não pule nem repita nível.
4. Cards com `GMCard`/`GMSection` (raio 20, padding 16 ou o `padding:` do card). Não recrie card com `background(Theme.card, in: .rect(cornerRadius: …))`; raios só da escala `Theme.radius*`.
5. Uma ação primária (acento) por tela; o resto `.secondary` ou `.ghost`.
6. Tudo tocável usa `GMPress`.
7. Números com `.monospacedDigit()`. Tamanho de fonte próprio só com `gmFont`.
8. Nenhum controle nativo listado na seção 1; nada de `.sheet`, `.alert`, `.confirmationDialog`.
9. Datas pelo `GMDateText` e locale `pt_BR`.
10. Seleção vibra (`selectionChanged`), sucesso vibra (`.success`).
11. Botão só com ícone tem rótulo do VoiceOver (`GMIconButton(label:)`, `accessibilityLabel`).

### Checklist para uma nova tela

- [ ] Raiz é `GMScreen` (empurrada) ou `GMModal` (apresentada com `gmModal`)?
- [ ] Conteúdo agrupado em `GMSection` com rótulo curto e rodapé quando a regra não é óbvia?
- [ ] Listas com `GMDivider` entre itens, sem divisor no fim?
- [ ] Estado vazio com `GMEmptyState` e próximo passo?
- [ ] Apagar passa por `gmActions` com `destructive: true` e mensagem de consequência?
- [ ] Escolhas com `GMSegmented`/`GMChoiceChips`/`gmActions`, nunca `Picker`/`Menu`?
- [ ] Datas e horas com `GMDateTimePicker`/`GMDateField`/`GMTimeField`?
- [ ] Nenhuma cor fora de `Theme`/`Attribute`, nenhum raio fora da escala `Theme.radius*`?
- [ ] Texto de tamanho próprio com `gmFont`; botões só com ícone com rótulo?
- [ ] Texto sobre acento em preto; números monoespaçados?
- [ ] Conteúdo não fica sob a barra de abas (`bottomInset` do `GMScreen` ou `padding(.bottom, 90+)`)?
- [ ] Háptico de sucesso ao salvar?
- [ ] Textos em português, com acentuação e tom informal?

## 7. Inconsistências encontradas

Resolvidas desde a primeira versão: cores do tema duplicadas no widget (agora `Shared/Theme.swift`), cor fixa do botão de vídeo (`Theme.video`), cores do sistema com significado (tokens semânticos), ponto vermelho de "ao vivo" (agora `GMOnlineDot`), raios dispersos (escala `radiusXS`–`radiusXL`), cards à mão na Home e na corrida (`GMCard`), botão flutuante duplicado (`GMFloatingButton`), steppers paralelos (`GMCompactStepper`), `Theme.raised` e trilho com valores literais, `GMTextButton` sem uso, `GMModal(cancel:)` sem efeito, perfil fora do `GMScreen`, cena de evolução com `.fullScreenCover` direto e os dois calendários com cálculos diferentes (`GMMonth`). Continua:

| Ponto | Onde | Observação |
|---|---|---|
| Cores do sistema fora de token | `GMEffortPicker`, `MapScreen` (`color(kind)`), `MuscleViews` (mapa de calor) | Escala de esforço e cores de percurso ainda usam `.yellow`, `.orange`, `.red`, `.cyan` direto (as anilhas são cores de domínio) |
| Terceiro calendário | `GymBros/DesignSystem/PeriodPicker.swift` (`GMRangeCalendar`) | Calcula a grade por conta própria e usa "D S T Q Q S S", em vez de `GMMonth` ("Dom Seg Ter…") |
| Cards montados à mão | `DexView` (conquistas e seletor de espécie), `WorkoutView` (card do exercício, barra de descanso), `LeaguesView` (resumo, linhas), `MapScreen` (raio `radiusL`) | Já usam `Theme.card` e tokens de raio, mas não `GMCard` (precisam de contorno ou padding variável) |
| Telas com `ScrollView` à mão | `GymBros/Friends/PublicProfile.swift` (`FriendProfileView`), `GymBros/Leagues/CheckInDetail.swift`, `GymBros/Train/WorkoutView.swift` | Fogem do `GMScreen`; as duas últimas têm layout de tela cheia próprio |
| Trilhos com literal | `GMSwitch` (`.white.opacity(0.15)`), `XPBar` do widget (`.white.opacity(0.12)`) | Próximos de `Theme.track` (0,1), mas diferentes |
| Tamanhos fixos | ícones e emojis (`GMEmptyState`, roleta, reações, troféu), `PetWidget` | 30 usos de `.font(.system(size:))`, fora do `gmFont` (a arte do story fica de fora: é imagem, não tela) |
| Telas cheias fora de `GMScreen`/`GMModal` | `LoginView` (`GymBros/Services/Auth.swift`), `StoryComposerView` (`GymBros/Activities/StoryShare.swift`) | O login monta o próprio `ScrollView` e recria o fundo do campo de senha (`SecureField` com `Theme.card`, porque `GMTextField` não tem modo seguro); o story abre por `UIHostingController` em tela cheia, com cabeçalho próprio |
