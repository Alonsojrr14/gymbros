# Árvore de evolução

```mermaid
flowchart LR
    O[🥚 Ovo<br/>0 XP] -->|60 XP| G[Gymmon<br/>Bebê]
    G -->|300 XP| C[Cutemon<br/>Rookie]
    C -->|1200 XP · Força| HF[Halteromon]
    C -->|1200 XP · Resistência| MR[Maratomon]
    C -->|1200 XP · Agilidade| SA[Saltamon]
    C -->|1200 XP · Técnica| ZE[Zenmon]
    HF & MR & SA & ZE -->|3600 XP · Força| TR[Trebomon]
    HF & MR & SA & ZE -->|3600 XP · Resistência| FO[Fôlegomon]
    HF & MR & SA & ZE -->|3600 XP · Agilidade| RE[Relampamon]
    HF & MR & SA & ZE -->|3600 XP · Técnica| ME[Mestremon]
```

## Estágios

| Estágio | XP total | Forma |
|---|---|---|
| Ovo | 0 | <img src="GymMonsters/Assets.xcassets/sprite_egg.imageset/egg.png" width="80"> |
| Bebê | 60 | <img src="GymMonsters/Assets.xcassets/sprite_baby.imageset/baby.png" width="80"><br>Gymmon |
| Rookie | 300 | <img src="GymMonsters/Assets.xcassets/sprite_rookie.imageset/rookie.png" width="80"><br>Cutemon |

## Galhos (Champion → Ultimate)

| Atributo | Champion · 1200 XP | Ultimate · 3600 XP |
|---|---|---|
| 💪 Força | <img src="GymMonsters/Assets.xcassets/sprite_champion_forca.imageset/champion_forca.png" width="90"><br>Halteromon | <img src="GymMonsters/Assets.xcassets/sprite_ultimate_forca.imageset/ultimate_forca.png" width="90"><br>Trebomon |
| ❤️ Resistência | <img src="GymMonsters/Assets.xcassets/sprite_champion_resistencia.imageset/champion_resistencia.png" width="90"><br>Maratomon | <img src="GymMonsters/Assets.xcassets/sprite_ultimate_resistencia.imageset/ultimate_resistencia.png" width="90"><br>Fôlegomon |
| ⚡ Agilidade | <img src="GymMonsters/Assets.xcassets/sprite_champion_agilidade.imageset/champion_agilidade.png" width="90"><br>Saltamon | <img src="GymMonsters/Assets.xcassets/sprite_ultimate_agilidade.imageset/ultimate_agilidade.png" width="90"><br>Relampamon |
| ✨ Técnica | <img src="GymMonsters/Assets.xcassets/sprite_champion_tecnica.imageset/champion_tecnica.png" width="90"><br>Zenmon | <img src="GymMonsters/Assets.xcassets/sprite_ultimate_tecnica.imageset/ultimate_tecnica.png" width="90"><br>Mestremon |

## Como o galho é escolhido

- Ao chegar em **Champion** (1200 XP), vence o atributo que você mais treinou **desde que virou Rookie**.
- Ao chegar em **Ultimate** (3600 XP), vence o atributo mais treinado **durante a fase Champion**. Dá para trocar de linha: um Halteromon que passou a fase correndo vira Fôlegomon.
- Empate fica com a ordem Força → Resistência → Agilidade → Técnica.

## Atividade → atributos

| Atividade | Força | Resistência | Agilidade | Técnica |
|---|---|---|---|---|
| Musculação | 80% | | | 20% |
| Crossfit | 40% | 40% | 20% | |
| Corrida | | 80% | 20% | |
| Caminhada | | 100% | | |
| Bike | 20% | 80% | | |
| Natação | | 60% | | 40% |
| Vôlei | | | 60% | 40% |
| Futebol | | 50% | 50% | |
| Lutas | 30% | | 40% | 30% |
| Dança | | | 50% | 50% |
| Yoga | | | | 100% |
| Outro | 25% | 25% | 25% | 25% |

XP de cada atividade = duração × gasto típico (MET) × esforço; acima de 150 XP no dia rende 1/3, com teto de 300 XP/dia. Treinando todo dia, o Champion chega em ~5 semanas e o Ultimate em ~3–4 meses.
