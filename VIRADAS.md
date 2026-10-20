# GymBros: prompts das Lendas de virada

Lenda de virada: o Atleta mudou de treino na fase Atleta (regra e nomes no `EVOLUCAO.md`). São 9 por Atleta, 90 por espécie, **720 artes**. Os nomes estão em `GymBros/Bros/Viradas.swift`.

Os prompts são montados por `tools/artes/viradas.py` a partir de um modelo, porque são muitos. Cada pedido leva:

- **Referências:** 1ª a Lenda pura do Atleta de origem (identidade, corpo, pelo e base da roupa); 2ª a Lenda pura do treino novo (equipamento, detalhes da roupa e cores). Ex.: Estivabro = Trebobro + Fôlegobro.
- **Conceito:** o nome da virada, de onde ele veio e para que treino mudou. O nome é um trocadilho em português e inspira o acessório principal, a pose e um detalhe da roupa.
- **Corpo:** o corpo do Atleta de origem, transformado pelo treino novo (pernas e rosto do atributo novo; numa dupla, tronco do 1º e pernas do 2º).
- **Pelo:** coelho com duas cores (cabeça e braços da origem, tronco e pernas do treino novo); as outras espécies mantêm o pelo e ganham mechas na cor do treino novo.
- **Aura:** só quando o treino novo é uma dupla (como as Lendas híbridas), nas duas cores dela.

**Arquivo:** `sprite_<espécie>_ultimate_<origem>_to_<saída>` (coelho sem prefixo), ex.: `ultimate_forca_to_resistencia.png`, `urso_ultimate_forca_to_forca_resistencia.png`. Sem a arte, o app mostra um espaço reservado no lugar da imagem.

Para ver o prompt completo de uma arte:

```sh
cd tools/artes && ARTES_WORK=.work-viradas python3 viradas.py
python3 -c "import json; print(next(j['prompt'] for j in json.load(open('.work-viradas/jobs.json')) if j['name'] == 'Estivabro'))"
```
