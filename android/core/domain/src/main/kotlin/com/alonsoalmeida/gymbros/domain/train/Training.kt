package com.alonsoalmeida.gymbros.domain.train

import java.time.Instant
import java.util.UUID

// Porte de Models/Training.swift: rotina, treino e séries, com as mesmas regras de superset, troca de exercício e
// atualização da rotina. Imutável: cada mudança devolve um treino novo (a tela grava na cópia da conta).

data class RoutineItem(val exerciseID: String, val sets: Int = 3, val reps: Int = 10, val rest: Int = 90, val order: Int = 0,
                       val supersetNext: Boolean = false)

data class Routine(val uuid: String, val name: String, val weekdaysRaw: String = "", val order: Int = 0, val items: List<RoutineItem> = emptyList()) {
    /** Dias da semana do Calendar do iOS (1 = domingo … 7 = sábado) */
    val weekdays: Set<Int> get() = weekdaysRaw.split(",").mapNotNull { it.trim().toIntOrNull() }.toSet()
    fun withWeekdays(days: Set<Int>) = copy(weekdaysRaw = days.sorted().joinToString(","))
    val sortedItems: List<RoutineItem> get() = items.sortedBy { it.order }
}

data class LoggedSet(
    val exerciseID: String,
    val exerciseOrder: Int,
    val index: Int,
    val weight: Double,
    val reps: Int,
    val targetReps: Int = reps,
    val rest: Int = 90,
    val done: Boolean = false,
    /** Série de aquecimento: não conta para progressão, recordes e volume */
    val warmup: Boolean = false,
    /** Identidade na tela (não vai para a cópia da conta) */
    val key: String = UUID.randomUUID().toString(),
)

data class Session(
    val uuid: String,
    val title: String,
    val routineUUID: String? = null,
    val start: Instant,
    /** null enquanto o treino está em andamento */
    val end: Instant? = null,
    val effort: Int = 6,
    val activityUUID: String? = null,
    val currentExerciseID: String? = null,
    val restEnd: Instant? = null,
    val restTotal: Int = 90,
    val gymUUID: String? = null,
    val placeAsked: Boolean = false,
    /** Exercícios ligados ao seguinte em superset (ids separados por vírgula) */
    val supersetRaw: String = "",
    val isDeload: Boolean = false,
    val sets: List<LoggedSet> = emptyList(),
) {
    val orderedSets: List<LoggedSet> get() = sets.sortedWith(compareBy({ it.exerciseOrder }, { it.index }))

    /** Exercícios na ordem do treino */
    val exerciseIDs: List<String> get() = orderedSets.map { it.exerciseID }.distinct()

    fun setsOf(id: String): List<LoggedSet> = orderedSets.filter { it.exerciseID == id }

    // Superset

    fun linkedNext(id: String): Boolean = supersetRaw.split(",").any { it == id }

    fun setLinkedNext(id: String, on: Boolean): Session {
        val s = supersetRaw.split(",").filter { it.isNotEmpty() }.toMutableSet()
        if (on) s += id else s -= id
        return copy(supersetRaw = s.sorted().joinToString(","))
    }

    /** Bloco de exercícios seguidos ligados em superset que contém `id` */
    fun group(id: String): List<String> {
        val ids = exerciseIDs
        var i = ids.indexOf(id)
        if (i < 0) return listOf(id)
        while (i > 0 && linkedNext(ids[i - 1])) i--
        val out = mutableListOf(ids[i])
        while (i < ids.size - 1 && linkedNext(ids[i])) { i++; out += ids[i] }
        return out
    }

    fun pending(id: String): Boolean = sets.any { it.exerciseID == id && !it.done }

    /** Depois de uma série de `id`: escolhe o exercício atual e diz se é hora de descansar */
    fun advance(after: String): Pair<Session, Boolean> {
        val members = group(after)
        val i = members.indexOf(after).coerceAtLeast(0)
        members.drop(i + 1).firstOrNull { pending(it) }?.let { return copy(currentExerciseID = it) to false }
        members.firstOrNull { pending(it) }?.let { return copy(currentExerciseID = it) to true }
        val ids = exerciseIDs
        val last = members.lastOrNull()
        val j = last?.let { ids.indexOf(it) } ?: -1
        if (j >= 0) {
            val next = (ids.drop(j + 1) + ids.take(j)).firstOrNull { pending(it) } ?: after
            return copy(currentExerciseID = next) to true
        }
        return this to true
    }

    /** Exercício "fazendo agora": o marcado, ou o primeiro com série a fazer (LiveWorkout.currentExercise) */
    val currentExercise: String?
        get() {
            val ids = exerciseIDs
            currentExerciseID?.let { if (it in ids) return it }
            return ids.firstOrNull { id -> !setsOf(id).all { it.done } } ?: ids.lastOrNull()
        }

    val log: SessionLog
        get() = SessionLog(start, orderedSets.filter { !it.warmup }.map { SetLog(it.exerciseID, it.weight, it.reps, it.targetReps, it.done) }, isDeload)

    /** Séries de trabalho (sem aquecimento) */
    val workSets: List<LoggedSet> get() = sets.filter { !it.warmup }
    val doneWorkSets: List<LoggedSet> get() = sets.filter { it.done && !it.warmup }
    /** Σ carga × reps das séries de trabalho feitas; distância fica fora */
    val volume: Double
        get() = doneWorkSets.filter { Exercises.byID(it.exerciseID)?.type != ExerciseType.DISTANCE }.sumOf { it.weight * it.reps }

    /** Treino de CrossFit: tem algum exercício da biblioteca de CrossFit */
    val isCrossfit: Boolean get() = sets.any { Exercises.byID(it.exerciseID)?.crossfit == true }

    fun updating(key: String, change: (LoggedSet) -> LoggedSet): Session = copy(sets = sets.map { if (it.key == key) change(it) else it })

    /** Passa as séries pendentes de `old` para `new` com a sugestão (Training.swift `swapPending`) */
    fun swapPending(old: String, new: String, s: Suggestion): Session {
        val pending = orderedSets.filter { it.exerciseID == old && !it.done }
        val work = pending.filter { !it.warmup }
        val allMoved = sets.none { it.exerciseID == old && it.done }
        val linked = linkedNext(old)
        val warmKeys = pending.filter { it.warmup }.map { it.key }.toSet()
        var list = sets.filter { it.key !in warmKeys }
        val workKeys = work.map { it.key }
        if (!allMoved && work.isNotEmpty()) {
            val order = work.first().exerciseOrder
            list = list.map { if (it.exerciseOrder > order) it.copy(exerciseOrder = it.exerciseOrder + 1) else it }
            list = list.map { if (it.key in workKeys) it.copy(exerciseOrder = order + 1) else it }
        }
        list = list.map { x ->
            val k = workKeys.indexOf(x.key)
            if (k < 0) x else x.copy(exerciseID = new, index = k, weight = s.weight, reps = s.reps, targetReps = s.reps)
        }
        var out = copy(sets = list)
        if (linked && work.isNotEmpty()) out = out.setLinkedNext(old, false).setLinkedNext(new, true)
        return out.copy(currentExerciseID = new)
    }

    /** Como o treino ficou: exercício, séries, reps alvo, descanso e superset */
    data class Plan(val id: String, val sets: Int, val reps: Int, val rest: Int, val superset: Boolean)

    fun plan(routine: Routine?): List<Plan> {
        val ids = exerciseIDs
        return ids.mapIndexedNotNull { i, id ->
            val work = orderedSets.filter { it.exerciseID == id && !it.warmup }
            val first = work.firstOrNull() ?: return@mapIndexedNotNull null
            // Com objetivo, as reps mudam a cada treino pela dupla progressão: não são mudança da rotina
            val reps = if (TrainingGoal.of(id) != null) routine?.items?.firstOrNull { it.exerciseID == id }?.reps ?: first.targetReps else first.targetReps
            Plan(id, work.size, reps, first.rest, linkedNext(id) && i < ids.size - 1)
        }
    }

    /** Diferenças entre o treino feito e a rotina, em frases */
    fun routineChanges(r: Routine): List<String> {
        val old = r.sortedItems.map { Plan(it.exerciseID, it.sets, it.reps, it.rest, it.supersetNext) }
        val new = plan(r)
        if (old == new) return emptyList()
        val out = mutableListOf<String>()
        val oldIDs = old.map { it.id }
        val newIDs = new.map { it.id }
        for (p in new) if (p.id !in oldIDs) out += "Entra ${Exercises.name(p.id)} (${p.sets}×${p.reps})"
        for (p in old) if (p.id !in newIDs) out += "Sai ${Exercises.name(p.id)}"
        if (oldIDs.filter { it in newIDs } != newIDs.filter { it in oldIDs }) out += "Nova ordem dos exercícios"
        for (p in new) {
            val o = old.firstOrNull { it.id == p.id } ?: continue
            val name = Exercises.name(p.id)
            if (o.sets != p.sets) out += "$name: ${o.sets} → ${p.sets} séries"
            if (o.reps != p.reps) out += "$name: ${o.reps} → ${p.reps} reps"
            if (o.rest != p.rest) out += "$name: descanso ${clock(o.rest)} → ${clock(p.rest)}"
            if (o.superset != p.superset) out += "$name: ${if (p.superset) "superset com o próximo" else "sai do superset"}"
        }
        return out.ifEmpty { listOf("Ajustes na estrutura do treino") }
    }

    /** Os itens da rotina como o treino ficou (cargas não entram) */
    fun applyTo(r: Routine): Routine =
        r.copy(items = plan(r).mapIndexed { i, p -> RoutineItem(p.id, p.sets, p.reps, p.rest, i, p.superset) })

    companion object {
        fun newID(): String = UUID.randomUUID().toString().uppercase()
    }
}

/** Texto de uma série (TrainView.swift `setText`) */
fun setText(s: LoggedSet): String = setText(s.exerciseID, s.weight, s.reps)

fun setText(exerciseID: String, weight: Double, reps: Int): String = when (Exercises.byID(exerciseID)?.type ?: ExerciseType.WEIGHTED) {
    ExerciseType.DISTANCE -> "${meters(weight)} em ${clock(reps)}"
    ExerciseType.TIME -> "$reps s" + if (weight > 0) " · ${Progression.fmt(weight)} kg" else ""
    ExerciseType.BODYWEIGHT -> if (weight == 0.0) "$reps reps" else "${Progression.fmt(weight)} kg × $reps"
    else -> "${Progression.fmt(weight)} kg × $reps"
}

/**
 * Começa um treino (de rotina ou livre) já com as cargas sugeridas pelo histórico (LiveWorkout.startSession).
 * `history`: treinos concluídos, do mais antigo ao mais novo.
 */
object WorkoutStart {
    fun session(routine: Routine?, history: List<SessionLog>, deload: Boolean, autoWarmup: Boolean, now: Instant, id: String = Session.newID()): Session {
        var session = Session(id, routine?.name ?: "Treino livre", routine?.uuid, now, isDeload = deload)
        val sets = mutableListOf<LoggedSet>()
        var warmedUp = false
        for ((i, item) in routine?.sortedItems.orEmpty().withIndex()) {
            var sug = Progression.suggest(item.exerciseID, item.sets, item.reps, history)
            var count = sug.sets ?: item.sets
            val ramp = sug.ramp
            if (deload) { val (s, c) = Deload.apply(sug, count, item.exerciseID); sug = s; count = c }
            var k = 0
            fun warm(w: Double, reps: Int) { sets += LoggedSet(item.exerciseID, i, k, w, reps, rest = 60, warmup = true); k++ }
            val ex = Exercises.byID(item.exerciseID)
            if (autoWarmup && !warmedUp && ex != null && ex.type == ExerciseType.WEIGHTED && sug.weight >= 20) {
                warmedUp = true
                for ((w, r) in Progression.warmup(sug.weight, ex.increment, if (ex.usesBar && ex.weightIncludesBar()) 20.0 else 0.0)) warm(w, r)
            } else {
                for ((w, r) in ramp) if (w < sug.weight) warm(w, r)
            }
            repeat(count) { sets += LoggedSet(item.exerciseID, i, k, sug.weight, sug.reps, rest = item.rest); k++ }
            if (item.supersetNext) session = session.setLinkedNext(item.exerciseID, true)
        }
        return session.copy(sets = sets)
    }

    /** Exercício adicionado no meio do treino (WorkoutView.add) */
    fun add(session: Session, ex: Exercise, history: List<SessionLog>): Session {
        val order = (session.sets.maxOfOrNull { it.exerciseOrder } ?: -1) + 1
        val reps = when (ex.type) { ExerciseType.TIME -> 30; ExerciseType.DISTANCE -> 300; else -> 10 }
        var s = Progression.suggest(ex.id, 3, reps, history)
        var count = 3
        if (session.isDeload) { val (a, b) = Deload.apply(s, 3, ex.id); s = a; count = b }
        val start = if (ex.type == ExerciseType.DISTANCE && s.weight == 0.0) 1000.0 else s.weight
        return session.copy(sets = session.sets + (0 until count).map { LoggedSet(ex.id, order, it, start, s.reps, rest = 90) })
    }

    /** Três séries leves antes da carga de trabalho (WorkoutView.addWarmup) */
    fun addWarmup(session: Session, ex: Exercise): Session {
        val sets = session.setsOf(ex.id)
        val first = sets.firstOrNull() ?: return session
        if (first.weight <= 0) return session
        val warm = Progression.warmup(first.weight, ex.increment, if (ex.usesBar && ex.weightIncludesBar(session.isCrossfit)) 20.0 else 0.0)
        val keys = sets.map { it.key }.toSet()
        val moved = session.sets.map { if (it.key in keys) it.copy(index = it.index + warm.size) else it }
        return session.copy(sets = moved + warm.mapIndexed { k, (w, r) -> LoggedSet(ex.id, first.exerciseOrder, k, w, r, rest = 60, warmup = true) })
    }

    fun removeWarmup(session: Session, id: String): Session {
        val keep = session.sets.filter { !(it.exerciseID == id && it.warmup) }
        val work = keep.filter { it.exerciseID == id }.sortedBy { it.index }.map { it.key }
        return session.copy(sets = keep.map { val k = work.indexOf(it.key); if (k >= 0) it.copy(index = k) else it })
    }

    fun removeExercise(session: Session, id: String): Session =
        session.copy(sets = session.sets.filter { it.exerciseID != id }).setLinkedNext(id, false)

    /** Tira uma série e renumera as que ficam (a última série leva o exercício junto) */
    fun removeSet(session: Session, key: String): Session {
        val s = session.sets.firstOrNull { it.key == key } ?: return session
        val rest = session.setsOf(s.exerciseID).filter { it.key != key }.map { it.key }
        var out = session.copy(sets = session.sets.filter { it.key != key }.map { val k = rest.indexOf(it.key); if (k >= 0) it.copy(index = k) else it })
        if (rest.isEmpty()) out = out.setLinkedNext(s.exerciseID, false)
        return out
    }

    fun duplicateSet(session: Session, key: String): Session {
        val sets = session.setsOf(session.sets.firstOrNull { it.key == key }?.exerciseID ?: return session)
        val pos = sets.indexOfFirst { it.key == key }
        val s = sets[pos]
        val after = sets.drop(pos + 1).map { it.key }.toSet()
        val moved = session.sets.map { if (it.key in after) it.copy(index = it.index + 1) else it }
        return session.copy(sets = moved + LoggedSet(s.exerciseID, s.exerciseOrder, s.index + 1, s.weight, s.targetReps, rest = s.rest, warmup = s.warmup))
    }

    /** "+ Série" no card do exercício */
    fun addSet(session: Session, id: String): Session {
        val sets = session.setsOf(id)
        val base = sets.lastOrNull()
        return session.copy(sets = session.sets + LoggedSet(id, base?.exerciseOrder ?: 0, sets.size, base?.weight ?: 0.0, base?.targetReps ?: 10,
                                                              rest = base?.rest ?: 90))
    }
}

/** Alternativas para o mesmo músculo (SwapExercise.swift `ranked`) */
object Swap {
    fun counts(history: List<SessionLog>): Map<String, Int> {
        val count = HashMap<String, Int>()
        for (s in history) for (id in s.sets.map { it.exerciseID }.toSet()) count[id] = (count[id] ?: 0) + 1
        return count
    }

    fun ranked(base: Exercise, candidates: List<Exercise>, exclude: Set<String>, history: List<SessionLog>): List<Exercise> {
        val count = counts(history)
        return candidates.filter { it.group == base.group && it.id != base.id && it.id !in exclude }
            .sortedWith { a, b ->
                val ca = count[a.id] ?: 0
                val cb = count[b.id] ?: 0
                if (ca != cb) return@sortedWith cb.compareTo(ca)
                val ea = a.equipment == base.equipment
                val eb = b.equipment == base.equipment
                if (ea != eb) return@sortedWith if (ea) -1 else 1
                Exercises.byName.compare(a.name, b.name)
            }
    }
}

/** Anilhas de cada lado (Profile/BodyTools.swift `Plates`) */
object Plates {
    val available = listOf(25.0, 20.0, 15.0, 10.0, 5.0, 2.5, 1.25)
    val bars = listOf(20.0, 15.0, 10.0, 0.0)

    /** Anilhas de cada lado para chegar no total; `rest` é o que não deu para montar */
    fun perSide(total: Double, bar: Double): Pair<List<Double>, Double> {
        var side = maxOf((total - bar) / 2, 0.0)
        val out = mutableListOf<Double>()
        for (p in available) while (side + 0.0001 >= p) { out += p; side -= p }
        return out to side * 2
    }
}
