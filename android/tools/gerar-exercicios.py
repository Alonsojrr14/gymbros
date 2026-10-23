import json, re, sys, os
root = sys.argv[1]
ios = os.path.join(root, "ios/GymBros")
out = os.path.join(root, "android/core/domain/src/main/kotlin/com/alonsoalmeida/gymbros/domain/train/ExerciseData.kt")
def read(p): return open(os.path.join(ios, p), encoding="utf-8").read()
src = read("Exercises/Exercises.swift") + read("Exercises/ExerciseExtra.swift")
ex_re = re.compile(r'\.init\(id: "([^"]+)", name: "([^"]+)", group: \.(\w+), equipment: "([^"]+)"(?:, type: \.(\w+))?(?:, crossfit: (true))?\)')
lib_src = read("Exercises/Exercises.swift")
lib = [m.groups() for m in ex_re.finditer(lib_src)]
extra = [m.groups() for m in ex_re.finditer(read("Exercises/ExerciseExtra.swift"))]
w = json.load(open(os.path.join(ios, "Resources/wger.json"), encoding="utf-8"))
new = [(n["id"], n["name"], n["group"], n["equipment"], n["type"], None) for n in w["new"]]
def kstr(s): return '"' + s.replace('\\', '\\\\').replace('"', '\\"').replace('$', '\\$') + '"'
def ex(t):
    i, n, g, e, ty, cf = t
    return f'    E({kstr(i)}, {kstr(n)}, MuscleGroup.{g.upper()}, {kstr(e)}, ExerciseType.{(ty or "weighted").upper()}{", true" if cf else ""}),'
mus_re = re.compile(r'"([^"]+)": MuscleTargets\(primary: \[([^\]]*)\], secondary: \[([^\]]*)\]\)')
def ms(s): return ", ".join("Muscle." + re.sub(r'(?<!^)([A-Z])', r'_\1', x.strip()[1:]).upper() for x in s.split(",") if x.strip())
muscles = []
for f in ["Exercises/ExerciseMuscles.swift", "Exercises/ExerciseExtra.swift"]:
    for m in mus_re.finditer(read(f)):
        muscles.append(f'    {kstr(m.group(1))} to MuscleTargets(listOf({ms(m.group(2))}), listOf({ms(m.group(3))})),')
ins = read("Exercises/ExerciseInstructions.swift")
steps = []
for m in re.finditer(r'"([^"]+)": \[((?:\s*"(?:[^"\\]|\\.)*",?)+)\s*\]', ins):
    items = re.findall(r'"((?:[^"\\]|\\.)*)"', m.group(2))
    steps.append(f'    {kstr(m.group(1))} to listOf(' + ", ".join(kstr(x) for x in items) + '),')
k = ["package com.alonsoalmeida.gymbros.domain.train", "",
     "// GERADO de ios/GymBros/Exercises (Exercises.swift, ExerciseExtra.swift, ExerciseMuscles.swift, ExerciseInstructions.swift)",
     "// e de ios/GymBros/Resources/wger.json (`new`). Não edite à mão: rode o gerador da frente do treino.", "",
     "private typealias E = Exercise", "",
     "internal val LIBRARY: List<Exercise> = listOf("] + [ex(t) for t in lib] + [")", "",
     "internal val EXTRA: List<Exercise> = listOf("] + [ex(t) for t in extra] + [ex(t) for t in new] + [")", "",
     "internal val MUSCLES: Map<String, MuscleTargets> = mapOf("] + muscles + [")", "",
     "internal val INSTRUCTIONS: Map<String, List<String>> = mapOf("] + steps + [")", ""]
os.makedirs(os.path.dirname(out), exist_ok=True)
open(out, "w", encoding="utf-8").write("\n".join(k))
print(len(lib), len(extra), len(new), len(muscles), len(steps))
