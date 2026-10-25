package com.alonsoalmeida.gymbros.ui.map

import android.annotation.SuppressLint
import android.view.MotionEvent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.alonsoalmeida.gymbros.domain.map.Coordinate
import com.alonsoalmeida.gymbros.domain.map.GymPlaces
import com.alonsoalmeida.gymbros.ui.theme.GMColors
import org.maplibre.android.MapLibre
import org.maplibre.android.camera.CameraUpdateFactory
import org.maplibre.android.geometry.LatLng
import org.maplibre.android.maps.MapLibreMap
import org.maplibre.android.maps.MapLibreMapOptions
import org.maplibre.android.maps.MapView
import org.maplibre.android.maps.Style
import org.maplibre.android.style.expressions.Expression
import org.maplibre.android.style.layers.FillLayer
import org.maplibre.android.style.layers.LineLayer
import org.maplibre.android.style.layers.Property
import org.maplibre.android.style.layers.PropertyFactory
import org.maplibre.android.style.sources.GeoJsonSource
import org.maplibre.geojson.Feature
import org.maplibre.geojson.FeatureCollection
import org.maplibre.geojson.LineString
import org.maplibre.geojson.Point
import org.maplibre.geojson.Polygon
import kotlin.math.cos
import kotlin.math.log2
import kotlin.math.roundToInt

// O Map do MapKit no iOS, com MapLibre e o estilo escuro gratuito do OpenFreeMap (dados do OpenStreetMap, sem chave nem
// conta). Raios e percursos são camadas do mapa; pinos (academias, amigos, você) são Compose por cima, presos à coordenada.

/** Estilo vetorial escuro do OpenFreeMap; o fundo é trocado pelo `bg` do app */
const val MAP_STYLE = "https://tiles.openfreemap.org/styles/dark"

/** A aba está visível: o MapView só existe na aba aberta (as abas escondidas continuam compostas, transparentes) */
val LocalTabVisible = compositionLocalOf { true }

/** Um círculo de raio em metros (MapCircle) */
data class MapCircle(val center: Coordinate, val radius: Double, val color: Color)

/** Uma linha (MapPolyline) */
data class MapLine(val points: List<Coordinate>, val color: Color, val width: Float, val opacity: Float = 1f)

/** Câmera e projeção do mapa: `version` muda a cada movimento para os pinos acompanharem */
class MapController {
    internal var map: MapLibreMap? = null
    internal var view: android.view.View? = null
    internal var version by mutableIntStateOf(0)
    /** Pedido feito antes de o mapa ficar pronto */
    private var pending: ((MapLibreMap) -> Unit)? = null

    internal fun attach(m: MapLibreMap?) {
        map = m
        if (m != null) { pending?.invoke(m); pending = null }
        version++
    }

    private fun run(animate: Boolean, block: (MapLibreMap) -> org.maplibre.android.camera.CameraUpdate) {
        val m = map
        if (m == null) { pending = { m2 -> m2.moveCamera(block(m2)) }; return }
        if (animate) m.animateCamera(block(m), 500) else m.moveCamera(block(m))
    }

    /** Enquadra `meters` em volta do centro no lado menor do mapa (MKCoordinateRegion com latitudinalMeters) */
    fun focus(c: Coordinate, meters: Double, animate: Boolean = true) {
        run(animate) {
            val v = view
            val density = v?.resources?.displayMetrics?.density ?: 1f
            val sideDp = v?.let { minOf(it.width, it.height) / density }?.takeIf { it > 0 } ?: 340f
            // Metros por dp no zoom z (tiles de 512): 40075016,686 · cos(lat) / (512 · 2^z)
            val zoom = log2(40_075_016.686 * cos(Math.toRadians(c.latitude)) * sideDp / (512 * meters))
            CameraUpdateFactory.newLatLngZoom(LatLng(c.latitude, c.longitude), zoom.coerceIn(2.0, 19.0))
        }
    }

    /**
     * Enquadra todos os pontos (o `MKMapRect` do RouteMap no iOS): o percurso com 20 % de folga mais 300 m de cada lado.
     * Calculado pela distância, como o `focus`, para funcionar antes de o mapa ter tamanho.
     */
    fun fit(points: List<Coordinate>, animate: Boolean = false) {
        if (points.isEmpty()) return
        val minLat = points.minOf { it.latitude }; val maxLat = points.maxOf { it.latitude }
        val minLon = points.minOf { it.longitude }; val maxLon = points.maxOf { it.longitude }
        val center = Coordinate((minLat + maxLat) / 2, (minLon + maxLon) / 2)
        val height = (maxLat - minLat) * 111_320.0
        val width = (maxLon - minLon) * 111_320.0 * cos(Math.toRadians(center.latitude))
        focus(center, maxOf(height, width) * 1.4 + 600, animate)
    }

    /** A pessoa arrastou ou deu zoom no mapa: quem segue a sua posição para de seguir até pedir de novo */
    var moved by mutableIntStateOf(0)
        internal set

    /** Posição na tela (px, relativa ao mapa); lê `version` para recalcular quando a câmera anda */
    fun project(c: Coordinate): Offset? {
        version
        val p = map?.projection?.toScreenLocation(LatLng(c.latitude, c.longitude)) ?: return null
        return Offset(p.x, p.y)
    }
}

private fun hex(c: Color): String = String.format("#%06X", 0xFFFFFF and c.toArgb())

@SuppressLint("ClickableViewAccessibility")
@Composable
fun GymMapView(
    controller: MapController,
    circles: List<MapCircle>,
    lines: List<MapLine>,
    modifier: Modifier = Modifier,
    onTap: ((Coordinate) -> Unit)? = null,
    pins: @Composable BoxScope.() -> Unit = {},
) {
    val visible = LocalTabVisible.current
    Box(modifier) {
        if (visible) {
            val context = LocalContext.current
            val lifecycle = LocalLifecycleOwner.current.lifecycle
            val tap by rememberUpdatedState(onTap)
            var style by remember { mutableIntStateOf(0) }
            val holder = remember { arrayOfNulls<Style>(1) }
            val view = remember {
                MapLibre.getInstance(context)
                // TextureView: aceita o canto arredondado e a transparência das abas (SurfaceView não)
                MapView(context, MapLibreMapOptions.createFromAttributes(context).textureMode(true).logoEnabled(false)
                    .rotateGesturesEnabled(false).tiltGesturesEnabled(false)).apply {
                    onCreate(null)
                    controller.view = this
                    // Arrastar o mapa não rola a tela
                    setOnTouchListener { v, e ->
                        if (e.actionMasked == MotionEvent.ACTION_DOWN) v.parent?.requestDisallowInterceptTouchEvent(true)
                        false
                    }
                    getMapAsync { m ->
                        m.setStyle(Style.Builder().fromUri(MAP_STYLE)) { st ->
                            st.getLayer("background")?.setProperties(PropertyFactory.backgroundColor(hex(GMColors.bg)))
                            st.addSource(GeoJsonSource("gm-circles"))
                            st.addSource(GeoJsonSource("gm-lines"))
                            st.addLayer(FillLayer("gm-circle-fill", "gm-circles").withProperties(
                                PropertyFactory.fillColor(Expression.get("color")), PropertyFactory.fillOpacity(0.18f)))
                            st.addLayer(LineLayer("gm-circle-line", "gm-circles").withProperties(
                                PropertyFactory.lineColor(Expression.get("color")), PropertyFactory.lineWidth(2f)))
                            st.addLayer(LineLayer("gm-lines", "gm-lines").withProperties(
                                PropertyFactory.lineColor(Expression.get("color")), PropertyFactory.lineWidth(Expression.get("width")),
                                PropertyFactory.lineOpacity(Expression.get("opacity")),
                                PropertyFactory.lineCap(Property.LINE_CAP_ROUND), PropertyFactory.lineJoin(Property.LINE_JOIN_ROUND)))
                            holder[0] = st
                            style++
                        }
                        m.addOnCameraMoveListener { controller.version++ }
                        m.addOnCameraMoveStartedListener { reason ->
                            if (reason == MapLibreMap.OnCameraMoveStartedListener.REASON_API_GESTURE) controller.moved++
                        }
                        m.addOnCameraIdleListener { controller.version++ }
                        m.addOnMapClickListener { ll -> tap?.invoke(Coordinate(ll.latitude, ll.longitude)); tap != null }
                        controller.attach(m)
                    }
                }
            }
            DisposableEffect(lifecycle) {
                val obs = LifecycleEventObserver { _, e ->
                    when (e) {
                        Lifecycle.Event.ON_START -> view.onStart()
                        Lifecycle.Event.ON_RESUME -> view.onResume()
                        Lifecycle.Event.ON_PAUSE -> view.onPause()
                        Lifecycle.Event.ON_STOP -> view.onStop()
                        else -> {}
                    }
                }
                lifecycle.addObserver(obs)
                onDispose {
                    lifecycle.removeObserver(obs)
                    controller.attach(null)
                    controller.view = null
                    view.onPause(); view.onStop(); view.onDestroy()
                }
            }
            LaunchedEffect(style, circles, lines) {
                val st = holder[0] ?: return@LaunchedEffect
                (st.getSource("gm-circles") as? GeoJsonSource)?.setGeoJson(FeatureCollection.fromFeatures(circles.map { c ->
                    Feature.fromGeometry(Polygon.fromLngLats(listOf(GymPlaces.circle(c.center, c.radius).map { Point.fromLngLat(it.longitude, it.latitude) })))
                        .apply { addStringProperty("color", hex(c.color)) }
                }))
                (st.getSource("gm-lines") as? GeoJsonSource)?.setGeoJson(FeatureCollection.fromFeatures(lines.filter { it.points.size > 1 }.map { l ->
                    Feature.fromGeometry(LineString.fromLngLats(l.points.map { Point.fromLngLat(it.longitude, it.latitude) })).apply {
                        addStringProperty("color", hex(l.color)); addNumberProperty("width", l.width); addNumberProperty("opacity", l.opacity)
                    }
                }))
            }
            AndroidView({ view }, Modifier.matchParentSize())
            pins()
        }
    }
}

/** Pino preso à coordenada: o ponto `anchor` (a partir do topo, centrado na horizontal) fica em cima dela */
@Composable
fun MapPin(controller: MapController, at: Coordinate, anchor: Dp, content: @Composable () -> Unit) {
    val anchorPx = with(LocalDensity.current) { anchor.toPx() }
    Box(Modifier.layout { measurable, constraints ->
        val p = measurable.measure(constraints.copy(minWidth = 0, minHeight = 0))
        layout(0, 0) {
            val o = controller.project(at) ?: return@layout
            p.place((o.x - p.width / 2f).roundToInt(), (o.y - anchorPx).roundToInt())
        }
    }) { content() }
}
