# Árvore de evolução dos bros

```mermaid
flowchart LR
    O[🥚 Ovo<br/>0 XP] -->|60 XP| G[Gymbro<br/>Bebê]
    G -->|300 XP| C[Cutebro<br/>Novato]
    C -->|1200 XP · Força| HF[Halterobro]
    C -->|1200 XP · Resistência| MR[Maratobro]
    C -->|1200 XP · Agilidade| SA[Saltabro]
    C -->|1200 XP · Técnica| ZE[Zenbro]
    HF & MR & SA & ZE -->|3600 XP · Força| TR[Trebobro]
    HF & MR & SA & ZE -->|3600 XP · Resistência| FO[Fôlegobro]
    HF & MR & SA & ZE -->|3600 XP · Agilidade| RE[Relampabro]
    HF & MR & SA & ZE -->|3600 XP · Técnica| ME[Mestrebro]
    C -.->|1200 XP · dois atributos quase empatados| HC[Atleta híbrido<br/>Crossbro · Golpebro · Arrancobro<br/>Chuteirabro · Nadobro · Gingabro]
    HF & MR & SA & ZE & HC -.->|3600 XP · dois atributos quase empatados| HU[Lenda híbrida<br/>Hércubro · Titãbro · Olimpibro<br/>Tufãobro · Marébro · Piruetabro]
    HC -->|3600 XP · um atributo| TR & FO & RE & ME
```

Linha cheia: forma normal (o atributo mais treinado). Pontilhada: forma híbrida (o segundo atributo tem pelo menos 90% do primeiro).

## Estágios

| Estágio | XP total | Forma |
|---|---|---|
| Ovo | 0 | <img src="GymBros/Resources/Assets.xcassets/sprite_egg.imageset/egg.png" width="80"> |
| Bebê | 60 | <img src="GymBros/Resources/Assets.xcassets/sprite_baby.imageset/baby.png" width="80"><br>Gymbro |
| Novato | 300 | <img src="GymBros/Resources/Assets.xcassets/sprite_rookie.imageset/rookie.png" width="80"><br>Cutebro |

## Galhos (Atleta → Lenda)

| Atributo | Atleta · 1200 XP | Lenda · 3600 XP |
|---|---|---|
| 💪 Força | <img src="GymBros/Resources/Assets.xcassets/sprite_champion_forca.imageset/champion_forca.png" width="90"><br>Halterobro | <img src="GymBros/Resources/Assets.xcassets/sprite_ultimate_forca.imageset/ultimate_forca.png" width="90"><br>Trebobro |
| ❤️ Resistência | <img src="GymBros/Resources/Assets.xcassets/sprite_champion_resistencia.imageset/champion_resistencia.png" width="90"><br>Maratobro | <img src="GymBros/Resources/Assets.xcassets/sprite_ultimate_resistencia.imageset/ultimate_resistencia.png" width="90"><br>Fôlegobro |
| ⚡ Agilidade | <img src="GymBros/Resources/Assets.xcassets/sprite_champion_agilidade.imageset/champion_agilidade.png" width="90"><br>Saltabro | <img src="GymBros/Resources/Assets.xcassets/sprite_ultimate_agilidade.imageset/ultimate_agilidade.png" width="90"><br>Relampabro |
| ✨ Técnica | <img src="GymBros/Resources/Assets.xcassets/sprite_champion_tecnica.imageset/champion_tecnica.png" width="90"><br>Zenbro | <img src="GymBros/Resources/Assets.xcassets/sprite_ultimate_tecnica.imageset/ultimate_tecnica.png" width="90"><br>Mestrebro |

## Formas híbridas

Quando os **dois atributos mais treinados** da fase ficam quase empatados (o segundo com pelo menos 90% do primeiro), o bro vira a forma híbrida da dupla: mistura as duas roupas e o corpo dos dois treinos. Na Lenda híbrida, uma aura com as duas cores envolve o bro.

| Dupla | Atleta · 1200 XP | Lenda · 3600 XP |
|---|---|---|
| 💪 Força + ❤️ Resistência | <img src="GymBros/Resources/Assets.xcassets/sprite_champion_forca_resistencia.imageset/champion_forca_resistencia.png" width="90"><br>Crossbro | <img src="GymBros/Resources/Assets.xcassets/sprite_ultimate_forca_resistencia.imageset/ultimate_forca_resistencia.png" width="90"><br>Hércubro |
| 💪 Força + ⚡ Agilidade | <img src="GymBros/Resources/Assets.xcassets/sprite_champion_forca_agilidade.imageset/champion_forca_agilidade.png" width="90"><br>Golpebro | <img src="GymBros/Resources/Assets.xcassets/sprite_ultimate_forca_agilidade.imageset/ultimate_forca_agilidade.png" width="90"><br>Titãbro |
| 💪 Força + ✨ Técnica | <img src="GymBros/Resources/Assets.xcassets/sprite_champion_forca_tecnica.imageset/champion_forca_tecnica.png" width="90"><br>Arrancobro | <img src="GymBros/Resources/Assets.xcassets/sprite_ultimate_forca_tecnica.imageset/ultimate_forca_tecnica.png" width="90"><br>Olimpibro |
| ❤️ Resistência + ⚡ Agilidade | <img src="GymBros/Resources/Assets.xcassets/sprite_champion_resistencia_agilidade.imageset/champion_resistencia_agilidade.png" width="90"><br>Chuteirabro | <img src="GymBros/Resources/Assets.xcassets/sprite_ultimate_resistencia_agilidade.imageset/ultimate_resistencia_agilidade.png" width="90"><br>Tufãobro |
| ❤️ Resistência + ✨ Técnica | <img src="GymBros/Resources/Assets.xcassets/sprite_champion_resistencia_tecnica.imageset/champion_resistencia_tecnica.png" width="90"><br>Nadobro | <img src="GymBros/Resources/Assets.xcassets/sprite_ultimate_resistencia_tecnica.imageset/ultimate_resistencia_tecnica.png" width="90"><br>Marébro |
| ⚡ Agilidade + ✨ Técnica | <img src="GymBros/Resources/Assets.xcassets/sprite_champion_agilidade_tecnica.imageset/champion_agilidade_tecnica.png" width="90"><br>Gingabro | <img src="GymBros/Resources/Assets.xcassets/sprite_ultimate_agilidade_tecnica.imageset/ultimate_agilidade_tecnica.png" width="90"><br>Piruetabro |

## Como o galho é escolhido

- Ao chegar em **Atleta** (1200 XP), vence o atributo que você mais treinou **desde que virou Novato**.
- Ao chegar em **Lenda** (3600 XP), vence o atributo mais treinado **durante a fase Atleta**. Dá para trocar de linha: um Halterobro que passou a fase correndo vira Fôlegobro.
- Empate fica com a ordem Força → Resistência → Agilidade → Técnica.
- **Híbrido:** nas duas viradas, se o segundo atributo da fase tiver pelo menos 90% do primeiro, sai a forma híbrida da dupla em vez da normal (ex.: quem passa a fase jogando futebol, metade Resistência e metade Agilidade, vira Chuteirabro). Também dá para entrar ou sair do híbrido na Lenda: um Crossbro que passou a fase só correndo vira Fôlegobro.
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

XP de cada atividade = duração × gasto típico (MET) × esforço; acima de 150 XP no dia rende 1/3, com teto de 300 XP/dia. Treinando todo dia, o Atleta chega em ~5 semanas e a Lenda em ~3–4 meses.

## Espécies

A espécie é decidida quando o ovo choca (60 XP, de 1 a 4 treinos), pela **atividade** dos treinos que o chocaram: a atividade com **mais da metade dos minutos** treinados no ovo define o animal. Sem atividade principal (uma mistura) ou com "Outro", nasce o **Coelho**. Os minutos contam, não o XP: senão a corrida, que rende quase o dobro de XP por minuto, venceria a musculação. Urso e Rato dividem musculação e crossfit; o sorteio entre os dois é fixo pelo id do bro. Depois de nascer, a espécie fica gravada no bro. A forma (Atleta, Lenda, híbrido) continua saindo dos atributos.

| Espécie | Atividades no app | No Apple Saúde (tipo exato do treino) |
|---|---|---|
| Urso e Rato | Musculação, Crossfit | Força tradicional e funcional, core, cross training, HIIT, cardio misto, pular corda, escada, step |
| Lobo | Corrida, Bike, Natação | Corrida, atletismo, ciclismo, handbike, cadeira de rodas (corrida), natação, hidroginástica, remo, canoagem e remo de pé, esqui cross-country, triatlo, elíptico, mergulho |
| Cachorro | Caminhada, Futebol | Caminhada, trilha, cadeira de rodas (passeio), futebol, futebol americano e australiano, rúgbi, basquete, handebol, hóquei, lacrosse, beisebol, softbol, críquete, polo aquático, frisbee, brincar, hipismo, caça |
| Esquilo | Vôlei | Vôlei, escalada, ginástica, tênis, tênis de mesa, badminton, squash, raquetebol, pickleball, patinação, snowboard, esqui alpino, esportes na neve, surfe, esportes aquáticos |
| Gato | Lutas, Dança | Artes marciais, boxe, kickboxing, luta, esgrima, dança (cardio e social), barre |
| Coruja | Yoga | Yoga, pilates, flexibilidade, mente e corpo, tai chi, preparação e recuperação, desaquecimento, golfe, arco e flecha, boliche, curling, vela, pesca |
| Coelho | Outro, ou mistura sem atividade principal | Outro, jogos de fitness, transição |

Treinos importados do Apple Saúde usam o tipo exato (tênis vira Esquilo, golfe vira Coruja); os registrados no app usam a categoria. Todas as 84 atividades que o iPhone e o Apple Watch gravam têm um animal (`GymBros/Bros/Hatch.swift`).

Para incluir uma espécie (`Species.all` em `GymBros/Bros/Game.swift`): id, nome, nomes das 10 formas e dos 12 híbridos, as atividades em `GymBros/Bros/Hatch.swift` e as artes `sprite_<id>_<forma>` no app e no widget.

| Espécie | Nasce de | Bebê → Novato | Atletas (Força / Resistência / Agilidade / Técnica) | Lendas |
|---|---|---|---|---|
| Coelho | Outro ou mistura | Gymbro → Cutebro | Halterobro / Maratobro / Saltabro / Zenbro | Trebobro / Fôlegobro / Relampabro / Mestrebro |
| Urso | Musculação, Crossfit | Pelucibro → Ursabro | Supinobro / Trilhabro / Rolabro / Sumobro | Grizzlibro / Montanhabro / Avalanchebro / Kodiabro |
| Rato | Musculação, Crossfit | Queijibro → Ratibro | Marombabro / Rodibro / Fuxibro / Labiribro | Ratazanabro / Esteirabro / Sombrabro / Engenhobro |
| Lobo | Corrida, Bike, Natação | Uivibro → Lobinbro | Alfabro / Trotebro / Caçabro / Matilhabro | Fenribro / Luabro / Ventobro / Ancestrabro |
| Cachorro | Caminhada, Futebol | Filhotibro → Caramelbro | Pitbulbro / Galgobro / Frisbeebro / Pastorbro | Mastibro / Huskybro / Agilitybro / Guiabro |
| Esquilo | Vôlei | Nozibro → Esquilbro | Quebranozbro / Galhobro / Pulabro / Acrobabro | Carvalhobro / Florestabro / Voadorbro / Parkourbro |
| Gato | Lutas, Dança | Novelbro → Bichanobro | Garrabro / Rondabro / Telhadobro / Ronrobro | Jubabro / Panterabro / Linxbro / Esfingebro |
| Coruja | Yoga | Penugbro → Corujabro | Rapinabro / Noturnbro / Planabro / Sabiobro | Harpiabro / Luarbro / Rasantebro / Oraculobro |

Só nascem espécies com as 10 artes no app; as demais ficam cadastradas esperando a arte. Prontas: todas as 8.

Cada espécie também tem as 12 formas híbridas, cada uma com nome próprio: nenhum nome se repete no jogo (ex.: Força + Resistência é **Crossbro** no coelho, **Burpeebro** no urso e **Viralatabro** no cachorro). A lista completa está no `HIBRIDOS.md`. As artes ficam em `sprite_<id>_champion_<a>_<b>` e `sprite_<id>_ultimate_<a>_<b>`; sem a arte, o bro segue a forma normal do atributo dominante. Os prompts estão no `HIBRIDOS.md` e o passo a passo para gerar e instalar, em `tools/README.md`. Prontas: todas as 96.

### Galeria dos híbridos

**Atletas**

| Espécie | Força + Resistência | Força + Agilidade | Força + Técnica | Resistência + Agilidade | Resistência + Técnica | Agilidade + Técnica |
|---|---|---|---|---|---|---|
| Coelho | <img src="GymBros/Resources/Assets.xcassets/sprite_champion_forca_resistencia.imageset/champion_forca_resistencia.png" width="48"><br>Crossbro | <img src="GymBros/Resources/Assets.xcassets/sprite_champion_forca_agilidade.imageset/champion_forca_agilidade.png" width="48"><br>Golpebro | <img src="GymBros/Resources/Assets.xcassets/sprite_champion_forca_tecnica.imageset/champion_forca_tecnica.png" width="48"><br>Arrancobro | <img src="GymBros/Resources/Assets.xcassets/sprite_champion_resistencia_agilidade.imageset/champion_resistencia_agilidade.png" width="48"><br>Chuteirabro | <img src="GymBros/Resources/Assets.xcassets/sprite_champion_resistencia_tecnica.imageset/champion_resistencia_tecnica.png" width="48"><br>Nadobro | <img src="GymBros/Resources/Assets.xcassets/sprite_champion_agilidade_tecnica.imageset/champion_agilidade_tecnica.png" width="48"><br>Gingabro |
| Urso | <img src="GymBros/Resources/Assets.xcassets/sprite_urso_champion_forca_resistencia.imageset/urso_champion_forca_resistencia.png" width="48"><br>Burpeebro | <img src="GymBros/Resources/Assets.xcassets/sprite_urso_champion_forca_agilidade.imageset/urso_champion_forca_agilidade.png" width="48"><br>Patadabro | <img src="GymBros/Resources/Assets.xcassets/sprite_urso_champion_forca_tecnica.imageset/urso_champion_forca_tecnica.png" width="48"><br>Arremessobro | <img src="GymBros/Resources/Assets.xcassets/sprite_urso_champion_resistencia_agilidade.imageset/urso_champion_resistencia_agilidade.png" width="48"><br>Mateirobro | <img src="GymBros/Resources/Assets.xcassets/sprite_urso_champion_resistencia_tecnica.imageset/urso_champion_resistencia_tecnica.png" width="48"><br>Salmãobro | <img src="GymBros/Resources/Assets.xcassets/sprite_urso_champion_agilidade_tecnica.imageset/urso_champion_agilidade_tecnica.png" width="48"><br>Meialuabro |
| Rato | <img src="GymBros/Resources/Assets.xcassets/sprite_rato_champion_forca_resistencia.imageset/rato_champion_forca_resistencia.png" width="48"><br>Bigodefitbro | <img src="GymBros/Resources/Assets.xcassets/sprite_rato_champion_forca_agilidade.imageset/rato_champion_forca_agilidade.png" width="48"><br>Mordidabro | <img src="GymBros/Resources/Assets.xcassets/sprite_rato_champion_forca_tecnica.imageset/rato_champion_forca_tecnica.png" width="48"><br>Gorgonzolabro | <img src="GymBros/Resources/Assets.xcassets/sprite_rato_champion_resistencia_agilidade.imageset/rato_champion_resistencia_agilidade.png" width="48"><br>Bueirobro | <img src="GymBros/Resources/Assets.xcassets/sprite_rato_champion_resistencia_tecnica.imageset/rato_champion_resistencia_tecnica.png" width="48"><br>Esgotobro | <img src="GymBros/Resources/Assets.xcassets/sprite_rato_champion_agilidade_tecnica.imageset/rato_champion_agilidade_tecnica.png" width="48"><br>Arraiabro |
| Lobo | <img src="GymBros/Resources/Assets.xcassets/sprite_lobo_champion_forca_resistencia.imageset/lobo_champion_forca_resistencia.png" width="48"><br>Caninobro | <img src="GymBros/Resources/Assets.xcassets/sprite_lobo_champion_forca_agilidade.imageset/lobo_champion_forca_agilidade.png" width="48"><br>Investidabro | <img src="GymBros/Resources/Assets.xcassets/sprite_lobo_champion_forca_tecnica.imageset/lobo_champion_forca_tecnica.png" width="48"><br>Cumebro | <img src="GymBros/Resources/Assets.xcassets/sprite_lobo_champion_resistencia_agilidade.imageset/lobo_champion_resistencia_agilidade.png" width="48"><br>Rastrobro | <img src="GymBros/Resources/Assets.xcassets/sprite_lobo_champion_resistencia_tecnica.imageset/lobo_champion_resistencia_tecnica.png" width="48"><br>Riachobro | <img src="GymBros/Resources/Assets.xcassets/sprite_lobo_champion_agilidade_tecnica.imageset/lobo_champion_agilidade_tecnica.png" width="48"><br>Crepúsculobro |
| Cachorro | <img src="GymBros/Resources/Assets.xcassets/sprite_cachorro_champion_forca_resistencia.imageset/cachorro_champion_forca_resistencia.png" width="48"><br>Viralatabro | <img src="GymBros/Resources/Assets.xcassets/sprite_cachorro_champion_forca_agilidade.imageset/cachorro_champion_forca_agilidade.png" width="48"><br>Boxerbro | <img src="GymBros/Resources/Assets.xcassets/sprite_cachorro_champion_forca_tecnica.imageset/cachorro_champion_forca_tecnica.png" width="48"><br>Bulldogbro | <img src="GymBros/Resources/Assets.xcassets/sprite_cachorro_champion_resistencia_agilidade.imageset/cachorro_champion_resistencia_agilidade.png" width="48"><br>Gandulabro | <img src="GymBros/Resources/Assets.xcassets/sprite_cachorro_champion_resistencia_tecnica.imageset/cachorro_champion_resistencia_tecnica.png" width="48"><br>Labradorbro | <img src="GymBros/Resources/Assets.xcassets/sprite_cachorro_champion_agilidade_tecnica.imageset/cachorro_champion_agilidade_tecnica.png" width="48"><br>Poodlebro |
| Esquilo | <img src="GymBros/Resources/Assets.xcassets/sprite_esquilo_champion_forca_resistencia.imageset/esquilo_champion_forca_resistencia.png" width="48"><br>Bolotabro | <img src="GymBros/Resources/Assets.xcassets/sprite_esquilo_champion_forca_agilidade.imageset/esquilo_champion_forca_agilidade.png" width="48"><br>Ouriçobro | <img src="GymBros/Resources/Assets.xcassets/sprite_esquilo_champion_forca_tecnica.imageset/esquilo_champion_forca_tecnica.png" width="48"><br>Torabro | <img src="GymBros/Resources/Assets.xcassets/sprite_esquilo_champion_resistencia_agilidade.imageset/esquilo_champion_resistencia_agilidade.png" width="48"><br>Copabro | <img src="GymBros/Resources/Assets.xcassets/sprite_esquilo_champion_resistencia_tecnica.imageset/esquilo_champion_resistencia_tecnica.png" width="48"><br>Cachoeirabro | <img src="GymBros/Resources/Assets.xcassets/sprite_esquilo_champion_agilidade_tecnica.imageset/esquilo_champion_agilidade_tecnica.png" width="48"><br>Cipóbro |
| Gato | <img src="GymBros/Resources/Assets.xcassets/sprite_gato_champion_forca_resistencia.imageset/gato_champion_forca_resistencia.png" width="48"><br>Miaufitbro | <img src="GymBros/Resources/Assets.xcassets/sprite_gato_champion_forca_agilidade.imageset/gato_champion_forca_agilidade.png" width="48"><br>Unhadabro | <img src="GymBros/Resources/Assets.xcassets/sprite_gato_champion_forca_tecnica.imageset/gato_champion_forca_tecnica.png" width="48"><br>Pumabro | <img src="GymBros/Resources/Assets.xcassets/sprite_gato_champion_resistencia_agilidade.imageset/gato_champion_resistencia_agilidade.png" width="48"><br>Gatunobro | <img src="GymBros/Resources/Assets.xcassets/sprite_gato_champion_resistencia_tecnica.imageset/gato_champion_resistencia_tecnica.png" width="48"><br>Molhadobro | <img src="GymBros/Resources/Assets.xcassets/sprite_gato_champion_agilidade_tecnica.imageset/gato_champion_agilidade_tecnica.png" width="48"><br>Muretabro |
| Coruja | <img src="GymBros/Resources/Assets.xcassets/sprite_coruja_champion_forca_resistencia.imageset/coruja_champion_forca_resistencia.png" width="48"><br>Madrugabro | <img src="GymBros/Resources/Assets.xcassets/sprite_coruja_champion_forca_agilidade.imageset/coruja_champion_forca_agilidade.png" width="48"><br>Bicadabro | <img src="GymBros/Resources/Assets.xcassets/sprite_coruja_champion_forca_tecnica.imageset/coruja_champion_forca_tecnica.png" width="48"><br>Mochobro | <img src="GymBros/Resources/Assets.xcassets/sprite_coruja_champion_resistencia_agilidade.imageset/coruja_champion_resistencia_agilidade.png" width="48"><br>Revoadabro | <img src="GymBros/Resources/Assets.xcassets/sprite_coruja_champion_resistencia_tecnica.imageset/coruja_champion_resistencia_tecnica.png" width="48"><br>Martimbro | <img src="GymBros/Resources/Assets.xcassets/sprite_coruja_champion_agilidade_tecnica.imageset/coruja_champion_agilidade_tecnica.png" width="48"><br>Plumabro |

**Lendas**

| Espécie | Força + Resistência | Força + Agilidade | Força + Técnica | Resistência + Agilidade | Resistência + Técnica | Agilidade + Técnica |
|---|---|---|---|---|---|---|
| Coelho | <img src="GymBros/Resources/Assets.xcassets/sprite_ultimate_forca_resistencia.imageset/ultimate_forca_resistencia.png" width="48"><br>Hércubro | <img src="GymBros/Resources/Assets.xcassets/sprite_ultimate_forca_agilidade.imageset/ultimate_forca_agilidade.png" width="48"><br>Titãbro | <img src="GymBros/Resources/Assets.xcassets/sprite_ultimate_forca_tecnica.imageset/ultimate_forca_tecnica.png" width="48"><br>Olimpibro | <img src="GymBros/Resources/Assets.xcassets/sprite_ultimate_resistencia_agilidade.imageset/ultimate_resistencia_agilidade.png" width="48"><br>Tufãobro | <img src="GymBros/Resources/Assets.xcassets/sprite_ultimate_resistencia_tecnica.imageset/ultimate_resistencia_tecnica.png" width="48"><br>Marébro | <img src="GymBros/Resources/Assets.xcassets/sprite_ultimate_agilidade_tecnica.imageset/ultimate_agilidade_tecnica.png" width="48"><br>Piruetabro |
| Urso | <img src="GymBros/Resources/Assets.xcassets/sprite_urso_ultimate_forca_resistencia.imageset/urso_ultimate_forca_resistencia.png" width="48"><br>Colossobro | <img src="GymBros/Resources/Assets.xcassets/sprite_urso_ultimate_forca_agilidade.imageset/urso_ultimate_forca_agilidade.png" width="48"><br>Brutobro | <img src="GymBros/Resources/Assets.xcassets/sprite_urso_ultimate_forca_tecnica.imageset/urso_ultimate_forca_tecnica.png" width="48"><br>Gigantebro | <img src="GymBros/Resources/Assets.xcassets/sprite_urso_ultimate_resistencia_agilidade.imageset/urso_ultimate_resistencia_agilidade.png" width="48"><br>Nevascabro | <img src="GymBros/Resources/Assets.xcassets/sprite_urso_ultimate_resistencia_tecnica.imageset/urso_ultimate_resistencia_tecnica.png" width="48"><br>Polarbro | <img src="GymBros/Resources/Assets.xcassets/sprite_urso_ultimate_agilidade_tecnica.imageset/urso_ultimate_agilidade_tecnica.png" width="48"><br>Aurorabro |
| Rato | <img src="GymBros/Resources/Assets.xcassets/sprite_rato_ultimate_forca_resistencia.imageset/rato_ultimate_forca_resistencia.png" width="48"><br>Metrôbro | <img src="GymBros/Resources/Assets.xcassets/sprite_rato_ultimate_forca_agilidade.imageset/rato_ultimate_forca_agilidade.png" width="48"><br>Presabro | <img src="GymBros/Resources/Assets.xcassets/sprite_rato_ultimate_forca_tecnica.imageset/rato_ultimate_forca_tecnica.png" width="48"><br>Parmesãobro | <img src="GymBros/Resources/Assets.xcassets/sprite_rato_ultimate_resistencia_agilidade.imageset/rato_ultimate_resistencia_agilidade.png" width="48"><br>Ventaniabro | <img src="GymBros/Resources/Assets.xcassets/sprite_rato_ultimate_resistencia_tecnica.imageset/rato_ultimate_resistencia_tecnica.png" width="48"><br>Correntezabro | <img src="GymBros/Resources/Assets.xcassets/sprite_rato_ultimate_agilidade_tecnica.imageset/rato_ultimate_agilidade_tecnica.png" width="48"><br>Piãobro |
| Lobo | <img src="GymBros/Resources/Assets.xcassets/sprite_lobo_ultimate_forca_resistencia.imageset/lobo_ultimate_forca_resistencia.png" width="48"><br>Lobisombro | <img src="GymBros/Resources/Assets.xcassets/sprite_lobo_ultimate_forca_agilidade.imageset/lobo_ultimate_forca_agilidade.png" width="48"><br>Ragnarbro | <img src="GymBros/Resources/Assets.xcassets/sprite_lobo_ultimate_forca_tecnica.imageset/lobo_ultimate_forca_tecnica.png" width="48"><br>Cordilheirabro | <img src="GymBros/Resources/Assets.xcassets/sprite_lobo_ultimate_resistencia_agilidade.imageset/lobo_ultimate_resistencia_agilidade.png" width="48"><br>Vendavalbro | <img src="GymBros/Resources/Assets.xcassets/sprite_lobo_ultimate_resistencia_tecnica.imageset/lobo_ultimate_resistencia_tecnica.png" width="48"><br>Fiordebro | <img src="GymBros/Resources/Assets.xcassets/sprite_lobo_ultimate_agilidade_tecnica.imageset/lobo_ultimate_agilidade_tecnica.png" width="48"><br>Eclipsebro |
| Cachorro | <img src="GymBros/Resources/Assets.xcassets/sprite_cachorro_ultimate_forca_resistencia.imageset/cachorro_ultimate_forca_resistencia.png" width="48"><br>Cérberobro | <img src="GymBros/Resources/Assets.xcassets/sprite_cachorro_ultimate_forca_agilidade.imageset/cachorro_ultimate_forca_agilidade.png" width="48"><br>Dobermanbro | <img src="GymBros/Resources/Assets.xcassets/sprite_cachorro_ultimate_forca_tecnica.imageset/cachorro_ultimate_forca_tecnica.png" width="48"><br>Sãobernardobro | <img src="GymBros/Resources/Assets.xcassets/sprite_cachorro_ultimate_resistencia_agilidade.imageset/cachorro_ultimate_resistencia_agilidade.png" width="48"><br>Salukibro | <img src="GymBros/Resources/Assets.xcassets/sprite_cachorro_ultimate_resistencia_tecnica.imageset/cachorro_ultimate_resistencia_tecnica.png" width="48"><br>Terranovabro | <img src="GymBros/Resources/Assets.xcassets/sprite_cachorro_ultimate_agilidade_tecnica.imageset/cachorro_ultimate_agilidade_tecnica.png" width="48"><br>Borderbro |
| Esquilo | <img src="GymBros/Resources/Assets.xcassets/sprite_esquilo_ultimate_forca_resistencia.imageset/esquilo_ultimate_forca_resistencia.png" width="48"><br>Sequoiabro | <img src="GymBros/Resources/Assets.xcassets/sprite_esquilo_ultimate_forca_agilidade.imageset/esquilo_ultimate_forca_agilidade.png" width="48"><br>Espinheirobro | <img src="GymBros/Resources/Assets.xcassets/sprite_esquilo_ultimate_forca_tecnica.imageset/esquilo_ultimate_forca_tecnica.png" width="48"><br>Jequitibro | <img src="GymBros/Resources/Assets.xcassets/sprite_esquilo_ultimate_resistencia_agilidade.imageset/esquilo_ultimate_resistencia_agilidade.png" width="48"><br>Redemoinhobro | <img src="GymBros/Resources/Assets.xcassets/sprite_esquilo_ultimate_resistencia_tecnica.imageset/esquilo_ultimate_resistencia_tecnica.png" width="48"><br>Cascatabro | <img src="GymBros/Resources/Assets.xcassets/sprite_esquilo_ultimate_agilidade_tecnica.imageset/esquilo_ultimate_agilidade_tecnica.png" width="48"><br>Trapezistabro |
| Gato | <img src="GymBros/Resources/Assets.xcassets/sprite_gato_ultimate_forca_resistencia.imageset/gato_ultimate_forca_resistencia.png" width="48"><br>Tigrebro | <img src="GymBros/Resources/Assets.xcassets/sprite_gato_ultimate_forca_agilidade.imageset/gato_ultimate_forca_agilidade.png" width="48"><br>Smilodonbro | <img src="GymBros/Resources/Assets.xcassets/sprite_gato_ultimate_forca_tecnica.imageset/gato_ultimate_forca_tecnica.png" width="48"><br>Leãobro | <img src="GymBros/Resources/Assets.xcassets/sprite_gato_ultimate_resistencia_agilidade.imageset/gato_ultimate_resistencia_agilidade.png" width="48"><br>Guepardobro | <img src="GymBros/Resources/Assets.xcassets/sprite_gato_ultimate_resistencia_tecnica.imageset/gato_ultimate_resistencia_tecnica.png" width="48"><br>Onçabro | <img src="GymBros/Resources/Assets.xcassets/sprite_gato_ultimate_agilidade_tecnica.imageset/gato_ultimate_agilidade_tecnica.png" width="48"><br>Bastetbro |
| Coruja | <img src="GymBros/Resources/Assets.xcassets/sprite_coruja_ultimate_forca_resistencia.imageset/coruja_ultimate_forca_resistencia.png" width="48"><br>Grifobro | <img src="GymBros/Resources/Assets.xcassets/sprite_coruja_ultimate_forca_agilidade.imageset/coruja_ultimate_forca_agilidade.png" width="48"><br>Falcãobro | <img src="GymBros/Resources/Assets.xcassets/sprite_coruja_ultimate_forca_tecnica.imageset/coruja_ultimate_forca_tecnica.png" width="48"><br>Atenabro | <img src="GymBros/Resources/Assets.xcassets/sprite_coruja_ultimate_resistencia_agilidade.imageset/coruja_ultimate_resistencia_agilidade.png" width="48"><br>Ciclonebro | <img src="GymBros/Resources/Assets.xcassets/sprite_coruja_ultimate_resistencia_tecnica.imageset/coruja_ultimate_resistencia_tecnica.png" width="48"><br>Albatrozbro | <img src="GymBros/Resources/Assets.xcassets/sprite_coruja_ultimate_agilidade_tecnica.imageset/coruja_ultimate_agilidade_tecnica.png" width="48"><br>Fênixbro |
