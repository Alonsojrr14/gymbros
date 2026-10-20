#!/usr/bin/env python3
"""Monta os pedidos de arte das 720 Lendas de virada (VIRADAS.md): grava <ARTES_WORK>/jobs.json.
Referências: a Lenda pura do Atleta de origem (identidade) e a Lenda pura do treino novo (o que mudou).
Uso: ARTES_WORK=.work-viradas python3 viradas.py"""
import re, os, json
from prompts import ROOT, STYLE, ATTR_EN, UPPER, LOWER, HEAD, ULT_COLOR, ref

WORK = os.environ.get("ARTES_WORK", os.path.join(os.path.dirname(os.path.abspath(__file__)), ".work-viradas"))
RAW = f"{WORK}/raw"
ANIMAL = {"coelho": "bunny", "urso": "bear", "rato": "rat", "lobo": "wolf", "cachorro": "dog",
          "esquilo": "squirrel", "gato": "cat", "coruja": "owl"}
TRAIN = {"forca": "heavy strength training (lifting weights)",
         "resistencia": "endurance training (long runs, rides and swims)",
         "agilidade": "agility training (sprints, jumps and quick footwork)",
         "tecnica": "technique training (yoga, balance and precise form)"}
A = list(ATTR_EN)


def names():
    swift = open(f"{ROOT}/GymBros/Bros/Game.swift", encoding="utf-8").read()
    pure = {"coelho": {}}
    std = re.search(r'static let standard = Species\((.*?)spritePrefix', swift, re.S).group(1)
    for k, v in re.findall(r'"(ultimate_\w+)": "([^"]+)"', std):
        pure["coelho"][k] = v
    hyb = re.findall(r'"([^"]+)"', re.search(r'zip\(hybridKeys, \[(.*?)\]\)', std, re.S).group(1))
    pairs = [f"{a}_{b}" for i, a in enumerate(A) for b in A[i + 1:]]
    for p, n in zip(pairs, hyb[6:]):
        pure["coelho"][f"ultimate_{p}"] = n
    for m in re.finditer(r'make\("(\w+)", "\w+", \[(.*?)\],\s*\[(.*?)\]\)', swift, re.S):
        n, h = re.findall(r'"([^"]+)"', m[2]), re.findall(r'"([^"]+)"', m[3])
        pure[m[1]] = {f"ultimate_{a}": n[6 + i] for i, a in enumerate(A)} | {f"ultimate_{p}": x for p, x in zip(pairs, h[6:])}
    vir = {}
    src = open(f"{ROOT}/GymBros/Bros/Viradas.swift", encoding="utf-8").read()
    for sp, body in re.findall(r'"(\w+)": \[(.*?)\]', src, re.S):
        vir[sp] = dict(re.findall(r'"(ultimate_\w+)": "([^"]+)"', body))
    return pure, vir


def split(branch):
    return branch.split("_")


def build(sp, key, name, pure):
    origin, outcome = key[len("ultimate_"):].split("_to_")
    o, n = split(origin), split(outcome)
    animal = ANIMAL[sp]
    oname, nname = pure[sp][f"ultimate_{origin}"], pure[sp][f"ultimate_{outcome}"]
    otrain = " mixed with ".join(TRAIN[x] for x in o)
    ntrain = " mixed with ".join(TRAIN[x] for x in n)
    refs_txt = (f"Attached references: the FIRST image is {oname}, the {animal}'s final form this character comes from: keep its "
                f"identity, body build, face, fur colors and pattern, and the base of its outfit. The SECOND image is {nname}, "
                f"another final form of the same {animal}, showing the training this character switched to: borrow its "
                f"gear, outfit details and colors. Match their pixel art style and size exactly.")
    concept = (f"It is a legend named {name}: a {animal} that became {oname} through {otrain}, and then spent its whole last "
               f"training phase doing {ntrain} instead. It is a new final form, not a copy of either reference: one "
               f"character whose old body is now visibly adapted to the new training. Its name is Portuguese (a pun ending in "
               f"'bro'): let the meaning of the name inspire its main prop, pose and one outfit detail.")
    new_body = (f"{UPPER[n[0]]} and {LOWER[n[-1]]}" if len(n) == 2 else f"{LOWER[n[0]]} and {HEAD[n[0]]}")
    body = (f"BODY: start from the FIRST reference's body ({UPPER[o[0]]}), then show the new training reshaping it: "
            f"{new_body}. Mature, heroic final-form proportions, as strong as the references.")
    colors = " and ".join(ULT_COLOR[x] for x in n)
    if sp == "coelho":
        fur = (f"FUR (very important): this bunny's fur color changes with its training. Keep the FIRST reference's fur "
               f"colors on the head, ears and arms, and change the torso, legs and feet to the SECOND reference's fur colors, "
               f"with a pixel-dithered patchy transition around the chest. Inner ears and blush cheeks stay pink.")
    else:
        fur = (f"FUR: keep the FIRST reference's fur colors as the base, with {colors} streaks and fur tips spreading "
               f"from the legs and tail, like the new training is tinting the fur. The species must stay obvious.")
    aura = ""
    if len(n) == 2:
        aura = (f"AURA (MANDATORY, must be obvious at a glance): a big, bright glowing aura surrounding the whole body, made "
                f"of chunky pixel energy flames with a dark outline, {ULT_COLOR[n[0]]} on the left side swirling into "
                f"{ULT_COLOR[n[1]]} on the right side, with pixel sparkles around it. The aura is part of the sprite, close "
                f"to the body, not a background.")
    task = "Generate ONE image (square, 1:1) following this description exactly. Reply only with the image."
    return "\n\n".join(x for x in [task, refs_txt, STYLE, concept, body, fur, aura,
                                    f"Keep the {animal} features clearly visible."] if x), [ref(sp, f"ultimate_{origin}"), ref(sp, f"ultimate_{outcome}")]


if __name__ == "__main__":
    pure, vir = names()
    os.makedirs(RAW, exist_ok=True)
    out = []
    for sp in ANIMAL:
        for key, name in vir[sp].items():
            prompt, refs = build(sp, key, name, pure)
            fname = (key if sp == "coelho" else f"{sp}_{key}") + ".png"
            out.append(dict(fname=fname, stage="ultimate", name=name, prompt=prompt, refs=refs, out=f"{RAW}/{fname}"))
    assert len(out) == 720, len(out)
    json.dump(out, open(f"{WORK}/jobs.json", "w"), ensure_ascii=False, indent=1)
    print(f"{len(out)} pedidos, {sum(not os.path.exists(o['out']) for o in out)} sem arte em {RAW}")
