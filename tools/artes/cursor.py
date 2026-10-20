#!/usr/bin/env python3
"""Gera pelo Cursor CLI (cursor-agent, ferramenta de imagem do agente) as artes que faltam em <ARTES_WORK>/jobs.json,
do fim da lista para o começo (o gerar.mjs vai do começo). Cada pedido roda numa pasta temporária com as
referências copiadas como ref1.png e ref2.png. Para no limite de uso.
Uso: ARTES_WORK=.work-viradas python3 cursor.py [paralelos]"""
import json, os, sys, subprocess, shutil, tempfile, threading
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.environ.get("ARTES_WORK", f"{HERE}/.work")
lock, stop = threading.Lock(), threading.Event()
queue = [j for j in json.load(open(f"{WORK}/jobs.json")) if not os.path.exists(j["out"])][::-1]


def log(*a):
    print(datetime.now().strftime("%H:%M:%S"), "[cursor]", *a, flush=True)


def gen(j):
    d = tempfile.mkdtemp(prefix="cursor-arte-")
    try:
        refs = []
        for i, r in enumerate(j["refs"], 1):
            shutil.copy(r, f"{d}/ref{i}.png")
            refs.append(f"ref{i}.png")
        p = (j["prompt"].replace("Attached references: the FIRST image", "Reference images in this folder: ref1.png (the FIRST image)")
             .replace("The SECOND image", "ref2.png (the SECOND image)").replace("the SECOND is", "ref2.png (the SECOND) is")
             .replace("the THIRD is", "ref3.png (the THIRD) is"))
        task = (f"Use your image generation tool, passing {' and '.join(refs)} as reference images, to create the image "
                f"described below. Save the result as out.png in this folder. Do not write code to draw it.\n\n{p}")
        r = subprocess.run(["cursor-agent", "-p", "--force", "--output-format", "text", task], cwd=d,
                           stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=900)
        out = (r.stdout + r.stderr).lower()
        if os.path.exists(f"{d}/out.png"):
            shutil.copy(f"{d}/out.png", j["out"] + ".tmp")
            os.replace(j["out"] + ".tmp", j["out"])
            return "ok"
        if any(k in out for k in ("usage limit", "rate limit", "quota", "upgrade", "out of", "spend limit")):
            return "limite: " + out[-200:].replace("\n", " ")
        return "sem imagem: " + out[-200:].replace("\n", " ")
    finally:
        shutil.rmtree(d, ignore_errors=True)


def worker():
    while not stop.is_set():
        with lock:
            j = next((x for x in queue if not os.path.exists(x["out"])), None)
            if j is None:
                return
            queue.remove(j)
        r = "erro"
        for _ in range(2):
            try:
                r = gen(j)
            except Exception as e:
                r = f"erro {e}"[:120]
            if r == "ok" or r.startswith("limite"):
                break
        log("ok" if r == "ok" else "FALHOU", j["fname"], "" if r == "ok" else r)
        if r.startswith("limite"):
            log("LIMITE do Cursor, parando")
            stop.set()


log("fila", len(queue))
ts = [threading.Thread(target=worker) for _ in range(int(sys.argv[1]) if len(sys.argv) > 1 else 2)]
[t.start() for t in ts]
[t.join() for t in ts]
jobs = json.load(open(f"{WORK}/jobs.json"))
log("FIM", sum(os.path.exists(j["out"]) for j in jobs), "/", len(jobs))
