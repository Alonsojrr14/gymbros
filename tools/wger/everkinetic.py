#!/usr/bin/env python3
"""Completa as fotos que faltam com as ilustrações do Everkinetic (github.com/everkinetic/data, CC BY-SA 4.0).

Uso (na raiz do repo, depois do build.py):
  git clone --depth 1 https://github.com/everkinetic/data.git "$TMPDIR/ek"
  python3 -I tools/wger/everkinetic.py "$TMPDIR/ek"
Usa dist/png e, para alguns exercícios, src/images-png-unknown (mesmos desenhos, sem cadastro).
"images-ai" no repo é o formato do Adobe Illustrator, não imagem gerada por IA.
"""
import json, os, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
JSON = os.path.join(ROOT, "GymMonsters", "wger.json")
ASSETS = os.path.join(ROOT, "GymMonsters", "Assets.xcassets", "Wger")
LICENSE = {"license": "CC BY-SA 4.0", "licenseURL": "https://creativecommons.org/licenses/by-sa/4.0/", "author": "Everkinetic"}
SOURCE = "https://github.com/everkinetic/data"

# Nosso exercício → exercício do Everkinetic
MAP = {
    "puxada-frente": "wide-grip-lat-pull-down", "rosca-concentrada": "concentration-curls-with-dumbbell",
    "stiff": "romanian-dead-lift", "terra-romeno": "romanian-dead-lift", "elevacao-pelvica": "bridging",
    "ponte-gluteo-barra": "bridging", "panturrilha-sentado": "seated-calf-raise-using-machine", "prancha-lateral": "side-plank",
    "abdominal-polia": "seated-ab-crunch-with-cable", "supino-aberto": "wide-grip-bench-press",
    "supino-declinado-halter": "decline-dumbbell-bench-press", "crucifixo-inclinado": "incline-dumbbell-flys",
    "supino-smith": "smith-machine-bench-press", "supino-inclinado-smith": "smith-machine-incline-bench-press",
    "flexao-aberta": "push-ups-close-and-wide-hand-versions", "pullover": "dumbbell-bent-arm-pullover",
    "desenvolvimento-arnold": "arnold-press", "desenvolvimento-sentado-barra": "seated-military-press",
    "cuban-press": "cuban-dumbbell-press", "rosca-inclinada": "alternating-incline-curl-with-dumbbell",
    "rosca-spider": "spider-curl-with-barbell", "rosca-zottman": "zottman-curl-with-dumbbells",
    "rosca-scott-maquina": "preacher-curl-with-machine", "rosca-arrastada": "drag-curl-with-barbell",
    "rosca-polia-alta": "high-cable-curls", "paralelas-triceps": "tricep-dips", "triceps-coice": "triceps-kickback-with-dumbbell",
    "triceps-inverso": "reverse-grip-triceps-pushdown", "triceps-barra-v": "triceps-pushdown-with-v-bar-and-cable",
    "triceps-deitado-halter": "lying-triceps-extension-with-dumbbells", "jm-press": "jm-press",
    "triceps-maquina": "triceps-extensions-using-machine", "mergulho-com-peso": "bench-dips", "afundo-barra": "barbell-lunges",
    "passada-barra": "walking-lunges", "subida-banco": "step-ups-with-dumbbells", "subida-banco-barra": "step-ups-with-barbell",
    "agachamento-box": "squat-to-bench-with-barbell", "agachamento-zercher": "zecher-squats",
    "agachamento-sumo-barra": "wide-stance-squat-with-barbell", "agachamento-sumo-halter": "pile-squat-with-dumbbell",
    "agachamento-halteres": "squats-using-dumbbells", "leg-press-fechado": "narrow-stance-leg-press",
    "extensora-unilateral": "leg-extensions", "sissy": "weighted-sissy-squat-with-weight-plate", "adutora-polia": "hip-adduction",
    "panturrilha-burrinho": "donkey-calf-raises", "panturrilha-halter": "standing-calf-raise-with-dumbbell",
    "tesoura": "flutter-kicks", "abdominal-declinado": "decline-crunch", "cf-overhead-squat": "overhead-squat-with-barbell",
}


# Ilustrações do repositório sem exercício cadastrado (src/images-png-unknown), identificadas uma a uma
UNKNOWN = {
    "cf-turkish": ["417a", "417c"], "rolo-punho": ["651a", "651b"], "cf-toes-to-bar": ["690a", "690b"],
    "cf-knees-to-elbows": ["690a", "690b"], "cf-kipping-pull-up": ["751a", "751b"], "barra-com-peso": ["751a", "751b"],
    "cf-push-jerk": ["767a", "767b"], "lenhador": ["949a", "949b"], "thruster": ["344b", "344c"],
}


def add_unknown(ek, out):
    added = 0
    for ours, frames in UNKNOWN.items():
        entry = out["exercises"].get(ours)
        if entry and entry["images"]:
            continue
        images = []
        for f in frames:
            src = os.path.join(ek, "src", "images-png-unknown", f + ".svg.png")
            if not os.path.exists(src): continue
            asset = f"ek_u{f}"
            folder = os.path.join(ASSETS, asset + ".imageset")
            os.makedirs(folder, exist_ok=True)
            dst = os.path.join(folder, asset + ".png")
            if not os.path.exists(dst):
                subprocess.run(["sips", "-Z", "480", src, "--out", dst], check=True, capture_output=True)
            json.dump({"images": [{"idiom": "universal", "filename": asset + ".png"}], "info": {"author": "xcode", "version": 1}},
                      open(os.path.join(folder, "Contents.json"), "w"))
            images.append({"asset": asset, "source": SOURCE, **LICENSE})
        if not images: continue
        if entry:
            entry["images"] = images
        else:
            out["exercises"][ours] = {"wger": 0, "url": SOURCE, "language": "en", "steps": [], "text": LICENSE,
                                      "images": images, "videos": []}
        added += 1
    return added


def main(ek):
    data = {x["name"]: x for x in json.load(open(os.path.join(ek, "exercises.json")))}
    out = json.load(open(JSON))
    added = 0
    for ours, name in MAP.items():
        x = data.get(name)
        entry = out["exercises"].get(ours)
        if not x or (entry and entry["images"]):
            continue
        images = []
        for i, frame in enumerate(["relaxation", "tension"]):
            src = os.path.join(ek, "dist", "png", f"{x['id_num']}-{frame}.png")
            if not os.path.exists(src): continue
            asset = f"ek_{x['id_num']}_{i}"
            folder = os.path.join(ASSETS, asset + ".imageset")
            os.makedirs(folder, exist_ok=True)
            dst = os.path.join(folder, asset + ".png")
            if not os.path.exists(dst):
                subprocess.run(["sips", "-Z", "480", src, "--out", dst], check=True, capture_output=True)
            json.dump({"images": [{"idiom": "universal", "filename": asset + ".png"}], "info": {"author": "xcode", "version": 1}},
                      open(os.path.join(folder, "Contents.json"), "w"))
            images.append({"asset": asset, "source": SOURCE, **LICENSE})
        if not images: continue
        if entry:
            entry["images"] = images
        else:
            out["exercises"][ours] = {"wger": 0, "url": SOURCE, "language": "en", "steps": x.get("steps", []),
                                      "text": LICENSE, "images": images, "videos": []}
        added += 1
    added += add_unknown(ek, out)
    json.dump(out, open(JSON, "w"), ensure_ascii=False, indent=1)
    print(f"{added} exercícios ganharam ilustração do Everkinetic")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.environ.get("TMPDIR", "/tmp"), "ek"))
