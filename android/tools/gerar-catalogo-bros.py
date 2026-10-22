#!/usr/bin/env python3
"""Gera core/domain/.../BroCatalog.kt a partir do vetor R exportado pelo iOS (ios/GymBrosTests/Fixtures/gymbros-golden-R.json).
Nomes das formas e das espécies, espécie de cada tipo do Apple Saúde e o ícone de cada tipo de treino. Não editar o .kt à mão."""
import json, os

root = os.path.join(os.path.dirname(__file__), "..", "..")
d = json.load(open(os.path.join(root, "ios/GymBrosTests/Fixtures/gymbros-golden-R.json")))

def q(s): return json.dumps(s, ensure_ascii=False)

lines = ["package com.alonsoalmeida.gymbros.domain", "",
         "/**",
         " * Nomes das formas e espécies, espécie de cada tipo do Apple Saúde e ícone (SF Symbol) de cada tipo de treino.",
         " * Gerado por android/tools/gerar-catalogo-bros.py a partir de ios/GymBrosTests/Fixtures/gymbros-golden-R.json",
         " * (exportado de Game.swift, Viradas.swift, Hatch.swift e WorkoutCatalog.swift); não editar à mão.",
         " */",
         "object BroCatalog {"]
lines.append("    val speciesNames: Map<String, String> = linkedMapOf(")
lines += [f"        {q(s['id'])} to {q(s['name'])}," for s in d["species"]]
lines.append("    )")
# Listas por espécie para não estourar o limite de tamanho de método da JVM
by_species = {}
for f in d["forms"]:
    if f["stage"] == 0: continue
    sp = f["id"].split("/")[0] if "/" in f["id"] else "coelho"
    by_species.setdefault(sp, []).append((f["key"], f["name"]))
for sp, items in by_species.items():
    lines.append(f"    private fun names_{sp}(): Map<String, String> = hashMapOf(")
    lines += [f"        {q(k)} to {q(n)}," for k, n in items]
    lines.append("    )")
lines.append("    /** Nome de cada forma por espécie e chave (`champion_forca`, `ultimate_forca_to_tecnica`…) */")
lines.append("    val formNames: Map<String, Map<String, String>> by lazy {")
lines.append("        hashMapOf(" + ", ".join(f"{q(sp)} to names_{sp}()" for sp in by_species) + ")")
lines.append("    }")
lines.append("    /** Espécies candidatas de cada tipo do Apple Saúde (`HKWorkoutActivityType.rawValue`) */")
lines.append("    val healthSpecies: Map<Long, List<String>> = hashMapOf(")
lines += [f"        {k}L to listOf({', '.join(q(x) for x in v)})," for k, v in sorted(d["health"].items(), key=lambda kv: int(kv[0]))]
lines.append("    )")
lines.append("    val kindSpecies: Map<String, List<String>> = hashMapOf(")
lines += [f"        {q(k)} to listOf({', '.join(q(x) for x in v)})," for k, v in d["kindSpecies"].items()]
lines.append("    )")
lines.append("    /** Ícone do tipo de treino no iOS (SF Symbol); o app Android troca pelo equivalente do Material */")
lines.append("    val workoutSymbols: Map<Long, String> = hashMapOf(")
lines += [f"        {k}L to {q(v)}," for k, v in sorted(d["symbols"].items(), key=lambda kv: int(kv[0]))]
lines.append("    )")
lines.append("    /** Tipo de treino equivalente a cada categoria antiga (`WorkoutType.of(kind)`) */")
lines.append("    val classicType: Map<String, Long> = hashMapOf(")
lines += [f"        {q(k)} to {v}L," for k, v in d["classicType"].items()]
lines.append("    )")
lines.append("}")
out = os.path.join(root, "android/core/domain/src/main/kotlin/com/alonsoalmeida/gymbros/domain/BroCatalog.kt")
open(out, "w").write("\n".join(lines) + "\n")
print(out)
