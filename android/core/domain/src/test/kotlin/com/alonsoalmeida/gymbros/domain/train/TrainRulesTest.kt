package com.alonsoalmeida.gymbros.domain.train

import com.alonsoalmeida.gymbros.domain.ActivityKind
import com.alonsoalmeida.gymbros.domain.Attribute
import com.alonsoalmeida.gymbros.domain.AttributeSplit
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.time.Instant
import java.time.LocalDate

/** Porte dos testes do iOS: ProgressionTests, WodImportTests, WodFormatsTests e AttributeSplitTests (mesmos casos e números) */
class ProgressionTest {
    private val now = Instant.ofEpochSecond(1_800_000_000)
    private fun session(id: String, weight: Double, reps: List<Int>, target: Int, daysAgo: Int = 1, deload: Boolean = false) =
        SessionLog(now.minusSeconds(daysAgo * 86_400L), reps.map { SetLog(id, weight, it, target, true) }, deload)

    @AfterEach fun reset() { TrainingGoal.goals = emptyMap(); PRBook.manual = emptyMap() }

    @Test fun firstTimeWithoutHistorySuggestsNoLoad() {
        val s = Progression.suggest("supino-reto", 3, 10, emptyList())
        assertEquals(0.0, s.weight); assertEquals(10, s.reps)
    }

    @Test fun completingAllSetsAddsIncrement() {
        assertEquals(62.5, Progression.suggest("supino-reto", 3, 10, listOf(session("supino-reto", 60.0, listOf(10, 10, 10), 10))).weight)
        assertEquals(105.0, Progression.suggest("agachamento", 3, 8, listOf(session("agachamento", 100.0, listOf(8, 8, 8), 8))).weight)
    }

    @Test fun missingRepsKeepsLoad() {
        val s = Progression.suggest("supino-reto", 3, 10, listOf(session("supino-reto", 60.0, listOf(10, 10, 7), 10)))
        assertEquals(60.0, s.weight); assertEquals(10, s.reps)
    }

    @Test fun threeMissesInARowDeloadsTenPercent() {
        val h = (3 downTo 1).map { session("agachamento", 100.0, listOf(8, 8, 6), 8, it * 2) }
        assertEquals(90.0, Progression.suggest("agachamento", 3, 8, h).weight)
    }

    @Test fun higherTargetKeepsLoad() {
        val s = Progression.suggest("supino-reto", 3, 10, listOf(session("supino-reto", 60.0, listOf(8, 8, 8), 8)))
        assertEquals(60.0, s.weight); assertEquals(10, s.reps)
    }

    @Test fun bodyweightAndTimeProgressByRepsAndSeconds() {
        assertEquals(13, Progression.suggest("flexao", 3, 12, listOf(session("flexao", 0.0, listOf(12, 12, 12), 12))).reps)
        assertEquals(50, Progression.suggest("prancha", 3, 45, listOf(session("prancha", 0.0, listOf(45, 45, 45), 45))).reps)
    }

    @Test fun goalStartsAtBottomOfRangeAndDoubleProgression() {
        TrainingGoal.goals = TrainingGoal.decode(TrainingGoal.encode(mapOf("supino-reto" to "hipertrofia")))
        assertEquals(TrainingGoal.HIPERTROFIA, TrainingGoal.of("supino-reto"))
        assertEquals(8, Progression.suggest("supino-reto", 3, 10, emptyList()).reps)
        val a = Progression.suggest("supino-reto", 3, 9, listOf(session("supino-reto", 40.0, listOf(9, 9, 9), 9)))
        assertEquals(40.0, a.weight); assertEquals(10, a.reps)
        val b = Progression.suggest("supino-reto", 3, 12, listOf(session("supino-reto", 40.0, listOf(12, 12, 12), 12)))
        assertEquals(42.5, b.weight); assertEquals(8, b.reps)
        val c = Progression.suggest("supino-reto", 3, 10, listOf(session("supino-reto", 40.0, listOf(10, 10, 8), 10)))
        assertEquals(40.0, c.weight); assertEquals(10, c.reps)
    }

    @Test fun firstTimeUsesManualPR() {
        PRBook.manual = mapOf("agachamento" to listOf(SetLog("agachamento", 100.0, 5, 5, true)))
        val s = Progression.suggest("agachamento", 3, 10, emptyList())
        assertEquals(80.0, s.weight)
        assertTrue(s.reason.contains("PR"))
    }

    @Test fun deloadSessionsDoNotCountAsReference() {
        val h = listOf(session("supino-reto", 60.0, listOf(10, 10, 10), 10, 8), session("supino-reto", 42.5, listOf(10, 10), 10, 1, deload = true))
        assertEquals(62.5, Progression.suggest("supino-reto", 3, 10, h).weight)
    }

    @Test fun warmupIsLighterThanWorkAndRespectsBar() {
        val w = Progression.warmup(100.0, 5.0, 20.0)
        assertEquals(listOf(40.0, 60.0, 80.0), w.map { it.first })
        assertEquals(listOf(10, 6, 3), w.map { it.second })
        assertTrue(Progression.warmup(20.0, 2.5, 20.0).isEmpty())
        assertTrue(Progression.warmup(0.0, 2.5).isEmpty())
    }

    @Test fun oneRMEpley() {
        assertEquals(100.0, Progression.oneRM(100.0, 1))
        assertEquals(120.0, Progression.oneRM(90.0, 10)!!, 0.01)
        assertNull(Progression.oneRM(50.0, 15))
        assertNull(Progression.oneRM(0.0, 5))
    }

    @Test fun recordsDetectHeavierLoad() {
        val before = listOf(session("supino-reto", 60.0, listOf(10, 10), 10, 5))
        assertFalse(Progression.records(session("supino-reto", 65.0, listOf(8, 8), 8, 0), before).isEmpty())
        assertTrue(Progression.records(session("supino-reto", 60.0, listOf(10, 10), 10, 0), before).isEmpty())
    }

    @Test fun fiveKiloStepOnlyForBarbellInHeavyGroups() {
        assertEquals(5.0, Exercises.byID("agachamento")?.increment)
        assertEquals(5.0, Exercises.byID("levantamento-terra")?.increment)
        for (id in listOf("cadeira-extensora", "leg-press", "remada-baixa", "remada-unilateral", "supino-reto")) assertEquals(2.5, Exercises.byID(id)?.increment)
    }

    @Test fun formatKeepsQuarterKiloPlates() {
        assertEquals("1,25", Progression.fmt(1.25)); assertEquals("2,5", Progression.fmt(2.5)); assertEquals("82,5", Progression.fmt(82.5))
        assertEquals("20", Progression.fmt(20.0)); assertEquals("116,7", Progression.fmt(116.6667))
    }

    @Test fun repCalculatorRoundsToExerciseIncrement() {
        val fine = Progression.repTable(100.0, 2.5).toMap()
        val coarse = Progression.repTable(100.0, 5.0).toMap()
        assertEquals(85.0, fine[5]); assertEquals(85.0, coarse[5]); assertEquals(72.5, fine[12]); assertEquals(70.0, coarse[12])
    }

    @Test fun bestMarkDoesNotMixOneRMWithRawLoad() {
        val high = SetLog("supino-reto", 60.0, 15, 15, true)
        val low = SetLog("supino-reto", 70.0, 5, 5, true)
        assertEquals(15, PRBook.best(listOf(low, high))?.reps)
        assertTrue(PRBook.beats(high, low)); assertFalse(PRBook.beats(low, high)); assertFalse(PRBook.beats(low, low))
    }

    @Test fun autoFinishEffortIsAverageOfRecentWorkouts() {
        assertEquals(7, Progression.estimatedEffort(emptyList()))
        assertEquals(7, Progression.estimatedEffort(listOf(8, 6, 7)))
        assertEquals(10, Progression.estimatedEffort(listOf(10, 10, 9)))
        assertEquals(9, Progression.estimatedEffort(List(5) { 2 } + List(10) { 9 }))
    }

    @Test fun deloadAppliesToAnyPrescription() {
        val (s, sets) = Deload.apply(Suggestion(100.0, 10, ""), 3, "supino-reto")
        assertEquals(70.0, s.weight); assertEquals(10, s.reps); assertEquals(2, sets)
        assertEquals(75.0, Deload.apply(Suggestion(105.0, 5, ""), 1, "agachamento").first.weight)
    }

    @Test fun customExerciseNameResolves() {
        Exercises.register(listOf(CustomExercise("TESTE", "Remada no cabo da academia", "costas", "Polia", "weighted", "")))
        assertEquals("Remada no cabo da academia", Exercises.name("custom-TESTE"))
        assertEquals("Exercício personalizado", Exercises.name("custom-APAGADO"))
        assertEquals("Supino reto", Exercises.name("supino-reto"))
        Exercises.register(emptyList())
    }

    @Test fun swapAlternativesPutSameEquipmentFirst() {
        val base = Exercises.byID("supino-reto")!!
        val list = Swap.ranked(base, Exercises.builtIn, emptySet(), emptyList())
        assertFalse(list.isEmpty())
        assertTrue(list.none { it.id == base.id } && list.all { it.group == MuscleGroup.PEITO })
        val firstOther = list.indexOfFirst { it.equipment != "Barra" }.let { if (it < 0) list.size else it }
        assertTrue(list.take(firstOther).all { it.equipment == "Barra" })
        assertTrue(list.drop(firstOther).none { it.equipment == "Barra" })
        assertEquals("crucifixo", Swap.ranked(base, Exercises.builtIn, emptySet(), listOf(session("crucifixo", 14.0, listOf(12), 12))).first().id)
    }

    private fun ramped(pairs: List<Pair<Double, Int>>, target: Int = 10) =
        SessionLog(now.minusSeconds(86_400), pairs.map { SetLog("agachamento", it.first, it.second, target, true) })

    @Test fun manualRampIsNotWork() {
        val s = Progression.suggest("agachamento", 4, 8, listOf(ramped(listOf(30.0 to 10, 50.0 to 10, 70.0 to 10, 70.0 to 10))))
        assertEquals(75.0, s.weight); assertEquals(2, s.sets); assertEquals(listOf(30.0, 50.0), s.ramp.map { it.first })
    }

    @Test fun loadAndSetsDoNotRiseTogether() {
        val up = Progression.suggest("agachamento", 3, 8, listOf(ramped(listOf(70.0 to 10, 70.0 to 10))))
        assertEquals(75.0, up.weight); assertEquals(2, up.sets)
        val same = Progression.suggest("agachamento", 3, 10, listOf(ramped(listOf(70.0 to 10, 70.0 to 7))))
        assertEquals(70.0, same.weight); assertEquals(3, same.sets)
    }

    @Test fun pyramidCloseToTopCountsAsWork() {
        val s = Progression.suggest("agachamento", 3, 8, listOf(ramped(listOf(60.0 to 10, 65.0 to 10, 70.0 to 10))))
        assertTrue(s.ramp.isEmpty()); assertEquals(3, s.sets)
    }
}

class SessionRulesTest {
    private val t = Instant.ofEpochSecond(1_800_000_000)
    private fun sets(id: String, order: Int, n: Int, done: Int = 0) = (0 until n).map { LoggedSet(id, order, it, 50.0, 10, done = it < done) }

    @Test fun supersetAdvancesWithoutRestUntilTheRoundCloses() {
        var s = Session("S", "T", start = t, sets = sets("a", 0, 2) + sets("b", 1, 2) + sets("c", 2, 2)).setLinkedNext("a", true)
        assertEquals(listOf("a", "b"), s.group("b"))
        s = s.updating(s.setsOf("a")[0].key) { it.copy(done = true) }
        val (s1, rest1) = s.advance("a")
        assertFalse(rest1); assertEquals("b", s1.currentExerciseID)
        val s2 = s1.updating(s1.setsOf("b")[0].key) { it.copy(done = true) }
        val (s3, rest2) = s2.advance("b")
        assertTrue(rest2); assertEquals("a", s3.currentExerciseID)
    }

    @Test fun swapPendingMovesAfterDoneSetsAndKeepsSuperset() {
        val s = Session("S", "T", start = t, sets = sets("a", 0, 3, done = 1) + sets("b", 1, 2)).setLinkedNext("a", true)
        val out = s.swapPending("a", "x", Suggestion(40.0, 8, ""))
        assertEquals(listOf("a", "x", "b"), out.exerciseIDs)
        assertEquals(listOf(0, 1), out.setsOf("x").map { it.index })
        assertTrue(out.setsOf("x").all { it.weight == 40.0 && it.targetReps == 8 })
        assertTrue(out.linkedNext("x")); assertFalse(out.linkedNext("a"))
        assertEquals("x", out.currentExerciseID)
    }

    @Test fun routineChangesAndApply() {
        val r = Routine("R", "Rotina", items = listOf(RoutineItem("supino-reto", 3, 10, 90, 0), RoutineItem("crucifixo", 3, 12, 90, 1)))
        val s = Session("S", "Rotina", "R", t, sets = (0 until 4).map { LoggedSet("supino-reto", 0, it, 60.0, 10) } + sets("remada-baixa", 1, 3))
        val changes = s.routineChanges(r)
        assertTrue(changes.contains("Entra Remada baixa (3×10)"))
        assertTrue(changes.contains("Sai Crucifixo"))
        assertTrue(changes.contains("Supino reto: 3 → 4 séries"))
        assertEquals(emptyList<String>(), s.routineChanges(s.applyTo(r)))
    }

    @Test fun startSessionWarmsUpFirstWeightedExercise() {
        val r = Routine("R", "A", items = listOf(RoutineItem("agachamento", 3, 8, 120, 0), RoutineItem("supino-reto", 3, 10, 90, 1)))
        val h = listOf(SessionLog(t.minusSeconds(86_400), listOf(SetLog("agachamento", 100.0, 8, 8, true), SetLog("agachamento", 100.0, 8, 8, true),
                                                                  SetLog("agachamento", 100.0, 8, 8, true))))
        val s = WorkoutStart.session(r, h, deload = false, autoWarmup = true, now = t)
        val squat = s.setsOf("agachamento")
        // Plates-only (musculação): mínimo da barra não se aplica; 105 → 40 %, 60 %, 80 % arredondados de 5
        assertEquals(listOf(40.0, 65.0, 85.0), squat.filter { it.warmup }.map { it.weight })
        assertEquals(3, squat.count { !it.warmup && it.weight == 105.0 })
        assertTrue(s.setsOf("supino-reto").none { it.warmup })
    }
}

class WodRulesTest {
    private val today = LocalDate.of(2026, 10, 20)

    @Test fun messageWithSections() {
        val d = WodParser.parse("*TREINO SEXTA 17/10* 🔥🔥\nAQUECIMENTO\n3 rounds\n- 10 air squats\n- 200m run\nB) Força:\nBack squat 5x5 @75%\n*WOD*\nAMRAP 15'\n10 wall balls 9/6kg\n10 burpees 💪", today = today)
        assertEquals(WodFormat.Amrap(15), d.format)
        assertFalse(d.guessed)
        assertEquals(listOf("10 wall balls 9/6kg", "10 burpees"), d.lines)
        assertEquals(listOf("Aquecimento", "Força"), d.parts.map { it.title })
        assertEquals(listOf("3 rounds", "10 air squats", "200m run"), d.parts.first().lines)
    }

    @Test fun formatOnHeaderLineAndTimeCap() {
        val d = WodParser.parse("WOD: For Time - TC 12min\n21-15-9\nThruster 43/30kg\nPull-up", today = today)
        assertEquals(WodFormat.ForTime(12), d.format)
        assertEquals(listOf("21-15-9", "Thruster 43/30kg", "Pull-up"), d.lines)
        assertTrue(d.parts.isEmpty())
    }

    @Test fun formats() {
        assertEquals(WodFormat.Emom(10), WodParser.format("EMOM 10"))
        assertEquals(WodFormat.Every(120, 16), WodParser.format("E2MOM de 16 min"))
        assertEquals(WodFormat.Amrap(20), WodParser.format("20' AMRAP"))
        assertEquals(WodFormat.Tabata(6), WodParser.format("Tabata 6 rounds"))
        assertEquals(WodFormat.ForTime(null), WodParser.format("3 rounds for time"))
        assertNull(WodParser.format("10 burpees"))
        assertNull(WodParser.format("Força total no agachamento"))
        assertEquals(WodFormat.Every(120, 10), WodParser.format("E2MOM 10'"))
        assertEquals(WodFormat.Every(120, 10), WodParser.format("DURANTE 10' A CADA 2'"))
        assertEquals(WodFormat.Every(120, 0), WodParser.format("A CADA 2,00"))
        assertEquals(WodFormat.Every(90, 12), WodParser.format("Every 90s for 12 min"))
        assertEquals(WodFormat.Emom(12), WodParser.format("EMOM 12'"))
    }

    @Test fun formatLineWithMovementStaysAndGuess() {
        val d = WodParser.parse("3 rounds for time:\n400m run\n21 KB swings", today = today)
        assertEquals(WodFormat.ForTime(null), d.format)
        assertEquals(listOf("3 rounds for time:", "400m run", "21 KB swings"), d.lines)
        val g = WodParser.parse("50 double unders\n30 sit-ups", today = today)
        assertTrue(g.guessed)
        assertEquals(listOf("50 double unders", "30 sit-ups"), g.lines)
    }

    @Test fun numberedSectionsAndCapOnOwnLine() {
        val d = WodParser.parse("Bom dia, galera! Treino de hoje 👇\n1. Mobilidade\nQuadril 2'\n2. Skill: Double unders\n3. Metcon\nFor time\nCap: 15'\n5 rounds:\n12 deadlift 60/40", today = today)
        assertEquals(WodFormat.ForTime(15), d.format)
        assertEquals(listOf("Aquecimento", "Skill"), d.parts.map { it.title })
        assertEquals(listOf("5 rounds:", "12 deadlift 60/40"), d.lines)
    }

    private val tecnofit = listOf("WOD 19/10/2026", "WOD 1", "TIME CAP 15'", "AMRAP 3'", "5 WALL BALL", "7 KETTLEBELL SWING (1KB)", "9 PUSH UP",
        "REST 2'", "AMRAP 3'", "03 DEVIL PRESS (2DB)", "06 AVANÇO COM DUMBEL", "9 AIR SQUAT", "REST 2'", "AMRAP 3'", "5 BURPEERS",
        "7 BICEPS (2DB)", "9 REMADA COSTA (2DB)", "TECNOFIT").joinToString("\n")

    @Test fun boxExportBlocksAndLines() {
        val d = WodParser.parse(tecnofit, today = today)
        assertEquals(WodFormat.Intervals(listOf(3, 3, 3), 120, false), d.format)
        assertFalse(d.guessed)
        assertTrue(d.parts.isEmpty())
        assertEquals(listOf("AMRAP 3'", "5 Wall ball", "7 Kettlebell swing (1 KB)", "9 Push up", "Descanso 2'",
                            "AMRAP 3'", "3 Devil press (2 DB)", "6 Avanço com dumbbell", "9 Air squat", "Descanso 2'",
                            "AMRAP 3'", "5 Burpees", "7 Biceps (2 DB)", "9 Remada costa (2 DB)"), d.lines)
        assertEquals(LocalDate.of(2026, 10, 19), d.day)
        assertEquals(listOf("cf-wall-ball", "kettlebell-swing", "flexao", "cf-devil-press", "afundo", "agachamento-livre-corpo", "burpee",
                            "rosca-alternada", "remada-curvada-halter"), WodMovements.ids(d.lines))
    }

    @Test fun blocksTimeline() {
        val f = WodParser.parse(tecnofit, today = today).format
        assertEquals(13 * 60, f.totalSeconds)
        assertEquals("3× AMRAP 3' · descanso 2'", f.name)
        assertEquals(WodSegment(0, false, 180), f.segment(0)?.first)
        assertEquals(true, f.segment(200)?.first?.rest)
        assertEquals(100, f.segment(200)?.second)
        assertEquals(WodSegment(1, false, 180), f.segment(300)?.first)
        assertEquals(2, f.segment(600)?.first?.block)
    }

    @Test fun blocksInOneLineAndOldPlan() {
        assertEquals(WodFormat.Intervals(listOf(4, 4, 4), 60, false), WodParser.parse("WOD\n3x AMRAP 4' descanso 1'\n10 burpees\n10 wall balls", today = today).format)
        val p = PlannedWod(day = Instant.now(), name = "WOD", format = WodFormat.Amrap(13), lines = WodParser.parse(tecnofit, today = today).lines)
        assertEquals(WodFormat.Intervals(listOf(3, 3, 3), 120, false), p.wod().format)
    }

    @Test fun roundsPerBlock() {
        val start = Instant.ofEpochSecond(1000)
        var st = WodRunState(Wod("x", "x", "Coach", WodParser.parse(tecnofit, today = today).format, emptyList()), start, startedAt = start)
        for (sec in listOf(10L, 20L, 200L, 310L)) st = st.addRound(start.plusSeconds(sec))
        assertEquals(listOf(2, 1, 0), st.blockRounds)
        assertEquals(1, st.roundsShown(start.plusSeconds(320)))
    }

    @Test fun identifyVariants() {
        assertEquals(listOf("kettlebell-swing"), WodMovements.identify("21 KB swings 24/16kg"))
        assertEquals(listOf("thruster", "cf-kipping-pull-up"), WodMovements.identify("10 Thrusters + 10 pull-ups"))
        assertEquals(listOf("cf-toes-to-bar"), WodMovements.identify("15 T2B"))
        assertEquals(listOf("cf-squat-clean"), WodMovements.identify("5 squat cleans 60/40"))
        assertEquals(listOf("cf-box-jump-over"), WodMovements.identify("10 box jump over"))
        assertEquals(listOf("esteira"), WodMovements.identify("400m run"))
        assertEquals(listOf("flexao"), WodMovements.identify("10 flexões de braço"))
        assertEquals(emptyList<String>(), WodMovements.identify("Descanso 2'"))
    }

    @Test fun dateIgnoresLoads() {
        assertNull(WodParser.date("10 wall balls 9/6kg", today))
        assertNotNull(WodParser.date("Treino sexta 17/10", today))
    }

    @Test fun roundsLadderChipperAndBlocks() {
        assertEquals(5, WodScheme.rounds(listOf("5 rodadas de:", "400 m de corrida")))
        assertEquals(3, WodScheme.rounds(listOf("3 rounds for time", "10 burpees")))
        assertNull(WodScheme.rounds(listOf("10 burpees")))
        assertEquals(listOf(21, 15, 9), WodScheme.ladder(listOf("21-15-9 repetições de:", "Thruster")))
        assertNull(WodScheme.ladder(listOf("10 wall balls 9/6kg")))
        assertTrue(WodScheme.isChipper(Wod("c", "c", "Coach", WodFormat.ForTime(30), listOf("50 wall balls", "40 burpees", "30 kettlebell swings", "20 pull-ups"))))
        assertFalse(WodScheme.isChipper(Wod.byID("fran")!!)); assertFalse(WodScheme.isChipper(Wod.byID("helen")!!))
        assertEquals(listOf(listOf("5 Wall ball", "7 Kettlebell swing (1 KB)", "9 Push up"), listOf("3 Devil press (2 DB)"), listOf("5 Burpees")),
                     WodScheme.blocks(listOf("AMRAP 3'", "5 Wall ball", "7 Kettlebell swing (1 KB)", "9 Push up", "Descanso 2'",
                                             "AMRAP 3'", "3 Devil press (2 DB)", "Descanso 2'", "AMRAP 3'", "5 Burpees")))
    }

    @Test fun loads() {
        assertEquals(3, WodLoads.reps(listOf("Back squat 5x3 @75%")))
        assertEquals(5, WodLoads.reps(listOf("A cada 2,00", "5 reps")))
        assertEquals(5, WodLoads.reps(listOf("5-4-3-2-1/reps")))
        assertEquals(5, WodLoads.reps(listOf("Push jerks")))
        assertEquals(5, WodLoads.next(emptyList(), "levantamento-terra", 5, emptyList(), 20.0).reps)
        assertEquals(WodSet(80.0, 5), WodLoads.next(listOf(WodSet(80.0, 5)), "levantamento-terra", 5, emptyList(), 20.0))
        val first = WodLoads.next(emptyList(), "cf-push-jerk", 2, emptyList(), 15.0)
        assertEquals(15.0, first.bar); assertTrue(first.weight >= 15)
        assertEquals(30.0, WodSet(80.0, 5, 20.0).perSide)
        val s = WodLoads.session(listOf(WodLoad("levantamento-terra", 1, listOf(WodSet(80.0, 5), WodSet(85.0, 5))), WodLoad("cf-push-jerk", 2)),
                                 "WOD · cargas", "A", Instant.now(), 60, 8, null, 20.0)!!
        assertEquals(listOf(60.0, 65.0), s.log.sets.map { it.weight })
        val cf = WodLoads.session(listOf(WodLoad("cf-push-jerk", 2, listOf(WodSet(60.0, 2, 20.0)))), "x", "A", Instant.now(), 60, 8, null, 20.0)!!
        assertEquals(listOf(60.0), cf.sets.map { it.weight })
    }

    @Test fun formatAndPlanJsonRoundTrip() {
        for (f in listOf(WodFormat.ForTime(null), WodFormat.ForTime(12), WodFormat.Amrap(15), WodFormat.Emom(10), WodFormat.Tabata(8),
                         WodFormat.Intervals(listOf(3, 3), 120, true), WodFormat.Every(120, 0))) assertEquals(f, WodFormat.fromJson(f.toJson()))
        assertEquals("""{"forTime":{}}""", WodFormat.ForTime(null).toJson().toString())
        val p = PlannedWod("ABC", Instant.ofEpochSecond(1_800_000_000), "WOD", WodFormat.Amrap(12), listOf("10 burpees"), listOf(WodPart("Força", listOf("5x5"))))
        assertEquals(p, WodPlan.all(WodPlan.encode(listOf(p))).single())
        assertEquals("coach-ABC", p.wodID)
    }
}

class TrainSplitTest {
    private fun sets(id: String, reps: Int, rest: Int = 120) = List(4) { TrainSplit.SetSignal(id, reps, rest) }

    @Test fun plainActivityMatchesProvenSplit() {
        assertEquals(AttributeSplit.split(ActivityKind.MUSCULACAO, 50, 6), TrainSplit.split(ActivityKind.MUSCULACAO, 50, 6))
    }

    @Test fun heavyVersusLightStrength() {
        val heavy = TrainSplit.split(ActivityKind.MUSCULACAO, 50, 7, sets = sets("agachamento", 3))
        val light = TrainSplit.split(ActivityKind.MUSCULACAO, 50, 7, sets = sets("cadeira-flexora", 20, 40))
        assertTrue(heavy[Attribute.FORCA]!! > 0.8)
        assertTrue(light[Attribute.RESISTENCIA]!! > light[Attribute.FORCA]!!)
        assertEquals(1.0, heavy.values.sum(), 0.001); assertEquals(1.0, light.values.sum(), 0.001)
    }

    @Test fun olympicLiftingIsTechnique() {
        assertTrue(TrainSplit.split(ActivityKind.MUSCULACAO, 60, 7, sets = sets("cf-snatch", 2))[Attribute.TECNICA]!! > 0.35)
    }

    @Test fun wodFormatAndMovements() {
        val gym = TrainSplit.split(ActivityKind.CROSSFIT, 12, 8, wod = TrainSplit.WodSignal(WodFormat.Amrap(12), listOf("cf-hspu", "cf-pistol", "cf-toes-to-bar")))
        val engine = TrainSplit.split(ActivityKind.CROSSFIT, 30, 7, wod = TrainSplit.WodSignal(WodFormat.ForTime(30), listOf("cf-row-cal", "esteira")))
        assertTrue((gym[Attribute.TECNICA] ?: 0.0) > 0.25)
        assertTrue(engine[Attribute.RESISTENCIA]!! > 0.6)
    }
}
