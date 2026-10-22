#!/usr/bin/env python3
"""Gera pelo Codex CLI as artes que faltam em <ARTES_WORK>/jobs.json, do fim da lista para o começo
(o gerar.mjs vai do começo, então os dois não disputam a mesma arte). Para no limite de uso.
Uso: ARTES_WORK=.work-viradas python3 codex.py [paralelos]"""
import json, os, sys, subprocess, glob, time, shutil, threading
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.environ.get("ARTES_WORK", f"{HERE}/.work")
IMAGES = os.path.expanduser("~/.codex/generated_images")
MODEL = os.environ.get("CODEX_MODEL", "gpt-5.6-terra")
lock, stop = threading.Lock(), threading.Event()
queue = [j for j in json.load(open(f"{WORK}/jobs.json")) if not os.path.exists(j["out"])][::-1]


def log(*a):
    print(datetime.now().strftime("%H:%M:%S"), "[codex]", *a, flush=True)


def gen(j):
    t0 = time.time()
    cmd = ["codex", "exec", "--skip-git-repo-check", "-s", "read-only", "-m", MODEL]
    for r in j["refs"]:
        cmd += ["-i", r]
    p = subprocess.run(cmd + ["--", j["prompt"]], stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=900)
    out = p.stdout + p.stderr
    if any(k in out.lower() for k in ("usage limit", "rate limit", "quota", "limite")):
        return "limite"
    new = [f for f in glob.glob(f"{IMAGES}/*/*.png") if os.path.getmtime(f) >= t0 and f"/{session_of(out)}/" in f] if session_of(out) else []
    if not new:
        return "sem imagem"
    shutil.copy(max(new, key=os.path.getmtime), j["out"] + ".tmp")
    os.replace(j["out"] + ".tmp", j["out"])
    return "ok"


def session_of(out):
    for line in out.splitlines():
        if line.startswith("session id:"):
            return line.split(":", 1)[1].strip()
    return None


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
            if r in ("ok", "limite"):
                break
        log("ok" if r == "ok" else "FALHOU", j["fname"], "" if r == "ok" else r)
        if r == "limite":
            log("LIMITE do Codex, parando")
            stop.set()


log("fila", len(queue))
ts = [threading.Thread(target=worker) for _ in range(int(sys.argv[1]) if len(sys.argv) > 1 else 2)]
[t.start() for t in ts]
[t.join() for t in ts]
log("FIM", sum(os.path.exists(j["out"]) for j in json.load(open(f"{WORK}/jobs.json"))), "/", len(json.load(open(f"{WORK}/jobs.json"))))
