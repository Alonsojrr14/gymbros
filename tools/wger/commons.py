#!/usr/bin/env python3
"""Fotos e ilustrações do Wikimedia Commons para os exercícios que wger e Everkinetic não cobrem.

Cada arquivo foi escolhido à mão (corpo inteiro, sem rosto em destaque quando possível) e só entra com
licença domínio público, CC0, CC BY ou CC BY-SA; autor e licença vêm da página do arquivo no Commons.
Uso (na raiz do repo, depois do build.py e do everkinetic.py): python3 -I tools/wger/commons.py
"""
import json, os, re, subprocess, time, urllib.parse, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
JSON = os.path.join(ROOT, "GymMonsters", "wger.json")
ASSETS = os.path.join(ROOT, "GymMonsters", "Assets.xcassets", "Wger")
OK = re.compile(r"^(Public domain|CC0|CC BY(-SA)? [0-9.]+)$", re.I)

PICKS = {
    "puxada-frente": ["Wide grip lat pull down 1.svg", "Wide grip lat pull down 2.svg"],
    "remada-alta-maquina": ["Cable-upright-rows-1.png", "Cable-upright-rows-2.png"],
    "desenvolvimento-arnold": ["Arnold-press-1.png", "Arnold-press-2.png"],
    "cuban-press": ["Cuban-press-1.png", "Cuban-press-2.png"],
    "clean": ["Power Clean.png"], "cf-snatch": ["Squat snatch.jpg"], "cf-power-snatch": ["Power snatch.jpg"],
    "cf-hang-snatch": ["Hang Squat Snatch.png"], "cf-clean-jerk": ["Squat clean and jerk.jpg"],
    "cf-squat-clean": ["Squat clean.jpg"], "cf-hang-power-clean": ["Hang Power Clean.jpg"],
    "cf-split-jerk": ["Split jerk con barra.jpg"],
    "farmer-walk": [4], "agachamento-livre-corpo": [3], "elevacao-pernas": [0], "burpee": [4, 5],
    "flexao-inclinada": [1], "remada-curvada-halter": [2], "terra-hexagonal": [0], "terra-deficit": [1],
    "rosca-punho-inversa": [0, 1], "panturrilha-halter": [0], "panturrilha-smith": [0], "abdominal-completo": [1],
    "remo-ergometro": [1], "eliptico": [0], "escada": [1], "corda-naval": [0], "cf-kb-snatch": [2, 4],
    "cf-box-jump": [1], "cf-box-jump-over": [0], "cf-burpee-box": [0], "cf-chest-to-bar": [1],
    "cf-ring-muscle-up": [1], "cf-hspu": [2], "cf-handstand-walk": [4], "cf-rope-climb": [3], "cf-l-sit": [3],
    "cf-row-cal": [4], "cf-bike-cal": [2], "cf-ski-cal": [0], "cf-sled-push": [1], "cf-sandbag": [3],
    "cf-sledgehammer": [2],
}


def get(url):
    for i in range(5):
        try:
            return urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "GymBros-build/1.0 (exercise credits)"}), timeout=60).read()
        except Exception:
            time.sleep(8 * (i + 1))
    raise RuntimeError("falhou " + url)


def info(title):
    url = "https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode({
        "action": "query", "format": "json", "titles": "File:" + title, "prop": "imageinfo",
        "iiprop": "url|extmetadata", "iiurlwidth": 640})
    p = next(iter(json.loads(get(url))["query"]["pages"].values()))
    ii = p["imageinfo"][0]; m = ii.get("extmetadata", {})
    return {"title": p["title"], "page": ii["descriptionurl"], "thumb": ii["thumburl"].split("?")[0],
            "license": m.get("LicenseShortName", {}).get("value", ""), "licenseURL": m.get("LicenseUrl", {}).get("value", ""),
            "author": re.sub(r"<[^>]+>", "", m.get("Artist", {}).get("value", "")).strip()}


def main():
    meta = json.load(open(os.path.join(os.environ.get("TMPDIR", "/tmp"), "cm", "meta.json")))
    out = json.load(open(JSON))
    added = 0
    for ours, picks in PICKS.items():
        entry = out["exercises"].get(ours)
        if entry and entry["images"] and all(
                any(f != "Contents.json" and os.path.getsize(os.path.join(ASSETS, i["asset"] + ".imageset", f)) > 0
                    for f in os.listdir(os.path.join(ASSETS, i["asset"] + ".imageset")))
                for i in entry["images"] if os.path.isdir(os.path.join(ASSETS, i["asset"] + ".imageset"))):
            continue
        images = []
        for n, p in enumerate(picks):
            c = info(meta[ours][p]["title"][5:] if isinstance(p, int) else p)
            time.sleep(1.5)
            if not OK.match(c["license"].strip()):
                print("licença fora:", ours, c["title"], c["license"]); continue
            slug = re.sub(r"[^a-z0-9]+", "-", ours)
            asset = f"cm_{slug}_{n}"
            ext = "png" if c["thumb"].lower().endswith(".png") else "jpg"
            folder = os.path.join(ASSETS, asset + ".imageset")
            os.makedirs(folder, exist_ok=True)
            dst = os.path.join(folder, f"{asset}.{ext}")
            if not os.path.exists(dst) or os.path.getsize(dst) == 0:
                data = get(c["thumb"]); time.sleep(1)
                ext = "png" if data[:4] == b"\x89PNG" else "jpg"
                dst = os.path.join(folder, f"{asset}.{ext}")
                open(dst, "wb").write(data)
            json.dump({"images": [{"idiom": "universal", "filename": os.path.basename(dst)}], "info": {"author": "xcode", "version": 1}},
                      open(os.path.join(folder, "Contents.json"), "w"))
            author = (c["author"] or "Wikimedia Commons").replace("\n", " ")
            m = re.search(r"No machine-readable author provided\.\s*(\S+)\s+assum", author)
            author = m.group(1) if m else re.sub(r"\s*\(photos\s·\sphoto sets\)", "", author).replace(" photo by null", "")
            author = author if len(author) <= 60 else author[:57] + "…"
            lic = c["license"].replace("Public domain", "Domínio público")
            images.append({"asset": asset, "source": c["page"], "license": lic,
                           "licenseURL": c["licenseURL"] or c["page"], "author": author})
        if not images: continue
        if entry:
            entry["images"] = images
        else:
            out["exercises"][ours] = {"wger": 0, "url": images[0]["source"], "language": "en", "steps": [],
                                      "text": {k: images[0][k] for k in ("license", "licenseURL", "author")},
                                      "images": images, "videos": []}
        added += 1
        print("ok", ours, [i["license"] for i in images], flush=True)
        json.dump(out, open(JSON, "w"), ensure_ascii=False, indent=1)
    json.dump(out, open(JSON, "w"), ensure_ascii=False, indent=1)
    print(f"{added} exercícios com imagem do Commons")


if __name__ == "__main__":
    main()
