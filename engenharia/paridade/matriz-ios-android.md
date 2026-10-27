# Matriz de paridade iOS × Android

**Escopo.** Uma linha por jornada ou tela, com o status de paridade de cada uma. Status permitidos: `IMPLEMENTED_AND_VERIFIED`, `IMPLEMENTED_BUT_UNVERIFIED`, `PARTIALLY_IMPLEMENTED`, `NOT_IMPLEMENTED`, `INTENTIONALLY_PLATFORM_SPECIFIC`, `BLOCKED`. A paridade de negócio fica separada da paridade visual.
**Base de evidência.** Inventário do `ui-parity-analyst` (Sonnet 5.5) e matriz de requisitos. O Android ainda não existe.
**Status.** Rodada 1. Hoje todos os itens estão `NOT_IMPLEMENTED`. A coluna "v1?" é uma proposta que depende das decisões do dono (`../plano/riscos-e-perguntas.md`).

## 1. Telas e jornadas

| Jornada / tela | iOS (arquivo) | Android proposto | Marca ou plataforma | Requisitos | v1? | Negócio | Visual |
|---|---|---|---|---|---|---|---|
| Login, cadastro e conta obrigatória | `Services/Auth.swift`, `App.swift` RootView | `LoginScreen` | marca, com campos do sistema | RF-SOC (conta), RNF | sim | NOT_IMPLEMENTED | NOT_IMPLEMENTED |
| Restauração da cópia da conta | `AccountSync.swift` | `AccountLoadingScreen` | marca | contrato §4 | sim | NOT_IMPLEMENTED | — |
| Tutorial (10 passos, spotlight) | `Onboarding/*` | overlay Compose com recorte | marca; mecânica adaptada | RF-JOG-41 | sim | NOT_IMPLEMENTED | NOT_IMPLEMENTED |
| Barra de abas (Feed, Treino, [bro], Ligas, Mapa) | `DesignSystem/GMTabBar.swift`, `App.swift:172` | barra própria com o bro no centro | marca | RF-JOG-21/47 | sim | — | NOT_IMPLEMENTED |
| Início / bro / humor / evolução | `Bros/HomeView.swift`, `EvolutionView.swift`, `Hatch.swift` | `HomeScreen` + cenas animadas | marca | RF-JOG-05…22 | sim | NOT_IMPLEMENTED | NOT_IMPLEMENTED |
| Registrar atividade (grade de 80 tipos) | `Activities/LogActivityView.swift`, `WorkoutTypes.swift` | `LogActivityScreen` | marca | RF-JOG-01…04 | sim | NOT_IMPLEMENTED | NOT_IMPLEMENTED |
| Histórico, detalhe, editar e apagar | `Activities/*` | telas equivalentes | marca | RF-JOG-27…30, 44 | sim | NOT_IMPLEMENTED | NOT_IMPLEMENTED |
| Box, BroBook (897 formas), ficha | `Bros/Monsters.swift`, `DexView.swift`, `DexEntryView.swift` | grades Compose | marca | RF-JOG-16, 24…26, 42, 45 | sim | NOT_IMPLEMENTED | NOT_IMPLEMENTED |
| Treino guiado, rotinas, progressão, PR | `Train/WorkoutView.swift`, `Progression.swift`, `PR.swift` | `WorkoutScreen`; descanso em serviço em primeiro plano | marca; plataforma no timer | RF-TRE | proposta: sim | NOT_IMPLEMENTED | NOT_IMPLEMENTED |
| WOD (formatos, níveis, % do PR) | `Train/Wod*.swift` | telas WOD | marca | RF-TRE | proposta: sim, **sem** importação por foto | NOT_IMPLEMENTED | NOT_IMPLEMENTED |
| Importar treino por foto (Vision + FoundationModels) | `Train/WodImport.swift` | — | plataforma | RF-TRE | fora da v1 | INTENTIONALLY_PLATFORM_SPECIFIC (proposto) | — |
| Ligas: lista, detalhe, check-in, mural, revisão, moderação, campeões, times | `Leagues/*` | `LeaguesScreen` e subtelas | marca | RF-SOC ligas, 57, 61 | sim | NOT_IMPLEMENTED | NOT_IMPLEMENTED |
| Rodada suíça | `Leagues/Swiss.swift`, `SwissRoundSection.swift` | seção nas ligas | marca | RF-SOC-37 | sim | NOT_IMPLEMENTED | NOT_IMPLEMENTED |
| Feed dos amigos e comentários (até 150 posts e comentários dos 60 primeiros) | `Friends/FriendsFeed.swift`, `SocialExtras.swift`, `CommentSync.swift` | `FeedScreen` | marca | RF-SOC | sim | NOT_IMPLEMENTED | NOT_IMPLEMENTED |
| Amigos, código e QR, deep link | `Friends/Friends.swift`, `App.swift:291` | tela de amigos + App Link **com confirmação** | marca; plataforma no link | RF-SOC; SEC-AND-01 | sim | NOT_IMPLEMENTED | NOT_IMPLEMENTED |
| Mapa e treino ao vivo | `Friends/MapScreen.swift`, `FriendsLive.swift`, `LiveShare.swift` | Maps SDK ou MapLibre | plataforma | RF-SOC | proposta: só leitura dos amigos na v1 | NOT_IMPLEMENTED | NOT_IMPLEMENTED |
| X1 (só entre amigos, um por bro, até 20 no histórico) | `Duels/*` | `DuelScreens` | marca | RF-SOC-38/58 | sim | NOT_IMPLEMENTED | NOT_IMPLEMENTED |
| Trocas (48 h, até 20 concluídas) | `Trades/*` | `TradeScreens` | marca | RF-JOG-46 | sim | NOT_IMPLEMENTED | NOT_IMPLEMENTED |
| Caixa de entrada e DMs | `Inbox/*` | `InboxScreen` | marca | RF-SOC | sim | NOT_IMPLEMENTED | NOT_IMPLEMENTED |
| Perfil público e privado, constância, metas, medidas | `Profile/*`, `Friends/PublicProfile.swift` | `ProfileScreens` | marca | RF-SOC-59/60 | sim | NOT_IMPLEMENTED | NOT_IMPLEMENTED |
| Rotinas públicas (curtir, copiar) | `Train/PublicRoutines.swift` | tela | marca | RF-SOC | sim | NOT_IMPLEMENTED | NOT_IMPLEMENTED |
| Moderação e denúncias; admin (RBAC) | `Moderation/*`, `Access/*` | telas | marca | RF-SOC; `docs/rbac.md` | denúncia e bloqueio sim; admin fora da v1 (proposto) | NOT_IMPLEMENTED | NOT_IMPLEMENTED |
| Ajustes, termos, privacidade, créditos e licenças, exclusão de conta | `App/Settings*.swift`, `TermsView.swift` | `SettingsScreen` | marca; plataforma nas permissões | RNF | sim (créditos obrigatórios por licença CC BY-SA) | NOT_IMPLEMENTED | NOT_IMPLEMENTED |
| Mapa muscular (15 músculos em heatmap) | `Exercises/MuscleViews.swift` (MuscleMap MIT) | desenho próprio em Canvas ou porte dos paths mantendo o aviso MIT | marca | RF-TRE | sim | NOT_IMPLEMENTED | NOT_IMPLEMENTED |
| Stories 1080×1920 | `Activities/StoryShare.swift` | gerar bitmap + Sharesheet | marca; plataforma no envio | RF-JOG-39 | proposta: v1.1 | NOT_IMPLEMENTED | NOT_IMPLEMENTED |
| Apple Saúde | `Services/HealthSync.swift` | Health Connect | plataforma | RNF privacidade | proposta: v1.1 | NOT_IMPLEMENTED | — |
| Widgets, Live Activities, Controls | `GymBrosWidget/*` | Glance e notificação contínua | plataforma | RF-JOG-19, 33 | proposta: v1.1 | NOT_IMPLEMENTED | — |
| Relógio | `GymBrosWatch*` | Wear OS | plataforma | — | fora da v1 | INTENTIONALLY_PLATFORM_SPECIFIC (proposto) | — |
| Atalhos, Siri, botão de ação | `App/Shortcuts.swift`, `Shared/WorkoutIntents.swift` | App Shortcuts | plataforma | — | fora da v1 | INTENTIONALLY_PLATFORM_SPECIFIC (proposto) | — |
| Música ("Ouvindo agora") | `Music/Music.swift` | MediaSession (NotificationListener) | plataforma | — | fora da v1 | INTENTIONALLY_PLATFORM_SPECIFIC (proposto) | — |
| Pro / StoreKit | `App/ProAndComingSoon.swift` | Play Billing | plataforma | — | a confirmar se o Pro é real | UNKNOWN | — |

## 2. Regras de negócio (paridade só é provada por vetor compartilhado)

| Regra | Vetor | Status Android |
|---|---|---|
| `Game.xp`, teto diário, snapshot, galhos, viradas, espécie | grupos A e B | NOT_IMPLEMENTED |
| Roster: 1,0× principal, 0,8× representante, atividades aposentadas | B | NOT_IMPLEMENTED |
| `League.score` em todos os modos, `PhotoRule`, `pointRules` | A | NOT_IMPLEMENTED |
| Feed da liga, dias ativos, tetos, ranking e desempate | B | NOT_IMPLEMENTED |
| `SeededRandom`, `Swiss.pair`, `Swiss.table`, bônus | A e B | NOT_IMPLEMENTED |
| Campeões, constância, metas | D (propriedade) | NOT_IMPLEMENTED |
| X1 (valor, janela, fases) | B | NOT_IMPLEMENTED |
| Progressão de carga, WOD | A | NOT_IMPLEMENTED |
| Cópia da conta (JSON, DEFLATE cru, pedaços, bplist) | C | NOT_IMPLEMENTED |

## 3. Checklist de paridade visual
- Tokens exatos de `Shared/Theme.swift` (usar as frações RGB, não os hex arredondados); app sempre escuro; texto preto sobre o verde.
- Fonte: SF no iOS e a fonte do sistema no Android (Roboto). É uma diferença de plataforma aceita, a não ser que o dono escolha embutir uma fonte livre.
- Pixel art sem suavização (`FilterQuality.None`).
- 1, 5 e 50 itens em toda lista; estados vazios com `GMEmptyState`; truncamentos de negócio iguais aos do iOS (feed 150, comentários dos 60 primeiros, X1 20, trocas 20, vencedores 6).
- Escala de fonte em `sp`, com teto na barra de abas (xxLarge) e no ao vivo (xLarge), como no iOS.
- TalkBack: os cerca de 77 rótulos do iOS com o mesmo texto; ícones sem texto com `contentDescription`.
- Cores do sistema usadas no iOS sem hex fixo (laranja da sequência, ciano, amarelo, rosa, vermelho): o hex delas precisa ser fixado por decisão de design (UNKNOWN).
