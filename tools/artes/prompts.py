#!/usr/bin/env python3
"""Monta os pedidos de arte das formas híbridas a partir do HIBRIDOS.md: grava .work/jobs.json
(prompt, referências e arquivo de saída de cada uma das 96). Uso: python3 tools/artes/prompts.py"""
import re, os, glob, json

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
ASSETS = f"{ROOT}/GymMonstersWidget/Assets.xcassets"
WORK = os.environ.get("ARTES_WORK", f"{HERE}/.work")
RAW = f"{WORK}/raw"

SPECIES = {"Coelho": "coelho", "Urso": "urso", "Rato": "rato", "Lobo": "lobo",
           "Cachorro": "cachorro", "Esquilo": "esquilo", "Gato": "gato", "Coruja": "coruja"}

STYLE = ("Original pixel art game sprite in the same style as the attached reference images: chunky pixels, "
         "thick dark outline, flat colors with one shade of shading, cute chibi proportions, front-facing full body, "
         "centered, single original character, plain flat light background, no text, no shadow on the ground, 1:1.")

CHAMP_COLOR = {"forca": "coral-red", "resistencia": "light-blue", "agilidade": "lime-green", "tecnica": "lavender"}
ULT_COLOR = {"forca": "deep crimson", "resistencia": "deep blue", "agilidade": "electric green", "tecnica": "deep purple"}
ATTR_EN = {"forca": "Strength", "resistencia": "Endurance", "agilidade": "Agility", "tecnica": "Technique"}

UPPER = {
    "forca": "broad shoulders, big bulky arms and a thick chest",
    "resistencia": "a lean, defined torso with slim toned arms",
    "agilidade": "light wiry arms and fur tufts on the shoulders swept back as if by speed",
    "tecnica": "an upright, perfectly balanced posture with calm, controlled arms",
}
LOWER = {
    "forca": "thick sturdy legs in a wide planted stance",
    "resistencia": "long lean runner legs with defined calves",
    "agilidade": "springy legs with big quick feet, light on the toes",
    "tecnica": "flexible legs in a precise, poised stance",
}
HEAD = {
    "forca": "a confident, tough grin",
    "resistencia": "steady, determined eyes",
    "agilidade": "ears (or head tufts/feathers) swept back like it is moving fast",
    "tecnica": "a small glowing diamond mark on the forehead",
}


def parse():
    md = open(f"{ROOT}/HIBRIDOS.md", encoding="utf-8").read()
    jobs, species = [], None
    for block in re.split(r"\n(?=#{1,3} )", md):
        h1 = re.match(r"# (\w+)\s*$", block.splitlines()[0])
        if h1 and h1.group(1) in SPECIES:
            species = SPECIES[h1.group(1)]
            continue
        m = re.match(r"### (Champion|Ultimate) .*?: (.+)\n`([\w.]+)`", block)
        if not (m and species):
            continue
        prompt = re.search(r"^> (.+)$", block, re.M).group(1).strip()
        fname = m.group(3)
        stage, a, b = re.search(r"(champion|ultimate)_(\w+?)_(\w+)\.png", fname).groups()
        jobs.append(dict(species=species, stage=stage, a=a, b=b, name=m.group(2), fname=fname, prompt=prompt))
    return jobs


def ref(species, key):
    pre = "" if species == "coelho" else f"{species}_"
    hits = glob.glob(f"{ASSETS}/sprite_{pre}{key}.imageset/*.png")
    assert hits, f"sem referência {pre}{key}"
    return hits[0]


def build(j):
    sp, a, b, ult = j["species"], j["a"], j["b"], j["stage"] == "ultimate"
    base = j["prompt"]
    if sp == "coelho":
        base = base.replace("cream-white fur, ", "")
    colors = ULT_COLOR if ult else CHAMP_COLOR
    ca, cb = colors[a], colors[b]
    animal = "bunny" if sp == "coelho" else {"urso": "bear", "rato": "rat", "lobo": "wolf", "cachorro": "dog",
                                              "esquilo": "squirrel", "gato": "cat", "coruja": "owl"}[sp]
    if ult:
        refs_txt = (f"Attached references: the FIRST image is the hybrid Champion this character evolves from (keep its "
                    f"identity, body mix and fur pattern, but evolved). The SECOND is the {animal}'s {ATTR_EN[a]} Ultimate and "
                    f"the THIRD is its {ATTR_EN[b]} Ultimate. Match their pixel art style and size exactly.")
    else:
        refs_txt = (f"Attached references: the FIRST image is the {animal}'s {ATTR_EN[a]} Champion and the SECOND is its "
                    f"{ATTR_EN[b]} Champion. This new character is literally a mix of those two: same species, both outfits "
                    f"and both bodies blended. Match their pixel art style and size exactly.")
    if sp == "coelho":
        src = "SECOND and THIRD" if ult else "FIRST and SECOND"
        fur = (f"TWO-TONE FUR (very important): this bunny's fur color changes with its training, so it has BOTH fur colors "
               f"of the {src} reference images: the head, ears and arms in the {ATTR_EN[a]} reference's fur color, and the torso, "
               f"legs and feet in the {ATTR_EN[b]} reference's fur color, blending with a pixel-dithered patchy transition "
               f"around the chest and belly. Inner ears and blush cheeks stay pink. It must clearly read as a two-color bunny.")
    else:
        fur = (f"FUR: keep the {animal}'s natural fur colors as the base, but the training is changing it: add {ca} "
               f"streaks and fur tips on the head and upper body, and {cb} streaks and fur tips on the legs and tail, "
               f"like the fur is being tinted by the two training styles. The species must stay obvious.")
    body = (f"BODY CHANGES (not just the outfit, the training is visibly reshaping the body): upper body with "
            f"{UPPER[a]}; lower body with {LOWER[b]}; head with {HEAD[a]} and {HEAD[b]}. The upper body clearly comes from "
            f"{ATTR_EN[a]} training and the legs clearly come from {ATTR_EN[b]} training.")
    if ult:
        body += " This is the final form: every body change is more extreme, mature and heroic than the Champion."
        aura = (f"AURA (MANDATORY, must be obvious at a glance): a big, bright glowing aura surrounding the whole body, made "
                f"of chunky pixel energy flames with a dark outline, {ca} on the left side swirling into {cb} on the right "
                f"side, with pixel sparkles around it. The aura is part of the sprite, close to the body, not a background.")
    else:
        aura = ""
    task = "Generate ONE image (square, 1:1) following this description exactly. Reply only with the image."
    return "\n\n".join(x for x in [task, refs_txt, STYLE, base, body, fur, aura,
                                    f"Keep the {animal} features clearly visible."] if x)


def refs(j):
    """Champion: os dois Champions da espécie. Ultimate: o Champion híbrido gerado + os dois Ultimates."""
    sp, a, b = j["species"], j["a"], j["b"]
    if j["stage"] == "ultimate":
        return [f"{RAW}/{j['fname'].replace('ultimate_', 'champion_')}", ref(sp, f"ultimate_{a}"), ref(sp, f"ultimate_{b}")]
    return [ref(sp, f"champion_{a}"), ref(sp, f"champion_{b}")]


if __name__ == "__main__":
    jobs = parse()
    assert len(jobs) == 96, len(jobs)
    os.makedirs(RAW, exist_ok=True)
    out = [dict(fname=j["fname"], stage=j["stage"], prompt=build(j), refs=refs(j), out=f"{RAW}/{j['fname']}") for j in jobs]
    json.dump(out, open(f"{WORK}/jobs.json", "w"), ensure_ascii=False, indent=1)
    print(f"{len(out)} pedidos, {sum(not os.path.exists(o['out']) for o in out)} sem arte em {RAW}")
