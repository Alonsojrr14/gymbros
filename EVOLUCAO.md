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
    C -.->|1200 XP · dois atributos quase empatados| HC[Champion híbrido<br/>Crossbro · Golpebro · Arrancobro<br/>Chuteirabro · Nadobro · Gingabro]
    HF & MR & SA & ZE & HC -.->|3600 XP · dois atributos quase empatados| HU[Ultimate híbrido<br/>Hércubro · Titãbro · Olimpibro<br/>Tufãobro · Marébro · Piruetabro]
    HC -->|3600 XP · um atributo| TR & FO & RE & ME
```

Linha cheia: forma normal (o atributo mais treinado). Pontilhada: forma híbrida (o segundo atributo tem pelo menos 90% do primeiro).

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

## Formas híbridas

Quando os **dois atributos mais treinados** da fase ficam quase empatados (o segundo com pelo menos 90% do primeiro), o bro vira a forma híbrida da dupla: mistura as duas roupas e o corpo dos dois treinos. No Ultimate híbrido, uma aura com as duas cores envolve o bro.

| Dupla | Champion · 1200 XP | Ultimate · 3600 XP |
|---|---|---|
| 💪 Força + ❤️ Resistência | <img src="GymMonsters/Assets.xcassets/sprite_champion_forca_resistencia.imageset/champion_forca_resistencia.png" width="90"><br>Crossbro | <img src="GymMonsters/Assets.xcassets/sprite_ultimate_forca_resistencia.imageset/ultimate_forca_resistencia.png" width="90"><br>Hércubro |
| 💪 Força + ⚡ Agilidade | <img src="GymMonsters/Assets.xcassets/sprite_champion_forca_agilidade.imageset/champion_forca_agilidade.png" width="90"><br>Golpebro | <img src="GymMonsters/Assets.xcassets/sprite_ultimate_forca_agilidade.imageset/ultimate_forca_agilidade.png" width="90"><br>Titãbro |
| 💪 Força + ✨ Técnica | <img src="GymMonsters/Assets.xcassets/sprite_champion_forca_tecnica.imageset/champion_forca_tecnica.png" width="90"><br>Arrancobro | <img src="GymMonsters/Assets.xcassets/sprite_ultimate_forca_tecnica.imageset/ultimate_forca_tecnica.png" width="90"><br>Olimpibro |
| ❤️ Resistência + ⚡ Agilidade | <img src="GymMonsters/Assets.xcassets/sprite_champion_resistencia_agilidade.imageset/champion_resistencia_agilidade.png" width="90"><br>Chuteirabro | <img src="GymMonsters/Assets.xcassets/sprite_ultimate_resistencia_agilidade.imageset/ultimate_resistencia_agilidade.png" width="90"><br>Tufãobro |
| ❤️ Resistência + ✨ Técnica | <img src="GymMonsters/Assets.xcassets/sprite_champion_resistencia_tecnica.imageset/champion_resistencia_tecnica.png" width="90"><br>Nadobro | <img src="GymMonsters/Assets.xcassets/sprite_ultimate_resistencia_tecnica.imageset/ultimate_resistencia_tecnica.png" width="90"><br>Marébro |
| ⚡ Agilidade + ✨ Técnica | <img src="GymMonsters/Assets.xcassets/sprite_champion_agilidade_tecnica.imageset/champion_agilidade_tecnica.png" width="90"><br>Gingabro | <img src="GymMonsters/Assets.xcassets/sprite_ultimate_agilidade_tecnica.imageset/ultimate_agilidade_tecnica.png" width="90"><br>Piruetabro |

## Como o galho é escolhido

- Ao chegar em **Champion** (1200 XP), vence o atributo que você mais treinou **desde que virou Rookie**.
- Ao chegar em **Ultimate** (3600 XP), vence o atributo mais treinado **durante a fase Champion**. Dá para trocar de linha: um Halterobro que passou a fase correndo vira Fôlegobro.
- Empate fica com a ordem Força → Resistência → Agilidade → Técnica.
- **Híbrido:** nas duas viradas, se o segundo atributo da fase tiver pelo menos 90% do primeiro, sai a forma híbrida da dupla em vez da normal (ex.: quem passa a fase jogando futebol, metade Resistência e metade Agilidade, vira Chuteirabro). Também dá para entrar ou sair do híbrido no Ultimate: um Crossbro que passou a fase só correndo vira Fôlegobro.
- Crossfit sozinho já tende a híbrido (40% Força, 40% Resistência): quem só faz crossfit vira Crossbro e depois Hércubro.

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

Cada espécie também tem as 12 formas híbridas, cada uma com nome próprio: nenhum nome se repete no jogo (ex.: Força + Resistência é **Crossbro** no coelho, **Burpeebro** no urso e **Viralatabro** no cachorro). A lista completa está no `HIBRIDOS.md`. As artes ficam em `sprite_<id>_champion_<a>_<b>` e `sprite_<id>_ultimate_<a>_<b>`; sem a arte, o bro segue a forma normal do atributo dominante. Os prompts estão no `HIBRIDOS.md` e o passo a passo para gerar e instalar, em `tools/README.md`. Prontas: todas as 96.

### Galeria dos híbridos

**Champions**

| Espécie | Força + Resistência | Força + Agilidade | Força + Técnica | Resistência + Agilidade | Resistência + Técnica | Agilidade + Técnica |
|---|---|---|---|---|---|---|
| Coelho | <img src="GymMonsters/Assets.xcassets/sprite_champion_forca_resistencia.imageset/champion_forca_resistencia.png" width="48"><br>Crossbro | <img src="GymMonsters/Assets.xcassets/sprite_champion_forca_agilidade.imageset/champion_forca_agilidade.png" width="48"><br>Golpebro | <img src="GymMonsters/Assets.xcassets/sprite_champion_forca_tecnica.imageset/champion_forca_tecnica.png" width="48"><br>Arrancobro | <img src="GymMonsters/Assets.xcassets/sprite_champion_resistencia_agilidade.imageset/champion_resistencia_agilidade.png" width="48"><br>Chuteirabro | <img src="GymMonsters/Assets.xcassets/sprite_champion_resistencia_tecnica.imageset/champion_resistencia_tecnica.png" width="48"><br>Nadobro | <img src="GymMonsters/Assets.xcassets/sprite_champion_agilidade_tecnica.imageset/champion_agilidade_tecnica.png" width="48"><br>Gingabro |
| Urso | <img src="GymMonsters/Assets.xcassets/sprite_urso_champion_forca_resistencia.imageset/urso_champion_forca_resistencia.png" width="48"><br>Burpeebro | <img src="GymMonsters/Assets.xcassets/sprite_urso_champion_forca_agilidade.imageset/urso_champion_forca_agilidade.png" width="48"><br>Patadabro | <img src="GymMonsters/Assets.xcassets/sprite_urso_champion_forca_tecnica.imageset/urso_champion_forca_tecnica.png" width="48"><br>Arremessobro | <img src="GymMonsters/Assets.xcassets/sprite_urso_champion_resistencia_agilidade.imageset/urso_champion_resistencia_agilidade.png" width="48"><br>Mateirobro | <img src="GymMonsters/Assets.xcassets/sprite_urso_champion_resistencia_tecnica.imageset/urso_champion_resistencia_tecnica.png" width="48"><br>Salmãobro | <img src="GymMonsters/Assets.xcassets/sprite_urso_champion_agilidade_tecnica.imageset/urso_champion_agilidade_tecnica.png" width="48"><br>Meialuabro |
| Rato | <img src="GymMonsters/Assets.xcassets/sprite_rato_champion_forca_resistencia.imageset/rato_champion_forca_resistencia.png" width="48"><br>Bigodefitbro | <img src="GymMonsters/Assets.xcassets/sprite_rato_champion_forca_agilidade.imageset/rato_champion_forca_agilidade.png" width="48"><br>Mordidabro | <img src="GymMonsters/Assets.xcassets/sprite_rato_champion_forca_tecnica.imageset/rato_champion_forca_tecnica.png" width="48"><br>Gorgonzolabro | <img src="GymMonsters/Assets.xcassets/sprite_rato_champion_resistencia_agilidade.imageset/rato_champion_resistencia_agilidade.png" width="48"><br>Bueirobro | <img src="GymMonsters/Assets.xcassets/sprite_rato_champion_resistencia_tecnica.imageset/rato_champion_resistencia_tecnica.png" width="48"><br>Esgotobro | <img src="GymMonsters/Assets.xcassets/sprite_rato_champion_agilidade_tecnica.imageset/rato_champion_agilidade_tecnica.png" width="48"><br>Arraiabro |
| Lobo | <img src="GymMonsters/Assets.xcassets/sprite_lobo_champion_forca_resistencia.imageset/lobo_champion_forca_resistencia.png" width="48"><br>Caninobro | <img src="GymMonsters/Assets.xcassets/sprite_lobo_champion_forca_agilidade.imageset/lobo_champion_forca_agilidade.png" width="48"><br>Investidabro | <img src="GymMonsters/Assets.xcassets/sprite_lobo_champion_forca_tecnica.imageset/lobo_champion_forca_tecnica.png" width="48"><br>Cumebro | <img src="GymMonsters/Assets.xcassets/sprite_lobo_champion_resistencia_agilidade.imageset/lobo_champion_resistencia_agilidade.png" width="48"><br>Rastrobro | <img src="GymMonsters/Assets.xcassets/sprite_lobo_champion_resistencia_tecnica.imageset/lobo_champion_resistencia_tecnica.png" width="48"><br>Riachobro | <img src="GymMonsters/Assets.xcassets/sprite_lobo_champion_agilidade_tecnica.imageset/lobo_champion_agilidade_tecnica.png" width="48"><br>Crepúsculobro |
| Cachorro | <img src="GymMonsters/Assets.xcassets/sprite_cachorro_champion_forca_resistencia.imageset/cachorro_champion_forca_resistencia.png" width="48"><br>Viralatabro | <img src="GymMonsters/Assets.xcassets/sprite_cachorro_champion_forca_agilidade.imageset/cachorro_champion_forca_agilidade.png" width="48"><br>Boxerbro | <img src="GymMonsters/Assets.xcassets/sprite_cachorro_champion_forca_tecnica.imageset/cachorro_champion_forca_tecnica.png" width="48"><br>Bulldogbro | <img src="GymMonsters/Assets.xcassets/sprite_cachorro_champion_resistencia_agilidade.imageset/cachorro_champion_resistencia_agilidade.png" width="48"><br>Gandulabro | <img src="GymMonsters/Assets.xcassets/sprite_cachorro_champion_resistencia_tecnica.imageset/cachorro_champion_resistencia_tecnica.png" width="48"><br>Labradorbro | <img src="GymMonsters/Assets.xcassets/sprite_cachorro_champion_agilidade_tecnica.imageset/cachorro_champion_agilidade_tecnica.png" width="48"><br>Poodlebro |
| Esquilo | <img src="GymMonsters/Assets.xcassets/sprite_esquilo_champion_forca_resistencia.imageset/esquilo_champion_forca_resistencia.png" width="48"><br>Bolotabro | <img src="GymMonsters/Assets.xcassets/sprite_esquilo_champion_forca_agilidade.imageset/esquilo_champion_forca_agilidade.png" width="48"><br>Ouriçobro | <img src="GymMonsters/Assets.xcassets/sprite_esquilo_champion_forca_tecnica.imageset/esquilo_champion_forca_tecnica.png" width="48"><br>Torabro | <img src="GymMonsters/Assets.xcassets/sprite_esquilo_champion_resistencia_agilidade.imageset/esquilo_champion_resistencia_agilidade.png" width="48"><br>Copabro | <img src="GymMonsters/Assets.xcassets/sprite_esquilo_champion_resistencia_tecnica.imageset/esquilo_champion_resistencia_tecnica.png" width="48"><br>Cachoeirabro | <img src="GymMonsters/Assets.xcassets/sprite_esquilo_champion_agilidade_tecnica.imageset/esquilo_champion_agilidade_tecnica.png" width="48"><br>Cipóbro |
| Gato | <img src="GymMonsters/Assets.xcassets/sprite_gato_champion_forca_resistencia.imageset/gato_champion_forca_resistencia.png" width="48"><br>Miaufitbro | <img src="GymMonsters/Assets.xcassets/sprite_gato_champion_forca_agilidade.imageset/gato_champion_forca_agilidade.png" width="48"><br>Unhadabro | <img src="GymMonsters/Assets.xcassets/sprite_gato_champion_forca_tecnica.imageset/gato_champion_forca_tecnica.png" width="48"><br>Pumabro | <img src="GymMonsters/Assets.xcassets/sprite_gato_champion_resistencia_agilidade.imageset/gato_champion_resistencia_agilidade.png" width="48"><br>Gatunobro | <img src="GymMonsters/Assets.xcassets/sprite_gato_champion_resistencia_tecnica.imageset/gato_champion_resistencia_tecnica.png" width="48"><br>Molhadobro | <img src="GymMonsters/Assets.xcassets/sprite_gato_champion_agilidade_tecnica.imageset/gato_champion_agilidade_tecnica.png" width="48"><br>Muretabro |
| Coruja | <img src="GymMonsters/Assets.xcassets/sprite_coruja_champion_forca_resistencia.imageset/coruja_champion_forca_resistencia.png" width="48"><br>Madrugabro | <img src="GymMonsters/Assets.xcassets/sprite_coruja_champion_forca_agilidade.imageset/coruja_champion_forca_agilidade.png" width="48"><br>Bicadabro | <img src="GymMonsters/Assets.xcassets/sprite_coruja_champion_forca_tecnica.imageset/coruja_champion_forca_tecnica.png" width="48"><br>Mochobro | <img src="GymMonsters/Assets.xcassets/sprite_coruja_champion_resistencia_agilidade.imageset/coruja_champion_resistencia_agilidade.png" width="48"><br>Revoadabro | <img src="GymMonsters/Assets.xcassets/sprite_coruja_champion_resistencia_tecnica.imageset/coruja_champion_resistencia_tecnica.png" width="48"><br>Martimbro | <img src="GymMonsters/Assets.xcassets/sprite_coruja_champion_agilidade_tecnica.imageset/coruja_champion_agilidade_tecnica.png" width="48"><br>Plumabro |

**Ultimates**

| Espécie | Força + Resistência | Força + Agilidade | Força + Técnica | Resistência + Agilidade | Resistência + Técnica | Agilidade + Técnica |
|---|---|---|---|---|---|---|
| Coelho | <img src="GymMonsters/Assets.xcassets/sprite_ultimate_forca_resistencia.imageset/ultimate_forca_resistencia.png" width="48"><br>Hércubro | <img src="GymMonsters/Assets.xcassets/sprite_ultimate_forca_agilidade.imageset/ultimate_forca_agilidade.png" width="48"><br>Titãbro | <img src="GymMonsters/Assets.xcassets/sprite_ultimate_forca_tecnica.imageset/ultimate_forca_tecnica.png" width="48"><br>Olimpibro | <img src="GymMonsters/Assets.xcassets/sprite_ultimate_resistencia_agilidade.imageset/ultimate_resistencia_agilidade.png" width="48"><br>Tufãobro | <img src="GymMonsters/Assets.xcassets/sprite_ultimate_resistencia_tecnica.imageset/ultimate_resistencia_tecnica.png" width="48"><br>Marébro | <img src="GymMonsters/Assets.xcassets/sprite_ultimate_agilidade_tecnica.imageset/ultimate_agilidade_tecnica.png" width="48"><br>Piruetabro |
| Urso | <img src="GymMonsters/Assets.xcassets/sprite_urso_ultimate_forca_resistencia.imageset/urso_ultimate_forca_resistencia.png" width="48"><br>Colossobro | <img src="GymMonsters/Assets.xcassets/sprite_urso_ultimate_forca_agilidade.imageset/urso_ultimate_forca_agilidade.png" width="48"><br>Brutobro | <img src="GymMonsters/Assets.xcassets/sprite_urso_ultimate_forca_tecnica.imageset/urso_ultimate_forca_tecnica.png" width="48"><br>Gigantebro | <img src="GymMonsters/Assets.xcassets/sprite_urso_ultimate_resistencia_agilidade.imageset/urso_ultimate_resistencia_agilidade.png" width="48"><br>Nevascabro | <img src="GymMonsters/Assets.xcassets/sprite_urso_ultimate_resistencia_tecnica.imageset/urso_ultimate_resistencia_tecnica.png" width="48"><br>Polarbro | <img src="GymMonsters/Assets.xcassets/sprite_urso_ultimate_agilidade_tecnica.imageset/urso_ultimate_agilidade_tecnica.png" width="48"><br>Aurorabro |
| Rato | <img src="GymMonsters/Assets.xcassets/sprite_rato_ultimate_forca_resistencia.imageset/rato_ultimate_forca_resistencia.png" width="48"><br>Metrôbro | <img src="GymMonsters/Assets.xcassets/sprite_rato_ultimate_forca_agilidade.imageset/rato_ultimate_forca_agilidade.png" width="48"><br>Presabro | <img src="GymMonsters/Assets.xcassets/sprite_rato_ultimate_forca_tecnica.imageset/rato_ultimate_forca_tecnica.png" width="48"><br>Parmesãobro | <img src="GymMonsters/Assets.xcassets/sprite_rato_ultimate_resistencia_agilidade.imageset/rato_ultimate_resistencia_agilidade.png" width="48"><br>Ventaniabro | <img src="GymMonsters/Assets.xcassets/sprite_rato_ultimate_resistencia_tecnica.imageset/rato_ultimate_resistencia_tecnica.png" width="48"><br>Correntezabro | <img src="GymMonsters/Assets.xcassets/sprite_rato_ultimate_agilidade_tecnica.imageset/rato_ultimate_agilidade_tecnica.png" width="48"><br>Piãobro |
| Lobo | <img src="GymMonsters/Assets.xcassets/sprite_lobo_ultimate_forca_resistencia.imageset/lobo_ultimate_forca_resistencia.png" width="48"><br>Lobisombro | <img src="GymMonsters/Assets.xcassets/sprite_lobo_ultimate_forca_agilidade.imageset/lobo_ultimate_forca_agilidade.png" width="48"><br>Ragnarbro | <img src="GymMonsters/Assets.xcassets/sprite_lobo_ultimate_forca_tecnica.imageset/lobo_ultimate_forca_tecnica.png" width="48"><br>Cordilheirabro | <img src="GymMonsters/Assets.xcassets/sprite_lobo_ultimate_resistencia_agilidade.imageset/lobo_ultimate_resistencia_agilidade.png" width="48"><br>Vendavalbro | <img src="GymMonsters/Assets.xcassets/sprite_lobo_ultimate_resistencia_tecnica.imageset/lobo_ultimate_resistencia_tecnica.png" width="48"><br>Fiordebro | <img src="GymMonsters/Assets.xcassets/sprite_lobo_ultimate_agilidade_tecnica.imageset/lobo_ultimate_agilidade_tecnica.png" width="48"><br>Eclipsebro |
| Cachorro | <img src="GymMonsters/Assets.xcassets/sprite_cachorro_ultimate_forca_resistencia.imageset/cachorro_ultimate_forca_resistencia.png" width="48"><br>Cérberobro | <img src="GymMonsters/Assets.xcassets/sprite_cachorro_ultimate_forca_agilidade.imageset/cachorro_ultimate_forca_agilidade.png" width="48"><br>Dobermanbro | <img src="GymMonsters/Assets.xcassets/sprite_cachorro_ultimate_forca_tecnica.imageset/cachorro_ultimate_forca_tecnica.png" width="48"><br>Sãobernardobro | <img src="GymMonsters/Assets.xcassets/sprite_cachorro_ultimate_resistencia_agilidade.imageset/cachorro_ultimate_resistencia_agilidade.png" width="48"><br>Salukibro | <img src="GymMonsters/Assets.xcassets/sprite_cachorro_ultimate_resistencia_tecnica.imageset/cachorro_ultimate_resistencia_tecnica.png" width="48"><br>Terranovabro | <img src="GymMonsters/Assets.xcassets/sprite_cachorro_ultimate_agilidade_tecnica.imageset/cachorro_ultimate_agilidade_tecnica.png" width="48"><br>Borderbro |
| Esquilo | <img src="GymMonsters/Assets.xcassets/sprite_esquilo_ultimate_forca_resistencia.imageset/esquilo_ultimate_forca_resistencia.png" width="48"><br>Sequoiabro | <img src="GymMonsters/Assets.xcassets/sprite_esquilo_ultimate_forca_agilidade.imageset/esquilo_ultimate_forca_agilidade.png" width="48"><br>Espinheirobro | <img src="GymMonsters/Assets.xcassets/sprite_esquilo_ultimate_forca_tecnica.imageset/esquilo_ultimate_forca_tecnica.png" width="48"><br>Jequitibro | <img src="GymMonsters/Assets.xcassets/sprite_esquilo_ultimate_resistencia_agilidade.imageset/esquilo_ultimate_resistencia_agilidade.png" width="48"><br>Redemoinhobro | <img src="GymMonsters/Assets.xcassets/sprite_esquilo_ultimate_resistencia_tecnica.imageset/esquilo_ultimate_resistencia_tecnica.png" width="48"><br>Cascatabro | <img src="GymMonsters/Assets.xcassets/sprite_esquilo_ultimate_agilidade_tecnica.imageset/esquilo_ultimate_agilidade_tecnica.png" width="48"><br>Trapezistabro |
| Gato | <img src="GymMonsters/Assets.xcassets/sprite_gato_ultimate_forca_resistencia.imageset/gato_ultimate_forca_resistencia.png" width="48"><br>Tigrebro | <img src="GymMonsters/Assets.xcassets/sprite_gato_ultimate_forca_agilidade.imageset/gato_ultimate_forca_agilidade.png" width="48"><br>Smilodonbro | <img src="GymMonsters/Assets.xcassets/sprite_gato_ultimate_forca_tecnica.imageset/gato_ultimate_forca_tecnica.png" width="48"><br>Leãobro | <img src="GymMonsters/Assets.xcassets/sprite_gato_ultimate_resistencia_agilidade.imageset/gato_ultimate_resistencia_agilidade.png" width="48"><br>Guepardobro | <img src="GymMonsters/Assets.xcassets/sprite_gato_ultimate_resistencia_tecnica.imageset/gato_ultimate_resistencia_tecnica.png" width="48"><br>Onçabro | <img src="GymMonsters/Assets.xcassets/sprite_gato_ultimate_agilidade_tecnica.imageset/gato_ultimate_agilidade_tecnica.png" width="48"><br>Bastetbro |
| Coruja | <img src="GymMonsters/Assets.xcassets/sprite_coruja_ultimate_forca_resistencia.imageset/coruja_ultimate_forca_resistencia.png" width="48"><br>Grifobro | <img src="GymMonsters/Assets.xcassets/sprite_coruja_ultimate_forca_agilidade.imageset/coruja_ultimate_forca_agilidade.png" width="48"><br>Falcãobro | <img src="GymMonsters/Assets.xcassets/sprite_coruja_ultimate_forca_tecnica.imageset/coruja_ultimate_forca_tecnica.png" width="48"><br>Atenabro | <img src="GymMonsters/Assets.xcassets/sprite_coruja_ultimate_resistencia_agilidade.imageset/coruja_ultimate_resistencia_agilidade.png" width="48"><br>Ciclonebro | <img src="GymMonsters/Assets.xcassets/sprite_coruja_ultimate_resistencia_tecnica.imageset/coruja_ultimate_resistencia_tecnica.png" width="48"><br>Albatrozbro | <img src="GymMonsters/Assets.xcassets/sprite_coruja_ultimate_agilidade_tecnica.imageset/coruja_ultimate_agilidade_tecnica.png" width="48"><br>Fênixbro |
