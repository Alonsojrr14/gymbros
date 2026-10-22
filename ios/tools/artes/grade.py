#!/usr/bin/env python3
"""Lendas de virada em grade 3×3: uma imagem por Atleta com as 9 viradas dele (mesmas referências, menos gerações).

  python3 grade.py montar [N]   → .work-grades/jobs.json com as grades dos Atletas que ainda têm virada sem arte
  python3 grade.py cortar       → corta cada grade gerada em 9 e põe em .work-viradas/raw (só as que faltam)

Depois: ARTES_WORK=.work-grades node gerar.mjs 1 e ARTES_WORK=.work-viradas ./instalar.sh"""
import json, os, subprocess, sys
from prompts import STYLE, ATTR_EN, ULT_COLOR, ref
from viradas import ANIMAL, A, names

HERE = os.path.dirname(os.path.abspath(__file__))
GRID = f"{HERE}/.work-grades"
CELLS = f"{HERE}/.work-viradas/raw"

GEAR = {"forca": "heavy lifting gear (barbell, dumbbells, belt) and bulkier arms",
        "resistencia": "running gear (sneakers, race bib, sweatband) and lean runner legs",
        "agilidade": "sprint and jump gear, springy legs and fur swept back by speed",
        "tecnica": "martial arts / yoga clothes, calm poised stance and a small glowing forehead mark"}
ORDER = [[a] for a in A] + [[a, b] for i, a in enumerate(A) for b in A[i + 1:]]


def cell_name(sp, origin, outcome):
    key = f"ultimate_{'_'.join(origin)}_to_{'_'.join(outcome)}"
    return (key if sp == "coelho" else f"{sp}_{key}") + ".png"


def build(limit=None):
    pure, vir = names()
    jobs = []
    for sp in ANIMAL:
        for origin in ORDER:
            outs = [o for o in ORDER if o != origin]
            cells = [cell_name(sp, origin, o) for o in outs]
            if all(os.path.exists(f"{CELLS}/{c}") for c in cells):
                continue
            animal = ANIMAL[sp]
            oname = pure[sp][f"ultimate_{'_'.join(origin)}"]
            lines = []
            for i, o in enumerate(outs, 1):
                name = vir[sp][f"ultimate_{'_'.join(origin)}_to_{'_'.join(o)}"]
                gear = " plus ".join(GEAR[x] for x in o)
                aura = f"; a two-color glowing pixel aura ({ULT_COLOR[o[0]]} and {ULT_COLOR[o[1]]})" if len(o) == 2 else "; no aura"
                fur = ("; fur colors blend the original with the new training's colors" if sp == "coelho"
                       else f"; {' and '.join(ULT_COLOR[x] for x in o)} streaks on the fur tips")
                lines.append(f"{i}. {name}: now trains {' + '.join(ATTR_EN[x] for x in o)}: {gear}{aura}{fur}.")
            prompt = "\n\n".join([
                "Generate ONE image (square, 1:1) following this description exactly. Reply only with the image.",
                f"It is a sprite sheet for {oname}: a 3x3 grid with 9 separate characters, one centered in each cell, "
                f"same size in every cell, plain flat light background, generous empty space between cells, no grid lines, "
                f"no text, no labels, no numbers.",
                f"Attached references: the FIRST image is {oname}, the {animal}'s final form that all 9 characters come from: "
                f"keep its identity, face, body build and fur pattern in every cell. The other images are the {animal}'s "
                f"Strength, Endurance, Agility and Technique final forms: borrow gear and colors from them.",
                STYLE.replace("centered, single original character, ", "").replace(", 1:1.", "."),
                "Each cell is a different evolved legend: the same character after switching its training. "
                "Row by row, left to right:\n" + "\n".join(lines),
                f"Every character: one per cell, full body, front-facing, mature heroic final-form proportions. "
                f"Keep the {animal} features clearly visible in all 9.",
            ])
            refs = [ref(sp, f"ultimate_{'_'.join(origin)}")] + [ref(sp, f"ultimate_{a}") for a in A if [a] != origin]
            fname = f"grade_{sp}_{'_'.join(origin)}.png"
            jobs.append(dict(fname=fname, stage="ultimate", prompt=prompt, refs=refs, out=f"{GRID}/raw/{fname}", cells=cells))
    if limit:
        jobs = jobs[:limit]
    os.makedirs(f"{GRID}/raw", exist_ok=True)
    json.dump(jobs, open(f"{GRID}/jobs.json", "w"), ensure_ascii=False, indent=1)
    print(f"{len(jobs)} grades ({sum(not os.path.exists(f'{CELLS}/{c}') for j in jobs for c in j['cells'])} viradas sem arte)")


def size(path):
    out = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", path], capture_output=True, text=True).stdout
    vals = [int(l.split(":")[1]) for l in out.splitlines() if "pixel" in l]
    return vals[0], vals[1]


def cut():
    jobs = json.load(open(f"{GRID}/jobs.json"))
    done = 0
    for j in jobs:
        if not os.path.exists(j["out"]):
            continue
        w, h = size(j["out"])
        cw, ch = w // 3, h // 3
        for i, c in enumerate(j["cells"]):
            dest = f"{CELLS}/{c}"
            if os.path.exists(dest):
                continue
            x, y = (i % 3) * cw, (i // 3) * ch
            subprocess.run(["sips", "-c", str(ch), str(cw), "--cropOffset", str(y), str(x), j["out"], "--out", dest],
                           capture_output=True)
            done += 1
    print(f"{done} viradas cortadas para {CELLS}")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "montar"
    if cmd == "cortar":
        cut()
    else:
        build(int(sys.argv[2]) if len(sys.argv) > 2 else None)
