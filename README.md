# GymMonsters

App de iPhone (SwiftUI + SwiftData, iOS 17) em que seus treinos chocam e evoluem um monstrinho.

- Ao começar você ganha um **ovo**, que choca com 60 XP de atividade.
- Cada atividade (musculação, corrida, crossfit, vôlei…) rende XP por **duração × MET da atividade × esforço (1–10)** e soma em quatro atributos: **Força, Resistência, Agilidade e Técnica**.
- Estágios: Ovo → Bebê (60 XP) → Rookie (300) → Champion (1200) → Ultimate (3600).
  Em Champion e Ultimate, o atributo mais treinado desde a última evolução decide o galho.
- Anti-farm: no máximo 240 min por atividade; acima de 150 XP no dia o ganho cai para 1/3, com teto de 300 XP/dia.
- Tudo é derivado do histórico (`GymMonsters/Game.swift`): apagar ou editar uma atividade recalcula a evolução.
- Os dados ficam só no aparelho, sem conta e sem servidor.

As artes dos galhos de Resistência, Agilidade e Técnica são provisórias (as de Força com outra cor).

## Rodar no iPhone

```sh
xcodebuild -project GymMonsters.xcodeproj -scheme GymMonsters \
  -destination 'id=<UDID>' -derivedDataPath build -allowProvisioningUpdates build
xcrun devicectl device install app --device <UDID> build/Build/Products/Debug-iphoneos/GymMonsters.app
```

A versão web anterior (Next.js + Express) continua no branch `main`.
