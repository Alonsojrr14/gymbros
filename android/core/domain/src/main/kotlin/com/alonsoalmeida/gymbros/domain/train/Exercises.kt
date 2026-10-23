package com.alonsoalmeida.gymbros.domain.train

import java.text.Normalizer

/** Grupos musculares (Exercises/Exercises.swift `MuscleGroup`); `raw` é o que a cópia da conta grava */
enum class MuscleGroup(val raw: String, val label: String) {
    PEITO("peito", "Peito"), COSTAS("costas", "Costas"), OMBROS("ombros", "Ombros"), BICEPS("biceps", "Bíceps"),
    TRICEPS("triceps", "Tríceps"), ANTEBRACO("antebraco", "Antebraço"), QUADRICEPS("quadriceps", "Quadríceps"),
    POSTERIOR("posterior", "Posterior"), GLUTEOS("gluteos", "Glúteos"), PANTURRILHA("panturrilha", "Panturrilha"),
    ABDOMEN("abdomen", "Abdômen"), CORPO("corpo", "Corpo todo");

    /** Grupos em que um salto de 5 kg é normal (com barra; ver `Exercise.increment`) */
    val heavy: Boolean get() = this in setOf(COSTAS, QUADRICEPS, POSTERIOR, GLUTEOS, PANTURRILHA)

    /** Músculos padrão, para exercícios personalizados */
    val muscles: MuscleTargets get() = when (this) {
        PEITO -> MuscleTargets(listOf(Muscle.CHEST), listOf(Muscle.DELTOIDS, Muscle.TRICEPS))
        COSTAS -> MuscleTargets(listOf(Muscle.UPPER_BACK), listOf(Muscle.BICEPS, Muscle.TRAPEZIUS))
        OMBROS -> MuscleTargets(listOf(Muscle.DELTOIDS), listOf(Muscle.TRAPEZIUS, Muscle.TRICEPS))
        BICEPS -> MuscleTargets(listOf(Muscle.BICEPS), listOf(Muscle.FOREARM))
        TRICEPS -> MuscleTargets(listOf(Muscle.TRICEPS), emptyList())
        ANTEBRACO -> MuscleTargets(listOf(Muscle.FOREARM), emptyList())
        QUADRICEPS -> MuscleTargets(listOf(Muscle.QUADRICEPS), listOf(Muscle.GLUTEAL, Muscle.HAMSTRING))
        POSTERIOR -> MuscleTargets(listOf(Muscle.HAMSTRING), listOf(Muscle.GLUTEAL, Muscle.LOWER_BACK))
        GLUTEOS -> MuscleTargets(listOf(Muscle.GLUTEAL), listOf(Muscle.HAMSTRING))
        PANTURRILHA -> MuscleTargets(listOf(Muscle.CALVES), emptyList())
        ABDOMEN -> MuscleTargets(listOf(Muscle.ABS), listOf(Muscle.OBLIQUES))
        CORPO -> MuscleTargets(listOf(Muscle.QUADRICEPS, Muscle.CHEST, Muscle.UPPER_BACK), listOf(Muscle.DELTOIDS, Muscle.GLUTEAL, Muscle.ABS))
    }

    /** SF Symbol do grupo (a tela troca pelo ícone Material) */
    val symbol: String get() = when (this) {
        PEITO, OMBROS, TRICEPS -> "figure.arms.open"
        COSTAS -> "figure.rower"
        BICEPS, ANTEBRACO -> "dumbbell.fill"
        QUADRICEPS, POSTERIOR, GLUTEOS, PANTURRILHA -> "figure.step.training"
        ABDOMEN -> "figure.core.training"
        CORPO -> "figure.cross.training"
    }

    companion object {
        fun of(raw: String): MuscleGroup? = entries.firstOrNull { it.raw == raw }
    }
}

/** Como a série é registrada (`ExerciseType`) */
enum class ExerciseType(val raw: String, val label: String) {
    /** Carga × repetições */
    WEIGHTED("weighted", "Carga × reps"),
    /** Peso do corpo: progride em repetições (carga extra opcional) */
    BODYWEIGHT("bodyweight", "Peso do corpo"),
    /** Medido em segundos (prancha, isometria) */
    TIME("time", "Por tempo"),
    /** Distância × tempo: `weight` guarda os metros e `reps` os segundos */
    DISTANCE("distance", "Distância × tempo");

    companion object {
        fun of(raw: String): ExerciseType? = entries.firstOrNull { it.raw == raw }
    }
}

/** Músculos do mapa (pacote MuscleMap do iOS), com o nome em português (MuscleViews.swift `ptName`) */
enum class Muscle(val label: String) {
    ABS("Abdômen"), BICEPS("Bíceps"), CALVES("Panturrilha"), CHEST("Peito"), DELTOIDS("Ombros"), FOREARM("Antebraço"),
    GLUTEAL("Glúteos"), HAMSTRING("Posterior de coxa"), LOWER_BACK("Lombar"), OBLIQUES("Oblíquos"), QUADRICEPS("Quadríceps"),
    TRAPEZIUS("Trapézio"), TRICEPS("Tríceps"), UPPER_BACK("Costas"), ADDUCTORS("Adutores"), NECK("Pescoço");

    companion object {
        /** Músculos que entram no mapa e na lista do que ficou sem treino */
        val tracked = listOf(TRAPEZIUS, DELTOIDS, CHEST, UPPER_BACK, BICEPS, TRICEPS, FOREARM, ABS, OBLIQUES, LOWER_BACK, GLUTEAL,
                             QUADRICEPS, HAMSTRING, ADDUCTORS, CALVES)
    }
}

data class MuscleTargets(val primary: List<Muscle>, val secondary: List<Muscle>)

/** Exercício da biblioteca ou personalizado (Exercises.swift `Exercise`) */
data class Exercise(
    val id: String,
    val name: String,
    val group: MuscleGroup,
    val equipment: String,
    val type: ExerciseType = ExerciseType.WEIGHTED,
    /** Movimento de CrossFit (seção própria da biblioteca) */
    val crossfit: Boolean = false,
) {
    /** Passo de carga: 5 kg só com barra em grupo pesado; máquina, polia e halteres sobem de 2,5 */
    val increment: Double get() = if (group.heavy && equipment == "Barra") 5.0 else 2.5
    val isCustom: Boolean get() = id.startsWith("custom-")
    val isCrossfit: Boolean get() = crossfit || id in Exercises.crossfitAlso
    /** Usa barra olímpica (polia e máquina não) */
    val usesBar: Boolean get() = equipment == "Barra"

    /** A carga anotada já inclui a barra? No treino de CrossFit, o total; na musculação, só as anilhas */
    fun weightIncludesBar(sessionIsCrossfit: Boolean? = null): Boolean = !usesBar || (sessionIsCrossfit ?: crossfit)

    /** Rótulo da carga na série */
    fun weightUnit(sessionIsCrossfit: Boolean? = null): String =
        if (usesBar) (if (weightIncludesBar(sessionIsCrossfit)) "kg total" else "kg anilhas") else "kg"

    val muscles: MuscleTargets get() = MUSCLES[id] ?: group.muscles
    /** Instruções em português da biblioteca original */
    val instructions: List<String> get() = INSTRUCTIONS[id].orEmpty()

    /** Busca no YouTube de como fazer o exercício */
    val videoQuery: String get() = "como fazer $name ${if (crossfit) "crossfit" else "exercício"}"
}

/** Exercício personalizado, como a cópia da conta guarda (`customExercises`) */
data class CustomExercise(val uuid: String, val name: String, val group: String, val equipment: String, val type: String, val notes: String) {
    val exerciseID: String get() = "custom-$uuid"
    val exercise: Exercise
        get() = Exercise(exerciseID, name, MuscleGroup.of(group) ?: MuscleGroup.CORPO, equipment, ExerciseType.of(type) ?: ExerciseType.WEIGHTED)
}

/**
 * Biblioteca embutida e os personalizados da conta. Os personalizados mudam com a cópia da conta: quem lê a conta chama
 * `register` (Exercise.register do iOS).
 */
object Exercises {
    val crossfitAlso = setOf("burpee", "thruster", "clean", "kettlebell-swing", "farmer-walk", "agachamento-frontal",
                             "levantamento-terra", "barra-fixa", "flexao", "agachamento-livre-corpo", "abdominal",
                             "desenvolvimento", "agachamento", "paralelas", "prancha")

    val equipments = listOf("Barra", "Halteres", "Máquina", "Polia", "Peso do corpo", "Kettlebell", "Elástico", "Corda", "Caixa", "Argola", "Bola", "Outro")

    /** Biblioteca completa embutida (original + extras + CrossFit + as que vieram só do wger) */
    val builtIn: List<Exercise> = LIBRARY + EXTRA
    private val index: Map<String, Exercise> = LinkedHashMap<String, Exercise>().apply { for (e in builtIn) putIfAbsent(e.id, e) }

    @Volatile var custom: Map<String, Exercise> = emptyMap()
        private set
    @Volatile var customNotes: Map<String, String> = emptyMap()
        private set

    fun register(list: List<CustomExercise>) {
        val c = LinkedHashMap<String, Exercise>()
        val n = LinkedHashMap<String, String>()
        for (e in list) { c.putIfAbsent(e.exerciseID, e.exercise); n.putIfAbsent(e.exerciseID, e.notes) }
        custom = c
        customNotes = n
    }

    /** Recém-criado: já vale antes de a cópia da conta voltar com ele */
    fun add(c: CustomExercise) {
        custom = custom + (c.exerciseID to c.exercise)
        customNotes = customNotes + (c.exerciseID to c.notes)
    }

    fun byID(id: String): Exercise? = index[id] ?: custom[id]

    val all: List<Exercise> get() = builtIn + custom.values.sortedBy { it.name }

    /** Nome para mostrar (apagado vira "Exercício personalizado") */
    fun name(id: String): String = byID(id)?.name ?: if (id.startsWith("custom-")) "Exercício personalizado" else id

    /** Busca sem acento e sem caixa (`localizedStandardContains`) */
    fun matches(e: Exercise, query: String): Boolean {
        if (query.isBlank()) return true
        val q = fold(query.trim())
        return fold(e.name).contains(q) || fold(e.group.label).contains(q) || fold(e.equipment).contains(q)
    }

    fun fold(s: String): String = Normalizer.normalize(s, Normalizer.Form.NFD).replace(Regex("\\p{M}"), "").lowercase()

    /** Ordem de `localizedStandardCompare` (sem acento, sem caixa) */
    val byName: Comparator<String> = Comparator { a, b -> fold(a).compareTo(fold(b)) }
}

/** Volume relativo por músculo: série feita conta 1 no principal e 0,5 nos secundários (MuscleViews.swift `muscleLoad`) */
fun muscleLoad(sets: List<SetLog>): Map<Muscle, Double> {
    val load = LinkedHashMap<Muscle, Double>()
    for (s in sets) {
        if (!s.done) continue
        val m = Exercises.byID(s.exerciseID)?.muscles ?: MuscleTargets(emptyList(), emptyList())
        for (p in m.primary) load[p] = (load[p] ?: 0.0) + 1
        for (x in m.secondary) load[x] = (load[x] ?: 0.0) + 0.5
    }
    return load
}

fun normalized(load: Map<Muscle, Double>): Map<Muscle, Double> {
    val top = load.values.maxOrNull() ?: 0.0
    if (top <= 0) return emptyMap()
    return load.mapValues { 0.25 + 0.75 * it.value / top }
}
