# Árvore de evolução dos bros

```mermaid
flowchart LR
    O[🥚 Ovo<br/>0 XP] -->|60 XP| G[Gymbro<br/>Bebê]
    G -->|300 XP| C[Cutebro<br/>Rookie]
    C -->|1200 XP · Força| HF[Halterobro]
    C -->|1200 XP · Resistência| MR[Maratobro]
    C -->|1200 XP · Agilidade| SA[Saltabro]
    C -->|1200 XP · Técnica| ZE[Zenbro]
    HF & MR & SA & ZE -->|3600 XP · Força| TR[Trebobro]
    HF & MR & SA & ZE -->|3600 XP · Resistência| FO[Fôlegobro]
    HF & MR & SA & ZE -->|3600 XP · Agilidade| RE[Relampabro]
    HF & MR & SA & ZE -->|3600 XP · Técnica| ME[Mestrebro]
```

## Estágios

| Estágio | XP total | Forma |
|---|---|---|
| Ovo | 0 | <img src="GymMonsters/Assets.xcassets/sprite_egg.imageset/egg.png" width="80"> |
| Bebê | 60 | <img src="GymMonsters/Assets.xcassets/sprite_baby.imageset/baby.png" width="80"><br>Gymbro |
| Rookie | 300 | <img src="GymMonsters/Assets.xcassets/sprite_rookie.imageset/rookie.png" width="80"><br>Cutebro |

## Galhos (Champion → Ultimate)

| Atributo | Champion · 1200 XP | Ultimate · 3600 XP |
|---|---|---|
| 💪 Força | <img src="GymMonsters/Assets.xcassets/sprite_champion_forca.imageset/champion_forca.png" width="90"><br>Halterobro | <img src="GymMonsters/Assets.xcassets/sprite_ultimate_forca.imageset/ultimate_forca.png" width="90"><br>Trebobro |
| ❤️ Resistência | <img src="GymMonsters/Assets.xcassets/sprite_champion_resistencia.imageset/champion_resistencia.png" width="90"><br>Maratobro | <img src="GymMonsters/Assets.xcassets/sprite_ultimate_resistencia.imageset/ultimate_resistencia.png" width="90"><br>Fôlegobro |
| ⚡ Agilidade | <img src="GymMonsters/Assets.xcassets/sprite_champion_agilidade.imageset/champion_agilidade.png" width="90"><br>Saltabro | <img src="GymMonsters/Assets.xcassets/sprite_ultimate_agilidade.imageset/ultimate_agilidade.png" width="90"><br>Relampabro |
| ✨ Técnica | <img src="GymMonsters/Assets.xcassets/sprite_champion_tecnica.imageset/champion_tecnica.png" width="90"><br>Zenbro | <img src="GymMonsters/Assets.xcassets/sprite_ultimate_tecnica.imageset/ultimate_tecnica.png" width="90"><br>Mestrebro |

## Como o galho é escolhido

- Ao chegar em **Champion** (1200 XP), vence o atributo que você mais treinou **desde que virou Rookie**.
- Ao chegar em **Ultimate** (3600 XP), vence o atributo mais treinado **durante a fase Champion**. Dá para trocar de linha: um Halterobro que passou a fase correndo vira Fôlegobro.
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

## Espécies

A espécie é decidida quando o ovo choca, pelos treinos que o chocaram: se o atributo dominante bate com a afinidade de alguma espécie, nasce ela; senão, nasce o Coelho (espécie padrão). Depois de nascer, a espécie fica gravada no bro. Liga nenhuma restringe espécie.

Para incluir uma espécie (`Species.catalog` em `GymMonsters/Game.swift`): id, nome, afinidade, nomes das 10 formas e as artes `sprite_<id>_<forma>` (baby, rookie, champion_forca… ultimate_tecnica) no app e no widget.

| Espécie | Afinidade | Bebê → Rookie | Champions (Força / Resistência / Agilidade / Técnica) | Ultimates |
|---|---|---|---|---|
| Coelho | padrão | Gymbro → Cutebro | Halterobro / Maratobro / Saltabro / Zenbro | Trebobro / Fôlegobro / Relampabro / Mestrebro |
| Urso | Força | Pelucibro → Ursabro | Supinobro / Trilhabro / Rolabro / Sumobro | Grizzlibro / Montanhabro / Avalanchebro / Kodiabro |
| Rato | Força | Queijibro → Ratibro | Marombabro / Rodibro / Fuxibro / Labiribro | Ratazanabro / Esteirabro / Sombrabro / Engenhobro |
| Lobo | Resistência | Uivibro → Lobinbro | Alfabro / Trotebro / Caçabro / Matilhabro | Fenribro / Luabro / Ventobro / Ancestrabro |
| Cachorro | Resistência | Filhotibro → Caramelbro | Pitbulbro / Galgobro / Frisbeebro / Pastorbro | Mastibro / Huskybro / Agilitybro / Guiabro |
| Esquilo | Agilidade | Nozibro → Esquilbro | Quebranozbro / Galhobro / Pulabro / Acrobabro | Carvalhobro / Florestabro / Voadorbro / Parkourbro |
| Gato | Agilidade | Novelbro → Bichanobro | Garrabro / Rondabro / Telhadobro / Ronrobro | Jubabro / Panterabro / Linxbro / Esfingebro |
| Coruja | Técnica | Penugbro → Corujabro | Rapinabro / Noturnbro / Planabro / Sabiobro | Harpiabro / Luarbro / Rasantebro / Oraculobro |

Só nascem espécies com as 10 artes no app; as demais ficam cadastradas esperando a arte. Prontas: todas as 8.
