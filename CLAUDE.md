# GymBros

App pessoal nativo para iPhone (SwiftUI + SwiftData, iOS 17) com Apple Watch, widgets, Live Activities e servidor no Firebase (plano Spark). Treinos chocam e evoluem um "bro"; há ligas, X1, amigos, feed, caixa de entrada, treino guiado e WOD. Conta obrigatória. Em andamento: preparar o repositório para um app Android nativo (Kotlin) com as mesmas regras.

Responda e documente em português do Brasil, com acentuação correta. Identificadores de código ficam no original.

## Mapa
- `GymBros/` app iOS (pasta sincronizada do Xcode: arquivo novo entra no alvo sem mexer no `project.pbxproj`). `Shared/` código comum com widget e relógio.
- `GymBrosWidget/`, `GymBrosWatch/`, `GymBrosWatchWidget/`, `GymBrosTests/` (XCTest, `TEST_HOST` = app).
- `firebase/` regras e índices do Firestore: **única autoridade do servidor** (não há Cloud Functions). XP, evolução, pareamento suíço e pontuação das ligas são calculados no cliente.
- `docs/` é o **site público do GitHub Pages** (publicado da branch `swift`). Nada de engenharia interna nem achado de segurança aqui.
- `engenharia/` documentos de engenharia (descoberta, arquitetura, requisitos, paridade, plano, segurança). Comece por `engenharia/README.md`.
- `tools/` geradores de recursos (`tools/wger/build.py` → `GymBros/Resources/wger.json`, recorte de sprites). Não execute sem pedido.
- `graphify-out/` grafo do código (pode estar defasado; mapa de navegação, nunca prova).

## Build e teste (só no iPhone físico)
```sh
UDID=00008150-001E15363C04C01C
xcrun devicectl list devices            # confirmar que o iPhone está conectado
xcodebuild -project GymBros.xcodeproj -scheme GymBros -destination "id=$UDID" \
  -derivedDataPath build -allowProvisioningUpdates build
xcrun devicectl device install app --device $UDID build/Build/Products/Debug-iphoneos/GymBros.app
xcodebuild test -project GymBros.xcodeproj -scheme GymBros -destination "id=$UDID" \
  -derivedDataPath build -allowProvisioningUpdates
```
Assinatura sempre com o Personal Team `5UV7WAAAL2`. Os testes rodam no aparelho do dono, com os dados reais: avise antes de rodar. Mudança aprovada no iOS só está entregue depois de "App installed".

## Regras invioláveis
- Preserve o trabalho não commitado do dono. Sem commit, push, troca de branch, `reset`, `clean`, `stash` ou `checkout` de arquivos sem pedido explícito.
- Não mova, apague ou renomeie arquivos do app, nem edite Swift, `project.pbxproj`, entitlements ou `Info.plist`, sem aprovação da fase correspondente.
- Firebase: nenhuma ação no projeto real (nem leitura), nenhum deploy de regras, nenhum registro de app sem aprovação. `GoogleService-Info.plist` e o futuro `google-services.json` ficam fora do git; nunca imprima seus valores.
- Não instale JDK, Gradle, SDKs nem dependências; não apague nada sem pedido (em 22/10 o dono autorizou limpar o que é regenerável; ficaram ~18 GB livres).
- `AppRuntime.isTesting` deixa o app inerte sob XCTest: não remova. Teste nenhum grava no banco real (`AppData.container`); use `scratchDefaults(_:)` do `GymTestCase`.
- Dados do Apple Saúde nunca vão para a nuvem (`cloudKitDatabase: .none` é proposital). Fotos ficam só no aparelho (`NoPhotoStore`): não proponha fotos na nuvem.
- Conta obrigatória nos dois apps. UI nova funciona e fica bonita com 1, 5 e 50 itens.
- Identidade visual: fundo `#0D0F14`, cards `#1A1C24`, verde `#A3E636`, fonte do sistema (SF) com `gmFont` e Dynamic Type; Jersey 10 é só do site em `docs/` (`Shared/Theme.swift`, `docs/design-system.md`, componentes `GM*` em `GymBros/DesignSystem/`). Não invente paleta.
- Relógio: telas de conteúdo fixas, sem rolagem; só listas de escolha rolam pela coroa.
- Documento contra código: o código vence; a divergência é registrada como CONFLICTING.

## Fluxo multiagente (iOS → Android)
A sessão principal é o orquestrador (subagente não cria subagente). Uma skill por fase, cada uma com portão:
`/mobile-discovery` (fases A–E) → `/repository-reorganization` (F) → `/android-foundation` (G) → `/android-feature` (H) → `/parity-audit` (I).
Especialistas em `.claude/agents/`. Estado atual, portões e pendências: `engenharia/README.md`.
