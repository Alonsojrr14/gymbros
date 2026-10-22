#!/usr/bin/env python3
"""Monta a base de exercícios a partir do wger (wger.de), com licença e autor de cada item.

Uso: python3 -I tools/wger/build.py   (na raiz do repo)
Gera GymBros/Resources/wger.json e as imagens em GymBros/Resources/Assets.xcassets/Wger/.
Conteúdo do wger: CC-BY-SA 3/4 ou CC0, por item. Só entram imagens não geradas por IA.
"""
import html, json, os, re, sys, urllib.request

API = "https://wger.de/api/v2"
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_JSON = os.path.join(ROOT, "GymBros", "Resources", "wger.json")
OUT_ASSETS = os.path.join(ROOT, "GymBros", "Resources", "Assets.xcassets", "Wger")

# Nosso exercício → exercício do wger
MAP = {
    "supino-reto": 73, "supino-reto-halter": 75, "supino-inclinado": 538, "supino-inclinado-halter": 537,
    "supino-declinado": 185, "supino-maquina": 129, "crucifixo": 238, "peck-deck": 135, "crossover": 323,
    "flexao": 1551, "paralelas": 194, "barra-fixa": 475, "puxada-triangulo": 158, "remada-curvada": 83,
    "remada-unilateral": 81, "remada-baixa": 1117, "remada-cavalinho": 513, "remada-maquina": 1725,
    "pulldown": 1726, "levantamento-terra": 184, "hiperextensao": 301, "desenvolvimento": 566,
    "desenvolvimento-halter": 567, "desenvolvimento-maquina": 543, "elevacao-lateral": 348,
    "elevacao-lateral-polia": 1378, "elevacao-frontal": 256, "crucifixo-inverso": 487, "face-pull": 222,
    "encolhimento": 572, "encolhimento-barra": 571, "rosca-direta": 91, "rosca-alternada": 1012,
    "rosca-martelo": 272, "rosca-scott": 465, "rosca-polia": 95, "triceps-pulley": 1185, "triceps-corda": 1900,
    "triceps-testa": 246, "triceps-frances": 1336, "supino-fechado": 76, "mergulho-banco": 197, "rosca-punho": 51,
    "agachamento": 1801, "agachamento-frontal": 257, "agachamento-smith": 1747, "agachamento-goblet": 203,
    "hack": 375, "leg-press": 371, "cadeira-extensora": 369, "afundo": 984, "bulgaro": 1706, "terra-romeno": 507,
    "stiff-halteres": 1652, "mesa-flexora": 365, "cadeira-flexora": 366, "flexora-em-pe": 367, "good-morning": 1392,
    "elevacao-pelvica": 294, "cadeira-abdutora": 1748, "gluteo-polia": 1131, "cadeira-adutora": 12,
    "panturrilha-pe": 622, "panturrilha-sentado": 590, "panturrilha-leg": 146, "prancha": 458, "abdominal": 167,
    "abdominal-infra": 377, "elevacao-pernas": 979, "roda-abdominal": 1573, "kettlebell-swing": 960,
    "crucifixo-polia": 237, "crossover-baixo": 1296, "supino-inclinado-smith": 925, "supino-inclinado-maquina": 539,
    "flexao-declinada": 1112, "flexao-pliometrica": 1554, "pullover": 161, "supino-chao": 1084,
    "barra-supinada": 152, "puxada-fechada": 1136, "puxada-supinada": 1127, "remada-supinada": 84,
    "remada-unilateral-polia": 1621, "remada-invertida": 1198, "remada-banco-inclinado": 1283, "rack-pull": 484,
    "terra-sumo": 630, "pulldown-corda": 1634, "remada-alta": 693, "remada-alta-halter": 694,
    "crucifixo-inverso-polia": 822, "voador-inverso": 828, "desenvolvimento-smith": 916, "rosca-w": 94,
    "rosca-inversa": 1290, "rosca-martelo-corda": 275, "triceps-coice": 655, "triceps-deitado-halter": 245,
    "flexao-diamante": 1086, "afundo-barra": 46, "passada-barra": 802, "passada": 206, "subida-banco": 981,
    "agachamento-box": 977, "stiff-unilateral": 1736, "giro-russo": 1193, "pallof": 1194, "abdominal-obliquo": 576,
    "bike-ergometrica": 1618, "esteira": 1615, "cf-push-press": 478, "cf-devil-press": 1556, "cf-wall-ball": 1100,
    "cf-hspu": 282, "cf-pistol": 456, "cf-dumbbell-snatch": 1947, "rosca-scott-maquina": 584,
}

# Exercícios novos (só do wger): id, nome, grupo, equipamento, tipo, wger
NEW = [
    ("pike-push-up", "Flexão pike", "ombros", "Peso do corpo", "bodyweight", 454),
    ("hollow-hold", "Hollow hold", "abdomen", "Peso do corpo", "time", 297),
    ("bird-dog", "Bird dog", "abdomen", "Peso do corpo", "bodyweight", 1572),
    ("elevacao-joelhos-barra", "Elevação de joelhos na barra", "abdomen", "Peso do corpo", "bodyweight", 978),
    ("flexao-lateral-halter", "Flexão lateral com halter", "abdomen", "Halteres", "weighted", 1650),
    ("prancha-toque-ombro", "Prancha com toque no ombro", "abdomen", "Peso do corpo", "bodyweight", 1091),
    ("rosca-concentrada-polia", "Rosca concentrada na polia", "biceps", "Polia", "weighted", 1109),
    ("supino-hex", "Supino hex com halteres", "peito", "Halteres", "weighted", 1353),
    ("crucifixo-polia-sentado", "Crucifixo na polia sentado", "peito", "Polia", "weighted", 1922),
    ("flexao-com-peso", "Flexão com peso", "peito", "Peso do corpo", "weighted", 1902),
    ("terra-kettlebell", "Levantamento terra com kettlebell", "posterior", "Kettlebell", "weighted", 1003),
    ("terra-sumo-kettlebell", "Terra sumô com kettlebell", "gluteos", "Kettlebell", "weighted", 1612),
    ("elevacao-pelvica-halter", "Elevação pélvica com halter", "gluteos", "Halteres", "weighted", 1642),
    ("coice-gluteo-halter", "Coice de glúteo com halter", "gluteos", "Halteres", "weighted", 1616),
    ("ponte-gluteo", "Ponte de glúteo", "gluteos", "Peso do corpo", "bodyweight", 265),
    ("passada-lateral-elastico", "Passada lateral com elástico", "gluteos", "Outro", "bodyweight", 2618),
    ("coice-gluteo-elastico", "Coice de glúteo com elástico", "gluteos", "Outro", "bodyweight", 1613),
    ("polichinelo", "Polichinelo", "corpo", "Peso do corpo", "bodyweight", 320),
    ("skipping", "Skipping (joelho alto)", "corpo", "Peso do corpo", "bodyweight", 983),
    ("afundo-reverso", "Afundo reverso", "quadriceps", "Peso do corpo", "bodyweight", 999),
    ("afundo-reverso-halter", "Afundo reverso com halteres", "quadriceps", "Halteres", "weighted", 1651),
    ("afundo-smith", "Afundo no Smith", "quadriceps", "Máquina", "weighted", 1593),
    ("agachamento-pendular", "Agachamento pendular", "quadriceps", "Máquina", "weighted", 1521),
    ("agachamento-frontal-halter", "Agachamento frontal com halteres", "quadriceps", "Halteres", "weighted", 1640),
    ("agachamento-lateral", "Agachamento lateral", "quadriceps", "Halteres", "weighted", 1653),
    ("agachamento-isometrico", "Agachamento isométrico", "quadriceps", "Peso do corpo", "time", 1733),
    ("nordico-reverso", "Nórdico reverso", "quadriceps", "Peso do corpo", "bodyweight", 909),
    ("remada-renegada", "Remada na prancha (renegade row)", "costas", "Kettlebell", "weighted", 1022),
    ("pullover-polia", "Pullover na polia alta", "costas", "Polia", "weighted", 1137),
    ("elevacao-frontal-polia", "Elevação frontal na polia", "ombros", "Polia", "weighted", 1745),
    ("elevacao-lateral-maquina", "Elevação lateral na máquina", "ombros", "Máquina", "weighted", 1744),
    ("bus-driver", "Bus driver (volante com anilha)", "ombros", "Outro", "weighted", 915),
    ("desenvolvimento-unilateral", "Desenvolvimento unilateral com halter", "ombros", "Halteres", "weighted", 1968),
    ("clean-press", "Clean and press com barra", "corpo", "Barra", "weighted", 1901),
]

LICENSES = {1: ("CC BY-SA 3.0", "https://creativecommons.org/licenses/by-sa/3.0/"),
            2: ("CC BY-SA 4.0", "https://creativecommons.org/licenses/by-sa/4.0/"),
            3: ("CC0 1.0", "https://creativecommons.org/publicdomain/zero/1.0/"),
            4: ("CC BY 4.0", "https://creativecommons.org/licenses/by/4.0/"),
            5: ("ODbL", "https://opendatacommons.org/licenses/odbl/")}


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "GymBros-build/1.0 (exercise credits)"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def text(desc):
    """HTML do wger → parágrafos/itens em texto puro"""
    desc = re.sub(r"</(p|li)>", "\n", desc or "")
    desc = re.sub(r"<[^>]+>", "", desc)
    lines = [html.unescape(l).strip() for l in desc.split("\n")]
    return [l for l in lines if len(l) > 2]


def lic(obj):
    lid = obj["license"]["id"] if isinstance(obj["license"], dict) else obj["license"]
    name, url = LICENSES.get(lid, ("CC BY-SA 4.0", LICENSES[2][1]))
    return {"license": name, "licenseURL": url, "author": (obj.get("license_author") or "").strip() or "wger.de"}


def main():
    cache = os.path.join(os.environ.get("TMPDIR", "/tmp"), "wger", "ex.json")
    if os.path.exists(cache):
        data = json.load(open(cache))["results"]
    else:
        data = json.loads(get(f"{API}/exerciseinfo/?limit=1000"))["results"]
    by_id = {e["id"]: e for e in data}
    os.makedirs(OUT_ASSETS, exist_ok=True)
    json.dump({"info": {"author": "xcode", "version": 1}, "properties": {"provides-namespace": False}},
              open(os.path.join(OUT_ASSETS, "Contents.json"), "w"))

    wanted = dict(MAP)
    for n in NEW: wanted[n[0]] = n[5]
    out = {"source": "wger.de", "exercises": {}, "new": []}
    for ours, wid in sorted(wanted.items()):
        e = by_id.get(wid)
        if not e:
            print("faltou", ours, wid, file=sys.stderr); continue
        tr = {t["language"]: t for t in e["translations"]}
        t = tr.get(7) or tr.get(2)
        entry = {"wger": wid, "url": f"https://wger.de/exercise/{wid}/view/",
                 "language": "pt" if 7 in tr else "en", "steps": text(t["description"]), "text": lic(t),
                 "images": [], "videos": []}
        for img in sorted(e["images"], key=lambda i: not i["is_main"])[:2]:
            if img.get("is_ai_generated"): continue
            name = f"wger_{img['id']}"
            folder = os.path.join(OUT_ASSETS, name + ".imageset")
            os.makedirs(folder, exist_ok=True)
            ext = img["image"].rsplit(".", 1)[-1].lower()
            src = (img.get("thumbnails") or {}).get("medium") or img["image"]
            data = get(src)
            kind = "png" if data[:4] == b"\x89PNG" else "jpg" if data[:3] == b"\xff\xd8\xff" else ext
            file = f"{name}.{kind}"
            path = os.path.join(folder, file)
            if not os.path.exists(path):
                open(path, "wb").write(data)
            json.dump({"images": [{"idiom": "universal", "filename": file}], "info": {"author": "xcode", "version": 1}},
                      open(os.path.join(folder, "Contents.json"), "w"))
            entry["images"].append({"asset": name, "source": img["image"], **lic(img)})
        for v in e["videos"][:1]:
            entry["videos"].append({"url": v["video"], **lic(v)})
        out["exercises"][ours] = entry
    for n in NEW:
        if n[0] in out["exercises"]:
            out["new"].append({"id": n[0], "name": n[1], "group": n[2], "equipment": n[3], "type": n[4]})
    json.dump(out, open(OUT_JSON, "w"), ensure_ascii=False, indent=1)
    imgs = sum(len(x["images"]) for x in out["exercises"].values())
    vids = sum(len(x["videos"]) for x in out["exercises"].values())
    print(f"{len(out['exercises'])} exercícios, {len(out['new'])} novos, {imgs} imagens, {vids} vídeos")


if __name__ == "__main__":
    main()
