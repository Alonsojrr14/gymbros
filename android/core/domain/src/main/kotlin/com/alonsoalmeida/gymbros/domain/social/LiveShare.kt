package com.alonsoalmeida.gymbros.domain.social

import com.alonsoalmeida.gymbros.domain.ActivityKind
import com.alonsoalmeida.gymbros.domain.map.Coordinate
import com.alonsoalmeida.gymbros.domain.map.kindName
import com.alonsoalmeida.gymbros.domain.map.kmText
import com.alonsoalmeida.gymbros.domain.train.Exercises
import com.alonsoalmeida.gymbros.domain.train.Session
import com.alonsoalmeida.gymbros.domain.train.setText
import java.time.Instant

// Treino ao vivo: o seu (ios/GymBros/Friends/LiveShare.swift e Services/FirebaseSocial.swift `LivePresence`).
// Enquanto você treina, os amigos veem no mapa onde você está, a atividade e o exercício atual. Aqui ficam as regras sem
// plataforma: se o treino compartilha, o que vai no documento `live/{uid}` e o ritmo das gravações.

/**
 * Escolha do ao vivo (LiveShare.swift). O padrão (`shareLive`, ligado) e a escolha de cada treino (`shareLiveWorkouts`:
 * id do treino → compartilha) ficam nos ajustes da conta (`AccountData.userKeys` → plist `accountSettings`), como no
 * iPhone: mudou num aparelho, vale no outro.
 */
object LiveShare {
    /** Padrão para os próximos treinos (Mapa > Ajustes) */
    const val KEY = "shareLive"
    /** Escolha feita num treino específico, só enquanto ele está aberto */
    const val OVERRIDES_KEY = "shareLiveWorkouts"
    const val DEFAULT_ON = true

    fun isOn(settings: Map<String, Any?>): Boolean = when (val v = settings[KEY]) {
        is Boolean -> v
        is Number -> v.toInt() != 0
        else -> DEFAULT_ON
    }

    fun overrides(settings: Map<String, Any?>): Map<String, Boolean> =
        (settings[OVERRIDES_KEY] as? Map<*, *>).orEmpty().mapNotNull { (k, v) ->
            val id = k as? String ?: return@mapNotNull null
            when (v) {
                is Boolean -> id to v
                is Number -> id to (v.toInt() != 0)
                else -> null
            }
        }.toMap()

    /** Este treino compartilha? Sem escolha própria, vale o padrão */
    fun isSharing(id: String, settings: Map<String, Any?>): Boolean = overrides(settings)[id] ?: isOn(settings)
}

/** Estado publicado do treino (`LivePresence.Status`) */
data class LiveStatus(
    val kind: ActivityKind,
    val start: Instant,
    val place: String,
    val now: String,
    val done: List<String> = emptyList(),
    val sets: Int? = null,
    val meters: Double? = null,
    val coordinate: Coordinate? = null,
    val route: List<Coordinate> = emptyList(),
) {
    /**
     * Mudança que sobe na hora (respeitando o intervalo mínimo): atividade, começo, lugar, exercício, o que terminou e as
     * séries. Posição, distância e percurso sozinhos esperam a próxima janela (o `==` do iOS também ignora esses).
     */
    fun sameAs(o: LiveStatus?): Boolean =
        o != null && kind == o.kind && start == o.start && place == o.place && now == o.now && done == o.done && sets == o.sets
}

object LivePresenceRules {
    /** No máximo uma gravação a cada 30 s, além do começo e do fim: uma hora de treino gasta umas 120 gravações */
    const val INTERVAL_MILLIS = 30_000L
    /** Pontos do percurso que vão no documento (os últimos) */
    const val ROUTE_POINTS = 100

    /** Quanto falta para poder gravar de novo (0: já pode) */
    fun waitMillis(lastWrite: Long, now: Long): Long = maxOf(INTERVAL_MILLIS - (now - lastWrite), 0L)

    /** Grava agora ou agenda: só quando mudou algo que importa ou a janela já passou */
    fun shouldSchedule(changed: Boolean, wait: Long): Boolean = changed || wait <= 0

    /** Percurso achatado em [lat, lon, lat, lon…] (o Firestore não guarda lista de listas) */
    fun flatRoute(route: List<Coordinate>): List<Double> = route.takeLast(ROUTE_POINTS).flatMap { listOf(it.latitude, it.longitude) }

    /**
     * Documento `live/{uid}` enquanto o treino roda (`LivePresence.write`), com merge. Datas como [Instant] (quem grava
     * converte para Timestamp); null vira null no Firestore, como o `Fire.fields` do iOS. `music` vai nulo: o Android
     * não compartilha música (e assim não fica a de um treino antigo do iPhone).
     */
    fun fields(uid: String, name: String, formID: String, s: LiveStatus, now: Instant): Map<String, Any?> = linkedMapOf(
        "user" to uid, "name" to name, "formID" to formID, "kind" to s.kind.raw, "start" to s.start, "place" to s.place,
        "now" to s.now, "done" to s.done, "sets" to s.sets, "meters" to s.meters,
        "latitude" to s.coordinate?.latitude, "longitude" to s.coordinate?.longitude, "route" to flatRoute(s.route),
        "music" to null, "endedAt" to null, "updatedAt" to now,
    )

    /** Treino encerrado (ou "Ao vivo" desligado nele): fica só o "visto há…" (`LivePresence.end`) */
    fun endedFields(uid: String, kind: ActivityKind?, now: Instant): Map<String, Any?> = linkedMapOf(
        "user" to uid, "start" to null, "now" to "", "done" to emptyList<String>(), "route" to emptyList<Double>(), "endedAt" to now,
        "kind" to kind?.raw, "updatedAt" to now,
    )

    /**
     * Musculação (`LivePresence.workout` com o estado do Live Activity): exercício e série atuais e os exercícios já
     * terminados (todas as séries de trabalho feitas).
     */
    fun workout(s: Session, place: String, coordinate: Coordinate?): LiveStatus {
        val done = s.exerciseIDs.mapNotNull { id ->
            val sets = s.orderedSets.filter { it.exerciseID == id && !it.warmup }
            if (sets.isEmpty() || !sets.all { it.done }) null else "${Exercises.name(id)} · ${sets.size} séries"
        }
        val cur = s.currentExercise
        val exercise = cur?.let(Exercises::name) ?: "Treino livre"
        val sets = cur?.let(s::setsOf).orEmpty()
        val next = sets.indexOfFirst { !it.done }.takeIf { it >= 0 }
        val setText = next?.let { (if (sets[it].warmup) "Aquecimento · " else "") + setText(sets[it]) } ?: ""
        val setNumber = (next ?: sets.size) + 1
        val now = if (setText.isEmpty()) exercise else "$exercise · série $setNumber de ${sets.size} · $setText"
        return LiveStatus(ActivityKind.MUSCULACAO, s.start, place, now, done, s.doneWorkSets.size, coordinate = coordinate)
    }

    /** CrossFit (`LivePresence.wod`): a parte ou o WOD em andamento */
    fun wod(name: String, label: String, start: Instant, place: String, coordinate: Coordinate?): LiveStatus =
        LiveStatus(ActivityKind.CROSSFIT, start, place, "$name · $label", coordinate = coordinate)

    /** Corrida, caminhada e bike (`LivePresence.route`): posição e percurso do GPS */
    fun route(kind: ActivityKind, start: Instant, meters: Double, here: Coordinate, route: List<Coordinate>): LiveStatus =
        LiveStatus(kind, start, kindName(kind), kmText(meters), meters = meters, coordinate = here, route = route)
}
